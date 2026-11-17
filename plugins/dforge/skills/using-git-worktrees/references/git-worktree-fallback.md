# Step 1b: Git worktree fallback

**Only use this if Step 1a does not apply** — you have no native worktree tool available. Create a worktree manually using git.

## Directory Selection

Follow this priority order. Explicit user preference always beats observed filesystem state.

1. **Check your instructions for a declared worktree directory preference.** If the user has already specified one, use it without asking.

2. **Check for an existing project-local worktree directory:**
   ```bash
   ls -d .worktrees 2>/dev/null     # Preferred (hidden)
   ls -d worktrees 2>/dev/null      # Alternative
   ```
   If found, use it. If both exist, `.worktrees` wins.

3. **If there is no other guidance available**, default to `.worktrees/` at the project root.

## Safety Verification (project-local directories only)

**MUST verify the chosen directory is ignored before creating worktree** —
the one `$LOCATION` names, not any of the candidates. The trailing slash lets
a directory pattern such as `.worktrees/` match before the directory exists:

```bash
git check-ignore -q "$LOCATION/" 2>/dev/null
```

**If NOT ignored:** Add to .gitignore, commit the change, then proceed.

**Why critical:** Prevents accidentally committing worktree contents to repository.

## Create the Worktree

```bash
# Determine path based on chosen location
path="$LOCATION/$BRANCH_NAME"

git worktree add "$path" -b "$BRANCH_NAME"
cd "$path"
```

**Sandbox fallback:** If `git worktree add` fails with a permission error (sandbox denial), tell the user the sandbox blocked worktree creation and you're working in the current directory instead. Then run setup and baseline tests in place. In an auto run under `isolation worktree`, do not work in place: run `scripts/auto-run stop --reason "the sandbox refused the execution worktree"` and end as [auto-run.md](../../../reference/auto-run.md) §Stopping says.
