# Rejected

Approaches a future session would propose again, and why they were dropped.

## Executor registry

### Rejecting two registry entries that claim one id
Tried: a duplicate-id rule in the executor interface plan's Contracts and in `list_ids`
Why it looked right: two entries naming one executor would be ambiguous
Why it failed: validity keys on `id == filename stem`, so two entries can never claim one id; the rule was dead and untested, and was dropped in review round 1 (2026-09-21)
Would change if: an entry's id stops being its filename stem
Source: docs/superpowers/notes/2026-09-21-executor-interface-plan-review.md@7221a67

### Carrying an Override above `#### Part A` into every part unit
Tried: making `plan-revise` apply a task-level `**Override:**` line to each of its parts
Why it looked right: the override was written for the whole task
Why it failed: `plan-lint` reads each part's own text, so the tools already agree by construction; carrying it would report as `fail:override` units that `plan-lint` accepts (parked ruling, revising-plans Task 4, 2026-09-21)
Would change if: `plan-lint` starts reading a task's Override for its parts
Source: docs/superpowers/notes/2026-09-21-dr-superpowers-revising-plans-followups.md@da5b2e3

### Counting `**Override:**` lines in the revising-plans survey's `eligible`
Tried: excluding overridden units from the survey's eligible count
Why it looked right: an overridden unit is not delegated
Why it failed: spec §4 defines survey eligibility as potential, and neither legacy corpus held an Override line (parked ruling, revising-plans Task 5)
Would change if: a corpus with Override lines needs surveying
Source: docs/superpowers/notes/2026-09-21-dr-superpowers-revising-plans-followups.md@da5b2e3

## Session budget

### Merging `ctx_primary_root` with `ctx_candidates`
Tried: deduplicating the two-line git-common-dir walk they share
Why it looked right: the same walk in two places
Why it failed: deduplicating would touch the Claude-host budget path (parked in the Codex budget plan, Task 4)
Would change if: the Claude path is being changed anyway
Source: docs/superpowers/notes/dr-superpowers-codex-budget-followups.md@0b4b05f
