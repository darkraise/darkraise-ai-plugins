#!/usr/bin/env bash
# Stop hook: a turn that leaves UI changes without a passing proof is held
# once. The changes are the UI files that differ from the commit this
# checkout's branch pointed at when the turn started (scripts/turn-start.sh
# records it), committed or not; a passing proof is `ui-proof check` exit 0.
# It applies only where the gate is on: the project has a UI profile, or the
# session ran dforge:ui-ux. It stands down while an auto run is bound to the
# session (turn-end.sh owns those stops), on the retry (stop_hook_active), in
# fast mode (lib/fast-mode.sh), when the last message ends with
# "UI proof: pending — <why>", when it carries the `## Next session` block
# next-step wrote this turn (a handoff; lib/next-ending.sh; without a turn
# stamp, any such block), when a ledger written this turn ends on a `Task <N>: waiting — `
# question, and while finite background work or a timer runs (lib/in-flight.sh):
# each of those stops is not a claim that the UI work is done. The last message
# is the hook's, else the transcript's (lib/last-message.sh). Anything
# missing (jq, the turn stamp, a branch head for this checkout) passes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
command -v jq >/dev/null 2>&1 || exit 0
stdin_json="$(cat 2>/dev/null || true)"
jq -e . >/dev/null 2>&1 <<<"$stdin_json" || exit 0
session_id=$(jq -r '.session_id // empty' <<<"$stdin_json")
cwd=$(jq -r '.cwd // empty' <<<"$stdin_json")
transcript_path=$(jq -r '.transcript_path // empty' <<<"$stdin_json")
is_retry=$(jq -r '.stop_hook_active // false' <<<"$stdin_json")
[ -n "$session_id" ] || exit 0
. "$SCRIPT_DIR/lib/stand-down.sh"
! stand_down_active "$session_id" || exit 0
[ "$is_retry" = true ] && exit 0
root=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
if (cd "$root" && bash "$SCRIPT_DIR/auto-run" --session "$session_id" pending >/dev/null 2>&1); then exit 0; fi

stamp="${HOME:-}/.claude/dforge/sessions/turns/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-')"
[ -f "$stamp.refs" ] || exit 0
base=$(tail -n +3 "$stamp.refs" | awk -F'\t' -v top="$root" 'stop { next } $2 == top { print $1; stop = 1 }')
[ -n "$base" ] || exit 0

. "$SCRIPT_DIR/lib/ui-ux.sh"
# No UI file differs from the base: ui-proof check would pass, so the stop
# passes before the transcript scans below. A base git cannot resolve is left
# to the check, which holds with its error.
if git -C "$root" rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1 \
   && [ -z "$(uiux_changed "$root" "$base")" ]; then
  exit 0
fi
active=() act=""
if [ ! -f "$(uiux_profile "$root")" ]; then
  uiux_ran_skill "$transcript_path" || exit 0
  active=(--active) act=" --active"
fi
. "$SCRIPT_DIR/lib/last-message.sh"
message=$(last_message "$stdin_json" "$transcript_path")
last=$(printf '%s\n' "$message" | tr -d '\r' | awk 'NF { l = $0 } END { print l }')
last=$(sed -E 's/^[[:space:]`]+//; s/[[:space:]`]+$//' <<<"$last")
# Only the closing line counts, so quoting the hook's own wording mid-message
# does not release it.
if grep -qE '^UI proof: pending[[:space:]]+(—|–|-)[[:space:]]*[^[:space:]]' <<<"$last"; then exit 0; fi
. "$SCRIPT_DIR/lib/fast-mode.sh"
fast_mode_on "$transcript_path" "$message" && exit 0
. "$SCRIPT_DIR/lib/roots.sh"
. "$SCRIPT_DIR/lib/next-ending.sh"
if [ -f "$stamp" ]; then
  ending_released_any "$message" "$stamp" "$(dforge_latest_file "$root")" "$root" && exit 0
else
  grep -qF '## Next session' <<<"$message" && exit 0
fi
if [ -f "$stamp" ]; then
  . "$SCRIPT_DIR/lib/plan.sh"
  sdd=$(dforge_ledger_root "$root") || sdd=""
  ws="$(dforge_dir state "$root")/sdd"
  if [ -d "$sdd" ]; then
    while IFS= read -r ledger; do
      # As turn-end.sh reads it: under darkmem progress every worktree shares
      # the mirror's ledgers, and one without a workspace here is another's.
      [ -d "$ws/$(basename "$(dirname "$ledger")")" ] || continue
      tr -d '\r' < "$ledger" | awk 'NF { l = $0 } END { print l }' | grep -qE '^Task [0-9]+: waiting — ' && exit 0
    done < <(find "$sdd" -name progress.md -newer "$stamp" 2>/dev/null)
  fi
fi
. "$SCRIPT_DIR/lib/in-flight.sh"
if running=$(inflight_list "$transcript_path" "$(inflight_since "$session_id")" "$session_id" 2>/dev/null) \
   && [ -n "$(awk -F '\t' '$6 == "work" || $6 == "timer"' <<<"$running")" ]; then
  exit 0
fi

out=$(cd "$root" && bash "$SCRIPT_DIR/ui-proof" check --base "$base" ${active[@]+"${active[@]}"} 2>&1)
status=$?
[ "$status" -ne 0 ] || exit 0
# Exit 2 means the check could not run (a bad base, no fingerprint); that is
# not a pass, so it holds like exit 1 and the reason carries the error.

root_shown=$PLUGIN_ROOT
if command -v cygpath >/dev/null 2>&1; then root_shown=$(cygpath -m "$PLUGIN_ROOT" 2>/dev/null || printf '%s' "$PLUGIN_ROOT"); fi
named=$(grep -E '^ui-proof: FAIL (scope|coverage)' <<<"$out" | sed 's/^ui-proof: FAIL //' | tr '\n' ';' | cut -c1-300)
[ -n "$named" ] || named=$(head -n 1 <<<"$out" | cut -c1-200)
reason="Run the dforge:ui-ux Prove phase, then \`bash \"${root_shown}/scripts/ui-proof\" check --base ${base}${act}\`; if the proof cannot happen this turn, end your message with the line \`UI proof: pending — <why>\`. Failure: UI files changed without a passing UI proof (${named%;})."
jq -n --arg r "$reason" --arg m "dforge: Claude is proving the UI changes before it stops; nothing is needed from you." \
  '{decision: "block", reason: $r, systemMessage: $m}'
exit 0
