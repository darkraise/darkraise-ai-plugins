# Example Workflow

```
You: I'm using Subagent-Driven Development to execute this plan.

[Setup: worktree verified]
[task-brief --header <docs>/plans/feature-plan.md; read plan-header.md, never the whole plan]
[Resolve workspace: scripts/sdd-workspace <docs>/plans/feature-plan.md — no ledger inside, fresh start]
[Create todos for all tasks]
[Pre-flight: ruling seat returns preflight.md — clean; ledger the pre-flight ruling]

Task 1: Hook installation script  (**Implementer:** dforge:impl-sonnet-low)

[task-step start PLAN_FILE 1: brief written, assigned line Task 1: implementer impl-sonnet-low (assigned; base a1b2c3d), dispatch file task-1-dispatch.md; dispatch impl-sonnet-low with that path, no model or effort argument]
[Only waiting remains: end the turn; the implementer's completion starts the next one]

Implementer: DONE — 5/5 passing; report file written; assumptions: user-level install (brief silent)

[task-step review PLAN_FILE 1: seat judge-sonnet-high, prompt task-1-review-prompt.md, check identity: clean, check attribution: clean; dispatch the seat with the prompt path]
Judge: report task-1-review-report.md — spec pass, quality approved, scores 17/18/16/16, 0 findings
[task-step verdict PLAN_FILE 1: spec: pass, quality: approved, scores: spec 17 / scope 18 / verification 16 / quality 16, fix: none, check tracked: clean]

[Ledger: Task 1: complete (commits a1b2c3d..d4e5f6a, review clean; scores spec 17 / scope 18 / verification 16 / quality 16) — done: install-hook command; verified: node --test test/hook.test.js → 5/5; remaining: none; discovered: none; assumptions: user-level install]

Task 2: Recovery modes  (**Implementer:** dforge:impl-sonnet-medium)

[task-step start PLAN_FILE 2; dispatch impl-sonnet-medium with the dispatch file's path]
Implementer: DONE — 8/8 passing

[task-step review PLAN_FILE 2: state line shows t0; dispatch judge-sonnet-high with the prompt path]
Judge: report task-2-review-report.md — spec fail, quality changes, scores 7/17/15/12, 2 Important
[task-step verdict PLAN_FILE 2: spec: fail; Important 2 src/progress.ts:0 — missing progress reporting; Important 2 src/index.ts:88 — magic number (100); fix: task-2-fix-1.md (2 findings)]

[date +%s → t1; t1 − t0 = 140s, so resume the implementer with the path of task-2-fix-1.md, whose two bullets name both findings]
Implementer: Added progress reporting, extracted PROGRESS_INTERVAL. 10/10 passing.

[task-step rereview PLAN_FILE 2: two findings are open, so no skip; dispatch the printed seat with task-2-rereview-1-prompt.md]
Re-reviewer: report task-2-rereview-1-report.md — fix round addressed, 0 open
[task-step verdict PLAN_FILE 2 --rereview 1: fix round: addressed, open: 0, fix: none]

[Ledger: Task 2: fix round 1/2 (2 addressed, 0 open; commits d4e5f6a..b7c8d9e; resumed)]
[Ledger: Task 2: complete (commits d4e5f6a..b7c8d9e, review clean; scores spec 16 / scope 17 / verification 15 / quality 15) — …]

...

[After the last task's complete line: context-size --final says ok — continue to Final Review]
[final-review.md: package the branch; review-route --final prints judge-opus for this plain plan; Codex round in the background]
[a fresh judge-opus dedupes and verifies the union: 1 CONFIRMED (both), 1 REJECTED]
[ONE fix dispatch, told to run the full suite through suite-run after its last commit; one scoped re-review; clean]

[Ledger: Final review: clean (commits a1b2c3d..f0e1d2c) — finishing is never budget-checked]
[Skill tool: dforge:finishing-a-development-branch, in this turn — suite-run reuses the fix wave's pass at the unchanged HEAD; gates, Rulings I made, the three-option menu last]
```
