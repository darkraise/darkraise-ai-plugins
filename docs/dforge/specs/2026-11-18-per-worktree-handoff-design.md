# Per-worktree handoff files — design (DRAFT)

**Status:** draft — the decisions and the approach are settled with the owner; the design, acceptance, riskiest assumption, self-review, critic, Fable review and spec review are still to do (dforge:brainstorming, Auto by default steps 1-5).
**Execution strategy:** sequential — inline execution
**Depth:** full — risk
**Register:** docs/dforge/registers/2026-11-18-per-worktree-handoff.md

## Problem

`latest.md` is one file per repository: `scripts/lib/roots.sh` `_dforge_local`
sets `_DFORGE_LATEST` from `$primary` (dforge `:64`, dagents `:53`) while the
ledger root already uses `$base`, the session's own checkout. With darkmem
progress it is one `work/handoff/latest.md` per project mirror. Two sessions in
two worktrees overwrite each other's next-session block, so parallel sessions
are not safe.

## Decisions

- Process: the owner chose "Full dforge flow (Recommended)" over fast mode.
- Scope: "dforge and dagents (Recommended)" — the same change in both, one commit per concern covering both plugins.
- Visibility: "Own + list others (Recommended)" — each session resumes only its own worktree's handoff; repo-audit and project-status list every worktree's handoff.
- Prompt form: "cd in launch + paths in prompt (Recommended)" — the launch command enters the worktree (`cd <worktree> && claude --model … --effort …`) and the first prompt names the worktree, its branch and its handoff file by absolute path.
- Location: "A: in the worktree (Recommended)" — `<worktree>/.dforge/handoff/latest.md` (dagents `.dagents/`), like the ledger; the primary checkout keeps today's path, so no migration; the file goes with the worktree.
- Rejected: B (every handoff in the primary, keyed per worktree: key mapping and cleanup), C (one file with a section per worktree under a lock: every reader learns sections, sessions still contend).

## Design sketch (to be written up as the spec)

1. **Path source.** `_dforge_local`: latest from `$base`. `darkmem-config.mjs:147-149` local branch: `worktreeRoot`, not `repoRoot ?? worktreeRoot`.
2. **Which file `next-step` writes.** The handoff of the checkout the block sends the next session to: `ledger_root` for a plan in flight, `root` for adhoc work in a worktree, else the cwd's checkout. Today it writes the cwd's (always the primary's) file at `:656`, `:672-697`.
3. **Launch line and prompt.** `Launch in <dir>` stays; `launch_cmd` gains a quoted `cd '<dir>' && ` prefix (Claude and Codex hosts; `ROUTE_LAUNCH_CMD` at `:253`). Every prompt opens with `Work in the worktree \`<abs>\` (branch <b>); its handoff is \`<abs latest.md>\`.` (the primary is named the same way), replacing "First enter the existing worktree" (`:376-377`, `:608-609`). `latest_shown` (`:293-294`) becomes the absolute path. auto-run's launch regex (`auto-run.sh:473`) is unanchored, so the `cd` prefix still parses.
4. **Stop hook.** `turn-end.sh` (`:86`, `:127`) and `ui-turn-end.sh` (`:58`) release the stop when this turn wrote the handoff of any worktree of the repository, since `next-step` in the primary may now write a worktree's file.
5. **auto-run.** `ar_handoff`/`ar_clear` read the run's checkout's file (the cockpit calls them from the session checkout); the plan-name check in `ar_clear` (`:503` comment "One latest.md serves every worktree") stays as a guard.
6. **Cockpit** (`register.tsx`, dforge `:146-147`, `:3786-3805`; dagents `:143-144`, `:3536-3544`): `readRun` reads the session checkout's handoff, not `${primary}/.dforge`; `resumePrompt()` names the absolute path; `next-step --print --latest` already runs in the session checkout (`:3693-3696`).
7. **Listing.** `repo-audit` (`:101-121`) prints one handoff line per worktree that has one; `project-status` lists them; the SessionStart snapshot (`snapshot.sh:41`) stays own-only.
8. **darkmem** (dforge and dagents both carry it today): proposal to rate `medium` and ask at the spec review — a linked worktree's handoff lives at `<mirror>/work/handoff/worktrees/<worktree dir name>/latest.md`, the primary keeps `work/handoff/latest.md`; push sends the session worktree's file (checkpoint still keyed by workstream, `darkmem-mirror.mjs:757-775`); pull writes only the primary's file (`darkmem-pull.mjs:226-280`); `darkmem-progress-move.mjs:163-164` carries every worktree's file.
9. **Docs.** `reference/project-state.md:97`, `skills/project-status/SKILL.md:32-35`, `skills/distilling-docs/SKILL.md:74,168`, `reference/auto-run.md:288`, `skills/finishing-a-development-branch/SKILL.md:362-370`, `skills/resume-execution/SKILL.md:17-18`, `README.md:337,719` (dagents: `README.md:440,812`, `auto-run.md:259`).
10. **Out of scope.** Two sessions in one worktree still share its file.

## Tests that pin today's shared file (update or extend)

dforge: `tests/dforge/roots.test.sh:35,45,66,71`; `tests/dforge/next-step.test.sh:73,187-190,227,240,243`; `tests/dforge/next-step-print.test.sh:149,162-165`; `tests/dforge/next-session-routing.acceptance.test.sh:251-260`; `tests/dforge/repo-audit.test.sh:47,63-78`; `tests/dforge/plugin-review-fixes.acceptance.test.sh:276-281`; `tests/dforge/darkmem-sync/config.test.mjs:191-200`; `tests/dforge/darkmem-sync/reconcile-progress.test.mjs:30-33`; `plugins/dforge/tests/cockpit.test.ts:181,5342,5695-5702`; `plugins/dforge/tests/next-session-routing.acceptance.test.ts:499,513`.
dagents: `tests/dagents/roots.test.sh:35,47,49`; `tests/dagents/next-step.test.sh:75,277-280,317,330,333`; `tests/dagents/next-step-print.test.sh:150,163-165`; `tests/dagents/darkmem-sync/config.test.mjs:191`; `tests/dagents/darkmem-sync/reconcile-progress.test.mjs:30`; `plugins/dagents/tests/cockpit.test.ts:5213,5566`.

## Still to settle in the spec

- Riskiest assumption candidate: a session launched with `cd <worktree> && claude` gives the cockpit and every hook the worktree as their checkout, and a session that enters a worktree mid-way (EnterWorktree) moves the cockpit's session checkout with it. Unverified — verify first.
- CI covers two platforms this host does not: Windows Git Bash and uutils (ubuntu-latest); the `cd` quoting must hold on Git Bash. The owner said "do not push" on 2026-11-18, so the early-CI question defaults to no early run.
- The unmerged `chore/audit-2026-11-17` branch removes darkmem from dagents (163 commits not on main): darkmem edits to dagents may conflict with it.
- `finishAction` and `worktree` settings: at their defaults (`dforge-config workflow` printed only `designApproval=whole`).
