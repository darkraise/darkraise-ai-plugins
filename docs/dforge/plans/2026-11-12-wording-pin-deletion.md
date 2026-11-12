# Wording-Pin Deletion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dforge's suites stop pinning skill wording that no script reads, the test-quality lens's globs stop matching non-test directories, a timed-out lens-route call reports as a timeout, and A13 stops asserting on the developer's host state.

**Architecture:** One data-line fix in `criteria/lenses/test-quality.md` with one table test; one test-helper fix; then mechanical deletion of the approved wording pins, part by part, following the work order `docs/dforge/notes/2026-11-12-wording-pin-deletion-list.md`, with each task updating the suites, part lists and README lines that depend on what it deletes.

**Tech Stack:** Bash scripts and bash test suites, Node test suites under `evals/`, Markdown criteria.

**Spec:** docs/dforge/specs/2026-11-12-wording-pin-deletion-design.md

**Execution:** inline — `claude --model opus --effort high` — the hardest tasks total 6

**Parallelism:** sequential — inline execution

**Task check:** none — full suite every 3 tasks

**Integration check:** `timeout 1500 node scripts/test-all.mjs --jobs 6 && timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate . && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge`

**CI:** `.github/workflows/validate.yml` — platforms: uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/test-all.mjs`; `node scripts/validate-repository.mjs`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: uutils (ubuntu-latest), Windows Git Bash

## Global Constraints

- English only in code, comments, docs, commits and tests.
- Commits are `<type>(<scope>): <subject>`, subject at most 50 characters, authored as `Darkraise <quangtc94@gmail.com>`, with no AI attribution of any kind.
- No code comment unless the why is non-obvious; never reference this task or plan in a comment.
- Nothing is pushed before finishing.
- Do not edit historical plans or specs (`docs/dforge/plans/*` and `docs/dforge/specs/*` other than this plan and its spec).
- The work order's header (R1-R7, dependencies, task split) overrides its count. Line numbers in it are for 1675af60: find each row by its label and target, and delete from the highest line down within a file.
- A task deletes assertions and the helpers, fixtures and comments only they use; it rewords no surviving assertion and adds none, except Task 1's table case. A surviving suite keeps at least one assertion; a suite left with none is deleted with its dependents.
- Pass labels: before a task, the session holds each suite's sorted `ok   - <label>` lines (Node: `✔ <name>`) from the pinned baseline at 6ecbad1b. After the task every touched suite exits 0 with 0 FAIL, and its labels are a subset of the baseline's.
- Every test or suite command runs under `timeout`.
- Windows Git Bash and uutils: deletion adds no new command; any line a task must change (a part list, a sourced helper) keeps the constructs the file already uses.

## Contracts

- **test-quality `Applies:`:** `Applies: paths tests/* */tests/* test/* */test/* *__tests__/* *.test.* *_test.* *.spec.* test_*.py */test_*.py`. `lens-route` (`lens_match`) and `review-record ratio` read it with bash `case` semantics.
- **`lens_lines` (review-depth-qa):** prints `status=<n>` when the last `lr` call's status is non-zero, else the count of `^lens ` lines.

## Assumptions (evidence)

- No script or test pins the test-quality glob text; `criteria.test.sh` 61 accepts the new clause (Fable ruling 2026-11-12, searched). unverified — Task 1 runs `criteria.test.sh`.
- The count's line numbers match 1675af60 for the four passages the ruling seat checked; the rest are unverified and found by label.
- `scripts/test-all.mjs` 91 and 96 list suite part ids that Task 4 and Task 2 remove (ruling, Dependencies).

## Task index

1. test-quality globs match test directories only
2. Delete dependents and meta-pins (part g0, R6)
3. Delete parts g1 and g2, and A13's host checks
4. Delete part g3 and report lens-route timeouts
5. Delete part g5, first eight files
6. Delete part g5, remaining files
7. Delete part g6a
8. Delete part g6b
9. Weights, README lines and the final sweep

---

### Task 1: test-quality globs match test directories only

**Files:**
- Modify: `plugins/dforge/criteria/lenses/test-quality.md` (line 3)
- Modify: `plugins/dforge/tests/review-record.test.sh` (one table case)

**Items:** 16
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

In `review-record.test.sh`, beside its existing `ratio` cases and with its helpers, add one case: a throwaway repository with a base commit and one commit adding one line to each of `latest/a.txt`, `contest/b.txt`, `protests/c.txt`, `src/latest_news.py`, `test/a.txt`, `pkg/test/b.txt`, `tests/c.txt`, `pkg/tests/d.txt`, `test_e.py`, `pkg/test_f.py`; check that `review-record ratio BASE HEAD` prints a line beginning `Test ratio: 6 test / 4 code lines (`.

- [ ] **Step 2: Run it and see it fail**

Run: `timeout 300 bash plugins/dforge/tests/review-record.test.sh`
Expected: the new case FAILs with `10 test / 0 code`.

- [ ] **Step 3: Implement**

Replace line 3 of `criteria/lenses/test-quality.md` with the Contracts line. Any fixture that relied on the loose match moves to a real test directory.

- [ ] **Step 4: Run the checks**

Run: `for s in review-record retained-review-data.acceptance lens-route test-volume-rules.acceptance criteria review-depth.acceptance review-depth-qa.acceptance; do timeout 600 bash plugins/dforge/tests/$s.test.sh | tail -1; done`
Expected: every suite prints `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/criteria/lenses/test-quality.md plugins/dforge/tests/review-record.test.sh
git commit -m "fix(dforge): match test directories only"
```

### Task 2: Delete dependents and meta-pins (part g0, R6)

**Files:**
- Modify: `plugins/dforge/tests/speed-and-cost.acceptance.test.sh`, `plugins/dforge/tests/speed-and-cost-followups.acceptance.test.sh` (part g0)
- Modify: `plugins/dforge/tests/auto-default.test.sh` (161-162, 165-172 only)
- Modify: `evals/tiers/tests/test-tiers-and-ci-parity.acceptance.test.mjs`, `evals/tiers/tests/speed-and-cost.acceptance.test.mjs` (R6)
- Modify: `scripts/test-all.mjs` (part lists naming removed ids)

**Items:** 22
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 1 = 5

- [ ] **Step 1: No new test, because the task only deletes assertions and adds no behaviour; the remaining suites are the existing checks**

- [ ] **Step 2: Read the work order**

Read the work order's header and `# PART g0`, plus `## 4-pre`. R6: read each candidate `test(...)` body before deleting; delete one only when every assertion matches text read from `plugins/dforge/{skills,reference,criteria,agents}`, `README.md` or another test file; keep any test that runs a script. Delete the A2 sentence-split check of both suites with `REWORDED`, `REMOVED`, `norm` and `SPLIT`. Delete `test-tiers-and-ci-parity.acceptance.test.mjs`'s test reading `tests/delegated-suite.test.sh` (line 232).

- [ ] **Step 3: Delete**

Delete the approved rows and the helpers only they use. Record the number of removed `test(...)` blocks per file.

- [ ] **Step 4: Run the checks**

Run each touched suite alone under `timeout 900` (`bash` for `.sh`, `node --test` for `.mjs`). Expected: exit 0, 0 failed, pass labels a subset of the baseline.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge/tests evals/tiers/tests scripts/test-all.mjs
git commit -m "test(dforge): drop meta and sentence-split pins"
```
The body lists the removed counts per file and any R1-kept row with its script `file:line`.

### Task 3: Delete parts g1 and g2, and A13's host checks

**Files:**
- Modify: `plugins/dforge/tests/plan-revise.test.sh`, `criteria.test.sh` (78-81 only, R3) (part g1)
- Modify: `plugins/dforge/tests/clean-session-phases.acceptance.test.sh`, `task-loop-steps.acceptance.test.sh`, `task-step-base.test.sh`, `task-step-settle.test.sh`, `task-step-suite.test.sh`, `task-step-text.test.sh`, `typed-seats-and-drafting.acceptance.sh` (part g2)

**Items:** 21, 22
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 1 = 5

- [ ] **Step 1: No new test, because the task only deletes assertions and adds no behaviour; the remaining suites are the existing checks**

- [ ] **Step 2: Read the work order**

Header, `# PART g1`, `# PART g2`. Apply R1's recheck list to `task-step-text.test.sh` 81-82, 131-133, 204-205, 208, 230-231, 268-269, `task-step-settle.test.sh` 30-31 and `clean-session-phases` 183-185: keep a row only when its needle is a line form a script matches, with the script's `file:line` found by `rg` under `plugins/dforge/scripts` or `plugins/dforge/hooks`.

- [ ] **Step 3: Delete**

Delete the approved rows. In `typed-seats-and-drafting.acceptance.sh` A13 also delete the state-directory, worktree-list and branch-list checks (lines 169-171 at 1675af60); the tracked-content checks stay.

- [ ] **Step 4: Run the checks**

Run each touched suite alone under `timeout 900`. Expected: exit 0, 0 failed, labels a subset of the baseline. Then `git branch scratch-row21-check && timeout 300 bash plugins/dforge/tests/typed-seats-and-drafting.acceptance.sh A13; git branch -D scratch-row21-check`. Expected: 0 failed.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge/tests
git commit -m "test(dforge): drop g1 and g2 wording pins"
```

### Task 4: Delete part g3 and report lens-route timeouts

**Files:**
- Modify: `plugins/dforge/tests/faster-plans.acceptance.test.sh`, `review-depth-qa.acceptance.test.sh`, `review-depth.acceptance.test.sh`, `review-route.test.sh` (part g3)
- Delete: `plugins/dforge/tests/project-status.test.sh` (R5)
- Modify: `scripts/test-all.mjs` (part lists), `plugins/dforge/README.md` (the line naming `project-status.test.sh`)

**Items:** 20, 22
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 1 - coupling 2 - risk 1 = 6

- [ ] **Step 1: No new test, because the task deletes assertions and changes only a test helper's failure text; the A8 checks are the existing checks**

- [ ] **Step 2: Read the work order**

Header, `# PART g3`. R1 keeps `faster-plans` 514 and 644-646 only with a script line; R4 deletes the spec reads in both review-depth suites and `review-route` 826-835; R2 adds `review-route.test.sh` 510, 511, 514, 515.

- [ ] **Step 3: Delete, then fix the helper**

Delete the approved rows and `project-status.test.sh`; drop removed part ids (`a1`, `a14`, `a15`, `a16`, `A6` as they apply) from `scripts/test-all.mjs` 91 and 96 and from each suite's `ALL`/dispatch list. Then in `review-depth-qa.acceptance.test.sh` change `lens_lines` to the Contracts form, first confirming every use follows a call expected to exit 0; in `review-depth.acceptance.test.sh` A8, where a `timeout 60` call's output is counted, capture `rc` and put it in the checked value as A16 does.

- [ ] **Step 4: Run the checks**

Run each touched suite alone under `timeout 900`. Expected: exit 0, 0 failed, labels a subset of the baseline. Then run review-depth-qa once with a `timeout` shim on `PATH` that exits 124 (not committed). Expected: an A8 lens-count check FAILs with `got: [status=124]`.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge/tests scripts/test-all.mjs plugins/dforge/README.md
git commit -m "test(dforge): drop g3 pins, report lens timeouts"
```

### Task 5: Delete part g5, first eight files

**Files:**
- Modify: `plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh`, `auto-default.test.sh`, `auto-run-skills.test.sh`, `auto-run-worktree-setting-qa.acceptance.test.sh`, `auto-run-worktree-setting.acceptance.test.sh`, `budget-line.test.sh`, `inline-mode.test.sh`, `inline-only-execution.acceptance.test.sh`

**Items:** 22
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 1 = 5

- [ ] **Step 1: No new test, because the task only deletes assertions and adds no behaviour; the remaining suites are the existing checks**

- [ ] **Step 2: Read the work order**

Header, `# PART g5` sections for these eight files. R1: the `format contract` rows stay. R2 adds `inline-mode.test.sh` 177 and `inline-only-execution.acceptance.test.sh` 266. R4 confirms `auto-default` 175-180.

- [ ] **Step 3: Delete**

Delete the approved rows and the helpers only they use.

- [ ] **Step 4: Run the checks**

Run each touched suite alone under `timeout 900`. Expected: exit 0, 0 failed, labels a subset of the baseline.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge/tests
git commit -m "test(dforge): drop g5 wording pins, first half"
```

### Task 6: Delete part g5, remaining files

**Files:**
- Modify: `plugins/dforge/tests/inline-only.acceptance.test.sh`, `process-roles.test.sh`, `seats.test.sh`, `settings-skills.test.sh`, `ui-ux-skill.acceptance.test.sh`, `ui-ux-skill.test.sh`

**Items:** 22
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 1 = 5

- [ ] **Step 1: No new test, because the task only deletes assertions and adds no behaviour; the remaining suites are the existing checks**

- [ ] **Step 2: Read the work order**

Header, `# PART g5` sections for these six files. R2 adds `ui-ux-skill.test.sh` 27-28 and `inline-only.acceptance.test.sh` 227-228. R3 keeps `process-roles` 53-55 and 201, `settings-skills` 105-109, `seats` 49-50. `seats.test.sh` loops are narrowed, not deleted.

- [ ] **Step 3: Delete**

Delete the approved rows and the helpers only they use.

- [ ] **Step 4: Run the checks**

Run each touched suite alone under `timeout 900`. Expected: exit 0, 0 failed, labels a subset of the baseline.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge/tests
git commit -m "test(dforge): drop g5 wording pins, second half"
```

### Task 7: Delete part g6a

**Files:**
- Modify: `plugins/dforge/tests/ladder.test.sh`, `agy-gemini-first.acceptance.test.sh`, `gates-manifest.test.sh`, `fleet.test.sh`, `executors.test.sh`, `executor-recovery.test.sh`, `codex-review.test.sh`, `hook.test.sh`, `dforge-config.test.sh`, `dforge-dir.test.sh`
- Delete: `plugins/dforge/tests/delegated-suite.test.sh`, `final-phase.test.sh`, `impl-clauses.test.sh`, `distilling-docs.test.sh` (R5)
- Modify: `plugins/dforge/README.md` (the line naming `distilling-docs.test.sh`), `scripts/test-all.mjs` if it names a deleted file

**Items:** 22
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 1 = 5

- [ ] **Step 1: No new test, because the task only deletes assertions and adds no behaviour; the remaining suites are the existing checks**

- [ ] **Step 2: Read the work order**

Header, `# PART g6a`. R3 keeps `gates-manifest` 83-132. R4 adds `agy-gemini-first` 355-358. R7: fix the `fleet.test.sh:43` label's agent count to the number the check counts.

- [ ] **Step 3: Delete**

Delete the approved rows, the four files, and the helpers only they use.

- [ ] **Step 4: Run the checks**

Run each touched suite alone under `timeout 900`. Expected: exit 0, 0 failed, labels a subset of the baseline (the fleet label aside).

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge/tests plugins/dforge/README.md scripts/test-all.mjs
git commit -m "test(dforge): drop g6a wording pins"
```

### Task 8: Delete part g6b

**Files:**
- Modify: `plugins/dforge/tests/lanes.test.sh`, `test-simplifier.test.sh`, `lane-breaker.test.sh`, `native-routing.test.sh`, `working-directory.test.sh`, `turn-end.test.sh`, `worktree-instructions.test.sh`
- Delete: `plugins/dforge/tests/waiting-text.test.sh`, `parallel-grouping.test.sh`, `readme-unattended.test.sh`, `migrate-skill.test.sh` (R5)

**Items:** 22
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 1 = 5

- [ ] **Step 1: No new test, because the task only deletes assertions and adds no behaviour; the remaining suites are the existing checks**

- [ ] **Step 2: Read the work order**

Header, `# PART g6b`. R4 adds `lanes.test.sh` 358-359 and the calibration assertions in 363-436, keeping 397-410.

- [ ] **Step 3: Delete**

Delete the approved rows, the four files, and the helpers only they use.

- [ ] **Step 4: Run the checks**

Run each touched suite alone under `timeout 900`. Expected: exit 0, 0 failed, labels a subset of the baseline.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge/tests
git commit -m "test(dforge): drop g6b wording pins"
```

### Task 9: Weights, README lines and the final sweep

**Files:**
- Modify: `scripts/test-shards.mjs` (weights of the nine deleted files)
- Modify: any file the sweep finds naming a deleted suite or removed part id, outside `docs/`

**Items:** 22
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

- [ ] **Step 1: No new test, because the task removes stale references and adds no behaviour; test-shards.test.mjs is the existing check**

- [ ] **Step 2: Sweep**

Run: `rg -n 'delegated-suite|final-phase\.test|impl-clauses|parallel-grouping|readme-unattended|waiting-text|project-status\.test|distilling-docs\.test|migrate-skill\.test' --glob '!docs/**'`
Expected after the step: no match.

- [ ] **Step 3: Remove**

Remove the nine weights from `scripts/test-shards.mjs` and every match the sweep found.

- [ ] **Step 4: Run the checks**

Run: `timeout 600 node --test tests/test-shards.test.mjs && timeout 1500 node scripts/test-all.mjs --jobs 6`
Expected: both exit 0.

- [ ] **Step 5: Commit**

```bash
git add -A scripts plugins
git commit -m "chore(dforge): drop deleted suites' weights"
```
