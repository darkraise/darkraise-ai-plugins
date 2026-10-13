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
| 1 | The task brief's last line | `budget (auto): …k of 60k … — compact` | 2026-10-13, match: `budget (auto): 62k of 60k (103%) — compact — source: record` |
| 2 | The turn's last line after the task completes | `Auto run: compacting`, and the Stop hook lets it end | 2026-10-13, match: turns ended on `Auto run: compacting` and the Stop hook let them end |
| 3 | The cockpit compacts on its own | a compaction, then a prompt naming `auto-run after-compact` | 2026-10-13, match: the cockpit compacted on its own and submitted `Continue the auto run: run … auto-run after-compact first …` |
| 4 | The compaction snapshot | the SessionStart `compact` snapshot is in context after the cockpit's compaction | 2026-10-13, match: the transcript holds the `SessionStart:compact` hook after the cockpit's compaction |
| 5 | `auto-run after-compact` | `continue — …k after compaction; regime …` | 2026-10-13, match: `continue — 23k after compaction; regime normal` |
| 6 | A self-resume by hand: run `scripts/next-step <plan>`, which writes `<state>/handoff/latest.md` with its launch and first-prompt blocks (`scripts/auto-run clear` reads them and exits 1 without), then `scripts/auto-run clear`, and end a turn with `Auto run: clearing` | the cockpit runs `/clear`, then `/model` and `/effort` from the launch line, then submits the first prompt | 2026-10-13, match, through row 12's run-driven path rather than by hand: `/clear`, `/model sonnet`, `/effort high`, then the handoff's first prompt. Side effect: `/model` saved `sonnet` as the user's default model in settings.json (new register row) |
| 7 | In the cleared session, `echo $CLAUDE_CODE_SESSION_ID`, and the `session` field of `<state>/sdd/auto-run.json` in the primary checkout (`status` does not print it) | the cleared session's own id, equal to the run's `session` after `rebind` | 2026-10-13, match: the cleared session's transcript id `f9cd7dc9…` equals the run's `session` after `rebind` |
| 8 | In the cleared session, the SessionStart `clear` hook | a fresh record under `~/.claude/dr-forge/sessions/by-id/` for the new id | 2026-10-13, match: `~/.claude/dr-forge/sessions/by-id/f9cd7dc9-….json` written for the cleared session |
| 9 | The plan finishes | final review, then finishing by `finishAction`, no question asked | 2026-10-13, match: final review clean (judge-opus), `finishAction` `ask` kept the branch, no AskUserQuestion in either run |
| 10 | Over the whole run | at least two cockpit compactions (`auto-run status` counts them) | 2026-10-13, match: 4 cockpit compactions in the first run, 3 in the second |
| 11 | Right after a cockpit compaction, the pane's Context card | `no reading yet`, then a fresh figure: shows whether the cockpit's own `session.compact` hook ran for its own call | 2026-10-13, match: `no reading yet` 1–3 s after the compaction, then `107% of handoff` by 6 s |
| 12 | A self-resume driven by the run itself: set `autoCompactWindow` to 100,000 for one session so a compaction leaves 85% of it | `after-compact` prints `handoff`, the model hands off, runs `auto-run clear` and the cockpit resumes as in row 6 | 2026-10-13, match with a staged reading: the scripts read autoCompactWindow from the user settings only, so the 85% reading was staged by setting `pending` to `handoff` as the compaction was booked; `after-compact` printed `handoff`, the model handed off, ran `auto-run clear`, and the cockpit resumed as in row 6. The threshold itself is covered by tests/context-size.test.sh |

## Afterwards

Fill the Observed column. Register row 5 (compact at the budget) rests on rows
1, 2, 3, 5 and 10 here, row 8 (the compaction loop until finish) on rows 2, 3,
9 and 10, and row 9 (a compaction that leaves 85% of the window hands off) on
rows 6, 7, 8 and 12. When every row a register row rests on matches, set it to
`done`. A row that does not match is a bug against the design: file it as a new
register row before anything is changed.

## Run notes (2026-10-13)

Driven from tmux on this branch's build: one run of the three-task plan, then
a two-task plan for rows 6-8, 11 and 12. With `DR_FORGE_BUDGET=60000` a reload
after each compaction already exceeds the budget, so every budget line said
`compact` straight after a compaction. The model ruled to run the next task
first each time, and both plans finished. The budget is a test setting: at the
derived budget a compaction leaves far more headroom. In the second run the
session entered a native worktree, and its first budget line measured a guessed
transcript.

