# UI proof: dflow HUD guard line

**Contract:** touch
**Fingerprint:** bc488cb026818f4a
**Platform:** terminal
**Viewports:** 200x60, 120x40
**Themes:** default
**Evidence:** local
**Judge:** ship bc488cb026818f4a — docs/dforge/ui-ux/proofs/2026-11-17-dflow-guard-line.judge.md

## Delta

**UI/UX depth:** touch — one line on the dflow HUD's surfaces (`plugins/dflow/hooks/hud/register.tsx`, `band.mjs`) while another workflow plugin is enabled beside dflow; with no conflict nothing drawn changes

- **UI-1** — With dflow and dforge both enabled, the band above the prompt draws one line, `dflow@darkraise, dforge@darkraise are enabled together; run node <plugin root>/scripts/workflow-guard.mjs --host claude`, and no other HUD row: no framed band, no pane, no resume offer.
- **UX-1** — Under the conflict `/dflow:hud` answers with the same line and opens nothing.
- **UX-2** — The line names the plugins that collide and the exact command to run for the details; the SessionStart block above it carries the disable commands.
- **UX-3** — With dforge disabled the HUD draws as before: the framed band above the prompt, `/dflow:hud` answers `dflow HUD: pane` and docks the pane, and no guard line appears.
- **OP-1** — Proven at 200x60 and 120x40, default theme; at 120x40 the line wraps onto two rows and stays whole.
- **OP-2** — The line reads without colour: its meaning is all in its words, and the colour (yellow) is emphasis only.
- **OP-3** — Under the conflict the HUD runs no command but the guard check, before and after its poll interval.

## Results

| ID | Verdict | Evidence | Note |
|---|---|---|---|
| UI-1 | pass | .dforge/ui-ux/2026-11-17-dflow-guard-line/band-200x60.ansi, .dforge/ui-ux/2026-11-17-dflow-guard-line/band-120x40.ansi; test "under a conflict the HUD draws the guard line alone and runs nothing else" | Above the prompt the capture holds only the guard line (and the engine's own `[-]` collapse control); the transcript above holds the SessionStart conflict block naming `dflow@darkraise (this session), dforge@darkraise (user)`. The test asserts the band's and the pane's Text lists each equal `[guardLine(...)]` exactly |
| UX-1 | pass | .dforge/ui-ux/2026-11-17-dflow-guard-line/hud-command-200x60.ansi; test "under a conflict the HUD draws the guard line alone and runs nothing else" | `/dflow:hud` + Enter drew `⎿ dflow: dflow@darkraise, dforge@darkraise are enabled together; run node …/plugins/dflow/scripts/workflow-guard.mjs --host claude`; no pane opened and the band still held the line alone. The test, started with a stored pane mode, records no `open dflow-hud` |
| UX-2 | pass | .dforge/ui-ux/2026-11-17-dflow-guard-line/band-200x60.ansi; test "the HUD guard line names the active plugins and the check, only on a conflict" | The line names both plugin ids and the absolute path of the check; the block above lists `claude plugin disable dflow@darkraise --scope local` and, for dforge, the local then the user command. The session's stand-down marker appeared under the scratch config's `plugins/data/dflow-inline/workflow-guard/` |
| UX-3 | pass | .dforge/ui-ux/2026-11-17-dflow-guard-line/no-conflict-200x60.ansi, .dforge/ui-ux/2026-11-17-dflow-guard-line/no-conflict-hud-command-200x60.ansi, .dforge/ui-ux/2026-11-17-dflow-guard-line/no-conflict-120x40.ansi; test "with no conflict the HUD draws as before" | Same scratch repository with `dforge@darkraise: false`: the framed band showed the account, folder and branch; `/dflow:hud` answered `dflow HUD: pane` and docked the pane with its cards; no capture holds `enabled together` |
| OP-1 | pass | .dforge/ui-ux/2026-11-17-dflow-guard-line/band-120x40.ansi, .dforge/ui-ux/2026-11-17-dflow-guard-line/band-200x60.ansi | 200x60: one row. 120x40: the line wraps after `run node` onto a second row, every word present |
| OP-2 | pass | .dforge/ui-ux/2026-11-17-dflow-guard-line/band-200x60.ansi | The line's only colour is a yellow foreground; no state depends on it |
| OP-3 | pass | test "under a conflict the HUD draws the guard line alone and runs nothing else" | The test records every `$.process.run` call, advances the clock 130 s (past the 2 s poll and the 10 s git reads) and asserts no call but the guard's. With the guard's answer forced to no conflict the test fails (mutation run) |

## Automated checks

- Walked on 2026-11-17 on Claude Code 2.1.326 in tmux (a throwaway HOME and `CLAUDE_CONFIG_DIR`, a dummy API key, `installed_plugins.json` recording dforge@darkraise at user scope, `settings.json` enabling it, a scratch repository set up with `dflow init` and `dflow status`, and `--plugin-dir plugins/dflow` at 73ed2f2f). No model turn was needed. Re-walked after the final review's fix wave (6b2af58a: a check that timed out or failed to start is asked again rather than cached), which does not change what a check that answers draws; every capture was taken again, each tmux window pinned to its size (`window-size manual`, `resize-window`).
- `claude plugin test plugins/dflow`: 41 pass, 0 fail, the two guard tests among them; `node --test plugins/dflow/tests/*.test.mjs`: 130 pass, the guard line test among them.

## Not proven

- A pointer press is not exercised: tmux sends keys only, and the line has no control.
- The recorded dforge install was not loaded by the host (no marketplace copy), so only dflow's half of the conflict ran in the walk; dforge's half is proven in docs/dforge/ui-ux/proofs/2026-11-17-dforge-guard-line.md.
