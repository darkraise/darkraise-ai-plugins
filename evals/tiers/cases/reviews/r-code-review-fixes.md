# r-code-review-fixes

Source: the final-review fix commit `dea77c5`, reviewed at head `3955c80`.

## D1: the final-review step follows a template written for an agent with a shell

- Where: `plugins/dr-superpowers/reference/final-review.md`, step 1
- Defect: the step uses the code-reviewer template without saying that the printed `primary` is dispatched as `subagent_type` in place of the template's "Subagent (general-purpose)" line, and without saying that the template's Read-Only Review instructions (`git show`, `git diff`, `git worktree`) do not apply to judge agents, which carry no shell.
- Evidence: `dea77c5` adds both statements to step 1.
- Minimum severity: Important

## D2: the workspace clean-up command is refused from inside the worktree

- Where: `plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md`, Step 6, "Otherwise"
- Defect: the skill says to run `(cd "$WORKTREE_PATH" && scripts/sdd-workspace PLAN_FILE)` with the plan path the session holds, an absolute path into the main repository root. `scripts/sdd-workspace` now calls `plan_require_same_repo`, which treats a linked worktree and its primary checkout as different repositories, so the command exits with an error and the workspace is never deleted.
- Evidence: `dea77c5` tells the reader to `cd` into the worktree and re-resolve `PLAN_FILE` against that checkout's own copy of the plan file.
- Minimum severity: Critical
