## Verdict
verdict: ship e99527a131618d7d
scores: coverage 18 / fidelity 18 / states 16 / deviations 18

Disputed items: 0.

## What I opened

All six captures under .dforge/ui-ux/2026-11-17-dflow-guard-line/ (read as ANSI text): band-200x60, band-120x40, hud-command-200x60, no-conflict-200x60, no-conflict-hud-command-200x60, no-conflict-120x40. Also register.test.tsx (the world mock, lines 85-175, and the two guard tests at 860-893), hud.test.mjs (the guardLine test at 409-413), register.tsx (guardNow, standsDown, every hook, both ui.render handlers) and band.mjs (guardLine).

## Per item

| ID | Judged | What I saw |
|---|---|---|
| UI-1 | proven | band-200x60 row 55 holds one yellow (38;5;220) line, `dflow@darkraise, dforge@darkraise are enabled together; run node /root/.../plugins/dflow/scripts/workflow-guard.mjs --host claude`, plus the host's own `[-]` collapse control. No rounded frame, no pane, no resume row anywhere in the capture. Code: the AbovePrompt handler returns only `<Text color="yellow">{conflict}</Text>` before reading the HUD atom, so no band, offer or warning can draw. The test asserts the band's and the pane's Text lists equal `[line]` exactly. The `[-]` control belongs to the host and the report names it. |
| UX-1 | proven | hud-command-200x60 and band-120x40 both show `/dflow:hud` answered with `dflow: <the same line>`; no pane appears and the band still holds the line alone. Code: the command.run handler returns `{ text: conflict }` before any mode change. The test, started with stored mode `pane`, asserts the answer equals the line and `w.calls` has no `open dflow-hud`. |
| UX-2 | proven | The line names both plugin ids and the absolute check path. The SessionStart block above it in every conflict capture lists `claude plugin disable dflow@darkraise --scope local` and, for dforge, the local then user commands. The hud.test.mjs guardLine test pins the exact string. The report's claim about a stand-down marker file has no cited capture, but the contract item does not need it. |
| UX-3 | proven | no-conflict-200x60 shows the framed band (`╭─ config ... Remote ○ not connected ... Expand ─╮`, folder, `⎇ main`, model, `$0.00`). no-conflict-hud-command-200x60 shows `dflow: dflow HUD: pane` with the pane docked (Account, Plan, Context, Usage, Board, Repo cards). No `enabled together` text in any no-conflict capture. The test "with no conflict the HUD draws as before" finds `band-expand` and `band-line-0` containing `dflow 4/7 · Task 5`. |
| OP-1 | proven | 200x60 is one row. In band-120x40 the line wraps after `run node ` onto a second row (rows 34-35) with every word present, including `--host claude`. |
| OP-2 | proven | The only colour on the line is the yellow foreground. The words carry the full meaning: which plugins, what is wrong, what to run. |
| OP-3 | proven by test | The test records every process.run. After `advance(130_000)` the only command is the one matching the guard regex. register.tsx confirms why: session.start stands down before `$.clock.every` is set, and turn.complete, turn.step, attach, detach and dflow:build all return `next(e)` first. The report's "mutation run" claim is not verifiable from what I read; it is not needed for the verdict. |

## Criteria

- coverage (18): every Delta item has a row with evidence I opened that shows it. Captures and tests agree with the report's notes.
- fidelity (18): copy matches the contract exactly (`<ids> are enabled together; run node <root>/scripts/workflow-guard.mjs --host claude`). It is a plain Text in yellow, with no new component. The no-conflict band matches the existing framed design.
- states (16): the conflict state and the no-conflict state are both shown, the command is shown under both, and 200x60 and 120x40 are both captured. The guard-error state (null result gives no line) is covered by the guardLine unit test. Gaps: the no-conflict band is captured only at 200x60. The no-conflict 120x40 capture shows the docked pane, not the band, and its pane is clipped after the Repo card. The test mock never returns a guard failure through register.tsx, so the `() => guardLine(null, ...)` rejection path is covered only through guardLine itself. The report states that no pointer press was exercised, and the line has no control.
- deviations (18): the report lists no deviations and I found none. Differences from the plain HUD under a conflict are the contract's own.

## Disputed items

None.

Verdict: ship e99527a131618d7d
