# UI proof: cockpit keep-warm

**Contract:** touch
**Fingerprint:** 191777b6b40a568d
**Platform:** terminal
**Viewports:** 200x60, 120x40
**Themes:** default
**Evidence:** local
**Judge:** ship 191777b6b40a568d — docs/dforge/ui-ux/proofs/2026-11-15-cockpit-keep-warm.judge.md

## Delta

**UI/UX depth:** touch — the branch adds the keep-warm rule to the cockpit watchdog in `plugins/dforge/hooks/cockpit/register.tsx` and a `keepWarm` setting the settings view draws; nothing else drawn changes

- **UX-1** — The settings view's Context tab lists `Keep warm` with its default `50min`, its stepper and its help text.
- **UX-2** — Outside an auto run, with background work running and no main turn for `keepWarm` minutes, the cockpit submits the keep-warm prompt, and again after each further interval.
- **UX-3** — No keep-warm prompt goes while a turn is live, while an auto run is bound, when only a service command runs, when no background work runs, or when `keepWarm` is 0.
- **UX-4** — No keep-warm prompt goes while the prompt box holds a draft; one goes once the box is empty.
- **UX-5** — A keep-warm turn leaves the held Done in place and sends no Done of its own.
- **UX-6** — At most six keep-warm prompts go in a row; a turn the person or a task notification starts lets six more go.
- **UX-7** — A keep-warm turn that ends in error, refusal or abort keeps the held Done, raises no Turn failed alert, and stops further keep-warm prompts until a turn of another origin; a submit that fails takes back its count.
- **OP-1** — Proven at 200x60 and 120x40, in the default theme (Claude Code emits colour under NO_COLOR=1, so there is no second theme to walk).

## Results

| ID | Verdict | Evidence | Note |
|---|---|---|---|
| UX-1 | pass | .dforge/ui-ux/cockpit-keep-warm/settings-context-v200x60.txt, .dforge/ui-ux/cockpit-keep-warm/settings-context-v200x60.ansi, .dforge/ui-ux/cockpit-keep-warm/settings-context-nohelp-v120x40.txt, .dforge/ui-ux/cockpit-keep-warm/settings-context-nohelp-v120x40.ansi | at 200x60 the Context tab (hotkey 3) reads `Context · all defaults` and, last in the group, `Keep warm        50min   [ − ] [ + ] [ Edit ]` with the help text `Outside an auto run, while the session waits on background work, the cockpit submits a one-line turn after this many minutes so the prompt cache does not expire. 0 turns it off. Set 4 on the five-minute cache.`; at 120x40 with help hidden (Tab, then the `i` hotkey; the button then reads `Show help`) the same row `Keep warm        50min   [ − ] [ + ] [ Edit ]` is the last row above the card's closing rule |
| UX-2 | pass | test "keep-warm > submits the prompt once keepWarm minutes pass with background work running, and again each further interval" | not reachable live: a background shell needs a model turn, which the placeholder API key starts none of |
| UX-3 | pass | tests "keep-warm > submits nothing while a turn is live", "submits nothing while an auto run is bound to the session", "submits nothing when only a service command runs in the background", "submits nothing when no background work runs", "submits nothing when keepWarm is 0" | a mutation that calls the rule while a turn is live fails "submits nothing while a turn is live" |
| UX-4 | pass | test "keep-warm > submits nothing while the composer holds a draft" | the test answers the plugin's `$.prompt.read()` with the draft; a mutation without the draft check fails it |
| UX-5 | pass | tests "keep-warm > a keep-warm turn leaves the held Done in place and does not become its text", "a keep-warm turn sends no Done of its own" | the first asserts the released Done carries the chain's own answer, `Started it.` |
| UX-6 | pass | tests "keep-warm > stops after six in a row, and a composer turn lets six more go", "stops after six in a row, and a task-notification turn lets six more go" | |
| UX-7 | pass | tests "keep-warm > a keep-warm turn that fails keeps the held Done, raises no alert and stops the keep-warm prompts", "an aborted keep-warm turn keeps the held Done and stops the keep-warm prompts", "a submit that fails takes back its count, so six still go" | added with 0de86851; not reachable live for the same reason as UX-2 |
| OP-1 | pass | .dforge/ui-ux/cockpit-keep-warm/settings-context-v200x60.txt, .dforge/ui-ux/cockpit-keep-warm/settings-context-v120x40.txt, .dforge/ui-ux/cockpit-keep-warm/settings-context-nohelp-v120x40.txt | tmux reported the window as 200x60 and 120x40 at each capture; the Context tab opens at both. With help shown, the 120x40 window ends at the Auto-compact rows and the Keep warm row is below the fold, as for any group taller than the window; with help hidden the whole group fits |

## Automated checks

- Walked on Claude Code 2.1.325 in tmux (`NO_COLOR=1`, a throwaway HOME and config directory, a placeholder API key) with `--plugin-dir plugins/dforge` at the branch head, the window pinned to the stated size.
- Re-walked on 2026-11-15 at d3742ddc after 0de86851 changed `register.tsx`: the three captures were retaken at 200x60 and 120x40 and read as before.
- `claude plugin test plugins/dforge`: 558 pass, 0 fail (at d3742ddc)
- `claude plugin validate` passes on the marketplace and on `plugins/dforge`
- `node scripts/test-all.mjs`: exit 0

## Not proven

- No test draws or presses the `Keep warm` row: UX-1 rests on the two live captures.
- The keep-warm prompt itself was not seen in a live session: it needs background work that only a model turn can start.
