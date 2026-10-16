# dr-forge process roles: analyst, architect critic, QA and review lenses

**Execution strategy:** sequential — the four items share `skills/brainstorming/SKILL.md`, `reference/final-review.md` and the execution skills' ledger grammar.
**Approach:** best-of-3 — QA writes tests first (A) vs QA tests the built branch black-box (B) vs QA audits the plan's tests (C); B won 2–0, grafts below.
**Register:** `docs/superpowers/registers/2026-10-17-process-roles.md`
**Reviewed:** Fable, round 1 (revise) — every finding applied; see the review notes at the end.

## Goal

Add four roles that the official plugins (`code-modernization`, `feature-dev`,
`pr-review-toolkit`) have and dr-forge lacks, without new agent types and
without weakening the auto run:

1. **Architecture critic** — an adversarial review of an architectural spec's design.
2. **QA** — a seat other than the plan writer turns the spec's acceptance
   statements into executable tests.
3. **Specialist review lenses** — security, silent failures, test quality, type
   design, docs and comments, and per-language defect patterns, each run only
   when the change set calls for it.
4. **Business analyst discipline** — every acceptance statement carries a
   confidence rating, and the human rules on the uncertain ones.

Paths are relative to `plugins/dr-forge/` unless they start with `docs/` or
`<docs>/`. `<docs>` is the forge docs root the skills already use.

## Non-goals

- No developer or implementer per language. Models already write idiomatic
  code; project conventions belong in `CLAUDE.md`/`AGENTS.md` and `gates.md`.
  Language knowledge enters only as review lenses (owner ruling, 2026-10-17).
- No new agent files. Every role is a brief dispatched onto a seat that exists.
- No lens on every task review: per-task lenses run only on risk-3 tasks.
- No change to the bounded or spike paths, apart from the optional security lens
  in `requesting-code-review`.
- No integration with the official `claude-security` plugin beyond a
  documented example gate.

## 1. Shared shape

| Role | Brief | Seat on Claude | Seat on Codex |
|---|---|---|---|
| Architecture critic | `skills/brainstorming/references/architecture-critic-prompt.md` with `criteria/architecture-critique.md` | `dr-forge:judge-opus` | native judge, rank 8 or above |
| QA | `reference/acceptance-qa.md` | `dr-forge:impl-sonnet-high` | native implementer `gpt-6.1-sol / high` (the `impl-sonnet-high` row) |
| Review lens, final review | `criteria/lenses/<id>.md` | `dr-forge:judge-sonnet-high` | native judge, rank 8 or above |
| Review lens, risk-3 task | the same file, appended to the task's Claude review dispatch | the seat `scripts/review-route --task` names | native task judge |
| Analyst | brainstorming's Draft acceptance step | the human, through the multiple-choice prompt | the same |

`reference/native-codex.md` has no seat map. It gains one line per role
stating the Codex column above, dispatched under its §Dispatch and review.

All four items apply to architectural-path specs and plans only. The one
exception is the security lens in `requesting-code-review` (section 5).

Release: dr-forge 3.1.0 in both `.claude-plugin/plugin.json` and
`.codex-plugin/plugin.json`.

## 2. Acceptance statements and analyst verdicts (item 4)

### Statement format

Each statement in a spec's `## Acceptance` section is one line:

```
A<n>. [<test|demo>[, neg], <high|confirmed>] <Given/When/Then or checklist item>
```

- **Stable numbers.** `A<n>` numbers are never reused. A deferred or deleted
  statement leaves a gap line, `A<n>. deferred — register row <id>`.
- **`test` or `demo`.** `test` means an automated test can check the statement.
  `demo` means only a person observing the result can, as with visual output
  or an interactive UI.
- **`neg`.** Marks a statement about what must not happen. At least one
  statement carries it.
- **Ratings in a written spec:**
  - `high`: the statement follows directly from what the human said, from code
    read in this session, or from a recorded seat ruling.
  - `confirmed`: the human ruled it Right. This rating is reserved for the
    human.
  - No other rating appears in a written spec.

### Drafting and the verdict step

In brainstorming's architectural checklist, a new step **Draft acceptance**
sits between step 6 (present the design) and step 7 (offer an auto run):

1. Draft every statement and rate it `high`, `medium` or `low`. Each `medium`
   or `low` statement also gets the exact question that would settle it.
2. Show the full list in chat. Then ask about each statement rated below `high`
   with the multiple-choice prompt, at most four per call. Each question shows
   the statement, why it is uncertain and the settling question. The options
   are **Right**, **Wrong, or not wanted** and **Not sure**. A typed note is
   kept verbatim.
3. Act on each verdict:
   - **Right**: the statement becomes `confirmed`.
   - **Wrong**: rewrite the statement from the note and ask once more. A
     second **Wrong** or **Not sure** defers it.
   - **Not sure**: defer the statement.

   To defer a statement, add it to the register as
   `scripts/register add <register> "A<n>: <statement>" --state deferred --note "Q: <question>"`.
   When no register is open, open `<docs>/registers/<date>-<spec-slug>.md`
   first. Its `**Covers:**` stays `-` until step 8 writes the spec. Register
   rows whose Item begins with `A<n>:` are deferred acceptance statements
   wherever this design refers to them.

The step asks nothing when every statement is `high`.

**Statements added later.**
- *Attended:* a statement added or changed while writing the spec, and rated
  below `high`, is asked with the same prompt before the spec is committed.
- *In an auto run:* it goes up the ruling ladder instead (section 6). A
  statement a seat rules on stays `high`, and the ruling is recorded with
  `scripts/auto-run ruling add`.

### Checks

- **Spec checks.** Brainstorming's spec self-review item 6 (**Acceptance**)
  and the spec reviewer prompt
  (`skills/brainstorming/references/spec-document-reviewer-prompt.md`) also
  check that:
  - every statement matches the line format;
  - at least one statement carries `neg`;
  - no rating other than `high` or `confirmed` appears.
- **Plan rule.** `skills/writing-plans/SKILL.md` gains a rule: a task's
  `**Items:**` line never names a deferred `A<n>:` row.

## 3. Architecture critic (item 1)

`criteria/architecture-critique.md` is a criteria file in the existing format.
It has a ground-truth note and four criteria with stable ids, in ASCII only:

- `{#simplest}` **Simplest sufficient design:** is a simpler design available
  that meets the stated requirements? Are there abstractions with one use, or
  boundaries that match no real seam?
- `{#unstated}` **Unstated requirements:** which non-functional requirements
  (latency, throughput, consistency, compatibility, cost) does the design
  depend on without stating them, and does it violate any of them?
- `{#failure}` **Failure and change paths:** trace one failure end to end, and
  describe the migration or rollback story. "We'll figure it out" is a finding.
- `{#operability}` **Operability:** what would the person debugging this in
  production need that the design does not give them?

**The prompt template.** `skills/brainstorming/references/architecture-critic-prompt.md`
tells the judge to use the criteria as review lenses, not to score them 1-20.
It asks for findings ranked **Blocker / High / Medium / Nit**, each with what,
where in the spec, why it matters, and a suggested change. The output ends
with one sentence: "If I could change one thing, it would be ...".

**When it runs.** On the architectural path, after the spec self-review round
and before the human or Fable reviews the spec. It runs once per spec, and a
revision does not trigger a second critic round. The dispatch gives the critic
the spec path, the approved design sections and the repository.

**What the spec must do with findings.**
- Each Blocker and High finding is either fixed in the spec or answered in a
  new `## Critic findings` section with the reason it stands.
- Medium and Nit findings are listed in that section and need no answer.
- The spec-review request to the human states the counts, for example
  "Critic: 0 Blocker, 2 High (1 fixed, 1 answered), 3 Medium".
- The spec reviewer prompt checks that no Blocker or High finding is left
  without a fix or an answer.

## 4. QA acceptance tests (item 2)

### When

`reference/final-review.md` gains **step 0.5, Acceptance QA**, after step 0
(gates) and before step 1 (Claude review).

- The `scripts/review-package` line moves below step 0.5, so the package
  includes the QA commit.
- Both `subagent-driven-development` and `executing-plans` reach step 0.5
  through `final-review.md`.
- It is skipped, with one line saying so, when the plan's spec has no `test`
  statement.

### Ledger lines and recovery

Two ledger lines, modelled on the existing `Final fix:` pair:

```
Acceptance QA: dispatched (base <sha7>)
Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo
```

- **Before and after.** `dispatched` is written before the dispatch, and
  `complete` after the session has read the report.
- **On recovery, after a compaction or a clear:**
  - **`complete` present:** skip step 0.5.
  - **`dispatched` without `complete`, report present:** if
    `<workspace>/acceptance-report.md` exists, read it and write the
    `complete` line.
  - **`dispatched` without `complete`, no report:** re-dispatch once, telling
    the brief that the acceptance file may already exist and is to be re-run,
    not rewritten. That dispatch counts as the one re-dispatch.
- **Where the grammar lives.** Both lines join the ledger grammar blocks of
  `skills/subagent-driven-development/SKILL.md` and
  `skills/executing-plans/SKILL.md`.
- **Parsers.** Existing parsers key on `^Task N:`, `^Group`,
  `^Final review: clean` and `Ruling:`, so neither line disturbs them.

### Who and with what

- **Seat.** Dispatch `dr-forge:impl-sonnet-high` with
  `reference/acceptance-qa.md`.
- **What it receives.** The spec path, the list of `test` statements,
  `MERGE_BASE`, `HEAD`, and the test command from `gates.md` when one is
  declared.
- **What it may not read.** The plan, the ledger, the task reports and the
  review package. Independence from the plan writer is the point of this seat.
- **Time limit.** The dispatch runs under the implementer rung's wall-clock
  bound. On timeout the session stops the agent and records
  `cannot-test: timeout` for every statement it did not report.

### The brief's procedure

1. **Expectations first.** For each statement, write its expected outcome from
   the spec text alone, as literal values in the test, before reading any
   implementation beyond the public surface (CLI, HTTP routes, exported API,
   files written, `--help`).
2. **Where tests live.** Put the tests in the project's existing test layout,
   in one file named `<spec-slug>.acceptance.<ext>`, or the nearest name the
   framework accepts. Each test name starts with `A<n>:`. Where a test name
   cannot carry a colon, use `a<n>_<words>`.
3. **Run, with a timeout.** Run the file. A setup or import error is the seat's
   own bug, which it fixes. An assertion failure is a finding, which it never
   fixes. A failing test is re-run once, and if the two runs disagree it is
   recorded as `flaky`.
4. **Mutation check on every `neg` statement.**
   - Create the worktree with `git worktree add --detach <workspace>/qa-mutation HEAD`.
   - Run the plan's `**Worktree setup:**` line when it has one; otherwise
     symlink the dependency directories (for example `node_modules`, a
     virtualenv) from the main worktree.
   - Make one minimal break to the behaviour the statement guards.
   - Run that statement's test and expect it to fail.
   - Remove the worktree, then confirm with `git worktree list` and
     `git status` that the main worktree is unchanged.
   - A test that stays green is a finding: "A<n> test does not detect a
     violation".
5. **Commit and report.** Commit the test files and fixtures only. Write
   `<workspace>/acceptance-report.md` with columns `Statement | Test | Result |
   Mutation`:
   - Result is `pass`, `fail`, `flaky`, `cannot-test: ambiguous`,
     `cannot-test: no-surface` or `cannot-test: timeout`.
   - Mutation is `red`, `green` or `n/a`.
   - `demo` statements are listed as `demo — not executed`.

**Cleanup after the dispatch.** When QA returns, the session checks
`git worktree list`. A QA worktree still listed is removed with
`git worktree remove --force` and `git worktree prune`, and the removal is
logged as a `Ruling:` line. The worktree holds nothing but the throwaway
break.

### Results

The session reads the report and acts on each result:

- **`fail`, `flaky`, or mutation `green`.** A finding in the final fix wave.
  The fixer must not weaken an acceptance test. To dispute one, it records
  `REJECTED: A<n> — <evidence>`, and the existing scoped re-review decides.
  The re-review prompt (`skills/subagent-driven-development/references/re-review-prompt.md`)
  gains the question: would this acceptance test fail if the code violated
  A<n>?
- **A residual failure.** This is a `fail` or `flaky` that survives the fix
  wave (the rejection is upheld, or the ruling seat parks it). It is the one
  edit allowed on an acceptance test:
  - the session marks the test skipped, with a reason naming its register row;
  - it commits that change;
  - it adds the statement with
    `scripts/register add <register> "A<n>: <statement>" --state deferred --note "<the upheld rejection>"`.

  Finishing's test run is then green. A `fail` that the fix wave fixed stays
  as written.
- **`cannot-test: no-surface`.** A finding: the spec promised behaviour that
  has no observable surface.
- **`cannot-test: ambiguous`.** Goes to the ruling seat as the new kind
  `acceptance-ambiguous`. It is added to `scripts/review-route --ruling` and
  the ruling prompt (`references/ruling-prompt.md`), and pinned in
  `tests/review-route.test.sh`. The seat returns one of two verdicts:
  - `REWORD <new statement>`: the session edits the spec's statement,
    commits it, and re-dispatches QA for that statement;
  - `PARK`: the statement is deferred to the register.

  All ambiguous statements in one report share the single re-dispatch.
  Section 6 covers what an auto run does when the seat gives no ruling.

QA is re-dispatched at most once per final review, and the recovery
re-dispatch counts toward that.

### Review and evidence

- **Reviewer question.** The reviewer template
  (`skills/requesting-code-review/references/code-reviewer.md`) gains one
  question: for each `A<n>:` test, would it fail if the code violated A<n>?
- **Fix-wave verification.** The fix wave's verification runs the acceptance
  file again.
- **Durable evidence.** The committed `A<n>:` tests are the durable evidence.
  `closing-a-milestone`'s judge looks for them by statement id.
- **The report is not evidence.** `acceptance-report.md` lives in the
  workspace, which finishing deletes, so it is never cited as milestone
  evidence.
- **Separate id spaces.** Register Notes do not carry statement-to-test
  mappings, so statement ids and row ids stay apart.

## 5. Specialist review lenses (item 3)

### Lens files

Each lens is a file `criteria/lenses/<id>.md` in the criteria format, ASCII
only, plus one header line, `Applies:`. A lens holds known defect patterns
only, never general style advice. The initial set:

| Id | Looks for | Applies (draft) |
|---|---|---|
| `security` | injection, authn/authz gaps, secrets, unsafe deserialization, path traversal, unsafe shell | `always` |
| `silent-failures` | swallowed errors, empty catch, fallbacks that hide failure, ignored exit codes | `added` lines matching catch/except/rescue, `\|\| true`, `2>/dev/null`, `?? `, `fallback` |
| `test-quality` | tests that pass against a stub, assert nothing, or pin implementation | `paths` matching test files |
| `type-design` | invariants not expressed in types, leaky encapsulation | `added` type, interface, class, struct, record or enum declarations in typed languages |
| `docs-comments` | comments or docs contradicting the code, comment rot | `paths` `*.md`, or `added` comment lines |
| `lang-typescript` | TS/JS defect patterns (floating promises, `==`, `any` leaks, ESM/CJS mixups) | `paths` `*.ts *.tsx *.js *.mjs *.cjs` |
| `lang-csharp` | `async void`, sync-over-async, `IDisposable` leaks, captured loop variables | `paths` `*.cs` |
| `lang-bash` | unquoted expansions, missing `set -u`/`pipefail` handling, `cd` without check, word splitting | `paths` `*.sh`, or a bash shebang in an added file |
| `lang-python` | mutable default arguments, bare `except`, late-binding closures | `paths` `*.py` |

**`Applies:` grammar.** The line holds one or more clauses separated by
` ; `:

- `always`
- `paths <glob> ...`: each glob is matched with bash `case` against the
  repository-relative path, so `*` crosses `/` and `*.sh` matches
  `scripts/x.sh`.
- `added <ERE>`: matched against the added lines of the diff.

A lens applies when any clause matches. The exact patterns are settled in the
plan and pinned by tests.

### Selection: `scripts/lens-route`

```
lens-route PLAN_FILE --final BASE HEAD
lens-route PLAN_FILE --task ID
```

**`--final`** evaluates every lens's `Applies:` against `git diff BASE..HEAD`,
with BASE being the merge base, as in `review-package`. Its output:

- `lens <id> criteria=<path> seat=dr-forge:judge-sonnet-high reason=<clause>`
  for each applicable lens, in a fixed priority order: security,
  silent-failures, test-quality, the lang-* lenses alphabetically,
  type-design, docs-comments.
- Once the cap is reached, `lens-skipped <id> reason=cap` for each remaining
  applicable lens.

**The cap.** The cap is the forge setting `lensCap`:

| Property | Value |
|---|---|
| Default | 4 |
| Range | 0 to 9 |
| Environment override | `DR_FORGE_LENS_CAP` |
| Enforced by | script |
| Settings group | Workflow |

When `lensCap` is 0, final-review lenses are off. `lens-route --final` then
prints a single line, `lenses off`, and the final report says so.

**`--task ID`** prints `lens <id> criteria=<path>` for each id on the task's
`**Lenses:**` line, with no cap applied.

**Exit codes.**
- 0: routed, including when no lens applies.
- 2: a usage error, a missing plan or task, an unknown lens id, or a plan
  whose header reads `Host: codex`, as `review-route` does.

### Final review

- **Dispatch.** In step 1, the session dispatches the lens seats in the same
  message as the Claude review, so they run in parallel. Each lens gets the
  package path, its criteria file and the spec and plan paths.
- **Findings as files.** Each lens writes `<workspace>/lens-<id>.md` and
  returns one count line. The Claude list is the review report plus those
  files, each finding tagged `[lens:<id>]`, and the dedupe judge and the fixer
  receive the paths.
- **Steps 2 to 4 are unchanged.** The Codex round, the two-list dedupe and
  verification, and the report all stay as they are.
- **Report additions.** The report names each lens skipped by the cap.
- **Recovery.** Lens seats are read-only, so step 1's existing recovery may
  re-dispatch them safely.

### Risk-3 tasks

- **The plan line.** In `skills/writing-plans/SKILL.md`, a task scored risk 3
  may carry `**Lenses:** <id>[, <id>]`, naming the lenses that match why it is
  risky. A task whose risk is security carries `security`.
- **Linting.** `scripts/plan-lint` rejects a `**Lenses:**` line on a task below
  risk 3, and an id with no file in `criteria/lenses/`.
- **Where the review is dispatched.** The task review is dispatched from
  `reference/delegated-task.md` §3 in both execution modes, so that file
  appends the `lens-route --task` criteria files.
- **How the reviewer treats them.** `task-reviewer-prompt.md` gains a
  `[LENS_FILES]` section: "Lens criteria are defect-pattern checks: report each
  hit as a finding tagged `[lens:<id>]` at your own severity; do not score
  them." This adds no dispatch.

### Outside plans

- `skills/requesting-code-review/SKILL.md`: when a change touches
  authentication, secrets, input parsing or shell construction, append
  `criteria/lenses/security.md` to the reviewer dispatch, with the same
  do-not-score instruction.
- `skills/running-gates/references/gates-template.md`: add a commented example
  gate that runs the official `claude-security` plugin's branch scan, for
  projects that install it.

## 6. Auto run

The auto run asks nothing after `scripts/auto-run start`, bounds every loop,
resumes from ledger lines, and keeps the branch for a person when something it
could not verify remains. Each role keeps those properties.

| Role | Where in the run | Bound | When nothing can decide |
|---|---|---|---|
| Analyst verdicts | Before `auto-run start`, attended | One pass, plus one re-ask per Wrong | n/a: the human is present |
| Statement added or changed while writing the spec | Spec phase | Ruling ladder | A seat ruling keeps the statement `high`. If Fable gives no ruling, the statement is **deferred**, not guessed: an exception to "take the first option", because a guessed requirement is what item 4 exists to stop |
| Architecture critic | After self-review, before the Fable spec review | One dispatch | The session answers Blocker and High findings in `## Critic findings`, and Fable's existing review (at most two rounds) checks those answers. A Blocker that Fable leaves undecided is deferred as a register row and recorded as `unresolved — row <id>`. The run continues, and finishing keeps the branch |
| QA | Phase `final`, after gates | One dispatch, plus at most one re-dispatch; the `dispatched`/`complete` ledger pair handles resume; a wall-clock bound | `acceptance-ambiguous` goes to Opus first. If Opus gives no ruling, the Fable batch runs **at once**, as for a blocked task. If Fable gives no ruling either, the statement is parked (deferred with a register row) and the run continues |
| Lenses at final review | Phase `final`, parallel with the Claude review | `lensCap` dispatches; findings as files | The findings enter the single fix wave like any other |
| Lenses on risk-3 tasks | Phase `execute` | No added dispatch | The existing task-review flow |

Rules the auto run must also keep:

- **Nothing left running.**
  - QA removes its mutation worktree before returning, and the session
    removes any QA worktree still listed (section 4).
  - Every test run, and the QA dispatch itself, has a time bound, so the Stop
    hook never finds a background process.
- **Compaction and clears.** The `Acceptance QA:` ledger pair decides whether
  step 0.5 is skipped, completed from the report, or re-dispatched once. Lens
  dispatches are read-only and re-runnable.
- **Budget.**
  - The new seats are subagents, and their output reaches the main session as
    files plus one count line each.
  - Added calls per architectural plan: one Opus (critic), one Sonnet
    implementer (QA, plus at most one re-dispatch), up to `lensCap` Sonnet
    judges, and one ruling per ambiguous batch.
  - The budget line's verdicts are unchanged.
- **Finishing keeps the branch for a person.** `merge` also keeps the branch
  when any of these hold:
  - the `Acceptance QA: complete` line reports any `fail`, `flaky` or
    `cannot-test`;
  - a residual failure was skipped;
  - any `A<n>:` row was deferred during the run;
  - a critic Blocker is `unresolved`.

  This rule goes into `reference/auto-run.md` §Finishing and
  `skills/finishing-a-development-branch/SKILL.md` §Auto run, and is pinned in
  `tests/auto-run-skills.test.sh`. A `pr` finish is unaffected: a person
  reviews it anyway.
- **Finishing message.** In addition to what it lists today, it names:
  - the deferred `A<n>:` rows;
  - the `demo — not executed` statements;
  - the lenses skipped by the cap;
  - any unresolved critic Blocker.
- **`reference/auto-run.md`** gains these rows in its Rulings, The spec and
  Finishing sections, and **`tests/auto-run-skills.test.sh`** pins them.

## 7. Files

| File | Change |
|---|---|
| `skills/brainstorming/SKILL.md` | Draft acceptance step; statement format; critic dispatch; self-review items; statements added later |
| `skills/brainstorming/references/spec-document-reviewer-prompt.md` | Format, `neg`, rating and critic-answer checks |
| `skills/brainstorming/references/architecture-critic-prompt.md` | New |
| `criteria/architecture-critique.md` | New |
| `reference/acceptance-qa.md` | New |
| `criteria/lenses/*.md` | New, nine files |
| `scripts/lens-route` | New |
| `scripts/forge-config` (schema and settings docs) | `lensCap` setting |
| `scripts/plan-lint` | `**Lenses:**` checks |
| `scripts/review-route` | `acceptance-ambiguous` ruling kind |
| `reference/final-review.md` | Package line moved below step 0.5; step 0.5; lens dispatch in step 1; report lines |
| `reference/delegated-task.md` | Risk-3 lens append |
| `skills/subagent-driven-development/SKILL.md` | `Acceptance QA:` ledger lines and recovery; step 0.5 pointer |
| `skills/subagent-driven-development/references/task-reviewer-prompt.md` | `[LENS_FILES]` section |
| `skills/subagent-driven-development/references/re-review-prompt.md` | The `A<n>` question |
| `skills/subagent-driven-development/references/ruling-prompt.md` | `acceptance-ambiguous` with `REWORD` and `PARK` |
| `skills/executing-plans/SKILL.md` | `Acceptance QA:` ledger lines and recovery; step 0.5 pointer |
| `skills/writing-plans/SKILL.md` | `**Lenses:**` line; deferred `A<n>:` row rule |
| `skills/requesting-code-review/SKILL.md`, `references/code-reviewer.md` | Security lens outside plans; the `A<n>` question |
| `skills/closing-a-milestone/references/milestone-judge.md` | `A<n>:` tests as evidence |
| `skills/finishing-a-development-branch/SKILL.md` | Keep-branch conditions; finishing message additions |
| `skills/running-gates/references/gates-template.md` | `claude-security` example gate |
| `reference/auto-run.md` | Section 6 rows in Rulings, The spec and Finishing |
| `reference/native-codex.md` | Seat lines for the critic, QA and lenses |
| `tests/criteria.test.sh` | Also validates `criteria/lenses/*.md`, `Applies:` and the critique file |
| `tests/lens-route.test.sh` (new), `tests/plan-lint.test.sh`, `tests/review-route.test.sh`, `tests/auto-run-skills.test.sh` | New or extended |
| `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` | 3.1.0 |

## Acceptance

A1. [test, high] Given a change set touching only `scripts/foo.sh`, when `scripts/lens-route PLAN --final BASE HEAD` runs, then it prints `lens security` and `lens lang-bash` lines and no `lang-csharp`, `lang-python` or `lang-typescript` line.
A2. [test, high] Given more applicable lenses than `DR_FORGE_LENS_CAP`, `lens-route --final` prints exactly that many `lens` lines in the priority order, then one `lens-skipped <id> reason=cap` per remaining applicable lens; with the cap at 0 it prints only `lenses off`.
A3. [test, neg, high] `lens-route --final` never prints a `lens` line for a lens whose every `Applies:` clause fails to match the change set.
A4. [test, high] `lens-route --task` on a task without a `**Lenses:**` line prints nothing and exits 0; with an unknown id, or on a `Host: codex` plan, it exits 2.
A5. [test, high] `scripts/plan-lint` reports an error for a `**Lenses:**` line on a task scored below risk 3, and for an id with no file in `criteria/lenses/`.
A6. [test, high] `tests/criteria.test.sh` validates `criteria/architecture-critique.md` and every `criteria/lenses/*.md`: ASCII only, ground-truth note, two to four criteria with ids and, for lenses, one `Applies:` line that parses.
A7. [test, high] `skills/brainstorming/SKILL.md` places the Draft acceptance step after the design is presented and before the auto-run offer, and states the statement line format, `neg`, and the `high|confirmed` rule.
A8. [test, neg, high] No step added by this design asks the human after `scripts/auto-run start`: `reference/auto-run.md` names the ruling ladder or deferral for the spec-phase statement change, the critic Blocker and the QA `acceptance-ambiguous` result, and the auto-run test pins those lines.
A9. [test, high] `reference/final-review.md` orders gates, then Acceptance QA, then `review-package`, then the Claude review with the lens dispatches; and both execution skills define the `Acceptance QA: dispatched` and `Acceptance QA: complete` lines and the three recovery cases.
A10. [demo, high] Given a merged branch of this repository and a spec statement it satisfies, when a defect violating that statement is seeded and `reference/acceptance-qa.md` is run on `impl-sonnet-high`, then its `A<n>:` test fails and the report records `fail`; on the unseeded branch it records `pass`.
A11. [test, high] Both dr-forge manifests read 3.1.0, and `node scripts/validate-repository.mjs` passes.
A12. [test, high] `scripts/review-route PLAN --ruling acceptance-ambiguous` routes to the ruling seat and exits 0.
A13. [test, neg, high] `reference/auto-run.md` §Finishing and `finishing-a-development-branch` §Auto run state that `merge` keeps the branch when QA reported `fail`, `flaky` or `cannot-test`, a residual failure was skipped, an `A<n>:` row was deferred during the run, or a critic Blocker is unresolved; the auto-run test pins it.

## Riskiest assumption

A QA seat that reads the built code but not the plan writes acceptance tests
that fail when a statement is violated, instead of tests that mirror what the
code does. The mutation check covers only `neg` statements.

Evidence: unverified. The plan's first task verifies it with the A10 probe on
one merged branch of this repository, before any skill text depends on it. If
the seeded defect goes undetected, the brief's "expectations first" rule is
strengthened, or the mutation check is extended to every `test` statement,
before the rest of the plan runs.

## Grafts recorded from the approach ranking

- From C: the mutation check on `neg` statements, and the reviewer question
  "would this test fail if the code violated A<n>?".
- From A and C: stable statement ids and the `neg` tag.
- From A: in an auto run, `ambiguous` goes up the ruling ladder.
- From C: statement ids stay out of register Notes.
- B's proposed rule against planning end-to-end tests of acceptance statements
  is dropped; it conflicted with the new-user-journey rule in `writing-plans`.

## Review notes (Fable, round 1)

The verdict was revise, and every finding was applied:

- **Blocker, residual acceptance failure.** Handled in section 4, Results.
- **High, the dispatched/complete ledger pair.** Added in section 4.
- **High, keep the branch on unverified acceptance.** Added in section 6.
  Owner confirmation is pending at the spec review.
- **Medium findings:**
  - the `acceptance-ambiguous` kind with `REWORD`/`PARK`, and the immediate
    Fable batch;
  - the rating for a statement a seat ruled on;
  - an unresolved critic Blocker;
  - the Codex seats stated per role;
  - the mutation worktree's `--detach`, dependency setup and cleanup;
  - the risk-3 append in `delegated-task.md` with no scoring;
  - lens findings returned as files;
  - the workspace report dropped as milestone evidence;
  - the review-package order.
- **Nits:**
  - ASCII-only criteria files;
  - `<docs>` paths;
  - glob matching against full paths;
  - `lensCap=0` prints `lenses off`, plus the setting's environment key;
  - the scope exception;
  - the re-review question;
  - the critic prompt template;
  - the shared re-dispatch;
  - `A<n>:` rows defined;
  - `BASE..HEAD`;
  - the attended late-statement prompt;
  - the QA wall-clock bound.
