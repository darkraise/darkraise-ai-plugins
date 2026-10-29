---
name: handoff
description: Use when a budget line says handoff, at a hard phase stop (plan saved outside an auto run, except a light plan of 1-3 tasks with room to continue, or a switch from inline to subagent mode), on Codex after 3 tasks or a task that needed 3+ fix rounds, or when your human partner steps away or asks to stop - ends the session with durable handoff files and a resume guide
---

# Handoff

End this session so a fresh one continues without loss. Past its budget a
session re-reads its whole context on every request, and near the auto-compact
point compaction drops the reports, findings and rulings a controller needs.
A fresh session reloads only its baseline plus these files. The numbers are in
[session-budget.md](../../reference/session-budget.md).

**Announce at start:** "I'm using the handoff skill to end this session
cleanly."

## When

- A budget line — printed by `scripts/task-brief`, `scripts/review-package`
  and `scripts/context-size` — said `handoff`. Finish the task in flight
  through its `Task N: complete` line, then hand off; start no new task. The
  budget leaves room for one task to finish.
- A hard stop: the plan is saved outside an auto run, or a plan has just
  switched from inline to subagent mode. A saved plan at depth light is a stop
  only when it has 4 or more tasks, or when `scripts/context-size` does not
  say `ok` after steps 0-4 (dforge:writing-plans §Execution Handoff): a light
  plan of 1-3 tasks runs steps 0-4 and continues in this session.
  The last task completing is never a stop in either execution mode: the
  final review and finishing run in the same session whatever
  `scripts/context-size --final` prints. A task budget line printed during
  that final phase does not stop it, and nothing stops finishing once the
  final review is clean. In strict mode the plan's last two tasks never hand
  off either: their budget lines say `ok` past the budget.
- On Codex: after every 3 completed tasks, or after any task that needed 3 or
  more fix rounds. The budget line there reports a measured number with an
  `unknown` verdict, and the measured number does not override it.
- An auto run ([auto-run.md](../../reference/auto-run.md)) hands off for
  a compaction that left too much. A saved plan switches in place instead
  (auto-run.md §The switch): only steps 0-3 below run, and the session does
  not end. On a handoff the steps below run as always, but the turn does not
  end on the next-step block: return to the step that invoked this skill,
  which runs `scripts/auto-run clear` and ends the turn (auto-run.md §Clears).
  This skill never runs `scripts/auto-run clear` itself. A switch from inline
  to subagent mode hands off too, and the step that invoked this skill runs
  `scripts/auto-run clear --phase` (dforge:executing-plans §Switching to
  subagent mode).
- Your human partner says they are stepping away for more than an hour, or
  asks you to stop. Reconcile live children first, exactly as step 0 says:
  wait for them, or stop them and record a Ruling. Tell your partner which you
  did.

## Steps

0. **Nothing you started is still running.** On Claude Code run
   `scripts/in-flight`: it lists every background shell and agent this session
   launched that is still running, including an agent that sent its report
   (`DONE`, `DONE_WITH_CONCERNS`, …) but left a shell or agent of its own
   alive, which Claude Code keeps listing. A report is not the end of the
   launch; the list is. Exit 0 means nothing is running; exit 3 means it could
   not read this session, so list them by hand (`list_agents` on Codex, or the
   launch ids in your transcript). `scripts/next-step` runs the same check and
   prints no block while anything is listed. For each one, either wait for it,
   or stop it:
   - Wait: on Claude Code, end the turn without the block; its notification
     starts the next turn, and you resume here. On Codex, `wait_agent` in
     bounded stretches, since completion mail does not wake an idle session.
   - Stop: `TaskStop` with its task id on Claude Code; on Codex, `kill` a
     background shell's pid, or `close_agent` where your tools offer it. An
     agent whose report you already have is stopped only to clear what it
     left running; its report stands. Otherwise append a ruling to the ledger
     naming the task it served and that its result is void:
     `Task <N>: Ruling: stopped <what> at handoff — its result is void — <cost if wrong>`.

   Only then continue. An assigned line is a resume point only when nothing
   it names is still running: the agent or wrapper reported back, or you
   stopped it and ruled on it. An executor line that carries a thread id is
   resumed by that id in the next session, on either host. One that still
   says `thread pending` names a wrapper that has not reported: wait for it
   or stop it.
1. **Make the durable record current.**
   - Execution: the ledger's last line records where you are (a
     `Task N: complete`, a fix-round line, or an assigned line whose run is
     over, per step 0). Update
     `<ledger dir>/handoff.md` (below; `<ledger dir>` per
     using-dforge §Session Budget).
   - Design phase (brainstorming, a spec, a plan in progress): save the draft
     file. It is the authority.
   - Unplanned work (a change designed in chat, or a punch list, with no plan
     or draft file): the notes in `latest.md` are the authority, so step 3's
     `State` must carry every item.
2. **Commit the plan and the spec** if either has uncommitted changes, in a
   `docs(<scope>): …` commit of their own (push instead while documents live
   in darkmem; see project-state.md). Never commit `<state>/`.
3. **Write the notes sections of `latest.md`** at `<latest.md>`.
   Replace everything above `## Next session` with exactly these sections,
   each under 15 lines:

   ```markdown
   # Handoff — <YYYY-MM-DD> (<budget | phase stop | Codex count | owner request>)

   ## State
   - Worktree: `<absolute worktree path>` (branch `<branch>`, HEAD `<sha7>`)
   - Plan: `<plan name>`; ledger: `<ledger dir>/progress.md`; handoff: `<ledger dir>/handoff.md`
   - <one line on where the work stands>

   ## Gotchas
   - <what the next session would otherwise rediscover>

   ## Do not
   - <owner constraints and prohibitions>
   ```

   In a design phase, `State` names the draft instead of a plan and ledger,
   on the line ``- Draft: `<spec path>` `` in place of the `- Plan:` line, where
   `<spec path>` is the draft's name (`dforge-path name`). darkmem files the
   checkpoint under the workstream either line names.
   For unplanned work, `State` lists each item with its state: implemented
   and uncommitted, committed, awaiting feedback (with the link), or
   unscoped.
4. **Run `scripts/next-step`** (see using-dforge §Session Budget):
   - Execution: `scripts/next-step PLAN_FILE`.
   - Design phase: `scripts/next-step --draft DRAFT_FILE --next "<the next action, naming its skill>"`,
     for example `--next "Write the implementation plan with dforge:writing-plans."`
   - Unplanned work: `scripts/next-step --adhoc --phase <design|build> --next "<the next action, naming its skill>"`.
     The phase is `design` when the next action, or any item the next
     session may pick up, is unscoped or awaits a design decision or
     feedback; otherwise `build`.
   It prints the `## Next session` block and writes it into `latest.md`. If it
   exits 4, say `latest.md` could not be written.

   Then run `scripts/darkmem-sync push` and promote the session's durable
   facts ([project-state.md](../../reference/project-state.md) §darkmem sync
   points): the push carries the ledger, `handoff.md` and `latest.md`.

   On Codex, add `--host codex` to the design-phase and unplanned-work calls,
   so the block names the Codex client rather than Claude. A plan states its
   own host in its header, so the execution call needs no flag.
5. **End the session.** Your final message is one line on why you stopped,
   then the block, verbatim, as the last thing. The block is the resume guide:
   the launch command, the directory to launch it in, and the first prompt.
   A caller that continues in this session instead, as a light plan of 1-3
   tasks with room does, stops after step 4.

## handoff.md

`<ledger dir>/handoff.md` holds what the ledger cannot, in under 40 lines:

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
| "The agent is nearly done, I'll hand off and it will finish" | Its result arrives in a session that has ended, and nobody reads it. Wait for it or stop it and record a Ruling (step 0). |
| "Compaction will take care of it" | Compaction drops reports, findings and rulings. Hand off before it fires. |
