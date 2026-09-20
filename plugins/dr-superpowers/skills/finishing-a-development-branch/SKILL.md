---
name: finishing-a-development-branch
description: Use when implementation is complete, all tests pass, and you need to decide how to integrate the work
---

# Finishing a Development Branch

## Overview

**Core principle:** Verify tests → Detect environment → Present options → Execute choice → Record the plan → Clean up → Report the next step.

**Announce at start:** "I'm using the finishing-a-development-branch skill to complete this work."

## Step 1: Verify Tests

When the project declares `docs/superpowers/gates.md`, run
dr-superpowers:running-gates — it determines its own base, so it works here even
though Step 3 has not established one yet. Otherwise run the project's full test
suite (`npm test` / `cargo test` / `pytest` / `go test ./...`).

**If tests fail**, report the failures and stop — the menu comes after a green suite:

```
Tests failing (<N> failures). Must fix before completing:

[Show failures]

Next: fix these failures, then re-run dr-superpowers:finishing-a-development-branch.
```

Do not run `scripts/next-step` here: the branch is not ready to integrate, and
it would send the next session straight back into this skill.

**If tests pass:** continue to Step 2.

## Step 2: Detect Environment

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
# Capture now, while still inside the workspace — Step 5 changes directory
# before cleanup (Step 6) needs this value
WORKTREE_PATH=$(git rev-parse --show-toplevel)
```

This determines which menu to show and how cleanup works:

| State | Menu | Cleanup |
|-------|------|---------|
| `GIT_DIR == GIT_COMMON` (normal repo) | Standard 3 options | No worktree to clean up |
| `GIT_DIR != GIT_COMMON`, named branch | Standard 3 options | Provenance-based (see Step 6) |
| `GIT_DIR != GIT_COMMON`, detached HEAD | Reduced 2 options (no merge) | Externally managed — leave in place |

## Step 3: Determine Base Branch

The base branch is whatever this work forked from — usually named in the
plan, the conversation, or the branch's upstream. If it is not already
known, ask: "This branch split from <your best guess> - is that correct?"
Confirm before merging: merging into the wrong base is expensive to undo.

**Rulings first.** If this work came from a plan with a ledger (`progress.md`
in the directory `scripts/sdd-workspace PLAN_FILE` prints) and this session
has not yet printed its "Rulings I made" and "Amendments made" lists, print
them now: every ledger line containing `Ruling:`, in order, then every entry
of `amendments.md` in the same directory, in full. Your human partner chooses
how to integrate with those decisions in view.

## Step 4: Present Options

**Normal repo and named-branch worktree — present exactly these 3 options:**

```
Implementation complete. What would you like to do?

1. Merge back to <base-branch> locally
2. Push and create a Pull Request
3. Keep the branch as-is (I'll handle it later)

Which option?
```

**Detached HEAD — present exactly these 2 options:**

```
Implementation complete. You're on a detached HEAD (externally managed workspace).

1. Push as new branch and create a Pull Request
2. Keep as-is (I'll handle it later)

Which option?
```

Directly above the menu, write one line saying what follows the plan. Run
`scripts/register open --spec <the plan's Spec path>` first, and again with the
spec its `**Program:**` line names when that differs, because a programme's
register covers the programme design rather than each child's. Ignore every row
whose `assigned` value is this plan's repository-relative path: Step 5b resolves
those, so they are not open after integration. While any other row remains,
the line is `After integration: <n> register rows are still open — #<id>
<item>`, whatever the Program line says.

Only when every covering register is fully resolved once those rows land does
the Program line answer, read as before: `After integration: sub-project <k+1> (<title>) of
<spec>` when it names `next: <title>`, `After integration: the program is
complete` when it is the last sub-project, and `After integration: no
follow-on work recorded` when there is no Program line or no plan. Step 7 turns
this into the launch block once the choice is made.

Present the menu exactly as written — concise, with every option coming
from the list above. The menu is the last thing in your message: rulings,
findings and the summary go above it, never after, and never replace it with
a request in prose such as "tell me 'merge it'". Discarding the work happens only in response to your
human partner explicitly asking for it (see "If your human partner asks to
discard the work" below). Wait for their answer; the integration decision
is theirs.

## Step 5: Execute Choice

### Option 1: Merge Locally

```bash
# Get main repo root for CWD safety
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"

# Merge first — verify success before removing anything
git checkout <base-branch>
git pull
git merge <feature-branch>

# Verify the merged result: gates when the project declares a manifest
# (dr-superpowers:running-gates), otherwise the full test suite. Gates that
# passed on the branch say nothing about the merged tree.
<test command>
```

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

Then create the pull/merge request against <base-branch> with the forge's
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

## Step 5b: Record the plan as completed

A merged plan leaves no committed trace that it ran: its ledger lives in the
gitignored workspace that Step 6 deletes, and its branch is deleted with it.
Without a record, dr-superpowers:project-status cannot tell a merged plan from
one nobody ever started, and will recommend re-executing finished work.

So append one line to `docs/superpowers/plans/completed.md` in the adopting
project. The write is bound to the **outcome**, not to Step 6 — Step 6 also runs
for a confirmed discard, and never runs for Options 2 and 3.

The two line forms:

```markdown
- 2026-09-12 `docs/superpowers/plans/2026-09-12-example.md` — merged into `main` at 6a4619a
- 2026-09-12 `docs/superpowers/plans/2026-09-12-example.md` — via PR
```

| Path | When | Which form |
|---|---|---|
| Option 1, merge locally | On the base branch, as its own commit, after Step 5's merged-result verification passes | the `merged into` form |
| Option 2, push and PR | On the branch, before the push | the `via PR` form |
| Option 3, keep as-is | Never | — |
| Confirmed discard | Never | — |

Option 3 and a confirmed discard write nothing. Step 6 runs for a discard, which
is exactly why this write is bound to the outcome and not to Step 6.

The SHA on an Option 1 line is the base branch head after the merge, not the
merge commit's own hash — a commit cannot contain its own hash, and the merge
fast-forwards when it can, leaving no merge commit at all.

Two branches each appending a last line conflict on integration. Adopting
projects add `docs/superpowers/plans/completed.md merge=union` to
`.gitattributes` so those appends resolve without one; say so once if the file
is missing that line.

There is no index when a project adopted the plugin mid-programme. Create it
with this first line; do not backfill plans whose outcome you cannot verify.

The date is the date the plan landed, which is today's date when you write the
line — not the plan file's own date. Commit an Option 1 index line as
`docs(plans): complete <slug>`, which fits the 50-character subject limit where
a full basename would not.

**Carry open findings with it.** The ledger is the only record of what the run
left open, and Step 6 deletes it.

When a register covers this plan's spec, it is where open work lives, and the
prose note is not written. In the same commit as the index line:

- resolve every row this plan covered — one its tasks cite, or one whose
  `Assigned` cell is this plan's path — with
  `scripts/register set <register> <id> done`, or `verify --note <what is owed>`
  when the row's acceptance names a check only your human partner can perform;
- add a row for every `minor (deferred)` line, every `parked` line, every
  complete line's `discovered:` field that is not `none`, and every final-review
  finding you left for your human partner, with
  `scripts/register add <register> "<item>"` — `--state deferred --note <the
  ruling>` when it is not work anyone will do, plain `open` when it is.

When no register covers the plan, write
`docs/superpowers/notes/<slug>-followups.md` instead, listing those same
findings one bullet each with its task number. Write nothing when all of them
are empty. Either artifact travels with the same outcomes as the index line:
Options 1 and 2 only.

## Step 6: Cleanup Workspace

**Runs for Option 1 and confirmed discards.** Options 2 and 3 always
preserve the worktree. Both callers have already changed directory to the
main repo root — worktree removal must run from outside the worktree —
and use the `GIT_DIR`/`GIT_COMMON`/`WORKTREE_PATH` values captured in
Step 2, from before that directory change.

A plan's workspace (`.superpowers/sdd/<plan>/`: ledger, briefs, reports,
`handoff.md`) is git-ignored and lives in the worktree, so it goes with it —
`git worktree remove` deletes ignored files without `--force`. Options 2 and 3
keep it for the next session.

**If `GIT_DIR == GIT_COMMON`:** Normal repo, no worktree to clean up. If this
work came from a plan, delete its workspace — `rm -rf` on the directory
`scripts/sdd-workspace PLAN_FILE` prints. Done.

**If `WORKTREE_PATH` is under `.worktrees/` or `worktrees/`:** Superpowers
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
place. If this work came from a plan, first delete its workspace: running
`scripts/sdd-workspace PLAN_FILE` from the main repo root (where Step 6
already is) resolves against the wrong checkout, so `cd "$WORKTREE_PATH"`
and re-resolve `PLAN_FILE` against that checkout's own copy of the plan
file — not the absolute path into the main repo root the session may still
be holding, which `scripts/sdd-workspace` now refuses from inside the
worktree (`plan_require_same_repo` treats a linked worktree and its primary
checkout as different repositories). Then run `scripts/sdd-workspace
PLAN_FILE` and `rm -rf` the path it prints. Then, if your platform provides
a workspace-exit tool, use it.

## Step 7: Report the Next Step

**Runs after Options 1, 2 and 3.** A discard ends at Step 6: the work is
gone, so nothing follows from it.

If this work came from a plan file, run `scripts/next-step --complete PLAN_FILE`
(see using-superpowers §Session Budget), with the
working directory inside the repository — after Option 1 that is the main
repo root. It prints a `## Next session` block naming what follows the plan:
the next program sub-project with its launch command and first prompt, or
that the program is complete, or that the plan records no follow-on work. It
also rewrites the primary checkout's `.superpowers/handoff/latest.md` to
match, so a fresh session finds the same answer. If it exits 4, say the
handoff file could not be written.

The last thing in your final message is that block, verbatim. Without a
plan file, end with: "No plan file — no follow-on work recorded."

## Quick Reference

| Option | Merge | Push | Keep Worktree | Cleanup Branch |
|--------|-------|------|---------------|----------------|
| 1. Merge locally | yes | - | - | yes |
| 2. Create PR | - | yes | yes | - |
| 3. Keep as-is | - | - | yes | - |
| Discard (explicit request only) | - | - | - | yes (force) |

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Tests passed earlier this session" | Run the suite on the tree you are about to integrate. A green run only proves the tree it ran on. |
| "They obviously want it merged" | Integration is your human partner's decision. Present the menu and wait. |
| "I'll ask for the merge in prose" | A request buried in a long report goes unseen. The three-option menu, verbatim, is the last thing in the message. |
| "The open findings are in my report" | The report scrolls away and Step 6 deletes the ledger. Commit them in the followups note. |
| "They seem done with this feature — I'll offer to discard it" | The menu is complete as written. Discard happens only when your human partner asks for it in so many words. |
| "'Yeah, get rid of it' counts as confirmation" | Only the typed word `discard` authorizes deletion. |
| "The PR is up, so the worktree is clutter now" | PR feedback gets fixed in that worktree. It stays until the work lands. |
| "This other worktree looks stale — I'll clean it too" | Clean up only worktrees under `.worktrees/` or `worktrees/`. Everything else belongs to the host. |
| "Removal refused — `--force` is just finishing the cleanup" | The refusal means files exist only in that worktree. `--force` destroys them permanently. Show your human partner and ask. |
| "The merged-result failure is probably flaky" | A failing merged result stops everything. Branch and worktree stay put while you investigate. |
| "The base branch is obviously main" | Confirm the fork point or ask. Merging into the wrong base is expensive to undo. |
| "The push was rejected — force-push will fix it" | A rejected push means the remote moved. Investigate; force-push only on your human partner's explicit request. |
| "I summarized the outcome — the next step is obvious" | Not to a fresh session or a partner who stepped away. End with the `next-step` block, verbatim. |
