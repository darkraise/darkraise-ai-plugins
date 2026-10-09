# Session budget

The numbers and rules behind dr-superpowers' handoffs. The cost model they rest
on is §3 of the program design
(`docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`).

The goal is a finished plan. The budget only keeps a session clear of
auto-compaction: a session stops for a `handoff` verdict or a hard stop below,
never earlier.

## Numbers

| Item | Value | Source |
|------|-------|--------|
| Handoff budget | The compaction point minus 140,000: min(`autoCompactWindow`, model window) × 93% − 140,000, so 465k at a 650,000 window; `DR_SUPERPOWERS_BUDGET` overrides | Owner ruling, 2026-09-19 |
| Final-phase limit | 85% of min(`autoCompactWindow`, model window): 553k at a 650,000 window, 680k at 800,000; `DR_SUPERPOWERS_BUDGET` does not move it | Owner ruling, 2026-10-02 |
| Model window | 1,000,000 for Fable 5.1, Opus 5.5 and Sonnet 5.5; 200,000 for Haiku 4.5 | Claude API model table, cached 2026-06-24; Opus 5.5 from its launch notes; Sonnet 5.5 from the model table and a CLI probe, 2026-09-29 |
| `autoCompactWindow` | 800,000 with `DR_SUPERPOWERS_BUDGET` pinned at 465,000, in `~/.claude/settings.json` (650,000 before) | Set 2026-09-11; raised 2026-10-02 |
| Where auto-compaction fires | About 93-96% of the window: 467k, 467k and 479k observed at 500,000 | Inference from three transcripts |
| Hook output cap | 10,000 characters; longer output becomes a file reference | Claude Code hooks reference |
| Skill bodies after compaction | First 5,000 tokens per skill, 25,000 in total, oldest dropped | Claude Code context-window docs |
| Codex | Hand off every 3 tasks, or after a task that needed 3+ fix rounds | Program design R7; the measured line does not override it |

The budget sits below the point where compaction fires by one task's worst
growth — a controller adds about 140k across a long fix loop — so a task that
starts under budget always finishes before compaction. `scripts/lib/context.sh`
reads `autoCompactWindow` from `settings.json` and the model from the
transcript, so the budget follows either when they change.

## The budget line

```
budget: 312k of 465k (67%) — ok — source: record
budget: 470k of 465k (101%) — handoff — source: record
budget: unknown of 465k — unknown — no transcript found
```

On a Codex host the line reports a measured number and no verdict:

```
budget: 187k measured — unknown — source: rollout
budget: unknown — unknown — no usage entry in <path>
```

`source: rollout` is the session's own Codex rollout, found under
`${CODEX_HOME:-~/.codex}/sessions` by its recorded working directory. Only an
interactive rollout counts: an executor-lane run started by a Claude controller
records that controller's directory, so selecting it would replace a live Claude
session's verdict. Where a Claude transcript and a rollout both match, the more
recently written one is the live session.

The verdict stays `unknown` because no Codex budget has been set yet, so the
count rule below still decides when a Codex session hands off.
`DR_SUPERPOWERS_BUDGET` does not apply to a rollout measurement.

Each Codex measurement appends a row to
`<primary checkout>/.superpowers/sdd/budget-log.tsv`, and
`scripts/context-size --observations` prints it back as the growth between
consecutive task briefs within each session, followed by one `span` line per
session (`<session>  span  40k -> 31k`) — the data a later phase needs to set the
budget. A negative delta is a compaction, reported as `compacted` rather than a
number.

`source` is `record` (the SessionStart hook's session record, this session's
own when `CLAUDE_CODE_SESSION_ID` is set, else the directory's), `record?` (the
directory's record, and a newer transcript exists in the same directory or the
record names another session: two sessions may share it) or
`guessed` (no record; the newest transcript for the directory) or, on a Codex
host, `rollout` (the session's own rollout file). `unknown` means
apply the count rule on Codex and the phase stops everywhere.

`scripts/task-brief` and `scripts/review-package` print it as their last line,
so checking before every task and every review costs no extra request.
`scripts/context-size` prints it on demand (exit 0 ok, 5 handoff, 3 unknown);
`scripts/repo-audit` includes it. Only the verdict matters: a high percentage
under `ok` is not a reason to stop.

## Checkpoints

- **subagent-driven-development:** every `task-brief` and `review-package`
  until the last task completes; then `context-size --final` after the last
  `Task N: complete` line and again before finishing.
- **executing-plans:** the budget line on every `task-brief`; then
  `context-size --final` after the last `Task N: complete` line and again
  before finishing.
- **Acting on `handoff`:** finish the task in flight through its
  `Task N: complete` line, then hand off. Start no new task.
- **brainstorming:** `context-size` once, after the spec is committed.
- **Anywhere:** `context-size` when in doubt.

## Stops

- **Hard:** the plan is saved; a plan switches from inline to subagent mode.
  Both launch the execution model the Execution line names. writing-plans runs
  dr-superpowers:handoff once the plan is reviewed.
- **Soft:** the last task is complete, in either mode; the final review is
  clean. The final review and finishing follow in the same session unless
  `context-size --final` says `handoff`. The final phase - the final review,
  its one fix wave, the scoped re-review and finishing - grows far less than a
  task's fix loop, so it is measured against the final-phase limit, and a task
  budget line saying `handoff` inside it does not stop it.
- **Budget:** a `handoff` verdict at any checkpoint.
- **Codex:** the count rule above.

Every stop runs dr-superpowers:handoff.

## A larger compaction window with the same task budget

To give the final phase more room without lengthening task sessions, raise
`autoCompactWindow` and pin the task budget, in the active `settings.json`:

```json
{
  "autoCompactWindow": 800000,
  "env": { "DR_SUPERPOWERS_BUDGET": "465000" }
}
```

Tasks then still hand off at 465k, the final phase continues below 680k, and
compaction fires at about 744k.

## Idle

After more than an hour idle the one-hour prompt cache is cold: the next
request re-writes the whole context at twice the input price. Start a fresh
session from `latest.md` rather than continuing (Claude Code also offers
"Resume from summary" in that case), and hand off before a planned break.

## After compaction

The SessionStart hook appends a compaction snapshot (`scripts/lib/snapshot.sh`):
the handoff's next step, ledger tails and rulings, the files the session
edited, the owner's last three prompts and background agent and command ids.
Trust it, the ledger and `git log` over the summary. The long execution skills
open with an "After compaction" block because only their first 5,000 tokens
come back.

## Compact Instructions for CLAUDE.md

Claude Code re-reads the project-root CLAUDE.md after compaction and uses a
"Compact Instructions" section to shape the summary. Paste this into it:

```markdown
# Compact instructions

Preserve verbatim: the worktree path; the plan, ledger and handoff paths; the
current HEAD; every owner constraint and prohibition; every `Ruling:` line; and
every open question. Name the task in progress and its fix round.
```

`scripts/repo-audit` reports whether the section is present.
