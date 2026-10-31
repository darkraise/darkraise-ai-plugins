# Test tiers, fewer tests and CI parity

**Execution strategy:** sequential — the owner asked for A, then B, then C; parts 1-5 share `skills/writing-plans/SKILL.md`, `reference/delegated-task.md` and `scripts/plan-lint`, and part 6 is small enough not to earn a wave.
**Depth:** standard — interface

## Decisions

- **Scope.** The owner chose recommendations A, B and C from the test-bloat research of 2026-10-31, in that order: "I want to do A then B then C, also update test-simplifier to achieve same as this plan." Register: `docs/dforge/registers/2026-10-31-test-cost-and-ci.md`, rows 1-5.
- **CI scope.** Question: "Where should the CI-failure prevention live?" Answer: "Both (Recommended)": "A generic dforge mechanism for every project: before finishing, read the CI workflow and run its local equivalent; plans name the platforms CI covers; after a push, wait for CI and treat red as not done. Plus checks specific to this repo: a static lint for known Git Bash pitfalls and a check that every suite has a shard weight and fits its time limit."
- **Repo suite.** Question: "Should this work also slim this repo's own test suite now?" Answer: "Skills only (Recommended)": "Change dforge's skills and scripts and add this repo's CI checks. Slimming this repo's suite becomes a later, separate test-simplifier run that uses the new process."
- **Per-task tier (A).** Question: "What should the controller run for each task?" Answer: "Two tiers (Recommended)": "`Task check:` fast command for each task; full suite at wave checks, final review and finishing; a passing run at the same commit is reused. If a project has no fast command, the full suite runs every 3 tasks instead of every task." Rejected: dropping the per-task controller run (do-less), and dforge working out which tests a diff affects by itself, per language.
- **CI mechanism.** Question: "For CI prevention in every dforge project: how far should dforge go?" Answer: "Three points + early run (Recommended)": "`CI:` plan line and portability constraints, local `ci-mirror` before the final review, wait for CI after the push, and an optional early CI run on the pushed branch with consent per plan." Rejected: waiting for CI after the push only (do-less).
- **Spec review (2026-10-31), shard rule.** Question: "What should part 6 do?" Answer: "Fix weights in the same task (Recommended)": "Part 6 also splits task-step.test.sh into parts, gives faster-plans a third part, and raises next-step and auto-run to 700 s, so the check is green at merge."
- **Spec review (2026-10-31), CI wait.** Question: "Which finish paths should wait for CI?" Answer: "Wait when finishing pushed (Recommended)": "Wait after a pull request or an early-CI push of the final head. After a local merge, print the exact `gh run list --commit` / `gh run watch` lines to run after you push, without calling the branch CI-green."
- **Spec review (2026-10-31), A7.** Answer: "300 seconds (Recommended)".
- **Spec review (2026-10-31), A13.** Answer: "20% growth (Recommended)".
- **Execution strategy.** No `executionStrategy` setting is in force and `autoRun=on` does not ask; sequential, for the reason on the line above.

Finish: merge

## Problem

Measured on 2026-10-31:

- The full suite runs once per task. Subagent mode starts it beside every review of a task, of a group, and of each fix round (`reference/delegated-task.md`, "The suite runs beside the review"). A red run starts a second full run at the base commit to separate new failures from old ones. Inline mode runs it before every task's commit (`skills/executing-plans/SKILL.md`, step 4). Wave checks, the final review, the fix wave and finishing add more runs. A 10-task plan with a one-hour suite spends most of a day on suite runs.
- Every plan task opens with "Step 1: Write the failing test" (`skills/writing-plans/SKILL.md`), and TDD's "Good Tests" table says "One thing. 'and' in name? Split it." Tests grow one task at a time, and narrow tests are kept after a broader test written later covers them. Nothing removes tests except `test-simplifier`, which nobody runs routinely.
- In this repository, 22 of the last 60 `Validate marketplace` runs failed. Almost all of them failed in the Windows shards. The fixing commits name two causes: Git Bash path and tool quirks that a Linux run cannot show (`MSYS_NO_PATHCONV` with `jq.exe`/`git.exe`, `/c/` against `C:/`, gawk `-v` escapes, ESM `D:/` imports), and suites growing past shard or suite time limits (`99a06ae1`, `26952102`, `ae852f07`). dforge itself never reads CI configuration and never waits for a CI run.

## Design

### 1. Test tiers in the default flow (A, register row 1)

There are three tiers. One shared reference, `reference/test-tiers.md`, defines them and holds the impact-selection table now in `skills/test-simplifier/references/runners.md`. `runners.md` points to it instead of keeping a copy.

| Tier | Command source | Runs |
|---|---|---|
| Task check | the plan header's `**Task check:**` line | beside every task review, every fix round, and inline before every task commit |
| Full suite | the plan header's `**Integration check:**` line | each wave's merged check, tasks whose number is a multiple of 3 (and the last task) when the task check is `none`, the final review, the fix wave, finishing |
| Sweep | the project's CI | after push (part 5) |

**Plan header.** writing-plans always writes two lines. `**Integration check:**` holds the full suite command, on every plan, not only wave plans. `**Task check:**` holds one of:

- a command, the first that applies: a gate in `<docs>/gates.md` with `Tier: task`; else the full suite itself when its last recorded passing run took 300 seconds or less (tiering a fast suite saves nothing); else an impact-selection command for the project's runner from `reference/test-tiers.md` (for example `npx jest --changedSince=main`, `pytest --testmon`, `vitest --changed main`);
- `none — full suite every 3 tasks`, when none of those applies.

writing-plans states the source in a trailing `— <why>`. For the 300-second rule it reads only rows in `suites.tsv` of the checkout it runs in, matched by suite-run's quoted key for `bash -c '<cmd>'` run from the top level (`scripts/task-step:78-82`). When the row is missing, or is a six-column row with no duration, the suite counts as not fast.

**plan-lint compatibility.** Plans written before this change lack these lines, and so do the existing lint fixtures. A missing `**Task check:**` or `**Integration check:**` line is a WARN (`no **Task check:** line yet`), as a missing `Plan review` line is today (`scripts/plan-lint:108`). A present but malformed line is an ERROR. A wave plan still requires `**Integration check:**`, as today. A `**Task check:**` that is neither one command code span nor the `none` form is malformed.

**gates.md.** Gates gain an optional `Tier:` field with the values `task`, `branch` or `sweep`. The default is `branch`, so an existing manifest means what it meant before. running-gates runs the `task` and `branch` gates. For each `sweep` gate it skips, it prints one line naming the gate and saying it belongs to CI.

**suite-run gains duration.** `suites.tsv` gains a seventh column, the run's duration in seconds. Every current reader stays correct. suite-run's reuse check reads columns 1-6 (`suite-run:81-83`). `suite_row`'s callers cut columns 4 and 5 (`task-step:219-220, 257-259`). `read -r _ kind _ code log _` absorbs the extra column (`:1364`).

**Controller, subagent mode** (`reference/delegated-task.md` §1 "Suite command", §2, §5):

- **A plan with no `**Task check:**` line** runs as it does today: the Integration check, else gates, else the project manifest, at every task.
- **A command task check:** every `task-step start` passes `--suite '<task check>'`. The rest of the loop is unchanged: the run starts beside the review, `verdict` reads it, and a red line not failing at the base is an Important finding.
- **`none`, sequential plan.** The schedule is by task number: the integration check runs on every task whose number is a multiple of 3, and on the last task. The controller decides at review time, in the same turn it starts the run, because `start` runs before anyone knows whether the task will be held or grouped.
  - `task-step review` and `task-step review --group` accept `--suite CMD` and `--suite-base SHA`. They write `suite` and `suiteBase` onto the step file `verdict` reads (for a group, the last member's: `task-step:1351-1355`), overriding what `start` recorded.
  - `<sha>` is the head of the last full-suite run, or the plan's base before the first run. So a regression made two tasks earlier is not excused as a base failure. Normally `suites.tsv` already holds a row at `<sha>`, so the base comparison costs nothing. When that task had a fix round, `<sha>` has no row, and `verdict` runs the suite once there (bounded at 3600 seconds, `TASK_STEP_BASE_TIMEOUT`).
  - A group runs the integration check when it holds a scheduled task.
  - A fix round runs a suite only when its task's review did.
- **`none`, wave plan:** no per-task suite at all. The merged wave check is the suite of the wave's grouped tasks (`reference/delegated-task.md:184-185`), and writing-plans' wave schedule stands (`skills/writing-plans/SKILL.md:221-225`). A command task check still runs per task in the task's worktree, as today.
- **The `not scheduled` line.** When the plan's `**Task check:**` is `none` and the step file has no `suite`, `verdict` prints `suite: not scheduled (next at Task <N>)`, computed from the plan alone, and does not exit 7. A step file with no `suite` on any other plan keeps printing `suite: none recorded`. §5's completion rule (`:694-697`) adds `not scheduled` to `pass`, `red` with 0 failing, and `none recorded`.
- **The final review** starts the integration check through `suite-run` in the background, beside its reviewers, at the branch head. A failing line that does not fail at the merge base is a final-review finding. The fix subagent runs it again after its last commit (as now), and finishing reuses that pass at the same commit.

**Inline mode** (`skills/executing-plans/SKILL.md` step 4): run the focused tests while working and the task check once before committing, in place of the full suite. With a task check of `none`, run the integration check on tasks numbered a multiple of 3 and on the last one.

**Implementer prompt.** Unchanged in substance: focused tests only, never the whole suite. The sentence naming the controller's run says "the task check" instead of "the full suite".

**Codex hosts.** The per-task suite on a `Host: codex` plan is in `reference/delegated-task.md`, "The steps by hand" §2 (`:764-770`). It runs the task check, under the same `none` schedule.

### 2. Fewer tests in the plan (B, register row 2)

**Task template** (`skills/writing-plans/SKILL.md`). Step 1 takes one of three forms:

- **Write the failing test** — a behaviour no existing or planned test reaches. This is the current form.
- **Extend the test `<file>::<name>`** — a variant of a behaviour already tested, or new behaviour that belongs in an existing test. The step gives the added row, case or assertion in full, and it must fail before the implementation, as a new test would.
- **Covered by Task `<N>`'s test `<name>`** — only for a task that adds no new observable behaviour: wiring, extraction or configuration whose result an earlier task's test exercises end to end. A task adding behaviour uses "Extend" instead. The step names the fault in this task's code that the test would catch. The task has no step that writes its own failing test, and its verification runs the covering test. The plan reviewer judges such a task's Executability by the named fault.

Plans are written per behaviour: one test per acceptance statement or behaviour, at the lowest layer that can fail for it, rather than one per task. The existing rule against end-to-end tests for edge cases stays.

**plan-lint** accepts the three forms. It fails a `Covered by Task <N>` when Task `<N>` does not exist, has no test step of its own, or does not run before the citing task. In a sequential plan `<N>` must be lower than the citing task's number. In a wave plan Task `<N>` must sit in an earlier wave.

**Plan review** (`criteria/plan-review.md`). A new criterion, "Redundant test": a planned test that fails for no fault an existing test or another planned test does not already catch. It scores the task LOW under Executability, as a test that cannot fail does (`criteria/plan-review.md:20-35`). The reviewer names the overlapping test.

**TDD skill** (`skills/test-driven-development/SKILL.md`). The "Minimal" row becomes "One behaviour: variants of one behaviour are rows of one parametrized or table-driven test; distinct behaviours get distinct tests." `references/writing-good-tests.md` adds a step after "Name the production change that would make the test fail": find whether an existing test already fails for that change. If one does, extend it, or write no test.

### 3. Routine, cheaper cleanup (C, register row 3)

**TDD REFACTOR step.** After green, a test written on the current branch may be deleted when a broader test written on the branch fails for every fault the narrower one catches. The commit body names those faults. The rule covers only tests that do not exist at the branch's merge base, and never a regression test that names a fixed bug. A test that predates the branch goes through test-simplifier.

**Final review.** The `test-quality` lens (`criteria/lenses/test-quality.md`) gains a criterion, "Redundant tests" `{#redundant}`: among tests added or changed on the branch, report one that fails for no fault another branch test or an existing test does not also catch, and name the test that covers it. Findings go to the fix wave, which merges the tests into a row of a table or deletes the redundant one. The fix wave may delete only tests added on the branch, under the same rule as the REFACTOR step.

**closing-a-milestone.**
- The audit compares two durations from `suites.tsv` in the checkout it runs in: the last passing full-suite run at or before the milestone's head, and the last one at or before the previous milestone's close (or the oldest row when there is none).
- The rows exist because finishing's merged-result verification in the main checkout goes through `suite-run`, leaving one full-suite row at each merge head. A plan's own worktree rows are removed with the worktree.
- The audit names the checkout whose rows it read. With fewer than two rows it says so and recommends nothing. That is the expected answer until two plans have merged under this version.
- When the full suite grew by 20% or more, or passes a declared budget, the closing report recommends dforge:test-simplifier, scoped to the modules the milestone touched, as the next step. It recommends only and removes nothing.
- The budget is an optional `Budget:` line on the gate whose `Command` equals the plan's `**Integration check:**`. When no such gate exists, the audit uses the 20% rule only.

### 4. test-simplifier matches the plan (register row 4)

- **Phase 3** uses the tier names and sources of part 1. It proposes a `Tier: task` gate, and a `Budget:` line, as a `gates.md` diff, still applied only on approval. The impact-selection table moves to `reference/test-tiers.md`.
- **Scope.** The skill takes an optional scope: `--modules <paths>` (the closing-a-milestone recommendation passes the milestone's modules) or `--since <ref>` (tests added after a ref). With a scope, Phase 1 still profiles the whole suite, while Phase 4 waves take candidates only from inside the scope.
- **Candidate class 6, "Subsumed scaffolding":** a narrow test whose every fault a broader test of the same behaviour also catches. The evidence rules are unchanged: mutation runs, or named faults applied as patches, plus the judge verdict.
- **Division of labour,** stated in the skill: tests added on the current branch are merged or removed by the REFACTOR step and the final-review lens (part 3). test-simplifier handles tests already on the default branch.
- `tests/test-simplifier.test.sh` keeps its current pins; they cover rules this part does not change.

### 5. CI parity in every project (register row 5, generic)

**Reference** `reference/ci-parity.md`:
- how to find the CI configuration (`.github/workflows/*.yml` first, then `.gitlab-ci.yml`, `azure-pipelines.yml`, `.circleci/config.yml`);
- how to read jobs, platforms and commands from it;
- a pitfalls table per platform the local host may not run: Windows Git Bash (`MSYS_NO_PATHCONV` paths for native tools, `/c/` against `C:/`, CR stripping, gawk `-v` escapes, ESM drive-letter imports), macOS (BSD `sed -i`, `date`, `readlink -f`), and uutils coreutils on `ubuntu-latest` (non-exclusive `mkdir`, `timeout` signalling only the command).

**Plan header** `**CI:**`, which writing-plans always writes. It reads `none` (no CI configuration found), or:

`` `<workflow files>` — platforms: <list> — local: `<cmd>`; `<cmd>` — uncovered: <platforms or none> ``

writing-plans fills it from the CI configuration. For every uncovered platform, it copies that platform's rows of the pitfalls table into `## Global Constraints`, so every task brief carries them. plan-lint warns on a missing line, like the part 1 lines, and fails a malformed one.

**Header line** `**Early CI:**`, optional: `after wave <k>` or `after task <n>`, then `— consented <YYYY-MM-DD>`.
- **When it is offered.** writing-plans offers it only when the CI line has an uncovered platform, and asks the owner; the answer is the consent. An auto run writes the plan unattended, so there brainstorming reads the CI configuration while writing the spec. When a platform is uncovered, it asks the early-CI question at the spec review and records the answer in `## Decisions`, and writing-plans copies it into the header (`skills/brainstorming/references/auto-by-default.md` gains this question).
- **Lint.** plan-lint fails the line when the consent clause is missing, or when the point is malformed: a wave reference on a sequential plan, or a task number past the last.
- **Auto runs.** `reference/auto-run.md`'s never-performed list (`:181-185`) gains a second exception beside the finish action: the `**Early CI:**` push and workflow dispatch, performed only when the header line carries `— consented <date>`.

When the controller reaches the early-CI point:
1. It pushes the branch (`git push -u origin <branch>`).
2. It starts CI with `gh workflow run <workflow> --ref <branch>` when the workflow declares `workflow_dispatch`. Otherwise it says so in one line and skips the early run. It never opens a pull request on its own.
3. `gh workflow run` prints no run id, so the controller finds the run with `gh run list --workflow <file> --branch <branch> --limit 1 --json databaseId,headSha`, retrying for up to 60 seconds, and checks that `headSha` is the pushed commit.
4. It runs `gh run watch <id>` in the background and keeps working.

Ledger lines: `Early CI: dispatched run <id> at <sha7>`, `Early CI: green run <id>`, `Early CI: red run <id> — <job>/<step>[, ...]`. Any failure of `git push` or `gh` (no remote, not logged in, the API refusing) prints one line and writes `Early CI: skipped — <reason>`, never a stop. A red run becomes a bullet the controller writes into the next task's fix file, the route §4 already gives a mechanical check's finding. With no task left, it becomes a final-review finding, debugged with dforge:systematic-debugging.

**Script** `scripts/ci-mirror PLAN_FILE`. It reads the plan's `**CI:**` line and runs each `local:` command through `suite-run`, which records each run and reuses a pass at the same commit. It prints one digest line per command, then `uncovered: <platforms>`. It exits non-zero when any command fails or cannot launch, with the digest line naming that command. A line reading `none` prints `ci: none` and exits 0.
- The final review runs it at step 0, before the gates. A failure is a final-review finding.
- running-gates reports a gate whose `Command` equals, byte for byte, a ci-mirror command that passed at this HEAD as passed from that record, naming its log. It runs every other gate as today.

**Finishing** (`skills/finishing-a-development-branch/SKILL.md`). When finishing itself pushed (the open-a-pull-request option, and an Early CI push whose head equals the final head), it waits for the CI run of the pushed commit:
- `gh run list --commit <sha>`, then `gh run watch <id>` in the background. The Bash call's `timeout` is set to (90 × 60 + 120) × 1000 ms, because a background call otherwise stops at 30 minutes (`reference/final-review.md:131-132`). In an auto run the controller ends the turn and resumes on the notification.
- It records `CI: <sha7> run <id> <green|red|still running at 90 min>` on the ledger, and the final message quotes it.
- Green completes the branch.
- Red reopens it through dforge:systematic-debugging, with each failed job and step named; the fix is pushed and the wait repeats.
- A run still going at the bound is reported as not done, never as done.
- With `keep`, no `gh`, `gh` not logged in, or a CI line of `none`, it prints why in one line and skips the wait without calling the branch CI-green.
- After a local merge, which pushes nothing, it does not wait. It prints the exact `gh run list --commit <merge sha>` and `gh run watch <id>` lines for the owner to run after pushing, and does not call the branch CI-green.
- After a local merge on a plan with an `**Early CI:**` line, it runs `git push origin --delete <branch>`. With `keep`, it says the remote branch exists.

### 6. This repository's CI checks (register row 5, repo-specific)

- **`scripts/lint-portability.mjs`**, run by `scripts/validate-repository.mjs` over `plugins/*/scripts/**`, `plugins/*/tests/**` and `scripts/**`. It has four rules, taken from `reference/ci-parity.md`'s Windows Git Bash rows:
  - `git -C "$PWD"` or `git -C "$(pwd)"` without `dr_native_path` (`plugins/dforge/scripts/lib/native-path.sh:13`);
  - `awk -v` carrying a backslash;
  - a dynamic `import()` of an absolute path variable not wrapped in `pathToFileURL`;
  - `jq` given a file argument built from `$PWD`, `$(pwd)` or `$TMPDIR` in a file that exports `MSYS_NO_PATHCONV`.

  A line ending `# portability: ok — <reason>` (or `// portability: ok — <reason>`) is exempt. Each hit prints `file:line rule message` and fails validation.
- **Shard weights.** `tests/test-shards.test.mjs` fails when a shell suite has no weight in `scripts/test-shards.mjs`. The shell suites are `plugins/dforge/tests/*.test.sh` and `plugins/dr-status/tests/run-all.sh`, read through `test-all.mjs --list`. The other jobs (`validate-repository.mjs`, the `--test` jobs, `claude plugin test`, `tsc`) keep the default weight. It also fails when a weight exceeds 80% of that suite's limit (`suiteSeconds`, else 600), with the message "raise its suiteSeconds or split it". The comments at `test-shards.mjs:8-9` and `tests/test-shards.test.mjs:24`, which describe new suites as weighted by default, change to match. The same task brings today's weights inside the rule, so the check is green at merge: `task-step.test.sh` is split into parts through `suiteParts` (a larger limit cannot fit the 25-minute Windows job, `.github/workflows/validate.yml:115`), `faster-plans` gets a third part, and `next-step` and `auto-run` get `suiteSeconds` of 700.
- **Drift warning.** `scripts/test-all.mjs` prints a GitHub `::warning::` line naming a suite whose duration passes 75% of its limit, so growth shows up before it fails a run.

### Tests for this work

This plan follows part 2 itself. A new behaviour gets a new test. A variant extends an existing test as a row. Pins of skill wording that this work changes are updated in place, not duplicated; one of them is `tests/suite-run.test.sh:76`, "the row has six fields". New script behaviour gets tests in the existing suite for that script, or in one new suite per new script: `task-step review --suite`/`--suite-base`, `suite-run`'s duration column, `ci-mirror`, `lint-portability.mjs`, and the plan-lint rules.

## Acceptance

A1. [test, high] plan-lint warns on a plan without a `**Task check:**` or an `**Integration check:**` line and fails one where either line is malformed. A plan with both lines well formed passes, and a wave plan without `**Integration check:**` still fails.
A2. [test, high] With a command task check, the subagent-mode controller passes that command, never the integration check, to every `task-step start` (`reference/delegated-task.md` says so, and `tests/delegated-suite.test.sh` pins it).
A3. [test, high] `task-step review --suite <cmd> --suite-base <sha>` (and `review --group`) writes `suite` and `suiteBase` onto the step file `verdict` reads. `verdict` then excuses only the failing lines that also fail at that sha, so a regression made by an earlier task since the last full run is reported as a finding.
A4. [test, neg, high] On a sequential plan whose task check is `none`, a task whose number is not a multiple of 3 and is not the last runs no suite. Its verdict prints `suite: not scheduled (next at Task <N>)`, never `suite: not run`, never exits 7, and the task can complete.
A5. [test, high] `suite-run` writes a seventh duration column to `suites.tsv`, and a six-column row still parses everywhere `suites.tsv` is read.
A6. [test, high] The final review runs the integration check at the branch head through `suite-run`, and finishing reuses a pass recorded at the same commit on a clean tree instead of running again.
A7. [test, confirmed] writing-plans picks the full suite as the task check when its last passing run took 300 seconds or less, and treats a missing duration as not fast.
A8. [test, high] plan-lint accepts the three Step 1 forms. It fails a `Covered by Task <N>` naming a missing task, a task with no test step, or a task that does not run before the citing task (a higher number in a sequential plan, the same or a later wave in a wave plan).
A9. [test, high] `criteria/plan-review.md` carries the "Redundant test" criterion, scored LOW under Executability, with the reviewer naming the overlapping test.
A10. [test, high] The TDD skill's "Minimal" row is replaced by the one-behaviour, parametrized-variants rule, and `writing-good-tests.md` asks whether an existing test already fails for the change.
A11. [test, neg, high] Neither the REFACTOR rule nor the final-review fix wave deletes a test that exists at the branch's merge base, or a regression test naming a fixed bug.
A12. [test, high] The `test-quality` lens carries a `{#redundant}` criterion that names the covering test.
A13. [test, confirmed] closing-a-milestone recommends a scoped test-simplifier run when the full suite grew by 20% or more, or passes a declared `Budget:`, names the checkout whose rows it read, and recommends nothing with fewer than two rows.
A14. [test, high] test-simplifier's Phase 3 uses the tier names of `reference/test-tiers.md`, accepts `--modules` and `--since` scopes, lists the "Subsumed scaffolding" class, and states the division of labour with the branch-level cleanup.
A15. [test, high] plan-lint warns on a plan without a `**CI:**` line, fails a malformed one, and passes `none`.
A16. [test, high] `ci-mirror` runs every `local:` command of the CI line through `suite-run`, prints `uncovered: <platforms>`, exits non-zero when one command fails, and prints `ci: none` with exit 0 for `none`.
A17. [test, neg, high] With no `**Early CI:**` line, no step of the controller pushes the branch or triggers CI before finishing. With the line present, the controller never opens a pull request to start CI. `reference/auto-run.md` names the consented early-CI push and dispatch as the second exception to its never-performed list.
A18. [test, confirmed] When finishing pushed, it waits for the CI run of the pushed commit, bounded at 90 minutes, records the `CI:` ledger line, and never reports the branch done while that run is red or still running.
A19. [test, high] writing-plans copies the pitfalls-table rows for each uncovered platform into `## Global Constraints`.
A20. [test, high] `lint-portability.mjs` flags each of its four rules on a fixture line, passes the same line carrying the exemption comment, and runs from `validate-repository.mjs`.
A21. [test, confirmed] `test-shards.test.mjs` fails for a shell suite with no weight and for a weight above 80% of its limit, does not fail for the non-shell jobs, and passes on the repository's weights at merge.
A22. [test, high] `test-all.mjs` prints a `::warning::` naming a suite whose duration passes 75% of its limit.
A23. [test, neg, high] An existing `gates.md` with no `Tier:` field runs exactly the gates it ran before.
A24. [test, neg, high] plan-lint fails an `**Early CI:**` line without `— consented <YYYY-MM-DD>`, one naming a wave on a sequential plan, and one naming a task past the last.
A25. [test, high] running-gates prints one line per skipped `Tier: sweep` gate naming it as CI's, and still runs every `task` and `branch` gate.
A26. [test, neg, high] `ci-mirror` with a `local:` command that cannot launch prints the digest line naming it and exits non-zero. Finishing with `gh` absent or not logged in prints one line and skips the wait without calling the branch done.
A27. [test, neg, confirmed] After a local merge, finishing prints the `gh run list --commit <sha>` and `gh run watch` lines and never calls the branch CI-green.

## Riskiest assumption

That a fast task check, plus the full suite only at wave checks, the final review and every third task when there is no fast check, catches regressions early enough that the final-review fix wave does not grow to cost what the per-task suite runs saved.

Evidence: Meta reports catching over 99.9% of regressions while running about a third of the tests through predictive selection ([engineering.fb.com, 2018](https://engineering.fb.com/2018/11/21/developer-tools/predictive-test-selection/)). Google defers broad testing until after submission for the same cost reason ([research.google/pubs/pub52465](https://research.google/pubs/pub52465)). Locally, attribution to the right task is already supported: `task-step` compares a sequential group with its first member's base (`plugins/dforge/scripts/task-step:126`), which `--suite-base` generalises. No local history measures how often the per-task suite caught a regression that focused tests missed: the ledgers in `.dforge/sdd` hold no suite verdicts (checked 2026-10-31), and the darkmem mirror was unreachable this session. Residual risk is bounded by the early CI run and the every-third-task fallback. The first plan executed after this work records, in its final review, how many final-suite failing lines no task check caught.

## Review rulings

- Required header lines warn when missing and fail when malformed; a plan with no `**Task check:**` runs as today.
- The `none` schedule is by task number (multiples of 3 and the last task), computed from the plan alone.
- `task-step review` and `review --group` take `--suite`/`--suite-base`, so the schedule is decided at review time.
- On a wave plan, `none` means no per-task suite; the wave schedule stands.
- `not scheduled` joins §5's completion rule, printed only when the task check is `none` and the step file has no `suite`.
- The Codex per-task suite lives in delegated-task.md "The steps by hand" §2, not native-codex.md.
- The seventh `suites.tsv` column is safe for every reader. `tests/suite-run.test.sh:76` is updated in place, and a missing duration counts as not fast.
- auto-run.md gains the consented early-CI push and dispatch as a second exception.
- plan-lint fails an `**Early CI:**` line without consent or with a malformed point (A24).
- Early CI finds its run id with `gh run list`, writes three ledger line forms, and treats any `git push`/`gh` failure as a one-line skip.
- After a local merge, finishing deletes the remote branch an early push created.
- The 90-minute watch sets its Bash timeout explicitly and records a `CI:` ledger line.
- ci-mirror runs before the gates, and a gate with the same command reuses its pass.
- The shard-weight rule is scoped to the shell suites; the two comments describing default weights change.
- The portability lint has four rules sourced from `reference/ci-parity.md`, with `dr_native_path` named.
- `Covered by Task <N>` applies only to tasks adding no observable behaviour.
- The Redundant test criterion scores LOW under Executability.
- `Budget:` sits on the gate whose `Command` equals the Integration check.
- Milestone durations come from the main checkout's rows, recorded by finishing's merged-result verification.
- The cost of a `--suite-base` run when no row exists at the base is stated.
- A25 covers skipping `sweep` gates.
- A26 covers a `ci-mirror` command that cannot launch and finishing without `gh`.

## Critic findings

Folded into Fable's review. 0 Blocker, 5 High, 10 Medium, 5 Nit.

- [High] The early-CI push contradicted auto-run's never-performed rule. Fixed: auto-run.md gains the consented exception (part 5).
- [High] The `none` schedule could not be applied at `task-step start` for a grouped task. Fixed: `review` takes `--suite`/`--suite-base` (part 1).
- [High] Three required header lines broke existing plans and lint fixtures. Fixed: warn when missing, fail when malformed (parts 1 and 5).
- [High] The 80% shard-weight rule is red on today's weights (`faster-plans`, `task-step.test.sh`, `next-step`, `auto-run`). Answered at the spec review: part 6 brings today's weights inside the rule in the same task.
- [High] The wait for CI had no trigger on the local-merge path. Answered at the spec review: finishing waits only when it pushed, and after a local merge prints the commands to run.
- [Medium] `Covered by Task <N>` could not be failing-first. Fixed: restricted to behaviour-free tasks.
- [Medium] ci-mirror duplicated the gates at the same HEAD. Fixed: gates reuse its pass.
- [Medium] The milestone comparison read rows that cleanup deletes. Fixed: rows come from the main checkout.
- [Medium] The early run had no run id, ledger line or `gh` failure outcome. Fixed.
- [Medium] Consent sat in a header line nothing checked. Fixed: A24.
- [Medium] The early push left `origin/<branch>` behind after a local merge. Fixed.
- [Medium] A 90-minute background watch outlived the Bash default limit. Fixed.
- [Medium] The missing-weight rule flagged jobs with no weight by design. Fixed: scoped to shell suites.
- [Medium] native-codex.md had nothing to change. Fixed: repointed.
- [Medium] The lint's rule set was misdescribed and sourced from a private file. Fixed.
- [Nit] The `suite-run.test.sh:76` pin was unnamed. Fixed.
- [Nit] A six-column row had no duration. Fixed: treated as not fast.
- [Nit] The LOW dimension was unnamed. Fixed: Executability.
- [Nit] "The full-suite gate" was undefined. Fixed.
- [Nit] The base run after a fix round was unpriced. Fixed.
