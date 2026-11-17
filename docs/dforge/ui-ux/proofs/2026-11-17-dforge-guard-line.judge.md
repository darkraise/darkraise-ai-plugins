## Verdict
verdict: ship 725607f44d838649
scores: coverage 18 / fidelity 18 / states 17 / deviations 18

## Evidence opened

All six captures were read as text. I also read the three tests (guardLine unit test, "under a conflict ..." and "with no conflict ..."), `guardNow` and `standsDown` in register.tsx, and `guardLine` in lib.ts.

## Per item

- UI-1 (proven): `band-200x60.ansi` row 55 is the one guard line in yellow, followed by the engine's `[-]` control. Nothing else is drawn above the prompt: no pane, no framed band, no resume offer. The SessionStart conflict block names dagents@darkraise (user) and dforge@darkraise (this session). The test asserts the band's Text list equals `[guardLine(CONFLICT, root)]` exactly.
- UX-1 (proven): `cockpit-command-200x60.ansi` shows `/dforge:cockpit` answered with `dforge: dagents@darkraise, dforge@darkraise are enabled together; run node …/workflow-guard.mjs --host claude`. No pane is drawn, and the band at row 55 still holds the line alone. The code agrees: the `command.run` handler returns `{ text: conflict }` before opening anything.
- UX-2 (proven): the line names both plugin ids and the absolute check path. The SessionStart block above it, in the same captures, carries the `claude plugin disable ...` commands. The `guardLine` unit test pins the exact string, and returns null for exit 0 and for a failed start.
- UX-3 (proven): `no-conflict-200x60.ansi` shows the docked pane (Account, Context, Usage, Agents, Guard) with no SessionStart conflict block, no guard line and no command run, so the pane opened at session start. `no-conflict-cockpit-command-200x60.ansi` shows `dforge: Cockpit pane opened.`. `no-conflict-120x40.ansi` shows the same at the smaller size. None of the three contains "enabled together". The "with no conflict ..." test asserts the band expand control and the account card, and that the check ran once.
- OP-1 (proven): at 200x60 the line is one row. In `band-120x40.ansi`, rows 34-35 show it wrapping after `run node ` onto a second row with every word and the full path present. Both sizes are covered.
- OP-2 (proven): the line is 256-colour yellow (38;5;220) foreground only. Plugin ids, the verb and the command are all in the text, so nothing depends on colour.
- OP-3 (proven by test): the test records every `$.process.run`, unmounts the band, advances the clock 130 s and asserts that no call other than the guard's was made. The code agrees: `session.start` cancels the watchdog and poll under a conflict instead of arming them, and every hook calls `standsDown` first. I did not rerun the report's mutation check.

## Differences I found

- The command answer is prefixed `dforge: ` and shows the path as `…/plugins/dforge/scripts/...` in a narrow terminal. The prefix is the host's own formatting, and the full absolute path is in the band line. The contract says `<plugin root>`, which this satisfies. Not a deviation.
- The report's UI-1 note says the conflict-state capture holds "the engine's own `[-]` collapse control and effort hint". The conflict captures show `[-]` but no effort hint (it appears only in the no-conflict captures). This is a wrong detail in the note. It does not change what the evidence proves, because the band holds no cockpit row besides the guard line.
- The host's own status rows (managed-settings warning, "Switched to Manual", "Auto-update failed") appear in every capture. They are the throwaway-HOME environment, not cockpit surfaces.
- The captures cannot show which config the no-conflict walk used (dagents false); only the report says so. The no-conflict test covers the same state independently, so the proof does not rest on that statement alone.

## Disputed items

None.

## Notes on criteria

- Coverage: every Delta item has a row, and I opened the evidence for each. The deduction is the small note inaccuracy above.
- Fidelity: copy, the single yellow line and the wrap behaviour match the Delta. The pane with no conflict matches the pre-change cockpit.
- States: conflict, no conflict, the failed-check fallback (unit test), both viewports and the command path are shown. The report states that no pointer or keyboard control exists on the line, and none is expected. The 120x40 no-conflict capture is truncated by the pane height. That is how the pane lays out, not a regression this change causes.
- Deviations: none are claimed and none were found that need a citation.

Verdict: ship 725607f44d838649
