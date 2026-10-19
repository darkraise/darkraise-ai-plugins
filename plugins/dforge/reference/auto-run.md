# Auto run

The default on Claude Code (`autoRun=on`): once your human partner approves the
written spec at the spec review, dforge writes the plan, executes, reviews and
finishes without asking anything. Under `autoRun=ask` it is offered once the
design is approved and starts before the spec is written; `autoRun=off` never
starts one. The designs are
`docs/superpowers/specs/2026-10-13-dr-forge-auto-run-design.md` and
`docs/superpowers/specs/2026-10-18-auto-execution-default-design.md` in the
dforge repository; this file is the contract the skills cite. Every
`scripts/…` command runs as `bash <plugin-root>/scripts/<name>`.

Claude Code only: the cockpit mod compacts, switches and clears the session.
No run starts on Codex, where `autoRun=on` behaves as `off`.

## Starting

Under `autoRun=on`, dforge:brainstorming starts it once your human partner
approves the spec at the spec review (dforge:brainstorming §Auto by default).
Under `autoRun=ask` it offers it once, after the last design section is
approved and before the spec is written, and starts it on yes. Either way,
from the checkout the design was made in:

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
  `scripts/auto-run attach --plan <plan>` once the plan is reviewed, then
  `scripts/auto-run switch` (see The switch),
  `scripts/auto-run phase execute` when execution starts,
  `scripts/auto-run phase final` before the final review and
  `scripts/auto-run phase finish` when finishing starts.
- **Each completed task:** `scripts/auto-run task-complete` right after its
  `Task N: complete` ledger line.
- **A message from your human partner** does not stop the run: answer it and
  continue, unless it asks you to stop (see Stopping).

## The spec

Under `autoRun=on` the critic and the Fable review run before the run starts,
as dforge:brainstorming §Auto by default says: what Fable leaves undecided is
asked at the spec review instead of deferred, and its rulings are imported
after `start` with `scripts/auto-run ruling add`. The rest of this section is
the spec phase of a run started under `autoRun=ask`.

After your own self-review round and the architecture critic
(dforge:brainstorming §Architecture critic), dispatch `dforge:judge-fable` on
the spec against the approved design: the design sections as approved,
verbatim, and the spec's path. Apply what it rules, and record each ruling
with
`scripts/auto-run ruling add "Fable, spec: <item> — <ruling>"`. Add each item
it leaves undecided or without a suggestion to the run's register, except a
critic Blocker, which takes the note below:

    scripts/register add <register> "<item>" --state deferred --note "Fable: <its words>"

At most two Fable rounds run (review, revise, re-review); anything still open
after the second is deferred the same way. Then write the plan in this
session: `scripts/context-size --plan` does not run in an auto run.

**Acceptance statements and critic findings in the spec phase:**

- A statement added or changed while writing the spec and rated below `high`
  is never asked: it goes up the ladder under Rulings. A seat ruling raises it
  to `high`; record the ruling with `scripts/auto-run ruling add`.
- Give Fable the spec's `## Critic findings` section with the spec; it checks
  each answer to a Blocker or High finding. A Blocker it leaves undecided after
  its rounds is added with
  `scripts/register add <register> "<the finding>" --state deferred --note "critic Blocker unresolved"`
  and marked `unresolved — row <id>` in `## Critic findings`. The run
  continues, and finishing keeps the branch.

## Rulings

The ladder for anything you would have asked:

1. **Opus.** During execution, the ruling seat (`dforge:judge-opus`) as the
   execution skills dispatch it; CONFIRMED-GAP, PARK and AMEND are carried out
   as always. Before execution (a spec or planning choice), dispatch
   `dforge:judge-opus` yourself with the question, its options with your
   recommendation first, the spec's path and the plan's path when one exists,
   asking for `ruling: <choice> — <reason>` or `no ruling`.
2. **The pending list.** An Opus `BLOCKED` or `no ruling`, or an implementer
   that exhausted the ladder, is added:

       scripts/auto-run decision add --id <id> --question "<q>" --options "<recommended | other>" --opus-reason "<why Opus did not rule>" [--task <N>]

3. **Fable, in one batch.** Dispatch `dforge:judge-fable` once with every
   line of `scripts/auto-run decision list`, asking for each item
   `ruling: <choice> — <reason>` or `no ruling`. Carry out each ruling as a
   ruling-seat verdict. Record it as a `Ruling:` ledger line when the plan's
   ledger exists (`Task <N>: Ruling: …` for a task's item), and with
   `scripts/auto-run ruling add` before it does. Then
   `scripts/auto-run decision clear`.

**When Fable gives no ruling:**

- **A task's item:** the task is deferred. Write its terminal ledger line,
  and the same line for every task that depends on it: a task whose
  `**Depends on:**` line names it, or, in a plan without those lines, a later
  task whose `Consumes:` line cites a Contracts entry the deferred task's
  `Produces:` line cites:

      Task <N>: complete (deferred by the auto run) — done: nothing; verified: not run; remaining: <the item>[; partial commits <a7>..<b7>, kept for the final review | ; unmerged task ref <ref>]; discovered: none; assumptions: none; Ruling: <why> — <cost if wrong>

  Add one deferred register row per such task. Recovery, `scripts/next-step`
  and the final review count the line as complete, so the run moves on. In a
  wave, a deferred task's branch is not merged, so its commits lie outside the
  final review's range: its line takes `unmerged task ref <ref>`, the ref
  `scripts/wave ref PLAN_FILE <N>` prints, in place of the partial-commits
  clause, and its register row's note names the same ref. Only outside a wave
  are partial commits kept for the final review.
- **A spec or planning choice:** take the option listed first, record
  `scripts/auto-run ruling add "unconfirmed: <choice> — Fable gave no ruling"`,
  and add a deferred register row naming the choice.
- **An acceptance statement in the spec phase:** the statement is deferred, not
  guessed:
  `scripts/register add <register> "A<n>: <statement>" --state deferred --note "Fable gave no ruling"`,
  and its spec line becomes `A<n>. deferred — register row <id>`. It is the one
  spec choice that does not take the option listed first.
- **A QA `acceptance-ambiguous` item:** PARK it, as
  [final-review.md](final-review.md) step 0.5 says, and the final review
  continues.
- **A `final-residual` item** (a final-review finding that belongs to no open
  task): park it and add it to the run's register with
  `scripts/register add <run register> "<the finding>" --state deferred --note "final review residual"`.
  Such a row keeps a `merge` finish (§Finishing).

A batch runs at once for a blocked task and for a QA `acceptance-ambiguous`
item, and otherwise whenever the list is
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
anything smaller returns to the normal one. In the `plan`, `final` and
`finish` phases P never hands off, and once a compaction has run in `final` or
`finish` every budget line says `ok`. The tail rule, the final-phase
limit and relaxed mode do not apply. Finishing is never measured.

## Ending a turn

A run's turn ends only with one of three lines as the last line of the message:

- `Auto run: compacting` when `scripts/auto-run pending` says `compact`;
- `Auto run: clearing` after `scripts/auto-run clear` exits 0;
- `Auto run: switching` after `scripts/auto-run switch` exits 0.

`scripts/auto-run pending` prints `compact`, `after-compact`, `handoff`,
`clear`, `resume`, `switch`, `switch-resume` or `none`. `handoff` is a
compaction that left too much
behind; it stays until `scripts/auto-run clear` turns it into `clear`, and the
Stop hook holds a turn that tries to end before that.

Nothing you started may still run in the background. The Stop hook holds any
other ending, its retries included, up to three times in a row; the fourth
stops the run (`the turn ended 3 times in a row without its sentinel line`)
and is held once more to end as Stopping says. The cockpit then compacts, or
clears the session and binds the new one, and submits the next prompt itself.

## After a compaction

Run `scripts/auto-run after-compact` first after any compaction, whether or
not a prompt asks for it: the cockpit's prompt asks after the compactions it
runs, but a compaction Claude Code starts on its own comes with no prompt.
It prints `continue` (exit 0) or `handoff` (exit 5); in the `plan`, `final`
and `finish` phases it always prints `continue`, since the plan, the final
review and finishing stay in this session. It settles only a
compaction that was booked (`pending` is `after-compact`): while a `clear` or
`handoff` is pending it prints `handoff` and changes nothing.

- `continue`: carry on with the phase `scripts/auto-run status` names. In
  `plan`, resume dforge:writing-plans from the spec and the plan file on disk
  (before `attach`, the newest file in the plans directory whose `**Spec:**`
  line names the spec). In
  `execute` and `final`, follow the After compaction steps of the execution
  skill the plan's Execution line names, for the plan `status` names: its
  workspace, ledger and `git log` are the authority. `latest.md` predates the
  execution worktree, so do not resume from it. When the line says the size
  is unknown, record that with `scripts/auto-run ruling add`.
- `handoff`: follow Clears.

## The switch

Once the plan is reviewed and attached, the session moves to execution in
place; dforge:handoff does not end it. In order:

1. When the spec's `## Decisions` holds a `Finish: <action>` line,
   `scripts/finish-choice set <action> --plan PLAN_FILE`.
2. dforge:handoff steps 0-3: reconcile background agents and shells, commit
   the plan and the spec, and update the handoff notes. Do not end the session.
3. `scripts/next-step PLAN_FILE`. Exit 5 means background work is still
   listed: run `scripts/in-flight`, wait for or stop each launch it lists, and
   run `scripts/next-step PLAN_FILE` again; a second exit 5 runs
   `scripts/auto-run stop --reason "background work still running at the switch: <next-step's message>"`
   and ends as Stopping says. Any other nonzero exit means `latest.md` was
   not written: run `scripts/auto-run stop --reason "the handoff file could
   not be written"` and end as Stopping says.
4. `scripts/auto-run switch`, which also sets the phase to `execute`. It exits
   4 without an attached plan, or when the first prompt in `latest.md` names
   another plan; on exit 4 or any other nonzero exit, stop the run the same
   way. On exit 0, end the turn with
   `Auto run: switching` as its last line.

The cockpit then compacts the session, keeping the spec, plan, register and
base paths and dropping the design conversation (`compacted --switch` leaves
`switch-resume` pending), runs `/model` and `/effort` from the plan's launch
command, puts back the user's default model and effort, and submits the plan's
first prompt behind "Run `scripts/auto-run after-compact` first." Run it, then
follow the first prompt in this same session. No ledger exists yet, so the
execution skill starts at its Setup, worktree first: `scripts/auto-run status`
says setup is due until `phase execute` runs from the execution worktree. A
switch is a phase transition:
it never counts as a self-resume. Its compaction is measured in the `execute`
phase, so one that leaves 85% of the window or more hands off as Clears says.
A failure in either stage is retried once in that stage; the second stops the
run.

## Clears

The step that hands off owns the clear; dforge:handoff itself never runs it.
Run dforge:handoff first (`scripts/auto-run clear` reads the first prompt
and launch command `scripts/next-step` wrote to `latest.md`), then:

- **A compaction that left too much:** `scripts/auto-run clear`.
- **A switch from inline to subagent mode** (dforge:executing-plans
  §Switching to subagent mode): `scripts/auto-run clear --phase`. A phase
  clear never counts as a self-resume.

Plan saved is no clear: the session switches in place (§The switch). A run
started under `autoRun=ask` writes its plan in the same session too.

If `scripts/next-step` exits 4, do not run `scripts/auto-run clear`: the
`latest.md` it would read is an older handoff's. Run `scripts/auto-run stop
--reason "the handoff file could not be written"` and end as Stopping says.

If it exits 5, background work is still listed and nothing was written: run
`scripts/in-flight`, wait for or stop each launch it lists, and run
`scripts/next-step PLAN_FILE` again, as §The switch step 3 does. A second
exit 5 runs
`scripts/auto-run stop --reason "background work still running at the clear: <next-step's message>"`
and ends as Stopping says; do not run `scripts/auto-run clear`.

When `scripts/auto-run clear` exits 0, end the turn with `Auto run: clearing`
as the last line, below the next-step block. The cleared session runs on the
launch command's model and effort; the cockpit then puts back the default model
and effort that its `/model` and `/effort` saved in the user settings, writing
them again until the engine reads them back. On exit 5 the run has stopped (the
third self-resume in a row without a completed task): end with the next-step
block alone, as Stopping says.

## Stopping

`scripts/auto-run stop --reason "<why>"` ends the run; without a reason it
ends as finished. Run it, then end as the attended flow would, when:

- your human partner asks you to stop;
- dforge:resume-execution would stop to ask (a worktree whose branch is
  gone);
- finishing hits one of its unattended stops (failing tests at its first
  step or on the merged result, a rejected push, a refused worktree removal);
- `scripts/next-step` exits 4 during a clear (see Clears).
- `scripts/next-step` exits 5 a second time during a clear (see Clears).

When `scripts/auto-run clear` exits 5, or the cockpit's prompt says the run
stopped, it has already stopped: end with the next-step block. The cockpit
sends one Discord `blocked` notice when a run stops with a reason.

## Finishing

Finishing carries out at once, into the base `scripts/auto-run status` names,
the choice `scripts/finish-choice get --plan PLAN_FILE` prints, which the spec
review recorded, or else the `finishAction` setting: `merge` and `pr` as
named; `keep`, `ask` and `wait` keep the branch, and so does `merge` when the
base is `none`. `merge`
also keeps the branch when the ledger holds a
`Task <N>: complete (deferred by the auto run)` line, so a deferred task's
partial commits reach the base only after a person has looked at them.
`merge` also keeps the branch when the `Acceptance QA: complete` line reports a nonzero count of
`cannot-test`, or when the run added a deferred register row
whose Item begins `A<n>:` or whose Note is `critic Blocker unresolved`: an
acceptance statement that failed or went unverified reaches the base only
after a person has looked
at it. The line's `fail` and `flaky` counts are not read: they are taken
before the fix wave, a failure that survives it is a deferred `A<n>:` row or a
red test at finishing's first step, and one the fix wave fixed does not keep
the branch. A row
deferred at the spec review, before the run started, counts as one the run
added. `merge` also keeps the branch when the run added a deferred row whose
Note is `final review residual`. On a detached HEAD there is no merge: `merge`
keeps the branch and `pr` pushes a new branch from the detached HEAD. A `pr`
with base `none` opens its request against the dforge's default branch. No
menu. Its final message lists every `Ruling:` ledger line, every line of
`scripts/auto-run ruling list`, every deferred row the run added,
every `demo` statement of the spec, every lens
named by a `final review lens-skipped <id> reason=cap` line in the ledger
(final-review.md step 4 writes them; do not run `scripts/lens-route --final`
here, since after a merge its base..HEAD range is empty), and it runs
`scripts/auto-run stop` with no `--reason` before the next-step block: a
reason marks the run as stopped and sends a `blocked` notice.
