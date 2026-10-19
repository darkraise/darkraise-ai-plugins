# Auto run reliability fixes

**Execution strategy:** sequential — most fixes edit the same few files
(the two execution skills, auto-run.md, `scripts/lib/auto-run.sh`, the
cockpit's `register.tsx`), so parallel parts would collide.

**Register:** docs/superpowers/registers/2026-10-18-auto-execution-default.md
(rows 13-24 and 26-31; the Low bundles, rows 25 and 32, stay deferred)

**Approach:** inline - skip 1: every root cause is located, by the
2026-10-19 end-to-end probe (row 11) or by the three Fable reviews of
2026-10-19 and verified against the code

## Decisions

The owner's answers on 2026-10-19.

1. Row 13 gets both the skill-text fix and a script guard.
2. The plan executes sequentially.
3. Scope: rows 13-15 plus every High and Medium finding of the two Fable
   reviews of the auto flow (rows 16-24, 26-31); the Low bundles stay
   deferred.

## Problem

An auto run must go from the approved spec to a finished branch with no
person present. The row 11 probe and three Fable reviews found ways it can
instead commit to the base branch, ask a question nobody answers, stall with
nothing to wake it, loop without a cap, or change the owner's settings. Each
section below names the register row it closes.

## Design

### A. Execution starts at Setup after the switch (row 13)

After the in-place switch a compaction summary sits above the plan's first
prompt, so the execution skill follows `## After compaction`, which never
reaches Setup; the probe's run committed every task to `main`.

1. **The first prompt says where to begin.** `scripts/next-step`, when the
   plan has no ledger, writes the first prompt as
   ``Continue `<plan>` with dforge:<skill>. No ledger exists yet: begin at the skill's Setup, worktree first; the first task is Task <N> (<title>).``
   The `**Next:**` line is unchanged. This reaches the switch (the cockpit
   submits the stored prompt) and every attended cold start.
2. **The compaction keeps the fact.** The cockpit's switch compaction
   instructions (`AUTO_SWITCH_INSTRUCTIONS` in `register.tsx`) add: "No task
   has started and no execution worktree exists yet; execution begins at the
   execution skill's Setup."
3. **The run records that Setup is due.** `ar_switch` sets `setupDue: true`.
   `scripts/auto-run status` adds `— setup due` to its line while it is set,
   and `after-compact` appends `; setup due: begin at the execution skill's
   Setup, worktree first` to a `continue` line. `phase execute`, when it
   passes the guard below, clears it.
4. **The skills check it first.** dforge:executing-plans and
   dforge:subagent-driven-development each open `## After compaction` with:
   "In an auto run, when `scripts/auto-run status` says setup is due, or when
   no ledger names this plan, no task has started: skip the rest of this
   section and follow Setup from its first step." The rest keep their order.
   The Auto run Setup bullet says to run `scripts/auto-run phase execute`
   from the execution worktree, and that exit 4 means the worktree step was
   skipped. auto-run.md §The switch says execution starts at Setup.
5. **The guard fails closed.** `scripts/auto-run phase execute` exits 4 when
   the caller is the primary checkout, that is when
   `git rev-parse --absolute-git-dir` equals
   `git rev-parse --path-format=absolute --git-common-dir` (both from git,
   so no path normalisation is needed), and prints
   `auto-run: this is the primary checkout; create the execution worktree first (dforge:using-git-worktrees), then run auto-run phase execute from it`.
   A run that started in a linked worktree passes, as it should: its
   execution worktree is another linked one, and using-git-worktrees creates
   none when already in one. `scripts/auto-run task-complete` run from the
   primary checkout stops the run with the reason `a task was completed in
   the primary checkout` and exits 5, so a controller that skipped
   `phase execute` too stops after its first task instead of finishing on the
   base. In a submodule, where `ar_path` already fails, both commands keep
   failing with exit 2 as today.

### B. The spec's finish line is read by the script (row 14)

`scripts/finish-choice get --plan PLAN_FILE`, with no `finish.json` yet,
locates the plan with `plan_locate`, reads its `**Spec:**` header line with
`plan_header_line` (stripping backticks as `next-step` does), resolves the
path with `dforge_resolve` (so mirrored documents and pre-4.0 prefixes work),
and reads that spec's `## Decisions` section up to the next `## ` heading,
skipping fenced blocks and stripping `\r`. A line matches when, after an
optional list marker (`-`, `*` or `<digits>.`) and spaces, it is
`Finish: merge`, `Finish: pr` or `Finish: keep` with nothing after the value
but spaces; a quoted or other value (`3. Finish: "Ask at spec review"`) does
not match. The first match is recorded as
`{action, base: null, chosenAt, source: "spec"}` and printed. Order, first
match wins:

1. a recorded `finish.json`;
2. the spec's `Finish:` line;
3. the `finishAction` setting, when it is not `ask`;
4. exit 3.

Without `--plan`, or with no line, nothing changes. brainstorming's spec
review writes the line in the bare form `Finish: <merge|pr|keep>` as its own
paragraph in `## Decisions`. finish-preference.md's When to ask states that
`get` reads the line. finishing-a-development-branch's Auto run rule, which
tells the controller to read the spec and run `set`, becomes "read
`scripts/finish-choice get --plan PLAN_FILE`; it reads the spec's line
itself". The execution skills' "run `finish-choice set` instead of asking"
sentence stays as a backstop. The cockpit Run card shows the choice once
`get` has recorded it; before that it shows none, as today.

### C. `dforge-path ledger` takes a plan path (row 15)

`dforge-path ledger ARG` turns `\` into `/`, and when ARG then contains `/`
or ends in `.md`, uses `basename ARG .md`. The usage line reads
`ledger SLUG|PLAN_FILE`. `dforge_ledger_dir` is unchanged; every script
caller already passes a slug.

### D. Worktree creation never asks or works in place in an auto run (row 17)

dforge:using-git-worktrees, in an auto run:

- Step 0 does not read the `worktree` setting: the worktree is always
  created, `worktree=never` included.
- Step 3, when the baseline tests fail, records
  `scripts/auto-run ruling add "Setup: baseline tests red — <failing summary>"`
  and continues; the final review and finishing's first step run the suite
  again.
- The sandbox fallback does not work in place: it runs
  `scripts/auto-run stop --reason "the sandbox refused the execution worktree"`
  and ends as auto-run.md §Stopping says.

### E. The final phase starts before the last budget check (row 16)

`scripts/context-size --final`, when a run is bound to the session and its
phase is `execute`, sets the phase to `final` before it measures, so a
compaction from there never hands off. The execution skills drop the After
compaction step 3 parenthetical "(in an auto run, the Auto run section's
`handoff` rule still applies)", and Task Loop step 8 and the Session Budget
paragraph say that in an auto run a `compact` line still ends the turn on
`Auto run: compacting`.

### F. Task bookkeeping sits in the task loops (row 18)

executing-plans Task Loop step 7, delegated-task.md §5 and parallel-waves.md
§4 each say, right after the complete line: "In an auto run, run
`scripts/auto-run task-complete`, then the Fable batch when
`scripts/auto-run decision list` prints anything."

### G. Escalation to subagent mode clears by phase (row 19)

executing-plans §Switching to subagent mode step 4, in an auto run: run
dforge:handoff steps 0-4, then `scripts/auto-run clear --phase`, and end the
turn with `Auto run: clearing`. auto-run.md §Clears lists this case beside
the compaction one. A phase clear never counts as a self-resume.

### H. Final-review stops have auto-run rules (rows 20, 21)

final-review.md step 0, in an auto run: a red gate becomes the fix wave's
first finding, and the gates run again after the fix wave; a second red, or
a manifest defect, runs `scripts/auto-run stop --reason "gate <name> red"`.

auto-run.md §Rulings: a `final-residual` item with no ruling is added with
`scripts/register add <run register> "<the finding>" --state deferred --note "final review residual"`.
The keep rules (auto-run.md §Finishing and finishing's Auto run section) add
a deferred row whose Note is `final review residual`, and finishing's final
message lists those rows.

### I. Spec-review deferrals reach the run's register (row 22)

brainstorming §Auto by default step 5 carries the deferral command itself:
`scripts/register add <register> "A<n>: <statement>" --state deferred --note "Q: <question>"`,
opening the item register first when none is open. Step 6 passes
`--register <that register>` to `scripts/auto-run start`.

### J. Dependents of a deferred task are found from the plan (row 23)

auto-run.md §Rulings and the execution skills' deferral bullet: the tasks
that depend on a deferred task are those whose `**Depends on:**` line names
it, or, in a plan without those lines, every later task whose `Consumes:`
line cites a Contracts entry the deferred task's `Produces:` line cites.

### K. A deferred task's rows stay deferred at finishing (row 24)

finishing Step 5b, under every finish action: a row cited only by a task
whose complete line reads `(deferred by the auto run)` is set to `deferred`
with the note `deferred by the auto run: <the line's Ruling>`, never `done`
or `verify`.

### L. The run has a watchdog and a heartbeat (rows 26, 29, 30)

The cockpit adds a watchdog with `$.clock.every(60_000)`:

1. **Heartbeat.** Each tick, and at `session.start`, it writes the current
   epoch seconds to `$HOME/.claude/dforge/sessions/cockpit/<session id>`.
   `scripts/auto-run start` exits 2 with `auto-run: no live cockpit in this
   session` when that file for `AR_SESSION` is missing or older than 180
   seconds; brainstorming already continues without a run on exit 2.
   `ar_is_stale` treats the bound session's run as stale when its heartbeat
   is older than 180 seconds, and uses today's 60-minute transcript rule only
   when no heartbeat file exists.
2. **Stall detection.** A tick acts when an active run is bound to this
   session, no turn is live, the activity kind is `idle` or `failed` (never
   `interrupted`: an Esc hands the session to the owner until they submit a
   prompt), and the activity's `endedAt` is more than 180 seconds ago. When pending
   is `compact`, `clear`, `switch` or `switch-resume` and no stage timer is
   armed, it arms that stage. Otherwise it runs `scripts/auto-run stalled`,
   which adds 1 to `stalls` and, at 3, stops the run with the reason
   `three stalls without a completed task` and exits 5; on exit 0 the
   cockpit submits "The auto run stalled: the last turn ended without its
   sentinel line. Run `bash <root>/scripts/auto-run status`, continue the
   phase it names, and end the turn as reference/auto-run.md §Ending a turn
   says." On exit 5 it ends the run as a stopped run. `task-complete` resets
   `stalls`.
3. **Bounded deferral.** `autoAct` defers while spawns or shells are live,
   as today, but after 30 minutes of continuous deferral it books
   `scripts/auto-run failure --reason "a background launch kept the <stage> waiting 30 minutes"`,
   so the second such failure stops the run.
4. **Holds without a stamp.** `scripts/turn-end.sh` runs the auto-run
   `pending` check before the turn-stamp gate, so a bound run is held even in
   a session that has no stamp (a cleared session, a hook that ran before
   `turn-start.sh`). It creates the holds file's directory, and when the
   holds count cannot be written it treats the cap as reached, so holds stay
   bounded.

### M. Compactions without progress are capped (row 27)

`ar_compacted` adds 1 to `compactionsSinceTask` in the `plan` and `execute`
phases; `task-complete` and `ar_switch` reset it. At 3 it stops the run with
the reason `three compactions without a completed task` and returns 5; the
cockpit ends the run as stopped when `compacted` exits 5, both in its own
compact stage and in `bookAutoCompaction`. `bookAutoCompaction` also skips a
pending `handoff` (the clear still has to happen) and a pending `compact`
(the cockpit's own stage books it), so neither is overwritten or counted
twice.

### N. `/model` and `/effort` run only when they can be undone (row 28)

Before running `/model` and `/effort`, the cockpit reads the user defaults
and runs `node --version`. When the defaults cannot be read or node does not
run, it skips both commands, and the prompt's note says "The cockpit kept
this session on <model> because it could not put back your default model
afterwards." When it ran them and the restore still fails, it also sends a
Discord notice of kind `blocked` naming the settings file.

### O. A background launch at the switch is waited for, not fatal (row 31)

auto-run.md §The switch step 3 and writing-plans: when `scripts/next-step`
exits 5 (background work still listed), run `scripts/in-flight`, wait for or
stop each listed launch, and run `next-step` again; a second exit 5 runs
`scripts/auto-run stop --reason "background work still running at the switch: <next-step's message>"`.
Any other nonzero exit keeps today's stop.

### Version

dforge goes from 4.0.0 to 4.1.0 in `.claude-plugin/plugin.json` and
`.codex-plugin/plugin.json`: `auto-run start` now needs a live cockpit.

## Testing

Script behaviour is tested in the existing suites:
`tests/auto-run.test.sh` (guard, `task-complete` stop, `setupDue`, `stalled`,
`compactionsSinceTask`, heartbeat start and staleness; its two existing
`phase execute` calls move to the linked worktree `$TMP/side`, and its
`start` calls write a heartbeat first), `tests/finish-choice.test.sh`,
`tests/roots.test.sh` (`dforge-path ledger`), `tests/next-step.test.sh`
(the new prompt; its pin at line 74 changes), `tests/turn-end.test.sh`
(holds without a stamp, unwritable holds file), `tests/context-size.test.sh`
or `tests/final-phase.test.sh` (`--final` moves the phase), and
`tests/cockpit.test.ts` (watchdog, heartbeat, deferral cap,
`bookAutoCompaction` exclusions and exit 5, the restore pre-check, the switch
instructions). Skill and reference text is pinned in
`tests/auto-run-skills.test.sh` and `tests/auto-default.test.sh`; the
existing pin at `tests/auto-run-skills.test.sh:23` is replaced by the new
Setup bullet.

## Acceptance

A1. [test, high] `scripts/next-step` on a plan with no ledger writes the first prompt with `No ledger exists yet: begin at the skill's Setup, worktree first; the first task is Task <N> (<title>).`, and the `**Next:**` line is unchanged.
A2. [test, high] The cockpit's switch compaction instructions state that no task has started and execution begins at the execution skill's Setup.
A3. [test, high] After `scripts/auto-run switch`, `status` says setup is due and `after-compact`'s `continue` line names Setup; a `phase execute` that passes the guard clears it.
A4. [test, high] dforge:executing-plans and dforge:subagent-driven-development each open `## After compaction` with the setup-due / no-ledger step that sends the session to Setup's first step.
A5. [test, neg, high] `scripts/auto-run phase execute` exits 4 with the message naming dforge:using-git-worktrees in the primary checkout, and exits 0 from a linked worktree, including for a run that started in a linked worktree.
A6. [test, neg, high] `scripts/auto-run task-complete` in the primary checkout stops the run with `a task was completed in the primary checkout` and exits 5.
A7. [test, high] `scripts/finish-choice get --plan` with nothing recorded reads a `Finish: keep` line from the spec's `## Decisions`, bare or after a `-`, `*` or `6.` marker, and records and prints it with `"source": "spec"`, even when `finishAction` is `merge`.
A8. [test, high] A recorded `finish.json` outranks the spec's line; a spec without the line falls through to the setting and then to exit 3; a spec found through `dforge_resolve` (a mirrored or `docs/superpowers/` path) is read.
A9. [test, neg, high] A `Finish:` line outside `## Decisions`, inside a fenced block, or with a value other than exactly `merge`, `pr` or `keep` (such as `3. Finish: "Ask at spec review"`) is not read.
A10. [test, high] brainstorming writes the spec review's finish answer as a bare `Finish: <merge|pr|keep>` paragraph; finish-preference.md and finishing's Auto run rule say `get` reads the line.
A11. [test, high] `dforge-path ledger` given `docs/dforge/plans/2026-10-19-greet.md` or `docs\dforge\plans\2026-10-19-greet.md` prints the same directory as given `2026-10-19-greet`.
A12. [test, high] using-git-worktrees, in an auto run, ignores `worktree=never`, records a red baseline as a ruling and continues, and stops the run when the sandbox refuses the worktree.
A13. [test, high] `scripts/context-size --final` in a bound run whose phase is `execute` sets the phase to `final`, and the execution skills no longer say the `handoff` rule applies at the final check.
A14. [test, high] executing-plans step 7, delegated-task.md §5 and parallel-waves.md §4 each name `scripts/auto-run task-complete` and the Fable batch after the complete line.
A15. [test, high] executing-plans §Switching to subagent mode, in an auto run, runs `scripts/auto-run clear --phase` and ends on `Auto run: clearing`, and auto-run.md §Clears lists that case.
A16. [test, high] final-review.md step 0 has the auto-run rule for a red gate and a manifest defect.
A17. [test, high] A final-residual item with no ruling becomes a deferred row noted `final review residual`, and such a row keeps a `merge` finish.
A18. [test, high] brainstorming §Auto by default step 5 carries the `register add … --state deferred` command, and step 6 passes `--register` with that register.
A19. [test, high] auto-run.md §Rulings defines a deferred task's dependents by `**Depends on:**`, or else by `Consumes:` citing the deferred task's `Produces:`.
A20. [test, high] finishing Step 5b sets a row cited only by a deferred-by-the-auto-run task to `deferred`, under every finish action.
A21. [test, neg, high] `scripts/auto-run start` exits 2 with `no live cockpit` when the session's heartbeat is missing or older than 180 seconds, and a run whose bound session's heartbeat is older than 180 seconds is stale.
A22. [test, high] With an active run bound, no live turn, activity `idle` or `failed` and the last turn over 180 seconds old, the watchdog re-arms a pending cockpit stage, or runs `auto-run stalled` and submits the stall prompt; it does nothing after an Esc (`interrupted`).
A23. [test, neg, high] The third `scripts/auto-run stalled` without a `task-complete` stops the run with `three stalls without a completed task` and exits 5.
A24. [test, high] `autoAct` books a failure after 30 minutes of continuous deferral.
A25. [test, high] `scripts/turn-end.sh` holds a bound run's turn when no turn stamp exists, and treats an unwritable holds count as the cap.
A26. [test, neg, high] The third compaction in the `plan` or `execute` phase without a `task-complete` stops the run with `three compactions without a completed task`, and `bookAutoCompaction` books nothing while `handoff` or `compact` is pending.
A27. [test, neg, high] When the user defaults cannot be read or `node --version` fails, the cockpit runs neither `/model` nor `/effort` and says so in the prompt; a failed restore after running them sends a `blocked` notice.
A28. [test, high] The switch step waits for or stops a listed background launch on `next-step` exit 5 and stops the run only on a second exit 5.
A29. [demo, high] In a fresh scratch repository, a real auto run of a one-task plan switches in place, creates the execution worktree before Task 1, leaves the base branch without task commits, and finishes with the spec's `Finish: keep`.
A30. [demo, high] In the same kind of repository, an attended run whose spec carries `Finish: keep` never asks the finish question, and its ledger is at `.dforge/sdd/<plan basename>/progress.md`.

## Riskiest assumption

That a submitted prompt from the watchdog is a safe nudge. It runs only when
the session is idle or failed, a run is bound to it, and no Esc was pressed;
the stall cap bounds it to three nudges per task. A29 runs the switch and the
Setup path on a real engine; the watchdog itself is verified in the cockpit
tests only, since provoking a real API error on demand is not practical.

## Review rulings

The Fable spec review of 2026-10-19 (verdict: revise) and how this revision
answers it:

- H1, the recorded-checkout guard blocked a run started in a linked
  worktree: the guard now tests the primary checkout (A.5); `checkout` and
  its fallback are gone.
- H2, the exact-line rule missed numbered lists: list markers are accepted
  and brainstorming writes the bare form (B, A7, A10).
- H3, the stored prompt said "Start at Task 1": the prompt names Setup and
  the compaction keeps the fact (A.1, A.2).
- M1, a stale ledger in the primary defeats a no-ledger test: `setupDue`
  makes the switch itself the signal (A.3), and A29 uses a fresh repository.
- M2, the sandbox fallback had no path through the guard: D stops the run.
- M3, mirrored and legacy spec paths: `dforge_resolve` (B).
- M4, path forms on Git Bash: both sides of the guard come from git (A.5).
- L1, the existing Setup-bullet pin: replaced (Testing).
- L2, finishing still told the model to read the spec: rewritten (B).
- L3, the Run card before `get` runs: stated (B).
- L4, backslash paths: normalised (C).
- L5, fenced and CRLF lines: skipped and stripped (B).
- L6, submodules: both commands keep exit 2 (A.5).
