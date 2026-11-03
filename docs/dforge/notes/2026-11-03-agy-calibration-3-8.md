# agy calibration for totals 3-8

Six completed tasks were replayed through `scripts/run-agy-task.sh` with the real `agy` 1.4.12 on 2026-11-03: three scored 3-4 and three scored 6-7, each from its parent commit. The goal was to measure Gemini 4 Argon against the Claude rungs the ladder then assigned to those totals, which had been copied from the native table without a measurement. The pass rule is the one in `docs/dforge/notes/2026-11-02-agy-calibration.md`: the run ends DONE, its result passes the original commit's tests restored over it, it stays inside the original write set without touching the real repository's refs or status, and a blind Claude judge returns `spec: pass` and `quality: approved`.

Changes from that method:
- Each run used its own clone of the repository, with the task in a linked worktree of that clone, so no worktree or branch was created in the real repository.
- Up to three candidates ran at once, one per model, on the same task.
- Judges got neutral ids (`J01`-`J14`), with worktree paths scrubbed from the reports. Tasks scored 3-4 went to `dforge:judge-sonnet-high` and tasks scored 6-7 to `dforge:judge-opus`.
- Before any `agy` run, every task's tests passed on its original commit on this host.

## Replays

| Key | Plan and task | Total | Parent | Original | Tests run on the result |
|---|---|---|---|---|---|
| M1 suite-run | `docs/dforge/plans/2026-10-26-task-loop-steps.md` Task 4 | 3 | `57c46376` | `017f54c6` | `suite-run.test.sh` |
| M2 depth-route | `docs/dforge/plans/2026-10-27-review-depth.md` Task 2 | 3 | `66e0a384` | `98d2f7dc` | `depth-route.test.sh` |
| M3 draft-pack-join | `docs/dforge/plans/2026-10-25-typed-seats-and-drafting.md` Task 4 | 4 | `b2ccedd7` | `8fd6fb14` | `draft-pack.test.sh` |
| H1 executors-ranked | `docs/dforge/plans/2026-11-02-antigravity-executor-lane.md` Task 1 | 6 | `7349308b` | `c575bdf3` | `executors`, `executor-session`, `detect` suites |
| H2 review-tier | `docs/dforge/plans/2026-10-26-faster-plans.md` Task 4 | 6 | `34ff422a` | `13bcfe2f` | `review-route`, `task-step`, `working-directory`, `task-loop-steps.acceptance` suites |
| H3 suite-duration | `docs/dforge/plans/2026-10-31-test-tiers-and-ci-parity.md` Task 1 | 7 | `960e2d1a` | `f1fcd1b4` | `suite-run`, `task-step-suite`, `task-step-base` suites |

## Results

| Task replayed | Rung | Status | Tests | Scope | Judge | Wall s | Tokens |
|---|---|---|---|---|---|---|---|
| M1 suite-run | gemini-4-argon/low | DONE | pass | clean | pass | 137 | 42706 |
| M1 suite-run | gemini-4-argon/medium | DONE | pass | clean | pass | 143 | 48280 |
| M1 suite-run | claude-sonnet-5-5/medium | DONE | pass | clean | fail | 86 | 80756 |
| M2 depth-route | gemini-4-argon/low | DONE | pass | clean | pass | 122 | 44628 |
| M2 depth-route | gemini-4-argon/medium | DONE | pass | clean | pass | 173 | 58563 |
| M2 depth-route | claude-sonnet-5-5/medium | DONE | pass | clean | pass | 80 | 72401 |
| M3 draft-pack-join | gemini-4-argon/low | DONE | pass | clean | pass | 104 | 38006 |
| M3 draft-pack-join | gemini-4-argon/medium | DONE | pass | clean | pass | 80 | 30280 |
| M3 draft-pack-join | claude-sonnet-5-5/medium | DONE | pass | clean | pass | 39 | 41011 |
| H1 executors-ranked | gemini-4-argon/high | DONE | pass | clean | pass | 158 | 55500 |
| H1 executors-ranked | claude-sonnet-5-5/high | DONE | pass | clean | pass | 59 | 61657 |
| H1 executors-ranked | claude-opus-5-5/high | DONE | pass | clean | pass | 104 | 83873 |
| H2 review-tier | gemini-4-argon/high | DONE | pass | clean | pass | 426 | 101985 |
| H2 review-tier | claude-sonnet-5-5/high | blocked | n/a | clean | n/a | 233 | 82508 |
| H2 review-tier | claude-opus-5-5/high | blocked | n/a | clean | n/a | 120 | 81277 |
| H3 suite-duration | gemini-4-argon/high | DONE | pass | clean | pass | 202 | 54678 |

Judges reported only Minor findings, apart from one Important. Their scores (spec / scope / verification / quality, out of 20) were 19 / 18-20 / 13-18 / 13-18.
- M1 on `claude-sonnet-5-5/medium`: the judge returned `quality: changes`. Its one Important finding is that the reuse key omits the working directory, in code the brief dictates word for word. The judges of the two Argon M1 runs reviewed the same code and graded that point Minor. The row fails under the pass rule; the finding is judge variance on brief-mandated code, not a defect of that run.
- H2 on both Claude rungs blocked on quota, not capability (below). H3 did not run on a Claude rung for the same reason.

## Quota

The first real `agy` quota error, from both Claude runs of H2 at 14:09 and 14:11 host time:

```
RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 4h47m34s.
```

It arrives in the result's `.error` field and in a stderr `AGY_ERROR:` JSON line (`"status":"RESOURCE_EXHAUSTED","error_code":429,"retryable":true`). It matches the wrapper's quota pattern, which until now had been assumed rather than observed.
- **The Claude quota is separate from Gemini's.** Argon kept working after the Claude error: H2 on `gemini-4-argon/high` finished at 14:14, and H3 ran from 14:18 to 14:21. Its gate refresh read `usable=true` both times.
- **The Claude allowance is small.** It ran out after about 500k tokens of Sonnet and Opus runs in this session (the seven Claude rows above). Whether earlier use that day counted toward it is unknown.
- **The Gemini limit was not reached.** Argon used about 475k tokens across nine runs.

## Conclusions

- Argon low passed every task scored 3-4, using 53-93% of Sonnet medium's tokens (65% overall) and taking 1.5-2.7 times as long.
- Argon high passed every task scored 6-7. It is the only rung measured on all three high tasks.
- Claude through `agy` is too scarce to be a first rung: one session of calibration exhausted it.

## Left in place

- The run clones, briefs, reports and blinded judge packages sit in the session scratchpad of 2026-11-03. Nothing was created in the repository.
