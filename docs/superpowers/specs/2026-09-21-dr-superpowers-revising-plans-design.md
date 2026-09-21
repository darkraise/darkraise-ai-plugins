# Revising plans for the executor lane

A skill and a script that bring a plan written before the external executor
lane existed up to the current plan format, so its eligible tasks can be
delegated instead of implemented by the controlling session; and one shared
rule for reading `**Evaluation:**` lines, which two callers currently get wrong
in two different ways.

## 1. Purpose

`dr-superpowers` gained an external executor lane, and every plan written before
it names no executor. Those plans still execute, but every task runs on the
Claude lane because nothing in the file says otherwise. This design adds a way
to revise such a plan in place: score what is unscored or unparseable, tick the
executors the live roster offers, give every task that passes the lane gate an
`**Executor:**` line, and settle the `**Execution:**` line from what remains.

The result is an ordinary current-format plan. Nothing downstream changes:
`subagent-driven-development`, `review-route`, `plan-lint` and the wrapper all
read the revised file exactly as they read a freshly written one.

Building `plan-revise` means writing a third reader of `**Evaluation:**` lines.
The two that exist disagree with each other, so §5a fixes the rule at the source
before adding a caller to it.

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

Three states exist, not two, and the third is the one a naive implementation
misses. Running the shipped `plan_scores` over every plan:

| State | darkmem | darkcloud |
|---|---|---|
| Every task scores (`N total risk`) | 21 | 17 |
| No `**Evaluation:**` line anywhere (`-`) | 79 | 27 |
| At least one line that does not parse (`?`) | 1 | 0 |

The `?` plan is `2026-09-03-artifacts-frame-and-tree.md`, whose five lines use an
older prose form — `**Evaluation:** spec completeness 1 (exact signatures given),
coupling 0 …` — with no `files`, no `risk` and no `= N`. A checklist that scores
only tasks carrying *no* line skips all five and leaves the plan unroutable.

Legacy plans are also missing header sections `plan-lint` requires. For example
`2026-06-11-memory-source-attribution.md` has no Global Constraints, no
Contracts, no Assumptions and no Task index.

Applying the **full** lane gate — `total >= 2`, `risk <= 1`, and Rule S clean,
which means `files + spec + coupling < 4` and `spec != 3` — to every scoring unit
that parses:

| Repository | Scoring units that parse | Passing the lane gate |
|---|---|---|
| darkmem | 238 | 133 (55%) |
| darkcloud | 313 | 194 (61%) |

Rule S rarely binds, because a plan written under `writing-plans` already
satisfies it; it is stated here because the gate is not the three-condition
approximation it resembles. Per plan the share ranges from none to all, which is
why the survey exists: some plans are not worth revising and the skill should be
able to say so before the work starts rather than after.

## 3. Decisions

1. **A script owns the mechanical rules; the skill owns the judgment.** Gate
   arithmetic, survey aggregation, plan parsing and the recommended execution
   mode go in `scripts/plan-revise`. Scoring a task, deciding a split, choosing
   among eligible executors and every edit stay with the model.
2. **Unscored and unparseable plans are both repaired, not refused.** A task
   whose score is absent or returns `?` cannot be routed — task routing dies
   without a parseable line — so repairing it is what gives the task a review
   seat.
3. **The survey reports evidence and never infers a verdict.** Where the signals
   disagree it prints `unknown` and shows them.
4. **A plan under execution is never edited.** A live ledger means the plan file
   is immutable and corrections go through `plan-amend`.
5. **The reviewer needs no per-task revision.** `review-route` derives the seat
   from the `**Evaluation:**` line at execution time. Decision 2 is the reviewer
   fix.
6. **One shared rule for reading `**Evaluation:**` lines, fixed at the source.**
   Both existing readers are wrong, in different ways, and `plan-revise` would be
   the third. See §5a.

## 4. `scripts/plan-revise` — survey mode

```
plan-revise --survey DIR
```

`DIR` is a directory of plan files. A plan file is a `*.md` file in `DIR` from
which `plan_tasks` yields at least one task; anything else is skipped silently,
which excludes `completed.md`, `PROGRESS.md` and notes without naming them.
Subdirectories are not descended.

One row per plan, then a summary line:

```
plan  <basename>  tasks=<n>  scored=<n>  unparsed=<n>  eligible=<n|-|n+?>  exec=<inline|subagent|-> executors=<ids|->  live=<yes|no|unknown>  <evidence>
```

**Counting.** A task with parts contributes one scoring unit per part; a task
without parts contributes one. `tasks` counts tasks, `scored` and `unparsed`
count scoring units, so `scored + unparsed` need not equal `tasks`.

**`eligible`.** `-` when nothing in the plan parses, because eligibility is
unknowable before the plan is repaired and `0` would read as "nothing to gain".
`<n>` when every unit parses. `<n>+?` when some parse and some do not: `n` units
are known eligible and the remainder is unknown. A count is never coerced to a
number that hides an unknown.

**Eligibility here is potential, not authorised.** The survey has no executor
selection, so it applies the score conditions of the lane gate and not
`require_external_enabled`. A row's `eligible` says how much of the plan *could*
be delegated if an executor were ticked, which is the question the survey is
asked.

**Liveness** is decided by one precedence contract, shared with the refusal in
§6 so the two cannot disagree:

1. `plan_ledger` returns a file — the ledger at
   `<worktree>/.superpowers/sdd/<basename without .md>/progress.md` whose
   identity line names *this* plan. `plan_ledger` already ignores a stale ledger
   sharing the slug, which is why it is used rather than a path test. This is
   `live=yes`, and it outranks everything below it.
2. No ledger, and `completed.md` names the plan with the `merged into` form —
   `live=no`.
3. No ledger, and `completed.md` names the plan with the `via PR` form —
   `live=unknown`. `finishing-a-development-branch` writes that line *before* the
   push and does not clean up the worktree on that path, so the plan may be
   awaiting a merge.
4. Anything else — `live=unknown`, with the checked and unchecked step counts
   printed as evidence. Checkbox counts are evidence, never a verdict: a
   subagent-mode plan records progress in the ledger, not in the file.

A ledger may live in a linked worktree rather than the primary checkout, so the
survey resolves ledgers across the worktrees `git worktree list` reports and says
which one a ledger came from.

Exit 0 when `DIR` held at least one plan, 1 when it held none, 2 on usage or a
missing directory.

## 5. `scripts/plan-revise` — single-plan mode

```
plan-revise PLAN_FILE
```

Prints what the plan is missing, one row per scoring unit, and a recommendation:

```
header  execution=<mode|missing>  executors=<ids|missing>  sections=<missing list|ok>
unit <id>  score=<total|?|->  risk=<r|?|->  rule_s=<ok|violated|unknown>  gate=<pass|fail:<condition>|unknown>  executor=<id|none>  rungs=<id>:<model>/<effort>[,...]
recommend  execution=<inline|subagent>  model=<model>  effort=<effort>  delegated=<n>/<tasks>
```

`<id>` is a task number, or a task number and a part letter for a split task.

**Every row says what is actionable**, which is what makes §6's verification
step possible: a unit already carrying an `**Executor:**` line reports it, so
"every `gate=pass` unit carries an executor" is a condition the output can
express.

**Batching is not represented here, because a plan cannot represent it.**
`subagent-driven-development` decides batches at dispatch from the briefs of
contiguous candidate tasks, and a batched task then never runs on an external
executor. Nothing in the plan file marks a batch, so revision writes an
`**Executor:**` line on every unit the gate passes and the dispatcher's batching
decision overrides it later. A revision that tried to predict batches would be
guessing at a decision made with information it does not have.

**`rungs` names every executor that would take the unit.** Each executor's
thresholds and rung come from its own registry entry — `executors get <id>
blocks.gate` and `blocks.assignment` — never from a hardcoded table. Where
several ticked executors admit a unit the script lists each; choosing between
them is the skill's judgment, and the plan carries at most one `**Executor:**`
line.

**Single-plan mode applies the whole gate, including `require_external_enabled`.**
A unit whose scores pass while the header ticks no executor that admits it
reports `gate=fail:not_enabled`, not `gate=pass`. Reporting it as passing would
invite an `**Executor:**` line naming an executor nobody selected. This is the
one place single-plan mode and the survey differ: the survey answers "how much
*could* be delegated", so it ignores selection, while single-plan mode answers
"what this plan should now say", which selection decides.

**`recommend`** applies the `writing-plans` execution rule mechanically over the
revised scores: the heavy count, the four-band population and the third
threshold, and the resulting model and effort. It is arithmetic over numbers the
script already holds, and leaving it to the model was the reason §5a's
counterexample went unnoticed.

The script writes nothing. It reports; the skill edits.

Exit 0 when the plan parsed, 1 when it holds no unit the skill could revise,
2 on usage or a missing file.

## 5a. One rule for reading `**Evaluation:**` lines

Two readers exist and neither is right. Both were reproduced on 2026-09-21.

**Defect 1 — a leftover line above `#### Part A` is counted.** Item 1 of
`docs/superpowers/registers/2026-09-20-review-fixes-deferrals.md`. A task whose
stale whole-task line scores 6 above two parts each scoring 2:

| Call | Reported | Correct |
|---|---|---|
| `plan_scores` | `1  6  1` | `1  2  0` |
| `plan_heavy` | Task 1 is heavy | not heavy |
| `review-route --task 1` | `codex:heavy` / `judge-opus`, `reason=band` | the light band |
| `review-route --task 1A` | `codex:light` / `judge-sonnet-high` | already correct |

**Defect 2 — `review-route` does not skip fenced blocks.** `plan_scores` filters
fences; `review-route:241` greps raw text. A task scoring 2 that merely *shows*
an example line inside a fence:

| Call | Reported | Correct |
|---|---|---|
| `plan_scores` | `1  2  0` | correct already |
| `review-route --task 1` | `codex:heavy+judge-fable`, `reason=risk` | the light band |

Defect 2 escalates to the most expensive seat in the table, and unlike defect 1
it misfires on an unsplit task. The part-lettered path is affected too: the part
filter does not skip fences either, so `1A` is *not* reliably correct in general
— only in defect 1's shape.

**The rule.** An `**Evaluation:**` line scores a unit when it is outside every
fenced block, and, when the task's text holds any `#### Part <L>:` heading, at or
after the first such heading. A `#### Part <L>:` heading inside a fence is not a
heading. A line left above `#### Part A` scores the task as it stood *before* the
split — the score that forced the split, so always the wrong one.

**Where it lives.** One helper in `scripts/lib/plan.sh`, taking task text and
returning the lines that score it. `plan_scores` calls it, and so does
`review-route`'s own loop over both a whole-task id and a part id. The contract
is total: nothing else in the library or the scripts may read `**Evaluation:**`
lines from text directly. Two call sites implementing one rule privately is how
these two drifted apart.

**Consumers to re-verify**, because all of them read `plan_scores`: `plan_heavy`,
`plan_delegated`, `plan-lint`, `task-brief`, and `review-route` in its `--task`,
`--ruling`, `--plan-round` and `--final` modes. `plan_executors` reads
`**Executor:**` lines, not scores, and is unchanged.

**`plan-lint` gains a NOTE**, not an error, when a task has parts and also an
`**Evaluation:**` line above the first one. Once the line stops counting, a
reader who sees it still reads the old total off the page while the tooling uses
another. It is a NOTE because the plan is correct as the tooling now reads it.

**What the fix changes, stated accurately.** It lowers review bands and never
raises them. It does **not** preserve execution assignment. Reproduced: a plan
whose Task 1 carries a stale total-5 line above parts scoring 4 and 2, plus a
total-4 Task 2 and a total-2 Task 3.

| | `plan_delegated` |
|---|---|
| Before | `1 heavy`, `2 total 4` — two of three delegated |
| After | nothing delegated |

Task 1 drops from 5 to 4, so two of three tasks are four-band, `3 × 2 > 3` trips
the threshold, and neither is delegated. An inline plan therefore implements more
itself and may need a heavier model than its existing `**Execution:**` line
names. A plan already carrying an Execution line can be invalidated by this fix,
which is why `plan-revise` recomputes the recommendation rather than trusting
the line.

## 6. The skill: `revising-plans`

`skills/revising-plans/SKILL.md`, invoked on a named plan. Its checklist, in
this order — the order matters, and §Planning of `reference/executor-lane.md` is
the authority it must match:

1. **Refuse a plan under execution**, by the §4 precedence contract. `live=yes`
   stops the skill and names `plan-amend`. `live=unknown` also stops it, and
   says which signals disagreed: editing a plan that might be running is the
   failure this guard exists to prevent.
2. **Repair the plan's structure.** Add the header sections `plan-lint` requires
   and the plan lacks — Global Constraints, Contracts, Assumptions, Task index —
   drawn from the plan's own content, not invented.
3. **Score every unit that needs it.** A unit with no `**Evaluation:**` line, a
   unit whose line does not parse, and a unit with a score but no
   `**Implementer:**` line are all repaired here. Apply Rule S: a unit scoring
   `reducible >= 4` or `spec = 3` is split or redesigned, not assigned a larger
   model. Scoring precedes any executor question, because the gate reads the
   scores.
4. **Read the project's constraints.** `docs/superpowers/distilled/constraints.md`
   when it exists.
5. **Gate each executor, then run the roster.** Enumerate executors with
   `executors list`. For each, *run* its gate — `bash "$(bash <plugin-root>/scripts/executors path <id> gate)"`,
   which is a script to execute, not a path to print — and say its line aloud
   when it ends `source=probe`. Run `detect-executors.sh` only for executors
   whose gate printed `lane=true`. An executor a constraint declares on is
   auto-ticked only when the roster also reports it `usable`; a constraint cannot
   tick an executor that is not there.
6. **Offer the rest**, as the multi-select question in `executor-lane.md`
   §Planning, naming every other detected executor with its reason. If none is
   usable, ask nothing. Record the tick as the header's
   `> **External executors:**` line.
7. **Apply the gate.** Run `plan-revise PLAN_FILE` and give every `gate=pass`
   unit an `**Executor:**` line at the rung it printed for the ticked executor.
8. **Settle the `**Execution:**` line** from `plan-revise`'s `recommend` row.
9. **Verify.** `plan-lint PLAN_FILE` clean, and a re-run of `plan-revise` in
   which every unit is `gate=fail` or `executor=<id>`, and the header's
   `execution` matches the `recommend` row.

Where a task's description is too thin to score honestly, the skill leaves it
unscored, says which task and why, and lets `plan-lint` report the plan as
incomplete. A guessed score is worse than a visible gap.

A survey run is the same skill invoked without a plan: it runs `--survey` over
the project's plan directory and reports, writing nothing.

## 7. What this does not change

The plan format, the ladder, the gate thresholds, the wrapper and the ledger are
untouched. A revised plan is indistinguishable from a plan written today; that
is the acceptance criterion for the skill.

§5a is a deliberate behaviour change to shipped routing, correcting seats and
delegation sets that were already wrong.

`plan-lint`'s lane-eligible warning stays off for inline plans. Item 5 of
`docs/superpowers/registers/2026-09-20-opencode-executor.md` deferred turning it
on because it changes a pinned fixture. Revision makes that warning more useful,
not less, but it remains out of scope here.

## 8. Testing

`tests/plan-revise.test.sh` for the new script, and the §5a fix tested in the
suites that own the affected code.

For §5a, in `plan-lib.test.sh`, `review-route.test.sh`, `plan-lint.test.sh` and
`task-brief.test.sh`:

- defect 1: a split task with a stale parent line, scored from its parts, for
  `plan_scores`, `plan_heavy`, `plan_delegated` and the whole-task review seat;
- defect 2: a fenced example line ignored by `review-route` for both a
  whole-task id and a part id;
- a `#### Part <L>:` heading inside a fence, which is not a heading;
- **both directions of the four-band threshold**: the counterexample above,
  where the fix removes every delegation, and a case where the delegated set is
  unchanged;
- the new `plan-lint` NOTE;
- `plan_executors` unchanged by the fix.

For `plan-revise`:

- a fully scored plan, a plan with no lines, and a plan with unparseable lines
  in the older prose form, giving `eligible=<n>`, `-` and `<n>+?`;
- the gate boundaries: `total 1` fails, `total 2` passes, `risk 2` fails,
  `spec 3` fails, and `files + spec + coupling = 4` fails on Rule S while
  totalling under 5;
- each liveness precedence rule, including a ledger whose identity line names a
  different plan, and a `via PR` entry yielding `unknown`;
- a ledger in a linked worktree;
- the `recommend` row against `writing-plans`' rule, including the four-band
  third threshold;
- the rung resolved through the registry, driven by the `stub` executor in
  `tests/fixtures/executors/stub.json` with `tests/fixtures/stub-ladder.md`, so
  a second registered executor is exercised rather than assumed;
- a unit admitted by two ticked executors, which reports both rungs;
- a unit whose scores pass while no executor is ticked, which does not pass;
- exits: empty directory, unparseable plan, already-revised plan.

Skill prose assertions join the existing `inline-mode.test.sh` pattern.

## 9. Repository integration

- `skills/revising-plans/SKILL.md` — new; skills are discovered from `./skills/`,
  so neither manifest lists it.
- `skills/using-superpowers/SKILL.md` — one routing row.
- `scripts/plan-revise` — new.
- `tests/plan-revise.test.sh` — new.
- `scripts/lib/plan.sh`, `scripts/review-route`, `scripts/plan-lint` — §5a.
- `docs/superpowers/registers/2026-09-20-review-fixes-deferrals.md` — item 1
  moves to `done` through `scripts/register set`, with §5a as its note; defect 2
  is added as a new row and closed in the same work.
- `README.md` — the skill inventory prose.
- Both manifests — a version bump, kept equal.

## 10. Out of scope

- Turning on `plan-lint`'s lane-eligible warning for inline plans.
- Any automatic repo-wide revision. The survey reports; a revision is always
  invoked on one named plan.
- Deciding whether a plan is worth revising. The survey gives the evidence.

## 11. Risks

**§5a changes how existing plans route and delegate.** A plan in flight whose
split task carries a leftover line will route that task to a cheaper seat, and
an inline plan may delegate a different set of tasks than it did yesterday — in
the reproduced case, none at all. Any plan mid-execution should be re-checked
against `plan-revise`'s `recommend` row before its next task is dispatched.

The rule and its call sites land in consecutive commits on one branch rather
than in a single commit. There are three call sites, not two — `plan-lint` reads
these lines directly as well — and a task touching the helper, all three scripts
and four test suites scores `files 3`, which Rule S forbids. The intermediate
commits are not a regression: `review-route` and `plan-lint` already disagree
with `plan_scores` today, so a bisect landing between them finds the shipped
inconsistency, not a new one. Nothing outside the branch observes the
intermediate states.

**Repairing a legacy plan is a long run.** A 58-task plan needs every task read.
The survey exists partly so that cost is visible before it is paid.

**A score written now is not the score the original planner would have
written.** The rubric is applied to a task description written under a different
process. §6's thin-description rule is the mitigation.

**The roster can change between revision and execution.** Not new:
`reference/executor-lane.md` §Dispatch re-checks the roster at dispatch and never
trusts the plan's copy. A revised plan inherits that guarantee.
