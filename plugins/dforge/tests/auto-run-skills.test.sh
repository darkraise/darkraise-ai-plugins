#!/usr/bin/env bash
# Both execution skills carry the auto run where a plan run would otherwise
# stop for its human: each check is a whole instruction, not a keyword.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID DFORGE_BUDGET CLAUDE_PROJECT_DIR

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" "yes"
}

for skill in subagent-driven-development executing-plans; do
  F="$P/skills/$skill/SKILL.md"
  names "$skill: the section" "$F" '## Auto run'
  names "$skill: after a compaction" "$F" '`scripts/auto-run after-compact` before step 0 above'
  names "$skill: setup asks nothing, from the worktree" "$F" 'from the execution worktree, once dforge:using-git-worktrees has created it.'
  names "$skill: exit 4 is a skipped worktree" "$F" 'Exit 4 means the worktree step was skipped: create the worktree, then run'
  names "$skill: no ledger goes to Setup" "$F" 'no ledger names this plan, no task has started: skip the rest of this'
  names "$skill: setup due goes to Setup" "$F" '0. In an auto run, when `scripts/auto-run status` says setup is due, or when'
  names "$skill: a task-complete stop" "$F" 'A `task-complete` exit 5 means the run stopped (a task was completed in the'
  names "$skill: dependents come from the plan" "$F" 'names the task; in a plan without those lines, its `Consumes:` line cites'
  names "$skill: compact still ends the turn at the final check" "$F" 'a `compact` line still ends the turn on `Auto run: compacting`.'
  check "$skill: no handoff rule at the final check" "$(grep -c "Auto run section's \`handoff\`" "$F")" "0"
  names "$skill: blocked goes to Fable" "$F" '`BLOCKED` goes on the pending list and one Fable batch runs at once'
  names "$skill: the deferred line" "$F" 'Task <N>: complete (deferred by the auto run)'
  names "$skill: dependents are deferred too" "$F" 'and every task that depends on it'
  names "$skill: never performed" "$F" 'irreversible, security-sensitive or outside-the-worktree action is never'
  case $skill in
    executing-plans) after='`scripts/auto-run task-complete`. After each task, run the Fable batch when' ;;
    *) after='`scripts/auto-run task-complete`. After each wave, or each task in' ;;
  esac
  names "$skill: each task resets the count" "$F" "$after"
  names "$skill: compact ends the turn" "$F" '`Auto run: compacting` as its last line'
  names "$skill: the step owns the clear" "$F" 'then run `scripts/auto-run clear` and end as auto-run.md §Clears says'
  names "$skill: a handoff line waits for the task in flight" "$F" 'On `handoff`, finish the task in'
  names "$skill: the finish is the one outside action" "$F" '(the finish action is the one exception)'
  names "$skill: final review" "$F" 'run `scripts/auto-run phase final`'
  names "$skill: the four stops give way" "$F" 'except in an auto run'
done
names "subagent-driven-development: a deferred task is not merged" "$P/skills/subagent-driven-development/SKILL.md" "a deferred task's branch is"
EPF="$P/skills/executing-plans/SKILL.md"
names "executing-plans: step 7 runs task-complete" "$EPF" 'auto run, run `scripts/auto-run task-complete`, then the Fable batch when'
names "executing-plans: step 8 moves to the final phase" "$EPF" '`scripts/context-size --final`; in an auto run it moves the run to the'
names "executing-plans: the budget section says so too" "$EPF" 'Finishing is never budget-checked. In an auto run `--final` also moves the'
names "subagent-driven-development: the budget section says so" "$P/skills/subagent-driven-development/SKILL.md" 'from the ledger. In an auto run `--final` also moves the run to the final'
names "executing-plans: the mode switch clears by phase" "$EPF" '`scripts/auto-run clear --phase`, and end the turn with'
names "executing-plans: the mode switch in an auto run" "$EPF" 'not need. In an auto run, run dforge:handoff steps 0-4, then'
names "delegated-task.md: task-complete after the complete line" "$P/reference/delegated-task.md" 'In an auto run, run `scripts/auto-run task-complete`, then the Fable batch when'
names "parallel-waves.md: task-complete after the merge" "$P/reference/parallel-waves.md" '`; merged <sha7>`. In an auto run, run `scripts/auto-run task-complete`'
names "parallel-waves.md: before any budget check" "$P/reference/parallel-waves.md" 'right after it, before any budget check or dispatch; the Fable batch runs'
names "handoff: the mode switch hands off too" "$P/skills/handoff/SKILL.md" 'mode hands off too, and the step that invoked this skill runs'

R="$P/reference/auto-run.md"
names "auto-run.md: an unwritten handoff stops the run" "$R" 'If `scripts/next-step` exits 4, do not run `scripts/auto-run clear`'
names "auto-run.md: Stopping lists it" "$R" '`scripts/next-step` exits 4 during a clear (see Clears).'
names "auto-run.md: a deferred task keeps the branch" "$R" 'also keeps the branch when the ledger holds a'
names "finishing: a deferred task keeps the branch" "$P/skills/finishing-a-development-branch/SKILL.md" '`merge` keeps when the ledger holds a'
names "auto-run.md: the critic runs before Fable" "$R" 'After your own self-review round and the architecture critic'
names "auto-run.md: a late statement goes up the ladder" "$R" 'is never asked: it goes up the ladder under Rulings'
names "auto-run.md: an undecided critic Blocker" "$R" '--note "critic Blocker unresolved"'
names "auto-run.md: a statement is deferred, not guessed" "$R" '**An acceptance statement in the spec phase:** the statement is deferred, not'
names "auto-run.md: QA ambiguity is parked" "$R" '**A QA `acceptance-ambiguous` item:** PARK it'
names "auto-run.md: QA ambiguity batches at once" "$R" 'A batch runs at once for a blocked task and for a QA'
names "auto-run.md: a critic Blocker takes its own note" "$R" 'it leaves undecided or without a suggestion to the run'"'"'s register, except a'
names "auto-run.md: unverified acceptance keeps the branch" "$R" '`merge` also keeps the branch when the `Acceptance QA: complete` line reports a nonzero count of'
names "auto-run.md: an untested statement keeps the branch" "$R" '`cannot-test`, or when the run added a deferred register row'
names "auto-run.md: fail and flaky counts are not read" "$R" 'at it. The line'"'"'s `fail` and `flaky` counts are not read: they are taken'
names "auto-run.md: a deferred statement or unresolved Blocker keeps the branch" "$R" 'whose Item begins `A<n>:` or whose Note is `critic Blocker unresolved`'
names "auto-run.md: the final message lists demos and lenses" "$R" 'every `demo` statement of the spec, every lens'
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
names "finishing: unverified acceptance keeps the branch" "$FIN" '`merge` also keeps when the `Acceptance QA: complete` line reports a nonzero count of'
names "finishing: an untested statement keeps the branch" "$FIN" '`cannot-test`, or when the run added a deferred register'
names "finishing: fail and flaky counts are not read" "$FIN" 'The line'"'"'s `fail` and `flaky` counts are not read: they are taken before'
for f in "$R" "$FIN"; do
  check "$(basename "$f"): a fixed QA failure does not keep the branch" \
    "$(grep -qF -- 'nonzero count of' "$f" && grep -A1 -F -- 'nonzero count of' "$f" | grep -qF -- '`fail`, `flaky` or' && echo yes || echo no)" "no"
done
names "finishing: a deferred statement or unresolved Blocker keeps the branch" "$FIN" 'row whose Item begins `A<n>:` or whose Note is `critic Blocker unresolved`.'
names "finishing: the final message lists demos and lenses" "$FIN" 'every `demo` statement of the spec, every lens'

# The default flow (docs/superpowers/specs/2026-10-18-auto-execution-default-design.md).
names "auto-run.md: the default" "$R" 'The default on Claude Code (`autoRun=on`): once your human partner approves the'
names "auto-run.md: the switch section" "$R" '## The switch'
names "auto-run.md: the switching line" "$R" '- `Auto run: switching` after `scripts/auto-run switch` exits 0.'
names "auto-run.md: plan saved is no clear" "$R" 'Plan saved is no clear: the session switches in place (§The switch).'
names "auto-run.md: finishing reads the recorded choice" "$R" 'the choice `scripts/finish-choice get --plan PLAN_FILE` prints, which the spec'
names "auto-run.md: a spec-review deferral keeps a merge" "$R" 'deferred at the spec review, before the run started, counts as one the run'
check "auto-run.md: the one phase clear is the mode switch" "$(grep -c 'clear --phase' "$R")" "1"
names "auto-run.md: the mode switch clears by phase" "$R" '- **A switch from inline to subagent mode** (dforge:executing-plans'
names "auto-run.md: the switch starts at Setup" "$R" 'execution skill starts at its Setup, worktree first: `scripts/auto-run status`'
names "auto-run.md: a listed launch is waited for" "$R" 'listed: run `scripts/in-flight`, wait for or stop each launch it lists, and'
names "auto-run.md: a second exit 5 stops the run" "$R" '`scripts/auto-run stop --reason "background work still running at the switch: <next-step'"'"'s message>"`'
names "auto-run.md: dependents come from the plan" "$R" '`**Depends on:**` line names it, or, in a plan without those lines, a later'
names "auto-run.md: a final residual is a deferred row" "$R" '`scripts/register add <run register> "<the finding>" --state deferred --note "final review residual"`.'
names "auto-run.md: a final residual keeps the branch" "$R" 'added. `merge` also keeps the branch when the run added a deferred row whose'
names "auto-run.md: a finish stops the run with no reason" "$R" 'stop` with no `--reason` before'
names "finishing: a finish stops the run with no reason" "$FIN" 'stop` with no `--reason` before printing the next-step block'
names "final-review.md: a red gate in an auto run" "$P/reference/final-review.md" 'run ([auto-run.md](auto-run.md)), a red gate does not stop the review: the'
names "final-review.md: a second red stops the run" "$P/reference/final-review.md" '`scripts/auto-run stop --reason "gate <name> red"` and ends as auto-run.md'
GWF="$P/skills/using-git-worktrees/SKILL.md"
names "final-review.md: a manifest defect has its own reason" "$P/reference/final-review.md" 'a manifest defect does the same with the reason'
names "executing-plans: the mode switch handles next-step exits" "$EPF" 'a `next-step` exit 4 or 5 there is'
names "using-git-worktrees: never is not read" "$GWF" 'The `worktree` setting is not read: `worktree=never` creates it too'
names "using-git-worktrees: the sandbox stops the run" "$GWF" 'In an auto run, do not work in place: run `scripts/auto-run stop --reason "the sandbox refused the execution worktree"`'
names "using-git-worktrees: a red baseline is a ruling" "$GWF" 'In an auto run, ask nothing: run `scripts/auto-run ruling add "Setup: baseline tests red — <failing summary>"` and continue'
names "finish-preference.md: get reads the spec line" "$P/reference/finish-preference.md" 'the plan'"'"'s spec carries a `Finish: <merge|pr|keep>` line in `## Decisions`,'
names "session-budget.md: the last task is never a stop" "$P/reference/session-budget.md" '- **Never a stop:** the last task completing, in either mode. The final review'
names "finish-preference.md: the spec review's answer" "$P/reference/finish-preference.md" 'once the plan is attached. Finishing carries out that choice, or else'
names "README: the default" "$P/README.md" 'The default on Claude Code (`autoRun=on`). Brainstorming asks its clarifying'
names "README: the opt-outs" "$P/README.md" '`autoRun=ask` offers the run once the design is approved instead, and'
names "README: the autoRun row" "$P/README.md" '| Workflow | `autoRun` | `on` |'
names "README: the strategy row" "$P/README.md" '| Workflow | `executionStrategy` | `parallel` |'
# The rename to dforge rewrote "the forge" (the code host) as "the dforge".
check "no prose names the code host 'the dforge'" "$(grep -rlF "the dforge's" "$P/skills" "$P/reference" | tr '\n' ' ')" ""

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
