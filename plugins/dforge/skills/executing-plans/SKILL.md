---
name: executing-plans
description: Use when a plan's Execution line names inline mode - the session implements every task, with the whole-branch final review as its gate
---

# Executing Plans

## After compaction

If this session was compacted - a compaction snapshot or summary sits above -
your memory of the run is gone, and only the start of this file may have come
back. Before anything else:

0. In an auto run, when `scripts/auto-run status` says setup is due, or when
   no ledger names this plan, no task has started: skip the rest of this
   section and follow Setup from its first step.
1. Run `scripts/sdd-workspace PLAN_FILE` (see using-dforge §Session Budget),
   and read `progress.md` and `handoff.md` in `<ledger dir>`, not in the
   directory it prints: while progress lives in darkmem the two differ.
2. Trust the ledger and `git log` over the summary. For each task the last
   ledger line decides; see the Recovery table in [recovery.md](references/recovery.md).
3. When every task has its `complete` line, run `scripts/context-size --final`
   and go on to the final review or finishing unless it says `handoff` (the
   hard limit). In an auto run it also moves the run to the final
   phase, and a `compact` line still ends the turn on `Auto run: compacting`.
   Otherwise run `scripts/context-size`; on exit 5, finish the task in
   flight, then invoke dforge:handoff. In an auto run, exit 6 (`compact`) is
   [auto-run.md](../../reference/auto-run.md) §The budget line.
4. Re-read this skill in full before the next task, and re-read
   `<workspace>/plan-header.md`: a brief for a task you implement points at it
   instead of repeating the Global Constraints and Contracts. If a task's last
   ledger line is `fix round R/2`, also re-read
   [delegated-task.md](../../reference/delegated-task.md) before continuing.

## Auto run

When `scripts/auto-run status` exits 0, this run is unattended
([auto-run.md](../../reference/auto-run.md)); read that file once per session.
What changes here:

- **After any compaction**, whether or not a prompt asks for it, run `scripts/auto-run after-compact` before step 0 above. On
  `handoff` (exit 5), invoke dforge:handoff,
  then run `scripts/auto-run clear` and end as auto-run.md §Clears says.
- **Setup:** skip the finish-preference question; run `scripts/auto-run phase execute`
  from the execution workspace once dforge:using-git-worktrees Step 0 has prepared it.
  Exit 4 means the workspace step was skipped:
  follow dforge:using-git-worktrees Step 0 for the run, then run the command again.
- **Nothing stops for your human partner.** A ruling-seat or exhausted
  `BLOCKED` goes on the pending list and one Fable batch runs at once. An
  irreversible, security-sensitive or outside-the-worktree action is never
  performed (the finish action and the consented Early CI push and dispatch
  are the exceptions).
  A task Fable gives no ruling for, or whose action is never performed, is
  deferred, and every task that depends on it (its `**Depends on:**` line
  names the task; in a plan without those lines, its `Consumes:` line cites
  a Contracts entry the deferred task's `Produces:` line cites): write
  the `Task <N>: complete (deferred by the auto run)` line auto-run.md §Rulings
  gives, and a deferred register row for each. Other tasks keep running.
- **Each task:** `scripts/task-close` runs `scripts/auto-run task-complete`
  for you right after it writes the `Task N: complete` line, prints the
  decisions waiting, and ends on the run's budget line: on `compact`, end the
  turn on `Auto run: compacting` before the next task opens. After each task, run the Fable batch when it printed any
  (`scripts/auto-run decision list` shows the same). When that line leaves every
  task with its `complete` line, run `scripts/auto-run phase final` next, before any budget check and
  before the turn ends: a compaction there never hands off; three without progress stop the run.
  A `task-close` exit 5 means the run stopped (a task was completed
  on the run base, off its branch or in the primary checkout, or a carried path was committed):
  end as auto-run.md §Stopping says.
- **The budget line** reads `budget (auto…)`. On `compact` (exit 6), finish
  the task in flight, then end the turn with
  `Auto run: compacting` as its last line. On `handoff`, finish the task in
  flight, then invoke dforge:handoff, then run `scripts/auto-run clear` and end as auto-run.md §Clears says.
  The tail rule and the final-phase limit do not apply;
  `scripts/context-size --final` prints the auto line too.
- **Final review:** run `scripts/auto-run phase final`; on exit 4 (here or after the last task),
  run `scripts/auto-run stop --reason "<path> is a carried path and was committed"` (no path: `--reason "git could not check the carried paths"`) and end as auto-run.md §Stopping says. On exit 7, run it again with the `cd` prefix it printed: never a stop. With pending items,
  run the Fable batch first; the review's findings take the
  same ladder.
- **A turn ends** only on `Auto run: compacting` or `Auto run: clearing` as
  its last line, or after `scripts/auto-run stop --reason "<why>"` when the
  run must stop.

## Select the host first

On Codex, the ruling seat is a native judge at Astra high or above
([native-codex.md](../../reference/native-codex.md)), and the budget line
carries a measured number but no verdict: hand off after every 3 completed
tasks, or after any task that needed 3 or more fix rounds. Everything else
here is host-neutral - inline mode
dispatches nothing but the ruling seat, risk-3 task reviews and the final
review.

## Lookups

Put independent lookups in one turn (parallel tool calls, or one Bash call
with several patterns) and read line ranges, not whole files. With darkmem
tools listed, try `code_search` and `code_context` before grep chains.

## Overview

Execute a plan yourself, task by task, with the whole-branch final review as
the gate.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Why this mode.** Every plan runs inline: the session reads each task's files through
its brief and keeps them, where a subagent per task would rebuild them; an auto
run starts in a cleared session.
A task that still carries an
`**Executor:**` line is implemented here too: `plan-lint` warns that the line
is obsolete. The `**Execution:**` line's model and effort cover the hardest
task, at least high effort when a task has risk 3.
Subagent availability has nothing to do with it - the line decides, and only
your human partner overrides it.

**Risk-3 tasks.** A brief whose second line is `**Review:** per-task — risk 3`
is yours to implement, and a judge reviews it before its complete line: run
[delegated-task.md](../../reference/delegated-task.md) §The session review
loop for it. On a Codex host, which writes no such line, the trigger is an
`**Evaluation:**` line reading `risk=3`.

**Why no per-task review of your own tasks.** Risk 3 is the exception. The rest
is caught by the plan's verification steps, your self-review of each diff and
one broad review of the branch at the end.

**Continuous execution.** Do not pause between tasks to check in or summarize
progress: you were asked to execute the plan.

Read [ruling-seat.md](references/ruling-seat.md) for when to rule on a mechanical problem yourself.

**Surgical execution.** Change only what the task names. Note adjacent problems
in the ledger as `Task <N>: minor (deferred): <one-liner>` instead of fixing
them.

Four things stop you, and only these: an irreversible or destructive operation;
a security-sensitive action; a side effect outside the execution workspace that norms say
you ask about first (a merge, a push to a shared branch, a publish); and a
ruling-seat `BLOCKED` verdict. For those, stop and ask — except in an auto run,
which asks nothing (see Auto run). Asking does not end the session: run
`scripts/ask PLAN_FILE N "<question>"`, end on the question with no next-step
block, and continue once your partner answers.

**Every session ends with the next step.** Whenever this session ends before
the plan is finished - a context-budget handoff, or your human partner asking
you to stop - first
reconcile live children exactly as dforge:handoff step 0 says: wait
for them, or `TaskStop` them and record a Ruling. Tell your partner which you
did. Then run `scripts/next-step PLAN_FILE` (see using-dforge §Session
Budget) as your last action. The
last thing in your final message is the block it prints, verbatim. It also
rewrites that block in the plan's `<handoff>` in the next session's checkout; on
exit 4, say it could not be written. When the plan finishes,
dforge:finishing-a-development-branch runs it instead.

## Setup

Read [setup.md](references/setup.md) before you set up the workspace, the ledger and the plan header.

## The Ledger

The lines this skill writes:

```
# SDD ledger — plan: <path>
Task <N>: implementer inline (assigned; base <sha7>)
Task <N>: fix round R/3 (<what failed>; commits a..b; passing | still failing)
Task <N>: minor (deferred): <one-liner>
Task <N>: parked — <finding> — Ruling: <why the code stands>
Task <N>: Ruling: <finding> — <what was decided and why>
Task <N>: Ruling: (unseated) <item> — <decision> — <cost if wrong>
Task <N>: Ruling: amendment A<k> — <reason> — <cost if wrong>
Ruling: amendment A<k> (Header) — <reason> — <cost if wrong>
Task <N>: BLOCKED — ruling seat — <what a human must decide>
Task <N>: waiting — <question> (written by scripts/ask)
Task <N>: complete (commits a..b, unreviewed | K parked) — done: …; verified: <command → result>; remaining: none | <parked>; discovered: none | …; assumptions: none | …
Ruling: <what> — <why> — <cost if wrong>
Review depth: <light|standard|full> (<reason>)
Acceptance QA: dispatched (base <sha7>)
Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo
Acceptance QA: skipped (depth light)
Final review: clean (commits <merge-base7>..<head7>[, K parked])
```

- `Acceptance QA:` lines are written by
  [final-review.md](../../reference/final-review.md) step 0.5. On recovery:
  a `complete` line skips step 0.5; a `dispatched` line with no `complete`
  line and `<workspace>/acceptance-report.md` present means read the report
  and write `complete`; with no report, re-dispatch QA once with `[MODE]`
  `rerun`. Step 0.5 holds the rest of the procedure.
- `Acceptance QA: skipped (depth light)` counts as `complete` on recovery.
  `Review depth: <light|standard|full> (<reason>)` is written once, before
  step 0 of the final review, and is read on recovery, never recomputed; it is
  not a `Final review:` line, which recovery keys on.
- With `darkmemEnabled` true, after each `fix round` line, run
  `scripts/darkmem-sync push`, and at `complete` promote the task's durable
  facts ([project-state.md](../../reference/project-state.md) §darkmem sync points).
  With it false, run neither.
- `implementer inline` is this mode's assigned line. You are the implementer,
  so the agent slot says so, and `base` is `git rev-parse --short HEAD` taken
  before you change anything. `task-brief --open` writes it, once per task;
  `task-close` writes the `complete` line from that base to `HEAD`.
- `unreviewed` says no judge scored this task. The branch's review is the
  `Final review:` line.
- There is no scores clause. A scores clause appears only when a judge scored
  the task.
- The fix cap is 3 for a task you implement; a risk-3 task's reviewed loop keeps 2 (5 on a `Host: codex` plan). You are fixing your own work, so a
  fourth round is not a better round. A fix-round line is written after the
  round, with its outcome: `passing`
  when the task's verifications now pass, `still failing` otherwise.
  After `fix round 3/3`, the task goes to the ruling seat as a `breaker` item.
  In an auto run it goes on the pending list.
- An older ledger may hold a `Task <N>: escalated inline -> subagent` line from
  the retired subagent mode; recovery.md says how to read it.
- A ruling-seat `BLOCKED` that belongs to no task (a Header amendment) is
  logged against the lowest-numbered task without a complete line, so
  recovery reads it as that task's terminal line.
- The checkpoint after the `—` is yours to write, and the final review reads it
  as a claim to check rather than a finding. `done` is a one-line summary of
  the deliverable, `verified` the covering command and its result, `remaining`
  the parked findings, `discovered` the problems you found and did not fix, and
  `assumptions` what you assumed where the plan was silent.
- Write each line in the same message as your other bookkeeping, never later.
- A risk-3 task writes `fix round R/2` lines ending `; session)` and a
  reviewed complete line (delegated-task.md §The session review loop).

Read [recovery.md](references/recovery.md) before you resume a task from its last ledger line.

## Session Budget

`scripts/task-brief` ends its output with the budget line
([session-budget.md](../../reference/session-budget.md)), so you check the
budget before every task at no extra request:

    budget: 312k of 465k (67%) — ok — source: record

- `ok` or `unknown`: carry on, however high the percentage.
- `handoff`: finish the task in flight through its `Task N: complete` line,
  then invoke dforge:handoff. Never hand off in the middle of a task.

In strict mode the plan's last two tasks and its final phase hand off only at
the hard limit: `budget (last 2 tasks)`, `budget (last task)` and
`budget (final)` lines say `ok` past the budget below it. After the last
task's `Task <N>: complete` line, `task-close` prints the `--final` budget line
(run `scripts/context-size --final` yourself if it did not).
After every earlier task, the next brief's budget line is the check.

The last task completing is no stop while that line says `ok`: the final
review, its fix wave and finishing run in this session; a
`review-package` budget line saying `handoff` does not stop them. On
`handoff` from `--final`, finish the step in hand, then invoke
dforge:handoff: the next session resumes the final phase from the ledger.

## The Task Loop

For each task, in order:

1. **Open the task.** Run `scripts/task-brief --open PLAN_FILE N` and read the
   brief it prints. One call writes the brief (the task text with every
   amendment applied), rewrites `<workspace>/plan-header.md`, appends
   `Task <N>: implementer inline (assigned; base <sha7>)` once, and prints
   the `task check:` line and the budget line. A brief for a task you
   implement points at `plan-header.md` for the Global Constraints and
   Contracts: read that file the first time in a session and again after a
   compaction, not before every task. You never read task text any other way:
   reading the plan file directly skips the amendments. If the brief's second
   line is `**Review:** per-task — risk 3`, run
   [delegated-task.md](../../reference/delegated-task.md) §The session review
   loop instead of steps 2 to 6, then go to step 7.
2. **Take the base from the open line.** The `base` on that ledger line is the
   commit the task's range starts from; do not take another.
3. **Implement exactly what the task names.** Follow its steps in order. Where
   the task says to write a test first, use
   dforge:test-driven-development. Touch only the files and lines the
   task names; a change the task did not ask for is a deferred minor, not a
   bonus.
4. **Run the verifications as written.** A step that says `Expected: PASS` is
   not done until you have seen it pass. Run the focused test while you work
   and the task check once before committing, in place of the full suite.
   The task check is the `task check:` line `--open` printed (the plan
   header's `**Task check:**` line). With a task check of `none`, the line
   says whether the integration check is due: every task numbered a multiple
   of 3 and the last. A plan with no `**Task check:**` line keeps the full
   suite once before committing.
5. **Self-review your own diff** against the brief before you commit. This is
   the only per-task gate this mode has, so it is not a formality: read
   `git diff`, and check that every step is done, that nothing outside the
   named files changed, and that no test you wrote would pass against an
   unimplemented function. A test that passes with `return <constant>` is not
   a test.
6. **Commit** as the task's commit step specifies.
7. **Close the task.** Run
   `scripts/task-close PLAN_FILE N '<checkpoint>'` in the same message as your
   other bookkeeping, and mark the todo complete. The checkpoint is the text
   after the dash on the complete line, with its five fields (`done:`,
   `verified:`, `remaining:`, `discovered:`, `assumptions:`); a risk-3 task
   adds `--review '<review clean; scores …>'`, in place of `unreviewed`. It
   writes the `Task <N>: complete (commits <base>..<head>, …)` line, pushes
   the ledger to darkmem when that is on, and in an auto run records the
   completion and lists the decisions waiting, which you take to the Fable
   batch. When its output says `early CI: due after this task`, run
   [delegated-task.md](../../reference/delegated-task.md) §Early CI.
8. **Check the budget after the last task.** After the last task
   `task-close` prints the `--final` budget line itself (in an auto run it
   moves the run to the final phase, and a `compact` line still ends the turn
   on `Auto run: compacting`); run `scripts/context-size --final` only when it
   did not. After any other task, go to the next task's step 1: its brief
   prints the budget line.

**When a verification will not pass.** Fix, re-run, then append the
`fix round R/3` line with the round's outcome; §The Ledger gives the cap and
the `breaker` item after `3/3`, never a complete line.

**When the plan is silent** - it does not say which of two reasonable things to
do - rule, log it, and carry on.

**When the plan is wrong** - its steps contradict each other, the output it
expects cannot be produced, a name it mandates does not exist - send a
`blocked-plan` item to the ruling seat. Improvising here is the one failure
this mode cannot review its way out of, because the final review reads the
branch against the spec, not against what you meant.

## The Ruling Seat

Read [ruling-seat.md](references/ruling-seat.md) before you send the ruling seat an item or carry out its verdict.

## Final Review

Every task is complete, so the branch gets one broad review: follow
[final-review.md](../../reference/final-review.md), the procedure both
execution skills share; its reviewer is the seat
`scripts/review-route PLAN_FILE --final` prints, and its fix wave is your own
pass. In this mode it runs in this session.
List any
`(unseated)` rulings for the reviewer alongside the ledger's parked and
deferred-minor lines.

## Finish

When the final review is clean and its fixes are committed, append
`Final review: clean (commits <merge-base7>..<head7>[, K parked])` to the
ledger. Do not delete the workspace:
dforge:finishing-a-development-branch removes it with the worktree once
the work is merged or discarded, and until then it is what a later session
resumes from.

**Finishing is a Skill tool call in this same turn.** Call the Skill tool
with `dforge:finishing-a-development-branch` right after the ledger
line. Writing its name in a message is not invoking it, and a turn that ends
on a summary of the run leaves your human partner with no integration menu
and no next step. Write no wrap-up message of your own: finishing's message is
the final one.
