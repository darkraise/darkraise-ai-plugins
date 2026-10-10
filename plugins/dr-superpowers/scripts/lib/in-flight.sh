# Background work this session started that is still listed as running.
# Sourced by scripts/turn-end.sh, scripts/in-flight and scripts/next-step;
# defines functions only.
#
# The transcript schema is observed, not documented. A launch's tool result
# opens "Command running in background with ID: <id>" (Bash) or "Async agent
# launched" with an "agentId: <id>" line (Agent). Its task notification names
# the launch's tool_use id and a status. A launch is still running when:
#   - it has no notification with a finished status yet, or
#   - its latest notification says the agent "stopped with background work of
#     its own still running": the agent sent its report, but a shell or agent it
#     started is alive, so Claude Code still lists it and will notify again.
# Two kinds of launch never get a notification and are not running: one
# stopped by TaskStop (its result opens "Successfully stopped task: <id>"), and
# one made before the session last started or resumed (SINCE), whose process
# died with the old one. A line that is not JSON is skipped.

# inflight_scan TRANSCRIPT [SINCE]
# stdout: one line per launch still running: <agent|shell> <task id> <what>
inflight_scan() {
  local tp=$1 since=${2:-} events launched stopped latest
  [ -n "$tp" ] && [ -f "$tp" ] || return 0
  events=$(jq -rR --arg since "$since" 'fromjson? | select(.isSidechain? != true)
      | select($since == "" or ((.timestamp? // $since) >= $since))
      | if .type? == "assistant" then
          .message.content? | arrays | .[] | select(.type? == "tool_use")
          | "U\t\(.id // "-")\t\((.input.description? // .input.command? // "") | tostring | gsub("[\t\r\n]+"; " ") | .[0:80])"
        elif .type? == "user" then
          .message.content? | arrays | .[] | select(.type? == "tool_result")
          | (.content | if type == "array" then (.[0].text? // "") else tostring end) as $text
          | if ($text | test("^Command running in background with ID")) then
              "L\t\(.tool_use_id // "-")\t\(($text | capture("with ID: (?<id>[A-Za-z0-9_-]+)").id) // "-")\tshell"
            elif ($text | test("^Async agent launched")) then
              "L\t\(.tool_use_id // "-")\t\(($text | capture("agentId: (?<id>[A-Za-z0-9_-]+)").id) // "-")\tagent"
            elif ($text | test("^(\\{\"message\":\")?Successfully (stopped task|killed shell): ")) then
              "S\t\(($text | capture("Successfully (stopped task|killed shell): (?<id>[A-Za-z0-9_-]+)").id) // "-")"
            else empty end
        else empty end' "$tp" 2>/dev/null | tr -d '\r')
  launched=$(awk -F '\t' '$1 == "L" && $2 != "-"' <<<"$events")
  [ -n "$launched" ] || return 0
  stopped=$(awk -F '\t' '$1 == "S" && $2 != "-" { print $2 }' <<<"$events" | sort -u)
  # The latest notification per launch decides. Notifications are read only
  # where Claude Code delivers them (a queued command, a queue operation, or a
  # user message's own text), never from tool output that quotes one. Each is
  # copied into several entries, in order, so the last copy is the latest.
  latest=$(jq -rR 'fromjson? | select(.isSidechain? != true)
      | [ .attachment.prompt?, (select(.type? == "queue-operation") | .content?),
          (select(.type? == "user") | .message.content? | if type == "string" then . elif type == "array" then (.[] | select(.type? == "text") | .text?) else empty end) ]
      | .[] | strings | select(contains("<task-notification>")) | gsub("[\r\n]+"; " ")' "$tp" 2>/dev/null \
      | grep -oE '<tool-use-id>[^<]+</tool-use-id>[^<]*(<output-file>[^<]*</output-file>[^<]*)?<status>[a-z_]+</status>[^<]*(<summary>[^<]*</summary>[^<]*)?(<note>[^<]*</note>)?' \
      | awk '
        { id = $0; sub(/^<tool-use-id>/, "", id); sub(/<.*/, "", id)
          state = "done"
          if ($0 ~ /<status>(running|pending)<\/status>/ || $0 ~ /background work of its own still running/) state = "running"
          last[id] = state }
        END { for (id in last) print id "\t" last[id] }')
  STOPPED="$stopped" LATEST="$latest" EVENTS="$events" awk -F '\t' '
      BEGIN { n = split(ENVIRON["STOPPED"], s, "\n"); for (i = 1; i <= n; i++) gone[s[i]] = 1
              n = split(ENVIRON["LATEST"], l, "\n")
              for (i = 1; i <= n; i++) { split(l[i], p, "\t"); state[p[1]] = p[2] }
              n = split(ENVIRON["EVENTS"], e, "\n")
              for (i = 1; i <= n; i++) { split(e[i], p, "\t"); if (p[1] == "U") what[p[2]] = p[3] } }
      ($2 in state) && state[$2] == "done" { next }
      ($3 in gone) || seen[$2]++ { next }
      { w = what[$2]; if (w == "") w = "(no description)"; print $4 " " $3 " " w }' <<<"$launched"
}

# inflight_since SESSION_ID: the time scripts/session-start.sh recorded when
# the session last started or resumed, or nothing.
inflight_since() {
  local f="${HOME:-}/.claude/dr-superpowers/sessions/turns/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-').since"
  [ -n "$1" ] && [ -f "$f" ] && head -n 1 "$f" | tr -d '\r'
  return 0
}
