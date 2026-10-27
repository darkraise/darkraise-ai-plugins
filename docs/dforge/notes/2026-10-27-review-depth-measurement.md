# Review-depth measurement — 2026-10-27

**Sample size:** 0
**Plans with a Critical plan-review finding or a QA fail:** 0
**Verdict:** inconclusive

The verdict is `inconclusive`: the sample holds 0 plans, fewer than the four the measurement needs; the design proceeds and a deferred register row re-checks once five light plans have shipped.

The question: on plans whose spec scores light and whose tasks are all at risk 1 or below, do plan review and acceptance QA rarely find a defect that the task reviews and the whole-branch review would miss? A plan is in the sample when its spec reads light under the seven Process Depth triggers (no `risk`, `new-subsystem` or `interface` trigger) and a plan-review report or an `Acceptance QA: complete` ledger line is still held. A plan counts as a hit when a held report lists a Critical finding or the QA line reports at least one fail.

## Candidates

Completed plans whose tasks are all scored at risk 1 or below, with the evidence the workspaces and the ledger store still hold (plan names with the retired dcc- prefix print without it, because the repository validator rejects that prefix in docs outside docs/superpowers):

```
stores: documents local progress local
worktrees searched:
/root/repositories/darkraise-ai-plugins
/root/repositories/darkraise-ai-plugins/.claude/worktrees/agent-a0336e1d480ef96e6
/root/repositories/darkraise-ai-plugins/.claude/worktrees/agent-a7058bdd42f2549b3
/root/repositories/darkraise-ai-plugins/.claude/worktrees/review-depth
/root/repositories/darkraise-ai-plugins/.claude/worktrees/task-loop-steps
/root/repositories/darkraise-ai-plugins/.claude/worktrees/typed-seats
/root/repositories/darkraise-ai-plugins/.claude/worktrees/ui-ux-skill

PLAN docs/superpowers/plans/2026-08-21-companions-reserve-tier.md tasks=5 spec=docs/superpowers/specs/2026-08-21-companions-reserve-tier-design.md
  plan-review header: none
  no evidence held
PLAN docs/superpowers/plans/2026-08-28-darkraise-ui.md tasks=10 spec=docs/superpowers/specs/2026-08-27-darkraise-framework-skills-design.md
  plan-review header: none
  no evidence held
PLAN docs/superpowers/plans/2026-08-28-darkraise-win32ui.md tasks=10 spec=docs/superpowers/specs/2026-08-27-darkraise-framework-skills-design.md
  plan-review header: none
  no evidence held
PLAN docs/superpowers/plans/2026-08-31-companions-external-executors.md tasks=9 spec=docs/superpowers/specs/2026-08-31-companions-external-executors-design.md
  plan-review header: none
  no evidence held
PLAN docs/superpowers/plans/2026-09-11-dr-superpowers-standalone-base.md tasks=10 spec=docs/superpowers/specs/2026-09-11-dr-superpowers-standalone-base-design.md
  plan-review header: none
  no evidence held
PLAN docs/superpowers/plans/2026-10-01-dr-superpowers-tier-eval.md tasks=21 spec=docs/superpowers/specs/2026-10-01-dr-superpowers-tier-eval-design.md
  plan-review header: **Plan review:** 2026-10-01 — dr-superpowers:judge-opus — executability 16 / coherence 17 / coverage 18 / assumptions 15 (round 2)
  no evidence held
PLAN docs/superpowers/plans/2026-10-18-controller-model-eval.md tasks=4 spec=docs/superpowers/notes/2026-10-17-controller-model-eval.md
  plan-review header: **Plan review:** 2026-10-18 — dr-superpowers:judge-opus — executability 16 / coherence 17 / coverage 17 / assumptions 13 (round 2)
  no evidence held
```

The survey listed worktrees from `.claude/worktrees/*`, not `git worktree list`, so a worktree outside that directory was not searched; the re-check lists them with `git worktree list`.

## Sample

No candidate holds a plan-review report or an `Acceptance QA` ledger line, so no plan was read.
