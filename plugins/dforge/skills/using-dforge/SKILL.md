---
name: using-dforge
description: Use when starting any conversation - establishes how dforge works with the harness's own planning and which dforge skills apply
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, ignore this skill.
</SUBAGENT-STOP>

## How to work

- **Plan in the harness.** Non-trivial work goes through the harness's own plan mode; trivial work is done directly.
- **Think before coding.** State assumptions. Ask while planning; during execution, decide and say what you decided.
- **Simplicity first.** The least code that meets the goal; no speculative abstraction.
- **Surgical changes.** Touch only what the task needs; report adjacent problems instead of fixing them.
- **Goal-driven.** Define a verifiable success check up front, run it, and show its output before you claim done.

## Routing

Invoke the skill before any response or action on that kind of work.

| When | Skill |
|---|---|
| Anything a user sees or does | dforge:ui-ux |
| A bug, failing test or surprise | dforge:systematic-debugging |
| A repository or home on an older layout | dforge:migrate |

## Scripts and paths

- Call every `scripts/…` command as `bash <plugin-root>/scripts/<name>`, with the working directory inside the project's worktree. The plugin root is printed below this entry point (on Codex: the parent of the `skills/` directory).
- `<state>` and `<docs>` in these skills: `bash <plugin-root>/scripts/dforge-path state|docs [RELATIVE]` prints each in the checkout it runs in, or in the darkmem mirror where `documentStore` keeps it ([project-state.md](../../reference/project-state.md)).
- With the darkmem MCP, prefer its `code_search` over Explore subagents.

## Platform and Precedence

- Codex: read `references/codex-tools.md`.
- User instructions (CLAUDE.md, AGENTS.md, direct requests) outrank skills, which outrank defaults.
