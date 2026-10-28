# The Ruling Seat

Judgment about the plan, the spec or a finding belongs to the ruling seat, not
to you, whatever model you run on. It reads the whole plan, the spec,
`amendments.md` and the ledger; you read the header and one brief at a time. It
and delegated tasks are all this mode dispatches before the final review.

**When.** These points arise in this mode:

| Kind | Decision point |
|---|---|
| `preflight` | Once, before Task 1, when the plan has a heavy task (Setup) |
| `blocked-plan` | The plan is wrong and no path forward is a mechanical choice |
| `plan-conflict` | A final-review finding, or a delegated task's review finding, that conflicts with what the plan's text requires, or is labelled plan-mandated |
| `cannot-verify` | A delegated task's `cannot-verify:` digest line |
| `breaker` | A delegated task's findings still open after round 2/2 |
| `executor-empty-diff` | An external executor's fix round that returned DONE with an empty diff and an argument |
| `final-residual` | Findings still open after the final review's one fix wave |

`executor-empty-diff` is reachable here too: an inline plan dispatches its
offloaded tasks, so one of their fix rounds can return DONE with an empty diff,
and `preflight` arises only for a plan with a heavy task.

**How.** Write `<workspace>/rulings-<point>-<task>.md` - `<task>` is the task
number the items concern, or `plan` for a plan-level point, so a recurring
point never overwrites an earlier file - listing each item: an id, its kind,
its task, and the paths it needs, with the findings copied verbatim. Run
`scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]` and dispatch the
`primary` it prints with
[ruling-prompt.md](../../subagent-driven-development/references/ruling-prompt.md),
expanding its placeholders. Its `[REPORT_FILE]` is
`<workspace>/rulings-<point>-<task>-report.md`. The seat writes its report
there and replies in at most 10 lines;
read only its `## Verdict` section
(`awk '/^## / { on = ($0 == "## Verdict") } on' <report>`), never the rest.
Items of several kinds at one point share one
dispatch, and `<kind>` is then one comma-separated list; the route prints
`dforge:judge-sonnet-high` when every kind is `cannot-verify` or
`executor-empty-diff` and no task it names is risk 3, and `dforge:judge-opus`
otherwise. A delegated task's cannot-verify item that a `check identity:` or
`check attribution:` line of `scripts/task-step review` answers `clean` goes to
no seat: log
`Task <N>: Ruling: cannot-verify — settled by task-step check <name> — none`.
On any exit 2, dispatch
`dforge:judge-opus` and say why, quoting its message - except on a
Codex host, where `review-route --ruling` exits 2 on every `Host: codex` plan and the
seat is the native judge named in Select the host first.

**Carry out each verdict**, and copy its `Ruling:` line into the ledger
verbatim:

- **CONFIRMED-GAP** - the finding is real. For a task you implement, make
  the smallest fix the ruling names. A CONFIRMED-GAP whose fix you attempt and
  fail is a trigger in Switching to subagent mode. A delegated task's gap is
  never yours to fix: mid-task it enters that task's fix loop, and at the
  breaker it is logged `Task <N>: Ruling: <finding> — <ruling>` and carried
  into the next dependent task's dispatch (with none, the next task in plan
  order; after the last task, the final review), as
  [delegated-task.md](../../../reference/delegated-task.md) §5 completes it.
- **PARK** - log `Task <N>: parked — <finding> — Ruling: <why>`; the code
  stands.
- **AMEND** - run
  `scripts/plan-amend PLAN_FILE --report <workspace>/rulings-<point>-<task>-report.md --id A<k>`,
  `A<k>` being the item's `Amendment:` line; never copy the entry by hand. On `amended: A<k> …`, write the amendment ledger line; your next
  `task-brief` carries the amendment. On `rejected: …`, make one fresh seat
  dispatch carrying the report path, the entry's id and the rejection output;
  a second rejection is BLOCKED. A Header amendment is confirmed by a second, independent `judge-opus` dispatch
  before `plan-amend` runs, exactly as dforge:subagent-driven-development
  §The Ruling Seat describes, including its ledger line.
- **BLOCKED** - log `Task <N>: BLOCKED — ruling seat — <decision>`, name it in
  your final message, and stop.

Never soften, merge or second-guess a verdict. If you think the seat is wrong,
carry the verdict out anyway: the ledger line is where your human partner sees
it.

**When no subagent facility exists at all**, the seat is unreachable. Rule
yourself, write `Task <N>: Ruling: (unseated) <item> — <decision> — <cost if
wrong>`, and say it aloud; list every unseated ruling for the final reviewer. A
visible ruling your human partner can rework beats a session parked on a
question. On Claude Code and on Codex this never fires - if it does, check
whether you are in the mode and on the host you think you are.
