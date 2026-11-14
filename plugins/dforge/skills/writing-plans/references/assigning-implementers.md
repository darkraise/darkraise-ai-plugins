# Why the scoring rules are shaped this way

The procedure lives in writing-plans' "Score every task" section. This file holds the reasons, for when a rule looks arbitrary.

## Score the plan, not the imagined task

"Spec completeness" is a fact about the plan text: if the task's steps contain
the complete code to write, that axis is 0 no matter how clever the code is.
A Claude plan's code task gives its tests and interfaces but not its
implementation, so it scores 2. Score the task as the plan describes it, not
as you imagine it might grow.

Count file shapes, not file instances: sixteen files generated from one template
carry one decision, and the axis measures decisions.

## Resist a bigger model

Three of the four axes measure how you drew the task, not how hard the change
is. Buying capability to cover a decomposition defect keeps the defect and pays
for it. If a task keeps failing Rule S no matter how you split it, that is a
real finding about the work - say so in the plan rather than scoring around it.
Rule S caps a compliant Claude total at 8 (`reducible <= 5` plus risk 3), which
is why the execution floor table stops there; a `Host: codex` plan keeps
`reducible <= 3`. See [ladder.md](../../../reference/ladder.md).

## Why the heading form matters

`scripts/task-brief` finds a task by matching a heading that begins with
`Task <N>`, so `### Task 4: Wire the export pipeline` works and
`### Wire the export pipeline (Task 4)` does not: `task-brief` exits non-zero
leaving an empty brief, and the task cannot be dispatched.

The damage is not confined to that task. `task-brief` only stops copying when it
meets the *next* heading it recognizes, so a malformed heading silently appends
its whole task body to the **previous** task's brief. One bad heading breaks one
task and corrupts its neighbor, and the neighbor's brief still exits 0 and looks
fine. That is why `scripts/plan-lint` checks all headings as a set: a single
`task-brief` run only inspects the heading you asked for.

## Overriding

A kept `spec = 3` or a Rule S breach a human accepts carries an
`**Override:** <reason>` line below the Evaluation line, and `plan-lint`
reports that task's Rule S finding as a warning instead of an error. Planners
never write the line: it is how a human ruling stays legal without the checker
guessing who wrote it.

## Why a script checks the plan

These rules used to be a checklist the planner ran against its own work, and a
planner grading itself passes what it meant rather than what it wrote.
`scripts/plan-lint` applies the same checks the same way whichever model wrote
the plan, and it reads `ladder.md`'s floor table at run time, so the checks cannot
drift from the tables they enforce.
