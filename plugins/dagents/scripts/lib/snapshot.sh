# Build the compaction snapshot: what a compaction summary drops that the next
# turn needs — the handoff's next step, ledger tails and rulings, files the
# session edited, the owner's last prompts, background agent and command ids.
# Sourced by scripts/session-start.sh on the compact source; defines functions
# only.
#
# Capped because hook output over 10,000 characters is replaced by a file
# reference, and the injected entry point already takes about 5,000
# (tests/hook.test.sh caps it at 5,500 bytes); session-start.sh subtracts its
# measured length, so this is only the ceiling.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plan.sh"

SNAPSHOT_CAP=5500

. "$(dirname "${BASH_SOURCE[0]}")/dagents-env.sh"
. "$(dirname "${BASH_SOURCE[0]}")/fast-mode.sh"

_snapshot_mtime() { # FILE — modification time in epoch seconds, or nothing
  local t
  t=$(stat -c %Y -- "$1" 2>/dev/null | tr -d '\r') || t=""
  case $t in ''|*[!0-9]*) t=$(stat -f %m -- "$1" 2>/dev/null | tr -d '\r') || t="" ;; esac
  case $t in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$t"
}

# _snapshot_start TRANSCRIPT — the session's start: its first timestamp, in
# epoch seconds, or nothing.
_snapshot_start() {
  head -n 200 "$1" 2>/dev/null | tr -d '\r' | "${DAGENTS_JQ:-jq}" -R -r -n '
    first(inputs | fromjson? | objects | .timestamp? | strings
          | (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | floor)?) // empty' 2>/dev/null
}

# snapshot_latest CWD [START] — the Next session block of this repository's
# latest.md, headed with its age. With START (epoch seconds), only when this
# session wrote it: latest.md, or the ledger of a plan its block names, changed
# at or after START. A handoff from another session would steer this one.
snapshot_latest() {
  local latest block mt at keep=1 ledger _where lm plan_rel age="" d
  latest=$(dagents_latest_file "$1") || return 0
  [ -f "$latest" ] || return 0
  block=$(tr -d '\r' < "$latest" | awk '/^## Next session/ { f = 1; next } f && /^## / { exit } f')
  mt=$(_snapshot_mtime "$latest") || mt=""
  # next-step's marker names when the block was computed; a later edit of the
  # notes moves the mtime, not that.
  at=$(sed -nE 's/^<!-- next-step: .* at=([0-9]+) -->$/\1/p' <<<"$block" | tail -n 1)
  block=$(grep -vE '^<!-- next-step: ' <<<"$block" || true)
  if [ -n "${2:-}" ] && [ -n "$mt" ] && [ "$mt" -lt "$2" ]; then
    keep=0
    while IFS=$'\t' read -r ledger _where; do
      [ -n "$ledger" ] || continue
      lm=$(_snapshot_mtime "$ledger") || continue
      [ "$lm" -ge "$2" ] || continue
      plan_rel=$(ledger_plan "$ledger")
      if [ -n "$plan_rel" ] && grep -qF -- "$plan_rel" <<<"$block"; then keep=1; break; fi
    done < <(dagents_ledger_files "$1")
  fi
  [ "$keep" = 1 ] || return 0
  if [ -n "${at:-$mt}" ]; then
    d=$(( $(date +%s) - ${at:-$mt} ))
    [ "$d" -ge 0 ] || d=0
    if [ "$d" -lt 3600 ]; then age=" ($((d / 60))m old)"
    elif [ "$d" -lt 86400 ]; then age=" ($((d / 3600))h old)"
    else age=" ($((d / 86400))d old)"; fi
  fi
  echo "### From \`$latest\`$age"
  printf '%s\n' "$block"
}

# snapshot_ledgers CWD [LINES] [RULINGS] — every ledger dagents_ledger_files
# lists: its last LINES lines (default 8) and last RULINGS rulings (default 10).
snapshot_ledgers() {
  local ledger _where plan_rel rulings lines=${2:-8} keep=${3:-10}
  dagents_ledger_files "$1" | while IFS=$'\t' read -r ledger _where; do
    plan_rel=$(ledger_plan "$ledger")
    echo "### Ledger \`$ledger\` (plan \`${plan_rel:-unknown}\`)"
    echo "Last lines:"
    tr -d '\r' < "$ledger" | grep -v '^[[:space:]]*$' | tail -n "$lines" | sed 's/^/    /'
    rulings=""
    [ "$keep" -eq 0 ] || rulings=$(tr -d '\r' < "$ledger" | grep 'Ruling:' | tail -n "$keep")
    if [ -n "$rulings" ]; then
      echo "Rulings (most recent $keep):"
      printf '%s\n' "$rulings" | sed 's/^/    /'
    fi
  done
}

# FILE — sections 4-6 from the transcript's last 3000 lines, separated by
# @@4 / @@5 / @@6 marker lines.
snapshot_transcript_sections() {
  tail -n 3000 "$1" | tr -d '\r' | "${DAGENTS_JQ:-jq}" -R -r -n '
    [inputs | select(length > 0) | (try fromjson catch null) | objects
     | select((.isSidechain // false) == false)] as $e
    | ([$e[] | select(.type == "assistant") | .message.content[]?
        | select(type == "object" and .type == "tool_use"
                 and (.name == "Write" or .name == "Edit" or .name == "NotebookEdit"))
        | (.input.file_path // .input.notebook_path // empty)]
       | reverse | reduce .[] as $f ([]; if any(.[]; . == $f) then . else . + [$f] end)
       | .[:20]) as $files
    | ([$e[] | select(.type == "user" and ((.isCompactSummary // false) | not)
                      and ((.isMeta // false) | not)
                      and ((.message.content | type) == "string")
                      and ((.origin.kind // "") == "human"
                           or (.origin == null and (.message.content | startswith("<") | not))))
        | .message.content | gsub("\\s+"; " ") | .[:300]] | .[-3:]) as $prompts
    | ([$e[] | select(.type == "assistant") | .message.content[]?
        | select(type == "object" and .type == "tool_use" and .name == "Agent")
        | {key: .id, value: (.input.description // "")}] | from_entries) as $desc
    | ([$e[] | select(.type == "user") | .message.content | arrays | .[]
        | select(type == "object" and .type == "tool_result" and ($desc[.tool_use_id] != null))
        | . as $r
        | ([.content] | flatten | map(if type == "object" then (.text // "") else tostring end) | join(" "))
        | capture("agentId: (?<id>[A-Za-z0-9]+)")?
        | "\(.id) — \($desc[$r.tool_use_id])"] | .[-5:]) as $agents
    | ([$e[] | select(.type == "assistant") | .message.content[]?
        | select(type == "object" and .type == "tool_use" and .name == "Bash"
                 and (.input.run_in_background // false) == true)
        | {key: .id, value: (.input.description // "")}] | from_entries) as $bdesc
    | ([$e[] | select(.type == "user") | .message.content | arrays | .[]
        | select(type == "object" and .type == "tool_result" and ($bdesc[.tool_use_id] != null))
        | . as $r
        | ([.content] | flatten | map(if type == "object" then (.text // "") else tostring end) | join(" "))
        | capture("^Command running in background with ID: (?<id>[A-Za-z0-9_-]+)")?
        | "\(.id) — \($bdesc[$r.tool_use_id]) (command)"] | .[-5:]) as $commands
    | "@@4",
      (if ($files | length) > 0
       then "### Files edited by this session (most recent first)", ($files[] | "- `\(.)`")
       else empty end),
      "@@5",
      (if ($prompts | length) > 0
       then "### The owner'"'"'s last prompts (verbatim, truncated)", ($prompts[] | "- \(.)")
       else empty end),
      "@@6",
      (if ($agents + $commands | length) > 0
       then "### Background agents and commands (resume an agent by id while it runs; wait for a command or stop it)",
            ($agents[], $commands[] | "- \(.)")
       else empty end)
  ' 2>/dev/null
}

# snapshot_build TRANSCRIPT CWD [CAP] — the markdown snapshot, at most CAP
# characters (default SNAPSHOT_CAP). Sections 6, 5, 4 are dropped whole, in
# that order, until it fits; then section 3 is cut to each ledger's heading and
# newest lines, rulings first; sections 1-2 are never dropped.
snapshot_build() {
  local tp=${1:-} cwd=${2:-$PWD} cap=${3:-$SNAPSHOT_CAP} s1 s2 s3 s4="" s5="" s6="" raw out part step start="" fast
  s1='## Compaction snapshot

This session was just compacted. Trust this snapshot, the ledger and `git log`
over the summary above. If anything is unclear, run `scripts/repo-audit` by its
dagents plugin-root path, with the working directory inside the project;
if the next budget line says `handoff`, run the dagents handoff skill.'
  if [ -n "$tp" ] && command -v "${DAGENTS_JQ:-jq}" >/dev/null 2>&1; then
    if command -v cygpath >/dev/null 2>&1; then tp=$(cygpath -u "$tp"); fi
    if [ -f "$tp" ]; then
      start=$(_snapshot_start "$tp")
      # A session-scoped fast line may sit before what the summary keeps.
      if fast_mode_on "$tp"; then
        fast=$(tail -n 3000 "$tp" | tr -d '\r' | "${DAGENTS_JQ:-jq}" -R -r 'fromjson? | objects
            | select(.type? == "assistant" and .isSidechain? != true) | .message.content?
            | if type == "string" then . elif type == "array" then (.[] | select(.type? == "text") | .text? | strings) else empty end' 2>/dev/null \
          | fast_mode_process_lines | grep -E '^Process:[[:space:]]*fast[[:space:]]*\(session\)' | tail -n 1)
        [ -z "$fast" ] || s1+=$'\n\n'"Fast mode is on for this session: \`$fast\`"
      fi
      raw=$(snapshot_transcript_sections "$tp")
      s4=$(printf '%s\n' "$raw" | awk '/^@@4$/ { f = 1; next } /^@@5$/ { f = 0 } f')
      s5=$(printf '%s\n' "$raw" | awk '/^@@5$/ { f = 1; next } /^@@6$/ { f = 0 } f')
      s6=$(printf '%s\n' "$raw" | awk '/^@@6$/ { f = 1; next } f')
    fi
  fi
  s2=$(snapshot_latest "$cwd" "$start")
  s3=$(snapshot_ledgers "$cwd")
  for step in 6 5 4 8:5 8:0 4:0 2:0 1:0 end; do
    out=""
    for part in "$s1" "$s2" "$s3" "$s4" "$s5" "$s6"; do
      [ -n "$part" ] && out+="$part"$'\n\n'
    done
    [ "${#out}" -le "$cap" ] && break
    case $step in
      6) s6="" ;; 5) s5="" ;; 4) s4="" ;;
      *:*) [ -z "$s3" ] || s3=$(snapshot_ledgers "$cwd" "${step%:*}" "${step#*:}") ;;
    esac
  done
  # Sections 1-2 are never dropped, but s2 (the Next session block, copied
  # verbatim from latest.md) is unbounded — truncate it as a last resort so
  # the "at most CAP characters" contract holds even for an oversized handoff.
  # The cut ledgers stay when they fit beside section 1.
  if [ "${#out}" -gt "$cap" ]; then
    [ $((cap - ${#s1} - ${#s3} - 6)) -ge 0 ] || s3=""
    local room extra=0
    [ -z "$s3" ] || extra=$((${#s3} + 2))
    room=$((cap - ${#s1} - 4 - extra))
    [ "$room" -lt 0 ] && room=0
    s2="${s2:0:room}"
    out="$s1"$'\n\n'
    [ -n "$s2" ] && out+="$s2"$'\n\n'
    [ -n "$s3" ] && out+="$s3"$'\n\n'
  fi
  printf '%s\n' "${out%$'\n\n'}"
}
