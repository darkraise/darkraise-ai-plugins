# Theming

## Styles, presets and axes

7.0 has three levels:

- A **style** is a complete look: `flat`, `quiet` (the default), `tactile` or
  `glass`. It is the `style` axis.
- A **preset** is a named variant of one style, usually a brand (accent,
  neutral, fonts) plus structural picks. It is the `preset` axis; `base`, the
  default, is the style alone. The kit ships sixteen, such as `paper-ink`
  (Quiet), `forest-lime` (Flat), `braun-panel` (Tactile) and `mica-desk`
  (Glass).
- An **axis** is one user-changeable setting. There are twenty-three.

| Axis | Values | Default |
| --- | --- | --- |
| `mode` | `light` `dark` `system` | `system` |
| `accentColor` | `red` `coral` `orange` `amber` `yellow` `lime` `green` `emerald` `teal` `cyan` `sky` `blue` `indigo` `violet` `purple` `fuchsia` `pink` `rose` `neutral` | `blue` |
| `surfaceColor` | `slate` `gray` `cool` `zinc` `neutral` `iron` `mauve` `graphite` `stone` `sand` `olive` `sepia` (neutrals only) | `zinc` |
| `tintWithAccent` | `off` `on` | `off` |
| `signalColor` | `none`, or any accent name | `none` |
| `style` | `flat` `quiet` `tactile` `glass`, plus config styles | `quiet` |
| `preset` | `base`, plus the active style's built-in and config presets | `base` |
| `backgroundStyle` | `solid` `gradient` | `solid` |
| `gradientPattern` | `blobs` `aurora` `spotlight` `mesh` `dots` `grain` | `blobs` |
| `backgroundIntensity` | `neutral` `subtle` `balanced` `vivid` `intense` | `vivid` |
| `glassTransparency` | `low` `medium` `high` (glass styles only) | `medium` |
| `glassBlur` | `none` `low` `medium` `high` (glass styles only) | `medium` |
| `font` | `inter` `geist` `ibm-plex-sans` `hanken-grotesk` `newsreader`, plus config fonts | `hanken-grotesk` |
| `headingFont` | `body`, or any font name | `body` |
| `radius` | `sharp` `subtle` `rounded` `pill` | `rounded` |
| `density` | `compact` `cozy` `comfortable` `spacious` | `cozy` |
| `fontSize` | `small` `medium` `large` `extra-large` | `medium` |
| `contrast` | `low` `standard` `high` | `standard` |
| `darkAccentChroma` | `calm` `standard` `vivid` | `standard` |
| `elevation` | `flat` `standard` `high` | `standard` |
| `outerGlow` | `none` `subtle` `balanced` `vivid` | `none` |
| `innerGlow` | `none` `subtle` `balanced` `vivid` | `none` |
| `sidebarSelection` | `auto` `chip` `pill` `tile` `frosted` `tint` `accent` `rule` `key` `tab` | `auto` |

The authoritative unions are in `dist/theme/types.d.ts` and
`dist/theme/axes/registry.d.ts`; this table is a convenience.

## The theme config

`defaults` is a **partial** map — list only the axes you change; the rest take
the kit default. `switcher.enabled` is required.

```ts
import type { ThemeConfig } from "darkraise-ui/theme"

export const themeConfig: ThemeConfig = {
  defaults: { style: "glass", preset: "mica-desk", radius: "pill" },
  switcher: {
    enabled: true,
    axes: { sidebarSelection: false },   // false hides a control; omitted = shown
    advanced: true,                      // false drops the Advanced section
    presets: ["mica-desk", "paper-ink"], // limit the Preset control
  },
}
```

- `defaults.preset` must belong to the default style, so name `style` for any
  preset outside Quiet.
- **A preset beats your `defaults`.** Resolution per axis: the user's stored
  value, then the active preset's axes, then the style's defaults, then your
  `defaults`, then the kit default. Every built-in preset sets `accentColor`,
  `surfaceColor`, `tintWithAccent`, `signalColor`, `font` and `headingFont`, so
  your defaults for those do not show under one.
- A removed 6.x key fails type-checking in a typed `ThemeConfig` literal. In a
  JSON or cast config, it and any invalid value are ignored at runtime with
  only a dev-time `console.warn` — check the console.

## Custom styles, presets and fonts

Define them in the same config with the helpers from `darkraise-ui/theme-config`
(no React, safe in `vite.config.ts` and on a server). Read
`dist/theme/config/index.d.ts` for `StyleDefinition`, `PresetDefinition`,
`FontDefinition`, `PAINT_TOKENS` and `SIGNATURES`.

```ts
import { defineFont, definePreset, defineStyle, defineThemeConfig } from "darkraise-ui/theme-config"

export const themeConfig = defineThemeConfig({
  defaults: { style: "harbor", preset: "harbor-night" },
  switcher: { enabled: true },
  fonts: {
    "instrument-sans": defineFont({
      label: "Instrument Sans",
      family: '"Instrument Sans Variable", ui-sans-serif, system-ui, sans-serif',
      role: "sans",
    }),
  },
  styles: {
    harbor: defineStyle({
      label: "Harbor",
      extends: "quiet",
      signatures: { navSelection: "rule", tableHead: "ruled" },
      tokens: { shared: { cardRadius: "calc(var(--radius) * 1.5)" } },
    }),
  },
  presets: {
    "harbor-night": definePreset({
      label: "Harbor night",
      style: "harbor",
      axes: { accentColor: "teal", font: "instrument-sans" },
      shellStyle: "inset",
    }),
  },
})
```

- Names are kebab-case and may not reuse a built-in style, preset or font name,
  nor `base`, `default`, `glassmorphism` or `scifi` (and a font not `body`).
- Without `extends`, a style starts from the kit's unstyled defaults, not from
  Quiet.
- A font definition only names a face — the app installs and imports the font
  files itself.
- Token values reference colour tokens as `hsl(var(--primary))`; a bare
  `var(--primary)` is invalid, because colour tokens hold HSL channel triplets.
- `resolveRegistry(config).issues` lists definition errors. A definition with
  an error is dropped; the Vite plugin fails the build on it.

## Mounting and reading the theme

```tsx
import { ThemeProvider, useTheme, ThemeSwitcher, ThemeSettingsPanel } from "darkraise-ui/theme"
import { themeConfig } from "@/theme.config"

<ThemeProvider config={themeConfig}>
  <App />
</ThemeProvider>
```

Pass the **same** config to the Vite pre-render plugin, so the first paint
already carries the stored theme and your styles' CSS:

```ts
// vite.config.ts
import { darkraisePrerender } from "darkraise-ui/vite"
import { themeConfig } from "./src/theme.config"

export default defineConfig({ plugins: [darkraisePrerender({ config: themeConfig }), react()] })
```

Server-rendered apps without Vite emit the same head elements with
`themeStyleText` and `themePrerenderScript` from `darkraise-ui/theme-config`.

`useTheme()` returns every axis value with a setter (`style`/`setStyle`,
`preset`/`setPreset`, `setAxis(key, value)`), plus `resolvedMode`,
`syncStatus`, `canResetToPreset` and `resetToPreset`. `ThemeSwitcher` is the
popover control; `ThemeSettingsPanel` is the full panel, `layout="compact"` or
`"page"`. Do not build your own theme UI — these cover every axis, the Preset
control and Reset to preset.

`ThemeProvider` also takes `onChange`, a `persistence` adapter
(`load()`, `save(settings, { signal })`), `persistenceDebounce` and `nonce`.

The kit ships its five faces as woff2 inside `darkraise-ui/styles.css`; do not
add a Google Fonts link for them.

## Semantic tokens, not raw colors

The colour engine solves every colour token at runtime from the accent,
neutral, mode and contrast axes, and the style repaints surfaces. A raw
Tailwind color is a literal none of that can reach — it will not follow a mode
switch, an accent change, or a style.

**Incorrect**

```tsx
<div className="rounded-lg border border-slate-800 bg-slate-900 p-4">
  <h3 className="text-slate-100">Deployment</h3>
  <p className="text-slate-400">Last run 4 minutes ago.</p>
</div>
```

**Correct**

```tsx
<Card className="p-4">
  <CardHeader>
    <CardTitle>Deployment</CardTitle>
    <CardDescription>Last run 4 minutes ago.</CardDescription>
  </CardHeader>
</Card>
```

When you genuinely need a bare element, use the tokens:

```tsx
<div className="rounded-lg border border-border bg-card p-4 text-card-foreground">
```

### The token vocabulary

These are the Tailwind color utilities `styles.css` defines. Anything outside
this list is a raw color and breaks theming.

| Purpose | Utilities |
| --- | --- |
| Page | `bg-background`, `text-foreground` |
| Cards and panels | `bg-card`, `text-card-foreground` |
| Popovers and overlays | `bg-popover`, `text-popover-foreground` |
| Primary action | `bg-primary-fill` with `text-primary-foreground`; `bg-primary` is the raw accent |
| Accent-coloured text | `text-primary-text` — `text-primary` only clears 3:1, so use it for graphics, not text |
| Secondary action | `bg-secondary`, `text-secondary-foreground` |
| Muted / de-emphasised | `bg-muted`, `text-muted-foreground` |
| Accent (hover wash) | `bg-accent`, `text-accent-foreground` |
| Status (`destructive`, `success`, `warning`, `info`) | `bg-<status>-subtle`, `border-<status>-edge`, `text-<status>-text`, `bg-<status>-solid` with `text-<status>-solid-foreground` |
| Borders | `border-border`, `border-border-subtle`, `border-border-default`, `border-border-strong` |
| Inputs and focus | `border-input`, `ring-ring`, `ring-focus-ring` |
| Surface ladder | `bg-surface-sunken`, `bg-surface-base`, `bg-surface-sidebar`, `bg-surface-header`, `bg-surface-raised`, `bg-surface-overlay` |
| Sidebar | `bg-sidebar` |
| Charts | `chart-1` … `chart-8` (`fill-chart-1`, `bg-chart-3`, …) |

**There is no bare `bg-destructive`, `bg-success`, `bg-warning` or `bg-info`**,
and no `-foreground` pair for them. 7.0 removed those utilities; a class naming
one silently renders nothing.

### Colour tokens cannot be overridden in CSS

The engine writes colour tokens (`--primary`, `--background`, `--border`, …)
inline on `<html>`, where no stylesheet rule replaces them. Change colours
through the axes (`accentColor`, `surfaceColor`, `tintWithAccent`,
`signalColor`, `contrast`, `darkAccentChroma`), never with `:root { --primary: … }`.

## Upgrading a 6.x config

A 6.x key fails type-checking in a typed literal; in a JSON or cast config it
is ignored with a dev-time warning and the setting is lost. Rename them:

| 6.x | 7.0 |
| --- | --- |
| `preset: "default" \| "glass"` | `style: "quiet" \| "glass"`; `preset` now picks a preset of the style |
| `preset: "scifi"` | removed |
| `surfaceIntensity`, `borderIntensity` | `contrast` |
| `accentIntensity` (and the older `accentVibrancy`) | `darkAccentChroma` |
| `controlDepth`, `buttonElevation` | removed, no replacement |
| `shellStyle` in `defaults` | the layout's `defaultShellStyle` prop |
| `sidebarActiveBar` | `sidebarSelection` |
| `elevation: "low" \| "medium"` | `elevation: "standard"` |
| `surfaceColor: <accent name>` | a neutral plus `tintWithAccent: "on"` |
| `[data-preset="glass"]` selectors | `[data-style="glass"]` |

The full list, including removed CSS tokens and component changes, is in the
[7.0 upgrade guide](https://github.com/darkraise/darkraise-web-template/blob/master/docs/upgrade-7.0.md).
