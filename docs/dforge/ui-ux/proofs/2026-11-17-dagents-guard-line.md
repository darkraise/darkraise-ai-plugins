# UI proof: dagents cockpit guard line

**Contract:** touch
**Fingerprint:** 9db6821dd90b35d3
**Platform:** terminal
**Viewports:** 200x60, 120x40
**Themes:** default
**Evidence:** local
**Judge:** ship 9db6821dd90b35d3 — docs/dforge/ui-ux/proofs/2026-11-17-dagents-guard-line.judge.md

## Delta

**UI/UX depth:** touch — one line on the dagents cockpit's surfaces (`plugins/dagents/hooks/cockpit/register.tsx`, `lib.ts`) while another workflow plugin is enabled beside dagents; with no conflict nothing drawn changes

- **UI-1** — With dagents and dforge both enabled, the band above the prompt draws one line, `dagents@darkraise, dforge@darkraise are enabled together; run node <plugin root>/scripts/workflow-guard.mjs --host claude`, and no other cockpit row: no pane, no framed band, no resume offer.
- **UX-1** — Under the conflict the cockpit registers no `/cockpit` command, so typing it gets the engine's own `Unknown command: /cockpit` and opens nothing.
- **UX-2** — The line names the plugins that collide and the exact command to run for the details; the SessionStart block above it (Task 21) carries the disable commands.
- **UX-3** — With dforge disabled the cockpit draws as before: the docked pane opens at session start, `/cockpit` answers `Cockpit pane opened.`, and no guard line appears.
- **OP-1** — Proven at 200x60 and 120x40, default theme; at 120x40 the line wraps onto two rows and stays whole.
- **OP-2** — The line reads without colour: its meaning is all in its words, and the colour (256-colour 220, yellow) is emphasis only.
- **OP-3** — Under the conflict the cockpit runs no command but the guard check, before and after its refresh interval.

## Results

| ID | Verdict | Evidence | Note |
|---|---|---|---|
| UI-1 | pass | .dforge/ui-ux/2026-11-17-dagents-guard-line/band-200x60.ansi, .dforge/ui-ux/2026-11-17-dagents-guard-line/band-120x40.ansi; test "the workflow guard > under a conflict the cockpit draws the guard line alone and runs nothing else" | Above the prompt the capture holds only the guard line (and the engine's own `[-]` collapse control and effort hint); the transcript above it holds the SessionStart conflict block. The test asserts the band's Text list equals `[guardLine(...)]` exactly |
| UX-1 | pass | .dforge/ui-ux/2026-11-17-dagents-guard-line/cockpit-command-200x60.ansi | `/cockpit` + Enter drew `● Unknown command: /cockpit`; the guard line stayed and no pane opened. The command is registered in session.start, which returns before it under a conflict |
| UX-2 | pass | .dforge/ui-ux/2026-11-17-dagents-guard-line/band-200x60.ansi; test "the guard line names the active plugins and the check, only on a conflict" | The line names both plugin ids and the absolute path of the check; running that check by hand (`--host claude --self dagents` against the walk's config) printed one line per active plugin and exit 3 |
| UX-3 | pass | .dforge/ui-ux/2026-11-17-dagents-guard-line/no-conflict-200x60.ansi, .dforge/ui-ux/2026-11-17-dagents-guard-line/no-conflict-cockpit-command-200x60.ansi, .dforge/ui-ux/2026-11-17-dagents-guard-line/no-conflict-120x40.ansi; test "the workflow guard > with no conflict the cockpit draws as before" | Same scratch config with `dforge@darkraise: false`: the guard printed `dagents@darkraise self`, exit 0; the docked pane showed its Context card; `/cockpit` answered `dagents: Cockpit pane opened.`; no capture holds `enabled together` |
| OP-1 | pass | .dforge/ui-ux/2026-11-17-dagents-guard-line/band-120x40.ansi, .dforge/ui-ux/2026-11-17-dagents-guard-line/band-200x60.ansi | 200x60: one row. 120x40: the line wraps after `run node` onto a second row, every word present |
| OP-2 | pass | .dforge/ui-ux/2026-11-17-dagents-guard-line/band-200x60.ansi | The line's only SGR is `38;5;220` (foreground yellow) and the reset; no state depends on it |
| OP-3 | pass | test "the workflow guard > under a conflict the cockpit draws the guard line alone and runs nothing else" | The test records every `$.process.run` call, advances the clock 130 s (past the 2 s poll and the 60 s watchdog) and asserts no call but the guard's. With the guard's answer forced to no conflict the test fails (mutation run) |

## Automated checks

- Walked on 2026-11-17 on Claude Code 2.1.326 in tmux (a throwaway HOME and `CLAUDE_CONFIG_DIR` under the scratch directory, a dummy API key, `installed_plugins.json` recording dforge@darkraise at user scope, `settings.json` enabling it, and `--plugin-dir plugins/dagents` from the uncommitted working tree). No model turn was needed.
- `claude plugin test plugins/dagents`: 616 pass, 0 fail (5 files), the three guard tests among them.
- `ui-lint` on the two changed files: only the two raw-colour findings at lines that predate this change (`#ffaf5f` turns-left text and its sibling).

## Not proven

- A pointer press is not exercised: tmux sends keys only, and the line has no control.
- The walk used dforge 4.17.1's install record without its hooks loaded, so only dagents' half of the conflict ran; dforge's own stand-down is Task 23 and 24.
