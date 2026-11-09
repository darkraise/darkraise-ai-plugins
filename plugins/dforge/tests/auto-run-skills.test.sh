#!/usr/bin/env bash
# Both execution skills carry the auto run where a plan run would otherwise
# stop for its human: each check is a whole instruction, not a keyword.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID DFORGE_BUDGET CLAUDE_PROJECT_DIR
SKILL_VIEW_DIR=$(mktemp -d)
trap 'rm -rf "$SKILL_VIEW_DIR"' EXIT
. "$HERE/skill-view.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" "yes"
}
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
says() { # says <label> <file> <text> — the text, with line breaks folded
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "yes"
}

for skill in subagent-driven-development executing-plans; do
  F="$P/skills/$skill/SKILL.md"
  names "$skill: the section" "$F" '## Auto run'
  names "$skill: after a compaction" "$F" '`scripts/auto-run after-compact` before step 0 above'
  names "$skill: setup asks nothing, from the worktree" "$F" 'from the execution workspace'
  names "$skill: exit 4 is a skipped workspace step" "$F" 'Exit 4 means the workspace step was skipped:'
  names "$skill: no ledger goes to Setup" "$F" 'no ledger names this plan, no task has started: skip the rest of this'
  names "$skill: setup due goes to Setup" "$F" '0. In an auto run, when `scripts/auto-run status` says setup is due, or when'
  names "$skill: a task-complete stop" "$F" 'A `task-complete` exit 5 means the run stopped (a task was completed'
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
  says "$skill: the finish and the consented early CI are the outside actions" "$F" '(the finish action and the consented Early CI push and dispatch are the exceptions)'
  names "$skill: final review" "$F" 'run `scripts/auto-run phase final`'
  names "$skill: the four stops give way" "$F" 'except in an auto run'
done
names "subagent-driven-development: a deferred task is not merged" "$P/skills/subagent-driven-development/SKILL.md" "a deferred task's branch is"
EPF="$(skill_view executing-plans)"
names "executing-plans: step 7 runs task-complete" "$EPF" 'auto run, run `scripts/auto-run task-complete`, then the Fable batch when'
names "executing-plans: step 8 moves to the final phase" "$EPF" '`scripts/context-size --final`; in an auto run it moves the run to the'
names "executing-plans: the budget section says so too" "$EPF" 'Finishing is never budget-checked. In an auto run `--final` also moves the'
names "subagent-driven-development: the budget section says so" "$P/skills/subagent-driven-development/references/budget.md" 'from the ledger. In an auto run `--final` also moves the run to the final'
names "executing-plans: a task at its cap goes on the pending list" "$EPF" 'In an auto run it goes on the pending list, as an exhausted ladder does.'
names "executing-plans: recovery sends an old switch to subagent mode" "$EPF" '| `escalated inline -> subagent` | This plan has left inline mode: use dforge:subagent-driven-development |'
names "delegated-task.md: task-complete after the complete line" "$P/reference/delegated-task.md" 'In an auto run, run `scripts/auto-run task-complete`, then the Fable batch when'
names "parallel-waves.md: task-complete after the merge" "$P/reference/parallel-waves.md" '`; merged <sha7>`. In an auto run, run `scripts/auto-run task-complete`'
names "parallel-waves.md: before any budget check" "$P/reference/parallel-waves.md" 'right after it, before any budget check or dispatch; the Fable batch runs'
check "handoff: no mode switch clears by phase" "$(grep -c 'clear --phase' "$P/skills/handoff/SKILL.md")" "0"

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
FIN="$(skill_view finishing-a-development-branch)"
names "finishing: unverified acceptance keeps the branch" "$FIN" '`merge` also keeps when the `Acceptance QA: complete` line reports a nonzero count of'
names "finishing: an untested statement keeps the branch" "$FIN" '`cannot-test`, or when the run added a deferred register'
names "finishing: fail and flaky counts are not read" "$FIN" 'The line'"'"'s `fail` and `flaky` counts are not read: they are taken before'
for f in "$R" "$FIN"; do
  check "$(basename "$f"): a fixed QA failure does not keep the branch" \
    "$(grep -qF -- 'nonzero count of' "$f" && grep -A1 -F -- 'nonzero count of' "$f" | grep -qF -- '`fail`, `flaky` or' && echo yes || echo no)" "no"
done
names "finishing: a deferred statement or unresolved Blocker keeps the branch" "$FIN" 'row whose Item begins `A<n>:` or whose Note is `critic Blocker unresolved`.'
names "finishing: the final message lists demos and lenses" "$FIN" 'every `demo` statement of the spec, every lens'
names "finishing: every lens-skipped line is read, whatever its reason" "$FIN" 'a `final review lens-skipped <id> reason=<reason>` ledger line names,'
check "finishing: no lens-skipped line is read for reason=cap alone" "$(grep -c 'lens-skipped <id> reason=cap' "$FIN")" "0"
names "finishing: light lists the unverified test statements" "$FIN" 'every `A<n>` statement tagged `test` under `not verified (depth light)`'
names "finishing: Step 3 lists them before the menu" "$FIN" '**Unverified at light depth.** When the ledger holds a `Review depth: light`'
names "finishing: a skipped QA line carries no counts" "$FIN" 'An `Acceptance QA: skipped (depth light)` line carries no counts, so the'

# The default flow (docs/superpowers/specs/2026-10-18-auto-execution-default-design.md).
names "auto-run.md: the default" "$R" 'The default on Claude Code (`autoRun=on`): once your human partner approves the'
names "auto-run.md: the switch section" "$R" '## The switch'
names "auto-run.md: the switching line" "$R" '- `Auto run: switching` after `scripts/auto-run switch` exits 0.'
names "auto-run.md: plan saved is no clear" "$R" 'Plan saved is no clear: the session switches in place (§The switch).'
names "auto-run.md: finishing reads the recorded choice" "$R" 'the choice `scripts/finish-choice get --plan PLAN_FILE` prints, which the spec'
names "auto-run.md: a spec-review deferral keeps a merge" "$R" 'deferred at the spec review, before the run started, counts as one the run'
check "auto-run.md: the one phase clear is for an old switch" "$(grep -c 'clear --phase' "$R")" "1"
names "auto-run.md: an old switch clears by phase" "$R" '- **A plan that left inline mode before this change** (a ledger dforge:executing-plans'
names "auto-run.md: the switch starts at Setup" "$R" 'execution skill starts at its Setup, workspace first: `scripts/auto-run status`'
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
check "executing-plans: no mode switch clears by phase" "$(grep -c 'clear --phase' "$EPF")" "0"
names "using-git-worktrees: an auto run reads its state" "$GWF" 'read the auto-run state (`scripts/auto-run status`), not the `worktree` setting'
names "using-git-worktrees: the sandbox stops the run" "$GWF" 'In an auto run under `isolation worktree`, do not work in place: run `scripts/auto-run stop --reason "the sandbox refused the execution worktree"`'
names "using-git-worktrees: a red baseline is a ruling" "$GWF" 'In an auto run, ask nothing: run `scripts/auto-run ruling add "Setup: baseline tests red — <failing summary>"` and continue'
names "finish-preference.md: get reads the spec line" "$P/reference/finish-preference.md" 'the plan'"'"'s spec carries a `Finish: <merge|pr|keep>` line in `## Decisions`,'
names "session-budget.md: the last task is never a stop" "$P/reference/session-budget.md" '- **Never a stop:** the last task completing, in either mode. The final review'
names "finish-preference.md: the spec review's answer" "$P/reference/finish-preference.md" 'once the plan is attached. Finishing carries out that choice, or else'
names "README: the default" "$P/README.md" 'The default on Claude Code (`autoRun=on`). Brainstorming asks its clarifying'
names "README: the opt-outs" "$P/README.md" '`autoRun=ask` offers the run once the design is approved instead, and'
names "README: the autoRun row" "$P/README.md" '| Workflow | `autoRun` | `on` |'
names "README: the strategy row" "$P/README.md" '| Workflow | `executionStrategy` | `sequential` |'
# The rename to dforge rewrote "the forge" (the code host) as "the dforge".
check "no prose names the code host 'the dforge'" "$(grep -rlF "the dforge's" "$P/skills" "$P/reference" | tr '\n' ' ')" ""

# Early CI: the controller step, the ledger grammar and the auto-run exception
# (docs/dforge/specs/2026-10-31-test-tiers-and-ci-parity-design.md, part 5).
D="$P/reference/delegated-task.md"
SDDF="$P/skills/subagent-driven-development/SKILL.md"
LEDGER_MD="$P/skills/subagent-driven-development/references/ledger.md"
says "auto-run.md: the early CI push and dispatch are the second exception" "$R" 'The finish action is the first exception. The second is the `**Early CI:**` push and workflow dispatch, performed only when the header line carries `— consented <YYYY-MM-DD>`.'
names "delegated-task.md: the Early CI section" "$D" '## Early CI'
says "delegated-task.md: without the line nothing pushes" "$D" 'With no `**Early CI:**` line in the plan header, nothing in this loop pushes the branch or starts CI before finishing.'
says "delegated-task.md: consent gates the push" "$D" 'Push only when the line carries `— consented <YYYY-MM-DD>`.'
says "delegated-task.md: the task point" "$D" 'For `after task <n>`, run these steps right after the `Task <n>: complete` line.'
says "delegated-task.md: the wave point" "$D" 'For `after wave <k>`, run them right after the `Wave <k>: integrated` or `Wave <k>: merged` line.'
says "delegated-task.md: the push" "$D" 'Push the branch with `git push -u origin <branch>`.'
says "delegated-task.md: only a feature branch is pushed" "$D" 'push nothing and write `Early CI: skipped — <branch> is not a feature branch`.'
says "delegated-task.md: dispatch only with workflow_dispatch" "$D" 'Start CI with `gh workflow run <workflow> --ref <branch>` only when the workflow file declares `workflow_dispatch`; otherwise print one line saying so and skip the early run.'
says "delegated-task.md: the workflow is the first dispatchable one" "$D" '`<workflow>` is the first workflow file the plan'"'"'s `**CI:**` line names that declares `workflow_dispatch`.'
says "delegated-task.md: never a pull request" "$D" 'Never open a pull request to start CI.'
says "delegated-task.md: run discovery" "$D" 'Find the run with `gh run list --workflow <file> --branch <branch> --limit 1 --json databaseId,headSha`, retrying for up to 60 seconds until `headSha` is the pushed commit.'
says "delegated-task.md: the dispatched line" "$D" 'Write `Early CI: dispatched run <id> at <sha7>` once the run is found.'
says "delegated-task.md: the background watch" "$D" 'Run `gh run watch <id>` as a background Bash command, with the call'"'"'s `timeout` set to (90 × 60 + 120) × 1000 ms, and keep working.'
says "delegated-task.md: the outcome lines" "$D" 'When the watch ends, read `gh run view <id> --json conclusion,jobs` and write `Early CI: green run <id>`, or `Early CI: red run <id> — <job>/<step>[, <job>/<step> ...]` naming each failed job and its failed step.'
says "delegated-task.md: every watch outcome writes a line" "$D" 'writes `Early CI: skipped — run <id> still running at 90 min`.'
says "delegated-task.md: a git or gh failure is a skip" "$D" 'Any failure of `git push` or `gh` prints one line, writes `Early CI: skipped — <reason>`, and never stops the run.'
says "delegated-task.md: a red run is a fix bullet" "$D" 'A red run is a bullet you write into the next task'"'"'s fix file, as §4 does for a mechanical check'"'"'s finding.'
says "delegated-task.md: a red run with no task left" "$D" 'With no task left, a red run is a final-review finding, debugged with dforge:systematic-debugging.'
says "delegated-task.md: recovery" "$D" 'On recovery, a `dispatched` line with no `green`, `red` or `skipped` line after it gets `gh run view <id> --json status,conclusion` once, and a new background watch when the run is still going.'
for line in 'Early CI: dispatched run <id> at <sha7>' 'Early CI: green run <id>' 'Early CI: red run <id> — <job>/<step>[, <job>/<step> ...]' 'Early CI: skipped — <reason>' 'CI: <sha7> run <id> <green|red|still running at 90 min>'; do
  names "ledger.md: the grammar holds $line" "$LEDGER_MD" "$line"
done
RECOVERY_MD="$P/skills/executing-plans/references/recovery.md"
says "ledger.md: an unfinished early CI run is resumed first" "$LEDGER_MD" 'Whatever the task lines say, a ledger that holds an `Early CI: dispatched run <id> at <sha7>` line with no later `Early CI: green run <id>`, `Early CI: red run <id>` or `Early CI: skipped — run <id>` line for that run is resumed first, by applying [delegated-task.md](../../../reference/delegated-task.md) §Early CI'"'"'s recovery sentence;'
says "recovery.md: an unfinished early CI run is resumed first" "$RECOVERY_MD" 'Whatever the task lines say, a ledger that holds an `Early CI: dispatched run <id> at <sha7>` line with no later `Early CI: green run <id>`, `Early CI: red run <id>` or `Early CI: skipped — run <id>` line for that run is resumed first, by applying [delegated-task.md](../../../reference/delegated-task.md) §Early CI'"'"'s recovery sentence;'
says "subagent-driven-development: Early CI runs at the point the line names" "$SDDF" 'When the plan header has an `**Early CI:**` line, run [delegated-task.md](../../reference/delegated-task.md) §Early CI at the point the line names.'
says "executing-plans: step 7 runs Early CI" "$EPF" 'run [delegated-task.md](../../reference/delegated-task.md) §Early CI when the header'"'"'s `**Early CI:**` line names this task.'
# With no Early CI line no step may push or start CI, so these commands appear
# nowhere in the controller text outside the Early CI section.
outside() { awk '/^## / { skip = ($0 == "## Early CI") } !skip' "$1"; }
check "delegated-task.md: no step outside Early CI pushes the branch or starts CI" "$(outside "$D" | grep -cE 'git push|gh workflow run|gh run ')" "0"
check "subagent-driven-development: nothing in the skill pushes the branch or starts CI" "$(grep -cE 'git push|gh workflow run|gh run ' "$SDDF")" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
