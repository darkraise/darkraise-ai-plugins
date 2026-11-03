# Auto run: antigravity-executor-lane

**Source:** items the auto run for `docs/dforge/specs/2026-11-02-antigravity-executor-lane-design.md` deferred
**Covers:** docs/dforge/specs/2026-11-02-antigravity-executor-lane-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | run-agy-task.sh ref guard compares every ref of the shared repository, so another worktree, a fetch or a session stash blocks a running task until a user-approved baseline | PR 40 | - | done | ruled 2026-11-03 (spec amendment): block only own HEAD, index, branch, per-worktree refs, own-branch stash entries, deleted refs or stash entries, tags and non-descendant moves; other ref changes reported, refs/remotes ignored; CI run 41571183633 green |
| 2 | On Windows an interrupt does not reach a native agy.exe (run-agy-task.sh cleanup kill -TERM on the group) | - | - | deferred | final review PARK: task is left blocked; follow-up on a Windows host: taskkill on the pid in /proc/$agy_pid/winpid with a Windows-shard test |
| 3 | run-agy-task.sh:349 stderr-tail quota classification can match a quota or rate limit word in unrelated stderr and turn agy off for the session | PR 40 | - | done | ruled 2026-11-03 (spec amendment): a stderr-only quota match gives reason=quota without marking the lane off; .error and non-JSON stdout still mark it off; CI run 41571183633 green |
| 4 | antigravity-executor-lane.acceptance.test.sh: A5, the A2 base comparison and the A14 history checks skip on CI's depth-1 checkout, and the file's Windows cost against its 250 s shard weight is unmeasured | PR 40 | - | done | ruled 2026-11-03: depth-1 skips accepted (provenance checks against a fixed BASE, as speed-and-cost and review-depth-qa); Windows cost measured in run 41571183633: 238 s against weight 250 and limit 600 |
