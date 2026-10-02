# Tier eval log

## Smoke stage

- Date: 2026-10-02
- Usage before: 1% (5-hour) / 0% (weekly). Usage after: 2% (5-hour) / 0% (weekly).
- Share of the weekly limit per run, as an upper bound: under 0.2% (the weekly figure stayed at 0% and is shown in whole percent, so the stage moved it by less than 1 point; 1 / 5 runs).
- Projected upper bound for the rest of the repetition: under 28% of the weekly limit (0.2% times 139 runs). The 5-hour window rose 1 point for the five runs, a rough guide only.
- Isolation probe: first probe, with `--setting-sources project` alone, listed the owner's global headings (Communication, Code, Process hygiene, Risky actions, Conventions, Memory), so the flag did not isolate. After setting `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` the reply was `## claude.ai Claude Docs` only, a connector's server instructions, with none of `Process hygiene`, `The Rule` or `Routing`.
- Budget probe: `exit=1`, `is_error=true subtype=error_max_budget_usd cost=0.020601`, `kind=budget`; a budget stop is settled as `BLOCKED`.
- Models reported: `impl-haiku` claude-haiku-4-5-20251001; `impl-sonnet-medium` and `judge-sonnet-high` claude-sonnet-5-5; `impl-opus-low` and `judge-opus@medium` claude-opus-5-5.
- Effort: not named in the output (the effort grep matched one review transcript, as text). Costs of the two review rows on `r-code-judge-seats`: `judge-sonnet-high` $0.4503, `judge-opus@medium` $0.8367.
- Outcomes: three implementation rows `PASS` with `status=DONE` (6, 15 and 6 turns); two review rows `REVIEWED`; grading `GRADED`, `judge-opus@medium` found 3/5. The `impl-sonnet-medium` snapshot holds a commit changing `run-codex-task.sh` and its test, so tools and permissions worked. Stage spend `1.86` notional dollars.
- Fixes made: `c4a321a` sets `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` for every run, because `--setting-sources project` left the user CLAUDE.md loaded. The snapshot's own CLAUDE.md is skipped as well, and connector instructions still reach every arm.

## As-written stage

- Date: 2026-10-02
- Outcomes (rep 1, stage `written`): PASS 82, FAIL 3; cost 14.88 notional dollars. Repetition total so far 16.73 (smoke included), against the 250 cap.
- The three FAIL rows are one case, `w-darkmem-sync-client-t5`, failing `plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs` on `impl-opus-medium` (the row's current arm), `impl-opus-low` and `impl-sonnet-high`. A failure on the current arm suggests the case itself may be at fault; not yet investigated.
- Fixes or re-runs: none; the stage finished in one slice with exit 0.

## Stripped stage

- Date: 2026-10-02
- Outcomes (rep 1, stage `stripped`): PASS 20, FAIL 4, BLOCKED 2; cost 6.37 notional dollars. Repetition total so far 23.10 against the 250 cap.
- Non-PASS rows are all `impl-sonnet-high` and `impl-sonnet-medium` on three cases, each failing `plugins/dr-superpowers/tests/review-route.test.sh`: `s-review-routing-t17` BLOCKED with `NEEDS_CONTEXT` on both arms; `s-review-fixes-t8` and `s-execution-cost-t15` FAIL with `DONE_WITH_CONCERNS` on both arms.
- Fixes or re-runs: none; the stage finished in one slice with exit 0.
