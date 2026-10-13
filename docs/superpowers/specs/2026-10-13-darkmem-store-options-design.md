# darkmem store options: documents and progress chosen separately

Date: 2026-10-13
Status: design, owner-approved section by section on 2026-10-13.
Supersedes: §1 of `docs/superpowers/specs/2026-09-23-darkmem-mirror-design.md`
(configuration and modes) and §1 of
`docs/superpowers/specs/2026-09-28-darkmem-mirror-wiring-design.md` (names and
the two roots). Both specs' other sections stand as amended in §5 below.
Register: `docs/superpowers/registers/2026-09-24-darkmem-mirror.md` rows 2, 3,
4, 5, 16, 17 and 18; `docs/superpowers/registers/2026-10-11-dr-forge.md` row 13.
Amended 2026-10-13 by §7 (owner rulings on rows 5, 17 and 18).

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

- a plan is in progress in the source location (the definition `repo-audit`
  uses), or an auto run is active;
- darkmem is unreachable or the key is missing;
- another process holds the mirror lock (the move takes it);
- for documents leaving the repository, the docs directory has uncommitted
  changes;
- for documents entering darkmem, darkmem holds a different version at any of
  their uris; the note lists those uris and nothing is overwritten.

**Documents, repository → darkmem.** Import the primary checkout's docs
directory (`darkmem-import.mjs`'s document half), pull into the mirror, and
compare every file's hash with its mirror copy. Only then run
`git rm -r -q <docs dir>` in the primary checkout and leave the deletion
staged; the note asks the owner to commit it.

**Documents, darkmem → repository.** Pull, copy `<mirror>/superpowers` into
the primary checkout's `docs/forge` (§7.1: the prefix the repository used
before does not matter) untracked, compare hashes, and drop the documents'
sync state; darkmem keeps its copy. The note asks the owner to commit the
files.

**Progress, either direction.** Local ledgers live in each worktree, so going
to darkmem reads the primary checkout and every linked worktree `git worktree
list` names: import (`darkmem-import.mjs`'s ledger and checkpoint half), pull,
then compare hashes. Coming back, pull and copy the ledgers and `latest.md`
into the primary checkout, then compare hashes. The files are gitignored, so
the source copies are moved to a dated backup rather than deleted:
`<checkout>/.forge/moved-<stamp>/` in each checkout read going to darkmem,
`<mirror>/work-moved-<stamp>/` coming back. `<stamp>` is UTC
`YYYYMMDDTHHMMSSZ`. Import closes the workstreams it files, which is correct
here because no plan is in progress.

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
the checkout, so once §4's move removes `docs/superpowers`, new names come out
as `docs/forge/<rest>` while existing ledgers and `completed.md` lines keep
`docs/superpowers/<rest>`.

`roots.sh` gains `forge_name_key NAME`: the name with a leading
`docs/superpowers` replaced by `docs/forge`, any other name unchanged. Every
comparison of two document names compares their keys, and every search for a
name in `completed.md` accepts either spelling. Known sites: `plan_ledger`'s
identity check (`scripts/lib/plan.sh`), `plan_finished` (`next-step`) and
`completed_form` (`plan-revise`); the plan re-inventories the rest against the
tree. Names are still written as `forge_name` prints them; nothing on disk or
on darkmem is rewritten.

Chosen over recording the prefix in `stores.json`, which is per machine: a
second machine whose checkout no longer has `docs/superpowers` would name
files `docs/forge/<rest>` against ledgers it shares through darkmem. Chosen
over a marker file in the mirror, which adds a synced file for no gain.

### 7.2 Files the move cannot carry, and citations (row 5)

The mirror never syncs a dotfile, a symbolic link, or a file under the docs
directory's own `handoff/` (`listDocumentFiles`), so §4's hash comparison never
sees them and `git rm -r` would delete them. §4 gains one refusal: for
documents entering darkmem, the docs directory holds a tracked file of one of
those kinds; the note names each one.

Citations do not refuse the move. After documents move to darkmem, the note
lists the tracked files outside the docs directory whose text contains
`docs/superpowers/` or `docs/forge/` (for example darkmem's `CLAUDE.md`) and
asks the owner to rewrite them before committing the staged deletion. This
replaces the parent spec §6's "rewrite the `CLAUDE.md` citations first".

### 7.3 The cockpit reads through the roots (row 17)

`readRun` in `hooks/cockpit/register.tsx` reads `latest.md`, the ledgers and
the plan from the primary checkout only, so with progress applied darkmem its
plan section shows nothing. It takes the ledger root, `latest.md` and the docs
root from one `darkmem-config.mjs --mode` call per place change, the call
`roots.sh` makes, run in the primary checkout it reads today; when that call
fails it keeps today's checkout paths. The
plan named by the ledger resolves as `forge_resolve` does: a document name
under the docs root (either prefix), any other relative name under the
checkout. `finish.json` stays in the plan's workspace in the checkout, so it is
read at `<state>/sdd/<slug>/finish.json` for the newest ledger's slug, not
beside the ledger.

### 7.4 Testing

- `forge_name_key`: both prefixes, a non-document name; `plan_ledger`,
  `plan_finished` and `completed_form` match a ledger or `completed.md` line
  spelled with the other prefix.
- `reconcile`: each uncarried kind (a dotfile at depth, a symbolic link, a
  file under `handoff/`) refuses and is named; a citing `CLAUDE.md` is listed
  and the move still runs.
- Cockpit: the plan section reads a ledger, `latest.md` and a plan from a
  mirror when progress and documents are applied darkmem, and from the
  checkout when the `--mode` call fails.

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
