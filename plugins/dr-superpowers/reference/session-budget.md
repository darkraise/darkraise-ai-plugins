# Session budget

The numbers and rules behind dr-superpowers' handoffs. The cost model they rest
on is §3 of the program design
(`docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`).

## Numbers

| Item | Value | Source |
|------|-------|--------|
| Handoff budget | 475,000 tokens; `DR_SUPERPOWERS_BUDGET` overrides | Owner ruling, 2026-09-11 |
| `autoCompactWindow` | 650,000, in `~/.claude/settings.json` | Set 2026-09-11 |
| Where auto-compaction fires | About 93-96% of the window: 467k, 467k and 479k observed at 500,000 | Inference from three transcripts |
| Hook output cap | 10,000 characters; longer output becomes a file reference | Claude Code hooks reference |
| Skill bodies after compaction | First 5,000 tokens per skill, 25,000 in total, oldest dropped | Claude Code context-window docs |
| Codex | Hand off every 3 tasks, or after a task that needed 3+ fix rounds | Program design R7 |

The budget has to sit below the point where compaction fires by more than one
task's growth — a controller adds about 140k across a long fix loop. At a
650,000 window compaction lands near 605-625k, so 475k leaves that margin.

## The budget line

```
budget: 312k of 475k (65%) — ok — source: record
budget: 480k of 475k (101%) — handoff — source: record
budget: unknown of 475k — unknown — no transcript found
```

`source` is `record` (the SessionStart hook's session record), `record?` (a
newer transcript exists in the same directory: two sessions may share it) or
`guessed` (no record; the newest transcript for the directory). `unknown` means
apply the count rule on Codex and the phase stops everywhere.

`scripts/task-brief` and `scripts/review-package` print it as their last line,
so checking before every task and every review costs no extra request.
`scripts/context-size` prints it on demand (exit 0 ok, 5 handoff, 3 unknown);
`scripts/repo-audit` includes it.

## Checkpoints

- **subagent-driven-development:** every `task-brief` and `review-package`. On
  `handoff`, act at the next ledger write.
- **executing-plans:** `context-size` after each `Task N: complete` line.
- **brainstorming:** `context-size` once, after the spec is committed.
- **Anywhere:** `context-size` when in doubt.

## Stops

- **Hard:** the plan is saved; every plan task is complete under
  subagent-driven-development (the final review runs in a fresh session).
  The plan-saved stop is not yet wired into `writing-plans` — invoking
  dr-superpowers:handoff there is a follow-up, not part of this release.
- **Soft:** the final review is clean; executing-plans' last task is complete.
  Finishing follows in the same session unless the budget line says `handoff`.
- **Budget:** a `handoff` verdict at any checkpoint.
- **Codex:** the count rule above.

Every stop runs dr-superpowers:handoff.

## Idle

After more than an hour idle the one-hour prompt cache is cold: the next
request re-writes the whole context at twice the input price. Start a fresh
session from `latest.md` rather than continuing (Claude Code also offers
"Resume from summary" in that case), and hand off before a planned break.

## After compaction

The SessionStart hook appends a compaction snapshot (`scripts/lib/snapshot.sh`):
the handoff's next step, ledger tails and rulings, the files the session
edited, the owner's last three prompts and background agent ids. Trust it, the
ledger and `git log` over the summary. The long execution skills open with an
"After compaction" block because only their first 5,000 tokens come back.

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
