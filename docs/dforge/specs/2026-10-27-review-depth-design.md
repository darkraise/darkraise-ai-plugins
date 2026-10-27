# Review depth: a short evaluation that sizes a plan's process

**Execution strategy:** parallel — after a foundation part that builds
`scripts/depth-route`, the spec phase, the plan phase and the final review are
three parts with disjoint files (see Parallel decomposition).

**Depth:** standard — interface (depth-route does not exist yet; set by hand
from the rule in §1)

## Decisions

- **Scope.** Shown the four phases every architectural plan runs (spec reviews,
  plan drafting and review, execution, final review). Asked which phases the
  evaluation may trim. Answer: "All four phases" — the option read: "One
  evaluation decides the depth of the spec reviews, the plan review and
  handoff, execution, and the final review."
- **Evaluator.** Asked how the depth is decided. Answer: "Script, two
  checkpoints" — the option read: "The session answers a short fixed rubric
  when it classifies the request; a script turns the answers into a depth
  recorded in the spec. After the plan is written, the same script re-checks
  against the tasks' real scores and may only raise the depth, never lower
  it." The do-less option, "Session judgement" (a one-line pick with no
  script), was offered and not chosen.
- **Task count.** A first ladder raised the depth for plans of more than 12
  tasks. The owner rejected it: "some plan or features can have lots of tasks
  but most of them are simple, so it not worth a full process." Task count
  decides no depth; it keeps deciding only mechanics (drafters for 4+ tasks;
  handoffs come from the budget line).
- **Ladder.** Asked which ladder, task count removed. Answer: "Three depths,
  risk-driven" — the preview read:

  ```
              light          standard        full (today)
  Spec        self-review    + 1 Fable round  + critic
                             (critic folded)  + Fable 1-2
  Plan        lint only      1 review round   1-2 rounds
              no hard stop   handoff          handoff
  Execution   unchanged (task/group review tiers)
  Final       gates          gates            everything
              1 Opus review  1 Opus review
              security lens  QA + lenses
              if matched     (cap 2)

  full     : risk trigger (security, data loss,
             migration, concurrency), new subsystem,
             or any task at risk 3
  standard : an outside-facing interface changes,
             or any task at risk 2
  light    : everything else, whatever the count
  ```
- **Older specs and plans.** Not asked. A spec without a `**Depth:**` line, a
  plan whose spec has none, and any plan the script cannot score run at full,
  so every plan written or in flight before this ships keeps today's process.
- **Codex hosts.** Not asked; follows the faster-plans precedent of keeping the
  `codex-v4` protocol whole. A `Host: codex` plan is always full.
- **Owner override.** Asked at the spec review whether the owner may set the
  depth by hand, with a riskier task still raising it at plan time. Answer:
  "Right".
- **Light continuation.** Asked at the spec review which light plans continue
  in the design session rather than hand off to the execution model. Answer:
  "Only plans of 1-3 tasks" — the option read: "Small light plans continue in
  this session; a light plan of 4+ tasks still hands off to a fresh session on
  the execution model. Task count affects only this mechanic, not review
  depth."
- **Light under `autoRun=ask`.** Asked whether a light auto run started from
  the offer may reach execution with no reader of the written spec. Answer:
  "Accept it" — the option read: "Under autoRun=ask you approved every design
  section and acceptance statement by hand; that is the review light keeps."

Finish: merge

## Problem

Since faster-plans (2026-10-26), per-task review scales with each task's
score: low-risk tasks are reviewed in groups of four. Every other stage runs
at one depth for any architectural plan, whatever its risk. On Claude Code
under `autoRun=on` that is: the spec self-review, an architecture critic
(`dforge:judge-opus`, or folded into Fable when no risk or new-subsystem
trigger holds), one or two Fable spec-review rounds, the spec-review stop;
drafters, lint, one or two plan-review rounds and a hard stop with a handoff;
then gates, UI proof, acceptance QA (`dforge:impl-sonnet-high`, a 20-60 minute
timer, `reference/final-review.md` §0.5), the whole-branch review, up to
`lensCap` (default 4) specialist lenses, a Codex round when `codexReview` is
on, and a dedupe judge when two lists come back.

A three-task change that crosses one light trigger — the files could not be
enumerated before exploring, say — pays for the whole chain. So does a long
plan of simple tasks.

## Design

### 1. `scripts/depth-route`

The rule lives in a new `scripts/lib/depth.sh` (spec depth, task depth, and
their combination), sourced by `review-route` and `lens-route` and by a new
`scripts/depth-route`, the command-line form, beside them. All three already
source or will source `lib/plan.sh`, so no script shells out to another.

The "short fixed rubric" of the Evaluator decision is the seven-trigger list
the Process line already answers; there is no second questionnaire.

```
depth-route --spec-triggers LIST
depth-route PLAN_FILE
Output: depth=<light|standard|full> reason=<id>[,<id>...]
        (PLAN_FILE form adds: spec=<light|standard|full|none> tasks=<light|standard|full>)
Exit:   0 routed; 2 usage error, an unknown trigger id, or a missing plan
```

**Trigger ids** are the seven Process Depth triggers of dforge:using-dforge:
`new-subsystem`, `interface`, `unenumerable`, `approach`, `risk`, `intricate`,
`asked`. `LIST` is comma-separated and holds at least one id, since an
architectural path always names a trigger.

**Spec checkpoint** (`--spec-triggers`): `full` when the list holds `risk` or
`new-subsystem`; otherwise `standard` when it holds `interface`; otherwise
`light`. `reason` names the ids that decided it (for light, every id given).

**Plan checkpoint** (`PLAN_FILE`), on the plan with its `amendments.md`
applied (`plan_apply_amendments`, as `review-route` reads it):

- `spec=` is the depth on the `**Depth:**` line of the spec the plan's
  `**Spec:**` line names, the path resolved as `scripts/plan-lint` resolves it
  (`dforge_resolve` against the plan's checkout root, so a spec in the darkmem
  mirror resolves). The depth is the first word after `**Depth:**`; the rest
  of the line is free text. `none` when either line is missing, the spec
  cannot be read, or that word is not `light`, `standard` or `full`.
- `tasks=` comes from `plan_scores`: `full` when any task has risk 3, or has
  no Evaluation line, or an unparsable one; `standard` when the highest risk
  is 2; `light` otherwise. Task count and totals play no part.
- `depth=` is the higher of the two, and `full` when `spec=none` or the plan
  header says `Host: codex`. `reason` names what decided it: `spec`,
  `task-risk:<N>`, `unscored:<N>`, `no-spec-depth` or `codex-host`; when both
  inputs give the same depth, both are named (`reason=spec,task-risk:1`).

The plan checkpoint never lowers the spec's depth. Every consumer below calls
`depth-route PLAN_FILE` at the moment it decides, so a ruling-seat AMEND that
raises a task to risk 3 mid-execution raises the final review with it.

**The spec line.** Below `**Execution strategy:**`, every new spec carries
`**Depth:** <depth> — <reason ids>`. When the owner sets the depth at the spec
review, the line reads `**Depth:** <depth> — owner`, and that is the spec's
depth; the plan checkpoint still raises it. Only the owner replaces an owner
line: the ratchet rerun in §2 leaves it alone. `## Decisions` sits below the
Depth line.

### 2. Classification

`skills/using-dforge/SKILL.md` (Process Depth), `skills/brainstorming/SKILL.md`
(Three Paths, Checklist).

The Process line becomes
`Process: architectural, <inline|subagent>, depth <d> — <triggers>` on the
architectural path, where `<d>` is what `depth-route --spec-triggers` prints
for the triggers named. Spike and bounded lines are unchanged. The spec writes
the `**Depth:**` line from the same output. The ratchet already in
brainstorming applies: a trigger found later reruns the script and can only
raise the depth. Spec self-review item 5 also checks that the `**Depth:**`
line is present and its first word parses.

### 3. Spec phase by depth

`skills/brainstorming/SKILL.md` (Architecture critic, Auto by default, User
Review Gate), `reference/auto-run.md` (§The spec).

- **light:** the self-review round only. No critic and no Fable spec review
  run. The spec review message (or, attended, the User Review Gate) says
  `Critic: skipped (depth light)` in place of the counts. Under `autoRun=on`,
  step 6's `## Review rulings` import has nothing to import.
- **standard:** the critic folded into one Fable round when Fable reviews
  (under `autoRun=on`, or in an auto run), the separate critic round when
  attended. No second Fable round: what round 1 leaves open is asked at the
  spec review as a critic Blocker Fable did not settle, or, in an auto run
  started from the offer, deferred to the register.
- **full:** the separate critic, then Fable for one or two rounds, as today.

The fold keys on the depth, not on the Process line's triggers: an owner line
`**Depth:** full — owner` on a spec with no risk trigger gets the separate
critic. Part A rewrites the trigger-keyed sentences in brainstorming and
auto-run.md §The spec, and the one `tests/process-roles.test.sh` pins.

On a Codex host the spec phase runs as full at every depth, matching the
plan checkpoint's `codex-host` rule.

The spec review message, and attended the User Review Gate line, carry
`Depth: <d> — <reasons>` at every depth. At light the "Approve, keep the
normal stops" option adds "(depth light: the plan is not a stop; execution
follows in this session)". The owner overrides through **Changes needed**,
which writes `**Depth:** <d> — owner`.

The spec-review stop runs at every depth, except in an auto run started from
the offer under `autoRun=ask`, which skips the User Review Gate today. At
light that run reaches execution with no reader of the written spec; the
owner accepted this (Decisions), since under `ask` every design section and
acceptance statement was approved by hand, and §3's text says so. Rulings in an auto run (auto-run.md §Rulings)
are unchanged: they are for undecided items, not a review stage.

### 4. Plan phase by depth

`skills/writing-plans/SKILL.md` (Lint and Review, Execution Handoff),
`scripts/review-route` (`--plan-round`).

- After lint, the session runs `depth-route PLAN_FILE` and says its line.
- `review-route PLAN_FILE --plan-round R` takes its `cap=` from that depth on
  a Claude plan: `light` 0, `standard` 1, `full` 2. At cap 0 it prints
  `review-seat plan-round=1 primary=none fallback=- reason=depth-light cap=0`
  and no round runs; writing-plans then records
  `**Plan review:** <YYYY-MM-DD> — skipped (depth light)`, which satisfies
  `plan-lint`'s header check unchanged. A Claude plan has no cap-critical
  round (`scripts/review-route:268`): a round past the cap exits 2 at every
  depth, so at light `--plan-round 2` exits 2 and at standard a Critical
  finding left after round 1 goes to the owner attended, or to the pending
  list in an auto run, as writing-plans already says. Part B also corrects
  writing-plans' general sentence that gives every plan a cap-critical round,
  which already contradicts the script for Claude plans. A `Host: codex` plan
  keeps its cap rule.
- **No hard stop at light.** Attended (no auto run), a light plan that is
  saved runs dforge:handoff steps 0-4 (reconcile background work, commit the
  plan and the spec, write the handoff notes, `scripts/next-step PLAN_FILE`),
  as auto-run.md §The switch steps 2-3 do, so `latest.md` names this plan.
  Then it runs plain `scripts/context-size`, the task budget every
  `task-brief` line measures (not `--plan`, which measures room to write a
  plan). On `ok` the session invokes the skill the Execution line names in
  this session, saying in one line that the Execution line's model and effort
  are not applied; on `handoff` it ends as today. Only a light plan of 1-3
  tasks continues (Decisions, Light continuation); a light plan of 4 or more
  tasks ends with the handoff as today, on the execution model. Like drafting,
  this is a mechanic: task count still decides no depth. Standard and full keep the
  hard stop. An auto run keeps its switch at every depth. Part B updates
  `skills/handoff/SKILL.md`, whose description and phase-stop list name
  "plan saved outside an auto run" as a hard stop.
- Drafting is unchanged: 1-3 tasks in the session, 4 or more by drafters.

### 5. Execution

Unchanged. Task and group review tiers, the two-round fix loop and the wave
cadence already scale with each task's score.

### 6. Final review by depth

`reference/final-review.md`, `scripts/lens-route` (`--final`).

| Stage | light | standard | full |
|---|---|---|---|
| 0 Gates | runs | runs | runs |
| 0.2 UI proof | runs | runs | runs |
| 0.5 Acceptance QA | skipped | runs | runs |
| 1 Claude review (`dforge:judge-opus`) | runs | runs | runs |
| 1 Lenses | security only, when it applies | at most 2 | up to `lensCap` |
| 2 Codex round | skipped | skipped | as today |
| 3 Dedupe judge | never (one list) | never (one list) | with two lists |

- The session runs `depth-route PLAN_FILE` before step 0 and logs
  `Review depth: <depth> (<reason>)` to the ledger, so recovery after a
  compaction reads the same depth. The name keeps it apart from the
  `Final review:` prefix recovery keys on (`scripts/next-step`).
- QA skipped writes `Acceptance QA: skipped (depth light)`, which step 0.5's
  recovery and both execution skills' recovery notes treat as `complete`. The
  Codex round skipped is said in one line, `codex round skipped (depth <d>)`.
  Both new ledger lines join the ledger grammar blocks of
  `skills/executing-plans/SKILL.md` and
  `skills/subagent-driven-development/SKILL.md`.
- Step 4 writes every `lens-skipped` line to the ledger, whatever its reason,
  and finishing lists them all; today step 4,
  `skills/finishing-a-development-branch/SKILL.md` and auto-run.md
  §Finishing read only `reason=cap`.
- At light no `test` statement is checked before finishing, so the `merge`
  guard on `cannot-test` counts has nothing to read. Finishing's final message
  lists the spec's `test` statements under "not verified (depth light)",
  beside the `demo` statements it already lists.
- `lens-route PLAN_FILE --final BASE HEAD` reads the depth itself. At light it
  prints a `lens` line only for `security` when its Applies clause matches,
  and `lens-skipped <id> reason=depth` for every other lens that applied. At
  standard the cap is the smaller of `lensCap` and 2, and lenses past it print
  `reason=cap` as today. `lens-floor` and `lenses off` are unchanged.
- The fix wave and its scoped re-review are unchanged at every depth.

### 7. Documentation and tests

- `plugins/dforge/README.md`: one paragraph on the three depths and the table
  in §6.
- `tests/depth-route.test.sh` for §1, with fixture specs and plans in
  `tests/fixtures/`.
- `tests/review-route.test.sh` and `tests/lens-route.test.sh` gain the depth
  cases; the skill text suites that pin the edited sections are updated where
  they quote changed text.
- `tests/review-depth.acceptance.test.sh` covers the statements below.

## Parallel decomposition

- **Foundation:** `scripts/lib/depth.sh`, `scripts/depth-route`,
  `tests/depth-route.test.sh`, its fixtures. Every other part consumes the
  lib's functions or the script's output grammar (§1).
- **Part A, spec phase:** `skills/using-dforge/SKILL.md`,
  `skills/brainstorming/SKILL.md`, `reference/auto-run.md` (§The spec, and
  §Finishing's `lens-skipped` sentence), and `tests/auto-default.test.sh`.
- **Part B, plan phase:** `scripts/review-route`, `tests/review-route.test.sh`,
  `skills/writing-plans/SKILL.md`, `skills/handoff/SKILL.md`.
- **Part C, final review:** `scripts/lens-route`, `tests/lens-route.test.sh`,
  `reference/final-review.md`, `skills/executing-plans/SKILL.md`,
  `skills/subagent-driven-development/SKILL.md`,
  `skills/finishing-a-development-branch/SKILL.md`.
- **Closing part:** `plugins/dforge/README.md`,
  `tests/review-depth.acceptance.test.sh`, and the cross-part text suites
  `tests/process-roles.test.sh` and `tests/faster-plans.acceptance.test.sh`.

Existing `cap=2` assertions on fixture plans stay green: their Spec paths
resolve to no Depth line, so they route at full.

Parts A, B and C may run together after the foundation; the closing part runs
last. A text suite that pins files from two parts belongs to the plan's
closing part. A part's fixtures are new files under `tests/fixtures/` that it
alone creates. Tests share no ports or global state; each suite works in its
own `mktemp -d`.

## Acceptance

A1. [test, high] `depth-route --spec-triggers` prints `depth=full` for any list holding `risk` or `new-subsystem`, `depth=standard` for a list holding `interface` and neither of those, and `depth=light` for any other list, with `reason=` naming the deciding ids.
A2. [test, neg, high] `depth-route --spec-triggers` exits 2 on an empty list or an unknown trigger id, and prints no `depth=` line.
A3. [test, high] `depth-route PLAN_FILE` prints the higher of the spec's depth and the task depth, where a task at risk 3 gives `full`, a highest risk of 2 gives `standard` and risk 1 or below gives `light`, reading the plan with its `amendments.md` applied.
A4. [test, neg, high] A plan of 40 tasks, every one at risk 1 or below and some with totals of 8, whose spec says `light`, prints `depth=light`: task count and totals never raise the depth.
A5. [test, neg, high] `depth-route PLAN_FILE` prints `depth=full` when the spec has no `**Depth:**` line, the plan has no `**Spec:**` line, any task is unscored or unparsable, or the plan says `Host: codex`.
A6. [test, neg, high] A spec at `full` with every task at risk 0 still prints `depth=full`: the plan checkpoint never lowers the depth.
A7. [test, high] On a Claude plan `review-route --plan-round 1` prints `cap=0` with `primary=none reason=depth-light` at light, `cap=1` at standard and `cap=2` at full, and any round past the cap exits 2 (`--plan-round 2` at light and standard); a `Host: codex` plan prints the same cap as before this spec.
A8. [test, high] `lens-route --final` at light prints a `lens` line only for `security` and only when its Applies clause matches, and `lens-skipped <id> reason=depth` for every other applicable lens; at standard it prints at most 2 `lens` lines (fewer when `lensCap` is lower); at full its output is unchanged.
A9. [test, high] brainstorming and auto-run.md dispatch no critic and no Fable spec review at light and report `Critic: skipped (depth light)`; at standard they fold the critic into one Fable round with no second round; at full they run the separate critic and one or two Fable rounds; the fold is decided by the depth, not by the triggers.
A10. [test, high] writing-plans records `**Plan review:** <date> — skipped (depth light)` at light, which `plan-lint` accepts with no header warning, then runs handoff steps 0-4 and plain `context-size`, and continues into the execution skill in the same session on `ok` when the plan has 1-3 tasks; a light plan of 4 or more tasks, and every standard and full plan, keeps the hard stop.
A11. [test, high] final-review.md skips acceptance QA at light with the ledger line `Acceptance QA: skipped (depth light)`, which recovery treats as complete, skips the Codex round at light and standard, and logs `Review depth: <depth> (<reason>)` before step 0.
A15. [test, high] Final-review step 4 and finishing list every `lens-skipped` line whatever its reason, and at light finishing lists the spec's `test` statements under "not verified (depth light)".
A16. [test, high] A `**Depth:**` line is read by its first word, so `**Depth:** standard — interface (set by hand)` gives `spec=standard`, and a spec path in the darkmem mirror resolves as `plan-lint` resolves it.
A12. [test, neg, high] At every depth the spec-review stop, the gates, the UI proof, the whole-branch Claude review and the fix wave run.
A13. [test, confirmed] A spec whose line reads `**Depth:** light — owner` is read as `spec=light` whatever its triggers, and a task at risk 2 or 3 still raises the plan's depth.
A14. [test, high] The architectural Process line reads `Process: architectural, <mode>, depth <d> — <triggers>`, and every new spec carries `**Depth:**` below `**Execution strategy:**`.

## Riskiest assumption

That a plan whose riskiest task is at risk 1 or below loses little by skipping
plan review and acceptance QA: that, on such plans, those two stages rarely
find a defect the task reviews and the whole-branch review would miss.

unverified — the plan's first task verifies it: for every completed plan in
this repository's `docs/dforge/plans` and `docs/superpowers/plans` whose spec
would score light under §1 and whose tasks are all at risk 1 or below, read its
plan-review reports and its `Acceptance QA: complete` ledger line where the
workspace still holds them, and count the plans where plan review found a
Critical finding or QA found a `fail`, and record the sample size. When more
than one in four did, the plan stops for a ruling on keeping one plan-review
round or QA at light before any later task builds on §4 or §6. With fewer than
four plans in the sample (on 2026-10-27, `.dforge/sdd/` held two plan-review
reports and no ledger; the darkmem mirror's holdings are unknown), the task
records `inconclusive`, the design proceeds, and a deferred register row
re-checks once five light plans have shipped, comparing their final-review
Critical counts with standard plans'.

## Review rulings

- Fable, spec: round 1 — no cap-critical round at standard; Claude plans have none (`review-route:268`); writing-plans' general sentence corrected.
- Fable, spec: round 1 — the light continuation checks plain `context-size`, not `--plan`.
- Fable, spec: round 1 — the light continuation runs handoff steps 0-4 first; handoff/SKILL.md joins Part B.
- Fable, spec: round 1 — standard runs one Fable round, no second; full keeps one or two.
- Fable, spec: round 1 — the critic fold keys on the depth, not on the triggers.
- Fable, spec: round 1 — Depth line read by its first word; spec path resolved as plan-lint does; owner lines survive the ratchet.
- Fable, spec: round 1 — ledger line named `Review depth:`; `Acceptance QA: skipped` recovers as complete; grammar blocks updated; execution skills join Part C.
- Fable, spec: round 1 — every `lens-skipped` line is listed whatever its reason.
- Fable, spec: round 1 — light finishing lists unverified `test` statements.
- Fable, spec: round 1 — the spec review names the depth at every depth; the light approve option says the plan is not a stop.
- Fable, spec: round 1 — the riskiest-assumption task records its sample size and an `inconclusive` outcome below four plans.
- Fable, spec: round 1 — the rule lives in `scripts/lib/depth.sh`, sourced by three scripts.
- Fable, spec: round 1 — `reason` names both inputs on a tie; round 2 at light exits 2.
- Fable, spec: round 1 — self-review item 5 checks the Depth line; Decisions sit below it.
- Fable, spec: round 1 — cross-part text suites named and assigned.
- Fable, spec: round 1 — the Evaluator's rubric is the seven-trigger list.

## Critic findings

Folded into Fable's round 1. Critic: 0 Blocker, 2 High (1 fixed, 1 answered at
the spec review), 9 Medium, 4 Nit.

- High, §4: a cap-critical round at standard that Claude plans do not have — fixed (Review rulings).
- High, §4: the light continuation measured the wrong budget, skipped the handoff record and left the model switch open — budget and record fixed; the owner bounded the continuation to light plans of 1-3 tasks at the spec review.
- Medium, §3: standard inherited a second Fable round — fixed.
- Medium, §3: "the spec-review stop runs at every depth" was false for a run started from the offer — the owner accepted it at the spec review; §3 says so.
- Medium, §6: new ledger line kinds reached unlisted consumers — fixed.
- Medium, §1: Depth line grammar and path resolution undefined — fixed.
- Medium, §3: fold keyed on triggers while the design keys on depth — fixed.
- Medium, Riskiest assumption: the verifying task had almost nothing to read — fixed.
- Medium, §1: one rule in three scripts — fixed with `lib/depth.sh`.
- Medium, §3: the spec review named the depth only at light — fixed.
- Medium, §6: light merged with no acceptance check and no notice — fixed.
- Nit, §1: `reason` at light and round 2 at light unspecified; ledger prefix clash — fixed.
- Nit, Parallel decomposition: cross-part suites unnamed — fixed.
- Nit, Decisions: the rubric's form unstated — fixed.
- Nit, §6: UI proof at light goes beyond the preview's "gates" — no change; A12 states it.
