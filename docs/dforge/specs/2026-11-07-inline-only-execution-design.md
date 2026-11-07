# Inline-only execution

**Execution strategy:** sequential — inline execution implements its tasks one
after another, and `scripts/plan-lint`, `scripts/lib/plan.sh` and the
execution skills are touched by most parts.
**Depth:** standard — interface

## Goal

Stop dforge from implementing work through subagents. The session that runs a
plan implements every task itself, and writes every plan itself. Spec-driven
development stays as it is: brainstorming, the spec, the plan, the ledger and
the independent review seats. Subagent-driven development is deprecated now
and deleted in a later change.

The owner's premise: Anthropic's recent guidance says subagents do not improve
work quality but do increase token usage. The guidance Claude Code itself
carries matches it for implementation: a delegated agent knows only its brief,
returns only a summary, and rebuilds context the session already holds. Its one
stated exception, a review that is not anchored on the author's reading, is why
the review seats stay.

## Decisions

- **Flow.** Asked fast mode or the full flow; answer: "Full flow
  (Recommended)".
- **Scope.** Asked which subagent use to cut; answer: "Implementation only
  (Recommended)" — no implementer, drafter or scout subagents; independent
  reviews stay: architecture critic, plan review, final whole-branch review,
  milestone, distill and test-simplifier judges.
- **External executors.** Asked about the Codex and Antigravity lanes; answer:
  "Keep them (Recommended)" — they are separate CLIs, not Claude subagents; an
  inline plan still offloads tasks carrying an `**Executor:**` line.
- **Deprecation.** Asked what happens to subagent-driven-development and the
  `impl-*` agents; answer: "Deprecate, keep runnable (Recommended)" —
  writing-plans never emits `Execution: subagent`, the router stops pointing
  at it, existing plans with that line or an explicit owner request still run
  it, deletion comes later.
- **Approach.** Asked how heavy self-implemented tasks are reviewed; answer:
  "Judge review on risk 3 (Recommended)" — the plan format is unchanged
  (scores and `**Implementer:**` lines stay, so the deprecated mode can still
  run); a risk-3 task keeps one per-task judge review that the session fixes
  against; every other task relies on its verification steps and the final
  review.
- **Base.** Asked what the branch starts from; answer: "feat/dforge-fast-mode
  (Recommended)".
- **Seats kept without a question** (inside the Scope answer, recorded so the
  spec review can overturn them): Acceptance QA in the final review stays — it
  is a verification seat that writes tests against the spec without having
  seen the implementation; the auto run's Fable spec review and Fable ruling
  batches stay — they are rulings, not implementation;
  `dforge:requesting-code-review` and the ui-ux judge seats stay.
- **Codex host** (decided while writing): the same rule applies.
  A Codex-host plan is always inline, and its Execution pair covers the
  highest task score, instead of the all-or-nothing rule that sends a plan
  with one heavy task to native subagents.
- **Research subagents.** Asked whether read-only research subagents stay;
  answer: "Leave them (Recommended)" — Explore and general-purpose research
  dispatch are outside the Scope answer.
- **Heavy-task budget margin.** Asked whether to widen the margin now; answer:
  "Measure first (Recommended)" — `CTX_TASK_MARGIN` stays at 140k, and the
  first plan run under this rule records a before/after measurement for its
  first heavy task.

Early CI: none

Finish: pr

## Design

### 1. The Execution line is always inline

- writing-plans writes `**Execution:** inline` on every new plan, on either
  host. The majority rule (subagent when more than half the tasks are heavy)
  and the "parallel waves need subagent mode" path stop choosing the mode.
- The inline pair covers the hardest task the session implements, now
  including heavy tasks: the assignment table's model and effort for the
  highest total among scored tasks without an `**Executor:**` line (6-8 gives
  `opus` / `high`, 5 gives `sonnet` / `high`, and so on), with the effort
  raised to at least `high` when any such task has risk 3. Executor tasks do
  not count, since the session does not implement them.
- `executionMode=subagent`, or an owner instruction, still produces
  `**Execution:** subagent`. `executionMode=auto` now means inline.
- `executionStrategy` defaults to `sequential`. Its `ask` and `parallel`
  values are honoured only when the Execution line will be `subagent`;
  otherwise `ask` asks nothing and `parallel` records
  `**Parallelism:** sequential — inline execution`. writing-plans §Parallel
  waves, `references/auto-run-plan.md` and the schema's `executionStrategy`
  description say so, so a user who set `parallel` learns why nothing changed.
- Brainstorming stops asking the execution-strategy question and records
  `**Execution strategy:** sequential — inline execution`. The Process line
  drops its `<inline|subagent>` slot:
  `Process: <spike|bounded|architectural>[, depth <d>] — <triggers>`.

### 2. Heavy tasks are self-implemented

- `plan_delegated` (scripts/lib/plan.sh) returns executor rows only; a heavy
  task is no longer delegated. `task-brief` stops marking heavy tasks
  `**Dispatch:** delegated`; executor tasks keep the marker.
- **The preflight ruling stays, keyed on heaviness instead of delegation.**
  `task-brief --header` ends with `**Heavy:** Task <a> (total <t>, risk <r>), …`
  for every task `plan_heavy` names, and executing-plans' setup keys its
  `preflight` item on that line, so the whole-plan coupling scan before Task 1
  still runs when a plan has heavy tasks.
- **The session review loop for a risk-3 task.** Its brief carries
  `**Review:** per-task — risk 3` as its second line. The loop:
  1. `scripts/task-step start <N> --inline` records BASE and the suite in
     `task-<N>-step.json`, writes no dispatch file and no agent-named line;
     the session writes `Task <N>: implementer inline (assigned; base <sha7>)`.
  2. The session implements the task, then writes
     `<workspace>/task-<N>-report.md` in the implementer report shape
     (status, commits, verified, discovered, assumptions), since the reviewer
     prompt names that file.
  3. `scripts/task-step review <N>` dispatches the seat `scripts/review-route`
     prints, as delegated-task.md §3 does.
  4. Up to 2 fix rounds, each the session's own fix plus the scoped
     `task-step rereview`. The fix-round line's last slot reads `session`
     where it reads `resumed | fresh | escalated | HANDBACK` today.
  5. A clean verdict writes §5's reviewed complete line with `seat <seat>`.
     After `2/2` with findings open, the findings go to the ruling seat as a
     `breaker` item.
  recovery.md gains the row: `fix round R/2` after an `implementer inline`
  assigned line resumes the session loop at round R+1; `2/2` goes to the
  breaker. delegated-task.md documents this loop as its own section, so its
  "fresh dispatch on the successor rung" and "no controller fixes" rules stay
  scoped to dispatched implementers.
- Every other self-implemented task keeps today's inline rule: no per-task
  review, and its complete line says `unreviewed`.
- **A task that does not converge.** executing-plans' fix cap of 3 no longer
  ends in "Switching to subagent mode". After the `fix round 3/3 (…; still
  failing)` line the task goes to the ruling seat as a `breaker` item, and
  ruling-seat.md's breaker row widens to "a task's findings or verifications
  still open at its cap". In an auto run it goes on the pending list, as an
  exhausted ladder does. switching.md, the handoff skill's "switch from inline
  to subagent mode" hard stop and session-budget.md's matching hard-stop row
  are removed.
- **Executor fallback.** An executor task that is unavailable or refused is
  implemented by the session, not by its `**Implementer:**` agent. The agent
  slot reads `inline`, never a new word, so every reader keyed on
  `implementer inline` keeps working:
  `Task <N>: implementer inline (assigned; base <sha7>; executor <id> unavailable - <reason>)`.
  A handback mid-loop writes `HANDBACK to inline` on its fix-round line, and
  the task stays in the review loop it was already in: the session finishes
  it under the session loop above, never closing it `unreviewed`.
  executor-lane.md's "Never fall back silently" still holds.
- **Codex host.** A Codex-host plan is inline too. plan-lint's all-or-nothing
  ERROR for a heavy task on an inline Codex plan (the R5 Codex block) and the
  matching rule in native-codex.md go; the existing rank check (Execution rank
  at or above the highest score) stays. Since `review-route --task` and
  `task-step` exit 2 on `Host: codex` plans, a Codex plan's risk-3 review runs
  delegated-task.md §The steps by hand with a native judge at Astra high or
  above.

### 3. No drafters, no scouts

- writing-plans writes every task itself at any plan size. The drafter section
  and `references/drafter-prompt.md` go, along with `agents/drafter-sonnet.md`,
  `scripts/draft-pack` and its tests.
- selecting-approaches keeps `inline` and `advisor`; `best-of-3` (three scouts
  and a ranking judge) goes, with `agents/scout-sonnet.md`, the Codex scout
  role in `select-native-tier.sh`, `role_floors.scout` in codex-routing.json
  and native-codex.md's scout clauses. A gate that would have chosen
  `best-of-3` chooses `advisor`. plan-lint still accepts an existing
  `**Approach:** best-of-3 — …` line, since the line records a decision
  already made.

### 4. Subagent-driven development is deprecated, not deleted

- Its `description:` becomes "Deprecated — use only when a plan's Execution
  line names subagent or your human partner asks for subagent mode", and the
  skill opens with a two-line deprecation note naming executing-plans as the
  replacement.
- using-dforge's routing row for executing a plan names
  dforge:executing-plans, with subagent mode only for a plan whose line says
  so. Its Process Depth paragraph drops the heavy-task majority rule.
- plan-lint (Claude host):
  - prints `WARN header subagent execution is deprecated; inline is the
    default` on a subagent line;
  - drops both majority-rule warnings ("inline but N of M tasks are heavy"
    and "subagent but only N of M tasks are heavy");
  - derives the inline floor from the assignment row of the highest
    self-implemented total, model and effort both, raises the effort floor to
    `high` at risk 3, and errors on a model or an effort below the floor.
  Every other check on subagent plans, parallel waves and the `impl-*` agents
  stays, so a subagent plan still lints and runs.
- `scripts/plan-revise` recommends the same pair plan-lint's floor names,
  instead of its hardcoded `sonnet`.
- The `impl-*` agents, ladder.md, parallel-waves.md and delegated-task.md stay.

### 5. Prose and metadata

README, the plugin and marketplace descriptions ("tiered implementers"), the
cockpit's seat nudge (hooks/cockpit/lib.ts, which names the task's
`**Implementer:**` agent "for implementation"), and every skill or reference
sentence that tells the session to delegate a heavy task or to pick subagent
mode are rewritten to match. Historical plans, specs and notes are not edited.
The plugin version takes a minor bump.

## Error handling

- A plan written before this change with `**Execution:** subagent` runs under
  the deprecated skill unchanged; plan-lint warns, never errors.
- An inline plan written before this change whose heavy tasks would have been
  delegated now has them self-implemented. Its Execution pair may be below the
  new floor: plan-lint reports the floor ERROR, and `scripts/plan-revise`
  recommends the new pair.
- A ledger already holding an agent-named `assigned` line for a heavy task, or
  an `escalated inline -> subagent` line, resumes through delegated-task.md or
  the deprecated skill as today: resume reads the ledger, not the rule.

## Testing

The maintained suites (`node scripts/test-all.mjs`) are updated where they
assert delegation of heavy tasks, the majority rule, the drafter path, the
scout path, the Process line's mode slot or the `executionStrategy` default.
New cases cover the acceptance statements below. `node
scripts/validate-repository.mjs`, `claude plugin validate` on the marketplace
and every plugin, and `claude plugin test plugins/dforge` pass, and CI's
`Validate marketplace` run is green, the Windows shards included.

## Acceptance

A1. [test, high] `plan-lint` on a plan whose tasks are all heavy and whose header reads `**Execution:** inline — claude --model opus --effort high` reports no WARN or ERROR on the Execution line.
A2. [test, high] `plan-lint` on a plan whose highest self-implemented total is 6 and whose inline line names `sonnet` / `high` reports the model-floor ERROR.
A3. [test, high] `plan-lint` on a sequential plan with `**Execution:** subagent` prints the deprecation WARN, no majority-rule warning, and no ERROR attributable to the mode.
A4. [test, neg, high] `plan_delegated` on an inline plan with a heavy task and no Executor lines prints nothing, and `task-brief` writes no `**Dispatch:** delegated` line for that task.
A5. [test, high] `task-brief` for a self-implemented risk-3 task writes `**Review:** per-task — risk 3` as its second line; for a total-6, risk-2 task it does not.
A6. [test, high] `plan_delegated` still prints `<N>\texecutor` for a task carrying an `**Executor:**` line, heavy or not.
A7. [test, high] `scripts/dforge-config get executionStrategy` with no settings prints `sequential`, and `scripts/dforge-config workflow` prints nothing.
A8. [test, neg, high] No file under `plugins/dforge/skills` or `plugins/dforge/reference` tells the session to dispatch `dforge:drafter-sonnet` or `dforge:scout-sonnet`, and neither agent file exists.
A9. [test, high] `scripts/plan-revise` on an old inline plan with delegated heavy tasks recommends `execution=inline` with the model and effort that cover its hardest task, and counts only executor tasks as delegated.
A10. [test, high] The subagent-driven-development skill's description starts with `Deprecated`, and using-dforge's routing table names dforge:executing-plans for executing a plan.
A11. [test, neg, high] Outside an allowlist (executing-plans' recovery.md and setup.md, resume-execution, scripts/lib/plan.sh, scripts/next-step and the deprecated skill), no skill or reference names `escalated inline -> subagent` or "Switching to subagent mode"; `ledger_left_inline` still returns the task number for a fixture ledger holding that line.
A12. [test, high] A Codex-host plan with one heavy task and `**Execution:** inline` whose pair ranks at or above its highest score lints with no ERROR.
A13. [test, high] `node scripts/validate-repository.mjs`, `claude plugin validate` and `claude plugin test plugins/dforge` pass, and CI's `Validate marketplace` run for the pushed commit is green.
A14. [test, high] On a fixture plan with a risk-3 task, `task-step start <N> --inline` writes step state and no dispatch file, `task-step review <N>` routes a seat, and a ledger walking `implementer inline (assigned` → `fix round 1/2 (…; session)` → the reviewed complete line is read by `next-step` as complete.
A15. [test, high] `plan-lint` on an inline plan whose hardest self-implemented task is total 3, risk 3, with `--effort medium` reports the effort-floor ERROR.
A16. [test, high] `task-brief --header` on a plan with a total-6 task ends with a `**Heavy:**` line naming it, and executing-plans' setup reference keys its `preflight` item on that line.
A17. [test, neg, high] executing-plans names the `breaker` ruling for a task at `fix round 3/3`, and no skill tells the session to switch to subagent mode at the cap.
A18. [test, high] The brainstorming and using-dforge skills state the Process line as `Process: <spike|bounded|architectural>` with no `<inline|subagent>` slot.
A19. [test, high] executor-lane.md's unavailable-executor ledger line reads `implementer inline (assigned; …; executor <id> unavailable - <reason>)` and its handback line `HANDBACK to inline`.

## Riskiest assumption

That a session can implement heavy tasks (totals 5-8) itself without running
past its handoff budget mid-task. Today the task budget is sized for a session
whose heaviest work goes out to subagents (writing-plans §Task Right-Sizing
counts "an implementer dispatch, a review" per task), and the margin a task
may grow by is `CTX_TASK_MARGIN=140000` (scripts/lib/context.sh), sized for a
controller. Evidence: the brief's budget line is checked before every task
(executing-plans §Session budget), and inline mode already implements totals
up to 4 in-session. Unverified: how much context a total 6-8 task costs
in-session; no fixture can measure it, so the first plan executed under this
rule records a before/after measurement for its first heavy task. If that
overruns the margin, the remedy is a larger margin on a heavy brief, not a
return to delegation.

## Review rulings

- Fable, spec: Risk-3 per-task review — define the session's own loop (`task-step start --inline`, a session-written report, a `session` fix-round slot, the breaker at `2/2`, a recovery row) instead of pointing at delegated-task.md §3-§5.
- Fable, spec: Executor fallback ledger line — keep the agent slot `inline`; a mid-loop handback writes `HANDBACK to inline` and stays in its review loop.
- Fable, spec: Preflight ruling — keep it, keyed on `plan_heavy` through a `**Heavy:**` header line.
- Fable, spec: A task that does not converge at its cap — a `breaker` item, after the `fix round 3/3` line.
- Fable, spec: A7 — assert `dforge-config get executionStrategy` prints `sequential` and `workflow` prints nothing.
- Fable, spec: `executionStrategy` `ask` and `parallel` — honoured only with a subagent Execution line, and the prose and schema text say so.
- Fable, spec: Codex host — A12's question removed; plan-lint's all-or-nothing ERROR and native-codex.md's rule go; risk-3 review by hand with a native judge.
- Fable, spec: plan-lint majority rule — drop both branches.
- Fable, spec: A11 — a named allowlist plus a positive `ledger_left_inline` test.
- Register row 1: an owner request for subagent mode writes `Task <N>: escalated inline -> subagent — owner request` (executing-plans' setup.md, added to A11's allowlist) and never edits the plan's Execution line.

## Critic findings

Critic: 1 Blocker, 3 High (4 fixed, 0 answered), 7 Medium (in Fable's review). Every Blocker and High finding is fixed above.

- [Blocker, fixed] The risk-3 review could not reuse delegated-task.md §3-§5 without an implementer — §2 now defines the session review loop.
- [High, fixed] plan-lint's inline check was effort-only — §4 adds the model floor and the risk-3 effort floor; plan-revise follows.
- [High, fixed] `implementer session` would break readers keyed on `implementer inline` — the slot stays `inline`; handback defined.
- [High, fixed] The Codex host had no risk-3 review path and an unstated lint change — §2 Codex host.
- [Medium] The subagent majority branch would warn "only 0 of M tasks are heavy" — both branches dropped.
- [Medium] The preflight ruling would silently disappear — kept through `**Heavy:**`.
- [Medium] A7 asserted output `workflow` never prints — rephrased.
- [Medium] A11 was not checkable — allowlist form.
- [Medium] `executionStrategy` `ask` had no stated fate — §1.
- [Medium] Acceptance missed the main paths — A14-A19 added.
- [Medium] The exhausted-cap path named no ruling kind — `breaker`.
- [Nit] The pre-task budget check already exists — the remedy is a larger margin.
- [Nit] Scout role also in codex-routing.json and native-codex.md — named in §3.
- [Nit] Cockpit seat nudge — named in §5.
- [Nit] A1 should allow the `NOTE header delegated:` line — reworded.
