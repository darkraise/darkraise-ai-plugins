# Status clean-up

**Execution strategy:** sequential — three short tasks over one register and
one index; the remote deletion is the risky step and runs alone

**Registers:** `docs/superpowers/registers/2026-10-20-status-cleanup.md`; this
spec is its `**Covers:**` line

## Decisions

The owner's answers on 2026-10-20.

1. Row 1: main is not pushed; local main stays ahead of origin on purpose
   (closed `n/a`).
2. Row 5: no Compact Instructions section in CLAUDE.md (closed `n/a`).
3. Row 2 widens to every remote branch except `main`: the three stale
   branches the status report named and the 31 already merged.
4. Row 3 widens to every local branch except `main`: the 21 `worktree-agent-*`
   branches and five other merged branches.
5. Row 4 indexes a plan only on evidence that it landed; bulk indexing was
   rejected.
6. Sequential execution; both design sections approved as presented.

## Problem

The 2026-10-20 project-status report found nothing open but left clean-ups:
34 remote branches and 26 local branches no longer carry work main lacks, and
21 plans dated 2026-07-27 to 2026-09-14 are absent from
`docs/superpowers/plans/completed.md` because they landed before the index
began on 2026-09-16. Project-status rule 5 reads each absent plan as not
started and would recommend re-executing merged work.

## Design

### D1. Remote branches (row 2)

Every branch in the restore table below is deleted from `origin`.

1. Before deleting, re-check each branch against the table. A merged branch
   must be an ancestor of `origin/main`
   (`git merge-base --is-ancestor origin/<name> origin/main`). Each stale
   branch must still sit at its recorded tip, and `git cherry main
   origin/<name>` must list nothing beyond the commits noted for it. A branch
   whose tip moved, or that fails its check, is skipped and reported to the
   owner.
2. Delete the rest in one `git push origin --delete <names…>`, then
   `git fetch --prune origin`.
3. Restore, if ever needed: `git push origin <tip>:refs/heads/<name>`. The
   tips stay reachable from local main (merged) or, for the stale three, from
   this table and the local object store until garbage collection.

Restore table, tips as of 2026-10-20:

| Branch | Tip | Last commit | Kind |
|---|---|---|---|
| `claude/project-thread-bstzjt` | 6ef002f | 2026-10-07 | stale: one commit main lacks, 6ef002f, a CLAUDE.md attribution rule main carries in stronger form |
| `feat/repo-review-fixes` | b28c3a8 | 2026-10-07 | stale: one merge commit, no change main lacks |
| `fix/cockpit-flight-deck-match` | 01c453e | 2026-10-10 | stale: one merge commit, no change main lacks |
| `docs/readme-superpowers-cockpit-tqxrib` | d272513 | 2026-10-11 | merged |
| `feat/cockpit-buttons` | 927312b | 2026-10-09 | merged |
| `feat/cockpit-clear-finished-run` | 237a82f | 2026-10-09 | merged |
| `feat/cockpit-desktop-layout` | cb59f72 | 2026-10-10 | merged |
| `feat/cockpit-desktop-pictures` | 294aee0 | 2026-10-10 | merged |
| `feat/cockpit-flight-deck` | 0c11d86 | 2026-10-10 | merged |
| `feat/cockpit-hotkey-underline` | bd52807 | 2026-10-09 | merged |
| `feat/cockpit-minimize` | c0874ae | 2026-10-10 | merged |
| `feat/cockpit-pane-overhaul` | e1b0e7d | 2026-10-08 | merged |
| `feat/cockpit-repo-place` | 456986f | 2026-10-10 | merged |
| `feat/cockpit-shells-remote` | 646067b | 2026-10-09 | merged |
| `feat/cockpit-shells-section` | 20795f9 | 2026-10-09 | merged |
| `feat/cockpit-tier1` | 640154d | 2026-10-09 | merged |
| `feat/codex-gpt-6-1-sol` | 41b078c | 2026-10-07 | merged |
| `feat/codex-task-lane-fixes` | bf08644 | 2026-10-07 | merged |
| `feat/dr-cockpit` | 4456ccd | 2026-10-07 | merged |
| `feat/greenfield-roadmap` | 9428122 | 2026-10-07 | merged |
| `feat/parallel-execution-option-txulj4` | c04d5dd | 2026-10-10 | merged |
| `feat/plan-after-spec-in-session` | 8d4d394 | 2026-10-10 | merged |
| `feat/superpowers-1.27-model-updates` | f138194 | 2026-10-07 | merged |
| `feat/superpowers-auto-finish` | 6c2273e | 2026-10-10 | merged |
| `feat/test-simplifier` | 52fe202 | 2026-10-07 | merged |
| `fix/cockpit-desktop-preview` | c41518c | 2026-10-10 | merged |
| `fix/cockpit-pane-visibility` | 03983b6 | 2026-10-09 | merged |
| `fix/cockpit-shell-exit` | 1ee7453 | 2026-10-10 | merged |
| `fix/cockpit-windows-paths` | 00f59b1 | 2026-10-10 | merged |
| `fix/finish-small-work-in-session-5bh4ji` | 660d989 | 2026-10-10 | merged |
| `fix/sonnet-finish-handoff` | 6e85fba | 2026-10-08 | merged |
| `fix/superpowers-handoff-checks-running-work` | e477e3f | 2026-10-10 | merged |
| `fix/superpowers-stop-waits-for-background` | 39cc554 | 2026-10-09 | merged |
| `fix/superpowers-stopped-tasks-not-pending` | 90989c1 | 2026-10-10 | merged |

Check: `git branch -r` lists only `origin/HEAD -> origin/main` and
`origin/main`, plus any branch skipped under step 1.

### D2. Local branches (row 3)

Delete with `git branch -d`, which refuses an unmerged branch; a refusal is
reported to the owner, never forced with `-D`.

- The 21 `worktree-agent-*` branches, all at da585ac. No worktree uses them.
- `docs/darkmem-mirror-spec` (da3875e), `feat/forge-3-naming` (db20780),
  `feat/forge-3-retire-legacy` (74c2ece), `fix/forge-3-review` (5d794f7),
  `fix/forge-findings` (3be9b0c).

Check: `git branch` lists only `main`.

### D3. Backfill completed.md (row 4)

For each plan below, find its landing commit on `main`:

- **Default.** Collect the paths the plan names on `Create:` and `Modify:`
  lines. When at least half have history on main, the landing commit is the
  latest commit on main that touched any of them on or before the date the
  plan's work ended. That date is the last commit of a contiguous run of
  commits whose subjects match the plan's scope.
- **Outliers.** `2026-09-12-dr-superpowers-small-model-planning.md` (0 of 30
  paths found as written): resolve its paths against the plugin folder of
  that date. `2026-08-31-companions-external-executors.md` (2 of 15):
  check its named files and commit subjects matching its tasks.
  `2026-09-08-codex-terra-scoring.md` and
  `2026-09-08-dual-client-plugin-revision.md` (no named paths): commit
  subjects matching their task titles.
- **No evidence.** A plan with no landing commit is left out of the index and
  reported to the owner; row 4's note names it.

Append to `completed.md`, at its end and oldest first, one line saying the
following entries were backfilled on 2026-10-20 for plans that landed before
the index began, then one line per landed plan:

```markdown
- <landing date> `docs/superpowers/plans/<file>` — merged into `main` at <sha7>
```

The file is append-only: existing lines are not reordered or edited. The
backfill task also fills the evidence table below in this spec.

Plans: `2026-07-27-dcc-statusline.md`,
`2026-07-27-dcc-superpower-companions.md`,
`2026-07-28-dcc-statusline-visual-redesign.md`,
`2026-08-08-dcc-statusline-responsive-ui.md`,
`2026-08-08-dcc-telegram-notify-events.md`,
`2026-08-09-dcc-statusline-resize-refresh.md`,
`2026-08-09-dcc-telegram-notify-reply-back.md`,
`2026-08-19-companions-verifier-redesign.md`,
`2026-08-21-companions-reserve-tier.md`, `2026-08-28-dcc-darkraise-ui.md`,
`2026-08-28-dcc-darkraise-win32ui.md`,
`2026-08-31-companions-external-executors.md`,
`2026-09-08-codex-terra-scoring.md`,
`2026-09-08-dual-client-plugin-revision.md`,
`2026-09-11-dr-superpowers-fold-companions.md`,
`2026-09-11-dr-superpowers-session-budget.md`,
`2026-09-11-dr-superpowers-standalone-base.md`,
`2026-09-12-dr-superpowers-inline-mode.md`,
`2026-09-12-dr-superpowers-small-model-planning.md`,
`2026-09-14-dr-superpowers-judge-seats.md`,
`2026-09-14-dr-superpowers-project-state.md`.

Evidence table, filled by the backfill task:

| Plan | Landing commit | Date | Evidence |
|---|---|---|---|

Check: `scripts/repo-audit` and a project-status pass list no plan absent
from `completed.md` other than those reported under No evidence.

## Testing

No code changes. After the backfill: `node scripts/validate-repository.mjs`,
`node scripts/test-all.mjs`, `claude plugin validate` on the marketplace and
every Claude plugin, and `claude plugin test plugins/dforge`, each with a
timeout and nothing left running.

## Acceptance

A1. [read, high] D1's check holds; every skipped branch is reported with its
reason.
A2. [read, high] D2's check holds; no branch was deleted with `-D`.
A3. [read, high] `completed.md` gained one backfill note and one line per
landed plan, each matching the line form, each plan's line backed by an
evidence table row; no earlier line changed (`git diff` shows additions only).
A4. [test, high] The Testing commands pass on main.
A5. [read, high] The register has no `open` row; every row has six cells
(`scripts/register check`).

## Riskiest assumption

That every plan's landing can be told apart from later work that touched the
same files: the statusline and companions files were edited by many later
plans, so "latest commit touching a named path" without the date bound would
date a plan to work long after it landed. The end-of-run bound in D3 is the
guard; an ambiguous plan is dated by its last scope-matching commit and the
evidence cell says so.
