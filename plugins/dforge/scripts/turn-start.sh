#!/usr/bin/env bash
# UserPromptSubmit hook: stamp the start of this session's turn, so the Stop
# hook (scripts/turn-end.sh) can tell whether this turn wrote a plan's ledger,
# and record the branch heads it starts from, so it can tell whether the turn
# moved one without a plan.
# Prints nothing and always exits 0; without jq or a session id it does nothing,
# and turn-end.sh then has no stamp and checks nothing.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
stdin_json="$(cat 2>/dev/null || true)"
session_id=$(jq -r '.session_id // empty' 2>/dev/null <<<"$stdin_json" || true)
[ -n "$session_id" ] || exit 0
cwd=$(jq -r '.cwd // empty' 2>/dev/null <<<"$stdin_json" || true)

turns_dir="${HOME:-}/.claude/dforge/sessions/turns"
mkdir -p "$turns_dir" 2>/dev/null || exit 0
stamp="${turns_dir}/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-')"
touch "$stamp" 2>/dev/null || true
# The resume time session-start.sh wrote is read for the whole session; a
# session that outlives the prune below would otherwise lose it.
[ ! -f "$stamp.since" ] || touch "$stamp.since" 2>/dev/null || true
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/turn-refs.sh"
if [ -n "$cwd" ] && turn_refs "$cwd" > "$stamp.refs.tmp" 2>/dev/null; then
  mv "$stamp.refs.tmp" "$stamp.refs" 2>/dev/null || true
else
  rm -f "$stamp.refs.tmp" "$stamp.refs" 2>/dev/null || true
fi
find "$turns_dir" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null || true
exit 0
