---
name: resume-execution
description: Use when continuing a plan's execution in a fresh session after a handoff or compaction - verifies the worktree against the ledger, reloads the durable record, and hands control to the plan's execution skill
---

# Resume Execution

**Announce at start:** "I'm using the resume-execution skill to pick up <plan>."

The durable record — the plan's handoff, the ledger, `handoff.md` and git — is the
authority. Your context is empty by design: do not reconstruct the previous
session from memory or from a summary.

## Steps

1. **Orient and claim.** Run `scripts/repo-audit` (see using-dagents §Session Budget).
   The handoff is the file the first prompt names by its absolute path; only
   when it names none, it is the path
   `bash <plugin-root>/scripts/dagents-path handoff PLAN_FILE` prints. Claim it
   before anything else: `scripts/handoff claim <the handoff>`.
   - Exit 0: this session holds it. A `no handoff file at <path>` note means
     nothing was written there yet; the ledger and `git log` are the record.
   - Exit 3 from the claim (`held by <id8> (live, claimed <age> ago)`), or
     exit 7 from `dagents-path handoff`: another live session is working this
     plan. Stop and ask your human partner; in an auto run the script has
     already stopped the run.

   Then read the handoff.
2. **Verify the worktree** named in the handoff's `## State` (with no handoff
   file, the checkout that path is in) against
   `git worktree list --porcelain`. Normalise both paths before comparing:
   forward slashes, lowercase drive letter, no trailing slash
   (`D:\Repos\x`, `D:/Repos/x` and `/d/Repos/x` are one path).
   - Listed: continue.
   - Missing, but its branch still exists (`git branch --list <branch>`): run
     `git worktree prune`, then `git worktree add <path> <branch>`, and log
     `Ruling: re-added worktree <path> for <branch> — stale registration — none`
     in the ledger once you can read it.
   - Missing, and the branch is gone: stop and ask your human partner. The
     work may have been merged or discarded; guessing either way is worse than
     asking.

   In an auto run whose `scripts/auto-run status` names `branch <name>`, whichever case above held:
   when `git branch --list <name>` prints nothing, run
   `scripts/auto-run stop --reason "the run's branch <name> is gone"` and ask.
   Check HEAD in the recorded workspace, after step 3 has entered it when that is a linked worktree:
   When HEAD is not on it, run `git switch <name>`; a refused switch stops the run the same way.
3. **Enter the worktree** (EnterWorktree with its path on Claude Code; `cd`
   elsewhere). Skip EnterWorktree when the recorded workspace is the primary checkout. Take the head commit of the ledger's last `Task N: complete`
   line (or the branch's merge base with main when no task has completed) and
   check `git merge-base --is-ancestor <sha> HEAD`. If it fails, the
   history was rewritten after the handoff: log
   `Ruling: HEAD no longer descends from <sha> — history rewritten after the handoff — tasks re-verified from git log`
   and continue from the ledger plus `git log`.
4. **Reload** `<ledger dir>/handoff.md`, the plan's header (run
   `scripts/task-brief --header PLAN_FILE` and read the file it prints), and
   the ledger. The owner constraints and do-nots in
   `handoff.md` bind you as if your human partner had just said them. When the
   project has them, read `<docs>/distilled/constraints.md` and
   `<docs>/distilled/gotchas.md` in the same step: they bind the same
   way, and yield to `handoff.md` wherever both speak. Neither is an error when
   absent. See [project-state.md](../../reference/project-state.md).
5. **Continue** with what the `**Next:**` line of
   `scripts/next-step --print PLAN_FILE` says, not the handoff's (it recomputes
   the step from the plan and ledger and writes nothing):
   - Start or resume at Task N: invoke the skill the plan's `**Execution:**`
     line names — dagents:subagent-driven-development for `subagent`,
     dagents:executing-plans for `inline`. Its ledger recovery takes over.
     A ledger with a `Task <N>: escalated inline -> subagent` line and no later
     `implementer inline (assigned` line has left inline mode: invoke
     dagents:subagent-driven-development whatever the Execution line
     says. Inline mode writes that line only when your human partner asks for
     subagent mode; older ledgers may also hold it from a failed task.
   - Run the final whole-branch review: invoke the skill the plan's
     `**Execution:**` line names, as the previous bullet does. With every task
     complete, each goes straight to its Final Review section, and both follow
     the same [final-review.md](../../reference/final-review.md).
   - Run finishing: invoke dagents:finishing-a-development-branch.

## Auto run

When `scripts/auto-run status` exits 0
([auto-run.md](../../reference/auto-run.md)), the cockpit started this session
after a clear, and nobody is watching. Run every step as above. Where step 2
would stop and ask (the worktree and its branch are gone), run
`scripts/auto-run stop --reason "the worktree and its branch are gone"`
first, then ask. After a compaction an auto run does not come here: it
follows the execution skill's After compaction steps.

A run whose owner session is gone (crashed, or replaced outside the cockpit)
is bound to no live session, so `scripts/auto-run status` exits 3 here while
`<state>/sdd/auto-run.json` still reads `"active": true`. Run
`scripts/auto-run stop --stale` before resuming: it stops that run and prints
its pending decisions and rulings, which you read before going on. It exits 3
and changes nothing while the owner still lives.

## Red Flags

| Thought | Reality |
|---------|---------|
| "The summary says Task 5 is done" | Only a `Task 5: complete` ledger line says that. |
| "The worktree is gone — I'll recreate the branch from main" | A missing branch means merged or discarded. Ask. |
| "I'll look around instead of running repo-audit" | Looking around costs five to eight requests at a fresh session's full reload; the audit is one. |
