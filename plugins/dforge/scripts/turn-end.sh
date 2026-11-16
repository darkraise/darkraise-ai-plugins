#!/usr/bin/env bash
# Stop hook: a turn that wrote a plan's ledger must end on the next step — the
# finishing menu once the final review is clean, or the `## Next session` block
# once finishing carried out the choice recorded before the run; otherwise the
# `## Next session` block from scripts/next-step. Controllers that summarize and
# stop (common on Sonnet) leave the human with neither. When the last message carries neither,
# block the stop once with the instruction; Claude Code sets stop_hook_active on
# the retry, which passes unless it ends the session over running work (below).
# A question to the human is no ending: the ledger's last line records it.
# Anything missing (jq, a ledger written this turn, or the turn stamp from scripts/turn-start.sh unless an auto run is
# bound to the session) passes silently, and so
# does a plain stop while an agent or command this session started in the
# background is still running: the controller is waiting on it, and its
# notification starts the next turn. A running service (a dev server, a
# watcher) is no such wait: it never ends on its own, so it neither passes a
# plain stop nor holds a session-ending one. The reverse is held once: a next-step
# block or finishing menu printed over running work would invite the human to
# end a session whose work is still in flight.
# A plan's hold also stands down while a task notification is still queued: its
# delivery starts another turn as soon as this one ends.
# An auto run is the exception to holding once: nobody is watching to send the
# next prompt, so its retries are held too, up to AUTO_HOLD_CAP in a row; past
# that the run stops and one last hold asks for the attended ending. Every hold
# also tells the user why the session went on (systemMessage).
set -uo pipefail

AUTO_HOLD_CAP=3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

command -v jq >/dev/null 2>&1 || exit 0
stdin_json="$(cat 2>/dev/null || true)"
jq -e . >/dev/null 2>&1 <<<"$stdin_json" || exit 0
session_id=$(jq -r '.session_id // empty' <<<"$stdin_json")
cwd=$(jq -r '.cwd // empty' <<<"$stdin_json")
transcript_path=$(jq -r '.transcript_path // empty' <<<"$stdin_json")
[ -n "$session_id" ] || exit 0
is_retry=$(jq -r '.stop_hook_active // false' <<<"$stdin_json")

hold() { # hold <reason> <what the user sees>
  jq -n --arg reason "$1" --arg msg "$2" '{decision: "block", reason: $reason, systemMessage: $msg}'
}

stamp="${HOME:-}/.claude/dforge/sessions/turns/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-')"
# Set while a session-ending message over running work has been held; a stop
# that is no retry starts a fresh count.
[ "$is_retry" = true ] || rm -f "$stamp.bg-held" 2>/dev/null
# An auto run bound to this session (reference/auto-run.md) lives in the
# primary checkout, whichever worktree the turn ran in: its pending action. It
# is read before the stamp gate, so a session with no stamp (a cleared one,
# whose first prompt the cockpit submitted) is still held.
auto_pending=$(cd "${cwd:-$PWD}" 2>/dev/null && bash "${SCRIPT_DIR}/auto-run" --session "$session_id" pending 2>/dev/null) || auto_pending=""
[ -f "$stamp" ] || [ -n "$auto_pending" ] || exit 0
root=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
. "${SCRIPT_DIR}/lib/roots.sh"
. "${SCRIPT_DIR}/lib/plan.sh"
# In a subshell, so a malformed config costs only this check, never the hook.
sdd=$(dforge_ledger_root "$root") || sdd=""
[ -d "$sdd" ] || [ -n "$auto_pending" ] || exit 0
. "${SCRIPT_DIR}/lib/last-message.sh"
. "${SCRIPT_DIR}/lib/next-ending.sh"
last=$(last_message "$stdin_json" "$transcript_path")

# Every ledger written this turn must have its ending, since two plans can be
# active in one checkout. A plan whose final review is clean ends on the
# finishing menu, one of finishing's own stops (failing tests, a discard or
# worktree prompt) or the next-step block, which names finishing; any other
# plan ends on the next-step block, on the finish-preference question asked
# before its first task, or on a question to the human that the ledger's last
# line records (`Task <N>: waiting — <question>`): the answer is the next
# prompt, so the session is not over. The next-step block counts only as
# next-step wrote it this turn (lib/next-ending.sh), never hand-typed. The
# first ledger without its ending names the reason.
ends_with() { local e; for e in "$@"; do case "$last" in *"$e"*) return 0 ;; esac; done; return 1; }
latest=""
wrote_block() { [ -n "$latest" ] || latest=$(dforge_latest_file "$root"); ending_released "$last" "$stamp" "$latest"; }
ledger="" clean=0
[ -d "$sdd" ] || sdd=""
ws="$(dforge_dir state "$root")/sdd"
while IFS= read -r candidate; do
  [ -n "$candidate" ] || continue
  # While progress is darkmem every worktree shares the mirror's work/sdd, and a
  # plan's workspace is always local: a ledger without one here is another
  # session's.
  [ -d "$ws/$(basename "$(dirname "$candidate")")" ] || continue
  # Only a clean line that still covers HEAD sends the session to finishing; a
  # stale or rewritten one is a plan advanced without its next step.
  if [ "$(plan_final_review_state "$candidate" "$root")" = current ]; then
    ends_with 'Which option?' "Type 'discard' to confirm" \
              'Must fix before completing' 'Worktree removal refused' && continue
    wrote_block && continue
    ledger=$candidate clean=1
  else
    ends_with 'Ask me then: show the finish menu' && continue
    wrote_block && continue
    tr -d '\r' < "$candidate" | sed '/^[[:space:]]*$/d' | tail -n 1 | grep -q '^Task [0-9][0-9]*: waiting — ' && continue
    ledger=$candidate clean=0
  fi
  break
done < <([ -z "$sdd" ] || find "$sdd" -mindepth 2 -maxdepth 2 -name progress.md -newer "$stamp" 2>/dev/null | sort)

# The transcript scan below costs seconds on a long session, and its result is
# read only when this stop could be held: an auto run is pending, a ledger
# written this turn lacks its ending, or the message ends the session.
case "$last" in
  *'## Next session'* | *'Which option?'*) ;;
  *) [ -n "$auto_pending" ] || [ -n "$ledger" ] || exit 0 ;;
esac

root_shown=$PLUGIN_ROOT
if command -v cygpath >/dev/null 2>&1; then root_shown=$(cygpath -m "$PLUGIN_ROOT" 2>/dev/null || printf '%s' "$PLUGIN_ROOT"); fi
. "${SCRIPT_DIR}/lib/in-flight.sh"
# Background work this session started that is still listed (lib/in-flight.sh):
# no finished notification yet, or an agent that reported but left work of its
# own running.
since=$(inflight_since "$session_id")
running=$(inflight_list "$transcript_path" "$since" "$session_id") \
  || running="(unknown: the transcript could not be scanned; check your background shells and agents by hand)"
# Services never end, so only work and timers are waited on.
running=$(awk -F '\t' '$6 != "service"' <<<"$running")
pending=$(grep -c . <<<"$running" || true)
has_pending_background() { [ "$pending" -gt 0 ]; }

# While background work runs, a plain stop is the controller waiting for it and
# passes, in any turn. A message that ends the session over it (the next-step
# block or the finishing menu) is held once, in any turn too: that is the
# handoff that would leave the work to die with the session. Once means once
# for this reason, retries included: the block often comes as the answer to an
# earlier hold, so stop_hook_active alone would let it through. A marker that
# cannot be written on a retry passes, since the retry could otherwise loop.
if has_pending_background; then
  case "$last" in
    *'## Next session'* | *'Which option?'*)
      [ "$is_retry" = true ] && [ -f "$stamp.bg-held" ] && exit 0
      { mkdir -p "$(dirname "$stamp")" && : > "$stamp.bg-held"; } 2>/dev/null || [ "$is_retry" != true ] || exit 0
      reason="Your message ends the session, but ${pending} background launch(es) are still running:
$(inflight_text <<<"$running" | sed 's/^/- /')
Wait for each (end the turn without the block), or stop it with TaskStop <id>, then run next-step again."
      hold "$reason" "dforge held the stop: this message ends the session while ${pending} background launch(es) still run"
      ;;
  esac
  exit 0
fi
[ "$is_retry" = true ] && [ -z "$auto_pending" ] && exit 0

# A turn of an auto run ends only on the sentinel line that answers its pending
# action; the cockpit compacts, clears or switches on that line. Any other ending is held
# once.
if [ -n "$auto_pending" ]; then
  final_line=$(printf '%s\n' "$last" | sed -e 's/[[:space:]]*$//' -e '/^$/d' | tail -n 1)
  case "$auto_pending:$final_line" in
    'compact:Auto run: compacting' | 'clear:Auto run: clearing' | 'switch:Auto run: switching') rm -f "$stamp.holds"; exit 0 ;;
  esac
  holds=0
  [ "$is_retry" = true ] && holds=$(cat "$stamp.holds" 2>/dev/null || echo 0)
  case $holds in '' | *[!0-9]*) holds=0 ;; esac
  holds=$((holds + 1))
  # A count that cannot be kept would hold forever: treat it as the cap.
  if ! { mkdir -p "$(dirname "$stamp")" && printf '%s\n' "$holds" > "$stamp.holds"; } 2>/dev/null; then
    holds=$((AUTO_HOLD_CAP + 1))
  fi
  if [ "$holds" -gt "$AUTO_HOLD_CAP" ]; then
    rm -f "$stamp.holds" 2>/dev/null
    why="the turn ended ${AUTO_HOLD_CAP} times in a row without its sentinel line"
    (cd "${cwd:-$PWD}" 2>/dev/null && bash "${SCRIPT_DIR}/auto-run" --session "$session_id" stop --reason "$why" >/dev/null 2>&1) || true
    hold "The auto run stopped: ${why}. End as reference/auto-run.md §Stopping says." "dforge: the auto run stopped (${why})"
    exit 0
  fi
  reason="An auto run is bound to this session (pending: ${auto_pending}; see reference/auto-run.md), so its turns end only on a sentinel line. Do not stop: continue the run. When a budget line said compact, finish the task in flight, then end your message with the line \`Auto run: compacting\`. After \`auto-run clear\` exits 0, end with \`Auto run: clearing\`. After \`auto-run switch\` exits 0, end with \`Auto run: switching\`. If the run must stop (your human partner asked, or a stop the reference names), run \`bash \"${root_shown}/scripts/auto-run\" stop --reason \"<why>\"\` first, then end as the attended flow would."
  if [ "$auto_pending" = switch ]; then
    reason="An auto run is bound to this session and the plan is saved (pending: switch; see reference/auto-run.md §The switch), so this turn ends only on the switching line. Do not stop: end your message with the line \`Auto run: switching\`; the cockpit then clears this session and starts the plan on its launch model. If the run must stop, run \`bash \"${root_shown}/scripts/auto-run\" stop --reason \"<why>\"\` first, then end as the attended flow would."
  fi
  if [ "$auto_pending" = after-compact ]; then
    reason="An auto run is bound to this session and a compaction already ran (pending: after-compact; see reference/auto-run.md), so no sentinel ends this turn. Do not stop: run \`bash \"${root_shown}/scripts/auto-run\" after-compact\` now and follow what it prints (continue with the next task, or hand off and clear). If the run must stop, run \`bash \"${root_shown}/scripts/auto-run\" stop --reason \"<why>\"\` first, then end as the attended flow would."
  fi
  if [ "$auto_pending" = handoff ]; then
    reason="An auto run is bound to this session and a compaction left too much behind (pending: handoff; see reference/auto-run.md §Clears), so this turn ends only on the clearing line, after the clear. Do not stop: finish the task in flight, run dforge:handoff, then \`bash \"${root_shown}/scripts/auto-run\" clear\` and end with the line \`Auto run: clearing\`. If the run must stop, run \`bash \"${root_shown}/scripts/auto-run\" stop --reason \"<why>\"\` first, then end as the attended flow would."
  fi
  hold "$reason" "dforge held the stop (auto run, hold ${holds} of ${AUTO_HOLD_CAP}): pending ${auto_pending}, and the turn did not end on its sentinel line"
  exit 0
fi

[ -n "$ledger" ] || exit 0
inflight_queued "$transcript_path" "$since" && exit 0

plan=$(head -n 1 "$ledger" | sed -n 's/^# SDD ledger — plan: //p' | tr -d '\r')
[ -n "$plan" ] || plan="PLAN_FILE"

if [ "$clean" = 1 ]; then
  reason="Plan ${plan} passed its final review. Invoke dforge:finishing-a-development-branch with the Skill tool now and end on its menu or next-step block."
  shown="dforge held the stop: plan ${plan} passed its final review, and the message ends without the finishing menu"
else
  reason="Plan ${plan} advanced without a next step. Continue the work, or ask: end the ledger with \`Task <N>: waiting — <question>\` and stop on the question. Else run \`bash \"${root_shown}/scripts/next-step\" ${plan}\` and end with its block verbatim. If background work runs, end the turn without the block."
  shown="dforge held the stop: plan ${plan} advanced, and the message ends without the next step"
fi
hold "$reason" "$shown"
exit 0
