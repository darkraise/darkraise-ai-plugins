---
name: migrate
description: Use when session start or repo-audit says a repository or home still uses an older layout or prints `dforge 4.x layout found`, or when moving from dr-superpowers, dr-forge or dforge 4.x to dagents - previews the move with a dry run, migrates on one confirmation, and offers the commit
---

# Migrate

**Announce at start:** "I'm using the migrate skill to move this repository, the home directory's dagents files and darkmem's documents to dagents's names."

dagents reads only its own names. A repository or home that dr-superpowers
(before 3.0), dr-forge (3.x) or dforge 4.x set up keeps its work under the
older ones until `scripts/dagents-migrate` moves it:

| Older | dagents |
|---|---|
| `.dforge/`, `.superpowers/`, `.forge/` | `.dagents/` |
| `docs/dforge/`, `docs/superpowers/`, `docs/forge/` | `docs/dagents/` |
| `<git dir>/dforge/`, `<git dir>/dr-superpowers/`, `<git dir>/dr-forge/` | `<git dir>/dagents/` |
| `~/.dr-superpowers/`, `~/.dr-forge/` | `~/.dagents/` |
| this repository's record in `~/.dforge/stores.json`, and its mirror | `~/.dagents/stores.json`, `~/.dagents/mirror/` |
| the `~/.dforge/config.json` settings dagents defines, and this repository's darkmem mapping | `~/.dagents/config.json`, keeping every value it already has |
| darkmem's `superpowers/` and `forge/` documents | `dagents/` |
| darkmem's `dforge/` documents and this project's dforge 4.x workstreams | copied to `dagents/`, originals kept |

An active plan (one its `completed.md` does not record) and the handoff note
get their `dr-superpowers:`, `dr-forge:` and `dforge:` prefixes rewritten to
`dagents:`, so they keep running, and each rewrite of a tracked file is
staged. Finished plans, specs, ledgers and registers keep their text as
history; dagents still reads their citations. An ignore or attributes line
naming `.dforge` or `docs/dforge` is kept and gains its `dagents` twin. Any
other tracked file that still names dforge (a `CLAUDE.md`, a README) is listed
on a `report:` line and left as it is.

A dforge 5 project (an active `docs/dforge` plan with a task that has no
`**Implementer:**` line) is refused whole, as is a project a dforge run still
holds (a live lock under `<git dir>/dforge/locks/`, or an auto run bound to a
live session); nothing moves.

`~/.dforge/config.json` and `~/.dforge/stores.json` stay in place, since
dforge 5 serves every other repository from them. Copying darkmem's `dforge/`
data needs `darkmem.url` in `~/.dforge/config.json` and its API key variable
(`DARKMEM_API_KEY` by default) set; every copy is read back, and nothing in
darkmem is deleted.

Every change goes through `scripts/dagents-migrate`. This skill writes nothing
itself.

dagents stands down while dforge is also enabled for this project, and its
session start then says to use no dagents skill. Before migrating a dforge 4.x
project, have your human partner disable dforge for it
(`claude plugin disable dforge@darkraise --scope local`) and start a new
session.

## Steps

1. **Preview.** From the repository, run
   `bash <plugin-root>/scripts/dagents-migrate --dry-run` and show its output.
   When `~/.dr-forge/config.json`, `~/.dr-superpowers/config.json` or
   `~/.dagents/config.json` holds a `darkmem` section, say that darkmem's
   `superpowers/` and `forge/` documents move to `dagents/` at its next sync.
   For a dforge 4.x project, darkmem's `dforge/` documents and workstreams are
   copied by this run itself, not by a sync. Show each line naming a
   `DFORGE_*` or `DR_*` variable: dagents reads the `DAGENTS_*` name it gives,
   so the old one needs renaming where it is set.
2. **Nothing to move.** When it prints `nothing to migrate`, say so and stop.
3. **Foretold refusals.** When it exits 1, show each `refused:` line with the
   fix it names, and ask whether to resolve them first. A refusal stops only
   its own part; the rest still moves.
4. **Confirm once.** Ask your human partner whether to migrate. Run nothing
   that writes before a yes.
5. **Migrate.** Run `bash <plugin-root>/scripts/dagents-migrate` and show its
   output. On exit 1, list each refusal and its fix, and offer to run it again
   once they are resolved: a second run finishes the job.
   This run can refuse where the dry run exited 0: the dry run treats a
   directory an earlier line would create as absent, so a second directory
   moving into it (`.superpowers/` and `.forge/` both to `.dagents/`) is listed
   as a move, and only this run merges it and finds a file that differs.
   After a darkmem copy it prints the command that deletes the `dforge/`
   originals: show it, and say to run it only once no dforge checkout on any
   machine maps the project.
6. **Commit.** Show the `report:` lines and offer to edit the files they name
   by hand. Show the `commit:` lines and offer to commit what they name as
   one commit, `chore: move to the dagents layout`. Commit only after your
   human partner agrees, and stage nothing the lines do not name.
7. **Retire the old plugins.** When `dr-forge@darkraise` is installed, first
   tell your human partner to copy the cockpit's Discord webhook and mention.
   They stay in dr-forge's plugin store,
   `~/.claude/plugins/store/dr-forge_darkraise-*.json` (under
   `$CLAUDE_CONFIG_DIR` when set), as `notifyUrl` and `notifyMention`, and
   dagents does not read that file. Once copied, they set them in a dagents
   session: the webhook in `/cockpit settings` (or `DAGENTS_NOTIFY_URL`), the
   mention with `/cockpit notify mention <id>`.
   Then remind your human partner to uninstall
   `dr-forge@darkraise` and `dr-superpowers@darkraise` when either is
   installed (`claude plugin uninstall <name>`, or `codex plugin remove
   <name>`), so their hooks do not run beside dagents's. dagents reads
   `DAGENTS_*` environment variables in place of `DR_FORGE_*`: rename any that
   a shell profile sets.
