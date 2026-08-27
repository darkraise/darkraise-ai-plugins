# Eval suite

Four cases, each targeting a rule the skill exists to enforce.

| Case | Rule under test |
| --- | --- |
| `token-resolved-colors` | Every visual resolves from `Tokens.*`; no literals |
| `overlay-hover-step` | `Surface3`, not `Surface2`, on a `SurfaceOverlay` host |
| `current-item-marker` | The standard marker, two signals, never a travelling rail |
| `layout-primitives` | Layout primitives, not manual coordinates |

## Status: authored, not yet run

`claude plugin eval` is **early access** and is not enabled on this account — it
exits with "`plugin eval` is currently in early access". The suite has therefore
never been executed, and `claude plugin eval init` could not be used to generate
it.

The layout follows the shape `claude plugin eval init --bare` documents: one
directory per case, each holding `prompt.md` and `graders/criteria.md`. **The
grader files carry prose criteria and no frontmatter.** If the runner requires
frontmatter fields or a typed grader declaration, add them when early access
lands — the criteria themselves are the part worth keeping.

## Running it, once enabled

```bash
cd plugins/dcc-darkraise-win32ui
claude plugin eval --ablation with-without --runs 1 --max-cost-usd 5
```

`--ablation with-without` is the point: it runs a no-plugin baseline arm and
reports the score delta, the only direct measure of whether the skill changed
behaviour. **A case with a zero delta is not measuring the skill** — rewrite its
prompt so the un-skilled baseline actually fails it.
