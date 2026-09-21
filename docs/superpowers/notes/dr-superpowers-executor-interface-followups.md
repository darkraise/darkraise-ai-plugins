# Executor interface — follow-ups

What the run of `docs/superpowers/plans/2026-09-21-dr-superpowers-executor-interface.md`
left open. The ledger is deleted with the workspace, so this is the record.

## Needs an owner decision

- **Commit `f207899` flips `reference/codex-plugin.json` `trust.calibration`
  from `pending` to `pass`, with no recorded justification.** That makes
  `codex-gate` print `review=true`, turning on the Codex task-review seats and
  the final-review Codex round for every session. The design spec's §15 lists
  the calibration decision as out of scope, and the flip also changed
  `tests/codex-gate.test.sh`'s `pending,pass` assertion, in a suite the plan
  declared frozen. It arrived as an incidental commit inside Task 4's range
  and no ruling covers it. The final whole-branch review raised it as
  Important; the scoped re-review upheld deferring it to the owner rather than
  reverting it unilaterally. Ratify it or revert it.
  (The sibling commit `5e5807b`, which raised the astra judge bound from 3600
  to 5400, needs nothing: `reference/ladder.md:313-315` records it as made on
  the owner's instruction, with the measurement behind it.)

## Open, for sub-project B

- **Both plugin manifests and the marketplace entry describe "an external
  Codex executor"** (`.claude-plugin/plugin.json:4`, `.codex-plugin/plugin.json:4`,
  `.claude-plugin/marketplace.json:14`). Accurate while Codex is the only
  registry entry; it needs the same neutralisation when a second one lands.
- **A missing `reference/executors/codex.json` still fails mutely.** The
  final-residual ruling R5 made a *malformed* entry print the helper's
  diagnostic, but `executors get` on an unknown id is silent by design
  (spec §4.2), so a deleted entry turns the lane off with no explanation.
- **On a malformed entry the diagnostic prints twice per
  `executor_session_dir` call**, because that function asks for
  `session_dir_env` and then `session_dir`. Accepted by the R5 ruling as the
  cost of surfacing it at all.

## Open, unscheduled

- **`plan-lint` spawns roughly 60-100 subprocesses and re-reads
  `reference/ladder.md` once per task on a 20-task plan.** `executor_rung` and
  `executor_gate` each shell out to `scripts/executors`, which runs `jq` twice.
  Linear in executors x tasks. Caching `blocks.assignment` and its parsed rows
  per executor alongside `lane_gates` would remove nearly all of it.
  Performance only; no correctness component.
- **No migration note for an existing inline plan carrying an `**Executor:**`
  line.** Such a plan now requires `--effort high` and gains a larger delegated
  set, so a user re-linting an in-flight plan meets a new ERROR with nothing in
  any shipped document explaining it. The behaviour is spec-sanctioned (§9.2)
  and pinned by the `i1`/`i2` fixtures; only the note is missing.
- **`dr-superpowers:finishing-a-development-branch` Step 3 never reads
  `final-fix-report.md`.** It prints the ledger's `Ruling:` lines and
  `amendments.md`, so a final-review residual reaches the owner only if it was
  also written as a ledger line. `reference/final-review.md:109-110` promises
  those residuals surface here. Pre-existing gap in the skill, found by the
  scoped re-review after it caught this run relying on that promise.

## Closed during the final review, recorded so they are not re-found

- The lane gate failed open when an executor's `blocks.gate` named a block
  absent from the ladder (`${emin:-0}` / `${emax:-3}`). Fixed under ruling R4;
  `tests/plan-lint.test.sh` now pins it.
- `scripts/lib/executor-session.sh` swallowed the registry helper's stderr.
  Fixed under ruling R5.
- `reference/executor-lane.md:317-318` and `:509` named `codex-successor` in
  the generic failure taxonomy. Fixed under ruling R6; `:18` keeps the literal
  names because it lists what `ladder.md` actually holds.
- `:95` (`codex-timeout`, quoting Codex's own 900-2400 rung range) and `:365`
  (`scripts/codex-gate`, inside the Codex-only review-seats section) were
  reviewed and are correct as they stand.
