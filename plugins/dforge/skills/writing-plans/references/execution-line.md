**Read the settings first.** Two workflow settings shape a plan,
`executionMode` and `executionStrategy`. They arrive in the session-start line
`dforge settings in force (…)`. With no such line in context,
run `scripts/dforge-config workflow` before you choose the Execution line
or ask the strategy question; it prints nothing when both are at their
defaults. A key the line does not name is at its default, and your human
partner's own instructions outrank a setting.

**Choosing the Execution line.** The plan decides its execution mode:

A task is **heavy** when its total is 5 or more or its risk is 3, on any part.
An inline plan delegates its heavy tasks
and every task carrying an `**Executor:**` line: each runs through
[delegated-task.md](../../../reference/delegated-task.md) with an implementer
subagent — or, for an Executor line, that executor's wrapper — and the full
per-task review. The tasks not delegated are the **self-implemented** tasks.

- `subagent` when more than half the tasks are heavy, and always when the
  plan runs parallel waves (see Parallel waves):
  `claude --model sonnet --effort high`. The controller owns no judgment calls
  — the ruling seat does — so it needs no stronger model.
- Otherwise `inline`, the default, on `sonnet`: every self-implemented task
  (total 4 or less, risk below 3) is assigned to Sonnet, and heavy
  tasks are delegated. `<e>`
  is the assignment-table effort of the highest self-implemented total
  (`impl-haiku` counts as `low`), raised to `high` when any task is delegated:
  `claude --model sonnet --effort <e>`. When every task is heavy
  and your human partner overrides the line to inline, use
  `claude --model opus --effort high`.
- Your human partner may override the line; `plan-lint` checks its grammar,
  warns when it disputes the majority rule, and lists the delegated tasks with
  their reasons.
- The `executionMode` setting fixes the
  line when it is `inline` or `subagent`, in place of the majority rule.
  `inline` also makes the plan sequential, whatever the spec's
  `**Execution strategy:**` line or the `executionStrategy` setting says,
  because an inline session implements its own tasks one after another: write
  `**Parallelism:** sequential — executionMode is inline`
  and group no waves. An inline plan still delegates its heavy tasks and every
  task carrying an `**Executor:**` line.
