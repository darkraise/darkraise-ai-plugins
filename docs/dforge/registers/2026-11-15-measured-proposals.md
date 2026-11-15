# Measured proposals

**Source:** triage of deferred rows, 2026-11-15 (owner: brainstorm specs after the residual fixes)
**Covers:** docs/dforge/specs/2026-11-15-measured-proposals-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | plan review: move mechanical checks (edit old text present, paths and symbols resolve) into plan-lint; use the delta template for every round after the first | docs/dforge/plans/2026-11-15-measured-proposals.md | A1-A4 | done | plan-lint path and range checks (Task 2) |
| 2 | low-yield review stages outside the task loop: audit or drop unclassified second-judge and critique reviews; drop the language and docs lenses rather than lowering lensCap; run spec review only for architectural work | docs/dforge/plans/2026-11-15-measured-proposals.md | A5-A11, A20, A21 | done | code-quality lens grouped at route time (Tasks 3-4) |
| 3 | Evidence-bound findings: each judge finding cites a failing command or a quoted brief line, a fix round starts only for findings that reproduce, and the reviewer prompt says skip style | docs/dforge/plans/2026-11-15-measured-proposals.md | A14-A16 | done | kept: docs/dforge/notes/2026-11-15-review-prompt-replay.md |
| 4 | Diff-first, narrow judge search: specific questions, narrow grep, view only known ranges | docs/dforge/plans/2026-11-15-measured-proposals.md | A14, A16 | done | kept: docs/dforge/notes/2026-11-15-review-prompt-replay.md |
| 5 | Lean plans: decisions, signatures and test assertions instead of full code (overlaps token-efficiency row 14) | docs/dforge/plans/2026-11-15-measured-proposals.md | A17-A19 | done | kept: docs/dforge/notes/2026-11-15-lean-test-contracts.md |
| 6 | Review gating by diff size and risk, with a cheap pre-check | docs/dforge/plans/2026-11-15-measured-proposals.md | A12 | done | task-step small-fix skip removed (Task 5) |
| 7 | Re-check that plans at depth light lose little by skipping acceptance QA, by counting on five shipped light plans the acceptance-statement defects the final review missed | - | - | deferred | count plans whose depth-route depth is light, not the spec Depth line: 2 shipped by 2026-11-15 (dflow-hud-overhaul: final review caught the QA-reachable defect, none since; downloads-mutation-measurement: all demo); darkcloud's 3 light specs routed standard/full and ran QA; re-check after 3 more |
| 8 | Re-check the code-quality lens's yield per part once five review records carry its parts line | - | - | deferred | 0 review records carry a code-quality parts= line on 2026-11-15 (grouping shipped that day); re-check at five |
| 9 | task-loop-steps.acceptance.test.sh A5/A6 re-review rows are covered by task-step.test.sh 'prompts for a one-line fix' and its risk-3 row | - | - | deferred | final review: for dforge:test-simplifier |
| 10 | plan-lint's C1 errors read `ERROR Task <N>:` where the spec wrote `ERROR: Task <N>:` (preflight-13, parked at Task 2) | - | - | n/a | ruled at Task 2: plan-lint keeps its one output form; A1/A3 bind only an ERROR naming the task and path; no script parses the text after ^ERROR |
| 11 | skill-size.test.sh red at baseline: finishing SKILL.md 20085 bytes over its 20000 cap since 235f759d | - | - | done | fixed in the final fix wave (fd1e039a): SKILL.md now 19989 bytes |
| 12 | M2 run 4 contract 'the External executors header is accepted silently' says it fails today, but it passes at the base | - | - | n/a | a finished measurement's record, kept in docs/dforge/notes/2026-11-15-lean-test-contracts.md Limits; nothing to change |
| 13 | re-review-prompt.md:108 upholds a 'not reproduced' rejection only when the report shows the run, but final-review.md:431 lets the fixer reproduce by reading, and the REJECTED line format still says 'what was run' | - | - | done | not reproduced kept for runs; read-only contradictions go to the REJECTED check (final-review.md) |
