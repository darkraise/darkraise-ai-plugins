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
  tests-are-immutable clause; the Opus, Fable and Haiku tiers lack the scope-limit clause the
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
  reports them, and returns. The Report Format gains `## Verified`, one bullet
  per command run: `` - `<command>` — pass | fail: <n> passed, <m> failed ``;
  the short reply's last line is `Report: <absolute path>`. The Run Control
  paragraph names `[PLUGIN_ROOT]/scripts/context-size`, so `[PLUGIN_ROOT]`
  keeps a use in the prompt.
- **Suite command** (recommended; the owner confirms it at the spec review).
  `task-step start` takes `--suite '<command>'` and records it in
  `task-<N>-step.json`. The controller takes the command from the plan
  header's `**Integration check:**`, else from `<docs>/gates.md`'s test
  command, else decides it once from the project's manifest. The resolution
  rule is written in `reference/delegated-task.md` §1 Dispatch, so subagent
  mode and inline mode's delegated tasks read the same text; the
  `Ruling: suite command — <command> — none` line is logged the first time
  `task-step start --suite` runs on a plan, whichever caller runs it.
  executing-plans is not edited.
- **Controller.** On a DONE or DONE_WITH_CONCERNS report,
  `reference/delegated-task.md` has the controller start
  `bash <plugin-root>/scripts/suite-run -- bash -c '<suite command>'` as a
  background command from the checkout root (or from `--cwd` for a wave task)
  at the task's head, and dispatch the task review in the same turn. The
  controller runs `task-step verdict` only once both the review report and the
  suite's completion notification are in. `verdict` reads `suites.tsv` in the
  state directory of `--cwd` when given, else of the checkout, and matches the
  row by the `%q` form suite-run records for that argv, so a run started from a
  subdirectory never matches. It accepts a `clean` or `dirty` row at the
  review head, printing `suite: pass (<clean|dirty>)`: the controller's own
  uncommitted ledger lines make the tree dirty, and the tracked-file check
  already guards the reviewed state.
  - a pass, or failures that are all baseline (below), lets the task complete;
  - any other failure becomes an Important finding
    (`suite: <test> fails at <head7>`) in the fix file, and `verdict` prints
    `fix:` naming it;
  - no row prints `suite: not run (<command>)` and exits 7; the controller
    re-runs the suite before `verdict` again. A suite still in flight at a
    handoff is listed by `scripts/in-flight` and re-run by the next session.
- **Baseline failures.** For a red suite, `verdict` needs the base commit's
  failing lines. It reuses, in order, a `suites.tsv` row at the base sha in
  the checkout (a previous task's head), else
  `<workspace>/task-<N>-base-failures.txt`, else runs the recorded suite
  command once at the base commit in a temporary worktree through
  `suite-run --timeout 600`, after the header's `**Worktree setup:**` when it
  has one, and writes that file from the digest's failing lines before
  removing the worktree (whose own `.dforge` record goes with it). A failing
  line is baseline when the same line appears in the base failing lines, as
  `reference/parallel-waves.md` §1 already does with
  `base-proof-failures.txt`.
- **Fix rounds and groups.** A fix round's head gets its own suite run beside
  its re-review. `task-step rereview --covered` runs only after the fix head's
  suite notification; it skips the re-review only when `suites.tsv` holds a
  pass row (or all-baseline failures) for the recorded command at that head,
  and otherwise prints `re-review: not skipped (suite <red|not run>)` and
  writes the prompt. In sequential mode a group's suite runs once at the last held
  member's head; a wave's grouped tasks get no per-group suite, since the
  wave's merged check is their suite.
- **Where the loop applies.** Inline mode's own tasks (executing-plans steps
  2-7, including its full-suite-before-commit rule) are unchanged; a task
  inline mode delegates follows this loop. `reference/delegated-task.md`'s
  `## The steps by hand` §2 (Codex hosts and any run without `task-step`)
  gains: "On a DONE report, run
  `bash <plugin-root>/scripts/suite-run -- <suite command>` yourself in the
  background at the task's head and treat a non-baseline failure as §3's
  Important finding." `reference/final-review.md`'s fix-wave subagent (which
  still runs the suite so finishing reuses it) and the SKILL.md example line
  that shows a suite-run call are deliberately unchanged.
- **Baseline and existence facts.** The task-reviewer prompt gives
  cannot-verify items a structured form when they ask a mechanical question:
  `cannot-verify: exists <path|symbol> at <base|head> — <why it matters>` or
  `cannot-verify: baseline <command> — <why>`. `task-step verdict` settles them
  itself: `exists` by `git cat-file -e` for a path or `git grep -nwF` for a
  symbol at the named commit; `baseline` by running the named command verbatim
  at the base commit in a temporary worktree through
  `suite-run --timeout 600`, after `**Worktree setup:**` when the header has
  one. A settled item is logged
  `Task <N>: Ruling: cannot-verify — settled by task-step check <exists|baseline> — <evidence>`,
  where the evidence is the `git grep` hit `<file>:<line>`, `path present` or
  `path absent`, or the base run's log path, and reaches no seat; a free-text
  item still goes to the ruling seat.

### 3. Implementer agent clauses (row 7)

Every `agents/impl-*.md` gains three clauses after its scope paragraph: write a
general solution, never one that only passes specific test inputs; when a test
looks wrong, report it instead of working around it; never edit or delete an
existing test unless the brief names it. Every non-Sonnet tier
(`impl-opus-*`, `impl-fable-*`, `impl-haiku`) gains the scope-limit clause
the Sonnet tiers already carry ("Change only what the brief asks for");
recommended, the owner confirms the tier set at the spec review.

### 4. Implementer stop gate (row 13)

A plugin `SubagentStop` hook in `hooks/hooks.json`, matcher
`(dforge:)?impl-.*`, runs `scripts/impl-stop-gate`. Whether `agent_type`
carries the plugin prefix is unverified, so the gate also checks that
`agent_type` matches `(^|:)impl-` itself, and part D's first task logs one real
`SubagentStop` input and records the observed value in its test.

The gate acts only when `last_assistant_message` carries `**Status:** DONE` or
`**Status:** DONE_WITH_CONCERNS`; every other stop passes (other agent types,
BLOCKED, NEEDS_CONTEXT). Only `implementer-prompt.md` uses that status
contract; acceptance-qa and the final-review fix wave dispatch `impl-*` agents
without it, and part D's first task records a real reply from one of them to
confirm. When it acts, it reads only the `Report:` line and the report file's
`## Verified`, `## Discovered issues (not fixed)` and `## Assumptions made`
headings, and blocks with exit 2 and a one-line reason naming what is missing
when:

- the message has no `Report: <path>` line;
- the file does not exist;
- it lacks `## Discovered issues (not fixed)` or `## Assumptions made`;
- `## Verified` is missing or holds no bullet in §2's grammar.

`<state>` is the output of `bash "$CLAUDE_PLUGIN_ROOT/scripts/dforge-path" state`
run from the hook input's `cwd`. The counter file
`<state>/impl-stop-gate/<agent_id>` holds the block count and the sha256 of
the last blocked `last_assistant_message`; a stop whose hash equals the stored
one is the same stop fired twice and does not raise the count. The third
distinct stop of one agent id after two blocks passes and appends one line to
`<state>/impl-stop-gate.log`:
`<epoch> <agent_id> <agent_type> pass-through after 2 blocks — <last reason>`.
The gate runs no tests and makes no network call. The hooks docs state that
`SubagentStop` input carries `agent_type` and that exit 2 keeps the subagent
running with the reason as its next instruction
(https://code.claude.com/docs/en/hooks). The research note records that
versions before 2.1.311 fire it twice (observed during its 2.1.311
verification); the hooks docs do not state it.

### 5. Replay eval (row 11)

A new `pipeline` stage in `evals/tiers` replays a finished task through the
whole loop under a given plugin directory: an isolated clone at the task's base
commit with its own HOME and XDG directories, `claude -p --plugin-dir <arm>`
driving one task's implementer, suite, task review and up to two fix rounds,
then the existing hidden-test grader. Each arm's plugin directory is
materialised with `lib/snapshot.mjs`'s `snapshot(ref, <eval root>/arms/<ref7>)`,
which holds the whole repository tree, so the arm is loaded with
`--plugin-dir <eval root>/arms/<ref7>/plugins/dforge`; no git worktree is
created. `arms.json` gains
`"pipeline": { "baseline": "<ref>", "candidate": "<ref>" }`.

Pipeline runs go to `results/pipeline.tsv` with columns
`rep, case, arm, run, outcome, costUsd, seconds, dispatches, fixRounds, detail`.
`results.tsv` and `run-grid.mjs`'s existing stages are untouched, and the
start-commit refusal in `run-grid.mjs` does not apply to the pipeline stage,
whose arms are refs. The manifest takes 20 cases from finished plans,
preferring tasks that needed a fix round; each arm runs 3 times. The report
prints pass^3 (cases passing all three runs), total cost and median wall time
per arm. Nothing runs in a real project checkout or reads the owner's
settings.

### 6. Measured lane (rows 3, 4, 6, 8, 9, 10, 12, 15, 17)

Every candidate branches from, and is compared against, the mechanical-lane
merge commit `<M>` (recommended; the owner confirms it at the spec review).
The baseline arm runs once at `<M>`; a winning item is rebased onto main.
After the lane, one confirmation comparison of main against `<M>` (one arm,
about $120) checks the merged set together. An item merges when it meets the
merge rule (A14); otherwise its row closes `n/a` with the numbers. Order, by
expected value:

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
   reads of a second same-type dispatch), no eval arm. Row 10's other half,
   workers with disjoint files and shared decisions, already shipped as
   parallel waves (`reference/parallel-waves.md`).

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
| A task loop | `skills/subagent-driven-development/**` after F; `reference/delegated-task.md`; `scripts/task-step`; `scripts/suite-run`; their tests, including `task-step-text.test.sh`, `task-step.test.sh`, `task-loop-steps.acceptance.test.sh` and a pin on the `## Verified` grammar and `Report:` line in `implementer-prompt.md` | F's layout | with C, D, E, G |
| C agent clauses | `agents/impl-*.md`; new `tests/impl-clauses.test.sh` | — | with A, D, E, G |
| D stop gate | `hooks/hooks.json`; `scripts/impl-stop-gate`; `tests/impl-stop-gate.test.sh` | §2's report grammar, copied from this spec into its fixtures | with A, C, E, G |
| E replay eval | `evals/**` | the plugin as a directory (read only) | with A, C, D, G |
| G docs and audit | `plugins/dforge/README.md`; `docs/dforge/notes/2026-10-27-prompt-audit.md`; plugin version files and changelog | — | with A, C, D, E |
| M measured lane | one branch per item | A-G merged | after E, one item at a time |

Part A keeps `skills/subagent-driven-development/SKILL.md` at or under the
20,000-byte cap after its edits. In part A, the `task-step-text.test.sh` pin on
the implementer prompt's suite-run line flips to `lacks`, and the two checks
that the dispatch file carries the expanded `scripts/suite-run -- ` are
repointed at the expanded `scripts/context-size`. D reads the report grammar
from this spec rather than from `implementer-prompt.md`, so it does not wait on
A; the pin that keeps the two in step lives in A's tests.

Tests isolate by fixtures under each test's own temp directory; no part's test
shares a port, database or fixed path with another's.

## Acceptance

A1. [test, high] Every `plugins/dforge/skills/*/SKILL.md` is at most 20,000 bytes, and `tests/skill-size.test.sh` fails naming each file over the cap with its size.
A2. [test, neg, high] No rule is lost by the split: every new reference file is linked from its SKILL.md at the step that uses it, and the pin tests that existed before the split all still run and pass.
A3. [test, high] The subagent-mode implementer prompt no longer tells the implementer to run the full suite; it tells it to run the focused tests that cover its change and report each under `## Verified` in §2's grammar, ending its reply with a `Report:` line.
A4. [test, high] After an implementer's DONE report, the controller starts suite-run in the background at the task's head and dispatches the task review in the same turn.
A5. [test, neg, high] `task-step verdict` at a head whose recorded suite row has a non-baseline failure writes `suite: <test> fails at <head7>` as an Important finding into the fix file and prints `fix:` naming it; with no row for that head and command it prints `suite: not run (<command>)` and exits 7. `reference/delegated-task.md` says a task is marked complete only after `verdict` passes.
A6. [test, high] A structured `cannot-verify: exists …` or `cannot-verify: baseline …` item is settled by `task-step verdict` and logged as settled by task-step with its evidence, with no seat dispatched.
A7. [test, neg, high] A free-text cannot-verify item still goes to the ruling seat.
A8. [test, high] Every `agents/impl-*.md` carries the anti-hardcoding, report-incorrect-tests and tests-are-immutable clauses, and every non-Sonnet `agents/impl-*.md` carries the scope-limit clause.
A9. [test, high] The stop gate exits 2 with a reason naming what is missing when an `impl-*` agent stops with `**Status:** DONE` or `DONE_WITH_CONCERNS` and the message has no `Report:` line, or the report file is missing, lacks a required section, or has no `## Verified` bullet in §2's grammar.
A10. [test, neg, high] The gate exits 0 for any other agent type, for BLOCKED and NEEDS_CONTEXT stops, and for the third distinct stop of one agent id after two blocks, which it logs to `<state>/impl-stop-gate.log`; a repeated identical stop does not raise the block count.
A11. [test, neg, high] The gate runs no test command and makes no network call: with recording stubs for common test runners and network tools ahead on PATH, a gate run on a 1,000-line report invokes none of them.
A12. [test, high] The pipeline stage replays one case end to end under a given plugin directory and records pass, costUsd, wall time, dispatch count and fix rounds per run in `results/pipeline.tsv`.
A13. [test, neg, high] No pipeline run uses a working directory, plugin directory or HOME outside the eval's own temporary root.
A14. [test, medium] A measured item merges only when its pass^3 count over the same 20 cases x 3 runs is at least the baseline's and its total cost or median wall time is at least 10% lower. Q: is "pass^3 at least baseline, and 10% cheaper or faster" the merge rule you want, or should it allow a noise margin (pass^3 at least baseline − 1, or a fourth run to break a tie), since one case is 5% of 20?
A15. [demo, medium] The measured lane runs comparisons in the Design §6 order until eval spend reaches $1,200. Seven candidate arms (item 8 has none) plus one baseline at about $120 each is $960, plus $120 for the confirmation run, $1,080; this holds only with the single-baseline rule in §6. Q: is $1,200 the right spend cap, or should the plan stop after a smaller first batch?
A16. [test, high] The plugin README documents auto mode for unattended waves and `worktree.baseRef: "head"` for wave worktrees, each with its reason.
A17. [demo, medium] The prompt-audit note records `/doctor prompt-audit` and `/skill-doctor` output for dforge, and each proposed change appears as a register row. Q: if `/doctor prompt-audit` cannot run headless, is one owner-run session acceptable?
A18. [test, neg, high] `reference/native-codex.md` and executing-plans' inline suite rule are not edited; `reference/delegated-task.md`'s by-hand section runs the suite the controller used to get from the implementer.
A19. [demo, high] The stop gate finishes in under 2 seconds on a 1,000-line report on the Linux host.

## Riskiest assumption

The replay eval can drive one task's whole loop headless: `claude -p
--plugin-dir <arm>` in an isolated clone runs the controller's task loop
(implementer, background suite, review, fix rounds) to completion without a
human, and the hidden-test grader scores it. The weakest step is the wait: the
controller's protocol is to end its turn and let the completion notification
start the next one (`skills/subagent-driven-development/SKILL.md`), and under
`claude -p` ending the turn may end the process. Evidence so far: the tier
eval already runs single seats with `claude -p` in isolated snapshots
(`evals/tiers/README.md`), and the controller-model pilot read transcripts of
interactive sessions (`evals/controller/`); neither ran the full loop under a
second plugin directory. Unverified — part E's first task verifies it with one
smoke case on both arms before the rest of E is built. The smoke passes only
when both arms produce a `Task N: complete` ledger line, a graded result, and
a transcript in which the background suite-run and the judge dispatch overlap.
If `-p` ends at the first wait, the pipeline drives an interactive session
(tmux) and §5 is amended before E continues. The mechanical lane does not
depend on it.

## Review rulings

Fable, round 1 (2026-10-28):

1. Suite command source: `task-step start --suite`, from Integration check, else gates.md, else a one-time ruling; no row means `suite: not run`, exit 7 — recommended, owner confirms.
2. Inline mode: its own tasks unchanged; tasks it delegates follow the new loop.
3. Codex and by-hand runs: the by-hand §2 runs suite-run itself; A18 reworded.
4. Baseline: reviewer names a command; red suites compare failing lines against one base run, as parallel-waves §1 does.
5. `verdict` reads `suites.tsv` from `--cwd`'s state directory when given.
6. Group suite: sequential groups at the last held head; wave groups rely on the merged check.
7. Report grammar fixed in the spec: `## Verified` bullets and a `Report:` line.
8. Gate matcher `(dforge:)?impl-.*`, self-check `(^|:)impl-`, first task logs a real input.
9. Double fires keyed by sha256 of the last blocked message.
10. `<state>` from `dforge-path state`; pass-through log `<state>/impl-stop-gate.log`.
11. Gate acts only on a DONE status with a `Report:` line.
12. §5 covers row 11 only.
13. Arm plugin directories via `snapshot.mjs`, no git worktree.
14. Pipeline results in `results/pipeline.tsv`; existing stages and refusal untouched.
15. Measured lane: single baseline at `<M>`, rebase winners, one confirmation run — recommended, owner confirms.
16. Row 10's wave half already shipped; only the stagger is measured.
17. Scope-limit clause on every non-Sonnet tier — recommended, owner confirms.
18. Part C owns a new `tests/impl-clauses.test.sh`.
19. Part A flips the suite-run pin and repoints the two expansion checks at context-size; final-review.md and the SKILL.md example line unchanged.
20. A5 reworded to what `task-step verdict` does.
21. A14 question offers a noise margin; A15 arithmetic corrected.
22. Double-fire claim attributed to the research note.
23. Smoke pass criteria and the tmux fallback added to the riskiest assumption.

Fable, round 2 (2026-10-28):

24. A DONE stop with no `Report:` line blocks; A9 and A10 follow.
25. The controller runs `suite-run -- bash -c '<command>'` from the root; `verdict` matches the `%q` row and accepts clean or dirty.
26. `rereview --covered` waits for the fix head's suite and skips only on a pass.
27. The suite-command resolution rule lives in delegated-task.md §1; executing-plans is not edited.
28. Base failing lines persist in `task-<N>-base-failures.txt` before the temporary worktree goes.
29. Arm plugin directory is `<eval root>/arms/<ref7>/plugins/dforge`.
30. Problem lists Opus, Fable and Haiku as lacking the scope-limit clause.
31. Double-fire sentence reworded.

## Critic findings

Critic folded into Fable's round 1.

- **High — the suite result has no addressable key (§2).** Fixed: §2 Suite command and Controller (ruling 1), pending the owner's confirmation of the command source.
- **High — Codex hosts lose their only full-suite run (§2, A18).** Fixed: by-hand §2 runs suite-run (ruling 3).
- **High — measured-lane baseline economics are inconsistent (§6, A15).** Fixed: single baseline at `<M>` (ruling 15), pending the owner's confirmation.
- **High — the headless whole-loop assumption is untested at the wait (Riskiest assumption).** Fixed: smoke criteria and tmux fallback (ruling 23).
- **High — the A/D contract is a free-text report format (§2, §4).** Fixed: grammar fixed in §2 (ruling 7). The pin on `implementer-prompt.md` lives in A's tests rather than D's, so D's test does not fail before A merges.
- **Medium — `baseline` settlement as specified cannot run.** Fixed (ruling 4).
- **Medium — the gate catches non-task `impl-*` dispatches.** Fixed (ruling 11).
- **Medium — evaluation power with 20 cases.** Moved into A14's question (ruling 21).
- **Medium — wave worktrees keep their own `.dforge`.** Fixed (ruling 5).
- **Medium — A11's wall-clock bound would flake on Windows shards.** Fixed: A11 asserts no test or network command via PATH stubs; timing moved to A19 as a demo.
- **Medium — settled items leave no evidence.** Fixed: the settlement line carries its evidence; symbols use `git grep -nwF`.
- **Medium — simpler arm materialisation.** Fixed (ruling 13).
- **Medium — no outcome for a suite that never finishes.** Fixed: `suite: not run`, exit 7, re-run; `scripts/in-flight` lists a suite in flight at handoff.
- **Nit — row 12 double-listed; row 10's wave half; Fable and Haiku omitted from the scope clause; part C's test unnamed; double-fire attribution; part A's cap after its edits.** Fixed (rulings 12, 16, 17, 18, 22; Parallel decomposition).
