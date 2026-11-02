# agy calibration for totals 0-2

Three completed tasks scored 0-2 were replayed through `scripts/run-agy-task.sh` with the real `agy` 1.4.12 from their parent commits: R1 impl-clauses (`docs/dforge/plans/2026-10-28-speed-and-cost.md` Task 3, original `236975e3`), R2 ui-lint (`docs/dforge/plans/2026-10-24-ui-ux-skill.md` Task 4, original `b977b6c6`) and R3 ui-ux-proof (the same plan's Task 5, original `d80f69c0`), to pick the cheapest rung that can carry the lane's lowest band. Candidates ran cheapest first (`gemini-3.8-flash/low`, `gemini-3.8-flash/medium`, `gemini-4-argon/low`), each stopping at its first failed run, and a run passed only when it ended DONE, its result passed the original commit's tests restored over it, it stayed inside the original write set without touching refs or the other checkouts, and a blind Claude judge returned `spec: pass` and `quality: approved`.

| Task replayed | Rung | Status | Tests | Scope | Judge | Wall s | Tokens |
|---|---|---|---|---|---|---|---|
| R1 impl-clauses | gemini-3.8-flash/low | blocked | n/a | clean | n/a | 90 | 54953 |
| R1 impl-clauses | gemini-3.8-flash/medium | DONE | pass | clean | pass | 230 | 106257 |
| R2 ui-lint | gemini-3.8-flash/medium | DONE | pass | clean | pass | 269 | 172572 |
| R3 ui-ux-proof | gemini-3.8-flash/medium | DONE | pass | clean | pass | 127 | 135271 |
| S1 plan-lint-header-lines | claude-sonnet-5-5/high | DONE | pass | clean | pass | 189 | 104108 |

- R1 on `gemini-3.8-flash/low` failed: the agent ended DONE with the replayed brief's 55-character commit subject, which breaks the contract's 50-character limit, so the wrapper refused to commit and blocked the task (`invalid commit subject`).
- R1 on `gemini-3.8-flash/medium`: the judge found 2 Minor issues, both in test text the brief mandates (a doubled clause and the clause order are checked loosely).
- R2 on `gemini-3.8-flash/medium`: the judge found 3 Minor issues in `ui-lint` (a missing file is skipped silently, one `focus-visible` suppresses every `outline-removed` finding in a file, `awk -v` mangles backslashes in a path).
- R3 on `gemini-3.8-flash/medium`: the judge found 1 Minor issue (test evidence summarised, not quoted with its exit status).
- S1 on `claude-sonnet-5-5/high`: the judge found 3 Minor issues (two test cases cover one form only, and an unrecognised Early CI point skips the consent check untested).

**Decision:** totals 0-2 run gemini-3.8-flash/medium - the cheapest candidate that passed all three replays, after gemini-3.8-flash/low failed R1.
**Smoke:** pass

## Results

- Ladder: `agy-assignment` rows 0-2 name `gemini-3.8-flash medium`, the `agy-successor` row `gemini-3.8-flash/medium claude-sonnet-5-5/medium` stands, and the `agy-timeout` row is `gemini-3.8-flash/medium 900`: three times the slowest passing run (269 s) is 807 s, rounded up to a multiple of 300 that is 900, the floor. These match the rows the ladder already carried, so no ladder row changed.
- Smoke: S1 (`docs/dforge/plans/2026-10-31-test-tiers-and-ci-parity.md` Task 3, total 5, original `d814996b`) ran at its Claude rung `claude-sonnet-5-5/high` under the `agy-timeout` bound of 1800 s, and passed: a 17788-byte brief with a TDD contract reached DONE inside its write set, its result passed `plan-lint.test.sh` (291 passed, 0 failed) with the original test file restored, and the judge approved it.

## Left in place

- `/tmp/agy-calibration.kqoubK/wt-R1-flash-low` (branch `calib/R1-flash-low`): the blocked R1 run on `gemini-3.8-flash/low`, holding its uncommitted edits.
