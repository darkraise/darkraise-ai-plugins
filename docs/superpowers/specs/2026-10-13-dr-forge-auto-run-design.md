# dr-forge auto run — design

**Date:** 2026-10-13
**Plugin:** `plugins/dr-forge` (2.1.0 → 2.2.0)
**Status:** awaiting owner review
**Execution strategy:** parallel — once the run-state script, its state file and
the auto budget verdict exist, the cockpit mod and the skills with the Stop hook
touch different files and consume only the foundation's contract.
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
  or `keep`; under `ask` the branch is kept.
- Approach: the budget checkpoints decide (a script), the model ends its turn
  at a task boundary, and the cockpit mod compacts or clears and resumes.
  Rejected: a mod that compacts on its own whenever the session is idle (it
  would compact mid-task while agents run), and relying on Claude Code's own
  auto-compaction (it cannot express the owner's thresholds and compacts
  mid-task).
- The owner's thresholds (register rows 5-9) are kept as stated, including the
  90% figure whose risk is recorded under Compaction loop.

## Platform facts this rests on

From the mod API types (`plugins/dr-forge/.claude-plugin/types/claude-code/index.d.ts`):

- `$.session.compact({ instructions })` runs the same compaction `/compact`
  runs, only between turns; it rejects while a turn runs.
- `$.prompt.submit({ text, asUser })` queues a turn once the session is idle.
- `$.command.run({ command })` runs a slash command as if typed, once idle.
- After a compaction `$.session.usage()` has no token reading until the next
  response (the cockpit already handles this in its `session.compact` hook).

Running `/clear` through `$.command.run` and then submitting a prompt is
inferred from these docs, not yet observed; the manual smoke run settles it.

## Setting

`autoRun` in `config/schema.mjs`, group Workflow, `enforcedBy: 'skill'`:

- `ask` (default): brainstorming asks the opt-in question on the architectural
  path.
- `off`: the question is never asked.

There is no always-on value. The question is not asked on a Codex host, where
the mod does not run, nor on the bounded or spike paths, which have no spec or
plan.

## The opt-in question

Asked once, as its own message, right after the last design section is
approved:

```
Run the rest unattended? Spec → Fable spec review → plan → execution →
final review → finish (<finishAction's option, or "keep the branch">).
I won't ask anything else: undecided items go to Opus, then to Fable in
batches, and what neither settles goes on the deferred list.

1. Yes, run unattended
2. No, keep the normal stops

Which option?
```

On yes the session runs `scripts/auto-run start --spec <spec path> --register
<register path>` before writing the spec. The spec path is the one the spec
will be saved to; the register is the item register when one is open, else
`auto-run start` creates `docs/superpowers/registers/<date>-<slug>-auto.md`.

## Run state

`scripts/auto-run` owns `<primary checkout>/<state>/auto-run.json` (the state
directory from `scripts/lib/forge-dir.sh`). Fields:

| Field | Meaning |
|---|---|
| `active` | true from `start` until `stop` or the finish |
| `spec`, `plan`, `register` | repository-relative paths; `plan` is null until `attach` |
| `phase` | `spec`, `plan`, `execute`, `final`, `finish` |
| `regime` | `normal` or `high` |
| `pending` | null, `compact`, `after-compact` or `clear` |
| `compactions` | count for the run |
| `resumes` | item-9 handoffs in a row since a task last completed |
| `decisions` | the pending list: `{id, question, options, opusReason, task}` |

Commands:

- `start --spec P --register R`: refuses (exit 4) while another run is active.
- `attach --plan P`, `phase <name>`: record progress.
- `status`: prints the state as one line, exit 3 when no run is active.
- `verdict --tokens T` (used by the budget line): applies the rules below,
  sets `pending: compact` when they say so, prints the verdict.
- `after-compact`: measures the context, applies the after-compaction rule,
  prints `continue` or `handoff`.
- `task-complete`: resets `resumes`.
- `clear [--phase]`: sets `pending: clear`; without `--phase` it is an item-9
  handoff and counts toward `resumes`.
- `decision add|list|clear`: the pending list.
- `stop`: sets `active` false; the mod and skills fall back to normal behaviour.

While a run is active it overrides, without asking: the spec review stop
(`specReview` treated as off), the worktree question (`worktree` treated as
`always`), and the finish-preference question. The plan inherits the spec's
execution strategy line as today. Every other setting applies.

## Spec and plan phases

**Spec.** The spec is written, committed and self-reviewed as today. Then
`dr-forge:judge-fable` reviews it against the approved design. Its rulings are
applied. An item it leaves undecided or without a suggestion becomes a
`deferred` register row carrying its note. At most two Fable rounds run
(review, revise, re-review); anything still open after the second is deferred.

**Spec to plan.** `context-size --plan` runs as today. Under its limit the plan
is written in the same session; over it, the run hands off and self-resumes
through a phase clear (Compaction loop, after step 5).

**Plan.** writing-plans runs unchanged, including its self-review and plan
review rounds. Wherever it would ask the human (an open approach question from
selecting-approaches, an Execution-line choice), the question goes to the Opus
ruling seat; what Opus does not settle joins the pending list. A deferred item
that leaves a task underspecified parks that task.

**Plan saved.** The hard stop's handoff files are written, then the session
runs `auto-run clear --phase`, so execution starts in a cleared session through
resume-execution. This does not count toward `resumes`.

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

*B* is the task budget the budget line reports today (465,000 by default; the
final-phase limit under `handoffMode` `relaxed`). *W* is min(`autoCompactWindow`,
model window), 800,000 on the owner's machine.

Rules, applied by `auto-run`:

| State | Verdict |
|---|---|
| `normal`, context ≥ *B* | `compact` |
| `high`, context ≥ 0.90 *W* | `compact` |
| otherwise | `ok` |

After each compaction, with *P* the measured size:

| Condition | Result |
|---|---|
| *P* ≥ 0.85 *W* | `handoff`: hand off and self-resume |
| *P* ≥ 0.85 *B* | regime `high` |
| otherwise | regime `normal` |

A cleared session starts in `normal`. At the defaults: compact at 465k; high
regime when *P* ≥ 395k, compacting next at 720k; handoff when *P* ≥ 680k.

In an auto run these rules replace the tail rule, the final-phase limit and the
relaxed mode at every checkpoint (`task-brief`, `review-package`, `wave`,
`context-size --final`). Finishing is never measured. An `unknown` verdict
continues the run with a `Ruling:` line; Claude Code's own auto-compaction is
the backstop.

The budget line in an auto run:

```
budget (auto): 312k of 465k (67%) — ok — source: record
budget (auto): 471k of 465k (101%) — compact — source: record
budget (auto, high): 724k of 720k (101%) — compact — source: record
```

`context-size` exits 6 on `compact`.

**One compaction:**

1. A checkpoint prints `compact`; `auto-run verdict` has set `pending: compact`.
2. The model finishes the task in flight (in parallel mode the wave, through its
   merge), runs `auto-run task-complete` for each completed task, and ends its
   turn with the line `Auto run: compacting`.
3. The Stop hook passes a turn whose state has a `pending` action, in place of
   the next-step block.
4. On `turn.complete` in the main session, the mod reads the state file. With
   `pending: compact` and no background agent or shell running (the cockpit's
   own tracking), it calls `$.session.compact()` with these instructions:
   keep verbatim the worktree, plan, ledger, handoff and state-file paths,
   HEAD, every `Ruling:` line and the pending list. It sets
   `pending: after-compact` and submits the continue prompt.
5. The continue prompt runs `auto-run after-compact` first. On `continue` the
   run resumes with resume-execution's checks. On `handoff` the model runs
   dr-forge:handoff, then `auto-run clear`, and ends its turn with
   `Auto run: clearing`; the mod runs `/clear` and submits the resume prompt
   (`resume-execution` on the plan), and `resumes` goes up by one.

The phase clears (spec to plan over the `--plan` limit, and plan saved) use
the same `pending: clear` path with `auto-run clear --phase`, which leaves
`resumes` unchanged; their resume prompt continues the phase that comes next
(writing-plans on the spec, or resume-execution on the plan).

**Guards.**

- Three item-9 handoffs in a row without a completed task stop the run:
  `active` false, a Discord `blocked` notice, and the normal next-step block.
- The mod acts only on the main session, only on a state file whose `active`
  is true, and never while background work runs; it waits for the next
  `turn.complete`.
- A compaction the mod's hook chain vetoes (`{ skip }`) is retried at the next
  `turn.complete`; a second veto stops the run as above.
- Risk kept by the owner's choice: in the high regime a task starting just
  under 0.90 *W* can cross Claude Code's own compaction point (about 0.93 *W*)
  mid-task. The existing compaction snapshot carries the run on.

## Final review and finish

The final whole-branch review runs as today; its findings go through the same
ladder. Finishing runs `finishAction` at once when it is `merge`, `pr` or
`keep`, and keeps the branch under `ask`; no menu is shown and no wake is
armed. Finishing's existing unattended stops (a merged result failing its
tests, a rejected push, a refused worktree removal) still stop, with a Discord
`blocked` notice. The final message lists every `Ruling:` made on the owner's
behalf and every deferred row added by the run, then `auto-run stop` ends it.

## Cockpit

While a run is active, the plan section shows one line,
`Auto run · <regime> · <compactions> compactions · <resumes> resumes`, and a
**Stop auto** button that runs `auto-run stop`.

## Repository changes

| Area | Change |
|---|---|
| `config/schema.mjs` | `autoRun` setting |
| `scripts/auto-run`, `scripts/lib/auto-run.sh` | new: state file and rules |
| `scripts/lib/context.sh` | `budget (auto)` line and exit 6 while a run is active |
| `reference/auto-run.md` | new: the contract above, for skills to cite |
| `reference/session-budget.md`, `reference/finish-preference.md` | auto-run sections |
| `scripts/turn-end.sh` | pass a turn ending on a `pending` action |
| `hooks/cockpit/register.tsx`, `hooks/cockpit/lib.ts` | compact, clear and resume actuator; status line; Stop auto |
| skills: brainstorming, writing-plans, subagent-driven-development, executing-plans, finishing-a-development-branch, handoff, resume-execution | auto-run branches as described |
| `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` | 2.2.0 |

## Parallel decomposition

- **Foundation (first, alone):** `config/schema.mjs`, `scripts/auto-run`,
  `scripts/lib/auto-run.sh`, `scripts/lib/context.sh`, `reference/auto-run.md`,
  `tests/auto-run.test.sh`, `tests/budget-line.test.sh`,
  `tests/context-size.test.sh`, both plugin manifests.
- **A, the mod:** `hooks/cockpit/register.tsx`, `hooks/cockpit/lib.ts`,
  `tests/cockpit.test.ts`. Consumes the state file format and `auto-run stop`.
- **B, skills and hook:** the seven skills above,
  `reference/session-budget.md`, `reference/finish-preference.md`,
  `scripts/turn-end.sh`, `tests/turn-end.test.sh`,
  `tests/settings-skills.test.sh`. Consumes the `auto-run` commands and the
  budget line.

A and B may run together. Their tests share nothing: the shell suites use
their own temporary state directories and `cockpit.test.ts` runs in its own
process.

## Testing

- `tests/auto-run.test.sh`: each rule at its boundary (465k, 395k, 680k,
  720k at the defaults, and one non-default *B* and *W*), regime transitions,
  `resumes` reset by `task-complete`, the cap of three, refusing a second
  `start`, `stop`.
- `tests/budget-line.test.sh` and `tests/context-size.test.sh`: the auto line
  and exit 6 appear only while a run is active; the normal lines are unchanged.
- `tests/turn-end.test.sh`: a turn ending on a `pending` action passes; with no
  run active the existing holds are unchanged.
- `tests/cockpit.test.ts`: compacts on `pending: compact` only after
  `turn.complete` with nothing in flight; runs `/clear` and submits the resume
  prompt on `pending: clear`; does nothing with no active run; the second veto
  stops the run.
- `tests/settings-skills.test.sh`: `autoRun` is documented where the skills
  read workflow keys.

## Verification

`node scripts/validate-repository.mjs`, the maintained suites
(`node scripts/test-all.mjs`), `claude plugin validate` on the marketplace and
every Claude plugin, and `claude plugin test plugins/dr-forge`, each bounded by
a timeout. Then one manual smoke run: a three-task toy plan with
`DR_FORGE_BUDGET` set low enough to compact at least twice and self-resume
once, observed to finish with no question asked. Its result is reported as
observed; it settles the `/clear` inference above.

## Out of scope

- An always-on `autoRun` value, and auto runs on Codex or on the bounded path.
- Changing the ruling seats' models or efforts.
- Answering the clarifying questions or approving the design unattended.
