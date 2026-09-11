---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

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

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use dr-superpowers:subagent-driven-development (recommended) or dr-superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Spec:** [path to the spec/design doc this plan implements — the plan
argues from the spec, so the spec travels with it; executors read both]

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

---
```

## Task Structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Interfaces:**
- Consumes: [what this task uses from earlier tasks — exact signatures]
- Produces: [what later tasks rely on — exact function names, parameter
  and return types. A task's implementer sees only their own task; this
  block is how they learn the names and types neighboring tasks use.]

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
   task as the plan describes it: if its steps contain the complete code, spec
   completeness is 0. Count file shapes, not file instances.
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
choice is the interesting part. Under dr-superpowers:executing-plans the lines
are inert. [assigning-implementers.md](references/assigning-implementers.md)
explains why each of these rules exists.

**Check your work** before saving the plan:

- Every task has an `**Implementer:**` line and an `**Evaluation:**` line,
  plus an `**Approach:**` line whenever the task involved an approach
  decision.
- Every agent name is fully qualified and appears in `ladder.md`'s assignment
  table, or in its reserve table when your human partner overrode the
  assignment by hand. A reserve name you wrote yourself is an error, not an
  override.
- Every `**Evaluation:**` line's four scores sum to the stated total, and that
  total maps to the named agent — except under the spec-3 floor in
  `ladder.md` or a hand-edited override.
- Every task clears Rule S: `files + spec + coupling` below 4 and spec below 3.
  A total above 6 anywhere means the gate was skipped.
- Every `**Approach:**` line names `inline`, `advisor`, or `best-of-3`, and
  every `inline` cites a skip condition by number.
- Every task heading begins with `Task <N>`. Check them as a set:
  `grep -cE '^#+[[:space:]]+Task[[:space:]]+[0-9]' PLAN_FILE` must equal the
  number of tasks.
- Every `**Executor:**` line names a rung in `ladder.md`'s `codex-assignment`
  block matching the task's total, sits on a task that also has an
  `**Implementer:**` line, passed the lane gate without a human Rule S
  override, and names an executor listed in the plan header's
  `> **External executors:**` line.

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

**3. Type consistency:** Do the types, method signatures, and property names you used in later tasks match what you defined in earlier tasks? A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

**4. Assignments:** Run the Check your work list under Assign an implementer to every task.

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Execution Handoff

After saving the plan, run `scripts/next-step PLAN_FILE`, from the plugin
root (two levels above this skill's directory). It prints the block for
starting Task 1 in a fresh session — launch command from the Execution line
and a first prompt — and records it in the primary checkout's
`.superpowers/handoff/latest.md`. End your message with that block, verbatim,
after the execution choice below.

Offer execution choice:

**"Plan complete and saved to `docs/superpowers/plans/<filename>.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?"**

**If Subagent-Driven chosen:**
- **REQUIRED SUB-SKILL:** Use dr-superpowers:subagent-driven-development
- Fresh subagent per task + two-stage review

**If Inline Execution chosen:**
- **REQUIRED SUB-SKILL:** Use dr-superpowers:executing-plans
- Batch execution with checkpoints for review
