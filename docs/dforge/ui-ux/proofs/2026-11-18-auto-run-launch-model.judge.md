## Verdict
verdict: ship 73ea50846f939017
scores: coverage 16 / fidelity 17 / states 16 / deviations 16

## Disputed items

None.

## What I opened

All six captures under .dforge/ui-ux/2026-11-18-auto-run-launch-model/ (dforge and dagents, before 200x60, after 200x60, after 120x40), the five cited test files, and the `launched` and `S.launch` code in both cockpit register.tsx files (read in full for dforge, located by search in dagents).

## Per-item findings

- UI-1: supported. dforge-before and dagents-before show the Account card line `Haiku 5.5` (no effort). dforge-after-200x60 and dagents-after-200x60 show `Sonnet · low effort` on the same card, on the right-hand pane. The after captures follow a visible `/clear`. The code explains the readout: the `turn.step` hook rewrites the step first and then stores the rewritten model and effort in the `engine` atom that the card reads (register.tsx lines 771-777). The engine's own header still says `Haiku 5.5 with low effort`. The report states this in the UI-1 note and under Not proven, and the contract does not ask for the header to change.
- UX-1: supported by tests, and by the Account card capture indirectly. The cited cockpit.test.ts test in each plugin sends a main-loop step and a subagent step (`agentId` set). The main-loop step goes out as `sonnet`/`high`, and the subagent step keeps `claude-opus-5-5`/`max`. The `launched` function matches: it skips any step with an `agentId`, and any step from a different session. The captures do not show which model produced the replies. That claim rests on the unopened transcripts, so the engine honouring the rewritten request is the one part I could not confirm. The tests and the card readout make it likely.
- UX-2: supported. The dforge test (plugin-review-fixes A41, "a switch now leaves no snapshot and writes no settings") asserts no snapshot file, no `claude-restore` run and unchanged user settings. The dagents cockpit.test.ts test asserts no `claude-restore` run and unchanged user settings. dagents has no test of its own for "no snapshot file written", but its register.tsx has only a reader and sweeper of snapshots, no writer. The sha256 and scratch-HOME claims come from the walk and I could not open them. I weighed them against the tests, and they agree.
- UX-3: supported. dforge-after-200x60 and dagents-after-200x60 show `/clear`, then `Prompt from the dforge plugin` (`dagents` in the dagents capture), then the probe prompt, then `Probe resumed.`. No `/model` or `/effort` is on screen. Both plugins' A1 acceptance tests assert `commands` equals `['/clear']` and `prompts` equals `[FIRST_PROMPT]`, so no extra note is sent.
- OP-1: supported. dforge-after-120x40 and dagents-after-120x40 are 40-row captures about 120 columns wide, and the docked pane shows `Sonnet · low effort` in both. The 200x60 captures are 60 rows and 200 columns.
- OP-2: supported. The model and effort are plain words (`Sonnet`, `· low effort`) on the card line, so nothing depends on colour.

## Criteria notes

- coverage: every Delta item has a row with evidence I opened. The unopened transcripts and hashes are backed by tests. Held below the top band for two reasons: UX-1's real-engine effect is shown only by transcripts, and dagents has no dedicated no-snapshot test.
- fidelity: the Account card keeps its layout and gains the `Sonnet · low effort` text, with the same bold model word and grey effort suffix as the other cards. No element is dropped and the copy matches the contract.
- states: the touch contract names one before and after pair, at two viewports, in two plugins. All are captured. The case with no launch model is tested ("leaves the requests and the settings alone when the clear sets no model"). The change adds no control, so hover, focus and pointer states do not apply, and the report says so under Not proven.
- deviations: no row is marked deviation. The one visible difference I found is the engine header still reading Haiku while the card reads Sonnet. The report discloses it and names the engine as the limit, which the cockpit cannot change. I count that as cited.

Verdict: ship 73ea50846f939017
