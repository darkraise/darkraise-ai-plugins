# Measured Proposals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evidence-bound, diff-first review prompts (kept only if a replay shows no harm), plan-lint path checks, a stack-grouped code-quality lens, removal of the dead task-step skip, and lean plan tests (kept only if a measurement passes).

**Architecture:** Prompt and procedure edits in dforge's skills and references, with two measured changes whose task runs its own measurement and reverts on failure. Script changes in `plan-lint` (a path and range check in its per-task loop), `lens-route` (route-time grouping of six existing lens files) and `task-step` (option removal).

**Tech Stack:** Bash scripts and bash test suites, Node (`.mjs`) config schema and test runner, Markdown skills, references and criteria.

**Spec:** `docs/dforge/specs/2026-11-15-measured-proposals-design.md`

**Execution:** inline — `claude --model opus --effort high` — Tasks 1, 2, 3 and 7 total 7

**Parallelism:** sequential — inline execution

**Task check:** `timeout 1500 node scripts/test-all.mjs --jobs 6 && timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate . && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge` — the full suite last passed in 287 s

**Integration check:** `timeout 1500 node scripts/test-all.mjs --jobs 6 && timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate . && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge`

**CI:** `.github/workflows/validate.yml` — platforms: uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/test-all.mjs`; `node scripts/validate-repository.mjs`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: uutils (ubuntu-latest), Windows Git Bash

## Global Constraints

- Paths below are repository-relative; `plugins/dforge/` is the plugin root.
- English only; commits are `<type>(<scope>): <subject>`, subject at most 50 characters, imperative, no period, author `Darkraise <quangtc94@gmail.com>`, no AI attribution of any kind.
- Never push: the branch stays local and merges into `main` locally at the end (spec `Finish: merge`).
- Every command that runs a test, a build or a CLI carries an explicit `timeout`; every process a task starts is stopped before the task closes.
- Measurements run in scratch clones under the session's scratchpad directory, never in this checkout, and spend no API budget: subscription seats only.
- `plugins/dforge/criteria/plan-review.md` stays ASCII (`plugins/dforge/tests/criteria.test.sh:55-56`).
- Do not touch `plugins/dforge/README.md:22` (a heading in the fork's history).
- Windows Git Bash: a native program (`git.exe`, `jq.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset). Convert the path with `cygpath -m` before the call (dforge's `dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
- Windows Git Bash: the same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches. Normalise both sides with `cygpath -m`, or compare with `-ef`.
- Windows Git Bash: files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep. Pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes in the value, so a regex or a Windows path changes. Pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails. Import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): a lock built on `mkdir` failing when the directory exists does not exclude a second process. Create the lock file with `set -C` (noclobber), or use `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started, so the command's children keep running. Run the command in its own process group (`setsid`) and signal the group.

## Contracts

- **C1 plan-lint path errors** (Task 2). Two new error lines, in plan-lint's existing `ERROR Task <N>: ...` form:
  `ERROR Task <N>: <path> does not exist and no earlier task creates it` and
  `ERROR Task <N>: <path>:<range> is outside the file's <n> lines`, where `<range>` is the range text as written and `<n>` the file's line count (an unterminated last line counted).
- **C2 `plan_task_paths --detail`** (Task 2, `plugins/dforge/scripts/lib/plan.sh`). Reads task text on stdin; prints one line per `- Create:`, `- Modify:`, `- Test:` or `- Delete:` line outside fences, in order, not deduplicated: `<kind><TAB><path><TAB><range>`, where `<kind>` is the word before the colon, `<path>` the first code span with any range and a leading `./` removed, and `<range>` the removed `:`-suffix without its colon (`12`, `3-9`, `35-44,66-72`) or empty. Without `--detail` the output is unchanged.
- **C3 code-quality route line** (Task 3, consumed by Task 4's prose). `lens-route --final` prints, in `lens_order` position after test-quality:
  `lens code-quality parts=<p1>,<p2>,... seat=dforge:judge-sonnet-high reason=<reason>`, each `<p>` an absolute path to a part file in `plugins/dforge/criteria/lenses/`, in the order lang-bash, lang-csharp, lang-python, lang-typescript, type-design, docs-comments (only the matching ones); `<reason>` is the first matching part's reason. When skipped: `lens-skipped code-quality reason=<cap|depth>`. When no part applies: no line. The part ids are `lang-bash`, `lang-csharp`, `lang-python`, `lang-typescript`, `type-design`, `docs-comments`; `--final` prints no line naming a part id. `--task` output is unchanged.
- **C4 lensCap default** (Task 3). `5` in `plugins/dforge/config/schema.mjs` and both fallbacks of `plugins/dforge/scripts/lens-route`.
- **C5 code-quality retained line** (Task 4). `final review lens code-quality — <c> Critical, <i> Important, <m> Minor; fixed <f>, rejected <r>; parts <id>=<findings>,...`, counting findings tagged with any part's `[lens:<part id>]`; the seat's report is `<workspace>/lens-code-quality-report.md`.
- **C6 not-reproduced rejection** (Task 1). `REJECTED: <finding> — not reproduced: <what was run and its result>`, the finding keeping its `[lens:<id>]` tag.
- **C7 test contract entry** (Task 7). `` - `<test file>::<test name>` (<unit|integration|e2e>): given <input or state>, asserts <exact observable result>; fails today because <fault>. ``

## Assumptions (evidence)

- The Agent tool result reports a dispatch's total tokens as `subagent_tokens` in its `<usage>` block: seen on the Explore and judge-fable dispatches of 2026-11-15 (this session). M1 reads that number.
- M1's six commits exist: `git cat-file -t` on `b36eaf63`, `bc097711`, `5bb5545f`, `e48eeafa`, `9d46f4e`, `52da46e0` (2026-11-15; the last four checked by the spec review and this session).
- b3 (`5bb5545f..e48eeafa`) implemented `docs/dforge/plans/2026-11-13-reviewer-only-externals.md` (`git log 5bb5545f..e48eeafa -- docs/dforge/plans`, 2026-11-15); the dflow-hud range implemented `docs/dforge/plans/2026-11-13-dflow-hud-overhaul.md`; b1 has no plan.
- `scripts/review-package` takes `PLAN_FILE BASE HEAD [OUTFILE]` (`plugins/dforge/scripts/review-package:7`).
- `plugins/dforge/tests/plan-amend.test.sh::pre-existing errors: accepted` (`:129-134`) already proves plan-amend accepts an amendment to a plan with errors it did not add; the comparison is by `comm` over all ERROR lines (`plugins/dforge/scripts/plan-amend:133-136`), so it holds for C1's errors (A4).
- `lens-route` is the only script that prints lens lines, and `task-step` (`:757-764`) is the only script that parses them, `--task` lines only (rg over `plugins/dforge/scripts`, 2026-11-15). `--final` lines are read by the session.
- The full suite last passed in 287 s (`.dforge/suites.tsv`, 2026-11-15), so the Task check is the full suite.
- `dforge:impl-sonnet-high` and `dforge:judge-opus` are dispatchable seats in this session (the session's agent list, 2026-11-15).
- The plan-lint fixtures and the plan-amend fixture name `a.txt` on a Modify line after a Create line (`plugins/dforge/tests/plan-lint.test.sh:91,106`), which the new check accepts; any other fixture the check breaks is found by the suite in Task 2 Step 4.

## Task index

1. Evidence-bound review prompts and the M1 replay
2. plan-lint path and range checks
3. Group the code-quality lens in lens-route
4. Describe the code-quality lens in the review references
5. Remove the task-step small-fix re-review skip
6. Drop the stale implementer wording
7. Lean plan tests and the M2 check

---

### Task 1: Evidence-bound review prompts and the M1 replay

**Files:**
- Modify: `plugins/dforge/skills/requesting-code-review/references/code-reviewer.md`
- Modify: `plugins/dforge/reference/final-review.md`
- Modify: `plugins/dforge/skills/writing-plans/references/plan-reviewer-prompt.md`
- Modify: `plugins/dforge/reference/prompts/re-review-prompt.md`
- Create: `docs/dforge/notes/2026-11-15-review-prompt-replay.md`

**Interfaces:**
- Consumes: none.
- Produces: C6.

**Items:** 3, 4
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: No new test, because these are prompt and procedure files no script reads; M1 (Step 4) measures the change**

- [ ] **Step 2: Record the pre-change commit**

Run: `git rev-parse HEAD`
Expected: a sha; write it down as PRE. Step 4's old arm reads `git show PRE:plugins/dforge/skills/requesting-code-review/references/code-reviewer.md`.

- [ ] **Step 3: Edit the prompts**

1. `code-reviewer.md`: in `## What to Check` or directly before it, add the evidence rule and the diff-first rule; in `## Output Format`, add below each finding an indented `Evidence:` line (either the input, state or command that reaches the defect and the wrong result it gives, or a quoted spec, plan or brief line the change breaks, with its location), state that a finding without one is not reported, that style preferences are not findings, and change the Minor definition from "code style, optimization and documentation polish" to optimisation and documentation defects. Add a last report section `## Opened` with one `- <path> — <the question>` line per repository file opened outside the diff. Update the Example Output (about `:149-176`) so its findings carry `Evidence:` lines and the report ends with `## Opened`. Replace "read the diff file and the repository files it touches" in `## Read-Only Review` with: read the diff file once; open a repository file only for a range a hunk names or for a question that fits one sentence; grep for the named symbol rather than crawling.
2. `final-review.md`, lens prompt (the fenced block near `:280-295`): each finding's indented detail lines include its `Evidence:` line; raise "at most three lines" to "at most four lines"; add the diff-first sentence and the `## Opened` section to the report shape.
3. `final-review.md`, §Fixing what it finds: in "With one list the fixer first checks each finding" (about `:408-416`), state that with one list and with two the fixer reproduces each finding before fixing it, by running the input or command the finding's `Evidence:` line names at the review HEAD, or, for a quoted-line finding, by showing the quoted line beside the code or text that breaks it; a finding whose run contradicts it is recorded as C6. `[qa]`, `[suite]` and `[ci]` findings and carried gaps are exempt. Remove "in the one-list case" where it limits this triage (about `:427-428`).
4. `re-review-prompt.md` (about `:105-108`): add one sentence: a `not reproduced` rejection is upheld when the fix report shows the run and its result contradicts the finding.
5. `plan-reviewer-prompt.md`: in both templates' shared body (`## Findings`, about `:35-49`, and its Later rounds counterpart), add the evidence requirement (a finding cites the plan or spec line it concerns, quoted, or the command that shows the defect) and the diff-first rule (the plan is the diff; open code only to check a claim a task makes about it). In `## Output Format` (Claude seats only), add the indented `Evidence:` line and the `## Opened` section.
6. Commit: `git add` the four files, `git commit -m "feat(dforge): require evidence in review findings"`. Write down the sha as P1.

- [ ] **Step 4: Run M1**

1. For each range — b1 `b36eaf63..bc097711`, b3 `5bb5545f..e48eeafa` (plan `docs/dforge/plans/2026-11-13-reviewer-only-externals.md`), d `9d46f4e..52da46e0` (plan `docs/dforge/plans/2026-11-13-dflow-hud-overhaul.md`) — clone this repository into `<scratchpad>/m1-<name>` (`git clone -q`), check out the range's head, and build one package with `timeout 120 bash plugins/dforge/scripts/review-package <plan> <base> <head> <scratchpad>/m1-<name>.diff` run from this checkout (b1 passes the b3 plan path, since it has none; the package depends on BASE and HEAD). b1's `[PLAN_OR_REQUIREMENTS]` is its commit subjects (`git log --format=%s b36eaf63..bc097711`); the others' is their plan path.
2. For each range, dispatch `dforge:judge-opus` four times, one at a time, cwd the clone: twice with the old prompt (`git show PRE:...code-reviewer.md`, placeholders filled) and twice with the new one, each writing `<scratchpad>/m1-<name>-<old|new>-<k>-report.md`. Record each dispatch's `subagent_tokens`. A seat that fails twice for one run ends M1 as not passed.
3. Build one shuffled list of every finding from the twelve reports, each as `<file>:<line> — <one-liner>` plus its detail lines with every `Evidence:` line removed and no report or prompt named; keep the key (finding → run) out of the list's file. Dispatch one fresh `dforge:judge-opus` to mark each CONFIRMED (a real defect of that range's diff) or UNCONFIRMED, writing `<scratchpad>/m1-verdicts-report.md`.
4. Write `docs/dforge/notes/2026-11-15-review-prompt-replay.md`: per run, the findings by severity, confirmed Critical and Important, unconfirmed share (0 when a run has no findings), and tokens; then the sums per arm and the keep rule's result: kept when new confirmed Critical+Important ≥ old, and new total tokens < old or new unconfirmed share < old. State that M1 measures code-reviewer.md only; the lens prompt, the plan-reviewer prompt and the fixer rule are judged by that proxy.

- [ ] **Step 5: Keep or revert**

If the rule held: nothing to undo. If it failed or M1 could not finish: `git revert --no-edit P1`, and the note says why. Then:

Run: `timeout 60 bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-15-measured-proposals.md 3 <done|n/a> --note "<kept|reverted>: docs/dforge/notes/2026-11-15-review-prompt-replay.md"` and the same for row 4.
Expected: `register: 0 errors` from `bash plugins/dforge/scripts/register check docs/dforge/registers/2026-11-15-measured-proposals.md`.

- [ ] **Step 6: Run the task check**

Run: the Task check.
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add docs/dforge/notes/2026-11-15-review-prompt-replay.md docs/dforge/registers/2026-11-15-measured-proposals.md
git commit -m "docs(notes): record the review prompt replay"
```

### Task 2: plan-lint path and range checks

**Files:**
- Modify: `plugins/dforge/scripts/plan-lint`
- Modify: `plugins/dforge/scripts/lib/plan.sh`
- Modify: `plugins/dforge/skills/writing-plans/references/plan-reviewer-prompt.md`
- Modify: `scripts/test-all.mjs`
- Test: `plugins/dforge/tests/plan-lint.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: C1, C2.

**Items:** 1
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/plan-lint.test.sh`, change `ALL="one two"` to `ALL="one two paths"`, and add this part before the final `printf '\n%d passed...` line:

```bash
if want paths; then
# The path check: Modify and Test paths exist or an earlier task creates them,
# and ranges fit the file. Fixture lines carry a leading | so this suite lints.
mkdir -p "$TMP/paths" && cd "$TMP/paths" || exit 1
mkdir -p docs && printf '# Spec\n' > docs/spec.md
printf 'one\ntwo\nthree\n' > a.txt
printf 'x\ny' > b.txt
paths_plan() { # paths_plan <task 2 files lines> <task 2 step 1 heading>
  sed 's/^|//' <<EOF
|# Paths Plan
|
|**Goal:** Demo.
|
|**Spec:** \`docs/spec.md\`
|
|**Execution:** inline — \`claude --model sonnet --effort low\` — small
|
|**Task check:** none — full suite every 3 tasks
|
|**Integration check:** \`bash test.sh\`
|
|**CI:** none
|
|## Global Constraints
|
|- Bash only.
|
|## Contracts
|
|None
|
|## Assumptions (evidence)
|
|- None.
|
|## Task index
|
|1. Make
|2. Use
|
|### Task 1: Make
|
|**Files:**
|- Create: \`made.txt\`
|- Delete: \`gone.txt\`
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|- [ ] **Step 1: No new test, because it only creates a file**
|
|### Task 2: Use
|
|**Files:**
$1
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|- [ ] **Step 1: $2**
EOF
}
lint_paths() { paths_plan "$1" "${2:-Write the failing test}" > plan.md; bash "$LINT" plan.md 2>&1; }

out=$(lint_paths '- Modify: `missing.txt`')
has "paths: a missing Modify path is an error" "$out" "ERROR Task 2: missing.txt does not exist and no earlier task creates it"
out=$(lint_paths '- Test: `tests/missing.test.sh`' 'No new test, because it is prose')
has "paths: a missing Test path outside a Write-the-failing-test task is an error" "$out" "ERROR Task 2: tests/missing.test.sh does not exist and no earlier task creates it"
out=$(lint_paths '- Test: `tests/new.test.sh`')
lacks "paths: a Test path of a Write-the-failing-test task counts as created" "$out" "tests/new.test.sh does not exist"
out=$(lint_paths '- Modify: `made.txt`')
lacks "paths: a path an earlier task creates is not an error" "$out" "made.txt does not exist"
out=$(lint_paths '- Create: `fresh.txt`
|- Delete: `nowhere.txt`')
lacks "paths: Create and Delete paths are not checked" "$out" "does not exist"
out=$(lint_paths '- Modify: `src/*.sh`')
lacks "paths: a span holding * is not checked" "$out" "does not exist"
out=$(lint_paths '- Modify: `a.txt:2-3`
|- Modify: `a.txt:1-2,3`
|- Modify: `b.txt:2`')
lacks "paths: valid single, list and unterminated-last-line ranges pass" "$out" "is outside the file"
out=$(lint_paths '- Modify: `a.txt:3-4`')
has "paths: an end beyond the file is an error" "$out" "ERROR Task 2: a.txt:3-4 is outside the file's 3 lines"
out=$(lint_paths '- Modify: `a.txt:0`')
has "paths: a start below 1 is an error" "$out" "ERROR Task 2: a.txt:0 is outside the file's 3 lines"
out=$(lint_paths '- Modify: `a.txt:3-2`')
has "paths: a start above its end is an error" "$out" "ERROR Task 2: a.txt:3-2 is outside the file's 3 lines"
out=$(lint_paths '- Modify: `made.txt:40-50`')
lacks "paths: a range on a created path is not checked" "$out" "is outside the file"
cd "$TMP" || exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/plan-lint.test.sh paths`
Expected: FAIL on the four `has` checks for missing paths and bad ranges (plan-lint prints no such errors yet).

- [ ] **Step 3: Implement**

1. `plan_task_paths` in `plugins/dforge/scripts/lib/plan.sh`: add the `--detail` mode exactly as C2 states; without the flag the output stays byte-identical.
2. `plugins/dforge/scripts/plan-lint`: inside the existing per-task loop (about `:275-277`, where the task text is already held), call `plan_task_paths --detail` on that text, keep a running set of created paths (each task's `Create` paths, and its `Test` paths when the task's Step 1 heading is `Write the failing test`), and for each `Modify` or `Test` path: skip a path containing `*`; resolve it against the top level of `_plan_ctx "$plan"` (`plugins/dforge/scripts/lib/plan.sh:228-237`); print C1's first error when it neither exists nor is in the created set (this task's own creations included). For an existing file with a non-empty range, count its lines once (awk `END { print NR }`, which counts an unterminated last line) and print C1's second error when any comma-separated item `a` or `a-b` breaks `1 <= a <= b <= n`. Ranges on created paths are not checked. Add no subprocess per path without a range.
3. `plan-reviewer-prompt.md`: in the `**plan-lint output:**` line (about `:21-22`), say that path existence and line ranges are among the checks already run.
4. `scripts/test-all.mjs`: change `'plan-lint.test.sh': [['one'], ['two']]` to `[['one'], ['two'], ['paths']]`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 900 bash plugins/dforge/tests/plan-lint.test.sh paths && timeout 900 bash plugins/dforge/tests/plan-lint.test.sh one two && timeout 300 bash plugins/dforge/tests/plan-amend.test.sh`
Expected: PASS, `0 failed` in each. A fixture elsewhere that now fails on C1 gets the missing file created in its fixture setup, not a weaker check.

- [ ] **Step 5: Run the task check**

Run: the Task check, then `timeout 60 bash plugins/dforge/scripts/plan-lint docs/dforge/plans/2026-11-15-measured-proposals.md`.
Expected: PASS, and this plan's own lint reports `0 errors`; an error on a path or range of an already-completed task is stale, not a defect, and is recorded in the ledger.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/plan-lint plugins/dforge/scripts/lib/plan.sh plugins/dforge/tests/plan-lint.test.sh plugins/dforge/skills/writing-plans/references/plan-reviewer-prompt.md scripts/test-all.mjs
git commit -m "feat(dforge): check plan task paths and ranges"
```

### Task 3: Group the code-quality lens in lens-route

**Files:**
- Modify: `plugins/dforge/scripts/lens-route`
- Modify: `plugins/dforge/config/schema.mjs`
- Test: `plugins/dforge/tests/lens-route.test.sh`
- Test: `plugins/dforge/tests/dforge-config.test.sh`
- Test: `plugins/dforge/tests/review-depth.acceptance.test.sh`
- Test: `plugins/dforge/tests/review-depth-qa.acceptance.test.sh`
- Test: `plugins/dforge/tests/test-volume-rules.acceptance.test.sh`
- Test: `plugins/dforge/tests/ui-ux-skill.acceptance.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: C3, C4.

**Items:** 2
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Extend the test `plugins/dforge/tests/lens-route.test.sh::final: a shell-only change gets security and lang-bash`**

In `plugins/dforge/tests/lens-route.test.sh`:

1. Replace `short()` with a version that also strips the parts field, and add a parts reader:

```bash
short() { sed -E 's/ criteria=[^ ]*//; s/ parts=[^ ]*//; s/ seat=[^ ]*//; s/ reason=(always|added|ui-paths|paths:[^ ]*)$//' | tr '\n' ';'; }
parts() { sed -n 's/^lens code-quality parts=\([^ ]*\) .*/\1/p' | tr ',' '\n' | sed 's#.*/##' | tr '\n' ' '; }
```

2. Replace these checks (old name → new line):

```bash
check "final: a shell-only change gets security and code-quality" "$(short <<<"$out")" "lens security;lens code-quality;"
check "final: code-quality carries only the matching part" "$(parts <<<"$out")" "lang-bash.md "
check "final: no lens line names a part id" "$(grep -cE '^lens(-skipped)? (lang-|type-design|docs-comments)' <<<"$out")" "0"
check "final: the seat and reason" "$(grep -c '^lens security criteria=[^ ]* seat=dforge:judge-sonnet-high reason=always$' <<<"$out")" "1"
crit=$(sed -n 's/^lens code-quality parts=\([^, ]*\).*/\1/p' <<<"$out")
check "final: the part path exists" "$([ -f "$crit" ] && echo yes || echo no)" "yes"
check "final: the reason names the first part's glob" "$(grep -c '^lens code-quality parts=[^ ]* seat=dforge:judge-sonnet-high reason=paths:\*\.sh$' <<<"$out")" "1"
```

the non-ASCII check becomes

```bash
check "final: a non-ASCII file name still matches its part's paths" "$(parts <<<"$out")" "lang-python.md "
```

and the cap and floor checks become

```bash
check "cap 2: two lenses, the rest skipped in order" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens-skipped test-quality reason=cap;lens-skipped code-quality reason=cap;"
out=$(bash "$ROUTE" plan.md --final "$BASE" "$HEAD2")
check "default cap 5" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens test-quality;lens code-quality;"
check "default cap: parts in their fixed order" "$(parts <<<"$out")" "lang-bash.md lang-typescript.md docs-comments.md "
check "floor: a plan under the threshold gets the floor after the lenses" "$(short <<<"$out")" \
  "lens security;lens code-quality;lens-floor important tasks=3 from=4;"
```

(the floor check keeps its own `out=$(DFORGE_LENS_MINOR_FROM=4 ...)` line above it.)

3. Replace the depth checks' expected strings:

```bash
check "light: security only, every other applicable lens skipped for its depth" "$(short <<<"$out")" \
  "lens security;lens-skipped silent-failures reason=depth;lens-skipped test-quality reason=depth;lens-skipped code-quality reason=depth;"
check "light: lensCap 1 still keeps security, the rest skipped for depth" "$(short <<<"$out")" \
  "lens security;lens-skipped silent-failures reason=depth;lens-skipped test-quality reason=depth;lens-skipped code-quality reason=depth;"
check "light: the floor counts the one lens printed" "$(short <<<"$out")" \
  "lens security;lens-skipped code-quality reason=depth;lens-floor important tasks=1 from=4;"
check "standard: code-quality and test-quality sit outside the two-lens limit" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens test-quality;lens code-quality;"
check "standard: lensCap 2 skips test-quality and code-quality for the cap" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens-skipped test-quality reason=cap;lens-skipped code-quality reason=cap;"
check "standard: with no test file changed, code-quality still runs" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens code-quality;"
check "full: the default cap of 5" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens test-quality;lens code-quality;"
check "a light spec with a risk-2 task is standard: four lenses with test-quality and code-quality" "$(grep -c '^lens ' <<<"$out")" "4"
check "light: security prints nothing when its Applies clause does not match" "$(short <<<"$out")" \
  "lens-skipped silent-failures reason=depth;lens-skipped test-quality reason=depth;lens-skipped code-quality reason=depth;"
check "standard: without security, test-quality and code-quality use no slot" "$(short <<<"$out")" \
  "lens silent-failures;lens test-quality;lens code-quality;"
check "ui-ux: no profile and no contract: not routed" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens test-quality;lens code-quality;"
check "ui-ux: with a profile it is second and survives the default cap" "$(short <<<"$out")" \
  "lens security;lens ui-ux;lens silent-failures;lens test-quality;lens code-quality;"
```

The checks `standard: a lower lensCap wins` (1), `standard: lensCap 3 keeps test-quality as the third` (3), `a light spec with a risk-3 task is full: four lenses` (4), the two `routes at full` checks (4), every `--task` check and `a Codex-host plan exits 2` keep their expected values. Any other check after `:226` whose expected string names a part id as a lens takes the same mapping: the part lines go, and one `lens code-quality` (or `lens-skipped code-quality reason=<same reason>`) line stands after test-quality's position.

4. Add, after the `final: the reason names the first part's glob` check:

```bash
# A9: no part applies, so code-quality prints no line of either kind.
git checkout -q "$HEAD1"
commit_file data.json '{}'
out=$(bash "$ROUTE" plan.md --final "$HEAD1" "$(git rev-parse HEAD)")
check "final: no part applies, no code-quality line" "$(grep -c 'code-quality' <<<"$out")" "0"
git reset -q --hard "$HEAD1"
```

5. In `plugins/dforge/tests/dforge-config.test.sh:162`, change the expected `lensCap` default from `4` to `5`.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/lens-route.test.sh; timeout 300 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: FAIL: lens-route still prints part lens lines and caps at 4; dforge-config prints 4.

- [ ] **Step 3: Implement**

1. `lens_order` in `plugins/dforge/scripts/lens-route`: security, ui-ux, silent-failures, test-quality, `code-quality`, then any other lens file not a part. The part list is a fixed constant in the script: `lang-bash lang-csharp lang-python lang-typescript type-design docs-comments`.
2. `--final`: for `code-quality`, run `lens_match` on each part in that order; it applies when any part matches; print C3's line (or its skipped form). Count it toward `n` (lensCap) but, like test-quality, not toward `others` (standard's two-lens limit). Light depth skips it with `reason=depth`. No line when no part matches.
3. C4: the `lensCap` default `5` in `plugins/dforge/config/schema.mjs:147` (its description names code-quality instead of "the language lenses, type design, docs") and both fallbacks at `plugins/dforge/scripts/lens-route:112-113`; update the script's header comment (`:11-24`) to describe the code-quality line.
4. `--task`: unchanged.
5. `review-depth.acceptance.test.sh` (`:331-337`), `review-depth-qa.acceptance.test.sh` (`:361`, `:385-399`), `test-volume-rules.acceptance.test.sh` (`:211-255`) and `ui-ux-skill.acceptance.test.sh` (`:806-839`): update each expected lens-route line by the Step 1 mapping (part lens lines become one code-quality line after test-quality; counts of `^lens ` lines rise where code-quality now runs). Change only expected values that the grouping changes.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/lens-route.test.sh && timeout 300 bash plugins/dforge/tests/dforge-config.test.sh && timeout 900 bash plugins/dforge/tests/review-depth.acceptance.test.sh && timeout 900 bash plugins/dforge/tests/review-depth-qa.acceptance.test.sh && timeout 900 bash plugins/dforge/tests/test-volume-rules.acceptance.test.sh && timeout 900 bash plugins/dforge/tests/ui-ux-skill.acceptance.test.sh`
Expected: PASS, `0 failed` in each.

- [ ] **Step 5: Run the task check**

Run: the Task check.
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/lens-route plugins/dforge/config/schema.mjs plugins/dforge/tests/lens-route.test.sh plugins/dforge/tests/dforge-config.test.sh plugins/dforge/tests/review-depth.acceptance.test.sh plugins/dforge/tests/review-depth-qa.acceptance.test.sh plugins/dforge/tests/test-volume-rules.acceptance.test.sh plugins/dforge/tests/ui-ux-skill.acceptance.test.sh
git commit -m "feat(dforge): group code lenses into code-quality"
```

### Task 4: Describe the code-quality lens in the review references

**Files:**
- Modify: `plugins/dforge/reference/final-review.md`
- Modify: `plugins/dforge/README.md`
- Modify: `plugins/dforge/reference/native-codex.md`
- Modify: `plugins/dforge/skills/writing-plans/references/assignment-procedure.md`

**Interfaces:**
- Consumes: C3, C4.
- Produces: C5.

**Items:** 2
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: No new test, because these references are read by the session and by seats, not by a script; Task 3's tests pin the route line they describe**

- [ ] **Step 2: Edit the references**

1. `final-review.md:50` and `:274-278`: the depth text says standard keeps at most two lenses besides test-quality and code-quality, which it adds whenever they apply, within `lensCap` (default 5).
2. `final-review.md`, the lens prompt and the **Lenses.** paragraph (about `:259-295`): for a `lens code-quality parts=...` line, the prompt reads "Read the lenses at these part files: <parts>", the paths from `parts=`; its report is `<workspace>/lens-code-quality-report.md`; each finding keeps its part's own `[lens:<part id>]` tag; the dedupe judge and the fixer receive the part paths.
3. `final-review.md`, Retained lines (about `:483-489`): add C5 for code-quality.
4. `README.md:102` and `:916`: the lens row and the `lensCap` row say default `5`, list the lenses as security, ui-ux, silent failures, test quality and code quality (the language lenses, type design and docs grouped by the change's stack), and give standard's limit as at most 2 plus test-quality and code-quality.
5. `native-codex.md:306-313`: the priority list becomes security, ui-ux, silent-failures, test-quality, code-quality; a Codex host picks code-quality's parts by hand by reading each part file's `Applies:` line against the branch diff, and runs them as one lens seat.
6. `assignment-procedure.md`, the `**Lenses:**` bullet (`:40-44`): add that the line names part ids (`lang-bash`, `type-design`, ...), never `code-quality`.

- [ ] **Step 3: Run the task check**

Run: the Task check.
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add plugins/dforge/reference/final-review.md plugins/dforge/README.md plugins/dforge/reference/native-codex.md plugins/dforge/skills/writing-plans/references/assignment-procedure.md
git commit -m "docs(dforge): describe the code-quality lens"
```

### Task 5: Remove the task-step small-fix re-review skip

**Files:**
- Modify: `plugins/dforge/scripts/task-step`
- Modify: `plugins/dforge/reference/delegated-task.md`
- Test: `plugins/dforge/tests/task-step.test.sh`
- Test: `plugins/dforge/tests/task-loop-steps.acceptance.test.sh`
- Test: `plugins/dforge/tests/task-step-base.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: none.

**Items:** 6
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Extend the test `plugins/dforge/tests/task-step.test.sh::skips a one-line fix`**

In the `if want rereview; then` part of `plugins/dforge/tests/task-step.test.sh`, replace the twelve `rr_case` skip-rule rows (from `# The skip rule:` through `reads a backticked finding path with a line suffix`) and the `# A skipped round still packages the fix and advances the state.` block (through its `rereview skip: no prompt is written` check) with:

```bash
# Every fix round gets its re-review: there is no small-fix skip.
rr_case "prompts for a one-line fix" 1 "" "- app.txt: wrong value" "app.txt:mod" "0 prompt"
rr_case "prompts for a one-line fix on a risk 3 task" 2 "" "- app.txt: wrong value" "app.txt:mod" "0 prompt"
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 1 --covered
check "rereview: --covered is a usage error" "$rr_rc" "2"
```

In the block that follows (`# With the plan's other tasks complete the digest's budget line names the tail`) and in the `# A written prompt:` block, drop `--covered` from each `rr_run rereview ...` call. In `tests/task-step.test.sh:93` and `:293`, and in `tests/task-loop-steps.acceptance.test.sh` (`:112`, `:245`, `:371-401`) and `tests/task-step-base.test.sh` (`:251-293`), remove each `--covered` argument and each assertion about a skipped re-review (`re-review: skipped`, `suite_gap`, the skipped digest); a case whose whole subject is the skip is deleted.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 900 bash plugins/dforge/tests/task-step.test.sh rereview`
Expected: FAIL on `rereview: --covered is a usage error` (the option is accepted today, exit 0). The two `prompts for` rows pass today: they pin behaviour the removal must keep.

- [ ] **Step 3: Implement**

1. `plugins/dforge/scripts/task-step`: remove the `--covered` option from usage and parsing (`:10`, `:36`, `:307`, `:343`, `:352`), so passing it is a usage error (exit 2, as any unknown option); remove the skip decision (`:428-452`), `suite_gap` (`:287-304`) and the skipped digest (`:488-490`, `:494`). The re-review always writes its prompt.
2. `plugins/dforge/reference/delegated-task.md`: remove `:431-432`, `:435`, `:455-473`, the `[; re-review skipped (<n> lines)]` clause at `:476` and `:604`, and "its skip rule included" at `:602`; every fix round gets its re-review.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 900 bash plugins/dforge/tests/task-step.test.sh && timeout 1200 bash plugins/dforge/tests/task-loop-steps.acceptance.test.sh && timeout 1200 bash plugins/dforge/tests/task-step-base.test.sh`
Expected: PASS, `0 failed` in each; `rg -n 'covered|suite_gap|re-review skipped' plugins/dforge/scripts/task-step plugins/dforge/reference/delegated-task.md` prints nothing.

- [ ] **Step 5: Run the task check**

Run: the Task check.
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/reference/delegated-task.md plugins/dforge/tests/task-step.test.sh plugins/dforge/tests/task-loop-steps.acceptance.test.sh plugins/dforge/tests/task-step-base.test.sh
git commit -m "refactor(dforge): drop the small-fix re-review skip"
```

### Task 6: Drop the stale implementer wording

**Files:**
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md`
- Modify: `plugins/dforge/criteria/plan-review.md`
- Modify: `plugins/dforge/skills/writing-plans/references/plan-reviewer-prompt.md`
- Modify: `plugins/dforge/skills/writing-plans/references/assignment-procedure.md`

**Interfaces:**
- Consumes: none.
- Produces: none.

**Items:** 5
**Evaluation:** files 2 - spec 2 - coupling 0 - risk 0 = 4

- [ ] **Step 1: No new test, because the edit is prose no script reads; `plugins/dforge/tests/criteria.test.sh` already checks plan-review.md's shape and ASCII**

- [ ] **Step 2: Edit the wording**

Remove each sentence saying that a task's implementer sees only that task's text, or that small models execute the plan literally, from `SKILL.md:17-19` and `:195-197`, `plan-review.md:11` and `:14-16`, `plan-reviewer-prompt.md:6`, `:24-26` and `:153-155`, and `assignment-procedure.md:19-20`. Where the sentence carried an instruction (judge each task from its own text plus the header), replace it with: the session implements every task and reads it through its brief, which carries the task text with amendments plus the header's Global Constraints and Contracts. Keep `README.md:22`.

- [ ] **Step 3: Verify the wording is gone**

Run: `rg -n -i "implementer sees only|small models (will )?execute" plugins/dforge/skills plugins/dforge/criteria plugins/dforge/reference`
Expected: no output.

- [ ] **Step 4: Run the task check**

Run: the Task check.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/writing-plans/SKILL.md plugins/dforge/criteria/plan-review.md plugins/dforge/skills/writing-plans/references/plan-reviewer-prompt.md plugins/dforge/skills/writing-plans/references/assignment-procedure.md
git commit -m "docs(dforge): drop the stale implementer wording"
```

### Task 7: Lean plan tests and the M2 check

**Files:**
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md`
- Modify: `plugins/dforge/skills/writing-plans/references/test-step-forms.md`
- Modify: `plugins/dforge/criteria/plan-review.md`
- Modify: `plugins/dforge/skills/writing-plans/references/plan-reviewer-prompt.md`
- Modify: `plugins/dforge/README.md`
- Create: `docs/dforge/notes/2026-11-15-lean-test-contracts.md`

**Interfaces:**
- Consumes: none.
- Produces: C7.

**Items:** 5
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: No new test, because these are skill and criteria files no script reads for this content; M2 (Step 4) measures the change**

- [ ] **Step 2: Edit the plan format**

1. `SKILL.md`: the task template's Step 1 shows C7 entries instead of a fenced test; the paragraph "A task carries its files, its interfaces, the complete code of its tests" and `:292-296` say a Claude plan carries test contracts (C7), with the exact strings, exit codes and values from Contracts or inline; the No Placeholders list replaces "every test step carries its complete test code" and "Write tests for the above (without actual test code)" with a contract that names no exact asserted result. A `Host: codex` plan keeps complete test and implementation code.
2. `test-step-forms.md`: the Write form carries C7 entries; the Extend form carries one C7 entry for the added row or case; Covered-by and No-new-test are unchanged.
3. `plan-review.md` Executability: HIGH when every contract names its file, test name, layer, input and exact asserted result, and states a fault a stub would not survive; LOW for a contract two readers could turn into tests catching different faults, or one naming no exact result. Codex-host text unchanged. ASCII only.
4. `plan-reviewer-prompt.md`: "the complete code of its tests" becomes its test contracts; "a missing or stub test is" becomes a missing or vague contract.
5. `README.md:1163`: the same change.
6. Commit: `git add` the five files, `git commit -m "feat(dforge): plan tests as contracts"`. Write down the sha as P7.

- [ ] **Step 3: Pick the M2 tasks**

In `docs/dforge/plans/2026-11-14-api-decisions-keep-warm-hydrogen.md` and `docs/dforge/plans/2026-11-13-reviewer-only-externals.md`, take the first two tasks of each whose Step 1 is `Write the failing test` and whose commit `git log --format='%h %s'` finds by subject. Record each task's base (its commit's parent) and commit.

- [ ] **Step 4: Run M2**

1. For each task, rewrite its Step 1 as C7 entries from the plan's own test code, in a copy of the plan under `<scratchpad>/m2/`; record which entry covers each original assertion, and Step 1's line count before and after.
2. Clone this repository into `<scratchpad>/m2-<n>` at the task's base; produce its brief with `timeout 60 bash plugins/dforge/scripts/task-brief` on the plan copy (as `task-brief --help` prints), and dispatch one `dforge:impl-sonnet-high` seat, cwd the clone, given only the brief and `plan-header.md`, told to write the tests and nothing else and not to commit.
3. Check, with timeouts: the written tests fail at the base; with the task's commit's non-test files checked out, they pass; then for each non-test file the task changed, revert that file alone to the base at the task's commit and run both the plan's own tests and the written ones: whenever the plan's fail, the written ones must fail too.
4. Write `docs/dforge/notes/2026-11-15-lean-test-contracts.md`: the four tasks, the coverage mapping, the line counts, each check's result, the keep rule's result (kept only when all four pass every check), and the limit: the contracts were written from finished tests, so M2 shows an upper bound.

- [ ] **Step 5: Keep or revert**

If any task failed or M2 could not finish: `git revert --no-edit P7`, and the note names the contract that failed. Then:

Run: `timeout 60 bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-15-measured-proposals.md 5 <done|n/a> --note "<kept|reverted>: docs/dforge/notes/2026-11-15-lean-test-contracts.md"`
Expected: `register: 0 errors` from `bash plugins/dforge/scripts/register check docs/dforge/registers/2026-11-15-measured-proposals.md`.

- [ ] **Step 6: Run the task check**

Run: the Task check.
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add docs/dforge/notes/2026-11-15-lean-test-contracts.md docs/dforge/registers/2026-11-15-measured-proposals.md
git commit -m "docs(notes): record the lean test contract check"
```
