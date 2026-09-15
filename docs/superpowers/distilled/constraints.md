# Constraints

Rulings and policy that bind future work in this repository.

## Execution lanes

### The Codex executor lane is on
When `scripts/codex-gate` reports `lane=true`, the planner ticks `codex` without asking and gives every task that passes the lane gate an `**Executor:**` line.
Set by: owner, 2026-09-15 review-routing design session
Scope: every plan written for this repository on a Claude host
Source: docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md@18a00a7
