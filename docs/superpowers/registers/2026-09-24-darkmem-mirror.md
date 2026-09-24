# darkmem mirror for dr-superpowers

**Source:** darkmem register `docs/superpowers/registers/2026-09-23-work-log-lane.md` rows #3 ("they usually come with ledger and progress tracking documents") and #5 ("integrate with dr-superpowers to store the documents and progress tracking, reduce the repo pollution"), owner requests 2026-09-23
**Covers:** docs/superpowers/specs/2026-09-23-darkmem-mirror-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | darkmem-sync: config and modes, the mirror, pull, push, status and import over darkmem's keyed REST surface (spec §1, §3, §7) | docs/superpowers/plans/2026-09-24-darkmem-sync-client.md | tests/darkmem-sync.test.sh green; validate-repository and claude plugin validate pass; local mode unchanged | doing | - |
| 2 | Resolve every docs/superpowers and .superpowers reference through sp_docs_root / sp_work_root, including how a plan outside the repository is identified (spec §2) | - | - | open | needs a ruling: plan_require_same_repo, ledger identity lines, register Covers paths and plans/completed.md assume repository-relative plan paths |
| 3 | Run pull at SessionStart and push at the skills' stop points, with a Stop hook as the Claude Code safety net (spec §4) | - | - | open | - |
| 4 | Skills record durable facts with memory_add at task-complete and handoff (spec §5) | - | - | open | - |
| 5 | Move a repository into darkmem: mapping, import, round-trip check, delete docs/superpowers in its own commit; darkmem's CLAUDE.md citations first (spec §6) | - | - | open | owner-run, after rows 1-3 land and darkmem increment 1 is deployed |
