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

- **Spec review (2026-11-13).** Risk-2 tasks: "Light pair (Recommended)".
  Two light lists: "Judge every time". Billed verification runs: "Argon and
  Opus". Plan mode stalls: "Ship agy review off (Recommended)". Light tier
  unused in inline mode: "Accept, document it (Recommended)". The
  `revising-plans` skill and `plan-revise`: "Delete it, and we will retire 5.0
  plan".
- **dforge 5 retired (2026-11-13).** The earlier dforge 5 rebuild on the
  harness's plan mode (`refactor/dforge-5`, PR #54) is dropped: "retire version
  5.0 spec, plan and branch, totally drop it, we will keep the dforge workflow
  with some future improvement later." This change takes 5.0.0.

Early CI: none

Finish: pr

Worktree: worktree
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
| Task or batch at risk 0-2 | light | Codex `gpt-6.1-sol`, agy `gemini-4-argon` (each block's last row; no fallback) |
| Task at risk 3 | heavy | Codex `gpt-6-astra`, agy `claude-opus-5-5` (each block's first row, falling back once to its last row) |
| Plan review round 1 | heavy | as risk 3 |
| Final review's external round | heavy | as risk 3 |

The heavy fallbacks: Astra refused → `gpt-6.1-sol` (today's rule); agy Opus
refused → `gemini-4-argon high`. A Claude quota during an Opus run ends that
run `FAILED` and marks the Opus row off, so the following heavy panels run
Argon directly until the quota resets. The Claude quota on Antigravity is small
(`reference/ladder.md`, about 500k tokens), so the expected steady state after
one or two heavy reviews is Opus off and Argon reviewing; the ledger records it
as `agy claude-opus-5-5 off (quota until <time>)`, which tells a quota day from
a fault.

Under an inline plan only risk-3 tasks get a per-task review, and the final
external round runs at depth full only, so in the default inline mode the light
tier never runs: Sol and Argon are reached as heavy fallbacks, and a
standard-depth plan with no risk-3 task uses the externals for plan round 1
alone. The light tier serves per-task and batch reviews in the deprecated
subagent mode. A group keeps the Claude band judge, as today
(`scripts/task-step` sends a group's route to the Claude judge).

### The panel runner

New `scripts/run-review-panel --kind task|plan|final --tier light|heavy --cwd
DIR --out-dir DIR (--prompt FILE | --base SHA)`:

- For each family in registry priority order (`scripts/executors ranked`),
  reads its gate line once (`codex-gate`, `agy-gate`). A family whose gate does
  not print `review=true` is skipped and gets a `<id>-judge none/none
  status=SKIPPED reason=<r>` line, in the runners' own status-line grammar.
  `<r>` is the gate's reason; when the gate prints `usable=true review=false`
  it is `untrusted`, or `no-session-id` when `CLAUDE_CODE_SESSION_ID` is
  unset, never the gate's literal `reason=ok`.
- The panel owns availability: each runner's roster step is limited to its own
  family, so one panel run makes one Codex auth probe and never overlaps a
  Codex turn with a second probe.
- Starts each remaining family's runner (`run-codex-review.sh`,
  `run-agy-review.sh`) in the background, each in its own process group where
  `setsid` exists, so a bound reaches the runner's children (the uutils
  `timeout` pitfall), then waits for all of them. Without `setsid` (Git Bash,
  macOS) it starts them as plain background jobs and on its bound kills their
  PIDs and their direct children. `--tier` reaches the runners only for `--kind
  task`; plan and final runs take the heavy rows, as `run-codex-review.sh` does
  today.
- Each runner's stderr goes to `<out-dir>/<id>.stderr`, so two parallel runners
  never interleave, and every non-`OK` status line carries `reason=`.
- Prints each runner's own status line (`OK`, `FALLBACK`, `TIMEOUT`, `FAILED`)
  and a closing `panel tier=<t> lists=<n>`, where `<n>` counts `OK` and
  `FALLBACK` lines.
- A runner's bound is its first row's seconds plus its grace, as today: a
  fallback follows only a refusal, which ends at once. The panel's bound is the
  largest runner bound plus 120 seconds and stays at or under 7080 seconds, below
  the host's 7200-second background-call cap; on it the panel kills every
  runner it started. `task-step` prints the panel's `timeout:` as it prints the
  Codex one today.
- Exits 0 whenever it answered, `lists=0` included; 2 on a usage error.

### The agy review runner

New `scripts/run-agy-review.sh`, the twin of `run-codex-review.sh`: same flags,
outcomes and status-line grammar (`agy-judge <model>/<effort> status=… out=…`).
It runs `agy -p` with `--mode plan`, `--output-format json`, `--json-schema` set
to the existing review schemas in `criteria/` (for `--kind final`, a new
one-field schema holding the prose review as `review`, since the lane only ever
read `structured_output` and the field of a schema-less answer is unverified),
the answer read from the result's `structured_output`, `--model`, `--effort`,
`--print-timeout` and `--add-dir` for the prompt directory, and never with
`--dangerously-skip-permissions`. The prompt travels as a file named by a
one-sentence pointer, as the lane's did, to stay under the Windows
command-line limit.

Before the run it records `git status --porcelain` (tracked and untracked),
`HEAD` and the stash list of `--cwd`; if any changed, the run ends
`status=FAILED evidence=wrote` naming the changed paths, never counts as a
list, and the session restores those paths before any commit.

It carries over the lane's result classification from `run-agy-task.sh`, which
this change deletes: a print timeout that exits 0 is `TIMEOUT`; a clean JSON
answer is never scanned for quota words (a review of this repository mentions
quotas); a stderr-only quota marks nothing; `429` counts only as a whole
number; the reset is parsed from `Resets in`. A Gemini quota marks agy off
until the reset the error names, or for the session when it names none; a
Claude quota marks only the Opus row off, through the existing
`executor_session_mark_fallback_off`, and the heavy tier then runs Argon
directly.

### Consuming the lists

- **No list** (every reviewer skipped, timed out or failed): today's Claude
  seat: `judge-sonnet-high` for totals 0-5, `judge-opus` for 6 and risk 3.
- **Light tier, one list:** read it as a `codex:light` list is read today.
- **Light tier, two lists:** the band judge (`judge-sonnet-high` 0-5,
  `judge-opus` 6) dedupes both lists and rules CONFIRMED or REJECTED on each
  finding, as `judge-opus` does after Astra today.
- **Heavy tier:** `judge-opus` rules on every finding of every list, one or two.
- **Whose verdict counts:** when a judge runs, the judge's verdict and scores
  go on the ledger; with one list and no judge, that list's.
- **Judge prompt:** `task-step review` writes it before the panel runs, so its
  Second Pass section names a list of review files, and the judge reads those
  that exist. The report's external section is renamed from `## Codex
  findings` to `## External findings`, and `task-step verdict` reads the new
  name.
- **Plan round 1:** the plan writer reads every list, as it reads the single
  Codex list today. With two score sets the lowest score per criterion decides
  the "any score of 8 or below" gate, and the `**Plan review:**` header line
  names every seat that returned a list.
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
  `trust.smoke`. A runner reads only `usable` from its gate, as
  `run-codex-review.sh` does, so the plan's verification run can go through
  `run-agy-review.sh` directly while `trust.review` is still pending (with
  `agyReview` on). The setting's description says the switch does nothing while
  the surface is untrusted. The gate line prints the Claude-model mark as
  `claude=on|off` in place of `fallback=`, since Opus is now the heavy tier's
  first row; the stored key keeps its name.
- Registry entries keep `id`, `locator`, `probe`, `gate`, `session_dir`,
  `session_dir_env`, `priority`, `reasons`; `wrapper` becomes `runner` (the
  review runner); `surfaces` is `["review"]` for both; `blocks` keeps only
  `judge` (`codex-judge`, `agy-judge`), since the `gate` and `agy-lane-gate`
  ladder blocks are deleted; `reference` points at
  `reference/external-review.md`. `scripts/executors` requires `runner` and
  `gate`, no longer requires `blocks.gate`, and keeps `ranked`, which the panel
  reads. `detect-executors.sh` checks `runner` where it checked `wrapper`, and
  drops the rows for tools with no lane (`cursor-agent`, `opencode`).
- A stored `codexLane` or `agyLane` value is ignored: `dforge-config` resolves
  only schema keys. `dforge-config unset codexLane` exits 2 as for any unknown
  key, so the stale key stays in the file, harmlessly.

### The cockpit

The Workflow tab renders from `config/schema.mjs`, so removing `codexLane` and
`agyLane` and adding `agyReview` right after `codexReview` makes it show
"Codex reviews" and "Agy reviews" and no task switches. The cockpit test that
pressed `set-codexLane-toggle` to prove a script-enforced key is not reported
presses `set-agyReview-toggle` instead. The `executionMode` description loses
"executor tasks excepted". The README's cockpit settings table follows.

### Retiring the lane

Deleted: `run-codex-task.sh`, `run-agy-task.sh`, both task contracts and report
schemas, `lane-breaker`, `plan-revise`, the `revising-plans` skill and its
routing row, `lib/task-execution.sh`, `lib/task-state.sh`,
`reference/external-task-recovery.md`, the lane blocks of `ladder.md`
(`gate`, `codex-assignment`, `codex-successor`, `codex-timeout`,
`agy-lane-gate`, `agy-assignment`, `agy-successor`, `agy-timeout`), the
lane-only test files and fixtures, and the codex-client request fields
`resumeThreadId`, `persistThread`, `threadName` and `workspace-write`; the
review runner's request, which also sends the first three, drops them in the
same change.

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
task`, and nothing else reads the line. The header's `> **External
executors:**` line is ignored the same way, with no extra warning, and
`plan-lint` stops erroring on it.

A ledger line naming an executor is history: an incomplete task is implemented
by the session. When a task's last ledger line names an executor and no
complete line follows, the session first runs `git status`, shows the
leftover changes a stopped executor may have left in the tree, and keeps or
discards them before implementing. Leftover run locks and owner records under
the git directory are inert. `next-step` drops its `thread pending` warning.

### Migration and release

The change ships as dforge 5.0.0: it removes settings, a skill and scripts. The
README gains a "Migrating to 5.0" section naming the removed `codexLane` and
`agyLane` settings and the new `agyReview` switch, the removed
`revising-plans` skill and `plan-revise` (an old-format plan is fixed against
`plan-lint` or re-planned), and the mid-lane rule above.

Outside the plugin: the root README, `SECURITY.md`, the marketplace and plugin
manifests' descriptions, keywords and versions, `scripts/test-shards.mjs`
weights and `scripts/test-all.mjs` suite parts follow. `docs/` files that are
historical plans, specs, notes or registers are not edited. `evals/controller`
keeps counting `run-codex-task.sh` calls, since old transcripts contain them,
and adds `run-review-panel` to its review pattern, reading `--tier` the same
way, so reviews in new transcripts are still counted.

## Acceptance

A1. [test, high] With `codexReview` and `agyReview` on and both gates open, `run-review-panel --tier light` starts the Codex `gpt-6.1-sol` and agy `gemini-4-argon` runners so that both are running at the same time, and prints one status line for each plus `panel tier=light lists=2`; a runner that ends `status=FALLBACK` counts as a list.
A2. [test, high] `run-review-panel --tier heavy` runs Codex `gpt-6-astra` and agy `claude-opus-5-5`, and each falls back once to its block's last row when its first row is refused.
A3. [test, neg, high] A family whose gate does not print `review=true` (setting off, not installed, signed out, quota) is not started, and the panel prints `status=SKIPPED` for it with the gate's reason; with both skipped the panel prints `lists=0` and exits 0.
A4. [test, high] `review-route --task` prints `panel:light` for a task at risk 0-2 and `panel:heavy+judge-opus` at risk 3 while either review surface is open, and the Claude band seat with `reason=reviewers-off` while neither is.
A5. [test, high] `review-route --plan-round 1` prints `panel:plan` while either review surface is open.
A6. [test, neg, high] `run-agy-review.sh` never passes `--dangerously-skip-permissions`, and a run that changes a tracked file, adds an untracked file, moves `HEAD` or changes the stash list ends `status=FAILED evidence=wrote` naming the changed paths.
A7. [test, high] A Claude-model quota during an agy heavy review marks only the Opus row off, and the next heavy panel runs agy on `gemini-4-argon high`.
A8. [test, high] `agy-gate` with `agyReview` unset answers `review=false reason=setting` without running agy; `codex-gate`'s line carries no `lane=` field.
A9. [test, neg, high] `plan-lint` on a plan whose task carries `**Executor:** codex` exits without an error and prints one WARN naming the task and saying the line is obsolete; `task-brief` and `task-step` treat that task as an ordinary inline task.
A10. [test, neg, high] No file under `plugins/dforge`'s `scripts/`, `reference/`, `skills/`, `hooks/`, `config/` or manifests names `run-codex-task.sh`, `run-agy-task.sh`, `lane-breaker`, `plan-revise`, `codexLane`, `agyLane` or `executor-lane.md` (tests feeding legacy input and the README's migration text are exempt), and `validate-repository.mjs` passes.
A11. [test, high] `dforge-config` lists `agyReview` (default `false`, label "Agy reviews") right after `codexReview`, and neither `codexLane` nor `agyLane`; a settings file still holding `codexLane: false` resolves without an error.
A12. [demo, high] The cockpit's Workflow tab shows "Codex reviews" and "Agy reviews" toggles, no "Codex tasks" or "Agy tasks" rows, and no `executionMode` description mentioning executor tasks.
A13. [test, confirmed] Light-tier reviews map risk 0-2 to the light panel; risk 2 does not get the heavy panel.
A14. [test, confirmed] The panel's tasks-with-two-lists judge is the band judge (`judge-sonnet-high` 0-5, `judge-opus` 6), which dedupes and rules on both lists before the fix loop reads them.
A15. [test, high] The final review's dedupe judge runs whenever two or more lists carry findings and tags each finding with a `+`-joined origin set from `claude`, `codex`, `agy`.
A16. [test, confirmed] The plan makes one real, billed agy review run on this repository with `gemini-4-argon` and one with `claude-opus-5-5`; `agy-policy.json` ships with `trust.review: pass` only when both return a schema-valid list without writing, and with `trust.review: pending` (agy review stays off whatever the setting) otherwise.
A17. [test, high] One `run-review-panel` run makes exactly one Codex auth probe.
A18. [test, high] The README carries a "Migrating to 5.0" section naming `codexLane`, `agyLane`, `agyReview`, `revising-plans` and `plan-revise`, and `node scripts/release.mjs --dry-run` on the branch prints `release dforge 4.17.1 -> 5.0.0` (no marketplace file holds a dforge version, and CI's release step writes the version lines).

## Riskiest assumption

That `agy -p --mode plan` reads the worktree (the diff file and the sources it
names) and returns one JSON object matching the review schema without editing
anything. Evidence so far: `agy --help` (agy 1.5.6, run 2026-11-12) lists
`--mode` with values `accept-edits`, `auto`, `plan`, and `--json-schema` for
print mode; the lane already ran `-p --output-format json --json-schema` with
`--model gemini-4-argon` and `--effort high` (`scripts/run-agy-task.sh:271`).
Whether plan mode answers in print mode without asking for permission is
unverified — the plan's first task verifies it, with the owner's consent to the
billed runs (A16), one on Argon and one on Opus, after a free `agy models`
check that `claude-opus-5-5` is offered. The verification run's agy version becomes
`agy-policy.json`'s `min_version` and `calibrated`, since the flags were seen
only on 1.5.6. If plan mode stalls or cannot answer, agy review ships with
`trust.review: pending` and stays off; A6 is not relaxed.

## Known limits

- On Windows an interrupt does not reach a native `agy.exe`
  (`docs/dforge/registers/2026-11-02-antigravity-executor-lane-auto.md` row 2);
  the panel's bound inherits that. A reviewer that writes fails its run (A6),
  so a lingering run wastes quota and leaves any change for the session to
  restore.
- The quota mark race in
  `docs/dforge/registers/2026-11-03-agy-gemini-first.md` row 12 carries over to
  the review runner unchanged.
- Codex runs remain one at a time per machine; the panel never starts two Codex
  runs, so it does not hit that limit.

## Critic findings

Folded into Fable's round 1 (`.dforge/spec-review-2026-11-12-reviewer-only-externals-design-1-report.md`).

- [High] Group reviews had an external panel nothing could run — fixed: groups keep the Claude band judge; the light tier serves per-task and batch reviews in subagent mode.
- [High] The stalled-plan-mode fallback broke A6 and the write check saw too little — fixed: the fallback is gone (a failed check leaves `trust.review: pending`), and the check covers tracked and untracked files, `HEAD` and the stash list, names the paths, and the session restores them.
- [Medium] Two-list verdict source, judge prompt and report grammar undefined — fixed in Consuming the lists (whose verdict counts, a Second Pass list of files, `## External findings`, the plan-round rule); the light two-list rule is the band judge every time (A14, owner).
- [Medium] Heavy panel bound above the host's background cap — fixed: first row plus grace, panel bound at or under 7080 s, `task-step` prints the timeout, no-`setsid` behaviour stated.
- [Medium] agy runner rules lived in the deleted lane runner — fixed: the carried-over classification rules, the final-kind schema, the pointer file and `--add-dir` are listed.
- [Medium] Each runner's roster call probed every family — fixed: the panel owns availability, each runner probes only its own family (A17).
- [Medium] Panel output hid why a reviewer gave no list — fixed: the `untrusted` and `no-session-id` reasons, per-runner stderr files, `reason=` on every non-`OK` line, and the setting's description.
- [Medium] A10 conflicted with A11 and a migration note; no version — fixed: A10 scoped, Migration and release section, 5.0.0 (A18).
- [Medium] `trust.review: pass` on flags checked on one agy version — fixed: the verification run's version becomes `min_version` and `calibrated`, plus a free `agy models` Opus check.
- [Medium] A plan caught mid-lane had no path — fixed: the `git status` keep-or-discard rule, inert records, the `next-step` warning dropped.
- [Medium] Opus-first heavy tier on a small quota — answered: the owner asked for agy Opus; the expected steady state and its ledger text are now stated.
- [Medium] The controller eval stopped counting reviews — fixed: it adds `run-review-panel` to its pattern.
- [Medium] Deleting `revising-plans` removes non-lane behaviour — answered: the owner chose to delete it (Decisions, spec review).
- [Nit] Registry paragraph contradictions — fixed: `ranked` stays, `blocks` keeps only `judge`, `reference` moves.
- [Nit] `fallback=off` would mean the preferred row is off — fixed: the gate prints `claude=on|off`.
- [Nit] The review runner also sends the thread fields — fixed.
- [Nit] `executionMode` description mentions executor tasks — fixed, and in A12.
- [Nit] "Marks agy off for the session" understated the reset handling — fixed.

## Review rulings

- Fable, spec: Decisions Flow, Routing, Executor lines, agy default, Isolation and Internal names — met.
- Fable, spec: the header's `> **External executors:**` line is ignored with no extra warning; `plan-lint` stops erroring on it.
- Fable, spec: register items 1-7 each have a design section and an acceptance statement.
- Fable, spec: group reviews keep the Claude band judge.
- Fable, spec: `executors ranked` stays; `blocks.gate` goes.
- Fable, spec: A10 applies to scripts, references, skills, hooks, config and manifests.
- Fable, spec: a stored `codexLane` or `agyLane` is ignored; `unset` on it exits 2, harmlessly.
- Fable, spec: A6 wins over the plan-mode fallback.
- Fable, spec: with a judge, the judge's verdict and scores count; with one list and no judge, that list's.
- Fable, spec: `SKIPPED` for `usable=true review=false` reads `untrusted`, or `no-session-id`, never `reason=ok`.
- Fable, spec: a Claude quota mid-Opus run is `FAILED` plus the mark; Argon from the next heavy panel on.
- Fable, spec: a runner's bound is its first row plus grace.
- Fable, spec: the plan's verification run may go through `run-agy-review.sh` directly while `trust.review` is pending, with `agyReview` on.
- Fable, spec: the cockpit test swap's claim about the current test is correct.
