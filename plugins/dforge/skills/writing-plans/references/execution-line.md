**Choosing the Execution line.** Write `inline` on every plan. The session
implements every task, heavy tasks included. A task is **heavy** when its
total is 5 or more or its risk is 3, on any part. A risk-3 task gets a
per-task review in
[delegated-task.md](../../../reference/delegated-task.md)'s session review
loop.

- The pair covers the hardest task: `<m>` and `<e>` are the model and effort
  of the assignment-table row for the highest total (`impl-haiku` counts as
  `sonnet`/`low`), with `<e>` raised to `high` when a task has risk 3:
  `claude --model <m> --effort <e>`.
  `plan-lint` errors on a model or an effort below that floor.
- Your human partner may override the line; `plan-lint` checks its grammar.
- Every plan is sequential, because the session implements its own tasks
  one after another: write `**Parallelism:** sequential — inline execution`.
