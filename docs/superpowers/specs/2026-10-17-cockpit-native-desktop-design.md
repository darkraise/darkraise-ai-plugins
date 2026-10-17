# Cockpit: collapsible sections and a native desktop look

**Execution strategy:** sequential — collapsing, the native desktop panels
and the agent groups all edit `hooks/cockpit/register.tsx`; only the settings
screen (`settings-view.tsx`) stands apart, and one task's time is not worth a
wave.
**Register:** docs/superpowers/registers/2026-10-17-run-order-finish-controller.md, row 5 (and row 4's rank-1 adoption)

## Problem

The owner, on the cockpit in the Claude Code desktop app: it looks out of
place, the settings screen does not look like desktop UI, and there is no
spacing between sections. They also asked for collapsible sections, and for
the Agents section to group subagents by state the way the desktop's Projects
overview does (docs/superpowers/notes/2026-10-17-desktop-nested-sessions.md,
rank 1).

Today (`plugins/dforge/hooks/cockpit/register.tsx`, desktop branch from the
`if (isDesktop)` block): every section is a `Box` with `borderStyle="round"`,
`borderColor="subtle"`, `backgroundColor={CARD}` and `paddingX={1}` around one
`Svg` drawn by `panelSvg` (`hooks/cockpit/svg.ts`), so every title, row and
chip is an image with baked colors and the app's theme never reaches it; the
sections stack with no gap. The settings view (`hooks/cockpit/settings-view.tsx`)
draws every toggle and choice as a row of `Button`s.

## What the platform offers (Claude Code 2.1.302 mod typings)

From the plugin-authoring reference (`types/claude-code.d.ts`), read
2026-10-17:

- Desktop elements: `Box`, `Text`, `Button`, `Input`, `Select`, `Svg`, `Link`,
  `Code`, `Markdown`. No switch, checkbox, radio, tabs, divider or
  collapsible element.
- `Text` takes desktop-only `size` (`caption | footnote | body | heading |
  title`) and `weight` (`regular | medium | semibold | bold`); the terminal
  ignores `size` and draws only bold.
- Spacing props take `Space = number | 'xs' | 'sm' | 'md' | 'lg' | 'xl'`:
  numbers are character cells on every surface, named steps are sized by each
  surface's own scale. "Spacing flows from the parent: set `gap` on the Box."
- `Color` is a `ThemeKey` (`text`, `subtle`, `success`, `error`, `warning`,
  `suggestion`, `permission`, `planMode`, `claude`, …) that follows the
  person's theme, or a raw string.
- `Select`: `key`, `label?`, `options: {value, label?}[]`, `value?`,
  `onSelect(value)`. `Input`: `key`, `label?`, `placeholder?`, `value?`,
  `submitLabel?`, `onSubmit(value)`.
- A `Button` may hold only strings and `Text`; `Box` and `Text` take no
  `onPress`. A collapse control is therefore a `Button`.
- `$.agent.list()` returns this session's agents with `status: 'pending' |
  'running' | 'waiting' | 'idle' | 'completed' | 'failed' | 'killed'`; a
  subagent's `turn.complete` carries `reason: 'answer' | 'aborted' |
  'refusal' | 'error'`.

## Design

### 1. Collapsible sections (both surfaces)

- A new setting `collapsed` in `config/schema.mjs`: `type: 'string'`,
  `default: ''`, `group: 'Cockpit'`, `target: 'dforge'`, label `Collapsed`,
  title `Collapsed sections`, description `Sections drawn as their title row
  only, comma-separated: account, context, usage, shells, agents, plan, repo,
  guard. Empty expands all eight.`
- `hooks/cockpit/lib.ts`: `collapsedFrom(text: string): Section[]` (known
  names, each once, in `SECTIONS` order; empty text gives `[]`) and
  `collapsedToggled(collapsed: readonly Section[], name: Section): string`
  (adds or removes `name`, returns the setting text in `SECTIONS` order,
  `''` when none).
- `register.tsx`'s `Options`, `liveFrom` and `Live` (the parsed settings)
  gain `collapsed` (raw text) and `shownCollapsed: Section[]` (via
  `collapsedFrom`), as `sections` and `shown` do today.
- Each section's title is the collapse control; pressing it saves
  `collapsedToggled(...)` through `setOption($, 'collapsed', …)`, so the next
  session opens the same way:
  - desktop: one `<Button plain>` whose only child is
    `<Text size="heading" weight="semibold" color={lamp}>▾ <Title></Text>`
    (`▸` when collapsed);
  - terminal: `<Button plain label="▾ <Title>" />` drawn directly (not through
    the `button()` helper, whose rounded box and underline children apply
    only to action buttons), in the card's title colour.
- A collapsed section draws its title row with its headline (the summary the
  title row already carries) and nothing else of its body. The one exception
  is the Context section's `actions` row (Compact, Hand off, Stop auto,
  Settings, built at the `actions` constant), which stays below the title
  row. The resume card is outside every section and is unaffected.
- The settings screen's Cockpit tab draws a `Collapsed` chips row beside
  `Sections`, built like it (`custom.collapsed`).

### 2. Native desktop panels

- The desktop `panel()` helper keeps its signature (`key, title, lamp,
  right, lines, ...native`) but renders natively:
  - the card: `Box` column, `borderStyle="round"`, `borderColor="subtle"`,
    `backgroundColor={CARD}`, `paddingX="md"`, `paddingY="sm"`, `gap="xs"`;
  - the head row: the title `Button` (§1), then the headline runs as `Text
    size="footnote"`, right-aligned;
  - each `PanelLine` through a new `nativeLine(line)`: `text` → a row `Box`
    of `Text` runs (`size="footnote"` when `small`, `wrap="truncate-end"`
    unless `wrap`, `paddingLeft` = `Math.round(indent / 7.5)` cells), `right`
    runs right-aligned; `chips` → a wrapping row `Box` (`gap="xs"`) of pills;
    `badge` → a row `Box` of the badge `Svg` and two `Text` lines; `picture`
    → the `Svg` unchanged, with its own `alt` (so the picture alts asserted
    today still hold).
  - each `PanelRun` → `Text` with `color` mapped by `themeColor(name)`,
    `dimColor` for `dim`/`faint`, `weight="semibold"` for `bold`, `mono` for
    `mono`. A run with `chip: true`, in a `chips` line or inside a `text`
    line (the agents rows' seat pill, the band's head), is a pill:
    `Text size="caption" backgroundColor="subtle"`.
- `themeColor(name: string | undefined): Color | undefined` in `lib.ts`:
  `green → success`, `red → error`, `yellow → warning`, `cyan → suggestion`,
  `blue → suggestion`, `magenta → planMode`, `gray → subtle`, `white → text`;
  a theme key, a hex or any other name passes through unchanged.
- The desktop root `Box` gets `gap="md"` between sections and gauge rows; the
  gauges stay `Svg` tiles. The terminal branch keeps its numeric spacing.
- The desktop band (`drawBand`, its `head0` and `rest` lines, today drawn
  with `panelSvg`/`panelText`) renders those lines through `nativeLine` too;
  its meters stay `bandMetersSvg`.
- In `svg.ts`, `panelSvg`, `panelText`, the `{ kind: 'head' }` line kind and
  the helpers only they use (`wrapRuns`, `drawRunsAt`) are deleted. `THEME`,
  `cut`, `tspan`, `toneOf`, `measure` and `place` stay, because
  `gaugeTileSvg` and `bandMetersSvg` use them, as do the chart drawings
  (`meterSvg`, `labelledMeterSvg`, `trendSvg`, `stackSvg`, `seatSvg`,
  `gaugeSvg`, `segmentsSvg`, `avatarSvg`). `PanelLine` and `PanelRun` stay as
  the row description `nativeLine` reads. The panel tests in
  `tests/cockpit.test.ts` that exercise `panelSvg`/`panelText` (the `draws
  meters, a trend, a stack, run segments and a badge as SVG` test's panel
  part) are replaced by `nativeLine` tests.

### 3. Desktop settings screen

Only on the desktop surface: `SettingsModel` gains `isDesktop: boolean`
(register.tsx passes the `isDesktop` it already derives), and the native
controls are drawn when `model.isDesktop && 'Select' in table`. The terminal
table also has `Select` and `Input`, and its view is unchanged.

- A toggle row: `Select` with options `On`/`Off` (values `true`/`false`),
  `onSelect` → `act.set(key, value === 'true')`.
- A choices row: `Select` with one option per value, `onSelect` →
  `act.set(key, value)`.
- A number or text row: the existing `Input`, always shown (no Edit button
  step), `label` the row's label, `value` its current value, `onSubmit` →
  `act.submit(key, text)`; a number row keeps its `−`/`+` step buttons beside
  the `Input`. A refused entry must be visible: `act.submit` sets `editing`
  to the key on refusal (as the terminal's Edit step already does), so the
  row draws `model.error` below its `Input`.
- The open group's name: `Text size="title" weight="semibold"`; each row: a
  `Box` column with `gap="xs"`: the label `Text weight="medium"`, the
  description `Text size="footnote" dimColor`, the control; rows `gap="md"`.
- Group tabs stay `Button`s, the open one `variant="primary"`, in a row `Box`
  with `gap="sm"`. Locked rows, custom rows, help, reset and the footer keep
  their current behaviour with named-step spacing.

### 4. Agents grouped by state (both surfaces)

- `CockpitSpawn` (`types/index.d.ts`) gains `outcome: 'done' | 'failed' |
  null` (null while running; records loaded from older state read as null
  when not done and `done` when done). The subagent end hook sets `done` for
  `reason: 'answer'` and `failed` for `aborted`, `refusal` or `error`.
- A running subagent is waiting on you while it has an approval open: the
  cockpit already sees each subagent's permission prompt in-process
  (`tool.check` with `e.agentId`, which starts a wait with `startWait`, and
  `endWait`, which clears it). The wait entry records that `agentId`, and the
  Agents section counts a running spawn as waiting while an open wait names
  it. `$.agent.list()` is not used: its `waiting` status means a subagent
  waiting on its own background work, not on the person.
- The section lists four groups, each with a count, in this order, omitting
  an empty one: `Waiting on you`, `Working`, `Failed`, `Done` (the recent
  ones it shows today). The headline keeps today's running count.

## Error handling

- An unknown name in `collapsed` is ignored; a collapsed section that is also
  hidden by `sections` stays hidden.
- A wait that ends without `endWait` (a session cleared mid-prompt) leaves
  its spawn under Waiting only until the spawn ends; a done spawn is never
  waiting.
- A `Select` value outside the row's values is ignored by `act.set`'s
  existing validation.

## Testing

`tests/cockpit.test.ts`, on the terminal and the desktop surface:
- `collapsedFrom` and `collapsedToggled` unit cases (unknown names, order,
  empty).
- With `collapsed: "usage"`, the Usage section draws its title row and
  headline and no row of its body; pressing its title button saves a
  `collapsed` value without `usage`.
- A collapsed Context section still draws its Compact button.
- On desktop, the drawn tree has no `Svg` whose alt is a panel's text, the
  root `Box` has `gap: 'md'`, and a section title is a `Text` with `size:
  'heading'`; the gauges are still `Svg`.
- `themeColor` maps each named color and passes a hex through.
- On desktop, the settings screen draws a `Select` for a toggle and a choices
  row, and selecting a value saves it; the terminal settings screen draws no
  `Select`.
- A subagent ending with `reason: 'error'` is listed under `Failed`; one with
  `answer` under `Done`; a running one with an open approval prompt under
  `Waiting on you`, and under `Working` once the prompt is answered.
- On desktop, a refused number entry in settings shows its error below the
  `Input`.
- The desktop band draws its head and rows as native `Text`.

Then the full validation: `node scripts/validate-repository.mjs`, the shell
suites, `claude plugin validate` on the marketplace and every Claude plugin,
and `claude plugin test plugins/dforge`.

## Acceptance

A1. [test, high] With the `collapsed` setting `usage`, the Usage section draws its title row and headline and none of its body rows, on the terminal and on the desktop.
A2. [test, high] Pressing a section's title button saves the `collapsed` setting with that section added when it was expanded and removed when it was collapsed.
A3. [test, neg, high] A collapsed Context section still draws its Compact button.
A4. [test, high] `collapsedFrom('repo, usage, nope, usage')` returns `['usage', 'repo']`, and `collapsedFrom('')` returns `[]`.
A5. [test, high] On the desktop surface, the root of the full pane has `gap` `md`, each section title is a `Text` with `size` `heading`, and the gauges are still `Svg`.
A6. [test, neg, high] On the desktop surface, no section's rows are drawn as an `Svg` (no `Svg` carries a section's row text as its alt).
A7. [test, high] On the desktop surface, the settings screen draws a `Select` for a toggle row and for a choices row, and choosing a value saves it; the terminal settings screen draws no `Select`.
A8. [test, high] A subagent whose turn ends with reason `error` is listed under `Failed`, and one ending with `answer` under `Done`.
A9. [test, high] A running subagent with an open approval prompt is listed under `Waiting on you`, and under `Working` once the prompt is answered.
A12. [test, neg, high] The terminal settings screen draws no `Select`, and on the desktop a refused number entry shows its error below the `Input`.
A13. [test, high] On the desktop surface, the band above the prompt draws its head and rows as native `Text`, its meters as `Svg`.
A10. [demo, high] In the Claude Code desktop app, the cockpit pane shows space between sections, titles and rows in the app's own font and theme colors (switching the app between light and dark recolors them), and a section collapses and expands from its title.
A11. [demo, high] In the Claude Code desktop app, the cockpit settings screen shows dropdowns for toggles and choices and saves a change.

## Riskiest assumption

That the desktop app draws `Text size`/`weight`, theme-key colors and
named-step `gap`/`padding` as the 2.1.302 typings document, so a native panel
looks native. Evidence: the typings (`types/claude-code.d.ts`, `Text` props
and `Space`, read 2026-10-17); no desktop has rendered one for this repository
yet. unverified — the plan's first task verifies it: it renders a probe pane
and the owner checks it on the desktop app before the panels are rebuilt.

## Docs

`plugins/dforge/README.md`: a `collapsed` row in the settings table, the
settings-view paragraph (desktop dropdowns), and the cockpit paragraphs on
collapsing and the Agents groups.

## Review notes (Fable, round 1)

Issues Found, all seven applied: the deletion list now keeps what the gauges
and band meters use and converts the desktop band; the settings controls are
gated on the desktop surface, not on `Select`; a refused desktop entry shows
its error; one title-button shape per surface; chip runs inside text lines;
"Waiting on you" comes from the cockpit's own approval waits instead of
`$.agent.list()`; the collapsed exception names the Context `actions` row.
Advisory points taken: `Options`/`liveFrom` gain `collapsed`, README rows,
picture alts kept, `Math.round` on indents, `gray`/`white` mapped.

## Out of scope

- The "other sessions" row from the nested-sessions note (rank 2): not
  chosen.
- The terminal look, beyond the collapse buttons.
- A release version bump.
