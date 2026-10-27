# dforge: fewer review rounds, faster plans, shorter returns

**Source:** owner request of 2026-10-26 (book-intel plan of 148 tasks in darkcloud)
**Covers:** docs/dforge/specs/2026-10-26-faster-plans-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Reduce number of review round | docs/dforge/plans/2026-10-26-faster-plans.md | A5-A13, A17 | done | - |
| 2 | reduce time to implement/execution a plan. For example, I ask to add epub fixing and novel world building using LLM, and it created plan with 148 tasks (in darkcloud), with current execution approach of dforge (run-review-test-fix-review, etc...) it will take weeks to finish | docs/dforge/plans/2026-10-26-faster-plans.md | A1-A4, A13-A16, A22 | done | closed by the owner on 2026-10-27, who will verify the wall-clock drop on a real run; A1-A4, A13-A16 and A22 pass in the acceptance suite |
| 3 | Reduce token when sub-agent return back to main agent | docs/dforge/plans/2026-10-26-faster-plans.md | A18-A21 | done | - |
| 4 | Task 1: golden's "stripping removes no code" return has no test (evals/tiers/lib/cases.mjs:96) | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 5 | Task 1: build-manifest.mjs --slices ends in a mid-module process.exit(0) that can cut off async stdout | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 6 | Task 1: decide.mjs gives a slice total outside 5-8 an undefined assigned arm and an endless INCOMPLETE verdict | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 7 | Task 2: plan-lint says the ladder gate block is missing when only max_score is absent | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 8 | Task 2: plan-revise's survey skip at reducible 6 has no test that isolates it from the max_score check | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 9 | Task 2: the report's claude plugin validate run had a pre-existing ICON_MISSING warning | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 10 | Task 3: the past-cap stderr message is not asserted in review-route.test.sh (only the exit code) | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 11 | Task 3: the slice.md total-8 plan-round checks duplicate the light.md checks | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 12 | Task 3: one rewrapped line in criteria/plan-review.md runs about 88 characters | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 13 | Task 3: the Exit: comment atop review-route omits that a plan round past the cap exits 2 | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 14 | Task 4: a split task with some parts scored takes the scored part's tier, while an unscored part alone gets review=task; no test pins it | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 15 | Task 4: no test covers an unscored task that carries an Executor line | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 16 | Task 5: cannot-verify: the unchanged helpers (route_field, budget_of, prompt_text, fill, $state/$ws) behave as do_hold and do_group assume | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 17 | Task 5: cannot-verify: exit 6 in review --group for a member with no step file or no heldHead | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 18 | Task 5: the "prompt names the group" test greps 1,2,4, which the package path also contains, so it proves nothing beyond the placeholder check | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 19 | Task 5: a second hold after a group review overwrites heldHead without a ledger line | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 20 | Task 5: review-package logs one extra budget-observation row per group member | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 21 | Task 5: hold on a task started in a batch exits 6 because it has no step file | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 22 | Task 6: cannot-verify: a group member's complete line range ends at its held head, not its fix commits | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 23 | Task 6: next-step uses sort -un and paste -sd, which the Global Constraints list does not name (awk could replace both) | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 24 | Task 7: escalation.md "one successor per further exhaustion" no longer defines exhaustion under the two-round cap | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 25 | Task 7: the older-run round-4 test checks only the exit code and stderr, not that no prompt was written and state is unchanged | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 26 | Task 7: the executing-plans Recovery row for Codex R/5 is pinned by no names check | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 27 | Task 8: parallel-waves.md Session budget still says "integrate the wave" where §5 is now "Close the wave" | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 28 | Task 8: one reflowed line in parallel-waves.md §4 runs about 150 characters | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 29 | Task 8: task-8-report.md header says Status: DONE where the outcome was DONE_WITH_CONCERNS | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 30 | Task 9: task-9-report.md header says Status: DONE where the outcome was DONE_WITH_CONCERNS | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 31 | Task 10: cannot-verify: exit 3 and exit 4 for every id passed to verdict | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 32 | Task 10: rereview silently stops recording when the recorded .reviewCheck.cwd directory is gone, and verdict then blames a predated review step | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 33 | Task 10: plan-amend reports any non-3 awk failure as "no closed New fence" | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 34 | Task 11: Codex change 4's JSON where values (Task N, header) differ from the new "Task N:" / "header:" one-liner rule | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 35 | Task 11: no seats check pins the change-3 exception sentence | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 36 | Task 12: the comment above the acceptance-check copy no longer lists README.md | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 37 | Task 13: README paragraph at lines 96-99 is ragged-wrapped to keep a test phrase on one line | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 38 | Task 13: the settings-skills "no five-round loop" regex misses "Rounds 4 and 5", "five-round" and "stalled progress" | - | - | n/a | closed unfixed by the owner on 2026-10-27 |
| 39 | A8 acceptance test: the four-held case leaves a review=task task as the next open task, so next-step's held-count branch is untested (faster-plans.acceptance.test.sh line 562: mark Tasks 2, 4, 5 and 8 complete so the next open task is the review=group Task 9, and add an absent assertion for '(Start\|Resume) at Task 9' after line 565) | - | - | done | fixed in e0fa3430; with the four-held trigger disabled both A8 assertions fail |
