# dcc-superpower-companions: the reserve tier

Restore the nine implementer agents deleted in 0.2.0 as an off-ladder reserve
class, without loosening Rule S or raising the assignment ceiling.

## Problem

0.2.0 (commit `bf09dc0`) deleted nine implementers - `impl-sonnet-{xhigh,max}`,
`impl-opus-{xhigh,max}`, and all five `impl-fable-*` tiers - on the reasoning
that three of the four scoring axes measure how a task was drawn rather than how
hard it is, so buying capability to cover a decomposition defect keeps the
defect. That reasoning holds and is not being revisited.

What it left behind are two situations with no answer:

1. **A human wants a tier the rubric will not choose.** The `**Implementer:**`
   line is designed to be hand-edited, and a human ruling is supposed to beat the
   rubric. After 0.2.0 the only rulings available were the seven the rubric
   itself can reach.
2. **A task that genuinely cannot be split further.** The ladder's answer above
   `impl-opus-high` is `SPLIT`, and a split half that also exhausts reports
   BLOCKED. Risk is the one axis splitting cannot reduce, so an irreducible task
   could exhaust every option the fleet had while more capable models sat unused.

## Non-goals

- **Rule S does not change.** `reducible >= 4` or `spec = 3` still sends a task
  back to be split or re-designed.
- **The assignment table does not change.** It still runs 0 through 6 and still
  stops at `impl-opus-high`. A computed total of 7 or more still means the gate
  was skipped.
- **Ordinary escalation does not change.** The seven-row escalation table still
  ends `impl-opus-high SPLIT`. Splitting remains the first answer to a hard task.

Restoring the files must not become a way to score around the gate. Every
mechanism below is downstream of a split that has already been spent, or of an
explicit human ruling.

## Design

### Three agent classes

| Class | Members | Reached by |
|-------|---------|------------|
| Execution implementers (7) | `impl-haiku`, `impl-sonnet-{low,medium,high}`, `impl-opus-{low,medium,high}` | Assignment table, ordinary escalation |
| Reserve implementers (9) | `impl-sonnet-{xhigh,max}`, `impl-opus-{xhigh,max}`, `impl-fable-{low,medium,high,xhigh,max}` | Human override, or the reserve chain after a split is spent |
| Role agents (3) | `judge-fable`, `judge-opus`, `scout-sonnet` | Review and approach-ranking seats |

Nineteen agents. Reserve agents are never an output of scoring: no assignment
table row names one, and no ordinary escalation edge targets one.

### The reserve table

A new fenced `reserve` block in `reference/ladder.md`, parsed by the test suite
the same way the existing blocks are:

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

Three properties matter.

**`impl-opus-high` is the single entry edge, and it is conditional.** That agent
appears as a source in both tables: its successor is `SPLIT` on first
exhaustion, and `impl-opus-xhigh` only once the split has been taken and a half
has exhausted too. The condition is what keeps the reserve out of ordinary work
- the graph, not a convention, enforces that a task reaches Fable only after
splitting has been tried and failed.

**The Sonnet rungs rejoin the execution ladder.** `impl-sonnet-max` succeeds to
`impl-opus-high`, not into the Fable region. A human who hand-assigns
`impl-sonnet-max` and watches it stall still gets `impl-opus-high` and its split
before anything reaches the top of the reserve.

**Every reserve agent is a source exactly once**, so a human override of any of
the nine has a defined successor. Without this, hand-assigning `impl-fable-low`
would produce a task with nowhere to escalate.

### Termination

Extend the existing rank function: efforts rank `low` 0 through `max` 4, and
models rank Haiku 0, Sonnet 1, Opus 2, Fable 3, with
`rank = model * 10 + effort`. Every edge in both tables strictly increases rank,
so both graphs are acyclic and every walk terminates - the escalation table at
`SPLIT`, the reserve table at `BLOCKED`. Neither terminal is an agent.

Ranking Fable above Opus puts `impl-fable-low` (30) above `impl-opus-max` (24),
which is a claim about the reserve chain traversal order rather than a claim
that Fable at low effort out-thinks Opus at max. `impl-fable-low` is reachable
only by a human ruling, and its successors climb Fable from there; nothing
auto-dispatched crosses that edge.

### Retirement is over

The `retired` block is deleted. All nine names resolve natively again, so a
0.1.0 plan naming `impl-fable-max` now runs at the tier it recorded instead of
being clamped to `impl-opus-high`. The mapping step in the dispatching skill and
its failure-mode row go with it.

`ladder.test.sh` gains an assertion that no `retired` block exists, so a stale
table cannot rot back in unnoticed.

The spec-3 legacy floor is unaffected and stays as written.

## Changes by file

**`reference/ladder.md`** - add the reserve table and its rationale; extend the
rank definition to `xhigh`, `max`, and Fable; delete the retired-agent map;
rewrite the terminal-rung section so `SPLIT` is followed by the reserve rather
than by BLOCKED.

**`agents/`** - restore nine files in the existing house style, each pinning its
model and effort and preloading `superpowers:verification-before-completion`.
`impl-fable-max` carries the true top-rung language: no more capable implementer
exists above it, so the controller reports BLOCKED. `impl-opus-high` keeps its
split language and gains a sentence noting the controller holds a reserve beyond
the split.

**`skills/assigning-implementers/SKILL.md`** - one paragraph stating that
reserve agents exist, are never a scoring output, and are legal only as a
hand-edited override. Its check widens from "appears in the assignment table" to
"appears in the assignment or reserve table".

**`skills/dispatching-tiered-implementers/SKILL.md`** - the post-split terminal
becomes entry into the reserve chain instead of BLOCKED, recorded as a `Ruling:`
line naming the reserve tier; the retired-agent mapping step and its
failure-mode row become a reserve row; the model-pin supersession covers sixteen
implementers rather than seven.

**`scripts/tier-nudge.sh`** - the `subagent-driven-development` context string
drops its retired-agent-map mention.

**`tests/fleet.test.sh`** - expand to 19 agents; add a reserve list; allow
`xhigh` and `max` efforts and the `fable` model for reserve implementers only,
still forbidding both for the seven.

**`tests/ladder.test.sh`** - add reserve-block coverage reusing the existing
rank and walk machinery; assert the retired block is gone; leave the assignment
and escalation assertions untouched, since neither table changes.

**`README.md`** - nineteen agents in three classes; rewrite the paragraph
claiming `xhigh` and `max` are retired everywhere and Fable never implements.

**`.claude-plugin/plugin.json`** - version 0.3.0.

## Testing

The four existing suites are the acceptance criteria. `ladder.test.sh` proves
the tables are internally consistent and both graphs terminate; `fleet.test.sh`
proves every agent file matches its name and class; `hook.test.sh` and
`criteria.test.sh` must keep passing unchanged - neither asserts on the part of
the hook context string this design edits.

The invariants worth stating explicitly, because they are what this design
promises:

- No assignment table row above score 6.
- No ordinary escalation edge targets a reserve agent.
- `impl-opus-high` is the only source appearing in both the escalation and
  reserve tables.
- Every reserve agent appears exactly once as a reserve source.
- Every walk of either table terminates without cycling.
