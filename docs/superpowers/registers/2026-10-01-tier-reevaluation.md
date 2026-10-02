# Tier re-evaluation

**Source:** owner request, 2026-10-01 session: "With sonnet 5.5, I see the capability and ability of opus and sonnet is more effective and much better than before. Let re-evaluate them and update the agents mapping table."; evidence answer "Measured pilot"; scope answer: implementer rows 3-5, review seats, low rows 0-2, row 6 and escalation targets
**Covers:** docs/superpowers/specs/2026-10-01-dr-superpowers-tier-eval-design.md, docs/superpowers/specs/2026-10-02-dr-superpowers-ladder-update-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Let re-evaluate them (opus and sonnet) with a measured pilot: implementer rows 3-5, review seats, low rows 0-2, row 6 and escalation targets | docs/superpowers/plans/2026-10-01-dr-superpowers-tier-eval.md | spec §Acceptance | done | owner ruled 2026-10-02: rows 2-5 and judge-opus effort move, row 6 stays; see docs/superpowers/notes/2026-10-02-tier-eval-results.md, Owner rulings |
| 2 | update the agents mapping table | docs/superpowers/plans/2026-10-02-dr-superpowers-ladder-update.md | spec 2026-10-02 ladder-update §Acceptance | done | ladder update merged 2026-10-02 (plugin 1.24.0): totals 2-5 lowered, judge-opus at medium; plan 2026-10-02-dr-superpowers-ladder-update |
| 3 | Owner ruling: exclude or keep the three unwinnable stripped cases (s-review-routing-t17, s-review-fixes-t8, s-execution-cost-t15), then re-run report.mjs | - | ruling recorded | done | excluded 2026-10-02; report re-run, no verdict changed |
| 4 | Make strippedRow and the golden check reject cases whose files or tests need docs/superpowers (evals/tiers/lib/cases.mjs), with a fixture test; decide manifest handling first | - | - | deferred | fix before any repetition 2; the repetition 1 manifest stays pinned, the fix lands with its rebuild |
| 5 | Before repetition 2, sandbox the runs and keep stream-json transcripts so an answer leak can be checked | - | - | deferred | fix before any repetition 2; no repetition 2 scheduled |
| 6 | classify records a timed-out run at cost 0, so the spend cap and cost per PASS undercount (evals/tiers/lib/claude.mjs) | - | - | deferred | deferred until a repetition 2 is scheduled; changed no repetition 1 result: no timeout row |
| 7 | An overloaded error after the run spent money is classed as a usage limit, against the spec's BLOCKED rule (evals/tiers/lib/claude.mjs LIMIT) | - | - | deferred | deferred until a repetition 2 is scheduled; changed no repetition 1 result: no NOT_RUN row |
| 8 | statusWord takes the first status word anywhere in the reply; anchor on Status: (evals/tiers/lib/grade.mjs) | - | - | deferred | deferred until a repetition 2 is scheduled; changed no repetition 1 result: all 114 implementation replies' first status word matches their Status: line |
| 9 | The drift guard does not see untracked files under plugins/dr-superpowers (evals/tiers/run-grid.mjs) | - | - | deferred | fix before any repetition 2; the plugin had no untracked files at ruling time |
| 10 | Repeat gradings are the first six reviews by name, both code reviews, so no plan review is graded twice (evals/tiers/run-grid.mjs) | - | - | deferred | fix before any repetition 2; grader consistency is measured on code reviews only, as the results note says |
| 11 | Grades are written before the results row, so a crash between the two duplicates grades (evals/tiers/grade-review.mjs) | - | - | deferred | deferred until a repetition 2 is scheduled; changed no repetition 1 result: no duplicated grade |
| 12 | A harness test fixture directory under /tmp leaks when a test throws at top level | - | - | deferred | cosmetic; leaks on a top-level throw, not on a late import as first recorded |
| 13 | w-darkmem-sync-client-t5 fails one pull.test.mjs assertion on every arm including the current one | - | - | deferred | kept in the pool as a real result; the case may be at fault |
| 14 | tests/ui-discovery.test.mjs fails on this host because no rg binary is on PATH | - | - | deferred | environmental, fails before and after this plan |
| 15 | plan-revise.test.sh:126 and :173 total-2 fixtures still name impl-sonnet-medium | - | - | deferred | ruling seat PARK at preflight: no assertion reads them; two one-word substitutions if wanted |
| 16 | ladder.test.sh implementer check keeps only the last non-implementer and has no blank-line guard | - | - | deferred | from the plan's patch; still fails loudly on a bad or empty block |
