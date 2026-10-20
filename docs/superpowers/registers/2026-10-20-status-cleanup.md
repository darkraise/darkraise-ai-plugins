# Status clean-up

**Source:** owner request 2026-10-20, "I want to resolve all remaining items in one plan", after the project-status report's optional clean-ups
**Covers:** docs/superpowers/specs/2026-10-20-status-cleanup-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Push main to origin | - | - | n/a | owner ruling 2026-10-20: do not push; local main stays ahead of origin on purpose |
| 2 | Delete the three stale remote branches | docs/superpowers/plans/2026-10-20-status-cleanup.md | spec A1 | done | git ls-remote --heads origin lists only main; 34 branches deleted by one leased push, 3 stale tips kept as local archive tags |
| 3 | Delete the merged worktree-agent-* local branches | docs/superpowers/plans/2026-10-20-status-cleanup.md | spec A2 | done | 26 local branches deleted with git branch -d; git branch prints only main |
| 4 | Add the 21 old plans to completed.md so future status checks stop flagging them | docs/superpowers/plans/2026-10-20-status-cleanup.md | spec A3, A4 | done | commits 37c531e and a4e1062; none of the 21 plans was left out; check lines=21 bad=0 |
| 5 | CLAUDE.md has no Compact Instructions section | - | - | n/a | owner ruling 2026-10-20: skip the Compact Instructions section |
| 6 | Delete the filter-branch backup ref refs/original/refs/heads/feat/darkmem-sync-client | docs/superpowers/plans/2026-10-20-status-cleanup.md | spec A1 | done | refs/original deleted with old value ae3141e; git for-each-ref refs/original prints nothing |
