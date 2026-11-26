# Sourced; functions only; needs jq. The session state file the cockpit writes
# (hooks/cockpit/register.tsx writeSessionState): the window, the model and the
# running launches of one session, read in place of a transcript scan. Each
# reader returns 1 when the file cannot be trusted and logs why, once per turn,
# to <state>/session-state.log, so a fallback to the scan is visible.

if ! declare -F dforge_dir >/dev/null 2>&1; then
  . "${BASH_SOURCE[0]%/*}/dforge-dir.sh"
fi

_ss_id() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '-'; }

# ss_file SID — the state file's path.
ss_file() { printf '%s/.claude/dforge/sessions/state/%s.json\n' "${HOME:-}" "$(_ss_id "$1")"; }

# The turn stamp's modification time in epoch seconds; 1 when there is none.
_ss_stamp() {
  local t
  t=$(stat -c %Y -- "${HOME:-}/.claude/dforge/sessions/turns/$(_ss_id "$1")" 2>/dev/null | tr -d '\r') || t=""
  case $t in ''|*[!0-9]*) t=$(stat -f %m -- "${HOME:-}/.claude/dforge/sessions/turns/$(_ss_id "$1")" 2>/dev/null | tr -d '\r') || t="" ;; esac
  case $t in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$t"
}

# _ss_log SID READER REASON — one line per turn, reader and reason; outside a
# git checkout nothing is logged.
_ss_log() {
  local top dir log line
  top=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r') || return 0
  [ -n "$top" ] || return 0
  dir=$(dforge_dir state "$top") || return 0
  log="$dir/session-state.log"
  line=$(printf '%s\t%s\t%s\t%s' "$(_ss_stamp "$1" || printf 0)" "$1" "$2" "$3")
  [ -f "$log" ] && grep -qxF -- "$line" "$log" 2>/dev/null && return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  dforge_state_ignore "$top"
  printf '%s\n' "$line" >> "$log" 2>/dev/null || true
}

# _ss_read SID READER — the reader's verdict on the file: "ok\t<value>" lines,
# or the rejection reason. jq reads the file on stdin: jq.exe cannot open the
# POSIX form of a Git Bash path.
_ss_read() {
  local f out stamp=-1
  f=$(ss_file "$1")
  if [ ! -f "$f" ]; then _ss_log "$1" "$2" missing; return 1; fi
  [ "$2" != launches ] || stamp=$(_ss_stamp "$1") || stamp=-1
  out=$(jq -r --arg sid "$1" --arg reader "$2" --argjson stamp "$stamp" '
      def hm: try (. / 1000 | floor | localtime | strftime("%H:%M")) catch "-";
      def text: tostring | gsub("[\t\r\n]+"; " ") | .[0:80];
      if type != "object" then "unparseable"
      elif .session != $sid then "session mismatch"
      elif $reader == "window" then
        (if (.window | type) == "number" and .window > 0 and .window == (.window | floor) then "ok\t\(.window)" else "missing" end)
      elif $reader == "model" then
        (if (.model | type) == "string" and .model != "" then "ok\t\(.model)" else "missing" end)
      elif .partial != false then "partial"
      elif $stamp < 0 or ((.updated | type) != "number") or .updated < $stamp * 1000 then "stale"
      else "ok", (.launches // [] | .[]
        | "ok\t\(.kind)\t\(.id)\t\(.startedAt | hm)\t\(if (.outputFile // "") == "" then "-" else .outputFile end)\t\(.what // "" | text)\t\(if .service == true then "service" elif .timer == true then "timer" else "work" end)")
      end' < "$f" 2>/dev/null | tr -d '\r') || out=unparseable
  [ -n "$out" ] || out=unparseable
  case $out in
    ok*) printf '%s\n' "$out" ;;
    *) _ss_log "$1" "$2" "$out"; return 1 ;;
  esac
}

# ss_window SID — the context window in tokens.
ss_window() {
  local out
  out=$(_ss_read "$1" window) || return 1
  printf '%s\n' "${out#ok	}"
}

# ss_model SID — the session's model id.
ss_model() {
  local out
  out=$(_ss_read "$1" model) || return 1
  printf '%s\n' "${out#ok	}"
}

# ss_launches SID — the running launches as in-flight lines: kind, task id,
# started HH:MM, idle age (inflight_idle's when lib/in-flight.sh is sourced),
# what, and the role service, timer or work.
ss_launches() {
  local out kind id start file what role idle
  out=$(_ss_read "$1" launches) || return 1
  while IFS=$'\t' read -r _ kind id start file what role; do
    [ -n "$kind" ] || continue
    if declare -F inflight_idle >/dev/null 2>&1; then idle=$(inflight_idle "$kind" "$id" "$file" "")
    else idle="idle -"; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$id" "$start" "$idle" "$what" "$role"
  done <<<"$out"
  return 0
}

# ss_prune — delete state files untouched for 30 days, and run bindings and
# their seen files as old, except those of a session whose bound run is still
# active. Without jq no binding is deleted.
ss_prune() {
  local run="${HOME:-}/.claude/dforge/sessions/run" f base primary
  find "${HOME:-}/.claude/dforge/sessions/state" -maxdepth 1 -type f -name '*.json' -mtime +30 -delete 2>/dev/null || true
  [ -d "$run" ] && command -v "${DFORGE_JQ:-jq}" >/dev/null 2>&1 || return 0
  while IFS= read -r f; do
    f=${f%$'\r'}
    base=${f%.*}
    if [ -f "$base.json" ]; then
      primary=$("${DFORGE_JQ:-jq}" -r '.primary // empty | strings' < "$base.json" 2>/dev/null | tr -d '\r')
      [ -z "$primary" ] || ! "${DFORGE_JQ:-jq}" -e --arg s "$(basename "$base")" '.active == true and .session == $s' \
        < "$primary/.dforge/sdd/auto-run.json" >/dev/null 2>&1 || continue
    fi
    rm -f "$f"
  done < <(find "$run" -maxdepth 1 -type f \( -name '*.json' -o -name '*.seen' \) -mtime +30 2>/dev/null)
  return 0
}
