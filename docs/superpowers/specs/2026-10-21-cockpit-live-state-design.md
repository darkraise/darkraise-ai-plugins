# Cockpit live state and layouts

**Execution strategy:** sequential — every part edits
`plugins/dforge/hooks/cockpit/register.tsx` and `tests/cockpit.test.ts`

**Registers:** `docs/superpowers/registers/2026-10-21-cockpit-live-state.md`;
this spec is its `**Covers:**` line

## Decisions

The owner's answers on 2026-10-21.

1. Row 1: a distinct background state, and the Done notification is held until
   the background work and Claude's follow-up turn finish.
2. Row 2: tiered polling while the cockpit is visible — files every 2 s, git
   status and the context breakdown every 10 s; nothing polls while it is
   hidden.
3. Row 3: the dense pane draws one line per section.
4. Row 3: a new `density` key, independent of `layout`; saved configs stay
   valid and `layout: compact` keeps meaning minimized.
5. Row 4: minimized on the terminal, a bordered box with two lines below the
   prompt, the engine's hint carried inside it.
6. Sequential execution; both design sections approved as presented.

## Problem

- The Now row says `○ idle` and the `✅ Done` notification goes out as soon as
  a main turn ends, even when the turn left a background shell (a Codex review,
  a test run) or a background agent running and Claude will be woken when it
  finishes.
- `~/.dforge/config.json` is read at session start and after the pane's own
  save only. A change from `dforge-config.mjs`, a hand edit or another session
  shows after a restart. Git state and the context breakdown refresh only on
  `session.measure`.
- The pane has one density. A docked pane on a narrow terminal spends most of
  its rows on cards, charts and per-item lists.
- Minimized, the band takes four to five rows above the prompt.

## Probe (2026-10-21, Claude Code 2.1.304)

A throwaway mod in a scratch config directory hooked
`ui.render { component: 'PromptHint' }` and returned a `Box` with
`borderStyle="round"`, two `Text` rows and a `Button`:

- The engine drew the whole framed tree under the prompt, below a two-line
  `statusLine` command's output, in place of the hint text.
- The permission-mode label (`⏸ manual mode on ·`) stays at the left of the
  first row and the tree starts after it.
- `flexGrow` does not stretch the tree; an explicit `width` does. A width of
  `e.viewport.columns - 4` overflowed: the mode label wrapped and the right
  edge was cut. The tree must fit the room right of the label.
- Whether the `Button` takes a click there was not tested. Its hotkey cannot
  work: the prompt holds the focus.

## Design

### 1. Background state (row 1)

`CockpitActivity.kind` gains `'background'`. Background work is the main
session's tracked work: `shells` rows plus `spawns` with `isDone` false, the
same test `autoStage` already uses (`isBackground`).

- `turn.complete` for the main loop with `reason === 'answer'`: when background
  work is pending, the activity becomes `background` (keeping `lastTurnMs` and
  `endedAt`) instead of `idle`, and the Done notification is not sent. Instead
  `S.heldDone` records `{ startedAt }` — the first held turn's
  `turnStartedAt`; a later held turn keeps the earlier value.
- A main `turn.complete` with `reason === 'answer'` and no pending background
  work sends Done when `S.heldDone` is set, timed from its `startedAt`, with
  the existing `notifyAfter` threshold applied to that whole span; then
  clears it. Without `S.heldDone`, today's behaviour.
- When the last shell ends (`endShells`, `trackShells` on a stop) or the last
  running spawn completes while the activity is `background`, the activity
  becomes `idle` and `S.releaseTimer = $.clock.after(5000, …)` is armed: if no
  main turn has started when it fires, the held Done is sent then and cleared.
  Claude is normally woken by the task notification, whose turn start cancels
  the timer; the 5 s grace covers the gap between a spawn's completion and
  that turn.
- `failed` and `interrupted` turns clear `S.heldDone` and keep their current
  states and notifications.
- `nowLine` draws `background` as `◐ background · <n> shell(s) · <newest
  command, excerpted> · <age of the oldest>`, plus `· <n> agent(s)` when
  spawns run. The minimized box's second line uses the same runs.
- `syncTicker` treats `background` like `idle` for `S.isTurnLive`; the ticker
  already runs while shells or spawns are live.

Out of scope: the Monitor tool and other background tasks the cockpit does not
track; Claude Code's own spinner.

### 2. Polling while visible (row 2)

One timer, `S.poll`, from `$.clock.every(2000, …)`:

- Started when the pane is placed or the cockpit is minimized on a terminal;
  cancelled when the pane closes and the cockpit is not minimized, and on
  `session.end`. A single top-level `syncPoll($)` decides, called wherever the
  pane opens or closes and where `layout` changes.
- Each tick: `fs.stat` on `~/.dforge/config.json` and on the user
  `settings.json` (`userSettingsPath`); when either `mtimeMs` differs from the
  last seen value, run `applySettings` through the same path `loadSettings`
  uses (the `S.claudeSaved` overlay keeps a just-saved value from being
  reverted). Then `readRun($)`, which is already driven by `fs.stat` on the
  ledger, handoff and finish files.
- Every fifth tick: `refreshDetail($)` (place, context breakdown, git status).
- A tick that is still running when the next fires is skipped (`S.isPolling`),
  so a slow `git status` never stacks.
- Atom updates redraw the pane and the box; the poll never calls
  `$.ui.invalidate` itself.

The existing `session.measure` call to `refreshDetail` stays.

### 3. Dense pane (row 3)

Schema (`plugins/dforge/config/schema.mjs`), in the Cockpit group after
`layout`:

```js
density: {
  type: 'enum', values: ['detailed', 'dense'], default: 'detailed', group: 'Cockpit', target: 'dforge',
  label: 'Density', title: 'Pane density',
  description: 'detailed: cards, charts and lists. dense: one line per section. The pane\'s Dense and Detailed buttons set it.',
},
```

`Live` gains `density: 'detailed' | 'dense'`, anything else reading as
`detailed`.

When the pane is drawn in full (not the band) and `density` is `dense`:

- One row per section in `o.shown` order; `collapsed` does not apply. A section
  with nothing to say is left out (no shells, no agents, no plan, no
  refusals).
- The rows, each built by a pure function in `lib.ts` returning `Run[]`:
  - Now: `nowLine`.
  - `account`: email · billing · remote.
  - `context`: `ctx` + a 10-cell glyph bar + percent of the handoff budget +
    `<tokens>/<limit>` + `≈<n> turns`.
  - `usage`: `5h` and `7d` bars with percent, on one line.
  - `shells`: `$` + count + newest command (excerpted) + its age.
  - `agents`: `agt` + running count + running seats, short names.
  - `plan`: `plan` + run segments + `done/total` + the current task; from
    todos when no run.
  - `repo`: `⎇` + branch + ahead/behind + changed + untracked.
  - `guard`: `✗ <n> refused`.
- Each row is truncated at the pane's `bodyColumns`.
- The actions row draws single-line buttons (`isCompact: true`) and gains a
  toggle: **Dense** (hotkey `d`) in `detailed`, **Detailed** (hotkey `d`) in
  `dense`, which calls `setOption($, 'density', …)`.
- The desktop surface draws the same rows as text, no vector pictures.
- The settings view lists `density` from the schema, as it lists every key.

### 4. Minimized box below the prompt (row 4)

On the terminal surface, when `o.isMinimized`:

- `ui.render { component: 'AbovePrompt' }` no longer draws the band; the
  resume band still draws there (it needs focus for its buttons).
- A new `ui.render { component: 'PromptHint' }` hook draws the box; when not
  minimized, or on another surface, it returns `next(e)`.
- The box reuses the band's terminal branch of `drawBand`, generalised to take
  a width: the top rule carries email · billing · remote and an **Expand**
  `Button` that calls `expand`; line 1 and line 2 come from `fitBand`; line 2
  ends with `e.props.hint`, dimmed, when room is left. A warning row (blocked
  tasks, refusals) is drawn under them as today.
- Width: the mod cannot read the live permission mode at draw time (it reads
  only `permissions.defaultMode` from the settings; Shift+Tab changes the live
  one), so the box reserves the widest label every time:
  `e.viewport.columns - 2 - MODE_LABEL_RESERVE`, a constant in `lib.ts` set to
  the widest permission-mode label measured in the smoke step, separator
  included. The box keeps no explicit width beyond that budget; its content is
  fitted to it, so in a mode with a short label or none the box ends short of
  the right edge. Below `FRAME_MIN_COLUMNS` of budget the box falls back to
  today's unframed lines.
- The frame keeps the account colour (`tint`).
- The desktop surface keeps today's band above the prompt.
- If the Expand button does not take a click in the hint slot, `/cockpit`
  remains the way back; the plan's smoke step records which.

`layout`'s description becomes: `compact: minimized, a box below the prompt on
the terminal (above it on the desktop); Minimize sets it and Expand sets auto,
or full where the pane does not dock.`

## Files

- `plugins/dforge/hooks/cockpit/register.tsx`: rows 1, 2, 3, 4.
- `plugins/dforge/hooks/cockpit/lib.ts`: `nowLine` background case, dense row
  builders, `MODE_LABEL_RESERVE`, band width parameter.
- `plugins/dforge/types/index.d.ts`: `CockpitActivity.kind` gains
  `'background'`.
- `plugins/dforge/config/schema.mjs`: `density`; `layout` description.
- `plugins/dforge/tests/cockpit.test.ts`, and the `lib.ts` unit tests beside
  it: new cases below.
- `plugins/dforge/README.md`: the cockpit section (background state, live
  config, density, the minimized box).

## Testing

- `lib.ts` units: `nowLine` for `background`; each dense row builder, including
  empty sections and truncation; band fitting at a given width, and the box
  budget below `FRAME_MIN_COLUMNS` falling back to unframed lines.
- `cockpit.test.ts`:
  - a main turn ending with a background shell gives `background` and sends no
    Done; the follow-up turn ending clean sends one Done timed from the first
    turn; the shell ending with no follow-up turn sends it once the 5 s grace
    passes, and a turn starting inside the grace cancels that send;
  - an edited `~/.dforge/config.json` (new `mtimeMs`) is in force after one
    poll tick; nothing polls with the pane closed and not minimized;
  - `density: dense` draws one row per shown section and the toggle saves the
    key;
  - minimized on the terminal: `PromptHint` draws the box and `AbovePrompt`
    draws nothing without a resume offer.
- Smoke, in a scratch config directory per memory
  `driving-nested-claude-smoke-runs`: the box beside each permission mode at
  80 and 120 columns, and whether Expand takes a click.
- Repository validation as `CLAUDE.md` lists it.

## Acceptance

1. Row 1: with a background shell running after a turn, the Now row and the
   box read `◐ background`, and exactly one Done arrives after the follow-up
   turn.
2. Row 2: a setting changed outside the pane shows within 2 s while the
   cockpit is visible; git state within 10 s.
3. Row 3: `density: dense` draws the docked pane as one line per section, and
   the toggle switches it.
4. Row 4: minimized on the terminal, nothing draws above the prompt (no resume
   offer) and a framed two-line box draws below it, fitting beside the mode
   label at 80 and 120 columns, in every permission mode.

## Riskiest assumption

Every permission-mode label fits within one measured reserve. The probe saw
the manual-mode label only; the smoke step measures every mode the terminal
cycles through. A label wider than the reserve would wrap and cut the box's
right edge, as the probe's overflow did.
