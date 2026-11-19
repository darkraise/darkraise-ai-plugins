**Read the settings first.** Two workflow settings shape a plan,
`executionMode` and `executionStrategy`. They arrive in the session-start line
`dagents settings in force (…)`. With no such line in context,
run `scripts/dagents-config workflow` before you choose the Execution line
or ask the strategy question; it prints nothing when both are at their
defaults. A key the line does not name is at its default, and your human
partner's own instructions outrank a setting.

**Choosing the Execution line.** Write `subagent`, the default, unless the
`executionMode` setting is `inline` or your human partner asks for inline
execution. Under `executionMode=auto` (the default) and `executionMode=subagent`
the line is `subagent`. A task carrying an `**Executor:**` line is delegated in
either mode: it runs on that executor's wrapper through
[delegated-task.md](../../../reference/delegated-task.md) with the full
per-task review.

- `subagent`: `claude --model sonnet --effort high`. The session coordinates:
  it dispatches every task to the implementer its `**Implementer:**` line
  names, and a judge reviews it. The ruling seat owns the judgment calls, so
  the session needs no stronger model.
- `inline` only when the `executionMode` setting is `inline` or your human
  partner asks for it. The session implements every task that carries no
  `**Executor:**` line, heavy tasks included; those are the
  **self-implemented** tasks. A task is **heavy** when its total is 5 or more
  or its risk is 3, on any part. A self-implemented risk-3 task gets a
  per-task review, in delegated-task.md's session review loop. The pair covers
  the hardest self-implemented task: `<m>` and `<e>` are the
  model and effort of the assignment-table row for the highest
  self-implemented total (`impl-haiku` counts as `sonnet`/`low`), with `<e>`
  raised to `high` when a self-implemented task has risk 3 or any task
  carries an `**Executor:**` line: `claude --model <m> --effort <e>`.
  `plan-lint` errors on a model or an effort below that floor.
- Your human partner may override the line in either direction; `plan-lint`
  checks its grammar and, on an inline line, lists the delegated tasks.
- An inline plan is sequential, whatever the spec's
  `**Execution strategy:**` line or the `executionStrategy` setting says,
  because an inline session implements its own tasks one after another: write
  `**Parallelism:** sequential — inline execution`
  and group no waves. An inline plan still delegates every task carrying an
  `**Executor:**` line.
