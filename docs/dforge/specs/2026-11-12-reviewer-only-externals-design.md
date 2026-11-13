# Reviewer-only external models

**Execution strategy:** sequential — inline execution
**Depth:** standard — interface

## Goal

Retire dforge's external executor lane: no plan task is implemented by the
Antigravity CLI (`agy`) or by Codex any more; the session implements every task.
Keep both families as reviewers only, through four reviewers: Codex
`gpt-6.1-sol`, Codex `gpt-6-astra`, agy `gemini-4-argon` and agy
`claude-opus-5-5`. A review runs the external reviewers its risk calls for in
parallel and skips any reviewer that is switched off or unavailable at run time.
The cockpit's settings follow: the two lane switches go, an agy review switch
arrives beside the Codex one.

## Decisions

- **Flow.** Asked fast mode or the full flow; answer: "Full flow (Recommended)".
- **Routing.** Asked how the four reviewers share the review seats (offered:
  Codex first then agy; agy first then Codex; Codex light with agy heavy);
  answer: "run the reviewer parallel depends on the risk of task automatically,
  skip that reviewer if it's not available at the runtime."
- **Existing Executor lines.** Asked what happens to plans whose tasks still
  carry `**Executor:**`; answer: "Ignore with a warning (Recommended)".
- **agy review default.** Asked whether the new agy review switch is on or off
  by default; answer: "Off, like Codex (Recommended)".
- **Isolation.** The owner asked for a new worktree; the work runs in
  `.claude/worktrees/retire-executor-lanes` on `feat/retire-executor-lanes`,
  branched from `main`.
- **Approach** (recorded here, not asked). Three were weighed:
  (a) *do-less*: delete the lanes and keep Codex review exactly as it is, with
  no agy reviewer. It fails the request: Argon and agy Opus must review.
  (b) *session-side parallelism*: `task-step` prints one command per reviewer
  and the session starts them as background shells. It keeps the scripts small,
  but whether the reviewers really run in parallel, and which are skipped,
  would live in prose the session may not follow.
  (c) *a panel runner* (chosen): one script starts every eligible reviewer's
  runner at once, waits for all, and prints one status line per reviewer. The
  parallelism and the skip rule are code a test can reach, as
  `run-codex-review.sh` already is for one reviewer.
- **Internal names stay.** The registry (`reference/executors/*.json`),
  `scripts/executors`, `scripts/lib/executor-session.sh`, the session
  directories and the `DR_CODEX_SESSION_DIR` / `DR_AGY_SESSION_DIR` variables
  keep their names; renaming them to "reviewers" touches every gate and test
  for no behaviour. User-facing text says "reviewer".

## Design

### Reviewers and tiers

Each family has a judge block in `reference/ladder.md`, first row preferred,
last row the fallback, each row `model effort seconds`:

```codex-judge
gpt-6-astra xhigh 5400
gpt-6.1-sol xhigh 2400
```

```agy-judge
claude-opus-5-5 high 5400
gemini-4-argon high 2400
```

The `codex-judge` block is unchanged. The `agy-judge` block is new; its bounds
copy the Codex rows of the same tier.

Two tiers, chosen by risk:

| Review | Tier | Reviewers run in parallel |
|---|---|---|
| Task or group at risk 0-2 | light | Codex `gpt-6.1-sol`, agy `gemini-4-argon` (each block's last row; no fallback) |
| Task at risk 3 | heavy | Codex `gpt-6-astra`, agy `claude-opus-5-5` (each block's first row, falling back once to its last row) |
| Plan review round 1 | heavy | as risk 3 |
| Final review's external round | heavy | as risk 3 |

The heavy fallbacks: Astra refused → `gpt-6.1-sol` (today's rule); agy Opus
refused, or the agy Claude quota closed → `gemini-4-argon high`. Under an inline
plan only risk-3 tasks get a per-task review, so the light tier serves group
reviews and the deprecated subagent mode.

### The panel runner

New `scripts/run-review-panel --kind task|plan|final --tier light|heavy --cwd
DIR --out-dir DIR (--prompt FILE | --base SHA)`:

- For each family in registry priority order, reads its gate line
  (`codex-gate`, `agy-gate`). A family whose gate does not print `review=true`
  is skipped and gets a `<id>-judge none/none status=SKIPPED reason=<gate
  reason>` line, in the runners' own status-line grammar.
- Starts each remaining family's runner (`run-codex-review.sh`,
  `run-agy-review.sh`) in the background, each in its own process group, so a
  bound reaches the runner's children (the uutils `timeout` pitfall), then waits
  for all of them. `--tier` reaches the runners only for `--kind task`; plan and
  final runs take the heavy rows, as `run-codex-review.sh` does today.
- Prints each runner's own status line (`OK`, `FALLBACK`, `TIMEOUT`, `FAILED`,
  as today) and a closing `panel tier=<t> lists=<n>`, where `<n>` counts `OK`
  and `FALLBACK` lines.
- A runner's bound is the sum of the seconds of every row it may run (the
  heavy tier's first row plus its fallback row; the light tier's one row) plus
  the runner's per-call grace; the panel's bound is the largest runner bound
  plus 120 seconds, and on it the panel kills every runner group it started.
- Exits 0 whenever it answered, `lists=0` included; 2 on a usage error.

### The agy review runner

New `scripts/run-agy-review.sh`, the twin of `run-codex-review.sh`: same flags,
outcomes and status-line grammar (`agy-judge <model>/<effort> status=… out=…`).
It runs `agy -p` with `--mode plan`, `--output-format json`, `--json-schema` set
to the existing review schemas in `criteria/`, `--model`, `--effort` and
`--print-timeout`, and without `--dangerously-skip-permissions`. It records the
tracked files before the run and fails the run as `FAILED` with
`evidence=wrote` if anything changed, so a reviewer that writes never counts as
a list. A Gemini quota marks agy off for the session; a Claude quota marks only
the Opus row off, through the existing `executor_session_mark_fallback_off`, and
the heavy tier then runs Argon directly.

### Consuming the lists

- **No list** (every reviewer skipped, timed out or failed): today's Claude
  seat: `judge-sonnet-high` for totals 0-5, `judge-opus` for 6 and risk 3.
- **Light tier, one list:** read it as a `codex:light` list is read today.
- **Light tier, two lists:** the band judge (`judge-sonnet-high` 0-5,
  `judge-opus` 6) dedupes both lists and rules CONFIRMED or REJECTED on each
  finding, as `judge-opus` does after Astra today.
- **Heavy tier:** `judge-opus` rules on every finding of every list, one or two.
- **Plan round 1:** the plan writer reads every list, as it reads the single
  Codex list today.
- **Final review:** the external round runs at depth full only, as the Codex
  round does today, and contributes one list per reviewer; the
  dedupe judge runs whenever two or more lists (the Claude review's included)
  carry findings, and its origin tag becomes a `+`-joined set of `claude`,
  `codex` and `agy` (for example `[claude+agy]`), replacing `both`.

`review-route` prints `primary=panel:light` or `primary=panel:heavy+judge-opus`
(plan round 1: `panel:plan`), with the Claude seat as `fallback=`. While neither
gate opens its review surface it prints the Claude seat with
`reason=reviewers-off`, as `reason=codex-off` does today. `task-step review`
writes one prompt per kind as today and prints the panel command in place of
the Codex command. The ledger's seat clause names the reviewers that returned a
list and the judge, for example `seat codex gpt-6.1-sol/xhigh+agy
gemini-4-argon/high+judge-sonnet-high`.

### Gates and settings

- `codex-gate` drops the lane surface: its line loses `lane=`, the `codexLane`
  setting and `trust.smoke` go. With `codexReview` off it answers
  `reason=setting` without probing.
- `agy-gate` becomes a review gate: `review=<bool>` replaces `lane=`; the new
  `agyReview` setting (boolean, default `false`, enforced by script, group
  Workflow, label "Agy reviews") replaces `agyLane`; with it off the gate
  answers `reason=setting` without probing. The review surface opens only when
  `reference/agy-policy.json` records `trust.review: pass`, which replaces
  `trust.smoke`.
- Registry entries keep `id`, `locator`, `probe`, `gate`, `session_dir`,
  `session_dir_env`, `priority`, `reasons`; `wrapper` becomes `runner` (the
  review runner); `surfaces` is `["review"]` for both; `blocks` keeps only
  `gate` and `judge` (`codex-judge`, `agy-judge`). `scripts/executors` requires
  `runner` and `gate`, and loses `ranked`. `detect-executors.sh` checks `runner`
  where it checked `wrapper`, and drops the rows for tools with no lane
  (`cursor-agent`, `opencode`).
- A stored `codexLane` or `agyLane` value is ignored: `dforge-config` resolves
  only schema keys.

### The cockpit

The Workflow tab renders from `config/schema.mjs`, so removing `codexLane` and
`agyLane` and adding `agyReview` right after `codexReview` makes it show
"Codex reviews" and "Agy reviews" and no task switches. The cockpit test that
pressed `set-codexLane-toggle` to prove a script-enforced key is not reported
presses `set-agyReview-toggle` instead. The README's cockpit settings table
follows.

### Retiring the lane

Deleted: `run-codex-task.sh`, `run-agy-task.sh`, both task contracts and report
schemas, `lane-breaker`, `plan-revise`, the `revising-plans` skill and its
routing row, `lib/task-execution.sh`, `lib/task-state.sh`,
`reference/external-task-recovery.md`, the lane blocks of `ladder.md`
(`gate`, `codex-assignment`, `codex-successor`, `codex-timeout`,
`agy-lane-gate`, `agy-assignment`, `agy-successor`, `agy-timeout`), the
lane-only test files and fixtures, and the codex-client request fields only the
lane sent (`resumeThreadId`, `persistThread`, `threadName`, `workspace-write`).

`reference/executor-lane.md` is replaced by `reference/external-review.md`,
holding its review sections (task seats, final-review round, quota and gate
bullets) widened to the panel and agy; every link to the old file moves.
`delegated-task.md` keeps its session review loop and subagent-mode loop and
loses every executor passage. `plan-lint`, `task-step`, `task-brief`,
`next-step`, `lib/plan.sh`, the writing-plans, executing-plans,
subagent-driven-development and handoff skills lose their executor branches.
The ruling kinds `executor-empty-diff` and `codex-empty-diff` go.

A task that still carries `**Executor:**` gets one `plan-lint` WARN,
`Task <N>: the **Executor:** line is obsolete; the session implements this
task`, and nothing else reads the line. A ledger line naming an executor is
history: an incomplete task is implemented by the session.

Outside the plugin: the root README, `SECURITY.md`, the marketplace and plugin
manifests' descriptions and keywords, `scripts/test-shards.mjs` weights and
`scripts/test-all.mjs` suite parts follow. `docs/` files that are historical
plans, specs, notes or registers are not edited. `evals/controller` keeps
counting `run-codex-task.sh` calls, since old transcripts contain them.

## Acceptance

A1. [test, high] With `codexReview` and `agyReview` on and both gates open, `run-review-panel --tier light` starts the Codex `gpt-6.1-sol` and agy `gemini-4-argon` runners so that both are running at the same time, and prints one status line for each plus `panel tier=light lists=2`; a runner that ends `status=FALLBACK` counts as a list.
A2. [test, high] `run-review-panel --tier heavy` runs Codex `gpt-6-astra` and agy `claude-opus-5-5`, and each falls back once to its block's last row when its first row is refused.
A3. [test, neg, high] A family whose gate does not print `review=true` (setting off, not installed, signed out, quota) is not started, and the panel prints `status=SKIPPED` for it with the gate's reason; with both skipped the panel prints `lists=0` and exits 0.
A4. [test, high] `review-route --task` prints `panel:light` for a task at risk 0-2 and `panel:heavy+judge-opus` at risk 3 while either review surface is open, and the Claude band seat with `reason=reviewers-off` while neither is.
A5. [test, high] `review-route --plan-round 1` prints `panel:plan` while either review surface is open.
A6. [test, neg, high] `run-agy-review.sh` never passes `--dangerously-skip-permissions`, and a run that changes a tracked file ends `status=FAILED evidence=wrote`.
A7. [test, high] A Claude-model quota during an agy heavy review marks only the Opus row off, and the next heavy panel runs agy on `gemini-4-argon high`.
A8. [test, high] `agy-gate` with `agyReview` unset answers `review=false reason=setting` without running agy; `codex-gate`'s line carries no `lane=` field.
A9. [test, neg, high] `plan-lint` on a plan whose task carries `**Executor:** codex` exits without an error and prints one WARN naming the task and saying the line is obsolete; `task-brief` and `task-step` treat that task as an ordinary inline task.
A10. [test, neg, high] No shipped file under `plugins/dforge` outside `docs/` names `run-codex-task.sh`, `run-agy-task.sh`, `lane-breaker`, `plan-revise`, `codexLane`, `agyLane` or `executor-lane.md`, and `validate-repository.mjs` passes.
A11. [test, high] `dforge-config` lists `agyReview` (default `false`, label "Agy reviews") right after `codexReview`, and neither `codexLane` nor `agyLane`; a settings file still holding `codexLane: false` resolves without an error.
A12. [demo, high] The cockpit's Workflow tab shows "Codex reviews" and "Agy reviews" toggles and no "Codex tasks" or "Agy tasks" rows.
A13. [test, medium] Light-tier reviews map risk 0-2 to the light panel; risk 2 does not get the heavy panel. Q: should a risk-2 task (shared path or data-shape risk) get the heavy panel (Astra and agy Opus) instead of the light one?
A14. [test, medium] The panel's tasks-with-two-lists judge is the band judge (`judge-sonnet-high` 0-5, `judge-opus` 6), which dedupes and rules on both lists before the fix loop reads them. Q: is a judge pass on every two-list light review worth its cost, or should the session read both lists directly as it reads one?
A15. [test, high] The final review's dedupe judge runs whenever two or more lists carry findings and tags each finding with a `+`-joined origin set from `claude`, `codex`, `agy`.
A16. [test, medium] `agy-policy.json` ships with `trust.review: pass` after one real agy review run on this repository during the plan, and with `trust.review: pending` (agy review stays off whatever the setting) if that run is not made. Q: may the plan make one real, billed agy review run with Argon and one with Opus to open the surface?

## Riskiest assumption

That `agy -p --mode plan` reads the worktree (the diff file and the sources it
names) and returns one JSON object matching the review schema without editing
anything. Evidence so far: `agy --help` (agy 1.5.6, run 2026-11-12) lists
`--mode` with values `accept-edits`, `auto`, `plan`, and `--json-schema` for
print mode; the lane already ran `-p --output-format json --json-schema` with
`--model gemini-4-argon` and `--effort high` (`scripts/run-agy-task.sh:271`).
Whether plan mode answers in print mode without asking for permission is
unverified — the plan's first task verifies it, with the owner's consent to the
billed run (A16). If plan mode stalls, the fallback is `--sandbox` with
`--dangerously-skip-permissions`, kept honest by the tracked-file check (A6).

## Known limits

- On Windows an interrupt does not reach a native `agy.exe`
  (`docs/dforge/registers/2026-11-02-antigravity-executor-lane-auto.md` row 2);
  the panel's bound inherits that. A reviewer cannot write (A6), so a lingering
  run wastes quota but changes nothing.
- The quota mark race in
  `docs/dforge/registers/2026-11-03-agy-gemini-first.md` row 12 carries over to
  the review runner unchanged.
- Codex runs remain one at a time per machine; the panel never starts two Codex
  runs, so it does not hit that limit.
