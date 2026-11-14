## Verdict
verdict: ship
scores: coverage 17 / fidelity 18 / states 16 / deviations 17

Disputed items: none.

## What I opened

- Criteria file, the report (Delta and Results), and all six cited captures: the .txt and .ansi twins of settings-context-v200x60, settings-context-v120x40 and settings-context-nohelp-v120x40.
- plugins/dforge/tests/cockpit.test.ts: the whole describe 'keep-warm' (lines 3865-4054) and the World mock it runs on (submitFailures, draft, prompt.read, prompt.submit at lines 388-396), plus autoFiles (line 6209).
- plugins/dforge/hooks/cockpit/register.tsx: the prompt.submit and turn.start handlers, the turn.complete handler (lines 672-730), watchdogTick, keepWarm (lines 3054-3070), isMainBackground and KEEP_WARM_CAP.
- plugins/dforge/config/schema.mjs lines 107-111 (the keepWarm setting).

I did not run the tests. The 558 pass, 0 fail at d3742ddc is the dispatch's statement, not something I re-observed. The "mutation fails the test" remarks in the report's notes are likewise unverified claims and I did not count them as evidence.

## Per item

- UX-1: shown. At 200x60 the .txt (line 38-43) and its .ansi twin show `Keep warm        50min   [ − ] [ + ] [ Edit ]` as the last row of `Context · all defaults`, with help text that matches the schema.mjs description word for word. At 120x40 with help hidden (button reads `Show help`) line 12 shows the same row. Stepper and Edit buttons are drawn alongside the value and unit, like the neighbouring rows.
- UX-2: test "submits the prompt once keepWarm minutes pass..." asserts none at 49 min, one at 51 min, none at 48 min after the keep-warm turn and the second at 51 min after it. Matches keepWarm() (interval measured from the later of last turn end, last keep-warm, watch start).
- UX-3: five tests read. Live turn (t2 started, 10 min at keepWarm 4), auto run bound (autoFiles gives active: true, session sess-1; keepWarm is only called when no active run, and the test also asserts other prompts did go, so it is not a blank world), service command only (`npm run dev`, excluded by isMainBackground), no background work, keepWarm 0. All match the code gates.
- UX-4: test holds a draft through 60 min with zero sent, then clears it and one goes within a minute. The mock's prompt.read returns the draft, and keepWarm() checks `(await $.prompt.read()).text !== ''`.
- UX-5: both tests read. The first asserts no Done from the keep-warm turn and that the later released Done carries `Started it.`; the second asserts the fetch count does not grow. Code: `isHeld` and the `sendDone` branch are both guarded by `!isKeptWarm`, and heldDone is not touched.
- UX-6: both origin variants (composer, task-notification) read. Six go, a seventh only after a turn of another origin. Code: turn.start zeroes keepWarmCount whenever the turn is not a keep-warm turn.
- UX-7: three tests read.
  - Error: no fetch after the failed keep-warm turn (no Turn failed alert), still one prompt sent after 10 more minutes, and the later notification releases a Done whose text is `Started it.` (held Done kept).
  - Aborted: same assertions with reason 'aborted'.
  - Failed submit: the first submit throws, the loop still sends six in total, which only holds if the count was taken back (otherwise five).
  - Code at lines 680-697 agrees: `failed` is false for a keep-warm turn, a non-answer ending sets the count to the cap, and heldDone is only cleared when `!isKeptWarm`.
  - The three names the report cites exist verbatim in the describe.
- OP-1: the 200x60 capture is 60 lines and the two 120x40 captures are 40 lines, consistent with the stated sizes. Default theme only, with the NO_COLOR reason given in the contract. The .ansi twins show no colour beyond the existing reverse-video tab highlight, which supports that reason.

## Observations that do not dispute an item

- Refusal is named in UX-7 but no test uses reason 'refusal'. It takes the same branch as 'error' in the code (`failed` is in the non-answer set, count set to the cap, nothing cleared), so I count it covered by the error test. A direct test would remove the inference.
- At 120x40 with help shown (settings-context-v120x40), the Keep warm row, the card's closing rule and the Back and Hide help buttons are cut off by the window. The report discloses this under OP-1 and gives the help-hidden capture as the 120x40 proof of UX-1. I had no pre-change capture to confirm the clipping already existed for the Auto-compact rows, so the "as for any group taller than the window" explanation is stated, not shown. It is a scrolling and window-height property of the existing settings view, not a change made by this branch, and the report does not mark it pass-with-deviation.
- No capture or test presses the Keep warm stepper, shows `off` at 0, shows an invalid Edit entry, or walks the row by keyboard. The report's "Not proven" section says no test draws or presses the row. For a touch contract whose UX-1 asks only that the row be listed with default, stepper and help, I did not treat this as a dispute, but it is why states scores lower than the others.
- The live keep-warm prompt was never seen in a session (needs background work only a model turn can start). The report says so and the behaviour rests on the tests above.

## Scores

- coverage 17: every item has a row, and the evidence I opened shows each one. Refusal in UX-7 is covered by equivalence rather than a direct test.
- fidelity 18: the Keep warm row has the same shape as its neighbours and the copy matches the schema; the build keeps to the touch scope.
- states 16: the behavioural states (live, auto run, service-only, none, off, draft, cap, reset, error, abort, failed submit) are each tested. The new row's control states and a keyboard walk are not shown.
- deviations 17: no row is marked deviation and I found no difference that changes the contract. The one clipped-window note is disclosed in OP-1.

Verdict: ship 191777b6b40a568d
