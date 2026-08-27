---
name: darkraise-ui
description: Manages darkraise-ui components and projects — adding, composing, styling, theming, and debugging UI. Applies when working with darkraise-ui, the darkraise web template, theme axes, create-darkraise-ui, or any project with darkraise-ui in its package.json. Also triggers for "darkraise theme", "theme.config.ts", and "UiLabelsProvider".
user-invocable: true
---

# darkraise-ui

A React 19 UI kit with themed components, hooks, a seventeen-axis theme system, and layout variants. Every primitive is implemented in-house — there is no Radix UI underneath — and components are styled with Tailwind CSS 4.

**These rules were written against `darkraise-ui` 6.5.0.** The probe below prints what is actually installed. **When the installed version differs from 6.5.0, the package's own type definitions win over anything written in this skill.**

## Principles

1. **Use the kit before writing custom UI.** Check the injected component list first — the kit is wider than it looks, and a styled `div` is almost always a component you did not know existed.
2. **Compose, don't reinvent.** A settings page is `Tabs` + `Card` + form fields. A dashboard is `SidebarLayout` + `Card` + `Chart` + `DataTable`.
3. **Use built-in variants before custom styles.** `variant="outline"`, `size="sm"` — the variant already carries the theme's opinion; a `className` color does not.
4. **Use semantic tokens, never raw color values.** Every one of the seventeen theme axes recomputes these tokens at runtime, so a raw Tailwind color silently opts the element out of the entire theme system.

## Current Project Context

Installed version:

```
!`cat node_modules/darkraise-ui/package.json | grep '"version"'`
```

Available components:

```
!`ls node_modules/darkraise-ui/dist/components/*.d.ts`
```

If the first probe prints `No such file or directory`, the package is not installed at that path. Say so and offer to install it — never guess at the API. In a workspace that hoists differently, `pnpm why darkraise-ui` resolves the real location.

## Read the types before you write

**Before using, creating, fixing, or debugging any component, read
`node_modules/darkraise-ui/dist/components/<kebab-name>.d.ts`.** These files are
small and exact — they give you the complete variant union, size union, and props
interface. Do not infer props from a component's name or from shadcn/ui.

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

**Follow re-exports.** Some typings pull their principal symbols from a shared
chunk file rather than declaring them inline. `calendar.d.ts` declares its hook
types locally but re-exports `Calendar` and `CalendarProps` from a chunk; so does
`dist/lib/index.d.ts` for `cn`. If the symbol you need is re-exported, read the
chunk file the import names. Never write a chunk filename into code or docs — the
hash in it changes on every build.

## Critical Rules

These rules are **always enforced**. Each links to a file with Incorrect/Correct code pairs.

### Theming → [theming.md](./rules/theming.md)

- **Semantic tokens only.** `bg-background`, `text-muted-foreground`, `bg-card`, `border-border`, `bg-primary`. Never `bg-blue-500`.
- **Theme axes live in `theme.config.ts`.** All seventeen keys are required.
- **`accentVibrancy` no longer exists.** It was renamed `accentIntensity`; `surfaceIntensity` and `controlDepth` became required in the same line of releases.

### Styling → [styling.md](./rules/styling.md)

- **Never `!important`, never Tailwind's `!` modifier.** The layer order already makes your utilities win.
- **State variants are independent.** `bg-red-500` overrides the resting state only; hover needs its own `hover:bg-red-600`.
- **`className` carries layout, not color or typography.**
- **Use `cn()` from `darkraise-ui/lib` for conditional classes.**
- **Tailwind 4 only.** There is no `tailwind.config.js`.

### Composition → [composition.md](./rules/composition.md)

- **No Radix.** Never install `@radix-ui/*`. Never assume `asChild` — check the `.d.ts`.
- **Subpath imports, not the barrel.** Some components — `MultiSelect` among them — are not re-exported from the barrel at all and are reachable only by subpath.
- **Dialog, Sheet, and Drawer always need a title.**
- **Use `EmptyState`, `Banner`, `Alert`, `Skeleton`, `Separator`, `Badge`** instead of styled divs.
- **Never hardcode English inside a kit component.** Override through `UiLabelsProvider`.

### Forms → [forms.md](./rules/forms.md)

- **Use the `darkraise-ui/forms` field primitives.** They already wrap `Field` correctly.
- **Validation is `isInvalid` + `errors`.** Never hand-rolled error markup.
- **Drop to raw `Field` / `FieldGroup` only for a control the kit does not cover.**

### Layout & Data → [layout-data.md](./rules/layout-data.md)

- **Use `SidebarLayout` + `PageHeader`,** not a hand-built app shell.
- **Mount `RouterAdapterProvider`.** The kit never imports a router.
- **Use `DataTable`,** not a hand-built table.
- **The provider stack order is load-bearing.**

## Key Patterns

```tsx
// Semantic tokens, not raw colors — the theme axes recompute these.
<Card className="p-4">                      // correct
<div className="bg-slate-900 p-4">          // wrong

// Subpath imports, not the barrel.
import { Button } from "darkraise-ui/components/button"   // correct
import { Button } from "darkraise-ui"                     // wrong

// Form fields: the forms primitives already wrap Field.
<TextField name="email" label="Email" value={v} onChange={setV} />  // correct
<div><Label /><Input /><p className="text-red-500" /></div>         // wrong

// Validation: isInvalid + errors, never hand-rolled markup.
<TextField isInvalid errors={["Invalid email."]} />        // correct
<Input className="border-red-500" />                       // wrong

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
| Data display | `Table`, `Card`, `Badge`, `Avatar`, `Stat`, `Timeline`, `TreeView`, `JsonTreeView` |
| Large tabular data | `DataTable` from `darkraise-ui/data-table` |
| Navigation | `SidebarLayout` from `darkraise-ui/layout`, `NavigationMenu`, `Breadcrumb`, `Tabs`, `Pagination`, `Steps` |
| Overlays | `Dialog` (modal), `Sheet` (side panel), `Drawer` (bottom sheet), `AlertDialog` (confirmation), `Popover`, `HoverCard` |
| Feedback | `sonner` (toast), `Alert` (inline), `Banner` (page-level), `Progress`, `Skeleton`, `Spinner` |
| Empty states | `EmptyState` |
| Command palette | `Command`, inside `Dialog` |
| Menus | `DropdownMenu`, `ContextMenu`, `Menubar` |
| Tooltips / info | `Tooltip`, `HoverCard`, `Popover` |
| Charts | `Chart`, `ContributionGraph` |
| Layout | `Card`, `Separator`, `Resizable`, `ScrollArea`, `Accordion`, `Collapsible`, `AspectRatio`, `Frame` |
| Media & files | `FileUpload`, `ImageCropper`, `ImageEditor`, `Carousel`, `QrCode`, `SignaturePad` |
| Onboarding | `Tour`, `Steps` |
| Floating windows | `FloatingPanel` with `FloatingPanelProvider` + `FloatingPanelHost` |
| Error pages | `NotFoundPage`, `ErrorPage`, `ServerErrorPage`, `MaintenancePage` from `darkraise-ui/errors` |

## Workflow

1. **Read the injected context.** The version and component list above are live.
2. **Check what is already available.** Import only components that appear in the list.
3. **Read the relevant `.d.ts`.** Every time, for every component you touch. Follow re-exports.
4. **Write the code**, using the kit's own primitives rather than markup that imitates them.
5. **Verify against the Critical Rules** above before you finish.

## Quick Reference

```bash
# Scaffold a new project
npm create darkraise-ui@latest

# Add to an existing project
pnpm add darkraise-ui
```

```tsx
// Subpath imports, not the barrel
import { Button } from "darkraise-ui/components/button"
import { ThemeProvider } from "darkraise-ui/theme"
import { TextField } from "darkraise-ui/forms"
```

```css
/* globals.css — Tailwind 4, no tailwind.config.js */
@import "darkraise-ui/styles.css";
```
