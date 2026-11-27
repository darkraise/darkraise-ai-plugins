# Background work this session started that is still listed as running.
# Sourced by scripts/turn-end.sh, scripts/in-flight and scripts/next-step;
# defines functions only.
#
# The transcript schema is observed, not documented. A launch's tool result
# opens "Command running in background with ID: <id>" or, for a command moved
# there by its foreground timeout, "Command did not complete within its <n>s
# timeout and was moved to the background (ID: <id>)" (Bash), or "Async agent
# launched" with an "agentId: <id>" line (Agent), a {"success":true,...} object
# with "resumedAgentId" (SendMessage resuming an agent), or "Monitor started
# (task <id>" (Monitor). Its task notification names the launch's tool_use id
# and a status. A launch is still running when:
#   - it has no notification with a finished status yet, or
#   - its latest notification says the agent "stopped with background work of
#     its own still running": the agent sent its report, but a shell or agent it
#     started is alive, so Claude Code still lists it and will notify again.
# Two kinds of launch never get a notification and are not running: one
# stopped by TaskStop (its result opens "Successfully stopped task: <id>", or
# "No task found with ID: <id>" when Claude Code no longer tracks it, so no
# notification can follow), and one made before the session last started or
# resumed (SINCE), whose process died with the old one. A line that is not JSON is skipped.

# inflight_mtime FILE: the modification time of the file FILE names, in epoch
# seconds, links followed (an agent's output file is a link to its transcript).
# Returns 1 when there is no such file.
inflight_mtime() {
  local t
  [ -n "$1" ] || return 1
  t=$(stat -L -c %Y -- "$1" 2>/dev/null | tr -d '\r') || t=""
  case $t in ''|*[!0-9]*) t=$(stat -L -f %m -- "$1" 2>/dev/null | tr -d '\r') || t="" ;; esac
  case $t in ''|*[!0-9]*) t=$(date -r "$1" +%s 2>/dev/null | tr -d '\r') || t="" ;; esac
  case $t in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$t"
}

# inflight_idle KIND ID OUTPUT_FILE TRANSCRIPT: "idle <N>m", the minutes since
# the launch's activity file last changed, or "idle -" when there is none. The
# file is the one the launch result names (OUTPUT_FILE, or "-"); an agent whose
# result names none, or whose named file is gone, is read from its own
# transcript, <session>/subagents/agent-<id>.jsonl beside the main one.
inflight_idle() {
  local kind=$1 id=$2 out=$3 tp=$4 t="" now
  [ "$out" = "-" ] || t=$(inflight_mtime "$out") || t=""
  if [ -z "$t" ] && [ "$kind" = agent ] && [ -n "$tp" ]; then
    t=$(inflight_mtime "${tp%.jsonl}/subagents/agent-$id.jsonl") || t=""
  fi
  if [ -z "$t" ]; then printf 'idle -'; return 0; fi
  now=$(date +%s)
  if [ "$now" -gt "$t" ]; then printf 'idle %sm' $(( (now - t) / 60 )); else printf 'idle 0m'; fi
}

# inflight_scan TRANSCRIPT [SINCE]
# stdout: one line per launch still running, six tab-separated fields:
#   <agent|shell|monitor> <task id> <started HH:MM> <idle Nm|idle -> <what> <work|service|timer>
# The start is the launch result's own timestamp in local time ("-" when it
# has none); the idle age is inflight_idle's; <what> is cut at 80 characters;
# the role is inflight_role's for a shell's command, and work for the rest.
# Returns 1 when the transcript could not be scanned, one named but missing
# included, which is not "nothing"; an empty TRANSCRIPT is nothing.
# jq reads it on stdin: under MSYS_NO_PATHCONV, jq.exe cannot open the /c/...
# form the session record's lookup yields.
inflight_scan() {
  local tp=$1 since=${2:-} events launched stopped latest running kind id start out what cmd roles
  local -a cmds=()
  [ -n "$tp" ] || return 0
  [ -f "$tp" ] || return 1
  events=$(set -o pipefail; jq -rR --arg since "$since" 'def hm($t): try ($t | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | localtime | strftime("%H:%M")) catch "-";
      def path_end: sub("\\s+$"; "") | sub("\\.(\\s.*)?$"; "");
      fromjson? | select(.isSidechain? != true)
      | select($since == "" or ((.timestamp? // $since) >= $since))
      | if .type? == "assistant" then
          .message.content? | arrays | .[] | select(.type? == "tool_use")
          | "U\t\(.id // "-")\t\((.input.description? // .input.command? // "") | tostring | gsub("[\t\r\n]+"; " ") | .[0:80])\t\((.input.command? // "") | tostring | (split("\n")[0] // "") | gsub("[\t\r]+"; " "))"
        elif .type? == "user" then
          (.timestamp? // "") as $ts
          | .message.content? | arrays | .[] | select(.type? == "tool_result")
          | (.content | if type == "array" then (.[0].text? // "") else tostring end) as $text
          | if ($text | test("^Command (running in background with ID|did not complete within its [0-9]+s timeout and was moved to the background)")) then
              "L\t\(.tool_use_id // "-")\t\(($text | capture("(with ID: |\\(ID: )(?<id>[A-Za-z0-9_-]+)").id) // "-")\tshell\t\(hm($ts))\t\(([$text | capture("Output is being written to: (?<p>[^\\r\\n]+)").p | path_end] | first) // "-")"
            elif ($text | test("^Async agent launched")) then
              "L\t\(.tool_use_id // "-")\t\(($text | capture("agentId: (?<id>[A-Za-z0-9_-]+)").id) // "-")\tagent\t\(hm($ts))\t\(([$text | capture("output_file: (?<p>[^\\r\\n]+)").p | path_end] | first) // "-")"
            elif ($text | test("^\\{\"success\":true,\"message\":\"Resuming agent ")) then
              "L\t\(.tool_use_id // "-")\t\(($text | capture("\"resumedAgentId\":\"(?<id>[A-Za-z0-9_-]+)\"").id) // "-")\tagent\t\(hm($ts))\t-"
            elif ($text | test("^Monitor started \\(task ")) then
              "L\t\(.tool_use_id // "-")\t\(($text | capture("^Monitor started \\(task (?<id>[A-Za-z0-9_-]+)").id) // "-")\tmonitor\t\(hm($ts))\t-"
            elif ($text | test("^(\\{\"message\":\")?Successfully (stopped task|killed shell): ")) then
              "S\t\(($text | capture("Successfully (stopped task|killed shell): (?<id>[A-Za-z0-9_-]+)").id) // "-")"
            elif ($text | test("^(<tool_use_error>)?No task found with ID: ")) then
              "S\t\(($text | capture("No task found with ID: (?<id>[A-Za-z0-9_-]+)").id) // "-")"
            else empty end
        else empty end' 2>/dev/null <"$tp" | tr -d '\r' | awk '{ print $0 "\t" NR }') || return 1
  # Each event ends in its index in the transcript: a stop removes the launches
  # of its id made before it, so a resume after a stop is running again.
  launched=$(awk -F '\t' '$1 == "L" && $2 != "-"' <<<"$events")
  [ -n "$launched" ] || return 0
  stopped=$(awk -F '\t' '$1 == "S" && $2 != "-" { print $2 "\t" $3 }' <<<"$events")
  # The latest notification per launch decides. Notifications are read only
  # where Claude Code delivers them (a queued command, a queue operation, or a
  # user message's own text), never from tool output that quotes one. Each is
  # copied into several entries, in order, so the last copy is the latest. A
  # resume reads as a running notification at its place in the transcript, so
  # the agent's earlier finished notification no longer decides.
  latest=$(set -o pipefail; jq -rR 'fromjson? | select(.isSidechain? != true)
      | [ .attachment.prompt?, (select(.type? == "queue-operation") | .content?),
          (select(.type? == "user") | .message.content? | if type == "string" then . elif type == "array" then (.[] | select(.type? == "text") | .text?) else empty end),
          (select(.type? == "user") | .message.content? | arrays | .[] | select(.type? == "tool_result")
            | (.content | if type == "array" then (.[0].text? // "") else tostring end)
            | select(test("^\\{\"success\":true,\"message\":\"Resuming agent "))
            | capture("\"resumedAgentId\":\"(?<id>[A-Za-z0-9_-]+)\"").id
            | "<task-notification><task-id>\(.)</task-id><status>running</status></task-notification>") ]
      | .[] | strings | select(contains("<task-notification>")) | gsub("[\r\n]+"; " ")' 2>/dev/null <"$tp" \
      | awk '
        # One line per delivered text; a text can carry several notifications.
        # A notification names the launch by task id and, usually, by tool_use
        # id: an agent'"'"'s final one after its own work ended carries only the
        # task id. Each key keeps the state of its latest notification.
        { n = split($0, chunk, "</task-notification>")
          for (i = 1; i <= n; i++) {
            c = chunk[i]
            if (c !~ /<status>[a-z_]+<\/status>/) continue
            state = "done"
            if (c ~ /<status>(running|pending)<\/status>/ || c ~ /background work of its own still running/) state = "running"
            seq++
            if (match(c, /<task-id>[^<]+<\/task-id>/)) print "t:" substr(c, RSTART + 9, RLENGTH - 19) "\t" seq "\t" state
            if (match(c, /<tool-use-id>[^<]+<\/tool-use-id>/)) print "u:" substr(c, RSTART + 13, RLENGTH - 27) "\t" seq "\t" state
          } }') || return 1
  # The three tables reach awk as files: a long transcript's events overflow
  # the per-string limit of an environment variable or an argument.
  running=$(awk -F '\t' '
      FILENAME == ARGV[1] { if ($0 != "") gone[$1] = $2 + 0; next }
      FILENAME == ARGV[2] { if ($0 != "") { seq[$1] = $2 + 0; state[$1] = $3 }; next }
      FILENAME == ARGV[3] { if ($1 == "U") { what[$2] = $3; cmd[$2] = $4 }; next }
      { u = "u:" $2; t = "t:" $3; k = ""
        if (u in seq) k = u
        if ((t in seq) && (k == "" || seq[t] > seq[k])) k = t
        if (k != "" && state[k] == "done") next }
      (($3 in gone) && gone[$3] > $7) || seen[$2]++ || ($3 != "-" && listed[$3]++) { next }
      { w = what[$2]; if (w == "") w = "(no description)"; print $4 "\t" $3 "\t" $5 "\t" $6 "\t" w "\t" cmd[$2] }' \
      <(printf '%s\n' "$stopped") <(printf '%s\n' "$latest") <(printf '%s\n' "$events") - <<<"$launched") || return 1
  [ -z "$running" ] && return 0
  while IFS=$'\t' read -r kind id start out what cmd; do
    [ "$kind" = shell ] && cmds+=("$cmd")
  done <<<"$running"
  roles=""
  # `--` keeps a command that opens with a dash a positional argument.
  if [ "${#cmds[@]}" -gt 0 ] && ! roles=$(MSYS_NO_PATHCONV=1 jq -r "$_INFLIGHT_ROLE"' $ARGS.positional[] | role($cfg)' --args -- "${cmds[@]}" < "$_INFLIGHT_SERVICES" 2>/dev/null); then
    roles=""
    echo "in-flight: could not tell services and timers from work (jq failed on $_INFLIGHT_SERVICES); every shell counts as work" >&2
  fi
  roles=${roles//$'\r'/}
  # A read loop, not mapfile: bash 3.2 has none.
  local -a role_of=()
  local line
  if [ -n "$roles" ]; then
    while IFS= read -r line; do role_of+=("$line"); done <<<"$roles"
  fi
  local n=0 role
  while IFS=$'\t' read -r kind id start out what cmd; do
    role=work
    if [ "$kind" = shell ]; then role=${role_of[$n]:-work}; n=$((n + 1)); fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$id" "$start" "$(inflight_idle "$kind" "$id" "$out" "$tp")" "$what" "$role"
  done <<<"$running"
}

# The services and the timer pattern the cockpit shares (config/services.json,
# contract C4). jq evaluates them: three patterns use lookahead, which grep -E
# lacks. A command is a timer when its trimmed first line is a bare sleep, and
# a service when a part of that line, split on &&, || and ;, trimmed and
# without leading NAME=value assignments, matches a services pattern.
_INFLIGHT_SERVICES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/services.json"
_INFLIGHT_ROLE='. as $cfg | def role($cfg): (split("\n")[0] // "") as $line
  | if ($line | gsub("^\\s+|\\s+$"; "") | test($cfg.timer)) then "timer"
    elif any($line | splits("&&|\\|\\||;") | gsub("^\\s+|\\s+$"; "") | sub("^(\\w+=\\S*\\s+)+"; ""); . as $part | any($cfg.services[]; . as $re | $part | test($re))) then "service"
    else "work" end;'

# inflight_role COMMAND: service, timer or work.
inflight_role() {
  local role
  if ! role=$(MSYS_NO_PATHCONV=1 jq -r --arg c "$1" "$_INFLIGHT_ROLE"' $c | role($cfg)' < "$_INFLIGHT_SERVICES" 2>/dev/null); then
    role=""
    echo "in-flight: could not tell services and timers from work (jq failed on $_INFLIGHT_SERVICES); the command counts as work" >&2
  fi
  role=${role//$'\r'/}
  printf '%s\n' "${role:-work}"
}

# inflight_queued TRANSCRIPT [SINCE]: status 0 when a task notification is
# still queued, so its delivery will start another turn. A dequeue names no
# entry and takes the oldest; a remove names its entry by content. Other
# queued entries stay in the queue so a dequeue still takes the right one.
inflight_queued() {
  local tp=$1 since=${2:-}
  [ -n "$tp" ] && [ -f "$tp" ] || return 1
  jq -rR --arg since "$since" 'fromjson? | select(.type? == "queue-operation" and .isSidechain? != true)
      | select($since == "" or ((.timestamp? // $since) >= $since))
      | [.operation // "", ((.content? // "") | tostring)] | @tsv' 2>/dev/null <"$tp" | tr -d '\r' | awk -F '\t' '
      $1 == "enqueue" { q[++last] = $2; next }
      $1 == "dequeue" { while (first < last) { first++; if (first in q) { delete q[first]; break } } next }
      $1 == "remove" { for (i = first + 1; i <= last; i++) if ((i in q) && q[i] == $2) { delete q[i]; break } }
      END { for (i in q) if (index(q[i], "<task-notification>")) exit 0; exit 1 }'
}

# inflight_text: inflight_scan's lines on stdin, the first five fields with
# single spaces between them and the role named when it is not work, for a
# person to read.
inflight_text() {
  awk -F '\t' '{ s = $1; m = NF < 5 ? NF : 5; for (i = 2; i <= m; i++) s = s " " $i
    if ($6 == "service") s = s " (service)"; else if ($6 == "timer") s = s " (timer)"
    print s }'
}

# inflight_list TRANSCRIPT SINCE SID: the session state file's launches when
# lib/session-state.sh trusts them (ss_launches, an agent with no output file
# aged by its transcript), else inflight_scan's lines, with its exit status.
inflight_list() {
  local out
  if [ -n "${3:-}" ] && out=$(ss_launches "$3" "$1"); then
    [ -z "$out" ] || printf '%s\n' "$out"
    return 0
  fi
  inflight_scan "$1" "${2:-}"
}

# inflight_source SID: "session file" or "transcript", the source
# inflight_list takes, without logging a rejection.
inflight_source() {
  if [ -n "${1:-}" ] && ( _ss_log() { :; }; ss_launches "$1" >/dev/null ); then
    printf 'session file\n'
  else
    printf 'transcript\n'
  fi
}

# inflight_since SESSION_ID: the time scripts/session-start.sh recorded when
# the session last started or resumed, or nothing.
inflight_since() {
  local f="${HOME:-}/.claude/dforge/sessions/turns/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-').since"
  [ -n "$1" ] && [ -f "$f" ] && head -n 1 "$f" | tr -d '\r'
  return 0
}

. "$(dirname "${BASH_SOURCE[0]}")/session-state.sh"
