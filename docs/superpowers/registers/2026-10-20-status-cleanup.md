# Status clean-up

**Source:** owner request 2026-10-20, "I want to resolve all remaining items in one plan", after the project-status report's optional clean-ups
**Covers:** docs/superpowers/specs/2026-10-20-status-cleanup-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Push main to origin | - | - | n/a | owner ruling 2026-10-20: do not push; local main stays ahead of origin on purpose |
| 2 | Delete the three stale remote branches | docs/superpowers/plans/2026-10-20-status-cleanup.md | spec A1 | planned | owner ruling 2026-10-20: widened to all 34 remote branches but main |
| 3 | Delete the merged worktree-agent-* local branches | docs/superpowers/plans/2026-10-20-status-cleanup.md | spec A2 | planned | owner ruling 2026-10-20: widened to all 26 local branches but main |
| 4 | Add the 21 old plans to completed.md so future status checks stop flagging them | docs/superpowers/plans/2026-10-20-status-cleanup.md | spec A3, A4 | planned | - |
| 5 | CLAUDE.md has no Compact Instructions section | - | - | n/a | owner ruling 2026-10-20: skip the Compact Instructions section |
| 6 | Delete the filter-branch backup ref refs/original/refs/heads/feat/darkmem-sync-client | docs/superpowers/plans/2026-10-20-status-cleanup.md | spec A1 | planned | Fable spec review finding 14; owner ruling 2026-10-20: delete |
