# dr-superpowers — Execution and review cost (sub-project 10 design)

Date: 2026-09-17. Status: owner-approved design. Sub-project 10 of 10 of
`docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`, the last.
Scope: Claude-host plans. A `Host: codex` plan keeps its own scoring and routing
in `reference/native-codex.md` and is untouched.

## 1. What this sub-project is for

Running dr-superpowers spends the owner's weekly limit too fast. The cause is
not the number of review seats: a 16-task plan dispatches about 38 seats here
against about 34 under upstream superpowers 6.3.0. The cause is three things:

- **Execution mode.** One task totalling 5 forces a whole plan into subagent
  mode, which dispatches an implementer, a task review and fix-round re-reviews
  for every task.
- **Reviewer tier.** Most task reviews land on Opus, and with Codex off every
  task at risk 2 or above lands on Fable.
- **Review rounds.** Plan review re-rounds on any Important finding, so it
  nearly always runs all three rounds.

This sub-project keeps the ladder and the implementer assignment table, which
decide *which* seat, and changes how many seats run and on which model.

## 2. Decisions fixed here

Owner rulings, 2026-09-16 and 2026-09-17:

1. SP10 runs only after SP9 merged (sequence A, 2026-09-16). SP9 merged at
   06d5939.
2. SP10 is one sub-project.
3. **Mixed mode.** An inline plan delegates its heavy tasks to an implementer
   subagent with the full per-task review loop (§4).
4. **Whole-plan subagent mode** only when more than half the tasks are heavy
   (§4.2).
5. **Shared loop.** The per-task loop moves to `reference/delegated-task.md`;
   delegation is derived from the Evaluation line, with no new plan syntax (§5).
6. **Fable is kept for critical seats only**: risk-3 task reviews, the two-list
   final-review dedupe, plan review round 1 of an intricate plan when Codex is
   unavailable, and critical rulings. Sonnet and Opus take the rest (§6).
7. **Codex reviews Claude-implemented tasks when available**: Sol for totals
   0-3, Astra for 4-6, at any risk; Astra is paired with Fable at risk 3 (§6.1).
8. **Plan review** re-rounds only on a Critical finding or a score of 8 or
   below, capped at 1, 2 or 3 rounds by the plan's highest task total (§6.2).
9. **Budget.** A controller of a subagent-mode plan hands off at 350k; every
   other session keeps 475k (§7).

## 3. Evidence

Measured 2026-09-16 from 93 session transcripts in this project, weighted by API
cache pricing (1-hour write 2.0x, 5-minute write 1.25x, read 0.1x). Whether the
subscription limit weighs tokens exactly this way is unverified.

| Measurement | Value |
|---|---|
| One subagent seat, median of 16 runs with usage records | 238k units, about 101k of it the cold-start write |
| Seats for a 16-task plan in subagent mode | about 48, so about 11.4M units (median x count, not a total) |
| Context growth per task, controller | 9.7k median |
| Context growth per task, inline | 19.1k median, 30.9k p75 |
| Static floor at a session's first call | 57k median |
| Budget 475k -> 250k, all sessions replayed with a realistic rebuild | about -4% to -22%; inline fits only 2-4 tasks at 250k |

**Correction measured 2026-09-17.** The 2026-09-16 figure of 133k context at an
inline session's first task is not reproducible. The four inline sessions whose
transcripts invoke `executing-plans` reached their first `task-brief` at 69k,
78k, 81k and 90k, against a first-call context of 48-59k. Pre-task overhead is
14-42k, of which the `executing-plans` body is about 6k tokens. Pre-task overhead
is therefore not a lever on its own; it matters only in that mixed mode must not
load the whole `subagent-driven-development` body (about 14k tokens) into an
inline session (§5).

## 4. Mixed mode

### 4.1 Heavy task

A task is **heavy** when its `**Evaluation:**` line totals 5 or more, or its risk
is 3. A task split into parts is heavy when any part is. A task with no
Evaluation line is not heavy.

### 4.2 The Execution line (`writing-plans`)

Count tasks by `### Task N` heading; parts do not count separately.

- `subagent` when `2 x heavy > tasks`. The line stays
  `claude --model sonnet --effort high`.
- Otherwise `inline`. The model follows the highest total among the non-heavy
  tasks: `sonnet` when every non-heavy task totals 3 or less, `opus` when one
  totals 4. The effort is that task's assigned tier's effort (`impl-haiku` counts
  as `low`), as today.
- The owner may override the line either way.

### 4.3 `plan-lint` rule 5

Rule 5 no longer rejects an inline plan for a heavy task. It:

- prints `NOTE header: delegated: Task 2, Task 6` for an inline plan with any
  heavy task (a `NOTE` counts as neither an error nor a warning);
- warns `WARN header: Execution line is inline but <h> of <n> tasks are heavy`
  when the majority rule says `subagent`, and
  `WARN header: Execution line is subagent but only <h> of <n> tasks are heavy`
  when it says `inline`;
- keeps its error for an inline model weaker than the highest non-heavy total
  needs.

### 4.4 `task-brief`

When the plan is not `Host: codex`, its Execution line is not `subagent`, and the
task is heavy, the brief's second line (after the task heading) is
`**Dispatch:** delegated — total <t>, risk <r>`, using the heaviest part's
values. No other brief changes. The session never re-scores; it reads this line.

### 4.5 `executing-plans`

Per task:

- **No Dispatch line.** Unchanged: the session implements, fixes up to 3
  rounds, and writes `complete (…, unreviewed)`.
- **`**Dispatch:** delegated`.** The session reads `reference/delegated-task.md`
  if it has not this session, and runs it: the task's `**Implementer:**` agent,
  the seat `review-route` prints, fix rounds up to 5 with the ladder's
  escalation, and the complete line with `review clean` and scores.

A delegated task that is still failing after `fix round 5/5` goes to the ruling
seat as a `breaker` item, as in subagent mode. It is not a trigger in Switching
to subagent mode, whose three triggers are unchanged.

### 4.6 Ledger and recovery

No new line types. Delegated tasks write subagent mode's lines:
`Task <N>: implementer <agent> (assigned; base <sha7>)`,
`Task <N>: fix round R/5 (…)` and
`Task <N>: complete (commits …, review clean; scores …, seat <seat>) — …`.

The `executing-plans` Recovery table gains rows keyed on those shapes:

| Last line | Action |
|---|---|
| `implementer <agent> (assigned; base <sha7>)`, agent not `inline` | Resume the delegated loop at dispatch: `delegated-task.md`'s recovery for an assigned line |
| `fix round R/5`, R < 5 | Resume the delegated loop at round R+1 |
| `fix round 5/5` | Send the `breaker` item |

The Plan-state rule is unchanged: only an `escalated inline -> subagent` line
with no later `implementer inline (assigned` line means the plan left inline
mode. `scripts/next-step` and `resume-execution` need no mode change; a test
proves a mixed ledger resumes inline at the delegated task (§10).

## 5. `reference/delegated-task.md`

**Moves out of `subagent-driven-development`**, nearly verbatim, and exists
nowhere else afterwards:

- The Task Loop steps 1-5: dispatch the implementer, handle the report, review
  the task, the fix loop, complete the task.
- The Seats table's implementer, external implementer, task reviewer and scoped
  re-review rows, and the rules "fleet agents take no model argument",
  "general-purpose seats always take an explicit model" and "turn count beats
  token price".

**Stays in `subagent-driven-development`:** After compaction, host selection,
Overview, When to Use, the process graph, Setup, the ruling-seat and final-review
rows of Seats, The Ledger and its recovery table, The Ruling Seat, Session
Budget, the batching and waiting paragraphs, Final Review, Finish, Common
Rationalizations and the Example Workflow. Its Task Loop section becomes those
two paragraphs plus: for each task, or batch, run `delegated-task.md`.

**Contract at the top of the file.** The caller holds the plan workspace, the
ledger, the task's brief file and a ruling seat it can dispatch. The loop writes
only shared-grammar ledger lines, and returns on a `complete` line or a
`BLOCKED` line.

**External executor.** The Executor branch stays in the loop for subagent mode.
It is unreachable from an inline plan: the lane admits only risk <= 1 and totals
2-4, so no heavy task carries an Executor line. `plan-lint` keeps skipping lane
warnings on inline plans.

**References.** `reference/external-executor.md:420` ("§3 Review the task") and
every other pointer into the moved steps point at `delegated-task.md`.

**Compaction.** Both skills' After compaction blocks gain: if a task's last line
is an agent-named assigned line or `fix round R/5`, re-read
`reference/delegated-task.md` before continuing.

## 6. Review routing

`judge-sonnet-high`, `judge-opus` and `judge-fable` run Sonnet 5, Opus 5 and
Fable 5 at high effort. Codex Sol is `gpt-5.6-sol / high` (the `codex-judge`
block's last row); Codex Astra is `gpt-6-astra / high`, falling back once to Sol
on a refusal (the first row). The rule that `judge-opus` takes any seat naming
`judge-fable` when Fable is unavailable or the owner declined it, said aloud,
applies throughout.

### 6.1 Task reviews (`scripts/review-route --task`)

**Band** (Claude seat for a total): 0-3 `judge-sonnet-high`, 4-6 `judge-opus`.
Today it is 0-1 Sonnet, 2-4 Opus, 5-6 Fable.

First matching row wins; a batch or a split task routes on its highest total and
highest risk.

| # | Condition | Primary | Fallback | reason |
|---|---|---|---|---|
| 1 | Task carries an `**Executor:**` line, risk 3 | `judge-fable` | - | executor |
| 2 | Task carries an `**Executor:**` line | band | - | executor |
| 3 | Codex review surface off, risk 3 | `judge-fable` | - | codex-off |
| 4 | Codex review surface off | band | - | codex-off |
| 5 | Risk 3 | `codex:heavy+judge-fable` | `judge-fable` | risk |
| 6 | Total 0-3 | `codex:light` | band | band |
| 7 | Total 4-6 | `codex:heavy` | band | band |

Changes from today: rows 1, 3 and 5 match at risk 3 instead of risk >= 2; rows 6
and 7 admit risk 2; the band moves. Row 1 is unreachable under the lane gate and
stays for an overridden task.

### 6.2 Plan review (`writing-plans` Lint and Review, `review-route --plan-round`)

**Intricate plan:** any task at risk 3 or totalling 6.

| Round | Codex review surface on | Codex off |
|---|---|---|
| 1 | `codex:plan`, fallback `judge-fable` if intricate, else `judge-opus` | `judge-fable` if intricate, else `judge-opus` |
| 2, 3 | `judge-opus` | `judge-opus` |

**Cap** from the plan's highest task total: <= 3 gives 1 round, 4-5 gives 2,
6 gives 3. `review-route` appends `cap=<n>` to every `--plan-round` line, so the
cap is computed in a tested script. A plan with no parseable Evaluation line
exits 2 as today.

**Re-round** only while `r < cap` and a round returned a Critical finding or any
score of 8 or below. Important findings are fixed and re-linted with no new
round; Minor findings are advisory. At the cap, remaining Critical findings and
scores of 8 or below go to the owner. A borderline score (9-13) still gets its
one-line decision in Assumptions. On any `review-route` exit 2 other than a
Codex-host plan, review with `judge-opus` and say why.

### 6.3 Final review (`reference/final-review.md`)

Step 3 runs only when **both** the Claude review and the Codex round produced a
findings list with at least one finding. It stays one `judge-fable` dispatch that
merges, tags and returns CONFIRMED or REJECTED.

With **one list** (Codex off, `TIMEOUT`, `FAILED`, or a Codex round with no
findings) there is no step-3 seat. Every finding enters the one fix wave. The
fixer — the fix subagent in subagent mode, the session itself inline — checks
each against the code under dr-superpowers:receiving-code-review, fixes the real
ones and records each rejected one with its evidence in
`<workspace>/final-fix-report.md`. The one scoped re-review reads that report,
and a rejection it disputes goes to the ruling seat as a `final-residual` item.
The report step lists confirmed findings as the fixed ones and rejected findings
as the fixer's rejections. This keeps a subagent-mode controller free of
judgment calls.

### 6.4 Ruling seat (`review-route --ruling`)

New form: `review-route PLAN_FILE --ruling KIND [ID ...]`, printing
`review-seat ruling=<kind> tasks=<ids|plan> primary=<seat> fallback=- reason=<why>`.

| Condition | Seat | reason |
|---|---|---|
| `KIND` is `final-residual` | `judge-fable` | merge-gate |
| Any named task at risk 3 | `judge-fable` | risk |
| `KIND` is `preflight` and the plan is intricate (§6.2) | `judge-fable` | intricate |
| Otherwise | `judge-opus` | routine |

A batch of items at one decision point routes on its heaviest item. `KIND` must
be one of the seven kinds in `ruling-prompt.md`, else exit 2.

**Header amendments.** When a `judge-opus` ruling returns AMEND for the Header
target, dispatch `judge-fable` once with that entry and the Opus verdict before
running `scripts/plan-amend`. Fable's verdict replaces the Opus verdict. Log
`Ruling: header amendment confirmed by judge-fable — <verdict>`.

Both execution skills dispatch the seat `--ruling` prints instead of naming
`judge-fable`.

### 6.5 Other Fable seats

| Seat | Today | After |
|---|---|---|
| `selecting-approaches` ring ranking | `judge-fable` | `judge-opus` |
| `distilling-docs` verification | `judge-fable` | `judge-opus` |

The `judge-fable` and `judge-opus` agent descriptions are rewritten to list the
seats each now serves.

## 7. Budget by session type

A session hands off at **350k** when it controls a subagent-mode plan, and at
**475k** otherwise. `DR_SUPERPOWERS_BUDGET` overrides both.

- `scripts/context-size` gains `--plan PLAN_FILE`. The budget is 350k when the
  plan's Execution line is `subagent`, or when its ledger holds an
  `escalated inline -> subagent` line with no later
  `implementer inline (assigned` line. A `Host: codex` plan, a missing plan or no
  `--plan` gives 475k.
- The ledger test moves into a `lib/plan.sh` helper, used by `context-size`,
  `next-step` (replacing its inline grep at `scripts/next-step:101`) and the
  executing-plans Plan-state prose, so the three cannot disagree.
- `task-brief` and `review-package` pass `--plan` when they print the budget
  line.
- The budget line's format is unchanged.
- `reference/session-budget.md`'s Numbers table gains the controller row (350k,
  owner ruling 2026-09-17, 9.7k against 19.1k per task) and its margin note is
  updated.

## 8. Interface changes

| Surface | Change |
|---|---|
| `scripts/review-route` | New band; risk-3 rows; `cap=` on `--plan-round`; round-1 fallback by intricacy; new `--ruling` |
| `scripts/plan-lint` | Rule 5 rewritten (§4.3); `NOTE` severity |
| `scripts/task-brief` | `**Dispatch:** delegated` line (§4.4); passes `--plan` |
| `scripts/review-package` | Passes `--plan` |
| `scripts/context-size`, `scripts/lib/context.sh` | `--plan`; mode-dependent default |
| `scripts/lib/plan.sh` | Heavy-task and left-inline helpers |
| `scripts/next-step` | Uses the left-inline helper |
| `reference/delegated-task.md` | New (§5) |
| `skills/subagent-driven-development/SKILL.md` | Task Loop moved out; ruling seat via `--ruling` |
| `skills/executing-plans/SKILL.md` | Delegated tasks, recovery rows, ruling seat via `--ruling`, eligibility prose |
| `skills/writing-plans/SKILL.md` | Execution-line rule; plan-review cap, trigger and fallback |
| `skills/selecting-approaches/SKILL.md`, `skills/distilling-docs/SKILL.md` | `judge-opus` |
| `reference/final-review.md` | Two-list step 3; one-list fix wave |
| `reference/external-executor.md` | Risk-3 rows; pointer to `delegated-task.md` |
| `reference/session-budget.md` | Controller budget |
| `skills/subagent-driven-development/references/ruling-prompt.md`, `task-reviewer-prompt.md` | Seat names |
| `agents/judge-fable.md`, `agents/judge-opus.md`, `README.md` | Descriptions |
| Both manifests | 1.10.0 -> 1.11.0 |

## 9. Approaches considered

- **Raise the inline ceiling to total 5, no per-task review.** Rejected: a risk-2
  change to a shared code path would never be reviewed alone.
- **Inline, reviewing risky tasks the session implemented.** Rejected in favour
  of mixed mode: the reviewer would check work from the same seat that holds the
  whole run's context.
- **Only an owner override picks subagent mode.** Rejected: a plan full of heavy
  tasks would run with an Opus inline session as its coordinator.
- **A condensed copy of the loop in `executing-plans`.** Rejected: two copies of
  the fix-round and escalation rules drift, as the stale role names after
  sub-project 2 showed.
- **Hand each delegated task to `subagent-driven-development`.** Rejected: it
  loads about 14k tokens, and a mode switch is a hard stop.
- **Split on risk under Rule S.** Rejected: risk is the axis the ladder defines as
  irreducible by splitting.
- **Ruling seat always Opus, or always Fable.** Rejected for the tiered rule in
  §6.4.
- **One 475k budget, or three budgets with planning at 300k.** Rejected: under
  mixed mode subagent sessions are the only ones the data supports cutting.
- **Pre-task overhead as its own change.** Dropped after the 2026-09-17
  measurement (§3).

## 10. Testing

Suites under `plugins/dr-superpowers/tests/`:

- **`plan-lint.test.sh`**: an inline plan with a heavy minority passes and prints
  the `NOTE`; heavy majority marked inline warns; light plan marked subagent
  warns; the model error uses the highest non-heavy total; a split task is heavy
  when one part is; `Host: codex` plans are unaffected.
- **`review-route.test.sh`**: every row of §6.1 with the Codex surface on and
  off; risk 2 at totals 3 and 5; batches and parts; round 1 on and off for an
  intricate and a plain plan; `cap=` for highest totals 3, 5 and 6; every
  `--ruling` row, an unknown kind, and a batch routing on its heaviest item.
- **`context-size.test.sh`**, **`budget-line.test.sh`**: 475k with no `--plan`;
  350k for a subagent plan and for an inline plan whose ledger left inline mode;
  475k after a later `implementer inline` line; the environment variable
  overriding both; a `Host: codex` plan at 475k.
- **`inline-mode.test.sh`**: the Dispatch line appears only for heavy tasks of a
  non-subagent plan and carries the heaviest part's values; `next-step` on a
  mixed ledger (inline tasks complete, a delegated task at `fix round 2/5`)
  resumes that task inline without reporting a mode switch.
- **`next-step.test.sh`**: existing switch cases pass through the helper.
- **Content checks** (`criteria.test.sh` or `tests/repository-layout.test.mjs`):
  `delegated-task.md` holds the five step headings and the contract;
  `subagent-driven-development` holds none of the moved headings and links the
  file; `executing-plans` links it; neither execution skill names `judge-fable`
  as the ruling seat; `final-review.md` states the two-list condition;
  `selecting-approaches` and `distilling-docs` name `judge-opus`.
- **`fleet.test.sh`**: agent descriptions still validate.

## 11. Verification

- `node scripts/validate-repository.mjs`.
- `node scripts/test-all.mjs`; the only expected failure is the pre-existing
  `rg: command not found` in `tests/ui-discovery.test.mjs`.
- `claude plugin validate` on the marketplace and every Claude plugin.
- Every test and CLI run bounded, and every process it starts cleaned up.

## 12. Out of scope

- The 5-round fix cap per task.
- The final whole-branch reviewer's model.
- Codex host plans and `reference/native-codex.md`.
- The Codex executor lane and its gate.
- Backfilling `docs/superpowers/plans/completed.md` and removing stale
  `.superpowers/sdd/` workspaces.

## 13. Program design amendment

Appended to §6 of the program design:

**Amendment 2026-09-17 (sub-project 10 spec).** Sub-project 10, "Execution and
review cost", is the last of ten. Measurement over 93 sessions found the weekly
limit spent on execution mode and reviewer tier rather than seat count. An
inline plan now delegates its heavy tasks (total >= 5 or risk 3) through a
shared `reference/delegated-task.md`, and whole-plan subagent mode needs a heavy
majority. Fable is kept for risk-3 task reviews, the two-list final-review
dedupe, round 1 of an intricate plan with Codex unavailable, and critical
rulings; Codex Sol and Astra review Claude-implemented tasks when available.
Plan review re-rounds only on a Critical finding or a score of 8 or below, capped
by the highest task total. A subagent-mode controller hands off at 350k. Details:
`docs/superpowers/specs/2026-09-17-dr-superpowers-execution-cost-design.md`.
