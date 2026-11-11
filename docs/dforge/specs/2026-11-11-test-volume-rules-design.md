# Test volume rules (batch B)

**Register:** `docs/dforge/registers/2026-11-10-tdd-and-lifecycle-review.md`, rows 4, 5, 6, 7, 9, 11, 12 (the batch B half) and 13.
**Execution strategy:** sequential — inline execution
**Depth:** standard — interface

## Decisions

- **Process:** architectural, depth standard, trigger `interface`: `plan-lint` gains a fourth Step 1 form and warns on any other heading, and every plan's Step 1 heading depends on that. Asked "Fast mode, or the full dforge flow?" Answer: "Full dforge flow (Recommended)".
- **Approaches:** none proposed. Each row's Note holds the owner's ruling of 2026-11-10, made after a Fable review, and this spec carries out those rulings. No approach question is open.
- **Wording pins:** asked "How should batch B handle a wording pin it breaks?" Answer: "Delete each broken pin (Recommended)". The answer was given against this description: "Same rule as rows 6 and 7, and row 12's rule that a sentence gets a test only when a script reads it. Behaviour tests (lens-route's output, review-depth A8) are updated, never deleted. The A2 lost-sentence check gets REMOVED entries, as the last plan did."
- **Ruling (session, upheld by Fable): lensCap at standard depth.** Row 9 says test-quality "is exempt from the limit of two lenses" and "the lensCap setting still applies". Test-quality therefore does not use either of the two standard slots, and it counts toward `lensCap` in today's lens order (security, ui-ux, silent-failures, test-quality, …). Moving it ahead in the order would change full-depth output as well, and no row asks for that.
- **Ruling (session, upheld by Fable): an empty reason.** A Step 1 heading that begins `No new test` but is not the exact fourth form is an ERROR, not a WARN: it is a failed attempt at the form, not other wording.
- **Redundant merge-base test:** asked, at the spec review, which handling row 9's deferred finding gets. Answer: "Important, parked (Recommended)". The lens reports it as Important with a `deferred: test-simplifier —` prefix, the fixer never gets it, and the session records it as a deferred register row.

Early CI: none

Finish: pr

Worktree: in-place

## Problem

The owner sees too many tests in every project (row 1). The mutation run of 2026-11-11 (`docs/dforge/test-simplifier/2026-11-11-darkcloud-downloads.md`) found that 275 of 543 downloads tests make no unique kill. The dforge rules that produce tests disagree with each other:

- The test-driven-development skill asks for a test for every new function and for every edge case. Its own `writing-good-tests.md` asks for a test only where a realistic fault exists.
- Reviewers may report a missing case without naming an input that reaches it.
- A plan has no Step 1 form for a task that needs no test, so authors invent headings that `plan-lint` never checks.
- The final review's test-quality lens rarely runs at standard depth, so redundant tests go unreported.
- Acceptance QA's one-file rule cannot be followed by a spec that spans several test projects.
- Tests that only check a skill's wording keep appearing, because the rule against them is cited nowhere a plan or spec is written.

## Design

### Row 4: test-driven-development agrees with writing-good-tests

In `skills/test-driven-development/SKILL.md`:

- Verification Checklist: "Every new function/method has a test" becomes "Every behaviour with a realistic fault has a test". "Edge cases and errors covered" becomes "The mutation check (writing-good-tests.md) finds no realistic mutation that every test survives".
- When to Use: "Refactoring" leaves the **Always** list. A new line says a refactor keeps existing tests green and writes no test. The one exception, stated in this skill on its own authority, is a single characterization test written first, when no existing test reaches the code being moved.
- Common Rationalizations: the "Too simple to test" row applies only to code that validates, derives or has side effects. The "Existing code has no tests" row applies only to the behaviour being changed.
- Iron Law: "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST" becomes "NO PRODUCTION BEHAVIOUR WITHOUT A FAILING TEST FIRST". Final Rule: "Production code → test exists and failed first" becomes "Production behaviour → test exists and failed first". Without these two changes the skill contradicts its new checklist.

`writing-good-tests.md` is the authority and does not change.

### Row 5: a missing-case finding names its input

A reviewer reports a missing case only when it can name the input that reaches the untested branch and the wrong result that input produces. A finding that names neither is not reported. The replacements, site by site:

- `criteria/lenses/test-quality.md`, `{#missing}`: the condition above is added to "Report a finding when an error path, a boundary value or a "must not happen" case has no test that reaches it."
- `skills/requesting-code-review/references/code-reviewer.md`: the Testing item "Edge cases covered?" becomes "Is there an input that reaches an untested branch and produces a wrong result? Name both, or report nothing." The example Strengths line "Comprehensive test coverage (18 tests, all edge cases)" becomes a strength that names a tested behaviour with a file and line and gives no test count.
- `skills/subagent-driven-development/references/implementer-prompt.md`: the self-review question "Are tests comprehensive?" becomes "Does every behaviour with a realistic fault have a test? Add a case only when you can name the input that reaches the untested branch and the wrong result it produces."
- `skills/subagent-driven-development/references/task-reviewer-prompt.md`: "Are the task's edge cases covered?" gains the condition above. The calibration sentence `"Coverage could be broader" and polish suggestions are Minor.` becomes "Polish suggestions are Minor."
- `skills/subagent-driven-development/references/group-reviewer-prompt.md`: "and cover the task's edge cases" gains the condition above, and its calibration sentence changes the same way as the task reviewer's.

`criteria/codex-final-review.md` has no test wording and does not change.

### Row 6: the fourth Step 1 form

`skills/writing-plans/references/test-step-forms.md`:

- Its heading `## The three Step 1 forms` becomes `## The Step 1 forms`, and its opening sentence becomes "Step 1 takes one of four forms."
- It gains the form `- [ ] **Step 1: No new test, because <reason>**`. The form is for a task with no realistic fault that an existing test does not already catch. A refactor, or prose that no script reads, are examples. The reason names one of two things:
  - the property that rules a fault out;
  - the existing test that catches it, as `<file>::<name>`.
- The task's later steps run the existing checks.
- The form's paragraph also says what `plan-lint` does with it: a missing reason fails, and any other heading draws a warning.

`scripts/plan-lint`, in its Step 1 section, reads only a task's first `- [ ] **Step 1: ` line, as today. A task with no such line prints nothing, as today. The headings are classified as follows:

- A heading matching `^No new test, because .*[A-Za-z0-9]` is the fourth form (`step1_class` `none`) and prints nothing.
- Any other heading that begins `No new test` prints `ERROR Task <n>: Step 1 must read "No new test, because <reason>"`.
- A heading that is none of the four forms prints `WARN Task <n>: Step 1 "<heading>" is none of the forms in test-step-forms.md`. `<heading>` is the text `plan-lint` already extracts. The four forms are:
  - `Write the failing test`, plurals included;
  - ``Extend the test `…` ``;
  - ``Covered by Task <N>'s test `…` ``;
  - the `No new test` form.
- A `Covered by Task <N>` whose Task `<N>` has the `none` form gets the existing ERROR `Covered by Task <N> — Task <N> has no test step`. The current code already gives it (`plan-lint` counts only `write` and `extend` as test steps).

`criteria/plan-review.md`, Executability:

- A task whose Step 1 reads "No new test, because" is judged by its reason, as a Covered by task is judged by its fault. Score LOW when the reason names neither a property nor an existing test. Also score LOW when a realistic fault exists that no existing test catches.
- Score LOW a task whose Step 1 heading is none of the four forms. A one-line Assumptions entry does not excuse the heading.

Fixtures change wherever their Step 1 heading is incidental to what they test. The heading becomes `Write the failing test`:

- `tests/plan-lint.test.sh`: the `claude_plan` fixture's `Write it` becomes `Write the failing test`, and ``Mark the `TODO` column`` becomes ``Write the failing test for the `TODO` column``. The check that reads that text follows it. The expected warning counts do not move.
- `tests/inline-only-execution.acceptance.test.sh`: `Step 1: Do it` becomes `Step 1: Write the failing test`, so its no-WARN assertion holds.
- `tests/antigravity-executor-lane.acceptance.test.sh` A5: its `a5_scope` filter, which already drops lines that later specs changed on purpose, also drops the new Step 1 WARN line. That covers both the fixture plans and the historical plans it lints.

Other suites with unrecognized headings assert nothing the WARN changes and are not edited:

- `tests/review-depth-qa.acceptance.test.sh`;
- `tests/inline-only.acceptance.test.sh`;
- `tests/ui-ux-skill.acceptance.test.sh`.

Delete the pin `process-roles.test.sh` "writing-plans forms: Step 1 takes one of three forms". Add no test that pins "the complete code of its tests".

### Row 7: one test per behaviour moves into writing-plans

Move the sentence "Plan tests per behaviour: one test per acceptance statement or behaviour, at the lowest layer that can fail for it, rather than one per task." out of `test-step-forms.md`. It goes into `skills/writing-plans/SKILL.md`, in the paragraph that begins "Step 1's test sits at the lowest layer".

`criteria/plan-review.md`, Executability, gains a finding beside Redundant test: score LOW when a plan writes one test per task where one test per behaviour would do, and name the tasks whose tests one test would cover.

Delete the pin `process-roles.test.sh` "writing-plans forms: tests are planned per behaviour".

### Row 9: test-quality at every standard final review that changes a test

`scripts/lens-route --final` at standard depth applies two counts:

- A lens other than test-quality prints while two conditions hold: fewer than two lenses other than test-quality have printed, and the total printed is below `lensCap`.
- Test-quality, when its `Applies:` clause matches, prints while the total printed is below `lensCap`.
- Any other lens that applies prints `lens-skipped <id> reason=cap`.

For example, `lensCap` 3 with security, silent-failures, test-quality and lang-bash applying prints the first three and skips lang-bash. Light depth and full depth do not change.

Prose that describes the limit follows the script:

- the Lenses row of the depth table in `reference/final-review.md`, and its step 1 sentence "at standard it prints at most two";
- the usage comment of `lens-route`;
- the matching row in `plugins/dforge/README.md`.

`criteria/lenses/test-quality.md`, `{#redundant}`, is reworded:

- **Scope:** among the tests in files the branch changes, report a test that fails for no fault that another test does not also catch, and name the covering test.
- **A redundant test added on the branch:** report it as Important. The fix is to merge it into a table row or delete it, under the existing rule.
- **A redundant test that exists at the merge base, covered by a branch test:** handled as the owner decided at the spec review (Decisions).

The lens reports such a test as Important, with the one-liner prefix `deferred: test-simplifier —`. The **Redundant tests.** paragraph of `reference/final-review.md` gains one sentence:

- the fixer is not given such a finding;
- the session records it with `scripts/register add <register> "<old test> is covered by <new test>" --state deferred --note "final review: for dforge:test-simplifier"`, the way `reference/auto-run.md` records a residual;
- it is counted in the lens line's raised count only, as a parked finding is.

This behaviour supersedes the "standard keeps at most two lenses" statements of earlier specs. The behaviour tests that check them are updated to the new output:

- the standard cases in `tests/lens-route.test.sh`;
- A8 in `tests/review-depth.acceptance.test.sh`;
- A8 in `tests/review-depth-qa.acceptance.test.sh`.

Historical specs are not edited.

### Row 11: one acceptance file per test project

`reference/acceptance-qa.md`, procedure step 2: QA writes one file named `<spec-slug>.acceptance.<ext>` per test project the statements reach. A test project is a directory with its own test runner or project file.

Every singular reference to the file becomes plural:

- the `rerun` mode: "the acceptance files may already exist", "Run them as they are, never rewrite a test in them";
- the `reword` mode: "run the whole files";
- step 3: each file runs with its own project's runner, scoped to it, under `timeout`; the commit sentence names the acceptance files;
- step 4's mutation-worktree sentence;
- step 5's "the acceptance file and the test's line";
- the report example, which carries one `Command:` line per file. No script parses that line.

The fix-wave sentence of `reference/final-review.md` that begins "The fix wave's verification runs the acceptance file" also becomes plural. No file-count check is added. Delete the pins `process-roles.test.sh` "qa: the committed tests reach the mutation worktree" and "qa: rerun mode".

### Row 12 (batch B half): no new wording pins

- **`skills/writing-plans/SKILL.md`**, beside the row 7 sentence: a sentence in a skill, reference or prompt gets a test only when a script reads it (writing-good-tests.md, "Behavior, not text"). Wording a script parses, such as the Step 1 forms and a template's placeholders, is the exception. If this sentence would push `SKILL.md` past 20,000 bytes, it goes into `test-step-forms.md` instead, which is read before every Step 1. The row 7 sentence stays in `SKILL.md` either way.
- **`criteria/plan-review.md`, Executability:** score LOW a planned test that checks the wording of a document no script reads.
- **`skills/brainstorming/references/drafting-acceptance.md`**, in the bullet that defines `test` and `demo`: a statement about the wording of a document no script reads is tagged `demo`. Acceptance QA would turn a `test` statement into a test, and that test would be a wording pin.

### Row 13: a bounded design names its tests

`skills/brainstorming/SKILL.md`:

- Bounded step 3 becomes "approach, files touched, and the tests: each one, the fault it catches and any existing test it extends, or that the change earns none and why".
- Self-review item 2 checks the same thing.

It is not a gate and has no cost threshold.

### Pins, the split check and the size cap

Every wording pin this batch breaks is deleted in the commit that changes the sentence, and the commit body names it. Besides the five `process-roles.test.sh` pins at "Step 1 takes one of three forms", "tests are planned per behaviour", "qa: the committed tests reach the mutation worktree", "qa: rerun mode" and "lens: a redundant branch test names its cover", these break:

- `final-phase.test.sh` "final review: the lens column by depth";
- the `{#redundant}` sentence assertion of A12 in `evals/tiers/tests/test-tiers-and-ci-parity.acceptance.test.mjs`. The heading assertion stays.

After the edits, each sentence that A2 in `evals/tiers/tests/speed-and-cost.acceptance.test.mjs` reports as lost goes into that file's `REMOVED` list, and nothing else does. The A2 check itself stays. It searches each split skill's `SKILL.md` together with its `references/`, so a sentence moved between them is not lost.

Sizes on 2026-11-11 (`wc -c`):

| File | Bytes |
|---|---|
| `writing-plans/SKILL.md` | 18,678 |
| `brainstorming/SKILL.md` | 18,767 |
| `test-driven-development/SKILL.md` | 10,375 |

Every `skills/*/SKILL.md` stays at or under 20,000 bytes (`tests/skill-size.test.sh`).

## Files

- `plugins/dforge/scripts/plan-lint`, `plugins/dforge/scripts/lens-route`
- `plugins/dforge/tests/plan-lint.test.sh`, `plugins/dforge/tests/lens-route.test.sh`, `plugins/dforge/tests/review-depth.acceptance.test.sh`, `plugins/dforge/tests/review-depth-qa.acceptance.test.sh`, `plugins/dforge/tests/process-roles.test.sh`, `plugins/dforge/tests/final-phase.test.sh`, `plugins/dforge/tests/inline-only-execution.acceptance.test.sh`, `plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh`
- `evals/tiers/tests/test-tiers-and-ci-parity.acceptance.test.mjs`, `evals/tiers/tests/speed-and-cost.acceptance.test.mjs`
- `plugins/dforge/skills/test-driven-development/SKILL.md`
- `plugins/dforge/criteria/lenses/test-quality.md`, `plugins/dforge/criteria/plan-review.md`
- `plugins/dforge/skills/requesting-code-review/references/code-reviewer.md`
- `plugins/dforge/skills/subagent-driven-development/references/{implementer,task-reviewer,group-reviewer}-prompt.md`
- `plugins/dforge/skills/writing-plans/SKILL.md`, `plugins/dforge/skills/writing-plans/references/test-step-forms.md`
- `plugins/dforge/skills/brainstorming/SKILL.md`, `plugins/dforge/skills/brainstorming/references/drafting-acceptance.md`
- `plugins/dforge/reference/final-review.md`, `plugins/dforge/reference/acceptance-qa.md`, `plugins/dforge/README.md`

## Acceptance

A1. [test, high] `plan-lint` on a plan whose task has `- [ ] **Step 1: No new test, because the change is prose no script reads**` prints no ERROR and no WARN line naming that task's Step 1.
A2. [test, neg, high] `plan-lint` prints `ERROR Task <n>: Step 1 must read "No new test, because <reason>"` and exits non-zero for each Step 1 heading `No new test`, `No new test, because`, `No new test, because .` and `No new test because x`.
A3. [test, high] `plan-lint` prints `WARN Task <n>: Step 1 "Do it" is none of the forms in test-step-forms.md` for a Step 1 heading of `Do it`, and that warning alone leaves its exit status 0.
A4. [test, neg, high] `plan-lint` prints no Step 1 WARN for `Write the failing test`, `Write the failing tests`, ``Extend the test `t/a.test.sh::first` ``, a valid ``Covered by Task <N>'s test `first` ``, or a task with no Step 1 line.
A5. [test, neg, high] `plan-lint` prints `ERROR Task <m>: Covered by Task <n> — Task <n> has no test step` when Task `<n>`'s Step 1 is the `No new test` form.
A6. [test, high] `lens-route --final` at standard depth with the default `lensCap` 4, on a change set that adds a shell file with `2>/dev/null`, a test file and a README, prints `lens security`, `lens silent-failures` and `lens test-quality`, and skips every other applicable lens with `reason=cap`.
A7. [test, neg, high] `lens-route --final` at standard depth, on a change set where no path matches test-quality's `Applies:` clause, prints at most two `lens` lines.
A8. [test, high] `lens-route --final` at standard depth with `lensCap` 2, on a change set that changes a test file and where security and silent-failures apply, prints exactly two `lens` lines and `lens-skipped test-quality reason=cap`.
A9. [test, high] `lens-route --final` at standard depth, run from a copy of the plugin whose security lens has an `Applies:` clause that matches nothing, on a change set where silent-failures, test-quality and lang-bash apply, prints `lens` lines for those three.
A10. [test, neg, high] For the change set of A6, `lens-route --final` at light depth prints `lens security` and skips silent-failures, test-quality and every other applicable lens with `reason=depth`. At full depth with `lensCap` 4 it prints `lens security`, `lens silent-failures`, `lens test-quality` and `lens lang-bash`, and skips the rest with `reason=cap`.
A11. [demo, high] The test-driven-development skill's checklist, When to Use list, the two rationalization rows, the Iron Law and the Final Rule read as Row 4 describes, and nothing in the skill asks for a test per function, per edge case, or for a refactor.
A12. [demo, high] The five reviewer and self-review sites of Row 5 ask for the input that reaches the untested branch and the wrong result. The Strengths example names a behaviour, not a test count. No site calls an unnamed coverage gap a finding.
A13. [demo, high] `test-step-forms.md` lists four forms, one of them `No new test, because <reason>`, and `plan-review.md` judges that form by its reason and scores LOW a heading that is none of the four.
A14. [demo, high] The one-test-per-behaviour sentence appears in `writing-plans/SKILL.md` and not in `test-step-forms.md`, and `plan-review.md` Executability scores LOW one test per task where one per behaviour would do.
A15. [demo, high] `test-quality.md` `{#redundant}` reports a redundant branch test as Important and a merge-base test covered by a branch test as Important with the prefix `deferred: test-simplifier —`. `final-review.md` keeps that finding from the fixer and records it as a deferred register row. `final-review.md` and the README describe the standard lens limit as `lens-route` prints it.
A16. [demo, high] `acceptance-qa.md` asks for one acceptance file per test project, runs each with its own project's runner, reports one `Command:` line per file, and has no singular "the acceptance file" left.
A17. [demo, high] `writing-plans` (its `SKILL.md`, or `test-step-forms.md` under the size fallback) and `plan-review.md` cite the "Behavior, not text" rule with the script-parsed exception, and `drafting-acceptance.md` tags a wording-only statement `demo` in the bullet that defines the tags.
A18. [demo, high] Bounded step 3 and self-review item 2 of `brainstorming/SKILL.md` ask for each test, the fault it catches and any test it extends, or for the reason the change earns none.
A19. [demo, neg, high] No test added on this branch reads the text of a skill, reference, criteria or prompt file to assert its wording. Every wording pin this branch breaks is deleted rather than updated, the A2 `REMOVED` entries aside.

## Riskiest assumption

The suites that the new WARN turns red are exactly the three Fable found by reading them on 2026-11-11:

- `tests/plan-lint.test.sh`: the `claude_plan` fixture's two headings change its warning counts, and a check reads one of those headings;
- `tests/inline-only-execution.acceptance.test.sh`: a no-WARN assertion;
- `tests/antigravity-executor-lane.acceptance.test.sh` A5: it lints fixture plans and five historical plans and compares the output with a base checkout's.

No caller outside the tests lints plans for warnings, and `plan-amend` compares only ERROR lines (`scripts/plan-amend`). Status: unverified — the plan's first task verifies it, by running the whole dforge suite with only the WARN in place.

## Review rulings

- Fable, spec: the lensCap session ruling upheld, stated as two counts with a `lensCap` 3 example.
- Fable, spec: the empty-reason session ruling upheld; the form is `^No new test, because .*[A-Za-z0-9]`, every other `No new test` heading gets `Step 1 must read "No new test, because <reason>"`, and A2 gains `No new test because x`.
- Fable, spec: a task with no Step 1 line prints nothing, and only a task's first Step 1 line is read.
- Fable, spec: the fourth form covers a task whose realistic faults an existing test already catches, so a refactor fits it; the reason names a property or an existing test.
- Fable, spec: the riskiest assumption was false; three suites go red, two were missing from Files, and the first task runs the whole suite.
- Fable, spec: incidental fixture headings become `Write the failing test`; A5's `a5_scope` drops the new WARN line.
- Fable, spec: test-step-forms.md's heading becomes `## The Step 1 forms`, and the fourth form's paragraph says what plan-lint does.
- Fable, spec: the refactor characterization exception is the TDD skill's own, not writing-good-tests.md's.
- Fable, spec: Row 5 gives each site's replacement text and adds the two "Coverage could be broader" calibration lines.
- Fable, spec: `{#redundant}` is reworded to reach tests in changed files; a fifth `process-roles.test.sh` pin breaks.
- Fable, spec: A8 names the changed test file, A9 uses a plugin copy whose security lens matches nothing, A10 gives literal output.
- Fable, spec: Row 11 lists every singular reference in acceptance-qa.md; step 3 runs each file with its project's runner; one `Command:` line per file.
- Fable, spec: the spec records the SKILL.md sizes, and the row 12 sentence moves to test-step-forms.md if writing-plans would pass the cap.
- Fable, spec: only sentences A2 reports as lost go into `REMOVED`; A19 excepts those entries.
- Fable, spec: the row 12 tagging rule goes in drafting-acceptance.md's bullet that defines the tags.

## Critic findings

Critic: 1 Blocker, 1 High (2 fixed, 0 answered), 4 Medium (in Fable's review).

- [Blocker] Row 9's deferred finding is dropped by the lens floor and recorded nowhere. Fixed: the owner chose Important, parked, at the spec review.
- [High] A refactor fitted no Step 1 form. Fixed: the fourth form now covers faults an existing test catches.
- [Medium] The riskiest assumption was false and two suites were missing from Files. Fixed.
- [Medium] The WARN was advisory. Fixed: plan-review scores LOW an unrecognized heading.
- [Medium] The added lens seat could report nothing on a short plan. Fixed: a redundant branch test is Important.
- [Medium] The size cap had no headroom figure or fallback. Fixed: sizes recorded, fallback stated.
- [Nit] The ERROR text was wrong for a reason in the wrong shape. Fixed with the empty-reason ruling.
