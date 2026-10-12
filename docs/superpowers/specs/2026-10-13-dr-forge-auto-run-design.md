# dr-forge auto run — design

**Date:** 2026-10-13
**Plugin:** `plugins/dr-forge` (2.1.0 → 2.2.0)
**Status:** awaiting owner review (Fable review round 1 applied)
**Execution strategy:** parallel — once the run-state script, its state file,
the auto budget verdict and the setting exist, the cockpit mod and the skills
with the Stop hook touch different files and consume only the foundation's
contract.
**Register:** `docs/superpowers/registers/2026-10-12-auto-execution.md`

## Problem

A dr-forge run needs a human at every phase boundary: the spec review stop, the
hard stop after the plan is saved, the worktree and finish-preference questions,
every budget handoff and every `BLOCKED` verdict. An approved design cannot be
left to run to a finished branch overnight. The owner wants an opt-in mode in
which, after the design is approved, the rest of the workflow runs without any
question, compacts its own context instead of handing off, and collects what it
cannot decide into a deferred list.

## Decisions

Owner answers, 2026-10-12/13 session:

- The opt-in question comes after the last design section is approved, before
  the spec is written. Clarifying questions, approaches and the design stay
  interactive.
- A handoff inside an auto run writes the usual handoff files and then resumes
  on its own in a cleared session, under a cap.
- Rulings escalate Opus, then Fable in batches, then the deferred list.
- The finish action is the `finishAction` setting when it names `merge`, `pr`
  or `keep`; under `ask` or `wait` the branch is kept.
- Approach: the budget checkpoints decide (a script), the model ends its turn
  at a task boundary with a sentinel line, and the cockpit mod compacts or
  clears and resumes. Rejected: a mod that compacts on its own whenever the
  session is idle (it would compact mid-task while agents run), and relying on
  Claude Code's own auto-compaction (it cannot express the owner's thresholds
  and compacts mid-task).
- The owner's thresholds (register rows 5-9) are kept as stated, including the
  90% figure whose risk is recorded under Compaction loop.
- All twenty findings of the first Fable review are applied.

## Platform facts this rests on

From the mod API types (`plugins/dr-forge/.claude-plugin/types/claude-code/index.d.ts`):

- `$.session.compact({ instructions })` runs the compaction `/compact` runs,
  only between turns; it rejects while a turn runs. It runs every hook but the
  calling one.
- `$.command.run({ command, args })` runs a slash command as if typed, once
  idle; it rejects inside a hook the turn is waiting on.
- `$.prompt.submit({ text, asUser })` queues a turn once the session is idle;
  a prompt the person types runs first.
- `turn.complete` carries `reason` (`answer`, `aborted`, `refusal`, `error`),
  the answer text and `agentId` for a subagent's turn.
- `$.session.id()` is the session id; `/clear` ends the session (`session.end`
  with reason `clear`) and the process continues under a new id, with no
  `session.start`.
- After a compaction `$.session.usage()` has no token reading until the next
  response.

Inferred, not yet observed; the manual smoke run settles each:

- `/clear`, `/model <name>` and `/effort <level>` run through `$.command.run`,
  and a prompt submitted after them starts the cleared session's first turn.
- The `SessionStart` hook with matcher `compact` (the compaction snapshot)
  fires for a compaction with trigger `plugin`, and the one with matcher
  `clear` fires after a `/clear` run by a mod.
- Whether the cockpit's own `session.compact` hook runs for the cockpit's own
  `$.session.compact()` call ("every hook but the calling one"). The design
  does not depend on it: the actuator clears the stale reading itself.
- Whether the mod's atoms survive `/clear`. The design does not depend on it:
  the actuator reads the state file, never an atom.

## Setting

`autoRun` in `config/schema.mjs`, group Workflow, `enforcedBy: 'skill'`:

- `ask` (default): brainstorming asks the opt-in question on the architectural
  path.
- `off`: the question is never asked.

There is no always-on value. The question is not asked on a Codex host, where
the mod does not run, nor on the bounded or spike paths, which have no spec or
plan. The README's settings table gains the row.

## The opt-in question

Asked once, as its own message, right after the last design section is
approved:

```
Run the rest unattended? Spec → Fable spec review → plan → execution →
final review → finish (<merge to <base> | open a pull request | keep the branch>).
I won't ask anything else: undecided items go to Opus, then to Fable in
batches, and what neither settles goes on the deferred list.

1. Yes, run unattended
2. No, keep the normal stops

Which option?
```

The finish wording follows `finishAction`: `merge` and `pr` name their action,
and `keep`, `ask` and `wait` all read "keep the branch". On yes the session
runs `scripts/auto-run start --spec <spec path> --register <register path>`
before writing the spec. The register is the item register when one is open,
else `auto-run start` creates `<docs>/registers/<date>-<slug>-auto.md`, where
`<docs>` is `forge_dir docs` (`scripts/lib/forge-dir.sh`).

## Run state

`scripts/auto-run` owns `<primary checkout>/<state>/sdd/auto-run.json`: the
`sdd/` directory self-ignores, so the file never dirties a worktree or enters a
review snapshot. `start` creates the directory's `*` `.gitignore` as
`scripts/sdd-workspace` does. Every caller (the scripts, the Stop hook, the
mod) finds the primary checkout as `ctx_primary_root` in
`scripts/lib/context.sh` does, never from the worktree's own top level.

Fields:

| Field | Meaning |
|---|---|
| `active` | true from `start` until `stop` |
| `session` | the session id the run belongs to |
| `rebind` | true between an `auto-run clear` and the cleared session's first `auto-run` call |
| `stopped` | null, or the reason the run stopped |
| `spec`, `plan`, `register` | repository-relative paths; `plan` is null until `attach` |
| `phase` | `spec`, `plan`, `execute`, `final`, `finish` |
| `regime` | `normal` or `high` |
| `pending` | null, `compact`, `after-compact` or `clear` |
| `resumePrompt` | the prompt the mod submits after a clear |
| `launch` | `{model, effort}` the cleared session runs on, or null |
| `failures` | consecutive refused or vetoed actuator attempts |
| `compactions` | count for the run |
| `resumes` | item-9 handoffs in a row since a task last completed |
| `decisions` | the pending list: `{id, question, options, opusReason, task}` |

**Session binding.** `start` writes `session` from `CLAUDE_CODE_SESSION_ID`.
Every `auto-run` command, the Stop hook and the mod act only when the caller's
session id equals `session`; a call from any other session sees no active run
(`status` exits 3) and changes nothing. The one exception is `rebind`: while it
is true, the first `auto-run` call from a session other than the recorded one
writes its id into `session` and clears `rebind`. The mod makes that call
itself right after `/clear`, as `auto-run rebind --session <$.session.id()>`,
before it submits the resume prompt.

**Stale runs.** `start` treats an active run as stale, and replaces it, when
its session's transcript (found as `scripts/lib/context.sh` finds transcripts)
has not been written for 60 minutes, or with `--force`. Otherwise it refuses
with exit 4.

Commands:

- `start --spec P --register R [--force]`
- `attach --plan P`, `phase <name>`: record progress.
- `status`: one line, exit 3 when no run is active for this session.
- `verdict --tokens T [--wave N]` (called by the budget line): applies the
  rules below, sets `pending: compact` when they say so, prints the verdict.
- `after-compact`: measures *P*, applies the after-compaction rule, sets
  `pending` to null, prints `continue` or `handoff`.
- `rebind --session ID`: accepted only while `rebind` is true.
- `task-complete`: resets `resumes`.
- `clear [--phase]`: reads the `Paste as the first prompt` text and the launch
  command that `scripts/next-step` just wrote into `<state>/handoff/latest.md`,
  stores them as `resumePrompt` and `launch`, sets `pending: clear` and
  `rebind`. Without `--phase` it is an item-9 handoff and adds one to
  `resumes`; at three it stops the run instead (see Guards).
- `booked-compaction`: called by the mod after a compaction it did not make;
  adds one to `compactions` and sets `pending: after-compact`.
- `decision add|list|clear`: the pending list.
- `stop [--reason TEXT]`: sets `active` false and `stopped` to the reason.

While a run is active it overrides, without asking: the spec review stop
(`specReview` treated as off), the worktree question in
dr-forge:using-git-worktrees (`worktree` treated as `always`), and the
finish-preference question. The plan inherits the spec's execution strategy
line as today. Every other setting applies.

**The human mid-run.** A prompt the person types runs before any queued mod
prompt and does not stop the run. When the person asks the session to stop,
the skills' auto branch runs `auto-run stop --reason "owner asked"` before
anything else.

## Spec and plan phases

**Spec.** The spec is written, committed and self-reviewed as today. Then
`dr-forge:judge-fable` reviews it against the approved design. Its rulings are
applied. An item it leaves undecided or without a suggestion becomes a
`deferred` register row carrying its note. At most two Fable rounds run
(review, revise, re-review); anything still open after the second is deferred.
`agents/judge-fable.md`'s description changes to name the two auto-run routes
(spec review and the Fable batch) besides the human override.

**Spec to plan.** `context-size --plan` runs as today. Under its limit the plan
is written in the same session; over it, the session runs dr-forge:handoff,
then `auto-run clear --phase`, and ends its turn with `Auto run: clearing`.

**Plan.** writing-plans runs unchanged, including its self-review and plan
review rounds. Wherever it would ask the human (an open approach question from
selecting-approaches, an Execution-line choice), the question goes to the Opus
ruling seat; what Opus does not settle joins the pending list. A deferred item
that leaves a task underspecified parks that task.

**Plan saved.** The hard stop's handoff runs as today, then
`auto-run clear --phase`, and the turn ends with `Auto run: clearing`.
Execution starts in a cleared session on the model and effort the Execution
line names. This does not count toward `resumes`.

## Rulings

The Opus round is the existing ruling seat (`dr-forge:judge-opus`): its
CONFIRMED-GAP, PARK and AMEND verdicts are carried out as today.

Where a run stops for the human today, an auto run does this instead:

| Today's stop | Auto run |
|---|---|
| Ruling seat `BLOCKED` | Joins the pending list; one Fable batch runs immediately |
| `BLOCKED — <agent> exhausted` | Same; Fable rules to split, amend or park |
| Irreversible or destructive operation | Not performed; the task is parked with a deferred row naming the operation |
| Security-sensitive action | Not performed; parked and deferred |
| A side effect outside the worktree (push, publish, mid-run merge) | Not performed; parked and deferred. The finish action is the one exception |

**The Fable batch.** One `dr-forge:judge-fable` dispatch carries the whole
pending list, each item with its id, question, options and Opus's reason for
not ruling. Fable answers each item `ruling: <choice> — <reason>` or
`no ruling`. A ruling is carried out like a ruling-seat verdict and logged as a
`Ruling:` ledger line. `no ruling` parks the task and adds a deferred register
row; tasks that depend on a parked task are parked too, each with its own row.
Independent tasks keep running.

A batch runs immediately for a blocked task, and otherwise at each boundary
where the pending list is not empty: after the spec, after the plan, after each
wave (each task in sequential mode), and before the final review.

`minor (deferred)` ledger lines are unchanged; finishing already copies them
into the register.

## Compaction loop

*B* is the task budget: `DR_FORGE_BUDGET`, else `handoffTokens`, else the
derived rule (604,000 at an 800,000 window; the owner pins 465,000 with
`DR_FORGE_BUDGET`). An auto run ignores
`handoffMode`. *W* is min(`autoCompactWindow`, model window), 800,000 on the
owner's machine. *M* is the per-task margin, 140,000.

Rules, applied by `auto-run verdict` for a checkpoint covering *N* tasks
(1 for a plain task, the wave width for a wave):

| State | Verdict |
|---|---|
| `normal`, context ≥ *B* − (*N*−1)·*M* | `compact` |
| `high`, context ≥ 0.90·*W* − (*N*−1)·*M* | `compact` |
| otherwise | `ok` |

The wave loop in `reference/parallel-waves.md` lowers the width while the
verdict is `compact`, as it does today on `handoff`; at width 1 a `compact`
verdict compacts.

After each compaction, with *P* the measured size:

| Condition | Result |
|---|---|
| *P* ≥ 0.85·*W* | `handoff`: hand off and self-resume |
| *P* ≥ 0.85·*B* | regime `high` |
| otherwise | regime `normal` |

A cleared session starts in `normal`. At the defaults: compact at 465k; high
regime when *P* ≥ 395k, compacting next at 720k; handoff when *P* ≥ 680k.

**Measuring *P*.** `auto-run after-compact` is the first tool call of the
continue prompt, so the transcript's newest usage entry (read as
`scripts/lib/context.sh` reads it) is the first response after the
compaction: the summary, the snapshot and the entry point. That is *P*.

In an auto run these rules replace the tail rule, the final-phase limit and
the relaxed mode at every checkpoint (`task-brief`, `review-package`, `wave`,
`context-size --final`). Finishing is never measured. An `unknown` verdict
continues the run with a `Ruling:` line; Claude Code's own auto-compaction is
the backstop.

The budget line in an auto run:

```
budget (auto): 312k of 465k (67%) — ok — source: record
budget (auto): 471k of 465k (101%) — compact — source: record
budget (auto, high): 724k of 720k (101%) — compact — source: record
budget (auto, wave of 3): 190k of 185k (103%) — compact — source: record
```

`context-size` exits 6 on `compact`.

**One compaction:**

1. A checkpoint prints `compact`; `auto-run verdict` has set `pending: compact`.
2. The model finishes the task in flight (in parallel mode the wave, through its
   merge), runs `auto-run task-complete` for each completed task, and ends its
   turn with the line `Auto run: compacting` as the last line.
3. The Stop hook passes the turn only when the last message ends with
   `Auto run: compacting` and the bound run's `pending` is `compact`, or ends
   with `Auto run: clearing` and `pending` is `clear`. Any other ending gets
   the existing holds.
4. The mod's `turn.complete` hook acts only when `agentId` is undefined,
   `reason` is `answer`, the answer ends with the sentinel matching `pending`,
   the run is bound to `$.session.id()`, and no background agent or shell is
   in flight (the cockpit's own tracking). It does not call the actuator from
   inside the hook: it schedules it with `$.clock.after(0, …)`, after the hook
   has returned.
5. For `compact`, the actuator calls `$.session.compact()` with these
   instructions: keep verbatim the worktree, plan, ledger, handoff and
   state-file paths, HEAD, every `Ruling:` line and the pending list. It sets
   the budget reading to null itself, sets `pending: after-compact`, and
   submits the continue prompt, which runs `auto-run after-compact` and then
   continues the phase the state names (through resume-execution's checks in
   `execute` and `final`).
6. On `handoff` from `after-compact`, the model runs dr-forge:handoff, then
   `auto-run clear`, and ends its turn with `Auto run: clearing`.
7. For `clear`, the actuator runs `/clear`, then `/model` and `/effort` from
   `launch` when it is set, then submits `resumePrompt`. A refused `/model` or
   `/effort` does not stop the run: the cleared session logs a `Ruling:` line
   naming the model it runs on.

The phase clears follow steps 6 and 7 with `auto-run clear --phase`.

**Compactions the mod did not make.** The mod's `session.compact` hook, on a
compaction of the main session (`agentId` undefined) with a trigger other than
`plugin` and a bound active run, calls `auto-run booked-compaction`. The
cockpit's existing `SessionStart` snapshot carries the model on, and the next
checkpoint's verdict call sees `pending: after-compact` and runs the
after-compaction rule, with *P* measured at that checkpoint, before its own.

**Guards.**

- Three item-9 handoffs in a row without a completed task stop the run.
- A refused or vetoed actuator attempt adds one to `failures` and is retried at
  the next qualifying `turn.complete`; a second consecutive failure stops the
  run. A successful attempt resets `failures`.
- A stopped run (`active` false with a `stopped` reason) ends with the normal
  next-step block. The mod sends one Discord `blocked` notice when it reads the
  transition to a stopped run with a reason.
- Risk kept by the owner's choice: in the high regime a task starting just
  under 0.90·*W* can cross Claude Code's own compaction point (about 0.93·*W*)
  mid-task. The existing compaction snapshot carries the run on, and the
  compaction is booked as above.

## Final review and finish

The final whole-branch review runs as today; its findings go through the same
ladder. Finishing runs `finishAction` at once when it is `merge`, `pr` or
`keep`, and keeps the branch under `ask` or `wait`; no menu is shown and no
wake is armed. Finishing's existing unattended stops (a merged result failing
its tests, a rejected push, a refused worktree removal) still stop, through
`auto-run stop --reason`. The final message lists every `Ruling:` made on the
owner's behalf and every deferred row added by the run, then `auto-run stop`
ends it.

## Cockpit

- While a run bound to this session is active, a small card of its own (drawn
  whether or not a ledger exists) shows
  `Auto run · <phase> · <regime> · <compactions> compactions · <resumes> resumes`
  and a **Stop auto** button that runs `auto-run stop --reason "owner pressed Stop auto"`.
- The handoff note to the model and the `Handoff budget reached` Discord notice
  are suppressed while such a run is active; the Context card's limit mark
  shows the auto threshold for the regime (*B* or 0.90·*W*).
- The new state the mod keeps gets its entries in `types/index.d.ts`.

## Repository changes

| Area | Change |
|---|---|
| `config/schema.mjs` | `autoRun` setting |
| `scripts/auto-run`, `scripts/lib/auto-run.sh` | new: state file, binding and rules |
| `scripts/lib/context.sh` | `budget (auto)` line and exit 6 while a bound run is active |
| `reference/auto-run.md` | new: the contract above, for skills to cite |
| `reference/session-budget.md`, `reference/finish-preference.md`, `reference/parallel-waves.md` | auto-run sections |
| `scripts/turn-end.sh` | pass a turn ending on the sentinel that matches `pending` |
| `hooks/cockpit/register.tsx`, `hooks/cockpit/lib.ts`, `types/index.d.ts` | actuator, booking, suppression, auto card |
| `agents/judge-fable.md` | description names the auto-run routes |
| skills: brainstorming, writing-plans, using-git-worktrees, subagent-driven-development, executing-plans, finishing-a-development-branch, handoff, resume-execution | auto-run branches as described |
| `README.md` | `autoRun` row in the settings table; a short auto-run section |
| `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` | 2.2.0 |

## Parallel decomposition

- **Foundation (first, alone):** `config/schema.mjs`, `scripts/auto-run`,
  `scripts/lib/auto-run.sh`, `scripts/lib/context.sh`, `reference/auto-run.md`,
  `skills/brainstorming/SKILL.md` (all of its auto-run text, which also keeps
  `tests/settings-skills.test.sh` green once `autoRun` exists),
  `tests/auto-run.test.sh`,
  `tests/budget-line.test.sh`, `tests/context-size.test.sh`, both plugin
  manifests.
- **A, the mod:** `hooks/cockpit/register.tsx`, `hooks/cockpit/lib.ts`,
  `types/index.d.ts`, `tests/cockpit.test.ts`. Consumes the state file format
  and the `auto-run` commands.
- **B, skills, hook and docs:** the seven skills above other than
  brainstorming, `agents/judge-fable.md`,
  `reference/session-budget.md`, `reference/finish-preference.md`,
  `reference/parallel-waves.md`, `README.md`, `scripts/turn-end.sh`,
  `tests/turn-end.test.sh`, `tests/settings-skills.test.sh`. Consumes the
  `auto-run` commands, the state file and the budget line.

A and B may run together. Their tests share nothing: the shell suites use
their own temporary state directories and `cockpit.test.ts` runs in its own
process.

## Testing

- `tests/auto-run.test.sh`: each rule at its boundary (465k, 395k, 680k, 720k
  at the defaults, and one non-default *B* and *W*); the wave reservation;
  regime transitions; `resumes` reset by `task-complete`; the cap of three;
  `clear --phase` not counting; `booked-compaction`; session binding (a call
  from another session sees no run and changes nothing); `rebind`; the stale
  run and `--force`; refusing a second `start`; the state file is ignored by
  git; `stop --reason`.
- `tests/budget-line.test.sh` and `tests/context-size.test.sh`: the auto lines
  and exit 6 appear only while a run bound to the session is active; the normal
  lines are unchanged.
- `tests/turn-end.test.sh`: a turn passes only with the sentinel matching
  `pending`; a mid-task summary with `pending` set but no sentinel is held; with
  no bound run the existing holds are unchanged; the hook finds the state in
  the primary checkout from a worktree.
- `tests/cockpit.test.ts`: the actuator runs only on an `answer` turn of the
  main session with the sentinel, a bound run and nothing in flight, and only
  after the hook returns; `aborted` and `error` turns do nothing; `/clear`, the
  launch commands and `resumePrompt` in order on `clear`; a rejection retried
  once, then the run stopped; a non-plugin compaction booked; the handoff note
  and budget notice suppressed during a run; the auto card drawn without a
  ledger; one Discord notice on a stop.
- `tests/settings-skills.test.sh`: `autoRun` is documented where the skills
  read workflow keys.

## Verification

`node scripts/validate-repository.mjs`, the maintained suites
(`node scripts/test-all.mjs`), `claude plugin validate` on the marketplace and
every Claude plugin, and `claude plugin test plugins/dr-forge`, each bounded by
a timeout. Then one manual smoke run: a three-task toy plan with
`DR_FORGE_BUDGET` set low enough to compact at least twice and self-resume
once, observed to finish with no question asked. It must observe, and report
as observed, each inferred platform fact listed above: `/clear`, `/model` and
`/effort` through `$.command.run`; the prompt after them; the `compact` and
`clear` `SessionStart` hooks firing for mod-driven actions; and whether the
cockpit's own `session.compact` hook runs for its own call.

## Out of scope

- An always-on `autoRun` value, and auto runs on Codex or on the bounded path.
- Changing the ruling seats' models or efforts.
- Answering the clarifying questions or approving the design unattended.
