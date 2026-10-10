#!/usr/bin/env bash
# Stop hook: a turn that wrote a plan's ledger must end on the next step — the
# finishing menu once the final review is clean, otherwise the `## Next session`
# block from scripts/next-step. Controllers that summarize and stop (common on
# Sonnet) leave the human with neither. When the last message carries neither,
# block the stop once with the instruction; Claude Code sets stop_hook_active on
# the retry, which always passes. Anything missing (jq, the turn stamp from
# scripts/turn-start.sh, a ledger written this turn) passes silently, and so
# does a plain stop while an agent or command this session started in the
# background is still running: the controller is waiting on it, and its
# notification starts the next turn. The reverse is held once: a next-step
# block or finishing menu printed over running work would invite the human to
# end a session whose work is still in flight.
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
# Background launches answered with a task id but no finished notification yet.
# The tool result opens "Command running in background with ID" (Bash) or
# "Async agent launched" (Agent); the notification names the launch's tool_use id beside its
# status. A line that is not JSON is skipped rather than ending the scan.
has_pending_background() {
  [ -n "$transcript_path" ] && [ -f "$transcript_path" ] || return 1
  local launched finished
  launched=$(jq -rR 'fromjson? | select(.type? == "user" and .isSidechain? != true) | .message.content? | arrays | .[]
      | select(.type? == "tool_result")
      | select((.content | if type == "array" then (.[0].text? // "") else tostring end)
          | test("^(Command running in background with ID|Async agent launched)"))
      | .tool_use_id // empty' "$transcript_path" 2>/dev/null | tr -d '\r' | sort -u)
  [ -n "$launched" ] || return 1
  finished=$(grep -oE '<tool-use-id>[^<]+</tool-use-id>[^<]*(<output-file>[^<]*</output-file>[^<]*)?<status>[a-z_]+</status>' \
      "$transcript_path" 2>/dev/null | grep -vE '<status>(running|pending)</status>' \
      | sed -E 's/^<tool-use-id>([^<]+)<.*/\1/' | tr -d '\r' | sort -u)
  pending=$(comm -23 <(printf '%s\n' "$launched") <(printf '%s\n' "$finished") | grep -c .)
  [ "$pending" -gt 0 ]
}

last=$(jq -r '.last_assistant_message // empty' <<<"$stdin_json")
if [ -z "$last" ] && [ -f "$transcript_path" ]; then
  last=$(jq -rs '[.[] | select(.type == "assistant")] | last | .message.content
    | if type == "string" then . elif type == "array" then map(select(.type == "text") | .text) | join("\n") else "" end' \
    "$transcript_path" 2>/dev/null || true)
fi

# While background work runs, a plain stop is the controller waiting for it and
# passes, in any turn. A message that ends the session over it (the next-step
# block or the finishing menu) is held once, in any turn too: that is the
# handoff that would leave the work to die with the session.
pending=0
if has_pending_background; then
  case "$last" in
    *'## Next session'* | *'Which option?'*)
      reason="Your message ends the session (the next-step block or the finishing menu), but ${pending} background launch(es) you started this session have not reported back. Do not hand off over running work. Either wait for each (end the turn without the block; its notification starts the next turn), or stop it with TaskStop and record a Ruling line in the ledger for the task it served, then run next-step again and end with the fresh block."
      jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
      ;;
  esac
  exit 0
fi

# Every ledger written this turn must have its ending, since two plans can be
# active in one checkout. A plan whose final review is clean ends on the
# finishing menu, one of finishing's own stops (failing tests, a discard or
# worktree prompt) or the next-step block, which names finishing; any other
# plan ends on the next-step block, or on the finish-preference question asked
# before its first task. The first ledger without its ending names the reason.
ends_with() { local e; for e in "$@"; do case "$last" in *"$e"*) return 0 ;; esac; done; return 1; }
ledger="" clean=0
while IFS= read -r candidate; do
  [ -n "$candidate" ] || continue
  if grep -q '^Final review: clean' "$candidate"; then
    ends_with '## Next session' 'Which option?' "Type 'discard' to confirm" \
              'Must fix before completing' 'Worktree removal refused' && continue
    ledger=$candidate clean=1
  else
    ends_with '## Next session' 'If it gets none within 30 minutes' && continue
    ledger=$candidate clean=0
  fi
  break
done < <(find "$root/.superpowers/sdd" -mindepth 2 -maxdepth 2 -name progress.md -newer "$stamp" 2>/dev/null | sort)
[ -n "$ledger" ] || exit 0

plan=$(head -n 1 "$ledger" | sed -n 's/^# SDD ledger — plan: //p' | tr -d '\r')
[ -n "$plan" ] || plan="PLAN_FILE"
root_shown=$PLUGIN_ROOT
if command -v cygpath >/dev/null 2>&1; then root_shown=$(cygpath -m "$PLUGIN_ROOT" 2>/dev/null || printf '%s' "$PLUGIN_ROOT"); fi

if [ "$clean" = 1 ]; then
  reason="This turn advanced plan ${plan} and its final review is clean, but your message ends without the finishing menu. Invoke dr-superpowers:finishing-a-development-branch with the Skill tool now and follow it: tests, the rulings and amendments, then the integration menu as the last thing in your message."
else
  reason="This turn advanced plan ${plan}, but your message ends without the next step. If work remains for this session, continue it. If you are waiting on an agent or command you started in the background, end the turn without the block: its notification will start the next turn. If you are stopping, run \`bash ${root_shown}/scripts/next-step ${plan}\` and end your message with the block it prints, verbatim."
fi
jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
exit 0
