---
name: darkraise-ui
description: Manages darkraise-ui components and projects — adding, composing, styling, theming, translating, and debugging UI. Applies when working with darkraise-ui, the darkraise web template, theme styles, presets and axes, create-darkraise-ui, or any project with darkraise-ui in its package.json. Also triggers for "darkraise theme", "theme.config.ts", "defineStyle", "UiLabelsProvider", and "UiI18nProvider".
user-invocable: true
---

# darkraise-ui

A React 19 UI kit with themed components, hooks, a theme system of styles, presets and twenty-three axes, layouts, and built-in localization. Every primitive is implemented in-house — there is no Radix UI underneath — and components are styled with Tailwind CSS 4.

**These rules target `darkraise-ui` 7.0.** The discovery steps below establish what is actually installed. **When the installed version differs, the package's own type definitions win over anything written in this skill.** A project still on 6.x uses different theme keys and tokens; follow the [7.0 upgrade guide](https://github.com/darkraise/darkraise-web-template/blob/master/docs/upgrade-7.0.md) to move it, or trust its installed types over the rules below.

## Principles

1. **Use the kit before writing custom UI.** Discover the installed component list first — the kit is wider than it looks, and a styled `div` is almost always a component you did not know existed.
2. **Compose, don't reinvent.** A settings page is `Tabs` + `Card` + form fields. A dashboard is `SidebarLayout` + `Card` + `ChartContainer` + `DataTable`.
3. **Use built-in variants before custom styles.** `variant="outline"`, `size="sm"` — the variant already carries the theme's opinion; a `className` color does not.
4. **Use semantic tokens, never raw color values.** The colour engine solves these tokens at runtime from the theme axes, and the active style repaints the surfaces, so a raw Tailwind color silently opts the element out of the entire theme system.

## Current Project Context

Use the active client's shell and file-reading tools explicitly. Start in the
consumer project, inspect its `package.json`, and locate the actual installed
`darkraise-ui` package. Read that package's `package.json` version and list its
`dist/components/` directories before selecting components.

For a hoisted or linked workspace dependency, follow the resolved package path
from the consumer's package-manager metadata (`pnpm why darkraise-ui` when pnpm
is used) and filesystem links. Treat `node_modules/darkraise-ui` below as the
resolved package directory, not a required physical layout. If the dependency
is missing or its location cannot be resolved, report that and request the
consumer project location or installation. Never substitute the pinned API for
an unavailable installed package. No inline preprocessing is required by either
Claude Code or Codex.

## Read the types before you write

**Before using, creating, fixing, or debugging any component, read
`node_modules/darkraise-ui/dist/components/<kebab-name>/index.d.ts`** and the
files it re-exports. These files are small and exact — they give you the
complete variant union, size union, and props interface. Do not infer props
from a component's name or from shadcn/ui.

Subpath entry points each have their own typings, read the same way:

| Import | Typings |
| --- | --- |
| `darkraise-ui/theme` | `dist/theme/index.d.ts` |
| `darkraise-ui/hooks` | `dist/hooks/index.d.ts` |
| `darkraise-ui/forms` | `dist/forms/index.d.ts` |
| `darkraise-ui/layout` | `dist/layout/index.d.ts` |
| `darkraise-ui/data-table` | `dist/data-table/index.d.ts` |
| `darkraise-ui/router` | `dist/router/index.d.ts` |
| `darkraise-ui/errors` | `dist/errors/index.d.ts` |
| `darkraise-ui/labels` | `dist/labels/index.d.ts` |
| `darkraise-ui/lib` | `dist/lib/index.d.ts` |
| `darkraise-ui/theme-config` | `dist/theme/config/index.d.ts` |
| `darkraise-ui/vite` | `dist/vite/index.d.ts` |
| `darkraise-ui/i18n` | `dist/i18n/index.d.ts` |
| `darkraise-ui/i18n/react-i18next` | `dist/i18n/react-i18next/index.d.ts` |
| `darkraise-ui/locales/en`, `/locales/vi` | `dist/locales/en.d.ts`, `dist/locales/vi.d.ts` |

**Follow re-exports.** An `index.d.ts` is usually a list of `export * from
"./Calendar"` lines; the declarations are in those sibling files
(`dist/components/calendar/Calendar.d.ts`, `dist/lib/utils.d.ts` for `cn`).
Import from the subpath, never from a file path inside `dist`.

**Server components.** Every entry except `lib`, `locales/*`, `theme-config`
and `vite` starts with `"use client"`. A server component may render kit
components with serialisable props, but kit hooks, functions passed as props,
and values such as `ACCENT_COLORS` belong in a `"use client"` file.

## Critical Rules

These rules are **always enforced**. Each links to a file with Incorrect/Correct code pairs.

### Theming → [theming.md](./rules/theming.md)

- **Semantic tokens only.** `bg-background`, `text-muted-foreground`, `bg-card`, `border-border`, `bg-primary-fill`. Never `bg-blue-500`.
- **No bare status utilities.** `bg-destructive`, `bg-success`, `bg-warning`, `bg-info` were removed; use `-subtle`, `-edge`, `-text`, `-solid`, `-solid-foreground`.
- **The theme lives in `theme.config.ts`.** `defaults` is partial; pick a `style` (`flat`, `quiet`, `tactile`, `glass`) and optionally a `preset` of it. Pass the same config to `ThemeProvider` and `darkraisePrerender`.
- **6.x keys are gone.** `surfaceIntensity`, `accentIntensity`, `controlDepth`, `buttonElevation` and `shellStyle` fail to compile in a typed config; `preset: "default"` compiles but is ignored with only a dev-time warning, as is anything in a JSON or cast config. See the rename table in theming.md.
- **Custom looks are definitions, not CSS hacks.** `defineStyle`, `definePreset`, `defineFont` from `darkraise-ui/theme-config`.

### Styling → [styling.md](./rules/styling.md)

- **Never `!important`, never Tailwind's `!` modifier.** The layer order already makes your utilities win; colour tokens are inline and change only through the axes.
- **State variants are independent.** `bg-red-500` overrides the resting state only; hover needs its own `hover:bg-red-600`.
- **`className` carries layout, not color or typography.**
- **Use `cn()` from `darkraise-ui/lib` for conditional classes.**
- **Tailwind 4 only.** There is no `tailwind.config.js`.

### Composition → [composition.md](./rules/composition.md)

- **No Radix.** Never install `@radix-ui/*`. Never assume `asChild` — check the `.d.ts`.
- **Subpath imports, not the barrel.** `MultiSelect` and the chart parts are not re-exported from the barrel at all and are reachable only by subpath.
- **Dialog, Sheet, and Drawer always need a title.**
- **Use `EmptyState`, `Banner`, `Alert`, `Skeleton`, `Separator`, `Badge`** instead of styled divs.
- **Never hardcode English inside a kit component.** Override strings with `UiLabelsProvider`; switch language with `UiI18nProvider` (or `AppI18nProvider` for react-i18next) and the shipped `en` / `vi` packs.

### Forms → [forms.md](./rules/forms.md)

- **Use the `darkraise-ui/forms` field primitives.** They already wrap `Field` correctly.
- **Validation is `isInvalid` + `errors`.** Never hand-rolled error markup.
- **Drop to raw `Field` / `FieldGroup` only for a control the kit does not cover.**

### Layout & Data → [layout-data.md](./rules/layout-data.md)

- **Use `SidebarLayout` (or another kit layout) + `PageHeader`,** not a hand-built app shell. Shell style is a layout prop.
- **Mount `RouterAdapterProvider`.** The kit never imports a router; the adapter's `Link` must forward `aria-current`.
- **Use `DataTable`,** not a hand-built table.
- **The provider stack order is load-bearing.**

## Key Patterns

```tsx
// Semantic tokens, not raw colors — the theme axes recompute these.
<Card className="p-4">                      // correct
<div className="bg-slate-900 p-4">          // wrong
<Badge className="bg-success-subtle text-success-text" />   // correct
<Badge className="bg-success text-success-foreground" />    // wrong: removed in 7.0

// Subpath imports, not the barrel.
import { Button } from "darkraise-ui/components/button"   // correct
import { Button } from "darkraise-ui"                     // wrong

// Form fields: the forms primitives already wrap Field.
<TextField name="email" label="Email" value={v} onChange={setV} />  // correct
<div><Label /><Input /><p className="text-red-500" /></div>         // wrong

// Validation: isInvalid + errors, never hand-rolled markup.
<TextField isInvalid errors={[{ message: "Invalid email." }]} />   // correct
<Input className="border-red-500" />                              // wrong

// Conditional classes: cn(), not a template-literal ternary.
<Card className={cn("p-4", isActive && "ring-2")} />       // correct
<Card className={`p-4 ${isActive ? "ring-2" : ""}`} />     // wrong

// State variants are independent — hover needs its own utility.
<Button className="bg-red-500 hover:bg-red-600" />         // correct
<Button className="bg-red-500" />                          // wrong: hover unchanged
```

## Component Selection

| Need | Use |
| --- | --- |
| Button / action | `Button` with a variant; `ButtonGroup` for a set |
| Form inputs | `Input`, `Textarea`, `Select`, `Combobox`, `Switch`, `Checkbox`, `RadioGroup`, `NumberInput`, `PasswordInput`, `InputOTP`, `Slider`, `DateInput`, `TimePicker` |
| Toggle between options | `ToggleGroup`, or `SegmentGroup` for a segmented control |
| Multi-value selection | `MultiSelect`, `TagsInput`, `CascadeSelect`, `Listbox` |
| Data display | `Table`, `Card`, `Badge`, `Avatar`, `Stat`, `Timeline`, `TreeView`, `JsonTreeView`, `RatingGroup`, `Timer` |
| Large tabular data | `DataTable` from `darkraise-ui/data-table` |
| App shell | `SidebarLayout`, `TopNavLayout`, `StackedLayout`, `SplitPanelLayout`, `PageHeader` from `darkraise-ui/layout` |
| In-page layout | `Stack`, `Inline`, `Container`, `Grid`, `Section`, `Box`, `Center` from `darkraise-ui/layout` |
| Navigation | `NavigationMenu`, `Breadcrumb`, `Tabs`, `Pagination`, `Steps`, `Toolbar` |
| Overlays | `Dialog` (modal), `Sheet` (side panel), `Drawer` (bottom sheet), `AlertDialog` (confirmation), `Popover`, `HoverCard` |
| Feedback | `toast()` + `Toaster` from `components/sonner`, `Alert` (inline), `Banner` (page-level), `Progress`, `Skeleton`, `Spinner` |
| Empty states | `EmptyState` |
| Command palette | `Command`, or `CommandDialog` for a modal one |
| Menus | `DropdownMenu`, `ContextMenu`, `Menubar` |
| Tooltips / info | `Tooltip`, `HoverCard`, `Popover` |
| Charts | `ChartContainer` with `recharts` (optional peer, subpath only), `ContributionGraph` |
| Layout | `Card`, `Separator`, `ResizablePanelGroup`, `ScrollArea`, `Accordion`, `Collapsible`, `AspectRatio`, `Frame` |
| Media & files | `FileUpload`, `ImageCropper`, `ImageEditor`, `Carousel`, `QrCode`, `SignaturePad` |
| Onboarding | `Tour`, `Steps` |
| Floating windows | `FloatingPanel` with `FloatingPanelProvider` + `FloatingPanelHost` |
| Language picker | `LocaleSwitcher` from `components/locale-switcher` |
| Theme controls | `ThemeSwitcher`, `ThemeSettingsPanel` from `darkraise-ui/theme` |
| Error pages | `NotFoundPage`, `ErrorPage`, `ServerErrorPage`, `MaintenancePage` from `darkraise-ui/errors` |

## Workflow

1. **Discover project context.** Resolve the installed version and component list using the steps above.
2. **Check what is already available.** Import only components that appear in the list.
3. **Read the relevant `.d.ts`.** Every time, for every component you touch. Follow re-exports.
4. **Write the code**, using the kit's own primitives rather than markup that imitates them.
5. **Verify against the Critical Rules** above before you finish.

## Quick Reference

```bash
# Scaffold a new project (asks for brand axes and style; --help lists every flag)
npm create darkraise-ui@latest

# Add to an existing project
pnpm add darkraise-ui
```

```tsx
// Subpath imports, not the barrel
import { Button } from "darkraise-ui/components/button"
import { ThemeProvider } from "darkraise-ui/theme"
import { TextField } from "darkraise-ui/forms"
import { defineThemeConfig } from "darkraise-ui/theme-config"
import { darkraisePrerender } from "darkraise-ui/vite"   // in vite.config.ts
```

```css
/* globals.css — Tailwind 4, no tailwind.config.js; the kit's fonts are bundled */
@import "darkraise-ui/styles.css";
```
