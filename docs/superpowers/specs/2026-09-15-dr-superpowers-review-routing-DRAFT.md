# Review routing and the external lane — APPROVED DESIGN (draft)

> **Status:** design approved in chat 2026-09-15; not yet a spec. The next
> session turns this into
> `docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md`
> via dr-superpowers:brainstorming's "Write design doc" step, then
> dr-superpowers:writing-plans. Nothing here is implemented.

**Sub-project 8** of `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`,
whose seven sub-projects were recorded complete on 2026-09-15. The program
design needs an amendment adding this one.

**Goal:** cut Claude quota spent on review seats without losing what those seats
catch, and actually use the Codex implementer lane that 51 eligible tasks
bypassed.

## Owner decisions (from the 2026-09-15 session — binding)

1. **Codex is the default task reviewer**, using both `gpt-5.6-sol` and
   `gpt-6-astra`. Sonnet and Opus judges become the *fallback* seats, not the
   primary ones.
2. **Risk >= 2 uses Fable with Astra**: Astra reviews, then Fable reviews the
   diff itself *and* verifies Astra's findings in the same pass — explicitly so
   that no extra verification round is needed.
3. **Every Codex path must check availability first** and degrade to its named
   Claude seat. Must-have, stated twice.
4. **Self-review is not acceptable**: a task carrying an `**Executor:**` line
   (it ran on Codex) is reviewed by a Claude judge, never by Codex.
5. **plan-lint gets a lazy availability probe** (option A of the lane-check
   question), with `--no-probe` for CI.
6. **Codex takes plan-review round 1**, Fable only on fallback.
7. **Calibration before trust**: replay the four plans that carry recorded Fable
   scores and gate on agreement.

## 1. Task review routing

| Condition | Reviewer | Quota |
|---|---|---|
| Score 0-3, no `Executor:` line | `codex gpt-5.6-sol / high` | ChatGPT |
| Score 4-6, no `Executor:` line | `codex gpt-6-astra / high` | ChatGPT |
| Task has an `**Executor:**` line | Claude judge for its tier | Claude |
| Risk >= 2 | Astra reviews -> Fable reviews *and* verifies | both |
| Codex unusable | 0-1 `judge-sonnet-high`; 2-4 `judge-opus-high`; 5-6 `judge-fable` | Claude |

The `Executor:` row preserves the no-self-review property the current design
depends on: the lane gate is `min_score 2 / max_risk 1`, so Codex already
implements tasks scored 2-4, and without this row it would review its own work.

## 2. The risk >= 2 seat

1. Astra reviews the diff -> findings.
2. Fable receives the diff **and** Astra's findings; returns its own findings
   plus CONFIRMED/REJECTED on each of Astra's. One call, no reconcile round.

**Prompt-structure requirement:** Fable must form its own findings *before*
reading Astra's, or it anchors on Astra's framing and stops being an independent
seat. The prompt has to enforce the ordering.

**Open, for the spec to settle:** this replaces today's three-seat average for
risk 3. Two consequences:
- Scoring becomes Fable's verdict with Astra's findings folded in, rather than a
  mean of three seats.
- The `risk3-spread` ruling item (a criterion whose three scores spread by more
  than 6 points) no longer has three seats to spread across. Either it is
  retired, or it is redefined against the two-seat shape.

## 3. Plan review

| Round | Seat | Reads |
|---|---|---|
| 1 | `codex gpt-6-astra / high` | the whole plan |
| 2+ | `judge-opus` | the delta since the last round, plus the prior findings |
| Codex unusable | `judge-fable` round 1, substitution said aloud | the whole plan |

This is A1 (delta rounds) + A2 (Opus for re-checks) + D (Codex round 1) combined.
Rounds are NOT cut: measured evidence says round 3 earns its place — it caught a
cross-task interface defect (a helper defined in Task 3, called only in Task 11)
and two vacuously-passing assertions.

## 4. Availability, as a binding rule

Every Codex seat resolves through `scripts/detect-executors.sh` before dispatch
and degrades to its named Claude seat when `usable` is false, saying the
substitution aloud and recording it in the ledger. Precedent exists:
`scripts/run-codex-review.sh` already does this and reports `FAILED` with the
roster's own `reason`.

## 5. Tooling changes

- **`plan-lint`**: lazy probe. Scan first; only if a gate-eligible task lacks an
  `**Executor:**` line, run the detector (+2.0s measured) and warn naming the
  rung. `--no-probe` keeps CI deterministic. Today plan-lint validates an
  Executor line when present (`plan-lint:214-221`) but never notices its absence.
- **`run-codex-review.sh`**: add `--kind plan`. `--kind task` is nearly free —
  the existing `risk3` kind already emits the task-review schema
  (`spec_verdict`, `task_quality`, `cannot_verify`), so this is an alias plus
  routing, not a new code path. Keep `risk3` accepted as an alias to avoid
  breaking SP7's contract.
- **New agent file**: `judge-sonnet-high`. `judge-opus` gains tier semantics
  alongside its existing "Fable unavailable" substitute role — both must be
  stated in the Seats table.
- **`docs/superpowers/distilled/constraints.md`**: one line declaring the Codex
  lane on for this repo, so the planner stops re-deciding per plan.

## 6. Gates before it ships

- **Calibration (D).** Replay the four plans carrying recorded `**Plan review:**`
  scores; ship only if Astra lands within +/-2 per axis *and* finds the known
  defects (the Task 3/Task 11 helper, the vacuous needles). Costs four Codex
  runs, no Claude quota, and is the only step that produces evidence.
- **Smoke test (C3).** One real task through `scripts/run-codex-task.sh` before
  trusting the lane with 51. The wrapper is untouched since Codex 0.153.4, the
  CLI is now 0.154.0, and it reports a CLI parse error as `BLOCKED` — which
  reads like a model that gave up rather than a CLI that refused.

## 7. Files this will touch

`reference/ladder.md`, `skills/writing-plans/`, `skills/subagent-driven-development/`,
`reference/external-executor.md`, `scripts/plan-lint`, `scripts/run-codex-review.sh`,
`agents/judge-sonnet-high.md` (new), `agents/judge-opus.md`,
`docs/superpowers/distilled/constraints.md`, the program design spec, plus the
affected suites (`lanes.test.sh`, `codex-review.test.sh`, plan-lint's suite).

## Evidence behind all of this (measured 2026-09-14/15)

- 24h notional spend ~$244; 19 of 23 subagent dispatches were `judge-fable`.
- Judge roles: plan review 10 (53%), spec review 5, final verify 2, ruling 2,
  per-task 0 (both sessions ran inline mode).
- Subagent-mode runs spend ~1 judge per implementer: SP3 14 judges / 13
  implementers; SP4 12 / 13.
- On SP3, 7 of 13 tasks scored 0-3 — including one `impl-haiku` task — and every
  one was reviewed by Fable 5 at high effort.
- Fable 5 bills $10/$50 per MTok; Opus 5 $5/$25; Sonnet 5 $2/$10.
- Cost composition: 68% cache reads, 17% cache writes, 12.8% output. Caching
  saved ~$1,025 (87%) over the same traffic uncached.
- 51 of 77 tasks in the last four plans met the lane gate; zero carried an
  `**Executor:**` line. Codex is usable here (cli 0.154.0, authenticated).
- `detect-executors.sh` runs in 2.0s; `plan-lint` in 4.6s.

## Explicitly not changing

- The 475k session budget (77% of cost sits at >150k context, but that is the
  owner's standing ruling after 200-250k proved worse).
- The 1-hour cache TTL.
- Ruling seat, final whole-branch verify, and spec review stay at Fable-high.
