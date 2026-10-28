---
name: executing-plans
description: Use when a plan's Execution line names inline mode - the session implements every task it does not delegate, with the whole-branch final review as its gate
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
   ledger line decides; see the Recovery table under The Ledger.
3. When every task has its `complete` line, run `scripts/context-size --final`
   and go on to the final review or finishing whatever it prints: the final
   phase never hands off. In an auto run it also moves the run to the final
   phase, and a `compact` line still ends the turn on `Auto run: compacting`.
   Otherwise run `scripts/context-size`; on exit 5, finish the task in
   flight, then invoke dforge:handoff. In an auto run, exit 6 (`compact`) is
   [auto-run.md](../../reference/auto-run.md) §The budget line.
4. Re-read this skill in full before the next task. If a task's last ledger
   line is an agent-named assigned line or `fix round R/2`, also re-read
   [delegated-task.md](../../reference/delegated-task.md) before continuing.

## Auto run

When `scripts/auto-run status` exits 0, this run is unattended
([auto-run.md](../../reference/auto-run.md)); read that file once per session.
What changes here:

- **After any compaction**, whether or not a prompt asks for it (the
  cockpit's prompt does; a compaction Claude Code starts on its own comes with
  none), run `scripts/auto-run after-compact` before step 0 above. On
  `handoff` (exit 5), invoke dforge:handoff,
  then run `scripts/auto-run clear` and end as auto-run.md §Clears says.
- **Setup:** skip the finish-preference question; run `scripts/auto-run phase execute`
  from the execution worktree, once dforge:using-git-worktrees has created it.
  Exit 4 means the worktree step was skipped: create the worktree, then run
  the command again from it.
- **Nothing stops for your human partner.** A ruling-seat or exhausted
  `BLOCKED` goes on the pending list and one Fable batch runs at once. An
  irreversible, security-sensitive or outside-the-worktree action is never
  performed (the finish action is the one exception).
  A task Fable gives no ruling for, or whose action is never performed, is
  deferred, and every task that depends on it (its `**Depends on:**` line
  names the task; in a plan without those lines, its `Consumes:` line cites
  a Contracts entry the deferred task's `Produces:` line cites): write
  `Task <N>: complete (deferred by the auto run) — done: nothing; verified: not run; remaining: <the item>[; partial commits <a7>..<b7>, kept for the final review]; discovered: none; assumptions: none; Ruling: <why> — <cost if wrong>`
  and a deferred register row for each. Other tasks keep running.
- **Each task:** right after its `Task N: complete` line, run
  `scripts/auto-run task-complete`. After each task, run the Fable batch when
  `scripts/auto-run decision list` prints anything. When that line leaves every
  task with its `complete` line (in subagent mode, after the last wave's
  merge), run `scripts/auto-run phase final` next, before any budget check and
  before the turn ends, so a compaction from there on never hands off.
  A `task-complete` exit 5 means the run stopped (a task was completed in the
  primary checkout): end as auto-run.md §Stopping says.
- **The budget line** reads `budget (auto…)`. On `compact` (exit 6), finish
  the task in flight, then end the turn with
  `Auto run: compacting` as its last line. On `handoff`, finish the task in
  flight, then invoke dforge:handoff, then run `scripts/auto-run clear` and end as auto-run.md §Clears says.
  The tail rule and the final-phase limit do not apply;
  `scripts/context-size --final` prints the auto line too.
- **Final review:** run `scripts/auto-run phase final` and, when the pending
  list is not empty, the Fable batch first; the review's findings take the
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
dispatches nothing but the ruling seat, delegated tasks and the final review.

## Overview

Execute a plan yourself, task by task, with the whole-branch final review as
the gate.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Why this mode.** The plan's `**Execution:**` line chose it because at most
half the tasks are heavy (total 5 or more, or risk 3). The rest are small
changes whose text carries the code, and a subagent per task would cost more in
context rebuild than the task itself. The line's model is Sonnet, and its
effort follows the highest score among the tasks you implement, at least high
when the plan delegates.
Subagent availability has nothing to do with it - the line decides, and only
your human partner overrides it.

**Delegated tasks.** A delegated task is not yours to implement: every heavy
task, and every task carrying an `**Executor:**` line. An offloaded task is
delegated for the same reason the others are — the session does not implement
it — and it runs on its executor's wrapper rather than an implementer
subagent. Its brief's second line is
`**Dispatch:** delegated — total <t>, risk <r>`, and `plan-header.md` ends with
`**Dispatch:** delegated — Task <a> (heavy), Task <b> (executor)`. Run
[delegated-task.md](../../reference/delegated-task.md) for it: an implementer
subagent, the review seat `scripts/review-route` prints, fix rounds up to 2 and
a reviewed complete line. Read that file the first time a delegated task comes
up, not before. Delegated tasks are never batched.

**Why no per-task review of your own tasks.** The eligibility bar is the gate,
applied when the plan was written. A task too large or too risky to implement
here is delegated and reviewed; what catches the rest is the plan's own
verification steps, your self-review of each diff, and one broad review of the
whole branch at the end.

**Continuous execution.** Do not pause between tasks to check in. "Should I
continue?" prompts and progress summaries waste your human partner's time -
they asked you to execute the plan, so execute it.

**Rulings, not stalls.** Decide the mechanical problems yourself - a missing
directory, a tool failure, a plan that is silent where you need
an answer - and record each in the ledger as `Ruling: <what you decided> —
<why> — <what it costs if wrong>`, said aloud. Everything that needs judgment
about the plan, the spec or a finding goes to the ruling seat, which reads the
whole plan and the spec you never read. A wrong ruling costs rework your human
partner can see and undo; a session parked on a question costs their whole day
and buys nothing.

**Surgical execution.** Change only what the task names. Note adjacent problems
in the ledger as `Task <N>: minor (deferred): <one-liner>` instead of fixing
them.

Four things stop you, and only these: an irreversible or destructive operation;
a security-sensitive action; a side effect outside this worktree that norms say
you ask about first (a merge, a push to a shared branch, a publish); and a
ruling-seat `BLOCKED` verdict. For those, stop and ask — except in an auto run,
which asks nothing (see Auto run).

**Every session ends with the next step.** Whenever this session ends before
the plan is finished - one of those four stops, a context-budget handoff, a
switch to subagent mode, or your human partner asking you to stop - first
reconcile live children exactly as dforge:handoff step 0 says: wait
for them, or `TaskStop` them and record a Ruling. Tell your partner which you
did. Then run `scripts/next-step PLAN_FILE` (see using-dforge §Session
Budget) as your last action. The
last thing in your final message is the block it prints, verbatim. It also
rewrites the `## Next session` section of
`<latest.md>`; if it exits 4, say the handoff file could not
be written. When the plan finishes,
dforge:finishing-a-development-branch runs it instead.

## Setup

Read [setup.md](references/setup.md) before you set up the workspace, the ledger and the plan header.

## The Ledger

This skill and dforge:subagent-driven-development share one grammar, so
a plan that changes mode mid-run leaves one readable record. The lines this
mode writes:

```
# SDD ledger — plan: <path>
Task <N>: implementer inline (assigned; base <sha7>)
Task <N>: fix round R/3 (<what failed>; commits a..b; passing | still failing)
Task <N>: escalated inline -> subagent — <trigger>
Task <N>: minor (deferred): <one-liner>
Task <N>: parked — <finding> — Ruling: <why the code stands>
Task <N>: Ruling: <finding> — <what was decided and why>
Task <N>: Ruling: (unseated) <item> — <decision> — <cost if wrong>
Task <N>: Ruling: amendment A<k> — <reason> — <cost if wrong>
Ruling: amendment A<k> (Header) — <reason> — <cost if wrong>
Task <N>: BLOCKED — ruling seat — <what a human must decide>
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
- After each `complete` and `fix round` line, run `scripts/darkmem-sync push`;
  at `complete`, also promote the task's durable facts
  ([project-state.md](../../reference/project-state.md) §darkmem sync points).
- `implementer inline` is this mode's assigned line. You are the implementer,
  so the agent slot says so, and `base` is `git rev-parse --short HEAD` taken
  before you change anything.
- `unreviewed` is where subagent mode writes `review clean`. No judge scored
  this task, and saying so is what keeps the two modes' complete lines honest.
  The branch's review is the `Final review:` line.
- There is no scores clause. A scores clause appears only when a judge scored
  the task.
- The fix cap is 3 for a task you implement, not subagent mode's 5; a delegated task keeps 5. You are fixing your own work, so a
  fourth round is not a better round - it is the trigger in Switching to
  subagent mode. A fix-round line is written after the round, with its
  outcome, exactly as subagent mode writes its own: `passing` when the
  task's verifications now pass, `still failing` otherwise.
- The escalated line is the switch itself. Every trigger in Switching to
  subagent mode writes it, whether or not a fix round preceded it, and it is
  the only line `scripts/next-step` and subagent mode's recovery read as a
  switch.
- A ruling-seat `BLOCKED` that belongs to no task (a Header amendment) is
  logged against the lowest-numbered task without a complete line, so
  recovery reads it as that task's terminal line.
- The checkpoint after the `—` is yours to write, and the final review reads it
  as a claim to check rather than a finding. `done` is a one-line summary of
  the deliverable, `verified` the covering command and its result, `remaining`
  the parked findings, `discovered` the problems you found and did not fix, and
  `assumptions` what you assumed where the plan was silent.
- Write each line in the same message as your other bookkeeping, never later.
- A delegated task writes subagent mode's per-task lines instead:
  the agent-named assigned line, `fix round R/2`, `HANDBACK`, `parked`,
  dispatch `Ruling:` lines, `BLOCKED — <agent> exhausted`, and the complete line
  with `review clean` or `K parked` and its scores clause
  (dforge:subagent-driven-development §The Ledger).

Read [recovery.md](references/recovery.md) before you resume a task from its last ledger line.

## Session Budget

`scripts/task-brief` ends its output with the budget line
([session-budget.md](../../reference/session-budget.md)), so you check the
budget before every task at no extra request:

    budget: 312k of 465k (67%) — ok — source: record

- `ok` or `unknown`: carry on, however high the percentage. Only the verdict
  stops you.
- `handoff`: finish the task in flight through its `Task N: complete` line,
  then invoke dforge:handoff. Never hand off in the middle of a task,
  delegated ones included. The budget holds one task's worst growth.

The plan's last two tasks are measured against the final-phase limit: their
brief prints `budget (last 2 tasks)` or `budget (last task)`, and only that
line's verdict decides. Run `scripts/context-size --final` after the last
task's `Task <N>: complete` line for the record: it never says `handoff`.
After every earlier task, the next brief's budget line is the check.
Finishing is never budget-checked. In an auto run `--final` also moves the
run to the final phase, and a `compact` line still ends the turn on
`Auto run: compacting`.

The last task completing is never a stop: the final review, its fix wave and
finishing run in this session whatever `context-size --final` prints, and a
`review-package` budget line saying `handoff` does not stop them. If the
context fills, Claude Code's own compaction is the backstop. A switch to
subagent mode is always a handoff.

## The Task Loop

For each task, in order:

1. **Read the brief.** Run `scripts/task-brief PLAN_FILE N` and read the
   file it prints. It carries the task text with every
   amendment applied, the header's Global Constraints and Contracts, and the
   budget line. You never read task text any other way: reading the plan file
   directly skips the amendments. If the brief's second line is
   `**Dispatch:** delegated`, run
   [delegated-task.md](../../reference/delegated-task.md) for this task instead
   of steps 2 to 7, then go to step 8.
2. **Open the task.** Take the base commit (`git rev-parse --short HEAD`) and
   append `Task <N>: implementer inline (assigned; base <sha7>)`.
3. **Implement exactly what the task names.** Follow its steps in order. Where
   the task says to write a test first, use
   dforge:test-driven-development. Touch only the files and lines the
   task names; a change the task did not ask for is a deferred minor, not a
   bonus.
4. **Run the verifications as written.** A step that says `Expected: PASS` is
   not done until you have seen it pass. Run the focused test while you work
   and the full suite once before committing.
5. **Self-review your own diff** against the brief before you commit. This is
   the only per-task gate this mode has, so it is not a formality: read
   `git diff`, and check that every step is done, that nothing outside the
   named files changed, and that no test you wrote would pass against an
   unimplemented function. A test that passes with `return <constant>` is not
   a test.
6. **Commit** as the task's commit step specifies.
7. **Close the task.** Append the complete line with its checkpoint, in the
   same message as your other bookkeeping, and mark the todo complete. In an
   auto run, run `scripts/auto-run task-complete`, then the Fable batch when
   `scripts/auto-run decision list` prints anything.
8. **Check the budget after the last task.** Run
   `scripts/context-size --final`; in an auto run it moves the run to the
   final phase, and a `compact` line still ends the turn on
   `Auto run: compacting`. After any other task, go to the
   next task's step 1: its brief prints the same budget line.

**When a verification will not pass.** Fix, re-run, then append
`Task <N>: fix round R/3 (<what failed>; commits a..b; passing | still failing)`
with the round's outcome. Rounds 1 through 3 are yours. A task still failing
after `3/3` goes to Switching to subagent mode - not to a fourth round, and
not to a complete line.

**When the plan is silent** - it does not say which of two reasonable things to
do - rule, log it, and carry on.

**When the plan is wrong** - its steps contradict each other, the output it
expects cannot be produced, a name it mandates does not exist - send a
`blocked-plan` item to the ruling seat. Improvising here is the one failure
this mode cannot review its way out of, because the final review reads the
branch against the spec, not against what you meant.

## The Ruling Seat

Read [ruling-seat.md](references/ruling-seat.md) before you send the ruling seat an item or carry out its verdict.

## Switching to subagent mode

Read [switching.md](references/switching.md) before you leave inline mode for subagent mode.

## Final Review

Every task is complete, so the branch gets one broad review: follow
[final-review.md](../../reference/final-review.md), the procedure both
execution skills share; its reviewer is the seat
`scripts/review-route PLAN_FILE --final` prints, and its fix wave is your own
pass. In this mode it runs in this session: the final phase never hands off.
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

Read [finish-rulings.md](references/finish-rulings.md) before you invoke finishing.

## Common Rationalizations

Read [rationalizations.md](references/rationalizations.md) before you skip a step of the task loop.
