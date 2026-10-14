# dr-forge 3.0.0: retire the superpowers names, make darkmem opt-in

**Goal:** dr-forge stops reading and writing every pre-2.0 `superpowers`
name, and darkmem becomes an opt-in whose absence or outage always leaves the
work on the local file system.

**Owner rulings (2026-10-14):**

1. Full retirement in a major release (3.0.0). A migrate command moves a
   pre-2.0 repository and home; every legacy read fallback is then deleted,
   except the read-time name translation `docs/superpowers/<rest>` ->
   `docs/forge/<rest>`, which historical specs and plans cite and which may not
   be rewritten (repository CLAUDE.md).
2. darkmem documents move from the `superpowers/` uri prefix to `forge/` at
   reconcile, on the server, verified by hash; the mirror folder follows.
3. When darkmem is disabled or the repository unmapped while a family lives in
   the mirror, the family moves back from the mirror without contacting
   darkmem; the mirror is kept as a dated backup.

**Ruling (implementer, cost if wrong: a reachable server is used one session
longer):** an enabled, mapped repository whose server is merely unreachable
keeps working from the mirror, which is local files; it does not move back.
Moving back on every outage would stage a `git rm`/re-add of `docs/forge/`
each time the server blinks.

## Track N — naming (worktree, subagent)

N1. `scripts/forge-migrate [DIR]`: for the repository at DIR (default: the
    working directory), its primary checkout and every linked worktree:
    - `.superpowers/` -> `.forge/` (plain rename; refuse a checkout that has
      both);
    - `docs/superpowers/` -> `docs/forge/` with `git mv` when tracked, plain
      rename when not (refuse when both exist or the directory has
      uncommitted changes);
    - `$gitdir/dr-superpowers` -> `$gitdir/dr-forge` (refuse when both exist);
    - `.gitignore`, `.gitattributes`, `.git/info/exclude` lines naming
      `.superpowers` or `docs/superpowers/` rewritten to the new names;
    - never edits any other file's content (historical plans/specs keep their
      citations); prints what it moved and what the user must commit;
    - then runs `node scripts/lib/darkmem-migrate.mjs` (Track D) when present
      for the home: `~/.dr-superpowers/` -> `~/.dr-forge/`.
    Exit 0 when done or nothing to do, 1 when something was refused.
N2. Delete the repository-level fallbacks: `forge-dir.sh` (always `.forge`,
    `docs/forge`; add `forge_legacy_layout [ROOT]`, which prints each pre-2.0
    path that still exists), `forge-env.sh` `DR_SUPERPOWERS_*`,
    `task-state.sh` `dr-superpowers`, the cockpit's `.superpowers` /
    `docs/superpowers` directory picks, `DR_SUPERPOWERS_BUDGET`, the
    `dr-superpowers:` prefix (`isSuperpowers` -> `isForge`), the cockpit's and
    `forge-config.mjs`'s `~/.dr-superpowers` import and `LEGACY_ENV`. The
    dr-cockpit options import stays (it is not a superpowers name).
    `reference/legacy-names.md` is deleted with every reference to it.
    Session start and `repo-audit` print one line naming `forge-migrate`
    when `forge_legacy_layout` finds anything.
N3. Rename `skills/using-superpowers` -> `skills/using-forge` (skill name
    `using-forge`) and every reference: session start, skills, references,
    agents, Codex files, tests. Its darkmem `code_search` line becomes
    conditional on the darkmem MCP being configured.
N4. Text: manifest descriptions and keywords, `run-codex-task.sh`,
    `reference/external-task-recovery.md`, `reference/native-codex.md`,
    `skills/finishing-a-development-branch/SKILL.md`,
    `skills/brainstorming/SKILL.md`, README (Track N owns README except the
    darkmem paragraph). Upstream credit stays in README's credits and LICENSES.
N5. `scripts/validate-repository.mjs`: refuse `superpowers` (any case) in
    `plugins/dr-forge/` outside an allowlist of files that carry the name
    translation, the migration code, the credits and LICENSES; tests excluded.
N6. Tests follow: legacy-fallback tests become migration tests.

## Track D — darkmem (main session)

D1. `darkmemEnabled` (boolean, default `false`, no environment override) in
    `config/schema.mjs`; `documentStore` and `progressSource` lose their
    environment overrides. Disabled or unmapped: both families configured
    `local`; `forge-path project` prints nothing, so no memory promotion.
D2. `~/.dr-forge/stores.json` records `project` and `mirror` with a family
    applied `darkmem`; `resolveStores` honours the record when the repository
    is disabled or unmapped, so a family is never stranded in the mirror. The
    first-run guess from the mirror's sync state is removed: no record means
    applied `local`.
D3. Offline move back: a pending move to `local` that cannot reach darkmem
    (disabled, unmapped, key unset, unreachable) copies the mirror's files
    into the checkout, names every unpushed edit and deletion, and sets the
    mirror aside as a backup.
D4. Hooks: session start runs reconcile for a repository the record lists;
    the Stop push and `push`/`pull` do nothing while darkmem is disabled.
D5. Prefix: `DOC_PREFIX` `forge`, mirror folder `forge/`, archives
    `forge/archive/`, handoffs `forge/handoff/`. Under the lock, a mirror whose
    state still holds `superpowers/` uris is renamed locally and marked; the
    next online command moves each `superpowers/*` document on darkmem to
    `forge/*` (PATCH, expected hash) before anything else. `forgeDir`,
    `preferNew` and `legacyHome` lose their fallbacks.
    `scripts/lib/darkmem-migrate.mjs` migrates the home and every mirror.
D6. Memory promotion falls back to `<docs>/notes/<date>-facts.md` when darkmem
    is off or its MCP tools are absent (`reference/project-state.md`).
D7. Tests.

## Release

3.0.0 in both manifests; README darkmem paragraph and a "Migrating to 3.0"
section; full validation per CLAUDE.md.
