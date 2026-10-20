# Housekeeping carry-over

**Source:** housekeeping 2026-10-21; items recorded only in gitignored handoff notes (`.superpowers/handoff/2026-10-16-dr-forge-findings.md` "Adjacent, not fixed", and the 2026-10-18 cockpit handoff cited by `docs/superpowers/plans/2026-10-17-cockpit-native-desktop.md`), carried here before those notes were deleted
**Covers:** -

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | `plugins/dforge/scripts/lib/auto-run.sh` writes the state `.gitignore` with `[ -f … ] \|\| printf '*\n' >`, which writes through a dangling symbolic link planted at that path | - | - | open | same pattern fe095c9 fixed in `dforge_self_ignore` (`scripts/lib/dforge-dir.sh`: refuse links, `set -C`) |
| 2 | `plugins/dforge/scripts/finish-choice` (no-plan branch) overwrites `<state>/sdd/.gitignore` unconditionally with `printf '*\n' >`, following a planted symbolic link | - | - | open | same fix as row 1; `dforge_self_ignore` already exists for it |
| 3 | cockpit: the `ui.render` hook for `ToolProgress` in `plugins/dforge/hooks/cockpit/register.tsx` awaits `endWait`, whose `setActivity` writes state during render; the engine throws `state.set: denied … while ui.render is being dispatched` | - | - | open | reported in the 2026-10-18 cockpit handoff; code unchanged since (last touched 0c3ab53, which did not change this path) |
