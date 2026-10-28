---
name: finishing-a-development-branch
description: Use when implementation is complete, all tests pass, and you need to decide how to integrate the work
---

# Finishing a Development Branch

## Overview

**Core principle:** Verify tests → Detect environment → Carry out the choice
made before the run, or present options → Execute choice → Record the plan →
Clean up → Report the next step.

**Announce at start:** "I'm using the finishing-a-development-branch skill to
complete this work."

## Auto run

When `scripts/auto-run status` exits 0
([auto-run.md](../../reference/auto-run.md)), run
`scripts/auto-run phase finish`, then follow this skill with these changes:

- **Step 3** asks nothing: the base branch is
  the base `scripts/auto-run status` names.
- **Step 4 shows no menu.** Read `scripts/finish-choice get --plan PLAN_FILE`:
  with nothing recorded in this checkout's plan workspace it reads the spec's
  `Finish:` line itself and records it with `"source": "spec"`, so the spec
  review's answer reaches an execution worktree too; else the `finishAction`
  setting; exit 3 means `ask`. Carry out the matching option as if your human
  partner had chosen it, by name, since the detached-HEAD menu renumbers them:
  `merge` is Merge Locally into that base, `pr` is Push and Create PR, and
  `keep`, `ask` and `wait` are Keep As-Is. Never discard. In an auto run this
  mapping replaces Step 4's recorded-choice block. Three cases override this:
  on a detached HEAD (Step 2) there is no merge, so `merge` keeps and `pr`
  pushes a new branch (`git push origin HEAD:refs/heads/<new-branch>`); when
  the base is `none`, `merge` keeps and `pr` opens its request against the
  code host's default branch; and `merge` keeps when the ledger holds a
  `Task <N>: complete (deferred by the auto run)` line, so a deferred task's
  partial commits never reach the base unreviewed.
  `merge` also keeps when the `Acceptance QA: complete` line reports a nonzero count of
  `cannot-test`, or when the run added a deferred register
  row whose Item begins `A<n>:` or whose Note is `critic Blocker unresolved`.
  A row deferred at the spec review, before the run started, counts as one
  the run added. `merge` also keeps when the run added a deferred row whose
  Note is `final review residual`.
  An `Acceptance QA: skipped (depth light)` line carries no counts, so the
  `cannot-test` case does not apply to it; Step 7's final message lists what
  went unchecked.
  `merge` and `pr` also keep when Step 1b's `ui-proof check` exited 1
  after the Prove re-run.
  The line's `fail` and `flaky` counts are not read: they are taken before the
  fix wave, a failure that survives it is a deferred `A<n>:` row or a red test
  at Step 1, and one the fix wave fixed does not keep the branch. The mapping
  keeps the recorded-choice block's first call: once these cases settle the
  option (`merge`, `pr` or `keep`), run
  `scripts/finish-choice answer <action> --plan PLAN_FILE` with it before
  carrying it out, so the cockpit's Run card drops its finish row and the
  record reads as acted on.
- **Where an unattended finish stops** (failing tests at Step 1, a merged
  result failing its tests, a rejected push, a refused worktree removal), run
  `scripts/auto-run stop --reason "<what stopped it>"` first, then stop as
  Step 1 or Step 5's "Whose choice it is" says.
- **The rulings** printed at Step 3 also include every line of
  `scripts/auto-run ruling list`, and Step 7's final message lists every
  deferred row the run added to its register (`scripts/auto-run status` names
  it; the `final review residual` rows among them),
  every `A<n>` statement tagged `test` under `not verified (depth light)`
  when the ledger's `Review depth:` line names light (no acceptance QA ran),
  every `demo` statement of the spec, every lens
  a `final review lens-skipped <id> reason=<reason>` ledger line names,
  whatever its reason (the final
  review wrote them; never run `scripts/lens-route` here, since after a merge
  base..HEAD is empty). Run
  `scripts/auto-run stop` with no `--reason` before printing the next-step block:
  a reason marks the run as stopped and sends a `blocked` notice.

## Step 1: Verify Tests

When the project declares `<docs>/gates.md`, run
dforge:running-gates — it determines its own base, so it works here even
though Step 3 has not established one yet. Otherwise run the project's full test
suite (`npm test` / `cargo test` / `pytest` / `go test ./...`) through
`bash <plugin-root>/scripts/suite-run -- <test command>`, in the background
when it can outrun Bash's ten-minute cap. It prints a digest, never the whole
output, and reuses a recorded pass (`suite: reused pass at <sha7>`) only at
the same HEAD, with a clean tree then and now, for the same command: a fix
wave's passing run at this HEAD stands, and any other tree runs the suite.
Its exit code is the verdict.

**If tests fail**, report the failures and stop — the menu comes after a
green suite:

```
Tests failing (<N> failures). Must fix before completing:

[Show the digest's failing lines]

Next: fix these failures, then re-run dforge:finishing-a-development-branch.
```

Do not run `scripts/next-step` here: the branch is not ready to integrate, and
it would send the next session straight back into this skill.

**If tests pass:** continue to Step 1b.

## Step 1b: Prove the UI

Read [ui-proof.md](references/ui-proof.md) before you prove the UI.

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
plan, the conversation, or the branch's upstream.
An upstream names the base only as Step 4 qualifies it: a local branch other
than this one. A finish preference
recorded before the run (`scripts/finish-choice get [--plan PLAN_FILE]`) names
the base your human partner confirmed then; use it. When Step 4 carries out
a recorded choice, never ask here: Step 4 says where its base comes from.
Otherwise, if it is not already known, ask: "This branch split from <your
best guess> - is that correct?" Confirm before merging: merging into the
wrong base is expensive to undo.

**Rulings first.** If this work came from a plan with a ledger
(`<ledger dir>/progress.md`) and this session
has not yet printed its "Rulings I made" and "Amendments made" lists, print
them now: under "Rulings I made", every ledger line containing `Ruling:`, in
order, each with what it costs if wrong, then every `BLOCKED` task; under
"Amendments made", every entry of `amendments.md` in the directory
`scripts/sdd-workspace PLAN_FILE` prints, in
full. The execution skills leave these lists to this step, so they are
exhaustive here. Your human partner chooses how to integrate with those
decisions in view.

**Unverified at light depth.** When the ledger holds a `Review depth: light`
line, no acceptance QA checked the spec. Print every `A<n>` statement tagged
`test` under `not verified (depth light)` with the rulings, so your human
partner chooses how to integrate with them in view. Without that line (a plan
that ran at standard or full depth, or one older than depth routing), print
nothing here.

**Lenses skipped.** Print every `final review lens-skipped <id> reason=<reason>`
ledger line, whatever its reason, with the rulings. The final review wrote
them; never run `scripts/lens-route` here: a new route reads the branch after
the fix wave, not the range the final review saw.

## Step 4: Present Options

**Nothing still running.** "Implementation complete" is a claim about every
launch, not only the reports. Run `scripts/in-flight` first. Exit 1 lists
background shells and agents this session started that are still running,
including an agent that sent its report but left work of its own alive. Wait
for each, or stop it with `TaskStop` (a reported agent's report stands), as
dforge:handoff step 0 says, and run it again. Go on only on exit 0, or on
exit 3 after checking by hand.

**A choice recorded before the run.** Then run
`scripts/finish-choice get [--plan PLAN_FILE]`
([finish-preference.md](../../reference/finish-preference.md)):

- It prints `merge`, `pr` or `keep` with no `answer` or `firedAt` field: show
  no menu.
  When Step 1b's `ui-proof check` exited 1, `merge` and `pr` become `keep`:
  say so, and that the UI is unproven.
  Run `scripts/finish-choice answer <action> [--plan PLAN_FILE]`, then carry
  the option out from Step 5 by name, exactly as if your human partner had
  chosen it; never discard. The base is the recorded `base`. When that is
  null or `none`, take it from the plan, the conversation or the branch's
  upstream, as Step 3 does, without asking or confirming. A name counts only
  when it is a local branch other than this one, checked with
  `git show-ref --verify --quiet refs/heads/<name>`. Drop a remote prefix
  (`origin/main` is `main`) only
  when no local branch has the whole name and its first segment is a configured remote
  (`git remote`), so a local `feature/x` stays `feature/x`. When none of those
  names one, `merge` keeps the branch and `pr` opens its request against the
  repository's default branch. On a detached HEAD, `merge` keeps the branch
  and `pr` pushes a new branch (`git push origin HEAD:refs/heads/<new-branch>`).
  Write no "After integration" line: Step 7's block says what follows. Open
  the final message with `Finished with <the option, as worded in the menu
  below>, as chosen before the run.`
- A record whose `answer` field is set has been used: an earlier immediate
  finish stopped, or the menu was answered. So has one with `firedAt` set,
  which an older version's timer wrote when it carried the choice out. Show
  the menu and wait; never re-run the action unattended.
- It prints `wait`, exits 3 (nothing recorded), or fails any other way (no
  jq, outside a repository): show the menu below and wait.

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
the Program line answer, read as before:
`After integration: sub-project <k+1> (<title>) of <spec>` when it names
`next: <title>`, `After integration: the program is complete` when it is the
last sub-project, and `After integration: no follow-on work recorded` when
there is no Program line or no plan. Step 7 turns this into the launch block
once the choice is made.

Present the menu exactly as written — concise, with every option coming
from the list above. The menu is the last thing in your message: rulings,
findings and the summary go above it, never after, and never replace it with
a request in prose such as "tell me 'merge it'". Discarding the work happens
only in response to your human partner explicitly asking for it (see "If your
human partner asks to discard the work" below). Wait for their answer; the
integration decision is theirs.

## Step 5: Execute Choice

Read [execute-choice.md](references/execute-choice.md) before you carry out the chosen option.

## Step 5b: Record the plan as completed

A merged plan leaves no committed trace that it ran: its ledger lives in the
gitignored workspace that Step 6 deletes, and its branch is deleted with it.
Without a record, dforge:project-status cannot tell a merged plan from
one nobody ever started, and will recommend re-executing finished work.

So append one line to `<docs>/plans/completed.md` in the adopting
project. The write is bound to the **outcome**, not to Step 6 — Step 6 also runs
for a confirmed discard, and never runs for Options 2 and 3.

The two line forms:

```markdown
- 2026-09-12 `docs/dforge/plans/2026-09-12-example.md` — merged into `main` at 6a4619a
- 2026-09-12 `docs/dforge/plans/2026-09-12-example.md` — via PR
```

Either prefix names the same document: an entry spelled
`docs/superpowers/<rest>` already records the plan `docs/dforge/<rest>`, so
never add a second line for it.

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
projects add `<docs>/plans/completed.md merge=union` to
`.gitattributes` so those appends resolve without one; say so once if the file
is missing that line.

There is no index when a project adopted the plugin mid-programme. Create it
with this first line; do not backfill plans whose outcome you cannot verify.

The date is the date the plan landed, which is today's date when you write the
line — not the plan file's own date. Commit an Option 1 index line as
`docs(plans): complete <slug>`, which fits the 50-character subject limit where
a full basename would not. While documents live in darkmem, `completed.md` is
in the mirror: push it instead of committing it (see project-state.md).

**Carry open findings with it.** The ledger is the only record of what the run
left open, and Step 6 deletes it.

When a register covers this plan's spec, it is where open work lives, and the
prose note is not written. In the same commit as the index line:

- resolve every row this plan covered — one its tasks cite (a `<register>#<id>`
  citation names its register; a bare id is the one covering register's row),
  or one whose `Assigned` cell is this plan's path — with
  `scripts/register set <register> <id> done`, or `verify --note <what is owed>`
  when the row's acceptance names a check only your human partner can perform;
  a row cited only by a task whose complete line reads
  `(deferred by the auto run)` is set with
  `scripts/register set <register> <id> deferred --note "deferred by the auto run: <the line's Ruling>[; unmerged task ref <ref>]"`
  instead, with the line's `unmerged task ref <ref>` clause when it has one,
  whichever finish action runs this step, never `done` or `verify`;
- add a row for every `minor (deferred)` line, every `parked` line, every
  complete line's `discovered:` field that is not `none`, and every final-review
  finding you left for your human partner, with
  `scripts/register add <register> "<item>"` — `--state deferred --note <the
  ruling>` only when a ruling already says no one will do it; plain `open`
  when it is work, or when it waits on your human partner's ruling. A
  `deferred` row is resolved, so `next-step` never routes to it; an open row
  with no assignment routes to a ruling session.

When `<docs>/roadmap.md` exists, run
`scripts/roadmap settle --spec <the plan's Spec path>` after resolving those
rows and commit its changes with them. It moves the epic row assigned to that
spec to `verify` once every register covering the spec is resolved, and never
to `done`: an epic is done only when dforge:closing-a-milestone has
audited it. Settle before Step 7, so `next-step` routes to the next epic rather
than back to this one.

When no register covers the plan, write
`<docs>/notes/<slug>-followups.md` instead, listing those same
findings one bullet each with its task number. Write nothing when all of them
are empty. Either artifact travels with the same outcomes as the index line:
Options 1 and 2 only.

## Step 6: Cleanup Workspace

Read [cleanup.md](references/cleanup.md) before you remove the worktree.

## Step 7: Report the Next Step

**Runs after Options 1, 2 and 3.** A discard ends at Step 6: the work is
gone, so nothing follows from it.

If this work came from a plan file, run `scripts/next-step --complete PLAN_FILE`
(see using-dforge §Session Budget), with the
working directory inside the repository — after Option 1 that is the main
repo root. It prints a `## Next session` block naming what follows the plan:
the next program sub-project or roadmap epic with its launch command and
first prompt, the milestone audit when the current milestone has nothing open,
or that the program or roadmap is complete, or that the plan records no
follow-on work. It
also rewrites `<latest.md>` to
match, so a fresh session finds the same answer. If it exits 4, say the
handoff file could not be written.

The last thing in your final message is that block, verbatim. Without a
plan file, when something follows (a register row this work left open, a
finding awaiting a ruling), run
`scripts/next-step --adhoc --phase <design|build> --next "<what follows>"` —
`design` when what follows is rulings, a spec or a plan — and end with the
block it prints, verbatim. When nothing follows, end with: "No plan file — no
follow-on work recorded."

## Quick Reference

| Option | Merge | Push | Keep Worktree | Cleanup Branch |
|--------|-------|------|---------------|----------------|
| 1. Merge locally | yes | - | - | yes |
| 2. Create PR | - | yes | yes | - |
| 3. Keep as-is | - | - | yes | - |
| Discard (explicit request only) | - | - | - | yes (force) |

## Common Rationalizations

Read [rationalizations.md](references/rationalizations.md) before you skip a step of finishing.
