# Cockpit live state and layouts

**Source:** user request, 2026-10-21 session (four pasted items)
**Covers:** docs/superpowers/specs/2026-10-21-cockpit-live-state-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | When running codex or other shell, cli, the status of main agent is complete, not running or waiting, since the cli and shell run in background. Is there anyway to reflect the correct state of conversation? | docs/superpowers/plans/2026-10-21-cockpit-live-state.md | With a background shell running after a turn, the Now row and the box read ◐ background, and exactly one Done arrives after the continuation turn | planned | - |
| 2 | Make the info on forge UI update immediately when config change or any of its data changed | docs/superpowers/plans/2026-10-21-cockpit-live-state.md | While the cockpit is visible, a setting changed outside the pane shows within 2 s and git state within 10 s; an idle tick redraws nothing | planned | - |
| 3 | Add compact view for forge UI, which still show as side pane but compact the layout, section and info | docs/superpowers/plans/2026-10-21-cockpit-live-state.md | density: dense draws the docked pane as one line per section, and the toggle switches it | planned | - |
| 4 | Minimize should render the forge UI at statusline position (below the promt input) | docs/superpowers/plans/2026-10-21-cockpit-live-state.md | Minimized on the terminal, nothing draws above the prompt and a framed box draws below it beside the mode label at 80 and 120 columns in every permission mode | planned | - |
