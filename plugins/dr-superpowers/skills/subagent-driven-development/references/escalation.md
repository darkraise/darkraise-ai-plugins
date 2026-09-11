# Escalation details

Read this when a task reaches an escalation point. The tables themselves - the
assignment, escalation, and reserve tables - live in
[ladder.md](../../../reference/ladder.md); never work from memory.

## Where escalation applies

Three points, and no others:

- **Fix rounds 4 and 5.** Dispatch a fresh implementer on the successor rung.
- **The BLOCKED handler**, when the task requires more reasoning. A BLOCKED
  report caused by missing context is not an escalation: supply the context and
  re-dispatch the same agent.
- **Round 3, when progress has stalled** - the re-review's progress reading is
  less than or equal to the previous round's. This can only pull the escalation
  point earlier, never later.

Escalation does **not** apply to fix rounds 1 and 2, nor to round 3 unless
progress has stalled. Those rounds resume the original agent (subject to the
cache rule), which preserves its model, its effort, and its context.
Re-dispatching a different tier there discards exactly what those rounds exist
to preserve.

None of the three applies to a task running on an external executor. Its fix
rounds resume the same Codex session and it leaves the lane by `HANDBACK`
instead of by climbing a rung - see
[external-executor.md](../../../reference/external-executor.md).

## Recording an escalation

Append one clause to the fix-round line the round already writes:

```
Task <N>: fix round 4/5 (1 addressed, 1 open - <one-liner>; commits <a7>..<b7>; escalated <old-agent> -> <new-agent>)
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
action, not an agent. When it is exhausted, do not report BLOCKED yet: break the
task's remaining work into smaller tasks, score each against Rule S, and
dispatch them fresh. Record it as a ruling in the ledger:

```
Ruling: split Task <N> at the top rung into <N>a and <N>b - impl-opus-high exhausted after 5 rounds - if wrong, the halves review separately and merge back
```

**A task may be split-escalated once.** If a split half also exhausts
`impl-opus-high`, the task has resisted both capability and decomposition, and
only then does it enter the reserve chain in
[ladder.md](../../../reference/ladder.md). It enters at `impl-opus-xhigh` and
walks one successor per further exhaustion. Record the entry as its own ruling,
and say it aloud:

```
Ruling: Task <N>a enters the reserve at impl-opus-xhigh - impl-opus-high exhausted again after the split - if wrong, the task is BLOCKED instead and waits for a human
```

A reserve dispatch is the one place this loop spends above the tier the plan
recorded. It should never be a surprise, which is why it is said aloud as well
as written down.

`impl-fable-max` has no successor. When it exhausts, write
`Task <N>: BLOCKED — impl-fable-max exhausted — <what a human must decide>`. Do
not loop, and do not split a second time.

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
  instead. The cost if wrong is spend, not quality.
- **Inside the reserve, for a hand-assigned Fable tier.** The same substitution
  has a target at every effort: `impl-fable-max` drops to `impl-opus-max`,
  `impl-fable-xhigh` to `impl-opus-xhigh`, and `impl-fable-high` to
  `impl-opus-high`.
- **Fable unavailable inside a reserve chain entered automatically.** The task
  reached Fable precisely by exhausting those Opus rungs; re-dispatching one of
  them would re-run an agent that already failed. Write `Task <N>: BLOCKED`
  with the reason instead.

Fable unavailability for a judge seat is a different case: dispatch
`judge-opus` and say so.
