---
name: migrate
description: Use when session start or repo-audit says a repository or home still uses an older layout, or when moving from dr-superpowers or dr-forge to dforge - previews the move with a dry run, migrates on one confirmation, and offers the commit
---

# Migrate

**Announce at start:** "I'm using the migrate skill to move this repository to dforge's names."

dforge reads only its own names. A repository or home that dr-superpowers
(before 3.0) or dr-forge (3.x) set up keeps its work under the older ones until
`scripts/dforge-migrate` moves it:

| Older | dforge |
|---|---|
| `.superpowers/`, `.forge/` | `.dforge/` |
| `docs/superpowers/`, `docs/forge/` | `docs/dforge/` |
| `<git dir>/dr-superpowers/`, `<git dir>/dr-forge/` | `<git dir>/dforge/` |
| `~/.dr-superpowers/`, `~/.dr-forge/` | `~/.dforge/` |
| darkmem's `superpowers/` and `forge/` documents | `dforge/` |

An active plan (one its `completed.md` does not record) and the handoff note
get their `dr-superpowers:` and `dr-forge:` prefixes rewritten to `dforge:`,
so they keep running. Finished plans, specs, ledgers and registers keep their
text as history; dforge still reads their citations.

Every change goes through `scripts/dforge-migrate`. This skill writes nothing
itself.

## Steps

1. **Preview.** From the repository, run
   `bash <plugin-root>/scripts/dforge-migrate --dry-run` and show its output.
   When `~/.dr-forge/config.json`, `~/.dr-superpowers/config.json` or
   `~/.dforge/config.json` holds a `darkmem` section, say that darkmem's
   documents move to `dforge/` at its next sync.
2. **Nothing to move.** When it prints `nothing to migrate`, say so and stop.
3. **Foretold refusals.** When it exits 1, show each `refused:` line with the
   fix it names, and ask whether to resolve them first. A refusal stops only
   its own part; the rest still moves.
4. **Confirm once.** Ask your human partner whether to migrate. Run nothing
   that writes before a yes.
5. **Migrate.** Run `bash <plugin-root>/scripts/dforge-migrate` and show its
   output. On exit 1, list each refusal and its fix, and offer to run it again
   once they are resolved: a second run finishes the job.
6. **Commit.** Show the `commit:` lines and offer to commit what they name as
   one commit, `chore: move to the dforge layout`. Commit only after your
   human partner agrees, and stage nothing the lines do not name.
7. **Retire the old plugins.** When `dr-forge@darkraise` is installed, first
   tell your human partner to copy the cockpit's Discord webhook and mention.
   They stay in dr-forge's plugin store,
   `~/.claude/plugins/store/dr-forge_darkraise-*.json` (under
   `$CLAUDE_CONFIG_DIR` when set), as `notifyUrl` and `notifyMention`, and
   dforge does not read that file. Once copied, they set them in a dforge
   session with `/cockpit notify url <url>` and `/cockpit notify mention <id>`.
   Then remind your human partner to uninstall
   `dr-forge@darkraise` and `dr-superpowers@darkraise` when either is
   installed (`claude plugin uninstall <name>`, or `codex plugin remove
   <name>`), so their hooks do not run beside dforge's. dforge reads
   `DFORGE_*` environment variables in place of `DR_FORGE_*`: rename any that
   a shell profile sets.
