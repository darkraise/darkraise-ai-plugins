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
# (dforge:running-gates runs first, with the sha printed above as its base),
# then the full suite through suite-run in every case. Gates that passed on
# the branch say nothing about the merged tree.
bash <plugin-root>/scripts/suite-run -- bash -c '<full suite command>'
```

`<full suite command>` is the `**Integration check:**` command of the plan
being finished, else the project's test command. `bash -c` keeps the row's
key the one writing-plans, task-step and ci-mirror look up. The suite runs
whether or not the project declares gates. suite-run reuses a pass a gate
already recorded at this HEAD. The run in the main checkout leaves one
full-suite row for each merge head. dforge:closing-a-milestone reads these
rows.

Shell variables do not survive between Bash calls, so `$PRE_MERGE` is gone by
the time dforge:running-gates runs. Pass the base as the literal sha the
`echo` printed. A gates manifest whose `Repo` fields name several
repositories needs one base per repository: capture each repository's
pre-merge `git rev-parse HEAD` the same way, before that repository's merge,
and name each sha with its repository.

If tests fail on the merged result: stop, leave the worktree and branch in
place, and investigate — nothing has been pushed, so the merge is local
and recoverable.

Step 5b also writes the plan's review record before its commit (The review
record, below).

Once the merged result is green: record the plan (Step 5b), clean up the
worktree (Step 6), then
delete the branch:

```bash
git branch -d <feature-branch>
```

After a local merge, nothing was pushed, so do not wait: print `gh run list --commit <merge sha>` and `gh run watch <id>` for your human partner to run after pushing, and never call the branch CI-green.

On a plan with an `**Early CI:**` line, run `git push origin --delete <feature-branch>` after the local merge. The delete applies only when `git ls-remote --exit-code --heads origin <feature-branch>` finds the branch and the sha it prints is an ancestor of the merge (`git merge-base --is-ancestor <sha> HEAD`), so a remote branch holding a commit the merge lacks, such as one pushed by someone else, is kept with one line saying so. A delete that fails prints one line and does not stop finishing.

### Option 2: Push and Create PR

Write the plan's review record before Step 5b's commit (The review record,
below) and commit it with the index line.

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

Then wait for CI as `### Wait for CI` says, with `sha` being `git rev-parse HEAD` at the push.

### The review record

When the plan has a ledger, write its review record before Step 5b's commit:

```bash
bash <plugin-root>/scripts/review-record retain PLAN_FILE [--from <worktree path>]
```

On Option 1 from a linked worktree, pass the literal `WORKTREE_PATH` Step 2
captured as `--from`: Step 5b runs in the main checkout, and the ledger is
in the worktree. Option 2 runs where the ledger is and needs no `--from`.
Add the path the script prints to the commit that holds the index line, or
push it with the mirror, as `completed.md` is, while documents live in
darkmem.

- Exit 3: the ledger holds no review lines. Say so in one line and go on.
- Exit 4: no ledger was found, and the script printed where it looked. Do
  not go on to Step 6, which deletes the workspace, until you have found
  the ledger and rerun with `--from`. When it cannot be found, tell your
  human partner that the review record will be lost before Step 6 runs;
  in an auto run, name the loss in the final message.

Option 3 and a discard write no review record.

### Option 3: Keep As-Is

Report: "Keeping branch <name>. Worktree preserved at <path>."

With keep on such a plan, say that the remote branch `origin/<feature-branch>` exists. This applies only when `git ls-remote --exit-code --heads origin <feature-branch>` finds the branch, so a failed early push says nothing false.

### Wait for CI

Finishing waits for CI only when it pushed: Option 2, or an Early CI push whose head is the final head. An Early CI push whose head is the final head means the ledger's last `Early CI: dispatched run <id> at <sha7>` line names `git rev-parse --short HEAD`, and its run id is the one to watch. Only keep reaches that case, since Option 1 never waits and Option 2 pushes again: with keep, the skip below does not apply to such a push.

Run `gh run list --commit <sha>`, then `gh run watch <id>` as a background Bash command. When it lists several runs, add `--workflow <file>` for each workflow file the `**CI:**` line names and watch each run found, one background watch and one `CI:` line per run. Set the call's `timeout` to (90 × 60 + 120) × 1000 ms, because a background call otherwise stops at 30 minutes. In an auto run, end the turn and resume on the notification.

When no run for the commit appears within 60 seconds, print one line saying so and skip the wait; never call the branch CI-green.

Record `CI: <sha7> run <id> <green|red|still running at 90 min>` on the ledger. Read the result with `gh run view <id> --json conclusion,jobs`.

- Green completes the branch.
- Red reopens the branch through dforge:systematic-debugging, naming each failed job and step; push the fix and wait again.
- A run still going after 90 minutes is reported as not done, never as done.
- In an auto run, a run still going after 90 minutes runs `scripts/auto-run stop --reason "CI run <id> still running at 90 min"` before the final message.

With keep, no `gh` (`command -v gh` fails), `gh` not logged in (`gh auth status` exits non-zero), or a CI line of `none`, print why in one line and skip the wait; never call the branch CI-green. The CI line is the plan's `**CI:**` header line, read from the plan file finishing was given. A plan with no such line counts as `none`.

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
