# Legacy plugin names

Plans, ledgers, and notes written before dr-superpowers 1.2.0 name skills and
agents under older plugin prefixes. Resolve them with this table when you read
them.

This is the only file in the maintained plugins allowed to spell the old
prefixes literally; `scripts/validate-repository.mjs` enforces that.

## Rule

- Resolve by suffix, whatever old prefix precedes it: `superpowers:`,
  `dcc-superpower-companions:`, or `dr-superpowers:`.
- Translate at read time. Never rewrite the plan or note that carries the name.
- Log one ledger line per distinct name translated:
  `Ruling: translated <old> -> <new> — legacy plugin name — none`
- A suffix not in the tables below is not a legacy name. It is an unknown name:
  on an `**Implementer:**` line, dr-superpowers:subagent-driven-development
  handles it through its Dispatch rulings; anywhere else, treat it as absent,
  log `Ruling: unknown name <name> ignored — not in legacy-names.md — <cost if
  wrong>`, and carry on. A running plan never stops on a name.

## Skills

| Suffix | Resolves to |
|---|---|
| `using-superpowers` | `dr-superpowers:using-superpowers` |
| `brainstorming` | `dr-superpowers:brainstorming` |
| `selecting-approaches` | `dr-superpowers:selecting-approaches` |
| `writing-plans` | `dr-superpowers:writing-plans` |
| `executing-plans` | `dr-superpowers:executing-plans` |
| `subagent-driven-development` | `dr-superpowers:subagent-driven-development` |
| `test-driven-development` | `dr-superpowers:test-driven-development` |
| `systematic-debugging` | `dr-superpowers:systematic-debugging` |
| `verification-before-completion` | `dr-superpowers:verification-before-completion` |
| `requesting-code-review` | `dr-superpowers:requesting-code-review` |
| `receiving-code-review` | `dr-superpowers:receiving-code-review` |
| `finishing-a-development-branch` | `dr-superpowers:finishing-a-development-branch` |
| `using-git-worktrees` | `dr-superpowers:using-git-worktrees` |
| `writing-skills` | `dr-superpowers:writing-skills` |
| `dispatching-parallel-agents` | No skill. Dispatch independent agents in one message so they run concurrently |
| `assigning-implementers` | `dr-superpowers:writing-plans`, section "Assign an implementer to every task" |
| `dispatching-tiered-implementers` | `dr-superpowers:subagent-driven-development` |

A plan header that says "REQUIRED SUB-SKILL: <old prefix>dispatching-tiered-implementers"
therefore needs nothing extra: subagent-driven-development already reads the
`**Implementer:**` lines itself.

## Agents

Each suffix resolves to `dr-superpowers:` followed by the same suffix.

| Suffix |
|---|
| `impl-haiku` |
| `impl-sonnet-low` |
| `impl-sonnet-medium` |
| `impl-sonnet-high` |
| `impl-sonnet-xhigh` |
| `impl-sonnet-max` |
| `impl-opus-low` |
| `impl-opus-medium` |
| `impl-opus-high` |
| `impl-opus-xhigh` |
| `impl-opus-max` |
| `impl-fable-low` |
| `impl-fable-medium` |
| `impl-fable-high` |
| `impl-fable-xhigh` |
| `impl-fable-max` |
| `judge-fable` |
| `judge-opus` |
| `scout-sonnet` |

Translation changes only the prefix. The tier a plan recorded — including a
reserve agent a human assigned — is the tier it runs at.
