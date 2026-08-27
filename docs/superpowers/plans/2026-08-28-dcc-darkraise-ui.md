# dcc-darkraise-ui Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Implementer assignments:** each task names its implementer agent in an
> `**Implementer:**` line. When executing with
> superpowers:subagent-driven-development, REQUIRED SUB-SKILL:
> dcc-superpower-companions:dispatching-tiered-implementers. Under
> superpowers:executing-plans these lines are inert; ignore them.

**Goal:** Ship a marketplace plugin whose single skill makes Claude write idiomatic `darkraise-ui` code — correct theming, the CSS layer contract, kit primitives over hand-rolled markup — on the first attempt.

**Architecture:** One plugin, one skill. `SKILL.md` carries opinionated knowledge (rules, selection guidance, workflow) and injects shell probes that read the installed package; five `rules/*.md` files carry Incorrect/Correct code pairs; exact component props are never written down, they are read live from `node_modules/darkraise-ui/dist/components/*.d.ts`.

**Tech Stack:** Markdown skill files, Claude Code plugin manifest schema, `claude plugin validate`, `claude plugin eval`.

**Spec:** `docs/superpowers/specs/2026-08-27-darkraise-framework-skills-design.md`

## Global Constraints

- Plugin name must start with `dcc-` and agree across the directory name, `plugins/<name>/.claude-plugin/plugin.json` `name`, and the `.claude-plugin/marketplace.json` entry. (CLAUDE.md)
- `claude plugin validate .` must pass after every task that touches a manifest.
- English only in all files. Conventional commits: `<type>(<scope>): <subject>`, subject ≤50 chars, imperative, no period.
- Version pinned in `SKILL.md`: `darkraise-ui` **6.5.0**.
- Never cite a `dist/*-<hash>.d.ts` chunk filename in skill prose — the hash changes every build.
- Never quote `packages/ui/package.json`'s `description` field; its counts ("65 themed components, 38 hooks, 6-axis theming") are stale on all three.
- Rule files state a rule, then an **Incorrect** block, then a **Correct** block. Prose without a code pair does not change behaviour.
- Source of truth for every claim: `D:\Repositories\Personal\darkraise-web-template\`. Verify before writing; do not assert from memory.

---

### Task 1: Plugin scaffold and marketplace registration

**Files:**
- Create: `plugins/dcc-darkraise-ui/.claude-plugin/plugin.json`
- Create: `plugins/dcc-darkraise-ui/README.md`
- Modify: `.claude-plugin/marketplace.json` (append to the `plugins` array)

**Interfaces:**
- Consumes: nothing.
- Produces: the plugin root `plugins/dcc-darkraise-ui/`, under which Task 2 creates `skills/darkraise-ui/SKILL.md`.

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing check**

Run this and expect it to fail — the plugin does not exist yet:

```bash
test -f plugins/dcc-darkraise-ui/.claude-plugin/plugin.json && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Create the plugin manifest**

Create `plugins/dcc-darkraise-ui/.claude-plugin/plugin.json`:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
  "name": "dcc-darkraise-ui",
  "description": "Teaches Claude to write idiomatic darkraise-ui code: the 17-axis theme system, the CSS layer override contract, kit form and layout primitives over hand-rolled markup, and exact component props read live from the installed package's type definitions.",
  "version": "0.1.0",
  "author": {
    "name": "Darkraise"
  },
  "homepage": "https://github.com/darkraise/claude-code-plugins/tree/main/plugins/dcc-darkraise-ui",
  "repository": "https://github.com/darkraise/claude-code-plugins",
  "license": "MIT",
  "keywords": [
    "darkraise-ui",
    "react",
    "tailwind",
    "design-system",
    "theming",
    "component-library"
  ]
}
```

- [ ] **Step 3: Register in the marketplace**

Append this object to the `plugins` array in `.claude-plugin/marketplace.json`, after the `dcc-statusline` entry:

```json
{
  "name": "dcc-darkraise-ui",
  "source": "./plugins/dcc-darkraise-ui",
  "description": "Teaches Claude to write idiomatic darkraise-ui code: the 17-axis theme system, the CSS layer override contract, kit form and layout primitives over hand-rolled markup, and exact component props read live from the installed package's type definitions.",
  "category": "development",
  "keywords": ["darkraise-ui", "react", "tailwind", "design-system", "theming", "component-library"]
}
```

- [ ] **Step 4: Write the README**

Create `plugins/dcc-darkraise-ui/README.md`. It must contain, as its own sections:

1. **What it does** — one paragraph: the skill fires in any project with `darkraise-ui` installed and supplies the kit's opinions.
2. **Invocation** — state the qualified slash form `/dcc-darkraise-ui:darkraise-ui`, and that the bare `/darkraise-ui` works only while no other installed plugin claims that skill name.
3. **How it stays current** — the skill pins `darkraise-ui` 6.5.0 and injects shell probes that print the installed version and component list; when they disagree, the package's own type definitions win.
4. **Requirement** — the probes use `!`-backtick command injection, a documented Claude Code feature that works on Windows through Git Bash. A permission policy can disable it, in which case the skill silently degrades to its prose with no visible error.

- [ ] **Step 5: Verify both checks pass**

```bash
test -f plugins/dcc-darkraise-ui/.claude-plugin/plugin.json && echo PASS || echo FAIL
claude plugin validate .
```

Expected: `PASS`, then validation success with no errors.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-darkraise-ui .claude-plugin/marketplace.json
git commit -m "feat(darkraise-ui): scaffold plugin and register it"
```

---

### Task 2: SKILL.md mechanism — frontmatter, version pin, probes, workflow

**Files:**
- Create: `plugins/dcc-darkraise-ui/skills/darkraise-ui/SKILL.md`

**Interfaces:**
- Consumes: the plugin root from Task 1.
- Produces: `SKILL.md` containing the probe block and the read-the-types contract. Task 3 appends the body to this same file; Tasks 4–8 are linked from the Critical Rules index Task 3 writes.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 1 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

```bash
grep -q 'dist/components' plugins/dcc-darkraise-ui/skills/darkraise-ui/SKILL.md 2>/dev/null && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Write the frontmatter and version pin**

Create the file starting with exactly this:

````markdown
---
name: darkraise-ui
description: Manages darkraise-ui components and projects — adding, composing, styling, theming, and debugging UI. Applies when working with darkraise-ui, the darkraise web template, theme axes, create-darkraise-ui, or any project with darkraise-ui in its package.json. Also triggers for "darkraise theme", "theme.config.ts", and "UiLabelsProvider".
user-invocable: true
---

# darkraise-ui

A React 19 UI kit with themed components, hooks, a seventeen-axis theme system, and layout variants. Every primitive is implemented in-house — there is no Radix UI underneath — and components are styled with Tailwind CSS 4.

**These rules were written against `darkraise-ui` 6.5.0.** The probe below prints what is actually installed. **When the installed version differs from 6.5.0, the package's own type definitions win over anything written in this skill.**
````

- [ ] **Step 3: Write the project-context probe block**

Append exactly this section:

````markdown
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
````

- [ ] **Step 4: Write the read-the-types contract**

Append exactly this section:

````markdown
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
````

- [ ] **Step 5: Write the workflow and quick reference**

Append a `## Workflow` section with these numbered steps: read the injected context; check which components are already available; read the relevant `.d.ts`; write the code; verify it against the Critical Rules.

Then append a `## Quick Reference` section containing:

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

- [ ] **Step 6: Verify**

```bash
grep -q 'dist/components' plugins/dcc-darkraise-ui/skills/darkraise-ui/SKILL.md && echo PASS || echo FAIL
grep -c '^!\`\|^```$' plugins/dcc-darkraise-ui/skills/darkraise-ui/SKILL.md
claude plugin validate .
```

Expected: `PASS`, and validation succeeds.

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-darkraise-ui/skills
git commit -m "feat(darkraise-ui): add skill probes and type contract"
```

---

### Task 3: SKILL.md body — principles, rules index, key patterns, selection table

**Files:**
- Modify: `plugins/dcc-darkraise-ui/skills/darkraise-ui/SKILL.md`

**Interfaces:**
- Consumes: the `SKILL.md` created in Task 2.
- Produces: the Critical Rules index, whose five relative links (`./rules/theming.md`, `./rules/styling.md`, `./rules/composition.md`, `./rules/forms.md`, `./rules/layout-data.md`) Tasks 4–8 must satisfy exactly.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

```bash
grep -q 'rules/theming.md' plugins/dcc-darkraise-ui/skills/darkraise-ui/SKILL.md && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Write the Principles section**

Insert a `## Principles` section after the version pin, with exactly these four numbered principles, each one sentence of explanation:

1. **Use the kit before writing custom UI.** Check the injected component list first.
2. **Compose, don't reinvent.** A settings page is Tabs + Card + form fields.
3. **Use built-in variants before custom styles.** `variant="outline"`, `size="sm"`.
4. **Use semantic tokens, never raw color values.** Every theme axis recomputes them; a raw Tailwind color opts out of the entire theme system.

- [ ] **Step 3: Write the Critical Rules index**

Append a `## Critical Rules` section. It has five subsections, each a `###` heading that links to its rule file, followed by that file's rules as one-line bullets:

```markdown
### Theming → [theming.md](./rules/theming.md)

- **Semantic tokens only.** `bg-background`, `text-muted-foreground`, `bg-card`, `border-border`, `bg-primary`. Never `bg-blue-500`.
- **Theme axes live in `theme.config.ts`.** All seventeen keys are required.
- **`accentVibrancy` no longer exists.** It was renamed `accentIntensity` in 6.1.0.

### Styling → [styling.md](./rules/styling.md)

- **Never `!important`, never Tailwind's `!` modifier.** The layer order already makes your utilities win.
- **State variants are independent.** `bg-red-500` overrides the resting state only; hover needs its own `hover:bg-red-600`.
- **`className` carries layout, not color or typography.**
- **Use `cn()` from `darkraise-ui/lib` for conditional classes.**
- **Tailwind 4 only.** There is no `tailwind.config.js`.

### Composition → [composition.md](./rules/composition.md)

- **No Radix.** Never install `@radix-ui/*`. Never assume `asChild` — check the `.d.ts`.
- **Subpath imports, not the barrel.**
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
```

- [ ] **Step 4: Write the Key Patterns block**

Append a `## Key Patterns` section: one `tsx` code block showing correct-vs-wrong pairs as inline comments, covering (a) a semantic token vs a raw color, (b) a subpath import vs a barrel import, (c) a `forms` field primitive vs a raw `div` + `Label` + `Input`, (d) `cn()` vs a template-literal ternary. Derive the exact component and prop names from `packages/ui/dist/`.

- [ ] **Step 5: Write the Component Selection table**

Append a `## Component Selection` section: a two-column "Need | Use" table. Populate it from the component list in `packages/ui/src/components/`. Cover at minimum: actions, form inputs, option sets, data display, navigation, overlays, feedback, command palette, charts, layout, empty states, menus, tooltips. Name only components that exist — verify each against `packages/ui/dist/components/`.

- [ ] **Step 6: Verify**

```bash
grep -q 'rules/theming.md' plugins/dcc-darkraise-ui/skills/darkraise-ui/SKILL.md && echo PASS || echo FAIL
grep -oE 'rules/[a-z-]+\.md' plugins/dcc-darkraise-ui/skills/darkraise-ui/SKILL.md | sort -u
```

Expected: `PASS`, then exactly five distinct paths: `rules/composition.md`, `rules/forms.md`, `rules/layout-data.md`, `rules/styling.md`, `rules/theming.md`.

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-darkraise-ui/skills
git commit -m "feat(darkraise-ui): add principles, rules index, patterns"
```

---

### Task 4: rules/theming.md

**Files:**
- Create: `plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/theming.md`

**Interfaces:**
- Consumes: the `### Theming` bullets from Task 3's Critical Rules index — this file must expand exactly those three bullets and no fewer.
- Produces: nothing later tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

```bash
test -f plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/theming.md && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Read the source of truth**

Read these before writing a word:
- `D:\Repositories\Personal\darkraise-web-template\apps\template\src\theme.config.ts` — the seventeen axes and their default values.
- `D:\Repositories\Personal\darkraise-web-template\packages\ui\dist\theme\index.d.ts` — `ThemeProvider`, `useTheme`, `ThemeSwitcher`, `ThemeSettingsPanel`, `generateTokens`, and the exported axis-value unions.
- `D:\Repositories\Personal\darkraise-web-template\packages\ui\src\styles\theme.css` — the semantic token names.

- [ ] **Step 3: Write the file**

Required sections, each with an Incorrect/Correct code pair:

1. **The seventeen axes.** A table: axis name, permitted values, default. All seventeen keys are required in `ThemeConfig.defaults`; omitting one is a type error.
2. **Semantic tokens, not raw colors.** Incorrect: `<div className="bg-slate-900 text-slate-100">`. Correct: `<div className="bg-card text-card-foreground">`. Explain that every axis recomputes these tokens at runtime, so a raw color silently opts out of the theme system.
3. **The 6.0→6.5 migration.** `accentVibrancy` was renamed `accentIntensity`; `surfaceIntensity` and `controlDepth` became required. Show a before/after `theme.config.ts`.
4. **Mounting and reading the theme.** `ThemeProvider config={themeConfig}` at the root; `useTheme()` to read; `ThemeSwitcher` and `ThemeSettingsPanel` as ready-made UI.
5. **Do not quote the package description.** Its axis count is stale; the axes are whatever `ThemeConfig` declares.

- [ ] **Step 4: Verify the axis list is complete and correct**

```bash
grep -cE '^\s+[a-zA-Z]+:' /d/Repositories/Personal/darkraise-web-template/apps/template/src/theme.config.ts
```

Cross-check every axis named in the file against `theme.config.ts`'s `defaults` block. Every one of the seventeen must appear; no invented axis may.

- [ ] **Step 5: Verify the file exists and validates**

```bash
test -f plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/theming.md && echo PASS || echo FAIL
claude plugin validate .
```

Expected: `PASS`, validation succeeds.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/theming.md
git commit -m "docs(darkraise-ui): add theming rules"
```

---

### Task 5: rules/styling.md

**Files:**
- Create: `plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/styling.md`

**Interfaces:**
- Consumes: the `### Styling` bullets from Task 3's Critical Rules index.
- Produces: nothing later tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

```bash
test -f plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/styling.md && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Read the source of truth**

- `D:\Repositories\Personal\darkraise-web-template\packages\ui\CONTRIBUTING.md` lines 60–80 — the override contract. **This is the only place it is documented, and it is not published to npm, so a consumer can never find it.**
- `D:\Repositories\Personal\darkraise-web-template\packages\ui\src\styles\theme.css` — confirm the `@layer` order declaration and locate the `@layer overrides` block.
- `D:\Repositories\Personal\darkraise-web-template\packages\ui\dist\lib\index.d.ts` — `cn` is re-exported from a chunk.

- [ ] **Step 3: Write the file**

Required sections, each with an Incorrect/Correct pair:

1. **The override contract.** Layer order is `theme, base, components, utilities, overrides`. Component CSS lives in `@layer components`; your utilities land in `@layer utilities` and therefore win **over component-class declarations**. State the qualifier explicitly: the package's own `@layer overrides`, where preset bindings live, outranks your utilities. Without the qualifier, a consumer utility losing to a preset reads as this skill being wrong.
2. **Never `!important`, never `!`.** Incorrect: `className="!bg-red-500"`. Correct: `className="bg-red-500"` — it already wins.
3. **State variants are independent.** Incorrect: `className="bg-red-500"` expecting hover to follow. Correct: `className="bg-red-500 hover:bg-red-600"`.
4. **`className` carries layout, not color or typography.** Incorrect: `<Button className="bg-purple-600 text-lg">`. Correct: `<Button variant="secondary" size="lg" className="w-full">`.
5. **`cn()` for conditional classes.** Incorrect: a template-literal ternary. Correct: `cn("dr-card", isActive && "ring-2")`, imported from `darkraise-ui/lib`.
6. **Tailwind 4 only.** `@import "darkraise-ui/styles.css"` plus `@theme` blocks in `globals.css`. There is no `tailwind.config.js` to edit.

- [ ] **Step 4: Verify**

```bash
test -f plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/styling.md && echo PASS || echo FAIL
grep -c 'Incorrect' plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/styling.md
```

Expected: `PASS`, and at least 6 Incorrect blocks.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/styling.md
git commit -m "docs(darkraise-ui): add styling and layer rules"
```

---

### Task 6: rules/composition.md

**Files:**
- Create: `plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/composition.md`

**Interfaces:**
- Consumes: the `### Composition` bullets from Task 3's Critical Rules index.
- Produces: nothing later tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

```bash
test -f plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/composition.md && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Confirm the no-Radix claim before asserting it**

```bash
grep -riE '"@radix-ui' /d/Repositories/Personal/darkraise-web-template/packages/ui/package.json
```

Expected: no matches. Also read `packages/ui/dist/components/button.d.ts` and confirm `asChild` is on `ButtonProps`, then spot-check two other components and confirm it is absent — that asymmetry is the point of the rule.

- [ ] **Step 3: Write the file**

Required sections, each with an Incorrect/Correct pair:

1. **No Radix.** Every primitive is in-house. Incorrect: `import * as Dialog from "@radix-ui/react-dialog"`. Correct: `import { Dialog, DialogContent, DialogTitle } from "darkraise-ui/components/dialog"`. Never assume `asChild` — `Button` has it, other components may not, and the `.d.ts` settles it.
2. **Subpath imports over the barrel.** Incorrect: `import { Button, Card } from "darkraise-ui"`. Correct: two subpath imports. Reason: bundle size.
3. **Items inside their group.** Show the correct nesting for a `Select` and a `DropdownMenu`, taken from their `.d.ts` export lists.
4. **Overlays need a title.** `Dialog`, `Sheet`, and `Drawer` each require their `*Title` for accessibility; use `className="sr-only"` when it should not be visible.
5. **Full `Card` composition.** Incorrect: everything inside `CardContent`. Correct: `CardHeader` / `CardTitle` / `CardDescription` / `CardContent` / `CardFooter`.
6. **Use the kit's components, not styled divs.** A table mapping intent to component: callout → `Alert`; page-level notice → `Banner`; empty state → `EmptyState`; loading placeholder → `Skeleton`; rule → `Separator`; status pill → `Badge`; toast → `sonner`.
7. **Never hardcode English inside a kit component.** Incorrect: forking a component to change its text. Correct: mount `UiLabelsProvider` and override the keys you need. Note that interpolated labels are functions, so a language that orders operands differently expresses that in its own function body.
8. **Reach for a kit hook before writing one.** Point at `dist/hooks/index.d.ts` and name `useDialog`, `useCombobox`, `useDisclosure`-style hooks that actually appear there — verify each name before writing it.

- [ ] **Step 4: Verify**

```bash
test -f plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/composition.md && echo PASS || echo FAIL
```

For every component name written in the file, confirm a matching file exists:

```bash
ls /d/Repositories/Personal/darkraise-web-template/packages/ui/dist/components/
```

Expected: `PASS`, and no invented component names.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/composition.md
git commit -m "docs(darkraise-ui): add composition rules"
```

---

### Task 7: rules/forms.md

**Files:**
- Create: `plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/forms.md`

**Interfaces:**
- Consumes: the `### Forms` bullets from Task 3's Critical Rules index.
- Produces: nothing later tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

```bash
test -f plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/forms.md && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Read the source of truth**

- `packages/ui/dist/forms/index.d.ts` — the seven field primitives plus `FieldWrapper`, `FormSection`, `FormActions`, and the shared `FieldPrimitiveProps<T>` shape.
- `packages/ui/dist/components/field.d.ts` — `Field`, `FieldGroup`, `FieldLabel`, `FieldDescription`, `FieldError`, `FieldSet`, `FieldLegend`.

Note the split: the field *primitives* live in `darkraise-ui/forms`; the `Field` *building blocks* live in `darkraise-ui/components/field`.

- [ ] **Step 3: Write the file**

Required sections, each with an Incorrect/Correct pair:

1. **Use the field primitives.** Table of the seven — `TextField`, `TextareaField`, `NumberField`, `SelectField`, `CheckboxField`, `SwitchField`, `RadioGroupField` — with the value type each carries. Incorrect: `<div><Label/><Input/><p className="text-red-500"/></div>`. Correct: `<TextField name="email" label="Email" value={v} onChange={setV} isInvalid errors={["Invalid email."]} />`.
2. **Validation is `isInvalid` + `errors`.** Never hand-rolled error markup, never a raw `text-red-500` paragraph.
3. **Grouping.** `FormSection` for a titled group of fields; `FormActions` for the submit/cancel pair with its pending state — show `isSubmitting` and `canSubmit`.
4. **When to drop to raw `Field`.** Only for a control the kit does not cover. Show `FieldWrapper` as the bridge that keeps label, description, and error wiring correct around a custom control.
5. **Import from the right place.** Incorrect: importing `TextField` from `darkraise-ui/components/field`. Correct: `import { TextField } from "darkraise-ui/forms"`.

- [ ] **Step 4: Verify every named export exists**

```bash
grep -oE '\b(TextField|TextareaField|NumberField|SelectField|CheckboxField|SwitchField|RadioGroupField|FieldWrapper|FormSection|FormActions)\b' /d/Repositories/Personal/darkraise-web-template/packages/ui/dist/forms/index.d.ts | sort -u
```

Expected: all ten names present. Any name in the rule file that is absent here is a bug — fix the rule file.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/forms.md
git commit -m "docs(darkraise-ui): add forms rules"
```

---

### Task 8: rules/layout-data.md

**Files:**
- Create: `plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/layout-data.md`

**Interfaces:**
- Consumes: the `### Layout & Data` bullets from Task 3's Critical Rules index.
- Produces: nothing later tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

```bash
test -f plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/layout-data.md && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Read the source of truth**

- `packages/ui/dist/layout/index.d.ts` — `SidebarLayout`, `SidebarNav`, `NavItem`, `NavGroup`, `PageHeader`, `UserMenu`, `SearchCommand`, `NotificationBell`.
- `packages/ui/dist/data-table/index.d.ts` — `DataTable`, `ColumnHeader`, `RowActions`, `DataTableSkeleton`, `DataTableEmpty`, `DataTableFacet`, `exportToCsv`.
- `packages/ui/dist/router/index.d.ts` — `RouterAdapter`, `RouterAdapterProvider`, `useRouterAdapter`.
- `apps/template/src/providers/app-providers.tsx` — the exact provider order.

- [ ] **Step 3: Write the file**

Required sections, each with an Incorrect/Correct pair:

1. **Use `SidebarLayout`.** Incorrect: a hand-built flex shell with a nav `<ul>`. Correct: `SidebarLayout` fed a `NavGroup[]`, with `PageHeader` supplying breadcrumbs, title, description, actions, and tabs.
2. **The kit is router-agnostic by construction.** No component imports a router. Mount `RouterAdapterProvider value={adapter}`; show the adapter shape from `RouterAdapter`.
3. **Use `DataTable`.** Incorrect: a hand-built `<table>` with manual sorting. Correct: `DataTable` with `columns`, `data`, `searchKey`, `facets`, and `virtualize`; `ColumnHeader` for sortable headers; `RowActions` for the row menu; `DataTableSkeleton` while loading; `DataTableEmpty` when empty.
4. **The provider stack order is load-bearing.** Give it verbatim, outermost first: `QueryClientProvider` → `ThemeProvider` → `RouterAdapterProvider` → `FloatingPanelProvider` → children → `FloatingPanelHost` → `Toaster`. State that a wrong order fails subtly rather than loudly.
5. **Error pages come from the kit.** `NotFoundPage`, `ErrorPage`, `ServerErrorPage`, `MaintenancePage`, `ErrorLayout` from `darkraise-ui/errors`, wired into the router's defaults.

- [ ] **Step 4: Verify the provider order matches the template exactly**

```bash
grep -nE 'Provider|Toaster|FloatingPanelHost' /d/Repositories/Personal/darkraise-web-template/apps/template/src/providers/app-providers.tsx
```

The order in the rule file must match this output. Any divergence is a bug in the rule file.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-darkraise-ui/skills/darkraise-ui/rules/layout-data.md
git commit -m "docs(darkraise-ui): add layout and data rules"
```

---

### Task 9: Eval suite

**Files:**
- Create: `plugins/dcc-darkraise-ui/evals/<case-name>/` (one directory per case)

**Interfaces:**
- Consumes: the finished skill from Tasks 2–8; the eval measures its effect.
- Produces: nothing later tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Confirm the real eval contract before authoring anything**

```bash
claude plugin eval --help
```

Read the output. Confirm: cases live in `<eval dir>/**/case.yaml`, or `prompt.md` plus `graders/*.md`; the eval dir defaults to `evals/`; `--ablation with-without` runs a no-plugin baseline arm and reports a score delta.

**Do not copy shadcn's `evals/evals.json`.** That belongs to a different harness and this command will never read it.

- [ ] **Step 2: Scaffold the suite through the built-in author flow**

```bash
cd plugins/dcc-darkraise-ui
claude plugin eval init --bare no-radix-import
```

Use `claude plugin eval init` (the interview) or `--bare <name>` per case. Let the command establish the file shape rather than hand-writing a schema.

- [ ] **Step 3: Author four cases**

| Case | Prompt asks for | Grader checks |
| --- | --- | --- |
| `no-radix-import` | a modal dialog | output does not contain `@radix-ui` (negative pattern grader) |
| `semantic-tokens` | a themed status card | no raw Tailwind color classes; uses `bg-card` / `text-muted-foreground` (LLM grader) |
| `form-primitives` | a settings form with a validated email field | uses `TextField` from `darkraise-ui/forms` with `isInvalid`/`errors`, not a raw `div` + `Label` + `Input` (LLM grader) |
| `subpath-imports` | a page using Button and Card | imports from `darkraise-ui/components/*`, not the barrel (pattern grader) |

- [ ] **Step 4: Run the suite with a baseline arm**

```bash
cd plugins/dcc-darkraise-ui
claude plugin eval --ablation with-without --runs 1 --max-cost-usd 5
```

Expected: each case scores higher with the plugin than without. A case with a zero delta is not measuring the skill — rewrite its prompt so the un-skilled baseline actually fails it.

**If the command reports the feature is not enabled for this account, stop and record that in the commit message.** The suite still lands; it simply cannot be run here.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-darkraise-ui/evals
git commit -m "test(darkraise-ui): add eval suite with baseline arm"
```

---

### Task 10: Final validation and release

**Files:**
- Modify: `plugins/dcc-darkraise-ui/README.md` (usage examples, if anything learned in Tasks 4–9 changes them)

**Interfaces:**
- Consumes: everything from Tasks 1–9.
- Produces: the releasable plugin.

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Validate the marketplace**

```bash
claude plugin validate .
```

Expected: success, no errors.

- [ ] **Step 2: Confirm every rules link resolves**

```bash
cd plugins/dcc-darkraise-ui/skills/darkraise-ui
for f in $(grep -oE 'rules/[a-z-]+\.md' SKILL.md | sort -u); do test -f "$f" && echo "OK $f" || echo "MISSING $f"; done
```

Expected: five `OK` lines, no `MISSING`.

- [ ] **Step 3: Confirm no chunk hash leaked into the prose**

```bash
grep -rnE '\-[A-Za-z0-9_]{8}\.(js|d\.ts)' plugins/dcc-darkraise-ui/skills/ && echo LEAK || echo CLEAN
```

Expected: `CLEAN`. A hit means a build-specific chunk filename was written into the skill and must be removed.

- [ ] **Step 4: Confirm no stale counts were copied from the package description**

```bash
grep -rnE '65 themed|38 hooks|6-axis' plugins/dcc-darkraise-ui/ && echo STALE || echo CLEAN
```

Expected: `CLEAN`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-darkraise-ui
git commit -m "chore(darkraise-ui): release 0.1.0"
```
