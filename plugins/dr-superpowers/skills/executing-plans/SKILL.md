---
name: executing-plans
description: Use when a plan's Execution line names inline mode - the session implements every task itself, with the whole-branch final review as its gate
---

# Executing Plans

## After compaction

If this session was compacted - a compaction snapshot or summary sits above -
your memory of the run is gone, and only the start of this file may have come
back. Before anything else:

1. Run `scripts/sdd-workspace PLAN_FILE`, from the plugin root (the path the session's entry point names; two
   levels above this skill's directory), and read `progress.md` and `handoff.md` in
   the directory it prints.
2. Trust the ledger and `git log` over the summary. For each task the last
   ledger line decides; see the Recovery table under The Ledger.
3. Run `scripts/context-size`. On exit 5, invoke dr-superpowers:handoff.
4. Re-read this skill in full before the next task.

## Select the host first

On Codex, the ruling seat is a native judge at Astra high or above
([native-codex.md](../../reference/native-codex.md)), and there is no budget
line: hand off after every 3 completed tasks, or after any task that needed 3
or more fix rounds. Everything else here is host-neutral - inline mode
dispatches nothing but the ruling seat and the final review.

## Overview

Execute a plan yourself, task by task, with the whole-branch final review as
the gate.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Why this mode.** The plan's `**Execution:**` line chose it because every task
scores 4 or less with none at risk 3: each is a small change whose text carries
the code, and a subagent per task would cost more in context rebuild than the
task itself. The line's model follows the highest score: Sonnet when every
task is 3 or less, Opus when any task scores 4. Subagent availability has
nothing to do with it - the line decides, and only your human partner
overrides it.

**Why no per-task review.** The eligibility bar is the gate, applied before
execution starts. A task too large, too vague or too risky for this mode never
reaches it: the plan would have said `subagent`. What catches the rest is the
plan's own verification steps, your self-review of each diff, and one broad
review of the whole branch at the end.

**Continuous execution.** Do not pause between tasks to check in. "Should I
continue?" prompts and progress summaries waste your human partner's time -
they asked you to execute the plan, so execute it.

**Rulings, not stalls.** Decide the mechanical problems yourself - a legacy
name, a missing directory, a tool failure, a plan that is silent where you need
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
ruling-seat `BLOCKED` verdict. For those, stop and ask.

**Every session ends with the next step.** Whenever this session ends before
the plan is finished - one of those four stops, a context-budget handoff, a
switch to subagent mode, or your human partner asking you to stop - run
`scripts/next-step PLAN_FILE`, from the plugin root, as your last action. The
last thing in your final message is the block it prints, verbatim. It also
rewrites the `## Next session` section of the primary checkout's
`.superpowers/handoff/latest.md`; if it exits 4, say the handoff file could not
be written. When the plan finishes,
dr-superpowers:finishing-a-development-branch runs it instead.

## Setup

Ensure the work happens in an isolated workspace: use
dr-superpowers:using-git-worktrees to create one or verify the existing one.
Never start implementation on a main/master branch without your human partner's
explicit consent.

Conversation memory does not survive compaction. Track progress in a ledger
file, not only in todos.

- Each plan owns a workspace: run `scripts/sdd-workspace PLAN_FILE`, from the
  plugin root, and it prints the plan's git-ignored directory
  (`<repo-root>/.superpowers/sdd/<plan-basename>/`), home to every artifact for
  THIS plan. Another plan's directory is never yours to read or write.
- This plan's ledger is `<workspace>/progress.md`. If its first line names your
  plan file, recover each task's state with the Recovery table under The
  Ledger. A ledger whose first line names a different plan - or a stray ledger
  at the old flat path `.superpowers/sdd/progress.md` - is another plan's
  progress: leave it in place and start your own, fresh.
- Create the ledger with its identity as the first line:
  `# SDD ledger — plan: <plan file path>` — the path exactly as you pass it to
  the scripts (checkout-relative or absolute; `next-step` resolves both).
- Create `<workspace>/handoff.md` from the template in dr-superpowers:handoff
  if it does not exist. Update it in the same message as a ledger write
  whenever an owner constraint, gotcha, prohibition or open question changes.
- `git clean -fdx` will destroy the workspace (it is git-ignored scratch); if
  that happens, recover from `git log`.

Read the plan's header, never the whole plan: run
`scripts/task-brief --header PLAN_FILE`, from the plugin root, and read the
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
  dr-superpowers:subagent-driven-development instead.
- The plan has no Execution line, because it was written before 1.4.0: log
  `Ruling: inline by invocation — plan predates the Execution line — if wrong,
  the run escalates at the first task that will not converge` and continue.

Never re-score the tasks. `scripts/plan-lint` enforced the eligibility rule
when the plan was saved, and a plan whose Execution line says `inline` has
passed it.

**Resolve legacy names.** Plans written before this plugin's 1.2.0 may name
skills and agents under older plugin prefixes. Translate each with
[legacy-names.md](../../reference/legacy-names.md) at read time, never edit the
plan, and log one `Ruling: translated <old> -> <new> — legacy plugin name —
none` per distinct name. `**Implementer:**` and `**Executor:**` lines are inert
in this mode: no task is dispatched, so their names need no translation.

There is no pre-flight scan. It is one whole-plan judge dispatch, and a plan
eligible for this mode is low-coupling by construction. A plan defect that
surfaces while you work goes to the seat as a `blocked-plan` item.

## The Ledger

This skill and dr-superpowers:subagent-driven-development share one grammar, so
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
Final review: clean (commits <merge-base7>..<head7>[, K parked])
```

- `implementer inline` is this mode's assigned line. You are the implementer,
  so the agent slot says so, and `base` is `git rev-parse --short HEAD` taken
  before you change anything.
- `unreviewed` is where subagent mode writes `review clean`. No judge scored
  this task, and saying so is what keeps the two modes' complete lines honest.
  The branch's review is the `Final review:` line.
- There is no scores clause. A scores clause appears only when a judge scored
  the task.
- The fix cap is 3, not subagent mode's 5. You are fixing your own work, so a
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

**Recovery.** For task N, take the last line in file order among its
`Task <N>:` lines, stepping over `minor (deferred)`, `parked`,
`Task <N>: Ruling:` and bare `Ruling:` lines. Then:

| Last line | Action |
|---|---|
| `complete` | Done; never redo |
| `BLOCKED` | Terminal. It is a stop of the fourth class for any task that depends on it; name it in your final message |
| `escalated inline -> subagent` | This plan has left inline mode: use dr-superpowers:subagent-driven-development |
| `fix round R/3 (…; passing)` | Re-run the task's verifications; if they pass, commit anything uncommitted and write the complete line, else treat as `still failing` |
| `fix round R/3 (…; still failing)`, R < 3 | Resume the loop at round R+1 |
| `fix round 3/3 (…; still failing)` | Go to Switching to subagent mode |
| `implementer inline (assigned; base <sha7>)` | If `git log <base>..HEAD` is non-empty, re-run the task's verifications and finish it from where those commits leave it; otherwise start the task |
| none | Not started |

**Plan state.** First, whatever the per-task lines say: if the ledger holds a
`Task <N>: escalated inline -> subagent` line with no later
`implementer inline (assigned` line after it, this plan has left inline mode -
use dr-superpowers:subagent-driven-development, exactly as `scripts/next-step`
reads the same ledger. Otherwise: every task complete and no `Final review:`
line: go to Final Review. A `Final review: clean` line: go to
dr-superpowers:finishing-a-development-branch.

## Session Budget

`scripts/task-brief` ends its output with the budget line
([session-budget.md](../../reference/session-budget.md)), so you check the
budget before every task at no extra request:

    budget: 312k of 475k (65%) — ok — source: record

- `ok` or `unknown`: carry on.
- `handoff`: finish the task in flight, write its ledger line, then invoke
  dr-superpowers:handoff. Never hand off mid-task.

Run `scripts/context-size` after each `Task <N>: complete` line and act on its
exit 5 the same way.

The last task completing is a soft stop: the final review runs in this session
unless the budget line says `handoff`. A switch to subagent mode is always a
handoff.

## The Task Loop

For each task, in order:

1. **Read the brief.** Run `scripts/task-brief PLAN_FILE N`, from the plugin
   root, and read the file it prints. It carries the task text with every
   amendment applied, the header's Global Constraints and Contracts, and the
   budget line. You never read task text any other way: reading the plan file
   directly skips the amendments.
2. **Open the task.** Take the base commit (`git rev-parse --short HEAD`) and
   append `Task <N>: implementer inline (assigned; base <sha7>)`.
3. **Implement exactly what the task names.** Follow its steps in order. Where
   the task says to write a test first, use
   dr-superpowers:test-driven-development. Touch only the files and lines the
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
   same message as your other bookkeeping, and mark the todo complete.
8. **Check the budget.** Run `scripts/context-size`.

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
is the only thing this mode dispatches before the final review.

**When.** Three points arise in this mode:

| Kind | Decision point |
|---|---|
| `blocked-plan` | The plan is wrong and no path forward is a mechanical choice |
| `plan-conflict` | A final-review finding that conflicts with what the plan's text requires, or is labelled plan-mandated |
| `final-residual` | Findings still open after the final review's one fix wave |

The other five kinds belong to seats this mode does not run: `preflight` (there
is no pre-flight scan), `cannot-verify` and `risk3-spread` (no task reviewer),
`breaker` (no five-round review loop), and `codex-empty-diff` (no external
executor).

**How.** Write `<workspace>/rulings-<point>-<task>.md` - `<task>` is the task
number the items concern, or `plan` for a plan-level point, so a recurring
point never overwrites an earlier file - listing each item: an id, its kind,
its task, and the paths it needs, with the findings copied verbatim. Dispatch
`dr-superpowers:judge-fable` (`dr-superpowers:judge-opus` when Fable is
unavailable or your human partner declined it - say the substitution aloud)
with
[ruling-prompt.md](../subagent-driven-development/references/ruling-prompt.md),
expanding its placeholders.

**Carry out each verdict**, and copy its `Ruling:` line into the ledger
verbatim:

- **CONFIRMED-GAP** - the finding is real. Make the smallest fix the ruling
  names. A CONFIRMED-GAP whose fix you attempt and fail is a trigger in
  Switching to subagent mode.
- **PARK** - log `Task <N>: parked — <finding> — Ruling: <why>`; the code
  stands.
- **AMEND** - copy the entry, from its `## A?` line through the New fence's
  closing line, to `<workspace>/amend-<id>.md` and run
  `scripts/plan-amend PLAN_FILE <workspace>/amend-<id>.md`, from the plugin
  root. On `amended: A<k> …`, write the amendment ledger line; your next
  `task-brief` carries the amendment. On `rejected: …`, make one fresh seat
  dispatch carrying the entry and the rejection output; a second rejection is
  BLOCKED.
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
4. Invoke dr-superpowers:handoff. The switch is always a handoff: subagent
   mode's value is a fresh controller that reads the header and one brief at a
   time, and this session's context is full of implementation detail it does
   not need.

Your human partner may also move a plan the other way, from subagent mode to
this one. Only their explicit instruction does that, and only at the same kind
of boundary.

## Final Review

Every task is complete, so the branch gets one broad review: follow
[final-review.md](../../reference/final-review.md), the procedure both
execution skills share. In this mode it runs in this session, unless the last
budget line said `handoff` - then invoke dr-superpowers:handoff, and
dr-superpowers:resume-execution brings the next session here. List any
`(unseated)` rulings for the reviewer alongside the ledger's parked and
deferred-minor lines.

## Finish

Before you leave this skill, collect every ledger line containing `Ruling:` -
translations, parked findings, unseated rulings, ruling-seat verdicts, the
mode-switch ruling if you made one - into your final message under "Rulings I
made", in the order you made them, each with what it costs if wrong. The list
is exhaustive: if the ledger holds a ruling, the list holds it. That list is
the only place the decisions you took on your human partner's behalf reach
them - they read it and rework whatever you got wrong. Name every `BLOCKED`
task there too.

Then, under "Amendments made", print every entry of `<workspace>/amendments.md`
in full, if the file exists. The workspace is deleted after a merge, so this
printed list is the only lasting record of how the plan changed during
execution.

When the final review is clean and its fixes are committed, append
`Final review: clean (commits <merge-base7>..<head7>[, K parked])` to the
ledger in the same message as printing the rulings. Do not delete the
workspace: dr-superpowers:finishing-a-development-branch removes it with the
worktree once the work is merged or discarded, and until then it is what a
later session resumes from.

Use dr-superpowers:finishing-a-development-branch.

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
| "I'll batch the commits at the end" | The ledger names commit ranges per task. A task without its own commits cannot be recovered or reviewed. |
| "The adjacent bug is a two-line fix" | It is a deferred minor. The final review triages it with the rest. |
| "I should check in before the next task" | Continuous execution. The stops are the four; "are you still happy?" is not one. |
| "Nothing dispatches here, so there is no ledger to keep" | The ledger is what survives compaction, in this mode exactly as in the other. |
