# darkraise-ai-plugins

A plugin marketplace for Claude Code and Codex. The marketplace ID is `darkraise`.

## Conventions

- For Codex, register the repository root to select the
  `.agents/plugins/marketplace.json` catalog.
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

A task that ends in a push is done only when the CI run for the pushed
commit is green: every job of `Validate marketplace`, the Windows shards
included (`gh run list --commit <sha>`, then `gh run view <id>`). Local
passes do not stand in for it; a failed or still-running run means the task
is not done.
