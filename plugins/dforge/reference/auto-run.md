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

    scripts/auto-run start --spec <spec path> --isolation <worktree|in-place> [--register <register path>]

`--isolation` is the spec review's `Worktree:` answer, or the offer's choice,
under `worktree=ask`; `worktree` under `always`; `in-place` under `never`. A
preference your human partner's instructions name outranks the setting.

`--register` names the item register when one is open; without it the script
creates `<docs>/registers/<date>-<slug>-auto.md` in this checkout and prints
its path. The branch checked out here becomes the run's base, the branch the
finish merges into. Exit 4 means another live run is active, exit 2 that this
session cannot be bound: say so in one line and continue without an auto run.
Exit 2 with `auto-run: the cockpit in this session does not see this run`
means the cockpit did not echo the binding within `DFORGE_BIND_WAIT` seconds
(default 10); nothing was started.

`start` writes the session's binding file,
`~/.claude/dforge/sessions/run/<session>.json`, which names the primary
checkout holding the run's state. Every script, the Stop hook and the cockpit
find the run through it, so a session started in one repository can run a
plan in another. A run of this session's in the working directory's own
repository is found first, unless it has ended and the binding names an
active one.

## While a run is bound to this session

`scripts/auto-run status` exits 0 and names the phase, the regime, the pending
action, the plan, the base and the register, then prints `api rungs: off`
when the Decisions API is off and every API budget cap is 0. Every `scripts/auto-run` command
exits 0 when done, 1 when it failed (no handoff file to read, or `jq` or
`mktemp` failed), 2 on bad usage, 3 when no run is bound to this session, 4
when refused, 5 when the run stopped (`handoff` for `after-compact`), 6
for `compact`, and 7 when a command that reads the working directory's git
state (`task-complete`, `phase execute|final|finish`, `setup-branch`, `clear`,
`switch`) runs outside the run's checkout: run the same command again with
the `cd '<path>' && …` prefix it printed. Exit 7 is never a reason to stop the
run. Every other command works from any directory. After its status line,
`status` prints `cockpit: sees this run` or `cockpit: does not see this run`.
Then:

- **Ask nothing.** No clarifying question, approval or menu. What you would
  have asked goes to the ladder under Rulings.
- **Skipped questions:** the spec review stop,
  the worktree consent (asked at the spec review under `worktree=ask`),
  the finish-preference question, and the execution stops under Rulings.
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

## Run log

Each run event appends one row to `<state>/sdd/auto-run-log.tsv` in the run's
primary checkout, with five tab-separated columns: the UTC time, the event
(`start`, `bind`, `rebind`, `phase`, `compacted`, `clear`, `switch`,
`stalled`, `hold`, `stop`, `resume`), the session, the phase at the event and
a detail (the spec, the primary, the new session or phase, `phase` or
`resume` for a clear, the stop reason). A new `start` keeps the file, so a
stopped run's history survives the next run. `scripts/auto-run log` prints
it, bound or not: the log of the run the session's binding names in another
checkout, as every command resolves it, else this checkout's; exit 3 when
there is none.

## Preflight

`scripts/auto-run preflight --isolation <worktree|in-place>` needs no run and
exits 0. It prints what would stop an unattended run: free space below
`DFORGE_PREFLIGHT_FREE` percent (default 15) on the checkout's or the temp
directory's filesystem, a refused git write in the primary checkout, and with
`--isolation worktree` a refused scratch worktree in `.worktrees` (or an
existing `worktrees`); `preflight: ok` when there is none. Then one line per
review family: its gate's answer, or `gate failed: <its error>` when the gate
could not answer, and its `<id>Review` setting.
dforge:brainstorming runs it before the spec review and shows every line at
the top of that message, so a blocker is met while your human partner is
present.

## The spec

Under `autoRun=on` the critic and the Fable review run before the run starts,
at the spec's depth (below), as dforge:brainstorming §Auto by default says:
what Fable leaves undecided is
asked at the spec review instead of deferred, and its rulings are imported
after `start` with `scripts/auto-run ruling add`. The rest of this section is
the spec phase of a run started under `autoRun=ask`.

The spec's `**Depth:**` line sizes this phase. At `light` the self-review
round is the whole of it: dispatch no critic and no Fable review, record no
spec ruling, and go on to the plan. Under `autoRun=ask`, a light run started
from the offer therefore reaches execution with no reader of the written spec:
every design section and acceptance statement was approved by hand before the
run started, and that is the review light keeps. At `standard` the critic is
folded into one Fable round with no second round; at `full` the separate
critic runs first and Fable for one or two rounds. The depth decides, not the
trigger list. What follows is the phase at `standard` and `full`.

After your own self-review round and the architecture critic
(dforge:brainstorming §Architecture critic, which folds the critic into
Fable's first round at depth standard), dispatch
`dforge:judge-fable` on
the spec against the approved design: the design sections as approved,
verbatim, and the spec's path, naming its report file as dforge:brainstorming's
The spec review's report says (`<state>/spec-review-<spec name>-<r>-report.md`):
it is told to write nothing else, and reply in at most 10 lines. Apply what it rules, and record each ruling
with
`scripts/auto-run ruling add "Fable, spec: <item> — <ruling>"`. Add each item
it leaves undecided or without a suggestion to the run's register, except a
critic Blocker, which takes the note below:

    scripts/register add <register> "<item>" --state deferred --note "Fable: <its words>"

Fable runs one round. A second runs only when round 1 leaves a Blocker or High
finding open at depth `full`, and checks only those answers; at depth
`standard` no second round runs. At either depth, anything still open after
the last round, a Blocker or High finding of Fable's included, is deferred the
same way. Then write
the plan in this session: `scripts/context-size --plan` does not run in an
auto run.

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

The ladder for anything you would have asked. The `scripts/decide` and
`scripts/run-api-judge` calls of rungs 1 and 2 are made only on Claude Code,
and only while `scripts/auto-run status` does not print `api rungs: off`. On
that line skip both calls: a choice item starts at rung 2, and a ruling the
route gives to `dforge:judge-opus` goes to that seat at once, with no
background run and no turn end:

1. **The Decisions API, for a choice item.** A choice item is a spec or
   planning choice before execution: a question with its options, your
   recommendation first. Run

       scripts/decide ask --id <id> --question "<q>" --options "<recommended> | <alternative> [| <alternative>]..." --evidence <the spec> [--evidence <the plan>] [--evidence <a file the question names>]...

   List only real options: `decide` adds `other` itself and refuses an
   option named `other` with exit 2. On exit 0 the printed ruling stands:
   record it with
   `scripts/auto-run ruling add "Decisions API: <item> — <ruling>"`. On
   exit 3, or any other exit, go on to rung 2. An acceptance statement rated below `high` is
   not a choice item and starts at rung 2. An item a judge has declined to
   rule never returns to this rung.
2. **Opus, on an API budget first.** During execution, the ruling seat
   (`dforge:judge-opus`) as the execution skills dispatch it; CONFIRMED-GAP,
   PARK and AMEND are carried out as always. Before execution (a spec or
   planning choice), the seat is given the question, its options with your
   recommendation first, the spec's path and the plan's path when one
   exists; it is asked for `ruling: <choice> — <reason>` or `no ruling`,
   told the report file `<state>/rulings-preexec-<k>-report.md` (`<k>` the
   next unused number) and to write nothing else, and to reply in at most
   10 lines; the report opens with `## Verdict` holding
   `ruling: <choice> — <reason>` or `no ruling`.

   Either way, a ruling the route gives to `dforge:judge-opus` goes to an
   API-billed judge first. Write the prompt the seat would get to a file
   under `<state>` and run, as a background Bash call with `timeout`
   2520000 and its output neither piped nor redirected:

       scripts/run-api-judge --prompt <file> --report <the report file> --cwd <the worktree> [--add-dir <dir>]...

   with one `--add-dir` for each directory outside the worktree that the
   prompt points at (the workspace holding the items file, ledger and
   amendments, and the documents root). Then end the turn and wait for its
   notification. Until it ends, change nothing under `--cwd` that git does
   not ignore, and run no git command there that changes its index or
   HEAD: a change voids the paid run. On exit 0 read the report's
   `## Verdict` as the seat's. On exit 3 dispatch `dforge:judge-opus`
   yourself, as above. Three rulings skip `scripts/run-api-judge` and go to
   the subscription seat directly: a `preflight` ruling, the fresh dispatch
   after `plan-amend` rejects an AMEND, and the independent confirmation
   of a Header amendment. A ruling the route gives to
   `dforge:judge-sonnet-high` is dispatched as today.

   When `decisionApi` is `shadow` and this rung ruled a choice item, run
   `scripts/decide record --id <id> --ruling "<the option it chose, or other>"`.

3. **The pending list.** An Opus `BLOCKED` or `no ruling`, or a task still
   open at its fix cap, is added:

       scripts/auto-run decision add --id <id> --question "<q>" --options "<recommended | other>" --opus-reason "<why Opus did not rule>" [--task <N>]

4. **Fable, in one batch.** Dispatch `dforge:judge-fable` once with every
   line of `scripts/auto-run decision list`, asking for each item
   `ruling: <choice> — <reason>` or `no ruling`, naming the report file
   `<state>/rulings-fable-<k>-report.md` and telling it to
   write nothing else, and reply in at most 10 lines; its `## Verdict` section holds one
   `### Item <id>` block per item with `ruling: <choice> — <reason>` or
   `no ruling`. Read only that section. Carry out each ruling as a
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

      Task <N>: complete (deferred by the auto run) — done: nothing; verified: not run; remaining: <the item>[; partial commits <a7>..<b7>, kept for the final review]; discovered: none; assumptions: none; Ruling: <why> — <cost if wrong>

  Add one deferred register row per such task. Recovery, `scripts/next-step`
  and the final review count the line as complete, so the run moves on.
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
task and before the final review. Tasks that do
not depend on a deferred task keep running.

**Never performed in an auto run,** whatever a ruling says: an irreversible or
destructive operation, a security-sensitive action, or a side effect
outside the execution workspace (a push, a publish, a merge before finishing). Defer the task, as
above, with a register row naming the operation. The finish action is the
first exception. The second is the `**Early CI:**` push and workflow dispatch,
performed only when the header line carries `— consented <YYYY-MM-DD>`.

## The budget line

While a run is bound to this session, every budget line but
`scripts/context-size --plan` prints the run's own verdict:

    budget (auto): 312k of 465k (67%) — ok — source: record
    budget (auto): 471k of 465k (101%) — compact — source: record
    budget (auto, high): 724k of 720k (101%) — compact — source: record

- `ok`, or `unknown`: carry on; on `unknown`, record that with
  `scripts/auto-run ruling add`.
- `compact` (`scripts/context-size` exit 6): finish the task in flight through
  its `Task N: complete` line, run
  `scripts/auto-run task-complete`, then end the turn as Ending a turn says.
  `scripts/task-close` measures before it records the completion and prints
  the run's line last (exit 0 whatever the verdict): `compact` there means
  ending the turn on `Auto run: compacting` before the next task opens.
  In `execute`, the lines `scripts/task-close` and `scripts/task-brief` print
  say `compact` from the limit minus 20% of the task budget (240k at a 300k
  budget), so the compaction falls between two tasks, and a compaction booked
  there stays pending until it runs.
- `handoff` (exit 5): the last compaction left too much behind. Finish the
  task in flight, then follow Clears.

The rules: every phase compacts at its limit, the task budget in the normal
regime or 90% of the compaction window in the high one. In `spec`, `plan`,
`final` and `finish` the high regime is capped at the hard limit
([session-budget.md](session-budget.md): the lower of 125% of the task budget
and the compaction point less 40,000). After a compaction of size P: P at 85% of the window or more hands
off; P at 85% of the task budget or more switches to the high regime;
anything smaller returns to the normal one. In the `plan`, `final` and
`finish` phases P never hands off. Three compactions in `spec`, `plan`,
`final` or `finish` with no ledger line, commit or saved draft between them
stop the run (`3 compactions in <phase> without progress`); `execute` stops
after three without a completed task. The tail rule, the final-phase
limit and relaxed mode do not apply.

`scripts/auto-run phase plan`, `phase execute`, `phase final`,
`task-complete` and `ruling add` print the run's budget line as their last
line and keep their own exit status; `attach` and `phase finish` print none,
since a clear follows both.

The cockpit measures each main response as well. At the limit with nothing
pending it books the compaction through `scripts/auto-run due` and appends
one note, in any mode, fast mode included, and no second one until the next
compaction:

    dforge: budget: 310k of 300k — compact. Finish the step in hand, record it, then end the turn on `Auto run: compacting`.

A step is in hand until its durable record is current: a task through its
`Task N: complete` line; a final-review step through its ledger line; a plan
draft or review round through the saved file; a finishing step through its
commit or ledger line. No note forces a compaction in the middle of a step.
After a mid-step compaction Claude Code starts on its own, the After
compaction steps resume as before.

## Ending a turn

A run's turn ends only with one of three lines as the last line of the message:

- `Auto run: compacting` when `scripts/auto-run pending` says `compact`;
- `Auto run: clearing` after `scripts/auto-run clear` exits 0;
- `Auto run: switching` after `scripts/auto-run switch` exits 0.

One more ending carries no sentinel line: a plain end of turn that waits for
the notification of a background call this session started and must read
(the §Rulings `scripts/run-api-judge` call, the final review's panel,
`scripts/ci-mirror` or the integration check). It carries no next-step block
either. `turn-end.sh` lets a plain stop through while that work is listed
(`scripts/in-flight`).

A message that ends on a sentinel line carries no next-step block: no launch
command and no first prompt to paste. `scripts/next-step` still writes the
block into the handoff, where `scripts/auto-run clear` reads it, and the
cockpit submits the first prompt itself; printed in the message, it reads as a
request to start the next session by hand while the run is still going. Only
a run that has stopped ends on the block (§Stopping).

`scripts/auto-run pending` prints `compact`, `after-compact`, `handoff`,
`clear`, `resume`, `switch` or `none`. `handoff` is a
compaction that left too much
behind; it stays until `scripts/auto-run clear` turns it into `clear`, and the
Stop hook holds a turn that tries to end before that.

While the run's checkout lies outside the directory the session started in,
the first prompt, the after-compaction prompt and the Stop hook's hold
messages say to run every command as `cd '<checkout>' && …`.

Apart from the wait for a background call above, nothing you started may
still run in the background. The Stop hook holds any other ending, its
retries included, up to three times in a row; the fourth stops the run
(`the turn ended 3 times in a row without its sentinel line`)
and is held once more to end as Stopping says. The cockpit then compacts, or
clears the session and binds the new one, and submits the next prompt itself.

## After a compaction

Run `scripts/auto-run after-compact` first after any compaction, whether or
not a prompt asks for it: the cockpit's prompt asks after the compactions it
runs, but a compaction Claude Code starts on its own comes with no prompt.
It prints `continue` (exit 0) or `handoff` (exit 5); in the `plan`, `final`
and `finish` phases it always prints `continue`, since the plan and the final
review stay in this session and finishing runs in one of its own. It settles only a
compaction that was booked (`pending` is `after-compact`): while a `clear` or
`handoff` is pending it prints `handoff` and changes nothing. In every phase
the budget lines after it measure against the limit again: one compaction no
longer makes the later lines of `final` or `finish` say `ok`.

- `continue`: carry on with the phase `scripts/auto-run status` names. In
  `plan`, resume dforge:writing-plans from the spec and the plan file on disk
  (before `attach`, the newest file in the plans directory whose `**Spec:**`
  line names the spec). In
  `execute` and `final`, follow the After compaction steps of the execution
  skill the plan's Execution line names, for the plan `status` names: its
  workspace, ledger and `git log` are the authority. A handoff in this
  checkout can predate the run, so do not resume from it. When the line says the size
  is unknown, record that with `scripts/auto-run ruling add`.
- `handoff`: follow Clears.

## The switch

Once the plan is reviewed and attached, the run moves to execution in a
cleared session; dforge:handoff does not end the run. In order:

1. When the spec's `## Decisions` holds a `Finish: <action>` line,
   `scripts/finish-choice set <action> --plan PLAN_FILE`.
2. dforge:handoff steps 0-3: reconcile background agents and shells, commit
   the plan and the spec, and write the handoff's notes file. Do not end the
   session.
3. `scripts/next-step --notes <notes> PLAN_FILE`, `<notes>` being the file
   step 2 wrote. Exit 5 means background work is still
   listed: run `scripts/in-flight`, wait for or stop each launch it lists, and
   run the same `scripts/next-step --notes <notes> PLAN_FILE` again; a second exit 5 runs
   `scripts/auto-run stop --reason "background work still running at the switch: <next-step's message>"`
   and ends as Stopping says. Any other nonzero exit means the handoff was
   not written: run `scripts/auto-run stop --reason "the handoff file could
   not be written"` and end as Stopping says.
4. `scripts/auto-run switch`, which also sets the phase to `execute`. It exits
   4 without an attached plan, or when the first prompt in the plan's handoff
   names another plan; on exit 4 or any other nonzero exit except 7, stop the
   run the same way. Exit 7 means the session is in another checkout: run the
   command it prints, with its `cd '<path>' && …` prefix, again. On exit 0,
   end the turn with `Auto run: switching` as its last line.

The cockpit then runs `scripts/auto-run clear --phase`, clears the session and
binds the new one, sends that session's requests on the model and effort of
the plan's launch command without changing the user's settings, and submits
the plan's first prompt. Follow it in the new session. No ledger exists yet, so the
execution skill starts at its Setup, workspace first: `scripts/auto-run status`
says setup is due until `phase execute` runs from the execution workspace. A
switch is a phase transition: it never counts as a self-resume. A failure in
either stage is retried once in that stage; the second stops the run.

## Clears

The step that hands off owns the clear; dforge:handoff itself never runs it.
Run dforge:handoff first (`scripts/auto-run clear` reads the first prompt
and launch command `scripts/next-step` wrote to the attached plan's handoff,
the file `scripts/next-step --target` names: the checkout the next session
works in, its first prompt naming that checkout; with no plan attached, the
newest handoff whose marker names this run's session), then:

- **A compaction that left too much:** `scripts/auto-run clear`.
- **The switch** (§The switch): the cockpit runs `scripts/auto-run clear --phase` itself.
- **Finishing** (§Finishing): `scripts/auto-run clear --phase`.

A saved plan moves through §The switch, where the cockpit runs the phase clear. A run
started under `autoRun=ask` also writes its plan in the session that wrote the
spec.

If `scripts/next-step` exits 4, do not run `scripts/auto-run clear`: the
handoff it would read is an older one. Run `scripts/auto-run stop
--reason "the handoff file could not be written"` and end as Stopping says.

If it exits 5, background work is still listed and nothing was written: run
`scripts/in-flight`, wait for or stop each launch it lists, and run the same
`scripts/next-step --notes <notes> PLAN_FILE` again, as §The switch step 3 does. A second
exit 5 runs
`scripts/auto-run stop --reason "background work still running at the clear: <next-step's message>"`
and ends as Stopping says; do not run `scripts/auto-run clear`.

When `scripts/auto-run clear` exits 0, end the turn with `Auto run: clearing`
as the last line, with no next-step block above it (§Ending a turn). The
cleared session runs on the
launch command's model and effort: the cockpit sends its main-loop requests on
them and never writes them to the user settings. On exit 5 the run has stopped (the
third self-resume in a row without a completed task): end with the next-step
block alone, as Stopping says.

## Stopping

`scripts/auto-run stop --reason "<why>"` ends the run; without a reason it
ends as finished. Run it, then end as the attended flow would, when:

- your human partner asks you to stop;
- dforge:resume-execution would stop to ask (a worktree whose branch is
  gone, or the run's branch is gone);
- finishing hits one of its unattended stops (failing tests at its first
  step or on the merged result, a rejected push, a refused worktree removal);
- `scripts/next-step` exits 4 during a clear (see Clears).
- `scripts/next-step` exits 5 a second time during a clear (see Clears).

Exit 7 from a `scripts/auto-run` command is never one of these: run the same
command again with the `cd '<path>' && …` prefix it printed.

When `scripts/auto-run clear` exits 5, or the cockpit's prompt says the run
stopped, it has already stopped: end with the next-step block. A handoff
another live session holds stops the run the same way: `scripts/handoff claim`
(exit 3) and `scripts/next-step` (exit 7) run `scripts/auto-run stop --reason
"handoff <key> is held by <id8>"` themselves, so report the holder and ask. The cockpit
sends one Discord `blocked` notice when a run stops with a reason.

## Resuming

`scripts/auto-run resume` reactivates a stopped run and binds it to the
calling session, which needs a live cockpit, as `start` does. It keeps the
phase, base branch, plan, register, isolation, branch and run totals, sets the
stall, resume, failure and API-error counts and `compactionsSinceTask` to 0,
clears the pending stage, and moves the stop to `stopHistory`
(`{reason, at, resumedAt}`). It records the resuming plugin's version and root
and prints the status line.

It refuses with exit 4, naming why, when:

- the run is active, or it finished (stopped with no reason);
- the stop was a workspace guard or a carried path (`stoppedKind` `guard` or
  `carried`; for an older run, the reason `task-complete` wrote);
- a carried path was committed since the run's branch began, in any phase;
- in the execute phase once Setup is done, or in the final phase, a task step
  here would trip the guard (resume from the run's workspace), or the work is
  gone: an in-place run's branch, or a worktree run's plan worktree.

Exit 2 means this session has no live cockpit, or, with `auto-run: the
cockpit in this session does not see this run`, that the cockpit did not echo
the binding (§Starting); the run is left as it was.

## Finishing

Finishing runs in a session of its own, measured against the run's limit like
every phase (`scripts/context-size --finish` prints the run's line and is not
needed there). At the entry of
dforge:finishing-a-development-branch, a run whose phase is not `finish` runs,
in order, `scripts/auto-run phase finish`, dforge:handoff steps 0-3 (do not
end the session), `scripts/next-step --notes <notes> PLAN_FILE` with the
notes file handoff step 3 wrote, and
`scripts/auto-run clear --phase`, and ends the turn with `Auto run: clearing`.
A commit in handoff step 2 moves HEAD and costs one suite run at finishing's
first step. `next-step`'s exits 4 and 5 are handled as §Clears says; a nonzero
`clear --phase` other than exit 7 stops the run as §Stopping says; on exit 7,
run the printed `cd '<path>' && …` command again. The cleared session arrives
through dforge:resume-execution with phase `finish`, and has no conversation
behind it: what the final review left open is in the ledger's parked and
`Ruling:` lines, the `final review residual` register rows, and the
workspace's `final-fix-report.md` and `final-rereview-report.md`, which exist
only when a fix wave or a scoped re-review wrote them, and its
`final-review-report.md`, `final-dedupe-report.md` and `lens-<id>-report.md`.
Read those that exist for Step 5b's findings and for the review's report.

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
with base `none` opens its request against the code host's default branch. No
menu. Its final message lists every `Ruling:` ledger line, every line of
`scripts/auto-run ruling list`, every line of `scripts/api-spend status`,
every deferred row the run added,
every `demo` statement of the spec, every lens
named by a `final review lens-skipped <id> reason=<reason>` line in the ledger,
whatever its reason (final-review.md step 4 writes them; do not run
`scripts/lens-route --final` here, since after a merge its base..HEAD range is
empty), and, when the ledger's `Review depth:` line says `light`, every `test`
statement of the spec under `not verified (depth light)`. It names each of
`decisionApi`, the three `apiBudget` caps and the three `DFORGE_*_API_KEY`
variables that is still off, 0 or unset.
Then the final message prints `scripts/auto-run counters` verbatim, then
the plan's usage summary from `<state>/sdd/usage-report-<plan>.json` in the
primary checkout (run `scripts/usage-report --plan PLAN_FILE --save` first when
the cleanup did not save it): the cost per completed task beside the
segment-only figure, and per task its turns, lookups, context growth and
seconds waiting on background work. When the save printed
`usage summary missing: <reason>` or wrote no file, print that line, or
`usage summary missing: not saved`, instead. Last comes the owner follow-up:
`Follow-up: update each repository's CLAUDE.md Compact Instructions to match
reference/session-budget.md §Compact Instructions for CLAUDE.md.` It runs
`scripts/auto-run stop` with no `--reason` before the next-step block: a
reason marks the run as stopped and sends a `blocked` notice.
