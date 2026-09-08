# Darkraise plugins revision

Status: revised after the GPT-6 Astra design review; implementation approved and
carried out on 2026-09-08. Validation evidence and remaining test limits are in
[the validation record](../../testing/dual-client-marketplace-validation.md).

## Outcome

The renamed `darkraise/darkraise-plugins` repository distributes four plugins.
The marketplace identifier remains `darkraise`.

| Plugin | Claude Code | Codex |
| --- | --- | --- |
| `dr-status` | Available | Absent from catalog |
| `dr-superpowers` | Available | Available |
| `dcc-darkraise-ui` | Available | Available |
| `dcc-darkraise-win32ui` | Available | Available |

Remove the Telegram plugin and its active documentation and tests. The untracked
`plugins/darkmem-resume/` directory is unrelated user work and is excluded.
Historical specifications and plans remain historical records.

## Distribution and naming

Rename `plugins/dcc-statusline/` to `plugins/dr-status/` and
`plugins/dcc-superpower-companions/` to `plugins/dr-superpowers/`. Update plugin
identifiers, slash commands, agent namespaces, active references, repository
URLs, and repository conventions. Both UI plugin identifiers remain unchanged.

Keep `.claude-plugin/marketplace.json` with all four plugins. Add
`.agents/plugins/marketplace.json` with only `dr-superpowers` and the two UI
plugins, plus native Codex manifests for those three plugins.

Codex supports the Claude marketplace and manifest formats as fallbacks. Its
loader searches `.agents/plugins/marketplace.json` first, so a dedicated catalog
controls repository-root discovery. The supported Codex registration routes are
the repository Git URL and a local repository-root directory. The guarantee is
that these routes list exactly three plugins and cannot install `dr-status`.
Explicitly loading `.claude-plugin/marketplace.json` bypasses root discovery and
is not a supported Codex installation route; document that limitation rather
than promising that every possible direct manifest load hides the Claude catalog.

Set `"hooks": {}` in the `dr-superpowers` Codex manifest. Omitting the field
would load the Claude `hooks/hooks.json` by default. Verify that the installed
Codex package loads no Claude hooks; preserve the Claude manifest's hook discovery.

### Existing registrations and releases

For an existing repository-root registration, refresh the marketplace first and
verify the selected catalog and its plugin names. A registration pinned to an old
commit must explicitly move to the revised release. If the renamed Git URL
conflicts with the existing `darkraise` source, record installed plugin names and
scopes, remove that marketplace registration through the client's supported
command, add the new repository root, and reinstall the selected supported
plugins. Check removal semantics before publishing those client-specific steps;
do not assume installed plugins survive marketplace removal. Preserve user
configuration and data, and document removal of previously installed Telegram
and statusline entries in Codex: removing a catalog entry alone is not an uninstall.

Disable the old Claude plugin identifiers before enabling their replacements so
both versions cannot register hooks concurrently. Removing Telegram from the
repository does not revoke its bot token or erase its per-user configuration.
Document how existing users uninstall it; deletion of their configuration is a
separate user action. Historical reports remain readable.

Use these release versions, with identical versions in each plugin's Claude and
Codex manifests where both exist:

| Plugin | Release version |
| --- | --- |
| `dr-status` | `0.8.0` |
| `dr-superpowers` | `0.5.0` |
| `dcc-darkraise-ui` | `0.2.0` |
| `dcc-darkraise-win32ui` | `0.2.0` |

Set `dr-status/scripts/VERSION` to `0.8.0` as well. Keep the installed statusline
renderer's version check tied to this value. Increase the Claude marketplace's
existing version to `0.3.0`. Upgrade tests must inspect installed skill and script
contents, since a catalog refresh alone does not demonstrate a plugin-cache update.

Codex `0.153.4` and Claude Code `2.1.263` are the local validation targets, not
asserted minimum supported versions. Actual old-registration upgrade behavior on
these versions remains unverified until the isolated installation tests pass.

Sources checked on 2026-09-08:

- [Codex marketplace loader](https://github.com/openai/codex/blob/main/codex-rs/core-plugins/src/marketplace.rs)
- [Codex plugin packaging](https://learn.chatgpt.com/docs/build-plugins)
- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
- [Codex hook discovery and versioned cache refresh](https://github.com/openai/codex/blob/main/codex-rs/core-plugins/src/loader.rs)
- [Codex registration and source conflicts](https://github.com/openai/codex/blob/main/codex-rs/core-plugins/src/marketplace_add.rs)

## Statusline installation

The public command becomes `/dr-status`. Keep scripts under
`~/.claude/dcc-statusline/`, presentation configuration at
`~/.claude/dcc-statusline.json`, and existing environment overrides. The rename
must not discard configured accounts or themes.

Persist installation locations in
`~/.claude/dcc-statusline-installations.json`, with schema version `1` and entries
keyed by normalized absolute account configuration directory. Each entry records
the normalized absolute script destination and the exact registered command.
Use the existing fake-home override to isolate this file in tests.

During installation, resolve the destination from an explicit
`DCC_STATUSLINE_HOME`, otherwise the account's recorded destination, otherwise
the default. `--all` applies this rule separately to every discovered or recorded
account. The override selects an installation destination; it need not remain
exported after installation. Changing it later moves an account only when the
user explicitly runs install again. Do not delete old script directories.

Synchronization, diagnostics, status, and removal use the account's recorded
destination and command, regardless of a later ambient destination override.
Match ownership by exact command equality, never by a loose substring or by
evaluating the settings command. Without an installation record, recognize only
the exact legacy command `bash ~/.claude/dcc-statusline/statusline.sh` at the
default destination. A legacy custom destination requires an explicit reinstall
with that override; do not guess ownership from arbitrary command text.

Serialize installation-record and settings changes with a bounded per-user lock,
and replace each validated JSON file atomically. Write the installation record
before registering a new settings command. If the settings write then fails,
return failure and retain the intended record as a detectable mismatch; a
subsequent install can repair it. Sync must require matching settings before
copying files, so an incomplete installation cannot activate itself.

- Parse the subcommand once and pass only its remaining arguments to the script.
- Return a nonzero exit code if any requested account fails installation or
  removal, while still reporting every account's outcome.
- Generate the registered command from the resolved script destination, with
  shell-safe quoting and JSON-safe serialization.
- Remove a statusline only when its command belongs to this installation,
  including the known command written by the previous release. Preserve any
  other provider's configuration.
- Remove an account's installation record only after successful removal of its
  owned settings command. A different provider is reported as such and left
  untouched. Status and doctor must use the same ownership predicate as removal;
  any nonempty `statusLine` is not sufficient evidence of installation.
- Preserve unrelated settings and fail without replacing malformed JSON.
- Explain migration from the old plugin identifier, including disabling the old
  plugin to avoid duplicate update hooks. Do not change real user settings during
  development or validation.

## Superpowers integration

Preserve the Claude agent fleet and existing scoring, split, escalation, and
review rules under the `dr-superpowers` namespace. Declare its required
Superpowers dependency using Claude Code's supported dependency schema.

### Client selection and plan migration

Add an explicit Codex path to each shared skill, selected from the active
client's native tools. The existence of a `codex` executable does not identify
the host. Codex uses its native subagent API with explicit model and effort;
Claude uses its registered agent fleet. Shared skill descriptions and explicit
invocation activate the Codex path without a `Skill` hook. Missing host tools,
model metadata, or required Superpowers skills produce an actionable prerequisite
failure before dispatch.

On Claude, translate only the exact old namespace
`dcc-superpower-companions:` to `dr-superpowers:` when reading a known fleet
agent. Preserve its agent suffix, effort, evaluation, and reserve override; record
the translation in the ledger without rewriting the consumer's plan. Unknown
suffixes fail validation. This is the rename migration, not a model substitution.

New plans record the host and routing-policy version in their header, and every
task records `Implementer`, `Evaluation`, and `Assignment source` (`rubric` or
`human`). A Codex implementer is written as `codex <model> / <effort>`. Keep the
original assignment fixed; actual attempts and substitutions belong in the ledger.

Opening a plan authored for the other host requires an explicit conversion:
show the original and proposed assignments, retain the evaluation, and obtain
approval before adding host-specific assignments. Do not rescore during conversion.
Treat legacy assignments without an assignment source as human-pinned; reserve
overrides have no automatic cross-host equivalent. Keep the previous assignment
alongside an approved replacement so historical intent survives. A Claude
external `Executor: codex ...` entry must not trigger recursive CLI offload when
the host is Codex.

### Native Codex routing policy `codex-v1`

Keep the existing four-axis rubric and Rule S. After the split gate passes, use
the following candidate policy. These pairs are plugin policy choices, not a
claim that every client or account exposes them:

| Score/rank | Model | Reasoning effort |
| --- | --- | --- |
| 0 | `gpt-5.6-luna` | `low` |
| 1 | `gpt-5.6-luna` | `medium` |
| 2 | `gpt-5.6-sol` | `low` |
| 3 | `gpt-5.6-sol` | `medium` |
| 4 | `gpt-5.6-sol` | `high` |
| 5 | `gpt-6-astra` | `high` |
| 6 | `gpt-6-astra` | `xhigh` |

Filter pairs against the active client's advertised model/effort capabilities
and applicable user model policy at planning and again at dispatch. For a
rubric-derived assignment, choose the first available rank at or above its
score; announce and record any promotion. Never silently demote, enter reserve,
or inherit the controller model. If no execution pair qualifies, stop with the
missing capability. A human-pinned pair requires approval before substitution.
Unadvertised capability is unknown and is not established through a paid probe.

At the existing escalation triggers, advance to the next available higher rank,
record the attempted ranks, and never revisit a rank for capability escalation.
Exhausting execution rank 6 requires splitting the remaining task once. If that
split is already consumed and the split child again exhausts execution ranks,
the reserve sequence is `gpt-6-astra/max`, then `gpt-6-astra/ultra`, then BLOCKED.
Skip unavailable reserve pairs; do not map them back to execution ranks. The
existing five-round review cap still applies and can terminate a task earlier.
Transport retries do not reset either the rank history or the split budget.

Scouts use the first available execution pair at or above rank 3; judges use
the first at or above rank 5. A reviewer is always a separate agent with the
review package, not the implementer's conversation. Preserve criteria scoring,
best-of-three selection, and the three independent risk-3 evaluations. Native
Codex provides independent review, not a guaranteed cross-provider review seat;
label that distinction in the README and ledger.

Every native child receives its role instructions, task/criteria inputs, and
the applicable verification-before-completion instructions explicitly. Never
assume Claude `skills:` or `tools:` frontmatter is applied. Start new children
with an isolated context and explicit model/effort using the active tool schema;
resume the recorded implementer for fix rounds while that client supports it.
Never assume a full-history fork accepts model overrides. Use supported
per-agent read-only restrictions for scouts and judges when available. If the
client cannot enforce them, label the role restrictions as instruction-only,
prohibit writes and further delegation in the prompt, run without concurrent
writers, and verify HEAD, index, tracked files, and untracked files afterward.
A mutation invalidates the review and blocks continuation; preserve the changes
for inspection. If the task or user's policy requires enforced isolation, this
fallback is unavailable and the role cannot run on that client.

### External Codex executor ownership

The external executor remains a Claude-hosted offload path. It continues using
the existing CLI-specific model policy, separate from native `codex-v1`, and
requires bounded `codex login status` detection. Distinguish a failed probe from
confirmed logged-out status without exposing credentials. Check and document
GNU `timeout` wherever direct commands require it.

Require an exclusively assigned linked Superpowers worktree for external runs;
refuse the primary checkout. The controller must reserve that worktree for the
current task and stop all other writing agents, watchers, and user editing
there before starting. Read-only reviews may run between attempts. This is an
explicit workflow precondition: fingerprints detect drift but cannot identify
an arbitrary concurrent writer. Concurrent manual editing of this worktree is
unsupported. Users can continue working in their primary checkout.

Use a persistent task-owner record plus an atomic per-run lock in the worktree's
Git directory. These prevent cooperating plugin invocations from sharing the
worktree. Bind them to the canonical repository/worktree identities, expected
HEAD, task ID, and process identity; a PID alone or an expired timer does not
prove a previous writer has stopped. Never force-clear an uncertain owner.

An initial task requires a clean index and no pending tracked or untracked
changes. Keep wrapper state and execution artifacts outside the source checkout
under its Git directory; do not exempt arbitrary untracked paths. The dispatcher
passes a stable `--task-id` on every initial run, retry, and resume. The wrapper
derives its state location from that ID independently of `--report`.

Resolve optional human-readable reports under Superpowers' ignored workspace or
outside the checkout. Reject report destinations that could become tracked or
untracked source changes. The authoritative execution artifacts remain in the
task directory even when the human-readable report path changes.

Before staging, require the same repository identity and expected HEAD, no
unexpected index changes, and a diff confined to the task's approved write set.
Derive that write set from the plan's explicit create/modify/delete paths; added
paths require a recorded scope amendment before another run. Use literal,
repository-relative paths, support deletions and both sides of renames, and
reject paths escaping the worktree. Stage only the validated diff, verify the
complete staged tree against it, then commit. Never use repository-wide
`git add -A`, and never treat a post-run fingerprint alone as ownership proof.

### Durable execution and recovery

The version-1 task record contains the task ID, repository/worktree identities,
initial base and expected HEAD, approved write set, model/effort, current thread,
attempt and review counters, process identities, phase, artifact locations, and
expected pending worktree/index state. Record paths, content hashes, file modes,
deletions, and rename endpoints. Update it atomically before launch and at every
phase transition, including successful runs.

Use phases `ready`, `running`, `pending`, `committing`, `complete`, `handed-back`,
and `blocked`. A phase is a recovery contract, not evidence that a child exited.

- Initial execution goes from ready to running only after clean preflight and
  lock acquisition. Record the process identities and discovered thread as soon
  as they become available. If termination occurs before these are recorded,
  block automatic recovery until the absence of a writer is established.
- An incomplete run with all children confirmed stopped becomes pending. Record
  the validated task diff and index state; unexpected paths or HEAD changes
  instead become blocked. A fresh retry uses the same task record and pending
  state, may launch a new thread, and preserves the previous thread in history.
- A successful run records the intended staged tree, parent, and commit subject
  before entering committing. After commit, record the resulting HEAD, clear
  pending changes, and enter complete. A no-change success still records its
  thread and complete state so subsequent review fixes can resume it.
- A review-fix resume is legal from complete or validated pending state. It must
  match the stored thread and model/effort and expected HEAD. Its feedback and
  report path may differ; the task record and counters do not reset.
- Staging or commit failure preserves the actual index and worktree snapshot in
  a blocked record with the prior phase. A dedicated commit-recovery operation
  revalidates the intended tree and parent before retrying the commit without
  rerunning the model. If the commit succeeded before a crash, adopt it only
  when HEAD matches the recorded candidate tree, parent, and subject exactly;
  otherwise require manual reconciliation.
- Interruption or timeout terminates the owned process tree and confirms it is
  gone before inspecting files or allowing another writer. A survivor or unknown
  process identity keeps the task blocked and ownership reserved. Do not use
  elapsed time as permission to retry.
- Handback validates and records the pending state, confirms child termination,
  then explicitly transfers worktree ownership to the Claude implementer. The
  old external task cannot resume after handback. Review completion releases a
  clean completed task's ownership; never remove a worktree containing blocked
  or unreconciled work.

Keep existing wrapper exit codes: 0 for DONE, 1 for an executed non-DONE run,
and 2 for preflight or persistence/commit failure. The task record and explicit
error phase distinguish an exit 2 before execution from one afterward. Replace
the dispatcher's existing manual whole-tree staging recovery with this protocol.
Old runs without a task record require explicit reconciliation; do not infer
ownership from an old report. Any manual repair must be accepted as a new
recorded baseline before automatic execution can continue.

## UI skills

Replace Claude-only inline shell preprocessing with explicit context-discovery
instructions executable through either client's available shell tools. Resolve
paths against the consumer project, and handle missing packages with an
actionable result rather than assuming the pinned API is installed.

For Win32 UI, inspect `PackageReference`, `ProjectReference`, and centrally
managed `PackageVersion` entries. Prefer the selected framework's resolved
version and package path from restore assets where available. Never infer the
installed version from the highest version in the entire NuGet cache. Retain
the rules and references bundled with both skills.

## Validation and delivery

Use targeted failing regression tests for installation arguments, error exits,
ownership-aware removal, custom destinations, authentication backends, executor
commit provenance, and central package-version discovery. Run the remaining
plugins' existing shell suites after the changes.

The regression matrix must include:

- Native routing for every score, missing models and efforts, pinned overrides,
  monotonic escalation, one split, exhausted reserve, and the five-round cap;
  old namespace translation and explicitly approved cross-host plan conversion.
- Native role prompts carrying verification and tool restrictions, no Claude
  hooks loaded by Codex, and mutation detection for instruction-only reviewers.
- A custom statusline install followed by sync, doctor, status, and uninstall
  without the original environment override; separate destinations for accounts,
  legacy default adoption, malformed registry/settings, and another provider's
  command reported accurately and preserved.
- Executor rejection of unrelated staged, unstaged, and untracked changes; primary
  checkout rejection; concurrent plugin lock contention; changed HEAD/index;
  files outside scope; deletion, rename, mode change, and paths with spaces.
- Partial initial retry, successful-run fix resume, changed report path, no-change
  success, commit failure and recovery, interruption around each durable phase,
  surviving children, thread mismatch, handback, and old runs without state.

Tests must not claim to detect the author of arbitrary concurrent filesystem
writes. Verify the exclusive-worktree contract and its checks, and retain this
limitation in the user documentation.

Add repository checks for catalog membership, matching identifiers and source
paths, manifest validity, bundled references, and removal of obsolete active
names. Continuous integration runs these checks, validates the Claude catalog
and each Claude plugin, and runs the maintained shell suites with explicit
timeouts and required dependencies.

Smoke-test marketplace registration, listing, and installation using isolated
temporary client configuration and plugin caches. Confirm that Claude lists
four repository plugins and Codex lists exactly three, with `dr-status` absent
and installation by name rejected. Count this repository's entries separately
from automatically installed dependencies. Test Git-URL and local-root routes,
old catalog refresh, a pinned old revision, renamed-source conflict/recovery,
and the documented direct-Claude-manifest exception. Preserve a fixture with
previously installed retired plugin IDs to verify that migration explicitly
removes those cached installations.

Seed old UI versions and a `0.7.0` installed statusline copy, then verify that
upgrading changes the active manifests and actual skill/script bytes. Check
matching versions across native manifests and statusline `scripts/VERSION`.
Use local fixture repositories to simulate source renaming without changing the
real GitHub repository. No Telegram messages or paid model calls are part of
these tests. Report native model execution as untested if only dispatch contracts
and package loading were exercised; do not equate installation with model parity.

Update the root README, plugin READMEs, and `CLAUDE.md` with the support matrix,
new repository URL, prerequisite and installation instructions, and rename
migration steps. Publishing, renaming the GitHub repository, and modifying the
user's installed plugins are outside this repository-editing change.
