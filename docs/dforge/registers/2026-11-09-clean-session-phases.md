# Clean-session phases

**Source:** the owner's answer on 2026-11-09 naming the three token-saving changes to apply
**Covers:** docs/dforge/specs/2026-11-09-clean-session-phases-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Run finish and CI in a clean session, since that phase cost 2.2M tokens at about 307k context per turn. | docs/dforge/plans/2026-11-09-clean-session-phases.md | A5-A7, A11, A15 | planned | - |
| 2 | Stop judges from re-reading the whole diff. They cost about 3.6M, and the 125KB final diff was read 10 times. | docs/dforge/plans/2026-11-09-clean-session-phases.md | A8-A10, A14 | planned | - |
| 3 | Start a fresh session after the plan is approved. | docs/dforge/plans/2026-11-09-clean-session-phases.md | A1-A4, A13 | planned | - |
