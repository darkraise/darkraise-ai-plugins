---
name: handoff
description: Use when a budget line says handoff, at a hard phase stop (plan saved, every plan task complete under subagent-driven-development, or a switch from inline to subagent mode), after 3 Codex tasks or a task that needed 3+ fix rounds, or when your human partner steps away or asks to stop - ends the session with durable handoff files and a resume guide
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
  and `scripts/context-size` — said `handoff`. Act at the next ledger write,
  never mid-dispatch: finish the step you are in, write the ledger line that
  records it, then hand off.
- A hard stop: the plan is saved; every plan task is complete under
  dr-superpowers:subagent-driven-development (the final whole-branch review
  runs in a fresh session); or a plan has just switched from inline to subagent
  mode. Under dr-superpowers:executing-plans the last task is a soft stop
  instead: the final review runs in the same session unless the budget line
  says `handoff`.
- On Codex: after every 3 completed tasks, or after any task that needed 3 or
  more fix rounds.
- Your human partner says they are stepping away for more than an hour, or
  asks you to stop.

## Steps

1. **Make the durable record current.**
   - Execution: the ledger's last line records where you are (a
     `Task N: complete`, a `fix round R/5`, or an assigned line). Update
     `<workspace>/handoff.md` (below); `<workspace>` is the directory
     `scripts/sdd-workspace PLAN_FILE` prints.
   - Design phase (brainstorming, a spec, a plan in progress): save the draft
     file. It is the authority.
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
4. **Run `scripts/next-step`**, from the plugin root (two levels above this
   skill's directory):
   - Execution: `scripts/next-step PLAN_FILE`.
   - Design phase: `scripts/next-step --draft DRAFT_FILE --next "<the next action, naming its skill>"`,
     for example `--next "Write the implementation plan with dr-superpowers:writing-plans."`
   It prints the `## Next session` block and writes it into `latest.md`. If it
   exits 4, say `latest.md` could not be written.
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

dr-superpowers:subagent-driven-development writes it at Setup and updates it
in the same message as a ledger write whenever one of these sections changes —
not after every task: task state lives in the ledger and git.

## Red Flags

| Thought | Reality |
|---------|---------|
| "One more dispatch, then I'll hand off" | The verdict is acted on at the next ledger write. Record the step you are in; start nothing new. |
| "The next session can read my summary" | It has none of your context. Only files cross the boundary. |
| "I'll write the resume prompt myself" | `next-step` computes it from the plan and ledger. Hand-written guides go stale. |
| "Compaction will take care of it" | Compaction drops reports, findings and rulings. Hand off before it fires. |
