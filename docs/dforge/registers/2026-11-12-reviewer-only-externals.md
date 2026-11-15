# Reviewer-only external models

**Source:** owner request in session, 2026-11-12
**Covers:** docs/dforge/specs/2026-11-12-reviewer-only-externals-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | retire the agy lane | docs/dforge/plans/2026-11-13-reviewer-only-externals.md | A10 and no lane runner remains (Task 3 lanes test) | done | - |
| 2 | retire the codex lane | docs/dforge/plans/2026-11-13-reviewer-only-externals.md | A10 and no lane runner remains (Task 3 lanes test) | done | - |
| 3 | only keep them as reviewer for argon, agy opus, codex astra, codex 6.1 sol | docs/dforge/plans/2026-11-13-reviewer-only-externals.md | A1-A3, A6, A7, A16, A17 | done | - |
| 4 | Update the cockpit as well | docs/dforge/plans/2026-11-13-reviewer-only-externals.md | A11, A12 | done | - |
| 5 | run the reviewer parallel depends on the risk of task automatically, skip that reviewer if it's not available at the runtime | docs/dforge/plans/2026-11-13-reviewer-only-externals.md | A1, A4, A5, A13-A15 | done | - |
| 6 | existing Executor lines: Ignore with a warning | docs/dforge/plans/2026-11-13-reviewer-only-externals.md | A9 | done | - |
| 7 | agy review switch: Off, like Codex | docs/dforge/plans/2026-11-13-reviewer-only-externals.md | A8, A11 | done | - |
| 8 | Turn agy review on: one owner-consented gemini-4-argon run with a command-free prompt, plus an Opus run, both status=OK with no evidence=wrote, then set trust.review pass in reference/agy-policy.json | - | - | done | 2026-11-15, agy 1.5.9: Argon light and Opus heavy runs both status=OK evidence=none, schema-valid; trust.review pass, min_version 1.5.9; agyReview set on |
| 9 | external-review.md: a final-review-panel-tree left by a crashed run makes git worktree add fail, with no recovery step in the doc | - | - | done | external-review.md's panel block clears a leftover tree first; final-review.md points to it (173d4eae) |
| 10 | run-agy-review.sh: rev-parse --path-format needs git 2.31 (the README's stated floor); on older git every agy review fails error with nothing naming the git version | - | - | done | run-agy-review.sh fails reason=git naming the version found, with a test (540167a3) |
| 11 | review-route.test.sh:725: the fenced-Executor test and the real-Executor-line test are redundant (deferred: test-simplifier) | - | - | deferred | final review DEFERRED to dforge:test-simplifier |
| 12 | agy write check known limits: refs other than HEAD and the stash, git-ignored files and the --add-dir directory are not compared; an inactive includeIf target is unseen; hooks named outside core.hooksPath are not followed; on Git Bash the symlink and exec-bit cases are skipped | - | - | deferred | final review ruling: left as limits; plan mode denying shell commands is the primary guard |
