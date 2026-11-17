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
| plan in flight | the checkout holding the plan's workspace `<state>/sdd/<slug>/`, found with `_plan_ledger_tree` (`plan.sh:287`, `:313`) in both stores — under darkmem the ledger is in the mirror, so `ledger_root` (`plan.sh:284`) cannot name it; the checkout next-step runs in when no workspace exists |
| everything else: `--complete`, `--kept`, a plan found finished, `--draft`, `--adhoc`, `--project` | the checkout next-step runs in — after finishing's Option 1 that is the primary, after Option 3 (`--kept`) the kept worktree, whose block already names it (`:474-475`) |

One helper computes T, and `next-step --target <same arguments>` prints T's
absolute handoff path and exits without writing; the handoff skill (§7) uses
it, so the notes and the block cannot land in different files.

`dir` (the `Launch in` directory, today always `$primary` at `:274`, `:283`)
becomes T. T's handoff path is resolved in a subshell
(`$(dforge_stores_init "$T"; dforge_latest_file "$T")`), so next-step's cached
roots stay the session checkout's. The marker counts
(`handoff_counts "$primary"`) and the `finish.json` clearing are unchanged.
`--print --latest` reads the handoff of the checkout it runs in.

`--complete` and `--kept` replace the file wholesale today (`:676-678`). They
still do when the existing marker names the same subject or there is no
marker; when it names another subject (another session's block in the same
checkout), they keep the notes, replace only the `## Next session` section,
and print `next-step: replaced the block for <subject>` on stderr.

### 3. Launch line and prompt

- **Launch command.** The launch line targets a POSIX shell. On a POSIX host
  (no `cygpath` on PATH), `launch_cmd` gains the prefix `cd '<T>' && `, T
  single-quoted with each `'` written `'\''`, on Claude and Codex hosts alike
  (`launch_for`, `execution_launch`, `ROUTE_LAUNCH_CMD` at `:253`). On a
  Windows host (`cygpath` on PATH) the command stays as today, since
  PowerShell 5.1 has no `&&` and cmd.exe keeps single quotes literally; the
  `Launch in `<T>`` line names the directory. With no launch command (the
  `Launch: see the **Execution:** line` case) the line becomes
  ``Launch from `<T>`: see the **Execution:** line in `<plan>`.``
- **Prompt.** Every first prompt opens with
  ``Work in `<T>` (branch <b>); its handoff is `<absolute handoff path>`. If your working directory is not `<T>`, enter it first.``
  The second sentence matters where no relaunch happens: an auto run's
  cockpit clears the session and pastes the prompt, so the `cd` prefix never
  runs. `<b>` is `git -C T branch --show-current`, or `detached at <sha7>`. This
  replaces both "First enter the existing worktree" sentences (`:376-377`,
  `:608-609`). `latest_shown` (`:293-294`) becomes T's absolute handoff path,
  so the draft and adhoc prompts name the same file.
- auto-run's launch regex (`auto-run.sh:473`) is unanchored, so it still
  finds `claude --model … --effort …` behind the prefix.

### 4. Stop hooks

- `wrote_block` in `turn-end.sh` (`:127`) and the release in `ui-turn-end.sh`
  (`:58`): `next-step` run in the primary may now write a worktree's file, so
  the stop is released when **any** checkout's handoff newer than the turn's
  stamp has a Next line that appears in the message (`ending_released`,
  `next-ending.sh:12-14`, applied to each file). Taking only the newest file
  would hold a session whose own block was followed by another session's
  write. A new `roots.sh` helper `dforge_latest_files [DIR]` (dagents
  `dagents_latest_files`) prints the handoff path of every checkout
  `git worktree list --porcelain` names whose directory exists, plus the
  mirror's file while progress is in darkmem.
- `changed_here` (`turn-end.sh:86`) keeps comparing against the session
  checkout's own handoff: the `--complete` and `--project` next-step it waits
  for writes there (§2), so another worktree's write cannot release it.
- The released condition is otherwise unchanged: a block next-step wrote this
  turn, never a hand-typed one.

### 5. auto-run

`ar_handoff` (`auto-run.sh:464-476`) reads the handoff of the checkout it runs
in (`git rev-parse --show-toplevel`), not `ar_primary_root`'s. The cockpit and
the model call it from the session's checkout, which is where next-step wrote
the block (§2: an in-flight plan's T is its workspace's checkout, where an
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

`skills/handoff/SKILL.md` step 3 writes the notes to the path
`scripts/next-step --target` prints for the same arguments step 4 will pass,
so the notes and the block next-step merges land in one file. `skills/resume-execution`
step 1 reads the handoff of the checkout it starts in (repo-audit prints it).

### 8. Listing

- `repo-audit` (`:99-121`) prints one entry per checkout that has a handoff,
  the session's own first, each with its path and the checkout's branch. Only
  the session's own is recomputed by `next-step --print --latest` (bounded by
  `with-timeout 20`, as today) and carries the count of commits on its HEAD
  since it was written; every other entry shows its stored Status and Next
  lines marked `stored`, so the cost does not grow with the worktree count.
  A worktree that is prunable or whose directory is gone is skipped with one
  line. No handoff anywhere prints `- none`.
- `project-status` lists them the same way and recommends the session's own.
- The SessionStart snapshot (`snapshot.sh:41`) shows only the session's own
  handoff, plus one count line when other checkouts hold one:
  `<n> other checkouts hold a handoff (scripts/repo-audit lists them).`

### 9. darkmem (dforge only)

Recommended, to be confirmed at the spec review (A11): while progress is in
darkmem, the primary's handoff stays `<mirror>/work/handoff/latest.md`, and a
worktree's handoff stays local at `<worktree>/.dforge/handoff/latest.md`.
`dforge_latest_file` and `darkmem-config.mjs` return the local path for a
worktree; pull and `darkmem-progress-move.mjs` are unchanged and carry only the
primary's file. Push (`darkmem-push.mjs:392`) still sends only the primary's
file, and when run from a linked worktree prints
`worktree handoff stays local: <path>`, so the handoff skill's "the push
carries … latest.md" (`skills/handoff/SKILL.md:130-132`) is not read as true
for a worktree. Reason: a worktree's work (uncommitted files, ignored
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
`skills/resume-execution/SKILL.md:17-18`, `skills/handoff/SKILL.md:89-132`,
`README.md:337,719`; dagents: `README.md:440,812`, `auto-run.md:259` and the
matching skill lines.

### 11. Out of scope

- Two sessions in one checkout still share its handoff. This includes a
  worktree session that finishes with Option 1 and so runs `--complete` in the
  primary beside a primary session; §2's notes-keeping rule limits the loss to
  the other session's `## Next session` block, named on stderr.
- No migration: a primary `latest.md` written before this change that sends the
  next session to a worktree still works, since its prompt says to enter it;
  it stays in the primary, offered to primary sessions, until the next write
  there replaces it.
- dagents with darkmem progress: dagents' `darkmem-config.mjs` darkmem branch
  keeps one mirror handoff per project until `chore/audit-2026-11-17` removes
  darkmem from dagents (the owner's 2026-11-17 ruling), so dagents' acceptance
  tests cover local progress only.
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

Each statement holds in dforge and in dagents (`.dagents/`, local progress), except A11 and A14 (dforge only).

A1. [test, high] With progress local, `dforge-path latest` run in a linked worktree prints `<worktree>/.dforge/handoff/latest.md`, and run in the primary prints `<primary>/.dforge/handoff/latest.md`.
A2. [test, neg, high] Two linked worktrees each run `next-step` for their own plan: each worktree's handoff holds its own block, and neither file names the other's plan.
A3. [test, neg, high] `next-step PLAN` run in the primary for a plan whose workspace is in worktree W writes W's handoff, its block reads ``Launch in `W`:``, and the primary's handoff is not modified.
A4. [test, high] On a POSIX host the block's launch command is `cd '<T>' && ` followed by the host's command; run by bash with the claude or codex command stubbed, it starts in T, including for a T that contains a space and a single quote. With `cygpath` on PATH the command carries no `cd` prefix.
A5. [test, neg, high] Every first prompt opens with ``Work in `<T>` (branch <b>); its handoff is `<absolute handoff path>`. If your working directory is not `<T>`, enter it first.``, and no prompt contains "First enter the existing worktree".
A6. [test, high] `next-step --complete PLAN` and `next-step --kept PLAN` write the handoff of the checkout they run in, and their block launches there.
A7. [test, neg, high] A turn in the primary that ran next-step and so wrote a worktree's handoff, ending on that block, is released by the stop hook; a turn ending on a hand-typed block with no handoff written this turn is still held.
A8. [test, high] `auto-run clear` run in worktree W reads W's handoff and stores its first prompt; a block in the primary's handoff is not read.
A9. [test, neg, high] The cockpit of a session whose checkout is worktree W reads W's handoff for the resume offer and its resume prompt names that file by absolute path; a handoff in the primary raises no offer in W's session.
A10. [test, high] `repo-audit` lists every checkout that has a handoff, the session's own first and recomputed, every other with its stored Status and Next marked `stored`; a checkout with none, or a prunable worktree, gets no entry; the SessionStart snapshot shows only the session checkout's handoff plus the count line for the others.
A11. [test, medium] With progress in darkmem, a linked worktree's handoff is `<worktree>/.dforge/handoff/latest.md`, the primary's stays `<mirror>/work/handoff/latest.md`, darkmem push and pull carry only the primary's, and push run from a linked worktree prints `worktree handoff stays local: <path>`. Q: keep linked worktrees' handoffs local under darkmem (recommended), or give each a mirror path keyed by worktree directory name?
A12. [test, neg, high] The primary's handoff path is unchanged: a `latest.md` written there before this change is read by `next-step --print --latest`, repo-audit and the cockpit without migration.
A13. [test, high] For every mode, `next-step --target <arguments>` prints the path the same `next-step <arguments>` then writes, and writes nothing itself.
A14. [test, neg, high] With progress in darkmem, `next-step PLAN` run in the primary for a plan whose workspace is in worktree W launches in W and names W in its prompt, not the primary (dforge only).
A15. [test, neg, high] `next-step --complete PLAN` run where the existing handoff's marker names another subject keeps that file's notes, replaces only its `## Next session` section and names the displaced subject on stderr.
A16. [test, neg, high] While session S's turn runs, another worktree's session writes its own handoff: S's turn ending on its own next-step block is still released, and S's turn that completed a plan without running next-step is still held.

## Riskiest assumption

A session's checkout — the directory its scripts run in and the one the
cockpit's `$.process.run` sees — is the worktree after
`cd '<worktree>' && claude …`, after `EnterWorktree` mid-session, and still
after the cockpit clears that session (`/clear`) for an auto run's next phase.

Evidence: the launch case is shell semantics (Claude Code starts in the
directory it is launched from). The mid-session case: the cockpit re-reads its
checkout after `EnterWorktree` (`register.tsx:959-963`, `:4653-4666`), a change
made after the live bug in `docs/dforge/registers/2026-10-25-token-efficiency.md`
row 10 (b6ab2adb, shipped 4.5.0), and `cockpit.test.ts:5981` pins it with a
mocked checkout. No live run since has confirmed that `$.process.run`, which
passes no cwd, follows the moved directory.

Whether `/clear` keeps the working directory has no evidence in the
repository.

Status: unverified on a live host — the plan's first task verifies it with a
nested session that enters a worktree, checks the cockpit's resume offer,
clears the session and checks its working directory again. If `/clear` resets
it, the prompt's "If your working directory is not `<T>`, enter it first"
(§3) is what moves the session back.
The design limits the damage if it is wrong: next-step picks T from the ledger,
not the cwd (§2), and the stop hooks look at every checkout (§4); only the
cockpit (§6) would read the primary's file, and its fix is to pass the
session's `$.session.cwd()` explicitly, as `:3696` already does with `cd --`.

## Critic findings

One `dforge:judge-opus` round: 0 Blocker, 4 High, 6 Medium, 2 Nit.

- [High, fixed] Under darkmem, `ledger_root` names the caller's checkout, not the plan's worktree: §2 now finds T from the plan's workspace with `_plan_ledger_tree`; A14 tests it.
- [High, fixed] `--complete`/`--kept` into the primary overwrote another session's file, and the `--kept` rationale was wrong: §2 now sends both to the checkout next-step runs in, keeps another subject's notes (A15), and §11 names the remaining sharing.
- [High, fixed] "Newest handoff" in the stop hooks breaks under parallel sessions: §4 now releases on any file newer than the stamp whose Next line the message carries, and `changed_here` keeps the session checkout's file; A16 tests it.
- [High, fixed] The `cd '<T>' &&` prefix breaks PowerShell and cmd.exe: §3 adds it on POSIX hosts only; A4 covers the Windows case.
- [Medium, fixed] The handoff skill re-derived T from prose: `next-step --target` prints it (§2, §7); A13 is now a test.
- [Medium, fixed] "Work in `<T>`" was weaker than the sentence it replaced and `/clear` was unverified: the prompt now says to enter T, and the riskiest assumption covers `/clear`.
- [Medium, fixed] Push implied a worktree handoff was synced: §9 adds the `worktree handoff stays local` line and the SKILL.md:130-132 doc edit.
- [Medium, answered] dagents' darkmem branch still shares one mirror handoff: kept as is under the owner's 2026-11-17 ruling that removes darkmem from dagents; §11 names the gap and dagents' tests cover local progress only.
- [Medium, fixed] repo-audit's cost grew with the worktree count and prunable worktrees broke it: §8 recomputes only the own handoff and skips prunable ones.
- [Medium, fixed] A primary session got no sign of worktree handoffs: §8 adds the snapshot count line.
- [Nit, fixed] `dforge_stores_init` for T switched next-step's cached roots: §2 resolves T's path in a subshell.
- [Nit, fixed] A pre-upgrade block for a worktree stays in the primary: §11 says so.
