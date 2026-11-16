# Escalation details

Read this when a task reaches an escalation point. The tables themselves - the
assignment, escalation, and reserve tables - live in
[ladder.md](../../../reference/ladder.md); never work from memory.

## Where escalation applies

Two points, and no others:

- **Fix round 2.** Dispatch a fresh implementer on the successor rung (the
  same rung when that successor is `SPLIT`; a reserve-tier task takes its
  reserve successor).
- **The BLOCKED handler**, when the task requires more reasoning. A BLOCKED
  report caused by missing context is not an escalation: supply the context and
  re-dispatch the same agent.

Escalation does **not** apply to fix round 1. That round resumes the original
agent (subject to the cache rule), which preserves its model, its effort, and
its context. Re-dispatching a different tier there discards exactly what that
round exists to preserve.

Neither applies to a task running on an external executor.
Its fix rounds resume that executor's own session at round 1 only - the one its
`**Executor:**` line names - and round 2 leaves the lane by `HANDBACK` instead
of climbing a rung - see
[executor-lane.md](../../../reference/executor-lane.md).

## Escalating out of inline mode

A task whose last ledger line is `escalated inline -> subagent` failed in an
inline session that may already run above the task's assigned tier, so the
successor of the `**Implementer:**` agent alone can land at or below the tier
that just failed. Rank both with [ladder.md](../../../reference/ladder.md)
§Why this terminates:

- the task's `**Implementer:**` agent, and
- the inline session's rung: the Execution line's `--model` and `--effort` as
  `impl-<model>-<effort>` (`haiku` as `impl-haiku`).

Start the walk from whichever ranks higher and dispatch its successor on the
escalation table, the first rung ranked strictly above both. For example,
`impl-sonnet-low` assigned in an `impl-sonnet-high` session dispatches
`impl-opus-high`, not `impl-opus-low`. When that start is `impl-opus-high`, its
successor is `SPLIT`, handled as §The top rung is SPLIT describes.

## Recording an escalation

Append one clause to the fix-round line the round already writes:

```
Task <N>: fix round 2/2 (1 addressed, 1 open - <one-liner>; commits <a7>..<b7>; escalated <old-agent> -> <new-agent>)
```

A BLOCKED-handler escalation happens outside the fix loop, so it has no
fix-round line to extend. Record it as a new assigned line for the task:

```
Task <N>: implementer <new-agent> (assigned; base <sha7>; escalated from <old-agent>: BLOCKED)
```

The ladder is deterministic, so the round number and the original assignment
re-derive every escalated agent after a crash.

## The top rung is SPLIT

The ladder's top rung is `impl-opus-high`, whose successor is `SPLIT` - an
action, not an agent, so round 2 of a task on `impl-opus-high` is a fresh
dispatch of `impl-opus-high`, and a split is reached only through the breaker's AMEND.
When round 2 leaves findings open, do not report BLOCKED yet, and do not
decide the decomposition yourself: the open findings go to the breaker, and
its AMEND rewrites Task N's body into ordered parts under the same heading and
number:

```markdown
### Task N: <title>          (unchanged)

#### Part A: <title>
**Files:** …
**Interfaces:** …
**Implementer:** dforge:impl-<tier>
**Evaluation:** files a - spec b - coupling c - risk d = t
- [ ] steps…

#### Part B: <title>
(the same blocks; Part B may consume Part A's output)
```

Each part is a unit `scripts/plan-lint` checks on its own against Rule S, and
`scripts/task-brief PLAN_FILE N` carries both. Apply the amendment through
`scripts/plan-amend` as any AMEND, then dispatch the parts in order, one
dispatch per part, each with a fresh brief and the instruction "Part A only"
(then "Part B only"). Each part gets its own review; the ledger's assigned and
fix-round lines carry `; part A` / `; part B`, and one complete line closes the
task after the last part, with `parts A, B` in its parenthesis. Log the split:

```
Ruling: split Task <N> at the top rung into parts A and B (amendment A<k>) - impl-opus-high exhausted after 2 rounds - if wrong, the parts review separately and merge back
```

**A task may be split-escalated once.** A part on `impl-opus-high` whose
round 1 leaves findings open takes `impl-opus-xhigh` at round 2: the split is
spent, the task has resisted both capability and decomposition, and only then
does it enter the reserve chain in
[ladder.md](../../../reference/ladder.md). It enters at `impl-opus-xhigh` and
walks one successor per further exhaustion. Record the entry as its own ruling,
and say it aloud:

```
Ruling: Task <N> part A enters the reserve at impl-opus-xhigh - impl-opus-high exhausted again after the split - if wrong, the task is BLOCKED instead and waits for a human
```

A reserve dispatch is the one place this loop spends above the tier the plan
recorded. It should never be a surprise, which is why it is said aloud as well
as written down.

`impl-fable-max` has no successor. When its round 1 leaves findings open,
write `Task <N>: BLOCKED — impl-fable-max exhausted — <what a human must decide>`
instead of a round 2. Do not loop, and do not split a second time.

## Reserve agents named in a plan

Nine implementers - the `xhigh` and `max` efforts, and every Fable tier - sit in
the reserve table and in no other table. `impl-opus-high` also appears there,
but only as the conditional entry edge; it is the score-6 execution assignment.

A plan line naming one of the nine is a human ruling, because no score reaches
them, and a human ruling beats the rubric. Dispatch it as written, note the tier
in the assigned line (`reserve tier`), and do not re-score the task down to an
execution tier.

## When a model is unavailable

Each substitution below is a ruling: say it aloud and log
`Ruling: <what> — <why> — <cost if wrong>`. Never substitute silently. If a bad
agent name quietly degraded to the session default, every task would run at the
session's model and effort and nothing in the output would reveal it.

- **An implementer's model is unavailable on this account.** Dispatch the same
  effort one model down: an `impl-opus-<effort>` agent becomes
  `impl-sonnet-<effort>`.
- **No same-effort model below exists** - any Sonnet agent, or `impl-haiku`.
  Haiku ships in one flavour with no effort variants, so "same effort, one model
  down" has no target. Dispatch the agent's successor in the escalation table
  instead. `impl-sonnet-xhigh` and `impl-sonnet-max` sit only in the reserve
  table, where every Sonnet row leads to `impl-opus-high`: dispatch that. The
  cost if wrong is spend, not quality.
- **Inside the reserve, for a hand-assigned Fable tier.** The same substitution
  has a target at every effort: `impl-fable-max` drops to `impl-opus-max`,
  `impl-fable-xhigh` to `impl-opus-xhigh`, `impl-fable-high` to
  `impl-opus-high`, `impl-fable-medium` to `impl-opus-medium`, and
  `impl-fable-low` to `impl-opus-low`.
- **Fable unavailable inside a reserve chain entered automatically.** The task
  reached Fable precisely by exhausting those Opus rungs; re-dispatching one of
  them would re-run an agent that already failed. Write `Task <N>: BLOCKED`
  with the reason instead.
- **A substitute that is itself unavailable.** A model found unavailable stays
  unavailable for the session, so never substitute onto it again: `impl-opus-low`
  to `impl-sonnet-low` and back to its successor `impl-opus-low` would loop.
  Walk the substitute's escalation successors past every agent on a model
  already found unavailable. When the walk reaches `SPLIT` or an agent already
  tried for this dispatch, write
  `Task <N>: BLOCKED — no available implementer — <the models found unavailable>`.
