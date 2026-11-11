# Test Volume Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dforge's rules ask for a test only where a realistic fault exists: plans gain a `No new test, because <reason>` Step 1 form that `plan-lint` checks, the test-quality lens runs at every standard final review that changes a test, and the skills, reviewer prompts and QA reference stop asking for tests per function, per edge case or per wording.

**Architecture:** Two script changes carry the behaviour: `scripts/plan-lint` classifies the fourth Step 1 form and warns on any other heading, and `scripts/lens-route` exempts test-quality from the standard two-lens limit. Everything else is prose in skills, references, criteria and prompts, with each wording pin the prose breaks deleted in the same commit.

**Tech Stack:** Bash scripts and bash test suites, Node test suites under `evals/`, Markdown skills and references.

**Spec:** docs/dforge/specs/2026-11-11-test-volume-rules-design.md

**Execution:** inline — `claude --model opus --effort high` — the hardest tasks total 7

**Parallelism:** sequential — inline execution

**Task check:** `node scripts/test-all.mjs` — the full suite last passed in 224 s

**Integration check:** `timeout 1500 node scripts/test-all.mjs && timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate . && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge`

**CI:** `.github/workflows/validate.yml` — platforms: uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/test-all.mjs`; `node scripts/validate-repository.mjs`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: uutils (ubuntu-latest), Windows Git Bash

**Plan review:** 2026-11-11 — dforge:judge-opus — executability 14 / coherence 18 / coverage 15 / assumptions 15 (round 1)

## Global Constraints

- English only in code, comments, docs, commits and tests.
- Commits are `<type>(<scope>): <subject>`, subject at most 50 characters, authored as `Darkraise <quangtc94@gmail.com>`, with no AI attribution of any kind.
- No code comment unless the why is non-obvious; never reference this task or plan in a comment.
- Nothing is pushed before finishing.
- Do not edit historical plans or specs (`docs/dforge/plans/*` and `docs/dforge/specs/*` other than this plan and its spec).
- Every `skills/*/SKILL.md` stays at or under 20,000 bytes (`plugins/dforge/tests/skill-size.test.sh`). On 2026-11-11: `writing-plans/SKILL.md` 18,678, `brainstorming/SKILL.md` 18,767, `test-driven-development/SKILL.md` 10,375.
- A wording pin (a test that asserts a skill, reference, criteria or prompt sentence) that a task's edit breaks is deleted in that task's commit, and the commit body names it. No task adds a test that asserts a document's wording.
- A2 in `evals/tiers/tests/speed-and-cost.acceptance.test.mjs` fails when a sentence of a split skill's `SKILL.md` at its base commit is in neither that `SKILL.md` nor its `references/`. The split skills are brainstorming, executing-plans, finishing-a-development-branch, subagent-driven-development, writing-plans and writing-skills. After a task edits a split skill's `SKILL.md` or a file under its `references/`, each sentence A2 reports as lost goes into that file's `REMOVED` list, verbatim as A2 prints it, and nothing else does.
- Every test or suite command runs under `timeout`.
- Windows Git Bash: A native program (`git.exe`, `jq.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset). Convert the path with `cygpath -m` before the call (dforge's `dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
- Windows Git Bash: The same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches. Normalise both sides with `cygpath -m`, or compare with `-ef`.
- Windows Git Bash: Files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep. Pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes in the value, so a regex or a Windows path changes. Pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails. Import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): A lock built on `mkdir` failing when the directory exists does not exclude a second process. Create the lock file with `set -C` (noclobber), or use `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started, so the command's children keep running. Run the command in its own process group (`setsid`) and signal the group.

## Contracts

- **The fourth Step 1 form:** `- [ ] **Step 1: No new test, because <reason>**`. `plan-lint` recognizes a heading text (after `Step 1: `, before the closing `**`) matching the bash regex `^No new test, because .*[A-Za-z0-9]` and classifies it `step1_class[n]=none`, which is not a test step for `Covered by Task <N>`.
- **`plan-lint` ERROR:** any other heading text beginning `No new test` prints `ERROR Task <n>: Step 1 must read "No new test, because <reason>"`.
- **`plan-lint` WARN:** a heading text that is none of the four forms prints `WARN Task <n>: Step 1 "<heading>" is none of the forms in test-step-forms.md`, `<heading>` being the extracted heading text verbatim. The four forms: text beginning `Write the failing test`; text beginning ``Extend the test ` ``; text matching the existing `covered_re`; the `No new test` form. Only a task's first Step 1 line is read; a task with none prints nothing.
- **`lens-route --final` at standard depth:** walking `lens_order`, a lens other than test-quality prints `lens …` while fewer than 2 lenses other than test-quality have printed and the total printed is below `lensCap`; test-quality prints while the total printed is below `lensCap`; any other applicable lens prints `lens-skipped <id> reason=cap`. Light and full depth are unchanged.
- **Deferred redundancy finding:** a test-quality finding on a merge-base test covered by a branch test is Important, with its one-liner beginning `deferred: test-simplifier — `.

## Assumptions (evidence)

- Exactly three suites go red on the new WARN alone: `plugins/dforge/tests/plan-lint.test.sh`, `plugins/dforge/tests/inline-only-execution.acceptance.test.sh` and `plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh` (A5). Read by the Fable spec review on 2026-11-11 (`.dforge/spec-review-2026-11-11-test-volume-rules-design-1-report.md`). unverified — Task 1 verifies it.
- No script reads the prose this plan rewrites, except `scripts/task-step`, which loads `implementer-prompt.md`, `task-reviewer-prompt.md` and `group-reviewer-prompt.md` as templates (`plugins/dforge/scripts/task-step:733`, `:846`, `:995`); no edit here touches a `[PLACEHOLDER]`. `rg` over `plugins/dforge/scripts` on 2026-11-11.
- None of these sentences is pinned by a test: "how the change will be verified", "files touched, testing", "means an automated test can check it", "FAILING TEST FIRST", "Coverage could be broader", "Are tests comprehensive", "test exists and failed first" (`rg -F` over `plugins/*/tests`, `evals`, `plugins/dforge/agents`, `plugins/dforge/scripts`, 2026-11-11, no match).
- The standard-depth change sets of the lens suites change a test file: `lens-route.test.sh` HEAD2 holds a TypeScript test, `review-depth.acceptance.test.sh` A8 writes `tests/a.test.ts`, `review-depth-qa.acceptance.test.sh` writes `tests/x.test.ts` (read 2026-11-11). Their standard expectations therefore gain `lens test-quality`: `lens-route.test.sh`'s standard checks and its risk-2 check, review-depth A8's two standard checks, and review-depth-qa A8's `a8-standard` lensCap 4 and 9 checks and its `a8-standard-spec` check (plan review round 1, 2026-11-11).
- `plan-amend` compares only ERROR lines of `plan-lint` (`plugins/dforge/scripts/plan-amend:133-134`), so the WARN does not change amendment checks.

## Task index

1. plan-lint checks the fourth Step 1 form
2. Plans write tests per behaviour, never per wording
3. lens-route runs test-quality at standard depth
4. Reviewers name the input before a missing case
5. TDD, brainstorming and acceptance tags ask for faults

---

### Task 1: plan-lint checks the fourth Step 1 form

**Files:**
- Modify: `plugins/dforge/scripts/plan-lint` (the `# --- Step 1 forms ---` section)
- Test: `plugins/dforge/tests/plan-lint.test.sh`
- Modify: `plugins/dforge/tests/inline-only-execution.acceptance.test.sh` (its `Step 1: Do it` fixture line)
- Modify: `plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh` (`a5_scope`)

**Interfaces:**
- Consumes: nothing
- Produces: the fourth Step 1 form, the `plan-lint` ERROR and the `plan-lint` WARN (Contracts)

**Items:** 6
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/plan-lint.test.sh`, directly after the line `lacks "a waves plan: Covered by a task in an earlier wave is accepted" "$out" "Covered by Task"`, add:

```bash
lint cov-ok.md
lacks "a Covered by heading draws no form WARN" "$out" "none of the forms"
step1 'No new test, because the change is prose no script reads' 'Write the failing test' > nnt-ok.md
lint nnt-ok.md
check "No new test with a reason: exit 0" "$status" "0"
lacks "No new test with a reason: no Step 1 ERROR" "$out" "Step 1 must read"
lacks "No new test with a reason: no form WARN" "$out" "none of the forms"
for h in 'No new test' 'No new test, because' 'No new test, because .' 'No new test because x'; do
  step1 "$h" 'Write the failing test' > nnt-bad.md
  lint nnt-bad.md
  check "No new test without a reason ($h): exit 1" "$status" "1"
  has "No new test without a reason ($h): the ERROR" "$out" 'ERROR Task 1: Step 1 must read "No new test, because <reason>"'
  lacks "No new test without a reason ($h): no form WARN" "$out" "none of the forms"
done
step1 'Do it' 'Write the failing test' > nnt-warn.md
lint nnt-warn.md
check "an unrecognized Step 1 heading: exit 0" "$status" "0"
has "an unrecognized Step 1 heading: the WARN" "$out" 'WARN Task 1: Step 1 "Do it" is none of the forms in test-step-forms.md'
for h in 'Write the failing tests' 'Extend the test `t/a.test.sh::first`'; do
  step1 "$h" 'Write the failing test' > nnt-known.md
  lint nnt-known.md
  lacks "a recognized Step 1 heading draws no form WARN ($h)" "$out" "none of the forms"
done
waves_plan 'sequential — one chain' > nnt-nostep.md
lint nnt-nostep.md --no-probe
lacks "a task with no Step 1 line draws no form WARN" "$out" "none of the forms"
waves_plan 'sequential — one chain' | with_steps 'Write the failing test' 'No new test, because prose only' $'Covered by Task 2\'s test `b`' > nnt-cov.md
lint nnt-cov.md --no-probe
has "Covered by a No new test task: it has no test step" "$out" "ERROR Task 3: Covered by Task 2 — Task 2 has no test step"
lacks "a No new test task with a reason draws no form WARN" "$out" 'Task 2: Step 1'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 900 bash plugins/dforge/tests/plan-lint.test.sh two 2>&1 | grep -E '^FAIL' | head -20`
Expected: FAIL for the four "No new test without a reason (…): exit 1" checks, the four "No new test without a reason (…): the ERROR" checks and "an unrecognized Step 1 heading: the WARN". "Covered by a No new test task: it has no test step" and every `lacks` check pass today, because the current code counts only write and extend as test steps and prints no form WARN. If the Step 1 forms section is in part `one`, run `one` instead; the part that prints the new check names is the one to use from here on.

- [ ] **Step 3: Implement**

1. `plugins/dforge/scripts/plan-lint`, the `while IFS=$'\t' read -r m heading` loop of the `# --- Step 1 forms ---` section: after the `covered_re` branch, add the classification the Contracts give: a heading matching `^No new test, because .*[A-Za-z0-9]` sets `step1_class[m]=none`; any other heading beginning `No new test` prints the Contracts ERROR through `say ERROR "Task $m" …`; any heading matching none of the four forms prints the Contracts WARN through `say WARN "Task $m" …`. Keep the loop's single awk pass; add no subprocess. Update the section's comment line "The forms are defined in …" only if the wording becomes wrong.
2. Run the whole suite with only the script changed: `timeout 1500 node scripts/test-all.mjs 2>&1 | tail -30`. This verifies the first Assumption: the failing suites must be exactly `plan-lint.test.sh` (the `claude_plan` fixture's warning counts and its `TODO` check), `inline-only-execution.acceptance.test.sh` (its no-WARN assertion) and `antigravity-executor-lane.acceptance.test.sh` (A5). Record the observed list in the ledger. A further suite failing is an assumption failure: log a `Ruling:` line and fix it in this task by the same rule as item 3.
3. Make every incidental Step 1 heading a recognized form, keeping each check's expected counts:
   - `plan-lint.test.sh`, `claude_plan`: `- [ ] **Step 1: Write it**` becomes `- [ ] **Step 1: Write the failing test**`, and ``- [ ] **Step 1: Mark the `TODO` column**`` becomes ``- [ ] **Step 1: Write the failing test for the `TODO` column**``. Update `step1()`'s two sed patterns to match the new headings (`Write the failing test\*\*\$` and `Write the failing test for the .+ column\*\*\$`), the `variant v6.md` pattern that matches `Write it`, and the check `lacks "inline-code TODO is not a finding" "$out" "Mark the"` to use the needle ``for the `TODO` column``. The `- [ ] **Step 1: Do it**` heading of `write_plan` in the item-registers section becomes `- [ ] **Step 1: Write the failing test**`. The new checks of Step 1 keep their own headings.
   - `inline-only-execution.acceptance.test.sh`: `- [ ] **Step 1: Do it**` in its `printf` becomes `- [ ] **Step 1: Write the failing test**`.
   - `antigravity-executor-lane.acceptance.test.sh`, `a5_scope`: add the alternatives `WARN Task [0-9]+: Step 1 ".*" is none of the forms in test-step-forms\.md` and `ERROR Task [0-9]+: Step 1 must read "No new test, because <reason>"` to its `grep -vE` pattern, matching the style of the alternatives already there.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 900 bash plugins/dforge/tests/plan-lint.test.sh && timeout 900 bash plugins/dforge/tests/inline-only-execution.acceptance.test.sh && timeout 1200 bash plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh A5`
Expected: each ends with `0 failed` and exits 0.

Then run: `timeout 1500 node scripts/test-all.mjs`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/plan-lint plugins/dforge/tests/plan-lint.test.sh plugins/dforge/tests/inline-only-execution.acceptance.test.sh plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh
git commit -m "feat(dforge): lint the no-new-test Step 1 form"
```

### Task 2: Plans write tests per behaviour, never per wording

**Files:**
- Modify: `plugins/dforge/skills/writing-plans/references/test-step-forms.md`
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md` (the paragraph beginning "Step 1's test sits at the lowest layer")
- Modify: `plugins/dforge/criteria/plan-review.md` (`### Executability {#executability}`)
- Modify: `plugins/dforge/tests/process-roles.test.sh` (delete two pins)
- Modify: `evals/tiers/tests/speed-and-cost.acceptance.test.mjs` (`REMOVED`, only if A2 reports a lost sentence)

**Interfaces:**
- Consumes: the fourth Step 1 form and the `plan-lint` ERROR and WARN (Contracts)
- Produces: nothing

**Items:** 6, 7, 12
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 1 = 5

- [ ] **Step 1: No new test, because the change is prose that no script reads, carried by spec statements A13, A14 and A17, which are demo**

- [ ] **Step 2: Confirm the anchors**

Run:
```bash
F=plugins/dforge/skills/writing-plans/references/test-step-forms.md
grep -n '^## The three Step 1 forms' "$F"; grep -nF 'Step 1 takes one of three forms.' "$F"; grep -nF 'Plan tests per behaviour' "$F"
grep -nF "Step 1's test sits at the lowest layer" plugins/dforge/skills/writing-plans/SKILL.md
grep -nF 'catch it. Ignore whether the spec is covered' plugins/dforge/criteria/plan-review.md
grep -nF 'Step 1 takes one of three forms' plugins/dforge/tests/process-roles.test.sh; grep -nF 'tests are planned per behaviour' plugins/dforge/tests/process-roles.test.sh
```
Expected: one line from each command. Sentences wrap across lines in the files; match words, not line breaks.

- [ ] **Step 3: Implement**

1. `test-step-forms.md`: the heading `## The three Step 1 forms` becomes `## The Step 1 forms`; "Step 1 takes one of three forms." becomes "Step 1 takes one of four forms." Leave the first, second and third forms' paragraphs word for word (other `process-roles.test.sh` pins hold them). Delete the paragraph "Plan tests per behaviour: one test per acceptance statement or behaviour, at the lowest layer that can fail for it, rather than one per task." Add, after the third form's paragraph, this paragraph wrapped at the file's width:
   "The fourth, `- [ ] **Step 1: No new test, because <reason>**`, is for a task with no realistic fault that an existing test does not already catch, such as a refactor or prose that no script reads. The reason names the property that rules a fault out, or the existing test that catches it as `<file>::<name>`. The task's later steps run the existing checks. The plan reviewer judges such a task's Executability by its reason. plan-lint fails a heading that begins `No new test` without `, because ` and a reason, and warns on any Step 1 heading that is none of the four forms."
2. `writing-plans/SKILL.md`: directly after the paragraph that begins "Step 1's test sits at the lowest layer that can fail for the task's change." and ends "dforge:test-simplifier's job.", insert a new paragraph:
   "Plan tests per behaviour: one test per acceptance statement or behaviour, at the lowest layer that can fail for it, rather than one per task. A sentence in a skill, reference or prompt gets a test only when a script reads it ([writing-good-tests.md](../test-driven-development/references/writing-good-tests.md), \"Behavior, not text\"); wording a script parses, such as the Step 1 forms and a template's placeholders, is the exception."
   Then `wc -c plugins/dforge/skills/writing-plans/SKILL.md`. Above 20,000 bytes: move the paragraph's second sentence to the end of `test-step-forms.md` as its own paragraph, with the link written relative to that file (`../../test-driven-development/references/writing-good-tests.md`), and keep the first sentence in `SKILL.md`.
3. `criteria/plan-review.md`, Executability: directly after "score LOW when it names none or the cited test would not catch it." and before "Ignore whether the spec is covered;", insert:
   "A task whose Step 1 reads \"No new test, because\" is judged by its reason: score LOW when the reason names neither a property that rules a fault out nor an existing test that catches it, or when a realistic fault exists that no existing test catches. Score LOW a task whose Step 1 heading is none of the four forms in test-step-forms.md; a line in the plan's Assumptions does not excuse it. Score LOW a plan that writes one test per task where one test per behaviour would do, and name the tasks whose tests one test would cover. Score LOW a planned test that checks the wording of a document no script reads."
   Keep four `### ` headings in the file.
4. `process-roles.test.sh`: delete the line `says "writing-plans forms: Step 1 takes one of three forms" …` and the line `says "writing-plans forms: tests are planned per behaviour" …`.
5. Run `timeout 300 node --test evals/tiers/tests/speed-and-cost.acceptance.test.mjs 2>&1 | grep -A80 'writing-plans/SKILL.md is lost'`. For each sentence it reports as lost, add it verbatim to `REMOVED` with a comment line naming the change ("the Step 1 forms gained a fourth form; tests are planned per behaviour"). No report: leave the file unchanged.

- [ ] **Step 4: Run the checks**

Run: `timeout 300 bash plugins/dforge/tests/process-roles.test.sh && timeout 300 bash plugins/dforge/tests/skill-size.test.sh && timeout 300 node --test evals/tiers/tests/speed-and-cost.acceptance.test.mjs evals/tiers/tests/test-tiers-and-ci-parity.acceptance.test.mjs`
Expected: each exits 0.

Then run: `timeout 1500 node scripts/test-all.mjs`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/writing-plans/references/test-step-forms.md plugins/dforge/skills/writing-plans/SKILL.md plugins/dforge/criteria/plan-review.md plugins/dforge/tests/process-roles.test.sh evals/tiers/tests/speed-and-cost.acceptance.test.mjs
git commit -m "docs(dforge): plan tests per behaviour" -m "Deletes the process-roles pins 'Step 1 takes one of three forms' and
'tests are planned per behaviour', which pinned the moved wording."
```

### Task 3: lens-route runs test-quality at standard depth

**Files:**
- Modify: `plugins/dforge/scripts/lens-route` (the `--final` loop and the usage comment)
- Test: `plugins/dforge/tests/lens-route.test.sh`
- Modify: `plugins/dforge/tests/review-depth.acceptance.test.sh` (A8 standard checks)
- Modify: `plugins/dforge/tests/review-depth-qa.acceptance.test.sh` (A8 standard checks)
- Modify: `plugins/dforge/reference/final-review.md` (the depth table's Lenses row and step 1's standard sentence)
- Modify: `plugins/dforge/README.md` (the depth table's Lenses row)
- Modify: `plugins/dforge/tests/final-phase.test.sh` (delete one pin)

**Interfaces:**
- Consumes: nothing
- Produces: the `lens-route --final` standard-depth rule (Contracts)

**Items:** 9
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/lens-route.test.sh`, replace the three standard checks that follow `out=$(bash "$ROUTE" standard-plan.md --final "$BASE" "$HEAD2")` (through `check "standard: a lensCap of 3 is cut to 2" …`) with:

```bash
out=$(bash "$ROUTE" standard-plan.md --final "$BASE" "$HEAD2")
check "standard: two lenses plus test-quality, the rest past the cap" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens test-quality;lens-skipped lang-bash reason=cap;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"
out=$(DFORGE_LENS_CAP=1 bash "$ROUTE" standard-plan.md --final "$BASE" "$HEAD2")
check "standard: a lower lensCap wins" "$(grep -c '^lens ' <<<"$out")" "1"
out=$(DFORGE_LENS_CAP=2 bash "$ROUTE" standard-plan.md --final "$BASE" "$HEAD2")
check "standard: lensCap 2 skips test-quality for the cap" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens-skipped test-quality reason=cap;lens-skipped lang-bash reason=cap;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"
out=$(DFORGE_LENS_CAP=3 bash "$ROUTE" standard-plan.md --final "$BASE" "$HEAD2")
check "standard: lensCap 3 keeps test-quality as the third" "$(grep -c '^lens ' <<<"$out")" "3"
commit_file src/b.ts 'run() ?? fallback()'
commit_file NOTES.md 'Notes.'
HEAD3=$(git rev-parse HEAD)
out=$(bash "$ROUTE" standard-plan.md --final "$HEAD2" "$HEAD3")
check "standard: with no test file changed, two lenses only" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"
```

The HEAD2..HEAD3 range changes no test path, so test-quality does not apply, and the last check guards that the exemption is for test-quality alone.

Change `check "a light spec with a risk-2 task is standard: two lenses" "$(grep -c '^lens ' <<<"$out")" "2"` to `check "a light spec with a risk-2 task is standard: three lenses with test-quality" "$(grep -c '^lens ' <<<"$out")" "3"`.

Directly after the check `"light: security prints nothing when its Applies clause does not match"`, add:

```bash
out=$(bash "$TMP/plug/scripts/lens-route" standard-plan.md --final "$BASE" "$HEAD2")
check "standard: without security, test-quality does not use a slot" "$(short <<<"$out")" \
  "lens silent-failures;lens test-quality;lens lang-bash;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/lens-route.test.sh 2>&1 | grep -E '^FAIL'`
Expected: FAIL for "standard: two lenses plus test-quality, the rest past the cap", "standard: lensCap 3 keeps test-quality as the third", "a light spec with a risk-2 task is standard: three lenses with test-quality" and "standard: without security, test-quality does not use a slot". "standard: lensCap 2 skips test-quality for the cap" and "standard: with no test file changed, two lenses only" pass already; the second guards the implementation against a plain cap of 3.

- [ ] **Step 3: Implement**

1. `plugins/dforge/scripts/lens-route`, `--final`: keep the configured `lensCap` as the total limit and stop lowering `cap` to 2 at standard depth. In the `lens_order` loop, count lenses other than test-quality separately and apply the Contracts rule at standard; light and full keep their current branches. Update the usage comment: the `reason=cap` line reads "past the lensCap setting, or at standard depth past 2 lenses besides test-quality", and the sizing line reads "standard keeps at most 2 lenses besides test-quality, which it adds when it applies, up to lensCap in all".
2. `review-depth.acceptance.test.sh`, A8 standard: `check "A8: standard prints at most 2 lens lines" … "2"` becomes `check "A8: standard prints the 2 lenses and test-quality" "$(grep -c '^lens ' <<<"$out_std")" "3"`, and the expected string of `"A8: standard skips the rest for the cap"` becomes `"lens security;lens silent-failures;lens test-quality;lens-skipped lang-bash reason=cap;lens-skipped lang-python reason=cap;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"`. The lensCap 1 check stays.
3. `review-depth-qa.acceptance.test.sh`, A8 standard (the block after `# standard: at most 2 lens lines.`): the comment becomes `# standard: at most 2 lens lines besides test-quality, which this change set needs.`; `"A8: standard, lensCap 4, prints 2 lens lines"` expects 3 and is renamed `"A8: standard, lensCap 4, prints 3 lens lines with test-quality"`; `"A8: standard, lensCap 9, still prints 2 lens lines"` expects 3 and is renamed `"A8: standard, lensCap 9, still prints 3 lens lines"`. The lensCap 1, 2 and 0 checks keep their expectations. `"A8: standard by the spec, lensCap 4, prints 2 lens lines"` (the `a8-standard-spec` plan) expects 3 and is renamed `"A8: standard by the spec, lensCap 4, prints 3 lens lines with test-quality"`.
4. `reference/final-review.md`: the depth table row `| 1 Lenses | \`security\` only, when it applies | at most 2 | up to \`lensCap\` |` becomes `| 1 Lenses | \`security\` only, when it applies | at most 2, plus \`test-quality\` when it applies, within \`lensCap\` | up to \`lensCap\` |`. In step 1, "at standard it prints at most two, fewer when `lensCap` is lower." becomes "at standard it prints at most two lenses besides `test-quality`, which it adds whenever its Applies clause matches, and never more than `lensCap` in all."
5. `plugins/dforge/README.md`: the row `| 1 Lenses | security only, when it applies | at most 2 | up to \`lensCap\` |` becomes `| 1 Lenses | security only, when it applies | at most 2, plus test-quality when it applies, within \`lensCap\` | up to \`lensCap\` |`.
6. `final-phase.test.sh`: delete the line `names "final review: the lens column by depth" "$FR" …`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/lens-route.test.sh && timeout 900 bash plugins/dforge/tests/review-depth.acceptance.test.sh A8 && timeout 900 bash plugins/dforge/tests/review-depth-qa.acceptance.test.sh A8 && timeout 300 bash plugins/dforge/tests/final-phase.test.sh`
Expected: each exits 0.

Then run: `timeout 1500 node scripts/test-all.mjs`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lens-route plugins/dforge/tests/lens-route.test.sh plugins/dforge/tests/review-depth.acceptance.test.sh plugins/dforge/tests/review-depth-qa.acceptance.test.sh plugins/dforge/reference/final-review.md plugins/dforge/README.md plugins/dforge/tests/final-phase.test.sh
git commit -m "feat(dforge): run test-quality at standard depth" -m "Deletes the final-phase pin 'final review: the lens column by depth',
which pinned the depth table's old Lenses row."
```

### Task 4: Reviewers name the input before a missing case

**Files:**
- Modify: `plugins/dforge/criteria/lenses/test-quality.md` (`{#missing}`, `{#redundant}`)
- Modify: `plugins/dforge/reference/final-review.md` (the **Redundant tests.** paragraph and the acceptance-file sentence)
- Modify: `plugins/dforge/skills/requesting-code-review/references/code-reviewer.md`
- Modify: `plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md`, `task-reviewer-prompt.md`, `group-reviewer-prompt.md`
- Modify: `plugins/dforge/reference/acceptance-qa.md`
- Modify: `plugins/dforge/tests/process-roles.test.sh` (delete three pins)
- Modify: `evals/tiers/tests/test-tiers-and-ci-parity.acceptance.test.mjs` (A12's sentence assertion)
- Modify: `evals/tiers/tests/speed-and-cost.acceptance.test.mjs` (`REMOVED`, only if A2 reports a lost sentence)

**Interfaces:**
- Consumes: nothing
- Produces: the deferred redundancy finding (Contracts)

**Items:** 5, 9, 11
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 2 - spec 1 - coupling 0 - risk 1 = 4

- [ ] **Step 1: No new test, because the change is reviewer and QA prose that no script reads, carried by spec statements A12, A15 and A16, which are demo**

- [ ] **Step 2: Confirm the anchors**

Run:
```bash
P=plugins/dforge
grep -nF 'has no test that reaches it.' $P/criteria/lenses/test-quality.md; grep -nF 'Among the tests added or changed on the branch' $P/criteria/lenses/test-quality.md
grep -nF '**Redundant tests.**' $P/reference/final-review.md; grep -nF "The fix wave's verification runs the acceptance file" $P/reference/final-review.md
grep -nF -e '- Edge cases covered?' -e 'Comprehensive test coverage (18 tests, all edge cases)' $P/skills/requesting-code-review/references/code-reviewer.md
grep -nF 'Are tests comprehensive?' $P/skills/subagent-driven-development/references/implementer-prompt.md
grep -nF -e "Are the task's edge cases covered?" -e '"Coverage could be broader"' $P/skills/subagent-driven-development/references/task-reviewer-prompt.md
grep -nF -e "and cover the task's edge cases" -e '"Coverage could be broader"' $P/skills/subagent-driven-development/references/group-reviewer-prompt.md
grep -nF -e '`rerun`: the acceptance file' -e 'in one file named' -e 'Run the file with' -e 'commit the acceptance file' -e 'committed the acceptance file' -e 'the acceptance file and the test' -e 'run the whole file' $P/reference/acceptance-qa.md
grep -nF -e 'committed the acceptance file, so' -e '`rerun`: the acceptance file may already exist' -e 'a redundant branch test names its cover' $P/tests/process-roles.test.sh
grep -nF 'Among the tests added or changed on the branch' evals/tiers/tests/test-tiers-and-ci-parity.acceptance.test.mjs
```
Expected: every pattern matches at least once. Sentences wrap across lines; match words, not line breaks.

- [ ] **Step 3: Implement**

Wrap each edited paragraph at its file's width.

1. `criteria/lenses/test-quality.md`, `{#missing}`: the criterion becomes "Look at the branches the diff adds in the code under test. Report a finding when an error path, a boundary value or a \"must not happen\" case has no test that reaches it, and only when you can name the input that reaches that branch and the wrong result it produces. A gap you cannot name both for is not a finding."
2. `criteria/lenses/test-quality.md`, `{#redundant}`: the criterion becomes "Among the tests in files the branch changes, report a test that fails for no fault that another test does not also catch, and name the test that covers it. A redundant test added on the branch is Important: the fix is to merge the tests into a row of a table, or to delete the redundant one. A redundant test that exists at the merge base, covered by a test added on the branch, is Important with its one-liner beginning `deferred: test-simplifier — `; it is never fixed in the review. Ignore tests that cannot fail, which the first criterion owns." Leave the heading and the `Applies:` line unchanged (`scripts/review-record` reads `Applies:`).
3. `reference/final-review.md`, at the end of the **Redundant tests.** paragraph, add: "A finding whose one-liner begins `deferred: test-simplifier — ` is not given to the fixer. The session records it with `scripts/register add <register> \"<old test> is covered by <new test>\" --state deferred --note \"final review: for dforge:test-simplifier\"` in the register that covers the plan's spec, or names it in the final message when no register covers it, and counts it in its lens line's Important count only, neither fixed nor rejected." Leave the paragraph's existing sentences word for word (`test-tiers-and-ci-parity` A11 and three `process-roles.test.sh` pins hold them).
4. `reference/final-review.md`: "The fix wave's verification runs the acceptance file again." becomes "The fix wave's verification runs the acceptance files again."
5. `code-reviewer.md`: the Testing item `- Edge cases covered?` becomes `- Is there an input that reaches an untested branch and produces a wrong result? Name both, or report nothing.`; the example `- Comprehensive test coverage (18 tests, all edge cases)` becomes `- An empty batch and a duplicate id each have a test that fails on the bug it names (summarizer.test.ts:12-40)`.
6. `implementer-prompt.md`: `- Are tests comprehensive?` becomes `- Does every behaviour with a realistic fault have a test? Add a case only when you can name the input that reaches the untested branch and the wrong result it produces.`
7. `task-reviewer-prompt.md`: `- Are the task's edge cases covered?` becomes `- Is there an input that reaches an untested branch of the task's code and gives a wrong result? Report a missing case only when you can name both.`; in the calibration paragraph, `"Coverage could be broader" and polish suggestions are Minor.` becomes `Polish suggestions are Minor.`
8. `group-reviewer-prompt.md`: `and cover the task's edge cases;` becomes `and reach every branch for which you can name an input that gives a wrong result;`; the calibration sentence changes as in item 7.
9. `reference/acceptance-qa.md`:
   - `rerun`: "the acceptance file may already exist from an earlier run that was cut off. Run it as it is, never rewrite a test in it, and write tests only for statements it does not cover yet;" becomes "the acceptance files may already exist from an earlier run that was cut off. Run them as they are, never rewrite a test in them, and write tests only for statements they do not cover yet;"
   - `reword`: "and run the whole file." becomes "and run every acceptance file."
   - step 2: "in one file named `<spec-slug>.acceptance.<ext>` (the spec's file name without its date and `-design.md`), or the nearest name the test framework accepts." becomes "in one file per test project the statements reach, each named `<spec-slug>.acceptance.<ext>` (the spec's file name without its date and `-design.md`), or the nearest name the test framework accepts. A test project is a directory with its own test runner or project file."
   - step 3: "Run the file with `[TEST_COMMAND]` scoped to it, or the framework's own runner, always under `timeout`." becomes "Run each file with its own project's runner, `[TEST_COMMAND]` scoped to it or the framework's own, always under `timeout`."; "commit the acceptance file and the fixtures it needs" becomes "commit the acceptance files and the fixtures they need".
   - step 4: "step 3 committed the acceptance file, so `HEAD` has it;" becomes "step 3 committed the acceptance files, so `HEAD` has them;".
   - The report: "(the acceptance file and the test's line)" becomes "(the test's acceptance file and line)"; "then `## Results`, the table and the command:" becomes "then `## Results`, the table and one `Command:` line per acceptance file:".
10. `process-roles.test.sh`: delete the lines `names "qa: the committed tests reach the mutation worktree" …`, `names "qa: rerun mode" …` and `says "lens: a redundant branch test names its cover" …`.
11. `test-tiers-and-ci-parity.acceptance.test.mjs`, A12: delete the `assert.match(criterion, /Among the tests added or changed on the branch, …/)` line and the `const criterion = …` line it alone uses. Keep the `{#redundant}` heading assertion.
12. Run `timeout 300 node --test evals/tiers/tests/speed-and-cost.acceptance.test.mjs 2>&1 | grep -A80 'subagent-driven-development/SKILL.md is lost'`. For each sentence it reports as lost, add it verbatim to `REMOVED` with a comment line ("reviewers name the input before a missing case"). No report: leave the file unchanged.

- [ ] **Step 4: Run the checks**

Run: `timeout 300 bash plugins/dforge/tests/process-roles.test.sh && timeout 300 node --test evals/tiers/tests/test-tiers-and-ci-parity.acceptance.test.mjs evals/tiers/tests/speed-and-cost.acceptance.test.mjs && timeout 300 bash plugins/dforge/tests/task-step-text.test.sh`
Expected: each exits 0.

Then run: `timeout 1500 node scripts/test-all.mjs`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/criteria/lenses/test-quality.md plugins/dforge/reference/final-review.md plugins/dforge/skills/requesting-code-review/references/code-reviewer.md plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md plugins/dforge/skills/subagent-driven-development/references/task-reviewer-prompt.md plugins/dforge/skills/subagent-driven-development/references/group-reviewer-prompt.md plugins/dforge/reference/acceptance-qa.md plugins/dforge/tests/process-roles.test.sh evals/tiers/tests/test-tiers-and-ci-parity.acceptance.test.mjs evals/tiers/tests/speed-and-cost.acceptance.test.mjs
git commit -m "docs(dforge): name the input before a missing case" -m "Deletes the wording pins 'qa: the committed tests reach the mutation
worktree', 'qa: rerun mode', 'lens: a redundant branch test names its
cover' and A12's {#redundant} sentence assertion."
```

### Task 5: TDD, brainstorming and acceptance tags ask for faults

**Files:**
- Modify: `plugins/dforge/skills/test-driven-development/SKILL.md`
- Modify: `plugins/dforge/skills/brainstorming/SKILL.md` (Bounded step 3, self-review item 2)
- Modify: `plugins/dforge/skills/brainstorming/references/drafting-acceptance.md` (the `test`/`demo` bullet)
- Modify: `evals/tiers/tests/speed-and-cost.acceptance.test.mjs` (`REMOVED`, only if A2 reports a lost sentence)

**Interfaces:**
- Consumes: nothing
- Produces: nothing

**Items:** 4, 12, 13
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 2 - spec 1 - coupling 0 - risk 1 = 4

- [ ] **Step 1: No new test, because the change is skill prose that no script reads, carried by spec statements A11, A17 and A18, which are demo**

- [ ] **Step 2: Confirm the anchors**

Run:
```bash
T=plugins/dforge/skills/test-driven-development/SKILL.md
grep -nF -e '- Refactoring' -e 'NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST' -e '| "Too simple to test" |' -e '| "Existing code has no tests" |' -e 'Every new function/method has a test' -e 'Edge cases and errors covered' -e 'Production code → test exists and failed first' "$T"
grep -nF -e '**Present short design in chat** — approach, files touched, testing' -e '**Testing:** the design says how the change will be verified.' plugins/dforge/skills/brainstorming/SKILL.md
grep -nF '`test` means an automated test can check it' plugins/dforge/skills/brainstorming/references/drafting-acceptance.md
```
Expected: every pattern matches once.

- [ ] **Step 3: Implement**

1. `test-driven-development/SKILL.md`:
   - When to Use: delete `- Refactoring` from the **Always:** list. Directly after the **Exceptions (ask your human partner):** list, add the paragraph "**Refactoring** keeps existing tests green and writes no test, except one characterization test written first when no existing test reaches the code being moved."
   - Iron Law: `NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST` becomes `NO PRODUCTION BEHAVIOUR WITHOUT A FAILING TEST FIRST`.
   - Common Rationalizations: the row `| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |` becomes `| "Too simple to test" | Code that validates, derives or has side effects breaks: test it. Code that does none of these earns no test. |`; the row `| "Existing code has no tests" | You're improving it. Add tests for existing code. |` becomes `| "Existing code has no tests" | Add tests for the behaviour you change, not for the rest of the code. |`.
   - Verification Checklist: `- [ ] Every new function/method has a test` becomes `- [ ] Every behaviour with a realistic fault has a test`; `- [ ] Edge cases and errors covered` becomes `- [ ] The mutation check (writing-good-tests.md) finds no realistic mutation that every test survives`.
   - Final Rule: `Production code → test exists and failed first` becomes `Production behaviour → test exists and failed first`.
2. `brainstorming/SKILL.md`: `3. **Present short design in chat** — approach, files touched, testing` becomes `3. **Present short design in chat** — approach, files touched, and the tests: each one, the fault it catches and any existing test it extends, or that the change earns none and why`; `2. **Testing:** the design says how the change will be verified.` becomes `2. **Testing:** the design names each test, the fault it catches and any existing test it extends, or says the change earns none and why.` Then `wc -c` the file: it must stay at or under 20,000 bytes.
3. `drafting-acceptance.md`: at the end of the bullet that begins "`test` means an automated test can check it", add the sentence "A statement about the wording of a document no script reads is `demo`: acceptance QA turns a `test` statement into a test, and that test would only pin wording."
4. Run `timeout 300 node --test evals/tiers/tests/speed-and-cost.acceptance.test.mjs 2>&1 | grep -A80 'brainstorming/SKILL.md is lost'`. For each sentence it reports as lost, add it verbatim to `REMOVED` with a comment line ("a bounded design names its tests"). No report: leave the file unchanged.

- [ ] **Step 4: Run the checks**

Run: `timeout 300 bash plugins/dforge/tests/process-roles.test.sh && timeout 300 bash plugins/dforge/tests/skill-size.test.sh && timeout 300 node --test evals/tiers/tests/speed-and-cost.acceptance.test.mjs`
Expected: each exits 0.

Then run: `timeout 1500 node scripts/test-all.mjs`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/test-driven-development/SKILL.md plugins/dforge/skills/brainstorming/SKILL.md plugins/dforge/skills/brainstorming/references/drafting-acceptance.md evals/tiers/tests/speed-and-cost.acceptance.test.mjs
git commit -m "docs(dforge): ask for a test per realistic fault"
```
