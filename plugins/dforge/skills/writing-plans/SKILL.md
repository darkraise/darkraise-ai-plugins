---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context
for our codebase and questionable taste. Document everything they need to know:
which files to touch for each task, the interfaces it produces and consumes,
the tests that pin it, docs they might need to check, how to verify it. Give
them the whole plan as feature-slice tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset
or problem domain. Assume they don't know good test design very well. Small
models execute these plans literally: each task's implementer sees only that
task's text plus the header's Global Constraints and Contracts.

**Keep it minimal and checkable:** no speculative abstractions; each task is the
minimum that meets the spec; each task ends with a check that proves it.

**Announce at start:** "I'm using the writing-plans skill to create the
implementation plan."

**Context:** If working in an isolated worktree, it should have been created via
the `dforge:using-git-worktrees` skill at execution time.

**Save plans to:** `<docs>/plans/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

## Auto run

Read [auto-run-plan.md](references/auto-run-plan.md) before you write this plan when `scripts/auto-run status` exits 0.

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken
into sub-project specs during brainstorming. If it wasn't, suggest breaking this
into separate plans — one per subsystem. Each plan should produce working,
testable software on its own.
Under `autoRun=on` the spec covers the whole request by design: write one plan for it, never suggest a split,
and take a later change of scope through the ruling seat's AMEND path. That
holds on Claude Code; on a Codex host `on` behaves as `off`.

## File Structure

Before defining tasks, map out which files will be created or modified and what
each one is responsible for. This is where decomposition decisions get locked
in.

- Design units with clear boundaries and well-defined interfaces. Each file
  should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are
  more reliable when files are focused. Prefer smaller, focused files over large
  ones that do too much.
- Files that change together should live together. Split by responsibility, not
  by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large
  files, don't unilaterally restructure - but if a file you're modifying has
  grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce
self-contained changes that make sense independently.

**Walking skeleton:** for a greenfield system, Task 1 builds the thinnest
end-to-end path through every layer, with its test, before any layer is fleshed
out.

## Task Right-Sizing

A task is the smallest unit that carries its own test cycle and is worth a
fresh reviewer's gate. When drawing task boundaries: fold setup,
configuration, scaffolding, and documentation steps into the task whose
deliverable needs them; split only where a reviewer could meaningfully
reject one task while approving its neighbor. Each task ends with an
independently testable deliverable. A task is a feature slice: on a Claude
plan its code task carries no implementation code and is scored with spec 2
(Assign an implementer, step 1).

## Plan Document Header

**Every plan MUST start with this header.** Everything before the first
`### Task` heading is the header. Execution controllers read only the header
and one task at a time, and every task brief carries the header's Global
Constraints and Contracts.

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Spec:** [repository-relative path to the spec/design doc this plan implements]

**Execution:** [inline|subagent] — `claude --model <model> --effort <effort>` — [why]

**Parallelism:** [sequential — <why> | waves — <ranges, e.g. 1 | 2-4 | 5>] (see Parallel waves)

**Integration check:** [waves only: the command that proves a merged wave works, normally the full suite]

**Worktree setup:** [waves only: what a fresh worktree runs before its tests, or `none`]

**Wave check:** [waves only, optional: a faster command — a build and the fast unit suite, say — run after the waves the full check skips; omit the line when there is none]

**Program:** [only when the spec is one sub-project of a program design:
`<program spec path>` — sub-project <k> of <n> — next: <title of sub-project
k+1, copied from the program's decomposition>. On the final sub-project,
end with `— last` instead of `— next: …`. Omit the line otherwise, and
always when the spec is an epic on `<docs>/roadmap.md`: the roadmap
computes what comes next.]

## Global Constraints

[The spec's project-wide requirements — version floors, dependency limits,
naming and copy rules, platform requirements — one line each, with exact
values copied verbatim from the spec. Every task's requirements implicitly
include this section.]

## Contracts

[Every name, signature, file path, format or exit code that one task
produces and another consumes, stated once. Task Interfaces blocks cite this
section rather than restate it. Write `None` when no task consumes another's
output.]

## Assumptions (evidence)

[One bullet per assumption the plan relies on, each with its evidence: a
command and the date it ran, a `file:line`, or a documentation URL. An
assumption you could not verify reads `unverified — Task N verifies it`, and
Task N contains the verifying step. When the spec's riskiest assumption reads
`unverified — the plan's first task verifies it`, Task 1 is that verifying step.]

## Task index

1. [Task 1 title, identical to its heading]
2. [...]

---
```

Codex plans also carry `Host: codex` and `Routing policy: codex-v4` lines
([native-codex.md](../../reference/native-codex.md)), and their Execution line
names the native pair:
`**Execution:** <inline|subagent> — codex <model> / <effort> — <why>`.
That pair runs the main session for the whole plan. A subagent plan names
`codex gpt-6.1-sol / high`; an inline plan names the execution tier at its
highest weighted routing score. `scripts/plan-lint` warns on any other pair,
and errors on an inline pair below that score.

**Read the settings first, then choose the Execution line.**

Read [execution-line.md](references/execution-line.md) before you write the header's Execution line.

## Parallel waves

**Ask first.** Read the spec's `**Execution strategy:**` line. When the spec has
none — it predates the question, or there is no spec — ask your human partner
the question in dforge:brainstorming's
[design-phase.md](../brainstorming/references/design-phase.md) (Choosing the execution strategy)
before you draft any task, and wait for the answer; when the `executionStrategy`
setting is `sequential` or `parallel` (dforge:brainstorming §Settings; the
default is `parallel`), take that value and do not ask. On a Codex host do not ask:
the plan is sequential. Sequential writes
`**Parallelism:** sequential — <why>` and nothing below applies.

**Parallel leans the plan toward independence.** It does not lower any other
bar here — every task keeps its tests, its review and its Rule S — and it
never invents parallelism the work does not have:

1. **Draft the tasks as usual, then sort them into two groups.** Give every
   task a `**Depends on:**` line below its `**Interfaces:**` block (and its
   `**Items:**` line, when there is one): `none`, or the tasks whose output it
   consumes, as `Task 1, Task 3`. Then:
   - **alone** — a task that cannot share a wave (rule 4 below, or a file it
     cannot give up to another task);
   - **parallel** — every other task.

   Dependencies decide only the order. A task's depth is one more than the
   deepest task it depends on; a task that depends on nothing has depth 1.
   Parallel tasks of one depth that share no file form one wave (rule 5 caps
   its width); an alone task is a wave of its own at its depth. Number the
   tasks so that the waves run in depth order, each a run of consecutive task
   numbers. Tasks 1-2 depending on nothing, Tasks 3-5 on Task 1 or 2, and
   Task 6 on Tasks 3-5 give `waves — 1-2 | 3-5 | 6`. Every dependency sits in
   an earlier wave.
2. **Shared things go first.** A type, schema, config key or helper that
   several tasks use is created by a foundation task in an earlier wave, and
   recorded in Contracts, so that the tasks of a later wave consume a fixed
   name rather than inventing their own.
3. **No two tasks in a wave name the same file** in their `**Files:**` blocks —
   Create, Modify, Test or Delete. Registries, index files, route tables and
   shared fixtures have one owner.
4. **Some tasks always run alone in their wave:** a task with risk 3, a task
   carrying an `**Executor:**` line, and a task that touches a dependency
   manifest or lockfile (`package.json`, `Cargo.toml`, `go.mod`,
   `pyproject.toml`, and their lockfiles).
5. **Keep a wave to three tasks** unless more are trivially independent: at
   most three run at once, and a wider wave runs in parts.
6. **Say how the tests stay apart.** When tasks' tests could meet at run time
   — a port, a database, a fixed temporary path, global state — write in
   Global Constraints how each task's tests avoid it, or move the tasks to
   different waves.
7. **Write the header lines.** `**Parallelism:** waves — 1 | 2-4 | 5`
   lists the waves in order, a single task or an `A-B` range each, covering
   every task once. `**Integration check:**` names the command that proves a
   merged wave works together — normally the whole suite.
   `**Worktree setup:**` is what a fresh checkout needs before its tests run
   (`npm ci`, a code generator), or `none`.
   `**Wave check:**`, optional, names a faster command run after the waves
   `scripts/wave check-due` does not give the full check — the full
   Integration check runs after every third wave, any wave holding a risk-3
   task and the last wave; without a Wave check those waves rest on each
   task's own tests and a clean merge.
8. **The Execution line names `subagent`**, `claude --model sonnet --effort
   high`, whatever the heavy-task count: inline mode implements the tasks it
   does not delegate in the session itself, one after another, so it has
   nothing to run in parallel. `plan-lint`
   skips the majority-rule warning for a waves plan.

`plan-lint` checks the waves mechanically — ranges, dependencies, shared
files, the tasks that must run alone, the header lines — and the pre-flight
ruling seat checks every same-wave pair for coupling the file lists cannot
show. A wave the seat or the run doubts is run one task after another, which
is always correct; see [parallel-waves.md](../../reference/parallel-waves.md).
If a plan ends up with no wave of two or more tasks, say so and write
`**Parallelism:** sequential — no independent tasks`.

## Drafting the tasks

A plan of 1-8 tasks is drafted in the session: you have already read the
code it changes, and every drafter would read it again from nothing. For 9
or more, write the header yourself, through the Task index, and save it as
the plan file. Then split the index into slices of 3-4 consecutive tasks and
dispatch one `dforge:drafter-sonnet` per slice, every slice in one message,
with [drafter-prompt.md](references/drafter-prompt.md). Each dispatch names
the spec path, the plan path, the slice range, the files the slice changes
or its tests join, as far as your exploration found them, the slice path
(`<state>/drafts/<plan basename without .md>/tasks-A-B.md`) and the plugin
root, as the template's placeholders; paste nothing else.

- **Contracts settle what slices share.** A drafter that reports
  `NEEDS_CONTEXT` needs a contract: add it to the header and re-dispatch that
  slice. An amendment that changes an existing Contract, rather than adding
  one, re-dispatches every slice: a slice drafted against the old Contract is
  stale, and nothing downstream can tell.
- **Join without reading.** Once every slice reports `DONE`, run
  `scripts/draft-pack --join PLAN_FILE`. It appends the slices in task order
  and deletes them; on exit 3 it names the gap or overlap and leaves the plan
  unchanged. Then continue at Assign an implementer.
- **On a Codex host, draft every task in the session.**

## Task Structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Interfaces:**
- Consumes: [what this task uses from earlier tasks — cite the Contracts entry]
- Produces: [what later tasks rely on — cite the Contracts entry. A task's
  implementer sees only their own task plus Global Constraints and
  Contracts; this block is how they learn which names they touch.]

**Items:** [only when a register covers this plan's spec: the register row
identifiers this task discharges, comma-separated, for example `4, 16`. When
more than one register covers it, name each row's register by its file's
basename, for example `core#4, review#16`. Omit the line otherwise.]

**UI/UX:** [only when the spec has a `## UI/UX contract` and the task's Files
match `scripts/ui-proof paths`: the contract IDs this task delivers, for
example `UI-2, UX-4`. Every `UI-` and `UX-` ID must reach some task; `OP-` IDs
are proven, not built. `plan-lint` checks both, and `task-brief` appends the
cited items to the brief (dforge:ui-ux).]

**Depends on:** [waves plans only: `none`, or the tasks whose output this one
consumes, for example `Task 1, Task 3`. Omit the line in a sequential plan.]

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Implement**

1. [The function or section to change, named by its signature, a heading or
   a quoted anchor line, never by a line number alone.]
2. [Its inputs and outputs, the exact strings and exit codes Contracts names,
   the edge cases, and what must not change.]

A task carries its files, its interfaces, the complete code of its tests, the
decisions it embodies, and the commands that verify it. Step 3 describes the
implementation; it carries no implementation code. Implementation code
appears only where no test can pin the behaviour: a configuration value, a
generated-file or migration command, or a fixed constant the spec names. A
test that still passes with `return <constant>` or with the implementation
deleted is a plan failure: `plan-review.md` scores it LOW.

On a Codex host, tasks keep the code-given shape: Step 3 is **Write the
implementation** and carries every line of it, because
[native-codex.md](../../reference/native-codex.md) keeps Rule S at
`reducible >= 4`.

Step 1's test sits at the lowest layer that can fail for the task's change. Plan
an end-to-end test only for a new user journey, never for an edge case a unit or
integration test reaches, and add a variant of an existing test as a row in its
table, not as a new test. Suites grown one task at a time otherwise end up
dforge:test-simplifier's job.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## Assign an implementer to every task

Read [assignment-procedure.md](references/assignment-procedure.md) before you score the tasks or write their assignment lines.

## Assign the register rows

Read [register-rows.md](references/register-rows.md) before you tie register rows to the plan's tasks.

## No Placeholders

Every step must contain the actual content an engineer needs. These are
**plan failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the test code or the description — the engineer
  may be reading tasks out of order)
- Tests that describe behaviour without asserting it (every test step carries
  its complete test code)
- References to types, functions, or methods not defined in any task

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the
plan against it. This round is required, and it is yours: run the checklist
once, never through a subagent. The plan review under Lint and Review comes
after it and does not replace it.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point
to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags — any of the patterns
from the "No Placeholders" section above. Fix them.

**3. Contracts:** Every cross-task name appears in Contracts, and every task
uses it exactly as stated there. A function called `clearLayers()` in Task 3 but
`clearFullLayers()` in Task 7 is a bug.

**3a. Waves (waves plans only):** Every `**Depends on:**` line names every task
whose output the task consumes, including through Contracts; a missing
dependency is the one waves error `plan-lint` cannot see.

**4. Lint:** Run the checker under Lint and Review.

If you find issues, fix them inline. If you find a spec requirement with no
task, add the task. Once `plan-lint` reports `0 errors`, post
`Self-review (round 1 of 1):` with one line per item (clean, or what you fixed)
before the first plan-review round. Do not re-review after fixing, and fixes a
plan-review round asks for do not start another round.
A revision your human partner asks for gets one new round.

## Lint and Review

Read [lint-and-review.md](references/lint-and-review.md) before you lint the plan or dispatch a plan review round.

## Execution Handoff

Read [execution-handoff.md](references/execution-handoff.md) before you end the planning session.
