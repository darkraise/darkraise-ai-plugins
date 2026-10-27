# Speed and cost: a mechanical lane now, a measured lane behind a replay eval

**Execution strategy:** parallel — after a foundation part that splits the
oversized skills, the task loop, the implementer agent files, the stop gate,
the replay eval and the docs are five parts with disjoint files (see Parallel
decomposition). The measured lane runs after the replay eval, one item at a
time.

**Depth:** standard — interface

**Register:** docs/dforge/registers/2026-10-27-speed-and-cost.md
**Research:** docs/dforge/notes/2026-10-27-speed-and-cost-research.md

## Decisions

- **Scope.** Asked to brainstorm "entire the list": the 18 register rows, all
  covered by this spec.
- **Gating.** Asked how the items are gated on measurement. Answer: "Two lanes"
  — the option read: "One spec: ship the mechanical items now; build the
  isolated replay eval in the same plan; the behaviour-changing items ship only
  after the eval shows no quality loss against today's baseline." Offered and
  not chosen: "Eval first, gate all"; "Ship all, measure later".
- **Full suite.** Asked who runs a task's full suite. Answer: "Controller,
  beside review" — the option read: "Implementer runs targeted tests only and
  returns; the controller starts suite-run in the background at once and
  dispatches the judge in parallel. A red suite becomes a finding for the fix
  round." Offered and not chosen: "Once per wave or group"; "Keep it in the
  implementer".
- **Stop gate.** Asked how strict the implementer SubagentStop gate is. Answer:
  "Report structure only" — the option read: "Block when the report file is
  missing, lacks a required section, or its verified line names no command and
  result. Runs no tests, so it is fast and deterministic; lets the stop through
  after 2 blocks and logs it." Offered and not chosen: "Structure + re-run
  check"; "No gate".
- **Eval size.** Asked how large the replay eval is. Answer: "20 tasks x 3
  runs" (about $240 per two-arm comparison at the estimated $2 per task run).
- **Approach.** Asked how measured items are built and compared. Answer:
  "Branch per item" — the option read: "Mechanical lane and the replay eval
  merge normally. Each measured item is built on its own branch; the eval loads
  the baseline and the branch as two --plugin-dir arms; only items with no
  quality loss and a cost or time gain merge. No runtime flags left behind."
  Offered and not chosen: "Settings flags, default off"; the do-less option
  "Mechanical lane only".
- **Execution strategy.** The `executionStrategy` setting is `parallel`; no
  question asked.
- **Ruling (session): `disable-model-invocation` is dropped from row 16.** The
  flag stops Claude from invoking a skill, and dforge skills invoke each other
  through the Skill tool, so no dforge skill qualifies. If wrong: a few hundred
  listing tokens per turn stay unsaved.
- **Ruling (session): row 2 is folded into row 1.** Once the implementer no
  longer runs the full suite, it has no long wait left to background.

## Problem

Measured over 56 dforge sessions (2026-09-27 to 2026-10-27, list API prices):

- dforge judges cost $782 against $822 for implementers; on judge-opus, 202
  ruling dispatches ($188) cost more than 289 task reviews ($168).
  `cannot-verify` is the largest ruling kind (100), still 43 on 2026-10-27
  after token-efficiency row 4 moved them to judge-sonnet-high; most are
  mechanical facts (a test failing at the base commit, a symbol existing).
- 98 implementer runs lost their 5-minute cache mid-run; 58 of those followed a
  wait on the full suite the implementer runs once at the end through
  suite-run. A 1-hour subagent TTL would cost more than it saves.
- Six SKILL.md files exceed 20 KB (subagent-driven-development 49,422 bytes).
  After compaction Claude Code re-attaches only the first 5,000 tokens of each
  invoked skill; upstream superpowers lost its fix-round cap that way.
- No implementer tier carries an anti-hardcoding, report-incorrect-tests or
  tests-are-immutable clause; the Opus tiers lack the scope-limit clause the
  Sonnet tiers have.
- The behaviour-changing ideas (lean plans, judge discipline, merged tasks,
  effort sweep) have outside evidence but none on dforge's own tasks, and the
  tier eval replays one seat at a time, so nothing can compare two versions of
  the whole task loop today.

## Design

### 1. Foundation: skills under 20 KB (row 14)

Every SKILL.md under `plugins/dforge/skills/` stays at or under 20,000 bytes.
A skill over the cap moves material its session reads only at one step into
`references/<topic>.md`, linked from the step that needs it with a "read
before you …" line, so a session that lost the tail after compaction still
reaches it. What stays in SKILL.md: the After compaction block, the entry
rules, the step list and anything every step needs. A new test,
`plugins/dforge/tests/skill-size.test.sh`, fails naming each file over the cap
and its size. Existing pin tests that grep moved text are repointed at the
reference file; none is deleted.

### 2. Task loop: the suite beside the review, and mechanical facts (rows 1, 2, 5)

- **Implementer.** `implementer-prompt.md` drops the final full-suite run: the
  implementer runs the focused tests that cover its change before each commit,
  reports them, and returns.
- **Controller.** On a DONE or DONE_WITH_CONCERNS report,
  `reference/delegated-task.md` has the controller start
  `scripts/suite-run -- <suite command>` as a background command at the task's
  head and dispatch the task review in the same turn. The controller runs
  `task-step verdict` only once both the review report and the suite's
  completion notification are in. `verdict` reads suite-run's record for that
  head: a pass, or failures that all also fail at the base commit (the
  baseline check below), lets the task complete; any other failure becomes an
  Important finding (`suite: <test> fails at <head7>`) in the fix round. A fix round's
  head gets its own suite run beside its re-review. A group review runs one
  suite at the group's last head. Inline mode and Codex hosts are unchanged.
- **Baseline and existence facts.** The task-reviewer prompt gives
  cannot-verify items a structured form when they ask a mechanical question:
  `cannot-verify: exists <path|symbol> at <base|head> — <why it matters>` or
  `cannot-verify: baseline <test> — <why>`. `task-step verdict` settles them
  itself: `exists` by `git grep -n -F` (or `git cat-file -e` for a path) at the
  named commit, `baseline` by running only that test at the base commit in a
  temporary worktree through suite-run. A settled item is logged
  `Task <N>: Ruling: cannot-verify — settled by task-step check <exists|baseline> — none`
  and reaches no seat; a free-text item still goes to the ruling seat.

### 3. Implementer agent clauses (row 7)

Every `agents/impl-*.md` gains three clauses after its scope paragraph: write a
general solution, never one that only passes specific test inputs; when a test
looks wrong, report it instead of working around it; never edit or delete an
existing test unless the brief names it. The Opus tiers gain the scope-limit
clause the Sonnet tiers already carry.

### 4. Implementer stop gate (row 13)

A plugin `SubagentStop` hook in `hooks/hooks.json`, matcher `dforge:impl-.*`,
runs `scripts/impl-stop-gate`. It reads the hook input (`agent_type`,
`agent_id`, `last_assistant_message`) and blocks with exit 2 and a one-line
reason when the last message reports `DONE` or `DONE_WITH_CONCERNS` and:

- it names no report file, or the file does not exist;
- the file lacks `## Discovered issues (not fixed)` or `## Assumptions made`;
- the file names no test command with a result.

It passes every other agent type, BLOCKED and NEEDS_CONTEXT stops, and the
third stop of one agent id after two blocks (counted in a file under the
plugin's state directory, keyed by agent id), logging that pass-through. It
runs no tests and makes no network call. The hooks docs state that
`SubagentStop` input carries `agent_type` and that exit 2 keeps the subagent
running with the reason as its next instruction
(https://code.claude.com/docs/en/hooks); Claude Code before 2.1.311 can fire
it twice, so the gate is idempotent per stop.

### 5. Replay eval (rows 11, 12)

A new `pipeline` stage in `evals/tiers` replays a finished task through the
whole loop under a given plugin directory: an isolated clone at the task's base
commit with its own HOME and XDG directories, `claude -p --plugin-dir <arm>`
driving one task's implementer, suite, task review and up to two fix rounds,
then the existing hidden-test grader. It records per run: pass, `costUsd`,
wall time, dispatch count and fix rounds. `arms.json` gains
`"pipeline": { "baseline": "<ref>", "candidate": "<ref>" }`, each ref built
into its own plugin directory with `git worktree add`. The manifest takes 20
cases from finished plans, preferring tasks that needed a fix round; each arm
runs 3 times. The report prints pass^3 (cases passing all three runs), total
cost and median wall time per arm. A baseline arm's results are reused by every
comparison against the same baseline ref. Nothing runs in a real project
checkout or reads the owner's settings.

### 6. Measured lane (rows 3, 4, 6, 8, 9, 10, 12, 15, 17)

Each item is built on its own branch from the merged mechanical lane and run as
the candidate arm. It merges when its pass^3 count is at least the baseline's
and its total cost or median wall time is at least 10% lower; otherwise its row
closes `n/a` with the numbers. Order, by expected value:

1. Lean plans (row 15): briefs carry decisions, signatures and test assertions,
   not full code. Needs a pipeline variant that re-drafts each case's brief
   from its spec section.
2. Judge discipline (rows 4, 6): findings cite a failing command or a quoted
   brief line, unreproduced findings start no fix round, "skip style",
   diff-first narrow search.
3. Chained tasks (row 3): consecutive tasks that consume each other's output
   and share files run as one dispatch with a commit per task.
4. Effort sweep (row 9): one rung lower per score band.
5. Brief as contract (row 8): machine-readable done-list and acceptance
   commands; the judge checks the stated objective.
6. Review pre-check (row 17): a cheap pre-check on top of the review-depth
   routing already shipped.
7. Pilots (row 12): no judge for score 0-2 tasks; escalation on early
   trajectory signals.
8. Stagger (row 10): measured from transcripts instead (first-request cache
   reads of a second same-type dispatch), no eval arm.

### 7. Docs and audit (rows 16, 18)

The plugin README gains a short "Unattended runs" note: auto mode, so wave
implementers never stall on a permission prompt, and `worktree.baseRef: "head"`,
because wave worktrees otherwise branch from origin while local main may be
ahead. A note records the output of `/doctor prompt-audit` and `/skill-doctor`
for dforge; each change it proposes becomes a register row or a measured-lane
candidate, never a direct edit.

## Parallel decomposition

| Part | Owns | Consumes | Runs |
|---|---|---|---|
| F foundation | every `plugins/dforge/skills/*/SKILL.md` over 20 KB and its new `references/*.md`; `tests/skill-size.test.sh`; pin tests repointed by the split | — | first |
| A task loop | `skills/subagent-driven-development/**` after F; `reference/delegated-task.md`; `scripts/task-step`; `scripts/suite-run`; their tests | F's layout | with C, D, E, G |
| C agent clauses | `agents/impl-*.md`; their pin test | — | with A, D, E, G |
| D stop gate | `hooks/hooks.json`; `scripts/impl-stop-gate`; `tests/impl-stop-gate.test.sh` | the report format in `implementer-prompt.md` (read only) | with A, C, E, G |
| E replay eval | `evals/**` | the plugin as a directory (read only) | with A, C, D, G |
| G docs and audit | `plugins/dforge/README.md`; `docs/dforge/notes/2026-10-27-prompt-audit.md`; plugin version files and changelog | — | with A, C, D, E |
| M measured lane | one branch per item | A-G merged | after E, one item at a time |

Tests isolate by fixtures under each test's own temp directory; no part's test
shares a port, database or fixed path with another's.

## Acceptance

A1. [test, high] Every `plugins/dforge/skills/*/SKILL.md` is at most 20,000 bytes, and `tests/skill-size.test.sh` fails naming each file over the cap with its size.
A2. [test, neg, high] No rule is lost by the split: every new reference file is linked from its SKILL.md at the step that uses it, and the pin tests that existed before the split all still run and pass.
A3. [test, high] The subagent-mode implementer prompt no longer tells the implementer to run the full suite; it tells it to run and report the focused tests that cover its change.
A4. [test, high] After an implementer's DONE report, the controller starts suite-run in the background at the task's head and dispatches the task review in the same turn.
A5. [test, neg, high] A task never gets a `complete` line while suite-run's record for its head shows a failure that is not marked baseline; that failure becomes a fix-round finding.
A6. [test, high] A structured `cannot-verify: exists …` or `cannot-verify: baseline …` item is settled by `task-step verdict` and logged as settled by task-step, with no seat dispatched.
A7. [test, neg, high] A free-text cannot-verify item still goes to the ruling seat.
A8. [test, high] Every `agents/impl-*.md` carries the anti-hardcoding, report-incorrect-tests and tests-are-immutable clauses, and every `agents/impl-opus-*.md` carries the scope-limit clause.
A9. [test, high] The stop gate exits 2 with a reason naming what is missing when a `dforge:impl-*` agent stops with DONE or DONE_WITH_CONCERNS and its report file is missing, lacks a required section, or names no test command with a result.
A10. [test, neg, high] The gate exits 0 for any other agent type, for BLOCKED and NEEDS_CONTEXT stops, and for the third stop of one agent id after two blocks, which it logs.
A11. [test, neg, high] The gate runs no test command and finishes in under 2 seconds on a 1,000-line report.
A12. [test, high] The pipeline stage replays one case end to end under a given plugin directory and records pass, costUsd, wall time, dispatch count and fix rounds per run.
A13. [test, neg, high] No pipeline run uses a working directory, plugin directory or HOME outside the eval's own temporary root.
A14. [test, medium] A measured item merges only when its pass^3 count over the same 20 cases x 3 runs is at least the baseline's and its total cost or median wall time is at least 10% lower. Q: is "pass^3 at least baseline, and 10% cheaper or faster" the merge rule you want?
A15. [demo, medium] The measured lane runs comparisons in the Design §6 order until eval spend reaches $1,200 (a reused baseline plus about $120 per candidate arm covers all eight). Q: is $1,200 the right spend cap, or should the plan stop after a smaller first batch?
A16. [test, high] The plugin README documents auto mode for unattended waves and `worktree.baseRef: "head"` for wave worktrees, each with its reason.
A17. [demo, medium] The prompt-audit note records `/doctor prompt-audit` and `/skill-doctor` output for dforge, and each proposed change appears as a register row. Q: if `/doctor prompt-audit` cannot run headless, is one owner-run session acceptable?
A18. [test, neg, high] Codex hosts are unchanged: `reference/native-codex.md` and the executing-plans inline suite rule are not edited.

## Riskiest assumption

The replay eval can drive one task's whole loop headless: `claude -p
--plugin-dir <arm>` in an isolated clone runs the controller's task loop
(implementer, background suite, review, fix rounds) to completion without a
human, and the hidden-test grader scores it. Evidence so far: the tier eval
already runs single seats with `claude -p` in isolated snapshots
(`evals/tiers/README.md`), and the controller-model pilot drove whole sessions
(`evals/controller/`); neither ran the full loop under a second plugin
directory. Unverified — part E's first task verifies it with one smoke case on
both arms before the rest of E is built; the mechanical lane does not depend
on it.
