# Dual-client plugin validation

Validated locally on Windows on 2026-09-08 with Claude Code `2.1.263`, Codex
`0.153.4`, Node.js, Git Bash, jq, and GNU coreutils. These are validation targets,
not minimum supported versions. Implementation was prepared on
`feat/dual-client-plugins`. The real GitHub repository and user-installed plugins
were not changed during validation.

## Distribution evidence

The isolated real-client smoke harness is `tests/marketplace-smoke.ps1`. Every
CLI invocation has a 60-second limit, captures its process, and terminates its
tree on timeout. All test profiles/caches live in a generated fixture directory
under the ignored `.superpowers` workspace and are removed after the run.
The harness downloads the actual official Claude marketplace and Superpowers
dependency over HTTPS; no paid model or Telegram calls are made.

Verified outcomes:

- Codex local-root registration lists exactly `dr-superpowers`, `dcc-darkraise-ui`,
  and `dcc-darkraise-win32ui`, and rejects `dr-status` installation by name.
- All three Codex plugins install; installed native manifest bytes match source.
  Superpowers' native manifest explicitly contains `"hooks": {}`.
- Claude installs all four repository plugins and resolves the declared
  `superpowers@claude-plugins-official` dependency. Dependency entries are counted
  separately from the four repository plugins.
- Codex upgrades a seeded UI `0.1.0` cache to `0.2.0`, replacing actual skill bytes.
- Git-source registration selects the dedicated Codex catalog. Git's process-local
  URL mapping routes a fixture HTTPS URL to a disposable local repository; the
  future published GitHub URL was not contacted.
- Refreshing a legacy Git registration changes from Claude fallback discovery
  to the dedicated Codex catalog. Previously installed statusline and Telegram
  caches remain until explicit plugin removal; those removal commands clear them.
- A pinned legacy commit stays pinned during refresh. Explicitly changing its
  source ref to `main` selects the revised catalog.
- Codex detects a different source using the same marketplace name. Supported
  remove/add/reinstall operations recover that source change.
- Codex 0.153.4 rejects direct catalog-file registration through its CLI. Direct
  file loading in other integrations is outside the root-discovery guarantee.

The Claude marketplace and all four individual Claude plugin manifests also
pass `claude plugin validate`. The repository validator checks membership,
source/name agreement, cross-client versions, explicit Codex hook suppression,
dependency allowlisting, script version agreement, and bundled Markdown links.

## Regression evidence

`node scripts/test-all.mjs` runs the maintained suites with bounded subprocesses.
The final full run passed 27 shell suites with 1,181 assertions and the then-current
12 Node tests. Final focused checks passed all 13 current Node tests and the
43-assertion executor recovery suite. Repository validation, shell syntax checks,
and `git diff --check` also passed. No test runner processes remained afterward.
Regression coverage includes:

- Custom statusline destinations after removing/changing the environment override,
  distinct account destinations, mismatch repair, legacy default ownership,
  malformed JSON preservation, other providers, argument dispatch, and bounded
  lock contention. Native Windows jq argument conversion and CRLF output are
  explicitly handled so account keys remain stable.
- Statusline script upgrades from a seeded `0.7.0` copy to `0.8.0`, preserving
  presentation configuration. Existing renderer/theme/layout suites remain green.
- Authentication confirmed through `codex login status`, including authentication
  without a credentials file, stale files, failed probes, and suppressed probe output.
- Linked-worktree ownership, dirty initial index/worktree rejection, stable task
  IDs, exact snapshot comparison, resume identity, partial retries, changed report
  paths, no-change success, commit-hook failure, commit-only recovery, post-commit
  crash adoption, handback/release, and owned-grandchild termination on timeout.
- Deletion and literal paths containing spaces, out-of-scope output rejection,
  and refusal to overwrite unrelated staged content during recovery.
- Reviewer snapshot invalidation for HEAD, index, tracked-file, and untracked-file
  mutations. Snapshots detect drift and do not claim to establish authorship.
- Every native routing score, capability promotion, missing metadata, human pins,
  role floors, monotonic execution, one split, reserve exhaustion, and review cap.
- The actual documented Win32 dependency query finds central PackageVersion
  entries, and the restore-assets query selects the chosen framework's package
  version rather than a higher cached version.

CI is configured to run maintained regression suites on Linux and Windows, and
Claude validation on Linux, using explicit job/step/process timeouts. CI has not
been triggered remotely by this local change.

## Practical limits

Native agent dispatch, model quality, and instruction-following under pressure
were not exercised through paid model calls. Native hook suppression was checked
through the explicit installed manifest and the loader contract, not a model
session. The independent native review path does not promise cross-provider review.

The suite covers representative durable failure/recovery states; it is not an
exhaustive operating-system crash or power-loss fault-injection campaign. Locks
with uncertain process identities require manual reconciliation. Shared manual
editing of an external executor's reserved worktree remains unsupported.

The published renamed GitHub URL, a remote CI run, and migrations of real user
profiles remain separate actions. Claude's old-registration source-removal
semantics were not exercised; record installed IDs/scopes and preserve data
before following any remove/reinstall migration.

Loader/dependency contracts used during implementation are documented in the
[Codex plugin loader](https://github.com/openai/codex/blob/main/codex-rs/core-plugins/src/loader.rs),
[Codex marketplace discovery](https://github.com/openai/codex/blob/main/codex-rs/core-plugins/src/marketplace.rs),
and [Claude plugin dependencies](https://code.claude.com/docs/en/plugin-dependencies).
