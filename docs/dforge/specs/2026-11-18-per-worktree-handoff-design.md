# Per-worktree handoff files — design

**Status:** approved — the owner, 2026-11-18: "Approve and run unattended".
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
- darkmem worktree handoffs (A11): "Right" — a linked worktree's handoff stays local under darkmem.
- `--complete` after Option 2: "Primary checkout (Recommended)" — a completed plan's follow-on block always goes to the primary.
- Windows launch line (Fable ruling, approved with the spec): on a Windows host the launch command carries no `cd` prefix, since no one line runs in PowerShell 5.1, cmd.exe and Git Bash; the `Launch in` line and the prompt name the directory instead.

Finish: merge

Worktree: in-place

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
`<checkout>/.dforge/handoff/latest.md` (dagents `<checkout>/.dagents/handoff/latest.md`),
except the primary's while progress is in darkmem, which is
`<mirror>/work/handoff/latest.md` (§9).

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
| plan in flight | in order: (1) progress local — the checkout of the plan's identity-checked ledger, the second field `plan_ledger_any` prints; (2) progress in darkmem with a ledger in the mirror — among linked worktrees holding `<state>/sdd/<slug>/`: the checkout next-step runs in when it is one of them, else the first `git worktree list` names; when none holds it, the primary if the primary does; (3) otherwise the checkout next-step runs in |
| `--complete`, or a plan found finished | the primary, as today: the follow-on work starts there, whichever finishing option ran (Option 2 keeps the worktree for review feedback) |
| `--kept`, `--draft`, `--adhoc`, `--project` | the checkout next-step runs in — after Option 3 (`--kept`) the kept worktree, whose block already names it (`:474-475`) |

The primary holds `<state>/sdd/<slug>/` for most plans whatever worktree
executes them: the plan review writes its lint and rounds into the workspace
`sdd-workspace` creates in the planning checkout (`sdd-workspace:38-41`), and
an auto run's switch runs `finish-choice set --plan` there. So the lookup
never takes the first checkout `git worktree list` names, which is the
primary. `_plan_ledger_tree` (`plan.sh:287`, `:313-320`) takes the same order,
since it shares the fault. `plan_final_review_state` (`:572`) is given T, not
`ledger_root`, which under darkmem is the caller's checkout.

One helper computes T, and `next-step --target <same arguments>` prints T's
absolute handoff path and exits without writing; the handoff skill (§7),
finishing (§7) and auto-run (§5) use it, so the notes, the block and its
readers cannot disagree. `--target` skips the background-work check as
`--print` does (it never exits 5), fails with the same usage and missing-file
exits as the real call, and is a usage error with `--latest`.

`dir` (the `Launch in` directory, today always `$primary` at `:274`, `:283`)
becomes T. T's handoff path is resolved in a subshell
(`$(dforge_stores_init "$T"; dforge_latest_file "$T")`), so next-step's cached
roots stay the session checkout's. The marker counts
(`handoff_counts "$primary"`) and the `finish.json` clearing are unchanged.
`--print --latest` reads the handoff of the checkout it runs in.

`--complete` and `--kept` replace the file wholesale today (`:676-678`). They
still do when there is no marker, when the marker names the same subject, when
its kind is `complete`, or when `plan_finished` records its plan: none of these
is another session's live block. Otherwise (another session's block in the
same checkout) they keep the notes, replace only the `## Next session`
section, and print `next-step: replaced the block for <subject>` on stderr,
naming the marker's kind (`adhoc`, `project`) when its subject is `-`.

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
- **Prompt.** Every first prompt next-step writes — plan, draft, adhoc,
  project, complete and kept — opens with
  ``Start in `<T>` (branch <b>); its handoff is `<absolute handoff path>`. If your working directory is not `<T>`, enter it first.``
  "Start in", not "Work in": a plan with no workspace yet begins at
  executing-plans' Setup, which creates the worktree, and an executor that
  read "Work in `<primary>`" literally would commit tasks there, which stops an
  auto run (`auto-run.sh:296-302`). The second sentence matters where no
  relaunch happens: an auto run's cockpit clears the session and pastes the
  prompt, so the `cd` prefix never runs. `(branch <b>)` is
  `git -C T branch --show-current`; a detached checkout reads
  ``(detached at `<sha7>`)``. This
  replaces both "First enter the existing worktree" sentences (`:376-377`,
  `:608-609`). `latest_shown` (`:293-294`) becomes T's absolute handoff path,
  so the draft and adhoc prompts name the same file.
- auto-run's launch regex (`auto-run.sh:473`) is unanchored, so it still
  finds `claude --model … --effort …` behind the prefix.

### 4. Stop hooks

- `wrote_block` in `turn-end.sh` (`:127`) and the release in `ui-turn-end.sh`
  (`:58`): `next-step` run in the primary may now write a worktree's file, so
  the stop is released by the session checkout's handoff as today
  (`ending_released`, `next-ending.sh:12-28`), or by another checkout's
  handoff newer than the turn's stamp whose Status line and Next line both
  appear in the message. Taking only the newest file would hold a session
  whose own block was followed by another session's write; matching the Next
  line alone would let another worktree's fresh block release a hand-typed
  one, since final-phase Next lines are the same for every plan. The
  cannot-write branch (a hand-typed block passes when the file cannot be
  written, `next-ending.sh:16-28`) applies to the session checkout's handoff
  only.
- A new `roots.sh` helper `dforge_latest_files [DIR]` (dagents
  `dagents_latest_files`) prints each checkout's resolved handoff once, for
  every checkout `git worktree list --porcelain` names whose directory exists:
  under darkmem the mirror's file in place of the primary's local path
  (dagents under darkmem: the mirror's file alone), computed by rule with no
  node start per worktree.
- `changed_here` (`turn-end.sh:86`) compares against the file the
  transition's next-step writes: the primary's handoff for a completed plan
  (§2), the session checkout's for `--project`. Another worktree's write to
  its own handoff cannot release it; a later write to the primary's handoff
  by another session (its `--complete`, or a primary session) still can, as
  today (§11).
- The released condition is otherwise unchanged: a block next-step wrote this
  turn, never a hand-typed one.

### 5. auto-run

`ar_handoff` (`auto-run.sh:464-476`) reads the handoff the T helper (§2)
resolves for the run's attached plan, and the handoff of the checkout it runs
in only when no plan is attached; never `ar_primary_root`'s unless T is the
primary. Reading by plan, not by working directory, matters twice: the
cockpit's own `auto-run clear --phase` at the switch (`autoRunCall`,
`register.tsx:3095`, `:3214`) passes `$.process.run` no directory, and after
the switch the primary's handoff still holds the plan's start block, which
passes `ar_clear`'s plan-name guard, so a clear run from the primary while the
plan executes in W would resume at "begin at Setup". `autoRunCall` also passes
the session checkout in argv, as `:3696` does with `cd --`. The plan-name
guard stays; its comment (`:503`, "One latest.md serves every worktree") is
rewritten to say the guard catches a block another session left in T.

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

- `skills/handoff/SKILL.md` step 3 writes the notes to the path
  `scripts/next-step --target` prints for the same arguments step 4 will pass,
  so the notes and the block next-step merges land in one file.
- `skills/resume-execution` step 1 reads the handoff the first prompt names by
  absolute path, and the session checkout's only when the prompt names none:
  the session may not have entered T yet, the case §3's second sentence
  exists for.
- **Finishing carries a worktree's notes.** For unplanned work the notes in
  `latest.md` are the only record (`skills/handoff/SKILL.md:83-85`), and
  finishing's Option 1 removes the worktree, whose ignored files
  `git worktree remove` deletes (`references/cleanup.md:9-12`), before Step 7
  runs `next-step --adhoc` in the primary (`SKILL.md:372-377`), whose block
  names the primary's handoff as the authority. So before Step 6, finishing
  reads the worktree's handoff; an open item in its notes counts as something
  that follows, beside register rows and findings (`SKILL.md:373-374`). The
  carry also applies when `references/cleanup.md:49-59` leaves a host-owned
  worktree in place. When something follows, it writes the notes
  sections with every item still open to the path
  `next-step --target --adhoc …` prints in the primary, then runs `--adhoc`,
  as Step 5b already carries the ledger's open findings (`SKILL.md:311-312`).

### 8. Listing

- `repo-audit` (`:99-121`) prints one entry per checkout that has a handoff,
  the session's own first, each with its path and the checkout's branch. Only
  the session's own is recomputed by `next-step --print --latest` (bounded by
  `with-timeout 20`, as today) and carries the count of commits on its HEAD
  since it was written; every other entry shows its stored Status and Next
  lines marked `stored`, so the cost does not grow with the worktree count.
  A worktree that is prunable or whose directory is gone is skipped with one
  line. Each stored entry shows its age from the marker's `at=`, since it is
  never recomputed. No handoff anywhere prints `- none`.
- `project-status` lists them the same way and recommends the session's own.
- The compaction snapshot (`snapshot.sh:41`, built only on the `compact`
  source, `session-start.sh:181-195`) stays own-only.
- The SessionStart context, on every source, beside the roadmap line
  (`session-start.sh:104-113`), adds one count line when other checkouts hold
  a handoff younger than the cockpit's three-day offer window
  (`register.tsx:150`), so an abandoned worktree adds no permanent line:
  `<n> other checkouts hold a handoff (scripts/repo-audit lists them).`

### 9. darkmem (dforge only)

Confirmed by the owner (A11): while progress is in
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
`skills/finishing-a-development-branch/SKILL.md:362-379` and its
`references/cleanup.md` (the carry, §7),
`skills/resume-execution/SKILL.md:17-18`, `skills/handoff/SKILL.md:89-132`,
`scripts/next-step:1-53` (the header's "the primary checkout's" and the usage
for `--target`), `skills/executing-plans/SKILL.md:144-146`,
`reference/project-state.md:106-111,131`,
`README.md:337,719`; dagents: `README.md:440,812`, `auto-run.md:259` and the
matching skill lines.

### 11. Out of scope

- Two sessions in one checkout still share its handoff. This includes a
  worktree session whose plan completes, since `--complete` writes the
  primary's handoff beside any primary session; §2's notes-keeping rule limits
  the loss to the other session's `## Next session` block, named on stderr.
- Finishing carries a worktree's unplanned-work notes into the primary (§7);
  a discarded worktree's handoff goes with it.
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
A2. [test, neg, high] Two linked worktrees each run `next-step` for their own plan, while the primary also holds `<state>/sdd/<slug>/` for both plans: each worktree's handoff holds its own block, neither file names the other's plan, and the primary's handoff is not modified.
A3. [test, neg, high] `next-step PLAN` run in the primary for a plan whose ledger is in worktree W, while the primary also holds `<state>/sdd/<slug>/`, writes W's handoff, its block reads ``Launch in `W`:``, and the primary's handoff is not modified.
A4. [test, high] On a POSIX host the block's launch command is `cd '<T>' && ` followed by the host's command; run by bash with the claude or codex command stubbed, it starts in T, including for a T that contains a space and a single quote. With `cygpath` on PATH the command carries no `cd` prefix.
A5. [test, neg, high] The first prompt of every mode — plan, draft, adhoc, project, complete and kept — opens with ``Start in `<T>` (branch <b>); its handoff is `<absolute handoff path>`. If your working directory is not `<T>`, enter it first.``, a detached T reading ``(detached at `<sha7>`)``; no prompt contains "First enter the existing worktree".
A6. [test, high] `next-step --complete PLAN` run in a worktree writes the primary's handoff and its block launches in the primary; `next-step --kept PLAN` writes the handoff of the checkout it runs in and launches there.
A7. [test, neg, high] In `turn-end.sh` and `ui-turn-end.sh`, a primary turn that is held (a ledger written this turn; UI changes for `ui-turn-end.sh`) and ran next-step, which wrote a worktree's handoff, is released when it ends on that block, including a darkmem case where the block is in the mirror's file; the same turn ending on a hand-typed block with no handoff written this turn is still held.
A8. [test, neg, high] `auto-run clear` for a run whose attached plan executes in worktree W reads W's handoff and stores its first prompt, whether it runs in W, in the primary (where the primary's handoff still holds the plan's start block, which is not read), or as the cockpit's phase clear with no working directory passed.
A9. [test, neg, high] The cockpit of a session whose checkout is worktree W reads W's handoff for the resume offer and its resume prompt names that file by absolute path; a handoff in the primary raises no offer in W's session.
A10. [test, high] `repo-audit` lists every checkout that has a handoff, the session's own first and recomputed, every other with its stored Status and Next marked `stored` and its age; a checkout with none gets no entry; a prunable worktree gets one skip line and no entry. On a `startup` source the SessionStart context carries the count line for other checkouts' handoffs younger than three days, and the compaction snapshot shows only the session checkout's handoff.
A11. [test, confirmed] With progress in darkmem, a linked worktree's handoff is `<worktree>/.dforge/handoff/latest.md`, the primary's stays `<mirror>/work/handoff/latest.md`, darkmem push and pull carry only the primary's, and push run from a linked worktree prints `worktree handoff stays local: <path>`.
A12. [test, neg, high] The primary's handoff path is unchanged: a `latest.md` written there before this change is read by `next-step --print --latest`, repo-audit and the cockpit without migration.
A13. [test, high] For every mode, `next-step --target <arguments>` prints the path the same `next-step <arguments>` then writes, writes nothing itself, never exits 5 over background work, exits as the real call does on a usage error or a missing plan, and is a usage error with `--latest`.
A14. [test, neg, high] With progress in darkmem, `next-step PLAN` run in the primary for a plan whose workspace is in worktree W, while the primary also holds `<state>/sdd/<slug>/`, writes W's handoff and leaves the primary's handoff unmodified, launches in W and names W in its prompt, not the primary (dforge only).
A15. [test, neg, high] `next-step --complete PLAN` and `next-step --kept PLAN`, run where the existing handoff's marker names another live subject, keep that file's notes, replace only its `## Next session` section and name the displaced subject (or its kind, for a subject of `-`) on stderr; a marker of kind `complete` or for a finished plan is replaced wholesale.
A16. [test, neg, high] While session S's turn runs, another worktree's session writes its own handoff: S's turn ending on its own next-step block is still released, S's turn that completed a plan without running next-step is still held, and S's hand-typed block carrying only the other block's Next line is still held.
A17. [demo, high] finishing-a-development-branch tells the session, under Option 1, before Step 6, when the session worked in a linked worktree, to treat an open item in the worktree handoff's notes as something that follows, carry the worktree handoff's open notes into the path `next-step --target --adhoc …` prints in the primary, and only then run `--adhoc`.

## Riskiest assumption

A session's checkout — the directory its scripts run in and the one the
cockpit's `$.process.run` sees — is the worktree after
`cd '<worktree>' && claude …`, after `EnterWorktree` mid-session, and still
after the cockpit clears that session (`/clear`) for an auto run's next phase.
The cockpit's `$.process.run` calls pass no directory: the resume offer's
next-step (`register.tsx:3696`, which already passes one in argv) and the
auto-run calls through `autoRunCall` (`:3095`, `:3214`, given one by §5).

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
nested session that enters a worktree, checks the cockpit's resume offer and
an `autoRunCall` phase clear, clears the session and checks its working
directory again. If `/clear` resets
it, the prompt's "If your working directory is not `<T>`, enter it first"
(§3) is what moves the session back.
The design limits the damage if it is wrong: next-step picks T from the
ledger, not the cwd (§2); auto-run reads by the attached plan (§5); the stop
hooks look at every checkout (§4). Only the cockpit's `readRun` (§6) would read
the primary's file, and its fix is to pass the session's `$.session.cwd()`
explicitly, as `:3696` already does with `cd --`.

## Critic findings

One `dforge:judge-opus` round: 0 Blocker, 4 High, 6 Medium, 2 Nit.
Superseded where `## Review rulings` differs.

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

## Review rulings

Fable, round 1 (`.dforge/spec-review-2026-11-18-per-worktree-handoff-design-1-report.md`): 14 rulings, 2 undecided.

- [Blocker] §2 T for a plan in flight resolved to the primary, which holds `<state>/sdd/<slug>/` after the plan review — T now comes from the identity-checked ledger (local) or a linked worktree's workspace (darkmem); `_plan_ledger_tree` and `plan_final_review_state` follow; A2, A3, A14 state the primary's workspace.
- [Blocker] Unplanned-work notes in a worktree's handoff were lost when Option 1 removes the worktree — finishing carries them into the primary before Step 6 (§7); A17 (demo, since it is skill wording no script reads).
- [Medium] Cockpit `autoRunCall` and a primary-side clear could read the wrong handoff — `ar_handoff` reads by the attached plan through the T helper, `autoRunCall` passes the checkout; A8 and the riskiest assumption extended.
- [Medium] The count line reached only compacted sessions — moved to the SessionStart context on every source, three-day window; A10 tests a `startup` source.
- [Low] Notes-keeping rule: kind named for a `-` subject; `complete` or finished-plan markers replaced wholesale; A15 covers `--kept`.
- [Low] Prompt opens "Start in", detached reads "(detached at `<sha7>`)"; A5 names the modes.
- [Low] Stop-hook release: cannot-write branch for the own handoff only; another checkout releases only on Status and Next both in the message.
- [Low] `dforge_latest_files` prints each checkout's resolved handoff once, the mirror's in place of the primary's under darkmem; the Terms paragraph names the exception.
- [Low] resume-execution reads the handoff the first prompt names.
- [Low] `--target` skips the background-work check, keeps the real call's exits, and is a usage error with `--latest`; A13.
- [Low] A7 names the hold, covers both hooks and a darkmem case.
- [Low] Windows exception kept and recorded in `## Decisions` for the owner.
- [Nit] A10 asserts the prunable skip line; stored entries show their age.
- [Nit] §10 adds `next-step:1-53`, `executing-plans/SKILL.md:144-146`, `project-state.md:106-111,131`.
- Undecided, settled at the spec review: A11 (local, confirmed) and `--complete` after Option 2 (always the primary).

Fable, round 2 (`.dforge/spec-review-2026-11-18-per-worktree-handoff-design-2-report.md`): both Blockers closed, 0 Blocker and 0 High open; five wording rulings applied — §2 rule (2) cell text, §4 `changed_here` sentence, A14 asserts the file written, A17 and §7 aligned on "under Option 1, before Step 6" with open notes counted as something that follows, and the superseded line under `## Critic findings`.
