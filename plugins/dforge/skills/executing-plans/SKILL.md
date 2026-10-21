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
   flight, then invoke dforge:handoff.
4. Re-read this skill in full before the next task. If a task's last ledger
   line is an agent-named assigned line or `fix round R/5`, also re-read
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
subagent, the review seat `scripts/review-route` prints, fix rounds up to 5 and
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

Ensure the work happens in an isolated workspace: use
dforge:using-git-worktrees to create one or verify the existing one.
Never start implementation on a main/master branch without your human partner's
explicit consent.

**Ask the finish preference first.** Before this run writes anything to its
ledger, follow [finish-preference.md](../../reference/finish-preference.md):
ask what finishing should do once the final review is clean, record the
answer, and start work in the same turn. Skip it when
`scripts/finish-choice get --plan PLAN_FILE` already prints a choice (it does
so unasked when the `finishAction` setting names an action), or when this
plan's ledger already exists: a resumed run does not stop to ask. When
the spec's `## Decisions` holds a `Finish: <action>` line, run
`scripts/finish-choice set <action> --plan PLAN_FILE` instead of asking. It is
the run's one question; nothing else waits on your human partner.

Conversation memory does not survive compaction. Track progress in a ledger
file, not only in todos.

- Each plan owns a workspace: run `scripts/sdd-workspace PLAN_FILE`
  (see using-dforge §Session Budget), and it prints the plan's git-ignored directory
  (`<repo-root>/<state>/sdd/<plan-basename>/`), home to every artifact for
  THIS plan except its ledger and handoff note, which live in `<ledger dir>`.
  Another plan's directory is never yours to read or write.
- This plan's ledger is `<ledger dir>/progress.md`. If its first line names your
  plan file, recover each task's state with the Recovery table under The
  Ledger. A ledger whose first line names a different plan - or a stray ledger
  at the old flat path `<state>/sdd/progress.md` - is another plan's
  progress: leave it in place and start your own, fresh.
- Create the ledger with its identity as the first line:
  `# SDD ledger — plan: <plan name>` — `bash <plugin-root>/scripts/dforge-path name PLAN_FILE`,
  so the ledger names the plan in either store.
- When a register covers this plan's spec, mark the rows this plan carries as
  in flight once, at the start of the run, skipping any row already at `verify`
  or `done`: `scripts/register set <register> <id> doing`. The register is read by
  `next-step`, `repo-audit` and dforge:project-status, so a run that
  never says it started reads as unscheduled work everywhere else.
- Create `<ledger dir>/handoff.md` from the template in dforge:handoff
  if it does not exist. Update it in the same message as a ledger write
  whenever an owner constraint, gotcha, prohibition or open question changes.
- Read `<docs>/distilled/constraints.md` when the project has one. Its
  entries bind like the owner constraints in `handoff.md` and yield to them
  wherever both speak; an absent file is not an error. See
  [project-state.md](../../reference/project-state.md).
- `git clean -fdx` will destroy the workspace (it is git-ignored scratch); if
  that happens, recover from `git log`.

Read the plan's header, never the whole plan: run
`scripts/task-brief --header PLAN_FILE` (see using-dforge §Session Budget), and read the
file it prints (`<workspace>/plan-header.md`). Note the Execution line, the
Global Constraints and the Contracts, and create a todo per Task index entry. A
plan written before 1.4.0 may have no Task index: then run
`scripts/task-brief PLAN_FILE N` for N = 1, 2, … until it exits 3, and take
each task's title from its brief's first line. You never read the spec: the
ruling seat and the final review do. If the plan's `**Spec:**` path is
unreachable, note it in the ledger and say so in every ruling-seat dispatch;
the seat marks its rulings provisional.

**Check the Execution line.** It must name `inline`.

- It names `subagent`: log `Ruling: routed to subagent mode — the plan's
  Execution line names it — none` and use
  dforge:subagent-driven-development instead.
- The plan has no Execution line, because it was written before 1.4.0: log
  `Ruling: inline by invocation — plan predates the Execution line — if wrong,
  the run escalates at the first task that will not converge` and continue.

A `**Parallelism:** waves` line is read only by subagent mode. When your human
partner has put a waves plan in this mode, run its tasks in index order and
ignore the waves: a waves plan's index order is always a correct sequential
order ([parallel-waves.md](../../reference/parallel-waves.md)).

Never re-score the tasks. `scripts/plan-lint` enforced the eligibility rule
when the plan was saved, and a plan whose Execution line says `inline` has
passed it.

A task whose brief's second line marks it delegated is dispatched, never
implemented here, and its `**Executor:**` line is read by
[delegated-task.md](../../reference/delegated-task.md) §1, which runs that
executor's wrapper in place of an implementer subagent. `**Implementer:**` lines are inert for the tasks
you implement.

**Preflight.** When `plan-header.md` ends with a `**Dispatch:** delegated`
line naming at least one `(heavy)` task, send one `preflight` item to the
ruling seat before Task 1 and carry out its verdicts. A plan with no heavy task
has no pre-flight scan, even when it offloads tasks: it is one
whole-plan judge dispatch, and a plan of small tasks is low-coupling by
construction. A plan defect that surfaces while you work goes to the seat as a
`blocked-plan` item.

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
Acceptance QA: dispatched (base <sha7>)
Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo
Final review: clean (commits <merge-base7>..<head7>[, K parked])
```

- `Acceptance QA:` lines are written by
  [final-review.md](../../reference/final-review.md) step 0.5. On recovery:
  a `complete` line skips step 0.5; a `dispatched` line with no `complete`
  line and `<workspace>/acceptance-report.md` present means read the report
  and write `complete`; with no report, re-dispatch QA once with `[MODE]`
  `rerun`. Step 0.5 holds the rest of the procedure.
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
  the agent-named assigned line, `fix round R/5`, `HANDBACK`, `parked`,
  dispatch `Ruling:` lines, `BLOCKED — <agent> exhausted`, and the complete line
  with `review clean` or `K parked` and its scores clause
  (dforge:subagent-driven-development §The Ledger).

**Recovery.** For task N, take the last line in file order among its
`Task <N>:` lines, stepping over `minor (deferred)`, `parked`,
`Task <N>: Ruling:` and bare `Ruling:` lines. Then:

| Last line | Action |
|---|---|
| `complete` | Done; never redo |
| `BLOCKED` | Terminal. It is a stop of the fourth class for any task that depends on it; name it in your final message |
| `escalated inline -> subagent` | This plan has left inline mode: use dforge:subagent-driven-development |
| `fix round R/3 (…; passing)` | Re-run the task's verifications; if they pass, commit anything uncommitted and write the complete line, else treat as `still failing` |
| `fix round R/3 (…; still failing)`, R < 3 | Resume the loop at round R+1 |
| `fix round 3/3 (…; still failing)` | Go to Switching to subagent mode |
| `implementer inline (assigned; base <sha7>)` | If `git log <base>..HEAD` is non-empty, re-run the task's verifications and finish it from where those commits leave it; otherwise start the task |
| An agent-named `implementer <agent> (assigned …)` line, or `fix round R/5` | A delegated task: apply [delegated-task.md](../../reference/delegated-task.md) §Recovery |
| none | Not started |

**Plan state.** First, whatever the per-task lines say: if the ledger holds a
`Task <N>: escalated inline -> subagent` line with no later
`implementer inline (assigned` line after it, this plan has left inline mode -
use dforge:subagent-driven-development, exactly as `scripts/next-step`
reads the same ledger. Otherwise: every task complete and no `Final review:`
line: go to Final Review. A `Final review: clean` line: go to
dforge:finishing-a-development-branch.

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

Judgment about the plan, the spec or a finding belongs to the ruling seat, not
to you, whatever model you run on. It reads the whole plan, the spec,
`amendments.md` and the ledger; you read the header and one brief at a time. It
and delegated tasks are all this mode dispatches before the final review.

**When.** These points arise in this mode:

| Kind | Decision point |
|---|---|
| `preflight` | Once, before Task 1, when the plan has a heavy task (Setup) |
| `blocked-plan` | The plan is wrong and no path forward is a mechanical choice |
| `plan-conflict` | A final-review finding, or a delegated task's review finding, that conflicts with what the plan's text requires, or is labelled plan-mandated |
| `cannot-verify` | A delegated task's "⚠️ Cannot verify from diff" item |
| `breaker` | A delegated task's findings still open after round 5/5 |
| `executor-empty-diff` | An external executor's fix round that returned DONE with an empty diff and an argument |
| `final-residual` | Findings still open after the final review's one fix wave |

`executor-empty-diff` is reachable here too: an inline plan dispatches its
offloaded tasks, so one of their fix rounds can return DONE with an empty diff,
and `preflight` arises only for a plan with a heavy task.

**How.** Write `<workspace>/rulings-<point>-<task>.md` - `<task>` is the task
number the items concern, or `plan` for a plan-level point, so a recurring
point never overwrites an earlier file - listing each item: an id, its kind,
its task, and the paths it needs, with the findings copied verbatim. Run
`scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]` and dispatch the
`primary` it prints with
[ruling-prompt.md](../subagent-driven-development/references/ruling-prompt.md),
expanding its placeholders. On any exit 2, dispatch
`dforge:judge-opus` and say why, quoting its message - except on a
Codex host, where `review-route --ruling` exits 2 on every `Host: codex` plan and the
seat is the native judge named in Select the host first.

**Carry out each verdict**, and copy its `Ruling:` line into the ledger
verbatim:

- **CONFIRMED-GAP** - the finding is real. For a task you implement, make
  the smallest fix the ruling names. A CONFIRMED-GAP whose fix you attempt and
  fail is a trigger in Switching to subagent mode. A delegated task's gap is
  never yours to fix: mid-task it enters that task's fix loop, and at the
  breaker it is logged `Task <N>: Ruling: <finding> — <ruling>` and carried
  into the next dependent task's dispatch (with none, the next task in plan
  order; after the last task, the final review), as
  [delegated-task.md](../../reference/delegated-task.md) §5 completes it.
- **PARK** - log `Task <N>: parked — <finding> — Ruling: <why>`; the code
  stands.
- **AMEND** - copy the entry, from its `## A?` line through the New fence's
  closing line, to `<workspace>/amend-<id>.md` and run
  `scripts/plan-amend PLAN_FILE <workspace>/amend-<id>.md`. On `amended: A<k> …`, write the amendment ledger line; your next
  `task-brief` carries the amendment. On `rejected: …`, make one fresh seat
  dispatch carrying the entry and the rejection output; a second rejection is
  BLOCKED. A Header amendment is confirmed by a second, independent `judge-opus` dispatch
  before `plan-amend` runs, exactly as dforge:subagent-driven-development
  §The Ruling Seat describes, including its ledger line.
- **BLOCKED** - log `Task <N>: BLOCKED — ruling seat — <decision>`, name it in
  your final message, and stop.

Never soften, merge or second-guess a verdict. If you think the seat is wrong,
carry the verdict out anyway: the ledger line is where your human partner sees
it.

**When no subagent facility exists at all**, the seat is unreachable. Rule
yourself, write `Task <N>: Ruling: (unseated) <item> — <decision> — <cost if
wrong>`, and say it aloud; list every unseated ruling for the final reviewer. A
visible ruling your human partner can rework beats a session parked on a
question. On Claude Code and on Codex this never fires - if it does, check
whether you are in the mode and on the host you think you are.

## Switching to subagent mode

Inline mode has one exit, and it runs in one direction. Take it when:

- your human partner says to;
- a task is still failing its own verifications after `fix round 3/3`;
- a ruling-seat CONFIRMED-GAP names a fix you have attempted and failed.

The trigger is mechanical, so the switch is your ruling, not a seat verdict:
the seat's four verdicts say nothing about execution mode. It happens only at a
task boundary where every earlier task is complete.

1. Append `Task <N>: escalated inline -> subagent — <trigger>`, where `<N>` is
   the task that will run first under subagent mode - the failing task, or,
   on your human partner's instruction, the next task not yet started. This
   line is the switch: every trigger writes it, with or without a preceding
   fix-round line.
2. Log, and say aloud, `Ruling: switch to subagent mode at Task <N> —
   <trigger> — if wrong, the remaining tasks each cost one dispatch that inline
   would not have spent`.
3. Do not edit the plan. `**Execution:**` is one of the lines
   `scripts/plan-amend` refuses to touch, and the ledger is where the switch is
   recorded.
4. Invoke dforge:handoff. The switch is always a handoff: subagent
   mode's value is a fresh controller that reads the header and one brief at a
   time, and this session's context is full of implementation detail it does
   not need. In an auto run, run dforge:handoff steps 0-4, then
   `scripts/auto-run clear --phase`, and end the turn with
   `Auto run: clearing` as its last line; a `next-step` exit 4 or 5 there is
   handled as auto-run.md §Clears says; a phase clear never counts as a
   self-resume.

Your human partner may also move a plan the other way, from subagent mode to
this one. Only their explicit instruction does that, and only at the same kind
of boundary. The return takes effect at the first remaining task that is not delegated:
only its `implementer inline (assigned` line records the return, so delegated
tasks before it still run under subagent mode.

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

**Your rulings ride in that message.** Finishing's Step 3 prints every ledger
line containing `Ruling:` - translations, parked findings, unseated rulings,
ruling-seat verdicts, the mode-switch ruling if you made one - under "Rulings I
made", in the order you made them, each with what it costs if wrong, then
every `BLOCKED` task, then every entry of `<workspace>/amendments.md` in full
under "Amendments made". The lists are exhaustive: they are the only place the
decisions you took on your human partner's behalf reach them, and the only
lasting record of how the plan changed once the workspace is deleted.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Subagents are available, so I should switch to the other skill" | The Execution line chose this mode, not the absence of subagents. Only your human partner overrides it. |
| "I'll read the whole plan, it's faster than one brief at a time" | The plan on disk has no amendments applied. `task-brief` is how corrections reach you. |
| "This task is harder than it scored - I'll just take more rounds" | Three rounds, then the switch. A fourth round on your own work is what not converging looks like. |
| "The owner said switch, but there is no fix round to mark" | The escalated line is its own ledger line. Write it; nothing else records the switch. |
| "The plan is wrong here, I'll fix it as I go" | You read one brief; the seat reads the plan and the spec. Send a blocked-plan item. |
| "No reviewer is watching, so the self-review is optional" | It is the only per-task gate this mode has. Skipping it makes the final review the first time anyone reads the diff. |
| "I'll mention the ruling in my final message instead of the ledger" | Your message dies with the session; the ledger survives compaction. |
| "The final review is clean - I'll summarize the run and stop" | A summary is not a finish. Call the Skill tool for finishing in this turn; its menu and next step are what your human partner acts on. |
| "I'll batch the commits at the end" | The ledger names commit ranges per task. A task without its own commits cannot be recovered or reviewed. |
| "The adjacent bug is a two-line fix" | It is a deferred minor. The final review triages it with the rest. |
| "The budget is at 89%, I'll hand off before the next task" | `ok` means continue. Only a `handoff` verdict stops the loop, and even then the task in flight finishes first. |
| "I should check in before the next task" | Continuous execution. The stops are the four; "are you still happy?" is not one. |
| "Nothing dispatches here, so there is no ledger to keep" | The ledger is what survives compaction, in this mode exactly as in the other. |
