# Auto run

An opt-in mode: once the design is approved, dr-forge writes the spec and the
plan, executes, reviews and finishes without asking its human anything. The
design is `docs/superpowers/specs/2026-10-13-dr-forge-auto-run-design.md` in
the dr-forge repository; this file is the contract the skills cite. Every
`scripts/…` command runs as `bash <plugin-root>/scripts/<name>`.

Claude Code only: the cockpit mod compacts and clears the session. No run
starts on Codex.

## Starting

dr-forge:brainstorming offers it once, after the last design section is
approved and before the spec is written, unless `autoRun=off`. On yes, from
the checkout the design was made in:

    scripts/auto-run start --spec <spec path> [--register <register path>]

`--register` names the item register when one is open; without it the script
creates `<docs>/registers/<date>-<slug>-auto.md` in this checkout and prints
its path. The branch checked out here becomes the run's base, the branch the
finish merges into. Exit 4 means another live run is active, exit 2 that this
session cannot be bound: say so in one line and continue without an auto run.

## While a run is bound to this session

`scripts/auto-run status` exits 0 and names the phase, the regime, the pending
action, the plan, the base and the register. Every `scripts/auto-run` command
exits 0 when done, 1 when it failed (no handoff file to read, or `jq` or
`mktemp` failed), 2 on bad usage, 3 when no run is bound to this session, 4
when refused, 5 when the run stopped (`handoff` for `verdict` and
`after-compact`) and 6 for `compact`. Then:

- **Ask nothing.** No clarifying question, approval or menu. What you would
  have asked goes to the ladder under Rulings.
- **Skipped questions:** the spec review stop, the worktree consent (create
  the worktree), the finish-preference question, and the execution stops
  under Rulings.
- **Phases:** `scripts/auto-run phase plan` when writing-plans starts,
  `scripts/auto-run attach --plan <plan>` once the plan is reviewed,
  `scripts/auto-run phase execute` when execution starts,
  `scripts/auto-run phase final` before the final review and
  `scripts/auto-run phase finish` when finishing starts.
- **Each completed task:** `scripts/auto-run task-complete` right after its
  `Task N: complete` ledger line.
- **A message from your human partner** does not stop the run: answer it and
  continue, unless it asks you to stop (see Stopping).

## The spec

After your own self-review round, dispatch `dr-forge:judge-fable` on the spec
against the approved design: the design sections as approved, verbatim, and
the spec's path. Apply what it rules, and record each ruling with
`scripts/auto-run ruling add "Fable, spec: <item> — <ruling>"`. Add each item
it leaves undecided or without a suggestion to the run's register:

    scripts/register add <register> "<item>" --state deferred --note "Fable: <its words>"

At most two Fable rounds run (review, revise, re-review); anything still open
after the second is deferred the same way. Then `scripts/context-size --plan`
as brainstorming says: under its limit write the plan here; over it, follow
Clears with `--phase`.

## Rulings

The ladder for anything you would have asked:

1. **Opus.** During execution, the ruling seat (`dr-forge:judge-opus`) as the
   execution skills dispatch it; CONFIRMED-GAP, PARK and AMEND are carried out
   as always. Before execution (a spec or planning choice), dispatch
   `dr-forge:judge-opus` yourself with the question, its options with your
   recommendation first, the spec's path and the plan's path when one exists,
   asking for `ruling: <choice> — <reason>` or `no ruling`.
2. **The pending list.** An Opus `BLOCKED` or `no ruling`, or an implementer
   that exhausted the ladder, is added:

       scripts/auto-run decision add --id <id> --question "<q>" --options "<recommended | other>" --opus-reason "<why Opus did not rule>" [--task <N>]

3. **Fable, in one batch.** Dispatch `dr-forge:judge-fable` once with every
   line of `scripts/auto-run decision list`, asking for each item
   `ruling: <choice> — <reason>` or `no ruling`. Carry out each ruling as a
   ruling-seat verdict. Record it as a `Ruling:` ledger line when the plan's
   ledger exists (`Task <N>: Ruling: …` for a task's item), and with
   `scripts/auto-run ruling add` before it does. Then
   `scripts/auto-run decision clear`.

**When Fable gives no ruling:**

- **A task's item:** the task is deferred. Write its terminal ledger line,
  and the same line for every task that depends on it:

      Task <N>: complete (deferred by the auto run) — done: nothing; verified: not run; remaining: <the item>[; partial commits <a7>..<b7>, kept for the final review]; discovered: none; assumptions: none; Ruling: <why> — <cost if wrong>

  Add one deferred register row per such task. Recovery, `scripts/next-step`
  and the final review count the line as complete, so the run moves on. In a
  wave, a deferred task's branch is not merged.
- **A spec or planning choice:** take the option listed first, record
  `scripts/auto-run ruling add "unconfirmed: <choice> — Fable gave no ruling"`,
  and add a deferred register row naming the choice.

A batch runs at once for a blocked task, and otherwise whenever the list is
not empty at a boundary: after the spec, after the plan is reviewed, after each
wave (each task in sequential mode) and before the final review. Tasks that do
not depend on a deferred task keep running.

**Never performed in an auto run,** whatever a ruling says: an irreversible or
destructive operation, a security-sensitive action, or a side effect outside
the worktree (a push, a publish, a merge before finishing). Defer the task, as
above, with a register row naming the operation. The finish action is the one
exception.

## The budget line

While a run is bound to this session, every budget line but
`scripts/context-size --plan` prints the run's own verdict:

    budget (auto): 312k of 465k (67%) — ok — source: record
    budget (auto): 471k of 465k (101%) — compact — source: record
    budget (auto, high): 724k of 720k (101%) — compact — source: record
    budget (auto, wave of 3): 190k of 185k (103%) — compact — source: record

- `ok`, or `unknown`: carry on; on `unknown`, record that with
  `scripts/auto-run ruling add`.
- `compact` (`scripts/context-size` exit 6): finish the task in flight through
  its `Task N: complete` line (a wave through its merge), run
  `scripts/auto-run task-complete`, then end the turn as Ending a turn says.
  In the wave loop, lower the width while `--wave` says `compact`, as on
  `handoff`; at width 1, compact.
- `handoff` (exit 5): the last compaction left too much behind. Finish the
  task in flight, then follow Clears.

The rules: compact at the task budget in the normal regime, or at 90% of the
compaction window in the high one, less 140k for each task of a wave beyond
the first. After a compaction of size P: P at 85% of the window or more hands
off; P at 85% of the task budget or more switches to the high regime;
anything smaller returns to the normal one. The tail rule, the final-phase
limit and relaxed mode do not apply. Finishing is never measured.

## Ending a turn

A run's turn ends only with one of two lines as the last line of the message:

- `Auto run: compacting` when `scripts/auto-run pending` says `compact`;
- `Auto run: clearing` after `scripts/auto-run clear` exits 0.

`scripts/auto-run pending` prints `compact`, `after-compact`, `handoff`,
`clear`, `resume` or `none`. `handoff` is a compaction that left too much
behind; it stays until `scripts/auto-run clear` turns it into `clear`, and the
Stop hook holds a turn that tries to end before that.

Nothing you started may still run in the background. The Stop hook holds any
other ending once. The cockpit then compacts, or clears the session and binds
the new one, and submits the next prompt itself.

## After a compaction

The cockpit's prompt asks you to run `scripts/auto-run after-compact` first.
It prints `continue` (exit 0) or `handoff` (exit 5). It settles only a
compaction that was booked (`pending` is `after-compact`): while a `clear` or
`handoff` is pending it prints `handoff` and changes nothing.

- `continue`: carry on with the phase `scripts/auto-run status` names. In
  `execute` and `final`, follow the After compaction steps of the execution
  skill the plan's Execution line names, for the plan `status` names: its
  workspace, ledger and `git log` are the authority. `latest.md` predates the
  execution worktree, so do not resume from it. When the line says the size
  is unknown, record that with `scripts/auto-run ruling add`.
- `handoff`: follow Clears.

## Clears

The step that hands off owns the clear; dr-forge:handoff itself never runs it.
Run dr-forge:handoff first (`scripts/auto-run clear` reads the first prompt
and launch command `scripts/next-step` wrote to `latest.md`), then:

- **Plan saved**, and **spec to plan** over the `--plan` limit:
  `scripts/auto-run clear --phase`.
- **A compaction that left too much:** `scripts/auto-run clear`.

On exit 0, end the turn with `Auto run: clearing` as the last line, below the
next-step block. The cleared session runs on the launch command's model and
effort. On exit 5 the run has stopped (the third self-resume in a row without
a completed task): end with the next-step block alone, as Stopping says.

## Stopping

`scripts/auto-run stop --reason "<why>"` ends the run; without a reason it
ends as finished. Run it, then end as the attended flow would, when:

- your human partner asks you to stop;
- dr-forge:resume-execution would stop to ask (a worktree whose branch is
  gone);
- finishing hits one of its unattended stops (failing tests at its first
  step or on the merged result, a rejected push, a refused worktree removal).

When `scripts/auto-run clear` exits 5, or the cockpit's prompt says the run
stopped, it has already stopped: end with the next-step block. The cockpit
sends one Discord `blocked` notice when a run stops with a reason.

## Finishing

Finishing carries out the `finishAction` setting at once, into the base
`scripts/auto-run status` names: `merge` and `pr` as named; `keep`, `ask` and
`wait` keep the branch, and so does `merge` when the base is `none`. On a
detached HEAD there is no merge: `merge` keeps the branch and `pr` pushes a new
branch from the detached HEAD. A `pr` with base `none` opens its request
against the forge's default branch. No menu, no wake. Its final message lists every `Ruling:` ledger line, every line of
`scripts/auto-run ruling list` and every deferred row the run added, and it
runs `scripts/auto-run stop` before the next-step block.
