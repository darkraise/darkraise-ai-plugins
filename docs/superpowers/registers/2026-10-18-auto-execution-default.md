# Auto execution as the default

**Source:** owner request in the 2026-10-18 brainstorming session
**Covers:** docs/superpowers/specs/2026-10-18-auto-execution-default-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | issue: force to write plan in new session | docs/superpowers/plans/2026-10-19-auto-execution-default.md | spec A6-A12: the plan is written in the spec's session and the cockpit switches in place at plan saved | doing | - |
| 2 | prefer parallel execution model, when planning, group tasks into 2 part: can parallel and cannot. Then based on the dependency of 2 group, decide the order of them. | docs/superpowers/plans/2026-10-19-auto-execution-default.md | spec A2, A13: executionStrategy defaults to parallel; writing-plans sorts alone and parallel tasks and orders waves by depth | doing | - |
| 3 | If development done, and only finish branch remaining, keep going instead of handoff | docs/superpowers/plans/2026-10-19-auto-execution-default.md | spec A14, A15: nothing hands off after the last task's complete line, attended or auto | doing | - |
| 4 | Polish the auto execution | docs/superpowers/plans/2026-10-19-auto-execution-default.md | spec A4, A5, A18, A19, A21: one spec review carries every open item and the finish choice; nothing is asked after it | doing | - |
| 5 | Stop asking approval for each section of spec. Instead, let write the spec then hand for reviewer | docs/superpowers/plans/2026-10-19-auto-execution-default.md | spec A3: under autoRun=on no design section is presented for approval | doing | - |
| 6 | To make the auto execution, I think that we should brainstorm, write spec and plan for all at once (not split into multiple planning phase or version), then while implementing, make appropriate adjustment id necessary. | docs/superpowers/plans/2026-10-19-auto-execution-default.md | spec A20: one spec and one plan per request, amended in place | doing | - |
| 7 | make the auto execution model the default execution | docs/superpowers/plans/2026-10-19-auto-execution-default.md | spec A1, A16, A17, A22: autoRun defaults to on; ask and off keep today's flows; Codex behaves as off | doing | - |
