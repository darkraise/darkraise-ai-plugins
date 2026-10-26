# Slice-sized code-free tasks — 2026-10-26

**Verdict:** KEEP §1 - the assigned arm passed 5 of 5
**Decision rule:** four of five pass on the arm §1 assigns keeps §1; fewer stops the plan for a ruling.

Subject: 5 slice cases from `evals/tiers/cases/slices.tsv` (start `46cc416`), each two or three consecutive tasks of one plan from this repository's history merged into one brief with the implementation code stripped, scored under docs/dforge/specs/2026-10-26-faster-plans-design.md §1, and run on `impl-sonnet-high`, `impl-opus-medium` and `impl-opus-high` through `run-grid.mjs --stage slice` (repetition 1, run on 2026-10-26).

## Cases

| Case | Plan | Tasks | Total | Arm §1 assigns |
|---|---|---|---|---|
| `l-fold-companions-t3-4` | `2026-09-11-dr-superpowers-fold-companions.md` | 3, 4 | 6 | `impl-opus-high` |
| `l-standalone-base-t7-8` | `2026-09-11-dr-superpowers-standalone-base.md` | 7, 8 | 6 | `impl-opus-high` |
| `l-judge-seats-t3-4` | `2026-09-14-dr-superpowers-judge-seats.md` | 3, 4 | 7 | `impl-opus-high` |
| `l-project-state-t1-2` | `2026-09-14-dr-superpowers-project-state.md` | 1, 2 | 5 | `impl-sonnet-high` |
| `l-review-routing-t11-12` | `2026-09-15-dr-superpowers-review-routing.md` | 11, 12 | 7 | `impl-opus-high` |

## Results

| Case | Total | Assigned | `impl-sonnet-high` | `impl-opus-medium` | `impl-opus-high` |
|---|---|---|---|---|---|
| `l-fold-companions-t3-4` | 6 | `impl-opus-high` | PASS | PASS | PASS |
| `l-standalone-base-t7-8` | 6 | `impl-opus-high` | PASS | PASS | PASS |
| `l-judge-seats-t3-4` | 7 | `impl-opus-high` | PASS | PASS | PASS |
| `l-project-state-t1-2` | 5 | `impl-sonnet-high` | PASS | PASS | PASS |
| `l-review-routing-t11-12` | 7 | `impl-opus-high` | PASS | PASS | PASS |

No cell on the assigned arm failed.

## Spend

$11.11 notional over the 15 slice runs; the longest run took 345 seconds.
