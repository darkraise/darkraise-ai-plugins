## Verdict
verdict: ship 9db6821dd90b35d3
scores: coverage 18 / fidelity 18 / states 17 / deviations 18

## What I opened

- All six cited captures under `.dforge/ui-ux/2026-11-17-dagents-guard-line/`, read as text with their ANSI escapes: `band-200x60`, `band-120x40`, `cockpit-command-200x60`, `no-conflict-200x60`, `no-conflict-cockpit-command-200x60`, `no-conflict-120x40`.
- Tests "the guard line names the active plugins and the check, only on a conflict" and `describe('the workflow guard')` (two tests) in `plugins/dagents/tests/cockpit.test.ts`, lines 8193-8232.
- `guardNow`, `standsDown`, the `session.start` and `command.run` hooks, and the `Pane` and `AbovePrompt` render hooks in `register.tsx`; `guardLine` in `lib.ts`.
- The round-1 report.

## Change since round 1

I could not run `git diff` (this seat has Read and Grep only), so I did not diff the file. I read the current `session.start` hook instead. Its comment now reads "A new session reads the plugins enabled now (a /clear or /resume fires no session.start, so the check made before it stands); timers an earlier session armed stop." The code beneath it is `guardCheck = null`, then `if ((await guardNow($)) !== null)` cancelling the watchdog and poll and returning `next(e)`. That is the behaviour the round-1 report described, and I saw nothing in the hook that a comment-only edit would not explain. This is a reading, not a diff: that no code changed is the dispatch's statement, and I found nothing contradicting it. The claim in the comment that `/clear` and `/resume` fire no `session.start` is an engine fact I cannot verify from here. It is a comment, and it changes nothing drawn, so the captures at 68895ed9fb6494e4 still show what the code draws.

## Per item

- UI-1: proven. `band-200x60.ansi` row 55 holds `dagents@darkraise, dforge@darkraise are enabled together; run node /root/repositories/darkraise-ai-plugins/plugins/dagents/scripts/workflow-guard.mjs --host claude` in `38;5;220`, with only the engine's `[-]` control on the same row. There is no pane, framed band or resume offer anywhere in the capture. The SessionStart conflict block is in the transcript at rows 7-11. The test asserts the band's Text list equals `[guardLine(CONFLICT, root)]`, and `AbovePrompt` returns the line before the band or offer code runs (register.tsx 2263-2268).
- UX-1: proven. `cockpit-command-200x60.ansi` row 13 shows `● Unknown command: /cockpit`. The guard line is still on row 55 and no pane opened.
- UX-2: proven. The line names both plugin ids and the absolute path of the check. The disable commands are in the SessionStart block, rows 9-10 of the 200x60 capture. `guardLine` is pinned by the unit test (exit 3 gives the line; exit 0 and null give no line).
- UX-3: proven. `no-conflict-200x60.ansi` shows the docked pane with Account, Context, Usage, Agents, Repo and Guard cards, and no `enabled together` text. `no-conflict-cockpit-command-200x60.ansi` shows `dagents: Cockpit pane opened.`. `no-conflict-120x40.ansi` shows the pane at 120 columns, cut off after the Repo card by the terminal height. The test "with no conflict the cockpit draws as before" checks the expand button and the account card, and that the guard ran once.
- OP-1: proven. At 200x60 the line is one row (row 55). In `band-120x40.ansi` it wraps after `run node` onto rows 34-35 and every word and flag is present.
- OP-2: proven. The line's only SGR is `38;5;220` and the reset, and the whole meaning is in the words. The code uses the named colour `yellow`.
- OP-3: proven by test. The test records every `process.run` call, advances the clock 130 s, and asserts that no call other than the guard's was made. I could not re-run the mutation check the report cites and treat that detail as unverified. The test is sound without it.

## Criteria notes

- Coverage: every item has a row, and the cited evidence opened and shows that item. A small deduction because the manual run of the check (exit 3, one line per plugin) has no saved file. The capture does show the check's output in use.
- Fidelity: copy, hierarchy, colour and the two-row wrap match the promise. The extra `[-]` and effort hint are engine chrome, and the report says so.
- States: conflict at both viewports, no conflict at both viewports, `/cockpit` in both states, and the check-failed case (`guardLine(null)` gives no line) are covered. Hover, focus and pointer states do not apply because the line has no control, and the report states the pointer limit. Deducted because the Pane render path under a conflict (the guard line in the pane slot, register.tsx 914-918) has no capture or test. The 120x40 `/cockpit` walk under conflict is also not captured.
- Deviations: none listed and none found.

## Adjacent observations (not disputes)

- `AbovePrompt` returns `next(e)` for `hasSurvey` before the guard check, so a survey suppresses the guard line. This is engine surface and does not break the contract.
- Because `/clear` and `/resume` fire no `session.start` (per the new comment), the cached guard result stands across them. A plugin disabled mid-session keeps the line until a new session, which the SessionStart text ("Then start a new session.") already tells the person.

## Disputed items

None.

Verdict: ship 9db6821dd90b35d3
