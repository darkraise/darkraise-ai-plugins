# workflow-ab: replay one plan under dforge and dagents

Replays a plan's execution in throwaway clones, once per arm, so the two
plugins can be compared on the same work with the same metrics. A run never
touches the source repository: it clones it, strips the clone to the base
commit, and refuses every push.

## Commands

```
evals/workflow-ab/prepare ARM RUN [--check]
```

`ARM` is `dforge` or `dagents`; `RUN` names the run (`1`, `2`, …). `prepare`
creates `<WAB_ROOT>/<ARM>-<RUN>/` and refuses an existing one.

- **Clone.** `git clone --no-hardlinks` of `WAB_SOURCE`, checked out on the
  branch `replay-base` at `WAB_BASE`. Every other branch and tag and the
  remote are deleted, the reflog expired and the objects pruned, so nothing
  past the base is reachable. A `pre-push` hook exits 1, and the clone commits
  as `Replay <replay@localhost>`. When the plan is absent at the base, the
  newest commit of the source that holds it supplies it.
- **Plan conversion.** dforge: the Execution line becomes `inline` on the
  highest tier any `dforge:impl-*` Implementer line names (haiku counts as
  sonnet), at that tier's effort, raised to `high` when a task has risk 3;
  bare `**Items:**` numbers are qualified with the basename of the register
  the spec's `**Register:**` line names; Implementer lines stay. dagents:
  `docs/dforge/` moves to `docs/dagents/` (dagents reads only its own docs
  tree) and `dforge:impl-` becomes `dagents:impl-`; the Execution and
  Parallelism lines stay. Both append one line to Global Constraints saying
  the run has no remote. The result is one commit, `chore: replay plan`, and
  the arm's `plan-lint` must pass.
- **Pins**, in the run's scratch `home/`: `handoffTokens` from the owner's
  dforge config (read only), else `DFORGE_BUDGET`, else 300000;
  `finishAction` `keep`; dforge `decisionApi` `off`, every `apiBudget*` cap 0,
  `codexReview` and `agyReview` false; dagents `codexReview`, `codexLane` and
  `agyLane` false. `clone/.claude/settings.local.json` switches off every
  plugin the clone's project settings enable, and is excluded from git.
- **Record.** `arm.json` holds the arm, the plan path in the clone, the plugin
  commit, the pins, the launch model and effort, parallelism, the Claude Code
  version, the `autoCompactWindow` the scripts read and whether a darkmem MCP
  server is configured for the nested session (in the config directory's
  `.claude.json` or the clone's `.mcp.json`). An unparsable settings or
  `.claude.json` file fails `prepare`.
- **`--check`** runs the plan's `**Worktree setup:**` and `**Integration
  check:**` commands in the clone under the launch environment (`env -i`
  with the variables `launch` sets, `HOME` and `GOCACHE` in the run
  directory), each in its own process group and killed at two hours. A failure
  writes `check-failed` to `state` and exits 1. Run it before any model
  spend on a large plan.

```
evals/workflow-ab/launch ARM RUN [--max-minutes N]
```

Runs a prepared replay. Exactly the arm's plugin may load: `launch` exits 1
when the clone's project settings enable any other. It starts the tmux
session `wab-<ARM>-<RUN>` (the only tmux session it touches) running Claude
Code in the clone under `env -i` with:

- `HOME=<run>/home`, `IS_SANDBOX=1`, and `CLAUDE_CONFIG_DIR` set to the
  owner's config directory for the login only (credentials are never copied);
- `GIT_ALLOW_PROTOCOL=file`, `GIT_SSH_COMMAND=false`, `GIT_TERMINAL_PROMPT=0`,
  an empty `GH_CONFIG_DIR`, an empty `WORKFLOW_GUARD_CLAUDE_DIR`, and no
  token, ssh agent or API key;
- `--setting-sources project,local`, `--settings` holding
  `{"skipDangerousModePermissionPrompt":true}`,
  `--plugin-dir <WAB_PLUGINS>/plugins/<ARM>` and a known `--session-id`.

It accepts the folder-trust prompt, waits for the cockpit's heartbeat, then
seeds the run through the arm's own switch path (`auto-run start`, `phase
plan`, `attach --plan`, `next-step`, `switch`, and a first prompt answered
`Auto run: switching`). Every session id the run binds is appended to
`sessions`. Every 30 seconds it reads the run's `auto-run.json`: `finished`
once the run is inactive in its finish phase with no stop reason, `stopped`
when it has one. At `--max-minutes` (default 720; `WAB_MAX_SECONDS` overrides
it) it stops the bound run, kills its tmux session and the session's process
tree, and writes `timed-out`. A launch killed by a signal stops the run the
same way and writes `stopped`.

```
evals/workflow-ab/collect ARM RUN
```

After a launch, copies the transcripts of the sessions listed in `sessions`
(with their `subagents/`) from the owner's project directory for the clone
into `out/transcripts/`, runs this repository's dforge copy of the usage
report core over that run alone (the clone's marker file, ledger, plan and
register), and writes `out/report.json` and `out/dispatches.json` (dispatch
counts per family).

```
evals/workflow-ab/compare [--out FILE]
```

Writes the comparison note (default `<WAB_ROOT>/comparison.md`) over every
run under `WAB_ROOT`: `## Runs` (each `arm.json`, runs that did not finish
marked and listed), `## Per-task distributions` (min, median and max of
turns, lookups, growth, cache writes and subagent share per arm, finished
runs only, a group row counted once and divided by its task count),
`## Spread across runs` (each finished run's median per metric),
`## Groups`, and `## What this replay cannot decide`.

### The w8 replay (run after merge)

```
export WAB_SOURCE=/root/repositories/darkpanel WAB_BASE=33bc6da6 \
  WAB_PLAN=docs/dforge/plans/2026-11-04-v1-w8-panel-exposure.md
```

Then, for runs 1 and 2 of each arm, `prepare ARM RUN --check` (it prepares
the run and runs the plan's setup and Integration check before any model
spend), `launch ARM RUN` and `collect ARM RUN`, and finally `compare`; the note is copied to
`docs/dforge/notes/<date>-dforge-vs-dagents-replay.md`.

## Parameters (environment)

| Name | Default | Meaning |
|---|---|---|
| `WAB_ROOT` | `${XDG_CACHE_HOME:-$HOME/.cache}/workflow-ab` | scratch root; refused under `/tmp` |
| `WAB_SOURCE` | (required) | source repository |
| `WAB_BASE` | (required) | base commit |
| `WAB_PLAN` | (required) | plan path in the source |
| `WAB_PLUGINS` | this repository | where `plugins/<arm>` is read from |
| `WAB_CLAUDE_CONFIG` | `$CLAUDE_CONFIG_DIR` or `~/.claude` | owner's Claude config directory (read only) |
| `WAB_DFORGE_CONFIG` | `~/.dforge/config.json` | owner's dforge config (read only) |
| `WAB_CLAUDE` | `/root/.local/bin/claude` | the `claude` binary |
| `WAB_TMUX` | `tmux` | the `tmux` binary |
| `WAB_MAX_SECONDS` | `--max-minutes` × 60 | the launch's wall-clock limit (tests) |

## Run directory

`<WAB_ROOT>/<ARM>-<RUN>/` holds `clone/`, `home/`, `arm.json`,
`plan.orig.md` (the plan as the source holds it), `out/` (`plan-lint.txt`,
the check logs, `seed.log`), `launcher.sh`, `claude-settings.json`,
`sessions`, `settings-key` and, once a check fails or a launch starts,
`state` (`check-failed`, `running`, `finished`, `stopped` or `timed-out`).

## Writes outside scratch

`prepare` writes nothing outside `WAB_ROOT`; it only reads the source, the
owner's dforge config and the owner's Claude settings and `.claude.json`. A launch writes the
nested sessions' transcripts and project entry under the owner's config
directory. Accepting the bypass prompt would write
`skipDangerousModePermissionPrompt` into the owner's `settings.json`: `launch`
records in `<run>/settings-repair` whether the key was there before, and
when it was not, its exit, or the start of the next `prepare`, `launch`,
`collect` or `compare` after a killed one, removes the key with an atomic rewrite (at the link's target when
`settings.json` is a symbolic link) that leaves every other byte as it was.

## Tests

`tests/dforge/workflow-ab.test.sh` builds a source from `fixture/`, a
two-task plan in one wave with `dforge:impl-*` Implementer lines and an
unqualified `**Items:**` citation. It runs on Linux only.

## Verified

On 2026-11-24, with Claude Code 2.1.331 and both plugins at this
repository's HEAD, `prepare --check` and `launch --max-minutes 90` ran the
fixture under each arm, one after the other: both runs were seeded through
the arm's own switch path (`arm.json` `"seeded": "switch path"`), bound three
sessions each (seeding, execution, finishing), and ended `finished`: dforge in
5 minutes, dagents in 9. The owner's `settings.json` hashed the same before
and after both runs (it already held `skipDangerousModePermissionPrompt`, so
the repair had nothing to remove), and neither clone gained a remote.
