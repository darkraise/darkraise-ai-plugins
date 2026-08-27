# Darkraise framework skills — design

Two Claude Code plugins, each holding one skill, that teach Claude to write correct
code against a Darkraise house framework: `darkraise-ui` (React web) and
`Darkraise.Win32UI` (Win32/Direct2D desktop). Both are modelled on the shadcn/ui
skill at `D:\Repositories\Community\shadcn-ui\skills\shadcn`.

## Problem

Both frameworks are large, opinionated, and unlike their nearest public
equivalents. `darkraise-ui` looks like shadcn/ui but implements every primitive
in-house, carries a seventeen-axis theme system, and enforces a CSS layer
contract. `Darkraise.Win32UI` looks like WPF but is neither WPF nor WinForms, and
its design system carries load-bearing rules — the raise ladder, the overlay-hover
step, the single current-item marker — that no amount of general knowledge will
supply.

Without a skill, Claude writes plausible code that violates these rules: raw
Tailwind colors that fight the theme axes, `@radix-ui` imports that do not exist,
hand-rolled form markup where field primitives exist, hardcoded color literals in
Win32 controls, invented navigation markers.

## Goals

- Claude writes framework-idiomatic code on the first attempt in a project that
  uses either framework.
- The skills stay correct as the frameworks move, without a maintenance ritual.
- Each skill is useful in a plain consumer project — one that has only the npm or
  NuGet package, not the framework source repository.

## Non-goals

- Documenting every component's props by hand. The package artifacts already carry
  that, exactly and always current.
- Teaching React or C#. The skills teach these frameworks' opinions only.
- A shared abstraction between the two skills. They mirror each other in shape;
  they share no content and no code.

## Architecture

Two plugins, mirrored in structure so that learning one teaches the other.

```
plugins/dcc-darkraise-ui/
  .claude-plugin/plugin.json
  README.md
  skills/darkraise-ui/
    SKILL.md
    rules/theming.md
    rules/styling.md
    rules/composition.md
    rules/forms.md
    rules/layout-data.md
    evals/evals.json

plugins/dcc-darkraise-win32ui/
  .claude-plugin/plugin.json
  README.md
  skills/darkraise-win32ui/
    SKILL.md
    rules/tokens.md
    rules/builder.md
    rules/layout.md
    rules/mvvm-draml.md
    rules/limitations.md
    evals/evals.json
```

Each plugin gets an entry in `.claude-plugin/marketplace.json`. Plugin names carry
the repository's mandatory `dcc-` prefix; skill names do not, following the
precedent of `dcc-superpower-companions`, whose skills are named for what they do.

Both skills are user-invocable, so `/darkraise-ui` and `/darkraise-win32ui` force
them, and both carry a description that auto-triggers on the framework being
present. This differs deliberately from shadcn, which sets `user-invocable: false`.

## Live project context

The shadcn skill injects `!npx shadcn@latest info --json` into its SKILL.md and
reads the project's configuration from the result. Neither Darkraise framework has
an equivalent CLI, so each skill injects a cheap shell probe instead and then
instructs Claude to read the package's own type or documentation artifacts for
exact API detail.

This is the central design decision. The skill carries the *opinionated* knowledge
— rules, selection guidance, composition patterns — and never the *mechanical*
knowledge, which the package already carries in a form that cannot go stale.

### darkraise-ui

The npm package publishes `dist` and `README.md` only. `dist/components/` holds 94
`.d.ts` files, one per component, each small and exact. `button.d.ts` is thirteen
lines and gives the complete variant union, size union, and props interface.

SKILL.md injects:

```
!`cat node_modules/darkraise-ui/package.json | grep '"version"'`
!`ls node_modules/darkraise-ui/dist/components/*.d.ts`
```

The first line establishes the installed version. The second establishes which
components exist in that version — a live catalog that no hand-written list can
match.

The standing instruction is: **before using, creating, fixing, or debugging any
component, read `node_modules/darkraise-ui/dist/components/<kebab-name>.d.ts`.**
Subpath entry points (`theme`, `forms`, `layout`, `data-table`, `router`, `errors`,
`labels`, `lib`) each have their own `dist/<name>/index.d.ts`, read the same way.

If `node_modules` is absent — a fresh clone before install — the probes emit
nothing, and the skill instructs Claude to say so and offer to install rather than
guess.

### Darkraise.Win32UI

The NuGet package sets `GenerateDocumentationFile`, so `Darkraise.Win32UI.xml`
ships alongside the assembly at:

```
~/.nuget/packages/darkraise.win32ui/<version>/lib/net10.0-windows/Darkraise.Win32UI.xml
```

The XML doc file is verbose, so the skill does not instruct reading it whole. It
instructs a targeted grep for the member prefix of the type in question — for
example `<member name="M:Darkraise.Win32UI.Builder.ButtonBuilder.` to enumerate a
builder's fluent methods.

When the framework is project-referenced rather than package-referenced (the
`darkraise-framework` repository itself, and any solution that includes it), the
skill prefers the source tree at `src/Darkraise.Win32UI/`, which is richer than the
XML docs.

SKILL.md injects a probe that resolves which of the two situations holds:

```
!`grep -rhoE 'Darkraise\.Win32UI[^"<]*' --include=*.csproj . | sort -u`
```

## Version drift

Both frameworks move quickly. `darkraise-ui` went from 6.0.0 to 6.5.0 in roughly a
month, renaming the theme axis `accentVibrancy` to `accentIntensity` and making
`surfaceIntensity` and `controlDepth` required keys — a breaking change to every
consumer's `theme.config.ts`.

Each SKILL.md therefore states, near the top, the exact version its prose was
written against. The injected probe prints the installed version. The standing
instruction is: **when the installed version differs from the pinned version, the
package's own type definitions or XML docs win over anything written in this
skill.**

This costs nothing to maintain and degrades safely — a stale rule is flagged as
possibly stale rather than read as authoritative.

## darkraise-ui skill content

### SKILL.md

Frontmatter (`name`, `description`, `user-invocable: true`), the version pin, the
injected project context, then:

**Principles** — four, in shadcn's style: use the kit before writing custom UI;
compose rather than reinvent; use built-in variants before custom styles; use
semantic tokens, never raw color values.

**Critical Rules** — each a one-line statement linking to the rule file that holds
its Incorrect/Correct pair.

**Key Patterns** — a single code block showing the handful of shapes that most
distinguish correct darkraise-ui code from plausible-looking wrong code.

**Component Selection** — a "need → use" table. Hand-written, because it encodes
judgement; the live probe supplies which of them exist.

**Workflow** — get context, check what is installed, read the `.d.ts`, write, then
verify against the Critical Rules.

**Quick Reference** — `create-darkraise-ui` scaffolding, `pnpm add darkraise-ui`,
the subpath import forms, the provider stack.

Scaffolding coverage is deliberately brief: `create-darkraise-ui` plus the provider
stack and `globals.css` shape. The weight goes to daily component work.

### rules/theming.md

The seventeen theme axes and their permitted values, sourced from `ThemeConfig`.
The rule that every visual choice routes through a semantic token — `bg-background`,
`text-muted-foreground`, `bg-card`, `border-border`, `bg-primary` — because each
axis recomputes those tokens at runtime, and a raw Tailwind color silently opts out
of the entire theme system. The 6.0→6.5 rename and the two newly-required keys. The
`ThemeProvider` / `useTheme` / `ThemeSwitcher` / `ThemeSettingsPanel` surface.

### rules/styling.md

The override contract, which is the single most consequential styling rule and is
documented only in the package's `CONTRIBUTING.md`, which consumers never see:
component CSS lives in `@layer components`, consumer utilities land in
`@layer utilities`, and the layer order in `theme.css` (`theme, base, components,
utilities, overrides`) means consumer utilities always win. Therefore `!important`
and Tailwind's `!` modifier are never needed and are forbidden.

State variants are independent. Passing `bg-red-500` overrides the resting state
only; the hover state needs its own `hover:bg-red-600`. This surprises everyone
once.

Also: `cn()` from `darkraise-ui/lib` for conditional classes; `className` carries
layout, not color or typography; Tailwind 4 only, with `@import
"darkraise-ui/styles.css"` and `@theme` blocks and no `tailwind.config.js`.

### rules/composition.md

No Radix. Every primitive is implemented in-house, so `@radix-ui/*` must never be
installed, and `asChild` must not be assumed — `Button` has it, other components
may not, and the `.d.ts` settles it.

Subpath imports over the barrel: `darkraise-ui/components/<kebab-name>` rather than
`darkraise-ui`, to keep bundles small.

Items inside their group. Dialog, Sheet, and Drawer always carry a title. Full Card
composition rather than everything dumped in `CardContent`. Use `EmptyState`,
`Banner`, `Alert`, `Skeleton`, `Separator`, `Badge` rather than styled divs.

Text is never hardcoded inside a kit component. Overrides go through
`UiLabelsProvider`, whose interpolated labels are functions so that a language with
different operand order can express it.

### rules/forms.md

`darkraise-ui/forms` supplies field primitives — `TextField`, `TextareaField`,
`NumberField`, `SelectField`, `CheckboxField`, `SwitchField`, `RadioGroupField` —
each of which already wraps `Field` with the correct label, description, and error
wiring. Use them. Drop to raw `Field` / `FieldGroup` / `FieldWrapper` only for a
control the kit does not cover.

Validation is `isInvalid` plus `errors`, not hand-rolled error markup. `FormSection`
groups related fields; `FormActions` renders the submit/cancel pair with its
pending state.

### rules/layout-data.md

`SidebarLayout` with `NavGroup` / `NavItem`, plus `PageHeader` for breadcrumbs,
title, description, actions, and tabs — rather than a hand-built app shell.
`UserMenu`, `SearchCommand`, `NotificationBell` are layout-provided.

The kit is router-agnostic by construction: no component imports a router. Mount
`RouterAdapterProvider` with an adapter (the template supplies a TanStack Router
one) and the kit's links work.

`DataTable` with `ColumnHeader`, `RowActions`, `DataTableSkeleton`,
`DataTableEmpty`, `DataTableFacet`, and `exportToCsv`, including the virtualization
option, rather than a hand-built table.

The provider stack, in order, from the template's `app-providers.tsx`:
`QueryClientProvider` → `ThemeProvider` → `RouterAdapterProvider` →
`FloatingPanelProvider` → children → `FloatingPanelHost` → `Toaster`. Wrong order
fails subtly rather than loudly.

## Darkraise.Win32UI skill content

### SKILL.md

Same shape as the web skill: frontmatter, version pin, injected context,
principles, critical rules linking to rule files, key patterns, a control-selection
table, workflow, quick reference.

The control-selection table is organised by the sixteen design-spec categories that
already exist in `docs/win32ui/design/` — actions, text input, date and time,
selection, range and pickers, status, feedback, overlays, modals, window and shell,
containers, navigation, data, code, media and motion, layout — because that
taxonomy is the framework's own and Claude choosing within it will choose well.

Scaffolding coverage: `DarkraiseApplication`, `ConfigureServices`, `Configure`, the
`[RootViewModel]` entry point, and the `net10.0-windows` requirement. Brief.

### rules/tokens.md

Colors, font families, radii, padding, gaps, and font sizes resolve from `Tokens.*`
values or a named design-system token. Never a literal. The framework enforces this
on its own `Controls/**` and `Builder/**` through the DRUI020 analyzer; custom
controls in a consumer project follow the same rule for the same reason — a literal
does not re-theme.

The raise ladder: the nine surface roles from `SurfaceSunken` through
`SurfaceOverlay` and the three component-internal steps, with what each is for.
The overlay-hover rule, which is load-bearing and easy to get wrong: a hover fill
must be at least one *visible* step above its host surface, so on a `SurfaceOverlay`
host — menus, dropdown lists — that means `Surface3`, because `Surface2` is nearly
identical to the overlay surface in dark mode and reads as no feedback at all.

Foreground tokens and the contrast rule: anything meant to be seen uses a
`Foreground*` token, never a `Border*` or `Surface*` color.

Borders: all structural borders are 1px. The only thicker strokes are the 2px
active-tab underline and the 3px focus halo.

Hairlines define structure; shadows define float. Shadows are reserved for things
that genuinely float — popovers, menus, dialogs, drawers, toasts — and for cards.
Nothing else casts a shadow.

One accent, four meanings, no leakage. The accent means interactive or current.
Red, amber, green, and blue mean destructive, warning, success, and info, and are
never decorative.

The current-item marker: one rule answers "you are here" everywhere, always
carrying at least two signals so it never rides on color alone, expressed in each
surface's own idiom, and never as a bar that travels between siblings. Controls
must not invent alternatives.

Motion is causality: animation confirms that an action caused a result. No ambient
or looping motion outside explicit progress indicators.

### rules/builder.md

Composition through the static `View` factory — 107 entry points covering controls,
containers, and layout. The fluent chain: `.Bind(vm, x => x.Property)` for one-way
and two-way binding, `.OnClick(vm.Method)` for commands, and the styling verbs
(`.FontSize()`, `.Bold()`, `.Muted()`, `.Padding()`).

How to discover a builder's methods rather than guess them: grep the XML doc file
for that builder's member prefix, or read `src/Darkraise.Win32UI/Builder/<Name>Builder.cs`
when the source is available.

The three `View` factories that return builders rather than controls, which is a
sanctioned inconsistency documented in the framework's known limitations and will
otherwise look like a bug.

### rules/layout.md

The layout and render contract: how a control decides its box, overflow and
clipping, text overflow, scroll as the only legitimate escape valve for real
overflow, how a container distributes space among children, horizontal and vertical
content alignment, constraints and responsive reflow, and when a change triggers
relayout versus repaint.

The layout primitives and when each applies: `Stack`, `Inline`, `Center`, `Box`,
`Border`, `Grid`, `GridPanel`, `DockPanel`, `WrapPanel`, `UniformGrid`, `Spacer`.
Only `Box` and `Border` paint; everything else is invisible skeleton that owns
spacing and structure.

The spacing scale, and the rule that density never comes from shrinking type below
the scale or removing padding below the tokens.

### rules/mvvm-draml.md

Convention-based MVVM: `FooViewModel` resolves to `FooView`. Screens derive from
`DarkraiseScreen` and raise change notifications through `Set(ref _field, value)`.
`[RootViewModel]` marks the entry point that `Run()` resolves after scanning the
configured assemblies. The view model lifecycle hooks, dependency injection, and
dialog access.

Markup views: `.drui` and `.draml` files handed to the compiler as
`AdditionalFiles`, compiled by `Darkraise.Win32UI.Generators` into control trees at
build time, so a renamed or mistyped binding is a compile error rather than a
silent runtime no-op. `DruiSchema.xsd` ships in the package for editor validation.
`.draml` can alternatively be loaded at runtime with `DramlView.LoadFile`, in which
case the files are `Content`, not `AdditionalFiles`.

The DRUI001 through DRUI014 diagnostic table, so a build error is diagnosable from
the skill alone without a web search.

### rules/limitations.md

What the framework cannot do, so Claude does not promise it: no UI Automation or
screen-reader support; IME and CJK input caveats; x64 and ARM64 only; a Windows
version floor; localization constraints; DPI behaviour; collection virtualization
boundaries; window sizing clamped to the monitor work area; GDI+ image formats
only; animated GIFs rendering their first frame only; `MenuPopup` rendering its
whole item list.

This file exists because the most damaging failure mode is not wrong code — it is
Claude confidently designing a feature the framework does not support.

## Rule file format

Every rule file follows the shadcn pattern that carries the most weight: a short
statement of the rule, then an **Incorrect** code block and a **Correct** code
block showing the same intent. Prose without a code pair does not change behaviour;
a code pair does.

## Testing

Manifest validation, per the repository convention:

```
claude plugin validate .
```

CI already runs this on every push to `main` and every pull request.

Behavioural verification through an eval suite per skill, in shadcn's style, at
`skills/<name>/evals/evals.json`. Each eval is a prompt plus assertions about the
code Claude produces. Coverage targets the rules most likely to be violated:

- **darkraise-ui** — a settings page must use subpath imports, semantic tokens, and
  `forms` field primitives rather than raw divs; a themed component must not carry a
  raw Tailwind color; a form must not hand-roll error markup; no `@radix-ui` import
  may appear.
- **Win32UI** — a custom control must resolve colors from `Tokens.*`; a dropdown's
  hover state must use `Surface3` on an overlay host; a navigation surface must use
  the standard current-item marker; a layout must use the layout primitives rather
  than manual coordinates.

Evals run through `claude plugin eval`.

## Risks

**The rules go stale.** Mitigated by the version pin plus runtime verification: the
skill states what it was written against, the probe states what is installed, and
the package artifacts win on disagreement.

**The probe fails on an unusual project layout.** A monorepo may hoist
`node_modules` above the working directory. The skill treats an empty probe as
"unknown, ask or search" rather than "not installed".

**Two skills drift apart in shape.** Mitigated by writing them against the same
outline in the same pass, and by the mirrored directory structure making a
divergence visible.
