## Verdict
verdict: ship 397c08400e3620b0
scores: coverage 18 / fidelity 18 / states 17 / deviations 18

## Evidence opened

- `.dforge/ui-ux/cockpit-keep-warm/settings-context-v200x60.txt` (and `.ansi`): 200x60 capture, help shown.
- `.dforge/ui-ux/cockpit-keep-warm/settings-context-v120x40.txt` (and `.ansi`): 120x40 capture, help shown.
- `.dforge/ui-ux/cockpit-keep-warm/settings-context-nohelp-v120x40.txt` (and `.ansi`): 120x40 capture, help hidden (the new one).
- `plugins/dforge/tests/cockpit.test.ts`, `describe('keep-warm'` block (lines 3865-4005).
- `plugins/dforge/hooks/cockpit/register.tsx`: `keepWarm` (3052-3068), `watchdogTick` gates (3011-3022), `prompt.submit` and `turn.start` and `turn.complete` handlers (606-696), `isMainBackground` (2656).
- The Keep warm setting in `plugins/dforge/config/schema.mjs:109`.

## Item by item

- UX-1, covered. The 200x60 capture shows the Context tab (`Context · all defaults`) with `Keep warm        50min   [ − ] [ + ] [ Edit ]` as the last row of the group, followed by the help text "Outside an auto run, while the session waits on background work, the cockpit submits a one-line turn after this many minutes so the prompt cache does not expire. 0 turns it off. Set 4 on the five-minute cache." That is the default, the stepper and the help text. The new 120x40 capture with help hidden (button reads `Show help`) shows the same row as the last row above the card's closing rule. It no longer depends on a fold.
- UX-2, covered by the test "submits the prompt once keepWarm minutes pass with background work running, and again each further interval". It checks no prompt at 49 minutes, one at 51, none at 48 more minutes after the keep-warm turn, and a second at 3 more. The tick (`watchdogTick` to `keepWarm`) computes elapsed time from the latest of the last turn end, the last keep-warm and `watchedSince`, which is what the test exercises. The report says the live path is not reachable (a model turn is needed to start background work); the report lists this under Not proven, and the test covers it.
- UX-3, covered. Each negative case has its own test: live turn, bound auto run, service-only command, no background work, `keepWarm` 0. The code agrees: `watchdogTick` returns while `S.isTurnLive`, `keepWarm` returns on 0 minutes, `isMainBackground` excludes service commands, and the keep-warm call is reached only when no auto run is active. The auto-run test also asserts that prompts did go through the other path (`w.prompts.length > 0`), so it is not trivially passing.
- UX-4, covered by "submits nothing while the composer holds a draft": no prompt at 60 minutes with a draft, one prompt a minute after the draft is cleared. It matches the `$.prompt.read()` check in `keepWarm`.
- UX-5, covered by two tests. One checks that no Done is sent after a keep-warm turn and that the later released Done carries `Started it.`. The other checks that a keep-warm turn adds no fetch. This matches the `isKeptWarm` branch in `turn.complete`, which leaves `heldDone` alone.
- UX-6, covered by two tests, one per origin (composer and task-notification). Each reaches six keep-warm prompts, no seventh, then a seventh after a person or notification turn. This matches `KEEP_WARM_CAP = 6` and the reset in `turn.start` when the turn is not a keep-warm one.
- OP-1, covered. Three captures exist at 200x60 and 120x40, default theme only. The report states the help-shown 120x40 window ends at the Auto-compact rows and says why. Its claim of a single theme (colour is emitted under NO_COLOR=1) is stated, not something I could check from the text captures, and it does not change what the contract asks.

## Criteria notes

- Coverage: every contract item has a row, and its evidence opened and shows that item. Not 20 because UX-2 to UX-6 rest on tests alone and the keep-warm prompt was never seen live; the report says so.
- Fidelity: the `Keep warm` label, the `50min` value, the `[ − ] [ + ] [ Edit ]` controls and the help copy in the captures match the contract's wording, and the row sits in the same format as the Auto-compact rows above it. No element dropped, no copy changed.
- States: the contract is a touch contract with no state matrix beyond the behaviour items, and each of those has a test. Not higher because no test presses or draws the Keep warm row (stepper, edit) and no keyboard walk of it exists; the report lists this under Not proven, and the contract asks only that the row be listed.
- Deviations: no row is marked deviation and I found no uncited difference. The one visible difference (Keep warm below the fold at 120x40 with help shown) is disclosed in the OP-1 note and answered by the help-hidden capture.

## Disputed items

None.

Verdict: ship 397c08400e3620b0
