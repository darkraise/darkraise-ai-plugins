---
name: subagent-driven-development
description: Use when executing implementation plans with independent tasks in the current session
---

# Subagent-Driven Development

## After compaction

If this session was compacted — a compaction snapshot or summary sits above —
your memory of the run is gone, and only the start of this file may have come
back. Before anything else:

0. In an auto run, when `scripts/auto-run status` says setup is due, or when
   no ledger names this plan, no task has started: skip the rest of this
   section and follow Setup from its first step.
1. Run `scripts/sdd-workspace PLAN_FILE` (see using-dforge §Session Budget),
   and read `progress.md` and `handoff.md` in `<ledger dir>`, not in the
   directory it prints: while progress lives in darkmem the two differ.
2. Trust the ledger and `git log` over the summary. Read
   [ledger.md](references/ledger.md) §Recovery before you act on a ledger line. For each task the last
   ledger line decides: `complete` is done;
   `fix round 1/2` resumes at round 2 with a fresh dispatch, and `fix round 2/2`
   goes to the breaker (an older run's `R/5` maps as ledger.md §Recovery
   says); an assigned line with commits after its base
   goes to review;
   `awaiting group review` is reviewed by the next group dispatch, never re-dispatched.
   An assigned line ending `thread pending` is an executor
   wrapper that may still be running: find it in the snapshot's background
   list and wait for its notification, or stop it and record a Ruling.
   A `Wave <k>: started` line with no later `integrated` or `merged` line
   is a parallel wave in flight: follow
   [parallel-waves.md](../../reference/parallel-waves.md) §Recovery.
3. When every task has its `complete` line, run `scripts/context-size --final`
   and go on to Final Review or finishing whatever it prints: the final phase
   never hands off. In an auto run it also moves the run to the final phase,
   and a `compact` line still ends the turn on `Auto run: compacting`.
   Otherwise run `scripts/context-size`; on exit 5, finish the task in flight,
   then invoke dforge:handoff. In an auto run, exit 6 (`compact`) is
   [auto-run.md](../../reference/auto-run.md) §The budget line.
4. Re-read this skill in full before the next dispatch, and
   [delegated-task.md](../../reference/delegated-task.md) when a task is
   mid-loop (an agent-named assigned line or `fix round R/2`).

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
  `Task <N>: complete (deferred by the auto run) — done: nothing; verified: not run; remaining: <the item>[; partial commits <a7>..<b7>, kept for the final review | ; unmerged task ref <ref>]; discovered: none; assumptions: none; Ruling: <why> — <cost if wrong>`
  and a deferred register row for each. In a wave, a deferred task's branch is
  not merged, so its commits lie outside the final review's range: its line
  takes `unmerged task ref <ref>`, the ref `scripts/wave ref PLAN_FILE <N>`
  prints, in place of the partial-commits clause, and its register row's note
  names the same ref. Other tasks keep running.
- **Each task:** right after its `Task N: complete` line, run
  `scripts/auto-run task-complete`. After each wave, or each task in
  sequential mode, run the Fable batch when `scripts/auto-run decision list`
  prints anything. When that line leaves every task with its `complete` line
  (in subagent mode, after the last wave's merge), run
  `scripts/auto-run phase final` next, before any budget check and before the
  turn ends, so a compaction from there on never hands off.
  A `task-complete` exit 5 means the run stopped (a task was completed in the
  primary checkout): end as auto-run.md §Stopping says.
- **The budget line** reads `budget (auto…)`. On `compact` (exit 6), finish
  the task in flight (a wave through its merge), then end the turn with
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

Identify the host through its native tool schemas, never by which executables
are installed. On Codex, follow [native-codex.md](../../reference/native-codex.md):
its `codex-v4` protocol replaces every Claude agent and external-CLI
invocation below, including the final branch review, and carries its own
conversion, retry and reserve rules. On Claude, use the seats and loop below.

## Overview

Execute a plan by dispatching, per task, the implementer its
`**Implementer:**` line names; a judge-scored review of each task, alone or, for a low-risk task, in a group with others; and
a broad whole-branch review at the end.

Read [rationale.md](references/rationale.md) before you explain or change why this mode uses subagents and tiered agents. A fleet dispatch passes neither `model` nor `effort`: either one overrides the pinned value.

**Narration:** between tool calls, narrate at most one short line — the
ledger and the tool results carry the record.

**Continuous execution:** Do not pause to check in with your human partner between tasks. Execute all tasks from the plan without stopping. The only reasons to stop are the four named below, or all tasks complete. "Should I continue?" prompts and progress summaries waste their time — they asked you to execute the plan, so execute it.

**Rulings, not stalls.** A running plan does not wait on a human, and it does
not wait on your judgment either. You decide the mechanical problems yourself —
the dispatch-problems table, resuming or re-dispatching by cache state, batching, a report missing a required section, a tool failure — and
record each in the ledger as `Ruling: <what you decided> — <why> — <what it
costs if wrong>`, said aloud. Everything that needs judgment about the plan,
the spec or a finding goes to the ruling seat (see The Ruling Seat): it reads
the whole plan and the spec, which you never read, and returns a verdict you
carry out. A wrong ruling costs rework your human partner can see and undo; a
session parked on a question costs their whole day and buys nothing.

Four things stop you, and only these: an irreversible or destructive
operation; a security-sensitive action; a side effect outside this worktree
that norms say you ask about first (a merge, a push to a shared branch, a
publish); and a ruling-seat `BLOCKED` verdict — a plan so broken that every
path forward is a guess. For those, stop and ask — except in an auto run,
which asks nothing (see Auto run).

**Every session ends with the next step.** Whenever this session ends before
the plan is finished — one of those four stops, a context-budget handoff, or
your human partner asking you to stop — first reconcile live children
exactly as dforge:handoff step 0 says: wait for them, or `TaskStop`
them and record a Ruling. Tell your partner which you did. Then run
`scripts/next-step PLAN_FILE` (see using-dforge §Session Budget) as your
last action. The last thing in your final message is the block it prints,
verbatim. It also rewrites the `## Next session` section of
`<latest.md>`; if it exits 4, say the handoff
file could not be written. When the plan finishes,
dforge:finishing-a-development-branch runs it instead.

## When to Use

When a plan's `**Execution:**` line names `subagent`. Without a plan, use
dforge:brainstorming first; with a line that names `inline`, use
dforge:executing-plans. What this mode adds over inline is a fresh
implementer per task and a judge-scored review after each one.

The plan's `**Execution:**` line decides the mode. Your human partner's explicit
instruction switches it in either direction, and only at a task boundary where
every earlier task is complete, recorded as a `Ruling:` line. Inline mode also
escalates here on its own when a task will not converge; it arrives with a
`Task <N>: escalated inline -> subagent` ledger line, and the Recovery table
in [ledger.md](references/ledger.md) says what to do with it.

## The Process

The flowchart is in [process-graph.md](references/process-graph.md); per task the steps are:

1. Dispatch the implementer the task's `**Implementer:**` line names, with the dispatch file `task-step start` writes ([implementer-prompt.md](references/implementer-prompt.md)). On NEEDS_CONTEXT, supply the missing fact and re-dispatch when it is mechanical; otherwise send a `blocked-plan` item to the ruling seat.
2. `scripts/review-route` grades the task `review=group` or `review=task`. A group task is held with `task-step hold` and reviewed with the others at 4 held, before a `review=task` dispatch and after the last task ([group-reviewer-prompt.md](references/group-reviewer-prompt.md)); any other task gets its own judge ([task-reviewer-prompt.md](references/task-reviewer-prompt.md)).
3. Verdicts clean and no score from 1 to 8: append the `complete` line and take the next task.
4. Otherwise a finding that conflicts with plan text goes to the ruling seat first ([ruling-prompt.md](references/ruling-prompt.md)). Then run fix round R of 2 (R=1 resume or fresh by cache state, R=2 the successor rung, fresh), each followed by a scoped re-review ([re-review-prompt.md](references/re-review-prompt.md)).
5. A finding still open after round 2 goes to the ruling seat as a `breaker` item: a CONFIRMED-GAP or AMEND is carried forward, BLOCKED stops, the rest are parked in the ledger with the ruling. Then append the `complete` line.

After the last task: final review (a code reviewer and a Codex round, a judge verifies the union), ONE fix dispatch, one scoped re-review, the ruling seat on residuals, `Final review: clean`, then dforge:finishing-a-development-branch.

Read [process-graph.md](references/process-graph.md) before you route a state the steps above do not place.

## Setup

Ensure the work happens in an isolated workspace: use dforge:using-git-worktrees to create one or verify the existing one. Never start implementation on a main/master branch without your human partner's explicit consent.

Read [setup.md](references/setup.md) before you create the ledger or dispatch Task 1.

## Seats

Every seat is named, so nothing silently inherits your session's model.

| Seat | Agent | Model argument |
|---|---|---|
| Ruling seat | The seat `scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]` prints (The Ruling Seat) | None |
| Final review | The seat `scripts/review-route PLAN_FILE --final` prints ([final-review.md](../../reference/final-review.md) step 1) | None |
| Final fix wave | The implementer `scripts/review-route PLAN_FILE --final-fix <file> ...` prints ([final-review.md](../../reference/final-review.md) §Fixing what it finds) | None |

The implementer, external implementer, task reviewer and scoped re-review seats,
and the rule that fleet agents take no `model` or `effort` argument, are in
[delegated-task.md](../../reference/delegated-task.md) §Seats.

**General-purpose seats always take an explicit model.** An omitted model
inherits your session's model — often the most capable and most expensive —
which silently defeats the choice.

## The Ledger

This skill owns every line in `<ledger dir>/progress.md`.

Read [ledger.md](references/ledger.md) before you write a ledger line or recover a task's state.

## The Ruling Seat

Judgment belongs to the ruling seat, never to you, whatever model you run on.

Read [ruling-seat.md](references/ruling-seat.md) before you send it an item or carry out a verdict.

## Session Budget

`scripts/task-brief`, `scripts/review-package` and every `scripts/task-step` digest end their output with the budget line ([session-budget.md](../../reference/session-budget.md)).

Read [budget.md](references/budget.md) before you act on a budget verdict.

## The Task Loop

Read [batching.md](references/batching.md) before you batch small same-shape tasks into one dispatch.

Everything you paste into a dispatch prompt — and everything a subagent
prints back — stays resident in your context for the rest of the session
and is re-read on every later turn. Hand artifacts over as files.

**Waiting on dispatched subagents (Claude Code):** Agent dispatches run in
the background, and so do a Codex review seat and a suite that outruns Bash's
ten-minute foreground cap. While local work remains — ledger updates,
packaging the next review, reading reports — keep working; child results
arrive on their own. When only waiting remains, end the turn: each completion
notification starts the next turn.
Never wait with `Monitor`, `sleep` or a polling loop.

On a turn that a notification started, run `scripts/in-flight` before
anything else and handle every launch that finished, including one whose
notification you missed. Its lines show each launch's start time and idle
minutes. In an auto run, a launch that never notifies is caught by the
cockpit, which after 20 minutes without a turn tells you to stop each launch
idle for 30 minutes or more.

On Codex, `wait_agent` covers the idle window instead, in bounded stretches,
because completion mail does not wake an idle session: see Waiting on
children in `skills/using-dforge/references/codex-tools.md`.

For each task, or batch, run [delegated-task.md](../../reference/delegated-task.md):
dispatch the implementer, handle the report, review the task, the fix loop and
the complete line. Its contract names what the loop needs from you.

**Group reviews.** A task `review-route` grades `review=group` is held after
DONE and reviewed with other held tasks in one judge dispatch, per
[delegated-task.md](../../reference/delegated-task.md) §3a.

**Parallel waves.** When the header says `**Parallelism:** waves — …`, run
every wave of more than one task through
[parallel-waves.md](../../reference/parallel-waves.md): its tasks run at once,
each in its own worktree, each through the same loop above, and are merged and
checked together before the next wave starts.
A wave of one task runs in the checkout, proves its base first and closes by §5: run [parallel-waves.md](../../reference/parallel-waves.md) §1 step 2, then the loop above, then §5 (`wave check-due`, then its `integrated` or `merged` line) before the next wave starts.
Every task of a plan without that line runs here exactly as above. Batching
never crosses a wave boundary.

## Final Review

This runs in the session that completed the last task. Only a stop the
final phase cannot avoid (your human partner asked, or the session ended)
brings it to a later session, through dforge:resume-execution.

Follow [final-review.md](../../reference/final-review.md), the procedure both
execution skills share. Point the reviewer at the ledger's deferred-minor and
parked lines, the complete lines' `discovered:` fields, and every borderline
(9-13) score, so it can triage which findings must be fixed before merge.

## Finish

When the final whole-branch review is clean and its fixes are committed,
append `Final review: clean (commits <merge-base7>..<head7>[, K parked])` to
the ledger. Do not delete the workspace:
dforge:finishing-a-development-branch removes it with the worktree once
the work is merged or discarded, and until then it is what a later session
resumes from. Then go on to finishing: it is never budget-checked, since it
costs far less than the fresh session a handoff would start.

**Finishing is a Skill tool call in this same turn.** Call the Skill tool
with `dforge:finishing-a-development-branch` right after the ledger
line. Writing its name in a message is not invoking it, and a turn that ends
on a summary of the run leaves your human partner with no integration menu
and no next step. Write no wrap-up message of your own: finishing's message is
the final one.

Read [finish-rulings.md](references/finish-rulings.md) before you call the finishing skill: your rulings ride in its message.

## Common Rationalizations

Read [rationalizations.md](references/rationalizations.md) before you skip a review, a re-review, a ledger line or a budget check.

## Example Workflow

Read [example-workflow.md](references/example-workflow.md) before you run your first task: it shows two tasks from Setup to finishing.

