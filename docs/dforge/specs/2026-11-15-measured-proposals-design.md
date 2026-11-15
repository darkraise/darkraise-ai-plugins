# Measured proposals

**Execution strategy:** sequential — inline execution
**Depth:** standard — interface

Five review and plan changes taken from
`docs/dforge/registers/2026-11-15-measured-proposals.md`. Two of them change
reviewer behaviour and are kept only if a replay on merged branches shows they
did no harm. Register row 7 (a re-check of light-depth plans) stays deferred.

## Decisions

- Flow: "Full dforge flow (Recommended)".
- Scope: "Review prompts (rows 3, 4), plan-lint path checks (row 1), Retire
  dead review parts (rows 2, 6), Lean plan tests (row 5)". Row 7 stays
  deferred: it needs five shipped light plans, and two exist
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
- Design ruling (mine, open to the spec review): plan-lint checks paths and
  line ranges, not symbols. A Step 3 anchor is free text, and a matcher for it
  would flag paraphrases, so symbol checks stay with the plan reviewer.

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
  seats. The Claude final review still files code style as Minor
  (`skills/requesting-code-review/references/code-reviewer.md`, Output
  Format), and nothing requires a fixer to reproduce a finding.
- Row 4: the task reviewer and re-reviewer already read the diff first and do
  no broad crawls (`reference/prompts/task-reviewer-prompt.md:36-50`). The
  Claude final review, the lens prompt and the plan reviewer have no search
  limit.
- Row 5: Claude plans already carry no implementation code; they still carry
  the complete code of every test (`skills/writing-plans/SKILL.md`, Step 3,
  and `criteria/plan-review.md` Executability). Three files still say that a
  small-model implementer sees only its task's text, which no longer matches
  inline execution: `skills/writing-plans/SKILL.md:17-19`,
  `criteria/plan-review.md:14-16` and the plan-reviewer prompt's opening.
- Row 6: risk gating already goes further than proposed: only risk-3 tasks get
  a per-task review. The small-fix re-review skip in `scripts/task-step`
  (about lines 420-450) refuses to skip on a risk-3 task, so it can never fire.

## Design

### 1. plan-lint path checks (row 1)

plan-lint gains one check over every task's `- Modify:` and `- Test:` lines
(outside fences, amendments applied), resolved against the plan's checkout
root:

- The path must exist, or be named on a `- Create:` line of a lower-numbered
  task. Otherwise: `ERROR: Task <N>: <path> does not exist and no earlier task
  creates it`.
- A `:<a>-<b>` (or `:<a>`) range on an existing file must satisfy
  `1 <= a <= b <= <line count>`. Otherwise: `ERROR: Task <N>: <path>:<range>
  is outside the file's <n> lines`. A range on a file that an earlier task
  creates is not checked.
- `- Create:` and `- Delete:` paths are not checked. A Delete path is gone once
  its task has run, so checking it would fail every later lint.

The check uses `plan_task_paths`, extended to keep the range for this caller,
and leaves the existing callers' output unchanged. Mid-run lints stay safe:
`scripts/plan-amend` blocks only on errors that its amendment adds, so a range
that went stale after a task ran blocks nothing. The plan-reviewer prompt's
note on the lint output gains one clause: path existence and line ranges are
checked, so the reviewer does not re-check them.

### 2. The code-quality lens (rows 2, 6)

`criteria/lenses/code-quality.md` is a new lens whose criteria are parts.
The six part files move to `criteria/lenses/code-quality/`: `lang-bash.md`,
`lang-csharp.md`, `lang-python.md`, `lang-typescript.md`, `type-design.md`
and `docs-comments.md`. Each keeps its `Applies:` line and its criteria. The
top-level `code-quality.md` holds the lens's shared instructions (what a part
is, the `[lens:code-quality/<part>]` tag) and no `Applies:` line of its own.

`scripts/lens-route --final`:

- `lens_order` becomes security, ui-ux, silent-failures, test-quality,
  code-quality, then any other top-level lens. Parts are never listed as
  lenses.
- code-quality applies when at least one part's `Applies:` line matches. It
  prints `lens code-quality criteria=<code-quality.md> parts=<p1>,<p2>
  seat=dforge:judge-sonnet-high reason=<first matching part's reason>`, with
  the matching part paths in the fixed order lang-* (alphabetical),
  type-design, docs-comments.
- Like test-quality, it does not count toward standard depth's two-lens limit.
  It still counts toward `lensCap`, whose default becomes 5
  (`config/schema.mjs`, the `lens-route` fallback, `README.md`). At light depth
  it prints `lens-skipped code-quality reason=depth`, as every lens except
  security does.
- When no part applies it prints nothing for code-quality.

`lens-route --task`: a `**Lenses:**` line may name `code-quality`. Its parts
are those whose `paths` clause matches a path from the task's Files lines.
When none match, every part is listed. plan-lint rejects a part id
(`lang-bash`, ...) on a `**Lenses:**` line as an unknown lens id, so
assignment-procedure.md names `code-quality` instead.

`reference/final-review.md`'s lens prompt reads "the lens at <criteria path>
and each part file it lists". `reference/native-codex.md`'s hand-picking rule
reads the parts' `Applies:` lines for code-quality.

`scripts/task-step`'s small-fix re-review skip and its `--covered` option are
removed, together with the text in `reference/delegated-task.md` that
describes them. Every fix round on a risk-3 task gets its re-review, as it
does today.

### 3. Evidence-bound, diff-first review prompts (rows 3, 4)

These apply to three prompts: the Claude final review
(`skills/requesting-code-review/references/code-reviewer.md`), the lens
prompt (`reference/final-review.md`), and the plan reviewer
(`skills/writing-plans/references/plan-reviewer-prompt.md`).

- **Evidence.** Every finding carries an indented `Evidence:` line: either the
  input, state or command that reaches the defect and the wrong result it
  gives, or a quoted line of the spec, plan or brief that the change breaks,
  with its location. A finding with no evidence is not reported. Style
  preferences are not findings; code-reviewer.md's Minor definition drops
  "code style" and keeps optimisation and documentation defects. The finding
  line format (`- [Severity] <file>:<line> — <one-liner>`) does not change,
  so `scripts/review-record` and the dedupe judge parse reports as before.
- **Diff first, narrow search.** The reviewer reads the diff file once, opens
  a repository file only for a range a hunk names or a question it can state
  in one sentence, greps for the named symbol rather than crawling, and
  reports which files outside the diff it opened. For the plan reviewer, the
  diff is the plan: it opens code only to check a claim a task makes about it.
- **Fixer reproduces first.** In `reference/final-review.md` §Fixing what it
  finds, the fixer reproduces each finding before fixing it, with a failing
  test or a command and its output. A finding it cannot reproduce is recorded
  as `REJECTED: not reproduced — <what was tried>`. The scoped re-review
  judges that rejection as it judges any other.

The external Codex and agy criteria are unchanged: they already carry this
rule.

### 4. Lean plan tests (row 5)

On a Claude plan, a task's Step 1 replaces the complete test code with a test
contract, one entry per test:

```
- `<test file>` › `<test name>` (<unit|integration|e2e>): given <input or
  state>, asserts <exact observable result>; fails today because <fault>.
```

The exact strings, exit codes and values the assertion checks come from the
plan's Contracts or are written inline. Step 2 (run it, see it fail) and the
Step 1 forms of `test-step-forms.md` ("Covered by Task N's test", "No new
test, because") are unchanged. A `Host: codex` plan keeps complete test and
implementation code.

Files: `skills/writing-plans/SKILL.md` (task template, No Placeholders list),
`skills/writing-plans/references/test-step-forms.md`,
`criteria/plan-review.md` (Executability: HIGH when every contract names its
file, test name, layer, input and exact asserted result, and states a fault
that a stub would not survive; LOW for a contract that two readers could turn
into tests catching different faults), and the plan-reviewer prompt. The
stale "implementer sees only that task's text" and "small models will execute
it literally" lines go from those three files. Their replacement says that
the session implements every task and reads the task through its brief.

### 5. Measurements

Both measurements write a note under `docs/dforge/notes/` and run in scratch
clones, never in this checkout. Seats are subscription seats; no API budget
is spent.

**M1, review prompts (after §3).** Three merged branches: b1 `b36eaf63..bc097711`
(cockpit fixes), b3 `5bb5545f..e48eeafa` (retire executor lanes) and the
dflow-hud overhaul (merge `52da46e0`, its first-parent range). For each, the
Claude final review runs twice on the same `scripts/review-package` output,
through `dforge:judge-opus`: once with code-reviewer.md as it stood before §3
(`git show <pre-change sha>:...`) and once with the new file. A fresh
`dforge:judge-opus` judges every finding from all six reports in one shuffled
list, with no prompt version named, as confirmed (a real defect of that diff)
or unconfirmed. The note records, per run, the findings by severity,
confirmed counts, and the dispatch's total tokens.

Keep rule: across the three branches, the new prompt's confirmed Critical and
Important findings are at least the old prompt's, and either its total tokens
are lower or its unconfirmed share is lower. If the rule fails, the §3 commits
are reverted and the note says why.

**M2, lean tests (after §4).** Four tasks: in each of
`docs/dforge/plans/2026-11-14-api-decisions-keep-warm-hydrogen.md` and
`docs/dforge/plans/2026-11-13-reviewer-only-externals.md`, the first two tasks
whose Step 1 is "Write the failing test" and whose commit `git log` can
identify by its subject. Each task's Step 1 is rewritten as a §4 contract. In a
scratch clone at the task's base commit, a `dforge:impl-opus-medium` seat
given only the brief with the contract writes the tests and nothing else.
Each written test must fail at the base commit and pass at the task's
commit, and must fail again when the task's change to the code it tests is
reverted.

Keep rule: all four tasks' tests pass that check. If any fails, the §4
commits are reverted and the note records the contract that failed.

## Acceptance

A1. [test, high] plan-lint reports an ERROR naming the task and path when a task's `- Modify:` or `- Test:` path does not exist in the checkout and no lower-numbered task's `- Create:` line names it.
A2. [test, neg, high] plan-lint reports no path error for a Modify or Test path created by a lower-numbered task, for any `- Create:` path, or for any `- Delete:` path.
A3. [test, high] plan-lint reports an ERROR when a Modify or Test range on an existing file has a start below 1, a start above its end, or an end beyond the file's line count, and none for a valid range.
A4. [test, neg, high] plan-amend accepts an amendment to a plan whose path or range errors were already there before the amendment.
A5. [test, high] `lens-route --final` prints exactly one `lens code-quality` line, whose `parts=` lists every part whose `Applies:` line matches the change set, in the order lang-* alphabetical, type-design, docs-comments, and prints no lens line for a part id.
A6. [test, high] At standard depth, with security, silent-failures, test-quality and at least one part applying, `lens-route --final` prints lens lines for all four and skips none for the cap at the default `lensCap`.
A7. [test, high] With `lensCap` unset, lens-route and `dforge-config` use 5.
A8. [test, neg, high] At light depth, code-quality prints `lens-skipped code-quality reason=depth` and no lens line.
A9. [test, neg, high] When no part applies, `lens-route --final` prints no code-quality line, lens or skipped.
A10. [test, medium] `lens-route --task` with `**Lenses:** code-quality` lists the parts whose paths clause matches the task's Files paths, and every part when none matches. Q: when no part matches a risk-3 task's files, should the lens list every part, or should plan-lint reject the line?
A11. [test, neg, high] plan-lint rejects a part id (`lang-bash`) on a `**Lenses:**` line as an unknown lens id.
A12. [test, high] `task-step` has no `--covered` option (a usage error), and a fix round of one finding in three or fewer lines on a risk-3 task still requires its re-review.
A13. [test, neg, high] `scripts/review-record` reads a Claude final report whose findings carry indented `Evidence:` lines with the same counts as without them.
A14. [demo, high] The Claude final review, lens and plan-review prompts require an `Evidence:` line per finding, report no style findings, and read diff-first with narrow searches; code-reviewer.md's Minor definition no longer names code style.
A15. [demo, high] The final-review fix wave reproduces each finding before fixing it and records an unreproduced one as `REJECTED: not reproduced — <what was tried>`.
A16. [demo, medium] The M1 note records the six runs and the keep rule's result, and the §3 change stays only if the rule held. Q: is "confirmed Critical+Important not fewer, and tokens or unconfirmed share lower, across three branches" the right keep rule?
A17. [demo, high] A Claude plan's Step 1 carries test contracts, not test code; a `Host: codex` plan still carries complete code; plan-review.md's Executability judges the contracts.
A18. [demo, medium] The M2 note records four tasks whose contract-written tests fail at base, pass at the task's commit and fail when the change is reverted, and the §4 change stays only if all four did. Q: are four tasks from two plans enough to keep the lean form?
A19. [demo, high] No dforge file says that a task's implementer sees only its task's text, or that small models execute the plan literally.
A20. [test, neg, high] `lens-route` still exits 2 on a `Host: codex` plan, and `native-codex.md` tells a Codex host how to pick code-quality parts by hand.

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
- Review JSON schemas and the external Codex and agy criteria.
- A pre-check before the final review beyond the existing ci-mirror, gates
  and ui-proof steps.
