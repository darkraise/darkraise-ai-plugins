# dagents suite baseline

The copied 4.17.1 suites under `plugins/dagents/tests/`, each run with
`timeout 900 bash <suite>` from the repository root, 8 at a time, on
2026-11-17 at commit `5a601b48`, with `CLAUDE_CONFIG_DIR` unset. One line per
suite: exit code, then path.

## Before the rename

```text
0 plugins/dagents/tests/agy-gate.test.sh
0 plugins/dagents/tests/agy-gemini-first.acceptance.test.sh
1 plugins/dagents/tests/antigravity-executor-lane.acceptance.test.sh
0 plugins/dagents/tests/auto-default.test.sh
0 plugins/dagents/tests/auto-run-skills.test.sh
0 plugins/dagents/tests/auto-run-worktree-setting-qa.acceptance.test.sh
1 plugins/dagents/tests/auto-run-worktree-setting.acceptance.test.sh
0 plugins/dagents/tests/auto-run.test.sh
0 plugins/dagents/tests/budget-line.test.sh
0 plugins/dagents/tests/ci-mirror.test.sh
0 plugins/dagents/tests/clean-session-phases.acceptance.test.sh
0 plugins/dagents/tests/codex-client.test.sh
0 plugins/dagents/tests/codex-gate.test.sh
0 plugins/dagents/tests/codex-review.test.sh
0 plugins/dagents/tests/context-size.test.sh
0 plugins/dagents/tests/criteria.test.sh
0 plugins/dagents/tests/darkmem-sync.test.sh
0 plugins/dagents/tests/depth-route.test.sh
0 plugins/dagents/tests/detect.test.sh
0 plugins/dagents/tests/dforge-config.test.sh
0 plugins/dagents/tests/dforge-dir.test.sh
0 plugins/dagents/tests/dforge-migrate.test.sh
0 plugins/dagents/tests/dforge-state.test.sh
0 plugins/dagents/tests/executor-recovery.test.sh
0 plugins/dagents/tests/executor-session.test.sh
0 plugins/dagents/tests/executors.test.sh
0 plugins/dagents/tests/faster-plans.acceptance.test.sh
0 plugins/dagents/tests/finish-choice.test.sh
0 plugins/dagents/tests/fleet.test.sh
0 plugins/dagents/tests/gates-manifest.test.sh
0 plugins/dagents/tests/hook.test.sh
0 plugins/dagents/tests/impl-stop-gate.test.sh
0 plugins/dagents/tests/in-flight.test.sh
0 plugins/dagents/tests/inline-mode.test.sh
1 plugins/dagents/tests/inline-only-execution.acceptance.test.sh
1 plugins/dagents/tests/inline-only.acceptance.test.sh
0 plugins/dagents/tests/ladder.test.sh
0 plugins/dagents/tests/lane-breaker.test.sh
0 plugins/dagents/tests/lanes.test.sh
0 plugins/dagents/tests/lens-route.test.sh
0 plugins/dagents/tests/lock.test.sh
0 plugins/dagents/tests/native-routing.test.sh
0 plugins/dagents/tests/next-step.test.sh
0 plugins/dagents/tests/plan-amend.test.sh
0 plugins/dagents/tests/plan-lib.test.sh
0 plugins/dagents/tests/plan-lint.test.sh
0 plugins/dagents/tests/plan-revise.test.sh
0 plugins/dagents/tests/polluter.test.sh
0 plugins/dagents/tests/process-roles.test.sh
0 plugins/dagents/tests/register.test.sh
0 plugins/dagents/tests/repo-audit.test.sh
0 plugins/dagents/tests/retained-review-data.acceptance.test.sh
0 plugins/dagents/tests/review-depth-qa.acceptance.test.sh
0 plugins/dagents/tests/review-depth.acceptance.test.sh
0 plugins/dagents/tests/review-record.test.sh
0 plugins/dagents/tests/review-route.test.sh
0 plugins/dagents/tests/roadmap.test.sh
0 plugins/dagents/tests/roots.test.sh
0 plugins/dagents/tests/run-agy-task.test.sh
0 plugins/dagents/tests/run-codex-task.test.sh
0 plugins/dagents/tests/sdd-references.test.sh
0 plugins/dagents/tests/seats.test.sh
0 plugins/dagents/tests/settings-skills.test.sh
0 plugins/dagents/tests/skill-size.test.sh
0 plugins/dagents/tests/skill-split-planning.test.sh
0 plugins/dagents/tests/snapshot.test.sh
1 plugins/dagents/tests/speed-and-cost-followups.acceptance.test.sh
0 plugins/dagents/tests/speed-and-cost.acceptance.test.sh
0 plugins/dagents/tests/suite-run.test.sh
0 plugins/dagents/tests/task-loop-steps.acceptance.test.sh
0 plugins/dagents/tests/task-state.test.sh
0 plugins/dagents/tests/task-step-base.test.sh
0 plugins/dagents/tests/task-step-settle.test.sh
0 plugins/dagents/tests/task-step-suite.test.sh
0 plugins/dagents/tests/task-step-text.test.sh
0 plugins/dagents/tests/task-step.test.sh
0 plugins/dagents/tests/test-simplifier.test.sh
0 plugins/dagents/tests/test-volume-rules.acceptance.test.sh
0 plugins/dagents/tests/turn-end.test.sh
0 plugins/dagents/tests/typed-seats-and-drafting.acceptance.sh
0 plugins/dagents/tests/ui-hooks.test.sh
0 plugins/dagents/tests/ui-lint.test.sh
0 plugins/dagents/tests/ui-proof.test.sh
1 plugins/dagents/tests/ui-ux-skill.acceptance.test.sh
0 plugins/dagents/tests/ui-ux-skill.test.sh
0 plugins/dagents/tests/wave.test.sh
0 plugins/dagents/tests/wording-pin-deletion.acceptance.test.sh
0 plugins/dagents/tests/working-directory.test.sh
0 plugins/dagents/tests/worktree-instructions.test.sh
```

## After the rename

`node scripts/test-all.mjs --plugin dagents` after `dagents-rename.mjs tree`,
with `CLAUDE_CONFIG_DIR` unset. Failing suites and their disposition:

- `skill-size.test.sh`, `clean-session-phases.acceptance.test.sh` (A11),
  `speed-and-cost.acceptance.test.sh` (A1): `skills/executing-plans/SKILL.md`
  grew to 20014 bytes from the longer name. Fixed: two wording trims bring it
  to 19995 bytes.
- `lanes.test.sh` (agy calibration decision) and
  `typed-seats-and-drafting.acceptance.sh` (A12, A13): they read this
  repository's own notes and plans, which stay under `docs/dforge/`. Fixed:
  the paths point at `docs/dforge/` again, and both files are on
  `DAGENTS_DFORGE_ALLOWED`.
- `faster-plans.acceptance.test.sh` A22: dropped the checks that lint this
  repository's own pre-spec plans; they name `dforge:` implementers, which
  dagents accepts only after `dagents-migrate`. The synthetic old-plan checks
  stay.
- `auto-run-worktree-setting.acceptance.test.sh` ("both manifests agree, at
  4.14.0 or later") and `inline-only.acceptance.test.sh` ("version is 4.13.0
  or later"): dropped; dagents starts at 1.0.0.
- `inline-only.acceptance.test.sh` ("marketplace keyword swapped"): dropped;
  the dagents catalog entry names `subagents` on purpose.
- `antigravity-executor-lane.acceptance.test.sh` A2 and A5 (compare against
  dforge commit `7349308b`) and A14's history checks (the commit that flipped
  `trust.smoke`): dropped; `plugins/dagents` has no history before its copy.
  A14's check of the shipped policy value stays.
- `claude plugin test plugins/dagents` failed before the rename only (its mod
  wrote state that dforge owns); it passes after it.
- `inline-only-execution.acceptance.test.sh` and
  `speed-and-cost-followups.acceptance.test.sh` failed in the first baseline
  run only and passed in every later run.
- `ui-ux-skill.acceptance.test.sh` failed in both runs before the rename and
  passes after it.

## Guard message

Checked by hand on 2026-11-17 with Claude Code 2.1.326. The nested session
used a fresh config directory whose `installed_plugins.json` and
`settings.json` install and enable `dforge@darkraise` at user scope, with
dagents loaded through `--plugin-dir plugins/dagents`. At startup the
transcript showed the guard's `systemMessage` as
`SessionStart:startup says: Workflow plugins conflict: dagents@darkraise (this session), dforge@darkraise (user) are enabled together.`
It also showed the two disable steps (`--scope local` for dagents;
`--scope local`, then `--scope user` for dforge) and "Then start a new
session." Injected context does not show on screen; stand-down.test.sh is
what checks that the dagents entry point is not injected. The cockpit pane
still rendered: its own guard line comes in Task 22.
