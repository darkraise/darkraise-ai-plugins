#!/usr/bin/env bash
# Stop hook: a turn that wrote a plan's ledger must end on the next step — the
# finishing menu once the final review is clean, otherwise the `## Next session`
# block from scripts/next-step. Controllers that summarize and stop (common on
# Sonnet) leave the human with neither. When the last message carries neither,
# block the stop once with the instruction; Claude Code sets stop_hook_active on
# the retry, which always passes. Anything missing (jq, the turn stamp from
# scripts/turn-start.sh, a ledger written this turn) passes silently.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

command -v jq >/dev/null 2>&1 || exit 0
stdin_json="$(cat 2>/dev/null || true)"
jq -e . >/dev/null 2>&1 <<<"$stdin_json" || exit 0
[ "$(jq -r '.stop_hook_active // false' <<<"$stdin_json")" = "true" ] && exit 0

session_id=$(jq -r '.session_id // empty' <<<"$stdin_json")
cwd=$(jq -r '.cwd // empty' <<<"$stdin_json")
transcript_path=$(jq -r '.transcript_path // empty' <<<"$stdin_json")
[ -n "$session_id" ] || exit 0

stamp="${HOME:-}/.claude/dr-superpowers/sessions/turns/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-')"
[ -f "$stamp" ] || exit 0
root=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -d "$root/.superpowers/sdd" ] || exit 0
ledger=$(find "$root/.superpowers/sdd" -mindepth 2 -maxdepth 2 -name progress.md -newer "$stamp" 2>/dev/null | head -n 1)
[ -n "$ledger" ] || exit 0

last=$(jq -r '.last_assistant_message // empty' <<<"$stdin_json")
if [ -z "$last" ] && [ -f "$transcript_path" ]; then
  last=$(jq -rs '[.[] | select(.type == "assistant")] | last | .message.content
    | if type == "string" then . elif type == "array" then map(select(.type == "text") | .text) | join("\n") else "" end' \
    "$transcript_path" 2>/dev/null || true)
fi

# The endings the skills prescribe: the next-step block, the finishing menu,
# and finishing's own stops (failing tests, a discard or worktree prompt).
for ending in '## Next session' 'Which option?' "Type 'discard' to confirm" \
              'Must fix before completing' 'Worktree removal refused'; do
  case "$last" in *"$ending"*) exit 0 ;; esac
done

plan=$(head -n 1 "$ledger" | sed -n 's/^# SDD ledger — plan: //p' | tr -d '\r')
[ -n "$plan" ] || plan="PLAN_FILE"
root_shown=$PLUGIN_ROOT
if command -v cygpath >/dev/null 2>&1; then root_shown=$(cygpath -m "$PLUGIN_ROOT" 2>/dev/null || printf '%s' "$PLUGIN_ROOT"); fi

if grep -q '^Final review: clean' "$ledger"; then
  reason="This turn advanced plan ${plan} and its final review is clean, but your message ends without the finishing menu. Invoke dr-superpowers:finishing-a-development-branch with the Skill tool now and follow it: tests, the rulings and amendments, then the integration menu as the last thing in your message."
else
  reason="This turn advanced plan ${plan}, but your message ends without the next step. If work remains for this session, continue it. If you are stopping, run \`bash ${root_shown}/scripts/next-step ${plan}\` and end your message with the block it prints, verbatim."
fi
jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
exit 0
