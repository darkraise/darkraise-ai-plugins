# Auto run: dflow-hud-overhaul

**Source:** items the auto run for `docs/dforge/specs/2026-11-13-dflow-hud-overhaul-design.md` deferred
**Covers:** docs/dforge/specs/2026-11-13-dflow-hud-overhaul-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Task 3: hudAtom shape tag not bumped when Hud gained fields | - | - | done | triage 2026-11-15: resolved during the plan (see the earlier note); closed |
| 2 | Task 4: collapsed atom keyed 'as any' without a PluginState entry | - | - | done | triage 2026-11-15: resolved during the plan (see the earlier note); closed |
| 3 | Task 9: density atom missing from PluginState | - | - | done | triage 2026-11-15: resolved during the plan (see the earlier note); closed |
| 4 | Task 9 parked: bar name clash between meter.mjs and view.mjs | - | - | done | triage 2026-11-15: resolved during the plan (see the earlier note); closed |
| 5 | Task 4: the mod test harness drops keys on Text elements | - | - | done | triage 2026-11-15: resolved during the plan (see the earlier note); closed |
| 6 | Task 5: the test fixture's session.compact stub returned no messages | - | - | done | triage 2026-11-15: resolved during the plan (see the earlier note); closed |
| 7 | Task 12: the host refuses a /-prefixed prompt.submit, so Resume runs /dflow:build as a command | - | - | done | triage 2026-11-15: resolved during the plan (see the earlier note); closed |
| 8 | Task 12: the engine refuses next(e) for a command.run with no args | - | - | done | triage 2026-11-15: resolved during the plan (see the earlier note); closed |
| 9 | Task 14: atoms outlive a reload, so a missing hud.json drew a stale Hud | - | - | done | triage 2026-11-15: resolved during the plan (see the earlier note); closed |
| 10 | claude plugin validate plugins/dflow warns TS7016 (no declaration file) for each .mjs the mod imports, and ICON_MISSING | - | - | done | TS7016 and TS7006: .d.mts declarations beside the five HUD modules; register.tsx validates clean. ICON_MISSING: won't fix; a directory-submission check dforge shares, a marketplace branding choice |
| 11 | Fix-wave follow-ups: the session-switch atom reset, the redraw on a changed reading and setMode's view reset have no assertion of their own; the switch reset writes atoms without an invalidate | - | - | done | three tests in register.test.tsx, each failing on its mutation; no invalidate added: read() in ui.render subscribes the drawing, so the reset's writes redraw |
| 12 | claude plugin validate warns TS2345 in register.test.tsx (38) and dforge's cockpit.test.ts: $.command.run test calls omit CommandRunInput's origin and presentation | - | - | done | dflow: the 38 calls go through a run() helper that builds a full CommandRunInput. dforge's 23 were not command.run calls: 22 mounted a BAND fixture missing AbovePrompt's isCollapsed, one passed a string-or-base64 fetch body to JSON.parse; fixed in cockpit.test.ts. Both plugins validate with no TS errors |
| 13 | AbovePrompt props carry isCollapsed, but neither dforge's band nor dflow's reads it (dforge's honours only hasSurvey) | - | - | done | no change needed: live check on Claude Code 2.1.325 — ctrl+x ctrl+a (abovePrompt:toggle) replaces the whole plugin panel with the host's 'plugin panel hidden' bar, so the bands never draw while collapsed |
