# Measured proposals

**Execution strategy:** sequential — inline execution
**Depth:** standard — interface

Five review and plan changes taken from
`docs/dforge/registers/2026-11-15-measured-proposals.md`. Two of them change
reviewer behaviour and are kept only if a replay on merged branches shows they
did no harm. Register row 7 (a re-check of light-depth plans) is set to
`deferred`.

## Decisions

- Flow: "Full dforge flow (Recommended)".
- Scope: "Review prompts (rows 3, 4), plan-lint path checks (row 1), Retire
  dead review parts (rows 2, 6), Lean plan tests (row 5)". Row 7 is deferred:
  it needs five shipped light plans, and two exist
  (`2026-11-13-dflow-hud-overhaul`, `2026-11-11-downloads-mutation-measurement`).
- Measurement: "Replay on past branches (Recommended)": the review-prompt
  change and the lean plan tests are each measured before and after, and
  each is kept only if the measurement passes.
- Evidence: "Prompt rule (Recommended)": an `Evidence:` line in the Claude
  final review, lens and plan-review prompts, and a fixer that rejects
  findings it cannot reproduce. The review schemas and task-step's parser stay
  as they are.
- Lenses: "Keep language lenses, run them in lens-code-quality depends on the
  project stack".
- Contents: "Fold both": the code-quality lens carries the matching language
  files, type-design and docs-comments.
- Ranking: "Outside the limits (Recommended)": code-quality, like
  test-quality, does not count toward standard depth's two-lens limit, and the
  `lensCap` default rises from 4 to 5. At light depth only security still
  runs.
- Design ruling (mine, upheld by the spec review): plan-lint checks paths and
  line ranges, not symbols. Step 3 may name its target by a signature, a
  heading or a quoted anchor (`skills/writing-plans/SKILL.md:229-230`), and no
  single matcher covers all three, so symbol checks stay with the plan
  reviewer.
- Design ruling (mine, from a spec-review Medium finding): the six part files
  stay in `criteria/lenses/`, and `lens-route --final` groups them at route
  time. Moving them would break plans whose `**Lenses:**` line names a part
  (`docs/dforge/plans/2026-11-13-reviewer-only-externals.md:746`), the lens
  shape test (`tests/criteria.test.sh:25-68`) and `lens-route --task`'s one
  reader (`scripts/task-step:757-764`), for no gain the Decisions ask for.
- M1 runs (spec review): "Two per arm (Recommended)".
- M2 check (spec review): "Add revert-per-file check (Recommended)".

Early CI: none

Finish: merge

Worktree: in-place

## Current state (2026-11-15)

The sweep of the current code that this design starts from:

- Row 1: the delta template for later plan-review rounds already exists
  (`skills/writing-plans/references/lint-and-review.md:62-66`). plan-lint does
  not check that task paths exist; `plan_task_paths` (`scripts/lib/plan.sh:209`)
  already parses them. The "edit's old text is present" check no longer
  applies, because a Claude plan's Step 3 carries no implementation code.
- Row 2: spec review already runs only for architectural work, and the critic
  already scales with depth. The second-judge stage no longer exists. Across
  the six records in `docs/dforge/reviews/`, `lang-bash`, `lang-typescript`
  and `docs-comments` never ran: at standard depth, security and
  silent-failures fill the two slots besides test-quality, and at full depth
  security, ui-ux, silent-failures and test-quality fill `lensCap` 4.
- Row 3: `criteria/codex-final-review.md:13-19` already requires each finding
  to name a concrete failure and forbids style findings, for the external
  final-review seats. The Claude final review still files code style as Minor
  (`skills/requesting-code-review/references/code-reviewer.md`, Output
  Format), and nothing requires a fixer to reproduce a finding.
- Row 4: the task reviewer and re-reviewer already read the diff first and do
  no broad crawls (`reference/prompts/task-reviewer-prompt.md:36-50`). The
  Claude final review, the lens prompt and the plan reviewer have no search
  limit.
- Row 5: Claude plans already carry no implementation code; they still carry
  the complete code of every test (`skills/writing-plans/SKILL.md`, Step 3,
  and `criteria/plan-review.md` Executability). Several files still say that
  a small-model implementer sees only its task's text, which no longer matches
  inline execution (listed in §4).
- Row 6: risk gating already goes further than proposed: only risk-3 tasks
  get a per-task review. The small-fix re-review skip in `scripts/task-step`
  (`:428-452`) refuses to skip on a risk-3 task, so it does not fire in the
  documented loop; it is reachable only when recovery reviews an older run's
  task (`reference/delegated-task.md:664`, `tests/task-step.test.sh:588`).

## Design

### 1. plan-lint path checks (row 1)

plan-lint gains one check, run inside its existing per-task loop
(`scripts/plan-lint:275-277`) on the task text it already holds, with
amendments applied. Paths resolve against the top level of
`_plan_ctx "$plan"` (`scripts/lib/plan.sh:228-237`), not against
`plan-lint`'s own `root`, which resolves a mirror plan under a git-tracked
home to the wrong checkout.

**Created paths.** A path counts as created for task N when it is on a
`- Create:` line of task N or a lower-numbered task, or on a `- Test:` line of
task N or a lower-numbered task whose Step 1 heading is `Write the failing
test` (the plan template puts a new test file there,
`skills/writing-plans/SKILL.md:188-191`).

**Existence.** Each `- Modify:` and `- Test:` path must exist or be created
in that sense. Otherwise: `ERROR: Task <N>: <path> does not exist and no
earlier task creates it`.

**Ranges.** A range on an existing file is either `:<a>` or a
comma-separated list of `:<a>-<b>` and `<a>` items (`:35-44,66-72` occurs in
`docs/dforge/plans/2026-10-25-typed-seats-and-drafting.md:593-594`). Each item
must satisfy `1 <= a <= b <= <line count>`, where the count includes an
unterminated last line. Otherwise: `ERROR: Task <N>: <path>:<range> is outside
the file's <n> lines`. A range on a created path is not checked. Lines are
counted only for paths that carry a range, with no subprocess per path,
because the plan-lint suite is already slow on the Windows shards
(`scripts/plan-lint:452-454`) and `scripts/plan-amend:133-134` runs the lint
twice per amendment.

**Parsing.** Only the first code span of a Files line is checked, as
`plan_task_paths` reads it (`scripts/lib/plan.sh:215-217`). A first span
holding `*` is not checked. `- Create:` and `- Delete:` paths are not checked:
a Delete path is gone once its task has run.

`plan_task_paths` gains a mode that keeps the range for this caller; its
existing callers' output is unchanged. Only `plan-amend`'s before-and-after
comparison is supported mid-run: it blocks only on errors its amendment adds,
so a range that went stale after a task ran blocks nothing. A lint run by hand
after tasks have run may print stale path errors.

The plan-reviewer prompt's note on the lint output gains one clause: path
existence and line ranges are checked, so the reviewer does not re-check them.

### 2. The code-quality lens and the dead skip (rows 2, 6)

**Grouping.** `lang-bash`, `lang-csharp`, `lang-python`, `lang-typescript`,
`type-design` and `docs-comments` stay in `criteria/lenses/` with their
`Applies:` lines and criteria. They become the parts of a code-quality lens
that `scripts/lens-route --final` assembles:

- `lens_order` becomes security, ui-ux, silent-failures, test-quality,
  code-quality, then any other lens. A part is never printed as a lens of its
  own by `--final`.
- code-quality applies when at least one part's `Applies:` line matches the
  change set. It prints `lens code-quality parts=<p1>,<p2>
  seat=dforge:judge-sonnet-high reason=<first matching part's reason>`, with
  the matching part paths in the order lang-* (alphabetical), type-design,
  docs-comments. When no part applies it prints nothing for code-quality.
- Like test-quality, it does not count toward standard depth's two-lens limit.
  It counts toward `lensCap`, whose default becomes 5. At light depth it prints
  `lens-skipped code-quality reason=depth`.

`lens-route --task` is unchanged: a risk-3 task's `**Lenses:**` line still
names part ids, and `scripts/task-step` reads the `criteria=` lines as today.
`skills/writing-plans/references/assignment-procedure.md:40-44` gains one
sentence: a `**Lenses:**` line names the part ids, never `code-quality`.

**Lens prompt** (`reference/final-review.md:280-295`). For code-quality the
prompt reads "Read the lenses at these part files: <parts>", the paths taken
from the route line's `parts=` field. Its report is
`<workspace>/lens-code-quality-report.md`, and each finding keeps its part's
own tag (`[lens:lang-bash]`, as the part file says). The dedupe judge and the
fixer receive the part paths. The retained line
(`reference/final-review.md:483-489`) for code-quality counts every finding
tagged with one of its parts, and ends `; parts <id>=<findings>,...`, so later
records show which parts earn their seat.

**Every site of the default and the limit text:** `config/schema.mjs:147`,
`scripts/lens-route:112-113`, `reference/final-review.md:50` and `:274-278`,
`README.md:102` and `:916`, `reference/native-codex.md:306-313` (its priority
list, and how a Codex host picks code-quality's parts by hand from their
`Applies:` lines).

**Dead skip removal.** In `scripts/task-step`: the `--covered` option (`:10`,
`:36`, `:307`, `:343`, `:352`), the skip decision (`:428-452`), `suite_gap`
(`:287-304`, whose only caller is `:450`) and the skipped digest (`:488-490`,
`:494`). In `reference/delegated-task.md`: `:431-432`, `:435`, `:455-473`, the
`[; re-review skipped (<n> lines)]` clause at `:476` and `:604`, and "its skip
rule included" at `:602`. Every fix round gets its re-review.

**Tests this changes:** `tests/lens-route.test.sh` (`:45`, `:62-102`,
`:145-226`, `:83`), `tests/dforge-config.test.sh:162`,
`tests/review-depth.acceptance.test.sh:331-337`,
`tests/review-depth-qa.acceptance.test.sh:361` and `:385-399`,
`tests/test-volume-rules.acceptance.test.sh:211-255`,
`tests/ui-ux-skill.acceptance.test.sh:806-839`, `tests/task-step.test.sh`
(`:93`, `:293`, `:587-731`), `tests/task-loop-steps.acceptance.test.sh`
(`:112`, `:245`, `:371-401`), `tests/task-step-base.test.sh:251-293`. A new
suite file needs a row in `scripts/test-shards.mjs`.

### 3. Evidence-bound, diff-first review prompts (rows 3, 4)

These apply to the Claude final review
(`skills/requesting-code-review/references/code-reviewer.md`, its Example
Output included), the lens prompt (`reference/final-review.md:280-295`), and
both templates of the plan reviewer
(`skills/writing-plans/references/plan-reviewer-prompt.md`: round 1 at
`:11-76` and Later rounds at `:148-209`).

- **Evidence.** Every finding carries an indented `Evidence:` line: either the
  input, state or command that reaches the defect and the wrong result it
  gives, or a quoted line of the spec, plan or brief that the change breaks,
  with its location. A finding with no evidence is not reported. Style
  preferences are not findings; code-reviewer.md's Minor definition drops
  "code style" and keeps optimisation and documentation defects. In the lens
  prompt the `Evidence:` line is one of the indented detail lines, and the
  limit at `reference/final-review.md:291-292` rises from three to four.
- **Diff first, narrow search.** The reviewer reads the diff file once, opens
  a repository file only for a range a hunk names or for a question it can
  state in one sentence, and greps for the named symbol rather than crawling.
  Each report format gains a last section `## Opened`, one
  `- <path> — <the question>` line per file outside the diff. For the plan
  reviewer, the diff is the plan: it opens code only to check a claim a task
  makes about it.
- **Plan reviewer on external seats.** The evidence requirement and the
  diff-first rule go in the templates' shared body (`## Findings`,
  `plan-reviewer-prompt.md:35-49`), so external seats get them and put the
  evidence in their schema's `summary`. The `Evidence:` line format and
  `## Opened` go in `## Output Format`, which only a Claude judge sees
  (`plan-reviewer-prompt.md:105-108`). No schema changes.
- **Fixer reproduces first.** In `reference/final-review.md` §Fixing what it
  finds, with one list and with two (`:427-428` loses "in the one-list case"),
  the fixer reproduces each finding before fixing it: it runs the input or
  command the finding's `Evidence:` line names at the review HEAD, or, for a
  quoted-line finding, shows the quoted line beside the code or text that
  breaks it. A finding whose run contradicts it is recorded as
  `REJECTED: <finding> — not reproduced: <what was run and its result>`, the
  finding keeping its `[lens:<id>]` tag. `[qa]`, `[suite]` and `[ci]` findings
  and carried gaps are exempt: their failing test or command is the
  reproduction.
- **Re-review.** `reference/prompts/re-review-prompt.md:105-108` gains one
  sentence: a not-reproduced rejection is upheld when the fix report shows the
  run and its result contradicts the finding.

No script reads these reports; the session and the dedupe judge do. The
finding line format (`- [Severity] <file>:<line> — <one-liner>`) does not
change. The external Codex and agy final-review criteria are unchanged.

### 4. Lean plan tests (row 5)

On a Claude plan, a task's Step 1 replaces the complete test code with a test
contract, one entry per test:

```
- `<test file>::<test name>` (<unit|integration|e2e>): given <input or
  state>, asserts <exact observable result>; fails today because <fault>.
```

The `::` notation is the one `test-step-forms.md:8` and `:27` and
`scripts/plan-lint:465` already use. The exact strings, exit codes and values
the assertion checks come from the plan's Contracts or are written inline.
Step 2 (run it, see it fail) is unchanged, and so are the "Covered by Task N's
test" and "No new test, because" forms. An Extend step
(`test-step-forms.md:8-12`) carries one contract entry for the added row or
case. A `Host: codex` plan keeps complete test and implementation code.

Files: `skills/writing-plans/SKILL.md` (task template, `:292-296`, No
Placeholders list), `skills/writing-plans/references/test-step-forms.md`,
`criteria/plan-review.md` (Executability: HIGH when every contract names its
file, test name, layer, input and exact asserted result, and states a fault a
stub would not survive; LOW for a contract that two readers could turn into
tests catching different faults; the file stays ASCII,
`tests/criteria.test.sh:55-56`), both plan-reviewer templates, and
`README.md:1163`.

**Stale wording** (its own commit, kept whatever M2 finds). The lines saying
that a task's implementer sees only that task's text, or that small models
execute the plan literally, go from `skills/writing-plans/SKILL.md:17-19`,
`:195-197`, `criteria/plan-review.md:11` and `:14-16`,
`plan-reviewer-prompt.md:6`, `:24-26` and `:153-155`, and
`skills/writing-plans/references/assignment-procedure.md:19-20`. Their
replacement says that the session implements every task and reads it through
its brief. `README.md:22`, a heading in the fork's history, stays.

### 5. Measurements

Both measurements write a note under `docs/dforge/notes/` and run in scratch
clones, never in this checkout. Seats are subscription seats; no API budget
is spent. Each runs inside the task that makes the change it measures, before
that task's `complete` line, so no later commit sits on hunks a revert would
undo. A measurement that cannot finish (a seat fails twice, a report is
missing) counts as not passed.

**M1, review prompts (the plan's first task, after §3's edits).** Three
merged branches, from `docs/dforge/notes/2026-11-14-agy-hydrogen-review.md:19-21`
and `docs/dforge/reviews/2026-11-13-dflow-hud-overhaul.md:8`: b1
`b36eaf63..bc097711` (cockpit fixes), b3 `5bb5545f..e48eeafa` (retire executor
lanes) and `9d46f4e..52da46e0` (dflow-hud overhaul). For each, the Claude final
review runs four times on the same `scripts/review-package` output, through
`dforge:judge-opus`: twice with code-reviewer.md as it stood before §3 (`git
show <pre-change sha>:...`) and twice with the new file, 12 reviews in all. b1 has no plan, so its
package is built with an explicit OUTFILE and its `[PLAN_OR_REQUIREMENTS]` is
its commit subjects, the same in both arms.

A fresh `dforge:judge-opus` judges every finding of all twelve reports in one
shuffled list, each finding given as `<file>:<line> — <one-liner>` and its
detail lines with any `Evidence:` line removed, and no prompt version named:
confirmed (a real defect of that diff) or unconfirmed. The note records, per
run, the findings by severity, the confirmed counts, and the dispatch's total
tokens from the Agent tool result; the plan's Assumptions confirm that number
is available before the first task.

Keep rule, summed over the three branches: the new prompt's confirmed
Critical and Important findings are at least the old prompt's, and either its
total tokens or its unconfirmed share is lower (a run with no findings has an
unconfirmed share of 0). M1 measures code-reviewer.md only; the lens prompt,
the plan-reviewer prompt and the fixer rule are judged by that proxy, and the
fixer rule's risk (a real finding rejected) is not measured. If the rule fails,
every §3 edit is reverted.

**M2, lean tests (inside the §4 task).** Four tasks: in each of
`docs/dforge/plans/2026-11-14-api-decisions-keep-warm-hydrogen.md` and
`docs/dforge/plans/2026-11-13-reviewer-only-externals.md`, the first two tasks
whose Step 1 is "Write the failing test" and whose commit `git log` identifies
by its subject. The session rewrites each Step 1 as a §4 contract from the
plan's own test code; the note records which contract entry covers each
original assertion, and the Step 1 line count before and after. In a scratch
clone at the task's base commit, a `dforge:impl-sonnet-high` seat, given only
the `scripts/task-brief` output for a plan copy with the rewritten Step 1 plus
`plan-header.md`, writes the tests and nothing else. Each written test must
fail at the base commit and pass at the task's commit. Then, for each
non-test file the task changed, that file alone is reverted to the base at the
task's commit: whenever the plan's own tests fail on that state, the
contract-written tests must fail too.

M2 shows an upper bound: the contracts are written by a session that holds the
finished tests, while a planner writes them before any test exists. It can
show that the contract grammar carries too little detail; it cannot show that
planners will write good contracts.

Keep rule: all four tasks' tests pass the check. If any fails, the §4 edits
are reverted (the stale-wording commit stays) and the note records the
contract that failed.

**Register outcome.** Rows 3 and 4 (M1) and row 5 (M2) end `done` when kept,
and `n/a` with a note naming the measurement note when reverted.

## Acceptance

A1. [test, high] plan-lint reports an ERROR naming the task and path when a task's `- Modify:` or `- Test:` path does not exist and is not created, for that task, by a `- Create:` line or by a `- Test:` line of a Write-the-failing-test task, numbered the same or lower.
A2. [test, neg, high] plan-lint reports no path error for a `- Create:` or `- Delete:` path, for a path created as A1 defines, for a `- Test:` path of a task whose Step 1 is Write the failing test, or for a first span holding `*`.
A3. [test, high] plan-lint reports an ERROR when any item of a Modify or Test range on an existing file has a start below 1, a start above its end, or an end beyond the file's line count (an unterminated last line counted), and none for valid single and comma-separated ranges.
A4. [test, neg, high] plan-amend accepts an amendment to a plan whose path or range errors were already there before the amendment.
A5. [test, high] `lens-route --final` prints exactly one `lens code-quality parts=...` line whose parts are every part whose `Applies:` line matches the change set, in the order lang-* alphabetical, type-design, docs-comments, and prints no lens or lens-skipped line for a part id.
A6. [test, high] At standard depth, with security, silent-failures, test-quality and at least one part applying, `lens-route --final` prints lens lines for all four and no `reason=cap` line, at the default `lensCap`.
A7. [test, high] With `lensCap` unset, lens-route and `dforge-config` use 5.
A8. [test, neg, high] At light depth, with a part applying, `lens-route --final` prints `lens-skipped code-quality reason=depth` and no code-quality lens line.
A9. [test, neg, high] When no part applies, `lens-route --final` prints no code-quality line of either kind.
A10. [test, neg, high] `lens-route --task` prints a `lens <part> criteria=<path>` line for each part id on a risk-3 task's `**Lenses:**` line, as before.
A11. [test, neg, high] `lens-route` exits 2 on a `Host: codex` plan.
A12. [test, high] `task-step` has no `--covered` option (a usage error), and a fix round of one finding in three or fewer lines still requires its re-review.
A13. dropped — the spec review found that no script reads review reports, so it had nothing to test.
A14. [demo, high] When M1's keep rule held: the Claude final review, lens and plan-review prompts require an `Evidence:` line per finding, report no style findings, read diff-first and end with `## Opened`, and code-reviewer.md's Minor definition no longer names code style; otherwise those files match their pre-change content and the M1 note records the result.
A15. [demo, high] When M1's keep rule held: the fix wave reproduces each finding first and records an unreproduced one as `REJECTED: <finding> — not reproduced: <what was run and its result>`, and the re-review prompt says when it upholds one; otherwise those files match their pre-change content.
A16. [demo, confirmed] The M1 note records all twelve runs (two per arm per branch) and the keep rule's result over their sums.
A17. [demo, high] When M2's keep rule held: a Claude plan's Step 1 carries test contracts, not test code, a `Host: codex` plan still carries complete code, and plan-review.md's Executability judges the contracts; otherwise those files match their pre-change content and the M2 note names the contract that failed.
A18. [demo, confirmed] The M2 note records the four tasks, each original assertion's covering contract entry, the fail-at-base and pass-at-commit result, and for each reverted non-test file whether the contract-written tests failed whenever the plan's own tests did.
A19. [demo, high] No dforge skill, criteria or prompt file says that a task's implementer sees only its task's text, or that small models execute the plan literally.
A20. [demo, high] `reference/native-codex.md` tells a Codex host how to pick code-quality's parts by hand.
A21. [demo, high] The retained `final review lens code-quality` line ends with each part that ran and its finding count.

## Riskiest assumption

That evidence-bound, diff-first prompts cut tokens or false findings without
losing confirmed Critical and Important findings. The only prior evidence is
external: arXiv 2603.00539, as cited in
`docs/dforge/notes/2026-10-27-speed-and-cost-research.md:55-58`.
unverified — the plan's first task verifies it: that task makes the §3 change
and runs M1, before anything else is built, and the keep rule reverts §3 if it
fails.

## Out of scope

- Register row 7: deferred until five light plans have shipped.
- Size-based review gating: per-task review already runs only at risk 3, and
  the final review's depth already sizes its stages.
- Review JSON schemas and the external Codex and agy final-review criteria.
- A pre-check before the final review beyond the existing ci-mirror, gates
  and ui-proof steps.

## Review rulings

Fable's spec review, round 1 (`.dforge/spec-review-2026-11-15-measured-proposals-design-1-report.md`): 26 rulings, all applied.

- §1 `- Test:` lines: a Test path of a Write-the-failing-test task counts as created (the critic's Blocker).
- §1 parsing: first span only; comma-separated ranges; `*` spans skipped; unterminated last line counted; root from `_plan_ctx`.
- §1 symbols: the paths-and-ranges-only ruling upheld.
- Current state row 6: the skip is reachable through recovery; removal stands.
- §2 `--task` output, part selection, prompt wording, file shape: superseded by grouping at route time (the critic's Medium on the move), which leaves `--task` and the part files unchanged.
- §2 sites of the default and limit text listed; tag and retained line specified; the removal's extent named.
- §3 review-record parses no reports: old A13 dropped.
- §3 rejection form keeps the finding and its tag; reproduction tied to the `Evidence:` line; re-review uphold condition added; rule applies with one list and two; `[qa]`, `[suite]`, `[ci]` exempt.
- §3 plan-reviewer templates: evidence and diff-first rules in the shared body, line format in Output Format.
- §3 `## Opened` section; lens detail limit three to four.
- §4 Extend form, `::` notation, full stale-wording list, A19 scoped to skill, criteria and prompt files.
- §5 M1 ranges corrected (`9d46f4e..52da46e0`); blind list without `Evidence:` lines; sums; token source; b1's package.
- §5 M2 seat `dforge:impl-sonnet-high`; who rewrites Step 1; brief contents; the redundant revert check dropped.
- Keep-rule failure path: measurement inside its own task; unfinished counts as failed; A14, A15, A17 conditional; stale wording in its own commit; register outcome.
- A20 split into a test (A11) and a demo (A20).
- Register row 7 deferred and Covers set (done 2026-11-15).

## Critic findings

Folded into Fable's round: 1 Blocker, 5 High, 7 Medium, 4 Nit. Every Blocker
and High is fixed by a ruling above.

- [Blocker] new test files on `- Test:` lines would fail the existence rule — fixed (§1 Created paths).
- [High] M2 named a seat that does not exist — fixed (`dforge:impl-sonnet-high`).
- [High] a not-reproduced rejection could never be upheld — fixed (§3 Re-review).
- [High] `--task` output for code-quality undefined — fixed by grouping at route time; `--task` unchanged.
- [High] revert path not designed — fixed (§5, A14, A15, A17).
- [High] M1's judge not blind — fixed (`Evidence:` lines removed).
- [Medium] one run per arm is noisy — asked at the spec review (A16).
- [Medium] M1 measures only code-reviewer.md — stated in §5 as a proxy.
- [Medium] M2 is an upper bound — stated in §5.
- [Medium] the move is avoidable — adopted: grouping at route time.
- [Medium] no per-part yield record — fixed (A21) and a deferred register row to re-check after five records.
- [Medium] affected tests not named — listed in §2.
- [Medium] Windows cost of the lint — §1 runs it in the existing loop and counts lines only for ranged paths.
- [Nit] code-reviewer.md's Example Output — included in §3.
- [Nit] mid-run lints — §1 says only plan-amend's comparison is supported.
- [Nit] assignment-procedure.md wording — §2 says it gains a sentence.
- [Nit] `--covered` gives a bare usage line — accepted.
