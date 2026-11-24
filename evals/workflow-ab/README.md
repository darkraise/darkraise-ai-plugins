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
  version, the `autoCompactWindow` the scripts read and whether darkmem is
  available.
- **`--check`** runs the plan's `**Worktree setup:**` and `**Integration
  check:**` commands in the clone with `HOME` and `GOCACHE` in the run
  directory, each in its own process group and killed at two hours. A failure
  writes `check-failed` to `state` and exits 1. Run it before any model
  spend on a large plan.

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

## Run directory

`<WAB_ROOT>/<ARM>-<RUN>/` holds `clone/`, `home/`, `arm.json`,
`plan.orig.md` (the plan as the source holds it), `out/` (`plan-lint.txt`,
the check logs) and, once a check fails or a launch starts, `state`.

## Writes outside scratch

`prepare` writes nothing outside `WAB_ROOT`; it only reads the source, the
owner's dforge config and the owner's Claude settings.

## Tests

`tests/dforge/workflow-ab.test.sh` builds a source from `fixture/`, a
two-task plan in one wave with `dforge:impl-*` Implementer lines and an
unqualified `**Items:**` citation. It runs on Linux only.
