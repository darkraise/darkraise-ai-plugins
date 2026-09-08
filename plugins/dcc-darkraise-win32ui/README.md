# dcc-darkraise-win32ui

Teaches Claude Code and Codex the design rules and API conventions of the `Darkraise.Win32UI`
desktop framework.

## What it does

The skill fires in any project referencing `Darkraise.Win32UI` and supplies what
the package cannot: the raise ladder and its overlay-hover step, the
one-accent-four-semantics rule, the single current-item marker, the fluent `View`
builder and how to discover a builder's real method surface, convention-based
MVVM, and compiled `draml` markup with its diagnostics.

It also carries a `rules/limitations.md`, because the most damaging failure here
is not wrong code — it is confidently designing a feature the framework does not
support.

## Invocation

The skill auto-triggers on `Darkraise.Win32UI` being referenced. To force it:

```
/dcc-darkraise-win32ui:darkraise-win32ui
```

The bare `/darkraise-win32ui` also works, but only while no other installed plugin
claims that skill name. The qualified form always resolves.

## How it stays current

The skill's prose is pinned to a `docs/win32ui/` revision, **not a package
version** — the prose tracks the framework's documentation, and the documentation
tracks the source.

**Drift here runs backwards compared to a normal package.** The published NuGet
package lags the source repository, so the skill can describe an API a consumer's
installed package does not have yet. When that happens the consumer needs a
package upgrade — the skill is not wrong and a workaround should not be invented.

Explicit discovery inspects PackageReference, ProjectReference, and centrally
managed PackageVersion entries, then the selected framework's restore assets.
Resolved package paths determine which XML documentation to read; the highest
globally cached version is not evidence of the consumer's installed version.

## Requirement

Use the active client's shell and file-reading tools. No Claude-only inline
preprocessing is required. Missing packages or restore assets produce an explicit
prerequisite result. Install `dcc-darkraise-win32ui@darkraise` from the repository
root marketplace in either client. The slash examples above describe Claude Code;
Codex can select or explicitly invoke the bundled skill.

## Contents

| File | Covers |
| --- | --- |
| `skills/darkraise-win32ui/SKILL.md` | Probes, the two XML doc files, principles, critical rules index, control selection |
| `rules/tokens.md` | The raise ladder, the overlay-hover rule, semantics, the current-item marker |
| `rules/builder.md` | The `View` factory, the inherited builder surface, custom controls |
| `rules/layout.md` | The layout and render contract, the primitives, the spacing scale |
| `rules/mvvm-draml.md` | Convention MVVM, conductors, compiled markup, DRUI diagnostics |
| `rules/limitations.md` | What the framework cannot do |

## Requirements

Targets `net10.0-windows` and requires Windows. Direct2D rendering needs a
D3D-capable device.

## License

MIT
