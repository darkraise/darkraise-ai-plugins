# fast_mode_on TRANSCRIPT [LAST_MESSAGE] — status 0 while fast mode is on: the
# user chose to run without dagents's flow, so the hooks that enforce it stand
# down. `Process: fast — <why>` covers its own request: it counts only after
# the current turn stamp (scripts/turn-start.sh), or anywhere when there is no
# stamp. `Process: fast (session) — <why>` stays on until a later `Process:`
# line names another path. The last message, when given, is read first: the
# transcript may not hold it yet at a stop.
#
# Transcripts reach tens of megabytes and the deciding line is usually near the
# end, so the transcript is read backwards in growing chunks. The verdict for
# the part before the stamp is cached in <stamp>.fast, so the scan past the
# current request runs once per turn; a new stamp is newer than the cache.
fast_mode_process_lines() {
  tr -d '\r' | sed -nE 's/^[[:space:]`*]*(Process:.*)$/\1/p'
}

FAST_MODE_CHUNK=1048576

# _fast_mode_scan STAMP PRE — transcript lines on stdin, oldest first. Prints
# on or off (decided after the stamp, or by PRE), pre on or pre off (decided
# before the stamp), or more (nothing decided in what was read). STAMP is the
# stamp's epoch seconds, empty without one; an entry at or after it, or with
# no timestamp, is after. PRE is the cached pre-stamp verdict, or empty.
_fast_mode_scan() {
  jq -R -r -n --arg stamp "$1" --arg pre "$2" '
    def fast: test("^Process:\\s*fast([^[:alnum:]_-]|$)");
    def session: test("^Process:\\s*fast\\s*\\(session\\)");
    def side:
      if $stamp == "" then "A"
      else ((.timestamp | strings | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)? // null) as $t
        | if $t == null or $t >= ($stamp | tonumber) then "A" else "B" end
      end;
    def plines:
      if .type? == "assistant" and .isSidechain? != true then
        [.message.content?
         | if type == "string" then . elif type == "array" then (.[] | select(.type? == "text") | .text? | strings) else empty end
         | split("\n")[] | gsub("\r"; "")
         | capture("^[\\s`*]*(?<p>Process:.*)$").p]
      else [] end;
    [inputs | fromjson? | objects | {s: side, l: plines}]
    | reverse
    | reduce .[] as $e (null;
        if . != null then .
        elif $e.s == "A" then
          ($e.l | reverse | map(if fast then "on" else "off" end) | first) // null
        elif $pre != "" then $pre
        else
          ($e.l | reverse | map(if session then "pre on" elif fast then empty else "pre off" end) | first) // null
        end)
    | . // "more"' 2>/dev/null
}

fast_mode_on() {
  local line stamp epoch="" cache="" pre="" size n out
  line=$(printf '%s\n' "${2:-}" | fast_mode_process_lines | tail -n 1)
  if [ -n "$line" ]; then
    grep -qE '^Process:[[:space:]]*fast([^[:alnum:]_-]|$)' <<<"$line"
    return
  fi
  [ -n "${1:-}" ] && [ -f "$1" ] || return 1
  stamp="${HOME:-}/.claude/dagents/sessions/turns/$(printf '%s' "$(basename "$1" .jsonl)" | tr -c 'A-Za-z0-9' '-')"
  if [ -n "${HOME:-}" ] && [ -f "$stamp" ]; then
    epoch=$(stat -c %Y -- "$stamp" 2>/dev/null | tr -d '\r') || epoch=""
    case $epoch in ''|*[!0-9]*) epoch=$(stat -f %m -- "$stamp" 2>/dev/null | tr -d '\r') || epoch="" ;; esac
    case $epoch in ''|*[!0-9]*) epoch="" ;; esac
  fi
  if [ -n "$epoch" ]; then
    cache="$stamp.fast"
    if [ "$cache" -nt "$stamp" ]; then
      pre=$(tr -d '\r\n' < "$cache" 2>/dev/null)
      case $pre in on|off) ;; *) pre="" ;; esac
    fi
  fi
  size=$(wc -c < "$1" | tr -d ' \r')
  n=$FAST_MODE_CHUNK
  while :; do
    # A chunk that starts inside the file starts mid-line: that line is dropped.
    if [ "$n" -ge "$size" ]; then out=$(_fast_mode_scan "$epoch" "$pre" < "$1")
    else out=$(tail -c "$n" "$1" | tail -n +2 | _fast_mode_scan "$epoch" "$pre"); fi
    case $out in
      on) return 0 ;;
      off | '') return 1 ;;
      'pre on' | 'pre off') out=${out#pre }; break ;;
    esac
    # The whole file read and nothing decided: no line turns fast mode on.
    if [ "$n" -ge "$size" ]; then out=${pre:-off}; break; fi
    n=$((n * 2))
  done
  [ -z "$cache" ] || [ -n "$pre" ] || printf '%s\n' "$out" > "$cache" 2>/dev/null || true
  [ "$out" = on ]
}
