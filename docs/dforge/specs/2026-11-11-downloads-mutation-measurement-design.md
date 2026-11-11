# Mutation measurement of darkcloud's downloads tests

**Register:** docs/dforge/registers/2026-11-10-tdd-and-lifecycle-review.md, row 1; its result feeds rows 8, 10 and 15, which stay `deferred` until it reports.
**Execution strategy:** sequential — inline execution
**Depth:** light — asked

## Decisions

- Process: the owner chose "Full dforge flow (Recommended)" over fast mode.
- Module: the register's 2026-11-10 ruling names darkcloud `web/src/features/downloads`. Asked why, the owner was told it is a sample of dforge-written tests in a real project, and answered "keep downloads, go ahead".
- Test scope: the owner chose "Whole web suite (Recommended)". Every Vitest test may kill a mutant, and the report counts downloads-* tests and all other tests separately. Rejected: running only `tests/downloads-*`, which hides kills by other files and so overstates how unique the downloads tests are.
- Run budget: an 8-hour hard timeout, narrowing to `transfers/` and `lib/` when the progress estimate exceeds it. The owner answered "Right" to A9 at the spec review.
- Analysis: a one-off Node script, embedded in the report so every count can be reproduced. Rejected: a maintained dforge script with its own tests. One run has not yet shown that the measurement is worth repeating, and row 8 can promote the script if Phase 4 needs it.
- Static mutants: `ignoreStatic: true`. A static mutant runs the whole suite under per-test coverage, and the report gives their count instead.

Early CI: none

Finish: merge

Worktree: in-place

## Problem

Row 1 says dforge creates too many tests, and nothing measures it. Line counts cannot tell a redundant test from a useful one; a mutation run with bail disabled can, because it records every test that kills each mutant. The run is measurement only: it deletes and edits no test (ruling 2026-11-10).

## Design

### Clone

- `git clone --no-hardlinks /root/repositories/darkcloud /root/mutation-runs/darkcloud-downloads`, outside `/root/repositories` and never a worktree of the project. The path is durable because row 8's Phase 4 wave reuses it.
- Record the clone's HEAD SHA, then `git remote remove origin` so nothing can be pushed back.
- In `web/`: `npm ci`, then `npm install --no-save @stryker-mutator/core@10.1.1 @stryker-mutator/vitest-runner@10.1.1`, and the generation steps the tests need (`npm run gen:routes`, `npm run gen:file-icons`).
- Baseline: `npx vitest run` in the clone is green. A red baseline stops the run, and the report lists the failing tests; no darkcloud test is fixed.

### Stryker configuration (`web/stryker.config.json`, in the clone only)

- `testRunner: "vitest"`, `coverageAnalysis: "perTest"`, `disableBail: true`, `ignoreStatic: true`.
- `mutate`: `src/features/downloads/**/*.ts` and `src/features/downloads/**/*.tsx`.
- `reporters`: `json`, `html`, `progress`, `clear-text`.
- `concurrency: 4`, lowered to 2 if the dry run leaves under 1 GB of memory free.
- The workspace's two projects (`dom`, `node`) run as darkcloud defines them.

### Run

1. `npx stryker run --dryRunOnly`. It must pass with both workspace projects reporting tests; it records the test count and the mutant count.
2. `timeout 8h npx stryker run`, started as a tracked background task. After 30 minutes, read the progress reporter's elapsed and remaining times. When their sum exceeds 8 hours, stop the run and restart it with `mutate` narrowed to `src/features/downloads/{transfers,lib}/**/*.{ts,tsx}`.
3. Copy `reports/mutation/mutation.json` to `<state>/test-simplifier/downloads-mutation/before/`, the Phase 4 "before" location.
4. Kill every process the run started and confirm none is left.

### Analysis

The Node script reads `mutation.json` (schema: `files.*.mutants[].status`, `coveredBy`, `killedBy`; `testFiles.*.tests[].id` and `name`). It never runs tests. Definitions:

- **Population:** every test in `testFiles`, split into *downloads* (files `tests/downloads-*`) and *other*.
- **Covering test:** appears in some mutant's `coveredBy`.
- **Kills nothing:** covering, but in no `killedBy`.
- **No unique kill:** kills at least one mutant, and every mutant it kills has another test in `killedBy`.
- **Greedy minimum killing set:** greedy set cover over Killed mutants. Each step picks the test that kills the most uncovered mutants, with ties broken by test id. The report gives the set's size and the tests outside it, per population.
- **A<n> test:** a test whose name begins with `A` followed by digits. For each one, the report checks whether every mutant it kills is also killed (a) by some test that is not an A<n> test (row 10), and (b) by another test in the same file with the same A<n> id (row 15).
- `Timeout` mutants count as caught but are attributed to no test, since Stryker names no killer for them. `Survived`, `NoCoverage`, `Ignored` and error statuses are counted only.

### Report: `docs/dforge/test-simplifier/<run date>-darkcloud-downloads.md`

It holds the environment (A1), the mutant status counts, the population counts, a per-file table for downloads-* files (tests, kills nothing, no unique kill, outside the greedy set), the A<n> counts, the embedded script with the command that ran it, and a short reading of what the numbers mean for row 1. It names candidates for row 8 and recommends no deletion.

### Plugin change

`plugins/dforge/skills/test-simplifier/references/runners.md`, under Mutation tools: most runners stop at a mutant's first killing test, so a report lists one killer. Finding tests no mutant needs takes bail disabled, which for StrykerJS is `disableBail: true` with `coverageAnalysis: "perTest"`; its Vitest runner handles a multi-project workspace.

### Register

Row 1's Note gets the headline counts and the report path, and the row moves to `verify`. Rows 10 and 15 get their counts in the Note; row 8's Note records that Phase 4 is ready to offer. Their states do not change.

## Out of scope

Deleting or merging tests (row 8), the TDD and review wording changes (batch B), and any other module or project.

## Acceptance

A1. [demo, high] The report names the darkcloud commit measured, the clone path, the Stryker, Vitest and Node versions, the full Stryker configuration, every command run and the run's wall time.
A2. [demo, high] Bail was really disabled: the report gives the number of Killed mutants with two or more tests in `killedBy`, and that number is above zero.
A3. [demo, high] The report counts, for downloads-* tests and other tests separately, the tests run, covering tests, tests that kill nothing, tests with no unique kill, and tests outside the greedy minimum killing set, with the set's size.
A4. [demo, high] The report counts A<n> tests whose every killed mutant another test kills, split into killed by a test that is not an A<n> test and killed by another test with the same A<n> id in the same file.
A5. [demo, high] Running the embedded script on the saved `mutation.json` reprints every count in the report.
A6. [demo, high] Timeout and ignored static mutants appear as counts and are attributed to no test.
A7. [demo, neg, high] `/root/repositories/darkcloud` is untouched: its HEAD and `git status --porcelain` match before and after, and the clone has no `origin` remote.
A8. [demo, neg, high] No darkcloud test is deleted or edited, in the clone or in the project.
A9. [demo, confirmed] When the progress estimate after 30 minutes exceeds 8 hours, the run is narrowed to `transfers/` and `lib/`, and the report states the narrowing and the estimate that triggered it.
A10. [demo, high] `runners.md` says that without bail disabled only a mutant's first killing test is recorded, and gives the StrykerJS settings.
A11. [demo, high] Register rows 1, 8, 10 and 15 cite the report as the Register section says, and row 1 is `verify`.
A12. [demo, neg, high] Once the report is written, no Stryker, Vitest or npm process started by the run is alive.

## Riskiest assumption

StrykerJS's Vitest runner records every killing test per mutant for darkcloud's two-project workspace. Partial evidence: `npm pack @stryker-mutator/vitest-runner@10.1.1` on 2026-11-11 shows `dist/src/vitest-test-runner.js:138` passing `bail: this.options.disableBail ? 0 : 1` to Vitest, and lines 145 and 278-294 iterating `ctx.projects` for tests and per-test coverage. Its peer range is `vitest >=2.0.0`, and darkcloud runs `^2.1.9`. Whether the dry run passes on this workspace, and whether the run fits 8 hours, is unverified — the plan's first task verifies it with `--dryRunOnly` and A2's count.
