#!/usr/bin/env bash
# UserPromptSubmit hook: stamp the start of this session's turn, so the Stop
# hook (scripts/turn-end.sh) can tell whether this turn wrote a plan's ledger,
# and record the branch heads it starts from, which scripts/ui-turn-end.sh
# compares UI changes against.
# Prints nothing and always exits 0; without jq or a session id it does nothing,
# and turn-end.sh then has no stamp and checks nothing.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
stdin_json="$(cat 2>/dev/null || true)"
session_id=$(jq -r '.session_id // empty' 2>/dev/null <<<"$stdin_json" | tr -d '\r' || true)
[ -n "$session_id" ] || exit 0
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/stand-down.sh"
! stand_down_active "$session_id" || exit 0
cwd=$(jq -r '.cwd // empty' 2>/dev/null <<<"$stdin_json" | tr -d '\r' || true)

turns_dir="${HOME:-}/.claude/dforge/sessions/turns"
mkdir -p "$turns_dir" 2>/dev/null || exit 0
stamp="${turns_dir}/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-')"
touch "$stamp" 2>/dev/null || true
rm -f "$stamp.asked" 2>/dev/null || true
# The resume time session-start.sh wrote is read for the whole session; a
# session that outlives the prune below would otherwise lose it.
[ ! -f "$stamp.since" ] || touch "$stamp.since" 2>/dev/null || true
# The once-per-session markers are kept the same way.
[ ! -f "$stamp.ui-ux" ] || touch "$stamp.ui-ux" 2>/dev/null || true
[ ! -f "$stamp.nonode" ] || touch "$stamp.nonode" 2>/dev/null || true
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/turn-refs.sh"
if [ -n "$cwd" ] && turn_refs "$cwd" > "$stamp.refs.tmp" 2>/dev/null; then
  mv "$stamp.refs.tmp" "$stamp.refs" 2>/dev/null || true
elif [ -n "$cwd" ] && [ ! -d "$cwd" ] && primary=$(turn_primary "$(head -n 1 "$stamp.refs" 2>/dev/null | tr -d '\r')") \
     && turn_refs "$primary" > "$stamp.refs.tmp" 2>/dev/null; then
  # The session's checkout was removed (a merged worktree): turn-end.sh falls
  # back to the primary checkout, so its refs stand in, start-of-turn HEAD
  # included; without them a roadmap edit reads as a milestone close.
  mv "$stamp.refs.tmp" "$stamp.refs" 2>/dev/null || true
else
  rm -f "$stamp.refs.tmp" "$stamp.refs" 2>/dev/null || true
fi
# A roadmap kept outside git (darkmem documents) has no start-of-turn version
# in git: turn-end.sh compares its closed count with this one, beside the
# documents directory it was read from, so a stop in another repository never
# compares two roadmaps. In a subshell, since roots.sh exits on a malformed
# store config.
rm -f "$stamp.closed" 2>/dev/null || true
if [ -n "$cwd" ]; then
  (
    lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
    root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) \
      || root=$(turn_primary "$(head -n 1 "$stamp.refs" 2>/dev/null | tr -d '\r')") || exit 0
    . "$lib/roots.sh"
    dforge_stores_init "$root" 2>/dev/null
    [ "$_DFORGE_DOCS_STORE" != local ] && [ -n "$_DFORGE_DOCS_ROOT" ] && [ -f "$_DFORGE_DOCS_ROOT/roadmap.md" ] || exit 0
    docs=$_DFORGE_DOCS_ROOT
    . "$lib/roadmap.sh"
    closed=$(roadmap_rows "$docs/roadmap.md" | awk -F'\t' '$5 == "closed"' | grep -c .)
    printf '%s\t%s\n' "$closed" "$docs" > "$stamp.closed"
  ) 2>/dev/null
fi
find "$turns_dir" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null || true
exit 0
