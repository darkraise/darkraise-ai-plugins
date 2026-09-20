# Review fixes deferrals — item register

**Source:** deferrals in the 1.11.0 whole-plugin review fixes spec, §12
**Covers:** docs/superpowers/specs/2026-09-17-dr-superpowers-review-fixes-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | M3: a leftover Evaluation line above `#### Part A` is counted by `plan_scores` and `review-route` | - | A split task scores from its part bodies only | open | Over-routes, never under-routes; deferred on 2026-09-17 with no successor recorded |
| 2 | A split-into-parts amendment applied then re-linted has no test | - | `plan-amend` applies a split and `plan-lint` accepts the result, in one test | open | Deferred on 2026-09-17 |
| 3 | No test covers paths with spaces or non-ASCII characters | - | One suite drives a plan under a path with a space and a non-ASCII character | open | Deferred on 2026-09-17 |
