---
name: darkraise-ui
description: Manages darkraise-ui components and projects — adding, composing, styling, theming, and debugging UI. Applies when working with darkraise-ui, the darkraise web template, theme axes, create-darkraise-ui, or any project with darkraise-ui in its package.json. Also triggers for "darkraise theme", "theme.config.ts", and "UiLabelsProvider".
user-invocable: true
---

# darkraise-ui

A React 19 UI kit with themed components, hooks, a seventeen-axis theme system, and layout variants. Every primitive is implemented in-house — there is no Radix UI underneath — and components are styled with Tailwind CSS 4.

**These rules were written against `darkraise-ui` 6.5.0.** The probe below prints what is actually installed. **When the installed version differs from 6.5.0, the package's own type definitions win over anything written in this skill.**

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

## Workflow

1. **Read the injected context.** The version and component list above are live.
2. **Check what is already available.** Import only components that appear in the list.
3. **Read the relevant `.d.ts`.** Every time, for every component you touch. Follow re-exports.
4. **Write the code**, using the kit's own primitives rather than markup that imitates them.
5. **Verify against the Critical Rules** below before you finish.

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
