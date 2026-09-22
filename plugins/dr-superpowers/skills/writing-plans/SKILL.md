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

A task is **heavy** when its total is 5 or more or its risk is 3, on any part.
A task is **four-band** when it is not heavy and its highest total is exactly 4.
An inline plan delegates its heavy tasks, its four-band tasks while they
are a third of the plan or fewer (`3 x four-band <= N`),
and every task carrying an `**Executor:**` line: each runs through
[delegated-task.md](../../reference/delegated-task.md) with an implementer
subagent — or, for an Executor line, that executor's wrapper — and the full
per-task review. Past that third, one Opus session costs less than a seat per
task, and no four-band task is delegated.
A total-4 task counts toward that third whether or not it is offloaded:
dropping it from the count could flip the threshold and newly delegate
four-band tasks nobody marked. The tasks not delegated are the
**self-implemented** tasks.

- `subagent` when more than half the tasks are heavy:
  `claude --model sonnet --effort high`. The controller owns no judgment calls
  — the ruling seat does — so it needs no stronger model. Four-band tasks never
  count toward this majority.
- Otherwise `inline`, the default. The model is `opus` when a self-implemented
  task totals 4 — so only when four-band tasks exceed a third of the plan and
  at least one of them carries no `**Executor:**` line — and `sonnet`
  otherwise. `<e>` is the assignment-table effort of the highest
  self-implemented total (`impl-haiku` counts as `low`),
  raised to `high` when any task is delegated:
  `claude --model <sonnet|opus> --effort <e>`. When every task is heavy
  and your human partner overrides the line to inline, use
  `claude --model opus --effort high`.
- Your human partner may override the line; `plan-lint` checks its grammar,
  warns when it disputes the majority rule, and lists the delegated tasks with
  their reasons.

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
identifiers this task discharges, comma-separated, for example `4, 16`. Omit
the line otherwise.]

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Write the implementation**

```python
def function(input):
    # the complete, real implementation - every line the implementer types
    ...
```

Step 3 carries the whole implementation. A body that returns a constant to
satisfy the test is a plan failure: `plan-review.md` scores it LOW, and the
implementer will transcribe it literally.

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
4. **Offer an external executor** and apply the lane gate — see
   [executor-lane.md](../../reference/executor-lane.md) §Planning. Every id
   `scripts/executors list` prints has its own gate; run each, resolved with
   `bash "$(bash scripts/executors path <id> gate)"`, before the roster, and
   make the offer once per plan
   for every executor whose gate prints `lane=true`. If none is usable, ask
   nothing.
5. **Write the lines** directly below the task's `**Items:**` line, or its
   `**Interfaces:**` block when there is no Items line, in
   this order:
   - `**Implementer:**` — always; the fully qualified agent, for example
     `dr-superpowers:impl-sonnet-medium`
   - `**Executor:**` — only when the lane gate passed, for example
     `codex gpt-6-sol / low`
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

**A task carries at most one `**Executor:**` line, and you choose it.** When
two ticked executors' gates both admit a task, nothing mechanical picks
between them: write one line, and `plan-lint` validates only what is written.
No precedence rule is introduced here — with one registered executor there is
no choice to make, and a rule invented now would be untested against a real
second executor.

A human may edit any `**Implementer:**` line by hand;
dr-superpowers:subagent-driven-development obeys it and never recomputes.
Leave the `**Evaluation:**` line in place — the gap between the score and the
choice is the interesting part. A hand edit that breaks a checked rule — a
reserve tier, a kept `spec = 3`, a table mismatch — carries an
`**Override:** <reason>` line below the Evaluation line, and `plan-lint` then
reports it as a warning. Never write an Override line yourself. Under
dr-superpowers:executing-plans the lines are read for the delegated tasks,
which include every task carrying an `**Executor:**` line.
[assigning-implementers.md](references/assigning-implementers.md) explains why
each of these rules exists.

## Assign the register rows

When a register covers this plan's spec, the plan is where its rows become
work.

1. Set every row this plan schedules with
   `scripts/register set <register> <id> planned --assigned <this plan's
   repository-relative path>`, and give it an `--acceptance` if it has none:
   that cell is what lets finishing decide between `done` and `verify`.
2. Put the identifiers on the tasks that discharge them, as `**Items:**` lines.
3. Record a deferral as a row, not as prose. An item this plan will not answer
   is `scripts/register set <register> <id> deferred --note "<the reason>"`. An
   "Out of scope" heading is read by nothing, which is how design-time
   deferrals were lost.

`plan-lint` then checks both directions: an assigned row no task cites, and a
task citing a row no register holds.

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

1. **Lint.** Run `scripts/plan-lint PLAN_FILE` (see using-superpowers §Session Budget)
   until it reports `0 errors`. Fix each
   WARN, or explain it in one line of the plan's Assumptions. The checker
   covers the header sections, the task headings and index, the Execution
   line, placeholders, and every task's assignment lines.
2. **Review.** Write the lint output to the plan's workspace:
   `scripts/plan-lint PLAN_FILE > <workspace>/plan-lint.txt`, where
   `<workspace>` is the directory `scripts/sdd-workspace PLAN_FILE` prints.
   Before each round `<r>`, copy the plan to `<workspace>/plan-round-<r>.md`,
   run `scripts/codex-gate` (say its line aloud when it ends `source=probe`),
   then `scripts/review-route PLAN_FILE --plan-round <r>`, and review with the
   seat it prints, using
   [plan-reviewer-prompt.md](references/plan-reviewer-prompt.md). The gate
   keeps an off answer for the session, so add `--refresh` when Codex may have
   come back since then, such as after a login. Every seat
   scores executability, coherence, coverage and assumptions (1-20) against
   [plan-review.md](../../criteria/plan-review.md) and lists findings. If
   `review-route` exits 2 naming `native-codex.md`, the plan is a Codex-host
   plan: dispatch the native judge the prompt's `[JUDGE]` placeholder
   describes. On any other exit 2, review with `dr-superpowers:judge-opus`
   and say why, quoting its message.
   - **`primary=codex:plan`** (round 1). Write the prompt its Round 1 on Codex
     section describes to `<workspace>/plan-review-prompt.md`, then run, as a
     background Bash call with no timeout (the rung's bound is longer than the
     Bash tool's ten-minute cap, and a background call is not bound by it):

     ```bash
     bash scripts/run-codex-review.sh --kind plan --cwd <repository-root> \
       --out <workspace>/plan-review-round-1.json --prompt <workspace>/plan-review-prompt.md
     ```

     Read its one status line. `OK` and `FALLBACK` are a review: read the four
     scores and `findings` from the JSON. On `FALLBACK`, or a line naming
     `gpt-6-sol/xhigh` with `status=OK`, say the substitution aloud with the
     runner's reason or the line's `evidence=`. `TIMEOUT` or `FAILED` produced
     no review: dispatch the printed `fallback` (`dr-superpowers:judge-opus`)
     with the full-plan template, save its reply to
     `<workspace>/plan-review-round-1.md`, and say why. Never run the Codex seat
     twice in one round.
   - **`reason=codex-off`** (round 1 while the gate has not opened the review
     surface). No Codex seat runs. The `primary` is
     `dr-superpowers:judge-opus`. Dispatch it with the full-plan template, save its reply to
     `<workspace>/plan-review-round-1.md`, and say `codex off — <reason>`,
     quoting the gate line's `reason` (`untrusted` when it printed
     `usable=true`).
   - **`primary=dr-superpowers:judge-opus`** (every later round). Write
     `diff -u <workspace>/plan-round-<r-1>.md PLAN_FILE > <workspace>/plan-delta-<r>.diff`,
     dispatch the seat with the Later rounds template, passing that file and
     the previous round's findings file, and save its reply to
     `<workspace>/plan-review-round-<r>.md`.
3. **Fix and repeat.** Fix every Critical and Important finding and re-lint;
   Minor findings are advisory. Run the next round only when a round returned
   a Critical finding or any score of 8 or below, and only while the round is
   below the `cap=` that `review-route` printed: 1 when the plan's highest
   task total is 3 or less, 2 for 4 or 5, 3 for 6. A delta round replaces a
   fresh full review. At the cap, a Critical finding earns exactly one more
   delta round (`reason=cap-critical`), scoped to its fix, which earns no
   other. Any Critical finding still open after it, and any score of 8 or
   below at the cap, go to your human partner. A borderline score (9-13) gets
   a one-line decision in the plan's Assumptions.
4. **Record.** Only now, add the header line
   `**Plan review:** <YYYY-MM-DD> — <seat> — executability e / coherence c / coverage v / assumptions a (round r)`
   below the `**Program:**` line (below `**Execution:**` when there is no
   Program line). `<seat>` is the seat that ran the last round:
   `codex <model> / <effort>` from the runner's status line, or the judge
   agent. The header template deliberately omits it, so `plan-lint` warns
   until the review has run.

## Execution Handoff

A saved, reviewed plan is a hard stop: execution starts in a fresh session.
Invoke dr-superpowers:handoff. It commits the plan and the spec, writes
`.superpowers/handoff/latest.md`, runs `scripts/next-step PLAN_FILE`, and ends
your message with the resume guide — the launch command from the Execution
line and the first prompt for the skill that line names. Offer no execution
choice: the Execution line already made it.
