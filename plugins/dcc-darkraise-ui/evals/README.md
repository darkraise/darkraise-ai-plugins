# Eval suite

Four cases, each targeting a rule the skill exists to enforce.

| Case | Rule under test |
| --- | --- |
| `no-radix-import` | No `@radix-ui` — every primitive is in-house |
| `semantic-tokens` | Semantic tokens, never raw Tailwind colors |
| `form-primitives` | `darkraise-ui/forms` primitives, and the `errors` object shape |
| `subpath-imports` | Subpath entry points, not the barrel |

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
cd plugins/dcc-darkraise-ui
claude plugin eval --ablation with-without --runs 1 --max-cost-usd 5
```

`--ablation with-without` is the point of the exercise: it runs a no-plugin
baseline arm and reports the score delta, which is the only direct measure of
whether the skill changed behaviour. **A case with a zero delta is not measuring
the skill** — rewrite its prompt so the un-skilled baseline actually fails it.
