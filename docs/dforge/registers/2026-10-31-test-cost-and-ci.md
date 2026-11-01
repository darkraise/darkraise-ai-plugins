# Test cost and CI failures

**Source:** chat request 2026-10-31 (recommendations A, B, C from the test-bloat research)
**Covers:** docs/dforge/specs/2026-10-31-test-tiers-and-ci-parity-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | A: change how often the suite runs (tiered runs: focused and impact-selected per task, full suite per wave or group and final review, full sweep in CI) | docs/dforge/plans/2026-10-31-test-tiers-and-ci-parity.md | A1-A7, A23, A25 | doing | - |
| 2 | B: write fewer tests in the first place | docs/dforge/plans/2026-10-31-test-tiers-and-ci-parity.md | A8-A10 | doing | - |
| 3 | C: make cleanup routine and cheaper | docs/dforge/plans/2026-10-31-test-tiers-and-ci-parity.md | A11-A13 | doing | - |
| 4 | also update test-simplifier to achieve same as this plan | docs/dforge/plans/2026-10-31-test-tiers-and-ci-parity.md | A14 | doing | - |
| 5 | after implement a feature, CI run always failed and need lots of effort to fix. I want to prevent it as well. | docs/dforge/plans/2026-10-31-test-tiers-and-ci-parity.md | A15-A22, A24, A26, A27 | doing | - |
| 6 | Final review follow-up: one escaping rule for a single quote in bash -c '<cmd>' used by final-review.md step 1, finishing Step 1 and execute-choice.md | - | - | deferred | final-residual res-1, ruled PARK: Minor, not a CI or behaviour break |
| 7 | Final review follow-up: committed tests for the extra plan-lint rules (waves Integration check, after-task on a waves plan, long digit string, fenced Covered by) and the ci-mirror malformed-line paths | - | - | deferred | final-residual res-2, ruled PARK: the rules beyond the spec were checked by hand |
| 8 | Final review follow-up: delete the remote branch with one git push --force-with-lease=<branch>:<sha> origin :<branch> instead of an ancestor check and a separate delete | - | - | deferred | final-residual res-3, ruled PARK: a race window only |
