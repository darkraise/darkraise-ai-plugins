#!/usr/bin/env bash
# Async Stop hook: darkmem's safety-net push (darkmem store options spec §5),
# apart from turn-end.sh so a slow darkmem never delays a turn's end or its
# decision. Claude Code waits for nothing here and enforces no timeout, so the
# push bounds itself (lib/darkmem-hook.sh). Prints nothing; always exits 0.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v jq >/dev/null 2>&1 || exit 0
stdin_json="$(cat 2>/dev/null || true)"
jq -e . >/dev/null 2>&1 <<<"$stdin_json" || exit 0
session_id=$(jq -r '.session_id // empty' <<<"$stdin_json")
cwd=$(jq -r '.cwd // empty' <<<"$stdin_json")
[ -n "$session_id" ] || exit 0
hook_lib="${SCRIPT_DIR}/lib/darkmem-hook.sh"
# darkmem_push_quietly bounds its config lookup and its push apart; a bound
# here around both would not reach the push's own.
if . "$hook_lib" 2>/dev/null; then
  darkmem_push_quietly "${cwd:-$PWD}" "$session_id" >/dev/null 2>&1
fi
exit 0
