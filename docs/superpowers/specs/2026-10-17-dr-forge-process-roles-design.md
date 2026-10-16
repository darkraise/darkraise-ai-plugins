# dr-forge process roles: analyst, architect critic, QA and review lenses

**Execution strategy:** sequential — the four items share `skills/brainstorming/SKILL.md` and `reference/final-review.md`.
**Approach:** best-of-3 — QA writes tests first (A) vs QA tests the built branch black-box (B) vs QA audits the plan's tests (C); B won 2–0, grafts below.
**Register:** `docs/superpowers/registers/2026-10-17-process-roles.md`

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

All paths below are relative to `plugins/dr-forge/` unless they start with `docs/`.

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

| Role | Brief | Seat (Claude) |
|---|---|---|
| Architecture critic | `criteria/architecture-critique.md` | `dr-forge:judge-opus` |
| QA | `reference/acceptance-qa.md` | `dr-forge:impl-sonnet-high` |
| Review lens, final review | `criteria/lenses/<id>.md` | `dr-forge:judge-sonnet-high` |
| Review lens, risk-3 task | the same file, appended to the task's Claude review seat | the seat `scripts/review-route --task` names (`judge-opus` at risk 3) |
| Analyst | brainstorming's Acceptance step | the human, through the multiple-choice prompt |

On a Codex host each seat takes the native seat `reference/native-codex.md`
maps its Claude seat to; that file gains one line per new role. All four
items apply to architectural-path specs and plans only.

Release: dr-forge 3.1.0 in both `.claude-plugin/plugin.json` and
`.codex-plugin/plugin.json`.

## 2. Acceptance statements and analyst verdicts (item 4)

### Statement format

Each statement in a spec's `## Acceptance` section is one line:

```
A<n>. [<test|demo>[, neg], <high|confirmed>] <Given/When/Then or checklist item>
```

- `A<n>` numbers are stable: a deferred or deleted statement's number is never
  reused, and the gap carries a one-line note naming its register row.
- `test` means an automated test can check it; `demo` means only a person
  observing the result can (visual output, interactive UI).
- `neg` marks a statement about what must not happen. At least one statement
  carries it.
- `high` is the author's rating when the statement follows directly from what
  the human said or from code read in this session. `confirmed` means the human
  ruled it Right. Nothing else may appear in a written spec.

### Drafting and the verdict step

In brainstorming's architectural checklist, a new step **Draft acceptance**
sits after the last design section is approved and before the auto-run offer:

1. Draft every statement and rate it `high`, `medium` or `low`. Each `medium`
   or `low` statement also gets the exact question that would settle it.
2. Show the full list in chat. Then ask about each statement rated below `high`
   with the multiple-choice prompt, at most four per call. Each question shows
   the statement, why it is uncertain and the settling question, and offers
   **Right**, **Wrong, or not wanted**, and **Not sure**. A typed note is kept
   verbatim.
3. Act on each verdict:
   - **Right**: the statement becomes `confirmed`.
   - **Wrong**: rewrite it from the note and ask once more. A second **Wrong**
     or **Not sure** defers it.
   - **Not sure**: remove it from the spec and add it to the register as
     `scripts/register add <register> "A<n>: <statement>" --state deferred --note "Q: <question>"`.
     When no register is open, open `docs/superpowers/registers/<date>-<spec-slug>.md` first.
     Planning never builds on a deferred statement.

The step asks nothing when every statement is `high`.

### Checks

- Brainstorming's spec self-review item 6 (**Acceptance**) and the spec
  reviewer prompt (`skills/brainstorming/references/spec-document-reviewer-prompt.md`)
  also check:
  - every statement matches the line format;
  - at least one statement carries `neg`;
  - no rating other than `high` or `confirmed` appears.
- `skills/writing-plans/SKILL.md` gains a rule: a task's `**Items:**` line
  never names a register row whose Note starts with `Q:` while that row is
  deferred.

## 3. Architecture critic (item 1)

`criteria/architecture-critique.md` is a criteria file in the existing format
(ground-truth note, two to four criteria with stable ids):

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

Output: findings ranked **Blocker / High / Medium / Nit**, each with what,
where in the spec, why it matters, and a suggested change. The output ends
with one sentence: "If I could change one thing, it would be …".

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
(gates) and before step 1 (Claude review). Both `subagent-driven-development`
and `executing-plans` reach it through `final-review.md`. It is skipped, with
one line saying so, when:

- the plan's spec has no `test` statement; or
- the ledger already holds `Acceptance QA: complete`, as when resuming after a
  compaction or a clear.

### Who and with what

Dispatch `dr-forge:impl-sonnet-high` with `reference/acceptance-qa.md`, the
spec path, the list of `test` statements, `MERGE_BASE`, `HEAD`, and the test
command from `gates.md` when one is declared.

The brief forbids reading the plan, the ledger, the task reports and the
review package. Independence from the plan writer is the point of this seat.

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
   - Create a throwaway worktree under the plan's workspace.
   - Make one minimal break to the behaviour the statement guards.
   - Run that statement's test and expect it to fail.
   - Remove the worktree, then confirm with `git worktree list` and
     `git status` that the main worktree is unchanged.
   - A test that stays green is a finding: "A<n> test does not detect a
     violation".
5. **Commit and report.** Commit the test files and fixtures only. Write
   `<workspace>/acceptance-report.md` with columns `Statement | Test | Result |
   Mutation`:
   - Result is `pass`, `fail`, `flaky`, `cannot-test: ambiguous` or
     `cannot-test: no-surface`.
   - Mutation is `red`, `green` or `n/a`.
   - `demo` statements are listed as `demo — not executed`.

### Results

The session reads the report and acts on each result:

- **fail, flaky, or mutation green**: a finding in the final fix wave. The
  fixer must not weaken an acceptance test. To dispute one, it records
  `REJECTED: A<n> — <evidence>`, and the existing scoped re-review decides.
- **cannot-test: no-surface**: a finding. The spec promised behaviour that
  has no observable surface.
- **cannot-test: ambiguous**:
  - attended: one ruling-seat dispatch, which ends AMEND (re-dispatch QA for
    that statement only) or PARK (defer it to the register);
  - auto run: see section 6.

QA is re-dispatched at most once per final review.

The ledger then gets
`Acceptance QA: complete — <p> pass, <f> fail, <c> cannot-test, <d> demo`.

### Review and evidence

- The QA commit lands before `scripts/review-package` runs, so the acceptance
  file is in the package. The reviewer template
  (`skills/requesting-code-review/references/code-reviewer.md`) gains one
  question: for each `A<n>:` test, would it fail if the code violated A<n>?
- The fix wave's verification runs the acceptance file again.
- `closing-a-milestone`'s judge takes `acceptance-report.md` rows and `A<n>:`
  test results as evidence.
- Register Notes are left alone, so statement ids and row ids stay in
  separate spaces.
- The finishing message lists every `demo — not executed` statement, so a
  person knows what to look at.

## 5. Specialist review lenses (item 3)

### Lens files

`criteria/lenses/<id>.md` uses the criteria format plus one header line,
`Applies:`. Each lens holds known defect patterns only, never general style
advice. The initial set:

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

`Applies:` grammar is one or more space-separated clauses joined by ` | `:

- `always`
- `paths <glob>…` (matched against the change set's file names)
- `added <ERE>` (matched against added diff lines)

A lens applies when any clause matches. The exact patterns are settled in the
plan and pinned by tests.

### Selection: `scripts/lens-route`

```
lens-route PLAN_FILE --final BASE HEAD
lens-route PLAN_FILE --task ID
```

- **`--final`**: evaluates every lens's `Applies:` against
  `git diff BASE...HEAD`.
  - It prints `lens <id> criteria=<path> seat=dr-forge:judge-sonnet-high reason=<clause>`
    for each applicable lens. Lenses come in fixed priority order: security,
    silent-failures, test-quality, the lang-* lenses alphabetically,
    type-design, docs-comments.
  - It stops at the cap, then prints `lens-skipped <id> reason=cap` for each
    remaining applicable lens.
  - The cap is the forge setting `lensCap` (default 4; 0 turns final-review
    lenses off).
- **`--task ID`**: prints `lens <id> criteria=<path>` for each id on the task's
  `**Lenses:**` line, uncapped.
- Exit codes: 0 when routed (including when no lens applies); 2 on usage
  error, a missing plan or task, or an unknown lens id.

### Final review

In step 1, the session dispatches the lens seats in the same message as the
Claude review, so they run in parallel. Each lens gets the package path, its
criteria file and the spec and plan paths. Lens findings join the Claude list,
each tagged `[lens:<id>]`. Steps 2–4 are unchanged: the Codex round, the
two-list dedupe and verification, and the report all stay as they are. The
report names each lens skipped by the cap.

### Risk-3 tasks

- **Writing the plan.** In `skills/writing-plans/SKILL.md`, a task scored risk 3
  may carry `**Lenses:** <id>[, <id>]`, naming the lenses that match why it is
  risky. A task whose risk is security carries `security`.
- **Linting.** `scripts/plan-lint` rejects a `**Lenses:**` line on a task below
  risk 3, and an id with no file in `criteria/lenses/`.
- **Reviewing the task.** `skills/subagent-driven-development/SKILL.md`
  appends the `lens-route --task` criteria files to the dispatch of that
  task's Claude review seat. This adds no dispatch.

### Outside plans

- `skills/requesting-code-review/SKILL.md`: when a change touches
  authentication, secrets, input parsing or shell construction, append
  `criteria/lenses/security.md` to the reviewer dispatch.
- `skills/running-gates/references/gates-template.md`: add a commented example
  gate that runs the official `claude-security` plugin's branch scan, for
  projects that install it.

## 6. Auto run

The auto run asks nothing after `scripts/auto-run start`, bounds every loop,
and resumes from ledger lines. Each role keeps those properties:

| Role | Where in the run | Bound | When nothing can decide |
|---|---|---|---|
| Analyst verdicts | Before `auto-run start`, attended | One pass, plus one re-ask per Wrong | n/a: the human is present |
| Statement added or changed while writing the spec | Spec phase | Ruling ladder | Fable no ruling: the statement is **deferred**, not guessed (an exception to "take the first option", because a guessed requirement is what item 4 exists to stop) |
| Architecture critic | After self-review, before the Fable spec review | One dispatch | The session answers Blocker/High in `## Critic findings`; Fable's existing review (at most two rounds) checks those answers; no extra round |
| QA | Phase `final`, after gates | One dispatch, plus at most one re-dispatch; ledger marker for resume | `ambiguous` goes up the ladder (Opus, then the Fable batch); no ruling: the statement is deferred with a register row and the run continues |
| Lenses at final review | Phase `final`, parallel with the Claude review | `lensCap` dispatches | Findings enter the single fix wave like any other |
| Lenses on risk-3 tasks | Phase `execute` | No added dispatch | Existing task-review flow |

Rules the auto run must also keep:

- **Nothing left running.** QA removes its mutation worktree before
  returning, and the session confirms `git worktree list` holds no QA
  worktree. Every test run has a timeout, so the Stop hook never finds a
  background process.
- **Compaction and clears.** Step 0.5 is skipped once the ledger has
  `Acceptance QA: complete`. Lens dispatches are part of step 1, which the
  final review's existing recovery already re-runs.
- **Budget.**
  - The new seats are subagents, so the main session pays only for their
    reports: the QA report is a file the session reads by summary, and the
    lens findings are lists.
  - Added calls per architectural plan: one Opus (critic), one Sonnet
    implementer (QA, plus at most one re-dispatch) and up to `lensCap` Sonnet
    judges.
  - The budget line's verdicts are unchanged.
- **Finishing message.** In addition to what it lists today, it names:
  - deferred acceptance statements;
  - `demo — not executed` statements;
  - lenses skipped by the cap.
- **`reference/auto-run.md`** gains these rows in its Rulings and The spec
  sections. **`tests/auto-run-skills.test.sh`** pins them.

## 7. Files

| File | Change |
|---|---|
| `skills/brainstorming/SKILL.md` | Draft acceptance step, statement format, critic dispatch, self-review items |
| `skills/brainstorming/references/spec-document-reviewer-prompt.md` | Format, `neg`, ratings and critic-answer checks |
| `criteria/architecture-critique.md` | New |
| `reference/acceptance-qa.md` | New |
| `criteria/lenses/*.md` | New, nine files |
| `scripts/lens-route` | New |
| `scripts/forge-config` (and its settings docs) | `lensCap` setting |
| `scripts/plan-lint` | `**Lenses:**` checks |
| `reference/final-review.md` | Step 0.5; lens dispatch in step 1; report lines |
| `skills/subagent-driven-development/SKILL.md` | Risk-3 lens append; step 0.5 pointer |
| `skills/executing-plans/SKILL.md` | Step 0.5 pointer |
| `skills/writing-plans/SKILL.md` | `**Lenses:**` line; deferred-`Q:` row rule |
| `skills/requesting-code-review/SKILL.md`, `references/code-reviewer.md` | Security lens outside plans; the `A<n>:` question |
| `skills/closing-a-milestone/references/milestone-judge.md` | Acceptance report as evidence |
| `skills/finishing-a-development-branch/SKILL.md` | Demo and deferred statements in the finish message |
| `skills/running-gates/references/gates-template.md` | `claude-security` example gate |
| `reference/auto-run.md` | Section 6 rows |
| `reference/native-codex.md` | Seat lines for the critic, QA and lenses |
| `tests/criteria.test.sh` | Also validates `criteria/lenses/*.md` and `Applies:` |
| `tests/lens-route.test.sh`, `tests/plan-lint.test.sh`, `tests/auto-run-skills.test.sh` | New or extended |
| `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` | 3.1.0 |

## Acceptance

A1. [test, high] Given a change set touching only `scripts/foo.sh`, when `scripts/lens-route PLAN --final BASE HEAD` runs, then it prints `lens security` and `lens lang-bash` lines and no `lang-csharp`, `lang-python` or `lang-typescript` line.
A2. [test, high] Given more applicable lenses than `lensCap`, `lens-route --final` prints exactly `lensCap` `lens` lines in the priority order, then one `lens-skipped <id> reason=cap` per remaining applicable lens.
A3. [test, neg, high] `lens-route --final` never prints a `lens` line for a lens whose every `Applies:` clause fails to match the change set.
A4. [test, high] `lens-route --task` on a task without a `**Lenses:**` line prints nothing and exits 0; with an unknown id it exits 2.
A5. [test, high] `scripts/plan-lint` reports an error for a `**Lenses:**` line on a task scored below risk 3, and for an id with no file in `criteria/lenses/`.
A6. [test, high] `tests/criteria.test.sh` validates `criteria/architecture-critique.md` and every `criteria/lenses/*.md`: ground-truth note, two to four criteria with ids and, for lenses, one `Applies:` line that parses.
A7. [test, high] `skills/brainstorming/SKILL.md` places the Draft acceptance step after the last design section and before the auto-run offer, and states the statement line format, `neg`, and the `high|confirmed` rule.
A8. [test, neg, high] No step added by this design asks the human after `scripts/auto-run start`: `reference/auto-run.md` names the ruling ladder or deferral for the spec-phase statement change, the critic and QA `ambiguous` results, and the auto-run test pins those lines.
A9. [test, high] `reference/final-review.md` orders gates, then Acceptance QA, then the Claude review with the lens dispatches, and says step 0.5 is skipped when the ledger holds `Acceptance QA: complete`.
A10. [demo, high] Given a merged branch of this repository and a spec statement it satisfies, when a defect violating that statement is seeded and `reference/acceptance-qa.md` is run on `impl-sonnet-high`, then its `A<n>:` test fails and the report records `fail`; on the unseeded branch it records `pass`.
A11. [test, high] Both dr-forge manifests read 3.1.0, and `node scripts/validate-repository.mjs` passes.

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
