## Verdict
verdict: ship de31263525d8c6cd
scores: coverage 17 / fidelity 17 / states 16 / deviations 16

Round two. Both earlier disputes are answered by captures I opened. No item is
disputed.

## Item review

| ID | Ruling | What I opened |
|---|---|---|
| UI-1 | proven | dforge-card-200x60 and dagents-card-200x60. Pane card reads `↻ Resumable work · handed off just now` (dagents: `1m ago`) over `Next: Probe: the worktree's next step.`. The band reads the same Next line after `—`. The string "primary's next step" appears in neither capture. The setup (the primary holding a different block) is the report's statement only; the test "reads the session worktree's handoff, not the primary's" backs the behaviour. |
| UX-1 | proven | dforge-resume-focus and dagents-resume-focus: the band `[ Resume ]` is SGR `1;7` (reverse), where the card captures show it as `1` only. dforge-resume and dagents-resume: `› Prompt from the dforge plugin` (dagents: `dagents`) followed by `Start in <wt> (branch w); its handoff is <wt>/.dforge/handoff/latest.md. If your working directory is not <wt>, enter it first. Continue the unplanned work recorded in <wt>/.dforge/handoff/latest.md: Probe: the worktree's next step.` (dagents path `.dagents`). The text matches the contract's opening. The keystrokes `ctrl+x tab` and Enter are not in the captures; the focus-then-submit sequence is inferred from the before/after states. This is the earlier UX-1 dispute: the dagents focus capture now exists and shows reverse video. |
| UX-2 | proven by test | Test "names the absolute handoff path in the fallback resume prompt (spec A9)" in both cockpit.test.ts files (dforge 5713, dagents 5584). It uses a worktree handoff with no fence and asserts the submitted prompt equals `Resume the work in <WT_LATEST> with the <plugin> resume-execution skill.`. `resumePrompt()` in both register.tsx files builds exactly that string from `S.latestName`. |
| UX-3 | proven by test | "reads the session worktree's handoff, not the primary's (spec A9)" asserts `nextStepRuns` is empty when only the primary holds a handoff. In the sibling test a worktree handoff makes `nextStepRuns` equal `[WORKTREE]`, so an empty list does mean no offer was raised. The test does not assert `resume-card` absent directly; that is a weaker form, but sound. "runs from the primary checkout when the session's directory is gone" deletes the worktree and its handoff and asserts the next run is from `/home/me/code/shop`. `readRun` (`isGone`, `here`) matches in both plugins. |
| UX-4 | proven by test | "passes the session checkout to every auto-run call (spec A8)" asserts every auto-run argv starts `bash -c cd -- "$1" && shift && exec bash "$@" auto-run <WORKTREE> ` and that at least one call was made. `autoRunCall` in both plugins builds that argv. The probe note records the cockpit's calls running in the worktree after `EnterWorktree`. |
| OP-1 | proven | dforge-card-120x40 and dagents-card-120x40 show the pane card with `Next: Probe: the worktree's next step.` in both plugins. dforge-after-120x40 shows the submitted `Start in …` prompt wrapped to 66 columns. 200x60 captures exist for both plugins. This is the earlier OP-1 dispute: the 120x40 card is now shown. The band at 120x40 truncates before the Next line (dforge title cut to `just no…`, dagents `1m ago …`), so the Next line there comes from the card, which the report says. |
| OP-2 | proven | Card text and prompt are plain words (`Next: …`, `Start in …`). The Resume focus state is reverse video, not colour-only. |

## Per criterion

- coverage 17: every item has a row. UI-1, UX-1 and OP-1 are backed by opened captures; UX-2 to UX-4 by tests I read plus the code they exercise. UX-3's test is indirect, and the "different block in the primary" setup is not visible in any capture.
- fidelity 17: the copy of the card, band title, Resume and Dismiss controls, and the submitted prompt match the contract in both plugins. Nothing is dropped or substituted.
- states 16: 200x60 and 120x40 are covered, keyboard focus is shown for both plugins, and the after-submit state is shown. Fallback prompt, no-handoff, gone-directory and auto-run cwd are test-only. No hover, no pointer press (the report says why), and no 120x40 focus or after-Resume capture for dagents; none is required by the contract.
- deviations 16: the report marks no row as deviation. The only difference I found is the 120x40 band truncation, which the report states openly, and the band layout is not something this delta changed. Nothing is passed with an uncited difference.

## Disputed items

None.

Verdict: ship de31263525d8c6cd
