# darkmem mirror, increment 2: wiring, plan names and deletion

Date: 2026-09-28
Status: design, owner-approved on 2026-09-28 (two rulings below).
Parent: `docs/superpowers/specs/2026-09-23-darkmem-mirror-design.md`, whose
Delivery section defines this increment (§2 roots, §4 triggers, §5
promotion) and names the one decision it left open. Register:
`docs/superpowers/registers/2026-09-24-darkmem-mirror.md` rows 2, 3 and 4.
Server half: §4 below, a change to the `darkmem` repository.

## Rulings (owner, 2026-09-28)

1. **A plan keeps its repository name in both modes.** Everything that names a
   plan or document names it `docs/superpowers/<rest>`, whether the file is in
   the repository or in the mirror. Chosen over naming by darkmem uri (every
   recorded name changes format) and over a symlink from the repository into
   the mirror (reverses the parent's §2, and `rg` and the Grep tool skip
   symlinked directories by default).
2. **Deleting a synced document archives it on darkmem.** Chosen over a
   hash-guarded delete (darkmem's delete cascades revisions, so a deleted
   source is unrecoverable) and over never propagating deletions (every other
   machine keeps pulling the file back).

## 1. Names and the two roots

A **name** is a repository-relative spelling, `docs/superpowers/<rest>` for a
document and `.superpowers/<rest>` for working files. Ledger identity lines
(`# SDD ledger — plan: <name>`), register `Covers` and `Assigned` cells,
`plans/completed.md` lines, `Source:` lines and darkmem's `CLAUDE.md`
citations all hold names and keep their current spelling. A cross-repository
`Assigned` cell (`darkmem: docs/superpowers/...`) is unchanged.

**Where files live today (inventory, 2026-09-28).** Local mode is not one
root. A plan's workspace, `.superpowers/sdd/<plan>/`, is in the *worktree*
executing it (`sdd-workspace`, `next-step` and `repo-audit` take the working
directory's top level), and it mixes files that sync (`progress.md`,
`handoff.md`) with files that are machine-local by nature (task briefs,
reports, review packages, `amendments.md`). `handoff/latest.md` and
`sdd/budget-log.tsv` are in the *primary* checkout. Documents are in each
worktree's own `docs/superpowers`. Nine scripts find a root by running `git`
in the plan's own directory (`plan_repo_canon`, `plan_ledger`,
`plan_amendments_file`, `plan_require_same_repo`, `plan-lint`, `plan-revise`,
`plan-amend`, `register check`, `repo-audit`'s ledger names), which fails for
a file outside any repository.

A new `scripts/lib/roots.sh`, sourced by `scripts/lib/plan.sh` (so by every
script that sources it), defines one helper per location:

| Helper | Local mode (today's paths) | darkmem mode |
|---|---|---|
| `sp_docs_root` | `<worktree>/docs/superpowers` | `<mirror>/superpowers` |
| `sp_ledger_dir SLUG` | `<worktree>/.superpowers/sdd/SLUG` | `<mirror>/work/sdd/SLUG` |
| `sp_latest_file` | `<primary>/.superpowers/handoff/latest.md` | `<mirror>/work/handoff/latest.md` |
| `sp_workspace SLUG` | `<worktree>/.superpowers/sdd/SLUG` | `<worktree>/.superpowers/sdd/SLUG` |
| `sp_resolve NAME` | `<worktree>/NAME` | `docs/superpowers/<rest>` → `<sp_docs_root>/<rest>`; any other name → `<worktree>/NAME` |
| `sp_name FILE` | FILE relative to `<worktree>` | under `sp_docs_root` → `docs/superpowers/<rel>`; else relative to `<worktree>` |

`<worktree>` is the working directory's `git rev-parse --show-toplevel`,
`<primary>` the primary checkout, `<mirror>` is
`~/.dr-superpowers/mirror/<project>`. The ledger and `handoff.md` live in
`sp_ledger_dir`, the synced place; briefs, reports, review packages and
`amendments.md` stay in `sp_workspace`, which is local in both modes (in local
mode the two are one directory, as today). `budget-log.tsv` keeps its primary
checkout path. So the parent's §2 table is refined, not reversed: its
`sp_work_root` is `sp_ledger_dir` plus `sp_latest_file`.

`sp_name` is computed from the roots, never by searching the path for a
`superpowers/` segment. `darkmem-mirror.mjs`'s `pathToUri` takes the roots and
does the same, which fixes the doubled uri the current regex produces when a
checkout or project directory is itself named `superpowers` (it matches the
leftmost segment).

**Mode** comes from `darkmem-config.mjs`'s `resolveMode`. A `--mode` entry
point on that module prints `local`, or `darkmem` and the mirror directory
separated by a tab; a `ConfigError` exits 2 with its message, and a missing
`node` is local mode. `roots.sh` calls it once per script run and caches the
answer in a shell variable. In local mode every helper returns today's path.

**Rewiring.** Every script that builds one of these paths, or derives a root
from a plan's directory, calls the helpers instead (the inventory's list: the
four `plan.sh` functions, `register.sh`'s `register_files`, `snapshot.sh`,
`next-step`, `plan-lint`, `plan-revise`, `plan-amend`, `register`,
`repo-audit`, `sdd-workspace`, and the scripts that call it). A script that
receives a plan argument accepts a name or a path and converts it with
`sp_name` before recording or comparing it. Skill and reference prose (63
lines) writes `<docs root>/…`, `<ledger dir>` and `<latest.md>`, and
`using-superpowers` states both expansions once.

**Git in the skills.** Skill text tells an agent to `git commit` a spec, plan
or `completed.md` line, and distilling-docs and project-status run `git log`,
`git show`, `git ls-files` and `git rm` on documents. In darkmem mode the
document is not in the repository: every "commit the spec/plan" step becomes
"push" (`darkmem-sync push`), `project-status` dates a document by its newest
revision, and distilling-docs follows §2. The code a plan changes is still
committed as today.

**`plan_require_same_repo` becomes `plan_require_same_project`.** Local mode
keeps today's check (plan and working directory share a git top level).
darkmem mode accepts a plan whose file lies under `sp_docs_root`; the mirror
is one per project, shared by every worktree, so a worktree session reaching
the mirror's plan is correct rather than a split. `plan_ledger` resolves
through `sp_ledger_dir` and `plan_amendments_file` through `sp_workspace`,
never from the plan file's directory.

## 2. Deletion archives

Sync state (`<mirror>/.sync-state.json`) already records each synced
document's uri and last hash. The manifest serves each document's `id`.

- **push:** a uri recorded in state whose file is gone from the mirror is
  moved on darkmem to `superpowers/archive/<stamp>/<rest>`, where `<stamp>` is
  the UTC time as `YYYYMMDDTHHMMSSZ` (a name deleted twice never collides),
  through §4's `PATCH` with `expected_hash` set to the recorded hash. Success
  drops the state entry. A `409` on the hash (edited on darkmem since the last
  sync) or on the uri is reported as a conflict and the state entry is kept;
  the next pull then reports the file as changed remotely.
- **pull:** skips every uri under `superpowers/archive/`. A uri recorded in
  state and absent from the manifest was archived or deleted elsewhere: the
  local file is removed with its state entry when its hash still equals the
  recorded one, and reported as a conflict otherwise.
- **`darkmem-sync restore <name>`:** moves the newest archived copy of `<name>`
  back to its uri with `expected_hash` set to the archived copy's hash, then
  pulls it. Refused when the uri is occupied.
- **`status`:** lists pending archives (`deleted: <uri>`).

**distilling-docs in darkmem mode.** A source is eligible when it is synced and
unchanged since the last push (the analogue of tracked and clean). Its
`Source:` line cites `<name>@r<revision id>`, the newest id from the keyed
revisions route. The two commits become two pushes, entries first and
deletions second, and `restore` replaces `git revert`. Local mode is
unchanged.

## 3. Triggers and promotion (rows 3 and 4)

Parent §4 and §5 as written, with the two defects row 3's note records:

- The handoff skill defines the literal `- Draft: \`<spec path>\`` line for a
  stop during design, beside the `- Plan:` line it already defines, since
  `checkpointTarget` reads either.
- `session-start.sh` and the Stop hook export `DR_SUPERPOWERS_SESSION_ID` from
  the hook payload into every `darkmem-sync` call; `runKey` already prefers it,
  so the session-record lookup (stale records, non-ASCII path mismatch) is
  only the fallback.

## 4. Server half (darkmem repository)

`PATCH /api/v1/documents/{document_id}`:

- admits a `capture`-scoped key (`require_scope("capture")`), joining the five
  document routes the mirror already syncs through; login auth is still accepted;
- takes an optional `expected_hash`. `update_document_metadata` adds
  `AND content_hash IS NOT DISTINCT FROM :expected_hash` to its own `UPDATE`
  (the rowcount-in-the-writer pattern `put` uses, never read-then-compare);
  no row returned is resolved by one follow-up existence read into
  `DocumentTargetUnresolved` (404) or `DocumentHashConflict` (409). A call
  naming only tags takes the existing `SELECT … FOR UPDATE` path and compares
  there, under the lock.

MCP `document_update` in id mode takes the same `expected_hash` and answers a
`hash_conflict` envelope, keeping the pair two-door. `docs/two-door-parity.md`'s
`documents.metadata` row, the keyed-route sentence in darkmem's `CLAUDE.md`
(MCP endpoint section) and the SDK generator's contract check are updated. The
guards leg runs after the change (a changed route signature), and the change
is deployed before the plugin half is tested against a live instance.

## 5. Testing

- Local mode: every existing suite passes unchanged with no config file.
- Layout: every `roots.sh` helper in local mode returns today's path from a
  linked worktree (documents and workspace in the worktree, `latest.md` in the
  primary checkout), and the mirror paths in darkmem mode; a `ConfigError`
  stops the script rather than falling back to local.
- Names: `sp_resolve`/`sp_name` round-trip in both modes, including a checkout
  and a project both named `superpowers`; `pathToUri` regression for the
  doubled uri.
- `plan_require_same_project`: accepts a mirror plan from a worktree in
  darkmem mode, refuses a foreign checkout's plan in local mode.
- Stub server: archive push sends the stamped uri and recorded hash; a `409`
  keeps the state entry and reports a conflict; pull removes an unchanged
  file whose uri left the manifest and reports a changed one; pull ignores
  `archive/`; `restore` moves back and refuses an occupied uri.
- Handoff: a design-phase `latest.md` with a `- Draft:` line files its
  checkpoint under the draft's slug.
- Server: route and MCP tests for the key scope, a matching and a stale
  `expected_hash`, 404 versus 409 disambiguation, and the tags-only path.
- `node scripts/validate-repository.mjs` and `claude plugin validate`.

## Delivery

1. Server half (§4) in darkmem, deployed. It gets its own plan in the darkmem
   repository, since a plan executes in one repository.
2. Plugin: helpers and `pathToUri` (§1), then rewiring, then deletion (§2),
   then triggers and promotion (§3).

Parent §6 (moving a repository) stays owner-run after both land.

## Not in scope

- Rewriting names already recorded; ruling 1 makes that unnecessary.
- Purging archived documents; `superpowers/archive/` grows until the owner
  deletes it by hand.
- Windows CI (row 6) and the sync hardening (row 7), tracked separately.
