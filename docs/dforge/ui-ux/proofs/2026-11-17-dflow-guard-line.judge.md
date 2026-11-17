## Verdict
verdict: ship bc488cb026818f4a
scores: coverage 18 / fidelity 18 / states 17 / deviations 18

## Evidence opened

All six captures under .dforge/ui-ux/2026-11-17-dflow-guard-line/ were read as text: band-200x60, band-120x40, hud-command-200x60, no-conflict-200x60, no-conflict-hud-command-200x60, no-conflict-120x40. Also read: plugins/dflow/hooks/hud/register.test.tsx (lines 820-893), plugins/dflow/tests/hud.test.mjs (guard line test), register.tsx (guardNow, command.run, AbovePrompt and Pane hooks), the suite log (lines 7587-7593), and the stand-down marker directory.

## Per item

- UI-1: proven. band-200x60 shows one yellow (38;5;220) row, `dflow@darkraise, dforge@darkraise are enabled together; run node /root/repositories/darkraise-ai-plugins/plugins/dflow/scripts/workflow-guard.mjs --host claude`, with only the engine's `[-]` control beside it. There is no frame, pane or resume offer. The test asserts the band's and the pane's Text lists each equal `[line]`. The SessionStart block above names both plugins.
- UX-1: proven. In hud-command-200x60, `/dflow:hud` answers `⎿ dflow: <same line>`, no pane opens, and the band keeps only the line. register.tsx returns `{ text: conflict }` from command.run. The test starts with a stored pane mode, and `expect(w.calls).not.toContain('open dflow-hud')` holds.
- UX-2: proven. The line names both plugin ids and the absolute check path. The SessionStart block in the same capture lists `claude plugin disable dflow@darkraise --scope local` and the local then user commands for dforge. hud.test.mjs asserts the exact guardLine text and null for no conflict or a null result. The marker file `13017d90-2c2e-4cb0-bc15-681d42831db6` exists under the walk's workflow-guard directory.
- UX-3: proven. no-conflict-200x60 and no-conflict-120x40 show the framed band (config, folder, branch, account) and no guard text. no-conflict-hud-command-200x60 shows `dflow: dflow HUD: pane` and the docked pane with its cards: Account, Plan, Context, Usage, Board, Repo and Next. The test "with no conflict the HUD draws as before" asserts band-expand and band-line-0.
- OP-1: proven. At 200x60 the line is one row. At 120x40 it wraps after `run node ` onto a second row and every word is present. The no-conflict state is also captured at both viewports.
- OP-2: proven. The line is plain words and its only colour is the yellow foreground (`<Text color="yellow">` in register.tsx; 38;5;220 in the capture).
- OP-3: proven by the test. It records every `$.process.run` call, advances the clock 130 s, and asserts that no call other than the guard's occurred. The suite log shows the test passing (line 7587) and "Finished plugin test plugins/dflow ... (exit 0)", 41 pass and 0 fail. The report's claim of a mutation run is not independently shown, but the assertion is real and sufficient.

## Notes (not disputes)

- The walk loaded only dflow's half of the conflict. The report states this and points to the dforge report.
- No pointer or hover states exist, since the line has no control. The report states this.
- No row is marked deviation, and none of my own findings is a deviation from the contract.

## Disputed items

None.

Verdict: ship bc488cb026818f4a
