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
6. Sequential execution; both design sections (branches; backfill) approved
   as presented.
7. After the Fable review: the three stale tips are kept as local
   `archive/<branch>` tags, never pushed.
8. After the Fable review: the filter-branch backup ref
   `refs/original/refs/heads/feat/darkmem-sync-client` is deleted (row 6).

## Problem

The 2026-10-20 project-status report found nothing open but left clean-ups:
34 remote branches and 26 local branches carry no change main lacks in
substance, and 21 plans dated 2026-07-27 to 2026-09-14 are absent from
`docs/superpowers/plans/completed.md` because they landed before the index
began on 2026-09-16. Project-status rule 5 reads each absent plan as not
started and would recommend re-executing merged work.

## Where it runs

Every task runs in the primary checkout with `main` checked out: D1 and D2
change refs, not files, and D3 is one documentation commit, so no worktree
and no feature branch are made. Commits land directly on local `main`, which
is not pushed (Decision 1). There is no branch to finish; the closing commit
updates the register.

## Design

### D1. Remote branches (row 2)

Every branch in the restore table below is deleted from `origin`.

1. **Archive the stale three.** `git tag archive/<name> <tip>` for each
   branch whose Kind is stale. The tags are local only and are the restore
   path for those three.
2. **Check the stale three.**
   - `claude/project-thread-bstzjt`: `git cherry main
     origin/claude/project-thread-bstzjt` prints exactly one `+` line, for
     6ef002f.
   - `feat/repo-review-fixes` and `fix/cockpit-flight-deck-match` (merge-commit
     tips): `git merge-base --is-ancestor <tip>^1 main` and
     `git merge-base --is-ancestor <tip>^2 main` both exit 0, and
     `git diff-tree --cc <tip>` prints nothing after its header line.
     `git cherry` skips merge commits, so it cannot carry this check.
3. **Check the merged 31.** `git merge-base --is-ancestor <tip> origin/main`
   exits 0 for each.
4. **Delete with a lease.** One push carries every branch that passed, each
   with its full tip as the lease, so a branch pushed to since this table was
   written is refused by the server rather than deleted:
   `git push origin --force-with-lease=refs/heads/<name>:<full sha> … :refs/heads/<name> …`.
   A branch that failed a check, or whose lease is refused, stays on the
   remote and is reported to the owner. Then `git fetch --prune origin`.
5. **Restore.** A merged branch: `git push origin <tip>:refs/heads/<name>`;
   its tip stays reachable from main. A stale branch:
   `git push origin archive/<name>:refs/heads/<name>`.

Restore table, tips as of 2026-10-20:

| Branch | Tip | Last commit | Kind |
|---|---|---|---|
| `claude/project-thread-bstzjt` | 6ef002f | 2026-10-07 | stale: one commit main lacks, 6ef002f, a CLAUDE.md attribution rule main carries in stronger form |
| `feat/repo-review-fixes` | b28c3a8 | 2026-10-07 | stale: one merge commit; both parents on main, no combined diff |
| `fix/cockpit-flight-deck-match` | 01c453e | 2026-10-10 | stale: one merge commit; both parents on main, no combined diff |
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
`origin/main`, plus any branch reported under step 4; `git tag -l 'archive/*'`
lists the three stale names at their tips.

### D2. Local refs (rows 3 and 6)

Delete branches with `git branch -d`, which refuses an unmerged branch; a
refusal is reported to the owner, never forced with `-D`.

- The 21 `worktree-agent-*` branches, all at da585ac. No worktree uses them.
- `docs/darkmem-mirror-spec` (da3875e), `feat/forge-3-naming` (db20780),
  `feat/forge-3-retire-legacy` (74c2ece), `fix/forge-3-review` (5d794f7),
  `fix/forge-findings` (3be9b0c).
- Row 6: `git update-ref -d refs/original/refs/heads/feat/darkmem-sync-client
  ae3141ec8857fc347032914ccdce281f06858542`. The old value makes the delete
  refuse if the ref moved.

`completed.md` records one plan as merged into `docs/darkmem-mirror-spec`;
that line stays as written (append-only) after the branch is gone.

Check: `git branch` lists only `main`; `git for-each-ref refs/original`
prints nothing.

### D3. Backfill completed.md (row 4)

For each plan below, find its landing commit on `main`:

- **Default.** Collect the paths the plan names on `Create:`, `Modify:` and
  `Test:` lines outside fenced code blocks, with the plan's own prefix
  applied. When at least half have history,
  list `git log --first-parent main --format='%h %cs %s' -- <paths>`. The
  plan's run is the consecutive commits in that list whose subjects match the
  plan's title or task titles; the landing commit is the last commit of that
  run, so a merge commit is seen as main's head after the merge, and the bound
  is a commit, not a date. The landing date is that commit's `%cs`.
- **Prefixes.** `2026-09-12-dr-superpowers-small-model-planning.md` defines
  `P` as `plugins/dr-superpowers`.
  `2026-08-31-companions-external-executors.md` names paths relative to
  `plugins/dcc-superpower-companions/`.
- **Subjects.** A plan under the half threshold, and the two that name no
  paths (`2026-09-08-codex-terra-scoring.md`,
  `2026-09-08-dual-client-plugin-revision.md`), are matched by
  `git log --first-parent main --format='%h %cs %s'` subjects against their
  task titles, in the weeks around the plan's date.
- **No evidence.** A plan with no landing commit under either rule is left
  out of the index and reported to the owner; row 4's note names it.

Append to `completed.md`, at its end, this paragraph exactly (no backticks,
and it does not contain the phrase the readers match on), a blank line, then
one line per landed plan, oldest first:

```markdown
Backfilled on 2026-10-20 for plans that landed before this index began; each line's commit and date come from the evidence table in docs/superpowers/specs/2026-10-20-status-cleanup-design.md.

- <landing date> `docs/superpowers/plans/<file>` — merged into `main` at <sha7>
```

The file is append-only: existing lines are not reordered or edited.

The evidence table below is filled in the same commit as the `completed.md`
lines, so the two cannot drift. Each Evidence cell gives the rule applied
(default or subjects), the paths matched as n/m for the default rule, and the
first and last commit of the run.

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
| `2026-07-27-dcc-superpower-companions.md` | 03a9e85 | 2026-07-27 | default, paths 13/14; run af9424b to 03a9e85 |
| `2026-07-27-dcc-statusline.md` | 4fc6542 | 2026-07-28 | default, paths 31/31; run 40b30a4 to 4fc6542 |
| `2026-07-28-dcc-statusline-visual-redesign.md` | 29bde71 | 2026-07-28 | default, paths 23/23; merge 29bde71 of the plan's branch |
| `2026-08-08-dcc-statusline-responsive-ui.md` | 8f97fdf | 2026-08-08 | default, paths 19/20; merge 8f97fdf of the plan's branch |
| `2026-08-08-dcc-telegram-notify-events.md` | 7b27e4a | 2026-08-09 | default, paths 10/10; merge 7b27e4a of the plan's branch |
| `2026-08-09-dcc-statusline-resize-refresh.md` | 91b9720 | 2026-08-09 | default, paths 11/11; merge 91b9720 of the plan's branch |
| `2026-08-09-dcc-telegram-notify-reply-back.md` | cc8594e | 2026-08-10 | default, paths 15/15; merge cc8594e of the plan's branch |
| `2026-08-19-companions-verifier-redesign.md` | 829075e | 2026-08-19 | default, paths 21/21; merge 829075e of the plan's branch |
| `2026-08-21-companions-reserve-tier.md` | e1e8626 | 2026-08-21 | default, paths 19/19; merge e1e8626 of the plan's branch |
| `2026-08-28-dcc-darkraise-ui.md` | afb9a35 | 2026-08-28 | default, paths 9/10; merge afb9a35 of the plan's branch |
| `2026-08-28-dcc-darkraise-win32ui.md` | 1256275 | 2026-08-28 | default, paths 9/10; merge 1256275 of the plan's branch |
| `2026-08-31-companions-external-executors.md` | 2d514e7 | 2026-08-31 | default, paths 14/15 under plugins/dcc-superpower-companions/; merge 2d514e7 of the plan's branch |
| `2026-09-08-dual-client-plugin-revision.md` | 99a1315 | 2026-09-08 | subjects; run c9eba8f to 99a1315: rename plugin and track installations, support native Codex execution, separate client marketplaces |
| `2026-09-08-codex-terra-scoring.md` | 86bfe94 | 2026-09-08 | subjects; single commit 86bfe94, add Terra and 0-9 scoring |
| `2026-09-11-dr-superpowers-standalone-base.md` | 266d92c | 2026-09-11 | default, paths 18/19; run 2235ea9 to 266d92c |
| `2026-09-11-dr-superpowers-fold-companions.md` | 930f784 | 2026-09-11 | default, paths 20/22; run 58ac9cb to 930f784 |
| `2026-09-11-dr-superpowers-session-budget.md` | 095048c | 2026-09-12 | default, paths 26/28; run 0d86b53 to 095048c |
| `2026-09-12-dr-superpowers-small-model-planning.md` | 6a4619a | 2026-09-12 | default, paths 33/33 under P = plugins/dr-superpowers; run e15d600 to 6a4619a |
| `2026-09-12-dr-superpowers-inline-mode.md` | ee89185 | 2026-09-12 | default, paths 12/12; run f23b0a2 to ee89185 |
| `2026-09-14-dr-superpowers-project-state.md` | 25dea81 | 2026-09-14 | default, paths 22/22; run b8a4a96 to 25dea81 |
| `2026-09-14-dr-superpowers-judge-seats.md` | 6d54b1e | 2026-09-14 | default, paths 13/13; run 11e82c8 to 6d54b1e |

Check: for every file under `docs/superpowers/plans/` for which `plan_tasks`
(`scripts/lib/plan.sh` in the dr-superpowers plugin) prints a task,
``grep -qF "`docs/superpowers/plans/<file>`" docs/superpowers/plans/completed.md``
succeeds, except the No-evidence set. A project-status pass is the
owner-facing confirmation.

## Commits

1. `docs(plans): backfill pre-index completions` — `completed.md` and this
   spec's evidence table.
2. `docs(registers): close the status clean-up` — rows 2, 3, 4 and 6.

D1 and D2 change no tracked file.

## Testing

No code changes. After the backfill: `node scripts/validate-repository.mjs`,
`node scripts/test-all.mjs`, `claude plugin validate` on the marketplace and
every Claude plugin, and `claude plugin test plugins/dforge`, each with a
timeout and nothing left running.

## Acceptance

A1. [read, high] D1's check holds; the three `archive/*` tags exist at their
tips; every branch left on the remote is reported with its reason.
A2. [read, high] D2's check holds; no branch was deleted with `-D`.
A3. [test, high] Each of the 21 lines `completed.md` gained after the
backfill paragraph for a pre-index plan (this plan's own line, written at
finishing in the ordinary form, is not one of them) matches
``^- [0-9]{4}-[0-9]{2}-[0-9]{2} `docs/superpowers/plans/[^`]+` — merged into `main` at [0-9a-f]{7}$``;
for each, `git merge-base --is-ancestor <sha> main` exits 0 and
`git log -1 --format=%cs <sha>` equals its date; each has exactly one
evidence table row carrying its plan, commit and date;
`git diff --numstat 0396023..HEAD -- docs/superpowers/plans/completed.md`
reports 0 removed lines.
A4. [test, high] The Testing commands pass on main.
A5. [read, high] Rows 2, 3, 4 and 6 are `done`; row 4's note names every plan
left out under No evidence, or says none was; `scripts/register check` reports
0 errors.

## Riskiest assumption

That every plan's landing can be told apart from later work that touched the
same files: the statusline and companions files were edited by many later
plans, so the latest commit touching a named path would date a plan to work
long after it landed. The run-of-matching-subjects bound in D3 is the guard;
an ambiguous plan is dated by its last subject-matching commit and the
evidence cell says so.

## Review rulings

Fable review, 2026-10-20, verdict approve with changes; all fifteen findings
applied.

1. Deletion is leased per branch (finding 1).
2. Merge-commit stale tips are checked by parents and combined diff, not
   `git cherry` (finding 2); both passed on 2026-10-20.
3. The stale three are kept as `archive/*` tags (finding 3, Decision 7).
4. Tasks run on main in the primary checkout; no branch to finish
   (finding 4).
5. The landing rule follows `--first-parent` main and ends at a commit
   (finding 5); the threshold falls through to subjects.
6. D3's check uses `plan_tasks` and `grep`, not `scripts/repo-audit`, which
   does not read `completed.md` (finding 6).
7. Plan prefixes named (7); note text fixed (8); A3 and A5 made testable
   (9, 10); evidence cell defined and committed with the index (11); commit
   plan added (12); wording reconciled (13); the backup ref deleted as row 6
   (14, Decision 8); the `docs/darkmem-mirror-spec` index line noted (15).

Codex plan review, 2026-10-20: D3's default rule counts `Test:` lines and
skips fenced code blocks, because a plan's last commit is often a test (the
statusline plan's landing commit 4fc6542 touches only `tests/e2e.test.sh`);
A3 excludes this plan's own finishing line and checks removals with
`--numstat`, which counts a removed `- ` entry that `^-[^-]` would miss.
