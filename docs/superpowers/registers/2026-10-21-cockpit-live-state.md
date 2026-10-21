# Cockpit live state and layouts

**Source:** user request, 2026-10-21 session (four pasted items)
**Covers:** docs/superpowers/specs/2026-10-21-cockpit-live-state-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | When running codex or other shell, cli, the status of main agent is complete, not running or waiting, since the cli and shell run in background. Is there anyway to reflect the correct state of conversation? | docs/superpowers/plans/2026-10-21-cockpit-live-state.md | With a background shell running after a turn, the Now row and the box read ◐ background, and exactly one Done arrives after the continuation turn | done | - |
| 2 | Make the info on forge UI update immediately when config change or any of its data changed | docs/superpowers/plans/2026-10-21-cockpit-live-state.md | While the cockpit is visible, a setting changed outside the pane shows within 2 s and git state within 10 s; an idle tick redraws nothing | done | - |
| 3 | Add compact view for forge UI, which still show as side pane but compact the layout, section and info | docs/superpowers/plans/2026-10-21-cockpit-live-state.md | density: dense draws the docked pane as one line per section, and the toggle switches it | done | - |
| 4 | Minimize should render the forge UI at statusline position (below the promt input) | docs/superpowers/plans/2026-10-21-cockpit-live-state.md | Minimized on the terminal, nothing draws above the prompt and a framed box draws below it beside the mode label at 80 and 120 columns in every permission mode | done | - |
| 5 | Cockpit: a Done held by a long-running background process (dev server) waits to the 30-minute cap; decide whether that late Done is acceptable | in-chat ruling 2026-10-21 | A turn leaving only a service shell (npm run dev, --watch, tail -f) sends its Done at once; a service beside a held job releases with the job; other shells keep the 30-minute cap | done | Ruled: service shells hold nothing (isServiceCommand) |
| 6 | Cockpit: turn.start's text on a notification wake-up is unobserved; a wake-up turn carrying other text could drop the held Done | in-chat ruling 2026-10-21 | A task-notification prompt.submit keeps the held Done whatever its text; composer and plugin origins drop it | done | Ruled: chain decided by prompt.submit origin.kind per the engine's PromptOrigin, not turn.start text; isTypedPrompt removed |
| 7 | Cockpit: an external layout change leaves the pane unplaced | - | - | done | Fixed in cb0ecf7: the poll re-seats the pane for a layout saved outside it |
| 8 | Cockpit: PromptHint render hook does not call next | - | - | n/a | By design: minimized on the terminal the box takes the hint line's place and draws the hint into its bottom rule |
| 9 | Cockpit: a released Done has no answer excerpt | - | - | done | Fixed in 3f5e7e8: a grace or cap release carries the held turn's answer |
| 10 | Cockpit: stale shell rows now hold a Done | - | - | done | Bounded in 10aa6da: work already running past the 30-minute cap holds no Done |
| 11 | Cockpit live-state spec contradicts itself on auto-run prompts | - | - | n/a | The contradiction is in the historical spec, which stays as written |
| 12 | Cockpit: after an aborted main turn with a subagent still running, a later subagent approval ends in running with no main turn and blocks the auto-run watchdog until the subagent finishes | - | - | done | Already fixed by 90be54a; regression test in e1cea2a |
| 13 | Cockpit: shell drop at turn.complete sits after the spawn===undefined early return, so a subagent with no recorded spawn keeps its shell rows | - | - | done | Fixed in b733ad4 |
| 14 | Cockpit: no negative test that a main-conversation (agentId null) or legacy shell survives a subagent's turn.complete | - | - | done | Tests in dcbe10b |
| 15 | Cockpit lib.ts nowLine computes Math.min over an empty shells list (Infinity) before its count guard | - | - | done | Fixed in 26ff41b |
| 16 | Cockpit: a command whose first line is blank gives an empty excerpt and a stray separator in the background row; untested | - | - | done | Fixed in a2ddfa5, in the shells card too |
| 17 | Cockpit: isTypedPrompt has no test for a task-notification block that follows other text | - | - | n/a | Moot: isTypedPrompt removed by the row 6 ruling |
| 18 | Cockpit: readRun's summary-equality early return skips sendLedgerEvents' first seeding call if the run atom outlives module state; a test preloading an equal run atom would settle whether atoms persist | - | - | done | Fixed by 8f704d1: ledger events are seeded on an unchanged run |
| 19 | Cockpit: a plan file appearing after the ledger was read is not noticed until the ledger mtime changes | - | - | done | Fixed in 66348ac: a plan not found yet is looked for at every read |
| 20 | Cockpit: no test covers the S.runKey reset at session start, the plan-mtime part of the key, or the summary-equality guard alone | - | - | done | Tests in 6e9c027 |
| 21 | Cockpit denseLine: account row ends in a bare 'Remote ' label when remote is an empty array | - | - | done | Fixed in e51cbb0 |
| 22 | Cockpit denseLine: the ⎇ label relies on padEnd(5) counting one cell for U+2387 | - | - | done | Fixed in 5f2250e: dense labels pad by cell width |
| 23 | Cockpit dense tests assert no colour or dim attributes and skip the turnsLeft boundary and the > 0 and plan.total === 0 branches | - | - | done | Tests in 8f5837e |
| 24 | Cockpit: no test for an unknown density value reading as detailed, nor for the dense Hand off and Stop auto buttons | - | - | done | Tests in bd437b0 |
| 25 | Cockpit bottomRule at width < 2 returns a 2-cell rule, breaking 'exactly width cells' | - | - | done | Fixed in e18d430 |
| 26 | Cockpit: no test for bottomRule widths below 10 (the room < 4 boundary) | - | - | done | Tests in 17bd0b6 |
| 27 | Cockpit: watchdogTick returns while any shell runs, so a dev server left running blocks the auto-run stall nudge | - | - | done | Fixed by 7dc4ce5: the watchdog ignores service shells |
