# r-plan-project-state

Source: the calibration record `docs/superpowers/notes/2026-09-20-review-routing-calibration.md`, sections "Known defects (Step 5) — performed for the first time" and "One Critical verified against shipped code"; each confirmed in the plan at `d6c288c`.

## D1: a test helper is defined in one task and used only by a later one

- Where: Task 3 (defines `absent()` in `tests/gates-manifest.test.sh`) and Task 11 (the only caller); the header's Contracts
- Defect: `absent` is a cross-task interface, but Contracts does not list it, so the Task 11 implementer, who sees only that task and the header, calls a helper it cannot see or verify, and the Task 3 implementer is asked to write a helper nothing in its own task uses.
- Evidence: calibration record, "Cross-task helper"; `absent()` is at plan line 539 (Task 3) and its one use at line 1802 (Task 11).
- Minimum severity: Important

## D2: structural tests accept a keyword instead of checking the guarantee

- Where: Task 1 (`"CLAUDE.md"`, `"optional"`), Task 3 (`'seven'`, `'exit 0'`), Task 5 (`'squash'`)
- Defect: several `present` assertions search a skill file for one common word, so a stub containing the word passes without the behaviour the assertion's name claims. The Task 5 assertion named "never squashed" passes on a file that tells the reader to squash.
- Evidence: calibration record, "Vacuous needles"; the assertions are at plan lines 178, 180, 556, 564 and 997.
- Minimum severity: Important

## D3: the skill runs repo-audit from the plugin root, which audits the wrong repository

- Where: Task 2, the project-status skill, "Orient in one call"
- Defect: the skill text says to run `scripts/repo-audit` from the plugin root, but the script derives the repository from its working directory (`git rev-parse --show-toplevel`), so an installed plugin audits the plugin's own checkout or fails outside a repository.
- Evidence: calibration record, "One Critical verified against shipped code", confirmed against `scripts/repo-audit:15`; the instruction is at plan line 374.
- Minimum severity: Critical
