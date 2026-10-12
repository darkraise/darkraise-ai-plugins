# dr-forge settings revamp and workflow controls

**Source:** owner request, 2026-10-12 session: "revamp the settings UI of forge plugin, also add more settings to control the workflow and development progress of plugin"; inherits rows 3-11, 19 and 20 of docs/superpowers/registers/2026-10-11-dr-forge.md, deferred there to this spec
**Covers:** docs/superpowers/specs/2026-10-12-dr-forge-settings-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | revamp the settings UI of forge plugin | docs/superpowers/plans/2026-10-12-dr-forge-settings.md | claude plugin test plugins/dr-forge passes with the tabbed view; owner confirms the pane by hand (spec Verification step 5) | doing | - |
| 2 | add more settings to control the workflow and development progress of plugin | docs/superpowers/plans/2026-10-12-dr-forge-settings.md | node scripts/test-all.mjs passes; forge-config get --json lists the 14 new keys; each is enforced as the spec's Enforcement section says | doing | - |
| 3 | Worktree default | docs/superpowers/plans/2026-10-12-dr-forge-settings.md | forge-config set worktree always shows in forge-config workflow; using-git-worktrees names the setting (tests/settings-skills.test.sh) | doing | - |
