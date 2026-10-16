# dr-forge Process Roles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the analyst, architecture-critic, QA and specialist-review-lens roles to dr-forge as briefs on existing seats, keeping the auto run unattended, bounded and resumable.

**Architecture:** Each role is a text brief (a criteria file or a reference file) dispatched onto an existing seat. Two small scripts carry the mechanical parts: `scripts/lens-route` selects lenses, and `plan-lint`/`review-route` learn one plan line and one ruling kind. Skill text wires each role into brainstorming, the final review, the ledger and the auto run.

**Tech Stack:** Bash scripts and shell test suites, Markdown skills and references, one Node settings schema entry.

**Spec:** `docs/superpowers/specs/2026-10-17-dr-forge-process-roles-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — 2 of 14 tasks are heavy (Tasks 10 and 12, total 5) and are delegated; the rest are self-implemented at totals of 4 or less

**Plan review:** 2026-10-17 — dr-superpowers:judge-opus — executability 16 / coherence 17 / coverage 17 / assumptions 16 (round 2)

**Parallelism:** sequential — the spec's Execution strategy is sequential: the tasks share brainstorming, final-review and the test file `tests/process-roles.test.sh`

## Global Constraints

- Edit only under `plugins/dr-forge/`, plus this plan's register and the probe note `docs/superpowers/notes/2026-10-17-acceptance-qa-probe.md`. Never edit historical specs or plans.
- Inside `plugins/dr-forge/`, agent names use the `dr-forge:` prefix (for example `dr-forge:impl-sonnet-high`).
- Every file under `plugins/dr-forge/criteria/` is ASCII only: no em dashes, no ellipsis character, no curly quotes.
- Shell scripts start with `#!/usr/bin/env bash` and `set -uo pipefail`, and carry a header comment saying what they do, their usage, output and exit codes, like `scripts/review-route`.
- Run every test suite from the repository root with a timeout: `timeout 600 bash plugins/dr-forge/tests/<name>.test.sh`. Run `unset CLAUDE_CONFIG_DIR` first in the same command.
- Commits use `<type>(<scope>): <subject>` (subject at most 50 characters, imperative, no period), author `Darkraise <quangtc94@gmail.com>`, and no AI attribution of any kind.
- Version: dr-forge 3.1.0 in both `plugins/dr-forge/.claude-plugin/plugin.json` and `plugins/dr-forge/.codex-plugin/plugin.json`.

## Contracts

- **C1 Acceptance statement line.** `A<n>. [<test|demo>[, neg], <high|confirmed>] <statement>`. A deferred statement's line is `A<n>. deferred — register row <id>`. Numbers are never reused. A register row whose Item begins `A<n>:` is a deferred acceptance statement.
- **C2 Lens file.** `plugins/dr-forge/criteria/lenses/<id>.md`, criteria format (`## Ground Truth Note`, `## Criteria`, two to four `### <Title> {#<id>}` headings, ASCII), plus exactly one line `Applies: <clause>[ ; <clause>]...`. Clauses: `always`; `paths <glob> [<glob>...]` (bash `case` patterns against repository-relative paths, `*` crosses `/`); `added <ERE>` (grep -E against added diff lines with the leading `+` removed). The nine ids: `security`, `silent-failures`, `test-quality`, `type-design`, `docs-comments`, `lang-typescript`, `lang-csharp`, `lang-bash`, `lang-python`.
- **C3 `scripts/lens-route`.** `lens-route PLAN_FILE --final BASE HEAD` prints, in priority order (security, silent-failures, test-quality, `lang-*` sorted, type-design, docs-comments, any other lens sorted), `lens <id> criteria=<absolute path> seat=dr-forge:judge-sonnet-high reason=<always|paths:<glob>|added>` for each applicable lens up to the cap, then `lens-skipped <id> reason=cap` for each further applicable lens. With the cap at 0 it prints only `lenses off`. `lens-route PLAN_FILE --task ID` prints `lens <id> criteria=<absolute path>` per id on the task's `**Lenses:**` line, uncapped, and nothing when the task has no such line. Exit 0 when routed (including nothing applicable); exit 2 on a usage error, a missing plan or task, an unknown lens id, or a `Host: codex` plan.
- **C4 Setting.** `lensCap`: number, default 4, range 0 to 9, environment override `DR_FORGE_LENS_CAP`, enforced by script, group Workflow. `lens-route` reads `DR_FORGE_LENS_CAP` first, then `forge_setting lensCap 4`.
- **C5 Plan line.** `**Lenses:** <id>[, <id>]`, only on a task scored risk 3. `plan-lint` errors: `a **Lenses:** line needs risk 3 (risk is <d>)` and `**Lenses:** names no lens file: <id>`.
- **C6 Ruling kind.** `acceptance-ambiguous`; `review-route PLAN --ruling acceptance-ambiguous` prints `review-seat ruling=acceptance-ambiguous tasks=plan primary=dr-forge:judge-opus fallback=- reason=routine`. Its verdicts: `REWORD` with the new statement text on a `New statement:` line, or `PARK`.
- **C7 Ledger lines.** `Acceptance QA: dispatched (base <sha7>)` and `Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo`.
- **C8 QA report.** `<workspace>/acceptance-report.md`, a table `| Statement | Test | Result | Mutation |`. Result is one of `pass`, `fail`, `flaky`, `cannot-test: ambiguous`, `cannot-test: no-surface`, `cannot-test: timeout`, `demo — not executed`. Mutation is `red`, `green` or `n/a`. A last line `Command: <command> → <summary>`.
- **C9 Acceptance tests.** One file `<spec-slug>.acceptance.<ext>` in the project's test layout; each test name starts `A<n>:`, or `a<n>_` where a name cannot hold a colon.
- **C10 QA brief.** `plugins/dr-forge/reference/acceptance-qa.md`, placeholders `[SPEC]`, `[STATEMENTS]`, `[BASE]`, `[HEAD]`, `[TEST_COMMAND]`, `[WORKSPACE]`, `[MODE]` (`first`, `rerun`, or `reword A<n>[, A<m>]`).
- **C11 Prose test suite.** `plugins/dr-forge/tests/process-roles.test.sh`, created by Task 1 with helpers `check <name> <got> <want>` and `names <label> <file> <text>`; later tasks insert their checks immediately above its line `printf '\n%d passed, %d failed\n' "$pass" "$fail"`.
- **C12 Lens reply files.** `<workspace>/lens-<id>.md`, written by the session from each lens seat's reply.

## Assumptions (evidence)

- The register script rejects a register with no `**Covers:**` line: `bash plugins/dr-forge/scripts/register check <file>` printed `ERROR 1: missing **Covers:** line`, `register: 1 errors`, exit 1 (run 2026-10-17); the check is `plugins/dr-forge/scripts/register:53-55`. The Task 2 probe relies on it.
- The riskiest assumption in the spec (a QA seat that has not read the plan writes tests that fail on a violation) is unverified — Task 2 verifies it.
- Criteria files are validated by `tests/criteria.test.sh` for every `criteria/*.md` (ground-truth note, criteria section, 2 to 4 ids, ASCII): `plugins/dr-forge/tests/criteria.test.sh:25-56`. Task 4's critique file is covered by that loop with no test change; Task 5 extends the loop to `criteria/lenses/`.
- Ruling kinds are a closed list in `plugins/dr-forge/scripts/review-route:185-193`; an unknown kind exits 2.
- `forge-config` applies a setting's `env` override in `resolve()`: `plugins/dr-forge/scripts/lib/forge-config.mjs:192`. `forge_setting` skips it under `DR_FORGE_NO_SETTINGS` (`scripts/lib/forge-env.sh:13`), so `lens-route` reads `DR_FORGE_LENS_CAP` itself.
- New suites under `plugins/dr-forge/tests/` are discovered by `node scripts/test-all.mjs` automatically (`CONTRIBUTING.md:61-66`).
- **Deviation from spec section 5 (Fable finding 11):** lens seats are read-only judges (`agents/judge-sonnet-high.md` tools: Read, Grep, Glob, WebFetch), so they cannot write `<workspace>/lens-<id>.md`. The session writes each reply to that file; the lens prompt caps a reply at ten findings of at most three lines each, so the context cost stays bounded.
- The keep-branch rule follows spec section 6 as the owner confirmed it on 2026-10-17: any `fail`, `flaky` or `cannot-test` in the `Acceptance QA: complete` line keeps the branch, even when the fix wave fixed the failure. A skipped residual failure and an unresolved critic Blocker each add a deferred register row (Tasks 10 and 12), which the rule also names.
- **Deviation from spec A9:** the three QA recovery cases live once, in `reference/final-review.md` step 0.5; each execution skill's ledger section carries the two lines and a bullet pointing at that step, rather than restating the cases.
- dr-forge defines no wall-clock bound for a Claude subagent (no "wall-clock" in the plugin; `reference/ladder.md` has Codex timeouts only). Task 10 sets one for QA: a background dispatch stopped after 45 minutes. The number is an unmeasured judgment (QA writes and runs one test file); the Task 2 probe runs show the real duration, and a later change can tune it.
- The `claude-security` plugin documents only an interactive launch (`claude --agent claude-security:claude-security`, in `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/claude-security/agents/claude-security.md:3`, read 2026-10-17); the gates-template example in Task 13 marks its headless `-p` form as unverified.
- The installed tooling is dr-superpowers 1.34.1, so this plan's Implementer lines name `dr-superpowers:` agents; the code it edits is dr-forge 3.0.0, whose own text names `dr-forge:` agents.

## Task index

1. QA brief and the prose test suite
2. Probe the QA brief on a seeded defect
3. Acceptance statements and analyst verdicts
4. Architecture critic
5. Review lens files
6. lensCap setting
7. lens-route script
8. Lenses plan line and plan-lint checks
9. acceptance-ambiguous ruling kind
10. Final review step 0.5, lens dispatch and ledger lines
11. Reviewer prompts carry lenses and the A<n> question
12. Auto run and finishing rules
13. Milestone evidence, security gate example and Codex seats
14. Release 3.1.0 and full validation

---

### Task 1: QA brief and the prose test suite

**Files:**
- Create: `plugins/dr-forge/reference/acceptance-qa.md`
- Create: `plugins/dr-forge/tests/process-roles.test.sh`

**Interfaces:**
- Produces: C10 (the brief and its placeholders), C8 (report format), C9 (test naming), C11 (the prose test suite).

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-forge/tests/process-roles.test.sh` with exactly:

```bash
#!/usr/bin/env bash
# The process roles (analyst, architecture critic, QA and review lenses) live
# in skill and reference text; each check pins one whole instruction.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "yes"
}

QA="$P/reference/acceptance-qa.md"
names "qa: the seat" "$QA" 'dispatches `dr-forge:impl-sonnet-high`'
names "qa: never reads the plan" "$QA" 'You may not read the plan, the'
names "qa: expectations first" "$QA" 'the spec text alone, as literal values in the test'
names "qa: test names" "$QA" 'Each test name starts with `A<n>:`'
names "qa: never fixes the code" "$QA" 'An assertion failure is a finding, which you never fix'
names "qa: detached mutation worktree" "$QA" 'git worktree add --detach [WORKSPACE]/qa-mutation HEAD'
names "qa: report path" "$QA" '`[WORKSPACE]/acceptance-report.md`'
names "qa: ambiguous result" "$QA" '`cannot-test: ambiguous`'
names "qa: rerun mode" "$QA" '`rerun`: the acceptance file may already exist'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/process-roles.test.sh`
Expected: FAIL lines for every `qa:` check, ending `0 passed, 9 failed`.

- [ ] **Step 3: Write the brief**

Create `plugins/dr-forge/reference/acceptance-qa.md` with exactly:

````markdown
# Acceptance QA

Step 0.5 of the final review ([final-review.md](final-review.md)). One
implementer seat that did not write the plan turns the spec's `test`
acceptance statements into executable tests against the built branch, so the
plan writer is not the only author of the tests that grade its work. This file
is the seat's brief; final-review.md §0.5 is the session's part.

## The dispatch

The session dispatches `dr-forge:impl-sonnet-high` (on a Codex host, the
native implementer `gpt-6.1-sol / high`) with this file and:

- `[SPEC]` — the spec's path.
- `[STATEMENTS]` — every `A<n>` line of the spec's `## Acceptance` section
  tagged `test`, verbatim.
- `[BASE]` and `[HEAD]` — the branch's merge base and its head.
- `[TEST_COMMAND]` — the test command the project's `gates.md` declares, or
  `none`.
- `[WORKSPACE]` — the plan's workspace directory.
- `[MODE]` — one of:
  - `first`: write and run a test for every statement;
  - `rerun`: the acceptance file may already exist from an earlier run that
    was cut off. Run it as it is, never rewrite a test in it, and write tests
    only for statements it does not cover yet;
  - `reword A<n>[, A<m>]`: the spec's text for those statements changed.
    Rewrite only their tests, from the new text, and run the whole file.

## What you may read

The spec, the repository's code at `[HEAD]`, its README and documentation, and
its existing tests for their layout and helpers. You may not read the plan, the
ledger, task reports, review packages or anything else under `[WORKSPACE]`
except the report you write. Independence from the plan is the point of this
seat: the plan's tests were written by the same author as its code.

## Procedure

1. **Expectations first.** For each statement, write its expected outcome from
   the spec text alone, as literal values in the test, before you read any
   implementation beyond the public surface: the CLI and its `--help`, HTTP
   routes, the exported API, and the files the code writes. When the code
   disagrees with the statement, the test follows the statement.
2. **Where tests live.** Put the tests in the project's existing test layout,
   in one file named `<spec-slug>.acceptance.<ext>` (the spec's file name
   without its date and `-design.md`), or the nearest name the test framework
   accepts. Each test name starts with `A<n>:`; where a test name cannot hold a
   colon, use `a<n>_<words>`. Test only through the public surface.
3. **Run, with a timeout.** Run the file with `[TEST_COMMAND]` scoped to it,
   or the framework's own runner, always under `timeout`. A setup or import
   error is your own bug: fix the test. An assertion failure is a finding, which you never fix: you do not
   edit the code under test. Re-run a failing test once; when the two runs
   disagree, record `flaky`.
4. **Mutation check on every `neg` statement.** For each statement tagged
   `neg` whose test passed:
   - `git worktree add --detach [WORKSPACE]/qa-mutation HEAD`;
   - in that worktree, link the dependency directories the tests need from the
     main worktree (for example `node_modules` or a virtualenv), or run the
     plan's `**Worktree setup:**` command when the session gave you one;
   - make one minimal change that violates the statement (remove the guard,
     invert the check, skip the refusal);
   - run that statement's test there and record `red` when it fails and
     `green` when it still passes;
   - `git worktree remove --force [WORKSPACE]/qa-mutation`, then confirm with
     `git worktree list` and `git status` that the main worktree is unchanged.
5. **Commit and report.** Commit the acceptance file and any fixtures it needs,
   and nothing else, as `test(<scope>): add acceptance tests for <spec-slug>`.
   Write the report below.

## The report

`[WORKSPACE]/acceptance-report.md`:

```markdown
| Statement | Test | Result | Mutation |
|---|---|---|---|
| A1 | `tests/foo.acceptance.sh` A1: rejects an empty name | pass | n/a |
| A2 | `tests/foo.acceptance.sh` A2: never writes outside the root | pass | red |

Command: timeout 300 bash tests/foo.acceptance.sh → 2 passed, 0 failed
```

Result is one of `pass`, `fail`, `flaky`, `cannot-test: ambiguous` (the
statement can be read two ways; name both readings in the Test cell),
`cannot-test: no-surface` (no public surface reaches the behaviour; say what
is missing) or `cannot-test: timeout`. List each `demo` statement as
`demo — not executed`. Mutation is `red`, `green` or `n/a`.

## Never

- Never edit the code under test, and never weaken a test so that it passes.
- Never leave the mutation worktree behind.
- Never write outside the test layout and `[WORKSPACE]/acceptance-report.md`.
- Never run a test without a timeout.
````

- [ ] **Step 4: Run test to verify it passes**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/process-roles.test.sh`
Expected: PASS, ending `9 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/reference/acceptance-qa.md plugins/dr-forge/tests/process-roles.test.sh
git commit -m "feat(dr-forge): add the acceptance QA brief"
```

### Task 2: Probe the QA brief on a seeded defect

**Files:**
- Create: `docs/superpowers/notes/2026-10-17-acceptance-qa-probe.md`

**Interfaces:**
- Consumes: C10 (the brief from Task 1), C8 (the report it writes).
- Produces: the probe note; no later task consumes it, but a failed probe stops the plan.

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2

This task is the session's own (the plan is inline): it dispatches two QA seats and judges their reports. It verifies spec acceptance statement A10 and the spec's riskiest assumption before any skill text depends on the brief.

- [ ] **Step 1: Write the probe spec**

Run `bash /root/.claude/plugins/cache/darkraise/dr-superpowers/1.34.1/scripts/sdd-workspace docs/superpowers/plans/2026-10-17-dr-forge-process-roles.md` and call the printed directory `WS`. Create `WS/probe/spec.md` with exactly:

```markdown
# Register check probe

## Acceptance

A1. [test, high] Given a register file with a title, a `**Source:**` line and an item table but no `**Covers:**` line, when `plugins/dr-forge/scripts/register check <file>` runs from the repository root, then it prints `ERROR 1: missing **Covers:** line` and exits with a non-zero status.
A2. [test, neg, high] Given that same register file, `plugins/dr-forge/scripts/register check <file>` never prints `register: 0 errors`.
```

- [ ] **Step 2: Run the clean probe**

Run `git worktree add --detach WS/probe/clean HEAD`. Dispatch `dr-superpowers:impl-sonnet-high` with the full text of `plugins/dr-forge/reference/acceptance-qa.md` as its instructions and these values: `[SPEC]` = `WS/probe/spec.md`; `[STATEMENTS]` = the two lines above; `[BASE]` and `[HEAD]` = the output of `git -C WS/probe/clean rev-parse HEAD`; `[TEST_COMMAND]` = `none`; `[WORKSPACE]` = `WS/probe/clean-ws`; `[MODE]` = `first`. Tell it to work inside `WS/probe/clean`, that the spec slug is `register-probe`, and to put the acceptance file in `plugins/dr-forge/tests/`. Say nothing else about the code.

Expected: `WS/probe/clean-ws/acceptance-report.md` records A1 `pass` and A2 `pass` with mutation `red`.

- [ ] **Step 3: Run the seeded probe**

```bash
git worktree add --detach WS/probe/seeded HEAD
sed -i '54s/.*/    :/;55s/.*/    :/' WS/probe/seeded/plugins/dr-forge/scripts/register
git -C WS/probe/seeded commit -q -am "probe: seed defect"
printf '# Seed check\n\n**Source:** probe\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | x | - | - | open | - |\n' > WS/probe/reg.md
bash WS/probe/seeded/plugins/dr-forge/scripts/register check WS/probe/reg.md; echo "exit=$?"
```

The last command must print `register: 0 errors` and `exit=0`; that confirms the seed took. Then dispatch a fresh `dr-superpowers:impl-sonnet-high` exactly as in Step 2, with `WS/probe/seeded` and `[WORKSPACE]` = `WS/probe/seeded-ws`. Do not mention the seed.

Expected: `WS/probe/seeded-ws/acceptance-report.md` records A1 `fail` and A2 `fail`.

- [ ] **Step 4: Record the result and clean up**

Create `docs/superpowers/notes/2026-10-17-acceptance-qa-probe.md`:

```markdown
# Acceptance QA probe — 2026-10-17

Brief: `plugins/dr-forge/reference/acceptance-qa.md` at <sha7 of HEAD>.
Seat: dr-superpowers:impl-sonnet-high, twice, fresh each time.
Statements: register check without a Covers line (A1), never "0 errors" (A2, neg).

| Run | A1 | A2 | A2 mutation |
|---|---|---|---|
| clean | <result> | <result> | <result> |
| seeded (Covers check blanked at scripts/register:54-55) | <result> | <result> | n/a |

Verdict: <the riskiest assumption held | it did not hold: what the seat did instead>.
```

Fill every `<…>` from the two reports. Then run `git worktree remove --force WS/probe/clean`, `git worktree remove --force WS/probe/seeded` and `git worktree prune`, and confirm `git worktree list` no longer shows them.

- [ ] **Step 5: Gate and commit**

When the clean run is not all `pass`, or the seeded run records `pass` for A1 or A2, the riskiest assumption failed: record the note, write `Task 2: BLOCKED — ruling seat — the QA brief did not detect a seeded violation; choose: strengthen "expectations first", or extend the mutation check to every test statement` in the ledger, and stop for your human partner. Otherwise commit:

```bash
git add docs/superpowers/notes/2026-10-17-acceptance-qa-probe.md
git commit -m "docs(dr-forge): record the acceptance QA probe"
```

### Task 3: Acceptance statements and analyst verdicts

**Files:**
- Modify: `plugins/dr-forge/skills/brainstorming/SKILL.md` (architectural checklist, After the Design, Documentation, Spec Self-Review)
- Modify: `plugins/dr-forge/skills/brainstorming/references/spec-document-reviewer-prompt.md`
- Modify: `plugins/dr-forge/skills/writing-plans/SKILL.md` (Assign the register rows)
- Test: `plugins/dr-forge/tests/process-roles.test.sh`

**Interfaces:**
- Consumes: C11.
- Produces: C1, and brainstorming checklist steps 7 (Draft acceptance) and 8 (Offer an auto run) that Task 4 renumbers.

**Items:** 4

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

Insert immediately above the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"` in `plugins/dr-forge/tests/process-roles.test.sh`:

```bash
BS="$P/skills/brainstorming/SKILL.md"
names "analyst: the checklist step" "$BS" '7. **Draft acceptance** — numbered, tagged, rated statements'
names "analyst: auto-run offer follows it" "$BS" 'right after the Draft acceptance step and before you'
names "analyst: the line format" "$BS" '`A<n>. [<test|demo>[, neg], <high|confirmed>] <statement>`'
names "analyst: the verdict options" "$BS" '**Right**, **Wrong, or not wanted** and **Not sure**'
names "analyst: not sure defers" "$BS" '--state deferred --note "Q: <question>"'
names "analyst: confirmed is the human's" "$BS" '`confirmed` is reserved for a verdict from your human partner'
names "analyst: self-review item" "$BS" 'every statement matches `A<n>. [<test|demo>[, neg], <high|confirmed>]'
after=$(grep -n '^## After the Design (architectural path)$' "$BS" | cut -d: -f1)
draft=$(grep -n '^\*\*Drafting acceptance:\*\*$' "$BS" | cut -d: -f1)
offer=$(grep -n '^\*\*Offering an auto run:\*\*$' "$BS" | cut -d: -f1)
check "analyst: drafting sits between After the Design and the auto-run offer" \
  "$([ -n "$after" ] && [ -n "$draft" ] && [ -n "$offer" ] && [ "$after" -lt "$draft" ] && [ "$draft" -lt "$offer" ] && echo yes || echo no)" "yes"
names "analyst: the process graph" "$BS" '"Draft acceptance\n(rate; ask below high)" -> "Offer an auto run\n(once, unless autoRun=off)";'
names "analyst: spec reviewer checks the format" "$P/skills/brainstorming/references/spec-document-reviewer-prompt.md" \
  'a rating other than `high` or `confirmed`'
names "analyst: plans never build on a deferred statement" "$P/skills/writing-plans/SKILL.md" \
  'A row whose Item begins `A<n>:` is a deferred acceptance statement'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/process-roles.test.sh`
Expected: FAIL on the eleven `analyst:` checks; the nine `qa:` checks pass.

- [ ] **Step 3: Edit the three files**

In `plugins/dr-forge/skills/brainstorming/SKILL.md`, replace:

```markdown
6. **Present design** — in sections scaled to their complexity, get user approval after each section
7. **Offer an auto run** — unless `autoRun=off` or on a Codex host: one question once the last section is approved (see After the Design)
8. **Write design doc** — save to `<docs>/specs/YYYY-MM-DD-<topic>-design.md` and commit
9. **Spec self-review** — one round for placeholders, contradictions, ambiguity, scope, acceptance and the riskiest assumption; post its block before the user review (see below)
10. **User reviews written spec** — ask user to review the spec file before proceeding (an auto run has Fable review it instead)
11. **Transition to implementation** — invoke writing-plans skill to create implementation plan
```

with:

```markdown
6. **Present design** — in sections scaled to their complexity, get user approval after each section
7. **Draft acceptance** — numbered, tagged, rated statements; ask your human partner about every one rated below `high` (see Drafting acceptance)
8. **Offer an auto run** — unless `autoRun=off` or on a Codex host: one question once the acceptance statements are settled (see After the Design)
9. **Write design doc** — save to `<docs>/specs/YYYY-MM-DD-<topic>-design.md` and commit
10. **Spec self-review** — one round for placeholders, contradictions, ambiguity, scope, acceptance and the riskiest assumption; post its block before the user review (see below)
11. **User reviews written spec** — ask user to review the spec file before proceeding (an auto run has Fable review it instead)
12. **Transition to implementation** — invoke writing-plans skill to create implementation plan
```

Replace:

```markdown
its own message, right after your human partner approves the last design
section and before you write the spec.
```

with:

```markdown
its own message, right after the Draft acceptance step and before you
write the spec.
```

In the `## Process Flow` dot graph, replace the node line:

```text
    "Offer an auto run\n(once, unless autoRun=off)" [shape=box];
```

with:

```text
    "Draft acceptance\n(rate; ask below high)" [shape=box];
    "Offer an auto run\n(once, unless autoRun=off)" [shape=box];
```

and replace the edge line:

```text
    "User approves design?" -> "Offer an auto run\n(once, unless autoRun=off)" [label="yes"];
```

with:

```text
    "User approves design?" -> "Draft acceptance\n(rate; ask below high)" [label="yes"];
    "Draft acceptance\n(rate; ask below high)" -> "Offer an auto run\n(once, unless autoRun=off)";
```

Replace the line `**Offering an auto run:**` (the first line under `## After the Design (architectural path)`) with this block (the drafting section, a blank line, then the original line):

```markdown
**Drafting acceptance:**

Once your human partner approves the last design section, draft the spec's
acceptance statements before the auto-run offer, while they are still here to
answer. Each statement is one line:

`A<n>. [<test|demo>[, neg], <high|confirmed>] <statement>`

- `A<n>` numbers are never reused. A deferred statement leaves the line
  `A<n>. deferred — register row <id>`.
- `test` means an automated test can check it; `demo` means only a person
  watching the result can (visual output, an interactive screen).
- `neg` marks a statement about what must not happen; at least one carries it.
- Rate each statement while drafting: `high` when it follows directly from what
  your human partner said, from code you read this session, or from a recorded
  seat ruling; `medium` or `low` otherwise, each with the exact question that
  would settle it. `confirmed` is reserved for a verdict from your human partner.

1. Show the whole list in chat.
2. Ask about every statement rated below `high` with the multiple-choice
   prompt, at most four per call: the statement, why it is uncertain and the
   settling question, with the options **Right**, **Wrong, or not wanted** and **Not sure**.
   Keep a typed note verbatim.
3. **Right**: the statement becomes `confirmed`. **Wrong**: rewrite it from the
   note and ask once more; a second **Wrong** or **Not sure** defers it.
   **Not sure**: defer it.
4. To defer a statement, run
   `scripts/register add <register> "A<n>: <statement>" --state deferred --note "Q: <question>"`.
   With no register open, first open `<docs>/registers/<date>-<spec-slug>.md`
   as Opening an item register says; its `**Covers:**` stays `-` until the spec
   is written. A register row whose Item begins `A<n>:` is a deferred acceptance
   statement wherever dr-forge refers to one.

The step asks nothing when every statement is `high`. A statement you add or
change while writing the spec, rated below `high`, is asked the same way before
the spec is committed; in an auto run it goes up the ruling ladder instead
([auto-run.md](../../reference/auto-run.md) §Rulings).

**Offering an auto run:**
```

Replace the Documentation bullet that begins `- Every spec has an \`## Acceptance\` section: numbered statements a test or a` and ends `these numbers.` (six lines) with:

```markdown
- Every spec has an `## Acceptance` section holding the statements settled in
  Drafting acceptance, one per line in the form
  `A<n>. [<test|demo>[, neg], <high|confirmed>] <statement>`. Cover the main
  path, the errors and edge cases, and at least one thing that must not happen
  (`neg`). State observable behaviour, not the implementation, and give a word
  like "fast" its number. When a register covers the spec, a row's Acceptance
  cell can cite these numbers.
```

Replace the Spec Self-Review item:

```markdown
6. **Acceptance:** The `## Acceptance` section is present, every statement in it is checkable by a test or a demo, and at least one says what must not happen.
```

with:

```markdown
6. **Acceptance:** The `## Acceptance` section is present, every statement matches `A<n>. [<test|demo>[, neg], <high|confirmed>] <statement>` and is checkable by a test or a demo, at least one carries `neg`, and no rating other than `high` or `confirmed` appears.
```

In `plugins/dr-forge/skills/brainstorming/references/spec-document-reviewer-prompt.md`, replace the table row:

```markdown
    | Acceptance | No `## Acceptance` section, a statement no test or demo could check, or no statement of what must not happen |
```

with:

```markdown
    | Acceptance | No `## Acceptance` section; a statement no test or demo could check; a line not in the form `A<n>. [<test|demo>[, neg], <high|confirmed>] <statement>`; no statement tagged `neg`; or a rating other than `high` or `confirmed` |
```

In `plugins/dr-forge/skills/writing-plans/SKILL.md`, replace:

```markdown
3. Record a deferral as a row, not as prose. An item this plan will not answer
   is `scripts/register set <register> <id> deferred --note "<the reason>"`. An
   "Out of scope" heading is read by nothing, which is how design-time
   deferrals were lost.
```

with:

```markdown
3. Record a deferral as a row, not as prose. An item this plan will not answer
   is `scripts/register set <register> <id> deferred --note "<the reason>"`. An
   "Out of scope" heading is read by nothing, which is how design-time
   deferrals were lost.
4. A row whose Item begins `A<n>:` is a deferred acceptance statement: your
   human partner or the ruling ladder left it unsettled. No task's `**Items:**`
   line names it, and no task builds on it.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/process-roles.test.sh`
Expected: PASS, ending `20 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/skills/brainstorming plugins/dr-forge/skills/writing-plans/SKILL.md plugins/dr-forge/tests/process-roles.test.sh
git commit -m "feat(dr-forge): rate acceptance statements in design"
```

### Task 4: Architecture critic

**Files:**
- Create: `plugins/dr-forge/criteria/architecture-critique.md`
- Create: `plugins/dr-forge/skills/brainstorming/references/architecture-critic-prompt.md`
- Modify: `plugins/dr-forge/skills/brainstorming/SKILL.md` (checklist; a new Architecture critic subsection; User Review Gate)
- Modify: `plugins/dr-forge/skills/brainstorming/references/spec-document-reviewer-prompt.md`
- Test: `plugins/dr-forge/tests/process-roles.test.sh`

**Interfaces:**
- Consumes: C11; the checklist Task 3 wrote.
- Produces: brainstorming step 11 (Architecture critic) and the `## Critic findings` spec section that Task 12 names.

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

Insert above the summary `printf` line of `plugins/dr-forge/tests/process-roles.test.sh`:

```bash
AC="$P/criteria/architecture-critique.md"
check "critic: criteria ids" \
  "$(grep -o '{#[a-z0-9_]\{1,\}}' "$AC" 2>/dev/null | tr -d '{#}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" \
  "failure operability simplest unstated"
CP="$P/skills/brainstorming/references/architecture-critic-prompt.md"
names "critic: the prompt does not score" "$CP" 'do not score them 1-20'
names "critic: ranked findings" "$CP" 'Blocker / High / Medium / Nit'
names "critic: one change" "$CP" 'If I could change one thing, it would be'
names "critic: checklist step" "$BS" '11. **Architecture critic** — one `dr-forge:judge-opus` round'
names "critic: findings section" "$BS" 'answered in a `## Critic findings` section'
names "critic: counts in the review request" "$BS" 'Critic: <b> Blocker, <h> High (<f> fixed, <a> answered), <m> Medium'
names "critic: spec reviewer checks answers" "$P/skills/brainstorming/references/spec-document-reviewer-prompt.md" \
  'a Blocker or High critic finding with neither a fix nor an answer'
names "critic: the process graph" "$BS" '"Architecture critic\n(one judge-opus round)" -> "User reviews spec?";'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/process-roles.test.sh`
Expected: FAIL on the nine `critic:` checks; all earlier checks pass.

- [ ] **Step 3: Write the critic files and wire them in**

Create `plugins/dr-forge/criteria/architecture-critique.md` with exactly (ASCII only):

```markdown
# Architecture Critique - Review Criteria

Applied by dr-forge:brainstorming on the architectural path, after the spec
self-review and before the spec review. These are review lenses, not a scored
rubric: the prompt asks for ranked findings.

## Ground Truth Note

Judge the design the spec describes against the repository as it is. Read the
files the spec names before believing what it says about them. A stated
rationale ("kept simple on purpose", "we will add it later") is the author
grading the design and settles nothing; weigh the design itself.

## Criteria

### Simplest Sufficient Design {#simplest}

Look at the components, files and abstractions the spec introduces. Report a
finding when a simpler design meets every stated requirement, when an
abstraction has one use and no second one in sight, or when a boundary matches
no real seam in the code. Ignore requirements the spec never states; the next
criterion owns those.

### Unstated Requirements {#unstated}

Look for the non-functional requirements the design depends on without saying
so: latency, throughput, consistency, compatibility with existing callers and
stored data, platform support, cost. Report a finding when the design relies on
one silently or would violate one. Ignore failure handling, which the next
criterion owns.

### Failure and Change Paths {#failure}

Trace one realistic failure end to end through the design, and read its
migration and rollback story. Report a finding when a failure has no defined
outcome, when existing data or users have no path from the old behaviour to the
new, or when the plan is "we will figure it out". Ignore day-to-day operation,
which the next criterion owns.

### Operability {#operability}

Picture the person debugging this in production, or in a stuck automated run.
Report a finding when the design gives them no way to see what happened: no
log line, status, ledger entry or error message that names the cause. Ignore
code style and naming.
```

Create `plugins/dr-forge/skills/brainstorming/references/architecture-critic-prompt.md` with exactly:

````markdown
# Architecture Critic Prompt Template

Use this template when dispatching the architecture critic: step 11 of the
architectural checklist, after the spec self-review and before the spec review.

```
Subagent (dr-forge:judge-opus; on a Codex host, a native judge at rank 8 or above):
  description: "Critique the spec's design"
  prompt: |
    You are a principal engineer reviewing a design before anyone builds it.
    Your default stance is skeptical: ask whether each part is needed and
    what happens when it fails.

    **Spec:** [SPEC_FILE_PATH]
    **Approved design sections:** [DESIGN_SECTIONS]
    **Repository:** [REPO_ROOT]

    Read the criteria at [PLUGIN_ROOT]/criteria/architecture-critique.md and
    use each criterion as a lens: do not score them 1-20. Read the files the
    spec names before judging what it says about them.

    ## Output

    Findings ranked Blocker / High / Medium / Nit, most severe first. Each:
    - what is wrong;
    - where in the spec (section heading);
    - why it matters, citing a file:line when the repository shows it;
    - a concrete change to the spec.

    A Blocker is a design that cannot meet a stated requirement or loses data;
    a High finding will cost a rewrite later. End with one sentence:
    "If I could change one thing, it would be ...". With nothing to report,
    write `No findings.` and that sentence.
```

**Placeholders:** `[SPEC_FILE_PATH]` and `[REPO_ROOT]` are paths; `[DESIGN_SECTIONS]`
is the approved design sections, verbatim; `[PLUGIN_ROOT]` is the resolved
dr-forge plugin directory.
````

In `plugins/dr-forge/skills/brainstorming/SKILL.md`, replace:

```markdown
10. **Spec self-review** — one round for placeholders, contradictions, ambiguity, scope, acceptance and the riskiest assumption; post its block before the user review (see below)
11. **User reviews written spec** — ask user to review the spec file before proceeding (an auto run has Fable review it instead)
12. **Transition to implementation** — invoke writing-plans skill to create implementation plan
```

with:

```markdown
10. **Spec self-review** — one round for placeholders, contradictions, ambiguity, scope, acceptance and the riskiest assumption; post its block before the user review (see below)
11. **Architecture critic** — one `dr-forge:judge-opus` round on the written spec; fix or answer every Blocker and High finding (see Architecture critic)
12. **User reviews written spec** — ask user to review the spec file before proceeding (an auto run has Fable review it instead)
13. **Transition to implementation** — invoke writing-plans skill to create implementation plan
```

In the `## Process Flow` dot graph, replace the node line:

```text
    "Spec self-review\n(one round, shown)" [shape=box];
```

with:

```text
    "Spec self-review\n(one round, shown)" [shape=box];
    "Architecture critic\n(one judge-opus round)" [shape=box];
```

and replace the edge line:

```text
    "Spec self-review\n(one round, shown)" -> "User reviews spec?";
```

with:

```text
    "Spec self-review\n(one round, shown)" -> "Architecture critic\n(one judge-opus round)";
    "Architecture critic\n(one judge-opus round)" -> "User reviews spec?";
```

Replace the line `**User Review Gate:**` with this block (the new subsection, a blank line, then the original line):

```markdown
**Architecture critic:**

After the self-review block, dispatch the critic once with
[architecture-critic-prompt.md](references/architecture-critic-prompt.md): the
spec path, the approved design sections verbatim and the repository root. It
runs in an auto run too, before the Fable review. A revision of the spec does
not earn a second critic round.

- Fix each Blocker and High finding in the spec, or keep the design with the
  finding answered in a `## Critic findings` section at the end of the spec:
  one bullet per finding, with the reason the design stands.
- List every Medium and Nit finding in that section too; they need no answer.
- Commit the spec, then state the counts in the review request below:
  `Critic: <b> Blocker, <h> High (<f> fixed, <a> answered), <m> Medium`.

**User Review Gate:**
```

In the User Review Gate, replace:

```markdown
> "Spec written and committed to `<path>`. Please review it and let me know if you want to make any changes before we start writing out the implementation plan."
```

with:

```markdown
> "Spec written and committed to `<path>`. Critic: <b> Blocker, <h> High (<f> fixed, <a> answered), <m> Medium. Please review it and let me know if you want to make any changes before we start writing out the implementation plan."
```

In `plugins/dr-forge/skills/brainstorming/references/spec-document-reviewer-prompt.md`, insert this row directly below the `| Riskiest assumption |` row:

```markdown
    | Critic findings | a Blocker or High critic finding with neither a fix nor an answer in `## Critic findings` |
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/process-roles.test.sh; timeout 600 bash plugins/dr-forge/tests/criteria.test.sh`
Expected: both PASS; process-roles ends `29 passed, 0 failed`, and criteria.test.sh reports the `architecture-critique:` checks as `ok`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/criteria/architecture-critique.md plugins/dr-forge/skills/brainstorming plugins/dr-forge/tests/process-roles.test.sh
git commit -m "feat(dr-forge): add the architecture critic"
```

### Task 5: Review lens files

**Files:**
- Create: `plugins/dr-forge/criteria/lenses/security.md`, `silent-failures.md`, `test-quality.md`, `type-design.md`, `docs-comments.md`, `lang-typescript.md`, `lang-csharp.md`, `lang-bash.md`, `lang-python.md`
- Modify: `plugins/dr-forge/tests/criteria.test.sh:25` and the loop body
- Test: `plugins/dr-forge/tests/criteria.test.sh`

**Interfaces:**
- Produces: C2 (the nine lens files and their `Applies:` lines).

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Write the failing test**

In `plugins/dr-forge/tests/criteria.test.sh`, change the loop header `for f in "$CRITERIA"/*.md; do` to:

```bash
for f in "$CRITERIA"/*.md "$CRITERIA"/lenses/*.md; do
```

Inside that loop, directly after the `check "$base: content is ASCII only" \` command (its two lines), insert:

```bash
  case $f in
    */lenses/*)
      check "$base: one Applies line" "$(grep -c '^Applies: ' "$f")" "1"
      bad=$(sed -n 's/^Applies: //p' "$f" | sed 's/ ; /\n/g' | grep -cvE '^(always|paths [^ ].*|added .+)$')
      check "$base: every Applies clause parses" "$bad" "0" ;;
  esac
```

Below the loop's `done`, insert:

```bash
got=$(for f in "$CRITERIA"/lenses/*.md; do [ -e "$f" ] && basename "$f" .md; done | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
check "the nine initial lenses exist" "$got" \
  "docs-comments lang-bash lang-csharp lang-python lang-typescript security silent-failures test-quality type-design"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/criteria.test.sh`
Expected: FAIL on `the nine initial lenses exist` (got an empty list).

- [ ] **Step 3: Write the nine lens files**

Each file is ASCII only. Create them with exactly this content.

`plugins/dr-forge/criteria/lenses/security.md`:

```markdown
# Security Lens - Review Criteria

Applies: always

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:security] at your own severity. Read by the final review and by a
risk-3 task review whose plan names it.

## Ground Truth Note

Judge the code in the diff, not the comments or commit messages that describe
it. A comment saying input is validated is not validation: find the check. A
passing test shows an attack path is closed only when it exercises that path.

## Criteria

### Injection and Unsafe Construction {#injection}

Look at every shell command, query, file path, URL, regular expression or
template the diff builds from data that can come from outside the process:
arguments, environment, files, network, user or hook input. Report a finding
when that data reaches the construct without quoting, parameterisation or an
allowlist, including eval, unquoted shell expansion and path joins that allow
"..". Ignore secrets, which the next criterion owns.

### Secrets and Credentials {#secrets}

Look at added literals, configuration, logs, error messages and test fixtures.
Report a finding when a credential, token, key or connection string is
hardcoded, logged, echoed into an error, written to a world-readable file or
committed as a fixture. Ignore authorization logic.

### Authorization and Trust Boundaries {#authz}

Look at code that decides who may do what, and at data crossing a trust
boundary: deserialisation, downloaded files, plugin or hook input. Report a
finding when a check is missing, runs after the action it guards, can be
bypassed by a default, or when untrusted data is deserialised or executed
without validation. Ignore construction defects, which the first criterion owns.
```

`plugins/dr-forge/criteria/lenses/silent-failures.md`:

```markdown
# Silent Failures Lens - Review Criteria

Applies: added (catch|except|rescue|\|\| *true|2>/dev/null|\?\?|fallback)

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:silent-failures] at your own severity.

## Ground Truth Note

A failure is silent when nobody downstream can tell it happened. Judge what the
code does when the operation fails, not what the happy path does. A log line
nobody reads is not handling.

## Criteria

### Swallowed Errors {#swallowed}

Look at every catch, except, rescue, "|| true", "2>/dev/null" and ignored
return value the diff adds. Report a finding when an error is caught and
dropped, replaced by a default, or logged and then treated as success, so the
caller proceeds on a false premise. Ignore fallbacks that are part of the
specified behaviour, which the next criterion owns.

### Fallbacks That Hide Failure {#fallback}

Look at default values, "??" and "||" chains, retries and alternate code paths.
Report a finding when a fallback makes a broken dependency look like a working
one: an empty list for a failed fetch, a cached value presented as fresh, a
retry loop with no final error. Ignore exit-status handling, which the next
criterion owns.

### Lost Exit Status {#status}

Look at pipelines, command substitutions, background jobs and process calls.
Report a finding when a non-zero status is lost: a pipeline without pipefail, a
"local x=$(cmd)" that masks the status, an awaited promise whose rejection is
ignored, a subprocess whose return code is never read.
```

`plugins/dr-forge/criteria/lenses/test-quality.md`:

```markdown
# Test Quality Lens - Review Criteria

Applies: paths *tests/* *test/* *__tests__/* *.test.* *_test.* *.spec.* *test_*.py

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:test-quality] at your own severity.

## Ground Truth Note

A test is worth its run time only if it fails when the behaviour it names
breaks. Judge each changed test by imagining the code broken in the way the
test's name describes.

## Criteria

### Tests That Cannot Fail {#cannot_fail}

Look at every added or changed test. Report a finding when it asserts nothing,
asserts only that code ran, would pass against a stub that returns a constant,
reads its expected value from the code under test, or is skipped. Ignore what
the test is coupled to, which the next criterion owns.

### Tests Pinned to Implementation {#pinned}

Report a finding when a test checks private structure, call order or mock
interactions instead of observable behaviour, so a correct refactor would break
it. Ignore missing cases, which the next criterion owns.

### Missing Cases {#missing}

Look at the branches the diff adds in the code under test. Report a finding
when an error path, a boundary value or a "must not happen" case has no test
that reaches it.
```

`plugins/dr-forge/criteria/lenses/type-design.md`:

```markdown
# Type Design Lens - Review Criteria

Applies: added ^[[:space:]]*(export[[:space:]]+)?((public|internal|private|protected|abstract|sealed|static|readonly|partial)[[:space:]]+)*(interface|type|class|struct|record|enum)[[:space:]]+[A-Z]

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:type-design] at your own severity.

## Ground Truth Note

Judge the types the diff declares by the states they allow, not by their names
or comments.

## Criteria

### Invariants in Types {#invariants}

Look at each added type. Report a finding when it can represent a state the
code treats as impossible: two fields that must not both be set, a status
string where a closed set exists, a nullable field that is never null after
construction, a number that must stay in a range. Ignore visibility, which the
next criterion owns.

### Encapsulation {#encapsulation}

Report a finding when a type exposes mutable internals that callers can use to
break its invariants, or when callers must remember a call order the type could
enforce itself.
```

`plugins/dr-forge/criteria/lenses/docs-comments.md`:

```markdown
# Docs and Comments Lens - Review Criteria

Applies: paths *.md ; added ^[[:space:]]*(//|/\*|\*[[:space:]]|#[[:space:]])

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:docs-comments] at your own severity.

## Ground Truth Note

The code is the authority. A comment or document that disagrees with it is the
defect, however well written.

## Criteria

### Accuracy {#accuracy}

Look at every comment and document line the diff adds or leaves next to changed
code. Report a finding when it states behaviour, a name, a path, a default, a
count or an exit code the code does not have. Ignore stale references
elsewhere, which the next criterion owns.

### Rot {#rot}

Search the repository for references to names, paths, flags and section
headings the diff renames or removes. Report a finding for each document or
comment still pointing at the old one.
```

`plugins/dr-forge/criteria/lenses/lang-typescript.md`:

```markdown
# TypeScript and JavaScript Lens - Review Criteria

Applies: paths *.ts *.tsx *.js *.jsx *.mjs *.cjs *.mts *.cts

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:lang-typescript] at your own severity. Known defect patterns only.

## Ground Truth Note

Judge the code the runtime will execute. Type annotations and casts are claims
the compiler may not check.

## Criteria

### Async Defects {#async}

Report a finding for a promise that is neither awaited nor returned (a floating
promise), an async callback passed to forEach, a missing await before a value
is used, or a rejection with no handler.

### Type Holes {#types}

Report a finding for "any" or an "as" cast that hides a real type error, a
non-null assertion on a value that can be null, "==" or "!=" where coercion
changes the result, or JSON parsed into a type without validation.

### Module Defects {#modules}

Report a finding for ESM and CommonJS mixed in one package without a boundary,
a default import of a module with only named exports (or the reverse),
__dirname or require in an ES module, or an import path missing the extension
an ES module needs.
```

`plugins/dr-forge/criteria/lenses/lang-csharp.md`:

```markdown
# C# Lens - Review Criteria

Applies: paths *.cs

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:lang-csharp] at your own severity. Known defect patterns only.

## Ground Truth Note

Judge the code the runtime will execute. Nullable annotations and analyzer
suppressions are claims, not checks.

## Criteria

### Async Defects {#async}

Report a finding for "async void" outside an event handler, ".Result",
".Wait()" or ".GetAwaiter().GetResult()" on a task (sync over async), a task
that is started and never awaited, or a CancellationToken accepted and ignored.

### Resource Lifetime {#disposal}

Report a finding for an IDisposable that is created and not disposed (no
"using"), an event handler subscribed and never removed on a longer-lived
publisher, or a timer or stream kept alive by a static reference.

### Null and Capture Defects {#nulls}

Report a finding for the null-forgiving "!" on a value that can be null, a
nullable warning suppressed instead of handled, or a loop variable of a "for"
loop captured by a closure that runs later.
```

`plugins/dr-forge/criteria/lenses/lang-bash.md`:

```markdown
# Bash Lens - Review Criteria

Applies: paths *.sh *.bash ; added ^#!.*(bash|/sh)

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:lang-bash] at your own severity. Known defect patterns only. Scripts here
must also run under Git Bash on Windows and on macOS.

## Ground Truth Note

Judge what the shell will do with the text, including word splitting and glob
expansion, not what the author meant.

## Criteria

### Quoting and Expansion {#quoting}

Report a finding for an unquoted variable or command substitution that can hold
spaces, newlines or glob characters, an unquoted array expansion, a "for" loop
over "ls" output, or a pattern left unquoted where a literal was meant.

### Error Handling {#errors}

Report a finding for a "cd" without "|| exit" or a check, a pipeline whose
failure is lost without pipefail, "local x=$(cmd)" that masks the status of
cmd, a "set -e" relied on inside a function called from a condition, or a
command run with no timeout where it can hang.

### Portability {#portability}

Report a finding for GNU-only or BSD-only flags with no fallback ("sed -i"
without a suffix check, "readlink -f", "date -d", "grep -P"), a bash-only
construct in a script with a /bin/sh shebang, or a path that assumes "/" where
Git Bash hands a Windows path.
```

`plugins/dr-forge/criteria/lenses/lang-python.md`:

```markdown
# Python Lens - Review Criteria

Applies: paths *.py

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:lang-python] at your own severity. Known defect patterns only.

## Ground Truth Note

Judge the code the interpreter will execute. Type hints are not enforced at run
time.

## Criteria

### Binding Defects {#binding}

Report a finding for a mutable default argument, a closure in a loop that reads
the loop variable later (late binding), or a class attribute used as
per-instance state.

### Exception Defects {#exceptions}

Report a finding for a bare "except:", "except Exception" that swallows the
error, an exception re-raised without "from" where the cause matters, or
"assert" used for validation that "python -O" removes.

### Resource Defects {#resources}

Report a finding for a file, socket or lock opened without a context manager, a
subprocess call with no timeout or with "shell=True" on built strings, or a
generator left half-consumed while it holds a resource.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/criteria.test.sh`
Expected: PASS, every `security:`, `lang-bash:` and other lens check `ok`, and `the nine initial lenses exist` `ok`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/criteria/lenses plugins/dr-forge/tests/criteria.test.sh
git commit -m "feat(dr-forge): add specialist review lenses"
```

### Task 6: lensCap setting

**Files:**
- Modify: `plugins/dr-forge/config/schema.mjs` (after the `codexReview` entry)
- Modify: `plugins/dr-forge/README.md` (settings table, after the `codexReview` row)
- Test: `plugins/dr-forge/tests/forge-config.test.sh`

**Interfaces:**
- Produces: C4.

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

In `plugins/dr-forge/tests/forge-config.test.sh`, add the row `lensCap 4 2 10` directly below the row `codexReview true false 0` in the `ROWS` heredoc. Directly below that heredoc's closing `ROWS` line (the first `ROWS` terminator in the file, at about line 126, followed by a blank line and `# --- Claude's own settings file`), insert:

```bash
fresh lens-env
check "lensCap: the environment wins" "$(DR_FORGE_LENS_CAP=1 fc get lensCap)" "1"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/forge-config.test.sh`
Expected: FAIL lines for `lensCap: default` and the other `lensCap:` checks.

- [ ] **Step 3: Add the setting**

In `plugins/dr-forge/config/schema.mjs`, directly after the closing `},` of the `codexReview` entry, insert:

```js
  lensCap: {
    type: 'number', default: 4, min: 0, max: 9, step: 1, zero: 'off', env: 'DR_FORGE_LENS_CAP', enforcedBy: 'script', group: 'Workflow', target: 'forge',
    label: 'Review lenses', title: 'Final-review lens cap',
    description: 'How many specialist review lenses the final review runs at most, highest priority first. 0 turns them off. DR_FORGE_LENS_CAP overrides it.',
  },
```

In `plugins/dr-forge/README.md`, directly below the `| Workflow | \`codexReview\` |` row, insert:

```markdown
| Workflow | `lensCap` | `4` | How many specialist review lenses (security, silent failures, test quality, the language lenses, type design, docs) the final review runs at most, in that priority order. `0` turns them off. `DR_FORGE_LENS_CAP` overrides it. |
```

- [ ] **Step 4: Run test to verify it passes**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/forge-config.test.sh`
Expected: PASS, ending with `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/config/schema.mjs plugins/dr-forge/README.md plugins/dr-forge/tests/forge-config.test.sh
git commit -m "feat(dr-forge): add the lensCap setting"
```

### Task 7: lens-route script

**Files:**
- Create: `plugins/dr-forge/scripts/lens-route`
- Create: `plugins/dr-forge/tests/lens-route.test.sh`

**Interfaces:**
- Consumes: C2 (lens files), C4 (cap).
- Produces: C3.

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-forge/tests/lens-route.test.sh` with exactly:

```bash
#!/usr/bin/env bash
# lens-route picks the specialist review lenses for a final review or a risk-3
# task. Each case pins one selection rule against a throwaway repository.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTE="$HERE/../scripts/lens-route"
export DR_FORGE_NO_SETTINGS=1
unset DR_FORGE_LENS_CAP CLAUDE_CONFIG_DIR

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
short() { sed -E 's/ criteria=[^ ]*//; s/ seat=[^ ]*//; s/ reason=(always|added|paths:[^ ]*)$//' | tr '\n' ';'; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
git init -q repo && cd repo || exit 1
git config user.email t@example.com && git config user.name t
git commit -q --allow-empty -m base
BASE=$(git rev-parse HEAD)
commit_file() { # commit_file <path> <content>
  mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; git add "$1"; git commit -q -m "add $1"
}

# Fixture lines carry a leading | so a plan that quotes this suite still lints.
sed 's/^|//' > plan.md <<'EOF'
|# Lens Fixture Plan
|
|## Task index
|
|1. risky
|2. plain
|3. unknown
|
|### Task 1: risky
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 3 = 3
|**Lenses:** security, lang-bash
|
|### Task 2: plain
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|### Task 3: unknown
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 3 = 3
|**Lenses:** nope
EOF

# A1/A3: a shell-only change set.
commit_file scripts/foo.sh 'echo hi'
HEAD1=$(git rev-parse HEAD)
out=$(bash "$ROUTE" plan.md --final "$BASE" "$HEAD1"); status=$?
check "final: exit 0" "$status" "0"
check "final: a shell-only change gets security and lang-bash" "$(short <<<"$out")" "lens security;lens lang-bash;"
check "final: no lens whose clauses all fail" "$(grep -cE '^lens (lang-csharp|lang-python|lang-typescript|type-design)' <<<"$out")" "0"
check "final: the seat and reason" "$(grep -c '^lens security criteria=[^ ]* seat=dr-forge:judge-sonnet-high reason=always$' <<<"$out")" "1"
crit=$(sed -n 's/^lens lang-bash criteria=\([^ ]*\) .*/\1/p' <<<"$out")
check "final: the criteria path exists" "$([ -f "$crit" ] && echo yes || echo no)" "yes"
check "final: the reason names the glob" "$(grep -c '^lens lang-bash .* reason=paths:\*\.sh$' <<<"$out")" "1"

# A2: more applicable lenses than the cap.
commit_file tests/a.test.ts 'try { run() } catch (e) {}'
commit_file README.md 'Docs.'
HEAD2=$(git rev-parse HEAD)
out=$(DR_FORGE_LENS_CAP=2 bash "$ROUTE" plan.md --final "$BASE" "$HEAD2")
check "cap 2: two lenses, the rest skipped in order" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens-skipped test-quality reason=cap;lens-skipped lang-bash reason=cap;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"
out=$(bash "$ROUTE" plan.md --final "$BASE" "$HEAD2")
check "default cap 4" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens test-quality;lens lang-bash;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"
out=$(DR_FORGE_LENS_CAP=0 bash "$ROUTE" plan.md --final "$BASE" "$HEAD2")
check "cap 0: lenses off" "$out" "lenses off"

# A4: per-task lenses.
out=$(bash "$ROUTE" plan.md --task 1); status=$?
check "task: exit 0" "$status" "0"
check "task: the named lenses, uncapped" "$(sed -E 's/ criteria=[^ ]*//' <<<"$out" | tr '\n' ';')" "lens security;lens lang-bash;"
out=$(bash "$ROUTE" plan.md --task 2); status=$?
check "task without a Lenses line: exit 0" "$status" "0"
check "task without a Lenses line: no output" "$out" ""
bash "$ROUTE" plan.md --task 3 >/dev/null 2>&1; check "task: an unknown lens id exits 2" "$?" "2"
bash "$ROUTE" plan.md --task 9 >/dev/null 2>&1; check "task: a missing task exits 2" "$?" "2"
bash "$ROUTE" plan.md >/dev/null 2>&1; check "usage: exit 2" "$?" "2"
{ printf 'Host: codex\n\n'; cat plan.md; } > codex.md
bash "$ROUTE" codex.md --task 1 >/dev/null 2>&1; check "a Codex-host plan exits 2" "$?" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/lens-route.test.sh`
Expected: FAIL (`final: exit 0` got `127`, the script does not exist).

- [ ] **Step 3: Write the script**

Create `plugins/dr-forge/scripts/lens-route` with exactly:

```bash
#!/usr/bin/env bash
# Print the specialist review lenses for a final review or a risk-3 task.
#
# A lens is criteria/lenses/<id>.md: defect patterns a judge reads as review
# lenses, with an Applies: line saying when the final review needs it. The
# selection lives here rather than in prose for the reason review-route gives:
# a rule a seat must follow is only reachable when a test can reach it.
#
# Usage: lens-route PLAN_FILE --final BASE HEAD
#        lens-route PLAN_FILE --task ID
# Output: lens <id> criteria=<path> seat=<seat> reason=<always|paths:<glob>|added>
#         lens-skipped <id> reason=cap      (--final, past the lensCap setting)
#         lenses off                        (--final, lensCap 0)
#         lens <id> criteria=<path>         (--task, one per id on the task's **Lenses:** line)
# Exit: 0 routed, also when no lens applies; 2 usage error, a missing plan or
# task, an unknown lens id, or a Host: codex plan.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/plan.sh"
. "$HERE/lib/forge-env.sh"
LENSES="$(cd "$HERE/../criteria/lenses" 2>/dev/null && pwd)"
SEAT=dr-forge:judge-sonnet-high

die() { printf 'lens-route: %s\n' "$1" >&2; exit 2; }
usage() { die "usage: lens-route PLAN_FILE --final BASE HEAD | --task ID"; }

[ $# -ge 2 ] || usage
[ -n "$LENSES" ] || die "no criteria/lenses directory next to this script"
plan=$(plan_locate "$1"); shift
[ -f "$plan" ] || die "no such plan file: $plan"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
src="$TMP/plan.md"
plan_apply_amendments "$plan" "$(plan_amendments_file "$plan")" > "$src" 2>/dev/null \
  || die "an amendment does not apply; run plan-lint"
header=$(plan_header "$src")
if grep -qE '^(\*\*)?Host:(\*\*)?[ \t]+codex[ \t]*$' <<<"$header"; then
  die "a Host: codex plan routes reviews through reference/native-codex.md"
fi

# lens_order — every lens id, highest priority first: three fixed leaders, the
# language lenses alphabetically, two fixed trailers, then any other lens.
lens_order() {
  local all id
  all=$(for f in "$LENSES"/*.md; do [ -e "$f" ] && basename "$f" .md; done | LC_ALL=C sort)
  for id in security silent-failures test-quality; do grep -qxF "$id" <<<"$all" && echo "$id"; done
  grep -E '^lang-' <<<"$all"
  for id in type-design docs-comments; do grep -qxF "$id" <<<"$all" && echo "$id"; done
  grep -vxE 'security|silent-failures|test-quality|type-design|docs-comments|lang-.*' <<<"$all"
}

# lens_match ID — print the first Applies clause that matches the change set
# ($changed: file names; $added: added lines without their +); status 1 when
# none does. Globs are bash case patterns, so * crosses /.
lens_match() {
  local value clause kind arg glob f
  value=$(sed -n 's/^Applies: //p' "$LENSES/$1.md" | head -n 1 | tr -d '\r')
  [ -n "$value" ] || return 1
  while IFS= read -r clause; do
    clause=${clause#"${clause%%[![:space:]]*}"}
    clause=${clause%"${clause##*[![:space:]]}"}
    kind=${clause%% *}
    arg=${clause#"$kind"}; arg=${arg# }
    case $kind in
      always) echo always; return 0 ;;
      paths)
        set -f
        for glob in $arg; do
          while IFS= read -r f; do
            [ -n "$f" ] || continue
            # shellcheck disable=SC2254
            case $f in $glob) set +f; echo "paths:$glob"; return 0 ;; esac
          done <<<"$changed"
        done
        set +f ;;
      added)
        if grep -qE -- "$arg" <<<"$added"; then echo added; return 0; fi ;;
    esac
  done < <(sed 's/ ; /\n/g' <<<"$value")
  return 1
}

case $1 in
  --final)
    [ $# -eq 3 ] || usage
    base=$2 head=$3
    git rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "bad BASE: $base"
    git rev-parse --verify --quiet "$head^{commit}" >/dev/null || die "bad HEAD: $head"
    cap=${DR_FORGE_LENS_CAP:-$(forge_setting lensCap 4)}
    [[ "$cap" =~ ^[0-9]$ ]] || cap=4
    if [ "$cap" -eq 0 ]; then echo "lenses off"; exit 0; fi
    changed=$(git diff --name-only "$base..$head")
    added=$(git diff -U0 "$base..$head" | awk '/^\+\+\+ /{next} /^\+/{print substr($0, 2)}')
    n=0
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      reason=$(lens_match "$id") || continue
      if [ "$n" -lt "$cap" ]; then
        printf 'lens %s criteria=%s seat=%s reason=%s\n' "$id" "$LENSES/$id.md" "$SEAT" "$reason"
        n=$((n + 1))
      else
        printf 'lens-skipped %s reason=cap\n' "$id"
      fi
    done <<<"$(lens_order)"
    exit 0 ;;
  --task)
    [ $# -eq 2 ] || usage
    id=$2
    [[ "$id" =~ ^[0-9]+$ ]] || die "not a task id: $id"
    text=$(plan_task_text "$src" "$id") || die "no Task $id in the plan"
    line=$(plan_lines Lenses <<<"$text" | head -n 1)
    [ -n "$line" ] || exit 0
    ids=$(sed 's/^\*\*Lenses:\*\*//' <<<"$line" | tr ',' ' ')
    for lid in $ids; do [ -f "$LENSES/$lid.md" ] || die "unknown lens id: $lid"; done
    for lid in $ids; do printf 'lens %s criteria=%s\n' "$lid" "$LENSES/$lid.md"; done
    exit 0 ;;
  *) usage ;;
esac
```

Then run `chmod +x plugins/dr-forge/scripts/lens-route` and `git update-index --chmod=+x` after adding it (Step 5).

- [ ] **Step 4: Run test to verify it passes**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/lens-route.test.sh`
Expected: PASS, ending `17 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lens-route plugins/dr-forge/tests/lens-route.test.sh
git update-index --chmod=+x plugins/dr-forge/scripts/lens-route
git commit -m "feat(dr-forge): add lens-route"
```

### Task 8: Lenses plan line and plan-lint checks

**Files:**
- Modify: `plugins/dr-forge/scripts/plan-lint` (the per-task loop, after the axis check)
- Modify: `plugins/dr-forge/skills/writing-plans/SKILL.md` (Assign an implementer, step 5)
- Test: `plugins/dr-forge/tests/plan-lint.test.sh`

**Interfaces:**
- Consumes: C2 (lens file names).
- Produces: C5.

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

In `plugins/dr-forge/tests/plan-lint.test.sh`, insert directly above its final `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line:

```bash
# --- Lenses lines ---
variant lens-low.md 's/^(\*\*Approach:\*\* inline - skip 2: follows the pattern)$/\1\n**Lenses:** security/'
lint lens-low.md
has "a Lenses line below risk 3 is an error" "$out" "ERROR Task 2: a **Lenses:** line needs risk 3 (risk is 2)"
variant lens-bad.md 's/risk 2 = 4$/risk 3 = 5/; s/^(\*\*Approach:\*\* inline - skip 2: follows the pattern)$/\1\n**Lenses:** security, nope/'
lint lens-bad.md
has "an unknown lens id is an error" "$out" "ERROR Task 2: **Lenses:** names no lens file: nope"
lacks "a known lens id is not flagged" "$out" "names no lens file: security"
lacks "risk 3 takes a Lenses line" "$out" "a **Lenses:** line needs risk 3"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/plan-lint.test.sh`
Expected: FAIL on `a Lenses line below risk 3 is an error` and `an unknown lens id is an error`.

- [ ] **Step 3: Add the checks and the guidance**

In `plugins/dr-forge/scripts/plan-lint`, find this block in the per-task loop:

```bash
  for v in "$a" "$b" "$c" "$d"; do
    [ "$v" -le 3 ] || { say ERROR "$where" "each axis must be 0-3"; break; }
  done
```

and insert directly below it:

```bash
  # A Lenses line names review lenses for a risk-3 task's review seat; below
  # risk 3 no seat reads it, so it would be a silent no-op.
  lenses=$(line Lenses)
  if [ -n "$lenses" ]; then
    [ "$d" -eq 3 ] || say ERROR "$where" "a **Lenses:** line needs risk 3 (risk is $d)"
    for lid in $(sed 's/^\*\*Lenses:\*\*//' <<<"$lenses" | tr ',' ' '); do
      [ -f "$HERE/../criteria/lenses/$lid.md" ] || say ERROR "$where" "**Lenses:** names no lens file: $lid"
    done
  fi
```

In `plugins/dr-forge/skills/writing-plans/SKILL.md`, replace:

```markdown
   - `**Approach:**` — only when the task involved an approach decision:
     `inline`, `advisor`, or `best-of-3`, a dash, and a one-line reason; an
     `inline` reason cites a skip condition by number
```

with:

```markdown
   - `**Approach:**` — only when the task involved an approach decision:
     `inline`, `advisor`, or `best-of-3`, a dash, and a one-line reason; an
     `inline` reason cites a skip condition by number
   - `**Lenses:**` — only on a task scored risk 3, and optional there: the
     lens ids under `criteria/lenses/` that match why the task is risky,
     comma-separated, for example `security` for an authentication change. The
     task's Claude review seat reads them as defect patterns; `plan-lint`
     rejects the line below risk 3 and an id with no lens file.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/plan-lint.test.sh`
Expected: PASS, ending with `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/plan-lint plugins/dr-forge/skills/writing-plans/SKILL.md plugins/dr-forge/tests/plan-lint.test.sh
git commit -m "feat(dr-forge): lint Lenses lines on plan tasks"
```

### Task 9: acceptance-ambiguous ruling kind

**Files:**
- Modify: `plugins/dr-forge/scripts/review-route:192` (the ruling-kind `case`)
- Modify: `plugins/dr-forge/skills/subagent-driven-development/references/ruling-prompt.md` (Verdicts and item kinds)
- Test: `plugins/dr-forge/tests/review-route.test.sh`

**Interfaces:**
- Produces: C6.

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

In `plugins/dr-forge/tests/review-route.test.sh`, insert directly above its final `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line:

```bash
out=$(bash "$ROUTE" "$TMP/round.md" --ruling acceptance-ambiguous 2>&1); status=$?
check "acceptance-ambiguous: exit 0" "$status" "0"
check "acceptance-ambiguous goes to the ruling seat" "$out" \
  "review-seat ruling=acceptance-ambiguous tasks=plan primary=dr-forge:judge-opus fallback=- reason=routine"
present "ruling prompt: the REWORD verdict" "$P/skills/subagent-driven-development/references/ruling-prompt.md" \
  'REWORD: the spec statement is what is wrong'
present "ruling prompt: the kind" "$P/skills/subagent-driven-development/references/ruling-prompt.md" \
  '- acceptance-ambiguous: the final review'"'"'s QA seat could not test a spec'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/review-route.test.sh`
Expected: FAIL on the four new checks (`acceptance-ambiguous: exit 0` got `2`).

- [ ] **Step 3: Add the kind**

In `plugins/dr-forge/scripts/review-route`, replace:

```bash
      final-residual) ;;
```

with:

```bash
      final-residual|acceptance-ambiguous) ;;
```

In `plugins/dr-forge/skills/subagent-driven-development/references/ruling-prompt.md`, replace:

```markdown
        Verdict: CONFIRMED-GAP | PARK | AMEND | BLOCKED
```

with:

```markdown
        Verdict: CONFIRMED-GAP | PARK | AMEND | REWORD | BLOCKED
```

Directly above the line `    - AMEND: the plan's text is what is wrong. After the Ruling line, write`, insert:

```markdown
    - REWORD: the spec statement is what is wrong (acceptance-ambiguous items
      only). After the Ruling line, write one line at column 0,
      `New statement: <the statement, reworded so it reads one way>`. PARK on
      an acceptance-ambiguous item defers the statement to the register.
```

Directly below the two lines

```markdown
    - final-residual: findings still open after the final review's one fix
      wave.
```

insert:

```markdown
    - acceptance-ambiguous: the final review's QA seat could not test a spec
      acceptance statement because it reads two ways; the item names both
      readings. REWORD picks one; PARK defers the statement.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/review-route.test.sh`
Expected: PASS, ending with `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/review-route plugins/dr-forge/skills/subagent-driven-development/references/ruling-prompt.md plugins/dr-forge/tests/review-route.test.sh
git commit -m "feat(dr-forge): add the acceptance-ambiguous ruling"
```

### Task 10: Final review step 0.5, lens dispatch and ledger lines

**Files:**
- Modify: `plugins/dr-forge/reference/final-review.md` (The review; Fixing what it finds)
- Modify: `plugins/dr-forge/skills/subagent-driven-development/SKILL.md` (The Ledger grammar and Plan state)
- Modify: `plugins/dr-forge/skills/executing-plans/SKILL.md` (ledger grammar)
- Test: `plugins/dr-forge/tests/process-roles.test.sh`

**Interfaces:**
- Consumes: C3, C6, C7, C8, C10, C12.
- Produces: final-review step 0.5 and the lens dispatch that Tasks 11 and 12 refer to.

**Items:** 2, 3

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing test**

Insert above the summary `printf` line of `plugins/dr-forge/tests/process-roles.test.sh`:

```bash
FR="$P/reference/final-review.md"
at() { grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1; }
g=$(at "$FR" '0. **Gates.**'); q=$(at "$FR" '0.5 **Acceptance QA.**')
k=$(at "$FR" 'Run `scripts/review-package PLAN_FILE MERGE_BASE HEAD`'); l=$(at "$FR" 'scripts/lens-route PLAN_FILE --final MERGE_BASE HEAD')
check "final review: gates, QA, package, lenses in order" \
  "$([ -n "$g" ] && [ -n "$q" ] && [ -n "$k" ] && [ -n "$l" ] && [ "$g" -lt "$q" ] && [ "$q" -lt "$k" ] && [ "$k" -lt "$l" ] && echo yes || echo no)" "yes"
names "final review: QA skipped when complete" "$FR" 'the ledger already holds `Acceptance QA: complete`'
names "final review: recovery from the report" "$FR" '`<workspace>/acceptance-report.md` exists, read it'
names "final review: recovery re-dispatch" "$FR" 'otherwise re-dispatch once with `[MODE]` `rerun`'
names "final review: leftover worktree" "$FR" 'git worktree remove --force <workspace>/qa-mutation'
names "final review: ambiguous goes to the ruling seat" "$FR" '`scripts/review-route PLAN_FILE --ruling acceptance-ambiguous`'
names "final review: lens replies as files" "$FR" 'save each reply to `<workspace>/lens-<id>.md`'
names "final review: residual acceptance failure" "$FR" 'is the one edit allowed on an acceptance test'
for f in "$P/skills/subagent-driven-development/SKILL.md" "$P/skills/executing-plans/SKILL.md"; do
  s=$(basename "$(dirname "$f")")
  names "$s: dispatched line" "$f" 'Acceptance QA: dispatched (base <sha7>)'
  names "$s: complete line" "$f" 'Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo'
  names "$s: recovery points at step 0.5" "$f" '`Acceptance QA:` lines are written by'
done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/process-roles.test.sh`
Expected: FAIL on the fourteen new checks.

- [ ] **Step 3: Edit final-review.md and both ledgers**

In `plugins/dr-forge/reference/final-review.md`, replace:

```markdown
Run `scripts/review-package PLAN_FILE MERGE_BASE HEAD` (MERGE_BASE is the commit
the branch started from, for example `git merge-base main HEAD`) and include the
printed path in each dispatch, so a reviewer reads one file instead of
re-deriving the branch diff with git commands.
```

with:

```markdown
MERGE_BASE is the commit the branch started from, for example
`git merge-base main HEAD`. Steps 0 and 0.5 run first; step 1 builds the
review package, so the package includes the acceptance tests step 0.5 commits.
```

Replace:

```markdown
   project has no manifest, say so in one line and go to step 1.
1. **Claude review.** Run `scripts/review-route PLAN_FILE --final` and dispatch
```

with:

````markdown
   project has no manifest, say so in one line and go to step 0.5.

0.5 **Acceptance QA.** Skip this step, saying so in one line, when the plan's
   spec has no `A<n>` statement tagged `test`, or when the ledger already holds `Acceptance QA: complete`. When the ledger holds
   `Acceptance QA: dispatched` with no `complete` line, QA was cut off: when
   `<workspace>/acceptance-report.md` exists, read it and go to (c) below;
   otherwise re-dispatch once with `[MODE]` `rerun`, under (b)'s timer, then
   continue at (c); it counts as this review's one re-dispatch. Otherwise:

   (a) Append `Acceptance QA: dispatched (base <sha7>)` (the HEAD you hand QA).

   (b) Dispatch `dr-forge:impl-sonnet-high` (on a Codex host, the native
      implementer `gpt-6.1-sol / high`) with
      [acceptance-qa.md](acceptance-qa.md) and its placeholders: the spec,
      its `test` statements verbatim, MERGE_BASE, HEAD, the test command
      `gates.md` declares or `none`, the workspace, and `[MODE]` `first`.
      Dispatch it in the background and, in the same message, start a
      background timer, `sleep 2700` (45 minutes), as
      [executor-lane.md](executor-lane.md) arms its timers. When the timer
      finishes first, stop the QA agent (TaskStop on Claude Code; on Codex,
      close the child) and record `cannot-test: timeout` for every statement
      its report does not cover. When QA finishes first, stop the timer.

   (c) When it returns, or on recovery, run `git worktree list`. A QA worktree still listed is
      removed with `git worktree remove --force <workspace>/qa-mutation` and
      `git worktree prune`, and logged as
      `Ruling: QA worktree removed — it held only the throwaway break — none`.
   (d) Read the report and act on each row:
      - `fail`, `flaky`, mutation `green`, or `cannot-test: no-surface`: a
        finding added to the Claude list (step 1), written
        `[qa] A<n>: <result> — <test>`.
      - `cannot-test: ambiguous`: an item for
        `scripts/review-route PLAN_FILE --ruling acceptance-ambiguous`, sent
        with [ruling-prompt.md](../skills/subagent-driven-development/references/ruling-prompt.md).
        `REWORD`: replace the statement's text in the spec with the
        `New statement:` line, commit the spec, and re-dispatch QA with
        `[MODE]` `reword A<n>[, A<m>]`; every ambiguous statement of one
        report shares that single re-dispatch. `PARK`: run
        `scripts/register add <register> "A<n>: <statement>" --state deferred --note "<the ruling>"`
        and change the spec line to `A<n>. deferred — register row <id>`.
        In an auto run a missing ruling follows
        [auto-run.md](auto-run.md) §Rulings.
      - `cannot-test: timeout`: no finding; it is reported, and it keeps the
        branch at an auto run's finish.
      - `demo — not executed`: no finding; finishing lists it.
   (e) Append `Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo`,
      counted from the final report.

   QA is re-dispatched at most once per final review, the recovery
   re-dispatch included.

1. **Claude review.** Run `scripts/review-package PLAN_FILE MERGE_BASE HEAD`
   and include the printed path in each dispatch below, so a reviewer reads
   one file instead of re-deriving the branch diff with git commands.

   **Lenses.** Run `scripts/lens-route PLAN_FILE --final MERGE_BASE HEAD`. In
   the same message as the Claude review, dispatch each printed `seat` with
   the prompt below, so they run in parallel; on a Codex host, a native judge
   at rank 8 or above. Then save each reply to `<workspace>/lens-<id>.md`:
   the Claude list for step 3 is the Claude review's findings plus every lens
   finding, tagged `[lens:<id>]`, and the dedupe judge and the fixer receive
   the lens file paths. `lens-skipped` lines and `lenses off` dispatch
   nothing; step 4 names them. Lens seats are read-only, so a recovery may
   dispatch them again.

   ```
   You are a specialist reviewer. Read the lens at <criteria path>: its
   criteria are defect patterns, not a rubric, so do not score them. Review
   the branch diff in <package path> against the spec <spec path> and the
   plan <plan path>, and report each hit, most severe first, as
   `### <Critical|Important|Minor>: [lens:<id>] <one-line claim>` followed by
   at most three lines: file:line, what fails, and the fix. Report at most ten
   findings. With none, write `No findings.` and stop.
   ```

   Then run `scripts/review-route PLAN_FILE --final` and dispatch
````

(The replaced text ended with `dispatch`, and the original sentence continues on the next line unchanged: `the \`primary\` it prints: ...`.)

In the same file, step 4, replace:

```markdown
4. **Report.** With two lists: confirmed findings ranked most severe first, then
```

with:

```markdown
4. **Report.** Name the lenses that ran, each `lens-skipped` lens (or
   `lenses off`), and the `Acceptance QA: complete` counts. With two lists:
   confirmed findings ranked most severe first, then
```

In the same file, under `## Fixing what it finds`, directly above the paragraph that begins `There is no second fix wave.`, insert:

```markdown
**Acceptance tests.** The fixer never weakens a test whose name starts with
`A<n>:`; to dispute one it records `REJECTED: A<n> — <evidence>`, and the
scoped re-review decides. The fix wave's verification runs the acceptance file
again. A `fail` or `flaky` acceptance test that survives the fix wave (the
rejection upheld, or the ruling seat parking it) is the one edit allowed on an acceptance test:
mark that test skipped with a reason naming its register row, commit it, and
run `scripts/register add <register> "A<n>: <statement>" --state deferred --note "<the upheld rejection>"`,
so finishing's test run is green and the statement is not lost.
```

In `plugins/dr-forge/skills/subagent-driven-development/SKILL.md`, in The Ledger's grammar block, replace:

```text
Final fix: implementer <agent> (assigned; base <sha7>)
Final review: clean (commits <merge-base7>..<head7>[, K parked])
```

with:

```text
Acceptance QA: dispatched (base <sha7>)
Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo
Final fix: implementer <agent> (assigned; base <sha7>)
Final review: clean (commits <merge-base7>..<head7>[, K parked])
```

and directly below that block's closing fence, before the bullet that begins `- After each \`complete\` and \`fix round\` line`, insert:

```markdown
- `Acceptance QA:` lines are written by
  [final-review.md](../../reference/final-review.md) step 0.5, which also
  says what to do with a `dispatched` line that has no `complete` line.
```

In the same file, replace:

```markdown
**Plan state.** Every task complete and no `Final review:` line: go to Final
Review.
```

with:

```markdown
**Plan state.** Every task complete and no `Final review:` line: go to Final
Review; an `Acceptance QA: dispatched` line with no `complete` line resumes at
its step 0.5.
```

In `plugins/dr-forge/skills/executing-plans/SKILL.md`, in its ledger grammar block, replace:

```text
Ruling: <what> — <why> — <cost if wrong>
Final review: clean (commits <merge-base7>..<head7>[, K parked])
```

with:

```text
Ruling: <what> — <why> — <cost if wrong>
Acceptance QA: dispatched (base <sha7>)
Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo
Final review: clean (commits <merge-base7>..<head7>[, K parked])
```

and directly below that block's closing fence, before the bullet that begins `- After each \`complete\` and \`fix round\` line`, insert the same bullet as in subagent-driven-development:

```markdown
- `Acceptance QA:` lines are written by
  [final-review.md](../../reference/final-review.md) step 0.5, which also
  says what to do with a `dispatched` line that has no `complete` line.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/process-roles.test.sh; timeout 600 bash plugins/dr-forge/tests/auto-run-skills.test.sh; timeout 600 bash plugins/dr-forge/tests/inline-mode.test.sh`
Expected: all three PASS; process-roles ends `43 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/reference/final-review.md plugins/dr-forge/skills/subagent-driven-development/SKILL.md plugins/dr-forge/skills/executing-plans/SKILL.md plugins/dr-forge/tests/process-roles.test.sh
git commit -m "feat(dr-forge): run acceptance QA and lenses in review"
```

### Task 11: Reviewer prompts carry lenses and the A<n> question

**Files:**
- Modify: `plugins/dr-forge/reference/delegated-task.md` (§3 Review the task)
- Modify: `plugins/dr-forge/skills/subagent-driven-development/references/task-reviewer-prompt.md`
- Modify: `plugins/dr-forge/skills/subagent-driven-development/references/re-review-prompt.md` (Tests)
- Modify: `plugins/dr-forge/skills/requesting-code-review/SKILL.md`
- Modify: `plugins/dr-forge/skills/requesting-code-review/references/code-reviewer.md`
- Test: `plugins/dr-forge/tests/process-roles.test.sh`

**Interfaces:**
- Consumes: C3 (`--task` output), C5, C9.
- Produces: a link to `reference/native-codex.md` for Codex-host lens choice; that file gains its lens text in Task 13.

**Items:** 2, 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

Insert above the summary `printf` line of `plugins/dr-forge/tests/process-roles.test.sh`:

```bash
names "task review: lens-route per task" "$P/reference/delegated-task.md" 'run `scripts/lens-route PLAN_FILE --task <N>`'
TRP="$P/skills/subagent-driven-development/references/task-reviewer-prompt.md"
names "task reviewer: lens section" "$TRP" '## Lens Criteria'
names "task reviewer: lenses are not scored" "$TRP" 'do not score them, and do not add them to Verification Scores'
names "task reviewer: the placeholder" "$TRP" '`[LENS_FILES]` — OPTIONAL'
names "re-review: the A<n> question" "$P/skills/subagent-driven-development/references/re-review-prompt.md" \
  'still fail if the code violated statement A<n> of the spec?'
names "code reviewer: the A<n> question" "$P/skills/requesting-code-review/references/code-reviewer.md" \
  'would it fail if the code violated spec statement A<n>?'
names "requesting review: security lens" "$P/skills/requesting-code-review/SKILL.md" 'criteria/lenses/security.md'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/process-roles.test.sh`
Expected: FAIL on the seven new checks.

- [ ] **Step 3: Edit the five files**

In `plugins/dr-forge/reference/delegated-task.md`, directly above the bullet that begins `- **Reviewer inputs:** the brief file (it ends with the plan's Global`, insert:

```markdown
- **Lenses:** run `scripts/lens-route PLAN_FILE --task <N>`. For each `lens`
  line it prints, add its `criteria=` path to the judge seat's `[LENS_FILES]`;
  with none, delete that section of the prompt. A Codex seat gets no lens
  files: on a risk-3 task the Claude judge beside it reads them. On a
  `Host: codex` plan `lens-route` exits 2; choose the lenses as
  [native-codex.md](native-codex.md) says.
```

In `plugins/dr-forge/skills/subagent-driven-development/references/task-reviewer-prompt.md`, replace the line:

```markdown
    ## Second Pass: The Codex Review
```

with:

```markdown
    ## Lens Criteria

    [Include this section only when [LENS_FILES] names files. Delete it otherwise.]

    Read each lens file in [LENS_FILES]. Lens criteria are defect-pattern
    checks: report each hit as an issue tagged `[lens:<id>]` at your own
    severity; do not score them, and do not add them to Verification Scores.

    ## Second Pass: The Codex Review
```

and directly above the placeholder line that begins `- \`[BRIEF_FILE]\` — REQUIRED: the task brief file` (so the three-line `[PLUGIN_ROOT]` bullet above it stays whole), insert:

```markdown
- `[LENS_FILES]` — OPTIONAL: the `criteria=` paths `scripts/lens-route PLAN_FILE --task <N>` printed. Delete the Lens Criteria section when there are none.
```

In `plugins/dr-forge/skills/subagent-driven-development/references/re-review-prompt.md`, replace:

```markdown
    specific doubt that no existing run answers — and then a focused test,
    never a package-wide suite.
```

with:

```markdown
    specific doubt that no existing run answers — and then a focused test,
    never a package-wide suite.

    When the fix diff touches a test whose name starts with `A<n>:` (an
    acceptance test the final review's QA seat wrote), ask: would this test
    still fail if the code violated statement A<n> of the spec? A change that
    makes the answer no weakens the test: report it under New Breakage in the
    Fix Diff, even when the fix report argues for it.
```

In `plugins/dr-forge/skills/requesting-code-review/references/code-reviewer.md`, replace:

```markdown
    - All tests passing?
```

with:

```markdown
    - All tests passing?
    - For each test named `A<n>:` (an acceptance test): would it fail if the code violated spec statement A<n>?
```

In `plugins/dr-forge/skills/requesting-code-review/SKILL.md`, replace:

```markdown
- `[HEAD_SHA]` - Ending commit

**3. Act on feedback:**
```

with:

```markdown
- `[HEAD_SHA]` - Ending commit

**Security lens:** when the change touches authentication, secrets, input
parsing or shell command construction, add to the prompt: "Also read
`<plugin root>/criteria/lenses/security.md`. Its criteria are defect-pattern
checks: report each hit as an issue tagged `[lens:security]` at your own
severity; do not score them."

**3. Act on feedback:**
```

- [ ] **Step 4: Run test to verify it passes**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/process-roles.test.sh`
Expected: PASS, ending `50 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/reference/delegated-task.md plugins/dr-forge/skills/subagent-driven-development/references plugins/dr-forge/skills/requesting-code-review plugins/dr-forge/tests/process-roles.test.sh
git commit -m "feat(dr-forge): give reviewers lenses and A<n> checks"
```

### Task 12: Auto run and finishing rules

**Files:**
- Modify: `plugins/dr-forge/reference/auto-run.md` (The spec, Rulings, Finishing)
- Modify: `plugins/dr-forge/skills/finishing-a-development-branch/SKILL.md` (Auto run)
- Test: `plugins/dr-forge/tests/auto-run-skills.test.sh`

**Interfaces:**
- Consumes: C1, C3, C6, C7; the `## Critic findings` section (Task 4); step 0.5 (Task 10).

**Items:** 1, 2, 3, 4

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing test**

In `plugins/dr-forge/tests/auto-run-skills.test.sh`, insert directly above its final `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line:

```bash
names "auto-run.md: the critic runs before Fable" "$R" 'After your own self-review round and the architecture critic'
names "auto-run.md: a late statement goes up the ladder" "$R" 'is never asked: it goes up the ladder under Rulings'
names "auto-run.md: an undecided critic Blocker" "$R" '--note "critic Blocker unresolved"'
names "auto-run.md: a statement is deferred, not guessed" "$R" '**An acceptance statement in the spec phase:** the statement is deferred, not'
names "auto-run.md: QA ambiguity is parked" "$R" '**A QA `acceptance-ambiguous` item:** PARK it'
names "auto-run.md: QA ambiguity batches at once" "$R" 'A batch runs at once for a blocked task and for a QA'
names "auto-run.md: unverified acceptance keeps the branch" "$R" '`merge` also keeps the branch when the `Acceptance QA: complete` line reports any'
names "auto-run.md: failures keep the branch" "$R" '`fail`, `flaky` or `cannot-test`, or when the run added a deferred register row'
names "auto-run.md: the final message lists demos and lenses" "$R" 'every `demo` statement of the spec, every lens'
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
names "finishing: unverified acceptance keeps the branch" "$FIN" '`merge` also keeps when the `Acceptance QA: complete` line reports any'
names "finishing: the final message lists demos and lenses" "$FIN" 'every `demo` statement of the spec, every lens'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/auto-run-skills.test.sh`
Expected: FAIL on the eleven new checks.

- [ ] **Step 3: Edit auto-run.md and finishing**

In `plugins/dr-forge/reference/auto-run.md`, replace:

```markdown
After your own self-review round, dispatch `dr-forge:judge-fable` on the spec
```

with:

```markdown
After your own self-review round and the architecture critic
(dr-forge:brainstorming §Architecture critic), dispatch `dr-forge:judge-fable` on the spec
```

Replace:

```markdown
## Rulings

The ladder for anything you would have asked:
```

with:

```markdown
**Acceptance statements and critic findings in the spec phase:**

- A statement added or changed while writing the spec and rated below `high`
  is never asked: it goes up the ladder under Rulings. A seat ruling keeps it
  `high`; record the ruling with `scripts/auto-run ruling add`.
- Give Fable the spec's `## Critic findings` section with the spec; it checks
  each answer to a Blocker or High finding. A Blocker it leaves undecided after
  its rounds is added with
  `scripts/register add <register> "<the finding>" --state deferred --note "critic Blocker unresolved"`
  and marked `unresolved — row <id>` in `## Critic findings`. The run
  continues, and finishing keeps the branch.

## Rulings

The ladder for anything you would have asked:
```

Replace:

```markdown
  and add a deferred register row naming the choice.
```

with:

```markdown
  and add a deferred register row naming the choice.
- **An acceptance statement in the spec phase:** the statement is deferred, not
  guessed:
  `scripts/register add <register> "A<n>: <statement>" --state deferred --note "Fable gave no ruling"`,
  and its spec line becomes `A<n>. deferred — register row <id>`. It is the one
  spec choice that does not take the option listed first.
- **A QA `acceptance-ambiguous` item:** PARK it, as
  [final-review.md](final-review.md) step 0.5 says, and the final review
  continues.
```

Replace:

```markdown
A batch runs at once for a blocked task, and otherwise whenever the list is
```

with:

```markdown
A batch runs at once for a blocked task and for a QA `acceptance-ambiguous`
item, and otherwise whenever the list is
```

Replace:

```markdown
partial commits reach the base only after a person has looked at them. On a
```

with:

```markdown
partial commits reach the base only after a person has looked at them.
`merge` also keeps the branch when the `Acceptance QA: complete` line reports any
`fail`, `flaky` or `cannot-test`, or when the run added a deferred register row
whose Item begins `A<n>:` or whose Note is `critic Blocker unresolved`: an
acceptance statement that failed or went unverified reaches the base only after
a person has looked at it. On a
```

Replace:

```markdown
every `Ruling:` ledger line, every line of `scripts/auto-run ruling list` and
every deferred row the run added, and it runs `scripts/auto-run stop` before
```

with:

```markdown
every `Ruling:` ledger line, every line of `scripts/auto-run ruling list`,
every deferred row the run added, every `demo` statement of the spec, every lens
`scripts/lens-route PLAN_FILE --final <base> HEAD` prints as `lens-skipped`, and
it runs `scripts/auto-run stop` before
```

In `plugins/dr-forge/skills/finishing-a-development-branch/SKILL.md`, replace:

```markdown
  `Task <N>: complete (deferred by the auto run)` line, so a deferred task's
  partial commits never reach the base unreviewed.
```

with:

```markdown
  `Task <N>: complete (deferred by the auto run)` line, so a deferred task's
  partial commits never reach the base unreviewed. `merge` also keeps when the `Acceptance QA: complete` line reports any
  `fail`, `flaky` or `cannot-test`, or when the run added a deferred register
  row whose Item begins `A<n>:` or whose Note is `critic Blocker unresolved`.
```

Replace:

```markdown
  `scripts/auto-run ruling list`, and Step 7's final message lists every
  deferred row the run added to its register (`scripts/auto-run status` names
  it).
```

with:

```markdown
  `scripts/auto-run ruling list`, and Step 7's final message lists every
  deferred row the run added to its register (`scripts/auto-run status` names
  it), every `demo` statement of the spec, every lens
  `scripts/lens-route PLAN_FILE --final <base> HEAD` prints as `lens-skipped`.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/auto-run-skills.test.sh; timeout 600 bash plugins/dr-forge/tests/auto-run.test.sh`
Expected: both PASS, each ending with `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/reference/auto-run.md plugins/dr-forge/skills/finishing-a-development-branch/SKILL.md plugins/dr-forge/tests/auto-run-skills.test.sh
git commit -m "feat(dr-forge): keep auto runs unattended with QA"
```

### Task 13: Milestone evidence, security gate example and Codex seats

**Files:**
- Modify: `plugins/dr-forge/skills/closing-a-milestone/references/milestone-judge.md` (Method step 2)
- Modify: `plugins/dr-forge/skills/running-gates/references/gates-template.md` (end of file)
- Modify: `plugins/dr-forge/reference/native-codex.md` (end of Dispatch and review)
- Test: `plugins/dr-forge/tests/process-roles.test.sh`

**Interfaces:**
- Consumes: C9, C10.

**Items:** 2, 3

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Write the failing test**

Insert above the summary `printf` line of `plugins/dr-forge/tests/process-roles.test.sh`:

```bash
names "milestone judge: A<n> tests are evidence" "$P/skills/closing-a-milestone/references/milestone-judge.md" \
  'is evidenced by the committed test whose name starts with `A<n>:`'
names "gates template: claude-security example" "$P/skills/running-gates/references/gates-template.md" \
  'claude --agent claude-security:claude-security'
NC="$P/reference/native-codex.md"
names "codex: critic and lens seats" "$NC" 'The architecture critic and every review lens are native judges at rank 8'
names "codex: QA seat" "$NC" 'Acceptance QA is a native implementer at `gpt-6.1-sol / high`'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/process-roles.test.sh`
Expected: FAIL on the four new checks.

- [ ] **Step 3: Edit the three files**

In `plugins/dr-forge/skills/closing-a-milestone/references/milestone-judge.md`, replace:

```markdown
   or the gate output line that proves it. Read the code; do not trust names,
   commit messages or plan text.
```

with:

```markdown
   or the gate output line that proves it. Read the code; do not trust names,
   commit messages or plan text. An Acceptance cell citing spec statement
   `A<n>` is evidenced by the committed test whose name starts with `A<n>:` (or
   `a<n>_`) and the test or gate output that ran it; a statement tagged `demo`
   is `UNVERIFIABLE` unless a recorded note says a person observed it.
```

At the end of `plugins/dr-forge/skills/running-gates/references/gates-template.md`, append:

````markdown

```markdown
An optional gate for projects that install the official claude-security
plugin. Its documented launch is interactive
(`claude --agent claude-security:claude-security`); the headless `-p` form
below is unverified, so run it once by hand before relying on it.

## 5. Security scan of the branch
Command: `claude --agent claude-security:claude-security -p "Scan this branch's changes"`
Green: the scan reports no finding at High severity or above
Evidence: judgment
Applies: always
Why: the review lenses read a diff; this scan traces data flow across the codebase
```
````

At the end of the `## Dispatch and review` section of `plugins/dr-forge/reference/native-codex.md` (directly above the line `## Claude plans`), insert:

```markdown
The process roles take native seats too. The architecture critic and every review lens are native judges at rank 8 (Astra high) or above, with no
file writes. Acceptance QA is a native implementer at `gpt-6.1-sol / high`
(the `impl-sonnet-high` row), dispatched with
[acceptance-qa.md](acceptance-qa.md). `scripts/lens-route` exits 2 on a
`Host: codex` plan, as `review-route` does: pick the lenses by reading each
`criteria/lenses/*.md` `Applies:` line against the change set.

```

- [ ] **Step 4: Run tests to verify they pass**

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/process-roles.test.sh; timeout 600 bash plugins/dr-forge/tests/gates-manifest.test.sh`
Expected: both PASS; process-roles ends `54 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/skills/closing-a-milestone plugins/dr-forge/skills/running-gates plugins/dr-forge/reference/native-codex.md plugins/dr-forge/tests/process-roles.test.sh
git commit -m "docs(dr-forge): wire QA evidence and Codex seats"
```

### Task 14: Release 3.1.0 and full validation

**Files:**
- Modify: `plugins/dr-forge/.claude-plugin/plugin.json:5`
- Modify: `plugins/dr-forge/.codex-plugin/plugin.json:3`
- Modify: `plugins/dr-forge/tests/review-route.test.sh:597-598` (the manifest version pins)

**Interfaces:**
- Consumes: every earlier task.

**Items:** 1, 2, 3, 4

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing test**

In `plugins/dr-forge/tests/review-route.test.sh`, replace:

```bash
present "the Claude manifest is 3.0.0" "$P/.claude-plugin/plugin.json" '"version": "3.0.0"'
present "the Codex manifest is 3.0.0" "$P/.codex-plugin/plugin.json" '"version": "3.0.0"'
```

with:

```bash
present "the Claude manifest is 3.1.0" "$P/.claude-plugin/plugin.json" '"version": "3.1.0"'
present "the Codex manifest is 3.1.0" "$P/.codex-plugin/plugin.json" '"version": "3.1.0"'
```

Run: `unset CLAUDE_CONFIG_DIR; timeout 600 bash plugins/dr-forge/tests/review-route.test.sh`
Expected: FAIL on the two manifest checks only.

- [ ] **Step 2: Bump both manifests**

In both manifest files, change `"version": "3.0.0",` to `"version": "3.1.0",`.

- [ ] **Step 3: Run the repository validation**

Run from the repository root, one command at a time:

```bash
unset CLAUDE_CONFIG_DIR; timeout 600 node scripts/validate-repository.mjs
unset CLAUDE_CONFIG_DIR; timeout 3000 node scripts/test-all.mjs
timeout 300 /root/.local/bin/claude plugin validate .
timeout 300 /root/.local/bin/claude plugin validate plugins/dr-forge
timeout 600 /root/.local/bin/claude plugin test plugins/dr-forge
```

Expected: `validate-repository` passes; `test-all` reports every suite passing (including the new `process-roles`, `lens-route` and extended suites); both `plugin validate` runs pass; `plugin test` passes. Confirm with `ps` that no process these commands started is still running.

- [ ] **Step 4: Verify the versions**

Run: `grep -h '"version"' plugins/dr-forge/.claude-plugin/plugin.json plugins/dr-forge/.codex-plugin/plugin.json`
Expected: both lines read `"version": "3.1.0",`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/.claude-plugin/plugin.json plugins/dr-forge/.codex-plugin/plugin.json plugins/dr-forge/tests/review-route.test.sh
git commit -m "chore(dr-forge): release 3.1.0"
```
