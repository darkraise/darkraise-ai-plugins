# Darkraise plugins implementation plan

> Execute inline with `superpowers:executing-plans`, using the checkpoints below.
> The user approved implementation on 2026-09-08. Commits, publishing, and changes
> to installed user plugins remain outside this execution.

**Goal:** Remove Telegram, distribute `dr-status` only through Claude Code, and
make `dr-superpowers` and both existing UI plugins installable and usable through
the appropriate Claude Code and Codex paths.

**Architecture:** Separate client catalogs select availability. Shared skills
branch on native host capabilities. Statusline installation records preserve
existing destinations. The external executor uses exclusive linked worktrees
and a durable task record to control writes, retries, commits, and handback.

**Tech stack:** Existing Bash/jq scripts and Markdown skills; JSON manifests;
Node.js built-in test runner for repository checks; GitHub Actions.

**Spec:** [Revised design](../specs/2026-09-08-dual-client-plugin-revision-design.md).

## Global constraints

- Work only in this repository and disposable test fixtures. Preserve untracked
  `plugins/darkmem-resume/`, historical specs/plans, and unrelated changes.
- Keep marketplace ID `darkraise`. Future repository URL is
  `https://github.com/darkraise/darkraise-plugins`; do not rename GitHub itself.
- Preserve the statusline's `dcc-statusline` user paths and existing `DCC_*`
  variables. Change public IDs and active references selectively.
- No live Telegram calls, paid model probes, real account configuration edits,
  or automatic plugin reinstalls in the user's environment.
- Run regression tests red before changing the corresponding behavior, then
  green. Fixture assertions must exercise actual scripts or documented commands.
  Contract checks cannot establish successful native model execution.
- Shell commands below run from the repository root using Bash, jq, Git, Node
  22, and GNU `timeout`. On Windows use Git Bash; do not translate recursive
  filesystem operations between shells. Check resolved paths before moves or
  removals, and remove only tracked Telegram files.
- Bound each command and its child cleanup. The outer test runner must capture
  processes and kill its owned tree on timeout, including on Windows. Confirm
  cleanup before each checkpoint. Never terminate user-owned processes.
- Keep commits optional until authorized. Suggested atomic commit subjects are
  provided for later use; stage explicit files only.

## Task 1: Establish separate catalogs and rename public identities

**Files**

- Move `plugins/dcc-statusline/` to `plugins/dr-status/`, and its
  `commands/dcc-statusline.md` to `commands/dr-status.md`.
- Move `plugins/dcc-superpower-companions/` to `plugins/dr-superpowers/`.
- Remove tracked files under `plugins/dcc-telegram-notify/`.
- Modify `.claude-plugin/marketplace.json`, the four remaining
  `.claude-plugin/plugin.json` files, `plugins/dr-status/scripts/VERSION`,
  `CLAUDE.md`, `README.md`, and active references inside the remaining plugins.
- Create `.agents/plugins/marketplace.json` and `.codex-plugin/plugin.json`
  inside `dr-superpowers`, `dcc-darkraise-ui`, and `dcc-darkraise-win32ui`.
- Create `scripts/validate-repository.mjs` and
  `tests/repository-layout.test.mjs`.

**Interface:** `validateRepository(root)` exported by the validator returns an
array of error strings. Direct execution prints errors and exits 1 when nonempty,
otherwise exits 0. It validates catalog-selected plugins, not every directory in
`plugins/`, so unrelated work is not accidentally enrolled.

- [ ] Add failing membership tests using the expected public contract:

  ```js
  const claudeNames = [
    'dcc-darkraise-ui', 'dcc-darkraise-win32ui', 'dr-status', 'dr-superpowers'
  ];
  const codexNames = claudeNames.filter(name => name !== 'dr-status');
  assert.deepEqual(claude.plugins.map(p => p.name).sort(), claudeNames);
  assert.deepEqual(codex.plugins.map(p => p.name).sort(), codexNames);
  assert.deepEqual(superpowersCodex.hooks, {});
  ```

  Load these variables from the corresponding JSON files in the fixture root.
  Also test missing source directories, duplicate names, mismatched versions,
  broken bundled references, and a missing explicit empty Codex hooks object.
  Run `timeout 60s node --test tests/repository-layout.test.mjs`; the current
  catalog and absent Codex catalog must fail.
- [ ] Record `git status --short` and tracked rename/removal lists. Resolve both
  source and destination paths within this repository before moving directories.
  Stop on destination collisions; preserve any untracked Telegram content.
- [ ] Apply the exact names and version map:

  ```json
  {"dr-status":"0.8.0","dr-superpowers":"0.5.0",
   "dcc-darkraise-ui":"0.2.0","dcc-darkraise-win32ui":"0.2.0"}
  ```

  Set Claude marketplace version to `0.3.0`. Use the currently supported native
  Codex catalog shape and local source paths resolved from the repository root.
  Consult the bundled plugin-creator scaffold for schema details; keep the
  design's `"hooks": {}` even if a stale helper validator rejects that field.
  Validate it against the actual Codex loader in Task 8.
- [ ] Replace old public command/agent IDs and repository URLs in active files.
  Keep old namespace text only in migration documentation, translation logic,
  and regression fixtures. Keep legacy statusline storage names. Update root
  conventions to describe the two catalogs and the four permitted public IDs.
- [ ] Verify the installed Claude CLI's dependency schema and the intended
  upstream Superpowers marketplace identity before writing `dr-superpowers`'
  dependency. Use the supported qualified dependency form; do not guess its
  source or silently bundle a copy. Task 8 must prove dependency resolution.
- [ ] Implement the validator over those contracts, rerun the failing test, and
  run `timeout 60s node scripts/validate-repository.mjs`.

**Checkpoint:** Four Claude entries, three Codex entries, no Codex statusline
manifest, and no tracked Telegram implementation. Installation is not yet proven.
Suggested commit: `refactor(plugins): split catalogs and shorten names`.

## Task 2: Repair statusline installation and lifecycle ownership

**Files:** Modify `plugins/dr-status/commands/dr-status.md`, `scripts/install.sh`,
`scripts/sync.sh`, `scripts/lib/path.sh`, `tests/install.test.sh`,
`tests/preview.test.sh`, and `README.md`. Create
`scripts/lib/installations.sh` and `tests/sync.test.sh` under that plugin.

**Interface:** `installations.sh` provides these shared functions, returning
nonzero on failure and writing diagnostics to stderr:

```text
dcc_installation_get ACCOUNT -> JSON {destination, command}, or null
dcc_installation_put ACCOUNT DESTINATION COMMAND -> atomically persist record
dcc_installation_remove ACCOUNT -> atomically remove record
dcc_installation_owns ACCOUNT -> exit 0 only for exact owned settings command
dcc_installation_lock -> acquire bounded per-user lock
dcc_installation_unlock -> release only this invocation's lock
```

The persisted format is `{"version":1,"accounts":{}}`, keyed by normalized
absolute account directory. All callers use the same fake-home-aware path
resolver. Mutating callers hold the lock across both registry and settings work.

- [ ] Extend lifecycle tests before fixing behavior. Representative regression,
  added after the existing fake-home/account setup:

  ```bash
  export DCC_STATUSLINE_HOME="$fake/custom scripts"
  dcc_main install
  unset DCC_STATUSLINE_HOME
  check "record preserves destination" \
    "$(jq -r --arg account "$fake/.claude" \
      '.accounts[$account].destination' \
      "$fake/.claude/dcc-statusline-installations.json")" \
    "$fake/custom scripts"
  ```

  Normalize the fixture account with the same public path convention when
  asserting on Windows. Execute the registered command with a renderer fixture
  to verify quoting, rather than merely checking its string shape.
  Run `timeout 120s bash plugins/dr-status/tests/install.test.sh` and retain
  failures for malformed settings exit status and another provider's uninstall.
- [ ] Implement the registry functions with jq type/version validation,
  same-directory temporary files, and atomic replacement. Serialize mutations
  with a bounded `mkdir` lock; do not force-clear a lock on age alone. Retain
  malformed input untouched and clean only temporary files owned by this run.
- [ ] Resolve install destination per account: explicit override, recorded
  destination, default. Enumerate the union of discovered and recorded accounts
  for `--all`. Copy scripts to each distinct destination; never delete previous
  destinations. Generate a Bash-quoted absolute launch path and serialize with
  `jq --arg`, preserving spaces, apostrophes, and shell metacharacters.
- [ ] Persist the record before settings registration. If settings registration
  fails, retain the intended record, report mismatch, and fail. Continue other
  requested accounts and return an aggregate nonzero status. Preserve unrelated
  settings and reject malformed registry/settings JSON without replacement.
- [ ] Make sync, doctor, status, and uninstall resolve the recorded destination
  without trusting later `DCC_STATUSLINE_HOME` values. Share exact command
  ownership detection, including only the known default legacy command without
  a registry. Sync only matching installations. Remove a registry entry only
  after removing its owned settings entry; retain other providers unchanged.
- [ ] Correct command instructions to consume one subcommand and forward only
  the remaining arguments: `install --all` reaches the installer once;
  `preview --width 80` reaches `preview.sh --width 80`. Add fixture checks for
  both invocation forms and their actual script exit codes.
- [ ] Cover two accounts with different destinations, override unset/changed,
  legacy default adoption, explicit custom legacy reinstall, record/settings
  mismatch repair, lock contention, partial multi-account failure, malformed
  JSON, and unrelated providers. Seed scripts at `0.7.0` and confirm sync updates
  actual bytes and `VERSION` to `0.8.0` while preserving presentation config.
- [ ] Run `timeout 300s bash plugins/dr-status/tests/run-all.sh`.

**Checkpoint:** Custom installs survive the whole lifecycle without the original
override; removal cannot erase another provider. Suggested commit:
`fix(status): persist installation ownership`.

## Task 3: Detect usable external executors without credential assumptions

**Files:** Modify `plugins/dr-superpowers/scripts/detect-executors.sh`,
`tests/detect.test.sh`, and `README.md`.

**Interface:** Preserve existing executor-array fields and boolean/null auth
compatibility. Add `auth_status` with `authenticated`, `logged_out`,
`probe_failed`, or `not_applicable`. `usable` requires confirmed Codex auth,
an enabled supported lane, and successful prerequisites.

- [ ] Add synthetic CLI tests where login succeeds without `auth.json`, a stale
  file exists but login reports logged out, and the status probe fails/times out.
  Assert that no token or raw credential-bearing probe output reaches stdout or
  stderr. Run `timeout 120s bash plugins/dr-superpowers/tests/detect.test.sh` red.
- [ ] Replace file-existence authentication with a bounded CLI status probe:

  ```bash
  timeout 20s codex login status >"$probe_output" 2>&1
  probe_rc=$?
  ```

  Interpret output and exit status using observed fixtures from the supported
  CLI. Only its explicit logged-out result means `logged_out`; unfamiliar
  responses and timeouts mean `probe_failed`. Do not print captured output.
  Check jq and GNU timeout before probing; missing prerequisites fail with a
  named installation requirement. Keep unsupported lanes disabled.
- [ ] Rerun the detector suite and document the distinction between the native
  host capability check and this Claude-only external CLI detector.

**Checkpoint:** Auth detection reflects the CLI backend, with no paid requests.
Suggested commit: `fix(executors): probe Codex authentication`.

## Task 4: Add durable external-task ownership and snapshots

**Files:** Create `plugins/dr-superpowers/scripts/lib/task-state.sh`,
`scripts/codex-task-state-schema.json`, `tests/task-state.test.sh`, and
`tests/lib/executor-fixtures.sh`.

**Interface:** The Bash library exports:

```text
dr_snapshot ROOT OUTPUT -> JSON root identity, HEAD, index, tracked/untracked files
dr_task_open ROOT TASK_ID WRITE_SET -> validate/init identity and export DR_TASK_DIR
dr_task_lock -> acquire the current task's per-run lock
dr_task_write RECORD_FILE -> validate schema and atomically replace task record
dr_task_assert_snapshot SNAPSHOT_FILE -> compare actual state, return nonzero on drift
dr_task_unlock -> release this process's lock, never persistent task ownership
```

`TASK_ID` is a nonempty stable string encoded/hashed for the directory name, not
used as a raw path. `WRITE_SET` is a JSON array of literal repository-relative
paths. Store authoritative files below the linked worktree's own Git directory
at `dr-superpowers/tasks/<encoded-id>/`; keep the worktree owner record and run
lock beside `tasks/`. Resolve the per-worktree Git directory, not the common one.
Snapshots carry their root identity, so comparison also works independently of
an open external task. A snapshot mismatch returns 1; invalid input returns 2.

- [ ] Build fixtures using a disposable primary repository plus a linked worktree.
  Include staged, unstaged, and untracked content separately. The fixture library
  tracks child PIDs and removes only its verified temporary root on exit.
  Add this initial regression around the new API:

  ```bash
  dr_snapshot "$worktree" "$fixture_root/before.json"
  printf 'unrelated\n' > "$worktree/unrelated.txt"
  dr_task_assert_snapshot "$fixture_root/before.json"
  rc=$?
  check "untracked drift rejects recovery" "$rc" "1"
  ```

  The fixture initializes the library's current task/root first through
  `dr_task_open`. Run `timeout 120s bash plugins/dr-superpowers/tests/task-state.test.sh`
  and confirm the absent API fails.
- [ ] Implement canonical repository/worktree identity, primary-checkout
  rejection, initial cleanliness checks, stable task lookup, owner reservation,
  and atomic per-run locking. Bind process identity to more than PID alone;
  ambiguous liveness blocks recovery. A lock expiry never transfers ownership.
- [ ] Define schema version 1 with identity, initial base/expected HEAD, write
  set, original/current model and effort, current/prior threads, attempts and
  review counters, owned process identities, phase/prior phase, artifact paths,
  pending snapshot, intended commit tree/parent/subject, and resulting commit.
  Permit only `ready`, `running`, `pending`, `committing`, `complete`,
  `handed-back`, and `blocked` phases; validate before atomic persistence.
- [ ] Snapshot the full index and tracked/untracked filesystem state with hashes,
  Git modes, symlink targets, deletion markers, and rename endpoints. Use
  NUL-delimited Git output and literal path handling; reject absolute paths,
  traversal, and symlink escapes from the write set. Include hidden/untracked
  files; state in the Git directory needs no source-tree exclusions.
- [ ] Exercise two cooperating invocations contending for one worktree, changed
  HEAD/index, invalid/truncated state JSON, same task with another report path,
  another task attempting reservation, PID reuse/uncertain child identity, path
  spaces, deletion, rename endpoints, symlink and mode changes. On platforms
  without executable-mode support, run that assertion in Linux CI explicitly.
- [ ] Rerun the state suite green. Keep snapshots reusable by native reviewer
  guards without requiring those guards to reserve an external task.

**Checkpoint:** Ownership is durable and drift blocks recovery; snapshots do
not claim to identify who wrote a file. Suggested commit:
`feat(executors): persist task ownership and state`.

## Task 5: Integrate scoped execution, commits, and recovery

**Files:** Modify `plugins/dr-superpowers/scripts/run-codex-task.sh`,
`scripts/codex-task-contract.md`, `tests/run-codex-task.test.sh`,
`skills/dispatching-tiered-implementers/SKILL.md`, and `README.md`.
Create `tests/executor-recovery.test.sh`; extend Task 4's state library as needed.

**Interface:** Preserve existing execution flags and exits, adding required
`--task-id ID` and initial `--write-set FILE`. Subsequent invocations must match
the recorded write set. Add mutually exclusive control operations
`--recover-commit`, `--handback`, and `--release`, all bound to `--cwd` and
`--task-id`; these do not launch a model. Add `--amend-write-set FILE` and
`--accept-baseline SNAPSHOT_FILE`, each requiring `--approval APPROVAL_FILE`.
The approval record contains the task ID, approved operation, exact proposed
file hash, and the controller's reference to the user's approval. It records
workflow authorization; it does not authenticate the user. Verify the current
snapshot, stopped children, and ownership under lock before either operation.
Preserve the original base and append amendments/reconciliations to history.
Never implicitly accept the current directory as a repaired baseline.

- [ ] Convert execution fixtures to exclusive linked worktrees and stable IDs.
  Add a stubbed DONE run with unrelated initial content and assert exit 2,
  no child launch, unchanged HEAD, and preserved content. Preserve the existing
  argv-order/resume/sandbox tests. `--dry-run` validates arguments and displays
  the invocation without acquiring ownership or writing artifacts.
  Run `timeout 180s bash plugins/dr-superpowers/tests/run-codex-task.test.sh` red.
- [ ] Separate argument/preflight, process execution, report parsing, snapshot
  validation, and commit/recovery stages. Use Task 4's APIs. Persist `ready`
  before launching; persist `running`, process identities, and thread discovery
  promptly. Keep authoritative prompt, JSONL, result, stderr, and reports in the
  task directory. Human reports may be outside the checkout or inside the
  actually Git-ignored Superpowers workspace; reject tracked/source destinations.
- [ ] Keep the existing CLI-specific model/effort/timeout table, independent of
  native `codex-v1`. Preserve required resume flag ordering and exact stored
  thread/model/effort matching. Permit review fixes from `complete` and validated
  `pending`; retries may start a new thread while retaining prior thread history,
  attempt counts, review counts, expected HEAD, and pending state.
- [ ] Require the controller's exclusive-worktree precondition before execution.
  Stop only controller-owned competing writers; require manual editing to cease
  in this worktree. This does not prohibit work in the primary checkout.
  Terminate and confirm the owned child tree before inspecting or transferring
  writes. Uncertain survivors or interrupted PID registration remain blocked.
- [ ] After execution, validate identity, expected HEAD, unchanged index, and
  the actual diff against the approved write set. Stage exactly the validated
  paths using literal pathspecs, including deletions and both rename endpoints:

  ```bash
  git --literal-pathspecs -C "$worktree" add -A -- "${validated_paths[@]}"
  ```

  Skip staging for an empty array. Verify the complete resulting index tree
  against the validated snapshot, including modes and deletions. Persist the
  intended tree/parent/subject before commit; never use repository-wide staging.
- [ ] Persist successful commit HEAD and clear pending state before `complete`.
  Record no-change DONE as complete with its thread. Incomplete execution with
  confirmed stopped children becomes `pending` only for a validated scoped diff.
  Unexpected paths, HEAD/index drift, persistence failures, or uncertain children
  block continuation and preserve files.
- [ ] Implement commit recovery without rerunning Codex. Revalidate the intended
  tree/parent and actual snapshot before retrying a failed commit. Adopt a commit
  after a crash only on exact tree, parent, and subject match. Staging/commit
  failures retain the actual snapshot and prior phase in blocked state. Where
  atomic record persistence itself fails, retain the last durable phase and
  fail closed on the next invocation; never pretend the new phase was saved.
- [ ] Implement explicit handback and release. Handback validates pending state
  and child termination, records Claude ownership, and permanently refuses the
  old external task's resume. Release requires clean complete state and finished
  review. Do not remove blocked worktrees. Legacy reports without state require
  explicit reconciliation; replace the skill's manual broad-staging fallback.
- [ ] Add deterministic failure injection through test shims for Git, Codex,
  and filesystem operations, rather than production-only test branches. Cover
  timeout and interruption around every phase, partial initial retry, review-fix
  resume, changed report path, no-change DONE, stage/commit failure, crash after
  commit, write-set amendment, manual baseline reconciliation, thread mismatch,
  surviving children, release, handback, and old no-state reports. Assert exits
  0 for DONE, 1 for executed non-DONE, 2 for preflight/persist/commit failures.
- [ ] Run both wrapper suites with 180-second and 300-second bounds respectively,
  followed by the state suite. Verify no tracked fixture child remains running.

**Checkpoint:** A stub executor cannot commit unrelated files; interrupted tasks
either recover from exact recorded state or stop without discarding work.
Suggested commit: `fix(executors): scope commits and recover durable tasks`.

## Task 6: Implement native Codex routing and plan migration

**Files:** Modify all three skills in `plugins/dr-superpowers/skills/`,
`reference/ladder.md`, agent namespace references, and `README.md`. Create
`reference/codex-routing.json`, `reference/native-codex.md`,
`scripts/select-native-tier.sh`, `tests/native-routing.test.sh`, and
`tests/native-contracts.test.mjs`. Extend `tests/fleet.test.sh`,
`tests/hook.test.sh`, `tests/ladder.test.sh`, and `tests/lanes.test.sh` only where
renaming or separating native and CLI policy changes their actual contracts.

**Interface:** `select-native-tier.sh --request FILE` reads validated JSON:
`policy`, `operation` (`assign` or `escalate`), `role`, `score`,
`assignment_source`, optional `pinned_pair`,
`available_pairs`, `attempted_ranks`, `attempted_reserves`, `split_consumed`,
and `review_rounds`. The caller supplies advertised pairs already intersected
with applicable user policy. Output JSON has `action` (`dispatch`, `approval`,
`split`, or `blocked`), optional rank/model/effort, and a reason. Invalid/missing
metadata exits 2; a valid routing decision exits 0. The script never dispatches,
edits a plan, or probes an API.

- [ ] Write table-driven executable tests for scores 0 through 6 against:

  ```text
  0 gpt-5.6-luna low
  1 gpt-5.6-luna medium
  2 gpt-5.6-sol low
  3 gpt-5.6-sol medium
  4 gpt-5.6-sol high
  5 gpt-6-astra high
  6 gpt-6-astra xhigh
  ```

  Assert score 2 promotes to rank 3 when only that higher pair is available,
  while the equivalent unavailable human pin returns `approval`. Missing
  capability metadata must not be interpreted as an empty approved fallback.
  Run `timeout 120s bash plugins/dr-superpowers/tests/native-routing.test.sh` red.
- [ ] Put this policy and reserve pairs in JSON consumed by the selector.
  Implement first-available rank at/above score, scout floor 3, judge floor 5,
  strict human pins, monotonic escalation, one split, then Astra max/ultra reserve
  in order without revisiting attempts. No reserve on initial assignment and
  no inherited default. Enforce the existing five-round cap before another
  dispatch; transport retries retain rank/split/review history.
  A transport retry reuses its recorded pair rather than asking for escalation.
  Validate jq availability before invoking the selector. Include actual
  request/response fixtures, for example:

  ```json
  {"policy":"codex-v1","operation":"assign","role":"implementer",
   "score":2,"assignment_source":"rubric",
   "available_pairs":[{"model":"gpt-5.6-sol","effort":"medium"}],
   "attempted_ranks":[],"attempted_reserves":[],
   "split_consumed":false,"review_rounds":0}
  ```

  Assert `action == "dispatch"`, `rank == 3`, the supplied model/effort, and
  a reason identifying promotion from score 2.
- [ ] Add explicit host branches to assigning, dispatching, and selecting skills.
  Native tool capabilities identify the host, never presence of the Codex CLI.
  Require Superpowers skills, advertised pairs, and callable host dispatch tools
  before routing. Claude uses its unchanged fleet and rubric; native Codex uses
  the selector and the active tool's supported isolated-context/model/effort
  arguments. Do not trigger the external CLI lane while hosted by Codex.
- [ ] Add host and policy version to plan headers and `Assignment source` to
  tasks. Keep original assignments fixed and record actual attempts/promotions
  in the ledger. Translate only known Claude fleet suffixes from the exact old
  namespace at read time. Unknown suffixes fail; existing plans remain on disk
  unchanged. Cross-host conversion previews old/new assignments, preserves
  Evaluation and prior assignment, and waits for approval without rescoring.
  Missing source means human-pinned; reserve overrides never auto-convert.
- [ ] Define native child prompt requirements in `reference/native-codex.md`:
  role, task/criteria inputs, verification instructions, explicit pair, and
  restricted tools where supported. Reviewers receive a separate context.
  Resume recorded implementers for fixes only when the active client supports
  it. Preserve criteria scoring, best-of-three, and three risk-3 evaluations.
- [ ] For instruction-only reviewer restrictions, prohibit writes/delegation,
  stop concurrent writers, and use Task 4's snapshot API before/after. Any HEAD,
  index, tracked, or untracked mutation invalidates review and blocks continuation
  while preserving changes. If enforced isolation is required, stop instead of
  using this fallback. Describe independence without claiming cross-provider
  review in the native lane.
- [ ] Add contract fixtures for old namespace/unknown suffixes, preserved
  evaluation/reserve, cross-host approval, legacy pins, host ambiguity, missing
  prerequisites, role prompt contents, no recursive offload, and hook isolation.
  Add executable reviewer snapshot tests with staged, tracked, untracked, and
  HEAD mutations. Test every missing-model/effort, promotion, escalation, split,
  reserve exhaustion, and cap case through the actual selector.
- [ ] Run the native shell suite and
  `timeout 60s node --test plugins/dr-superpowers/tests/native-contracts.test.mjs`,
  then the existing fleet, hook, ladder, criteria, and lane suites, each bounded
  by 120 seconds. Report these as policy/contract tests, not live model parity.

**Checkpoint:** Both hosts have explicit routing and migration rules; native
dispatch never inherits an unrecorded model or Claude-only agent restrictions.
Suggested commit: `feat(superpowers): add native Codex routing`.

## Task 7: Make UI context discovery portable

**Files:** Modify both UI `skills/*/SKILL.md` files and READMEs. Create
`tests/ui-discovery.test.mjs` and consumer fixtures beneath
`tests/fixtures/ui-discovery/`. Keep bundled rule files and existing evals intact.

**Interface:** Skills explicitly instruct the active host to discover the
consumer project's installed package/source before applying bundled rules.
No Claude inline shell expansion is required. These remain instruction skills,
not a new runtime package-discovery service.

- [ ] Add a regression fixture with centrally managed `PackageVersion` and run
  the existing documented discovery query against it, demonstrating the miss.
  Add tests rejecting the current Claude-only inline preprocessing. Run
  `timeout 60s node --test tests/ui-discovery.test.mjs` red.
- [ ] Replace inline preprocessing with explicit host-shell/read-tool steps.
  For web UI, inspect the consumer's manifest and actual resolved package/types,
  including hoisted/workspace layouts. Missing packages produce an installation
  or project-location request; pinned documentation never substitutes for the
  installed API. Keep paths relative to the selected consumer project.
- [ ] For Win32, make this portable query the dependency discovery starting point:

  ```bash
  rg -n 'PackageReference|ProjectReference|PackageVersion|Darkraise' \
    --glob '*.csproj' --glob 'Directory.Packages.props' .
  ```

  Then read the matching XML entries in full, including multiline elements and
  relevant imported files. For the selected target framework prefer resolved
  `obj/project.assets.json` targets/libraries/packageFolders to locate exact
  package versions and XML documentation. Follow ProjectReference source when
  used. Without restore assets, distinguish declared version from resolved
  installation; never pick the highest globally cached version. Multiple target
  frameworks require the consumer's selected target before choosing its API.
- [ ] Execute the exact documented query against fixtures containing all three
  reference forms, multiline XML, missing packages, and central versions. Add
  assets fixtures with multiple frameworks and multiple cached versions; ensure
  the documented JSON lookups select the framework's actual package path.
  Label prose sequencing checks as contract checks. Existing UI eval prompts
  remain available for later model evaluation without paid calls in this change.
- [ ] Rerun the UI suite and repository reference validation green.

**Checkpoint:** Both clients can follow discovery instructions, and centrally
managed Win32 dependencies are found. Suggested commit:
`fix(ui): make package discovery client portable`.

## Task 8: Validate installs, upgrades, and migration documentation

**Files:** Modify `.github/workflows/validate.yml`, `README.md`, `CLAUDE.md`,
and all four plugin READMEs. Create `scripts/test-all.mjs`,
`tests/marketplace-smoke.ps1`, and
`docs/testing/dual-client-marketplace-validation.md`.

**Interface:** `test-all.mjs` runs maintained suites once with per-child timeouts
and owned-process-tree cleanup, exits nonzero on failure, and reports skipped
platform requirements explicitly. `marketplace-smoke.ps1` accepts explicit
Claude/Codex executable paths and a temporary fixture root; it refuses real
profile/cache roots and records versioned evidence without credentials.

- [ ] Implement `test-all.mjs` using bounded `spawn` calls, an explicit maintained
  plugin list, Node test files, and Bash suites. Run statusline's aggregate once;
  enumerate maintained Superpowers `*.test.sh` plus its Node contract suite.
  Do not include Telegram or unrelated untracked plugins. On failure/timeout,
  or SIGINT/SIGTERM, terminate only the started process tree and confirm exit
  before returning. The supervising invocation must allow a bounded cleanup
  grace period before forced termination.
- [ ] Update CI with explicit job/step timeouts and Bash, jq, GNU coreutils, Git,
  ripgrep, and Node prerequisites. Validate the Claude marketplace and each
  remaining Claude plugin, then repository/native manifest contracts and all
  maintained suites. Pin validation CLI versions to those actually verified;
  do not silently rely on changing `@latest` behavior. Run filesystem/mode tests
  on Linux and process cleanup/lifecycle tests on Windows where supported.
- [ ] Before smoke tests, inspect current CLI help/source for isolated
  configuration/cache paths, registration/removal semantics, dependency support,
  and install/list/upgrade flags. Run help commands with 15-second bounds and
  set isolation variables before starting either client. If any cache location
  cannot be isolated, stop that smoke case and report it as unverified.
- [ ] Build disposable Git fixtures from tracked candidate files plus the new
  implementation files, with an old release commit and revised release commit.
  Use local Git-source fixtures to simulate URL/source renaming; do not require
  the future GitHub URL to exist. Keep the new unrelated user plugin excluded.
  Test the following with bounded real CLI commands, inspecting active installed
  manifests, hook loading, and skill/script bytes, not just catalog output:

  1. Fresh local-root and Git-source registration: Claude exposes four repository
     entries; Codex exposes exactly three. Count dependencies separately.
     Codex install-by-name for `dr-status` fails. Codex `dr-superpowers` loads no
     Claude hooks; Claude still discovers its hook and required dependency.
  2. Existing root registration refresh and install: new names appear and old
     catalog selection is replaced. Pinned old revision stays old until the
     explicit revision update, after which the revised catalog is selected.
  3. Same marketplace ID with renamed source: capture installed IDs/scopes,
     reproduce conflict if present, and verify supported remove/add/reinstall
     behavior without assuming installations survive marketplace removal.
  4. Seed retired installed IDs and prove refresh alone is not uninstall. Verify
     documented removal steps and disabling old Claude IDs before replacements.
     User settings/tokens remain untouched in the simulated migration.
  5. Seed UI `0.1.0` installations and a statusline `0.7.0` copy. Upgrade and
     assert active versions plus changed skill/script bytes, both manifest
     versions, and statusline `VERSION`. Preserve theme/account settings.
  6. Direct Claude-catalog registration in Codex: record its fallback behavior
     and document this as outside the supported root-registration guarantee.
- [ ] Write client-specific install and migration commands only after the smoke
  tests confirm their syntax and side effects. Cover supported root routes,
  refresh, pinned revision changes, source conflicts, obsolete cached installs,
  Superpowers dependency/prerequisites, external worktree exclusivity, statusline
  legacy storage, UI discovery, and the native review limitation. The final
  repository URL is future-facing until the user renames/publishes it.
- [ ] Record CLI versions, platform, commands, pass/fail/skips, cache evidence,
  and process cleanup in the validation document. Distinguish local Git-source
  coverage from an untested published HTTPS URL, and native dispatch contracts
  from untested paid model execution. If a packaging assumption fails, repair
  the owning task and rerun affected tests before updating the migration guide.
- [ ] Run final bounded checks:

  ```bash
  timeout 60s node scripts/validate-repository.mjs
  timeout 900s node scripts/test-all.mjs
  timeout 30s git diff --check
  ```

  Review the final tracked diff and untracked files against the initial status.
  Confirm no started process remains and `plugins/darkmem-resume/` is unchanged.

**Checkpoint:** Report actual install/upgrade evidence and every remaining gap.
Suggested commits: `test(plugins): verify both client marketplaces` and
`docs(plugins): document installation and migration`.

## Plan handoff

Execute Tasks 1–8 sequentially, inline, with the stated checkpoints. Catalog
work can be reviewed after Task 1; do not describe dual-client availability as
verified until Task 8. Implementation ends with repository changes and evidence
ready for review. Publishing, repository renaming, commits, and migration of the
user's installed plugins remain separate actions.

## Execution record

Implementation covers all eight task areas. Runtime details were factored into
`scripts/lib/task-state.sh` and `scripts/lib/task-execution.sh`; `manage.sh`
provides an executable statusline argument dispatcher. Test fixtures are created
at runtime rather than committed as duplicate consumer repositories. Native
role and conversion instructions are bundled in `reference/native-codex.md`;
their live model behavior was not evaluated with paid agent calls.

The scoped executor regression suite replaces the old execution fixtures that
reset the same worktree between unrelated runs without reconciling task state.
Existing CLI argument, quoting, and resume-order tests remain. Additional tests
exercise durable ownership, partial retries, commit recovery, handback, release,
process-tree termination, unexpected hook staging, and reviewer snapshot drift.

The real-client smoke harness verifies supported root routes, installed bytes,
official Superpowers dependency resolution, old catalog refresh, retired caches,
pinned revisions, and source conflicts. Codex 0.153.4 rejects direct catalog-file
registration through its CLI; the repository-root route selects the native
catalog. See [validation evidence](../../testing/dual-client-marketplace-validation.md)
for measured coverage and limits. The original checklists above remain the
approved design baseline rather than a claim that every proposed fixture was
implemented literally.
