# Assignment, escalation, and reserve tables

The raw axis definitions and Rule S are shared across hosts. The unweighted
totals, agent tables, and external CLI lane here apply to Claude. Native Codex
uses [native-codex.md](native-codex.md) and its weighted `codex-v2` score.
The fenced blocks below are parsed by `tests/ladder.test.sh`; keep them machine-readable.

## Scoring rubric

Score each task on four axes, 0 to 3 each, and sum them to a total.

| Axis | 0 | 1 | 2 | 3 |
|------|---|---|---|---|
| Files | one file | two or three | four to six | seven or more, or not enumerable |
| Spec completeness | complete code given verbatim | code given with small gaps | prose plus exact signatures | prose only, approach undecided |
| Coupling | self-contained, consumes nothing | consumes one interface from an earlier task | crosses a layer, or produces interfaces others depend on | changes a shared interface |
| Risk | additive, trivially revertible | localized behavior change | shared code path or data shape | security, data loss, migration, or concurrency |

**Count file shapes, not file instances.** Sixteen files generated from one
template are one shape and score 0 on Files. The axis measures how many distinct
decisions the task carries, and repeating one decision sixteen times is still
one decision. A task that creates one config file and one test file carries two
shapes.

## Three axes are reducible, one is not

| Reducible - fix by splitting | Irreducible |
|------------------------------|-------------|
| Files, Spec completeness, Coupling | Risk |

Files, spec completeness, and coupling are facts about how the plan was drawn.
Risk is a fact about the change itself. Answering a reducible axis with a more
capable model pays to keep a decomposition defect.

## Rule S - the split gate

Let `reducible = files + spec + coupling`.

**If `reducible >= 4`, or if `spec = 3`, the task must be split or re-designed.
Do not assign a larger model.**

`spec = 3` means prose only with the approach undecided. That is not a
model-selection problem; it is a design decision nobody made. Route it to
dr-superpowers:selecting-approaches, settle the approach, rewrite the
task with the decision in it, and re-score. The task will then score 0, 1, or 2
on that axis like every other compliant task.

Rule S caps a compliant total: `reducible <= 3` and `spec <= 2`, so
`total <= 3 + risk(3) = 6`. **The assignment table's ceiling is a consequence of
Rule S, not a separate choice.** A computed total of 7 or more means the gate was
skipped, not that a higher tier is needed.

### The one legacy floor

0.1.0 assigned a `spec = 3` task no lower than `impl-opus-low`. That floor now
applies only when a human overrides Rule S and keeps an undecided-approach task
as written. It raises; it never lowers.

## Assignment table

The total indexes this table directly. Two planners scoring a task identically
always reach the same agent.

```assignment
0 impl-haiku
1 impl-sonnet-low
2 impl-sonnet-medium
3 impl-sonnet-high
4 impl-opus-low
5 impl-opus-medium
6 impl-opus-high
```

## Escalation table

Escalation changes model before it changes effort, because an implementer that
is stuck usually needs more capability rather than marginally more thinking.

```escalation
impl-haiku impl-sonnet-medium
impl-sonnet-low impl-opus-low
impl-sonnet-medium impl-opus-medium
impl-sonnet-high impl-opus-high
impl-opus-low impl-opus-medium
impl-opus-medium impl-opus-high
impl-opus-high SPLIT
```

### The terminal rung is an action

`SPLIT` is not an agent. A task that exhausts `impl-opus-high` has its remaining
work broken into smaller tasks, each scored fresh against Rule S and dispatched
on its own. This is the ladder's answer to a task that is genuinely too large,
and it is the same answer Rule S gives at planning time.

**A task may be split-escalated once.** If a split half also exhausts
`impl-opus-high`, the task has resisted both capability and decomposition. That
is the one situation the reserve table below exists for, and the only one in
which it is entered automatically.

### Why this terminates

Rank each agent as `model_rank * 10 + effort_rank`, where Haiku ranks 0, Sonnet
1, Opus 2, and Fable 3, and effort ranks 0 through 4 from `low` to `max`. That
puts Haiku at 0, Sonnet at 10 to 14, Opus at 20 to 24, and Fable at 30 to 34.
Every successor in this table and in the reserve table has a strictly higher
rank, so both graphs are acyclic and every walk reaches a terminal: `SPLIT`
here, `BLOCKED` there. `tests/ladder.test.sh` asserts the ranking and both walks
rather than trusting this argument.

Judges and scouts are not on the ladder. They are not implementers, so they are
never an escalation source or target.

## Reserve table

Nine implementers exist that no score can reach: the `xhigh` and `max` efforts,
and every Fable tier. They are the reserve. No row of the assignment table names
one, and no row of the escalation table points at one.

Two things reach them:

1. **A human ruling.** A hand-edited `**Implementer:**` line naming a reserve
   agent is dispatched as written. A human ruling has always beaten the rubric;
   the reserve is what gives that ruling somewhere above `impl-opus-high` to go.
2. **A task that has run out of splits.** A task that exhausts
   `impl-opus-high`, is split once, and exhausts `impl-opus-high` again in one
   of its halves has resisted both capability and decomposition. That is the
   only case the reserve is entered automatically.

```reserve
impl-sonnet-xhigh impl-sonnet-max
impl-sonnet-max impl-opus-high
impl-opus-high impl-opus-xhigh
impl-opus-xhigh impl-opus-max
impl-opus-max impl-fable-high
impl-fable-low impl-fable-medium
impl-fable-medium impl-fable-high
impl-fable-high impl-fable-xhigh
impl-fable-xhigh impl-fable-max
impl-fable-max BLOCKED
```

`impl-opus-high` is a source in both tables, and the difference between them is
whether the split has been spent. Its escalation successor is `SPLIT` the first
time it is exhausted; its reserve successor, `impl-opus-xhigh`, applies only
after that split has happened and failed. That condition is the whole of the
guard: no ordinary task reaches Fable without a split standing between it and
the reserve.

The Sonnet reserve rungs point back at the execution ladder rather than upward
into Fable. A human who hand-assigns `impl-sonnet-max` and watches it stall gets
`impl-opus-high`, and with it the split, before anything reaches the top of the
reserve.

Every reserve agent is a source exactly once, so a hand-assigned
`impl-fable-low` has somewhere to escalate. `BLOCKED` is the terminal and is not
an agent: a task that exhausts `impl-fable-max` is logged
`Task <N>: BLOCKED — impl-fable-max exhausted — <what a human must decide>`.
There is no rung above it and no second split.

Ranking Fable above Opus puts `impl-fable-low` above `impl-opus-max` in the walk
order. That is a statement about how the chain is traversed, not a claim that
Fable at low effort out-thinks Opus at max: `impl-fable-low` is reachable only
by a human naming it, and the automatic path enters Fable at `impl-fable-high`.

0.1.0 plans name every one of these nine agents, and they now resolve natively.
A plan that recorded `impl-fable-max` runs at `impl-fable-max`, which is what it
asked for. Nothing is substituted on read, so there is nothing to state in the
ledger beyond the reserve tier itself.

## What the range actually reaches

A plan written to dr-superpowers:writing-plans bans placeholders and requires the
real code in every code step, so a compliant task scores 0 or 1 on spec
completeness almost by construction. Combined with Rule S, initial assignments
cluster in the 0 to 3 band - Haiku and Sonnet. Scores of 4 to 6 are reached
almost entirely through the Risk axis, which is the one axis splitting cannot
reduce.

That is the intended outcome. Do not inflate an axis to land on a tier that feels
right; if a task feels harder than its score, the plan text is probably hiding
something, and the fix is a better task description or a smaller task.

## The external lane

An external executor is not a rung on the escalation ladder above. Offload
selects downward at the cheap end while the ladder only moves upward, and one
total order cannot express both. The Claude ladder remains the sole backstop, so
its termination proof is unchanged by anything in this section.

### The lane gate

```gate
min_score 2
max_risk 1
require_rule_s_clean true
require_external_enabled true
```

All four conditions must hold. `require_rule_s_clean` excludes a task whose
`spec = 3` was kept by a human override under the legacy floor: such a task can
score `0 + 3 + 0 + 0 = 3` and would otherwise pass, sending a task whose approach
nobody decided to a one-shot external agent.

`min_score 2` is not arbitrary. Rule S caps `reducible` at 3, so under
`max_risk 1` the eligible totals are exactly 2, 3, and 4 - totals 5 and 6 need
`risk >= 2` and the risk clause already excludes them. Without the floor the gate
would reduce to `risk <= 1` and capture nearly every task by count. It would also
offload where offload is worthless: a score-0 task displaces `impl-haiku`, which
costs less to run than the wrapper costs to orchestrate.

### Codex assignment

```codex-assignment
2 gpt-5.5 medium
3 gpt-5.5 high
4 gpt-5.6-sol high
```

Only `gpt-5.5` and `gpt-5.6-sol` appear in this external CLI policy. On 2026-08-31,
Codex 0.151.0 on Windows with ChatGPT-subscription authentication rejected Luna
and Terra with HTTP 400 and provided no metadata for them. Those historical
observations do not establish current access on another account, CLI version,
or native client. Native Codex routes Terra through its separate capability filter.

This CLI policy allows `low`, `medium`, `high`, `xhigh`, and `ultra`, and rejects
`minimal`. Verify advertised capabilities for the actual CLI/account before use;
do not infer them from the native model list or make paid capability probes.

### Codex successor

```codex-successor
gpt-5.5/medium gpt-5.5/high
gpt-5.5/high gpt-5.6-sol/high
gpt-5.6-sol/high gpt-5.6-sol/xhigh
gpt-5.6-sol/xhigh HANDBACK
```

This is a single-successor column consulted at most once per task, not a
walkable chain. Only a failed *initial run* consults it: the fix loop resumes the
same session on rounds 1 to 3 and hands back on round 4, so no fix round ever
reads it. It is named `successor` rather than `escalation` for that reason.

A fix round whose resume fails to run at all is the case that looks closest to a
run failure, and it is still excluded. Changing rung mid-loop would discard the
session context those rounds exist to preserve, so such a round leaves the lane
by `HANDBACK` instead - the exit it was already heading for at round 4.

`HANDBACK` is an action, not an executor - the same shape as `SPLIT` at the top
of the escalation table. It resolves to the Claude assignment-table row for the
task's score, after which the ordinary ladder governs.

Ranking a rung as `model_rank * 10 + effort_rank`, where `gpt-5.5` ranks 0 and
`gpt-5.6-sol` ranks 1, gives every successor a strictly higher rank than its
source, so the column is acyclic and every walk reaches `HANDBACK`.

### Codex timeout

```codex-timeout
gpt-5.5/medium 900
gpt-5.5/high 1200
gpt-5.6-sol/high 1800
gpt-5.6-sol/xhigh 2400
```

Seconds. One constant cannot serve both a `medium` and an `xhigh` run.
