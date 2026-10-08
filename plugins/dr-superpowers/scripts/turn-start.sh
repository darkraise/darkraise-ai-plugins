#!/usr/bin/env bash
# UserPromptSubmit hook: stamp the start of this session's turn, so the Stop
# hook (scripts/turn-end.sh) can tell whether this turn wrote a plan's ledger.
# Prints nothing and always exits 0; without jq or a session id it does nothing,
# and turn-end.sh then has no stamp and checks nothing.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
stdin_json="$(cat 2>/dev/null || true)"
session_id=$(jq -r '.session_id // empty' 2>/dev/null <<<"$stdin_json" || true)
[ -n "$session_id" ] || exit 0

turns_dir="${HOME:-}/.claude/dr-superpowers/sessions/turns"
mkdir -p "$turns_dir" 2>/dev/null || exit 0
touch "${turns_dir}/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-')" 2>/dev/null || true
find "$turns_dir" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null || true
exit 0
