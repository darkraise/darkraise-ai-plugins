---
name: init
description: Set up dflow in a repository - scaffolds docs/dflow, configures the gates, writes project.md from the code and maps the repository to darkmem.
disable-model-invocation: true
---

# Init

1. `dflow init`. It creates `docs/dflow/` (project, decisions, gotchas, board, config) and ignores `.dflow/`. It never overwrites a file.

2. **Gates.** Find what proves a change here: the package scripts, the Makefile, the CI workflow. Add them from cheapest to most expensive:

   ```
   dflow init --gate "lint=<command>" --gate "types=<command>" --gate "test=<command>" --gate "build=<command>"
   ```

   Leave out what the project does not have. Run `dflow gate` once in the background; a gate that fails before any change is a fact for the owner, not something to fix now.

3. **A project with a UI.** Add to `docs/dflow/config.json` the command that starts the app and the files that are UI:

   ```json
   { "run": { "cmd": "<start command>", "url": "<address>" }, "ui": { "paths": ["src/ui/", "**/*.css"] } }
   ```

4. **project.md.** Write it from the code, in at most 150 lines: what the system is, a module map (each top-level part and what it is responsible for, with real paths in backticks), and how to run and verify it. Describe the present; history belongs in `decisions.md`.

5. **darkmem.** When the darkmem tools are connected, ask the owner for the project name, then `dflow init --darkmem <project>`. The server address lives in `~/.dflow/config.json` as `{"darkmem": {"url": "<address>"}}` and the key in the `DARKMEM_API_KEY` variable; ask the owner to set both, never write a key to a file. `dflow sync push` then files the docs and the board.

6. **Context.** The HUD mod resets the context at task boundaries. Where mods are not loaded, suggest `/autocompact 300k` to the owner so that a long build compacts before it grows large.

7. `dflow doctor`, then commit: `docs(dflow): set up dflow`.

Tell the owner what was configured, which gates fail today, and that `/dflow:plan` starts the first plan.
