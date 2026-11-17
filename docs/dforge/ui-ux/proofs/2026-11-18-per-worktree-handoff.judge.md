## Verdict
verdict: ship 2406b7defe6d1675
scores: coverage 17 / fidelity 17 / states 16 / deviations 17

## Scope of what I opened

- Criteria, report and its Delta (touch depth, UI-1, UX-1 to UX-4, OP-1, OP-2).
- All nine captures under `.dforge/ui-ux/2026-11-18-per-worktree-handoff/`, read as text with their SGR codes: `dforge-card-200x60`, `dforge-card-120x40`, `dforge-resume-focus-200x60`, `dforge-resume-200x60`, `dforge-after-120x40`, `dagents-card-200x60`, `dagents-card-120x40`, `dagents-resume-focus-200x60`, `dagents-resume-200x60`.
- The probe note `docs/dforge/notes/2026-11-18-worktree-cwd-probe.md`.
- In both `plugins/*/tests/cockpit.test.ts`, the five named tests (the dforge ones at lines 5695, 5707, 5713, 6828, 6843; the dagents ones at 5566, 5578, 5584, 6705, 6720), plus the mock `process.run` and `fs.stat` handlers in the dforge file.
- `autoRunCall` in both `register.tsx` files. Every `scripts/auto-run` call goes through it; a grep found no other `process.run` of `auto-run`.

I could not run the tests or check git (no shell). I take the `claude plugin test` counts (702/0, 616/0) from the dispatch, not from my own run. I could not confirm from git that the captures were taken at 6a6bc3a4. Nothing in the captures contradicts the report.

## Per item

| ID | Judgement | What I saw |
|---|---|---|
| UI-1 | proven | In `dforge-card-200x60` and `dagents-card-200x60`, the pane card reads `↻ Resumable work · handed off just now` over `Next: Probe: the worktree's next step.`. The band at the bottom reads the same text after `—`. The session path ends `…/uiw-<plugin>/wt` and the Repo card shows `⎇ w`. The text "worktree's next step" can only come from the worktree's file, and "primary's next step" appears in none of the nine captures. |
| UX-1 | proven | In both `*-resume-focus-200x60` captures, `[ Resume ]` is `1;7` (reverse video); in the matching card captures it is `1` only. In both `*-resume-200x60` captures, the submitted text is under `Prompt from the dforge plugin` (`dagents` in the dagents walk). It reads `Start in …/wt (branch w); its handoff is …/wt/.dforge/handoff/latest.md. If your working directory is not …/wt, enter it first. Continue the unplanned work recorded in …: Probe: the worktree's next step.`. The dagents handoff path ends `.dagents/handoff/latest.md`. The `Invalid API key` result is the report's stated placeholder-key behaviour. The keypress itself is not captured, only the before and after states. |
| UX-2 | proven by test | Both tests build a worktree session with an unfenced handoff at `<wt>/.dforge/handoff/latest.md` (`.dagents` in dagents). They press `pane-resume` and assert the single prompt `Resume the work in ${WT_LATEST} with the <plugin> resume-execution skill.`. This is a mock-level test, and the report says it was not walked live. |
| UX-3 | proven by test | The "reads the session worktree's handoff, not the primary's" test has only the primary's `latest.md` and a worktree session. It asserts `nextStepRuns` is empty, so no offer is raised. The "runs from the primary checkout when the session's directory is gone" test first shows a run from the worktree. It then deletes the worktree directory and its handoff, touches the primary's `latest.md`, and asserts the next run happens from `/home/me/code/shop`. A run only starts when an offer exists, so this shows the offer reads the primary's handoff. No assertion looks at a card. Same pair in both plugins. |
| UX-4 | proven by test and code | `autoRunCall` stats the session checkout and falls back to the primary when it is not a directory. It then runs `bash -c 'cd -- "$1" && shift && exec bash "$@"' auto-run <checkout> …/scripts/auto-run --session …`. The two named tests assert, for every recorded `auto-run` argv, a prefix of `… auto-run <worktree> ` and `… auto-run /home/me/code/shop ` respectively, and that the `compacted` call still runs. The test flow shows `compacted`/`resumed`-style calls, not a `stop` call directly. Both `stop` callers use the same `autoRunCall`, so I count this as covered. The probe note shows that `process.run` already follows `EnterWorktree` into the worktree, so the explicit `cd --` makes that explicit and changes nothing else. |
| OP-1 | proven | Card captures exist at 200x60 and 120x40 for both plugins. The dforge 120x40 pane card is intact with the path cut to `/…/scratchpad/uiw-dforge/wt`. The dforge 120x40 band truncates its title to `…just no…` before the Next line but keeps `[ Resume ]` and `Dismiss`. The dagents 120x40 capture has no pane, and its band carries the full Next line plus both buttons. `dforge-after-120x40` shows the wrapped `Start in` prompt after Resume. |
| OP-2 | proven | The Next line, the card title, the band and the submitted prompt are all plain words in the captures. The focus indicator is reverse video, not colour. |

## Disputed items

None.

## Observations (not disputed)

- At dforge 120x40 the band truncates before the Next line. UI-1 is stated for the 200x60 walk, and the pane card at 120x40 carries the Next line. The report discloses the truncation in OP-1. I count it as existing responsive layout, not a deviation, since this change drew no new control.
- UX-2 and UX-3 have only test evidence. A live walk of the fallback prompt and of the gone-directory case does not exist. The report says so under "Not proven", and the criteria accept a named test whose file I read.
- The report's Automated checks paragraph still describes both the 7b86861c first walk and the 6a6bc3a4 re-walk. It states that the captures come from the re-walk and replace the earlier ones. I cannot confirm that from the files alone.
- No pointer press and no hover were exercised. The report names this under "Not proven", and the touch delta draws no new control.

Verdict: ship 2406b7defe6d1675
