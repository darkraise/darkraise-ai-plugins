## Verdict
verdict: ship bc488cb026818f4a
scores: coverage 18 / fidelity 18 / states 17 / deviations 18

## Disputed items

None. The two items the earlier judge disputed (UI-1 and UX-3) are now supported by captures I opened.

## What I opened

All nine captures under .dforge/ui-ux/2026-11-17-dforge-guard-line/, both seeded handoff files, the three guard tests in plugins/dforge/tests/cockpit.test.ts (lines 8756-8795), the guard code in plugins/dforge/hooks/cockpit/register.tsx (guardNow, session.start, command.run, the Pane and AbovePrompt ui.render hooks), the README `openAtStart` rows, and the suite log.

## Per item

- UI-1 (pass, confirmed). `band-200x60.ansi` and `resume-200x60.ansi` hold one yellow (colour 220) guard line above the prompt, plus the engine's own `[-]` control. There is no pane, no framed band and no Resume offer. The conflict-with-handoff walk (`resume-200x60`) was seeded with `.dforge/handoff/latest.md`, which carries the `Paste as the first prompt:` block. The no-conflict walk's seed (`run-dforge-no-conflict-resume-200x60/.../latest.md`) has identical content apart from the worktree path. In `no-conflict-resume-200x60.ansi` that seed draws `↻ Resumable work · handed off just now` with Resume and Dismiss, both in the pane (rows 3-8) and in the framed band (rows 53-55). So the absence of an offer under the conflict comes from the guard. register.tsx agrees: the AbovePrompt hook returns the guard Text before `offerNow` is called. The test at cockpit.test.ts:8767 asserts the band's Text list equals `[guardLine(...)]`. That test is listed as `(pass)` in the suite log at lines 9506-9508.
- UX-1 (pass). `cockpit-command-200x60.ansi` shows `/dforge:cockpit`, then `⎿ dforge: dagents@darkraise, dforge@darkraise are enabled together; run node …/workflow-guard.mjs --host claude`. No pane is open and the band still holds the line alone. register.tsx's `command.run` returns `{ text: conflict }` before any open call.
- UX-2 (pass). The line names both plugin ids and the absolute path of the check. The SessionStart block above it in every conflict capture carries the `claude plugin disable ...` commands for both plugins. The unit test (cockpit.test.ts:8756) pins the exact text. The report's hand run of the check (`dagents@darkraise user`, `dforge@darkraise self`, exit 3) has no capture. The test's input has the same shape, so this is a minor gap, not a dispute.
- UX-3 (pass, confirmed). At 200x60, `no-conflict-200x60.ansi` shows the docked pane at session start (Account, Context, Usage, Agents, Guard "on · none refused") and no guard line. `no-conflict-cockpit-command-200x60.ansi` shows `dforge: Cockpit pane opened.` with the pane docked. At 120x40, `no-conflict-120x40.ansi` shows no pane and no guard line. The README (line 606 and the `openAtStart` row at 926) states the pane auto-opens only once the terminal is 144 columns wide (110 after the person has opened it before), and that `/dforge:cockpit` opens it at any width. That explains the absence. `no-conflict-cockpit-command-120x40.ansi` shows `dforge: Cockpit pane opened.` and the pane docked with its Context card. The test at cockpit.test.ts:8783 covers no change under no conflict and is listed as passing in the log.
- OP-1 (pass). `band-200x60.ansi` has the line on one row (row 55). `band-120x40.ansi` has it wrapped after `run node` onto rows 34-35, and every word is present.
- OP-2 (pass). The line's only colour is a yellow foreground (38;5;220). Every part of its meaning is in the words.
- OP-3 (pass). The test records `$.process.run` calls, advances the clock 130 s, and asserts that no call other than the guard's occurred. The suite log shows it passing, and 702 pass, 0 fail across 7 files. The mutation run in the report is not something I could verify.

## Criteria

- Coverage 18. Every Delta item has a row, and the cited evidence opened and showed the item. The small deductions are the hand-run check (UX-2), which has no capture, and the mutation run (OP-3), which has no log.
- Fidelity 18. Copy matches the Delta wording, the colour is the single yellow emphasis, and the wrap keeps the line whole. The no-conflict captures are unchanged from the normal cockpit.
- States 17. The conflict, no-conflict, resume-offer, command, 200x60 and 120x40 states are shown. The pointer press is declared not proven, and the line has no control. The 120x40 no-conflict session-start state is the width-gated one, shown by the empty capture plus the README rule rather than by a docked pane.
- Deviations 18. The only difference I found is the missing pane at session start at 120x40. It is cited to the README's 144-column rule, which the capture of `/dforge:cockpit` at the same size corroborates. No deviation is marked pass without a citation.

Verdict: ship bc488cb026818f4a
