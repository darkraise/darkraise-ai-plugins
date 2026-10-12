# Auto run smoke check

Settles the platform facts the auto-run design inferred
(`docs/superpowers/specs/2026-10-13-dr-forge-auto-run-design.md`, Platform
facts) and closes register rows 5, 8 and 9 of
`docs/superpowers/registers/2026-10-12-auto-execution.md`. It needs a person:
the session under test must run this branch's dr-forge build.

## Setup

1. A scratch repository with a committed toy spec and a three-task plan whose
   tasks each add one small file with a test, and whose Execution line names
   `subagent`.
2. Start Claude Code in it on this branch's dr-forge build, with
   `DR_FORGE_BUDGET=60000` in the environment and `autoCompactWindow` at
   800,000, so the first task brief already says `compact`.
3. In the session: `bash <plugin-root>/scripts/auto-run start --spec <spec>`,
   then `attach --plan <plan>` and `phase execute`, then ask it to execute the
   plan with dr-forge:subagent-driven-development.

## Observe

| # | What to observe | Expected | Observed (date, result) |
|---|---|---|---|
| 1 | The task brief's last line | `budget (auto): …k of 60k … — compact` | |
| 2 | The turn's last line after the task completes | `Auto run: compacting`, and the Stop hook lets it end | |
| 3 | The cockpit compacts on its own | a compaction, then a prompt naming `auto-run after-compact` | |
| 4 | The compaction snapshot | the SessionStart `compact` snapshot is in context after the cockpit's compaction | |
| 5 | `auto-run after-compact` | `continue — …k after compaction; regime …` | |
| 6 | A self-resume by hand: run `scripts/next-step <plan>`, then `scripts/auto-run clear`, and end a turn with `Auto run: clearing` | the cockpit runs `/clear`, then `/model` and `/effort` from the launch line, then submits the first prompt | |
| 7 | In the cleared session, `echo $CLAUDE_CODE_SESSION_ID` | the cleared session's own id, equal to the run's `session` after `rebind` | |
| 8 | In the cleared session, the SessionStart `clear` hook | a fresh record under `~/.claude/dr-forge/sessions/by-id/` for the new id | |
| 9 | The plan finishes | final review, then finishing by `finishAction`, no question asked | |
| 10 | Over the whole run | at least two cockpit compactions (`auto-run status` counts them) | |
| 11 | Right after a cockpit compaction, the pane's Context card | `no reading yet`, then a fresh figure: shows whether the cockpit's own `session.compact` hook ran for its own call | |
| 12 | A self-resume driven by the run itself: set `autoCompactWindow` to 100,000 for one session so a compaction leaves 85% of it | `after-compact` prints `handoff`, the model hands off, runs `auto-run clear` and the cockpit resumes as in row 6 | |

## Afterwards

Fill the Observed column. When every row matches, set rows 5, 8 and 9 of the
register to `done`. A row that does not match is a bug against the design:
file it as a new register row before anything is changed.
