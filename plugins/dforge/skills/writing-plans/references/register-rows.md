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
4. A row whose Item begins `A<n>:` is a deferred acceptance statement: your
   human partner or the ruling ladder left it unsettled. No task's `**Items:**`
   line names it, and no task builds on it.

`plan-lint` then checks both directions: an assigned row no task cites, and a
task citing a row no register holds. It also rejects a bare identifier that
more than one covering register holds.
