# Auto execution as the default

**Execution strategy:** parallel — the cockpit, brainstorming, planning and
execution parts own separate files once a foundation part fixes the settings
and the `scripts/auto-run` contract.

**Register:** docs/superpowers/registers/2026-10-18-auto-execution-default.md

## Decisions

The owner's answers in the 2026-10-18 brainstorming session. The critic and
Fable check this spec against them.

1. Last approval before the unattended part: "Review written spec" — the
   questions and approaches stay interactive; the whole spec is written with no
   per-section approvals, the critic and Fable review it, and the owner
   approves the spec once. Plan, execution, final review and finish run
   unattended after that.
2. Session boundaries: "Plan here; compact+switch to run" — after the spec
   approval the plan is always written in the same session, with no `--plan`
   handoff; at plan saved the cockpit compacts and switches to the plan's
   controller model in the same session instead of clearing.
3. Finish: "Ask at spec review" — when `finishAction` is `ask`, the spec
   approval message also asks merge, pull request or keep, and the run carries
   that choice out with no later menu; the existing keep rules still apply.
4. Approach: "Auto default in one flow" — `autoRun=on` becomes the default;
   `ask` and `off` stay as opt-outs; the existing skills gain the behaviour.
5. This plan's execution: "Parallel subagents".

## Problem

| Register row | Cause today |
|---|---|
| 1 plan forced into a new session | `context-size --plan` can hand off after the spec; "plan saved" is a hard stop that clears the session (`writing-plans` §Execution Handoff, `session-budget.md` §Stops) |
| 2 prefer parallel | `executionStrategy` defaults to `ask`; waves are drawn only on a "parallel" answer |
| 3 keep going to finish | `context-size --final` hands off after the last task in the attended flow; in an auto run a compaction leaving 85% of the window hands off in the final phase too |
| 4 polish | the stops listed under §Brainstorming below |
| 5 no per-section approval | `designApproval` defaults to `sections` |
| 6 one spec, one plan | brainstorming decomposes large work into sub-project specs chained by `**Program:**` lines |
| 7 auto by default | `autoRun` accepts only `ask` (offer it) and `off` |

Rows 1, 5 and 6 are met under `autoRun=on` only: `ask`, `off` and Codex hosts
keep the sectioned design, the program split and the plan-saved handoff. Rows
2 and 3 apply in every mode.

## Design

### Settings

- `autoRun` takes `on`, `ask` or `off`; the default becomes `on`. `on` runs the
  flow below. `ask` keeps today's flow (sectioned design, then the offer).
  `off` keeps the attended flow. A stored value is kept; only the default
  changes.
- `executionStrategy` defaults to `parallel` instead of `ask`. The existing
  fall-back rules stay: sequential when no two tasks can share a wave, on a
  Codex host, and under `executionMode=inline`. A plan with a wave of two or
  more tasks is a subagent-mode plan (`writing-plans` §Parallel waves), so
  attended plans that would have run inline now run subagents more often: more
  dispatches and a Sonnet controller in place of the session model.
- On a Codex host `autoRun=on` behaves as `off`, and brainstorming says so in
  one line: the cockpit that compacts and switches is Claude Code only.
- `designApproval` has no effect under `on`: no design is presented in chat.
- `specReview` has no effect under `on`: the spec review always happens, since
  it is the owner's only stop.

### Brainstorming under `autoRun=on`

Only the architectural path changes; spike and bounded paths are untouched.

1. Classify, open the register, explore, ask the clarifying questions and
   propose approaches as today. Ask the execution-strategy question only when
   the setting is `ask`.
2. Write the spec directly. No design sections are presented, and no
   acceptance question is asked before writing. One spec covers the whole
   request: no sub-project decomposition, no program spec, no `**Program:**`
   line. A new product still routes to dforge:planning-a-product.
3. The spec gains a `## Decisions` section: every clarifying question and
   approach choice with the owner's answer, quoted. It replaces "the approved
   design sections verbatim" wherever the critic or Fable is given them.
4. Self-review round, then the architecture critic, then the Fable spec review
   (at most two rounds), all before anything is bound. Self-review item 6
   accepts a statement rated `medium` or `low` when it carries its `Q:`; the
   spec review settles it. Fable's rulings are applied and listed in a
   `## Review rulings` section of the spec, one line each, since no run exists
   yet for `scripts/auto-run ruling add`.
5. **The spec review message** — the one stop. One message, with the questions
   asked through the multiple-choice prompt, at most four per call:
   - the spec path and `Critic: …` counts, and the number of Fable rulings;
   - every acceptance statement rated below `high`, asked as Drafting
     acceptance asks it today (Right / Wrong, or not wanted / Not sure);
     a deferral writes the same `A<n>:` register row as today;
   - every item Fable left undecided, and every critic Blocker it did not
     settle, as a question with the recommended option first;
   - when `finishAction` is `ask`: merge into `<current branch>`, open a pull
     request, or keep the branch;
   - the approval itself: **Approve and run unattended**, **Approve, keep the
     normal stops** (no run starts; the attended flow continues from the User
     Review Gate's approval), or **Changes needed**.
   Answers are applied to the spec. A change request gets the revision and one
   new self-review round; the critic and Fable do not run again. On approval
   the spec and the register are committed.
6. Bind: `scripts/auto-run start --spec <spec> [--register <register>]`, then
   import each `## Review rulings` line with `scripts/auto-run ruling add
   "Fable, spec: <line>"`, then dforge:writing-plans in the same session, whose
   first step is `scripts/auto-run phase plan`. `scripts/context-size --plan`
   does not run under `on`.

### Planning

- **Alone, then waves by dependency depth.** Whenever the strategy is parallel
  (attended or auto), writing-plans drafts the tasks, then sorts them into two
  groups:
  - **alone** — a task that cannot share a wave: risk 3, an `**Executor:**`
    line, a manifest, lockfile or other file that cannot be split between
    tasks (today's rule 4);
  - **parallel** — every other task.
  Dependencies then decide only the order. Each task's depth is one more than
  the deepest task it consumes (`**Depends on:**`), and a task that consumes
  nothing has depth 1. Parallel tasks of the same depth that share no file form
  one wave, in parts of at most three; an alone task forms a wave of its own at
  its depth. Waves run in depth order. This spec's own shape — F and C at
  depth 1, B, W and E at depth 2, P at depth 3 — gives
  `**Parallelism:** waves — 1-2 | 3-5 | 6`. The result is written in today's
  format; plan-lint, `scripts/wave` and parallel-waves.md do not change.
- **One plan, amended in place.** A task that shows the plan is wrong goes
  through the ruling seat's AMEND path and `scripts/plan-amend`, as today; an
  auto run never writes a follow-up plan or a second plan version.
- **A compaction while planning.** No budget line prints the run's verdict in
  the `plan` phase, so only Claude Code's own compaction can happen there. The
  cockpit books it as today; `after-compact` in the `plan` phase always prints
  `continue`, and dforge:writing-plans resumes from the spec and the plan file
  on disk. The compaction instructions name the spec, plan and register paths.
- **Plan saved, under `on`.** After the plan review and `scripts/auto-run
  attach --plan PLAN_FILE`:
  1. When the spec review recorded a finish choice, `scripts/finish-choice set
     <action> --plan PLAN_FILE`.
  2. dforge:handoff steps 0-3: reconcile background agents and shells, commit
     the plan and spec, and update the handoff notes. It does not end the
     session.
  3. `scripts/next-step PLAN_FILE`. Any nonzero exit means `latest.md` was not
     written: `scripts/auto-run stop --reason "the handoff file could not be
     written"` and end as auto-run.md §Stopping says.
  4. `scripts/auto-run switch`, then end the turn with `Auto run: switching` as
     its last line.

### The switch

Two stages, the way compact and continue work today.

- `scripts/auto-run switch` (exit 4 when no plan is attached, or when the
  fenced first prompt in `latest.md` does not name the attached plan) sets the
  pending action to `switch` and stores the first prompt and launch command
  read from `latest.md`, as `clear` reads them.
- The Stop hook (`scripts/turn-end.sh`) lets a turn end on `Auto run:
  switching` while `switch` is pending, holds any other ending then (its hold
  reason says to run `scripts/auto-run switch` and end on that line), and holds
  `Auto run: switching` under any other pending action.
- **Stage `switch`** (pending `switch`): the cockpit, from a timer, compacts
  the session with instructions to keep the spec, plan, register and base
  paths and drop the design conversation, then books `compacted --switch`,
  which sets the pending action to `switch-resume`.
- **Stage `switch-resume`** (pending `switch-resume`): runs `/model` and
  `/effort` from the launch command, restores the user's saved defaults (the
  existing code after `/clear`), submits the stored first prompt prefixed with
  "Run `scripts/auto-run after-compact` first.", and books `resumed`. A
  refused `/model` or `/effort` adds the note it adds today and is not a
  failure.
- A failure in either stage is booked with `failure --reason "the cockpit
  could not switch: <why>"` and retried in that same stage; the second failure
  in a row stops the run, as today.
- `after-compact` after a switch applies the regime rules to the size it
  reads; a `handoff` there falls back to today's Clears. A switch is a phase
  transition: it does not count toward the three self-resumes.
- `bookAutoCompaction` does not book an engine compaction while `switch` or
  `switch-resume` is pending, as it does not while `clear` is.
- The cockpit shows `switch` and `switch-resume` as pending stages, as it shows
  compact and clear.

### No handoff before finishing

- After the last `Task N: complete` line, both execution skills go on to the
  final review and finishing in the same session, attended or auto.
  `scripts/context-size --final` keeps printing its line but never exits 5;
  session-budget.md drops the soft stop.
- In an auto run, `after-compact` in the `final` and `finish` phases prints
  `continue`, never `handoff`, and after one compaction in those phases every
  budget line of the run prints `ok`: Claude Code's own compaction is the
  backstop, so the run cannot loop on compactions that free too little.
- The attended flow relies on Claude Code's own compaction there; the
  execution skills' After compaction steps resume the final phase from the
  ledger.

### Finishing

- An auto run's finishing reads `scripts/finish-choice get --plan PLAN_FILE`
  before `finishAction`, so the spec review's answer is the one the cockpit's
  Run card shows and the one finishing carries out, into the run's base.
- Every keep rule in auto-run.md §Finishing still applies. The deferred `A<n>:`
  rule counts every deferred `A<n>:` row in the run's register, including
  those deferred at the spec review before the run was bound.

### Unchanged

`autoRun=ask` and `autoRun=off` flows apart from the parallel default, the
grouping and the final phase; the ruling ladder after binding; the spike and
bounded paths; dforge:planning-a-product; the controller model; wave width;
Codex hosts.

## Parallel decomposition

| Part | Wave | Files it owns | Consumes |
|---|---|---|---|
| F foundation | 1 | `config/schema.mjs`, `scripts/auto-run`, `scripts/lib/auto-run.sh`, `scripts/turn-end.sh`, `reference/auto-run.md`, `reference/finish-preference.md`, `reference/session-budget.md`, `tests/auto-run.test.sh`, `tests/turn-end.test.sh`, `tests/dforge-config.test.sh` | — |
| C cockpit | 1 | `hooks/cockpit/register.tsx`, `hooks/cockpit/lib.ts`, `tests/cockpit.test.ts` | the pending names `switch` and `switch-resume`, the `compacted --switch` booking and the `Auto run: switching` sentinel, fixed by this spec |
| B brainstorming | 2 | `skills/brainstorming/SKILL.md`, `skills/brainstorming/references/architecture-critic-prompt.md`, `skills/using-dforge/SKILL.md`, `tests/settings-skills.test.sh` | F |
| W planning | 2 | `skills/writing-plans/SKILL.md`, `tests/parallel-grouping.test.sh` (new) | F |
| E execution | 2 | `skills/subagent-driven-development/SKILL.md`, `skills/executing-plans/SKILL.md`, `skills/finishing-a-development-branch/SKILL.md`, `skills/handoff/SKILL.md`, `scripts/context-size`, `tests/context-size.test.sh`, `tests/budget-line.test.sh` | F |
| P pins and release | 3 | `tests/auto-run-skills.test.sh`, `tests/process-roles.test.sh`, `README.md`, both plugin manifests | B, W, E |

All paths are under `plugins/dforge/`. Any other `scripts/lib` file that both
F and E change belongs to F. C runs beside F because it consumes only names
this spec fixes. It also carries the riskiest-assumption probe, which runs
against a hand-written auto-run state file with the pending action set to
`switch`. The shell tests run in their own temporary directories and the
cockpit tests in memory, so the parts' tests share nothing at run time.

## Acceptance

A1. [test, high] With no `autoRun` stored, `scripts/dforge-config get autoRun` prints `on`, and `ask` and `off` are still accepted.
A2. [test, high] With no `executionStrategy` stored, the default is `parallel`.
A3. [test, high] Under `autoRun=on` the architectural path presents no design section for approval and asks nothing between the approach choice (or the strategy question, when asked) and the spec review message.
A4. [test, high] The spec review message carries the spec path, the critic counts, every acceptance statement below `high`, every item Fable left undecided, the finish choice when `finishAction` is `ask`, and the three approval options.
A5. [test, high] A finish choice made at the spec review is recorded with `scripts/finish-choice set --plan`, and an auto run's finishing carries it out in place of `finishAction`, with every existing keep rule still keeping the branch.
A6. [test, neg, high] Under `autoRun=on` no handoff happens between the spec approval and execution: `context-size --plan` does not run, and `after-compact` in the `plan` phase prints `continue`.
A7. [test, high] After the plan review in an auto run, `scripts/auto-run switch` sets the pending action to `switch`, and exits 4 when `latest.md`'s first prompt does not name the attached plan.
A8. [test, high] The Stop hook lets a turn end on `Auto run: switching` while `switch` is pending, and holds it under any other pending action.
A9. [test, neg, high] On a `switch` pending, the cockpit compacts and books `compacted --switch`; on `switch-resume` it runs `/model` and `/effort` from the launch command, restores the user's defaults, submits the first prompt and books `resumed`; it never runs `/clear`.
A10. [test, high] A failure in the `switch-resume` stage after the compaction is retried in that stage and then either submits the first prompt or stops the run with a reason naming the switch.
A11. [test, neg, high] An engine compaction while `switch` or `switch-resume` is pending is not booked.
A12. [demo, high] In a real Claude Code session, a switch leaves the session on the plan's launch model and effort, and execution starts Task 1 in the same session.
A13. [test, high] writing-plans states the alone / parallel grouping and the waves-by-depth ordering, and a plan of this spec's shape gets `**Parallelism:** waves — 1-2 | 3-5 | 6`.
A14. [test, neg, high] After the last task's complete line, neither execution skill hands off, attended or auto, and `scripts/context-size --final` never exits 5.
A15. [test, high] In an auto run, `scripts/auto-run after-compact` prints `continue` in the `final` and `finish` phases, and after one compaction there every budget line prints `ok`.
A16. [test, neg, high] On a Codex host `autoRun=on` starts no auto run, and the attended flow runs.
A17. [test, neg, high] `autoRun=ask` and `autoRun=off` keep the sectioned design, the offer under `ask`, and the plan-saved handoff; only the `parallel` default, the grouping and the no-handoff final phase reach them.
A18. [test, neg, high] No question reaches the owner after the spec approval in an auto run.
A19. [test, high] An acceptance statement deferred at the spec review keeps a `merge` finish, as one deferred during the run does.
A20. [test, confirmed] Under `autoRun=on`, brainstorming never splits a request into sub-project specs or writes a `**Program:**` line, and dforge:planning-a-product still handles a new product.
A21. [test, confirmed] Items Fable leaves undecided in the spec phase are asked at the spec review instead of becoming deferred register rows.
A22. [test, neg, confirmed] Under `autoRun=on` the spec review always happens: `specReview=false` has no effect there.

## Riskiest assumption

A compaction followed by `/model` and `/effort` in the same session (no
`/clear`) leaves the session on the launch model and effort, with the user's
defaults restored. The parts exist separately — the cockpit compacts
in place and runs `/model` and `/effort` after `/clear`
(`plugins/dforge/hooks/cockpit/register.tsx:2333-2370`), and the restore loop
was verified on a real engine on 2026-10-13 (register
2026-10-12-auto-execution row 20) — but never in this order within one
session: unverified — the plan's first task verifies it (part C, wave 1).

## Critic findings

Critic: 1 Blocker, 4 High (5 fixed, 0 answered), 6 Medium, 4 Nit — all fixed
in the spec.

- Blocker B1, the Stop hook rejects `Auto run: switching`: fixed — §The switch
  and part F own `scripts/turn-end.sh`; A8.
- High H1, a failure after the compaction stalls the switch: fixed — two
  stages with their own pending values; A10.
- High H2, the serial group swallowed every dependent task: fixed — alone
  versus parallel, waves by dependency depth; A13.
- High H3, skipping dforge:handoff risks a stale `latest.md`: fixed — handoff
  steps 0-3 run, any nonzero `next-step` stops the run, `switch` checks the
  plan name; A7.
- High H4, the plan-phase budget step had no mechanism: fixed — `--plan` does
  not run, `after-compact` continues in the `plan` phase; A6.
- Medium M1, the final phase could loop on compactions: fixed — one
  compaction, then `ok`; A15.
- Medium M2, spec-phase rulings and deferrals missed finishing: fixed —
  rulings imported after `start`, spec-review deferrals keep a merge; A19.
- Medium M3, `--finish` duplicated `finish-choice`: fixed — `finish-choice
  set --plan`; A5.
- Medium M4, self-review item 6 rejected below-high statements: fixed —
  §Brainstorming step 4.
- Medium M5, an engine compaction could overwrite `switch`: fixed — A11.
- Medium M6, unstated default effects and no per-request opt-out: fixed —
  §Settings states them; the spec review offers "Approve, keep the normal
  stops".
- Nits — failure reason names the switch, the switch is not a self-resume,
  `--register` optional, the probe uses a hand-written state file, the Problem
  section says which rows `on` alone meets: all fixed.
