# Executor interface plan — review round 1

Plan reviewed: `docs/superpowers/plans/2026-09-21-dr-superpowers-executor-interface.md` @ `a14925c`.
Seat: `dr-superpowers:judge-opus` (`review-route` printed `primary=dr-superpowers:judge-opus reason=codex-off cap=2`; **codex off — untrusted**).
Run: 2026-09-21.

| executability | coherence | coverage | assumptions |
|---|---|---|---|
| 5 | 12 | 11 | 9 |

`plan-lint` reported 0 errors, so every finding below is something lint cannot
see. **All nine Criticals were verified against the files before being
accepted**; none was taken on the seat's word.

## What the seat confirmed as correct

Recorded so a later revision does not re-open them: Task 5 accounts for all
four `emit` call sites and every field the function sets; Task 7's awk produces
exactly the rows its own tests assert, including `heavy` beating `executor` and
the six-task threshold fixture; Task 6's four ERROR strings are byte-identical
for a Codex line once `$eid` is `codex`; and the header's own arithmetic is
right — Tasks 4 and 7 are the two heavy tasks, and 8 four-band of 18 exceeds a
third, which is what forces `--model opus --effort high`.

## Critical — all nine verified

| # | Task | Finding | Verified against |
|---|---|---|---|
| C1 | 6 | The stub's ladder blocks are unreachable. `ladder_block` hardcodes `reference/ladder.md`, which has no `stub-gate`/`stub-assignment`, so `executor_rung stub 2` is empty and the task's own "a stub Executor line is accepted" assertion fails. `tests/fixtures/stub-ladder.md` is read by nothing | `scripts/lib/plan.sh:70-72` |
| C2 | 6 | Both replacement ranges are wrong. The Executor branch is 271-283, not 272-284 — deleting 284 removes the outer `fi` and breaks the script. The warning comment is 294-299 and its `if` is 300; 301-303 are `roster=`, `usable=` and the inner `if`, which the replacement never restores | `scripts/plan-lint:271,283,284,299-303` |
| C3 | 1 | The malformed-JSON diagnostic is unreachable. Under `set -uo pipefail`, `id=$(jq … \| tr …) \|\| return 1` returns on jq's failure before the `printf` runs, so the stderr assertion gets 0 and wants 1 | logic of `scripts/executors` as drafted |
| C4 | 1 | The id-pattern case is self-defeating on NTFS: writing `Alpha.json` overwrites the existing `alpha.json`, so `list` prints only `beta` and the assertion fails | case-insensitive filesystem |
| C5 | 5 | The rewrite breaks `tests/detect.test.sh` wholesale. That suite seals `PATH` to shims for `jq timeout head tr node bash dirname cygpath`; `executors` also needs `basename` and `sort`, and the new dispatch needs `grep`. Without them `list` prints nothing and the codex row vanishes entirely | `tests/detect.test.sh:40-44` |
| C6 | 8 | The appended test uses `$TMP`, which the suite does not define — it has `DTMP` at line 233. Under `set -u` the suite aborts | `tests/inline-mode.test.sh:233` |
| C7 | 13 | The task asserts `absent` for "wrapper's own poll loop" and "codex-may-still-be-running", but both are still live and no step removes them. The preamble wrongly credits `a74f8e8`, which fixed the three §15 mismatches, not these two §10 defects | `reference/external-executor.md:94,241,246` |
| C8 | 16 | Step 5 deletes a sentence that two suites pin verbatim, and does not move the pins | `tests/inline-mode.test.sh:88`, `tests/review-route.test.sh:384` |
| C9 | 15 | Two "currently reads" blocks are not verbatim — line 55 continues "`. Run", line 166 continues "`**Implementer:**` lines are inert" — and the Step 4 target at `writing-plans/SKILL.md:265` does not exist: the word "inert" appears **zero** times in that file | `skills/executing-plans/SKILL.md:55,166`; `skills/writing-plans/SKILL.md:265` |

## Important

1. **Task 6** — the lane-eligible warning is not actually generalised as spec §6.2 requires. Step 5 renames the session call but leaves the candidate collection on Codex's `min_score`/`max_risk` and the roster read on `select(.id == "codex")`. Either implement the loop over `executors list` or move the deferral into §15 and the register.
2. **Task 5** — the prose says "replace the block from `if [ "$id" = codex ]` to its matching `else`" while the supplied code is the whole `emit` function. A literal executor splices a function into a function. Say "replace the whole `emit` function, lines 32-107".
3. **Tasks 8, 9, 11** — Step 2 passes rather than fails. Task 8's assertions all pass once Task 7 lands and its only edit is an unchecked comment; Task 9 states it adds no implementation; Task 11's assertions duplicate `executor-recovery.test.sh:111-117` and its real deliverable — the release instruction in `delegated-task.md` — has no assertion at all. Fold 8 and 9 into 7, and give 11 a prose check.
4. **Task 7** — `plan_executors`' awk uses `exit`, which `scripts/lib/plan.sh:92-94` documents as unsafe: the upstream writer takes SIGPIPE and under `pipefail` that becomes the caller's status, and `task-brief` runs `set -euo pipefail`. Use a `found` flag and print in `END`.
5. **Coverage** — spec §11's `writing-plans` row is unimplemented: the four-band definition at `skills/writing-plans/SKILL.md:121-134` (now contradicted by Task 7), the Execution-line model/effort paragraph §9.2 changes, the per-ticked-executor roster flow at line 234, and the one-Executor-line rule. `tests/inline-mode.test.sh:102-104` pin those sentences.
6. **Coverage** — spec §10's `delegated-task.md` wording is unaddressed. Task 14 rewrites only the path string; the "resumes its Codex session" sentences at lines 27, 50, 111, 196, 278 stay Codex-literal.
7. **Task 1 / Contracts** — the duplicate-id rule is dead and untested. Validity keys on `id == filename stem`, so two entries can never claim one id. Drop the clause, or define validity so it can occur.
8. **Task 13** — Step 6 expects "0 failed" while the rename it performs breaks eight path assertions in `review-route.test.sh` and three in `inline-mode.test.sh`. Merge 13 and 14 into one commit, or state the expected failure list.
9. **Task 15 Step 5** — two prose edits with no supplied text, gating two assertions. Give both replacement sentences verbatim.

## Minor

- Expected pass counts are wrong: Task 1's suite has 28 checks (plan says 26), Task 2 reaches 38 (says 36), Task 3 has 19 (says 20).
- Task 8's Files line says `scripts/task-brief:56-63` but the edit is at 47-48; Task 6's says `:191-194` where the edit is 191-193.
- Task 5's `STUB_LOCATOR=off regrun` relies on a temporary assignment propagating into a function's child and not persisting; bash 5.x changed this. Pass the mode as an argument or export/unset explicitly.
- Task 13's `present … 'two'` and `present … 'reaped'` are near-vacuous; quote the real sentences.
- Task 11 writes `scripts/run-<executor>-task.sh` while Tasks 13 and 17 resolve through `executors path <id> wrapper`; Contracts specifies the latter.
- Tasks 4 and 11 hard-code expected totals (54, 88, 181, 49) with no evidence of today's counts.
- The one `unverified` assumption names Task 2 as its verifier, but Task 2 proves only the stub's grammar; Task 5 is where the roster row is verified.

## Disposition

Round 1 returned Criticals, so round 2 is required (`cap=2`). The revision
touches Tasks 1, 5, 6, 7, 8, 9, 11, 13, 14, 15 and 16 — eleven of eighteen.
Not started in the session that produced this record.
