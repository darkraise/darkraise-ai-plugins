# Session Budget

`scripts/task-brief`, `scripts/review-package` and every `scripts/task-step`
digest end their output with the budget line ([session-budget.md](../../../reference/session-budget.md)), so you
check the session budget before every task and every review at no extra
request:

    budget: 312k of 465k (67%) — ok — source: record

- `ok` or `unknown`: carry on, however high the percentage. Only the verdict
  stops you.
- `handoff`: finish the task in flight — its reviews, fix rounds and
  `Task N: complete` line — then invoke dforge:handoff. Start no new
  task. The budget holds one task's worst growth, so the task lands before
  compaction.
- The plan's last two tasks never hand off in strict mode: their budget
  lines read `budget (last 2 tasks)` or `budget (last task)` and say `ok` past
  the budget. A short tail costs less to finish here than a fresh session's
  baseline and reload.
- After the last task's `Task N: complete` line, run
  `scripts/context-size --final` for the record, then
  continue to Final Review in this session and on to finishing, whatever it
  prints: the final phase never hands off, and a `review-package` budget line
  saying `handoff` does not stop it. If the context fills, Claude Code's own
  compaction is the backstop, and After compaction resumes the final phase
  from the ledger. In an auto run `--final` also moves the run to the final
  phase, and a `compact` line still ends the turn on `Auto run: compacting`.
- On Codex the budget line carries a measured number but no verdict: hand off
  after every 3 completed tasks, or after any task that needed 3 or more fix
  rounds.
