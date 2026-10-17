# darkraise-ui

Teaches Claude Code and Codex the conventions of the `darkraise-ui` React kit.

## What it does

The skill fires in any project with `darkraise-ui` installed and supplies what
the package itself cannot: the 7.0 theme model of styles, presets and axes,
custom definitions in the theme config, why a raw Tailwind color silently opts
out of it, the CSS layer override contract that makes `!important`
unnecessary, the kit's form and layout primitives, localization, and the
provider stack order. It deliberately does **not** carry component prop tables —
those are read live from the installed package's type definitions, so they can
never go stale.

## Invocation

The skill auto-triggers on `darkraise-ui` being present. To force it, use the
qualified slash form:

```
/darkraise-ui:darkraise-ui
```

The bare `/darkraise-ui` also works, but only while no other installed plugin
claims that skill name. The qualified form is the one that always resolves.

## How it stays current

The skill's prose targets `darkraise-ui` **7.0**, and points 6.x projects at the
kit's 7.0 upgrade guide. It explicitly directs the active client to resolve the
consumer's installed version and component types, including hoisted and linked
workspace dependencies.

**When the installed version differs from the pin, the package's own type
definitions win over anything written in the skill.** That is the standing
instruction, and it is why the skill carries rules rather than API tables — the
7.0 release alone renamed presets to styles, replaced five theme axes and
removed the bare status color utilities.

## Requirement

The consumer package, shell access, and file-reading tools are required. Missing
packages produce an explicit prerequisite result. Claude-only inline command
preprocessing is not needed. Install `darkraise-ui@darkraise` from the root
marketplace in either client; use the client's skill picker or explicit skill
invocation. The slash examples above describe Claude Code.

In Claude Code:

```text
/plugin marketplace add darkraise/darkraise-ai-plugins
/plugin install darkraise-ui@darkraise
```

## Contents

| File | Covers |
| --- | --- |
| `skills/darkraise-ui/SKILL.md` | Probes, the read-the-types contract, principles, critical rules index, component selection |
| `rules/theming.md` | Styles, presets, the twenty-three axes, custom definitions, semantic tokens, the 6.x→7.0 renames |
| `rules/styling.md` | The `@layer` override contract, state variants, `cn()`, Tailwind 4 |
| `rules/composition.md` | No Radix, subpath imports, overlays, `UiLabelsProvider`, locale packs and providers |
| `rules/forms.md` | The seven field primitives, `isInvalid`/`errors` validation |
| `rules/layout-data.md` | Layouts and shell styles, `RouterAdapterProvider`, `DataTable`, provider order |

## License

MIT
