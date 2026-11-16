## Verdict
verdict: ship 3f9e18a285a8d92d
scores: coverage 16 / fidelity 17 / states 16 / deviations 16

Disputed items: 0. Every contract item (UX-1 to UX-6, OP-1, OP-2) is shown by a capture I opened or a test I read. The report has a few inaccurate or mismatched citations, listed under "Report defects"; none changes what the evidence proves.

## What I opened

All 18 .txt captures and the three .ansi captures that carry the focus and colour claims (recompute-resume-focus-v200x60, dismiss-focus-v120x40, fallback-v200x60 by its .txt twin), under .dforge/ui-ux/next-session-routing/. I also read `describe('resume offer')` in plugins/dforge/tests/cockpit.test.ts (lines 5317-5665), `drawResumeBand`, `readResumeOffer`, `offerFrom` and `offerNow` in register.tsx, `markerOf` in lib.ts, and `--print --latest` in scripts/next-step (lines 294-354).

## Per item

- UX-1 proven. recompute-band-v200x60.txt and -v120x40.txt show the band `↻ Resumable work · handed off … — Next: Resume at Task 2 (Wire the export button).` with `[ Resume ] Dismiss` and no `not rechecked`. The 200x60 pane card (rows 3-7) shows the same Next line and a Resume button. Test "shows the recomputed block" asserts the recomputed Next text, that the stored text 'Write the plan' is absent, and that Resume submits the recomputed prompt.
- UX-2 proven. In recompute-resume-focus-v200x60.ansi, line 54 has the only ESC[7m in the file, around `[ Resume ]`. recompute-after-resume-v200x60.txt shows the submitted prompt `Resume docs/dforge/plans/2026-11-11-billing-export.md with dforge:resume-execution. Resume at Task 2 (Wire the export button). …`, with the band and pane card gone. The test asserts `prompts` equals the recomputed first prompt. The keystrokes (`ctrl+x tab`, Enter) are stated only in the report, but the focus capture and the result capture are consistent with them.
- UX-3 proven. superseded-v200x60, -v120x40 and -after-turn-v120x40 contain no band and no pane card; the 200x60 pane shows no resume card. Test "hides the offer when nothing is to resume" (exit 6) asserts both are undefined. The code returns null on exit 6 (`offerFrom`).
- UX-4 proven. fallback-v200x60.txt reads `↻ Resumable work · handed off 4m ago · not rechecked — Next: Start at Task 1 (Write the exporter).` with Resume and Dismiss. fallback-v120x40.txt keeps the mark and both buttons, and only the Next text ends in `…`. The pane card shows the stored line without the mark, which matches the contract (the mark is on the band's title). The cited tests cover exit 1 and a timeout; the exit-2 case is shown only by the live capture, and `offerFrom` treats every non-0, non-6 result the same way.
- UX-5 proven. stale-v200x60, -v120x40 and -after-turn-v120x40 show no band. The test that shows the marker rule is "ages from the marker" (line 5597): a marker four days old, a fresh file mtime, band undefined, and no next-step run. The report does not cite that test for UX-5 (see Report defects).
- UX-6 proven. In dismiss-focus-v120x40.ansi line 34 only `Dismiss` carries ESC[7m. after-dismiss shows the band gone. after-new-block-turn shows the band back as `handed off just now` after a turn. after-dismiss-2 and after-notes-edit-turn show it gone again after a notes edit and a turn. The test "ages from the marker: editing the notes keeps a dismissal" asserts the dismissal survives, and `--print --latest` prints the stored marker back (next-step line 330), so the dismissal key (`offer.at`) stays the same across a recompute. The "new marker brings it back" step has no test, only the capture.
- OP-1 proven. Captures are 60 and 40 lines. At 120x40 the mark and both buttons fit and the Next text truncates with `…` (`wrap="truncate-end"` on the text box, with the buttons outside it in `drawResumeBand`).
- OP-2 proven. A search of all .ansi files finds no SGR code other than 0 and 7. `not rechecked` is words, the focus ring is reverse video, and the keyboard reaches both buttons.

## Report defects (do not change a verdict, should be corrected)

- UX-1 says both captures read `handed off just now`. recompute-band-v120x40.txt reads `handed off 1m ago`; only the 200x60 capture reads `just now`.
- UX-1 says the pane card reads `Next: Resume at Task 2 (Wire the export …`, truncated. The 200x60 capture shows the full line `Next: Resume at Task 2 (Wire the export button).`.
- UX-5 cites the test "offers nothing for a handoff older than three days". That test ages a note with no marker by its file mtime (line 5425), so it does not test the marker rule. "ages from the marker" is the test that does.
- UX-6 and UX-3 absence captures have no same-fixture positive control. The fixtures are tested in the file, but the report's `next-step --print --latest` exit claims (0 for stale, 6 for superseded) cannot be checked from the captures.
- The after-turn captures (superseded-after-turn, stale-after-turn) show `Transcript writes are failing (disk full — ENOSPC)` in the footer. The report does not mention it. The band state is held in memory and read from latest.md, so I do not see how it affects the result, but the host had a full disk during the walk.
- The report's claim that the stored prompt for UX-2 began `Continue … executing-plans. No ledger exists yet` cannot be checked: the fixture's latest.md in the scratch directory holds the later rewritten note (Next: Resume at Task 2).

## Criteria

- coverage 16: all eight items have evidence I opened that shows the item. Deducted for the mismatched UX-5 test citation and the inaccurate quotes above.
- fidelity 17: band copy, the `↻` mark, the `· not rechecked` suffix, the Resume/Dismiss buttons and the truncation behaviour match the contract in both viewports. The only difference found (the pane card has no mark) is what the contract asks for.
- states 16: superseded, stale, fallback, recomputed, dismissed, returned and notes-edited states each have a capture; keyboard focus on Resume and on Dismiss is evidenced in .ansi captures. Deducted because each button's focus is shown at one viewport only, the Dismiss path and the Resume path are not both walked at both sizes, and the pointer press and the 20 s timeout are left unproven (the report discloses both).
- deviations 16: no row is marked deviation. The one difference found was not marked pass against the contract, and the report cites the spec for it. The report discloses the 120x40 behaviour that a re-read happens only after a turn because the pane is not drawn.

Verdict: ship 3f9e18a285a8d92d
