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
  evals/<case-name>/case.yaml

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
  evals/<case-name>/case.yaml
```

Each plugin gets an entry in `.claude-plugin/marketplace.json`. Plugin names carry
the repository's mandatory `dcc-` prefix; skill names do not, following the
precedent of `dcc-superpower-companions`, whose skills are named for what they do.

Both skills are user-invocable, so they can be forced rather than waiting on
description matching, and both carry a description that auto-triggers on the
framework being present. This differs deliberately from shadcn, which sets
`user-invocable: false`. The guaranteed invocation form is the qualified one —
`/dcc-darkraise-ui:darkraise-ui` and `/dcc-darkraise-win32ui:darkraise-win32ui`;
the bare `/darkraise-ui` works only while no other installed plugin claims that
skill name. Each README states the qualified form.

Note that `!`-backtick command injection in a skill body is a real, documented
Claude Code feature and works on Windows through Git Bash, but a permission
policy can disable it. Each README says so, because a disabled probe degrades
the skill to its prose without any visible error.

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
Subpath entry points (`theme`, `hooks`, `forms`, `layout`, `data-table`, `router`,
`errors`, `labels`, `lib`) each have their own `dist/<name>/index.d.ts`, read the
same way.

Some component typings re-export their principal symbols from a shared chunk file
rather than declaring them inline — `calendar.d.ts` declares its hook types
locally but pulls `Calendar` and `CalendarProps` from `../Calendar-CWyF6DAE.js`,
and `dist/lib/index.d.ts` gets `cn` the same way. The instruction therefore
carries a follow-through step: if the symbol you need is re-exported, read the
chunk `.d.ts` the import names. Those chunk filenames carry a content hash that
changes on every build, so the skill must never cite one in its prose.

If `node_modules` is absent — a fresh clone before install — `cat` writes "No such
file or directory", which the skill treats as a clear "not installed" signal:
say so and offer to install, never guess. In a workspace that hoists differently,
`pnpm why darkraise-ui` resolves the real location. Note that the tempting
`node -p "require('darkraise-ui/package.json').version"` does not work here — the
package's `exports` map does not expose `./package.json` — so `cat` is the correct
probe.

### Darkraise.Win32UI

The NuGet package sets `GenerateDocumentationFile`, so an XML doc file ships
alongside each assembly in the package cache. **Two** files matter, not one:

```
~/.nuget/packages/darkraise.win32ui/<version>/lib/net10.0-windows/Darkraise.Win32UI.xml
~/.nuget/packages/darkraise/<version>/lib/<tfm>/Darkraise.xml
```

The second is load-bearing and easy to miss: the MVVM surface the skill teaches —
`DarkraiseScreen`, `Set(ref …)`, `[RootViewModel]`, the conductors — lives in the
**Darkraise core assembly**, at `src/Darkraise/Mvvm/`, not in Darkraise.Win32UI.
A skill that names only the Win32UI XML file sends every MVVM lookup to a file
that does not contain the answer.

The XML doc files are verbose, so the skill does not instruct reading one whole.
It instructs a targeted grep for the member prefix of the type in question — for
example `<member name="M:Darkraise.Win32UI.Builder.ButtonBuilder.` to enumerate a
builder's own fluent methods. That prefix alone is insufficient, and the rule file
must say so: builders derive from `ViewBuilder<TControl,TBuilder>`, so the
inherited half of the fluent surface — `Padding`, `Margin`, `Width`, `Height`,
`Visible`, `Enabled`, `Name`, and the generic `Bind` — sits under the mangled
generic-arity prefix ``M:Darkraise.Win32UI.Builder.ViewBuilder`2.``. Grepping only
the concrete builder reports `ButtonBuilder` as having eight methods, which is
wrong in a way that looks right.

When the framework is project-referenced rather than package-referenced (the
`darkraise-framework` repository itself, and any solution that includes it), the
skill prefers the source tree at `src/Darkraise.Win32UI/` and `src/Darkraise/`,
which is richer than the XML docs.

SKILL.md injects two probes. The first resolves which situation holds and, unlike
a naive attribute-value grep, captures the whole reference element so the
`Version` attribute survives — the XML doc path depends on knowing the version:

```
!`grep -rh --include=*.csproj --include=Directory.Packages.props -oE '<(Package|Project)Reference[^>]*Darkraise[^>]*' . | sort -u`
```

The second enumerates what is actually in the cache, which also covers central
package management, where the csproj carries no version at all:

```
!`ls ~/.nuget/packages/darkraise.win32ui/ ~/.nuget/packages/darkraise/ 2>/dev/null`
```

## Version drift

Both frameworks move quickly, but they drift in opposite directions, and the skills
must handle both cases.

**darkraise-ui drifts ahead of the skill.** It went from 6.0.0 to 6.5.0 in twelve
days (2026-08-14 to 2026-08-26), renaming the theme axis `accentVibrancy` to
`accentIntensity` and making `surfaceIntensity` and `controlDepth` required keys —
a breaking change to every consumer's `theme.config.ts`. A consumer's installed
package is therefore likely *newer* than the skill's prose.

**Darkraise.Win32UI drifts behind it.** The published package lags the source
repository substantially — at the time of writing, the last tag is two weeks and
several hundred commits behind `main`, and packages publish to an
authentication-required feed. The skill's prose is written from
`docs/win32ui/`, which tracks the source. So a consumer's installed package is
likely *older* than the skill's prose, and the failure mode is the reverse of the
web one: the skill describes controls and methods the consumer's package does not
have yet.

Each SKILL.md therefore states, near the top, the exact version its prose was
written against — for Win32UI, the framework docs revision rather than a package
version, since that is what the prose actually tracks. The injected probes print
what is installed. The standing instruction is: **when installed and pinned
disagree, the package's own type definitions or XML docs win over anything written
in this skill** — and for Win32UI specifically, an API described here but absent
from the installed package's XML docs means the consumer needs an upgrade, not a
workaround.

This costs nothing to maintain and degrades safely in both directions — a stale
rule is flagged as possibly stale rather than read as authoritative.

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
utilities, overrides`) means consumer utilities always win *over component-class
declarations*. Therefore `!important` and Tailwind's `!` modifier are never needed
and are forbidden.

The qualifier is not pedantry and must be stated: the package's own
`@layer overrides` — where preset bindings live — outranks consumer utilities. A
consumer utility fighting a preset will lose, and without the qualifier that reads
as the skill being wrong about the whole contract.

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
values or a named design-system token. Never a literal, because a literal does not
re-theme.

The rule file must be explicit about where enforcement exists. The DRUI020 analyzer
is scoped to the assembly named `Darkraise.Win32UI` and, within it, to `Controls/**`
and `Builder/**`; it returns early for any other compilation. **A consumer project
gets no analyzer backstop at all** — Claude is the only enforcement there. Stating
this prevents the opposite error of assuming a clean build means the rule was
followed.

The raise ladder: the six surface roles — `SurfaceSunken`, `SurfaceBase`,
`SurfaceSidebar`, `SurfaceHeader`, `SurfaceRaised`, `SurfaceOverlay` — plus the
three component-internal state steps `Surface1`, `Surface2`, `Surface3`, with what
each is for.
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

Composition through the static `View` factory — 106 entry points covering controls,
containers, and layout. The fluent chain: `.Bind(vm, x => x.Property)` for one-way
and two-way binding, `.OnClick(vm.Method)` for commands, and the styling verbs
(`.FontSize()`, `.Bold()`, `.Muted()`, `.Padding()`).

How to discover a builder's methods rather than guess them: grep the XML doc file
for that builder's member prefix *and* the `ViewBuilder`2.` base prefix, or read
`src/Darkraise.Win32UI/Builder/<Name>Builder.cs` together with `Builder/ViewBuilder.cs`
when the source is available.

Authoring a custom control, condensed from `docs/win32ui/extending-controls.md`:
the extension contract a control must satisfy — measure and arrange, paint through
the drawing context, resolve every visual from tokens, and participate in the
interaction-state contract. This is required because one of the eval cases asks for
a custom control, and without it the skill would be graded on knowledge it never
supplies.

Every `View` factory returns a builder, uniformly. The framework's known-limitations
§15 records that `View.ImageView()`, `View.Drawer()`, and `View.Sheet()` were the
last three returning bare controls and were changed in the 2026-07-27 parity sweep —
so this is a *historical source break*, not a live inconsistency. The rule file
states the current uniform behaviour and notes only that older sample code
constructing those three no longer compiles, and that reaching a control member or
assigning to a concretely-typed target needs `.Build()`. Describing three factories
as still differing would teach a falsehood.

`Border` has no `View.Border()` factory despite `Border` being one of the two
painting primitives; the layout rule file must say how it is actually reached
rather than leaving a reader to call a factory that does not exist.

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

These types live in the **Darkraise core assembly** (`src/Darkraise/Mvvm/`), not in
Darkraise.Win32UI. The rule file says so and routes API lookups to `Darkraise.xml`
rather than `Darkraise.Win32UI.xml`.

Multi-screen navigation, which is the first thing a real app needs and which a
single-screen rule file would leave uncovered: `AppShellViewModel` and
`OneActiveConductor<DarkraiseScreen>` for page hosting and activation.

Markup views: `.drui` and `.draml` files handed to the compiler as
`AdditionalFiles`, compiled by `Darkraise.Win32UI.Generators` into control trees at
build time, so a renamed or mistyped binding is a compile error rather than a
silent runtime no-op. `DruiSchema.xsd` ships in the generator package under `content/`, which a
`PackageReference` does not copy into the consuming project — editor validation
means pointing the editor at the package-cache path, and the rule file says so
rather than implying the file appears locally. `.draml` can alternatively be loaded
at runtime with `DramlView.LoadFile`, in which case the files are `Content`, not
`AdditionalFiles`.

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

### Manifest validation

Per the repository convention, and the hard gate in CI, which already runs it on
every push to `main` and every pull request:

```
claude plugin validate .
```

### Behavioural evaluation

Verified against `claude plugin eval --help` rather than copied from shadcn.
shadcn's `evals/evals.json` belongs to a different harness and this command would
never read it. The real contract is a directory of **cases** below the eval dir:

```
plugins/dcc-darkraise-ui/evals/
  <case-name>/case.yaml          # or prompt.md + graders/*.md
```

The eval dir defaults to `evals/`, overridable by `--eval-dir` or by the manifest's
`experimental.evals` value. Cases are authored through `claude plugin eval init`,
which runs an interview that sources inputs and designs graders — the correct
implementation path, rather than hand-writing a schema from a guess. `--bare <name>`
produces a blank single-case template.

The mechanism that makes these evals worth writing is `--ablation with-without`:
it runs a no-plugin baseline arm alongside the plugin arm and reports the **score
delta**. That is a direct measurement of whether the skill changed behaviour,
which is precisely the question a rule change raises and which no amount of reading
the rule file can answer. Graders marked with-only — including `tool_used: Skill` —
serve as a plugin-fired indicator rather than contributing to the score.

Coverage targets the rules most likely to be violated:

- **darkraise-ui** — a settings page must use subpath imports, semantic tokens, and
  `forms` field primitives rather than raw divs; a themed component must not carry a
  raw Tailwind color; a form must not hand-roll error markup; no `@radix-ui` import
  may appear. The last of these is a one-line negative pattern grader; the others
  need an LLM grader.
- **Win32UI** — a custom control must resolve colors from `Tokens.*`; a dropdown's
  hover state must use `Surface3` on an overlay host; a navigation surface must use
  the standard current-item marker; a layout must use the layout primitives rather
  than manual coordinates.

Two operational constraints belong in the spec because they shape what CI can
assume. Eval runs invoke real models and therefore cost money — `--max-cost-usd`
bounds a run and `--runs` controls repetition — and the command may be gated
depending on account enablement. **CI keeps `claude plugin validate .` as the hard
gate; eval runs stay a local, deliberate step.** `--threshold` is available for
gating a run once that is desirable.

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

**Stale counts leak in from the package metadata.** `packages/ui/package.json`
advertises "65 themed components, 38 hooks, 6-axis theming" — all three are wrong
against the current source. No skill text quotes that description; counts come from
the live probe or from the source, or are omitted.
