# Test tiers, fewer tests and CI parity

**Execution strategy:** sequential — the owner asked for A, then B, then C; parts 1-5 share `skills/writing-plans/SKILL.md`, `reference/delegated-task.md` and `scripts/plan-lint`, and part 6 is small enough not to earn a wave.
**Depth:** standard — interface

## Decisions

- **Scope.** The owner chose recommendations A, B and C from the test-bloat research of 2026-10-31, in that order: "I want to do A then B then C, also update test-simplifier to achieve same as this plan." Register: `docs/dforge/registers/2026-10-31-test-cost-and-ci.md`, rows 1-5.
- **CI scope.** Question: "Where should the CI-failure prevention live?" Answer: "Both (Recommended)": "A generic dforge mechanism for every project: before finishing, read the CI workflow and run its local equivalent; plans name the platforms CI covers; after a push, wait for CI and treat red as not done. Plus checks specific to this repo: a static lint for known Git Bash pitfalls and a check that every suite has a shard weight and fits its time limit."
- **Repo suite.** Question: "Should this work also slim this repo's own test suite now?" Answer: "Skills only (Recommended)": "Change dforge's skills and scripts and add this repo's CI checks. Slimming this repo's suite becomes a later, separate test-simplifier run that uses the new process."
- **Per-task tier (A).** Question: "What should the controller run for each task?" Answer: "Two tiers (Recommended)": "`Task check:` fast command for each task; full suite at wave checks, final review and finishing; a passing run at the same commit is reused. If a project has no fast command, the full suite runs every 3 tasks instead of every task." Rejected: dropping the per-task controller run (do-less), and dforge working out which tests a diff affects by itself, per language.
- **CI mechanism.** Question: "For CI prevention in every dforge project: how far should dforge go?" Answer: "Three points + early run (Recommended)": "`CI:` plan line and portability constraints, local `ci-mirror` before the final review, wait for CI after the push, and an optional early CI run on the pushed branch with consent per plan." Rejected: waiting for CI after the push only (do-less).
- **Execution strategy.** No `executionStrategy` setting is in force and `autoRun=on` does not ask; sequential, for the reason on the line above.

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
| Full suite | the plan header's `**Integration check:**` line | each wave's merged check, every third completed task when the task check is `none`, the final review, the fix wave, finishing |
| Sweep | the project's CI | after push (part 5) |

**Plan header.** `**Integration check:**` becomes required for every plan, not only wave plans. It holds the full suite command. A new required line, `**Task check:**`, holds one of:

- a command, the first that applies: a gate in `<docs>/gates.md` with `Tier: task`; else the full suite itself when its last recorded passing run in `<state>/suites.tsv` took 300 seconds or less (tiering a fast suite saves nothing); else an impact-selection command for the project's runner from `reference/test-tiers.md` (for example `npx jest --changedSince=main`, `pytest --testmon`, `vitest --changed main`);
- `none — full suite every 3 tasks`, when none of those applies.

writing-plans resolves the value once and states the source in a trailing `— <why>`. plan-lint fails a plan missing either line, and fails a `**Task check:**` that is neither a command code span nor the `none` form.

**gates.md.** Gates gain an optional `Tier:` field with the values `task`, `branch` or `sweep`. The default is `branch`, so an existing manifest means what it meant before. running-gates runs the `task` and `branch` gates and skips `sweep` gates, saying they belong to CI.

**suite-run gains duration.** `suites.tsv` gains a seventh column, the run's duration in seconds. Readers that take six columns keep working. writing-plans reads this column for the 300-second rule.

**Controller, subagent mode** (`reference/delegated-task.md` §1 "Suite command", §2):

- A command task check: every `task-step start` passes `--suite '<task check>'`. The rest of the loop is unchanged: the run starts beside the review, `verdict` reads it, and a red line not failing at the base is an Important finding.
- `none`: `task-step start` passes `--suite '<integration check>' --suite-base <sha>` only on every third completed task and on the plan's last task. `<sha>` is the base of the first task since the last full run, so a regression made two tasks earlier is not excused as a base failure. Other tasks start without `--suite`, and their verdict prints `suite: not scheduled (next at Task <N>)`. This is a new digest line, distinct from `suite: none recorded`. A group review counts its members as completed tasks: it runs the integration check when the count crosses a multiple of three or the group holds the last task. A fix round runs a suite only when its task's review did.
- The final review starts the integration check through `suite-run` in the background, beside its reviewers, at the branch head. A failing line that does not fail at the merge base is a final-review finding. The fix subagent runs it again after its last commit (as now), and finishing reuses that pass at the same commit.

**task-step.** `start` accepts `--suite-base SHA` and stores it in the step file as `suiteBase`. `suite_base_sha` prefers `suiteBase` over the group rule and the task's own base. `verdict` accepts a step file with no `suite` and prints the `not scheduled` line when the plan's task check is `none`.

**Inline mode** (`skills/executing-plans/SKILL.md` step 4): run the focused tests while working and the task check once before committing, in place of the full suite. With a task check of `none`, run the integration check on every third task and the last one.

**Implementer prompt.** Unchanged in substance: focused tests only, never the whole suite. The sentence that names the controller's run says "the task check" instead of "the full suite".

**Native Codex** (`reference/native-codex.md`): wherever it runs a suite per task, it runs the task check, under the same `none` rule.

### 2. Fewer tests in the plan (B, register row 2)

**Task template** (`skills/writing-plans/SKILL.md`). Step 1 takes one of three forms:

- **Write the failing test** — a behaviour no existing or planned test reaches. This is the current form.
- **Extend the test `<file>::<name>`** — a variant of a behaviour already tested. The step gives the added row, case or assertion in full, and it must fail before the implementation, as a new test would.
- **Covered by Task `<N>`'s test `<name>`** — the behaviour is pinned by a test another task of this plan writes. The step names the fault in this task's code that the test catches. The task has no step that writes or runs its own failing test, and its verification runs that test.

Plans are written per behaviour: one test per acceptance statement or behaviour, at the lowest layer that can fail for it, rather than one per task. The existing rule against end-to-end tests for edge cases stays.

**plan-lint** accepts the three forms. It fails a `Covered by Task <N>` when Task `<N>` does not exist, has no test step of its own, or does not run before the citing task: in a sequential plan `<N>` must be lower than the citing task's number, and in a wave plan Task `<N>` must sit in an earlier wave.

**Plan review** (`criteria/plan-review.md`). A new criterion, "Redundant test": a planned test that fails for no fault that an existing test, or another planned test, does not already catch. It scores the task LOW in the same dimension as a test that cannot fail. The reviewer names the overlapping test.

**TDD skill** (`skills/test-driven-development/SKILL.md`). The "Minimal" row becomes "One behaviour: variants of one behaviour are rows of one parametrized or table-driven test; distinct behaviours get distinct tests." `references/writing-good-tests.md` adds a step after "Name the production change that would make the test fail": find whether an existing test already fails for that change. If one does, extend it, or write no test.

### 3. Routine, cheaper cleanup (C, register row 3)

**TDD REFACTOR step.** After green, a test written on the current branch may be deleted when a broader test written on the branch fails for every fault the narrower one catches. The commit body names those faults. The rule covers only tests that do not exist at the branch's merge base, and never a regression test that names a fixed bug. A test that predates the branch goes through test-simplifier.

**Final review.** The `test-quality` lens (`criteria/lenses/test-quality.md`) gains a criterion, "Redundant tests" `{#redundant}`: among tests added or changed on the branch, report one that fails for no fault another branch test or an existing test does not also catch, and name the test that covers it. Findings go to the fix wave, which merges the tests into a row of a table, or deletes the redundant one. The fix wave may delete only tests added on the branch, under the same rule as the REFACTOR step.

**closing-a-milestone.** The audit compares two durations from `suites.tsv`: the last passing full-suite run at or before the milestone's head, against the last one at or before the previous milestone's close (or the oldest row when there is none). With fewer than two such rows it says so and recommends nothing. When the full suite grew by 20% or more, or passes the budget `<docs>/gates.md` declares in an optional `Budget:` line on the full-suite gate, the closing report recommends dforge:test-simplifier scoped to the modules the milestone touched, as the next step. It recommends only and removes nothing.

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
- a pitfalls table per platform that the local host may not run: Windows Git Bash (`MSYS_NO_PATHCONV` paths for native tools, `/c/` against `C:/`, CR stripping, gawk `-v` escapes, ESM drive-letter imports), macOS (BSD `sed -i`, `date`, `readlink -f`), and uutils coreutils on `ubuntu-latest` (non-exclusive `mkdir`, `timeout` signalling only the command).

**Plan header** `**CI:**`, required. It reads `none` (no CI configuration found), or:

`` `<workflow files>` — platforms: <list> — local: `<cmd>`; `<cmd>` — uncovered: <platforms or none> ``

writing-plans fills it from the CI configuration. For every uncovered platform, it copies that platform's rows of the pitfalls table into `## Global Constraints`, so every task brief carries them. plan-lint fails a missing line and a malformed one.

**Header line** `**Early CI:**`, optional: `after wave <k>` or `after task <n>`, then `— consented <YYYY-MM-DD>`. writing-plans offers it only when the CI line has an uncovered platform, and asks the owner. The answer is the consent. An auto run writes the plan unattended, so there brainstorming reads the CI configuration while writing the spec and asks the early-CI question at the spec review when a platform is uncovered. The answer goes in the spec's `## Decisions`, and writing-plans copies it into the header (`skills/brainstorming/references/auto-by-default.md` gains this question). When the controller reaches that point:
1. it pushes the branch (`git push -u origin <branch>`);
2. it starts the CI run: `gh workflow run <workflow> --ref <branch>` when the workflow declares `workflow_dispatch`, else it says so in one line and skips the early run (it never opens a pull request on its own);
3. it watches the run in the background and keeps working.

A red early run becomes a finding for the next task's review. When no task is left, it becomes a final-review finding, debugged with dforge:systematic-debugging. Each red job, and each step in it, is named.

**Script** `scripts/ci-mirror PLAN_FILE`. It reads the plan's `**CI:**` line and runs each `local:` command through `suite-run`, which records each run and reuses a pass at the same commit. It prints one digest line per command, then `uncovered: <platforms>`, and exits non-zero when any command fails. A line reading `none` prints `ci: none` and exits 0. The final review runs it before dispatching reviewers. A failure is a final-review finding.

**Finishing** (`skills/finishing-a-development-branch/SKILL.md`). After a push, a merge that is then pushed, or a pull request, it waits for the CI run of the pushed commit:
- `gh run list --commit <sha>`, then `gh run watch <id>` in the background, bounded by 90 minutes;
- green completes the branch;
- red reopens it through dforge:systematic-debugging, with each failed job and step named; the fix is pushed and the wait repeats;
- a run still going at the bound is reported as not done, never as done;
- with `keep`, no `gh`, or a CI line of `none`, it says why in one line and skips the wait.

### 6. This repository's CI checks (register row 5, repo-specific)

- **`scripts/lint-portability.mjs`**, run by `scripts/validate-repository.mjs` over `plugins/*/scripts/**`, `plugins/*/tests/**` and `scripts/**`, with one rule per pitfall in the memory note on CI runner quirks:
  - `git -C "$PWD"` or `git -C "$(pwd)"` without the native-path helper;
  - `awk -v` carrying a backslash;
  - a dynamic `import()` of an absolute path variable not wrapped in `pathToFileURL`;
  - `jq` given a file argument built from `$PWD`, `$(pwd)` or `$TMPDIR` in a file that exports `MSYS_NO_PATHCONV`.
  
  A line ending `# portability: ok — <reason>` (or `// portability: ok — <reason>`) is exempt. Each hit prints `file:line rule message` and fails validation.
- **Shard weights.** `tests/test-shards.test.mjs` fails when a suite that `scripts/test-all.mjs` discovers has no weight in `scripts/test-shards.mjs`. It also fails when a weight exceeds 80% of that suite's limit (`suiteSeconds`, else 600), with the message "raise its suiteSeconds or split it".
- **Drift warning.** `scripts/test-all.mjs` prints a GitHub `::warning::` line naming the suite when its duration passes 75% of its limit, so growth shows up before it fails a run.

### Tests for this work

This plan follows part 2 itself. A new behaviour gets a new test. A variant extends an existing test as a row. Pins of skill wording that this work changes are updated in place, not duplicated. New script behaviour (`task-step --suite-base`, `suite-run`'s duration column, `ci-mirror`, `lint-portability.mjs`, the plan-lint rules) gets tests in the existing suite for that script, or in one new suite per new script.

## Acceptance

A1. [test, high] A plan without a `**Task check:**` or an `**Integration check:**` line fails plan-lint, and a plan with both lines passes plan-lint.
A2. [test, high] With a command task check, the subagent-mode controller passes that command, never the integration check, to every `task-step start` (`reference/delegated-task.md` says so, and `tests/delegated-suite.test.sh` pins it).
A3. [test, high] `task-step start --suite-base <sha>` stores `suiteBase`, and `verdict` excuses only the failing lines that also fail at that sha, so a regression made by an earlier task since the last full run is reported as a finding.
A4. [test, neg, high] With a task check of `none`, a task that is not every third and not the last runs no suite, and its verdict prints `suite: not scheduled (next at Task <N>)`, never `suite: not run`, and never exits 7.
A5. [test, high] `suite-run` writes a seventh duration column to `suites.tsv`, and a six-column row still parses everywhere `suites.tsv` is read.
A6. [test, high] The final review runs the integration check at the branch head through `suite-run`, and finishing reuses a pass recorded at the same commit on a clean tree instead of running again.
A7. [test, medium] writing-plans picks the full suite as the task check when its last passing run took 300 seconds or less. Q: Is 300 seconds the right threshold below which tiering is not worth it, or should it be lower or higher?
A8. [test, high] plan-lint accepts the three Step 1 forms, and fails a `Covered by Task <N>` naming a missing task, a task with no test step, or a task that does not run before the citing task (a higher number in a sequential plan, the same or a later wave in a wave plan).
A9. [test, high] `criteria/plan-review.md` carries the "Redundant test" criterion, scored LOW, with the reviewer naming the overlapping test.
A10. [test, high] The TDD skill's "Minimal" row is replaced by the one-behaviour, parametrized-variants rule, and `writing-good-tests.md` asks whether an existing test already fails for the change.
A11. [test, neg, high] Neither the REFACTOR rule nor the final-review fix wave deletes a test that exists at the branch's merge base, or a regression test naming a fixed bug.
A12. [test, high] The `test-quality` lens carries a `{#redundant}` criterion that names the covering test.
A13. [test, medium] closing-a-milestone recommends a scoped test-simplifier run when the full suite grew by 20% or more, or passes a declared `Budget:`. Q: Is 20% growth the right trigger?
A14. [test, high] test-simplifier's Phase 3 uses the tier names of `reference/test-tiers.md`, accepts `--modules` and `--since` scopes, lists the "Subsumed scaffolding" class, and states the division of labour with the branch-level cleanup.
A15. [test, high] plan-lint fails a plan without a `**CI:**` line, and a malformed one; `none` passes.
A16. [test, high] `ci-mirror` runs every `local:` command of the CI line through `suite-run`, prints `uncovered: <platforms>`, exits non-zero when one command fails, and prints `ci: none` with exit 0 for `none`.
A17. [test, neg, high] With no `**Early CI:**` line, no step of the controller pushes the branch or triggers CI before finishing. With the line present, the controller never opens a pull request to start CI.
A18. [test, high] Finishing waits for the CI run of the pushed commit, bounded at 90 minutes, and never reports the branch done while that run is red or still running.
A19. [test, high] writing-plans copies the pitfalls-table rows for each uncovered platform into `## Global Constraints`.
A20. [test, high] `lint-portability.mjs` flags each of its four rules on a fixture line, passes the same line carrying the exemption comment, and runs from `validate-repository.mjs`.
A21. [test, high] `test-shards.test.mjs` fails for a discovered suite with no weight, and for a weight above 80% of its limit.
A22. [test, high] `test-all.mjs` prints a `::warning::` naming a suite whose duration passes 75% of its limit.
A23. [test, neg, high] An existing `gates.md` with no `Tier:` field runs exactly the gates it ran before.

## Riskiest assumption

That a fast task check, plus the full suite only at wave checks, the final review and every third task when there is no fast check, catches regressions early enough that the final-review fix wave does not grow to cost what the per-task suite runs saved.

Evidence: Meta reports catching over 99.9% of regressions while running about a third of the tests through predictive selection ([engineering.fb.com, 2018](https://engineering.fb.com/2018/11/21/developer-tools/predictive-test-selection/)). Google defers broad testing until after submission for the same cost reason ([research.google/pubs/pub52465](https://research.google/pubs/pub52465)). Locally, attribution to the right task is already supported: `task-step` compares a sequential group with its first member's base (`plugins/dforge/scripts/task-step:126`), which `--suite-base` generalises. No local history measures how often the per-task suite caught a regression that focused tests missed: the ledgers in `.dforge/sdd` hold no suite verdicts (checked 2026-10-31), and the darkmem mirror was unreachable this session. Residual risk is bounded by the early CI run and the every-third-task fallback. The first plan executed after this work records, in its final review, how many final-suite failing lines no task check caught.
