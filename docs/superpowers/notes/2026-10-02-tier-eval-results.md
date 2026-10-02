# Tier evaluation results, repetition 1

Spec: `docs/superpowers/specs/2026-10-01-dr-superpowers-tier-eval-design.md`. Harness and data: `evals/tiers/`. Run: 2026-10-02 to 2026-10-02.

## What the rules produce

| Row or seat | Current | Verdict | Evidence |
|---|---|---|---|
| Row 1 | `impl-sonnet-low` | UNCHANGED | 7 trials, 0 regressions |
| Row 2 | `impl-sonnet-medium` | move: `impl-sonnet-low` (owner ruling, 0 stripped cases) | 8 trials, 0 regressions |
| Row 3 | `impl-sonnet-high` | move: `impl-sonnet-medium` (owner ruling, 3 stripped cases) | 11 trials, 0 regressions |
| Row 4 | `impl-sonnet-high` | move: `impl-sonnet-medium` | 14 trials, 0 regressions |
| Row 5 | `impl-opus-medium` | move: `impl-sonnet-high` (owner ruling, 2 stripped cases) | 10 trials, 0 regressions |
| Row 6 | `impl-opus-high` | move: `impl-opus-medium` (owner ruling, 1 stripped case) | 2 trials, 0 regressions |
| Review seat | `judge-opus@high` | move: judge-opus effort high to medium | 18 of 40 defects, 0 Critical missed (current arm: 18 of 40) |
| Review seat | `judge-sonnet-high` | unchanged | 10 of 40 defects, 0 Critical missed |

## Rulings left to the owner

- Row 2: the move to `impl-sonnet-low` rests on 8 as-written cases and no stripped case.
- Row 3: the move to `impl-sonnet-medium` rests on 3 stripped cases, fewer than the 4 the rules need.
- Row 5: the move to `impl-sonnet-high` rests on 2 stripped cases.
- Row 6: rests on two cases, one of them stripped.
- Row 0 has no case. On row 1 `impl-haiku` passed 7 of 7 with no regression, at $0.18 per PASS against $0.12 for the current `impl-sonnet-low`, so the rules leave row 1 unchanged because it saves nothing.
- Whether `judge-sonnet-high` may review above total 3 rests on whole-branch and plan reviews, not on task reviews. It found 10 of 40 defects against 18 for each Opus arm.

No row is INCONCLUSIVE.

## Proposed second repetition

- Row 3, with the next agent up from `impl-sonnet-high`: the report flags that `impl-sonnet-high` does not pass 2 cases.
- `impl-sonnet-xhigh` on row 5 is not proposed: `impl-sonnet-high` had no regression there.

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

### Row 3: MOVE to impl-sonnet-medium - owner ruling, only 3 stripped cases

| Arm | PASS | Of | Cost per PASS | Regressions |
|---|---|---|---|---|
| `impl-sonnet-high` | 9 | 11 | $0.21 | 0 |
| `impl-sonnet-medium` | 9 | 11 | $0.16 | 0 |

- 11 paired trials (3 stripped); zero regressions is consistent with a true regression rate up to 27%
- impl-sonnet-high does not pass 2 cases: second repetition with the next agent up

### Row 4: MOVE to impl-sonnet-medium

| Arm | PASS | Of | Cost per PASS | Regressions |
|---|---|---|---|---|
| `impl-sonnet-high` | 13 | 14 | $0.19 | 0 |
| `impl-sonnet-medium` | 13 | 14 | $0.14 | 0 |

- 14 paired trials (6 stripped); zero regressions is consistent with a true regression rate up to 21%

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

Notional spend: $63.29 over 180 runs.

## Every regression

None: every row has 0 regressions, meaning no case where the current arm passed and a cheaper arm did not. These rows were not PASS, and in each case the current arm failed too:

- `w-darkmem-sync-client-t5`, `impl-opus-medium`, FAIL: status=DONE failed=plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs
- `w-darkmem-sync-client-t5`, `impl-opus-low`, FAIL: status=DONE failed=plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs
- `w-darkmem-sync-client-t5`, `impl-sonnet-high`, FAIL: status=DONE failed=plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs
- `s-review-routing-t17`, `impl-sonnet-high`, BLOCKED: status=NEEDS_CONTEXT failed=plugins/dr-superpowers/tests/review-route.test.sh
- `s-review-routing-t17`, `impl-sonnet-medium`, BLOCKED: status=NEEDS_CONTEXT failed=plugins/dr-superpowers/tests/review-route.test.sh
- `s-review-fixes-t8`, `impl-sonnet-high`, FAIL: status=DONE_WITH_CONCERNS failed=plugins/dr-superpowers/tests/review-route.test.sh
- `s-review-fixes-t8`, `impl-sonnet-medium`, FAIL: status=DONE_WITH_CONCERNS failed=plugins/dr-superpowers/tests/review-route.test.sh
- `s-execution-cost-t15`, `impl-sonnet-high`, FAIL: status=DONE_WITH_CONCERNS failed=plugins/dr-superpowers/tests/review-route.test.sh
- `s-execution-cost-t15`, `impl-sonnet-medium`, FAIL: status=DONE_WITH_CONCERNS failed=plugins/dr-superpowers/tests/review-route.test.sh

The three `w-darkmem-sync-client-t5` rows fail one assertion of `pull.test.mjs` (`an edit darkmem has not moved past is push's to send`), and the other ten tests in that file pass.

## Limits of this evidence

- One repetition. Each row's note states the true regression rate its trial count still allows.
- As-written cases carry the plan's code, so they measure transcription, verification and cost, not problem-solving. Only the stripped cases measure the second, and rows 2, 3, 5 and 6 have fewer than four of them.
- A run could read the installed plugin or this repository on the same machine and find the historical answer. Nothing prevented it and no transcript was kept to check it.
- Cost is the CLI's notional API price, not a bill.
- The isolation probe showed `--setting-sources project` left the owner's global CLAUDE.md loaded; the fix (`c4a321a`, `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1`) also skips each snapshot's own CLAUDE.md, and connector instructions still reach every arm. No stage was re-run and no case was dropped.
- The effort setting could not be confirmed from the CLI output; the model could.
