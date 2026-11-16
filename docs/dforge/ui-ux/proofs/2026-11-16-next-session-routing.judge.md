## Verdict
verdict: ship 44c41addcc6b3993
scores: coverage 17 / fidelity 17 / states 16 / deviations 16

Disputed items: 0. Every Delta item (UX-1 to UX-6, OP-1, OP-2) has evidence I opened that shows it. The reasoning for keeping the older captures after commit 53d9182c holds (see "The 53d9182c reasoning").

## What I opened

- The criteria, the report, and the earlier judge report (docs/dforge/ui-ux/proofs/2026-11-16-next-session-routing.judge.md).
- All 18 .txt captures under .dforge/ui-ux/next-session-routing/ and the .ansi captures that carry the focus and colour claims: recompute-resume-focus-v200x60.ansi, dismiss-focus-v120x40.ansi, fallback-v200x60.ansi. I also searched all 18 .ansi files for escape codes.
- describe('resume offer') in plugins/dforge/tests/cockpit.test.ts (lines 5317-5680).
- In plugins/dforge/hooks/cockpit/register.tsx: `trackAutoRun` (3026-3041), `readResumeOffer` (3630-3670), `offerFrom`, `offerNow`, `drawResumeBand` (2356-2373), the turn-complete hook (752-755), `readSession` (4365-4414), `pollTick` (4422-4460), `stopAutoRun` (3554-3559).

I had no shell in this session, so I did not run the tests or `git diff`. I read the two added lines in `trackAutoRun` directly, and I did not check the "2 lines only" diffstat claim.

## The 53d9182c reasoning

The report says the commit changes when the offer is recomputed, not what the band or card draws, so the captures walked at c49d96a4 stand. This holds.

- The change is `if (before?.active === true && now?.active !== true) S.offerRanKey = null` (register.tsx 3037). It sits after the early return for an unchanged auto-run state and only runs on an active-to-inactive transition (a stopped run, or a state file that disappeared).
- Without the reset, `readResumeOffer` computes `runKey` from the latest.md key plus `offerTimes` (completed.md, roadmap.md, registers, the plans directory, the subject plan). It returns at `S.offerRanKey === runKey` (3652). A run moves the ledger, which the key leaves out, so the offer shown before the run would survive it. The two lines fix that. They clear a cache; nothing in `drawResumeBand` or the card changes.
- Ordering is right. The turn-complete hook calls `trackAutoRun` (752) before `readRun` (755), which calls `readResumeOffer` (3767). `stopAutoRun` also calls `trackAutoRun` and then `readRun`. On a poll tick, `readRun` runs before `trackAutoRun`, so the recompute happens one tick later; that is a delay, not a miss.
- No capture walks an auto run: the report says so. None of the walked scenarios can reach the changed branch, because the auto-run state is absent in all of them and the transition never occurs. So no capture's drawn output depends on the changed code.
- The test "runs again once an auto run ends, though no keyed file changed" (5648-5661) is the right test. It starts with a marked note and two queued next-step outputs (Task 3, then Task 5) and asserts the band reads Task 3. It then writes an active auto-run file and runs a turn, and asserts the band is gone (hidden by `offerNow`, 3739). It then writes an inactive one and runs a turn, and asserts two next-step runs and the band reading Task 5. No keyed file's mtime changes between the two runs, so on the old code `runKey` would match `offerRanKey` and `nextStepRuns` would stay at 1. The `toHaveLength(2)` assertion fails there, so the report's claim that the test fails before 53d9182c is sound by reading. I did not run it.

Gap (does not dispute an item): the report's test result, "675 pass, 0 fail", is stated at c49d96a4, which predates the new test. The "Re-proved at 3648e9f9" bullet gives no test run at the new head. It rests on the test I read above and on the diff being 2 lines.

## Per item

- UX-1 proven. recompute-band-v200x60.txt row 54 reads `↻ Resumable work · handed off just now — Next: Resume at Task 2 (Wire the export button).` with `[ Resume ] Dismiss` and no `not rechecked`. recompute-band-v120x40.txt row 34 reads the same with `1m ago`, so the report's per-size ages are now correct. The 200x60 pane card (rows 3-7) reads `Next: Resume at Task 2 (Wire the export button).` with a Resume button. Test "shows the recomputed block" asserts the Next text, that the stored text is absent, and that Resume submits the recomputed prompt. The new post-run recompute test is also cited here and covers the same offer path.
- UX-2 proven. In recompute-resume-focus-v200x60.ansi, the only escape codes are `ESC[7m` and `ESC[0m` around `[ Resume ]` on row 54, and `Dismiss` is plain. recompute-after-resume-v200x60.txt shows `❯ Resume docs/dforge/plans/2026-11-11-billing-export.md with dforge:resume-execution. Resume at Task 2 (Wire the export button). Progress ledger: …`, then `Invalid API key`, and no band and no card. The stored prompt's wording is not in any capture; the test asserts the submitted prompt equals the recomputed first prompt. The keystrokes are stated only in the report.
- UX-3 proven. superseded-v200x60, superseded-v120x40 and superseded-after-turn-v120x40 contain no band, and the 200x60 pane has no resume card (rows 2-9 show only idle and Account). Test "hides the offer when nothing is to resume" (exit 6) asserts both are undefined. `offerFrom` returns null on exit 6.
- UX-4 proven. fallback-v200x60.txt row 54 reads `↻ Resumable work · handed off 4m ago · not rechecked — Next: Start at Task 1 (Write the exporter).` with `[ Resume ] Dismiss`. fallback-v120x40.txt row 34 keeps the mark and both buttons, and the Next text ends `(Write the exp…`. The pane card shows the stored line without the mark, which matches the contract (the mark is on the band's title, and `drawResumeBand` is the only place `isRechecked` is read). The cited tests cover exit 1 and a timeout; exit 2 is shown only by the capture, and `offerFrom` treats every result other than 0 and 6 the same way.
- UX-5 proven. stale-v200x60, stale-v120x40 and stale-after-turn-v120x40 show no band and no card. The report now cites "ages from the marker" (5597), which tests a four-day-old marker on a fresh file and asserts no band and no next-step run. This fixes the earlier citation defect.
- UX-6 proven. dismiss-focus-v120x40.ansi row 34 has `ESC[7m` only around `Dismiss`. after-dismiss-v120x40.txt shows the band gone. after-new-block-turn-v120x40.txt shows it back as `handed off just now` after a turn. after-dismiss-2 and after-notes-edit-turn show it gone again after a notes edit and a turn (`❯ status again?` is visible). The test "ages from the marker: editing the notes keeps a dismissal" asserts the dismissal survives. The "new marker brings it back" step has only the capture, no test.
- OP-1 proven. Captures are 60 rows (200x60) and 40 rows (120x40). At 120x40, fallback-v120x40.txt keeps the mark and both buttons and only the Next text truncates with `…`; `drawResumeBand` puts `wrap="truncate-end"` on the text and the buttons outside it.
- OP-2 proven. Of the 18 .ansi files, only dismiss-focus-v120x40.ansi and recompute-resume-focus-v200x60.ansi contain any escape sequence, and those are `ESC[7m` and `ESC[0m`. The rest, including fallback-v200x60.ansi, have none, so `NO_COLOR=1` held. `not rechecked` is words, the focus ring is reverse video, and the keyboard reached both buttons.

## Weaker points (none disputes an item)

- The absence captures (UX-3, UX-5, and the dismissed states) have no positive control in the same capture. The recompute scenarios in the same harness and the cockpit tests show the band does draw when it should.
- The `-after-turn` 120x40 captures of the superseded and stale scenarios show the `Transcript writes are failing (disk full — ENOSPC)` footer. The report now explains it. The band state is read from latest.md and held in memory, so I do not see an effect on the cockpit.
- The pointer press and the 20 s timeout are not walked; both are disclosed under "Not proven". No live walk drives an auto run to its end; the report discloses it, and the test covers that path.
- At 120x40 the pane is not drawn, so the cockpit's poll does not re-read latest.md and re-reads happen at a turn end; the report discloses this under UX-6.

## Criteria

- coverage 17: all eight items have a row whose evidence I opened and which shows the item. The earlier citation errors (per-size ages, the UX-5 test, the pane card quote) are corrected. Deducted for the UX-2 stored-prompt claim and the keystrokes that no capture shows, and for the missing test run at the new head.
- fidelity 17: the band copy, the `↻` mark, the `· not rechecked` suffix, the Resume and Dismiss buttons and the truncation behaviour match the contract at both viewports. The recomputed card matches the band's Next line.
- states 16: the recomputed, superseded, stale, fallback, dismissed, returned and notes-edited states each have a capture. Keyboard focus on Resume and on Dismiss is shown in .ansi captures, one viewport each. Deducted because focus on each button is shown at one size only, and the pointer press and the 20 s timeout are unproven.
- deviations 16: no row is marked deviation. The one difference I found (the pane card has no `not rechecked` mark) is what the contract asks for and the report cites the spec for it.

Verdict: ship 44c41addcc6b3993
