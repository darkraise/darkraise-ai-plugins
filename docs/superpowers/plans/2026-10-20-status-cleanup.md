# Status Clean-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

> **External executors:** codex

**Goal:** Close register rows 2, 3, 4 and 6 of the status clean-up: delete every remote branch but `main` and the filter-branch backup ref, delete every local branch but `main`, and backfill `completed.md` for the 21 pre-index plans.

**Architecture:** Task 1 makes the irreversible ref deletions: it tags the three stale tips, checks every remote branch against the spec's restore table, deletes the survivors in one leased push, and deletes the backup ref with its old value. Task 2 deletes the 26 local branches with `git branch -d`. Task 3 appends the backfill to `completed.md` and fills the spec's evidence table in one commit; every line and row is supplied verbatim, derived from `git log --first-parent main` on 2026-10-20.

**Tech Stack:** git, bash.

**Spec:** docs/superpowers/specs/2026-10-20-status-cleanup-design.md

**Execution:** inline — `claude --model sonnet --effort high` — one task of three is heavy (Task 1, risk 3) and is delegated, as is Task 3 for its Executor line; Task 2 (total 1) is self-implemented

**Plan review:** 2026-10-20 — codex gpt-6-astra / xhigh — executability 15 / coherence 16 / coverage 15 / assumptions 16 (round 1)

**Parallelism:** sequential — the spec's strategy: three short tasks over one register and one index; the remote deletion runs alone

## Global Constraints

- Work in the primary checkout, `/root/repositories/darkraise-ai-plugins`, with `main` checked out. Make no worktree and no branch (spec, Where it runs). Never push `main`; Task 1's deletion push is the only write to `origin`.
- Commit as `Darkraise <quangtc94@gmail.com>`, the repository's configured identity (`git config user.name` / `user.email`, checked 2026-10-20). No `Co-Authored-By`, `Claude-Session` or other AI attribution in any commit.
- Commit subjects: `<type>(<scope>): <subject>`, type one of feat|fix|docs|style|refactor|test|chore|perf, at most 50 characters, imperative, no period.
- Under `docs/superpowers/`, edit only what a task names: Task 3 appends to `docs/superpowers/plans/completed.md` and fills the evidence table in the spec. Register rows change only through `<plugin-root>/scripts/register`. `<plugin-root>` is the dr-superpowers root the session's entry point prints (`Plugin root: …`); on this host on 2026-10-20 it was `/root/.claude/plugins/cache/darkraise/dr-superpowers/1.34.1`.
- Every git, test or CLI command runs under `timeout`; only the commit blocks run without one. Leave no process running.
- Run every test suite, `scripts/test-all.mjs` and `claude plugin test` with `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR` in front.
- `claude` and `rg` are shell functions on this host: call `/root/.local/bin/claude`, and use `grep` in scripts and steps.
- Never force: no `git branch -D`, no `git push --force` without a lease, no `git update-ref -d` without the old value. A refusal is reported to the owner, not worked around.
- Finishing, after Task 3 and a clean final review: there is no branch, so dr-superpowers:finishing-a-development-branch is not run. Instead, on `main`:
  1. Run the spec's Testing commands, each under `timeout`: `node scripts/validate-repository.mjs`, `node scripts/test-all.mjs`, `/root/.local/bin/claude plugin validate .` and `/root/.local/bin/claude plugin validate plugins/<name>` for `dforge`, `dr-status`, `darkraise-ui` and `darkraise-win32ui`, and `/root/.local/bin/claude plugin test plugins/dforge` (acceptance A4).
  2. Append this plan's own line to `docs/superpowers/plans/completed.md`: `- <today> \`docs/superpowers/plans/2026-10-20-status-cleanup.md\` — merged into \`main\` at <HEAD sha7 before this commit>`. It is the ordinary finishing form, not a backfill line: it needs no evidence row, and Task 3 Step 3's check leaves it out.
  3. Set rows 2, 3, 4 and 6 of `docs/superpowers/registers/2026-10-20-status-cleanup.md` to `done` with `timeout 60 bash <plugin-root>/scripts/register set <register> <id> done --note "<the commit or command evidence>"`; row 4's note says none of the 21 plans was left out (or names any that was). Then `timeout 60 bash <plugin-root>/scripts/register check docs/superpowers/registers/2026-10-20-status-cleanup.md` must print `register: 0 errors` (acceptance A5).
  4. Commit both files as `docs(registers): close the status clean-up`.
  5. Rerun Task 3 Step 3's check (it must end `lines=21 bad=0` and exit 0), then run `timeout 60 git diff --numstat 0396023..HEAD -- docs/superpowers/plans/completed.md`: its second column must be `0` (acceptance A3, cumulative).
  6. Run dr-superpowers:project-status. Expected: its Not started section names none of the 21 backfilled plans and no other plan, and its recommendation is not rule 5 (spec D3, owner-facing confirmation). Report anything else to the owner.

## Contracts

None. No task consumes another's output; each reads only the repository and the spec.

## Assumptions (evidence)

- Branch inventory, 2026-10-20 after `git fetch --prune origin`: 34 remote branches besides `main`; 31 are ancestors of `origin/main` (`git branch -r --merged origin/main`); 3 are not merged into `main`. Local: 26 branches besides `main`, none unmerged (`git branch --no-merged main` printed nothing); `.git/worktrees/` does not exist (Fable spec review). Tips are the spec's restore table and Task 1's table.
- Stale checks run 2026-10-20: `git cherry main origin/claude/project-thread-bstzjt` printed one `+` line, 6ef002f; for b28c3a8 and 01c453e both parents are ancestors of `main` and `git diff-tree --cc` printed nothing after the header line.
- `ae3141e` is contained only by `refs/original/refs/heads/feat/darkmem-sync-client` (`git for-each-ref --contains`, 2026-10-20): deleting the ref leaves it unreachable. The owner ruled the deletion (spec Decision 8), which is why Task 1 carries it at risk 3.
- Task 3's lines and rows were derived 2026-10-20 from `git log --first-parent main` over each plan's `Create:`/`Modify:`/`Test:` paths outside fenced blocks (prefixes per spec D3, amended after the Codex plan review to count `Test:` lines), and by subjects for terra-scoring and dual-client. Every default-rule landing commit appears in that path-filtered first-parent log (checked 2026-10-20); with `Create:`/`Modify:` alone the statusline plan's 4fc6542 would not. Run against copies of `completed.md` and the spec with Steps 1-2 applied, Step 3's check printed `lines=21 bad=0` and exited 0, and the coverage check in Step 4 printed the 21 plans before the append.
- `completed.md` ends with a newline (`od -c`, 2026-10-20), so the appended block's leading blank line separates it from the last entry.
- Task 1's script, extracted from Step 1 and run in `check` mode from a scratch path on 2026-10-20, printed 34 porcelain lines of the form `-	:refs/heads/<name>	[deleted]` and `Done` (a dry run; nothing was pushed). Step 3 repeats it at execution time.
- Executor lane: `codex-gate` printed `usable=true reason=ok review=true lane=true` (probe, 2026-10-20), `detect-executors.sh` reported codex present, and `docs/superpowers/distilled/constraints.md` turns the lane on, so codex is ticked without asking. Only Task 3 passes the lane gate (total 2, risk 1); Task 1 has risk 3 and Task 2 totals 1.
- Task 2's risk is 1: `git branch -d` refuses an unmerged branch, and every tip stays reachable from `main`, so any branch is recreated with `git branch <name> <tip>`.
- Register rows 2, 3, 4 and 6 are set `planned`, assigned to this plan, in the commit that adds it.

## Task index

1. Delete the remote branches and the backup ref
2. Delete the merged local branches
3. Backfill completed.md for pre-index plans

---

### Task 1: Delete the remote branches and the backup ref

**Files:**
- Create: `.superpowers/sdd/2026-10-20-status-cleanup/d1.sh` (gitignored workspace; not committed)

**Interfaces:**
- Consumes: None
- Produces: None (Contracts)

**Items:** 2, 6

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 3 = 3

The table's third column is the check each branch must pass: `merged` (an ancestor of `origin/main`), `cherry` (exactly the one known commit main lacks) or `mergetip` (a merge whose parents are both on `main` and which adds no combined diff). The script refreshes the tracking refs first, so a tip that moved on the server is caught here; the per-branch lease catches one that moves after the check.

- [ ] **Step 1: Write the script**

Create `.superpowers/sdd/2026-10-20-status-cleanup/d1.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# usage: d1.sh check|delete
set -u
mode=${1:?check or delete}
cd /root/repositories/darkraise-ai-plugins || exit 1
timeout 60 git fetch --prune origin || exit 1
args=(); ok=0; skip=0
while read -r kind name tip; do
  cur=$(git rev-parse -q --verify "refs/remotes/origin/$name") || { echo "SKIP $name: not on origin"; skip=$((skip+1)); continue; }
  [ "$cur" = "$tip" ] || { echo "SKIP $name: tip moved to ${cur:0:7}"; skip=$((skip+1)); continue; }
  case $kind in
    merged)
      git merge-base --is-ancestor "$tip" refs/remotes/origin/main ||
        { echo "SKIP $name: not an ancestor of origin/main"; skip=$((skip+1)); continue; } ;;
    cherry)
      [ "$(git cherry main "$tip" | grep '^+')" = "+ 6ef002f12249079b2fb3af0abad07ca2be36b1c0" ] ||
        { echo "SKIP $name: git cherry differs"; skip=$((skip+1)); continue; } ;;
    mergetip)
      { git merge-base --is-ancestor "$tip^1" main && git merge-base --is-ancestor "$tip^2" main &&
        [ -z "$(git diff-tree --cc "$tip" | tail -n +2)" ]; } ||
        { echo "SKIP $name: merge carries changes main lacks"; skip=$((skip+1)); continue; } ;;
  esac
  ok=$((ok+1))
  args+=("--force-with-lease=refs/heads/$name:$tip" ":refs/heads/$name")
done <<'EOF'
cherry claude/project-thread-bstzjt 6ef002f12249079b2fb3af0abad07ca2be36b1c0
mergetip feat/repo-review-fixes b28c3a8629ae78ecce78c20842c8482d05aa728e
mergetip fix/cockpit-flight-deck-match 01c453eb1cd31ccea3c39b61e66f0658e19bc9ae
merged docs/readme-superpowers-cockpit-tqxrib d272513c18412290c5cdb1d12d436c3f7fc246f1
merged feat/cockpit-buttons 927312bf1caf73d72a304cf718c857ad842658a3
merged feat/cockpit-clear-finished-run 237a82f12c6c9979ac73797a5409a797d8b76dfa
merged feat/cockpit-desktop-layout cb59f7205b3199b6924e21cc93303e24b17bdb7c
merged feat/cockpit-desktop-pictures 294aee054f4f6e6bdf25cc22e6a88f861b825987
merged feat/cockpit-flight-deck 0c11d86cc18349a063cf9ddb02f855cd7dc3022f
merged feat/cockpit-hotkey-underline bd52807e9612db23868dbac830556a0c104ed81d
merged feat/cockpit-minimize c0874ae643c820a3de05869a7e4634bbfb77df20
merged feat/cockpit-pane-overhaul e1b0e7d3a8b832c0baa75549c0460b71422f9411
merged feat/cockpit-repo-place 456986fc7b027c316ea90b56b300e9046ded377b
merged feat/cockpit-shells-remote 646067beb7cc301f9fbdc8a5a0b85af93e0c9800
merged feat/cockpit-shells-section 20795f9c152d002740a9c9c1e363ef0992dc1710
merged feat/cockpit-tier1 640154d30fdb2d87229f9c4a497940f3f7d84300
merged feat/codex-gpt-6-1-sol 41b078c8a37cd64f34a9c33765b96f3783619489
merged feat/codex-task-lane-fixes bf086444dd8eb16d5ad9f10bbb218d42ee3e3e49
merged feat/dr-cockpit 4456ccd0dece7a0fb9543287e0627131115d3ec1
merged feat/greenfield-roadmap 9428122d475628594c7289ce36a5be7c122caa47
merged feat/parallel-execution-option-txulj4 c04d5ddfc12c3647866465f8fa8d7e662cb751bd
merged feat/plan-after-spec-in-session 8d4d3943c8c296f2426a688a628b719ecfca7b1c
merged feat/superpowers-1.27-model-updates f138194b633deed6b05061987d8753f25e21450d
merged feat/superpowers-auto-finish 6c2273e5fa5aa240629242d75968074ce2f007ca
merged feat/test-simplifier 52fe2026ccfb582370a53129300868f0ccf963ad
merged fix/cockpit-desktop-preview c41518ca452f1334dd8470b9a10f283a87e7e03c
merged fix/cockpit-pane-visibility 03983b6850347eabb8b7bc617a3b5d087ac74a91
merged fix/cockpit-shell-exit 1ee74539348032db0b9171ae1b89bbf4ad62be99
merged fix/cockpit-windows-paths 00f59b1694cc9604c22c26d4012ad53e05c7b0c8
merged fix/finish-small-work-in-session-5bh4ji 660d9895589b1b424b06d245d2094ee605399e58
merged fix/sonnet-finish-handoff 6e85fba44f6557e50fe9325514db854aa0597e78
merged fix/superpowers-handoff-checks-running-work e477e3fc0e6217357b00882ee70e345da5b6e8de
merged fix/superpowers-stop-waits-for-background 39cc554f17b7842bed54514a43d862ad53fc9056
merged fix/superpowers-stopped-tasks-not-pending 90989c1f0cfe1d5be2ef83dd48fbf3600f65a560
EOF
echo "ok=$ok skip=$skip"
[ "$ok" -gt 0 ] || exit 0
case $mode in
  check)  timeout 120 git push --dry-run --porcelain origin "${args[@]}" ;;
  delete) timeout 120 git push --porcelain origin "${args[@]}"; rc=$?
          timeout 60 git fetch --prune origin; exit $rc ;;
esac
```

- [ ] **Step 2: Tag the three stale tips**

Run:

```bash
timeout 60 git tag archive/claude/project-thread-bstzjt 6ef002f12249079b2fb3af0abad07ca2be36b1c0
timeout 60 git tag archive/feat/repo-review-fixes b28c3a8629ae78ecce78c20842c8482d05aa728e
timeout 60 git tag archive/fix/cockpit-flight-deck-match 01c453eb1cd31ccea3c39b61e66f0658e19bc9ae
timeout 60 git for-each-ref --format='%(refname:short) %(objectname:short=7)' 'refs/tags/archive/*'
```

Expected: the last command prints exactly the three lines `archive/claude/project-thread-bstzjt 6ef002f`, `archive/feat/repo-review-fixes b28c3a8`, `archive/fix/cockpit-flight-deck-match 01c453e`. Do not push the tags.

- [ ] **Step 3: Dry run**

Run: `timeout 300 bash .superpowers/sdd/2026-10-20-status-cleanup/d1.sh check`
Expected: no `SKIP` line, `ok=34 skip=0`, and porcelain output with one `-` (deletion) line per branch, 34 in all, ending `Done`. A `SKIP` line or a porcelain line flagged `!` (rejected) is not a stop: the spec deletes every branch that passes and reports the rest (D1 step 4). Copy each such line into the task report as an exception, then continue to Step 4, which pushes only the branches that passed.

- [ ] **Step 4: Delete**

Run: `timeout 300 bash .superpowers/sdd/2026-10-20-status-cleanup/d1.sh delete`
Expected: `ok=34 skip=0`, 34 `-` lines in the porcelain output, exit 0. A `!` line means the server refused that branch's lease: it stays on the remote; add it to the task report's exceptions. A non-zero exit with `!` lines is that partial result, not a failure to retry.

- [ ] **Step 5: Delete the backup ref**

Run: `timeout 60 git update-ref -d refs/original/refs/heads/feat/darkmem-sync-client ae3141ec8857fc347032914ccdce281f06858542`
Expected: exit 0. A non-zero exit means the ref moved: report it, do not retry without the old value.

- [ ] **Step 6: Check**

Run:

```bash
timeout 60 git branch -r
timeout 60 git for-each-ref refs/original
timeout 60 git tag -l 'archive/*'
```

Expected: `git branch -r` prints exactly `  origin/HEAD -> origin/main` and `  origin/main`, plus one `  origin/<name>` line for each branch recorded as an exception in Steps 3-4 and no other; `git for-each-ref refs/original` prints nothing; `git tag -l` prints the three archive tags (acceptance A1). Nothing to commit: this task changes refs only.

### Task 2: Delete the merged local branches

**Files:**
- None (refs only)

**Interfaces:**
- Consumes: None
- Produces: None (Contracts)

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 1 = 1

- [ ] **Step 1: Confirm nothing is unmerged**

Run: `timeout 60 git branch --no-merged main`
Expected: no output. Any branch printed: stop and report it to the owner.

- [ ] **Step 2: Delete**

Run:

```bash
timeout 60 git branch -d docs/darkmem-mirror-spec feat/forge-3-naming feat/forge-3-retire-legacy fix/forge-3-review fix/forge-findings
timeout 60 git branch -d worktree-agent-a1daad5a7a3568f67 worktree-agent-a2505bea91f0493de worktree-agent-a26981bac858f9449 worktree-agent-a39e0441f92d7f7f4 worktree-agent-a3a9548ca6a5a141b worktree-agent-a558baa724a781b5d worktree-agent-a594530ebca2b1614 worktree-agent-a5ed5d60570080489 worktree-agent-a6de865e45ee5f7d4 worktree-agent-a74c396acba3a9be1 worktree-agent-a76eb82053215bd38
timeout 60 git branch -d worktree-agent-a879549b98bcbb7a7 worktree-agent-a8c0901909c90adfa worktree-agent-a9f0cca705cb9a024 worktree-agent-aa3a95ddb2a616cb4 worktree-agent-aaaead0960e1efb8d worktree-agent-ac12f13a47ec0c2bd worktree-agent-acca1c71c287f445f worktree-agent-acf28b635d041ebab worktree-agent-ae0d25f9e96ca712f worktree-agent-af8fe7713511adf38
```

Expected: one `Deleted branch <name> (was <sha>).` line per branch, 26 in all. A `not fully merged` error: report that branch; never use `-D`.

- [ ] **Step 3: Check**

Run: `timeout 60 git branch`
Expected: exactly `* main` (acceptance A2). Nothing to commit.

### Task 3: Backfill completed.md for pre-index plans

**Files:**
- Modify: `docs/superpowers/plans/completed.md` (append at the end)
- Modify: `docs/superpowers/specs/2026-10-20-status-cleanup-design.md` (the empty evidence table in D3)

**Interfaces:**
- Consumes: None
- Produces: None (Contracts)

**Items:** 4

**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Append the backfill**

Append exactly this block to the end of `docs/superpowers/plans/completed.md`. The block starts with an empty line; do not change any existing line.

```markdown

Backfilled on 2026-10-20 for plans that landed before this index began; each line's commit and date come from the evidence table in docs/superpowers/specs/2026-10-20-status-cleanup-design.md.

- 2026-07-27 `docs/superpowers/plans/2026-07-27-dcc-superpower-companions.md` — merged into `main` at 03a9e85
- 2026-07-28 `docs/superpowers/plans/2026-07-27-dcc-statusline.md` — merged into `main` at 4fc6542
- 2026-07-28 `docs/superpowers/plans/2026-07-28-dcc-statusline-visual-redesign.md` — merged into `main` at 29bde71
- 2026-08-08 `docs/superpowers/plans/2026-08-08-dcc-statusline-responsive-ui.md` — merged into `main` at 8f97fdf
- 2026-08-09 `docs/superpowers/plans/2026-08-08-dcc-telegram-notify-events.md` — merged into `main` at 7b27e4a
- 2026-08-09 `docs/superpowers/plans/2026-08-09-dcc-statusline-resize-refresh.md` — merged into `main` at 91b9720
- 2026-08-10 `docs/superpowers/plans/2026-08-09-dcc-telegram-notify-reply-back.md` — merged into `main` at cc8594e
- 2026-08-19 `docs/superpowers/plans/2026-08-19-companions-verifier-redesign.md` — merged into `main` at 829075e
- 2026-08-21 `docs/superpowers/plans/2026-08-21-companions-reserve-tier.md` — merged into `main` at e1e8626
- 2026-08-28 `docs/superpowers/plans/2026-08-28-dcc-darkraise-ui.md` — merged into `main` at afb9a35
- 2026-08-28 `docs/superpowers/plans/2026-08-28-dcc-darkraise-win32ui.md` — merged into `main` at 1256275
- 2026-08-31 `docs/superpowers/plans/2026-08-31-companions-external-executors.md` — merged into `main` at 2d514e7
- 2026-09-08 `docs/superpowers/plans/2026-09-08-dual-client-plugin-revision.md` — merged into `main` at 99a1315
- 2026-09-08 `docs/superpowers/plans/2026-09-08-codex-terra-scoring.md` — merged into `main` at 86bfe94
- 2026-09-11 `docs/superpowers/plans/2026-09-11-dr-superpowers-standalone-base.md` — merged into `main` at 266d92c
- 2026-09-11 `docs/superpowers/plans/2026-09-11-dr-superpowers-fold-companions.md` — merged into `main` at 930f784
- 2026-09-12 `docs/superpowers/plans/2026-09-11-dr-superpowers-session-budget.md` — merged into `main` at 095048c
- 2026-09-12 `docs/superpowers/plans/2026-09-12-dr-superpowers-small-model-planning.md` — merged into `main` at 6a4619a
- 2026-09-12 `docs/superpowers/plans/2026-09-12-dr-superpowers-inline-mode.md` — merged into `main` at ee89185
- 2026-09-14 `docs/superpowers/plans/2026-09-14-dr-superpowers-project-state.md` — merged into `main` at 25dea81
- 2026-09-14 `docs/superpowers/plans/2026-09-14-dr-superpowers-judge-seats.md` — merged into `main` at 6d54b1e
```

- [ ] **Step 2: Fill the evidence table**

In `docs/superpowers/specs/2026-10-20-status-cleanup-design.md`, under `Evidence table, filled by the backfill task:`, insert these 21 rows directly below the table's `|---|---|---|---|` separator line, leaving the header and every other line unchanged:

```markdown
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
| `2026-09-12-dr-superpowers-small-model-planning.md` | 6a4619a | 2026-09-12 | default, paths 31/34 under P = plugins/dr-superpowers; run e15d600 to 6a4619a |
| `2026-09-12-dr-superpowers-inline-mode.md` | ee89185 | 2026-09-12 | default, paths 12/12; run f23b0a2 to ee89185 |
| `2026-09-14-dr-superpowers-project-state.md` | 25dea81 | 2026-09-14 | default, paths 22/22; run b8a4a96 to 25dea81 |
| `2026-09-14-dr-superpowers-judge-seats.md` | 6d54b1e | 2026-09-14 | default, paths 13/13; run 11e82c8 to 6d54b1e |
```

- [ ] **Step 3: Check every new line (acceptance A3)**

Run:

```bash
timeout 60 bash -c '
spec=docs/superpowers/specs/2026-10-20-status-cleanup-design.md
n=0; bad=0
while IFS= read -r l; do n=$((n+1))
  printf "%s\n" "$l" | grep -qE "^- [0-9]{4}-[0-9]{2}-[0-9]{2} \`docs/superpowers/plans/[^\`]+\` — merged into \`main\` at [0-9a-f]{7}$" || { echo "FORM $l"; bad=1; continue; }
  d=${l:2:10}; s=${l: -7}; p=${l#*\`docs/superpowers/plans/}; p=${p%%\`*}
  git merge-base --is-ancestor "$s" main || { echo "NOT ON MAIN $s"; bad=1; }
  [ "$(git log -1 --format=%cs "$s")" = "$d" ] || { echo "DATE $s"; bad=1; }
  [ "$(grep -cF "| \`$p\` | $s | $d |" "$spec")" = 1 ] || { echo "NO EVIDENCE $p"; bad=1; }
done < <(awk "f && /^- /; /^Backfilled on 2026-10-20/ {f=1}" docs/superpowers/plans/completed.md | grep -vF "2026-10-20-status-cleanup.md")
echo "lines=$n bad=$bad"; [ "$n" = 21 ] && [ "$bad" = 0 ]'
timeout 60 git diff --numstat 0396023 -- docs/superpowers/plans/completed.md
```

Expected: the first command prints `lines=21 bad=0` and exits 0; any other output or a non-zero exit is a failure to fix before committing. The second prints `24	0	docs/superpowers/plans/completed.md`: 24 lines added (the blank line, the paragraph, the blank line and 21 entries), 0 removed, counted against 0396023 so staged changes are included.

- [ ] **Step 4: Check coverage**

Run:

```bash
timeout 60 bash -c 'source <plugin-root>/scripts/lib/plan.sh; for f in docs/superpowers/plans/*.md; do [ "$(basename "$f")" = completed.md ] && continue; [ -n "$(plan_tasks "$f")" ] || continue; grep -qF "\`$f\`" docs/superpowers/plans/completed.md || echo "MISSING $f"; done'
```

Expected: exactly one line, `MISSING docs/superpowers/plans/2026-10-20-status-cleanup.md` (this plan, indexed at finishing).

- [ ] **Step 5: Validate**

Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/plans/completed.md docs/superpowers/specs/2026-10-20-status-cleanup-design.md
git commit -m "docs(plans): backfill pre-index completions"
```
