# darkraise-ai-plugins

## What it is

A plugin marketplace for Claude Code and Codex. The marketplace ID is
`darkraise`. Each plugin lives in its own directory under `plugins/` and is
listed in a catalog per client.

## Module map

| Path | Responsibility |
| --- | --- |
| `.claude-plugin/marketplace.json` | The Claude Code catalog: every plugin |
| `.agents/plugins/marketplace.json` | The Codex catalog: the plugins Codex supports |
| `plugins/dflow/` | The dflow workflow plugin (Claude Code only): CLI in `plugins/dflow/lib/`, skills, two agents, hooks, the HUD mod in `plugins/dflow/hooks/hud/`, a workflow script and evals |
| `plugins/dforge/` | The dforge workflow plugin (Claude Code and Codex), with its cockpit mod |
| `plugins/dr-status/` | A status line for Claude Code |
| `plugins/darkraise-ui/` | A skill for writing darkraise-ui code |
| `plugins/darkraise-win32ui/` | A skill for writing Darkraise.Win32UI code |
| `scripts/validate-repository.mjs` | Checks catalogs, manifests, versions, links and retired names |
| `scripts/test-all.mjs` | Runs every maintained suite; `scripts/test-shards.mjs` splits them for Windows CI |
| `tests/` | Repository-level tests: catalog layout, shards, portability lint |
| `evals/tiers/` | The model-tier eval harness for dforge |
| `docs/dflow/` | dflow's design record, board and plans for this repository |
| `docs/dforge/` | dforge's specs, plans, registers and notes |
| `.github/workflows/validate.yml` | CI: Ubuntu, and Windows in fourteen shards |

A plugin's directory name, its catalog entries and its manifest name agree.
`dflow` and `dr-status` are Claude Code only and have no Codex manifest.

## Run and verify

Node 22, Bash, Git, `jq` and the Claude Code CLI are needed.

```text
node scripts/validate-repository.mjs
node scripts/test-all.mjs
claude plugin validate .
claude plugin validate plugins/<plugin>
claude plugin test plugins/dforge
claude plugin test plugins/dflow
```

Unset `CLAUDE_CONFIG_DIR` before `scripts/test-all.mjs`. Give every command a
timeout and stop what it starts. A change that is pushed is done only when
every job of the `Validate marketplace` run for that commit is green, the
Windows shards included.

dflow's own suite runs alone with:

```text
node --test "plugins/dflow/tests/*.test.mjs"
```

## Conventions

- Commits are `<type>(<scope>): <subject>`, with no attribution line.
- Do not enrol unrelated plugin directories in a catalog.
- Keep existing `DCC_*` variables and the status line's user storage paths.
