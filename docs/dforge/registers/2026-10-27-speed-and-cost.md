# dforge speed and cost improvements

**Source:** docs/dforge/notes/2026-10-27-speed-and-cost-research.md (research of 2026-10-27: Anthropic and external sources, plugin survey, transcripts of 56 dforge sessions)
**Covers:** docs/dforge/specs/2026-10-27-speed-and-cost-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Implementers run targeted tests; the controller runs the full suite once through suite-run (58 of 98 implementer cache misses followed a wait on a long full-suite run) | - | - | open | - |
| 2 | Implementers background slow suites and wait for the completion notification instead of polling | - | - | open | - |
| 3 | Merge consecutive tasks that chain on each other's output and touch the same files into one implementer dispatch, with a commit per task | - | - | open | - |
| 4 | Evidence-bound findings: each judge finding cites a failing command or a quoted brief line, a fix round starts only for findings that reproduce, and the reviewer prompt says skip style | - | - | open | - |
| 5 | Extend task-step's mechanical checks to baseline test status at the base commit and symbol or test existence, so those cannot-verify items reach no seat | - | - | open | - |
| 6 | Diff-first, narrow judge search: specific questions, narrow grep, view only known ranges | - | - | open | - |
| 7 | Implementer prompt: add the anti-hardcoding, report-incorrect-tests and tests-are-immutable clauses to every tier, and the scope-limit clause to the Opus tiers | - | - | open | - |
| 8 | Brief as contract: machine-readable done-list and acceptance commands; the judge checks the brief's stated objective | - | - | open | - |
| 9 | Re-tune the score-to-effort table with a measured sweep | - | - | open | - |
| 10 | Parallel waves of 3-5 workers with disjoint files and shared decisions in the header; stagger same-type dispatches a few seconds so later ones read the first one's cache | - | - | open | - |
| 11 | Isolated replay eval of 20-50 tasks from real dforge failures reporting pass^k, using claude plugin eval cost and duration fields; the prerequisite for the measured items | - | - | open | - |
| 12 | Pilot only: trajectory-based escalation, and no judge for score 0-2 tasks | - | - | open | - |
| 13 | Plugin SubagentStop gate: block an implementer stop whose report lacks the required sections or a passing verified command (Claude Code 2.1.311+) | - | - | open | - |
| 14 | Split SKILL.md files over about 20 KB into references read at the step that needs them, and add a size test | - | - | open | - |
| 15 | Lean plans: decisions, signatures and test assertions instead of full code (overlaps token-efficiency row 14) | - | - | open | - |
| 16 | Run /doctor prompt-audit over skills, agents and references, then /skill-doctor, and set disable-model-invocation on skills only ever invoked by name | - | - | open | - |
| 17 | Review gating by diff size and risk, with a cheap pre-check | - | - | open | - |
| 18 | Document auto mode for unattended waves and worktree.baseRef head as user settings for wave worktrees | - | - | open | - |
