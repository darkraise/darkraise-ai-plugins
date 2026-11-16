# UI/UX contract template

## The section

The contract is one spec section, `## UI/UX contract`. Its first line is the
depth line; the three parts follow as `###` headings. Every item is either a
bullet that starts with its bold ID, continued on lines indented by two
spaces, or a table row whose first cell is the ID. IDs are numbered per part,
never repeat and are never reused. `scripts/ui-proof contract <spec>` lists
the IDs the parser sees; run it after writing the section.

````markdown
## UI/UX contract

**UI/UX depth:** feature — a new settings screen and its save flow

### UI

- **UI-1** — Settings page: `SidebarLayout` with one `Card` per group, tokens
  `surface` and `muted-foreground`, no raw values.
  Board: `docs/ux/boards/settings.png` (default, saving, saved, error).
- **UI-2** — Typography: page title `heading-lg`, group titles `heading-sm`,
  help text `body-sm muted`.

### UX

- **UX-1** — Flow "change display name": entry from the account menu and the
  deep link `/settings#profile`; Save is disabled until the value changes;
  Escape or Cancel restores the saved value; back returns to the previous page.
- **UX-2** — State matrix, profile card:

  | State | Shows |
  |---|---|
  | loading | skeleton of the card, no layout shift |
  | error | "Couldn't load your profile" and a Retry button |
  | worst case | a 64-character name wraps inside the card |

- **UX-3** — Saving: the button shows its pending state after 200 ms, the
  toast says "Saved", focus stays on the field.

### Output promise

| ID | Promise |
|---|---|
| OP-1 | The built screens match boards UI-1 in components, tokens, hierarchy and copy; pixel offsets may differ. |
| OP-2 | Proven at 375x812, 768x1024 and 1440x900, light and dark themes. |
| OP-3 | WCAG 2.2 AA; LCP under 2.5 s on the settings route. |
| OP-4 | Declared deviation: no avatar upload (out of scope, owner 2026-10-24). |
````

## What each part holds

**UI (`UI-<n>`) — the interface.** The component map: every mockup region
mapped to an existing component of the design system and its tokens, never a
raw value; layout and hierarchy; typography; imagery and iconography; the
theme variants; the state boards, each with its path and the states it shows.

**UX (`UX-<n>`) — the experience.** Users and their jobs; every flow with its
entry points, alternate paths, cancel, undo, back and deep links; a state
matrix per surface (walk `state-catalogue.md`); interactions and feedback,
including where focus goes after each action (walk `interaction-rules.md`);
forms and validation; the copy deck; responsive changes per breakpoint; motion
and its reduced-motion fallback; accessibility; non-functional requirements
with numbers (performance budgets, data volumes, i18n and right-to-left,
supported platforms).

**Output promise (`OP-<n>`) — what the shipped result guarantees as a whole.**
Which state boards are binding and how closely; the viewports, themes and
platforms it is proven on; the accessibility level; the budgets; every
declared deviation from the mockup with its reason; what is out of scope.
`OP-` items are proven, not built: no plan task has to name them, every proof
must cover them.

## From items to acceptance

Each item becomes one or more acceptance statements whose text starts with
its ID:

```
A12. [test, high] UX-1: Escape restores the saved display name and keeps focus on the field.
A13. [demo, high] UI-1: The settings page matches its board in light and dark themes.
```

Tag a behaviour statement `test` when the profile's `**UI test runner:**`
names a runner the project can run; otherwise tag it `demo`. Either way, its
row in the proof report proves it.

## The touch delta

At touch depth there is no spec section. The proof report starts with a
`## Delta` section in the same item format: the depth line, then 5 to 15
items naming the states, viewports, themes and neighbouring surfaces the
change affects.

````markdown
## Delta

**UI/UX depth:** touch — the date picker closes on Escape

- **UX-1** — Escape closes the picker and returns focus to the date field.
- **UX-2** — The picker still opens by keyboard (Enter, Space) and pointer.
- **UI-1** — Dark theme: the focus ring stays visible on the field.
- **OP-1** — Proven at 375x812 and 1440x900, light and dark.
````

## Profile

`<docs>/ui-ux/profile.md`, created the first time the skill runs in a project
and read before every UI task. Ask the user for what the repository cannot
tell you. `**UI paths:**` takes bash case patterns matched against
repository-relative paths (`*` crosses `/`); without it the platform defaults
apply (`scripts/ui-proof paths` prints them).

````markdown
# UI profile

**Platform:** web
**Harness:** `npm run dev`, served at http://localhost:5173, driven by Playwright MCP
**UI test runner:** `npx playwright test`
**UI paths:** `src/*.tsx` `src/*.css`
**Design system:** darkraise-ui 7.x, theme in `src/theme.config.ts`
**Token paths:** `src/theme.config.ts`
**Viewports:** 375x812, 768x1024, 1440x900
**Themes:** light, dark
**Users:** photographers culling a shoot on a laptop, keyboard-heavy
**Voice:** plain, sentence case, verbs on buttons
**Screenshots:** local

## Decisions

- 2026-10-24 — Toasts confirm saves; dialogs only for destructive actions.
````
