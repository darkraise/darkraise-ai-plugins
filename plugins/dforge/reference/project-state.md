# Project state

Where dforge keeps a project's files, and when darkmem syncs them.

## Where `<state>` and `<docs>` are

`<state>` is `.dforge/` and `<docs>` is `docs/dforge/`. A repository that still
has a pre-3.0 directory is moved with `bash <plugin-root>/scripts/dforge-migrate`
first; session start names what it still has.

darkmem is off unless the `darkmemEnabled` setting is on. A repository mapped
to darkmem while it is on may keep its documents in the darkmem mirror instead
(`documentStore`; `bash <plugin-root>/scripts/dforge-path store` prints which).
Turned off or unmapped, they belong in the checkout: documents still in the
mirror are read there until the reconcile of a session start with no plan in
progress copies them back from the mirror, without asking darkmem.

| Token | Local | darkmem |
|---|---|---|
| `<docs>` | `<worktree>/docs/dforge` | `~/.dforge/mirror/<project>/dforge` |

`<state>` stays in the checkout either way.

Every script resolves these through `scripts/lib/roots.sh`; a skill resolves
them with `bash <plugin-root>/scripts/dforge-path state|docs [RELATIVE]`
before it reads or writes, never by spelling a path. `dforge-path` answers for
the checkout it runs in; for a path written under another root, such as
`<worktree>/<state>/…`, run it from that root:
`(cd "<root>" && bash <plugin-root>/scripts/dforge-path state)`.

Where a path is written into a file or onto a command line, write its name:
`bash <plugin-root>/scripts/dforge-path name <path>`. A document's name is
`docs/dforge/<rest>` in both stores (a name written before 3.0.0 as
`docs/superpowers/<rest>` still means it); every script accepts a name where
it takes a path.

While `dforge-path store` prints `documents darkmem`, a step that would commit
a file under `<docs>` runs `bash <plugin-root>/scripts/darkmem-sync push`
instead. Code commits are unchanged.

## darkmem sync points

Run `bash <plugin-root>/scripts/darkmem-sync push` after a file under `<docs>`
is saved. In a repository that is not mapped to darkmem, or while darkmem is
off, it prints one line and exits 0, so no check comes first. On Claude Code
the SessionStart hook runs `darkmem-sync reconcile`, then `pull`, and the Stop
hook pushes as a safety net. Codex has no hooks, so there these steps and the
session-start step in `skills/using-dforge/references/codex-tools.md` are the
only triggers.
