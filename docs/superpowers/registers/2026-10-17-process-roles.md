# Process roles

**Source:** owner request 2026-10-17, "I want all 4", after the official-plugin role comparison
**Covers:** docs/superpowers/specs/2026-10-17-dr-forge-process-roles-design.md, docs/superpowers/specs/2026-10-19-deferred-rows-sweep-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Architecture critic on the spec | docs/superpowers/plans/2026-10-17-dr-forge-process-roles.md | spec A6, A8, A13 | done | - |
| 2 | QA as a separate seat that writes the acceptance tests | docs/superpowers/plans/2026-10-17-dr-forge-process-roles.md | spec A9, A10, A12, A13 | done | - |
| 3 | Specialist QC lenses that run only when they apply | docs/superpowers/plans/2026-10-17-dr-forge-process-roles.md | spec A1-A6 | done | includes per-language defect lenses chosen by diff file types; no language implementers (owner ruling 2026-10-17) |
| 4 | BA confidence and human verdicts | docs/superpowers/plans/2026-10-17-dr-forge-process-roles.md | spec A7, A8, A13 | done | - |
| 5 | Review minor 8: QA is not given the demo statements it must list | plugins/dr-forge/reference/final-review.md | tests/process-roles.test.sh demo pins | done | owner ruling 2026-10-17: QA no longer lists demo statements; final review counts <d> from the spec |
| 6 | Review minor 9: a QA failure the fix wave fixed still keeps the branch in an auto run (complete line is written before the fix wave) | plugins/dr-forge/reference/auto-run.md | tests/auto-run-skills.test.sh keep-branch pins | done | owner ruling 2026-10-17: merge keeps on cannot-test only; a surviving fail or flaky is a deferred A<n> row or a red finishing test |
| 7 | Cosmetic and edge minors left by the run: review minors 5, 6, 7, 10, 11, 13; Task 2 Result-cell detail; Task 10 QA recovery leaves uncommitted files and a partial report gets no cannot-test rows, step 0.5 not a list marker; Task 12 block placement and wrap width; Task 14 final-review.md wrap width and recovery bullet lacking the spent-re-dispatch exception; preflight-15 finishing lens list can differ from the report's | docs/superpowers/plans/2026-10-19-deferred-rows-sweep.md | the deferred rows sweep spec item for this row is fixed and its Check passes | done | cosmetic, plan-mandated or harmless; the run ledger is deleted at finish |
