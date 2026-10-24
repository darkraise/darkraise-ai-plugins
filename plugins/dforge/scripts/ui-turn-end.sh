#!/usr/bin/env bash
# Stop hook: a turn that leaves UI changes without a passing proof is held
# once. The changes are the UI files that differ from the commit this
# checkout's branch pointed at when the turn started (scripts/turn-start.sh
# records it), committed or not; a passing proof is `ui-proof check` exit 0.
# It applies only where the gate is on: the project has a UI profile, or the
# session ran dforge:ui-ux. It stands down while an auto run is bound to the
# session (turn-end.sh owns those stops), on the retry (stop_hook_active), and
# when the last message carries "UI proof: pending" with its reason. Anything
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
[ "$is_retry" = true ] && exit 0
root=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
if (cd "$root" && bash "$SCRIPT_DIR/auto-run" --session "$session_id" pending >/dev/null 2>&1); then exit 0; fi

stamp="${HOME:-}/.claude/dforge/sessions/turns/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-')"
[ -f "$stamp.refs" ] || exit 0
base=$(tail -n +3 "$stamp.refs" | awk -F'\t' -v top="$root" 'stop { next } $2 == top { print $1; stop = 1 }')
[ -n "$base" ] || exit 0

. "$SCRIPT_DIR/lib/ui-ux.sh"
active=() act=""
if [ ! -f "$(uiux_profile "$root")" ]; then
  uiux_ran_skill "$transcript_path" || exit 0
  active=(--active) act=" --active"
fi
last=$(jq -r '.last_assistant_message // empty' <<<"$stdin_json")
case $last in *'UI proof: pending'*) exit 0 ;; esac

out=$(cd "$root" && bash "$SCRIPT_DIR/ui-proof" check --base "$base" ${active[@]+"${active[@]}"} 2>&1)
status=$?
[ "$status" -ne 0 ] || exit 0
# Exit 2 means the check could not run (a bad base, no fingerprint); that is
# not a pass, so it holds like exit 1 and the reason carries the error.

root_shown=$PLUGIN_ROOT
if command -v cygpath >/dev/null 2>&1; then root_shown=$(cygpath -m "$PLUGIN_ROOT" 2>/dev/null || printf '%s' "$PLUGIN_ROOT"); fi
reason="This turn leaves UI changes without a passing UI proof (dforge:ui-ux):
$out
Prove them before you say the work is done: run the dforge:ui-ux Prove phase (its references/walkthrough.md), stamp the report, record the judge's verdict, then run \`bash \"${root_shown}/scripts/ui-proof\" check --base ${base}${act}\` again. If the proof cannot happen in this turn, end your message with the line \`UI proof: pending — <why>\` instead, so the user knows the UI is unproven."
named=$(grep -E '^ui-proof: FAIL (scope|coverage)' <<<"$out" | sed 's/^ui-proof: FAIL //' | tr '\n' ';' | cut -c1-300)
[ -n "$named" ] || named=$(head -n 1 <<<"$out" | cut -c1-200)
jq -n --arg r "$reason" --arg m "dforge held the stop: UI files changed without a passing UI proof (${named%;})" \
  '{decision: "block", reason: $r, systemMessage: $m}'
exit 0
