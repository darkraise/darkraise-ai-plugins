---
name: using-git-worktrees
description: Use when starting feature work that needs isolation from current workspace or before executing implementation plans - ensures an isolated workspace exists via native tools or git worktree fallback
---

# Using Git Worktrees

## Overview

Ensure work happens in an isolated workspace. Prefer your platform's native worktree tools. Fall back to manual git worktrees only when no native tool is available.

**Core principle:** Detect existing isolation first. Then use native tools. Then fall back to git. Never fight the harness.

**Announce at start:** "I'm using the using-git-worktrees skill to set up an isolated workspace."

## Step 0: Detect Existing Isolation

**Before creating anything, check if you are already in an isolated workspace.**

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
```

**Submodule guard:** `GIT_DIR != GIT_COMMON` is also true inside git submodules. Before concluding "already in a worktree," verify you are not in a submodule:

```bash
# If this returns a path, you're in a submodule, not a worktree — treat as normal repo
git rev-parse --show-superproject-working-tree 2>/dev/null
```

**If `GIT_DIR != GIT_COMMON` (and not a submodule):** You are already in a linked worktree. Skip to Step 2 (Project Setup). Do NOT create another worktree.

Report with branch state:
- On a branch: "Already in isolated workspace at `<path>` on branch `<name>`."
- Detached HEAD: "Already in isolated workspace at `<path>` (detached HEAD, externally managed). Branch creation needed at finish time."

**If `GIT_DIR == GIT_COMMON` (or in a submodule):** You are in a normal repo checkout.

**In an auto run** (`scripts/auto-run status` exits 0, [auto-run.md](../../reference/auto-run.md)), read the auto-run state (`scripts/auto-run status`), not the `worktree` setting, and do it before the linked-worktree check above, in any checkout: the run's `isolation` was settled when it started, and it never commits to its base branch.

- When the status names `branch <name>`, switch to that branch if HEAD is elsewhere (`git switch <name>`), then go to Step 2.
- With no branch recorded, when HEAD is the run's base (the status's `base`) or detached, and the run is `isolation in-place` or this is a linked worktree under either isolation: run `git switch -c auto/<plan slug>`, the slug being the plan filename without `.md` and its `YYYY-MM-DD-` prefix, suffixed `-2`, `-3`, … until `git show-ref --verify --quiet refs/heads/<name>` fails. Unstaged and untracked changes come along. Then run `scripts/auto-run setup-branch <name>`, which records the branch and every uncommitted path as carried: the run never commits those. When it refuses with `staged changes in this checkout: <paths>`, run `git checkout -` and `git branch -d <name>`, so HEAD is back where it was, then `scripts/auto-run stop --reason "staged changes in this checkout: <paths>"` and end as auto-run.md §Stopping says. Exit 4 `the run's branch is already recorded: <b>`: go to the first bullet (switch to `<b>`). Exit 4 `<name> is the run's base branch` or `HEAD is not on <name>`: run `git checkout -` and `git branch -d <name>`, then `scripts/auto-run stop --reason "<the refusal text>"` and end as auto-run.md §Stopping says. Exit 7: run it again with the `cd '<path>' && …` prefix it printed (exit 7 never stops the run). Then go to Step 2.
- With no branch recorded and HEAD on a branch other than the run's base: under `isolation worktree` in a linked worktree, that branch is the run's own (Step 1 created it, and the run's branch guard accepts it), so go to Step 2. Otherwise run `scripts/auto-run stop --reason "HEAD is on <branch>, not the run's base, and the run has no branch"` and end as auto-run.md §Stopping says.
- Under `isolation worktree` in the primary checkout, create the worktree without asking (Step 1).

Outside an auto run:

Has the user already indicated their worktree preference in your instructions? If not, the `worktree` setting decides (read it from the session-start line `dforge settings in force (…)`, or run `scripts/dforge-config workflow` when no such line is in context): `worktree=always` creates the worktree without asking, `worktree=never` works in place and skips to Step 2, and `ask`, the default and the value when the line does not name the key, asks for consent before creating a worktree:

> "Would you like me to set up an isolated worktree? It protects your current branch from changes."

Honor any existing declared preference without asking. If the user declines consent, work in place and skip to Step 2.

## Step 1: Create Isolated Workspace

**You have two mechanisms. Try them in this order.**

### 1a. Native Worktree Tools (preferred)

The user has asked for an isolated workspace (Step 0 consent). Do you already have a way to create a worktree? It might be a tool with a name like `EnterWorktree`, `WorktreeCreate`, a `/worktree` command, or a `--worktree` flag. If you do, use it and skip to Step 2.

Native tools handle directory placement, branch creation, and cleanup automatically. Using `git worktree add` when you have a native tool creates phantom state your harness can't see or manage.

Only proceed to Step 1b if you have no native worktree tool available.

### 1b. Git Worktree Fallback

Read [git-worktree-fallback.md](references/git-worktree-fallback.md) when you have no native worktree tool.

## Step 2: Project Setup

A plan's `**Worktree setup:**` command, or the setup the repository's README,
`CLAUDE.md` or `AGENTS.md` names, wins over detection. Otherwise detect from
the lockfile, which names the tool the project actually uses; a manifest alone
does not:

- Node: `packageManager` in `package.json` (such as `pnpm@9.12.0`) names the
  tool and its version, and wins over the lockfile. Use the declared npm,
  pnpm, Yarn or Bun at that version, and never create a second lockfile. A
  pinned pnpm or Yarn is supplied by Corepack, so run `corepack enable` first
  (`npm install -g corepack` when the Node install lacks it).

```bash
# Node.js
pm=$(sed -n 's/.*"packageManager"[[:space:]]*:[[:space:]]*"\([a-z]*\)@.*/\1/p' package.json 2>/dev/null)
ver=$(sed -n 's/.*"packageManager"[[:space:]]*:[[:space:]]*"[a-z]*@\([^+"]*\).*/\1/p' package.json 2>/dev/null)
if [ -n "$pm" ]; then
  case "$pm" in
    pnpm|yarn) corepack enable; "$pm" install ;;
    *) if [ "$("$pm" --version 2>/dev/null)" = "$ver" ]; then "$pm" install
       else npx --yes "$pm@$ver" install; fi ;;
  esac
elif [ -f pnpm-lock.yaml ]; then pnpm install
elif [ -f yarn.lock ]; then yarn install
elif [ -f bun.lock ] || [ -f bun.lockb ]; then bun install
elif [ -f package.json ]; then npm install; fi

# Rust
if [ -f Cargo.toml ]; then cargo build; fi

# Python
if [ -f poetry.lock ]; then poetry install
elif [ -f uv.lock ]; then uv sync
elif [ -f requirements.txt ]; then pip install -r requirements.txt; fi

# Go
if [ -f go.mod ]; then go mod download; fi
```

A `pyproject.toml` with none of those files names no tool: read its
`[build-system]` and the README rather than guessing.

## Step 3: Verify Clean Baseline

Run tests to ensure workspace starts clean:

```bash
# Use project-appropriate command
npm test / cargo test / pytest / go test ./...
```

**If tests fail:** Report failures, ask whether to proceed or investigate. In an auto run, ask nothing: run `scripts/auto-run ruling add "Setup: baseline tests red — <failing summary>"` and continue; the final review and finishing's first step run the suite again.

**If tests pass:** Report ready.

### Report

```
Worktree ready at <full-path>
Tests passing (<N> tests, 0 failures)
Ready to implement <feature-name>
```

### Work without a plan

When no plan drives this work (it goes straight from the chat to
dforge:finishing-a-development-branch), ask the finish preference now,
before the first change: what finishing should do once the work is done. See
[finish-preference.md](../../reference/finish-preference.md).
A plan's execution skill asks it itself.
