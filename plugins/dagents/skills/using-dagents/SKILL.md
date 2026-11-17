---
name: using-dagents
description: Use when starting any conversation - establishes how to find and use skills, requiring skill invocation before ANY response including clarifying questions
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, ignore this skill.
</SUBAGENT-STOP>

## The Rule

If a skill might apply to what you are doing, invoke it before any response or action, clarifying questions and exploration included. Announce "Using [skill] to [purpose]" and follow it; a checklist gets a todo per item. Before entering plan mode, brainstorm.

| Thought | Reality |
|---|---|
| "This is just a simple question" | Questions are tasks. Check for skills. |
| "Let me explore first" | Skills tell you how to explore. Check first. |
| "I remember this skill" | Skills evolve. Read the current version. |

## Routing

| When | Skill |
|---|---|
| A new product from scratch | dagents:planning-a-product |
| Building or changing behaviour | dagents:brainstorming |
| Anything a user sees or does | dagents:ui-ux |
| A bug, failing test or surprise | dagents:systematic-debugging |
| An approach decision is open | dagents:selecting-approaches |
| A spec is approved | dagents:writing-plans |
| A plan predates the executor lane | dagents:revising-plans |
| Executing a plan | dagents:subagent-driven-development; dagents:executing-plans when the Execution line names inline |
| Writing code | dagents:test-driven-development |
| Isolating work | dagents:using-git-worktrees |
| Before claiming done | dagents:verification-before-completion |
| Asking for or receiving review | dagents:requesting-code-review, dagents:receiving-code-review |
| Work complete | dagents:finishing-a-development-branch |
| Stopping mid-work, or picking it up | dagents:handoff, dagents:resume-execution |
| Writing a skill | dagents:writing-skills |
| Where the work stands, what to do next | dagents:project-status |
| A phase or milestone done | dagents:closing-a-milestone |
| Before the final review or merge, when `gates.md` exists | dagents:running-gates |
| Session notes have accumulated | dagents:distilling-docs |
| Slow or heavy tests | dagents:test-simplifier |
| A repository or home on an older layout | dagents:migrate |

## Principles

- **Think before coding.** State assumptions. Ask only in design phases; during execution, rule and log the ruling.
- **Simplicity first.** The least code that meets the goal; no speculative abstraction.
- **Surgical changes.** Touch only what the task needs; report adjacent problems instead of fixing them.
- **Goal-driven.** Define a verifiable success check up front, and run it before you claim done.

## Seats

Every dispatch names a seat: a `dagents:` agent or a typed built-in (`Explore`); `general-purpose` takes an explicit `model`. No forks. Read-only checks (register rows, findings, a claim) go to `dagents:judge-sonnet-high`, or `dagents:judge-opus` across several files.

## Process Depth

Take the lightest path that fits. Write a spec and a plan only when a trigger holds: a new project or subsystem; an interface that something outside its own files depends on changes; the files touched cannot be enumerated after exploring; a load-bearing approach question is open; irreducible risk (security, data loss, migration, concurrency); behaviour too intricate for a chat design; or your human partner asked for a spec. State the choice in one line before acting, `Process: <spike|bounded|architectural> — <trigger | no trigger>`, and still get approval (under `autoRun=on`, the spec review). On Codex, `on` runs as `off`. Architectural: `Process: architectural, depth <d> — <triggers>`, `<d>` from `scripts/depth-route --spec-triggers`. A plan executes in subagent mode, one implementer agent per task, unless `executionMode=inline` or your human partner asks for inline.

With the darkmem MCP, prefer its `code_search` over Explore subagents.

## Session Budget

- Call every `scripts/…` command as `bash <plugin-root>/scripts/<name>`, with the working directory inside the project's worktree; a relative `PLAN_FILE` resolves against it. The plugin root is printed below this entry point (on Codex: the parent of the `skills/` directory).
- The goal is a finished plan; the budget only guards against auto-compaction. `scripts/task-brief`, `scripts/review-package` and `scripts/context-size` print a budget line. `ok`: continue at any percentage; `handoff`: finish the task in flight, then use dagents:handoff. See [session-budget.md](../../reference/session-budget.md).
- Picking up earlier work: run `scripts/repo-audit` first; a plan with a ledger resumes through dagents:resume-execution.
- After compaction, trust the snapshot, ledger and `git log` over the summary.
- `<state>`, `<docs>`, `<ledger dir>` and `<latest.md>` in these skills: `bash <plugin-root>/scripts/dagents-path state|docs [RELATIVE]|ledger <plan>|latest` prints each in the checkout it runs in, or in the darkmem mirror where `documentStore` or `progressSource` keeps it ([project-state.md](../../reference/project-state.md)).

## Platform and Precedence

- Codex: first run `node <plugin-root>/scripts/workflow-guard.mjs --host codex --self dagents`; on exit 3 show its output and stop. Then follow `<plugin-root>/skills/using-dagents/references/codex-tools.md`.
- No todo tool? Use the ledger or a checklist.
- User instructions (CLAUDE.md, AGENTS.md, direct requests, fast mode) outrank skills, which outrank defaults.
