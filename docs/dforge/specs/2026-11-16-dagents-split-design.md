# dagents split

**Execution strategy:** sequential — inline execution
**Depth:** full — risk,new-subsystem

## Decisions

- **Process:** full dforge flow. Owner: "Full dforge, but do not treat it as add
  new dagents built from 4.17.1, etc.... But look like: checkout version 4.17.1,
  copy to new dagents plugin folder, update plugin definition file, then apply
  bug fixes from latest code base (dforge 5.0.0)".
- **Version 5** is the dforge tree on `main` today: everything after tag
  `dforge-v4.17.1`, including the breaking `5b361920 refactor(dforge)!: retire
  the external executor lane`. **The last 4.x** is tag `dforge-v4.17.1`
  (`5bb5545f`, equal to `origin/main`).
- **Guard:** "Stand down and tell". Claude Code has no install or enable hook
  and no conflict field (code.claude.com/docs/en/plugins/manifest-reference.md,
  …/marketplace-reference.md, …/hooks.md, checked 2026-11-16), so the earliest
  point is each plugin's SessionStart hook and mod. Settings are never changed.
- **Fix scope:** "Every 4.x defect": port a fix whenever its defect exists in
  4.17.1 code, bringing the new code the fix needs (for example
  `next-step --print`); skip fixes to version-5-only features; version 5's own
  features stay out.
- **State paths:** "Rename to dagents, also other related settings, make sure 3
  plugins are fully isolated".
- **Existing 4.x state:** "Move on migrate".
- **Codex** (default, not asked): dagents joins the Codex catalog as dforge
  4.17.1 did, with explicit empty Codex hooks; dflow stays Claude-only.
- **Versions** (from `scripts/release.mjs`, not asked): the release workflow
  bumps dforge to 5.0.0 on the next push because of the `!` commit, so no
  commit hand-edits dforge's version. A plugin with no tag is released at its
  manifest version at HEAD, so dagents ships as 1.0.0 and dflow, which has no
  tag either, first releases as 1.0.0 with the guard included.
- **Order** (critic finding, accepted): the identifier rename runs right after
  the copy and the manifest edit, and every fix is ported through the same
  scripted rename, so every commit on the branch is a consistent dagents that
  CI validates.

## Goal

Three plugins in one marketplace, at most one of which is active in a session:
**dforge 5** (the current reviewer-panel workflow), **dagents 1.0** (the dforge
4.17.1 agent workflow: implementer agents, subagent mode, external executor
lanes, parallel waves, group review, revising-plans) carrying every version-5
fix for a defect it shares, and **dflow**. None of them reads or writes the
others' files, settings, environment variables or darkmem data.

## Design

### 1. Creating dagents

1. `git archive dforge-v4.17.1 plugins/dforge` extracted to `plugins/dagents`:
   the copy is byte-identical to the tag, committed alone.
2. The manifests (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`)
   take `"name": "dagents"`, `"version": "1.0.0"`, a description naming the
   agent workflow, and the dagents homepage. Committed alone.
3. `scripts/dagents-rename.mjs` (repository script, kept for the ports) applies
   the §3 map to a tree or to a patch. It runs once over `plugins/dagents`, and
   the result is committed alone with the repository wiring (§7), so CI runs
   dagents' suites from this commit on.
4. The version-5 fixes are ported (§2), each patch passed through the same
   script.
5. Migration (§4) and the guard (§5) follow.

### 2. Backporting the fixes

- **The backport register** `docs/dforge/registers/2026-11-16-dagents-backport.md`
  holds one row per non-merge commit in `dforge-v4.17.1..<base>` that touches
  `plugins/dforge/`, where `<base>` is the `main` commit the branch starts from
  (283 commits at `d85f6776`). The commit's hash and subject are the row's
  Item, so no commit can be lost. Before the merge, the query runs again
  against `main`'s head and new commits become rows.
- Each row ends `done`, with the dagents commit and the A4 results in its Note,
  or `n/a`, with one of these classes in its Note:
  - `5-only` — the defect is in code 4.17.1 does not have (the reviewer panel,
    API rulings, the agy review runner, task-close, the per-session state file);
  - `feature` — not a fix: a feat, perf or refactor commit, or a retirement;
  - `test-only` or `docs-only` — tests or text for a version-5 feature;
  - `superseded` — a later commit on the list reverts or replaces it.
- A commit of any type is `port` when its defect exists in 4.17.1: docs and test
  commits included (`86c359cd` fixed project-status routing as a `docs`
  commit). A port brings its regression test and whatever new code the fix
  needs. When the fix lives in code version 5 restructured (for example
  next-step's router moved to `route.sh`), the port reimplements the same
  behaviour in the 4.17.1 structure, and the row's Note says so.
- Port commits are `fix(dagents): <subject>`, with body `Backport of <sha>.`.
  One commit per fix, or per group of fixes from one register row of their
  source. The full dagents suite stays green after each port.
- dforge fixes that land after the merge are out of scope; a deferred row in the
  split register records that dagents does not follow them automatically.

### 3. The identifier rename (isolation)

Every dforge identifier in `plugins/dagents` becomes its dagents form:

| Kind | dforge 4.17.1 | dagents |
|---|---|---|
| Skill and agent namespace | `dforge:<name>` | `dagents:<name>` |
| Entry skill | `using-dforge` | `using-dagents` |
| Script and library names | `dforge-path`, `dforge-config`, `dforge-migrate`, `lib/dforge-*.{sh,mjs}` | `dagents-*` |
| Project state | `.dforge/` | `.dagents/` |
| Project documents | `docs/dforge/` | `docs/dagents/` |
| Home | `~/.dforge/` (config.json, stores.json, mirror, locks) | `~/.dagents/` |
| Session files | `~/.claude/dforge/` | `~/.claude/dagents/` |
| Environment, dforge's own | `DFORGE_*`, `DR_*` (`DR_CODEX_SESSION_DIR`, `DR_LOCK_*`, `DR_EXECUTORS_DIR`, `DR_*_POLICY`, …), dforge-defined `DARKMEM_*` tuning (`DARKMEM_SYNC_LOCK_WAIT_MS`, …) | `DAGENTS_*` |
| darkmem | client `dforge`, document prefix `dforge/`, workstream keys | `dagents`, `dagents/`, workstream keys prefixed `dagents/` |
| Commands and messages | `/dforge:…`, `dforge: …` prefixes | `/dagents:…`, `dagents: …` |

Shared on purpose: variables another tool owns (`CLAUDE_*`, `CODEX_*`, the
darkmem credentials and URL). The plan enumerates both lists from the tree.

The word `dforge` survives in `plugins/dagents` only where dagents must name
dforge itself: the 4.x migration (§4), the guard's sibling list (§5), the
README's origin note, and the older dr-forge and dr-superpowers translations
the migrate script carries. `validate-repository.mjs` gets that file allowlist.

### 4. Migrating a dforge 4.x project

dagents' migrate skill and `dagents-migrate` gain a `from dforge 4.x` move
beside the existing older-layout moves:

- **Which projects:** a project is 4.x when it has `docs/dforge/` or `.dforge/`
  and none of version 5's own state (the plan names the markers, starting with
  the per-session state file and reviewer-panel records). A project carrying
  any of them is reported "dforge 5 layout: not migratable", and nothing moves.
- **Project files:** in the checkout and every worktree, `docs/dforge/` →
  `docs/dagents/` and `.dforge/` → `.dagents/`, as staged `git mv` renames for
  tracked files and plain moves for ignored ones, with no commit. `dforge:`
  references in plans, ledgers and handoffs are rewritten to `dagents:`.
  `.gitignore`, `.gitattributes` and the shared `info/exclude` gain `.dagents`
  lines and keep their `.dforge` lines.
- **Home files, per repository:** `~/.dforge/config.json` and
  `~/.dforge/stores.json` stay where they are, since dforge 5 serves every other
  repository from them. The migrated repository's darkmem mapping is copied
  into `~/.dagents/config.json`. Its `stores.json` record moves, together with
  its mirror directory, into `~/.dagents/`, with the mirror path rewritten, and
  that one entry is removed from `~/.dforge/stores.json` under the home lock.
- **darkmem data:** the project's `dforge/…` documents and its workstreams are
  copied to the `dagents` namespace, and every copy is read back. The dforge
  originals are not deleted, because other checkouts and machines may still map
  the project. Migrate prints the command that deletes them, for use once no
  dforge checkout maps the project (A13).
- **How it runs:** a dry run first, then one confirmation, then the move. It
  refuses, and moves nothing, when a target already exists, when the tree is
  dirty, or when a live session holds the run (its lock or an auto-run
  binding). An unfinished 4.x ledger is not a refusal: dagents reads the 4.x
  format, so the plan resumes under dagents.
- **Detection:** dagents' session start and `repo-audit` report "dforge 4.x
  layout found" only when dagents is active and the project is 4.x by the rule
  above.

### 5. The workflow guard

- **One file, three copies.** `scripts/workflow-guard.mjs` is shipped
  byte-identical in dforge, dagents and dflow, because plugins never import
  each other. `validate-repository.mjs` fails when the copies differ.
- **Detection.** For each sibling `<name>@darkraise`, the guard computes the
  effective enabled value with Claude Code's precedence: managed settings
  (the file paths and drop-in directory per OS, which the plan takes from the
  settings documentation), then project-local `.claude/settings.local.json`,
  project `.claude/settings.json`, and user
  `${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json`. The project directory is
  `CLAUDE_PROJECT_DIR`, or else the working directory's git root. A sibling is
  active when that value is `true` and
  `${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/installed_plugins.json` holds an
  install of it whose scope applies to this project (a user install, or a
  project or local install for this project's path). The guard cannot see
  `--settings`, `--plugin-dir` or server-delivered managed settings, and the
  README says so.
- **Failing open.** When node is missing, a file is malformed or the check
  throws, the guard prints one diagnostic line and reports no conflict, so a
  broken guard never disables a working session.
- **Stand-down.** On a conflict, the plugin's SessionStart hook skips all of
  its normal work (the injection, darkmem reconcile and pull, the transcript
  record) and prints one block instead. The block names every active workflow
  plugin and the exact `claude plugin disable <name>@darkraise --scope <scope>`
  commands. It then writes a stand-down marker keyed by the session id in the
  plugin's own data directory (`CLAUDE_PLUGIN_DATA`), pruning markers older
  than seven days. Every other hook of that plugin exits 0 at once when the
  marker exists. The mod (cockpit or HUD) runs the read-only standalone check
  itself at load, before any side effect, and on a conflict renders one line
  pointing to the block and does nothing else. All active workflow plugins that
  carry the guard stand down. An installed sibling older than its guard release
  (dforge before 5.0.0, dflow before its first tagged release) does not stand
  down, and the block and the README say so.
- **Standalone check.** `node <plugin-root>/scripts/workflow-guard.mjs` prints
  the active workflow plugins with the scope that enables each. It exits 0 for
  zero or one and 3 for a conflict, and it writes nothing.
- **Codex.** dforge and dagents have no Codex hooks, so on Codex the entry
  skill's `codex-tools.md` step runs the standalone check first. That check
  reads `[plugins."<name>@darkraise"] enabled` (developers.openai.com/codex/plugins/build.md)
  from `${CODEX_HOME:-~/.codex}/config.toml` and the project's
  `.codex/config.toml`.

### 6. dforge 5 and dflow

- dforge: `workflow-guard.mjs`; the stand-down in `session-start.sh`; the
  marker check at the top of every other hook script in `hooks/hooks.json`; the
  load-time check in the cockpit mod; the Codex entry step; a README section on
  the guard; and a README line pointing the 4.x agent workflow to dagents. The
  version is left to the release workflow.
- dflow: the same guard wiring in its SessionStart hook, its other hooks and its
  HUD mod.

### 7. Repository wiring

Lands in the rename commit (§1 step 3):

- Both marketplace catalogs list dagents. `validate-repository.mjs` names it,
  with the Codex rules dforge has (explicit empty Codex hooks, no dependencies).
  Its `dforge:` reference check becomes `<plugin>:` resolving within that
  plugin's own tree, `.dagents` joins the unswept set, and dagents gets its own
  retired-name allowlists. The layout test's plugin list gains dagents.
- `scripts/test-all.mjs` and `scripts/test-shards.mjs` key `windowsSeconds`,
  `suiteSeconds` and `suiteParts` by plugin-relative path instead of basename,
  and `checkShellWeights` covers `plugins/dagents/tests/`. dagents' weights are
  measured. The Windows shard count rises when a shard would exceed its job
  timeout.
- `.github/workflows/validate.yml` gets a "Validate and test dagents" step and
  its own Linux job for dagents' suites, with a measured bound.
- `.gitignore` ignores `.dagents/`. Project `CLAUDE.md` Validation names
  `plugins/dagents` beside dforge and dflow.
- **Release order:** `main` is not pushed until this work is merged, so dforge
  5.0.0 and dagents 1.0.0 release in the same push.

## Acceptance

A1. [test, high] `plugins/dagents` at the copy commit is byte-identical to `plugins/dforge` at tag `dforge-v4.17.1`.
A2. [test, high] Both dagents manifests carry `"name": "dagents"` and `"version": "1.0.0"`; both marketplace catalogs list dagents with source `./plugins/dagents`; `claude plugin validate plugins/dagents` and the marketplace validation pass.
A3. [test, high] Every non-merge commit in `dforge-v4.17.1..<main head at merge>` touching `plugins/dforge/` is a row of the backport register, and `register open` on it exits 0 at the end: each row is `done` naming a dagents commit, or `n/a` with a class from §2.
A4. [test, high] For each port commit, its regression test (or, for a fix that shipped without one, a new test reproducing the defect) fails at the port's parent and passes at the port commit, and the register row records both results.
A5. [test, neg, high] dagents has none of version 5's features: no reviewer-panel runner, no API-ruling rungs, no `task-close`, no per-session state file; its 16 `impl-*` agents, subagent-driven-development, revising-plans and Executor-line routing are present.
A6. [test, neg, high] Outside the §3 allowlist, `rg -i dforge plugins/dagents` finds nothing.
A7. [test, neg, high] With dagents active, a full session-start, task-brief, next-step and turn-end cycle in a temporary project and home creates or changes nothing named `.dforge`, `docs/dforge`, `~/.dforge` or `~/.claude/dforge`, and a set `DFORGE_BUDGET` or `DR_CODEX_SESSION_DIR` changes nothing.
A8. [test, high] The full dagents suite, `claude plugin test plugins/dagents` and `tsc --noEmit -p plugins/dagents` pass.
A9. [test, high] dagents migrate on a fixture dforge 4.x project with a worktree stages `git mv` renames of `docs/dforge` and moves `.dforge` in each worktree, rewrites `dforge:` references in plans, ledgers and handoffs, adds `.dagents` ignore lines while keeping the `.dforge` ones, and leaves no dforge-named project file behind.
A10. [test, neg, high] The migrate dry run writes nothing, and the move refuses, writing nothing, when `docs/dagents` already exists, the tree is dirty, a live session holds the run, or the project carries version-5 state.
A11. [test, high] With two of dforge, dagents and dflow (each at its guard release) enabled at any settings scope and installed, each plugin's SessionStart prints the conflict block naming both and the disable commands with the right scopes, and neither its other hooks nor its mod writes or prints anything else for the rest of the session.
A12. [test, neg, high] The guard never writes a settings file or `installed_plugins.json`, under a conflict or not.
A13. [test, medium] Migrating a project whose documents live in darkmem copies its `dforge/…` documents and workstreams to the dagents namespace, reads every copy back, deletes nothing, and prints the deletion command for the originals. Q: is copy-and-print right for darkmem, given the dforge originals may still serve other checkouts or machines, or should migrate delete them as the local move does?
A14. [test, high] A sibling enabled in user settings but disabled in project settings, enabled but not installed, or installed at project scope for another project, is not a conflict; managed `false` overrides every other scope; a malformed settings file gives one diagnostic and no conflict.
A15. [test, high] The standalone check exits 0 with one or no workflow plugin active, exits 3 with two or more, and prints each active plugin with its enabling scope.
A16. [test, high] The three copies of `workflow-guard.mjs` are byte-identical, and `validate-repository.mjs` fails on a fixture where one differs.
A17. [test, neg, high] A session with exactly one workflow plugin active behaves as before: no guard output, no marker, and every existing dforge and dflow suite passes unchanged.
A18. [test, high] With a fixture `config.toml` enabling both dforge and dagents under `CODEX_HOME`, the standalone check exits 3.
A19. [test, high] Every job of `Validate marketplace` passes for the pushed commit, including all Windows shards, within the timeouts this work sets.
A20. [test, high] After migrating project A, dforge 5 in project B on the same home resolves its darkmem mapping and applied stores unchanged.
A21. [test, high] A 4.x project with an unfinished subagent-mode ledger migrates and resumes under dagents at its next task.
A22. [test, high] A dagents suite with the same basename as a dforge suite gets its own time limit, parts and weight in `test-all.mjs` and `test-shards.mjs`.
A23. [test, high] Before the push, `node scripts/release.mjs --dry-run` lists dforge 5.0.0 and dagents 1.0.0.
A24. [demo, medium] On Codex with dforge and dagents both enabled, the first turn runs the standalone check and stops with the conflict message. Q: is a skill-text check (no hook) acceptable on Codex, where neither plugin has hooks?

## Riskiest assumption

The mechanical rename of the 4.17.1 tree (4,037 `dforge` references in 260
files) yields a working plugin once its suite and `claude plugin test` pass.
Some references are load-bearing in ways a token replacement can break: a
string compared against Claude Code's own output, a skill name a test pins, or
an older-layout translation that must keep saying dforge. unverified — the
plan's first task verifies it, by running the copy's suite before the rename
and again right after it, ahead of any port.

## Out of scope

- Any change to dforge 5's behaviour beyond the guard and its README.
- Retiring or deprecating dforge 4.x installs in place: an installed dforge
  4.17.1 upgrades to 5.0.0 through the normal update path, and a user who wants
  the 4.x workflow installs dagents and runs its migrate.
- Following dforge fixes that land after the merge (a deferred row records it).
- This repository's own `docs/dforge/` records, which belong to its dforge use.

## Critic findings

- Blocker, home files moved: fixed. §4 keeps `~/.dforge/` files and moves only the migrated repository's record and mirror; A20.
- High, in-flight 4.x runs stranded: fixed. Only a live session's run refuses; A21; release order in §7.
- High, suites keyed by basename: fixed. §7 keys by plugin-relative path; A22.
- High, darkmem deletion and shared progress: fixed. Copy-and-read-back, no deletion, workstreams renamed; A13 keeps its question for the owner.
- Medium, 4.x versus 5 fingerprint: fixed in §4 and A10.
- Medium, git outcome and ignore files: fixed in §4 and A9.
- Medium, mod marker timing: fixed. The mod runs the check itself.
- Medium, guard detection details and failure: fixed in §5 and A14.
- Medium, `DR_*` variables: fixed in §3 and A7.
- Medium, validation wiring order: fixed. Rename before ports, wiring in the rename commit.
- Medium, Linux job size: fixed. Separate dagents Linux job; A19 reworded.
- Medium, 5.0.0 before dagents: fixed. Release order in §7; A23.
- Medium, register frozen at base: fixed. Refresh before merge; later fixes deferred.
- Medium, A4 uncheckable: fixed. Per port commit.
- Medium, SessionStart side effects and old siblings: fixed in §5 and A11.
- Medium, Codex key and home: fixed. Citation, `CODEX_HOME`, A18 now a test.
- Nit, dflow 1.1.0: fixed in Decisions (1.0.0).
- Nit, markers never pruned: fixed (seven days).
- Nit, `.gitignore`: fixed in §7.
- Nit, dforge wiring: fixed in §6.
