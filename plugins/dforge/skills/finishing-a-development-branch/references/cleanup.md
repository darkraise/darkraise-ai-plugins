# Step 6: Cleanup Workspace

**Runs for Option 1 and confirmed discards.** Options 2 and 3 always
preserve the worktree. Both callers have already changed directory to the
main repo root — worktree removal must run from outside the worktree —
and use the `GIT_DIR`/`GIT_COMMON`/`WORKTREE_PATH` values captured in
Step 2, from before that directory change.

A plan's workspace (`<state>/sdd/<plan>/`: briefs, reports, and the ledger
and `handoff.md` while progress is local) is git-ignored and lives in the
worktree, so it goes with it — `git worktree remove` deletes ignored files
without `--force`. Options 2 and 3 keep it for the next session.

**Carry the worktree's handoffs (Option 1 from a linked worktree, work
without a plan file).** Each checkout keeps its own handoffs, they leave with
the worktree, and the next session starts in the main repo root, so before
removing or leaving the worktree, read the worktree's handoffs
(`bash <plugin-root>/scripts/handoff list --checkout "$WORKTREE_PATH"` lists
them). An open item in their notes counts as something that follows in
Step 7, beside a register row this work left open and a finding awaiting a
ruling. When there is one, write a notes file carrying every open item
(handoff step 3) in the main repo root, for the key `scripts/next-step
--target --adhoc --phase <design|build> --next "<what follows>"` prints
there; Step 7's `--adhoc` call passes it with `--notes`. Work from a plan file carries nothing here:
its ledger and register hold what follows, and Step 7 runs `--complete`.

**If `GIT_DIR == GIT_COMMON`:** Normal repo, no worktree to clean up. If this
work came from a plan, delete its workspace — `rm -rf` on the directory
`scripts/sdd-workspace PLAN_FILE` prints. Done.

**If `WORKTREE_PATH` is under `.worktrees/` or `worktrees/`:** dforge
created this worktree — we own cleanup:

```bash
git worktree remove "$WORKTREE_PATH"
git worktree prune  # Self-healing: clean up any stale registrations
```

**If removal is refused** (`contains modified or untracked files`): the
worktree holds files that exist nowhere else — uncommitted plans, notes,
or scratch work. Never `--force` on your own initiative. Show your human
partner what is at stake and ask:

```bash
git -C "$WORKTREE_PATH" status --porcelain -uall
```

```
Worktree removal refused — these files were never committed:

<file list>

1. Commit them to <branch> before cleanup
2. Move them into <main repo root>
3. Delete them (unrecoverable)

Which?
```

Carry out the choice, then remove the worktree.

**Otherwise:** The host environment owns this workspace — leave it in
place, after carrying its handoff as above. If this work came from a plan,
first delete its workspace: running
`scripts/sdd-workspace PLAN_FILE` from the main repo root (where Step 6
already is) resolves against the wrong checkout, so `cd "$WORKTREE_PATH"`
and re-resolve `PLAN_FILE` against that checkout's own copy of the plan
file — not the absolute path into the main repo root the session may still
be holding, which `scripts/sdd-workspace` now refuses from inside the
worktree (`plan_require_same_project` treats a linked worktree and its primary
checkout as different repositories). Then run `scripts/sdd-workspace
PLAN_FILE` and `rm -rf` the path it prints. Then, if your platform provides
a workspace-exit tool, use it.
