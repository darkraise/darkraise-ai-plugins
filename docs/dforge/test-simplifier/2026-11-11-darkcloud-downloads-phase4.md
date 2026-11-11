# Test simplifier Phase 4: darkcloud downloads, 2026-11-11

Register row 8 of docs/dforge/registers/2026-11-10-tdd-and-lifecycle-review.md: one mutation-gated removal wave, approved by the owner on 2026-11-11, in the throwaway clone `/root/mutation-runs/darkcloud-downloads` (no remote). darkcloud itself is untouched; porting the wave there is the owner's call.

## Baseline

- Before report: the 2026-11-11 full-module run (docs/dforge/test-simplifier/2026-11-11-darkcloud-downloads.md), clone HEAD `dde303e0`, StrykerJS 10.1.1, `web/stryker.config.json` with `disableBail` and `ignoreStatic`. Copied to `.dforge/test-simplifier/downloads-phase4/before/mutation.json`.
- Downloads tests timed with `npx vitest run tests/downloads- --reporter=json` (four workers): 543 tests, 10.5 s summed file time. The 253 tests outside the greedy killing set take 2.6 s of test time in all, so removing every one of them would save almost nothing.

## Candidate selection

Most of the 253 mutation-redundant tests were not taken:

- Rows that each check one entry of a module-level map or status set (`statusLabel labels <status>`, `isFailureStatus classifies <status>`, `splitQueue treats <status> as active`, `downloadErrorMessage` per error code). `ignoreStatic` leaves those constants unmutated, so the report cannot see the one fault each row uniquely catches: a wrong label, message or membership. A `downloadErrorMessage` row is also the only test of its error path, which the never-removed rule protects.
- Rows at a boundary (`roughDuration` 1140, 3599 seconds), and rows exercising a distinct branch or input class.

Taken: five `parseChapterRange` table rows in `web/tests/downloads-submit.test.ts` whose input takes the same path to the same outcome as a kept row (class 2, near-duplicate examples, action: remove the row):

| Removed row | Kept row on the same path | Why the same path |
|---|---|---|
| refuses `""` | refuses `"   "` | both trim to empty at the first check |
| accepts `"2-8"` | accepts `"  2 - 8 "` | same split and bounds; the kept row adds the trim |
| refuses `" - "` | refuses `"-"` | both give an empty head and tail |
| refuses `"3-0"` | refuses `"5-2"` | `start > end` refuses both whatever the end bound check does |
| refuses `"abc"` | refuses `"+3"`, `"1.5"` | non-digit text fails the digit regex; the kept rows also catch a `Number`/`parseInt` fault |

The before report credits these rows (ids 1273, 1278, 1281, 1284, 1286) with 36 killed mutants, all in `src/features/downloads/lib/submit.ts`, and every one also has a killer outside the five. Predicted lost: 0. Never-removed check: no row names a fixed bug, guards a security check, or is the only test of its contract or error path, and no `gates.md` exists in darkcloud.

## Evidence

- Wave commit in the clone: `0ca6d99834d383f7c28449c9ab1c3a9055e20c1e`, `test(downloads): simplify chapter range tests`, one test file, two lines changed. `npx vitest run tests/downloads-submit.test.ts`: 45 passed (50 before).
- After run: `npx stryker run --mutate src/features/downloads/lib/submit.ts`, same configuration, 3 minutes 9 seconds, saved to `.dforge/test-simplifier/downloads-phase4/after/mutation.json`.

| submit.ts | Mutants | Killed | Timeout | Survived | NoCoverage | Ignored | Covered |
|---|---|---|---|---|---|---|---|
| before | 250 | 211 | 0 | 24 | 3 | 12 | 235 |
| after | 250 | 211 | 0 | 24 | 3 | 12 | 235 |

The mutant sets match by mutator, location and replacement; no mutant killed before is uncaught after, and covered mutants did not drop.

| Phase | `test-profile --brief` |
|---|---|
| baseline | not run: the speed goal is moot at 2.6 s of candidates; Phases 2 and 3 were not run |
| wave 1 | 5 tests removed, 0 mutants lost |

## Judge

Pending: dforge:judge-opus ruling on `0ca6d998`.
