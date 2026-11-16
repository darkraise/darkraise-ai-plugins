# fast_mode_on TRANSCRIPT [LAST_MESSAGE] — status 0 when the latest `Process:`
# line the main session wrote is `Process: fast`: the user chose to run the
# request without dforge's flow, so the hooks that enforce it stand down until
# a later `Process:` line starts the full flow again. The last message, when
# given, is read first: the transcript may not hold it yet at a stop.
fast_mode_process_lines() {
  tr -d '\r' | sed -nE 's/^[[:space:]`*]*(Process:.*)$/\1/p'
}
fast_mode_on() {
  local line
  line=$(printf '%s\n' "${2:-}" | fast_mode_process_lines | tail -n 1)
  if [ -z "$line" ] && [ -n "${1:-}" ] && [ -f "$1" ]; then
    line=$(jq -rR 'fromjson? | objects | select(.type? == "assistant" and .isSidechain? != true)
        | .message.content? | if type == "string" then . elif type == "array" then (.[] | select(.type? == "text") | .text? | strings) else empty end' \
        "$1" 2>/dev/null | fast_mode_process_lines | tail -n 1)
  fi
  grep -qE '^Process:[[:space:]]*fast([^[:alnum:]_-]|$)' <<<"$line"
}
