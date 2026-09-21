# Revising plans for the executor lane

A skill and a script that bring a plan written before the external executor
lane existed up to the current plan format, so its eligible tasks can be
delegated instead of implemented by the controlling session.

## 1. Purpose

`dr-superpowers` gained an external executor lane, and every plan written before
it names no executor. Those plans still execute, but every task runs on the
Claude lane because nothing in the file says otherwise. This design adds a way
to revise such a plan in place: score what is unscored, tick the executors the
live roster offers, give every task that passes the lane gate an `**Executor:**`
line, and settle the `**Execution:**` line from what remains.

The result is an ordinary current-format plan. Nothing downstream changes:
`subagent-driven-development`, `review-route`, `plan-lint` and the wrapper all
read the revised file exactly as they read a freshly written one.

## 2. What forced it

Measured on 2026-09-21 across the two projects that hold the backlog:

| Repository | Plan files | Carrying `**Implementer:**` | Carrying `**Execution:**` | Carrying `**Executor:**` |
|---|---|---|---|---|
| darkmem | 101 | 22 | 8 | 0 |
| darkcloud | 44 | 17 | 6 | 0 |

No plan in either project carries an `**Executor:**` line or the header's
`> **External executors:**` line, because both postdate every plan in the
backlog. The gap is not uniform: a plan may carry `**Implementer:**` lines and
still have no `**Execution:**` line, so a revision keyed to an "era" would
mis-handle the majority. The skill fills in whatever a given plan is missing.

Approximating the lane gate (`total >= 2`, `risk <= 1`, excluding `spec 3`)
over every task that already carries an `**Evaluation:**` line:

| Repository | Scored tasks | Passing the lane gate |
|---|---|---|
| darkmem | 243 | 133 (54%) |
| darkcloud | 313 | 196 (62%) |

Per plan the share ranges from none to all, which is why the survey exists: some
plans are not worth revising and the skill should be able to say so before the
work starts rather than after.

## 3. Decisions

1. **A script owns the mechanical rules; the skill owns the judgment.** Gate
   arithmetic, survey aggregation and plan parsing go in `scripts/plan-revise`.
   Scoring an unscored task stays with the model, because it is a reading of the
   task, not a computation over one.
2. **Unscored plans are scored, not refused.** A plan with no `**Evaluation:**`
   lines cannot be routed at all — `review-route` exits 2 without one — so
   scoring is what gives those tasks a review seat. It is the larger half of the
   backlog and refusing it would leave the reviewer gap unaddressed.
3. **The survey reports evidence and never infers a verdict.** `completed.md` in
   both projects begins at 2026-09-17, so a pre-September plan has no reliable
   done marker. Where the signals disagree the survey prints `unknown`.
4. **A plan under execution is never edited.** A live ledger means the plan file
   is immutable and corrections go through `plan-amend`.
5. **The reviewer needs no per-task revision.** `review-route` derives the seat
   from the `**Evaluation:**` line at execution time. Decision 2 is the reviewer
   fix.

## 4. `scripts/plan-revise` — survey mode

```
plan-revise --survey DIR
```

`DIR` is a directory of plan files. One row per plan, and a summary line:

```
plan  <basename>  tasks=<n>  scored=<n>  eligible=<n>  exec=<inline|subagent|-> executors=<ids|->  live=<yes|no|unknown>  <evidence>
```

`eligible` counts only tasks that carry a parseable `**Evaluation:**` line and
pass the gate; an unscored plan reports `eligible=-`, because its eligibility is
unknowable before it is scored and a zero there would read as "nothing to gain".

Liveness evidence is three observations, printed as the reason for the verdict:
whether `.superpowers/sdd/<plan-basename>/` holds a ledger, whether the
project's `completed.md` names the plan, and the plan's checked and unchecked
step counts. A ledger present and no `completed.md` entry is `live=yes`; a
`completed.md` entry is `live=no`; anything else is `live=unknown` with the
counts printed.

Exit 0 when the directory held at least one plan, 2 on usage or a missing
directory.

## 5. `scripts/plan-revise` — single-plan mode

```
plan-revise PLAN_FILE
```

Prints what the plan is missing and, for every task that carries a parseable
score, its gate verdict:

```
header  execution=<mode|missing>  executors=<ids|missing>
task <id>  score=<total> risk=<r> spec=<s>  gate=<pass|fail:<condition>>  rung=<model>/<effort>
```

`<id>` is a task number, or a task number and a part letter for a split task, so
a split task's parts are scored from their own part bodies. A leftover
`**Evaluation:**` line above `#### Part A` is a known defect — item 1 of
`docs/superpowers/registers/2026-09-20-review-fixes-deferrals.md`, where
`plan_scores` and `review-route` both count it. `plan-revise` must not inherit
it: a task with parts takes its scores from the parts alone. This design does
not fix the defect in the shared library; it declines to reproduce it.

`rung` comes from the `codex-assignment` block of `reference/ladder.md`, read
through `executors get <id> blocks.assignment`, never hardcoded.

The script writes nothing. It reports; the skill edits.

Exit 0 when the plan parsed, 1 when it holds no task the skill could revise,
2 on usage or a missing file.

## 6. The skill: `revising-plans`

`skills/revising-plans/SKILL.md`, invoked on a named plan. Its checklist:

1. **Refuse a plan under execution.** Run `sdd-workspace` for the plan and stop
   if a ledger exists, naming `plan-amend` as the route for a live plan.
2. **Read the project's constraints.** `docs/superpowers/distilled/constraints.md`
   when it exists; a constraint declaring an executor's lane on is ticked without
   asking, exactly as `reference/executor-lane.md` §Planning already requires.
3. **Gate, then roster.** `executors path <id> gate`, then
   `detect-executors.sh`. Unless a gate prints `lane=true`, write no executor
   lines and say so in one line.
4. **Tick the executors.** The multi-select question from
   `reference/executor-lane.md` §Planning, skipped for any executor a constraint
   already settled. Record the tick as the header's `> **External executors:**`
   line.
5. **Score what is unscored.** For each task with no `**Evaluation:**` line,
   read the task and write its `**Implementer:**` and `**Evaluation:**` lines
   under the rubric in `reference/ladder.md`, applying Rule S.
6. **Apply the gate.** Run `plan-revise PLAN_FILE` and give every `gate=pass`
   task an `**Executor:**` line at the rung it printed. A batched task takes
   none, per `reference/executor-lane.md`.
7. **Settle the `**Execution:**` line** from the heavy-task count the revised
   plan now carries, under the rule in `writing-plans`.
8. **Verify.** `plan-lint PLAN_FILE` clean, and a re-run of `plan-revise` showing
   no remaining `gate=pass` task without an `**Executor:**` line.

A survey run is the same skill invoked without a plan: it runs `--survey` over
the project's plan directory and reports, writing nothing.

## 7. What this does not change

The plan format, the ladder, the gate thresholds, the wrapper, the review seats
and the ledger are all untouched. A revised plan is indistinguishable from a
plan written today; that is the whole acceptance criterion.

`plan-lint`'s lane-eligible warning stays off for inline plans. Item 5 of
`docs/superpowers/registers/2026-09-20-opencode-executor.md` deferred turning it
on because it changes a pinned fixture. Revision makes that warning more useful,
not less, but it remains out of scope here and the register row is where it
lives.

## 8. Testing

`tests/plan-revise.test.sh`, in the established style of the suites beside it,
over fixture plans covering:

- a fully scored plan, where every eligible task is found;
- a plan with no `**Evaluation:**` lines, reporting `eligible=-` rather than `0`;
- a plan with a split task, scored from its parts and not from a leftover
  `**Evaluation:**` line above `#### Part A`;
- the gate boundaries: `total 1` fails, `total 2` passes, `risk 2` fails,
  `spec 3` fails;
- a plan with a ledger present, which the survey reports `live=yes`;
- a plan named in `completed.md`, reported `live=no`;
- a plan where the signals disagree, reported `live=unknown`;
- the rung for each of totals 2, 3 and 4, read from the assignment block rather
  than asserted as literals in two places.

Skill prose assertions join the existing `inline-mode.test.sh` pattern, which
already pins `writing-plans` prose by exact string.

## 9. Repository integration

- `skills/revising-plans/SKILL.md` — new; skills are discovered from `./skills/`,
  so neither manifest lists it.
- `skills/using-superpowers/SKILL.md` — one routing row.
- `scripts/plan-revise` — new.
- `tests/plan-revise.test.sh` — new.
- `README.md` — the skill inventory prose.
- Both manifests — a version bump, kept equal.

## 10. Out of scope

- Fixing the shared `plan_scores` split-task defect. `plan-revise` avoids it;
  the register row owns the fix.
- Turning on `plan-lint`'s lane-eligible warning for inline plans.
- Any automatic repo-wide revision. The survey reports; a revision is always
  invoked on one named plan.
- Deciding whether a plan is worth revising. The survey gives the evidence.

## 11. Risks

**Scoring an unscored plan is a long run.** A 58-task plan needs every task
read. The survey exists partly so that cost is visible before it is paid, and
the skill reports the task count before it starts scoring.

**A score written now is not the score the original planner would have
written.** The rubric is applied to a task description written under a different
process. Where a task's description is too thin to score, the skill says so and
leaves the task unscored rather than guessing; `plan-lint` then reports the plan
as incomplete, which is the honest outcome.

**The roster can change between revision and execution.** This is not new:
`reference/executor-lane.md` §Dispatch already re-checks the roster at dispatch
and never trusts the plan's copy. A revised plan inherits that guarantee.
