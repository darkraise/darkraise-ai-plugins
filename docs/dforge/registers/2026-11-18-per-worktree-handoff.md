# Per-worktree handoff

**Source:** the owner's request of 2026-11-18 in the session that merged fix/open-bugs-and-rulings
**Covers:** docs/dforge/specs/2026-11-18-per-worktree-handoff-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | the handoff file is shared across all worktree, this will block the ability to work in parallel using multiple sessions. I want that each worktree will keep its own handoff file | docs/dforge/plans/2026-11-18-per-worktree-handoff.md | A1, A2, A3, A6, A12, A14 | doing | - |
| 2 | the promt after handoff (which tell what should do in next session) will point to correct handoff file | docs/dforge/plans/2026-11-18-per-worktree-handoff.md | A5, A13, A17 | doing | - |
| 3 | include the worktree to use | docs/dforge/plans/2026-11-18-per-worktree-handoff.md | A4, A5 | doing | - |
| 4 | tests/{dforge,dagents}/next-step.test.sh "worktree: handoff written in the worktree" and "worktree: no handoff in the primary" are covered by A2 | - | - | deferred | final review: for dforge:test-simplifier |
| 5 | next-step --print --latest on a marker-less latest.md reports "no ledger at <path>" though the ledger exists | - | - | deferred | final review Minor: predates this branch (main prints the same) |
| 6 | SessionStart count line reads "1 other checkouts hold a handoff" for one checkout | - | - | deferred | final review Minor: C9's verbatim wording; a singular form needs a spec change |
