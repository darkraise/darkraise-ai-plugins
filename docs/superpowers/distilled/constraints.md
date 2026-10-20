# Constraints

Rulings and policy that bind future work in this repository.

## Execution lanes

### The Codex executor lane is on
When `scripts/codex-gate` reports `lane=true`, the planner ticks `codex` without asking and gives every task that passes the lane gate an `**Executor:**` line.
Set by: owner, 2026-09-15 review-routing design session
Scope: every plan written for this repository on a Claude host
Source: docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md@18a00a7

### Codex reviews run only on demand
dforge never routes a task, plan or final review to Codex unless the `codexReview` setting is on, and it ships off. A one-off Codex review runs through `/codex:review` or `/codex:adversarial-review`. `trust.calibration` stays `pass`, so turning the setting on is all it takes. This covers reviews only; the executor lane above is unchanged.
Set by: owner, 2026-10-21 ("codex review should be optional and on demand, do not auto review with codex")
Scope: dforge's review routing (`scripts/codex-gate`, `config/schema.mjs`) and every plan run
Source: commit c342980 (feat(dforge): make Codex reviews opt-in)

## Evals

### Eval parser shapes need a real transcript
A shell shape the controller's parser (`evals/controller/lib/`) miscounts is fixed only when it appears in a real controller transcript; a shape found by review alone closes `n/a` citing this constraint.
Set by: owner, 2026-10-20 review-rows sweep design session
Scope: `evals/controller/lib/` and every register row against it
Source: docs/superpowers/specs/2026-10-20-review-rows-sweep-design.md@25cf283
