# Acceptance QA probe — 2026-10-17

Brief: `plugins/dr-forge/reference/acceptance-qa.md` at f3b7d25.
Seat: dr-superpowers:impl-sonnet-high, twice, fresh each time.
Statements: register check without a Covers line (A1), never "0 errors" (A2, neg).

| Run | A1 | A2 | A2 mutation |
|---|---|---|---|
| clean | pass | pass | red |
| seeded (Covers check blanked at scripts/register:54-55) | fail | fail | n/a |

Verdict: the riskiest assumption held. A seat that had not read the plan wrote tests from the spec text alone; they passed on the correct code, the A2 mutation turned them red, and both failed on the seeded defect with the observed output (`register: 0 errors`, exit 0) recorded. The main worktree was unchanged after each run.

Observations:
- Duration: about 44 seconds (clean) and 34 seconds (seeded) of seat time, far under the 45-minute bound Task 10 sets for QA.
- The seeded report put detail inside the Result cell (`fail (got register: 0 errors, exit 0; reproduced on re-run)`) where the brief's enumeration allows only the bare value. A reader parsing the Result column by exact value would miss it.
- On the clean run the A1 test also went red under the A2 mutation; the seat noted it.
