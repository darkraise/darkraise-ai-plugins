---
name: handoff
description: Use when a budget line says handoff, at a hard phase stop (plan saved, or a switch from inline to subagent mode), on Codex after 3 tasks or a task that needed 3+ fix rounds, or when your human partner steps away or asks to stop - ends the session with durable handoff files and a resume guide
---

# Handoff

End this session so a fresh one continues without loss. Past its budget a
session re-reads its whole context on every request, and near the auto-compact
point compaction drops the reports, findings and rulings a controller needs.
A fresh session reloads only its baseline plus these files. The numbers are in
[session-budget.md](../../reference/session-budget.md).

**Announce at start:** "I'm using the handoff skill to end this session cleanly."

## When

- A budget line — printed by `scripts/task-brief`, `scripts/review-package`
  and `scripts/context-size` — said `handoff`. Finish the task in flight
  through its `Task N: complete` line, then hand off; start no new task. The
  budget leaves room for one task to finish.
- A hard stop: the plan is saved, or a plan has just switched from inline to
  subagent mode. The last task completing is a soft stop in both execution
  modes: the final review runs in the same session unless the budget line says
  `handoff`.
- On Codex: after every 3 completed tasks, or after any task that needed 3 or
  more fix rounds.
- Your human partner says they are stepping away for more than an hour, or
  asks you to stop.

## Steps

1. **Make the durable record current.**
   - Execution: the ledger's last line records where you are (a
     `Task N: complete`, a fix-round line, or an assigned line). Update
     `<workspace>/handoff.md` (below); `<workspace>` is the directory
     `scripts/sdd-workspace PLAN_FILE` prints.
   - Design phase (brainstorming, a spec, a plan in progress): save the draft
     file. It is the authority.
   - Unplanned work (a change designed in chat, or a punch list, with no plan
     or draft file): the notes in `latest.md` are the authority, so step 3's
     `State` must carry every item.
2. **Commit the plan and the spec** if either has uncommitted changes, in a
   `docs(<scope>): …` commit of their own. Never commit `.superpowers/`.
3. **Write the notes sections of `latest.md`** at
   `<primary checkout>/.superpowers/handoff/latest.md`. The primary checkout is
   `git -C "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" rev-parse --show-toplevel`.
   Replace everything above `## Next session` with exactly these sections,
   each under 15 lines:

   ```markdown
   # Handoff — <YYYY-MM-DD> (<budget | phase stop | Codex count | owner request>)

   ## State
   - Worktree: `<absolute worktree path>` (branch `<branch>`, HEAD `<sha7>`)
   - Plan: `<plan path>`; ledger: `<workspace>/progress.md`; handoff: `<workspace>/handoff.md`
   - <one line on where the work stands>

   ## Gotchas
   - <what the next session would otherwise rediscover>

   ## Do not
   - <owner constraints and prohibitions>
   ```

   In a design phase, `State` names the draft instead of a plan and ledger.
   For unplanned work, `State` lists each item with its state: implemented
   and uncommitted, committed, awaiting feedback (with the link), or
   unscoped.
4. **Run `scripts/next-step`** (see using-superpowers §Session Budget):
   - Execution: `scripts/next-step PLAN_FILE`.
   - Design phase: `scripts/next-step --draft DRAFT_FILE --next "<the next action, naming its skill>"`,
     for example `--next "Write the implementation plan with dr-superpowers:writing-plans."`
   - Unplanned work: `scripts/next-step --adhoc --phase <design|build> --next "<the next action, naming its skill>"`.
     The phase is `design` when the next action, or any item the next
     session may pick up, is unscoped or awaits a design decision or
     feedback; otherwise `build`.
   It prints the `## Next session` block and writes it into `latest.md`. If it
   exits 4, say `latest.md` could not be written.

   On Codex, add `--host codex` to the design-phase and unplanned-work calls,
   so the block names the Codex client rather than Claude. A plan states its
   own host in its header, so the execution call needs no flag.
5. **End the session.** Your final message is one line on why you stopped,
   then the block, verbatim, as the last thing. The block is the resume guide:
   the launch command, the directory to launch it in, and the first prompt.

## handoff.md

`<workspace>/handoff.md` holds what the ledger cannot, in under 40 lines:

```markdown
# Handoff notes — <plan path>

## Owner constraints
- <a constraint your human partner gave during execution, verbatim>

## Gotchas
- <a tooling or environment surprise and its workaround>

## Do not
- <a prohibition>

## Open questions
- <a question for your human partner, and what you assumed meanwhile>
```

Both execution skills write it at Setup and update it in the same message as
a ledger write whenever one of these sections changes — not after every task:
task state lives in the ledger and git.

## Red Flags

| Thought | Reality |
|---------|---------|
| "One more task, then I'll hand off" | Finish the task in flight; start no new one. |
| "The line says 89% — I'll hand off now to be safe" | `ok` means continue. Only a `handoff` verdict or a hard stop ends the session; the budget already holds a task's margin. |
| "The next session can read my summary" | It has none of your context. Only files cross the boundary. |
| "I'll write the resume prompt myself" | `next-step` computes it from the plan and ledger. Hand-written guides go stale. |
| "There is no plan, so I'll write the block myself" | Use `next-step --adhoc`. A hand-written launch command guesses the model. |
| "Compaction will take care of it" | Compaction drops reports, findings and rulings. Hand off before it fires. |
