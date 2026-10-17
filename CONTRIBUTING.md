# Contributing

Thanks for your interest. This repository is a plugin marketplace for Claude
Code and Codex; each plugin lives under `plugins/<name>/`. Bug reports, fixes and
documentation improvements are welcome. For a new feature or a new plugin, open
an issue first so the scope can be agreed before you write code.

## Repository layout

| Path | Contents |
| --- | --- |
| `.claude-plugin/marketplace.json` | The Claude Code catalog: `dr-forge`, `dr-status`, `darkraise-ui`, `darkraise-win32ui`. |
| `.agents/plugins/marketplace.json` | The Codex catalog: `dr-forge` and the two UI plugins. Codex discovers it from the repository root. |
| `plugins/<name>/` | One plugin: its manifests, skills, hooks, scripts and tests. |
| `scripts/` | Repository validation and the full test runner. |
| `tests/` | Repository-level tests (catalog layout, shards, UI discovery). |
| `docs/` | Design records, testing notes and the migration guide. |

## Conventions

- The marketplace ID is `darkraise`. A plugin's directory name, its catalog
  entries and its client manifest names must agree.
- Keep the Claude (`.claude-plugin/plugin.json`) and Codex
  (`.codex-plugin/plugin.json`) manifest versions equal. `dr-status` is Claude
  Code only and has no Codex manifest; add a Codex manifest only for a plugin
  Codex supports. `plugins/dr-status/scripts/VERSION` must match its manifest.
- Preserve existing `DCC_*` environment variables and the statusline's user
  storage paths.
- Do not enroll unrelated plugin directories in a catalog.
- Write code, comments, documentation and commit messages in English.
- Comment only where the reason is not obvious from the code.

### Commits

Use `<type>(<scope>): <subject>`, where the type is one of `feat`, `fix`,
`docs`, `style`, `refactor`, `test`, `chore` or `perf`. Keep the subject to 50
characters, in the imperative, without a trailing period, and add a body
(wrapped at 72 characters) for anything that needs the reasoning. Keep commits
atomic: one concern each.

## Checking your change

You need Node.js 22, Bash, Git, `jq` and the Claude Code CLI. Run these from the
repository root with a timeout on each, and stop anything they start:

```text
node scripts/validate-repository.mjs
node scripts/test-all.mjs
claude plugin validate .
claude plugin validate plugins/<plugin>
claude plugin test plugins/dr-forge
```

`node scripts/test-all.mjs` runs the full maintained suite and prints each
suite's duration. Unset `CLAUDE_CONFIG_DIR` first, since a value leaking in from
your shell changes the budget tests. A suite that runs against the real home
directory sets `DR_FORGE_NO_SETTINGS=1`, under which every `forge_setting`
answers its default without reading `~/.dr-forge/config.json`. Installation and upgrade tests use
disposable profiles, caches and Git repositories; they must never modify your
installed plugins or call a paid model.

CI runs the same checks on Ubuntu, and on Windows split across six shards
(`--shard 1/6` through `--shard 6/6`; add `--list` to inspect a shard without
running it). New suites are discovered automatically, and
`scripts/test-shards.mjs` holds the approximate timings used to balance the
shards.

### Tests

Add a test with a behavior change, and write it first: watch it fail for the
expected reason, then make it pass. Put each test at the lowest layer that can
fail for the change. dr-forge's shell suites live in
`plugins/dr-forge/tests/*.test.sh` and print only failures, ending with a
`N passed, M failed` line.

## Pull requests

1. Branch from `main`.
2. Make the change, with its tests and any documentation it affects.
3. Run the checks above and say in the pull request which ones you ran.
4. Describe what changed and why, and link the issue it closes.

By contributing you agree that your contribution is licensed under the
[MIT License](LICENSE).
