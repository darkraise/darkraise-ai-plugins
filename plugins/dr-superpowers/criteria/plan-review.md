# Plan Review - Verifier Criteria

Applied by dr-superpowers:writing-plans when a judge reviews an implementation
plan before it is saved.

## Ground Truth Note

Trust the plan text, the spec text, and the plan-lint output file. Do NOT trust
the planner's self-review, its task index, or its claims about what a task
covers: check each claim against the task text itself. A plan that reads as
thorough is not evidence that a small model can execute it; the exact paths,
code, and commands in each task are.

Every task's implementer sees only that task's text plus the header's Global
Constraints and Contracts. Judge each task from that view, not from your own
reading of the whole plan.

## Criteria

### Executability {#executability}

Look at each task's text together with the header's Global Constraints and
Contracts - nothing else. Score HIGH when every step names exact file paths,
every code step carries the complete code, every command is exact and states
its expected output, and every test would fail against a stub: a test that
still passes with `return <constant>` or with the implementation deleted is
invalid. Score LOW when a step leaves a decision to the implementer, refers to
something outside the task and header, says "similar to Task N", or specifies a
test that asserts nothing. Ignore whether the spec is covered; Coverage owns
that. Ignore cross-task agreement; Coherence owns that.

### Coherence {#coherence}

Look across the tasks, the Contracts section, and the Global Constraints.
Score HIGH when every name a task consumes is produced by an earlier task and
matches its Contracts entry exactly, when Interfaces blocks cite Contracts
instead of restating them, and when no two tasks contradict each other or a
Global Constraint. Score LOW for a name used before any task creates it, a
signature or path that differs between tasks or from Contracts, a task that
breaks a Global Constraint, or a Task index that disagrees with the headings.
Ignore whether the spec is covered, and ignore how well each single task is
written.

### Coverage {#coverage}

Look at the spec's requirements, section by section, against the Task index
and the task text. Score HIGH when every requirement maps to a task that
implements it and nothing is built that the spec does not ask for. Score LOW
for a requirement with no task, a requirement a task only mentions without
implementing, or a task with no requirement behind it. Ignore task quality and
cross-task agreement; the other criteria own those.

### Assumptions {#assumptions}

Look at the Assumptions (evidence) section and at the facts the tasks rely on
about existing files, tools, and behaviour. Score HIGH when every listed
assumption carries evidence that actually supports it - a command with the date
it ran, a file:line, a documentation URL - and every assumption marked
unverified has its verifying step in the named task. Score LOW when the
evidence does not show what the assumption claims, when a task relies on a
fact about the codebase or environment that is not listed, or when an
unverified assumption has no verifying step. Ignore executability and
coverage.
