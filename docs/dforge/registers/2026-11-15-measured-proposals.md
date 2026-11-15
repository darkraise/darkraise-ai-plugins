# Measured proposals

**Source:** triage of deferred rows, 2026-11-15 (owner: brainstorm specs after the residual fixes)
**Covers:** docs/dforge/specs/2026-11-15-measured-proposals-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | plan review: move mechanical checks (edit old text present, paths and symbols resolve) into plan-lint; use the delta template for every round after the first | docs/dforge/plans/2026-11-15-measured-proposals.md | A1-A4 | done | plan-lint path and range checks (Task 2) |
| 2 | low-yield review stages outside the task loop: audit or drop unclassified second-judge and critique reviews; drop the language and docs lenses rather than lowering lensCap; run spec review only for architectural work | docs/dforge/plans/2026-11-15-measured-proposals.md | A5-A11, A20, A21 | doing | from 2026-10-25-token-efficiency.md #15 |
| 3 | Evidence-bound findings: each judge finding cites a failing command or a quoted brief line, a fix round starts only for findings that reproduce, and the reviewer prompt says skip style | docs/dforge/plans/2026-11-15-measured-proposals.md | A14-A16 | done | kept: docs/dforge/notes/2026-11-15-review-prompt-replay.md |
| 4 | Diff-first, narrow judge search: specific questions, narrow grep, view only known ranges | docs/dforge/plans/2026-11-15-measured-proposals.md | A14, A16 | done | kept: docs/dforge/notes/2026-11-15-review-prompt-replay.md |
| 5 | Lean plans: decisions, signatures and test assertions instead of full code (overlaps token-efficiency row 14) | docs/dforge/plans/2026-11-15-measured-proposals.md | A17-A19 | doing | from 2026-10-27-speed-and-cost.md #15 |
| 6 | Review gating by diff size and risk, with a cheap pre-check | docs/dforge/plans/2026-11-15-measured-proposals.md | A12 | doing | from 2026-10-27-speed-and-cost.md #17 |
| 7 | Re-check that plans at depth light lose little by skipping acceptance QA, by counting on five shipped light plans the acceptance-statement defects the final review missed | - | - | deferred | needs five shipped light plans; two exist on 2026-11-15 (dflow-hud-overhaul, downloads-mutation-measurement) |
| 8 | Re-check the code-quality lens's yield per part once five review records carry its parts line | - | - | deferred | spec review Medium, 2026-11-15: lang-*, type-design and docs-comments never ran before, so there is no yield data |
