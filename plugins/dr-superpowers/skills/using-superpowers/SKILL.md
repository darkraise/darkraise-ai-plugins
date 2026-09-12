---
name: using-superpowers
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
| Building or changing behaviour | dr-superpowers:brainstorming |
| A bug, failing test or surprise | dr-superpowers:systematic-debugging |
| An approach decision is open | dr-superpowers:selecting-approaches |
| A spec is approved | dr-superpowers:writing-plans |
| Executing a plan | the skill its `**Execution:**` line names: dr-superpowers:subagent-driven-development or dr-superpowers:executing-plans |
| Writing code | dr-superpowers:test-driven-development |
| Isolating work | dr-superpowers:using-git-worktrees |
| Before claiming done | dr-superpowers:verification-before-completion |
| Asking for or receiving review | dr-superpowers:requesting-code-review, dr-superpowers:receiving-code-review |
| Work complete | dr-superpowers:finishing-a-development-branch |
| Stopping mid-work, or picking it up | dr-superpowers:handoff, dr-superpowers:resume-execution |
| Writing a skill | dr-superpowers:writing-skills |

## Principles

- **Think before coding.** State assumptions. Ask only in design phases; during execution, rule and log the ruling.
- **Simplicity first.** The least code that meets the goal; no speculative abstraction.
- **Surgical changes.** Touch only what the task needs; report adjacent problems instead of fixing them.
- **Goal-driven.** Define a verifiable success check before you start, and run it before you claim done.

## Process Depth

Take the lightest path that fits. Write a spec and a plan only when a trigger holds: a new project or subsystem; an interface that something outside its own files depends on changes; the files touched cannot be enumerated after exploring; a load-bearing approach question is open; irreducible risk (security, data loss, migration, concurrency); behaviour too intricate for a chat design; or your human partner asked for a spec. State the choice in one line before acting, `Process: <spike|bounded|architectural>, <inline|subagent> — <trigger | no trigger>` (the mode is your expectation; the plan's Execution line, checked by `plan-lint`, decides), and still get approval. Execute inline by default when the plan allows it (every task scores 4 or less, none at risk 3). Bugs go to systematic-debugging first.

Prefer an indexed code tool (for example darkmem `code_search`) over Explore subagents when one is available.

## Session Budget

- Every `scripts/…` command runs from the plugin root, the path printed under this entry point (on Codex: the directory two levels above any skill file).
- `scripts/task-brief`, `scripts/review-package` and `scripts/context-size` print a budget line. `handoff` means: finish the step in flight, then use dr-superpowers:handoff. See [session-budget.md](../../reference/session-budget.md).
- Picking up earlier work: run `scripts/repo-audit` first; a plan with a ledger continues through dr-superpowers:resume-execution.
- After more than an hour idle, start fresh from `.superpowers/handoff/latest.md`: the prompt cache is cold.
- After compaction, trust the compaction snapshot, the ledger and `git log` over the summary.

## Platform and Precedence

- Codex: read `references/codex-tools.md`.
- User instructions (CLAUDE.md, AGENTS.md, direct requests) take precedence over skills, which override default behaviour.
