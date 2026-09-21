# Review fixes deferrals — item register

**Source:** deferrals in the 1.11.0 whole-plugin review fixes spec, §12
**Covers:** docs/superpowers/specs/2026-09-17-dr-superpowers-review-fixes-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | M3: a leftover Evaluation line above `#### Part A` is counted by `plan_scores` and `review-route` | - | A split task scores from its part bodies only | done | Fixed by plan_eval_lines in scripts/lib/plan.sh: a split task scores from its part bodies only, and plan_scores, review-route and plan-lint all read through it |
| 2 | A split-into-parts amendment applied then re-linted has no test | - | `plan-amend` applies a split and `plan-lint` accepts the result, in one test | open | Deferred on 2026-09-17 |
| 3 | No test covers paths with spaces or non-ASCII characters | - | One suite drives a plan under a path with a space and a non-ASCII character | open | Deferred on 2026-09-17 |
| 4 | review-route read **Evaluation:** and **Executor:** lines without skipping fenced blocks, so a fenced example escalated the seat | - | A task holding a fenced example line routes on its real score | done | Found by the 2026-09-21 astra review of the revising-plans design; fixed with the split-task rule in the same shared helper |
