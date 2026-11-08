---
name: selecting-approaches
description: Use when an approach decision is open - during brainstorming, or when a plan task scores 3 on spec completeness - gates the decision to inline or one advisor pass
---

# Selecting Approaches

## Select the host first

Identify the active host from callable native tools, not installed
executables. On Codex, keep the gate below but dispatch the advisor judge as
[native-codex.md](../../reference/native-codex.md) describes: judges at Astra
high, read-only restrictions enforced where the host allows and disclosed where
it does not. On Claude, use the registered fleet.

Settle an open approach decision at a cost that matches what the decision is
worth. Two modes: `inline` and `advisor`. Most decisions are settled inline;
a load-bearing one earns one advisory pass.

**Announce at start:** "I'm using the selecting-approaches skill to settle this
approach decision."

## When this applies

Two entry points:

- **dforge:brainstorming**, at the architectural path's "propose 2-3
  approaches" step.
- **A plan task scoring 3 on spec completeness**, which Rule S in
  [`../../reference/ladder.md`](../../reference/ladder.md) routes here rather
  than to a larger model. Prose only with the approach undecided is a design
  decision nobody made, and buying capability is not the same as making it.

## The gate decides who decides, not whether

Every decision that reaches this skill gets settled before implementation. The
gate chooses which of two seats settles it:

| Outcome | Cost | Who settles it |
|---------|------|----------------|
| `inline` | 0 subagent calls | You do, and record why |
| `advisor` | 1 call | You choose; one judge checks the choice |

A load-bearing decision asks a verification question - "is this choice
wrong" - and one judge reading your chosen approach answers it. You draft the
candidates yourself: you have already read the code they would change.

## Skip to inline

Any one of these sends the decision to `inline`. **Cite it by number in the
`**Approach:**` line.** An uncited skip is not a skip - it is you deciding the
cost is inconvenient, which is exactly what the gate is here to stop.

1. **A bug fix whose root cause is located.** Fixing it correctly is one
   approach; the alternatives are wording.
2. **The repository already answers it.** An established pattern covers this
   exact change - a fourth adapter beside three, a new flag beside eight.
   Consistency dominates, and a creative alternative is a defect.
3. **The spec or your human partner already chose.** Ranking ruled-out options
   is theatre.
4. **Trivially reversible and confined to one file.** Being wrong costs a
   revert.
5. **The decision is not load-bearing** (as When advisor runs defines it).
   Write each candidate in one sentence before dispatching anything.

### Bugs are excluded on correctness grounds, not cost

Generating candidate approaches before a root cause is located produces N
guesses, and a ranking pass returns a winner whether or not any candidate is
right - laundering speculation into a confident pick, and a judge checking one
guess does no better. An unlocated root cause is
a debugging problem: use dforge:systematic-debugging. Come back here only
if, with the cause in hand, more than one structurally distinct fix exists.

## When advisor runs

Both must hold:

- The decision is load-bearing: it constrains later tasks, or it is expensive to
  reverse - an interface others consume, a data shape, a stored format, a
  migration, a public API, a dependency choice.
- Neither the repository nor the spec already answers it.

Everything else is `inline`. Draft the candidates yourself, choose one, and
send that choice to the advisor.

## Run advisor

State your chosen approach in a paragraph, with the candidates you rejected and
why, then dispatch one `dforge:judge-opus` to score it,
naming the report file `<state>/approaches-<decision>-advisor-report.md`:
write nothing else, and reply in at most 10 lines; its `## Verdict` section
holds `verdict: sound | wrong`. The judge scores it against the same criteria
file and answers one question: is this approach wrong for this repository, and
if so, what specifically would fail?

A judge that finds nothing is not a rubber stamp - it is the cheap outcome you
were paying for. A judge that finds something is why the seat exists; treat its
answer as a finding to address, not a veto to argue with.

## Record the decision

Write one line into the plan task or the design document:

```markdown
**Approach:** inline - skip 2: follows the existing hook-script pattern
**Approach:** advisor - load-bearing (produces the criteria file format)
```

An existing `**Approach:** best-of-3 - …` line is the record of a decision made
before best-of-3 was removed; `plan-lint` still accepts it, and nothing reruns
it.
