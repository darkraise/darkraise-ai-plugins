# Review-depth light re-check — 2026-10-28

**Sample size:** 8
**Plans with a silent plan-review finding:** 5 (P1, P2, P3, P4, P6)
**Verdict:** assumption fails for plan review — 5 of 8 is more than one in four, so register row 1 stops for a ruling on keeping one plan-review round at light; acceptance QA is unmeasured and stays deferred

This re-runs the riskiest assumption of `docs/dforge/specs/2026-10-27-review-depth-design.md` on evidence the first measurement (`docs/dforge/notes/2026-10-27-review-depth-measurement.md`) did not search: the plan-review seat outputs held in Claude Code subagent transcripts. The question: on plans whose tasks are all at risk 1 or below, does plan review rarely find a defect that the rest of the light process (task and group reviews, gates, one Opus final review) would miss?

## Method

- **Source.** Every subagent transcript under `/root/.claude/projects` (all accounts share it; retention about 30 days, the oldest on 2026-09-27) whose prompt carries the plan-review rubric (executability, coherence) and whose reply carries findings. 116 real plans across six repositories hold one; eval fixtures under `/tmp` are excluded.
- **Sample.** A plan is in it when its plan file, in its repository or recovered from git history (the ghr plans were deleted in `fd9a986`), has every `**Evaluation:**` line at risk 1 or below. Bands of the 116: 8 light, 39 standard, 69 full. Spec-side triggers were not applied, because these specs predate the `**Depth:**` line; that can only admit riskier plans, which leans against light.
- **Classification.** Each Critical and Important finding of every held round went to one `dforge:judge-opus` dispatch with the plan text, in four classes: **loud** (the implementer's own steps would stop on it), **reviewable** (a group task reviewer or the final Opus review would plausibly flag it against the spec), **silent** (would plausibly ship), **not-a-defect** (plan form only). A tie went to the class worse for the assumption. A plan is a hit when it has at least one silent finding. Minor findings were not classified.
- **Rule.** The spec's: more than one in four hits stops for a ruling; one in four or fewer holds; fewer than four plans is inconclusive.

The classification is counterfactual inference, not observation: these findings were fixed before execution, so what the light process would have done with them is the judge's reading of each finding's own claim (most say no test or probe covers the defect) and of what a diff-against-spec reviewer notices. Nothing was executed.

## Sample

| # | Plan | Tasks | Rounds | Critical / Important | Silent | Hit |
|---|---|---|---|---|---|---|
| P1 | darkcloud `2026-10-11-soft-glass-component-polish` | 10 | 2 | 2 / 11 | 8 | yes |
| P2 | darkcloud `2026-10-12-bulk-move-waits` | 3 | 1 | 0 / 1 | 1 | yes (borderline) |
| P3 | darkcloud `2026-10-12-file-picker-redesign` | 10 | 2 | 3 / 7 | 5 | yes |
| P4 | darkpanel `2026-10-23-v1-w0b-host-clients` | 13 | 1 | 0 / 3 | 3 | yes |
| P5 | darkpanel `2026-10-21-m2-local-timeout-and-readme` | 2 | 1 | 0 / 0 | 0 | no |
| P6 | darkraise-ai-plugins `2026-10-18-controller-model-eval` | 4 | 1 | 2 / 8 | 10 | yes |
| P7 | darkraise-web-template `2026-10-06-controls-c2` | 17 | 1 | 0 / 0 | 0 | no |
| P8 | ghr `2026-10-13-ghr-artifacts-revamp` | 5 | 1 | 0 / 0 | 0 | no |

Findings by class: 7 loud, 1 reviewable, 27 silent, 2 not-a-defect. Counting reviewable findings as hits gives the same five plans.

## How firm the verdict is

- **Borderline calls.** Moving every borderline finding (P1-F2, P1-F7, P1-F10, P2-F1, P3-F7, P3-F10) out of silent flips only P2. P1, P3, P4 and P6 stay hits on clearly silent findings — P1-F3, P1-F4, P1-F13, P3-F8, P3-F9, P4-F2, P6-F9 — so 4 of 8, still above one in four.
- **P6.** Eight of its ten silent findings are requirements not carried into a register row for a later plan, not code this plan ships; F9 and F10 make it a hit without them.
- **What kind of defect plan review catches here.** Four of the seven Critical findings are loud (P1-F2, P6-F1 and P6-F2 are not): a test that cannot pass, a step whose own check fails. The silent ones are mostly Important: a spec clause no task implements, a test or probe that passes vacuously, a premise about code outside the diff. Those are the cases a diff-scoped review is least likely to see.
- **Not tested here.** Whether a light final review finds these anyway; the judge's estimate is that it would not, because the defect sits outside the diff or behind a passing test.

## Acceptance QA

No sampled plan holds an `Acceptance QA` run; the held QA runs in the transcript store are mostly eval fixtures. That half of the assumption stays deferred, and its re-check moves to a register row of its own.

## Findings (verbatim from the plan-review transcripts)

Each finding's id, severity, round and date, as extracted; the class and the judge's reason follow in the table after them.

### P1: darkcloud/docs/superpowers/plans/2026-10-11-soft-glass-component-polish.md

Tasks: 10, risk scores {1: 8, 0: 2}; plan-review rounds held: 2

#### P1-F1 [Critical] round 1 (2026-10-11)

- [Critical] [Task 5]: The existing test `offers the three modes and the four palettes…` will fail after the rewrite, and the plan tells the implementer to report BLOCKED when it does.
  - Why: the test names each radio by `radio.getAttribute("aria-label") ?? radio.parentElement?.textContent`. A `SegmentGroupItem` is a `<button role="radio">` whose parent is the radiogroup `<div>` (`chunk-WCQSKHZB.js:186-199`, `chunk-ECVNECFC.js:107-121`), so the test receives `"SystemLightDark"` three times and `"AuroraLagoonDawnPlain"` four times. Step 5's claim that both existing cases "keep passing unchanged" is false, so the task stops at Step 5 every time.
  - Fix: have Step 1 change that mapping to `radio.textContent`, and delete the BLOCKED instruction.

#### P1-F2 [Critical] round 1 (2026-10-11)

- [Critical] [Task 6]: Every coloured badge turns grey on hover.
  - Why: the base rule's selector list includes `html[data-preset="glass"] .dr-badge[data-variant]:hover` (specificity 0,4,1) and declares `--dc-badge-hue: hsl(var(--muted-foreground))`. That outranks each per-hue rule such as `…[data-variant="green"]` (0,3,1), so the hue, and the dot with it, resets while hovered. No test or browser check hovers a badge. The `:hover` selector is also unnecessary: the kit's hover rules are (0,3,0) and already lose to the base rule.
  - Fix: drop the `:hover` selector from the base rule, or move the `--dc-badge-hue` default into a separate rule without `:hover`.

#### P1-F3 [Important] round 1 (2026-10-11)

- [Important] [Task 5]: A selected toggle-group item keeps the kit's gradient and 2px inset ring under the new tint.
  - Why: toggle-group items always carry `data-state="on"` when pressed (`chunk-UBF5ARVB.js:241-243`). The kit's `[data-preset="glass"] .dr-toggle[data-variant=…][data-state="on"]` (0,4,0) sets `background-image: var(--glass-state-selected-fill)` and a `box-shadow` containing `--glass-state-active-inset`. The plan's item rule that resets them is (0,3,1) and loses; the current-item rule (0,4,1) resets neither property. Step 6 reads only `bg` for that item, and Task 10 probes the group container, so this ships.
  - Fix: add `background-image: none; box-shadow: none;` to the current-item rule and assert both in the test.

#### P1-F4 [Important] round 1 (2026-10-11)

- [Important] [Task 5]: A track wider than its container cannot be scrolled back to its first items.
  - Why: the kit's `.dr-tabs-list[data-variant="default"]` and `.dr-toggle-group` are `justify-center` (`styles.css:6284`, `:7339`). The plan adds `overflow-x: auto` without changing justification, so overflow on the leading side is unreachable. The 390px check only reads the list width and the active tab's height.
  - Fix: add `justify-content: flex-start` to the track rule and assert it.

#### P1-F5 [Important] round 1 (2026-10-11)

- [Important] [Tasks 1–9]: Every commit block runs `cd web && npm run typecheck && npm run lint` and then `git add web/src/…` in the same block.
  - Why: run as one shell block, the paths resolve to `web/web/src/…`, `git add` fails with a pathspec error, and the commit that follows has nothing staged.
  - Fix: use `(cd web && npm run typecheck && npm run lint)`, or `git -C` with root-relative paths.

#### P1-F6 [Important] round 1 (2026-10-11)

- [Important] [Task 10]: The Step 4 overlay contrast check has a predetermined result and stops the task before the end-to-end run and the redeploy.
  - Why: a 46% white layer over the plan's pure black sheet composites to about `rgb(117,117,117)`, where body text `#1a1e2b` is about 3.6:1 by arithmetic. The step says not to continue to Step 5 below 4.5. The measurement the spec actually asks for (darkest real cover, white PDF page) is never taken, so the owner gets a bound the spec already predicted (about 4:1) and nothing new.
  - Fix: measure the two real cases the spec names and keep the synthetic sheet as a secondary figure, or let Steps 5–6 proceed and gate only the merge.

#### P1-F7 [Important] round 1 (2026-10-11)

- [Important] [Task 4]: Spec §2 "Invalid: destructive border" has no rule, and the new field rule suppresses the kit's.
  - Why: the kit sets the invalid colour through `&:where([data-invalid], [aria-invalid="true"])` (`styles.css:11422`), which adds no specificity. The plan's `border: 1px solid var(--sg-ctl-edge)` and its focus rule both outrank it, so an invalid field looks valid.
  - Fix: add `[aria-invalid="true"]` and `[data-invalid]` rules for rest and focus, with a test.

#### P1-F8 [Important] round 1 (2026-10-11)

- [Important] [Task 3 / Task 5]: The component tests spec "Testing" requires for the §9 call sites are not written.
  - Why: no test in `web/tests/files-*.test.tsx` asserts `aria-pressed` (grep found none), so the details toggle's pressed state and its fixed `outline` variant are unproven; the edit passes with either reverted. The tab-strip switch relies on unnamed existing cases in `jobs-pages` and `library-settings-general`, and `settings/LibrarySettingsPage.tsx` has no named test at all.
  - Fix: add one `aria-pressed` assertion for `InfoToggle`, and name the tab-switch case per strip.

#### P1-F9 [Important] round 1 (2026-10-11)

- [Important] [header / all tasks]: The spec's proof rule (each clause in §1–§8 removed, one named test fails) is reduced to one mutation per task, and many declarations have no test at all.
  - Why: untested declarations include the dropzone, the disabled opacity, the checked switch thumb in dark, the slider track, the field hover edge, the menu item height and radius, the tooltip radius, the alert icon, the table head size and the scrim blur. A later edit can delete any of these silently.
  - Fix: add assertions for them, or record the narrowing as a spec deviation for the owner.

#### P1-F10 [Important] round 1 (2026-10-11)

- [Important] [Task 7 / Task 8]: Several spec clauses are not implemented and not listed as deviations.
  - §5: numeric columns tabular; row-action and pagination buttons ghost; rows-per-page select at 28px.
  - §5: "no frame when the table sits in a card or panel" is applied to every table.
  - §6: the selected tree row's icon takes the accent (only the row's `color` is set, to foreground).
  - §7: overlay corners 8px (no radius rule).
  - §7: menu hover is `--sg-fog` in the spec, but Task 8 writes and tests `--sg-track`.
  - §4: toast status icon in its hue.
  - Fix: add the rules, or list each in Assumptions as a deviation for the owner, as was done for the menu check mark.

#### P1-F11 [Important] round 1 (2026-10-11)

- [Important] [Task 6]: State badges are dotted inconsistently.
  - Why: `MaintenanceTab.tsx:162` renders the same `jobStateVariant(job.state)` badge as the two jobs call sites and gets no dot. The spec's "library scan state" badge is not located; the plan only rules out `LibraryScanStatus.tsx:121`. Other state badges (`MountsTable.tsx:46`, `NetworkSharesTable.tsx:42,52`, `LiveQueue.tsx:117`, `UploadPanel.tsx:117`) are not classified either way.
  - Fix: add `MaintenanceTab.tsx:162` and state a decision for each of the others.

#### P1-F12 [Important] round 1 (2026-10-11)

- [Important] [Assumptions]: Facts the tasks rely on are not listed with evidence.
  - The npx cache path and the Chromium binary path hard-coded in both probe scripts (the `playwright-core` path does exist; the Chromium path was not checked).
  - The `localStorage` key `mode` used to set the theme.
  - Pillow for Task 10's Python step.
  - The click selectors `.dc-shell-header button:last-of-type`, `.dc-shell-content [aria-haspopup="menu"]` and `.dc-shell-sidebar a[href*="-"]`.
  - The DOM shape behind `> span:first-child svg` for menu indicators.
  - `Badge` forwarding `data-dot` (true per `chunk-JIT3S2RF.js`, but uncited).
  - Two listed assumptions are marked unverified although the kit settles them: a segment item does carry `dr-radio-group-item` (`styles.css:5172-5177`), and a pressed toggle-group item carries `data-state="on"` plus `aria-checked` or `aria-pressed`.

#### P1-F13 [Important] round 2 (2026-10-11)

- [Important] [Task 8]: The fill rule paints every `[role="listbox"]`, and three are inline page content, not floating layers: `FilesGrid.tsx:206` (the `/files` grid), `TrashView.tsx:178` and `DetailsList.tsx:126`. None carries a `bg-*` utility. - The main Files page gains a 46% white (dark: 46% `#111421`) slab on its panel. No test or probe catches it, because the Task 8 check reads `[role="listbox"]` only after opening a select on `/admin/jobs`. The plan relies on the unlisted fact that every element with these roles floats. - Scope the Task 8 fill rule and its test string to the kit's own classes: `.dr-menu-content, .dr-menu-sub-content, .dr-select-content, .dr-dialog-content, .dr-drawer-content, .dr-popover-content, .dr-toast`. Add a `/files` probe line expecting the grid's `bg` to be `rgba(0, 0, 0, 0)`. Record that the existing unlayered rule already gives those three lists a border, lift shadow and blur.

### P2: darkcloud/docs/superpowers/plans/2026-10-12-bulk-move-waits.md

Tasks: 3, risk scores {1: 3}; plan-review rounds held: 1

#### P2-F1 [Important] round 1 (2026-10-12)

- **[Important] Task 1: three routing doc comments the spec requires to be updated are left stale.** The spec says "The doc comments in `BatchOperationService.cs` and `BatchEndpoints.cs` that describe the routing are updated to match." Task 1 only edits the `BatchOptions` summary and `BatchEndpoints.cs:49`. These stay wrong:
  - `BatchOperationService.cs:46-49`, the interface doc on `RequiresJobAsync`, still says "a move/copy/trash whose selection includes a folder with descendants".
  - `BatchEndpoints.cs:14-16`, the class summary, still says "or a recursive directory op".
  - `BatchEndpoints.cs:51-52` still says "the only job-read route serves archive jobs only; a job-result read surface is deferred work". That is false (`GET /api/v1/jobs/{id}` is generic), and Task 1's new `api.ts` comment sends readers there with "(see BatchEndpoints.cs)".

  Why it matters: no test catches a stale comment, and the next reader of the routing code is told the opposite of what it does. Fix: add replacements to Task 1 Step 3 for those three comment blocks, with exact old and new text, and add the line ranges to the Files block.

### P3: darkcloud/docs/superpowers/plans/2026-10-12-file-picker-redesign.md

Tasks: 10, risk scores {1: 9, 0: 1}; plan-review rounds held: 2

#### P3-F1 [Critical] round 1 (2026-10-12)

- [Critical] [Task 1]: The test `adds a Shift range and Ctrl+A to a pick made in another folder` cannot pass against the plan's own implementation. After ticking Outer, `screen.getByText("Outer")` matches the row, the harness's `<div data-testid="picked">Outer</div>` and the old `PickedList` name span, so Testing Library throws "Found multiple elements". - Step 4's "Expected: PASS" is unreachable and this is the test Step 5's mutation check names, so a literal executor will bend correct code or the test to get green. - Open the folder with `screen.getByRole("button", { name: `${t("browser.open")} Outer` })` instead.

#### P3-F2 [Critical] round 1 (2026-10-12)

- [Critical] [Task 2]: The test `keeps the highlighted row while the filter reloads the listing` fails the same way. Clicking Alpha in single-select makes the harness `picked` div read exactly "Alpha", so the later `await screen.findByText("Alpha")` finds two elements and times out. - It is the test Step 5's mutation names, so "exactly this test fails" holds with or without the mutation and proves nothing. - Wait on `screen.findByRole("row", { name: /Alpha/ })`, or scope the query with `within(screen.getByRole("table"))`.

#### P3-F3 [Critical] round 1 (2026-10-12)

- [Critical] [Task 4]: The test `creates the folder with the typed name and selects it` fails for the same reason. `createNamedFolder` sets `setNaming(null)` and `onChange(replacePick(created))` in one batch, so once the name field is gone both the new row and the `picked` div read "Light novels" and `findByText("Light novels")` throws. - Step 4 cannot go green as written. - Assert the row through `within(screen.getByRole("table")).findByText("Light novels")` or through its Open button's name.

#### P3-F4 [Important] round 1 (2026-10-12)

- [Important] [header]: The Assumptions section lists nothing about the test harness rendering pick names as plain text, which is what breaks the three tests above. - Existing tests deliberately avoid re-querying a picked name by text; the new ones do not. - Add a Global Constraint: in `tests/file-browser.test.tsx`, never use `getByText`/`findByText` on a name that is currently picked; query by role or inside the table.

#### P3-F5 [Important] round 1 (2026-10-12)

- [Important] [Task 10]: The probe relies on environment facts that appear nowhere in Assumptions. These are the theme key `localStorage "mode"` (no such key found in `web/src`), the route `/library/manage` with a "New library" button, the `/api/v1/library/libraries` response shape, and credentials "recorded in the `measure-layout-in-a-browser` memory note". - A wrong one surfaces only as an `error` entry, with a fallback named only for the 390px Move case, and a wrong theme key silently measures light twice. - List each with file:line evidence, give a fallback per `try` block, and add a probe field that reads the applied mode so the dark runs are proven dark.

#### P3-F6 [Important] round 1 (2026-10-12)

- [Important] [Task 6]: The non-roomy dialog gets no width class; the spec's `max-w-lg` depends on the kit's `DialogContent` default, which is not in Assumptions (I found no `max-w` in `chunk-KHIZQVEE.js`). The interaction of `h-[min(40rem,85dvh)]` with the phone dialog rule from commit `6c735281` is also unstated. - Both are discovered only at Task 10, three tasks after the code is committed. - Write `max-w-lg` explicitly on the non-roomy branch, and list the phone rule as unverified with Task 10 as its verifying step.

#### P3-F7 [Important] round 1 (2026-10-12)

- [Important] [Task 5]: Two toolbar behaviours diverge from spec section 1. The filter closes only on blur, though the spec says "clearing or blurring an empty filter restores the location". Clicking the toggle while it is open with an empty filter blurs it closed and then toggles it open again, so the icon cannot close it. No test covers the icon mode at all; deleting `filterOpen` leaves every test green. - A requirement is only partly built and is unprotected. - Close in `onFilterChange` when the text becomes empty, use `onMouseDown` with `preventDefault` on the toggle, and add a jsdom test that clicks `browser.filterToggle` and asserts focus and `aria-pressed`.

#### P3-F8 [Important] round 1 (2026-10-12)

- [Important] [Task 4]: The name field is `disabled={naming.busy}`, and a disabled input loses focus. After a 409 the field is enabled again but unfocused, although the spec says the failure "leaves it editable"; the test only checks `toBeEnabled()`. - The user must click back into the field to retry, and Escape no longer reaches it. - Use `readOnly` while busy, or refocus when `busy` goes false, and assert `toHaveFocus()` in the conflict test.

#### P3-F9 [Important] round 2 (2026-10-12)

- [Important] [Task 10]: The probe measures the wrong element for scrolling. `scroller = el.querySelector("table")?.parentElement` is the kit's own `div.dr-table-wrapper` (`web/node_modules/darkraise-ui/dist/chunk-RY7Z2GFK.js:12`; `overflow-auto`, content height), not the `rail-scroll min-h-0 flex-1 overflow-y-auto` box Task 1 adds around it. - `listScrolls` is always false and `visibleRows` always equals `rowCount`, so the expectation "`listScrolls` is true wherever `rowCount` is greater than `visibleRows`" passes vacuously. The spec's "number of fully visible rows" and "the list actually scrolls" are never measured, and the Assumptions line "Task 10 measures that it scrolls" is untrue. A list that silently clips would pass. - Use `el.querySelector("table")?.closest(".rail-scroll")`, or put a `data-slot="browser-list"` on the scroll box in Task 1; keep the wrapper only for `listOverflowX`; add the kit wrapper to Assumptions.

#### P3-F10 [Important] round 2 (2026-10-12)

- [Important] [header, Tasks 1, 2, 6, 7]: Spec section 4 requires each register row to be closed by a mutation that fails exactly one named test, but the Global Constraint narrows this to one mutation per task. - Rows 8 (two and four columns), 10 (Open control), 19 (disabled folder does not open), 14 (chosen paths), 16 (`allowRoot`) and 17 have tests but no mutation step, so they will be closed without the proof the spec and `CLAUDE.md` Verification demand. - Add one named mutation per uncovered row to the task that owns it (for example, drop `!disabledIds?.has(...)` from `openable`; drop the `allowRoot` clause from `currentLocationSelectable`).

### P4: darkpanel/docs/dforge/plans/2026-10-23-v1-w0b-host-clients.md

Tasks: 13, risk scores {0: 12, 1: 1}; plan-review rounds held: 1

#### P4-F1 [Important] round 1 (2026-10-23)

- **[Important] Task 8:** Spec 1.8 requires route lookups "including the reverse lookup for an incoming flow". In the plan's code that lookup is `RouteQuery.IIF`, and `Mark` also feeds into it. No test covers either one. The only "reverse lookup" in `TestRouteGetLive` sets `Src` alone, and the only `OIF` test is the unknown-interface error. **Why it matters:** an implementation that never sends `RTA_IIF` or `RTA_MARK` passes every test, and the firewall guard in wave 1 depends on that lookup. **Fix:** move the request-body construction in `RouteGet` into its own function, such as `routeRequest(q RouteQuery, iif, oif int) []byte`. Add a unit test that decodes its attributes and asserts `RTA_IIF`, `RTA_OIF` and `RTA_MARK`. Also add a live case `RouteGet(RouteQuery{Dst: 127.0.0.1, Src: 127.0.0.1, IIF: "lo"})` that expects type `local`.

#### P4-F2 [Important] round 1 (2026-10-23)

- **[Important] Task 12:** Spec 1.8 says a contract test runs the wire types against a real tailscaled. The live test covers status, prefs, PATCH prefs, the DERP map and WhoIs, but never calls `Start`, the call that carries `ipn.Options{AuthKey, UpdatePrefs}`. **Why it matters:** tailscaled ignores JSON fields it does not know, so a wrong field name or a dropped field in `UpdatePrefs` fails silently. That breaks login in wave 4 and only the live test could catch it. **Fix:** on the logged-out node, call `Start` with no auth key and `UpdatePrefs` set to the current `Prefs` with a changed `Hostname`. Read `Prefs` back and assert both the new hostname and an unchanged unmodelled field. `Logout` on the logged-out node can also be called. If `CertPair` and `DebugDERPRegion` stay out of scope because they need a tailnet, say which later spike covers them.

#### P4-F3 [Important] round 1 (2026-10-23)

- **[Important] header (Global Constraints, "Later work"):** The plan defers "running the live tests in the harness" but names no wave or register row that owns it. Register row 79 is the only row that mentions these live tests. **Why it matters:** spec 1.8's requirement that the contract test run "against the tailscaled in the harness pins" ends up with no owner. The by-hand run against the floating `tailscale/tailscale:stable` tag does not track the harness pins. **Fix:** name the owner, for example the wave 4 spike or 9d, and add a register row for it.

### P5: darkpanel/docs/superpowers/plans/2026-10-21-m2-local-timeout-and-readme.md

Tasks: 2, risk scores {1: 1, 0: 1}; plan-review rounds held: 1

### P6: darkraise-ai-plugins/docs/superpowers/plans/2026-10-18-controller-model-eval.md

Tasks: 4, risk scores {0: 4}; plan-review rounds held: 1

#### P6-F1 [Critical] round 1 (2026-10-18)

- [Critical] [header/register]: The full case-by-arm matrix concern for the Stage 2 rule is not carried - a later Stage 2 plan written from the note can bring the flaw back unreviewed - extend row 24: the expected case IDs come from the case list, and every case-by-arm cell must be present and usable.

#### P6-F2 [Critical] round 1 (2026-10-18)

- [Critical] [header/register]: The per-case, per-check requirement for adopting Sonnet medium is not carried - same risk - extend row 24: Sonnet medium must match Sonnet high on every check, case by case, including busy waits under 20, continuations and cost.

#### P6-F3 [Important] round 1 (2026-10-18)

- [Important] [header/register]: Fixture HOME isolation is not carried - same risk - one line in row 24, or a pointer from row 24 to the round-1 findings file.

#### P6-F4 [Important] round 1 (2026-10-18)

- [Important] [header/register]: The concern that hidden tests may skip silently is not carried - a future case can pass with its checks skipped - row 24 should require that the intended tests actually ran, not only exit 0.

#### P6-F5 [Important] round 1 (2026-10-18)

- [Important] [header/register]: Checking the budget before every invocation and after compaction is not carried - same risk - add it to row 24.

#### P6-F6 [Important] round 1 (2026-10-18)

- [Important] [header/register]: Keeping limit and budget outcomes distinct from compaction failure is not carried - same risk - add it to row 24.

#### P6-F7 [Important] round 1 (2026-10-18)

- [Important] [header/register]: Adding up costs across retries is not carried - same risk - add it to row 24.

#### P6-F8 [Important] round 1 (2026-10-18)

- [Important] [header/register]: Making preflight-failure rows retryable is not carried - same risk - add it to row 24.

#### P6-F9 [Important] round 1 (2026-10-18)

- [Important] [Task 2]: `planSlugs` collects every `*.md` token from a per-task command. dforge documents `review-route PLAN_FILE --final-fix <file> ...` and `review-package PLAN_FILE BASE HEAD [OUTFILE]`, and controllers chain commands. So a final fix touching `README.md`, an output file ending `.md`, or `&& cat .dforge/handoff/latest.md` adds extra slugs. The session is then marked `shared` and the plan drops out of the decision with the wrong reason. In this repository, final fixes often touch `.md` files. No test covers this, and the cost reproduction only checked `includes(slug)`, never the slug count - only count the plan argument (the first `.md` positional after the script name, or paths under a `plans/` directory). Add `sessions.test.mjs` cases with `--final-fix README.md` and an `OUTFILE.md`.

#### P6-F10 [Important] round 1 (2026-10-18)

- [Important] [Task 1 / Assumptions]: The `completed` detector rests on an unverified fact: that the controller writes ledger lines with Write, Edit or MultiEdit on a path ending `progress.md`, or with a Bash command that contains the literal `progress.md`. The evidence cited is the ledger grammar at `SKILL.md:331`, not a transcript. Costs and seat misses were checked on real transcripts; completion was not. If the controller writes through a variable path or a script, every plan reads `complete: no`. That feeds `unfinished` in `stage1` and can turn `switch` into `ambiguous`. A Bash read such as `grep 'Task 3: complete (' progress.md` also counts as a write. No test would catch either - run `measure` (or `complete()`) on the three known completed plans, record that every task is found in Assumptions, and count only Bash commands that write (`>`, `>>`, `tee`, heredoc).

### P7: darkraise-web-template/docs/superpowers/plans/2026-10-06-controls-c2.md

Tasks: 17, risk scores {0: 8, 1: 9}; plan-review rounds held: 1

### P8: ghr/docs/superpowers/plans/2026-10-13-ghr-artifacts-revamp.md

Tasks: 5, risk scores {1: 4, 0: 1}; plan-review rounds held: 1


## Classification

| Finding | Severity | Class | Reason |
|---|---|---|---|
| P1-F1 | Critical | loud | a named existing test fails and the plan says to report BLOCKED |
| P1-F2 | Critical | silent (borderline) | the hover reset is a specificity clash with kit rules outside the diff, and no test or browser check hovers a badge |
| P1-F3 | Important | silent | depends on a kit rule in node_modules; the plan's checks read only the background |
| P1-F4 | Important | silent | depends on `justify-center` in the kit's styles; the 390px check reads only size |
| P1-F5 | Important | loud | `git add` fails with a pathspec error |
| P1-F6 | Important | loud | the step's own contrast check fails and halts the task |
| P1-F7 | Important | silent (borderline) | no rule covers spec §2 "Invalid"; a reviewer would likely assume the kit covers it |
| P1-F8 | Important | reviewable | the spec's Testing section names the missing tests, visible in the diff |
| P1-F9 | Important | silent (borderline) | the plan header narrows the spec's proof rule, and reviewers are pointed at the task text that sanctions it |
| P1-F10 | Important | silent (borderline) | six spec clauses missing; in one, the plan's test asserts the wrong token and passes |
| P1-F11 | Important | silent | the missed call site and badge are outside the diff |
| P1-F12 | Important | not-a-defect | missing Assumptions evidence; names no wrong fact that would ship |
| P1-F13 | Important | silent | the fill rule paints three inline lists outside the diff; the probe only opens a select |
| P2-F1 | Important | silent (borderline) | stale comments outside the diff hunks; the spec names the files, so an Opus spec review might notice |
| P3-F1 | Critical | loud | the test cannot pass ("Found multiple elements") |
| P3-F2 | Critical | loud | the named test times out on duplicate matches |
| P3-F3 | Critical | loud | the step cannot go green as written |
| P3-F4 | Important | not-a-defect | its only consequences are F1-F3, already loud |
| P3-F5 | Important | silent | a wrong theme key silently measures light twice (whether the key is wrong is Unknown) |
| P3-F6 | Important | loud | surfaces at the plan's own Task 10 probe |
| P3-F7 | Important | silent (borderline) | an event-order toggle bug; deleting `filterOpen` leaves every test green |
| P3-F8 | Important | silent | the test asserts `toBeEnabled()` while focus is lost, weaker than the spec |
| P3-F9 | Important | silent | the probe measures the wrong element and passes vacuously |
| P3-F10 | Important | silent (borderline) | register rows close without the spec's mutation proof |
| P4-F1 | Important | silent | an implementation that never sends `RTA_IIF` or `RTA_MARK` passes every test |
| P4-F2 | Important | silent | tailscaled ignores unknown JSON fields and no test calls `Start` |
| P4-F3 | Important | silent | a deferred live-test requirement has no owning wave or register row |
| P6-F1 | Critical | silent | a Stage 2 requirement not carried into register row 24; nothing downstream checks it |
| P6-F2 | Critical | silent | as P6-F1 |
| P6-F3 | Important | silent | as P6-F1 |
| P6-F4 | Important | silent | as P6-F1 |
| P6-F5 | Important | silent | as P6-F1 |
| P6-F6 | Important | silent | as P6-F1 |
| P6-F7 | Important | silent | as P6-F1 |
| P6-F8 | Important | silent | as P6-F1 |
| P6-F9 | Important | silent | `planSlugs` collects extra `.md` tokens; no test covers it |
| P6-F10 | Important | silent | the `completed` detector rests on an unverified premise; no test would catch it |
