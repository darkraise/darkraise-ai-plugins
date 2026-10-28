# Tier evaluation harness

Measures whether a dforge assignment row or review seat can move to a
cheaper agent, by replaying this repository's own plan history. The design,
the grading and the decision rules are in
`docs/superpowers/specs/2026-10-01-dr-superpowers-tier-eval-design.md`.

Only `run-grid.mjs`, `run-case.mjs` and `grade-review.mjs` call a model. They
run `claude -p`, which draws on the Claude subscription's usage limits.
Everything else, including the tests, is free. POSIX only.

Each run passes `--setting-sources project` and sets `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1`: the
flag alone leaves the user's global CLAUDE.md loaded.

## Commands

Run them from the repository root.

| Command | What it does |
|---|---|
| `node evals/tiers/build-manifest.mjs` | Enumerates eligible tasks, golden-checks each, writes `cases/manifest.tsv` and `cases/excluded.tsv` |
| `node evals/tiers/build-manifest.mjs --slices` | Merges two or three consecutive tasks of one plan into slice cases scored with spec 2, golden-checks them in order until five pass, writes `cases/slices.tsv` and `cases/slices-excluded.tsv` |
| `node evals/tiers/build-case.mjs CASE_ID DIR` | Builds one case's snapshot, brief and prompt, for inspection |
| `node evals/tiers/run-grid.mjs --stage STAGE [--rep N] [--minutes M] [--pass P]` | Runs the unscored cells of `smoke`, `written`, `stripped`, `review` or `slice`, two at a time; `--minutes` stops starting cells after M minutes; `--pass` grades every review again as passes P and P + 1 |
| `node evals/tiers/run-case.mjs CASE_ID ARM [--rep N]` | Runs and grades one cell |
| `node evals/tiers/run-case.mjs CASE_ID ARM [--rep N] --exclude REASON` | Runs nothing: takes the case out of the repetition for every arm, with the reason |
| `node evals/tiers/run-grid.mjs --stage pipeline [--rep N] [--minutes M]` | Replays every case of `cases/pipeline.tsv` under the baseline and the candidate ref of `arms.json`'s `pipeline` entry, two runs each, into `results/pipeline.tsv`; a cell with a settled row is skipped |
| `node evals/tiers/grade-case.mjs RUN_DIR` | Re-grades a finished implementation run |
| `node evals/tiers/grade-review.mjs CASE_ID ARM [--rep N] [--pass P]` | Grades one review against its rubric |
| `node evals/tiers/report.mjs [--rep N] [--pass P]` | Prints the decision table, reading review grades of pass P |
| `node evals/tiers/build-pipeline-manifest.mjs` | Golden-checks the tasks of the finished plans in `docs/dforge/plans/completed.md`, picks 12 (tasks with fix rounds first) and writes `cases/pipeline.tsv` |
| `node evals/tiers/report.mjs --pipeline [--rep N]` | Prints pass^2, total cost and median wall time per pipeline arm from `results/pipeline.tsv` |
| `node --test evals/tiers/tests/*.test.mjs` | The harness tests, against a stub `claude` |

`run-grid.mjs` exits 0 when the stage is complete, 3 when it stopped at a
rate limit, at the spend cap or at `--minutes`, 1 when cells remain after harness errors, and
2 when `plugins/dforge` differs from the manifest's start commit. It also exits 2
when the slice stage has no slice manifest.
Run the same command again to resume: a cell with a scored row is skipped.

A manifest built before dforge 4.0.0 names a start commit without `plugins/dforge`, so `run-grid.mjs` refuses it; build a new manifest for a new repetition.

## Files

| Path | Holds |
|---|---|
| `arms.json` | The agents each row and the review seat are compared on, current agent first |
| `cases/manifest.tsv` | The implementation cases; its first line pins the start commit |
| `cases/excluded.tsv` | Every task left out, with the reason |
| `cases/slices.tsv` | The slice cases; its first line pins its own start commit |
| `cases/slices-excluded.tsv` | Every slice window left out, with the reason |
| `cases/pipeline.tsv` | The 12 pipeline cases: case, plan, task, base commit and fix rounds |
| `cases/reviews/cases.json` | The ten review cases |
| `cases/reviews/<case>.md` | The known defects of one review case, one `## D<n>:` heading each |
| `results/results.tsv` | One line per run |
| `results/pipeline.tsv` | One line per pipeline run: `rep, case, arm, run, outcome, costUsd, seconds, dispatches, fixRounds, detail`; `arm` is `<label>@<ref7>` |
| `results/review-grades.tsv` | One line per rubric defect per graded review |

Snapshots and transcripts go to `~/.cache/dr-tier-eval`, outside the
repository, under `rep<N>/<case>/<arm>/`.

The pipeline stage materialises each arm's repository tree under `~/.cache/dr-tier-eval/pipeline/rep<N>/arms/<ref7>` and runs one `claude -p --plugin-dir <arm>/plugins/dforge` session per cell in a clone of the case's base commit. Each run has its own HOME, XDG directories, `CLAUDE_CONFIG_DIR` and `TMPDIR` beneath that root. The environment keeps the host's `ANTHROPIC_*` variables and `CLAUDE_CODE_OAUTH_TOKEN`, and the run's config directory receives a copy of the session's `.credentials.json` and nothing else, so the run is logged in but reads none of the owner's settings or plugins. No git worktree is created.
