---
name: project-status
description: Use when asked what to do next, where the project stands, whether the work is done, or for a checkpoint - reports state and exactly one recommended next step, and writes nothing
---

# Project Status

**Announce at start:** "I'm using the project-status skill to report where this project stands."

One screen: where the repository stands, what is open, and the single next step.
This skill writes nothing — not `latest.md`, not a workspace, not a ledger. It
never calls `scripts/next-step`, which rewrites `latest.md`. See
[project-state.md](../../reference/project-state.md) for the files it reads.

## Steps

1. **Orient in one call.** Run `scripts/repo-audit`
   (see using-superpowers §Session Budget). It gives branch and HEAD, worktrees, dirty files, plans with
   ledgers, the handoff file, and recent commits.
2. **Route out if execution is live.** If a ledger has incomplete tasks and no
   task's last line is `BLOCKED`, name the plan and the task reached and route
   to dr-superpowers:resume-execution. Stop there: this skill orients a session
   with no thread to pick up, and never duplicates the resume path.
3. **Classify each plan.** A file under `docs/superpowers/plans/` is a plan when
   it has at least one `Task N` heading outside a fenced block — what
   `plan_tasks` in `scripts/lib/plan.sh` extracts, and the test `scripts/next-step`
   applies when it fails with "no tasks".
   Do **not** use the `**Execution:**` header as the discriminator:
   `plan-lint` requires it, but only plans written since 1.4.0 have one, so it
   would hide most plans. Then, in order:
   - **In flight** — `<worktree>/.superpowers/sdd/<basename minus .md>/progress.md`
     exists with incomplete tasks, checked under every worktree the audit lists,
     because a ledger lives in the worktree executing it. Compute that path
     directly; never call `scripts/sdd-workspace`, which creates the directory.
     A plan whose tasks are all complete but which is not yet indexed as merged
     is also in flight — a review or an integration is still ahead of it.
   - **Complete** — listed in `docs/superpowers/plans/completed.md`. That index
     answers whether the branch landed, not whether the work is finished: an
     item register answers that. A ledger showing every task complete is not a
     completion signal either — the work may be unmerged.
   - **Not started** — neither, and only when `completed.md` exists. "No ledger"
     never means "never ran": dr-superpowers:finishing-a-development-branch
     deletes the workspace on integration.
4. **Match specs to plans.** A spec's slug is its filename without the leading
   `YYYY-MM-DD-` and the trailing `-design`. A plan matches when its filename
   without its own date prefix equals that slug; dates need not agree. A prefix
   match counts only when no other spec claims that plan exactly. A spec whose
   body decomposes a programme into sub-projects is a program design and is
   never unplanned — its plans belong to the sub-projects.
5. **Find unmerged work with no plan.** `git branch --no-merged <base>` plus the
   audit's worktrees. `<base>` is the integration branch —
   `git symbolic-ref refs/remotes/origin/HEAD`, else `main` — never a ledger's
   `base <sha7>`, which is one task's starting commit and would make both this
   check and rule 3 call every branch unmerged. Say which you used, since unlike
   finishing-a-development-branch you have no plan, conversation or upstream to
   derive it from.
6. **Read the open constraints.** When `docs/superpowers/distilled/constraints.md`
   exists, take the entries whose scope covers the current work.
7. **Read the item registers.** Every `docs/superpowers/registers/*.md` the
   audit lists. Unresolved rows — `open`, `planned`, `doing`, `verify` — are
   open work whatever the plans say, and a register whose `**Covers:**` is `-`
   is a list that arrived before anything was designed, which is open work too.
   Never report work complete while a covering register has an unresolved row.
8. **Report** the shape below, then stop. There is no memory-store step: every
   line comes from the audit or the tree.

## Output

Six sections, in this order, nothing else:

- **Repos** — the audit's branch, HEAD and worktree lines.
- **In flight** — one bullet per plan with an active ledger, tasks complete of
  total, and its last ledger line; plus each unmerged branch from step 5.
- **Not started** — one bullet per un-started plan and unplanned spec, with paths.
- **Owner-only items** — decisions and prohibitions waiting on your human
  partner, including every task whose last ledger line is `BLOCKED`.
- **Open items** — omit when no register holds an unresolved row. Otherwise per
  register, its unresolved rows as `#<id> <item> — <state>`. Rows at `verify` sit under a sub-heading reading awaiting your check:
  they are built, and only your human partner closes them.
- **Next step** — exactly one, naming the skill or command that starts it.

Unfinished work always appears. Finished work appears only when touched within
seven days: for an indexed plan that is the date on its `completed.md` line (a
merged plan's file date is when it was authored), for anything else
`git log -1 --format=%cs -- <path>`.

## The recommendation is ordered, not chosen

Two sessions on one repository must reach the same step. The first matching rule
wins, and the report names which one matched.

| # | Condition | Recommendation |
|---|---|---|
| 0 | A task's **last** ledger line is `Task N: BLOCKED` | No skill. The decision it names goes under Owner-only items |
| 1 | A ledger has incomplete tasks and no such line | dr-superpowers:resume-execution |
| 2 | Every task complete, no `Final review: clean` line | the final review, via the plan's `**Execution:**` skill |
| 3 | Final review clean, branch unmerged (`git merge-base --is-ancestor <branch> <base>` exits non-zero) | dr-superpowers:finishing-a-development-branch |
| 4 | `completed.md` exists and a spec has no plan | dr-superpowers:writing-plans |
| 5 | `completed.md` exists and a plan is absent from it with no ledger | dr-superpowers:using-git-worktrees, then the plan's execution skill |
| 6 | A register holds an unresolved row and no rule above matched | Route by the `Assigned` cell, as `scripts/next-step --complete` does, not by row order. Set aside `verify` rows (awaiting your check), rows assigned to a finished plan (one `completed.md` records; list them to resolve or reassign) and `.md` paths absent from this repository (another repository's work). Of the rest, the first row assigned to an existing plan goes to that plan's execution skill (dr-superpowers:resume-execution when it has a ledger), else one assigned to an existing spec to dr-superpowers:writing-plans, else any other label to dr-superpowers:brainstorming for its spec, else dr-superpowers:brainstorming to rule on the unassigned rows. Nothing left: no skill — name the set-aside rows |
| 7 | A dirty tree with no plan in flight | name the files and ask whether they are live work |
| 8 | None of the above | say the project is between programmes, offer dr-superpowers:brainstorming |

`BLOCKED` outranks everything: `scripts/next-step` already treats it as terminal
and hands the decision to your human partner. Rule 0 reads each task's **last**
line, as both execution skills' recovery tables do, so a task that was blocked
and later ruled and completed no longer matches.

Rules 4 and 5 require `completed.md` to exist. Without it nothing can be shown to
have finished, and firing rule 5 would recommend re-executing merged work — fall
to rule 8 and say the index is absent. When several plans match one rule, take
the newest filename date and say so. When a rule matches in more than one
worktree, report each and recommend the one whose branch has the newest commit.

## Red Flags

| Thought | Reality |
|---------|---------|
| "I'll list every plan so nothing is missed" | A list of forty is a list of none. Unfinished, plus seven days. |
| "Three things look important" | Pick one by the table and say which rule matched. |
| "I know roughly where this stands" | Every line comes from the audit or the tree. Nothing from memory. |
| "No ledger, so nobody ever ran it" | The workspace is deleted on merge. Check `completed.md` first. |
| "I should write the handoff while I'm here" | This skill writes nothing. `latest.md` belongs to dr-superpowers:handoff. |
