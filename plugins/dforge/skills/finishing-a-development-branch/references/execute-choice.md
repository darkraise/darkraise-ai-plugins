# Step 5: Execute Choice

**Whose choice it is.** When your human partner answers the menu, run
`scripts/finish-choice answer <merge|pr|keep|discard> [--plan PLAN_FILE]`
first, then carry out their answer. When Step 4 carries out a recorded
choice, it is theirs, made before the run. An immediate finish never asks:
where a step would ask (a refused worktree removal, a failing merged result,
a rejected push), it stops, leaves everything in place, reports what stopped
it and shows the menu; never pick a destructive answer for your human
partner.

### Option 1: Merge Locally

```bash
# Get main repo root for CWD safety
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"

# Merge first — verify success before removing anything
git checkout <base-branch>
git pull
PRE_MERGE=$(git rev-parse HEAD)
git merge <feature-branch>

echo "$PRE_MERGE"

# Verify the merged result: gates when the project declares a manifest
# (dforge:running-gates, with the sha printed above as its base), otherwise
# the full test suite through suite-run. Gates that passed on the branch say
# nothing about the merged tree, and the merged HEAD is new, so suite-run runs.
bash <plugin-root>/scripts/suite-run -- <test command>
```

Shell variables do not survive between Bash calls, so `$PRE_MERGE` is gone by
the time dforge:running-gates runs. Pass the base as the literal sha the
`echo` printed. A gates manifest whose `Repo` fields name several
repositories needs one base per repository: capture each repository's
pre-merge `git rev-parse HEAD` the same way, before that repository's merge,
and name each sha with its repository.

If tests fail on the merged result: stop, leave the worktree and branch in
place, and investigate — nothing has been pushed, so the merge is local
and recoverable.

Once the merged result is green: record the plan (Step 5b), clean up the
worktree (Step 6), then
delete the branch:

```bash
git branch -d <feature-branch>
```

### Option 2: Push and Create PR

First record the plan in the completed index (Step 5b) and commit it on the
branch, so the line travels with the PR. Then:

```bash
git push -u origin <feature-branch>
# From a detached HEAD, name the new branch on the remote:
# git push origin HEAD:refs/heads/<new-branch>
```

Then create the pull/merge request against <base-branch> with the code host's
tooling — its CLI if one is available, or the creation URL most forges
print when you push — following the repo's PR template and conventions if
present, and report the URL to your human partner.

Keep the worktree — your human partner iterates on PR feedback there.

### Option 3: Keep As-Is

Report: "Keeping branch <name>. Worktree preserved at <path>."

### If your human partner asks to discard the work

This path exists only as a response to an explicit request to throw the
work away. Confirm first:

```
This will permanently delete:
- Branch <name>
- All commits: <commit-list>
- Worktree at <path>

Type 'discard' to confirm.
```

Wait for that exact confirmation. When it arrives:

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
```

Then clean up the worktree (Step 6) and force-delete the branch:

```bash
git branch -D <feature-branch>
```
