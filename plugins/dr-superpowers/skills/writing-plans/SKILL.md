---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well. Small models execute these plans literally: each task's implementer sees only that task's text plus the header's Global Constraints and Contracts.

**Keep it minimal and checkable:** no speculative abstractions; each task is the minimum that meets the spec; each task ends with a check that proves it.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** If working in an isolated worktree, it should have been created via the `dr-superpowers:using-git-worktrees` skill at execution time.

**Save plans to:** `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure - but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

**Walking skeleton:** for a greenfield system, Task 1 builds the thinnest end-to-end path through every layer, with its test, before any layer is fleshed out.

## Task Right-Sizing

A task is the smallest unit that carries its own test cycle and is worth a
fresh reviewer's gate. When drawing task boundaries: fold setup,
configuration, scaffolding, and documentation steps into the task whose
deliverable needs them; split only where a reviewer could meaningfully
reject one task while approving its neighbor. Each task ends with an
independently testable deliverable.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement the minimal code to make the test pass" - step
- "Run the tests and make sure they pass" - step
- "Commit" - step

## Plan Document Header

**Every plan MUST start with this header.** Everything before the first
`### Task` heading is the header. Execution controllers read only the header
and one task at a time, and every task brief carries the header's Global
Constraints and Contracts.

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Spec:** [repository-relative path to the spec/design doc this plan implements]

**Execution:** [inline|subagent] — `claude --model <model> --effort <effort>` — [why]

**Program:** [only when the spec is one sub-project of a program design:
`<program spec path>` — sub-project <k> of <n> — next: <title of sub-project
k+1, copied from the program's decomposition>. On the final sub-project,
end with `— last` instead of `— next: …`. Omit the line otherwise.]

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
Task N contains the verifying step.]

## Task index

1. [Task 1 title, identical to its heading]
2. [...]

---
```

Codex plans also carry `Host: codex` and `Routing policy: codex-v2` lines
([native-codex.md](../../reference/native-codex.md)), and their Execution line
names the native pair: `**Execution:** <inline|subagent> — codex <model> / <effort> — <why>`.

**Choosing the Execution line.** The plan decides its execution mode:

- `inline` when every task's total is 3 or less and no task is at risk 3 —
  the default then: `claude --model sonnet --effort <e>`, where `<e>` is the
  effort of the highest-scoring task's assigned tier (`impl-haiku` counts as
  `low`).
- Otherwise `subagent`: `claude --model sonnet --effort high`. The controller
  owns no judgment calls — the ruling seat does — so it needs no stronger
  model.
- Your human partner may override the line; `plan-lint` checks its grammar and
  the inline rule.

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

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

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

Every task records which implementer runs it, so the choice is a property of
the plan rather than a judgment made from memory at dispatch time. Do this
after the tasks are drafted and before the plan is saved. Retrofitting an
existing plan is the same process: read it, resolve names written under older
plugin prefixes with [legacy-names.md](../../reference/legacy-names.md) (a name
outside that table: ask), score each task, and add the lines.

**Codex host:** follow [native-codex.md](../../reference/native-codex.md) — its
`codex-v2` selector, plan headers, assignment-source fields, and conversion
rules replace the Claude table, fleet, and external CLI lane below. Honor the
user's inline or delegation preference on either host.

1. **Score** each task on the four axes in
   [ladder.md](../../reference/ladder.md) — files, spec completeness,
   coupling, risk. Never restate its tables or work from memory. Score the
   task as its brief will carry it — the task text plus the header's Global
   Constraints and Contracts: if those contain the complete code and exact
   signatures, spec completeness is 0. Count file shapes, not file instances.
2. **Apply Rule S before the table.** If `files + spec + coupling >= 4`, split
   the task where a reviewer could reject one half while approving the other,
   and re-score both halves. If `spec = 3`, the approach is undecided: settle
   it with dr-superpowers:selecting-approaches, rewrite the task with the
   decision in its steps, and re-score. Never answer a reducible axis with a
   bigger model.
3. **Assign** from the assignment table, which the total indexes directly.
   Never assign a reserve agent — any `xhigh` or `max` effort, any Fable
   tier. Only a human edit puts one in a plan.
4. **Offer an external executor** once per plan and apply the lane gate — see
   [external-executor.md](../../reference/external-executor.md) §Planning. If
   no executor is usable, ask nothing.
5. **Write the lines** directly below the task's `**Interfaces:**` block, in
   this order:
   - `**Implementer:**` — always; the fully qualified agent, for example
     `dr-superpowers:impl-sonnet-medium`
   - `**Executor:**` — only when the lane gate passed, for example
     `codex gpt-5.5 / medium`
   - `**Evaluation:**` — always, for example
     `files 0 - spec 1 - coupling 1 - risk 0 = 2`
   - `**Approach:**` — only when the task involved an approach decision:
     `inline`, `advisor`, or `best-of-3`, a dash, and a one-line reason; an
     `inline` reason cites a skip condition by number

   ```markdown
   **Implementer:** dr-superpowers:impl-opus-medium
   **Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5
   **Approach:** inline - skip 2: follows the existing exporter pattern
   ```

6. **Keep the heading form** `### Task N: <name>`: `scripts/task-brief` finds a
   task by a heading that begins with `Task <N>`.

A human may edit any `**Implementer:**` line by hand;
dr-superpowers:subagent-driven-development obeys it and never recomputes.
Leave the `**Evaluation:**` line in place — the gap between the score and the
choice is the interesting part. A hand edit that breaks a checked rule — a
reserve tier, a kept `spec = 3`, a table mismatch — carries an
`**Override:** <reason>` line below the Evaluation line, and `plan-lint` then
reports it as a warning. Never write an Override line yourself. Under
dr-superpowers:executing-plans the lines are inert.
[assigning-implementers.md](references/assigning-implementers.md) explains why
each of these rules exists.

## No Placeholders

Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
- Steps that describe what to do without showing how (code blocks required for code steps)
- References to types, functions, or methods not defined in any task

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. This is a checklist you run yourself — not a subagent dispatch.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags — any of the patterns from the "No Placeholders" section above. Fix them.

**3. Contracts:** Every cross-task name appears in Contracts, and every task uses it exactly as stated there. A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

**4. Lint:** Run the checker under Lint and Review.

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Lint and Review

1. **Lint.** Run `scripts/plan-lint PLAN_FILE`, from the plugin root (two
   levels above this skill's directory), until it reports `0 errors`. Fix each
   WARN, or explain it in one line of the plan's Assumptions. The checker
   covers the header sections, the task headings and index, the Execution
   line, placeholders, and every task's assignment lines.
2. **Review.** Write the lint output to the plan's workspace:
   `scripts/plan-lint PLAN_FILE > <workspace>/plan-lint.txt`, where
   `<workspace>` is the directory `scripts/sdd-workspace PLAN_FILE` prints.
   Dispatch the judge with
   [plan-reviewer-prompt.md](references/plan-reviewer-prompt.md). It scores
   executability, coherence, coverage and assumptions (1-20) against
   [plan-review.md](../../criteria/plan-review.md) and lists findings.
3. **Fix and repeat.** Any score of 8 or below, or any Critical or Important
   finding: fix the plan, re-lint, and dispatch a fresh full review. At most 3
   review rounds; after the third, show the remaining findings to your human
   partner. A borderline score (9-13) gets a one-line decision in the plan's
   Assumptions.
4. **Record.** Only now, add the header line
   `**Plan review:** <YYYY-MM-DD> — <judge agent> — executability e / coherence c / coverage v / assumptions a (round r)`
   below the `**Program:**` line (below `**Execution:**` when there is no
   Program line). The header template deliberately omits it, so `plan-lint`
   warns until the review has run.

## Execution Handoff

A saved, reviewed plan is a hard stop: execution starts in a fresh session.
Invoke dr-superpowers:handoff. It commits the plan and the spec, writes
`.superpowers/handoff/latest.md`, runs `scripts/next-step PLAN_FILE`, and ends
your message with the resume guide — the launch command from the Execution
line and the first prompt for the skill that line names. Offer no execution
choice: the Execution line already made it.
