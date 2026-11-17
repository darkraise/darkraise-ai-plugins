# Per-worktree handoff files — design

**Status:** spec — awaiting the spec review.
**Execution strategy:** sequential — inline execution
**Depth:** full — risk
**Register:** docs/dforge/registers/2026-11-18-per-worktree-handoff.md

## Decisions

- Process: the owner chose "Full dforge flow (Recommended)" over fast mode.
- Scope: "dforge and dagents (Recommended)" — the same change in both, one commit per concern covering both plugins.
- Visibility: "Own + list others (Recommended)" — each session resumes only its own worktree's handoff; repo-audit and project-status list every worktree's handoff.
- Prompt form: "cd in launch + paths in prompt (Recommended)" — the launch command enters the worktree (`cd <worktree> && claude --model … --effort …`) and the first prompt names the worktree, its branch and its handoff file by absolute path.
- Location: "A: in the worktree (Recommended)" — `<worktree>/.dforge/handoff/latest.md` (dagents `.dagents/`), like the ledger; the primary checkout keeps today's path, so no migration; the file goes with the worktree.
- Rejected: B (every handoff in the primary, keyed per worktree: key mapping and cleanup), C (one file with a section per worktree under a lock: every reader learns sections, sessions still contend).
- darkmem in dagents: the owner's ruling of 2026-11-17, "remove the darkmem mirror for both dflow and dagents". dagents gets no darkmem design work; only its local path line changes (§1).
- Early CI: none — the owner, 2026-11-18: "merge locally, do not push".

## Problem

`latest.md` is one file per repository: `scripts/lib/roots.sh` `_dforge_local`
sets `_DFORGE_LATEST` from `$primary` (dforge `:64`, dagents `:53`) while the
ledger root already uses `$base`, the session's own checkout. With darkmem
progress it is one `work/handoff/latest.md` per project mirror. Two sessions in
two worktrees overwrite each other's next-session block, so parallel sessions
are not safe. The block's prompt also tells the next session to "First enter
the existing worktree" instead of starting it there.

## Design

Terms: the **primary** is the main checkout; a **worktree** is a linked
worktree; a **checkout** is either. The **handoff** of a checkout is
`<checkout>/.dforge/handoff/latest.md` (dagents `<checkout>/.dagents/handoff/latest.md`).

### 1. Path source

- `_dforge_local` (dforge `roots.sh:64`) and `_dagents_local` (dagents
  `roots.sh:53`): the latest file from `$base`, as the ledger root already is.
- `darkmem-config.mjs:147-149`, local branch: `worktreeRoot`, not
  `repoRoot ?? worktreeRoot` (dforge and dagents; in dagents this one line is
  the only darkmem change, since the audit branch deletes the file).
- The primary's path is unchanged, so an existing `latest.md` there is read as
  before with no migration.

### 2. Which handoff `next-step` writes

`next-step` computes a target checkout **T** and writes T's handoff, instead of
the cwd's checkout's file (`:656`, `:672-697`):

| Mode | T |
|---|---|
| plan, in flight or not started | `ledger_root` — the worktree holding the ledger, else the checkout next-step runs in |
| `--complete`, `--kept`, or a plan found finished | the primary: finishing removes the worktree, and what follows a finished plan starts from the primary |
| `--draft`, `--adhoc`, `--project` | the checkout next-step runs in |

`dir` (the `Launch in` directory, today always `$primary` at `:274`, `:283`)
becomes T. `dforge_stores_init` is run for T before `dforge_latest_file`. The
marker counts (`handoff_counts "$primary"`) and the `finish.json` clearing are
unchanged. `--print --latest` reads the handoff of the checkout it runs in.

### 3. Launch line and prompt

- **Launch command.** `launch_cmd` gains the prefix `cd '<T>' && `, T
  single-quoted with each `'` written `'\''`, on Claude and Codex hosts alike
  (`launch_for`, `execution_launch`, `ROUTE_LAUNCH_CMD` at `:253`). T is the
  path `_dforge_path` prints, so on Git Bash it is the `C:/…` form, which
  Git Bash's `cd` accepts. With no launch command (the `Launch: see the
  **Execution:** line` case) the line becomes
  ``Launch from `<T>`: see the **Execution:** line in `<plan>`.``
- **Prompt.** Every first prompt opens with
  ``Work in `<T>` (branch <b>); its handoff is `<absolute handoff path>`.``
  `<b>` is `git -C T branch --show-current`, or `detached at <sha7>`. This
  replaces both "First enter the existing worktree" sentences (`:376-377`,
  `:608-609`). `latest_shown` (`:293-294`) becomes T's absolute handoff path,
  so the draft and adhoc prompts name the same file.
- auto-run's launch regex (`auto-run.sh:473`) is unanchored, so it still
  finds `claude --model … --effort …` behind the prefix.

### 4. Stop hooks

`turn-end.sh` (`wrote_block` at `:127`, `changed_here` at `:86`) and
`ui-turn-end.sh` (`:58`) compare against the newest handoff of any checkout of
the repository, since `next-step` run in the primary may now write a worktree's
file. A new `roots.sh` helper `dforge_latest_files [DIR]` (dagents
`dagents_latest_files`) prints the handoff path of every checkout
`git worktree list --porcelain` names, plus the mirror's file while progress is
in darkmem; the hooks take the newest existing one. The released condition is
otherwise unchanged: a block next-step wrote this turn, never a hand-typed one.

### 5. auto-run

`ar_handoff` (`auto-run.sh:464-476`) reads the handoff of the checkout it runs
in (`git rev-parse --show-toplevel`), not `ar_primary_root`'s. The cockpit and
the model call it from the session's checkout, which is where next-step wrote
the block (§2: an in-flight plan's T is its ledger's worktree, where an
executing session already is). The plan-name guard in `ar_clear` stays; its
comment (`:503`, "One latest.md serves every worktree") is rewritten to say the
guard catches a block another session left in this checkout.

### 6. Cockpit

`register.tsx` (dforge `:146-147`, `:3786-3805`; dagents `:143-144`,
`:3536-3544`):

- `readRun` falls back to `${session ?? root}/.dforge/handoff/latest.md`, not
  `${primary}/.dforge/…`; `roots.progress.latestFile` already resolves from
  the session checkout once §1 lands. When the session's checkout no longer
  exists, it reads the primary's, as the resume offer's `isGone` path does.
- `S.latestName` is always the absolute handoff path, so `resumePrompt()`
  names it.
- `next-step --print --latest` already runs in the session checkout
  (`:3693-3696`).

### 7. Handoff skill

`skills/handoff/SKILL.md` step 3 writes the notes to T's handoff: run
`scripts/dforge-path latest` in the checkout the work is in (the ledger's
worktree for a plan in flight, the primary after a finished plan), so the notes
and the block next-step merges land in one file. `skills/resume-execution`
step 1 reads the handoff of the checkout it starts in (repo-audit prints it).

### 8. Listing

- `repo-audit` (`:99-121`) prints one entry per checkout that has a handoff,
  the session's own first, each with its path, the checkout's branch, the
  Status and Next lines recomputed by `next-step --print --latest` run in that
  checkout (bounded by `with-timeout 20` each, as today), and the count of
  commits on that checkout's HEAD since the file was written. No
  handoff anywhere prints `- none`.
- `project-status` lists them the same way and recommends the session's own.
- The SessionStart snapshot (`snapshot.sh:41`) stays own-only.

### 9. darkmem (dforge only)

Recommended, to be confirmed at the spec review (A11): while progress is in
darkmem, the primary's handoff stays `<mirror>/work/handoff/latest.md`, and a
worktree's handoff stays local at `<worktree>/.dforge/handoff/latest.md`.
`dforge_latest_file` and `darkmem-config.mjs` return the local path for a
worktree; push, pull and `darkmem-progress-move.mjs` are unchanged and carry
only the primary's file. Reason: a worktree's work (uncommitted files, ignored
state) is host-local, so its handoff is useless on another host, and a mirror
key per worktree would need a name that is stable across hosts, which a
worktree's path is not.

The alternative: a worktree's handoff at
`<mirror>/work/handoff/worktrees/<worktree dir name>/latest.md`; push sends the
session worktree's file (checkpoint still keyed by workstream,
`darkmem-mirror.mjs:757-775`); pull writes only the primary's
(`darkmem-pull.mjs:226-280`); `darkmem-progress-move.mjs:163-164` carries every
worktree's file. Two worktrees with one directory name collide.

### 10. Docs

`reference/project-state.md:97`, `skills/project-status/SKILL.md:32-35`,
`skills/distilling-docs/SKILL.md:74,168`, `reference/auto-run.md:288`,
`skills/finishing-a-development-branch/SKILL.md:362-370`,
`skills/resume-execution/SKILL.md:17-18`, `skills/handoff/SKILL.md:89-128`,
`README.md:337,719`; dagents: `README.md:440,812`, `auto-run.md:259` and the
matching skill lines.

### 11. Out of scope

- Two sessions in one checkout still share its handoff.
- No migration: a primary `latest.md` written before this change that sends the
  next session to a worktree still works, since its prompt says to enter it.
- The executor-session caching from the Fable registry review.

### 12. Merge hazard

The unmerged `chore/audit-2026-11-17` branch (163 commits) deletes dagents'
`darkmem-config.mjs` and rewrites dagents' `roots.sh`, `next-step` and cockpit
`register.tsx`. Its merge will conflict with §1-§6 in dagents; the resolution
is to keep the deletion and re-apply the one-line `_dagents_local` change and
the cockpit/next-step edits. That branch is not touched by this work.

## Tests that pin today's shared file (update or extend)

dforge: `tests/dforge/roots.test.sh:35,45,66,71`; `tests/dforge/next-step.test.sh:73,187-190,227,240,243`; `tests/dforge/next-step-print.test.sh:149,162-165`; `tests/dforge/next-session-routing.acceptance.test.sh:251-260`; `tests/dforge/repo-audit.test.sh:47,63-78`; `tests/dforge/plugin-review-fixes.acceptance.test.sh:276-281`; `tests/dforge/darkmem-sync/config.test.mjs:191-200`; `tests/dforge/darkmem-sync/reconcile-progress.test.mjs:30-33`; `plugins/dforge/tests/cockpit.test.ts:181,5342,5695-5702`; `plugins/dforge/tests/next-session-routing.acceptance.test.ts:499,513`.
dagents: `tests/dagents/roots.test.sh:35,47,49`; `tests/dagents/next-step.test.sh:75,277-280,317,330,333`; `tests/dagents/next-step-print.test.sh:150,163-165`; `tests/dagents/darkmem-sync/config.test.mjs:191`; `tests/dagents/darkmem-sync/reconcile-progress.test.mjs:30`; `plugins/dagents/tests/cockpit.test.ts:5213,5566`.

## Acceptance

Each statement holds in dforge and in dagents (`.dagents/`), except A11 (dforge only).

A1. [test, high] With progress local, `dforge-path latest` run in a linked worktree prints `<worktree>/.dforge/handoff/latest.md`, and run in the primary prints `<primary>/.dforge/handoff/latest.md`.
A2. [test, neg, high] Two linked worktrees each run `next-step` for their own plan: each worktree's handoff holds its own block, and neither file names the other's plan.
A3. [test, neg, high] `next-step PLAN` run in the primary for a plan whose ledger is in worktree W writes W's handoff, its block reads ``Launch in `W`:``, and the primary's handoff is not modified.
A4. [test, high] The block's launch command is `cd '<T>' && ` followed by the host's command; run by bash with the claude or codex command stubbed, it starts in T, including for a T that contains a space and a single quote.
A5. [test, neg, high] Every first prompt opens with ``Work in `<T>` (branch <b>); its handoff is `<absolute handoff path>`.``, and no prompt contains "First enter the existing worktree".
A6. [test, high] `next-step --complete PLAN` and `next-step --kept PLAN` run in a worktree write the primary's handoff, and their block launches in the primary.
A7. [test, neg, high] A turn in the primary that ran next-step and so wrote a worktree's handoff, ending on that block, is released by the stop hook; a turn ending on a hand-typed block with no handoff written this turn is still held.
A8. [test, high] `auto-run clear` run in worktree W reads W's handoff and stores its first prompt; a block in the primary's handoff is not read.
A9. [test, neg, high] The cockpit of a session whose checkout is worktree W reads W's handoff for the resume offer and its resume prompt names that file by absolute path; a handoff in the primary raises no offer in W's session.
A10. [test, high] `repo-audit` lists every checkout that has a handoff, one entry each with its path, branch and recomputed Status and Next, the session's own first; a checkout with none is not listed; the SessionStart snapshot shows only the session checkout's handoff.
A11. [test, medium] With progress in darkmem, a linked worktree's handoff is `<worktree>/.dforge/handoff/latest.md`, the primary's stays `<mirror>/work/handoff/latest.md`, and darkmem push and pull carry only the primary's. Q: keep linked worktrees' handoffs local under darkmem (recommended), or give each a mirror path keyed by worktree directory name?
A12. [test, neg, high] The primary's handoff path is unchanged: a `latest.md` written there before this change is read by `next-step --print --latest`, repo-audit and the cockpit without migration.
A13. [demo, high] The handoff skill tells the session to write its notes to the handoff of the checkout the work is in, the file next-step writes the block into.

## Riskiest assumption

A session's checkout — the directory its scripts run in and the one the
cockpit's `$.process.run` sees — is the worktree after
`cd '<worktree>' && claude …`, and after `EnterWorktree` mid-session.

Evidence: the launch case is shell semantics (Claude Code starts in the
directory it is launched from). The mid-session case: the cockpit re-reads its
checkout after `EnterWorktree` (`register.tsx:959-963`, `:4653-4666`), a change
made after the live bug in `docs/dforge/registers/2026-10-25-token-efficiency.md`
row 10 (b6ab2adb, shipped 4.5.0), and `cockpit.test.ts:5981` pins it with a
mocked checkout. No live run since has confirmed that `$.process.run`, which
passes no cwd, follows the moved directory.

Status: unverified on a live host — the plan's first task verifies it with a
nested session that enters a worktree and checks the cockpit's resume offer.
The design limits the damage if it is wrong: next-step picks T from the ledger,
not the cwd (§2), and the stop hooks look at every checkout (§4); only the
cockpit (§6) would read the primary's file, and its fix is to pass the
session's `$.session.cwd()` explicitly, as `:3696` already does with `cd --`.
