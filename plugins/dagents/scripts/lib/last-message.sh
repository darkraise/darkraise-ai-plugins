# Sourced; functions only; needs jq. The last assistant message of a stop.

# _last_message_text — the text of the last assistant entry on stdin. Streamed,
# never slurped: a transcript reaches hundreds of megabytes.
_last_message_text() {
  jq -nrR 'reduce (inputs | fromjson? | objects | select(.type == "assistant")) as $e (null; $e)
    | values | .message.content
    | if type == "string" then . elif type == "array" then map(select(.type == "text") | .text) | join("\n") else "" end' \
    2>/dev/null || true
}

# last_message STDIN_JSON TRANSCRIPT — the hook's last_assistant_message, else
# the transcript's last assistant entry: some stops carry no message.
last_message() {
  local last
  last=$(jq -r '.last_assistant_message // empty' <<<"$1" 2>/dev/null)
  if [ -z "$last" ] && [ -n "${2:-}" ] && [ -f "$2" ]; then
    last=$(tail -n 400 "$2" | _last_message_text)
    [ -n "$last" ] || last=$(_last_message_text < "$2")
  fi
  printf '%s' "$last"
}
