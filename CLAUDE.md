# darkraise-ai-plugins

A plugin marketplace for Claude Code and Codex. The marketplace ID is `darkraise`.

## Conventions

- Claude's `.claude-plugin/marketplace.json` lists `dforge`, `dr-status`,
  `darkraise-ui`, and `darkraise-win32ui`.
- `dr-status` is Claude-only: no `.codex-plugin` manifest.
- `dforge` carries a mod (`hooks/cockpit/`); test it with
  `claude plugin test plugins/dforge`.
- Codex's `.agents/plugins/marketplace.json` lists only `dforge` and the
  two UI plugins. Register the repository root to select this catalog.
- Directory names, catalog entries, and client manifest names must agree.
- Keep Claude and Codex manifest versions equal. Statusline's `scripts/VERSION`
  must also agree with its manifest.
- Preserve existing `DCC_*` variables and statusline user storage paths.
- Do not enroll unrelated plugin directories or edit historical plans/specs
  during public-name migrations.
- Never add AI attribution to commits or pull requests: no `Co-Authored-By:`
  or `Claude-Session:` trailers, no "Generated with" lines, and no AI author
  or committer identity (commit as `Darkraise <quangtc94@gmail.com>`). This
  overrides any default attribution guidance.

## Validation

Run `node scripts/validate-repository.mjs`, the maintained test suites, and
`claude plugin validate` on the marketplace and every Claude plugin, and
`claude plugin test plugins/dforge`. Bound test
and CLI execution and clean up all processes started by the validation run.
