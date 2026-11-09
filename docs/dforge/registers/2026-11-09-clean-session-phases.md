# Clean-session phases

**Source:** the owner's answer on 2026-11-09 naming the three token-saving changes to apply
**Covers:** -

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Run finish and CI in a clean session, since that phase cost 2.2M tokens at about 307k context per turn. | - | - | open | - |
| 2 | Stop judges from re-reading the whole diff. They cost about 3.6M, and the 125KB final diff was read 10 times. | - | - | open | - |
| 3 | Start a fresh session after the plan is approved. | - | - | open | - |
