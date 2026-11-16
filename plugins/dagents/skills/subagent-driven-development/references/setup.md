# Setup

Ensure the work happens in an isolated workspace: use
dforge:using-git-worktrees to create one or verify the existing one.
Never start implementation on a main/master branch without your human
partner's explicit consent.

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

Conversation memory does not survive compaction. In real sessions,
controllers that lost their place have re-dispatched entire completed task
sequences — the single most expensive failure observed. Track progress in
a ledger file, not only in todos.

- Each plan owns a workspace: at skill start, run
  `scripts/sdd-workspace PLAN_FILE` (see using-dforge §Session Budget) — it prints the plan's git-ignored
  directory (`<repo-root>/<state>/sdd/<plan-basename>/`), home to
  every artifact for THIS plan: briefs, reports, review packages. Its ledger
  and handoff note live in `<ledger dir>`.
  Another plan's directory is never yours to read or write.
- Check for this plan's ledger at `<ledger dir>/progress.md`. If its first
  line names your plan file, recover each task's state with the Recovery
  table in [ledger.md](ledger.md) §Recovery. A ledger whose first line names a different plan
  file — or a stray ledger at the old flat path `<state>/sdd/progress.md`
  — is another plan's progress: leave it in place and start your own, fresh.
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
  whenever an owner constraint, gotcha, prohibition or open question changes —
  not after every task.
- Read `<docs>/distilled/constraints.md` when the project has one. Its
  entries bind like the owner constraints in `handoff.md` and yield to them
  wherever both speak; an absent file is not an error. See
  [project-state.md](../../../reference/project-state.md).
- The ledger is your recovery map: the commits it names exist in git even
  when your context no longer remembers creating them. After compaction,
  trust the ledger and `git log` over your own recollection.
- `git clean -fdx` will destroy the workspace (it's git-ignored scratch); if
  that happens, recover from `git log`.

Read the plan's header, never the whole plan: run
`scripts/task-brief --header PLAN_FILE` (see using-dforge §Session Budget), and read the
file it prints (`<workspace>/plan-header.md`). Note the Execution line, the
`**Parallelism:**` line when there is one, the Global Constraints and the
Contracts, and create a todo per Task index entry.
A plan written before 1.4.0 may have no Task index: then run
`scripts/task-brief PLAN_FILE N` for N = 1, 2, … until it exits 3, and take
each task's title from its brief's first line. You never read the spec: the
ruling seat, the plan review and the final review do. If the plan's
`**Spec:**` path is unreachable, note it in the ledger and say so in every
ruling-seat dispatch; the seat marks its rulings provisional.

Before dispatching Task 1, send one `preflight` item to the ruling seat (see
The Ruling Seat). It scans the whole plan against the spec for:

- tasks that contradict each other, the Contracts, or the Global Constraints
- anything the plan explicitly mandates that the review rubric treats as a
  defect (a test that asserts nothing, verbatim duplication of a logic block)

- for a plan whose `**Parallelism:**` line names waves, every pair of tasks
  in one wave that could observe each other's change

The seat returns a table, not a verdict: one row for every pair of tasks that
share a file or an interface, and one row for every task on whether its own
text agrees with itself. Verdict blocks follow for the rows that found
something. Write the whole output to `<workspace>/preflight.md`, carry out
each verdict, log `Ruling: pre-flight — <clean | K findings, see
preflight.md> — none`, and dispatch Task 1. A resumed ledger that already
holds that line skips the dispatch. The review loop remains the net for
conflicts that only emerge from implementation.
