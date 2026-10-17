# dforge rename: dr-forge becomes dforge, the UI plugins drop dcc-, and a migrate skill

**Execution strategy:** sequential — the renames share both catalogs, `CLAUDE.md`, the root `README.md`, `scripts/validate-repository.mjs` and `.github/workflows/validate.yml`, and the migration work consumes the new names.
**Approach:** clean break — dforge reads only its own names and points every older layout at `/dforge:migrate`; chosen over reading the dr-forge names as a fallback for one major version (two branches on every path lookup, the split-work risk 3.0 removed) and over migrating at session start (moves files and remote darkmem data without consent).
**Register:** `docs/superpowers/registers/2026-10-17-dforge-rename.md`

## Goal

1. Rename the dr-forge plugin to dforge, and every name containing `forge` in
   it, internal identifiers included (register item 1).
2. Add a `migrate` skill that moves a repository and the home from either older
   generation, dr-superpowers or dr-forge, to the dforge names (item 2).
3. Rename `dcc-darkraise-ui` and `dcc-darkraise-win32ui` to `darkraise-ui` and
   `darkraise-win32ui` (item 3).

Paths are relative to the repository root. `plugins/dforge/` is the renamed
`plugins/dr-forge/`.

## Non-goals

- dr-status keeps its internal `dcc-` names: the `DCC_*` variables,
  `scripts/dcc-statusline.schema.json`, `~/.claude/dcc-statusline/` and
  `~/.claude/dcc-statusline-installations.json` (`CLAUDE.md`: preserve `DCC_*`
  variables and statusline user storage paths).
- Historical plans, specs, registers and notes are not edited, including this
  repository's whole `docs/superpowers/` tree (`CLAUDE.md`: do not edit
  historical plans/specs during public-name migrations). Their citations stay
  as written.
- The two UI plugins' skills are already named `darkraise-ui` and
  `darkraise-win32ui`; their content does not change beyond names it cites.
- No fallback reading of any older name, and no automatic migration.
- The dr-cockpit settings import in `forge-config.mjs` (`importLegacy`) keeps
  its behaviour; only its names change.

## 1. Name map

| Old | New |
|---|---|
| `plugins/dr-forge/`, manifest `name`/`displayName` `dr-forge` | `plugins/dforge/`, `dforge` |
| skill namespace `dr-forge:<skill>` | `dforge:<skill>` |
| skill `using-forge` | `using-dforge` |
| `.forge/` (state, per checkout) | `.dforge/` |
| `docs/forge/` (docs root) | `docs/dforge/` |
| `<git dir>/dr-forge/` | `<git dir>/dforge/` |
| `~/.dr-forge/` (`config.json`, `stores.json`, `mirror/`) | `~/.dforge/` |
| `DR_FORGE_*` environment variables | `DFORGE_*` |
| darkmem document uris `forge/<rest>`, archives `forge/archive/<stamp>/<rest>` | `dforge/<rest>`, `dforge/archive/<stamp>/<rest>` |
| mirror folder `<mirror>/forge/` | `<mirror>/dforge/` |
| scripts `forge-config`, `forge-migrate`, `forge-path` | `dforge-config`, `dforge-migrate`, `dforge-path` |
| `scripts/lib/forge-config.mjs`, `forge-dir.sh`, `forge-env.sh` | `dforge-config.mjs`, `dforge-dir.sh`, `dforge-env.sh` |
| `scripts/lib/darkmem-migrate.mjs` | `scripts/lib/dforge-home-migrate.mjs` |
| shell functions `forge_*` (e.g. `forge_dir`, `forge_self_ignore`, `forge_legacy_layout`) | `dforge_*` |
| JavaScript/TypeScript identifiers containing `forge`/`Forge` | `dforge`/`Dforge` |
| tests `tests/forge-*.test.sh`, `tests/forge-migrate.test.sh` | `tests/dforge-*.test.sh`, `tests/dforge-migrate.test.sh` |
| `plugins/dcc-darkraise-ui/`, `plugins/dcc-darkraise-win32ui/` | `plugins/darkraise-ui/`, `plugins/darkraise-win32ui/` |

A word that only contains `forge` as part of another word does not occur in
the plugin today; the rename is by the names above, not a blind substitution
of the substring.

## 2. Plugin and repository rename (items 1 and 3)

- Directories move with `git mv` so history follows them.
- Both manifests of each renamed plugin change `name` (and Codex
  `displayName`); both catalogs change the entry's `name` and `source` path.
- dforge goes to 4.0.0 in `.claude-plugin/plugin.json` and
  `.codex-plugin/plugin.json`. `darkraise-ui` and `darkraise-win32ui` go to
  0.3.0 in both of theirs. The marketplace version goes from 0.6.0 to 0.7.0.
- Every user-facing string follows: hook descriptions in `hooks/hooks.json`,
  session-start and repo-audit lines, cockpit text (the settings view's "Saved
  to ~/.dforge/config.json"), error messages, skill and reference text, agent
  descriptions, and the READMEs.
- Repository files that name the plugins change with them: `CLAUDE.md`,
  `README.md`, `CONTRIBUTING.md`, `docs/migration.md`,
  `docs/testing/dual-client-marketplace-validation.md`,
  `.github/ISSUE_TEMPLATE/*.yml`, `.github/workflows/validate.yml`,
  `scripts/validate-repository.mjs`, `scripts/test-shards.mjs`,
  `tests/repository-layout.test.mjs`, `tests/ui-discovery.test.mjs`,
  `tests/marketplace-smoke.ps1`, and the dr-status README where it names the
  dr-forge or dcc UI plugins.
- `CLAUDE.md` keeps its rule about `DCC_*` and statusline paths; its
  plugin lists and `claude plugin test plugins/dforge` follow the new names.

## 3. `scripts/dforge-migrate`

It keeps `forge-migrate`'s contract (exit 0 done or nothing to do, 1 something
refused, 2 usage or not in a git repository; a second run finishes after a
refusal is resolved) and widens each move to both older generations. For the
repository at `DIR`, its primary checkout and every linked worktree:

- **State directory:** `.superpowers/` and `.forge/` each move into `.dforge/`
  through the existing `mv_plain`/`merge_into`: a plain rename when the target
  is absent, otherwise file by file (a file the target lacks moves, an
  identical one is dropped, one that differs is refused and left).
- **Docs:** of `docs/superpowers/`, `docs/forge/` and `docs/dforge/`, more than
  one present is refused. Exactly one old tree present moves to
  `docs/dforge/`: `git mv` when it is tracked, refused when it has uncommitted
  changes, a plain rename when untracked.
- **Git directory:** `dr-superpowers/` and `dr-forge/` move into `dforge/` the
  same way as the state directory.
- **Ignore and attribute lines:** `rewrite_names` renames `.superpowers`,
  `.forge`, `docs/superpowers` and `docs/forge` to `.dforge` and `docs/dforge`
  in each checkout's `.gitignore` and `.gitattributes` and in the shared
  `info/exclude`, with the existing replace/add modes (a refused checkout keeps
  its old line and gains the new one).
- **Active plans:** once a checkout's docs sit at `docs/dforge/`, every plan
  under `docs/dforge/plans/` (`completed.md` aside) that the `completed.md`
  beside it does not record, under any of the three docs spellings, as
  `plan_finished` matches it, is active. In each active plan, and in the
  checkout's `.dforge/handoff/latest.md`, the plugin prefixes `dr-superpowers:`
  and `dr-forge:` before a skill or agent name become `dforge:`, so its
  `**Implementer:**` lines pass `plan-lint` and dispatch, and its header names
  dforge's execution skill. Finished plans, specs, ledgers and registers are
  history and keep their text. A checkout whose docs move was refused is not
  rewritten. A tracked plan it rewrote gets a `commit:` line. Plans kept in a
  darkmem mirror are not rewritten (the mirror syncs to a shared store; the
  human edits them through darkmem).
- **Home:** runs `scripts/lib/dforge-home-migrate.mjs` as today, refused when
  node is missing and an old home exists.
- **`--dry-run`:** usage becomes `dforge-migrate [--dry-run] [DIR]`. It prints one `would move A -> B` or
  `would rewrite FILE` line per action, and each refusal it can predict from
  the file system and git (two docs trees, uncommitted docs changes, differing
  files under a merge, a home config key conflict). It writes nothing, starts
  no darkmem traffic, and exits 1 when a refusal is predicted, 0 otherwise.
- The `commit:` lines it prints name the staged docs rename, a tracked state
  directory's rename and each tracked ignore file it rewrote.

## 4. Home migration (`scripts/lib/dforge-home-migrate.mjs`)

- **`~/.dr-forge/` → `~/.dforge/`:** a plain rename when `~/.dforge/` does not
  exist. Otherwise entry by entry: `config.json` merges key by key (a key only
  the old file has is copied; equal values are fine; a key whose values differ
  is refused and named, and the old file stays); every other file or mirror
  folder moves when the new home lacks it, is dropped when identical, and is
  refused when it differs. The old home is removed only when it is empty.
  A first dforge session can already have created `~/.dforge/config.json`
  (the `importLegacy` write), which is why the merge exists.
- **`stores.json`:** each record's `mirror`, an absolute path, is rewritten
  from `~/.dr-forge/mirror/<rest>` or `~/.dr-superpowers/mirror/<rest>` to
  `~/.dforge/mirror/<rest>` once that mirror has moved, so a family applied
  darkmem still finds its mirror.
- **`~/.dr-superpowers/`:** its darkmem mapping and mirrors move as
  `migrateHome` moves them today, into `~/.dforge/`.
- **Mirrors:** each mirror's local `superpowers/` or `forge/` folder becomes
  `dforge/`, and the sync state's document uris and pending links are renamed
  from either prefix; a mirror holding two of the three folders is refused.
- **darkmem server:** unchanged mechanism. `migrateServer` runs at the next
  sync while `state.prefix` is not `dforge`; it lists both old prefixes and
  moves each document to its `dforge/` uri under its content hash. A uri
  darkmem already holds is a failure, never overwritten; `state.prefix` is set
  only when nothing failed.

## 5. The migrate skill (`plugins/dforge/skills/migrate/SKILL.md`)

Invoked as `/dforge:migrate` on Claude Code and as the `dforge:migrate` skill
on Codex. Steps:

1. Run `bash <plugin-root>/scripts/dforge-migrate --dry-run` from the
   repository and show its output. When the home holds a darkmem mapping, say
   that darkmem's documents move to `dforge/` at the next sync.
2. When the dry run predicts no action, say so and stop. When it predicts
   refusals, show each with the fix it names and ask whether to fix them first.
3. Ask once for confirmation, then run `dforge-migrate`.
4. On exit 1, list each refusal and its fix, and offer to run again once the
   human has resolved them.
5. Show the `commit:` lines and offer to commit them as one commit; commit only
   after the human agrees.
6. Remind the human to uninstall `dr-forge@darkraise` and
   `dr-superpowers@darkraise` when installed, so their hooks do not run beside
   dforge's.

The skill writes nothing itself; every change goes through `dforge-migrate`.

## 6. Detection and citations

- `dforge_legacy_layout` names every existing older path: `.superpowers/`,
  `.forge/`, `docs/superpowers/`, `docs/forge/`, the git dir's
  `dr-superpowers/` and `dr-forge/`, the primary checkout's state directories
  (a linked worktree's handoff lives there), and `~/.dr-superpowers` or
  `~/.dr-forge` while either still holds a mapping, config or mirror.
- `scripts/session-start.sh` and `scripts/repo-audit` print one line naming
  those paths and `/dforge:migrate`, in place of today's script path.
- The citation translation that maps `docs/superpowers/<rest>` to the docs
  root when reading a historical plan, ledger or `**Spec:**` line also maps
  `docs/forge/<rest>`, both to `docs/dforge/<rest>`; darkmem's document-name
  translation maps both to `dforge/<rest>`.

## 7. Old-name guard (extends the existing retired superpowers-name check)

`scripts/validate-repository.mjs` fails when an old name appears outside an
allowlist:

- in `plugins/dforge/`: `dr-forge`, `.forge/`, `docs/forge/`, `DR_FORGE_`,
  `.dr-forge`, or a `forge_`/`forge-` code name not preceded by `d`;
- anywhere outside `docs/superpowers/`: `dcc-darkraise`.

The allowlist names files, not lines: `scripts/dforge-migrate`,
`scripts/lib/dforge-home-migrate.mjs`, `scripts/lib/dforge-dir.sh` (legacy
layout detection), the citation translators (`scripts/lib/roots.sh`,
`hooks/cockpit/lib.ts`, `scripts/lib/darkmem-mirror.mjs`,
`scripts/lib/darkmem-sync.mjs`, `scripts/lib/darkmem-reconcile.mjs`),
`reference/project-state.md` (which documents the layout history),
`skills/migrate/SKILL.md`, the tests for these, `README.md` (its migration
sections), and `docs/migration.md`.
`docs/superpowers/` is excluded.

## 8. Documentation

- `plugins/dforge/README.md` gains "Migrating to 4.0": reinstall
  (`dr-forge@darkraise` out, `dforge@darkraise` in), `/dforge:migrate`, what
  moves, and that darkmem follows at the next sync. "Migrating to 3.0" stays.
- `docs/migration.md` gains a dforge 4.0 paragraph under Replaced plugins and
  the two UI plugin renames.

## 9. Testing

- Renamed suites keep their assertions under the new names;
  `scripts/test-shards.mjs` and `tests/test-shards.test.mjs` follow.
- `plugins/dforge/tests/dforge-migrate.test.sh` adds: a pre-3.0 repository; a
  dr-forge repository; both state directories present and merged; two docs
  trees refused; uncommitted docs refused; `--dry-run` lists every action and
  leaves the tree, git dir and home byte-identical; dr-forge ignore lines
  renamed; a linked worktree migrated with the primary; an active plan's
  `dr-forge:` and `dr-superpowers:` prefixes rewritten while a finished plan
  and a spec keep theirs.
- Home migration tests: `~/.dr-forge/` renamed whole; `config.json` merged
  into an existing `~/.dforge/config.json`; a conflicting key refused and the
  old file kept; a `stores.json` mirror path rewritten; a mirror's `forge/`
  folder and state uris renamed;
  `migrateServer` moving `forge/` documents and refusing a uri already held.
- A static test for `skills/migrate/SKILL.md` asserts it runs `--dry-run`
  first, asks before migrating and before committing, and names the plugin
  uninstall.
- The old-name guard has a failing fixture per pattern and a passing allowlisted
  one in the repository tests.

## Acceptance

1. Both catalogs list `dforge`, `darkraise-ui` and `darkraise-win32ui` (and
   Claude's lists `dr-status`); directory names, catalog entries and manifest
   names agree; Claude and Codex versions are equal (dforge 4.0.0, UI plugins
   0.3.0).
2. `validate-repository.mjs`, with the old-name guard, passes; the guard fails
   on each fixture.
3. All maintained suites pass, `claude plugin validate` passes on the
   marketplace and all four plugins, and `claude plugin test plugins/dforge`
   passes.
4. `dforge-migrate` on a scratch copy of a dr-forge-layout repository with
   history, a linked worktree and a home holding `config.json`, `stores.json`
   and a mirror, and one active plan naming `dr-forge:` agents, leaves only
   dforge names, a staged `git mv`, rewritten ignore lines, an active plan
   that passes `plan-lint`, and exit 0; a second run prints that nothing is
   left to migrate.
5. `dforge-migrate --dry-run` on the same copy lists every action of criterion
   4 and changes nothing.
6. A session in a repository still on the dr-forge layout prints the
   `/dforge:migrate` line at start.

## Riskiest assumption

That Claude Code and Codex treat a renamed plugin as a new plugin, so the
uninstall-and-install note is the whole client-side migration: no state is
keyed by the plugin name. Checked for dr-forge: it does not use the per-plugin
data directory (`CLAUDE_PLUGIN_DATA`), and its settings live in its own home.
An `enabledPlugins` entry for `dr-forge@darkraise` is left to the uninstall.
