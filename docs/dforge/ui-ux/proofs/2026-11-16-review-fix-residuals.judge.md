## Verdict
verdict: ship 02d3682947ed9349
scores: coverage 17 / fidelity 18 / states 17 / deviations 18

## Scores

### Every Item Has Evidence (coverage): 17

Opened this round: the 200x60 and 120x40 `-toast`, `-after-press` and `-after-10s` captures, the `-sticks-*` captures, the 32 `consent-*` captures (text and `.ansi`), the cited tests in `plugins/dforge/tests/cockpit.test.ts` (lines 8423-8462 and 8502-8514), and `claudeReadBack` and `setOption` in `plugins/dforge/hooks/cockpit/register.tsx` (lines 4155-4217).

- UX-1, dropped save: both `-toast` captures show the host toast box with `dforge: autoCompactWindow did not stick` / `(the engine kept no value). Set it` / `again, or edit Claude's settings.json.` and no `…` inside the box. The 120x40 `…` is the host's cwd line, outside the box. `-after-press` reads `100k ... *`; `-toast` and `-after-10s` read `unset`, and `-after-10s` has no toast. Shown at both sizes. The test "a Claude-key save the engine drops says what to do about it" asserts the exact text and that it wraps to at most three 40-column rows.
- UX-1, kept save (the item disputed in round one): the new test "a Claude-key save the engine keeps stays and toasts nothing" settles it.
  - The press runs `claudeReadBack`, whose first poll runs at once. At that moment the mocked user settings still hold the old 650000, so the poll misses.
  - The test then sets `w.userSettings` and `w.settings` to the value the press saved, which it reads from the recorded `dforge-config set` run. The test advances the clock one second at a time for 10 s and asserts after every step that no `did not stick` toast exists. That covers the 3 to 7 s window where the dropped-save toast appears, and the read-back's whole 3 s wait.
  - It also asserts the row still shows the saved value.
  - The mocked `settings.read` returns `userSettings` for `source: 'user'`, which is what `claudeReadBack` queries.
  - Without the `return` at line 4200, the loop would run out its 3 s wait. `S.claudeSaved[key] === value` would still hold, so line 4213 would toast and the test would fail. The test therefore does exercise the kept-value path.
  - The four `-sticks-*` captures agree at 0 s and 12 s (`100k`, mark `*`, no toast), and the test fills the gap between them.
  - I read the test and did not run it, as I have no shell. The report's claim of 662 passing is unverified by me, but the test body is sound.
- UX-1, the 10 s clear: the `-after-10s` captures read `unset` with no toast. The 200x60 clear is unclocked and the 120x40 clock comes from a repeat press; the report says both. The captures are enough for "within 10 seconds". Not disputed.
- UX-2: `consent-plus-focus-*`, `-plus-focus-second-*` and `-edit-prompt-*` show `API budget: AgentRouter (USD): confirm a cap of 5?` (20 on the typed path) with `[ Confirm ] [ Cancel ]`. Searching the `.ansi` files for reverse-video runs finds `[ Confirm ]` alone in those captures. `-cancel-focus-*` has the ring on `[ Cancel ]`. `-after-cancel-*` reads `off [ − ] [ + ] [ Edit ]` with the ring on `[ + ]`. `-after-confirm-*` reads `5 ... *` and `-edit-confirmed-*` reads `20 ... *`. `-edit-field-*` and `-edit-typed-*` show the typed path (`0 ⏎ save [ Cancel ]`, then `20`). The cited test asserts only `autoFocus`, as the report admits, so the captures carry the ring claim. "No config file yet" and "wrote `{"apiBudgetAgentRouter": 5}`" have no cited artifact, only the screen state. The sibling test "raising the AgentRouter cap from 0 needs a second press" backs both. The ring lands on `[ − ]` after a confirm, which the report does not mention and the contract does not cover.
- OP-1: both items have captures at 200x60 and 120x40. Shown.
- OP-2: searching all `.ansi` files for any SGR code other than 0 and 7 finds none, so there is no colour. Focus is reverse video. Tab and Enter reached every control walked. Every state is carried by words or marks: `did not stick (the engine kept ...)`, `confirm a cap of 5?`, `*`.

### Built Matches Promised (fidelity): 18

The toast text matches the contract word for word, apart from the engine value in the parentheses. The consent line carries the cap, the third party and two named buttons, with the ring on Confirm at both sizes and on the typed path. The row layout is unchanged. Nothing was dropped or substituted, and there is no colour.

### Every State Is Shown (states): 17

Shown at both sizes: the dropped save (before, pressed, toasted, cleared), the kept save (0 s and 12 s captures, plus the per-second test across the toast window), the consent prompt, Confirm focus, Cancel focus, cancel result, confirm result, the typed-value path, and keyboard reach by Tab and Enter. The report's Not proven section states that no pointer press was made and that no ring shows in the typed edit field. A pointer press is acceptable to leave unproven for a keyboard contract.

### Deviations Are Cited (deviations): 18

The report has no deviation rows and I found no difference that needs one. The Not proven section is honest about the host toast box size, the unclocked 200x60 clear and the missing pointer press.

## Disputed items

None. Round one's UX-1 dispute (a save the engine keeps toasts nothing) is resolved by the new keep test, which checks every second across the toast window.

Verdict: ship 02d3682947ed9349
