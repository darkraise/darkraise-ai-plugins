# dcc-darkraise-win32ui Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Implementer assignments:** each task names its implementer agent in an
> `**Implementer:**` line. When executing with
> superpowers:subagent-driven-development, REQUIRED SUB-SKILL:
> dcc-superpower-companions:dispatching-tiered-implementers. Under
> superpowers:executing-plans these lines are inert; ignore them.

**Goal:** Ship a marketplace plugin whose single skill makes Claude write idiomatic `Darkraise.Win32UI` code — token-resolved visuals, the raise ladder, the builder API, convention MVVM — and stop it promising capabilities the framework does not have.

**Architecture:** One plugin, one skill, mirroring `dcc-darkraise-ui`. `SKILL.md` carries opinionated knowledge and injects two shell probes that resolve how the framework is referenced and which versions are cached; five `rules/*.md` files carry Incorrect/Correct code pairs; exact API detail is read live from the NuGet XML doc files, or from the source tree when the framework is project-referenced.

**Tech Stack:** Markdown skill files, Claude Code plugin manifest schema, `claude plugin validate`, `claude plugin eval`. Target framework is C# on `net10.0-windows`.

**Spec:** `docs/superpowers/specs/2026-08-27-darkraise-framework-skills-design.md`

## Global Constraints

- Plugin name must start with `dcc-` and agree across the directory name, `plugins/<name>/.claude-plugin/plugin.json` `name`, and the `.claude-plugin/marketplace.json` entry. (CLAUDE.md)
- `claude plugin validate .` must pass after every task that touches a manifest.
- English only in all files. Conventional commits: `<type>(<scope>): <subject>`, subject ≤50 chars, imperative, no period.
- Version pinned in `SKILL.md`: the **`docs/win32ui/` revision**, not a package version. The prose tracks the docs, and the published package lags them.
- **Two XML doc files matter, not one.** The MVVM surface lives in the Darkraise core assembly, so `Darkraise.xml` is as load-bearing as `Darkraise.Win32UI.xml`.
- Source of truth for every claim: `D:\Repositories\Personal\darkraise-framework\`. Verify before writing; do not assert from memory. Where a design rule and a control spec disagree, `docs/win32ui/design-system.md` wins — it says so itself.
- Rule files state a rule, then an **Incorrect** block, then a **Correct** block.

---

### Task 1: Plugin scaffold and marketplace registration

**Files:**
- Create: `plugins/dcc-darkraise-win32ui/.claude-plugin/plugin.json`
- Create: `plugins/dcc-darkraise-win32ui/README.md`
- Modify: `.claude-plugin/marketplace.json` (append to the `plugins` array)

**Interfaces:**
- Consumes: nothing.
- Produces: the plugin root `plugins/dcc-darkraise-win32ui/`, under which Task 2 creates `skills/darkraise-win32ui/SKILL.md`.

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing check**

```bash
test -f plugins/dcc-darkraise-win32ui/.claude-plugin/plugin.json && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Create the plugin manifest**

Create `plugins/dcc-darkraise-win32ui/.claude-plugin/plugin.json`:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
  "name": "dcc-darkraise-win32ui",
  "description": "Teaches Claude to write idiomatic Darkraise.Win32UI code: token-resolved visuals, the raise ladder and overlay-hover rule, the fluent View builder, convention-based MVVM and draml markup, plus the framework limits it must never promise past.",
  "version": "0.1.0",
  "author": {
    "name": "Darkraise"
  },
  "homepage": "https://github.com/darkraise/claude-code-plugins/tree/main/plugins/dcc-darkraise-win32ui",
  "repository": "https://github.com/darkraise/claude-code-plugins",
  "license": "MIT",
  "keywords": [
    "darkraise-win32ui",
    "win32",
    "direct2d",
    "desktop",
    "csharp",
    "mvvm",
    "design-system"
  ]
}
```

- [ ] **Step 3: Register in the marketplace**

Append this object to the `plugins` array in `.claude-plugin/marketplace.json`:

```json
{
  "name": "dcc-darkraise-win32ui",
  "source": "./plugins/dcc-darkraise-win32ui",
  "description": "Teaches Claude to write idiomatic Darkraise.Win32UI code: token-resolved visuals, the raise ladder and overlay-hover rule, the fluent View builder, convention-based MVVM and draml markup, plus the framework limits it must never promise past.",
  "category": "development",
  "keywords": ["darkraise-win32ui", "win32", "direct2d", "desktop", "csharp", "mvvm", "design-system"]
}
```

- [ ] **Step 4: Write the README**

Create `plugins/dcc-darkraise-win32ui/README.md` with these sections:

1. **What it does** — the skill fires in any project referencing `Darkraise.Win32UI` and supplies the framework's design rules and API conventions.
2. **Invocation** — the qualified slash form `/dcc-darkraise-win32ui:darkraise-win32ui`; the bare `/darkraise-win32ui` works only while no other installed plugin claims that skill name.
3. **How it stays current** — the skill pins a `docs/win32ui/` revision and probes what is cached. **State the drift direction explicitly:** the published package lags the source repository, so an API described by the skill but absent from the installed package's XML docs means the consumer needs an upgrade, not a workaround.
4. **Requirement** — the probes use `!`-backtick command injection, a documented Claude Code feature that works on Windows through Git Bash. A permission policy can disable it, in which case the skill silently degrades to its prose.

- [ ] **Step 5: Verify**

```bash
test -f plugins/dcc-darkraise-win32ui/.claude-plugin/plugin.json && echo PASS || echo FAIL
claude plugin validate .
```

Expected: `PASS`, validation succeeds.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-darkraise-win32ui .claude-plugin/marketplace.json
git commit -m "feat(win32ui): scaffold plugin and register it"
```

---

### Task 2: SKILL.md mechanism — frontmatter, pin, probes, API lookup contract

**Files:**
- Create: `plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/SKILL.md`

**Interfaces:**
- Consumes: the plugin root from Task 1.
- Produces: `SKILL.md` containing the two probes and the XML-doc lookup contract. Task 3 appends the body to this same file; Tasks 4–8 are linked from the Critical Rules index Task 3 writes.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 1 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

```bash
grep -q 'Darkraise.xml' plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/SKILL.md 2>/dev/null && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Write the frontmatter and version pin**

Create the file starting with exactly this, substituting the current `docs/win32ui/` revision for `<REV>` — obtain it with `git -C /d/Repositories/Personal/darkraise-framework log -1 --format=%h -- docs/win32ui`:

````markdown
---
name: darkraise-win32ui
description: Manages Darkraise.Win32UI desktop applications — building views, composing controls, theming, layout, MVVM, and draml markup. Applies when working with Darkraise.Win32UI, the View builder, DarkraiseScreen, .drui or .draml files, DRUI diagnostics, or any project referencing the Darkraise.Win32UI package.
user-invocable: true
---

# Darkraise.Win32UI

A desktop UI framework built directly on Win32 and Direct2D. No WPF, no WinForms, no third-party packages — windows are real `HWND`s, painting goes through Direct2D and DirectWrite, and the framework is NativeAOT compatible. Targets `net10.0-windows` and requires Windows.

**These rules were written against the `docs/win32ui/` revision `<REV>`.**

**Drift runs backwards here.** The published package lags the source repository. If this skill describes an API that is absent from the installed package's XML docs, the consumer needs a package upgrade — do not invent a workaround, and do not assume the skill is wrong.
````

- [ ] **Step 3: Write the project-context probes**

Append exactly this section. The first probe captures whole reference elements so the `Version` attribute survives — a bare attribute-value grep stops at the closing quote and yields no version, and the XML doc path depends on knowing it:

````markdown
## Current Project Context

How the framework is referenced:

```
!`grep -rh --include=*.csproj --include=Directory.Packages.props -oE '<(Package|Project)Reference[^>]*Darkraise[^>]*' . | sort -u`
```

What is in the package cache:

```
!`ls ~/.nuget/packages/darkraise.win32ui/ ~/.nuget/packages/darkraise/ 2>/dev/null`
```

A `ProjectReference` means the source tree is available and is the better source. A `PackageReference` means read the XML docs. The second probe also covers central package management, where the `.csproj` carries no version at all.
````

- [ ] **Step 4: Write the API lookup contract**

Append exactly this section:

````markdown
## Look up the API before you write

**Two XML doc files matter, not one:**

```
~/.nuget/packages/darkraise.win32ui/<version>/lib/net10.0-windows/Darkraise.Win32UI.xml
~/.nuget/packages/darkraise/<version>/lib/<tfm>/Darkraise.xml
```

The second is easy to miss and load-bearing. The **MVVM surface** — `DarkraiseScreen`, `Set(ref …)`, `[RootViewModel]`, the conductors — lives in the **Darkraise core assembly**, not in Darkraise.Win32UI. Sending an MVVM lookup to `Darkraise.Win32UI.xml` searches a file that does not contain the answer.

These files are verbose; never read one whole. Grep for the member prefix of the type in question:

```bash
grep -oE '<member name="M:Darkraise\.Win32UI\.Builder\.ButtonBuilder\.[^"]*"' <path-to-xml>
```

**That prefix alone is not enough.** Builders derive from `ViewBuilder<TControl,TBuilder>`, so the inherited half of the fluent surface — `Padding`, `Margin`, `Width`, `Height`, `Visible`, `Enabled`, `Name`, and the generic `Bind` — sits under the mangled generic-arity prefix. Grep for it too:

```bash
grep -oE '<member name="M:Darkraise\.Win32UI\.Builder\.ViewBuilder`2\.[^"]*"' <path-to-xml>
```

Grepping only the concrete builder reports `ButtonBuilder` as having eight methods, which is wrong in a way that looks right.

When the framework is project-referenced, prefer the source: `src/Darkraise.Win32UI/` and `src/Darkraise/`. Read `Builder/<Name>Builder.cs` **together with** `Builder/ViewBuilder.cs` for the same reason.
````

- [ ] **Step 5: Write the workflow and quick reference**

Append a `## Workflow` section: read the injected context; decide source-vs-XML lookup; look up the type including its base builder; write the code; verify against the Critical Rules; check `rules/limitations.md` before promising any capability.

Then append a `## Quick Reference` section with a minimal application — `Program.Main` calling `new App().Run()`, an `App : DarkraiseApplication` overriding `ConfigureServices` and `Configure`, a `[RootViewModel] ShellViewModel : DarkraiseScreen`, and a `ShellView : ViewBase<ShellViewModel>` with a `BuildView` returning a `View.Stack(...)`. Copy the shape from `src/Darkraise.Win32UI/README.md` and verify it compiles conceptually against `docs/win32ui/getting-started.md` §2.

- [ ] **Step 6: Verify**

```bash
grep -q 'Darkraise.xml' plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/SKILL.md && echo PASS || echo FAIL
grep -q 'ViewBuilder`2' plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/SKILL.md && echo PASS || echo FAIL
claude plugin validate .
```

Expected: two `PASS` lines, validation succeeds.

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-darkraise-win32ui/skills
git commit -m "feat(win32ui): add skill probes and API lookup contract"
```

---

### Task 3: SKILL.md body — principles, rules index, key patterns, control selection

**Files:**
- Modify: `plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/SKILL.md`

**Interfaces:**
- Consumes: the `SKILL.md` created in Task 2.
- Produces: the Critical Rules index, whose five relative links (`./rules/tokens.md`, `./rules/builder.md`, `./rules/layout.md`, `./rules/mvvm-draml.md`, `./rules/limitations.md`) Tasks 4–8 must satisfy exactly.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

```bash
grep -q 'rules/tokens.md' plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/SKILL.md && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Write the Principles section**

Insert a `## Principles` section after the version pin, with the five core design values taken from `docs/win32ui/design-system.md` §1, each one sentence:

1. **Raised from dark.** Hierarchy comes from surfaces stepping toward light, not decoration. Light theme derives from the same roles.
2. **Hairlines define structure; shadows define float.** Every container gets a 1px border; only genuinely floating things and cards cast shadows.
3. **One accent, four meanings, no leakage.** Accent means interactive or current; red, amber, green, blue mean destructive, warning, success, info and are never decorative.
4. **Motion is causality.** Animation confirms an action caused a result. No ambient or looping motion outside progress indicators.
5. **Density with hierarchy.** A desktop tool framework — 32px rows, 13px body text — but density never comes from shrinking type below the scale or cutting padding below the tokens.

- [ ] **Step 3: Write the Critical Rules index**

Append a `## Critical Rules` section with five `###` subsections linking to their rule files:

```markdown
### Tokens & color → [tokens.md](./rules/tokens.md)

- **Never a literal.** Colors, fonts, radii, padding, gaps, and font sizes resolve from `Tokens.*`.
- **A consumer project gets no analyzer backstop.** DRUI020 is scoped to the framework assembly; a clean build proves nothing about your code.
- **The overlay-hover rule.** A hover fill on a `SurfaceOverlay` host must be `Surface3`, never `Surface2`.
- **One current-item marker.** Two signals, per-item state, never a travelling rail.

### Builder API → [builder.md](./rules/builder.md)

- **Every `View` factory returns a builder.** Reaching a control member needs `.Build()`.
- **Half the fluent surface is inherited.** Look up `ViewBuilder<TControl,TBuilder>` too.
- **Bind, don't poll.** `.Bind(vm, x => x.Property)` and `.OnClick(vm.Method)`.

### Layout → [layout.md](./rules/layout.md)

- **Only `Box` and `Border` paint.** Every other layout primitive is invisible skeleton.
- **Scroll is the only legitimate escape valve for overflow.**
- **Containers own spacing, children do not.**

### MVVM & draml → [mvvm-draml.md](./rules/mvvm-draml.md)

- **`FooViewModel` resolves to `FooView` by convention.**
- **These types live in the Darkraise core assembly,** not Darkraise.Win32UI.
- **Markup views are compiled, not parsed.** A mistyped binding is a compile error.

### Limits → [limitations.md](./rules/limitations.md)

- **Check this file before promising any capability.**
- **No UI Automation or screen-reader support.** Do not claim accessibility compliance.
```

- [ ] **Step 4: Write the Key Patterns block**

Append a `## Key Patterns` section: one `csharp` block with correct-vs-wrong pairs as inline comments, covering (a) a token-resolved color vs a literal, (b) `.Bind(vm, x => x.P)` vs manual assignment, (c) a layout primitive vs manual coordinates, (d) `.Build()` where a concrete control type is required. Derive exact names from `src/Darkraise.Win32UI/Builder/View.cs` and `Builder/ViewBuilder.cs`.

- [ ] **Step 5: Write the Control Selection table**

Append a `## Control Selection` section organised by the sixteen design-spec categories, which are the framework's own taxonomy. Read `docs/win32ui/design/README.md` and reproduce its category-to-controls mapping as a "Need | Use" table: actions, text input, date & time, selection, range & pickers, status & indicators, feedback, overlays, modals & dialogs, window & shell, containers, navigation, data, code, media & motion, layout.

Verify every control named exists in `src/Darkraise.Win32UI/Controls/`.

- [ ] **Step 6: Verify**

```bash
grep -oE 'rules/[a-z-]+\.md' plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/SKILL.md | sort -u
```

Expected: exactly five paths — `rules/builder.md`, `rules/layout.md`, `rules/limitations.md`, `rules/mvvm-draml.md`, `rules/tokens.md`.

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-darkraise-win32ui/skills
git commit -m "feat(win32ui): add principles, rules index, patterns"
```

---

### Task 4: rules/tokens.md

**Files:**
- Create: `plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/tokens.md`

**Interfaces:**
- Consumes: the `### Tokens & color` bullets from Task 3's Critical Rules index.
- Produces: nothing later tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

```bash
test -f plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/tokens.md && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Read the source of truth**

- `docs/win32ui/design-system.md` §3.1 through §3.6 — surfaces, foreground, borders, accent and semantics, chart colors, derived state.
- `docs/win32ui/design-system.md` §2 — the current-item marker.
- `docs/win32ui/design-system.md` §6 — the interaction-state contract.
- `src/Darkraise.Win32UI.Generators/ThemeLiteralAnalyzer.cs` — confirm the analyzer's scope before describing it.

- [ ] **Step 3: Write the file**

Required sections, each with an Incorrect/Correct pair:

1. **Never a literal.** Incorrect: a hardcoded `Color.FromArgb(...)` or `"#1B1D21"`. Correct: the matching `Tokens.*` value. Reason: a literal does not re-theme.
2. **Where enforcement exists.** DRUI020 is scoped to the assembly named `Darkraise.Win32UI` and, within it, to `Controls/**` and `Builder/**`; it returns early for any other compilation. **A consumer project gets no analyzer backstop at all.** State this plainly so a clean build is not mistaken for compliance.
3. **The raise ladder.** A table of the **six surface roles** — `SurfaceSunken`, `SurfaceBase`, `SurfaceSidebar`, `SurfaceHeader`, `SurfaceRaised`, `SurfaceOverlay` — plus the **three component-internal state steps** `Surface1`, `Surface2`, `Surface3`, with the role of each. That is nine rows, not twelve; do not describe the steps as roles.
4. **The overlay-hover rule.** A hover fill must be at least one *visible* step above its host surface. On a `SurfaceOverlay` host — menus, dropdown lists — that means `Surface3`. Incorrect: `Surface2` on an overlay, which is nearly identical to the overlay surface in dark mode and reads as no feedback at all. This is load-bearing; give it its own worked pair.
5. **Foreground and the contrast rule.** `Foreground`, `ForegroundMuted`, `ForegroundSubtle` and what each is for. Anything meant to be seen uses a `Foreground*` token — never a `Border*` or `Surface*` color, which are invisible against nearby surfaces.
6. **Borders.** All structural borders are 1px. The only thicker strokes are the 2px active-tab underline and the 3px focus halo.
7. **Hairlines vs shadows.** Shadows are reserved for genuinely floating surfaces — popovers, menus, dialogs, drawers, toasts — and for cards. Nothing else casts a shadow.
8. **One accent, four semantics.** Accent means interactive or current. The four hues mean exactly what they say and are never decorative.
9. **The current-item marker.** One rule everywhere, at least two signals so it never rides on color alone, expressed in each surface's own idiom, and cleared-and-repainted rather than slid between siblings. Controls must not invent alternatives.
10. **Motion is causality.** No ambient or looping motion outside explicit progress indicators.

- [ ] **Step 4: Verify the surface list against the design system**

```bash
sed -n '/### 3.1 Surfaces/,/### 3.2/p' /d/Repositories/Personal/darkraise-framework/docs/win32ui/design-system.md
```

Every token named in the rule file must appear in that table; no invented token may.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/tokens.md
git commit -m "docs(win32ui): add token and color rules"
```

---

### Task 5: rules/builder.md

**Files:**
- Create: `plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/builder.md`

**Interfaces:**
- Consumes: the `### Builder API` bullets from Task 3's Critical Rules index.
- Produces: nothing later tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

```bash
test -f plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/builder.md && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Read the source of truth**

- `src/Darkraise.Win32UI/Builder/View.cs` — the factory surface.
- `src/Darkraise.Win32UI/Builder/ViewBuilder.cs` — the inherited fluent methods.
- `src/Darkraise.Win32UI/Builder/ButtonBuilder.cs` — a concrete builder, for the derived-vs-inherited contrast.
- `docs/win32ui/known-limitations.md` §15 — read it carefully; see step 3 item 3.
- `docs/win32ui/extending-controls.md` — the custom-control contract.

- [ ] **Step 3: Write the file**

Required sections, each with an Incorrect/Correct pair:

1. **Compose through the `View` factory.** 106 entry points covering controls, containers, and layout. Show a small view built with `View.Stack(...)`, `View.Label(...)`, `View.Button(...)`.
2. **The fluent chain.** `.Bind(vm, x => x.Property)` for binding, `.OnClick(vm.Method)` for commands, and the styling verbs. Incorrect: assigning a control property once at construction and expecting it to track the view model. Correct: `.Bind(...)`.
3. **Every `View` factory returns a builder — uniformly.** Known-limitations §15 records that `View.ImageView()`, `View.Drawer()`, and `View.Sheet()` were the *last three returning bare controls* and were changed in the 2026-07-27 parity sweep. **This is a historical source break, not a live inconsistency.** State the current uniform behaviour; note only that older sample code constructing those three no longer compiles, and that reaching a control member or assigning to a concretely-typed target needs `.Build()` (builders carry an implicit conversion to `Control`, so use-as-`Control` is unaffected). Do not write that three factories still differ — that would teach a falsehood.
4. **Half the fluent surface is inherited.** `ButtonBuilder` declares only a handful of its own members; `Padding`, `Margin`, `Width`, `Height`, `Visible`, `Enabled`, `Name`, and the generic `Bind` come from `ViewBuilder<TControl,TBuilder>`. Show the two greps from `SKILL.md`, and state that grepping only the concrete builder under-reports the surface.
5. **`Border` has no `View.Border()` factory.** Despite `Border` being one of the two painting primitives, there is no such factory — `View.cs` maps Border to `Box`. Say how `Border` is actually reached rather than leaving a reader to call a factory that does not exist. Verify the current mechanism in `Builder/View.cs` before writing this.
6. **Authoring a custom control.** Condensed from `docs/win32ui/extending-controls.md`: measure and arrange, paint through the drawing context, resolve every visual from tokens, and participate in the interaction-state contract. This section is required — Task 9's eval asks for a custom control, and without it the skill would be graded on knowledge it never supplies.

- [ ] **Step 4: Verify the factory count and the §15 claim**

```bash
grep -cE '^    public static' /d/Repositories/Personal/darkraise-framework/src/Darkraise.Win32UI/Builder/View.cs
sed -n '/## 15\./,/## 16\./p' /d/Repositories/Personal/darkraise-framework/docs/win32ui/known-limitations.md
```

Expected: `106`. Confirm the §15 text says the three were *changed to* builders, matching what the rule file asserts.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/builder.md
git commit -m "docs(win32ui): add builder API rules"
```

---

### Task 6: rules/layout.md

**Files:**
- Create: `plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/layout.md`

**Interfaces:**
- Consumes: the `### Layout` bullets from Task 3's Critical Rules index.
- Produces: nothing later tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

```bash
test -f plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/layout.md && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Read the source of truth**

- `docs/win32ui/design-system.md` §13 (all of §13.1 through §13.8) — the layout and render contract.
- `docs/win32ui/design-system.md` §5 — space, size, radius, elevation.
- `docs/win32ui/design/layout.md` — the per-primitive spec.
- `src/Darkraise.Win32UI/Layout/` — the layout managers.

- [ ] **Step 3: Write the file**

Required sections, each with an Incorrect/Correct pair:

1. **The primitives and when each applies.** `Box`, `Border`, `Label`, `Stack`, `Inline`, `Center`, `Grid`, `GridPanel`, `DockPanel`, `WrapPanel`, `UniformGrid`, `Spacer`. **Only `Box` and `Border` paint**; everything else is invisible skeleton that owns spacing and structure. Incorrect: positioning children at manual coordinates. Correct: a `Stack` with a gap.
2. **Sizing.** How a control decides its box (§13.1).
3. **Overflow and clipping** (§13.2) and **text overflow** (§13.3).
4. **Scroll is the only legitimate escape valve for real overflow** (§13.4). Incorrect: shrinking content below the type scale to make it fit. Correct: a scroll host.
5. **Distribution** — how a container splits space among children (§13.5).
6. **Content alignment**, horizontal and vertical (§13.6).
7. **Constraints and responsive reflow** (§13.7).
8. **Relayout vs repaint** (§13.8) — which changes trigger which, and why it matters for performance.
9. **The spacing scale.** Density never comes from shrinking type below the scale or removing padding below the tokens.

- [ ] **Step 4: Verify every primitive named exists**

```bash
ls /d/Repositories/Personal/darkraise-framework/src/Darkraise.Win32UI/Layout/
grep -nE 'public static (Stack|Inline|Center|Box|Grid|GridPanel|DockPanel|WrapPanel|UniformGrid)' /d/Repositories/Personal/darkraise-framework/src/Darkraise.Win32UI/Builder/View.cs
```

Every primitive named in the rule file must be reachable. If one is not reachable through `View`, say how it *is* reached — do not imply a factory that does not exist.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/layout.md
git commit -m "docs(win32ui): add layout contract rules"
```

---

### Task 7: rules/mvvm-draml.md

**Files:**
- Create: `plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/mvvm-draml.md`

**Interfaces:**
- Consumes: the `### MVVM & draml` bullets from Task 3's Critical Rules index.
- Produces: nothing later tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

```bash
test -f plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/mvvm-draml.md && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Read the source of truth**

- `src/Darkraise/Mvvm/DarkraiseScreen.cs` and `src/Darkraise/Mvvm/Attributes/RootViewModelAttribute.cs` — **note the assembly: these are in Darkraise core, not Darkraise.Win32UI.**
- `src/Darkraise/DarkraisePropertyChangedBase.cs` — the `Set(ref …)` overload and its `CallerMemberName`.
- `src/Darkraise.Win32UI/Mvvm/AppShellViewModel.cs` — multi-screen hosting.
- `docs/win32ui/getting-started.md` §3 (lifecycle) and §10 (draml).
- `src/Darkraise.Win32UI.Generators/README.md` — the diagnostics table and the `AdditionalFiles` wiring.
- `src/Darkraise.Win32UI.Generators/Darkraise.Win32UI.Generators.csproj` — confirm where `DruiSchema.xsd` is packaged.

- [ ] **Step 3: Write the file**

Required sections, each with an Incorrect/Correct pair where a pair makes sense:

1. **Convention-based MVVM.** `FooViewModel` resolves to `FooView`. `[RootViewModel]` marks the entry point that `Run()` resolves after scanning the configured assemblies. Screens derive from `DarkraiseScreen`. Incorrect: manually constructing and wiring a view. Correct: letting the convention resolve it.
2. **Where these types live.** `DarkraiseScreen`, `Set(ref …)`, `[RootViewModel]`, and the conductors are in the **Darkraise core assembly** (`src/Darkraise/Mvvm/`), not Darkraise.Win32UI. Route API lookups to `Darkraise.xml`, not `Darkraise.Win32UI.xml`. State this explicitly — it is the single most likely lookup mistake.
3. **Change notification.** `Set(ref _field, value)` with its `CallerMemberName` overload. Incorrect: assigning the backing field directly and expecting the UI to update.
4. **Multi-screen navigation.** `AppShellViewModel` and `OneActiveConductor<DarkraiseScreen>` for page hosting and activation. This is the first thing a real application needs; a single-screen example is not enough.
5. **Lifecycle hooks, DI, and dialogs** from the shared MVVM layer.
6. **Markup views are compiled, not parsed.** Hand `.drui` / `.draml` files to the compiler as `AdditionalFiles`; the generator emits a `ViewBase<TViewModel>` partial with bindings resolved against the real view-model type, so a renamed or mistyped property is a **compile error**, not a silent runtime no-op. Show the `<ItemGroup>` wiring and a small view file.
7. **Runtime-loaded draml is different.** `DramlView.LoadFile` parses at runtime; those files are `Content`, not `AdditionalFiles`. Getting this wrong produces a file that is either compiled twice or not shipped.
8. **`DruiSchema.xsd` does not appear in your project.** It ships in the generator package under `content/`, which a `PackageReference` does not copy into the consuming project. Editor validation means pointing the editor at the package-cache path. Say so rather than implying the file lands locally.
9. **The diagnostics table.** DRUI001 through DRUI014, each with its meaning, so a build error is diagnosable from this file without a web search. Copy the table from the generators README and verify each row.

- [ ] **Step 4: Verify the assembly claim and the diagnostics range**

```bash
find /d/Repositories/Personal/darkraise-framework/src -name "DarkraiseScreen.cs"
grep -oE 'DRUI[0-9]{3}' /d/Repositories/Personal/darkraise-framework/src/Darkraise.Win32UI.Generators/DruiGenerator.cs | sort -u
```

Expected: the path is under `src/Darkraise/`, confirming it is core and not Win32UI. The diagnostics list must match the table in the rule file exactly.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/mvvm-draml.md
git commit -m "docs(win32ui): add MVVM and draml rules"
```

---

### Task 8: rules/limitations.md

**Files:**
- Create: `plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/limitations.md`

**Interfaces:**
- Consumes: the `### Limits` bullets from Task 3's Critical Rules index.
- Produces: nothing later tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

```bash
test -f plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/limitations.md && echo PASS || echo FAIL
```

Expected: `FAIL`

- [ ] **Step 2: Read the source of truth**

`docs/win32ui/known-limitations.md` in full — all seventeen numbered sections.

- [ ] **Step 3: Write the file**

Open with a framing sentence: **this file exists because the most damaging failure is not wrong code, it is confidently designing a feature the framework does not support.** Then one short entry per limitation, each saying what to do instead:

1. No UI Automation or screen-reader support — never claim accessibility compliance.
2. IME / CJK text input caveats.
3. x64 / ARM64 only.
4. The Windows version floor.
5. Localization constraints.
6. DPI behaviour.
7. Layout and render contract gaps against design-system §13.
8. Collection virtualization boundaries.
9. Window sizing is clamped to the monitor work area.
10. `IDrawingContext.DrawImageData` takes `byte[]` only.
11. The sanctioned §9 ellipsis.
12. `MenuPopup` renders its whole item list — the practical size limit this implies.
13. GDI+ image formats only.
14. Animated GIFs render their first frame only.
15. The 2026-07-27 `View` factory source break — cross-reference `builder.md` rather than restating it, and do **not** describe it as a live inconsistency.
16. Popup corner rounding: DWM collapses Rounded and Pill.
17. `CodeDisplay` Copy/Cut require a selection.

- [ ] **Step 4: Verify the section count matches the source**

```bash
grep -cE '^## [0-9]+\.' /d/Repositories/Personal/darkraise-framework/docs/win32ui/known-limitations.md
grep -cE '^### |^[0-9]+\. ' plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/limitations.md
```

The rule file must cover every numbered limitation in the source. A missing entry is a capability Claude may promise wrongly.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui/rules/limitations.md
git commit -m "docs(win32ui): add known limitations rules"
```

---

### Task 9: Eval suite

**Files:**
- Create: `plugins/dcc-darkraise-win32ui/evals/<case-name>/` (one directory per case)

**Interfaces:**
- Consumes: the finished skill from Tasks 2–8; the eval measures its effect.
- Produces: nothing later tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Confirm the real eval contract**

```bash
claude plugin eval --help
```

Confirm: cases live in `<eval dir>/**/case.yaml`, or `prompt.md` plus `graders/*.md`; the eval dir defaults to `evals/`; `--ablation with-without` runs a no-plugin baseline arm and reports a score delta.

**Do not copy shadcn's `evals/evals.json`** — different harness, never read by this command.

- [ ] **Step 2: Scaffold the suite through the built-in author flow**

```bash
cd plugins/dcc-darkraise-win32ui
claude plugin eval init --bare token-resolved-colors
```

- [ ] **Step 3: Author four cases**

| Case | Prompt asks for | Grader checks |
| --- | --- | --- |
| `token-resolved-colors` | a custom status control | every visual resolves from `Tokens.*`; no color literal (pattern + LLM grader) |
| `overlay-hover-step` | a dropdown menu with hover feedback | hover fill is `Surface3` on the overlay host, not `Surface2` (LLM grader) |
| `current-item-marker` | a sidebar with an active item | uses the standard marker with two signals; no invented accent rail (LLM grader) |
| `layout-primitives` | a two-column form screen | uses `Stack` / `Grid` / `DockPanel`, not manual coordinates (LLM grader) |

- [ ] **Step 4: Run the suite with a baseline arm**

```bash
cd plugins/dcc-darkraise-win32ui
claude plugin eval --ablation with-without --runs 1 --max-cost-usd 5
```

Expected: each case scores higher with the plugin than without. A zero delta means the case is not measuring the skill — rewrite the prompt so the un-skilled baseline actually fails it.

**If the command reports the feature is not enabled for this account, stop and record that in the commit message.** The suite still lands; it simply cannot be run here.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-darkraise-win32ui/evals
git commit -m "test(win32ui): add eval suite with baseline arm"
```

---

### Task 10: Final validation and release

**Files:**
- Modify: `plugins/dcc-darkraise-win32ui/README.md` (usage examples, if anything learned in Tasks 4–9 changes them)

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
cd plugins/dcc-darkraise-win32ui/skills/darkraise-win32ui
for f in $(grep -oE 'rules/[a-z-]+\.md' SKILL.md | sort -u); do test -f "$f" && echo "OK $f" || echo "MISSING $f"; done
```

Expected: five `OK` lines, no `MISSING`.

- [ ] **Step 3: Confirm the §15 claim was not written as a live inconsistency**

```bash
grep -rniE 'three (View )?factories (that )?return' plugins/dcc-darkraise-win32ui/skills/
```

Any hit must read as a historical source break, not a current inconsistency. This was a factual error caught in spec review; verify it did not reappear.

- [ ] **Step 4: Confirm both XML doc files are named**

```bash
grep -rc 'Darkraise.xml' plugins/dcc-darkraise-win32ui/skills/
grep -rc 'Darkraise.Win32UI.xml' plugins/dcc-darkraise-win32ui/skills/
```

Expected: both non-zero. Naming only the Win32UI file sends every MVVM lookup to a file that cannot answer it.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-darkraise-win32ui
git commit -m "chore(win32ui): release 0.1.0"
```
