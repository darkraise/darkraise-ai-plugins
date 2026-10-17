# dforge rename

**Source:** owner request, 2026-10-17 session; depth answer "Everything named forge"; names answer "dforge, including internals"; darkmem answer "Rename to dforge/"; migrate answer "Whole layout"; approach answer "Clean break"; execution answer "Sequential"; active-plans answer "Rewrite prefixes"
**Covers:** docs/superpowers/specs/2026-10-17-dforge-rename-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Rename dr-forge to dforge | docs/superpowers/plans/2026-10-17-dforge-rename.md | dforge 4.0.0 in both catalogs and manifests; validator with the dr-forge guard, all suites, plugin validate and plugin test pass (spec acceptance 1-3, 6) | planned | - |
| 2 | Add migrate skill to migrate old active dr-superpowers docs to new dr-forge. | docs/superpowers/plans/2026-10-17-dforge-rename.md | /dforge:migrate over dforge-migrate moves a dr-forge or dr-superpowers repo, worktree and home; --dry-run changes nothing (spec acceptance 4-5) | planned | - |
| 3 | Rename all dcc-* plugins and skills to its plain name (without dcc-) | docs/superpowers/plans/2026-10-17-dforge-rename.md | Both catalogs list darkraise-ui and darkraise-win32ui 0.3.0; no dcc-darkraise outside docs/superpowers and docs/migration.md (spec acceptance 1-2) | planned | - |
