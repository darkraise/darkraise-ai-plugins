# Why the assignment rules are shaped this way

The procedure lives in writing-plans' "Assign an implementer to every task"
section. This file holds the reasons, for when a rule looks arbitrary.

## Score the plan, not the imagined task

"Spec completeness" is a fact about the plan text: if the task's steps contain
the complete code to write, that axis is 0 no matter how clever the code is.
Score the task as the plan describes it, not as you imagine it might grow.

Count file shapes, not file instances: sixteen files generated from one template
carry one decision, and the axis measures decisions.

## Resist a bigger model

Three of the four axes measure how you drew the task, not how hard the change
is. Buying capability to cover a decomposition defect keeps the defect and pays
for it. If a task keeps failing Rule S no matter how you split it, that is a
real finding about the work - say so in the plan rather than scoring around it.
Rule S also caps a compliant total at 6, which is why the assignment table stops
there; see [ladder.md](../../../reference/ladder.md).

## Reserve agents are never an assignment output

Nine implementers - the `xhigh` and `max` efforts, and every Fable tier - sit in
the reserve table and in no other table. No score reaches them, and reaching for
one anyway is the exact move Rule S exists to prevent. They are legal in a plan
only as a human override.

## Why the Executor is a second line

`**Implementer:**` still names the Claude agent for the score, and
`**Executor:**` is an override on a second line. That ordering makes every
degradation free: a machine without Codex, a cold session, and an executor whose
auth has lapsed all fall back by reading a line that is already there, rather
than re-deriving the assignment at dispatch time. It also keeps every
`**Implementer:**` value inside the assignment or reserve table, so the checks
still mean what they say.

## Why the lane gate excludes an overridden Rule S pass

The legacy floor lets a human keep a `spec = 3` task as written. Such a task can
score `files 0 + spec 3 + coupling 0 + risk 0 = 3` and would otherwise pass the
gate, handing a task whose approach nobody decided to a one-shot external agent
that cannot ask questions mid-run.

## Why batched tasks stay on the Claude lane

The rule to batch small same-shape work produces one dispatch covering several
tasks, which a per-task `**Executor:**` line and per-task thread id cannot
represent.

## The lines land in the brief

`scripts/task-brief` copies a task block verbatim, so the assignment lines reach
the implementer. That is intended: an implementer knowing its task's blast
radius is useful context.

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

A human can edit any `**Implementer:**` line by hand.
subagent-driven-development obeys the line and never recomputes when it is
present, so a human ruling always wins over the rubric. The `**Evaluation:**`
line stays, because the gap between the score and the choice is the interesting
part.

A hand edit that breaks a rule the checker enforces - a reserve tier, a kept
`spec = 3`, a table mismatch - carries an `**Override:** <reason>` line below
the Evaluation line, and `plan-lint` reports those findings on that task as
warnings instead of errors. Planners never write the line: it is how a human
ruling stays legal without the checker guessing who wrote it. An Executor line
on an overridden task still fails, because the lane gate excludes human
Rule S overrides.

## Why a script checks the plan

These rules used to be a checklist the planner ran against its own work, and a
planner grading itself passes what it meant rather than what it wrote.
`scripts/plan-lint` applies the same checks the same way whichever model wrote
the plan, and it reads `ladder.md`'s tables at run time, so the checks cannot
drift from the tables they enforce.
