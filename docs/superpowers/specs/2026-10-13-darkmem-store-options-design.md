# darkmem store options: documents and progress chosen separately

Date: 2026-10-13
Status: design, owner-approved section by section on 2026-10-13.
Supersedes: §1 of `docs/superpowers/specs/2026-09-23-darkmem-mirror-design.md`
(configuration and modes) and §1 of
`docs/superpowers/specs/2026-09-28-darkmem-mirror-wiring-design.md` (names and
the two roots). Both specs' other sections stand as amended in §5 below.
Register: `docs/superpowers/registers/2026-09-24-darkmem-mirror.md` rows 2, 3,
4, 5, 16, 17 and 18; `docs/superpowers/registers/2026-10-11-dr-forge.md` row 13.
Amended 2026-10-13 by §7 (owner rulings on rows 5, 17 and 18, revised after an
independent review) and the matching §4 refusals.

**Execution strategy:** sequential — the options feed the roots, the roots feed
the rewiring and the sync, and the move and triggers build on all of them.

## Rulings (owner, 2026-10-13)

1. **Two options, global with a per-repository override.** `documentStore` and
   `progressSource` are forge-config keys; a repository's darkmem mapping entry
   can override either. Chosen over global keys only and over per-repository
   keys only.
2. **A flipped option moves the family automatically** at the next session
   start, refused while a plan is in progress. Chosen over an owner-run move
   and over no move.
3. **Documents leaving the repository are deleted with a staged `git rm`**
   that the owner commits. Chosen over a commit made by the move and over
   leaving the repository copy in place.
4. **A new spec, two plans,** rather than editing the approved specs in place
   or one large plan.
5. **A Notion-like progress board is a separate darkmem project.** This spec
   only makes ledger entries carry properties such a board can read (§3).

## Why

The 2026-09-23 design has one switch: a mapped repository keeps both its
planning documents and its progress in darkmem. The owner wants each family
chosen on its own, for example documents committed in a public repository
while its progress lives in darkmem. darkmem serves the two families through
separate routes and stores (`/api/v1/documents`, `/api/v1/worklog`), so no
server change is needed.

The plugin was renamed dr-superpowers → dr-forge after the parent specs were
written. Every name below is the dr-forge one; the pre-2.0 names are read as
fallbacks exactly as `darkmem-config.mjs` and `scripts/lib/forge-dir.sh` do
today (`~/.dr-superpowers/`, `docs/superpowers/`, `.superpowers/`,
`DR_SUPERPOWERS_SESSION_ID`).

## 1. Configuration and resolution

**The families.**

| Family | Files |
|---|---|
| documents | the docs directory: `specs/`, `plans/`, `registers/`, `distilled/`, `notes/` and every other file under it |
| progress | each plan's `progress.md` (ledger) and `handoff.md`, and `handoff/latest.md` |

A plan's `handoff.md` is progress. Today `darkmem-mirror.mjs` syncs it as a
document (uri `superpowers/handoff/<slug>.md`); §2 moves it to the progress
family, synced only when progress is in darkmem. Its uri is unchanged.

**The keys.** `config/schema.mjs` gains two keys in a new `darkmem` group:

```js
documentStore: {
  type: 'enum', values: ['local', 'darkmem'], default: 'darkmem', env: 'DR_FORGE_DOCUMENT_STORE', group: 'darkmem', target: 'forge',
  label: 'Documents', title: 'Document store',
  description: 'Where a mapped repository keeps its specs, plans, registers and notes: local in the repository, or darkmem through the mirror. A change moves them at the next session start.',
},
progressSource: {
  type: 'enum', values: ['local', 'darkmem'], default: 'darkmem', env: 'DR_FORGE_PROGRESS_SOURCE', group: 'darkmem', target: 'forge',
  label: 'Progress', title: 'Progress tracking source',
  description: 'Where a mapped repository keeps its plan ledgers and handoffs: local in the repository, or darkmem through the mirror. A change moves them at the next session start.',
},
```

A per-repository override outranks the environment variable, unlike other
forge-config keys, because it is the more specific choice.

The default `darkmem` keeps the meaning of an existing mapping: a mapped
repository with no override keeps both families in darkmem.

**The override.** An entry in `darkmem.repos` may carry `documentStore` and/or
`progressSource`, each `local` or `darkmem`; any other value is a
`ConfigError`.

```json
{
  "documentStore": "darkmem",
  "progressSource": "darkmem",
  "darkmem": {
    "url": "http://<darkmem host>",
    "api_key_env": "DARKMEM_API_KEY",
    "repos": {
      "/root/repositories/darkmem": { "project": "darkmem" },
      "/root/repositories/darkraise-ai-plugins": { "project": "plugins", "documentStore": "local" }
    }
  }
}
```

**Resolution of the configured store,** per family: no mapping for the
repository → `local`, whatever the keys say; otherwise the mapping entry's
value, else the environment variable, else the global key, else `darkmem`.

**The applied store** is what the roots resolve to: the configured store once
§4's move has run, the previous store until then. `resolveMode` becomes
`resolveStores` and returns

```js
{
  repoRoot,
  documents: { configured, applied, root },
  progress: { configured, applied, ledgerRoot, latestFile },
  sync: { project, url, apiKey, mirror, statePath } | null,
}
```

`sync` is non-null whenever the repository is mapped. `apiKey` is `null` when
the named variable is unset.

**A missing key no longer means local.** A family applied to darkmem always
uses the mirror; only the sync needs the key. A missing key or an unreachable
server means working offline from the mirror, and `darkmem-sync` reports why
it skipped. Falling back to the repository is unsafe: after a move the
repository copy is gone, and §4 would read the fallback as a flip.

`darkmem-config.mjs --mode` prints one line per family,
`documents<TAB><applied><TAB><root>` and
`progress<TAB><applied><TAB><ledger root><TAB><latest file>`; a `ConfigError`
exits 2 with its message, and a missing `node` is local for both.

## 2. Roots, names and per-family sync

`scripts/lib/roots.sh`, sourced by `scripts/lib/plan.sh`, calls `--mode` once
per script run and caches it. It replaces the wiring spec's `sp_*` helpers:

| Helper | Applied local | Applied darkmem |
|---|---|---|
| `forge_docs_root` | `<worktree>/docs/forge` (pre-2.0: `docs/superpowers` where only it exists) | `<mirror>/superpowers` |
| `forge_ledger_dir SLUG` | `<worktree>/.forge/sdd/SLUG` | `<mirror>/work/sdd/SLUG` |
| `forge_latest_file` | `<primary>/.forge/handoff/latest.md` | `<mirror>/work/handoff/latest.md` |
| `forge_workspace SLUG` | `<worktree>/.forge/sdd/SLUG` | `<worktree>/.forge/sdd/SLUG` |
| `forge_resolve NAME` | name → path | name → path |
| `forge_name FILE` | path → name | path → name |

The first column follows `documents.applied` for `forge_docs_root` and
`progress.applied` for the two progress helpers. `<worktree>` is the working
directory's top level, `<primary>` the primary checkout, `<mirror>`
`~/.dr-forge/mirror/<project>`. Briefs, reports, review packages and
`amendments.md` stay in `forge_workspace`, local in both stores;
`budget-log.tsv` keeps its primary-checkout path.

**Names** keep the wiring spec's ruling 1: a document is named
`docs/forge/<rest>` (`docs/superpowers/<rest>` in a pre-2.0 repository) in
both stores, a working file `.forge/<rest>`. So a ledger in darkmem can name a
plan in the repository and the reverse. `forge_resolve` maps a document name
to `forge_docs_root`, any other name to `<worktree>`; `forge_name` inverts it,
computed from the roots, never by searching for a path segment.

**darkmem uris are unchanged:** the mirror's `superpowers/` and `work/`
subtrees and the `superpowers/` uri prefix stay, so nothing stored on darkmem
moves. `pathToUri` takes the roots and computes from them, which fixes the
leftmost-segment match (dr-forge register row 13).

**Rewiring.** Every script that builds one of these paths or derives a root
from a plan's directory calls the helpers: the wiring spec §1 list
(`plan.sh`'s four functions, `register.sh`'s `register_files`, `snapshot.sh`,
`next-step`, `plan-lint`, `plan-revise`, `plan-amend`, `register`,
`repo-audit`, `sdd-workspace` and its callers) re-inventoried against the
current tree, plus the current `forge_dir` callers (`roadmap.sh`, `context.sh`,
`auto-run.sh`). Skill and reference prose writes `<docs root>/…`,
`<ledger dir>` and `<latest.md>`; `using-superpowers` states both expansions
once. Where skill text says to commit a spec, plan or `completed.md` line, it
says to push instead when `documentStore` is applied darkmem; code commits are
unchanged. `plan_require_same_repo` becomes `plan_require_same_project`: it
accepts a plan under the mirror only when documents are applied darkmem.

**Per-family sync.** `darkmem-sync push` and `pull` run the documents step
only when documents are applied darkmem, and the ledger, checkpoint and plan
`handoff.md` steps only when progress is. Workstream properties
(`propertiesFor`) read the plan and spec through `forge_resolve`, wherever
they live; `linkHandoff` runs only when progress is in darkmem. Both families
share one lock and one state file per mirror. `status` prints each family's
configured and applied store and `not synced` for a local one.

## 3. Ledger entry properties

So a darkmem board can read progress without parsing markdown, push sends one
entry per complete ledger line (a line longer than darkmem's body limit is
split as today, each piece carrying the line's properties) with these entry
properties, each present only when the line yields it:

| Property | Value |
|---|---|
| `task` | the integer of a leading `Task N:` |
| `state` | the first match of: `done` for `complete (`, `blocked` for `BLOCKED`, `review` for `fix round`, `wip` for an implementer assignment (`implementer … (assigned`); the vocabulary of darkmem's progress board |
| `commit` | the last hash of a `commits <a>..<b>` range |

A trailing line without its newline is held until the next push; the ledger
offset advances only past complete lines, so the hardening's reconciliation
(`expected_last_seq`, `pending`) keeps its byte arithmetic. darkmem's
`WorklogEntryIn` already accepts per-entry `properties`.

## 4. The automatic move

**The record.** `~/.dr-forge/stores.json`, per machine, maps each primary
checkout's absolute path to `{ "documents": <applied>, "progress": <applied> }`.
With no entry, a family's applied store is `darkmem` when the mirror's sync
state already lists files of that family, else `local`, so a repository
already synced by hand is not imported over darkmem's copy.

**The trigger.** `session-start.sh` runs `darkmem-sync reconcile` before its
pull. For each family whose configured store differs from its applied store it
attempts the move; success updates the record and adds one line to the
session-start note, a refusal adds one line naming where the family still
lives, the configured store and the reason.

**Refusals.** No move runs while:

- a plan is in progress: any ledger in the progress family's source location
  (every worktree's when local, the mirror's when darkmem) whose plan has no
  `completed.md` entry (`plan_finished`, compared by §7.1's key); or an auto
  run is active;
- darkmem is unreachable or the key is missing;
- another process holds the mirror lock (the move takes it);
- for documents leaving the repository, the docs directory has uncommitted
  changes;
- for documents entering darkmem, darkmem holds a different version at any of
  their uris; the note lists those uris and nothing is overwritten;
- for documents entering darkmem, the docs directory holds a file the move
  cannot carry (§7.2); the note names each one.

**Documents, repository → darkmem.** Run §7.2's checks, then read darkmem's
document manifest and compare its hashes with the local files: import puts
documents without a hash precondition (`darkmem-import.mjs`), so this check is
what keeps darkmem's copies, and the window between it and the import is
accepted. Then import the primary checkout's docs directory
(`darkmem-import.mjs`'s document half), pull into the mirror, and
compare every file's hash with its mirror copy. Only then run
`git rm -r -q <docs dir>` in the primary checkout and leave the deletion
staged; the note asks the owner to commit it.

**Documents, darkmem → repository.** Pull, copy `<mirror>/superpowers` into
the primary checkout's `docs/forge` (§7.1: the prefix the repository used
before does not matter) untracked, compare hashes, and drop the documents'
sync state; darkmem keeps its copy. The note asks the owner to commit the
files, names any of them `git check-ignore` reports as ignored (a repository
moved under the parent spec's §6 ignored its docs directory), and names a
`.gitattributes` line that still points at `docs/superpowers/` (the
`completed.md merge=union` line).

**Progress, either direction.** Local ledgers live in each worktree, so going
to darkmem reads the primary checkout and every linked worktree `git worktree
list` names: import (`darkmem-import.mjs`'s ledger half, which today reads
only the primary checkout's ledgers; Plan 2 adds the linked worktrees and
`latest.md`, which it reads neither of), pull, then compare hashes. Coming back, pull and copy the ledgers and `latest.md`
into the primary checkout, then compare hashes. The files are gitignored, so
the source copies are moved to a dated backup rather than deleted:
`<checkout>/.forge/moved-<stamp>/` in each checkout read going to darkmem,
`<mirror>/work-moved-<stamp>/` coming back. `<stamp>` is UTC
`YYYYMMDDTHHMMSSZ`. Import closes the workstreams it files, which is correct
here because every ledger it reads belongs to a plan `completed.md` records.

**Leftovers.** When documents are applied darkmem and the working directory's
checkout still has a docs directory (a branch cut before the move, or a merge
that brought files back), session start warns that those files are not read.

## 5. Carried over from the parent specs

- **Deletion archives** (wiring §2) and `darkmem-sync restore` apply to the
  documents family when it is applied darkmem; distilling-docs' darkmem
  behaviour follows `documentStore`.
- **Triggers** (wiring §3, parent §4): session start runs `reconcile`, then
  pulls every family applied darkmem; the Stop hook and the skills' stop points
  push. The hooks export `DR_FORGE_SESSION_ID`; the handoff skill defines the
  `- Draft:` line.
- **Promotion** (parent §5): `memory_add` at task-complete and handoff runs
  whenever the repository is mapped, whichever families live in darkmem.
- **Moving a repository** (parent §6, register row 5) is replaced by §4 and
  §7.2.

## 6. Testing

- Local: with no config file every existing suite passes unchanged.
- Resolution: mapping entry over environment over global key over default;
  no mapping is local for both; an invalid override is a `ConfigError`; a
  missing key keeps an applied-darkmem family on the mirror.
- Layout: every `roots.sh` helper for all four applied combinations, from the
  primary checkout and from a linked worktree.
- Names: `forge_resolve`/`forge_name` round-trip in all four combinations,
  including a checkout and a project both named `superpowers`; the `pathToUri`
  regression.
- Sync, against the stub server: push and pull touch only applied-darkmem
  families; a plan `handoff.md` syncs with progress, not documents.
- Entry properties: each state mapping, `task` and `commit` extraction, a
  line with none, a held partial line, and a split long line.
- `reconcile`: each direction for each family; each refusal; the record's
  first-run rule; the staged `git rm`; the backup directories; the leftover
  warning; a second run after success does nothing.
- `node scripts/validate-repository.mjs`, the maintained suites,
  `claude plugin validate` on the marketplace and every plugin, and
  `claude plugin test plugins/dr-forge`.

## 7. Rulings on register rows 5, 17 and 18 (owner, 2026-10-13)

### 7.1 One document name under either prefix (row 18)

`docs/superpowers/<rest>` and `docs/forge/<rest>` name the same document.
Today `forge_name` takes the prefix from whichever docs directory exists in
the worktree (`forge_dir` prefers `docs/forge`), so the prefix already differs
between worktrees on different branches and between machines; and once §4's
move removes `docs/superpowers`, new names come out as `docs/forge/<rest>`
while existing ledgers, `completed.md` lines, register cells and plan headers
keep `docs/superpowers/<rest>`.

`roots.sh` gains `forge_name_key NAME`: after a leading `./` is stripped, a
`/`-separated name that is exactly `docs/superpowers` or begins
`docs/superpowers/` has that segment replaced by `docs/forge`; any other name,
`docs/superpowersx` included, is unchanged. Every comparison of two document
names compares their keys. A search for a name in `completed.md` runs
`grep -F` once per spelling and accepts either.

The sites, found by the 2026-10-13 review; the plan re-checks the tree for
others:

| Site | Compares |
|---|---|
| `scripts/lib/plan.sh` `plan_ledger` | a ledger's identity line with the plan |
| `next-step`, its own ledger check | a ledger's identity line with the plan |
| `next-step` `plan_finished` | the plan's name in `completed.md` |
| `next-step`, the register-row loop | a row's Assigned cell with the plan |
| `plan-revise` `ledger_for` | a ledger's identity line with the plan |
| `plan-revise` `completed_form` | the plan's name in `completed.md` |
| `plan-lint`, the register-row checks | a row's Assigned cell with the plan |
| `scripts/lib/register.sh` `register_for_spec` | a register's `**Covers:**` with a plan's `**Spec:**` or `**Program:**` |
| `scripts/lib/roadmap.sh`, `roadmap` | register names and Assigned cells with a spec |

The project-status and finishing-a-development-branch skills match a plan's
path by reading it; each gains one sentence that either prefix names the same
document. `pathToUri` already strips either prefix and the cockpit resolves
names rather than comparing them, so no JavaScript needs the key. Names are
still written as `forge_name` prints them; nothing on disk or on darkmem is
rewritten.

Chosen over recording the prefix in `stores.json`, which is per machine: a
second machine whose checkout no longer has `docs/superpowers` would name
files `docs/forge/<rest>` against ledgers it shares through darkmem. Chosen
over a marker file in the mirror, which adds a synced file for no gain.

### 7.2 Files the move cannot carry, and citations (row 5)

Before anything is sent, documents entering darkmem refuse the move, naming
each file, when the docs directory holds:

- a tracked file the mirror never syncs (`listDocumentFiles`): one whose own
  name, or the name of any directory between it and the docs directory, starts
  with a dot; a symbolic link, or anything reached through one; a file under
  the docs directory's own `handoff/`;
- a tracked file import refuses (`darkmem-import.mjs`): an empty file, or one
  that is not UTF-8;
- a tracked file whose uri `uriProblem` rejects, or that is a case twin of
  another (`caseGroups`): push and pull refuse these but import does not, and
  darkmem has no delete route to remove one once filed;
- an ignored file (`git status --porcelain --ignored -- <docs dir>`): the
  mirror walks the filesystem, so import would upload it, and `git rm -r`
  would leave it behind.

Tracked is the test for the first three because `git rm -r` deletes only
tracked paths; an untracked file that is not ignored already refuses through
§4's uncommitted-changes check.

Citations do not refuse the move. After documents move to darkmem, the note
lists the tracked files outside the docs directory whose text contains
`docs/superpowers/` or `docs/forge/` (`git grep -I -l`, which skips binary
files), the first 20 followed by a count of the rest, and asks the owner to
rewrite them before committing the staged deletion. This replaces the parent
spec §6's "rewrite the `CLAUDE.md` citations first".

### 7.3 The cockpit reads through the roots (row 17)

`readRun` in `hooks/cockpit/register.tsx` reads `latest.md`, the ledgers and
the plan from the primary checkout only, so with progress applied darkmem its
plan section shows nothing.

- **Roots.** `darkmem-config.mjs --mode` gains an optional directory argument
  (`resolveStores` already takes a `cwd`), because a mod's process call sets no
  working directory. The cockpit passes the primary checkout and takes the
  ledger root, `latest.md` and the docs root from the output. It calls it when
  the place changes and again whenever `~/.dr-forge/stores.json`'s
  modification time changes, so the session that runs §4's move sees the new
  roots; the call has a 5-second timeout. The reader is a top-level function
  taking `$`.
- **Failure.** On a non-zero exit or a timeout the cockpit keeps today's
  checkout paths and shows the first line of stderr as one note in the pane.
  With no `node`, it keeps the checkout paths silently, as `roots.sh` does.
- **The plan.** With documents applied local, a relative plan name is tried
  under the session's checkout first, then the primary, as today. With
  documents applied darkmem, a document name under either prefix resolves
  under the docs root.
- **`finish.json`.** It stays in the workspace of the worktree that ran the
  plan (`forge_workspace`, §2), so the cockpit reads
  `<state>/sdd/<slug>/finish.json` for the newest ledger's slug in the
  session's checkout first, then the primary; the no-plan
  `<state>/sdd/finish.json` is read in the same order.
- **The newest ledger.** A pull rewrites a changed mirror ledger, so progress
  pulled from another machine, or the first pull after a move, can make a
  ledger newer than the session's start and show it in the pane. This is
  intended: the pane shows the project's most recent progress.

### 7.4 Testing

- `forge_name_key`: both prefixes, a bare `docs/superpowers`, a leading `./`,
  `docs/superpowersx`, a name outside the docs directory. Each site in §7.1's
  table matches a ledger line, `completed.md` entry, register cell or plan
  header spelled with the other prefix.
- `reconcile`: each kind in §7.2 (a dotfile at depth, a dot directory, a
  symbolic link, a file under `handoff/`, an empty file, a non-UTF-8 file, a
  name `uriProblem` rejects, a case twin, an ignored file) refuses, is named,
  and sends nothing to the stub server; a darkmem copy with a different hash
  refuses before import; a ledger whose plan has no `completed.md` entry
  refuses and one with an entry does not; a citing `CLAUDE.md` is listed, the
  list is capped, and the move runs; the darkmem-to-repository note names an
  ignored copy and a stale `.gitattributes` line.
- Cockpit: the plan section reads a ledger, `latest.md` and a plan from a
  mirror when both families are applied darkmem; a failing `--mode` keeps the
  checkout paths and shows its reason; `finish.json` and a local plan are read
  from the session's linked worktree before the primary; a changed
  `stores.json` re-reads the roots.

## Delivery

1. **Plan 1:** the schema keys, `resolveStores`, `roots.sh`, `pathToUri`, the
   rewiring of scripts and prose, per-family `push`/`pull`/`status`, the
   `handoff.md` family change and §3's entry properties. Register rows 2 and
   16; dr-forge register row 13.
2. **Plan 2:** `stores.json` and `reconcile` (§4), the triggers, archives and
   `restore`, the `- Draft:` line, promotion and §7. Register rows 3, 4, 5,
   17 and 18.

## Not in scope

- Server changes: none are needed.
- The Notion-like progress board: a darkmem project, recorded in darkmem's
  work-log register.
- Purging `superpowers/archive/`, Windows CI (register row 6), and keeping
  `stores.json` consistent across machines (each machine applies its own
  configuration).
