# dcc-darkraise-ui

Teaches Claude Code and Codex the conventions of the `darkraise-ui` React kit.

## What it does

The skill fires in any project with `darkraise-ui` installed and supplies what
the package itself cannot: the seventeen-axis theme system and why a raw
Tailwind color silently opts out of it, the CSS layer override contract that
makes `!important` unnecessary, the kit's form and layout primitives, and the
provider stack order. It deliberately does **not** carry component prop tables —
those are read live from the installed package's type definitions, so they can
never go stale.

## Invocation

The skill auto-triggers on `darkraise-ui` being present. To force it, use the
qualified slash form:

```
/dcc-darkraise-ui:darkraise-ui
```

The bare `/darkraise-ui` also works, but only while no other installed plugin
claims that skill name. The qualified form is the one that always resolves.

## How it stays current

The skill's prose is pinned to `darkraise-ui` **6.5.0**. It explicitly directs
the active client to resolve the consumer's installed version and component
types, including hoisted and linked workspace dependencies.

**When the installed version differs from the pin, the package's own type
definitions win over anything written in the skill.** That is the standing
instruction, and it is why the skill carries rules rather than API tables — the
kit moved from 6.0.0 to 6.5.0 in twelve days, renaming a theme axis and adding
two required keys along the way.

## Requirement

The consumer package, shell access, and file-reading tools are required. Missing
packages produce an explicit prerequisite result. Claude-only inline command
preprocessing is not needed. Install `dcc-darkraise-ui@darkraise` from the root
marketplace in either client; use the client's skill picker or explicit skill
invocation. The slash examples above describe Claude Code.

## Contents

| File | Covers |
| --- | --- |
| `skills/darkraise-ui/SKILL.md` | Probes, the read-the-types contract, principles, critical rules index, component selection |
| `rules/theming.md` | The seventeen axes, semantic tokens, the 6.0→6.5 migration |
| `rules/styling.md` | The `@layer` override contract, state variants, `cn()`, Tailwind 4 |
| `rules/composition.md` | No Radix, subpath imports, overlays, `UiLabelsProvider` |
| `rules/forms.md` | The seven field primitives, `isInvalid`/`errors` validation |
| `rules/layout-data.md` | `SidebarLayout`, `RouterAdapterProvider`, `DataTable`, provider order |

## License

MIT
