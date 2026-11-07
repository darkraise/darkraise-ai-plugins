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
- **Codex host** (decided while writing, rated in A12): the same rule applies.
  A Codex-host plan is always inline, and its Execution pair covers the
  highest task score, instead of the all-or-nothing rule that sends a plan
  with one heavy task to native subagents.

## Design

### 1. The Execution line is always inline

- writing-plans writes `**Execution:** inline` on every new plan, on either
  host. The majority rule (subagent when more than half the tasks are heavy)
  and the "parallel waves need subagent mode" path stop choosing the mode.
- The inline pair covers the hardest task the session implements, now
  including heavy tasks: the assignment table's tier for the highest total
  among tasks without an `**Executor:**` line (6-8 gives `opus` / `high`,
  5 gives `sonnet` / `high`, and so on). A risk-3 task raises the effort to at
  least `high`. Executor tasks do not count, since the session does not
  implement them.
- `executionMode=subagent`, or an owner instruction, still produces
  `**Execution:** subagent`. `executionMode=auto` now means inline.
- `executionStrategy` defaults to `sequential`. `parallel` takes effect only
  together with a subagent Execution line; on an inline plan it records
  `**Parallelism:** sequential — inline execution` as today.
- Brainstorming stops asking the execution-strategy question and records
  `**Execution strategy:** sequential — inline execution`. The Process line
  drops its `<inline|subagent>` slot:
  `Process: <spike|bounded|architectural>[, depth <d>] — <triggers>`.

### 2. Heavy tasks are self-implemented

- `plan_delegated` (scripts/lib/plan.sh) returns executor rows only; a heavy
  task is no longer delegated. `task-brief` stops marking heavy tasks
  `**Dispatch:** delegated`; executor tasks keep the marker.
- A risk-3 task the session implements gets one review round through the
  delegated-task loop's review and fix steps (reference/delegated-task.md §3-§5,
  without §1-§2): the seat `scripts/review-route` prints for it, fix rounds by
  the session up to that loop's cap of 2, then a reviewed complete line. Its
  brief carries the marker line `**Review:** per-task — risk 3` as its second
  line.
  Every other self-implemented task keeps today's inline rule: no per-task
  review, its complete line says `unreviewed`.
- executing-plans' fix cap of 3 no longer ends in "Switching to subagent
  mode". A task that does not converge after 3 rounds (2 for a risk-3 task in the
  review loop) goes to the ruling seat
  as a `BLOCKED` problem (in an auto run, the pending list and the Fable
  batch), exactly as an exhausted delegated task does today. switching.md and
  the handoff skill's "switch from inline to subagent mode" hard stop are
  removed, along with session-budget.md's matching hard-stop row. Recovery
  still reads an existing `escalated inline -> subagent` ledger line, so an
  in-flight ledger resumes.
- An executor task that is unavailable, refused or handed back is implemented
  by the session, not by its `**Implementer:**` agent. Its ledger line names
  the session (`implementer session (…; executor <id> unavailable - <reason>)`)
  so the substitution stays visible, and executor-lane.md's "Never fall back
  silently" still holds.

### 3. No drafters, no scouts

- writing-plans writes every task itself at any plan size. The drafter section
  and `references/drafter-prompt.md` go, along with `agents/drafter-sonnet.md`,
  `scripts/draft-pack` and its tests.
- selecting-approaches keeps `inline` and `advisor`; `best-of-3` (three scouts
  and a ranking judge) goes, with `agents/scout-sonnet.md` and the Codex scout
  role in `select-native-tier.sh`. A gate that would have chosen `best-of-3`
  chooses `advisor`. plan-lint still accepts an existing `**Approach:**
  best-of-3 — …` line, since the line records a decision already made.

### 4. Subagent-driven development is deprecated, not deleted

- Its `description:` becomes "Deprecated — use only when a plan's Execution
  line names subagent or your human partner asks for subagent mode", and the
  skill opens with a two-line deprecation note naming executing-plans as the
  replacement.
- using-dforge's routing row for executing a plan names
  dforge:executing-plans, with subagent mode only for a plan whose line says
  so. Its Process Depth paragraph drops the heavy-task majority rule.
- plan-lint prints `WARN header subagent execution is deprecated; inline is
  the default` on a subagent line and drops the "inline but N of M tasks are
  heavy" warning. Every other check on subagent plans, parallel waves and the
  `impl-*` agents stays, so a subagent plan still lints and runs.
- The `impl-*` agents, ladder.md, parallel-waves.md and delegated-task.md stay.

### 5. Prose and metadata

README, the plugin and marketplace descriptions ("tiered implementers"), and
every skill or reference sentence that tells the session to delegate a heavy
task or to pick subagent mode are rewritten to match. Historical plans, specs
and notes are not edited. The plugin version takes a minor bump.

## Error handling

- A plan written before this change with `**Execution:** subagent` runs under
  the deprecated skill unchanged; plan-lint warns, never errors.
- An inline plan written before this change whose heavy tasks would have been
  delegated now has them self-implemented. Its Execution pair may be below the
  new floor: plan-lint reports that as the ERROR it already raises for an
  inline pair below its hardest task, and `scripts/plan-revise` recommends the
  new pair.
- A ledger already holding an agent-named `assigned` line for a heavy task
  resumes through delegated-task.md as today (resume reads the ledger, not the
  rule).

## Testing

The maintained suites (`node scripts/test-all.mjs`) are updated where they
assert delegation of heavy tasks, the majority rule, the drafter path, the
scout path, the Process line's mode slot or the `executionStrategy` default.
New cases cover A1-A11. `node scripts/validate-repository.mjs`,
`claude plugin validate` on the marketplace and every plugin, and
`claude plugin test plugins/dforge` pass, and CI's `Validate marketplace` run
is green, the Windows shards included.

## Acceptance

A1. [test, high] `plan-lint` on a plan whose tasks are all heavy and whose header reads `**Execution:** inline — claude --model opus --effort high` reports no Execution-mode warning.
A2. [test, high] `plan-lint` on a plan whose highest self-implemented total is 6 and whose inline line names `sonnet` / `high` reports the ERROR for a pair below the hardest task.
A3. [test, high] `plan-lint` on a plan with `**Execution:** subagent` prints the deprecation WARN and no ERROR attributable to the mode.
A4. [test, neg, high] `plan_delegated` on an inline plan with a heavy task and no Executor lines prints nothing, and `task-brief` writes no `**Dispatch:** delegated` line for that task.
A5. [test, high] `task-brief` for a self-implemented risk-3 task writes the per-task review marker; for a total-6, risk-2 task it does not.
A6. [test, high] `plan_delegated` still prints `<N>\texecutor` for a task carrying an `**Executor:**` line, heavy or not.
A7. [test, high] `scripts/dforge-config workflow` with no settings reports `executionStrategy` at `sequential`.
A8. [test, neg, high] No file under `plugins/dforge/skills` or `plugins/dforge/reference` tells the session to dispatch `dforge:drafter-sonnet` or `dforge:scout-sonnet`, and neither agent file exists.
A9. [test, high] `scripts/plan-revise` on an old inline plan with delegated heavy tasks recommends `execution=inline` with the pair that covers its hardest task and `delegated=0/<n>` (executor tasks counted when present).
A10. [test, high] The subagent-driven-development skill's description starts with `Deprecated`, and using-dforge's routing table names dforge:executing-plans for executing a plan.
A11. [test, neg, high] No skill or reference outside subagent-driven-development and the deprecated references names "Switching to subagent mode" or an `escalated inline -> subagent` line as something to write; recovery still parses an existing one.
A12. [test, medium] A Codex-host plan with one heavy task and `**Execution:** inline` with a pair at or above its highest score lints with no ERROR. Q: Should the Codex host also drop native implementer subagents, or keep its all-or-nothing rule for now?
A13. [test, high] `node scripts/validate-repository.mjs`, `claude plugin validate` and `claude plugin test plugins/dforge` pass, and CI's `Validate marketplace` run for the pushed commit is green.

## Riskiest assumption

That a session can implement heavy tasks (totals 5-8) itself without running
past its handoff budget mid-task. Today the task budget is sized for a session
whose heaviest work goes out to subagents (writing-plans §Task Right-Sizing
counts "an implementer dispatch, a review" per task), and the budget line is
read between tasks, not during one (reference/session-budget.md). Evidence:
inline mode already implements totals up to 4 in-session, and the budget line
after each task hands off before the next one starts. Unverified: how much
context a total 6-8 task costs in-session; no fixture can measure it, so the
first plan executed under this rule settles it. If one heavy task overruns the
room left after a budget check, the remedy is a pre-task budget check for heavy
tasks, not a return to delegation.
