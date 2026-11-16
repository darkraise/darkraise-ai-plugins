# UI proof: next-session routing resume band

**Contract:** touch
**Fingerprint:** 44c41addcc6b3993
**Platform:** terminal
**Viewports:** 200x60, 120x40
**Themes:** default
**Evidence:** local
**Judge:** ship 44c41addcc6b3993 — docs/dforge/ui-ux/proofs/2026-11-16-next-session-routing.judge.md

## Delta

**UI/UX depth:** touch — the cockpit's resume offer (`plugins/dforge/hooks/cockpit/register.tsx`, `lib.ts`) now shows what `next-step --print --latest` recomputes instead of the stored latest.md block; the band above the prompt is the one surface drawn differently

- **UX-1** — A stored note the repository has moved past (it says Task 1; the ledger has since completed Task 1) draws the band with the recomputed Next line, `Resume at Task 2 (Wire the export button).`, with no `not rechecked` mark; the pane's resume card shows the same line.
- **UX-2** — Resume, reached by keyboard (`ctrl+x tab` puts the focus ring on `[ Resume ]`, Enter presses it), submits the recomputed first prompt, not the stored one.
- **UX-3** — A note that `next-step --print --latest` finds superseded (exit 6: an ad hoc note written before a plan was indexed) draws no band and no card.
- **UX-4** — A note `next-step` cannot recompute (its plan file was deleted, exit 2) falls back to the stored Next line with the band's title reading `↻ Resumable work · handed off <age> · not rechecked`; Resume and Dismiss stay drawn.
- **UX-5** — A note whose marker is four days old draws no band.
- **UX-6** — Dismiss, reached by keyboard (`ctrl+x tab` twice), removes the band; editing the notes above the block keeps it dismissed, and a new next-step block (a new marker time) brings it back.
- **OP-1** — Proven at 200x60 and 120x40 in the default theme; at 120x40 the mark and both buttons stay visible and only the Next text truncates.
- **OP-2** — No state reads by colour alone; the keyboard reaches both band buttons.

## Results

| ID | Verdict | Evidence | Note |
|---|---|---|---|
| UX-1 | pass | .dforge/ui-ux/next-session-routing/recompute-band-v200x60.txt, .dforge/ui-ux/next-session-routing/recompute-band-v120x40.txt; tests "resume offer > shows the recomputed block", "resume offer > runs again once an auto run ends, though no keyed file changed" | fixture `w/recompute`: latest.md written by `next-step <plan>` reads `**Next:** Start at Task 1 (Write the exporter).`, then the ledger gained `Task 1: complete`. Both captures draw `↻ Resumable work · handed off <age> — Next: Resume at Task 2 (Wire the export button).` (`just now` at 200x60, `1m ago` at 120x40) with `[ Resume ] Dismiss` and no `not rechecked`; the 200x60 pane's card (top right) reads `Next: Resume at Task 2 (Wire the export button).` with its `Resume` button |
| UX-2 | pass | .dforge/ui-ux/next-session-routing/recompute-resume-focus-v200x60.ansi, .dforge/ui-ux/next-session-routing/recompute-after-resume-v200x60.txt | one `ctrl+x tab` put reverse video on `[ Resume ]` only (`-resume-focus`). Enter submitted `❯ Resume docs/dforge/plans/2026-11-11-billing-export.md with dforge:resume-execution. Resume at Task 2 (Wire the export button). Progress …`, the recomputed prompt (the stored one began `Continue … with dforge:executing-plans. No ledger exists yet`); the turn then failed `Invalid API key`, as the placeholder key makes every turn fail, and the band was gone |
| UX-3 | pass | .dforge/ui-ux/next-session-routing/superseded-v200x60.txt, .dforge/ui-ux/next-session-routing/superseded-v120x40.txt, .dforge/ui-ux/next-session-routing/superseded-after-turn-v120x40.txt; test "resume offer > hides the offer when nothing is to resume" | fixture `w/superseded`: an `--adhoc` note (`done=0`), then completed.md indexed a plan; `next-step --print --latest` there exits 6 `a plan or a milestone closed since the block was written`. No `Resumable` text at either size, 25 s after launch and after a failed turn (which re-reads the note) |
| UX-4 | pass | .dforge/ui-ux/next-session-routing/fallback-v200x60.txt, .dforge/ui-ux/next-session-routing/fallback-v120x40.txt; tests "resume offer > falls back on a failed run and marks it: …", "resume offer > falls back with the register check: …" | fixture `w/fallback`: the note's plan was deleted and committed, so `next-step --print --latest` exits 2 `no such file`. The band reads `↻ Resumable work · handed off 4m ago · not rechecked — Next: Start at Task 1 (Write the exporter).` at 200x60; at 120x40 `… · not rechecked — Next: Start at Task 1 (Write the exp… [ Resume ] Dismiss`. The pane's card shows the stored line without the mark: the spec (§3, A12) puts the mark on the band only |
| UX-5 | pass | .dforge/ui-ux/next-session-routing/stale-v200x60.txt, .dforge/ui-ux/next-session-routing/stale-v120x40.txt, .dforge/ui-ux/next-session-routing/stale-after-turn-v120x40.txt; tests "resume offer > offers nothing for a handoff older than three days", "resume offer > ages from the marker" | fixture `w/stale`: a `next-step <plan>` note with its marker's `at=` moved back four days; `next-step --print --latest` alone still exits 0 there, so the absence is the cockpit's age rule reading the marker. No `Resumable` text at either size, also after a failed turn |
| UX-6 | pass | .dforge/ui-ux/next-session-routing/dismiss-focus-v120x40.ansi, .dforge/ui-ux/next-session-routing/after-dismiss-v120x40.txt, .dforge/ui-ux/next-session-routing/after-new-block-turn-v120x40.txt, .dforge/ui-ux/next-session-routing/after-dismiss-2-v120x40.txt, .dforge/ui-ux/next-session-routing/after-notes-edit-turn-v120x40.txt; tests "resume offer > ages from the marker: editing the notes keeps a dismissal", "resume offer > Dismiss removes the offer without a prompt" | two `ctrl+x tab` put reverse video on `Dismiss` only; Enter removed the band (`after-dismiss`, no `Resumable`). A new `next-step <plan>` write (new marker time) brought the band back as `handed off just now` after the next turn (`after-new-block-turn`). Dismissed again (`after-dismiss-2`), then a `## Notes` section was inserted above the block (latest.md's mtime changed, its marker did not) and a turn ran (`❯ status again?`): still no band (`after-notes-edit-turn`). At 120x40 the side pane is not drawn, so the cockpit's poll does not re-read latest.md and the read happens at each turn end, as before this branch; every 120x40 re-read claim above therefore follows a turn |
| OP-1 | pass | .dforge/ui-ux/next-session-routing/recompute-band-v200x60.txt, .dforge/ui-ux/next-session-routing/recompute-band-v120x40.txt, .dforge/ui-ux/next-session-routing/fallback-v120x40.txt | each capture is 60 or 40 lines and at most 200 or 120 columns wide (`wc -L`); the window was pinned (`window-size manual`). At 120x40 the fallback band's title, mark and `[ Resume ] Dismiss` fit, the Next text ends in `…` |
| OP-2 | pass | .dforge/ui-ux/next-session-routing/recompute-resume-focus-v200x60.ansi, .dforge/ui-ux/next-session-routing/dismiss-focus-v120x40.ansi, .dforge/ui-ux/next-session-routing/fallback-v200x60.ansi | a parse of the SGR codes in all 18 `.ansi` captures finds only 0 (reset) and 7 (reverse video), so `NO_COLOR=1` held. The fallback is the words `not rechecked`, the focus ring is reverse video, and `ctrl+x tab` reached `[ Resume ]` and `Dismiss` |

## Automated checks

- Walked on 2026-11-16 on Claude Code 2.1.325 in tmux 3.5a (`NO_COLOR=1`, a throwaway HOME and `CLAUDE_CONFIG_DIR` per scenario and size under the scratch directory, a placeholder API key approved in that directory's `.claude.json`) with `--plugin-dir plugins/dforge` at c49d96a4 on branch `auto/next-session-routing`. Each scenario's work directory is a throwaway git repository whose latest.md was written by the branch's own `scripts/next-step`; the expected `next-step --print --latest` exit (0, 6, 2, 0) was confirmed in each before the walk.
- `claude plugin test plugins/dforge` at c49d96a4: 675 pass, 0 fail (the integration check, and `ci-mirror`'s pass of the same command), among them the `resume offer` tests named above.
- `ui-lint plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/hooks/cockpit/lib.ts`: two `raw-color` hits, register.tsx lines 1729 and 1782, both from 2026-10-09 (`git blame`); the merge base's register.tsx gives the same two, so this branch adds none.

- Re-proved at 3648e9f9 after the final review's fix 53d9182c, the one UI change since the walk at c49d96a4 (`git diff --stat c49d96a4 3648e9f9 -- plugins/dforge/hooks/` lists only register.tsx, 2 lines): `trackAutoRun` clears `S.offerRanKey` when an auto run stops being active, so the next read runs `next-step --print --latest` again instead of keeping the offer computed before the run. It changes when the offer is recomputed, not what the band or the card draws, so the captures above stand; the post-run recompute is proven by the test "resume offer > runs again once an auto run ends, though no keyed file changed" (cited under UX-1), which fails on the code before 53d9182c. No live walk drove an auto run to its end: the nested session has no working API key, so no run can start.
- The two `-after-turn` 120x40 captures of the superseded and stale scenarios carry the host's footer `⚠ Transcript writes are failing (disk full — ENOSPC)`: the session's `/tmp` tmpfs filled during the walk (other sessions' scratch directories). It concerns the nested session's transcript, not the cockpit; the band's absence in those captures matches the earlier captures of the same scenarios taken before the disk filled.

## Not proven

- A pointer press is not exercised: tmux sends keys only.
- The 20-second timeout path is covered by the cockpit tests only; no live run was made to hang.
