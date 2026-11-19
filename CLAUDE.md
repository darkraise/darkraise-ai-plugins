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

Run `node scripts/validate-repository.mjs`, the maintained test suites
(`node scripts/test-all.mjs` and `node scripts/test-all.mjs --plugin
dagents`), and `claude plugin validate` on the marketplace and every Claude
plugin, and `claude plugin test` on `plugins/dforge`, `plugins/dagents` and
`plugins/dflow`. Bound test and CLI execution and clean up all processes
started by the validation run.

A push runs the slice: the Linux suites and the Windows portability slice.
A task that ends in a push is done only when every job of the run for the
pushed commit is green (`gh run list --commit <sha>`, then
`gh run view <id>`). Local passes do not stand in for it; a failed or
still-running run means the task is not done. A dagents job skipped by its
path filter counts as green. Also read the latest full run on `main`
(`gh run list --workflow validate.yml --branch main --json
displayTitle,conclusion,headSha,createdAt,url`, titles ending `(full)`):
report a failed one, or none in the last 48 hours, as a finding against the
commits since the last green full run. Read the latest `release.yml` run too
(`gh run list --workflow release.yml --limit 1`): a nightly skips a commit a
full run already validated, so a failed release is not retried; report it,
and rerun it with `gh workflow run release.yml -f validated=<sha>`.
