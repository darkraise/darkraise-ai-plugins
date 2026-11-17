# stand_down_active SESSION_ID: status 0 when scripts/workflow-guard.mjs found
# another workflow plugin enabled at this session's start and left its marker
# (${CLAUDE_PLUGIN_DATA}/workflow-guard/<id, every other character a ->), so
# the hook calling it does nothing; 1 otherwise, or when either is empty.
stand_down_active() {
  [ -n "${CLAUDE_PLUGIN_DATA:-}" ] && [ -n "${1:-}" ] || return 1
  [ -e "${CLAUDE_PLUGIN_DATA}/workflow-guard/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')" ]
}
