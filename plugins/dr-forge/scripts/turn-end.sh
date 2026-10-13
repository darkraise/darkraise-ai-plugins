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

stamp="${HOME:-}/.claude/dr-forge/sessions/turns/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-')"
[ -f "$stamp" ] || exit 0
root=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
. "${SCRIPT_DIR}/lib/roots.sh"
# In a subshell, so a malformed config costs only this check, never the hook.
sdd=$(forge_ledger_root "$root") || sdd=""
# An auto run bound to this session (reference/auto-run.md) lives in the
# primary checkout, whichever worktree the turn ran in: its pending action.
auto_pending=$(cd "${cwd:-$PWD}" 2>/dev/null && bash "${SCRIPT_DIR}/auto-run" --session "$session_id" pending 2>/dev/null) || auto_pending=""
[ -d "$sdd" ] || [ -n "$auto_pending" ] || exit 0
root_shown=$PLUGIN_ROOT
if command -v cygpath >/dev/null 2>&1; then root_shown=$(cygpath -m "$PLUGIN_ROOT" 2>/dev/null || printf '%s' "$PLUGIN_ROOT"); fi
. "${SCRIPT_DIR}/lib/in-flight.sh"
# Background work this session started that is still listed (lib/in-flight.sh):
# no finished notification yet, or an agent that reported but left work of its
# own running.
running=$(inflight_scan "$transcript_path" "$(inflight_since "$session_id")")
pending=$(grep -c . <<<"$running" || true)
has_pending_background() { [ "$pending" -gt 0 ]; }

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
if has_pending_background; then
  case "$last" in
    *'## Next session'* | *'Which option?'*)
      reason="Your message ends the session (the next-step block or the finishing menu), but ${pending} background launch(es) you started this session are still running:
$(sed 's/^/- /' <<<"$running")
An agent that already sent its report is still running when work it started is alive. Do not hand off or finish over running work. Either wait for each (end the turn without the block; its notification starts the next turn), or stop it with TaskStop <id> and, if its result is not in hand, record a Ruling line in the ledger for the task it served. Then run next-step again and end with the fresh block."
      jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
      ;;
  esac
  exit 0
fi

# A turn of an auto run ends only on the sentinel line that answers its pending
# action; the cockpit compacts or clears on that line. Any other ending is held
# once.
if [ -n "$auto_pending" ]; then
  final_line=$(printf '%s\n' "$last" | sed -e 's/[[:space:]]*$//' -e '/^$/d' | tail -n 1)
  case "$auto_pending:$final_line" in
    'compact:Auto run: compacting' | 'clear:Auto run: clearing') exit 0 ;;
  esac
  reason="An auto run is bound to this session (pending: ${auto_pending}; see reference/auto-run.md), so its turns end only on a sentinel line. Do not stop: continue the run. When a budget line said compact, finish the task in flight, then end your message with the line \`Auto run: compacting\`. After \`auto-run clear\` exits 0, end with \`Auto run: clearing\`. If the run must stop (your human partner asked, or a stop the reference names), run \`bash ${root_shown}/scripts/auto-run stop --reason \"<why>\"\` first, then end as the attended flow would."
  if [ "$auto_pending" = after-compact ]; then
    reason="An auto run is bound to this session and a compaction already ran (pending: after-compact; see reference/auto-run.md), so no sentinel ends this turn. Do not stop: run \`bash ${root_shown}/scripts/auto-run after-compact\` now and follow what it prints (continue with the next task, or hand off and clear). If the run must stop, run \`bash ${root_shown}/scripts/auto-run stop --reason \"<why>\"\` first, then end as the attended flow would."
  fi
  if [ "$auto_pending" = handoff ]; then
    reason="An auto run is bound to this session and a compaction left too much behind (pending: handoff; see reference/auto-run.md §Clears), so this turn ends only on the clearing line, after the clear. Do not stop: finish the task in flight, run dr-forge:handoff, then \`bash ${root_shown}/scripts/auto-run clear\` and end with the line \`Auto run: clearing\`. If the run must stop, run \`bash ${root_shown}/scripts/auto-run stop --reason \"<why>\"\` first, then end as the attended flow would."
  fi
  jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
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
    ends_with '## Next session' 'If it gets none within ' && continue
    ledger=$candidate clean=0
  fi
  break
done < <(find "$sdd" -mindepth 2 -maxdepth 2 -name progress.md -newer "$stamp" 2>/dev/null | sort)
[ -n "$ledger" ] || exit 0

plan=$(head -n 1 "$ledger" | sed -n 's/^# SDD ledger — plan: //p' | tr -d '\r')
[ -n "$plan" ] || plan="PLAN_FILE"

if [ "$clean" = 1 ]; then
  reason="This turn advanced plan ${plan} and its final review is clean, but your message ends without the finishing menu. Invoke dr-forge:finishing-a-development-branch with the Skill tool now and follow it: tests, the rulings and amendments, then the integration menu as the last thing in your message."
else
  reason="This turn advanced plan ${plan}, but your message ends without the next step. If work remains for this session, continue it. If you are waiting on an agent or command you started in the background, end the turn without the block: its notification will start the next turn. If you are stopping, run \`bash ${root_shown}/scripts/next-step ${plan}\` and end your message with the block it prints, verbatim."
fi
jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
exit 0
