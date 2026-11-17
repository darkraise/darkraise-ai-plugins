# Scoring rubric, split gate and execution floor

The raw axis definitions are shared across hosts; Rule S's threshold is set by
host below. The unweighted totals, the execution floor table and the external
judge rungs here apply to Claude. Native Codex uses
[native-codex.md](native-codex.md) and its weighted `codex-v4` score.
The fenced blocks below are parsed by `tests/dforge/ladder.test.sh` in the repository; keep them machine-readable.

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

**If `reducible >= 6`, or if `spec = 3`, the task must be split or re-designed.
Do not assign a larger model.** That is the gate on a Claude plan, whose code
tasks carry their test contracts and interfaces but not their implementation and so
score 2 on spec completeness.

A `Host: codex` plan keeps `reducible >= 4` as its gate:
[native-codex.md](native-codex.md) derives its weighted 0-9 score from
`reducible <= 3`, and `codex-routing.json` ranks stop at 9. `scripts/plan-lint`
applies the gate by host.

`spec = 3` means prose only with the approach undecided. That is not a
model-selection problem; it is a design decision nobody made. Route it to
dforge:selecting-approaches, settle the approach, rewrite the
task with the decision in it, and re-score. The task will then score 0, 1, or 2
on that axis like every other compliant task.

Rule S caps a compliant Claude total: `reducible <= 5` and `spec <= 2`, so
`total <= 5 + risk(3) = 8`. **The floor table's ceiling is a consequence
of Rule S, not a separate choice.**
A computed total of 9 or more means the gate was skipped, not that a higher
tier is needed.

## Execution floor table

The session implements every task, so the plan's `**Execution:**` line must
carry a model and effort that can do the hardest one. `scripts/plan-lint` reads
the highest total's row: a Sonnet session may take totals 0 to 5, Opus is
needed for 6 to 8, and the row's effort is the least the line may name (a
risk-3 task raises it to `high`). Two planners scoring a task identically
always reach the same row.

```assignment
0 sonnet low
1 sonnet low
2 sonnet low
3 sonnet medium
4 sonnet medium
5 sonnet high
6 opus high
7 opus high
8 opus high
```

A Claude plan written to dforge:writing-plans gives each code task its test
contracts and interfaces but not its implementation, so a code task scores 2
on spec completeness and is drawn as a feature slice up to `reducible <= 5`. A Codex
plan still carries the code, so its tasks score 0 or 1 there.

Do not inflate an axis to land on a row that feels right; if a task feels harder
than its score, the plan text is probably hiding something, and the fix is a
better task description or a smaller task.

## External review rungs

An external model never implements a task. Each registered reviewer has one
judge block, named by `blocks.judge` in its registry entry and read at runtime
by its review runner.

### Codex judge rung

Every Claude-hosted Codex review seat — the task seats, plan-review round 1,
and the final-review round — takes its model from this block. The first row is
preferred; the last row is the fallback. `--tier light` runs the last row
directly, for tasks totalling 0 to 8 below risk 3; every other seat (risk 3,
plan review, the final round) uses the first row with its fallback. Totals 4
to 6 moved from Astra to the light row on 2026-10-07, when `gpt-6.1-sol`
replaced `gpt-6-sol` there, at about a fifth of Astra's price.

```codex-judge
gpt-6-astra xhigh 5400
gpt-6.1-sol xhigh 2400
```

The effort and the bound move together. At `high` with 1800 seconds the
largest plan in the 2026-09-20 calibration exceeded the bound on both
attempts and was never reviewed, so the one plan carrying that run's planted
defects produced no evidence. Raising the effort without raising the bound
would only buy more `TIMEOUT` rows, because more thinking takes more wall
clock on exactly the plans that already ran out of it.

The two rows carry different bounds. `gpt-6-astra/xhigh` runs the heavy seats,
so its 5400 is set for whole plans and branches. `gpt-6.1-sol/xhigh` runs the
light tier and keeps the 2400 it carried when the same pair also bounded task
execution.

`gpt-6-astra` is the rung `reference/codex-routing.json` already floors native
judges at, so both hosts now judge at the same tier. This plugin reads no model
catalog: `scripts/run-codex-review.sh` attempts the first row and falls back
once to the last row on a refusal, which is the only evidence of entitlement
that has ever been reliable.

The judge bounds are provisional operational budgets, not derived figures. Two
measurements exist: a `gpt-5.6-sol/high` whole-branch round at roughly four
minutes on 2026-09-14, and `project-state` completing at `gpt-6-astra/xhigh`
inside 3600 on 2026-09-21 after exceeding 1800 twice at `high`. The astra row
was raised to 5400 on 2026-09-21 for headroom above that single completion, on
the owner's instruction; nothing measures where its ceiling actually is.
Revise them when real runs warrant it.

### Agy judge rung

Every agy review seat takes its model from this block, read by
`scripts/run-agy-review.sh`. The first row is preferred; the last row is the
fallback and the light tier, which runs it directly. A heavy task review, a
plan review and a final review use the first row with one fallback to the
last on a refused model, and a `claude-*` row whose Claude quota is out runs
the last row instead. The bounds copy the Codex rows of the same tier.

```agy-judge
claude-opus-5-5 high 5400
gemini-4-argon high 2400
```

The Claude quota on Antigravity is small: the 2026-11-03 calibration drained it
after about 500k tokens. A review that finds it out runs the Gemini row, so a
drained quota costs a seat its preferred model, never its review.

## API-billed ruling judges

An auto run tries these budgets, in this order, before the subscription's
`judge-opus` seat, through `scripts/run-api-judge`. The whole chain has 2400
seconds, and a row gets its own seconds or what is left of them, whichever is
less.

```api-judge
anthropic claude-opus-5-5 medium 1800
openai gpt-6-astra xhigh 1800
agentrouter gpt-6-astra xhigh 1800
```
