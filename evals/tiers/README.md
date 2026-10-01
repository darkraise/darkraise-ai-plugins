# Tier evaluation harness

Measures whether a dr-superpowers assignment row or review seat can move to a
cheaper agent, by replaying this repository's own plan history. The design,
the grading and the decision rules are in
`docs/superpowers/specs/2026-10-01-dr-superpowers-tier-eval-design.md`.

Only `run-grid.mjs`, `run-case.mjs` and `grade-review.mjs` call a model. They
run `claude -p`, which draws on the Claude subscription's usage limits.
Everything else, including the tests, is free. POSIX only.

## Commands

Run them from the repository root.

| Command | What it does |
|---|---|
| `node evals/tiers/build-manifest.mjs` | Enumerates eligible tasks, golden-checks each, writes `cases/manifest.tsv` and `cases/excluded.tsv` |
| `node evals/tiers/build-case.mjs CASE_ID DIR` | Builds one case's snapshot, brief and prompt, for inspection |
| `node evals/tiers/run-grid.mjs --stage STAGE [--rep N] [--minutes M] [--pass P]` | Runs the unscored cells of `smoke`, `written`, `stripped` or `review`, two at a time; `--minutes` stops starting cells after M minutes; `--pass` grades every review again as passes P and P + 1 |
| `node evals/tiers/run-case.mjs CASE_ID ARM [--rep N]` | Runs and grades one cell |
| `node evals/tiers/run-case.mjs CASE_ID ARM [--rep N] --exclude REASON` | Runs nothing: takes the case out of the repetition for every arm, with the reason |
| `node evals/tiers/grade-case.mjs RUN_DIR` | Re-grades a finished implementation run |
| `node evals/tiers/grade-review.mjs CASE_ID ARM [--rep N] [--pass P]` | Grades one review against its rubric |
| `node evals/tiers/report.mjs [--rep N] [--pass P]` | Prints the decision table, reading review grades of pass P |
| `node --test evals/tiers/tests/*.test.mjs` | The harness tests, against a stub `claude` |

`run-grid.mjs` exits 0 when the stage is complete, 3 when it stopped at a
rate limit, at the spend cap or at `--minutes`, 1 when cells remain after harness errors, and
2 when `plugins/dr-superpowers` differs from the manifest's start commit.
Run the same command again to resume: a cell with a scored row is skipped.

## Files

| Path | Holds |
|---|---|
| `arms.json` | The agents each row and the review seat are compared on, current agent first |
| `cases/manifest.tsv` | The implementation cases; its first line pins the start commit |
| `cases/excluded.tsv` | Every task left out, with the reason |
| `cases/reviews/cases.json` | The ten review cases |
| `cases/reviews/<case>.md` | The known defects of one review case, one `## D<n>:` heading each |
| `results/results.tsv` | One line per run |
| `results/review-grades.tsv` | One line per rubric defect per graded review |

Snapshots and transcripts go to `~/.cache/dr-tier-eval`, outside the
repository, under `rep<N>/<case>/<arm>/`.
