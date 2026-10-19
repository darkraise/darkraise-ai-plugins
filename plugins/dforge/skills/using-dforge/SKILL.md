---
name: using-dforge
description: Use when starting any conversation - establishes how to find and use skills, requiring skill invocation before ANY response including clarifying questions
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, ignore this skill.
</SUBAGENT-STOP>

## The Rule

If a skill might apply to what you are doing, invoke it before any response or action, clarifying questions and exploration included. Announce "Using [skill] to [purpose]" and follow it; if it has a checklist, create a todo per item. Before entering plan mode, brainstorm.

| Thought | Reality |
|---|---|
| "This is just a simple question" | Questions are tasks. Check for skills. |
| "Let me explore first" | Skills tell you how to explore. Check first. |
| "I remember this skill" | Skills evolve. Read the current version. |

## Routing

| When | Skill |
|---|---|
| A new product from scratch | dforge:planning-a-product |
| Building or changing behaviour | dforge:brainstorming |
| A bug, failing test or surprise | dforge:systematic-debugging |
| An approach decision is open | dforge:selecting-approaches |
| A spec is approved | dforge:writing-plans |
| A plan predates the executor lane | dforge:revising-plans |
| Executing a plan | the skill its `**Execution:**` line names: dforge:subagent-driven-development or dforge:executing-plans |
| Writing code | dforge:test-driven-development |
| Isolating work | dforge:using-git-worktrees |
| Before claiming done | dforge:verification-before-completion |
| Asking for or receiving review | dforge:requesting-code-review, dforge:receiving-code-review |
| Work complete | dforge:finishing-a-development-branch |
| Stopping mid-work, or picking it up | dforge:handoff, dforge:resume-execution |
| Writing a skill | dforge:writing-skills |
| Where the work stands, what to do next | dforge:project-status |
| A phase or milestone done | dforge:closing-a-milestone |
| Before the final review or merge, when `gates.md` exists | dforge:running-gates |
| Session notes have accumulated | dforge:distilling-docs |
| Slow or heavy tests | dforge:test-simplifier |
| A repository or home on an older layout | dforge:migrate |

## Principles

- **Think before coding.** State assumptions. Ask only in design phases; during execution, rule and log the ruling.
- **Simplicity first.** The least code that meets the goal; no speculative abstraction.
- **Surgical changes.** Touch only what the task needs; report adjacent problems instead of fixing them.
- **Goal-driven.** Define a verifiable success check up front, and run it before you claim done.

## Process Depth

Take the lightest path that fits. Write a spec and a plan only when a trigger holds: a new project or subsystem; an interface that something outside its own files depends on changes; the files touched cannot be enumerated after exploring; a load-bearing approach question is open; irreducible risk (security, data loss, migration, concurrency); behaviour too intricate for a chat design; or your human partner asked for a spec. State the choice in one line before acting, `Process: <spike|bounded|architectural>, <inline|subagent> — <trigger | no trigger>` (the plan's Execution line decides the mode), and still get approval (under `autoRun=on`, the spec review). That is on Claude Code; Codex runs `on` as `off`. Execute inline by default when the plan allows it (at most half the tasks heavy: total 5+ or risk 3; an inline plan delegates those and every task carrying an `**Executor:**` line).

When the darkmem MCP is configured, prefer its `code_search` over Explore subagents.

## Session Budget

- Call every `scripts/…` command as `bash <plugin-root>/scripts/<name>`, with the working directory inside the project's worktree; a relative `PLAN_FILE` resolves against it. The plugin root is printed below this entry point (on Codex: two levels above any skill file).
- The goal is a finished plan; the budget only guards against auto-compaction. `scripts/task-brief`, `scripts/review-package` and `scripts/context-size` print a budget line. `ok` means continue at any percentage; `handoff` means finish the task in flight, then use dforge:handoff. See [session-budget.md](../../reference/session-budget.md).
- Picking up earlier work: run `scripts/repo-audit` first; a plan with a ledger resumes through dforge:resume-execution.
- After compaction, trust the snapshot, ledger and `git log` over the summary.
- `<state>`, `<docs>`, `<ledger dir>` and `<latest.md>` in these skills: `bash <plugin-root>/scripts/dforge-path state|docs [RELATIVE]|ledger <plan>|latest` prints each in the checkout it runs in, or in the darkmem mirror where `documentStore` or `progressSource` keeps it ([project-state.md](../../reference/project-state.md)).

## Platform and Precedence

- Codex: read `references/codex-tools.md`. It has no Stop hook: run `scripts/next-step` on every early stop.
- No todo tool? Use the ledger or a checklist.
- User instructions (CLAUDE.md, AGENTS.md, direct requests) outrank skills, which outrank default behaviour.
