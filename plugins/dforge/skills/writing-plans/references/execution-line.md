**Read the settings first.** Two workflow settings shape a plan,
`executionMode` and `executionStrategy`. They arrive in the session-start line
`dforge settings in force (…)`. With no such line in context,
run `scripts/dforge-config workflow` before you choose the Execution line
or ask the strategy question; it prints nothing when both are at their
defaults. A key the line does not name is at its default, and your human
partner's own instructions outrank a setting.

**Choosing the Execution line.** Write `inline` on every plan. The session
implements every task that carries no `**Executor:**` line, heavy tasks
included; those are the **self-implemented** tasks. A task is **heavy** when
its total is 5 or more or its risk is 3, on any part.
A task carrying an `**Executor:**` line is delegated: it runs on that executor's wrapper through
[delegated-task.md](../../../reference/delegated-task.md) with the full
per-task review. A self-implemented risk-3 task gets a per-task review too, in
that file's session review loop.

- The pair covers the hardest self-implemented task: `<m>` and `<e>` are the
  model and effort of the assignment-table row for the highest
  self-implemented total (`impl-haiku` counts as `sonnet`/`low`), with `<e>`
  raised to `high` when a self-implemented task has risk 3 or any task
  carries an `**Executor:**` line: `claude --model <m> --effort <e>`.
  `plan-lint` errors on a model or an effort below that floor.
- `subagent` only when the `executionMode` setting is `subagent` or your human
  partner asks for it: `claude --model sonnet --effort high`. Subagent mode is
  deprecated, and `plan-lint` warns on every subagent line.
- Your human partner may override the line; `plan-lint` checks its grammar
  and lists the delegated tasks.
- The `executionMode` setting fixes the
  line when it is `inline` or `subagent`.
  An inline plan is sequential, whatever the spec's
  `**Execution strategy:**` line or the `executionStrategy` setting says,
  because an inline session implements its own tasks one after another: write
  `**Parallelism:** sequential — inline execution`
  and group no waves. An inline plan still delegates every task carrying an
  `**Executor:**` line.
