# Setup

Ensure the work happens in an isolated workspace: use
dforge:using-git-worktrees to create one or verify the existing one.
Never start implementation on a main/master branch without your human partner's
explicit consent.

**Ask the finish preference first.** Before this run writes anything to its
ledger, follow [finish-preference.md](../../../reference/finish-preference.md):
ask what finishing should do once the final review is clean, record the
answer, and start work in the same turn. Skip it when
`scripts/finish-choice get --plan PLAN_FILE` already prints a choice (it does
so unasked when the `finishAction` setting names an action), or when this
plan's ledger already exists: a resumed run does not stop to ask. When
the spec's `## Decisions` holds a `Finish: <action>` line, run
`scripts/finish-choice set <action> --plan PLAN_FILE` instead of asking. It is
the run's one question; nothing else waits on your human partner.

Conversation memory does not survive compaction. Track progress in a ledger
file, not only in todos.

- Each plan owns a workspace: run `scripts/sdd-workspace PLAN_FILE`
  (see using-dforge §Session Budget), and it prints the plan's git-ignored directory
  (`<repo-root>/<state>/sdd/<plan-basename>/`), home to every artifact for
  THIS plan except its ledger and handoff note, which live in `<ledger dir>`.
  Another plan's directory is never yours to read or write.
- This plan's ledger is `<ledger dir>/progress.md`. If its first line names your
  plan file, recover each task's state with the Recovery table in
  [recovery.md](recovery.md). A ledger whose first line names a different
  plan - or a stray ledger at the old flat path `<state>/sdd/progress.md` - is
  another plan's progress: leave it in place and start your own, fresh.
- Create the ledger with its identity as the first line:
  `# SDD ledger — plan: <plan name>` — `bash <plugin-root>/scripts/dforge-path name PLAN_FILE`,
  so the ledger names the plan in either store.
- When a register covers this plan's spec, mark the rows this plan carries as
  in flight once, at the start of the run, skipping any row already at `verify`
  or `done`: `scripts/register set <register> <id> doing`. The register is read by
  `next-step`, `repo-audit` and dforge:project-status, so a run that
  never says it started reads as unscheduled work everywhere else.
- Create `<ledger dir>/handoff.md` from the template in dforge:handoff
  if it does not exist. Update it in the same message as a ledger write
  whenever an owner constraint, gotcha, prohibition or open question changes.
- Read `<docs>/distilled/constraints.md` when the project has one. Its
  entries bind like the owner constraints in `handoff.md` and yield to them
  wherever both speak; an absent file is not an error. See
  [project-state.md](../../../reference/project-state.md).
- `git clean -fdx` will destroy the workspace (it is git-ignored scratch); if
  that happens, recover from `git log`.

Read the plan's header, never the whole plan: run
`scripts/task-brief --header PLAN_FILE` (see using-dforge §Session Budget), and read the
file it prints (`<workspace>/plan-header.md`). Note the Execution line, the
Global Constraints and the Contracts, and create a todo per Task index entry. A
plan written before 1.4.0 may have no Task index: then run
`scripts/task-brief PLAN_FILE N` for N = 1, 2, … until it exits 3, and take
each task's title from its brief's first line. You never read the spec: the
ruling seat and the final review do. If the plan's `**Spec:**` path is
unreachable, note it in the ledger and say so in every ruling-seat dispatch;
the seat marks its rulings provisional.

**Check the Execution line.** It must name `inline`.

- It names `subagent`: log `Ruling: routed to subagent mode — the plan's
  Execution line names it — none` and use
  dforge:subagent-driven-development instead.
- The plan has no Execution line, because it was written before 1.4.0: log
  `Ruling: inline by invocation — plan predates the Execution line — if wrong,
  the run escalates at the first task that will not converge` and continue.

A `**Parallelism:** waves` line is read only by subagent mode. When your human
partner has put a waves plan in this mode, run its tasks in index order and
ignore the waves: a waves plan's index order is always a correct sequential
order ([parallel-waves.md](../../../reference/parallel-waves.md)).

Never re-score the tasks. `scripts/plan-lint` enforced the eligibility rule
when the plan was saved, and a plan whose Execution line says `inline` has
passed it.

A task whose brief's second line marks it delegated is dispatched, never
implemented here, and its `**Executor:**` line is read by
[delegated-task.md](../../../reference/delegated-task.md) §1, which runs that
executor's wrapper in place of an implementer subagent. `**Implementer:**` lines are inert for the tasks
you implement.

**Preflight.** When `plan-header.md` ends with a `**Dispatch:** delegated`
line naming at least one `(heavy)` task, send one `preflight` item to the
ruling seat before Task 1 and carry out its verdicts. A plan with no heavy task
has no pre-flight scan, even when it offloads tasks: it is one
whole-plan judge dispatch, and a plan of small tasks is low-coupling by
construction. A plan defect that surfaces while you work goes to the seat as a
`blocked-plan` item.
