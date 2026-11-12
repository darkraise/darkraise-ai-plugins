# Wording-pin deletion and register close-out

**Register:** `docs/dforge/registers/2026-11-10-tdd-and-lifecycle-review.md`, rows 16, 20, 21 and 22 (rows 2 and 3 close on this plan's finish).
**Execution strategy:** sequential — inline execution
**Depth:** standard — interface

## Decisions

- **Process:** architectural, depth standard, triggers `interface` (the test-quality lens's `Applies:` line is read by `lens-route` and `review-record` for every plan) and `asked` (the ruling of 2026-11-12 asks for one spec).
- **Rulings:** every ruling is the Fable ruling seat's of 2026-11-12, made under the owner's delegation ("resolve all remaining items by using fable to review and make the decision"). No approach question is open; the design approval is that ruling.
- **Work order:** `docs/dforge/notes/2026-11-12-wording-pin-deletion-list.md` is the deletion list. Its header (R1-R7, the added dependencies, the task split) overrides the count below it. A task that cites a part of it by heading is complete as written.
- **Delegation:** the deletion tasks are mechanical and long, so the session dispatches each to a `dforge:impl-sonnet-medium` agent with the work-order part and runs the task's checks itself.

Early CI: none

Finish: pr

Worktree: in-place

## Problem

- Row 22: about 2,241 assertions in 55 dforge test files check a skill's wording that no script reads, against the rule "a sentence in a skill gets a test only when a script consumes it". They break on every rewording and add run time while catching no fault.
- Row 16: the test-quality lens's `Applies:` globs `*tests/*`, `*test/*` and `*test_*.py` match `latest/`, `contest/`, `protests/` and `latest_news.py`, because bash `case` lets `*` cross `/`. Those paths route the lens and count as test lines in the retained Test ratio.
- Row 20: `review-depth-qa.acceptance.test.sh` A8's `lens_lines` ignores the call's status, so a timed-out `lens-route` reads as "0 lens lines".
- Row 21: `typed-seats-and-drafting.acceptance.sh` A13 asserts on the developer's state directory, worktree list and branch names, which fail locally on any name containing a common word and test nothing in CI.

## Design

1. `plugins/dforge/criteria/lenses/test-quality.md` line 3 becomes `Applies: paths tests/* */tests/* test/* */test/* *__tests__/* *.test.* *_test.* *.spec.* test_*.py */test_*.py`.
2. `review-depth-qa.acceptance.test.sh`: `lens_lines` prints `status=<n>` when the last call's status is non-zero, else the count. `review-depth.acceptance.test.sh` A8's counted `timeout 60` calls put their status in the checked value.
3. `typed-seats-and-drafting.acceptance.sh` A13 loses its three host-state checks (state directory, worktree list, branch list).
4. The work order's DELETE rows are deleted as amended by R1-R7: nine whole files go (`delegated-suite`, `final-phase`, `impl-clauses`, `parallel-grouping`, `readme-unattended`, `waiting-text`, `project-status`, `distilling-docs`, `migrate-skill`), sentence-pin tests in `evals/tiers/tests` go by rule (R6), format-contract and file-shape checks stay (R1, R3). Dependents change in the same task: suites that read a deleted file, `scripts/test-all.mjs` part lists, `scripts/test-shards.mjs` weights, `plugins/dforge/README.md` lines naming deleted suites.
5. No test is added except the row 16 table case. Tests: one table case in `tests/review-record.test.sh` catches a glob that over-matches or under-matches a test directory; every other task deletes and adds no behaviour.

## Acceptance

A1. [test, high] `review-record ratio` over one commit adding one line to each of `latest/a.txt`, `contest/b.txt`, `protests/c.txt`, `src/latest_news.py`, `test/a.txt`, `pkg/test/b.txt`, `tests/c.txt`, `pkg/tests/d.txt`, `test_e.py` and `pkg/test_f.py` prints `Test ratio: 6 test / 4 code lines (...)`.
A2. [test, high] `lens-route --final` over a change set whose only file is `latest/a.sh` prints no `lens test-quality` line, and over one whose only file is `pkg/test/a.sh` prints one.
A3. [demo, high] With a `timeout` shim on `PATH` that exits 124, a `review-depth-qa` A8 lens-count check fails with `got: [status=124]`.
A4. [demo, high] With a local branch named `scratch-row21-check`, `typed-seats-and-drafting.acceptance.sh A13` passes.
A5. [demo, high] For every edited suite, the set of passing labels after the change is a subset of the set before it, with 0 failed; nothing was added or reworded except A1's case.
A6. [demo, high] Outside `docs/`, no file names any of the nine deleted suites or a removed part id.
A7. [demo, high] Every assertion left in `plugins/dforge/tests` and `evals/tiers/tests` that reads a file under `skills/`, `reference/`, `criteria/`, `agents/` or `README.md` is a direct read of a script-parsed form (R1, with its script line), a file-shape check (R3), or a fixture.
A8. [demo, high] `node scripts/test-all.mjs`, `node scripts/validate-repository.mjs`, `claude plugin validate` on the marketplace and dforge, and `claude plugin test plugins/dforge` pass, and `Validate marketplace` is green on every job of the pushed commit.
