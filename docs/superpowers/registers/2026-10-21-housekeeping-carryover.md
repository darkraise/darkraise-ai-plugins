# Housekeeping carry-over

**Source:** housekeeping 2026-10-21; items recorded only in gitignored handoff notes (`.superpowers/handoff/2026-10-16-dr-forge-findings.md` "Adjacent, not fixed", and the 2026-10-18 cockpit handoff cited by `docs/superpowers/plans/2026-10-17-cockpit-native-desktop.md`), carried here before those notes were deleted
**Covers:** -

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | `plugins/dforge/scripts/lib/auto-run.sh` writes the state `.gitignore` with `[ -f … ] \|\| printf '*\n' >`, which writes through a dangling symbolic link planted at that path | - | - | done | 061b03d: `ar_start` calls `dforge_self_ignore`; `tests/auto-run.test.sh` "start: linked ignore never written through" |
| 2 | `plugins/dforge/scripts/finish-choice` (no-plan branch) overwrites `<state>/sdd/.gitignore` unconditionally with `printf '*\n' >`, following a planted symbolic link | - | - | done | 061b03d: the no-plan branch calls `dforge_self_ignore`, keeping an existing ignore; `tests/finish-choice.test.sh` pins both |
| 3 | cockpit: the `ui.render` hook for `ToolProgress` in `plugins/dforge/hooks/cockpit/register.tsx` awaits `endWait`, whose `setActivity` writes state during render; the engine throws `state.set: denied … while ui.render is being dispatched` | - | - | done | abeef74: the hook settles the wait on `$.clock.after(0, …)`; `tests/cockpit.test.ts` "the background pill under an approved call settles its wait after the draw" reproduced the denial before the fix |
