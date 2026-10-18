# Run order, finish, controller and desktop

**Source:** owner request in the 2026-10-17 brainstorming session
**Covers:** docs/superpowers/specs/2026-10-17-finish-without-wait-design.md, docs/superpowers/specs/2026-10-17-cockpit-native-desktop-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Run section: auto move done item to the bottom of list, push running and not started items to the top of list | commit 8cff656 | runList orders in flight, blocked, not started, done (plan order within each) on the terminal card and desktop panel; cockpit tests 'lists running, blocked and pending tasks before done ones' and 'replaces the plan card' | done | - |
| 2 | If user select the approach for finishing development when writting plan, auto use that to finish the devemopment, no need to ask and wait after done all tasks. | docs/superpowers/plans/2026-10-17-finish-without-wait.md | spec A1-A12: a recorded merge/pr/keep runs at once with no menu; the timer, finishTimeout and the countdown are gone | planned | - |
| 3 | Evaluate to use opus low/medium as controller instead of sonnet high, since I see that in claude code cloud, it always use opus low/medium as controller. | docs/superpowers/notes/2026-10-17-controller-model-eval.md | evaluation note recommends keep, switch or pilot; owner decides | doing | recommends keeping Sonnet high pending a pilot: Opus 5.5 is 2x Sonnet 5.5 per token, est. +$4/plan at low; pilot awaits owner |
| 4 | Analyze the nested sessions architecture of claude code desktop, to see if we can adapt anything | docs/superpowers/notes/2026-10-17-desktop-nested-sessions.md | note maps the desktop session model onto dforge and ranks adoption candidates | done | no plugin-drivable nesting API; ranks 1-2 (wave tasks grouped by state, other sessions list) feed item 5 |
| 5 | Improve UI with collapsible section and enhance the UI, comtibility with claude code desktop app | docs/superpowers/plans/2026-10-17-cockpit-native-desktop.md | spec A1-A13: sections collapse from their titles on both surfaces; desktop panels, band and settings use native text, theme colors and controls; Agents groups subagents by state; A10-A11 demos in the desktop app | planned | - |
