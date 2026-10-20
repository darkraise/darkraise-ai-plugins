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
7. After the Fable review: a typed prompt during a hold starts a new chain;
   the earlier held Done is dropped. Every other finding was accepted.

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

`CockpitActivity.kind` (`types/index.d.ts`) and `ActivityInput.kind`
(`lib.ts`) gain `'background'`.

Background work is the main loop's tracked work:

- `CockpitShell` gains `agentId: string | null`, set by `trackShells` from
  `e.agentId`. Only rows with `agentId === null` count. When a spawn's
  `turn.complete` marks it done, its shells' rows are dropped too: a
  notification for a finished subagent's loop may never reach `endShells`.
- `spawns` with `isDone` false. `trackShells`'s `TaskStop` / `KillShell`
  branch also marks a spawn done when the stopped id is its `agentId`.
- `isMainBackground($)`, a top-level function, answers the test. `autoStage`'s
  existing `isBackground` keeps its own wider test.

The hold:

- Main `turn.complete` with `reason === 'answer'` and main background work
  pending: the activity becomes `background` (keeping `lastTurnMs` and
  `endedAt`) instead of `idle`, and Done is not sent. `S.heldDone` records
  `{ startedAt, heldAt }`: `startedAt` is read from the activity's
  `turnStartedAt` before the update spreads `IDLE`; a held turn that
  continues a chain keeps the earlier `startedAt`.
- A chain is the turns Claude runs without a typed prompt. Main `turn.start`
  with `e.text` neither empty nor containing `<task-notification>` is a typed
  prompt (auto run's submitted prompts included): it clears `S.heldDone`, so
  the earlier held Done is dropped and the next Done is timed from this turn.
  The smoke step confirms what `e.text` carries on a notification wake-up.
- Main `turn.complete` with `reason === 'answer'` and no main background work
  left: when `S.heldDone` is set, Done is sent timed from its `startedAt`, the
  `notifyAfter` threshold judged on that span, and `S.heldDone` is cleared;
  otherwise today's behaviour. Whatever main turn ends next carries it, an
  auto run's continue turn included.
- Release without a turn: when `endShells`, the stop branch of `trackShells`,
  or a subagent's `turn.complete` leaves no main background work while the
  activity is `background`, the activity becomes `idle` and
  `S.releaseTimer = $.clock.after(5000, …)` is armed; when it fires with no
  main turn started since, the held Done is sent and cleared. Main
  `turn.start` cancels the timer.
- Cap: past `DEFER_CAP_MS` (30 min) from `S.heldDone.heldAt`, the watchdog
  tick (`watchdogTick`, every 60 s) sends the held Done, clears it, and sets
  the activity to `idle`, so a spawn that never completes cannot hold it for
  the session.
- `failed` and `interrupted` turns clear `S.heldDone` and keep their current
  states and notifications.
- `session.end` cancels `S.releaseTimer` and clears `S.heldDone`, beside
  `S.ticker`, `S.watchdog` and `S.poll`.
- `nowLine(now, at, work)` gains `work: { shells: CockpitShell[]; agents:
  number }`; it draws `background` as `◐ background · <n> shell(s) · <newest
  command, excerpted> · <age of the oldest>`, plus `· <n> agent(s)` when
  agents run. Existing callers and the tests at `cockpit.test.ts` that call
  `nowLine` directly pass the new argument.
- `syncTicker` treats `background` like `idle` for `S.isTurnLive`; the ticker
  already runs while shells or spawns are live.

Out of scope: the Monitor tool and other background tasks the cockpit does not
track; Claude Code's own spinner.

### 2. Polling while visible (row 2)

One timer, `S.poll`, from `$.clock.every(2000, …)`, managed by a top-level
`syncPoll($)`:

- Runs while the pane is open (placed or waiting: the engine raises no event
  when a waiting pane becomes placed) or the cockpit is minimized, on any
  surface. `syncPoll` is called at `session.start`, after every `$.ui.open`
  and `$.ui.close` the mod makes, from the `ui.close` hook, and after
  `layout` changes. Each tick first checks `isPaneUp($)` or `live($)`'s
  `isMinimized` and returns at once when nothing is drawn.
- A tick still running when the next fires is skipped (`S.isPolling`), so a
  slow `git status` never stacks.
- Every tick:
  - `fs.stat` on `~/.dforge/config.json`; when `mtimeMs` differs from
    `S.seen.config` (recorded by `loadSettings` and after the pane's own save),
    the file is re-read. A file that is not a JSON object keeps the values in
    force and records the problem in `S.settingProblems`, which the settings
    view shows; the poll never applies `{}`.
  - The Claude-target keys: a hash of `JSON.stringify(await
    $.settings.read())` against `S.seen.claude`. The engine's snapshot can
    trail a save; comparing it rather than the file's mtime re-applies once
    the engine has caught up. A change in either runs `applySettings` with the
    file as read.
  - `readRun($)`, made change-gated: the ledger and plan files are read only
    when the newest ledger's `mtimeMs` or the plan file's `mtimeMs` differ
    from the last read, and the `run` atom is written only when the summary
    differs from the current one, as `readFinish` and `readResumeOffer`
    already do. An unchanged tick writes no atom and redraws nothing.
- Every fifth tick (10 s): `refreshDetail($)` (place, context breakdown, git
  status), skipped when `session.measure` ran it within the last 10 s; and
  `trackAutoRun($)`, since another session's auto-run script can edit that
  file.
- Atom updates redraw the pane and the box; the poll never calls
  `$.ui.invalidate`.

Not polled: the account's `.claude.json` (`readAccount`, at start and on
`/cockpit`), the remote-control config row (`readRemote`, at turn end), and
rate limits, which only the engine's `session.measure` reports.

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

- One row per section in `o.shown` order; `collapsed` does not apply. Shells,
  agents, plan and guard are left out when they have nothing to show.
  `context` and `usage` before their first reading draw `ctx  no reading yet`
  and `5h/7d  no reading yet`, dimmed.
- The rows, each built by a pure function in `lib.ts` returning `Run[]`:
  - Now: `nowLine`, followed by the Minimize button where the pane offers it
    today.
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
- The actions row draws single-line buttons (`isCompact: true`, which on the
  terminal shows the `d: ` hotkey prefix rather than an underlined letter) and
  gains a toggle: **Dense** (hotkey `d`) in `detailed`, **Detailed** (hotkey
  `d`) in `dense`, calling `setOption($, 'density', …)`.
- The desktop surface draws the same rows as text: no gauge tiles, no vector
  pictures; the Now row keeps its Minimize button.
- The settings view lists `density` from the schema, as it lists every key.

### 4. Minimized box below the prompt (row 4)

On the terminal surface, when `o.isMinimized`:

- `ui.render { component: 'AbovePrompt' }` no longer draws the band; the
  resume band still draws there (it needs focus for its buttons).
- A new `ui.render { component: 'PromptHint' }` hook, registered
  unconditionally, draws the box; when not minimized, or on another surface,
  it returns `next(e)`. It draws while a turn runs too: it never yields.
- The box reuses the band's terminal branch of `drawBand`, generalised to take
  a width:
  - Top rule: email · billing · remote, and an **Expand** `Button` calling
    `expand`.
  - Lines 1 and 2: `fitBand`'s, unchanged in content (the band never names a
    command). Line 2 starts with `◐ ` while the activity is `background`.
  - Warning row (blocked tasks, refusals) as today.
  - Bottom rule: `e.props.hint`, dimmed, set into the rule (`╰─ esc to
    interrupt ───╯`) and cut to fit, so the engine's hint survives without
    taking room from line 2.
- Width: the mod cannot read the live permission mode at draw time (it reads
  only `permissions.defaultMode`; Shift+Tab changes the live one), so the box
  reserves the widest label every time: `budget = e.viewport.columns - 2 -
  MODE_LABEL_RESERVE`, a constant in `lib.ts` set to the widest label the
  smoke step measures, separator included. Content is fitted to the budget,
  so under a short label or none the box ends short of the right edge. With
  no `e.viewport`, or a budget below `FRAME_MIN_COLUMNS`, the box falls back
  to today's unframed lines.
- The frame keeps the account colour (`tint`).
- The desktop surface keeps today's band above the prompt.
- If the Expand button does not take a click in the hint slot, `/cockpit`
  remains the way back; the smoke step records which.

`layout`'s description becomes: `compact: minimized, a box below the prompt on
the terminal (above it on the desktop); Minimize sets it and Expand sets auto,
or full where the pane does not dock.`

## Files

- `plugins/dforge/hooks/cockpit/register.tsx`: rows 1, 2, 3, 4.
- `plugins/dforge/hooks/cockpit/lib.ts`: `ActivityInput.kind`, `nowLine`'s
  signature and background case, dense row builders, `MODE_LABEL_RESERVE`,
  the band's width parameter and bottom-rule hint.
- `plugins/dforge/types/index.d.ts`: `CockpitActivity.kind` gains
  `'background'`; `CockpitShell` gains `agentId`.
- `plugins/dforge/config/schema.mjs`: `density`; `layout` description.
- `plugins/dforge/tests/cockpit.test.ts`: new cases and the migrations below.
- `plugins/dforge/README.md`: the cockpit section (background state, live
  config, density, the minimized box).

## Testing

- `lib.ts` units: `nowLine` for `background`; each dense row builder,
  including empty sections, no-reading rows and truncation; band fitting at a
  given width; the bottom-rule hint cut to fit; a missing viewport or small
  budget falling back to unframed lines.
- `cockpit.test.ts`:
  - a main turn ending with a main-loop background shell gives `background`
    and sends no Done; the continuation turn ending clean sends one Done timed
    from the first turn; the shell ending with no follow-up turn sends it once
    the 5 s grace passes; a turn starting inside the grace cancels that send;
  - a typed prompt during the hold drops the held Done; the next Done is timed
    from the typed turn;
  - a subagent's shell does not hold the main Done, and its row goes when the
    subagent's turn completes;
  - `TaskStop` on a background agent's id marks it done; a hold older than
    `DEFER_CAP_MS` is sent by the watchdog tick;
  - `session.end` during the grace sends no Done afterwards;
  - an edited `~/.dforge/config.json` (new `mtimeMs`) is in force after one
    tick; a non-object file keeps the values in force and records a problem;
    a changed `$.settings.read()` result is applied; nothing polls with the
    pane shut (`isPaneShut: true`, since `openAtStart` opens it) and not
    minimized; an unchanged tick writes no `run` atom;
  - `density: dense` draws one row per shown section and the toggle saves the
    key;
  - minimized on the terminal: `PromptHint` draws the box and `AbovePrompt`
    draws nothing without a resume offer.
  - Migrated: the tests mounting `AbovePrompt` on `terminal` and expecting the
    band (about `cockpit.test.ts:1324-1361` and `1416-1423`) mount `HINT`
    instead.
- Smoke, in a scratch config directory per memory
  `driving-nested-claude-smoke-runs`: the label width of each permission mode
  (default, acceptEdits, plan, bypassPermissions, dontAsk, auto), giving
  `MODE_LABEL_RESERVE`; the box at 80 and 120 columns; whether Expand takes a
  click; what `turn.start`'s `e.text` carries on a task-notification wake-up.
- Repository validation as `CLAUDE.md` lists it.

## Acceptance

1. Row 1: with a background shell running after a turn, the Now row and the
   box read `◐ background`, and exactly one Done arrives after the
   continuation turn.
2. Row 2: while the cockpit is visible on any surface, a setting changed
   outside the pane shows within 2 s and git state within 10 s; an idle tick
   redraws nothing.
3. Row 3: `density: dense` draws the docked pane as one line per section, and
   the toggle switches it.
4. Row 4: minimized on the terminal, nothing draws above the prompt (no resume
   offer) and the box draws below it beside the mode label without wrapping
   it, at 80 and 120 columns in every permission mode: framed where the budget
   reaches `FRAME_MIN_COLUMNS`, unframed lines below that.

## Riskiest assumption

Every permission-mode label fits within one measured reserve. The probe saw
the manual-mode label only; the smoke step measures all six modes. A label
wider than the reserve would wrap and cut the box's right edge, as the
probe's overflow did.

## Review rulings

A Fable review on 2026-10-21 returned 27 findings, verdict "ready after listed
fixes". All were accepted and folded into the sections above:

- §1: subagent shells and stopped or teammate spawns no longer hold the Done
  (shell `agentId`, `TaskStop` marking, the `DEFER_CAP_MS` cap); the release
  condition reads "no main background work left"; `session.end` clears the
  timer and the hold; auto run's continue turn carries a held Done;
  `ActivityInput` and `nowLine`'s signature are listed; `startedAt` is read
  before `IDLE` is spread.
- §2: a non-object config is never applied; Claude-target keys compare the
  engine's settings read, not the file's mtime; `readRun` is change-gated;
  the desktop band is polled; the poll runs while the pane is open, placed or
  waiting; seen values start at `loadSettings`; `refreshDetail` skips a tick
  `session.measure` already covered; the not-polled sources are listed and
  `trackAutoRun` joins the 10 s tick.
- §3: no-reading rows, the desktop dense layout and the compact-button hotkey
  form are stated.
- §4: line 2 keeps `fitBand`'s content with a `◐` lead; the engine's hint
  moves to the bottom rule; a missing viewport unframes; the six modes are
  listed; the 80-column fallback is named in Acceptance 4; the migrated tests
  are named; the box never yields while a turn runs.
- The owner ruled on finding 5: a typed prompt starts a new chain and drops
  the earlier held Done.
