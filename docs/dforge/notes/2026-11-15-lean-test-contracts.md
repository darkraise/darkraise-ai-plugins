# Lean test contracts (M2)

Run 2026-11-15 on branch `auto/measured-proposals`, checking the plan format of
`461e2cc3` (P7): a Claude plan's Step 1 carries test contracts (C7) instead of
test code. For four past tasks, Step 1 was rewritten as contracts from the
plan's own test code, one `dforge:impl-sonnet-high` seat wrote the tests from
the brief and header of that plan copy alone (each in a scratch clone at the
task's base, writing only its output files), and the session checked the
seat's tests against the task's real commit.

## Tasks

| Run | Task | Base | Commit | Test files Step 1 writes | Step 2 suites |
|---|---|---|---|---|---|
| 1 | `2026-11-14-api-decisions-keep-warm-hydrogen` Task 2 | `6e5f4a10` | `12f6d957` | `api-spend.test.sh` (new), `dforge-config.test.sh` (rows) | both |
| 2 | `2026-11-14-api-decisions-keep-warm-hydrogen` Task 3 | `12f6d957` | `f38bc950` | `fixtures/stub-decisions/server.mjs`, `decide.test.sh` (both new) | `decide.test.sh` |
| 3 | `2026-11-13-reviewer-only-externals` Task 1 | `35325795` | `147082bf` | `fixtures/stub-agy/agy` (modes), `agy-review.test.sh` (new) | `agy-review.test.sh` |
| 4 | `2026-11-13-reviewer-only-externals` Task 4 | `5b361920` | `c8a18191` | `plan-lint.test.sh`, `executors.test.sh`, and the deletions in `faster-plans` and the inline-* suites | `plan-lint.test.sh`, `executors.test.sh` |

They are the first two tasks of each plan whose Step 1 is `Write the failing
test` and whose commit `git log` finds by subject. A test file is every file
under `tests/` that Step 1 writes, fixtures included; every other file the
commit changed is a non-test file.

## Coverage mapping

Each contract replaces one `# ---` section of the original Step 1 (or, where
the suite has none, one group of checks), and every assertion in that section
appears in the contract's asserted results with its exact string, exit code or
value. Fixture code (helpers, stub servers, stub modes) became a fixture
paragraph stating its exact outputs.

| Run | Assertion calls before | Original section → contract |
|---|---|---|
| 1 | 51, plus 6 `ROWS` lines | closed by default, A10, open/add/spent, the spend file, the lock, usage, the library, the price table, A8 → the contract of the same name; the six rows → `dforge-config.test.sh::ROWS` |
| 2 | 47 (the A2 and A4 tables expand at run time) | the stub server → fixture paragraph; A1, A2, A3, A4 and A5 (split into an A4 and an A5 contract), usage, A8 → the contract of the same name |
| 3 | 36 | the stub agy additions → fixture paragraph; light review; heavy and its fallback; the write/commit/stash loop; the quota, error and timeout cases; plan and final kinds; usage → one contract each |
| 4 | 5, plus the executors and deletion prose | each plan-lint check → its own contract; the two shipped-entry cases → two contracts; the deletion sentence kept as written |

## Line counts

Step 1 from its heading to Step 2, before (the plan's test code) and after
(contracts):

| Run | Lines before | Lines after | Bytes before | Bytes after |
|---|---|---|---|---|
| 1 | 152 | 17 | 9103 | 6468 |
| 2 | 224 | 18 | 14323 | 7568 |
| 3 | 139 | 12 | 8373 | 5264 |
| 4 | 22 | 13 | 1452 | 2654 |

Contract lines are long; bytes are the fairer measure. Runs 1 to 3 shrink by
29%, 47% and 37%; run 4, whose original was mostly prose, grows by 83%.

## Checks

Each check ran the plan's Step 2 suites under `timeout 600` in the run's clone,
the test files swapped in by copying: the contract version is the seat's, the
plan version `git show <commit>:<file>` (a file the commit does not have is
absent). (a) At the base with the contract version, the suites must fail. (b)
With every non-test file from the commit and the contract version, they must
pass. (c) For each non-test file reverted alone to the base (deleted when the
task created it), whenever the plan version fails the contract version must
fail too. In (a) and (b) the plan version ran as a control; it failed and
passed alike in every run. Script: [`2026-11-15-lean-test-contracts-check.sh`](2026-11-15-lean-test-contracts-check.sh), run per task as `M2_SCRATCH=<clones dir> M2_WORK=<seat outputs dir> bash <script> <n> <base> <commit> "<test files>" "<Step 2 suites>"`.

| Run | (a) contract / plan | (b) contract / plan | (c) |
|---|---|---|---|
| 1 | fail / fail: PASS | pass / pass: PASS | PASS: 5 files; the plan version failed for 4, the contract version for the same 4 |
| 2 | fail / fail: PASS | pass / pass: PASS | PASS: 3 files; both failed for `decide` and `lib/decisions.mjs`, both passed for `test-shards.mjs` |
| 3 | fail / fail: PASS | pass / pass: PASS | PASS: 8 files; both failed for the schema, `ladder.md`, `worktree-snapshot.sh` and `run-agy-review.sh`, both passed for the other 4 |
| 4 | fail / fail: PASS | pass / pass: PASS | PASS: 9 files (the commit's fixtures count as non-test files, since Step 1 does not write them); both failed for both shipped entries, `scripts/executors`, `plan-lint` and the codex fixture, both passed for the other 4 |

Run 2's first pass is not counted: the script copied the seat's `server.mjs`
into a directory the base does not have, the copy failed, and the contract runs
used the plan's server. The script now creates the directory first; the rerun
above had the seat's file in place.

## Result: kept

The keep rule holds: all four tasks passed every check, so `461e2cc3` stays.
In no reverted file did the plan's tests fail while the contract tests
passed, and the contract tests went red at the base and green at the commit
like the plan's. Register row 5 is done.

## Limits

The contracts were written from finished, passing tests, by the session that
read them, so M2 shows an upper bound: a planner writing contracts before any
test exists has less to go on. Four tasks from two plans, one seat run each.
One contract's "fails today" clause was wrong (run 4, "the External
executors header is accepted silently" passes at the base, as the plan's own
check does), which the seat reported; the check is a guard, not a red test.
The seats read the base checkout, so a contract left vague could be filled
from neighbouring suites, as a real implementer can.
