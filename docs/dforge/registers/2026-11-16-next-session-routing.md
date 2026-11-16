# Next-session routing

**Source:** owner bug report 2026-11-16 (two items, owner's words), plus the Fable review of the fix proposal (.dforge/handoff-routing-fix-review-report.md, 2026-11-16)
**Covers:** docs/dforge/specs/2026-11-16-next-session-routing-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | handoff promt show wrong state of current progress, so it often give promt to write plan but the plan already exists, ask to finish the branch but branch already merge, any many other cases | docs/dforge/plans/2026-11-16-next-session-routing.md | A1, A6, A10, A12 | doing | - |
| 2 | Not show next session promt when the plan not finish, especially when the controller agent is sonnet | docs/dforge/plans/2026-11-16-next-session-routing.md | A15, A16, A17, A20 | doing | - |
| 3 | next-step's register router sends a row assigned to a spec to writing-plans without checking for existing plans (darkpanel: write its plan for a spec with 25 plans); project-status rule 6 copies it | docs/dforge/plans/2026-11-16-next-session-routing.md | A1-A5, A23, A24 | doing | - |
| 4 | the cockpit resume band replays latest.md for three days and never checks repository state; its age is the file mtime, so a notes edit restarts the window and voids a dismissal | docs/dforge/plans/2026-11-16-next-session-routing.md | A12, A13 | doing | - |
| 5 | plain next-step PLAN_FILE ignores completed.md and reads only the cwd checkout's ledger (0 of N, Start at Task 1 for a merged plan or one half done in another worktree) | docs/dforge/plans/2026-11-16-next-session-routing.md | A8, A9 | doing | - |
| 6 | closing-a-milestone's stops (step 2, step 6 GAP, step 9) end without a next-session block, and the handoff skill has no form for between plans on a roadmap project (only model-written --adhoc) | docs/dforge/plans/2026-11-16-next-session-routing.md | A7, A20 | doing | - |
| 7 | a finishing turn that skips Step 7 is never held: the ledger is deleted, or the hook's cwd is a removed worktree (turn-end.sh exits at git -C cwd) | docs/dforge/plans/2026-11-16-next-session-routing.md | A15 | doing | - |
| 8 | the Stop hook checks the message for a ## Next session substring, never latest.md: a hand-typed block passes and latest.md stays stale | docs/dforge/plans/2026-11-16-next-session-routing.md | A17, A29 | doing | - |
| 9 | readers trust the stored Next line: resume-execution continues with latest.md's Next line, repo-audit prints it with only a commit-count caveat | docs/dforge/plans/2026-11-16-next-session-routing.md | A14, A20 | doing | - |
| 10 | finishing runs roadmap settle only for the plan's own spec, never the programme spec, and settle is all-or-nothing per spec across milestones, so programme epic rows never settle | docs/dforge/plans/2026-11-16-next-session-routing.md | A21, A30, A31 | doing | - |
| 11 | darkmem progress: a --complete/--kept latest.md has no ## State, so the checkpoint push refuses it; a pulled file gets a fresh mtime the band reads as the handoff time (inference) | docs/dforge/plans/2026-11-16-next-session-routing.md | A22 | doing | - |
| 12 | Codex: a milestone close is not an early stop, so nothing tells a Codex session to print the next-step block there | docs/dforge/plans/2026-11-16-next-session-routing.md | A20 | doing | - |
| 13 | the Stop hook misses a ledger in a worktree when the hook's cwd is the primary checkout (premise unconfirmed) | - | - | deferred | Fable spec review 2026-11-16: build only after one logged stop whose hook cwd differs from the ledger's worktree; match only task-brief/task-step/task-close/next-step Bash calls naming the plan |
