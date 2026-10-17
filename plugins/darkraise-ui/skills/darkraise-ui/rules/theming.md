# Theming

## The seventeen axes

`ThemeConfig.defaults` declares exactly seventeen keys. **None is optional** —
omitting one is a type error, not a silent default.

| Axis | Values |
| --- | --- |
| `accentColor` | `red` `coral` `orange` `amber` `yellow` `lime` `green` `emerald` `teal` `cyan` `sky` `blue` `indigo` `violet` `purple` `fuchsia` `pink` `rose` |
| `surfaceColor` | `slate` `gray` `cool` `zinc` `neutral` `iron` `mauve` `graphite` `stone` `sand` `olive` `sepia`, plus the eighteen accent hues |
| `preset` | `default` `glass` `scifi` |
| `backgroundStyle` | `solid` `gradient` |
| `backgroundIntensity` | `neutral` `subtle` `balanced` `vivid` `intense` |
| `gradientPattern` | `blobs` `aurora` `spotlight` `mesh` |
| `mode` | `light` `dark` `system` |
| `density` | `compact` `cozy` `comfortable` `spacious` |
| `elevation` | `flat` `low` `medium` `high` |
| `buttonElevation` | `flat` `low` `medium` `high` |
| `surfaceIntensity` | `flat` `subtle` `balanced` `bold` |
| `radius` | `sharp` `subtle` `rounded` `pill` |
| `fontSize` | `small` `medium` `large` `extra-large` |
| `accentIntensity` | `calm` `balanced` `vivid` `intense` |
| `controlDepth` | `flush` `subtle` `recessed` `deep` |
| `outerGlow` | `none` `subtle` `balanced` `vivid` |
| `innerGlow` | `none` `subtle` `balanced` `vivid` |

Read `dist/theme/index.d.ts` and the type module it imports for the authoritative
unions — the lists above are a convenience, and the types are the contract.

## Semantic tokens, not raw colors

Every axis recomputes the theme's tokens at runtime. A raw Tailwind color is a
literal that no axis can reach, so the element silently stops participating in
the theme — it will not follow a mode switch, an accent change, or a preset.

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

These are the Tailwind color utilities the theme defines. Anything outside this
list is a raw color and breaks theming.

| Purpose | Utilities |
| --- | --- |
| Page | `bg-background`, `text-foreground` |
| Cards and panels | `bg-card`, `text-card-foreground` |
| Popovers and overlays | `bg-popover`, `text-popover-foreground` |
| Primary action | `bg-primary`, `text-primary-foreground`, `bg-primary-fill` |
| Secondary action | `bg-secondary`, `text-secondary-foreground` |
| Muted / de-emphasised | `bg-muted`, `text-muted-foreground` |
| Accent | `bg-accent`, `text-accent-foreground` |
| Semantic | `bg-destructive`, `bg-success`, `bg-warning`, `bg-info` and their `-foreground` pairs |
| Borders | `border-border`, `border-border-subtle`, `border-border-default`, `border-border-strong` |
| Inputs and focus | `bg-input`, `ring-ring`, `ring-focus-ring` |
| Raise ladder | `bg-surface-sunken`, `bg-surface-base`, `bg-surface-sidebar`, `bg-surface-header`, `bg-surface-raised`, `bg-surface-overlay` |
| Sidebar | `bg-sidebar` |

## The 6.0 → 6.5 migration

Three breaking changes landed in twelve days. A `theme.config.ts` written against
6.0 will not type-check against 6.5.

**Incorrect** — a 6.0-era config

```ts
export const themeConfig: ThemeConfig = {
  defaults: {
    accentColor: "blue",
    surfaceColor: "slate",
    accentVibrancy: "balanced",   // renamed
    // surfaceIntensity missing   — now required
    // controlDepth missing       — now required
    ...
  },
}
```

**Correct**

```ts
export const themeConfig: ThemeConfig = {
  defaults: {
    accentColor: "blue",
    surfaceColor: "slate",
    accentIntensity: "balanced",  // was accentVibrancy
    surfaceIntensity: "balanced", // now required
    controlDepth: "recessed",     // now required
    ...
  },
}
```

`accentVibrancy` no longer exists at any version. If you see it, it is stale code.

## Mounting and reading the theme

`ThemeProvider` wraps the app and takes the config. It is the second provider in
the stack — see [layout-data.md](./layout-data.md) for the full order.

```tsx
import { ThemeProvider, useTheme, ThemeSwitcher, ThemeSettingsPanel } from "darkraise-ui/theme"
import { themeConfig } from "@/theme.config"

<ThemeProvider config={themeConfig}>
  <App />
</ThemeProvider>
```

`useTheme()` reads and updates the current settings. `ThemeSwitcher` is a
ready-made popover control; `ThemeSettingsPanel` is the full panel, in `compact`
or `page` layout. Do not build your own theme UI — these exist and are wired to
every axis.

`ThemeProvider` also accepts `onChange` and a `persistence` adapter, so
persisting a user's theme does not require lifting state.

### Which axes the switcher exposes

`ThemeConfig.switcher.axes` is a per-axis boolean map. Turning an axis off hides
it from the switcher; it does not change the default. A preset may also hide
common axes it owns, through `hiddenCommonAxes`.

## Do not quote the package description

`package.json`'s `description` field advertises a six-axis theme system. It is
stale — there are seventeen axes. The same field's component and hook counts are also
wrong. **The axes are whatever `ThemeConfig` declares**, and nothing else is
authoritative.
