---
name: resume-execution
description: Use when continuing a plan's execution in a fresh session after a handoff or compaction - verifies the worktree against the ledger, reloads the durable record, and hands control to the plan's execution skill
---

# Resume Execution

**Announce at start:** "I'm using the resume-execution skill to pick up <plan>."

The durable record — `latest.md`, the ledger, `handoff.md` and git — is the
authority. Your context is empty by design: do not reconstruct the previous
session from memory or from a summary.

## Steps

1. **Orient in one call.** Run `scripts/repo-audit`, from the plugin root (two
   levels above this skill's directory). Read
   `<primary checkout>/.superpowers/handoff/latest.md`; the audit prints its path.
2. **Verify the worktree** named in latest.md's `## State` against
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
3. **Enter the worktree** (EnterWorktree with its path on Claude Code; `cd`
   elsewhere). Take the head commit of the ledger's last `Task N: complete`
   line and check `git merge-base --is-ancestor <sha> HEAD`. If it fails, the
   history was rewritten after the handoff: log
   `Ruling: HEAD no longer descends from <sha> — history rewritten after the handoff — tasks re-verified from git log`
   and continue from the ledger plus `git log`.
4. **Reload** `<workspace>/handoff.md`, the plan's header (run
   `scripts/task-brief --header PLAN_FILE` and read the file it prints), and
   the ledger. The owner constraints and do-nots in
   `handoff.md` bind you as if your human partner had just said them.
5. **Continue** with what latest.md's `**Next:**` line says:
   - Start or resume at Task N: invoke the skill the plan's `**Execution:**`
     line names — dr-superpowers:subagent-driven-development for `subagent`,
     dr-superpowers:executing-plans for `inline`. Its ledger recovery takes over.
   - Run the final whole-branch review: invoke the skill the plan's
     `**Execution:**` line names, as the previous bullet does. With every task
     complete, each goes straight to its Final Review section, and both follow
     the same [final-review.md](../../reference/final-review.md).
   - Run finishing: invoke dr-superpowers:finishing-a-development-branch.

## Red Flags

| Thought | Reality |
|---------|---------|
| "The summary says Task 5 is done" | Only a `Task 5: complete` ledger line says that. |
| "The worktree is gone — I'll recreate the branch from main" | A missing branch means merged or discarded. Ask. |
| "I'll look around instead of running repo-audit" | Looking around costs five to eight requests at a fresh session's full reload; the audit is one. |
