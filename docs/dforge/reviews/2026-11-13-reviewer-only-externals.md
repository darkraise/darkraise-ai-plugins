# Review record: 2026-11-13-reviewer-only-externals

Plan: docs/dforge/plans/2026-11-13-reviewer-only-externals.md
Retained: 2026-11-13

Review depth: full (task-risk:9)
Acceptance QA: complete — 17 pass, 0 fail, 0 flaky, 0 cannot-test, 1 demo
Final review: minor (deferred): plugins/dforge/reference/external-review.md:136 — a final-review-panel-tree left by a crashed run makes `git worktree add` fail, with no recovery step in the doc
Final review: minor (deferred): plugins/dforge/scripts/run-agy-review.sh:186 — `rev-parse --path-format` needs git 2.31 (the README's stated floor); on older git every agy review fails `error` with nothing naming the git version
Final review: residual R1 (external-review.md:76 restore rule cannot undo hook, config or stash changes) sent to the ruling seat as final-residual
Final review: clean (commits 5bb5545..e48eeaf)
