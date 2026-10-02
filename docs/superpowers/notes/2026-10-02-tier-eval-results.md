# Tier evaluation results, repetition 1

Spec: `docs/superpowers/specs/2026-10-01-dr-superpowers-tier-eval-design.md`. Harness and data: `evals/tiers/`. Run: 2026-10-02 to 2026-10-02.

## What the rules produce

| Row or seat | Current | Verdict | Evidence |
|---|---|---|---|
| Row 1 | `impl-sonnet-low` | UNCHANGED | 7 trials, 0 regressions |
| Row 2 | `impl-sonnet-medium` | move: `impl-sonnet-low` (owner ruling, 0 stripped cases) | 8 trials, 0 regressions |
| Row 3 | `impl-sonnet-high` | move: `impl-sonnet-medium` (owner ruling, 1 stripped case) | 9 trials, 0 regressions |
| Row 4 | `impl-sonnet-high` | move: `impl-sonnet-medium` | 13 trials, 0 regressions |
| Row 5 | `impl-opus-medium` | move: `impl-sonnet-high` (owner ruling, 2 stripped cases) | 10 trials, 0 regressions |
| Row 6 | `impl-opus-high` | move: `impl-opus-medium` (owner ruling, 1 stripped case) | 2 trials, 0 regressions |
| Review seat | `judge-opus@high` | move: judge-opus effort high to medium | 18 of 40 defects, 0 Critical missed (current arm: 18 of 40) |
| Review seat | `judge-sonnet-high` | unchanged | 10 of 40 defects, 0 Critical missed |

## Case defect found in review

Three of the stripped cases cannot pass for any agent: `s-review-routing-t17`, `s-review-fixes-t8` and `s-execution-cost-t15`. A stripped snapshot has `docs/superpowers` deleted, but `plugins/dr-superpowers/tests/review-route.test.sh` checks files under `docs/superpowers/specs/` (for example lines 585 to 593), so that test fails on any stripped snapshot; `s-review-routing-t17` also lists a `docs/superpowers` file in its Files block, which both arms answered with `NEEDS_CONTEXT`. Re-running the test in the `s-review-fixes-t8` snapshot shows the `the program design ...` checks failing on the missing file. The golden check ran the tests on the full result tree, so it did not catch this. These cases account for every non-PASS row of the stripped stage (4 FAIL, 2 BLOCKED), and none of them is a regression. Rows 3 and 4 therefore have fewer usable stripped cases than the report counts: row 3 has 1 of its 3, and row 4 has 5 of its 6. The manifest was not rebuilt. By owner ruling the three cases are excluded from repetition 1 (three `EXCLUDED` rows in `results.tsv`), a departure from spec §1, which allows exclusion only for a run that cannot start. The verdicts above and the report below are the rules' output after the exclusion; no verdict changed, and row 3's flag for a second repetition, which rested on these cases, is gone.

## Owner rulings (2026-10-02)

- **Taken:** row 2 to `impl-sonnet-low`, rows 3 and 4 to `impl-sonnet-medium`, row 5 to `impl-sonnet-high`, and `judge-opus` effort high to medium.
- **Declined:** row 6 stays `impl-opus-high`. Two trials leave a true regression rate up to 100% possible, and no agent rung sits above it to absorb a wrong move.
- **Unchanged:** row 0 stays `impl-haiku` (no case), row 1 stays `impl-sonnet-low`, and `judge-sonnet-high` stays on totals 0 to 3 (10 of 40 defects against 18 for each Opus arm).
- **Escalation table:** unchanged. `impl-opus-medium` leaves the assignment table but stays an escalation rung, as `impl-opus-low` already is, and every agent keeps a successor.
- **No second repetition.** No row is INCONCLUSIVE and none is flagged after the exclusion. The harness defects found in review are deferred until a second repetition is scheduled; none of them changed a repetition 1 result (no timeout or NOT_RUN row, every implementation reply's first status word matches its `Status:` line, no duplicated grade). The repeat gradings covered the two code-review cases only, so grader consistency is unmeasured on plan reviews.

The taken moves go to the ladder update, register row 2, which gets its own spec.

## The report

# Tier eval - repetition 1

Start commit: `a271bda8f1b419f6e563daa2ea5ede82af95a05f`

## Implementer rows

### Row 1: UNCHANGED

| Arm | PASS | Of | Cost per PASS | Regressions |
|---|---|---|---|---|
| `impl-sonnet-low` | 7 | 7 | $0.12 | 0 |
| `impl-haiku` | 7 | 7 | $0.18 | 0 |

- 7 paired trials (0 stripped); zero regressions is consistent with a true regression rate up to 43%

### Row 2: MOVE to impl-sonnet-low - owner ruling, only 0 stripped cases

| Arm | PASS | Of | Cost per PASS | Regressions |
|---|---|---|---|---|
| `impl-sonnet-medium` | 8 | 8 | $0.12 | 0 |
| `impl-sonnet-low` | 8 | 8 | $0.10 | 0 |

- 8 paired trials (0 stripped); zero regressions is consistent with a true regression rate up to 38%

### Row 3: MOVE to impl-sonnet-medium - owner ruling, only 1 stripped cases

| Arm | PASS | Of | Cost per PASS | Regressions |
|---|---|---|---|---|
| `impl-sonnet-high` | 9 | 9 | $0.16 | 0 |
| `impl-sonnet-medium` | 9 | 9 | $0.13 | 0 |

- 9 paired trials (1 stripped); zero regressions is consistent with a true regression rate up to 33%
- excluded s-review-routing-t17: case defect: a stripped snapshot deletes docs/superpowers, which this case's tests or Files block need; owner ruling 2026-10-02
- excluded s-review-fixes-t8: case defect: a stripped snapshot deletes docs/superpowers, which this case's tests or Files block need; owner ruling 2026-10-02

### Row 4: MOVE to impl-sonnet-medium

| Arm | PASS | Of | Cost per PASS | Regressions |
|---|---|---|---|---|
| `impl-sonnet-high` | 13 | 13 | $0.17 | 0 |
| `impl-sonnet-medium` | 13 | 13 | $0.12 | 0 |

- 13 paired trials (5 stripped); zero regressions is consistent with a true regression rate up to 23%
- excluded s-execution-cost-t15: case defect: a stripped snapshot deletes docs/superpowers, which this case's tests or Files block need; owner ruling 2026-10-02

### Row 5: MOVE to impl-sonnet-high - owner ruling, only 2 stripped cases

| Arm | PASS | Of | Cost per PASS | Regressions |
|---|---|---|---|---|
| `impl-opus-medium` | 9 | 10 | $0.40 | 0 |
| `impl-opus-low` | 9 | 10 | $0.30 | 0 |
| `impl-sonnet-high` | 9 | 10 | $0.21 | 0 |

- 10 paired trials (2 stripped); zero regressions is consistent with a true regression rate up to 30%

### Row 6: MOVE to impl-opus-medium - owner ruling, only 1 stripped cases

| Arm | PASS | Of | Cost per PASS | Regressions |
|---|---|---|---|---|
| `impl-opus-high` | 2 | 2 | $0.54 | 0 |
| `impl-opus-medium` | 2 | 2 | $0.47 | 0 |

- 2 paired trials (1 stripped); zero regressions is consistent with a true regression rate up to 100%

## Review seats

| Arm | Found | Of | Under-graded | Verdict | Missed Critical |
|---|---|---|---|---|---|
| `judge-opus@high` | 18 | 40 | 6 | current | - |
| `judge-opus@medium` | 18 | 40 | 5 | SUPPORTED | - |
| `judge-sonnet-high` | 10 | 40 | 5 | NOT SUPPORTED | - |

Grader consistency: 1 disagreements on 30 repeated gradings - usable.

Notional spend: $63.29 over 183 runs.

## Every regression

None: every row has 0 regressions, meaning no case where the current arm passed and a cheaper arm did not. These rows were not PASS, and in each case the current arm failed too. The six stripped ones are explained by the case defect above, and their cases are now excluded:

- `w-darkmem-sync-client-t5`, `impl-opus-medium`, FAIL: status=DONE failed=plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs
- `w-darkmem-sync-client-t5`, `impl-opus-low`, FAIL: status=DONE failed=plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs
- `w-darkmem-sync-client-t5`, `impl-sonnet-high`, FAIL: status=DONE failed=plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs
- `s-review-routing-t17`, `impl-sonnet-high`, BLOCKED: status=NEEDS_CONTEXT failed=plugins/dr-superpowers/tests/review-route.test.sh
- `s-review-routing-t17`, `impl-sonnet-medium`, BLOCKED: status=NEEDS_CONTEXT failed=plugins/dr-superpowers/tests/review-route.test.sh
- `s-review-fixes-t8`, `impl-sonnet-high`, FAIL: status=DONE_WITH_CONCERNS failed=plugins/dr-superpowers/tests/review-route.test.sh
- `s-review-fixes-t8`, `impl-sonnet-medium`, FAIL: status=DONE_WITH_CONCERNS failed=plugins/dr-superpowers/tests/review-route.test.sh
- `s-execution-cost-t15`, `impl-sonnet-high`, FAIL: status=DONE_WITH_CONCERNS failed=plugins/dr-superpowers/tests/review-route.test.sh
- `s-execution-cost-t15`, `impl-sonnet-medium`, FAIL: status=DONE_WITH_CONCERNS failed=plugins/dr-superpowers/tests/review-route.test.sh

The six stripped rows fail because of the case defect above. The three `w-darkmem-sync-client-t5` rows fail one assertion of `pull.test.mjs` (`an edit darkmem has not moved past is push's to send`), and the other ten tests in that file pass. The case itself may be at fault; it was not investigated further, and it stayed in the pool.

## Limits of this evidence

- One repetition. Each row's note states the true regression rate its trial count still allows.
- As-written cases carry the plan's code, so they measure transcription, verification and cost, not problem-solving. Only the stripped cases measure the second, and rows 2, 3, 5 and 6 have fewer than four of them.
- A run could read the installed plugin or this repository on the same machine and find the historical answer. Nothing prevented it and no transcript was kept to check it.
- Cost is the CLI's notional API price, not a bill.
- The isolation probe showed `--setting-sources project` left the owner's global CLAUDE.md loaded; the fix (`c4a321a`, `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1`) also skips each snapshot's own CLAUDE.md, and connector instructions still reach every arm. No stage was re-run and no case was dropped.
- The effort setting could not be confirmed from the CLI output; the model could.
