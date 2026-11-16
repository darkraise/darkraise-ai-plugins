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
  scripted rename, so every commit from the rename on is a consistent dagents
  that CI validates.
- Early CI: none

Finish: merge

Worktree: in-place

## Goal

Three plugins in one marketplace, at most one of which is active in a session:
**dforge 5** (the current reviewer-panel workflow), **dagents 1.0** (the dforge
4.17.1 agent workflow: implementer agents, subagent mode, external executor
lanes, parallel waves, group review, revising-plans) carrying every version-5
fix for a defect it shares, and **dflow**. None of them reads or writes the
others' files, settings, environment variables or darkmem data, with two
deliberate exceptions: dagents' migrate reads and edits dforge's files, and the
guard reads the host's plugin settings through one shared override set (§5).

## Design

### 1. Creating dagents

1. `git read-tree --prefix=plugins/dagents/ -u dforge-v4.17.1:plugins/dforge`
   creates the copy, committed alone; its tree hash equals the tag's
   `plugins/dforge` tree.
2. The manifests (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`)
   take `"name": "dagents"`, `"version": "1.0.0"`, a description naming the
   agent workflow, and the dagents homepage. Committed alone.
3. `scripts/dagents-rename.mjs` (repository script, with a small test under
   `tests/`, kept after the merge for later manual backports) applies the §3
   map to a tree or to a patch. It runs once over `plugins/dagents`, and the
   result is committed with the repository wiring (§7).
4. **Green from the rename on.** The copy and manifest commits are exempt: before
   the rename, test paths name `plugins/dforge/…` and resolve to dforge 5, and
   `lint-portability.mjs` lints every `plugins/*` tree with today's rules. Each
   baseline failure of the renamed copy is listed and dispositioned before any
   port: fixed in the rename commit, or the test dropped with its reason.
5. The version-5 fixes are ported (§2), each patch passed through the same
   script. Migration (§4) and the guard (§5) follow.

### 2. Backporting the fixes

- **The backport register** `docs/dforge/registers/2026-11-16-dagents-backport.md`
  holds one row per non-merge commit in `dforge-v4.17.1..<base>` that touches
  `plugins/dforge/`, where `<base>` is the `main` commit the branch starts from
  (283 commits at `d85f6776`). The commit's hash and subject are the row's
  Item, so no commit can be lost. Before the merge, the query runs again
  against `main`'s head and new commits become rows.
- Each row ends `done`, with the dagents commit and the A4 results in its Note,
  or `n/a`, with one of these classes in its Note:
  - `5-only` — the defect is in code 4.17.1 does not have. Valid without
    comment only when every non-test path the commit touches is absent at the
    tag, which a plan script checks mechanically;
  - `feature` — not a fix: a feat, perf or refactor commit, or a retirement;
  - `test-only` or `docs-only` — tests or text for a version-5 feature;
  - `superseded` — a later commit on the list reverts or replaces it.
  Every `n/a` row other than a mechanically checked `5-only`, and any `feature`
  row whose subject says `fix`, carries a one-clause reason naming the code.
- A commit of any type is `port` when its defect exists in 4.17.1: docs and test
  commits included (`86c359cd` fixed project-status routing as a `docs`
  commit). A port brings its regression test and whatever new code the fix
  needs. When the fix lives in code version 5 restructured (for example
  next-step's router moved to `route.sh`), the port reimplements the same
  behaviour in the 4.17.1 structure, and the row's Note says so.
- Port commits are `fix(dagents): <subject>`, with body `Backport of <sha>.`,
  landing in source order. One commit per fix; source commits that fix the same
  defect may share one port commit, each row naming it.
- **Test cost:** each port runs the suites that name the scripts it changes; the
  full dagents suite runs at each plan-task boundary and at the end. A boundary
  failure is bisected and fixed in the offending port commit before work
  continues (the branch is unpushed).
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
| Git-directory state | `<git common dir>/dforge/` (locks) | `<git common dir>/dagents/` |
| Home | `~/.dforge/` (config.json, stores.json, mirror, locks) | `~/.dagents/` |
| Session files | `~/.claude/dforge/` | `~/.claude/dagents/` |
| Environment, dforge's own | `DFORGE_*`, `DR_*` (`DR_CODEX_SESSION_DIR`, `DR_LOCK_*`, `DR_EXECUTORS_DIR`, `DR_*_POLICY`, …), dforge-defined `DARKMEM_*` tuning (`DARKMEM_SYNC_LOCK_WAIT_MS`, …) | `DAGENTS_*` |
| darkmem | client `dforge`, document prefix `dforge/`, workstream keys | `dagents`, `dagents/`, workstream keys prefixed `dagents/` |
| Commands and messages | `/dforge:…`, `dforge: …` prefixes | `/dagents:…`, `dagents: …` |

Shared on purpose: variables another tool owns (`CLAUDE_*`, `CODEX_*`, the
darkmem credentials and URL), the repository test harness's `DR_TEST_BASH` and
`DR_TEST_ALL`, and the guard's input overrides (§5). The plan enumerates both
lists from the tree.

The word `dforge` survives in `plugins/dagents` only where dagents must name
dforge itself:
- the 4.x migration (§4);
- the readers that translate older spellings: `docs/dforge` and `.dforge` become
  a third older spelling beside `docs/forge` and `docs/superpowers`, read at the
  same places 4.17.1 translates those two (for example `lib/roots.sh`, the
  migrate script, the darkmem mirror, sync and reconcile; the plan finds every
  such list), so a migrated plan, ledger, register or
  `completed.md` citing `docs/dforge/…` still resolves;
- the guard's sibling list (§5) and the README's origin note;
- the older dr-forge and dr-superpowers translations the migrate script carries.

`validate-repository.mjs` gets that file allowlist. Version-qualified origin text
("off by default since dforge 3.0") is kept as dforge or reworded, and
`plugins/dagents` names no dagents version other than 1.x.

### 4. Migrating a dforge 4.x project

dagents' migrate skill and `dagents-migrate` gain a `from dforge 4.x` move
beside the existing older-layout moves, behaving as the existing migrate does:
each move is independent, an absent source is skipped, a source and an
existing target merge file by file, and a second run finishes the job.

- **Which projects:** a project is 4.x when it has `docs/dforge/` or `.dforge/`
  and no version-5 marker. Markers are only things version-5 work produces,
  including a tracked signal (a plan or ledger form 4.17.1 never writes); no
  marker is something a dforge 5 session start or turn hook writes on its own.
  A project carrying a marker is reported "dforge 5 layout: not migratable",
  and nothing moves.
- **Project files:** in the checkout and every worktree, `docs/dforge/` →
  `docs/dagents/`, `.dforge/` → `.dagents/` and `<git dir>/dforge/` →
  `<git dir>/dagents/`, as staged `git mv` renames for tracked files and plain
  moves for the rest, with no commit. `dforge:` prefixes in active plans and
  the handoff note are rewritten to `dagents:`; other tracked files that
  mention `docs/dforge`, `.dforge` or `dforge:` (a project `CLAUDE.md`, say)
  are reported, not rewritten. Every `.gitignore`, `.gitattributes` and shared
  `info/exclude` line naming `.dforge` or `docs/dforge` gains its dagents twin
  and is kept.
- **Home files, per repository:** `~/.dforge/config.json` and
  `~/.dforge/stores.json` stay where they are, since dforge 5 serves every other
  repository from them. Every key of `~/.dforge/config.json` that dagents'
  schema defines (workflow, cockpit and notification settings, and this
  repository's darkmem mapping) is copied into `~/.dagents/config.json` without
  overwriting a value dagents already has. The repository's `stores.json`
  record moves into `~/.dagents/stores.json` and is removed from
  `~/.dforge/stores.json` under the home lock. Its mirror directory moves, or
  is copied while another `~/.dforge/stores.json` record still names it, with
  the mirror path, the state file's document prefix and its uris rewritten to
  `dagents`. The dry run lists any set `DFORGE_*` or `DR_*` variable (process
  environment and Claude settings `env`) with its `DAGENTS_*` name.
  `~/.claude/dforge/` session files are not migrated.
- **darkmem data:** the project's `dforge/…` documents and its workstreams are
  copied to the `dagents` namespace, and every copy is read back. The dforge
  originals are not deleted, because other checkouts and machines may still map
  the project. Migrate prints the command that deletes them, for use once no
  dforge checkout maps the project (A13).
- **How it runs:** a dry run first, then one confirmation, then the moves. It
  refuses only a differing same-path file, two tracked docs trees, a dirty file
  among the paths it moves or rewrites, and a run a live session holds (dforge's
  lock or auto-run binding, read at dforge's locations). An unfinished 4.x
  ledger is not a refusal: with the older-spelling readers (§3), the plan
  resumes under dagents.
- **Detection:** dagents' session start and `repo-audit` report "dforge 4.x
  layout found" only when dagents is active and the project is 4.x by the rule
  above.

### 5. The workflow guard

- **One file, three copies.** `scripts/workflow-guard.mjs` is shipped
  byte-identical in dforge, dagents and dflow, because plugins never import
  each other. It parses the TOML subset it needs itself (no dependency).
  `validate-repository.mjs` fails when the copies differ.
- **Host.** The check takes `--host claude|codex` and never combines hosts.
  Hooks and mods pass `claude`; the Codex skill step passes `codex`.
- **Inputs and overrides.** Three roots are overridable through one variable
  set shared by the three copies: the Claude config directory (default
  `${CLAUDE_CONFIG_DIR:-~/.claude}`), the managed-settings directory (default
  per OS, the paths and drop-in directory taken from the settings
  documentation), and the project directory (default `CLAUDE_PROJECT_DIR`, else
  the working directory's git root). The shared shell test helper, the mod
  test setup and `test-all.mjs` point them at empty fixtures, so no suite
  depends on the host's plugins, whether run alone or through `test-all.mjs`.
  The plan confirms once by hand that SessionStart's `systemMessage` displays.
- **Detection on Claude Code.** For each sibling `<name>@darkraise`, the
  effective value is that of the highest-precedence scope that sets the key
  (managed, then project-local `.claude/settings.local.json`, project
  `.claude/settings.json`, user settings), else `true`, since plugins are
  enabled by default. A sibling is active when the value is `true` and
  `installed_plugins.json` holds an install whose scope applies to this project
  (a user install, or a project or local install for this project's path).
  The guard cannot see `--settings`, `--plugin-dir`, server-delivered settings,
  or MDM, registry and plist policy; the README says so.
- **Detection on Codex.** `[plugins."<name>@darkraise"] enabled` from the
  project's `.codex/config.toml` over `${CODEX_HOME:-~/.codex}/config.toml`
  (developers.openai.com/codex/plugins/build.md); Codex does not apply an
  untrusted project's file, and the README says so.
- **Failing open.** When node is missing, the guard is silent and reports no
  conflict. When a file is malformed or the check throws, it prints one
  diagnostic line and reports no conflict. A broken guard never disables a
  working session.
- **Stand-down.** The guard's SessionStart entry matches
  `startup|resume|clear|compact|fork`. On a conflict, the plugin's SessionStart
  hook skips all of its normal work (the injection, darkmem reconcile and pull,
  the transcript record) and returns JSON: the block in `systemMessage`, for
  the user, and in `hookSpecificOutput.additionalContext`, telling the model to
  relay it and to use no skill of either plugin until one is disabled. The
  block names every active workflow plugin and, for a sibling enabled at user
  or project scope, two commands: `claude plugin disable <name>@darkraise
  --scope local` (this project only) first, then the enabling scope's command.
  The hook then writes a stand-down marker keyed by the session id in the
  plugin's own data directory (`CLAUDE_PLUGIN_DATA`), pruning markers older
  than seven days; a SessionStart that finds no conflict deletes its session's
  marker. Every other hook of that plugin exits 0 at once when the marker
  exists. The mod (cockpit or HUD) runs the read-only standalone check through
  `$.process.run` and awaits it before registering anything with a side effect;
  on a conflict it renders one line naming the active plugins and the
  standalone check command, and does nothing else.
- **Limits.** Claude Code offers no way for a plugin to hide its skills, so a
  stood-down plugin's skills and scripts still run when invoked; the
  `additionalContext` text is the mitigation, and both READMEs state the limit.
  An installed sibling older than its guard release (dforge before 5.0.0, dflow
  before its first tagged release) does not stand down, and the block and the
  README say so.
- **Standalone check.** `node <plugin-root>/scripts/workflow-guard.mjs --host
  <host>` prints the active workflow plugins with the scope that enables each.
  It exits 0 for zero or one and 3 for a conflict, and it writes nothing.
- **Codex.** dforge and dagents have no Codex hooks, so on Codex the entry
  skill's `codex-tools.md` step runs the standalone check with `--host codex`
  first.

### 6. dforge 5 and dflow

- dforge: `workflow-guard.mjs`; the stand-down in `session-start.sh`; the
  marker check at the top of every other hook script in `hooks/hooks.json`; the
  load-time check in the cockpit mod; the Codex entry step; a README section on
  the guard; a README line pointing the 4.x agent workflow to dagents; and one
  clause naming dagents and `/dagents:migrate` in plan-lint's existing
  subagent-mode error and Executor-line warning. The version is left to the
  release workflow.
- dflow: the same guard wiring in its SessionStart hook, its other hooks and its
  HUD mod.

### 7. Repository wiring

Lands in the rename commit (§1 step 3):

- Both marketplace catalogs list dagents. `validate-repository.mjs` names it,
  with the Codex rules dforge has (explicit empty Codex hooks, no dependencies).
  Its `dforge:` reference check becomes `<plugin>:` resolving within that
  plugin's own tree, `.dagents` joins the unswept set, dagents gets its own
  retired-name allowlists, and `validateSchema` takes each plugin's own config
  schema and name instead of the hard-coded dforge path. The layout test's
  plugin list gains dagents.
- `scripts/test-all.mjs` and `scripts/test-shards.mjs` key `windowsSeconds`,
  `suiteSeconds` and `suiteParts` by plugin-relative path instead of basename,
  and `checkShellWeights` covers `plugins/dagents/tests/`. `test-all.mjs` gains
  a plugin selector, so the dagents Linux job runs dagents' suites and the main
  job drops them, and its tsc and `claude plugin test` jobs cover dagents.
  dagents' weights are measured. The Windows shard count rises when a shard
  would exceed its job timeout.
- `.github/workflows/validate.yml` gets a "Validate and test dagents" step and
  a dagents Linux job with a measured bound, on the same runner selection as
  `validate`, and the homelab wait job watches it too. The dagents Linux job
  and the dagents Windows shards run only when `plugins/dagents/`, `scripts/`,
  `tests/` or the workflow change; project `CLAUDE.md` says a skipped job
  counts as green.
- `.gitignore` ignores `.dagents/`. Project `CLAUDE.md` Validation names
  `plugins/dagents` beside dforge and dflow.
- The root `README.md` gains a dagents row and a one-of-three note, and
  `docs/migration.md` an entry for 4.x users: 4.17.1 updates to 5.0.0; to keep
  the agent workflow, install dagents, disable dforge for the project, and run
  `/dagents:migrate`.
- **Release order:** `main` is not pushed until this work is merged, so dforge
  5.0.0, dagents 1.0.0 and dflow 1.0.0 release in the same push.

## Acceptance

A1. [test, high] The copy commit's `plugins/dagents` tree hash equals the `plugins/dforge` tree hash at tag `dforge-v4.17.1`.
A2. [test, high] Both dagents manifests carry `"name": "dagents"` and `"version": "1.0.0"`; both marketplace catalogs list dagents with source `./plugins/dagents`; `claude plugin validate plugins/dagents` and the marketplace validation pass.
A3. [test, high] At merge time, a command lists every non-merge commit in `dforge-v4.17.1..<main head>` touching `plugins/dforge/` as a row of the backport register, `register open` on it exits 0, each row is `done` naming a dagents commit or `n/a` with a §2 class, and every `5-only` row without a reason passes the mechanical path check.
A4. [test, high] For each port commit that changes code or tests, its regression test (or, for a fix that shipped without one, a new test reproducing the defect) fails at the port's parent and passes at the port commit, and the register row records both results; a port that changes only skill or reference prose records `text-only` and the changed file instead.
A5. [test, neg, high] dagents has none of version 5's features (no reviewer-panel runner, no API-ruling rungs, no `task-close`, no per-session state file), and its agent set, subagent-driven-development, revising-plans and Executor-line routing equal the tag's under the rename.
A6. [test, neg, high] Outside the §3 allowlist, `rg -i dforge plugins/dagents` finds nothing, and `plugins/dagents` names no dagents version other than 1.x.
A7. [test, neg, high] With dagents active, a full session-start, task-brief, next-step and turn-end cycle in a temporary project and home creates or changes nothing named `.dforge`, `docs/dforge`, `~/.dforge` or `~/.claude/dforge`; a set `DFORGE_BUDGET` or `DR_CODEX_SESSION_DIR` changes nothing; and a pre-seeded `~/.dforge/config.json` (non-default settings and a darkmem mapping) plus `.dforge/` state leave dagents' output equal to the run without them, apart from the §4 "dforge 4.x layout found" line.
A8. [test, high] The full dagents suite, `claude plugin test plugins/dagents` and `tsc --noEmit -p plugins/dagents` pass.
A9. [test, high] dagents migrate on a fixture dforge 4.x project with a worktree stages `git mv` renames of `docs/dforge`, moves `.dforge` and `<git dir>/dforge` in each worktree, rewrites `dforge:` prefixes in active plans and the handoff note, reports other files that mention dforge, adds dagents twins to ignore and attributes lines while keeping the dforge ones, and copies the home settings dagents' schema defines without overwriting existing dagents values.
A10. [test, neg, high] The migrate dry run writes nothing; the move refuses, writing nothing for that item, on a differing same-path file, two tracked docs trees, a dirty file among the paths it moves, or a run a live session holds; a project with a version-5 marker, including a fresh clone of one, is refused; a 4.x project opened once under dforge 5 still migrates; and a second run after a partial migration finishes the job.
A11. [test, high] With two or all three of dforge, dagents and dflow (each at its guard release) enabled and installed, each plugin's SessionStart returns JSON whose `systemMessage` and `additionalContext` both name every active plugin and give the `--scope local` command first, plus the enabling scope's command for a user- or project-scope sibling; neither its other hooks nor its mod writes or prints anything else for the rest of the session.
A12. [test, neg, high] The guard never writes a settings file or `installed_plugins.json`, under a conflict or not.
A13. [test, confirmed] Migrating a project whose documents live in darkmem copies its `dforge/…` documents and workstreams to the dagents namespace, reads every copy back, deletes nothing, and prints the deletion command for the originals.
A14. [test, high] A sibling enabled in user settings but disabled in project settings, enabled but not installed, or installed at project scope for another project, is not a conflict; installed with no `enabledPlugins` entry at any scope is active; managed `false` overrides every other scope; a malformed settings file gives one diagnostic and no conflict; with node missing the hooks print nothing extra.
A15. [test, high] `workflow-guard.mjs --host claude` exits 0 with one or no workflow plugin active, exits 3 with two or more, and prints each active plugin with its enabling scope.
A16. [test, high] The three copies of `workflow-guard.mjs` are byte-identical, and `validate-repository.mjs` fails on a fixture where one differs.
A17. [test, neg, high] A session with exactly one workflow plugin active behaves as before: no guard output, no marker, and every existing dforge and dflow suite passes with no change other than the harness isolating the guard's inputs.
A18. [test, high] With a fixture `config.toml` enabling both dforge and dagents under `CODEX_HOME`, `workflow-guard.mjs --host codex` exits 3; with dforge enabled for Claude Code and dagents for Codex, neither host's check reports a conflict.
A19. [test, high] Every job of `Validate marketplace` passes for the pushed commit, including all Windows shards, within the timeouts this work sets.
A20. [test, high] After migrating project A, dforge 5 in project B on the same home resolves its darkmem mapping and applied stores unchanged.
A21. [test, high] After migrating a fixture 4.x project whose `completed.md` and unfinished subagent-mode ledger cite `docs/dforge/…`, next-step treats the finished plan as finished and resumes the unfinished one at its next task under dagents.
A22. [test, high] A dagents suite with the same basename as a dforge suite gets its own time limit, parts and weight in `test-all.mjs` and `test-shards.mjs`.
A23. [test, high] Before the push, `node scripts/release.mjs --dry-run` lists dforge 5.0.0, dagents 1.0.0 and dflow 1.0.0.
A24. [demo, confirmed] On Codex with dforge and dagents both enabled, the first turn runs the standalone check and stops with the conflict message; the README states the check runs only when the entry skill loads.
A25. [test, high] With an exported host config that enables a sibling workflow plugin, the dagents, dforge and dflow suites still pass.
A26. [test, high] A dagents push and pull against a stub darkmem server request only the `dagents` client, `dagents/…` documents and `dagents/`-prefixed workstream keys, with `dforge/…` data present and untouched; the first dagents sync after migrating a darkmem-applied project deletes nothing and re-uploads nothing.
A27. [test, high] A SessionStart with no conflict deletes its session's marker, and a `fork` session start runs the guard.
A28. [test, high] dforge 5's plan-lint subagent-mode error and Executor-line warning name dagents and `/dagents:migrate`.
A29. [test, neg, high] A push that changes none of `plugins/dagents/`, `scripts/`, `tests/` or the workflow runs no dagents job, and the run is green.

## Riskiest assumption

The mechanical rename of the 4.17.1 tree (4,037 `dforge` references in 260
files) yields a working plugin once its suite and `claude plugin test` pass.
Some references are load-bearing in ways a token replacement can break: a
string compared against Claude Code's own output, a skill name a test pins, or
an older-layout translation that must keep saying dforge. unverified — the
plan's first task verifies it, by running the copy's suite before the rename
and again right after it, ahead of any port, and dispositioning every failure
(§1 step 4).

## Out of scope

- Any change to dforge 5's behaviour beyond the guard, its README and the
  plan-lint signpost clause (§6).
- Retiring or deprecating dforge 4.x installs in place: an installed dforge
  4.17.1 upgrades to 5.0.0 through the normal update path, and a user who wants
  the 4.x workflow installs dagents and runs its migrate.
- Following dforge fixes that land after the merge (a deferred row records it).
- This repository's own `docs/dforge/` records, which belong to its dforge use.

## Critic findings

- Blocker, home files moved: fixed. §4 keeps `~/.dforge/` files and moves only the migrated repository's record and mirror; A20.
- High, in-flight 4.x runs stranded: fixed. Only a live session's run refuses; older-spelling readers (§3); A21; release order in §7.
- High, suites keyed by basename: fixed. §7 keys by plugin-relative path; A22.
- High, darkmem deletion and shared progress: fixed. Copy-and-read-back, no deletion, workstreams renamed; A13 keeps its question for the owner; A26.
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

## Review rulings

- Owner, spec review: A13 copy and keep originals; A24 skill-text check accepted; dforge 5 plan-lint signpost added (A28); dagents CI path-filtered (A29).

- Fable, spec: [High] conflict block reaches the user — `systemMessage` plus `additionalContext`; A11 asserts both.
- Fable, spec: [High] guard test seam — three overridable roots, harness points them at fixtures; A17 reworded; A25.
- Fable, spec: [High] 4.x path citations — `docs/dforge` and `.dforge` read as a third older spelling; migrate rewrites only `dforge:` prefixes in active plans and the handoff; A21.
- Fable, spec: default-enabled siblings count as active; A14.
- Fable, spec: the check takes `--host claude|codex` and never combines hosts; A15, A18.
- Fable, spec: migrate copies home settings dagents' schema defines, lists set `DFORGE_*`/`DR_*` variables; A9.
- Fable, spec: version-5 markers are tracked and never hook-written; A10 cases added.
- Fable, spec: migrate moves are independent and resumable, refusals per item; A10 reworded.
- Fable, spec: `<git dir>/dforge/` joins §3 and §4.
- Fable, spec: mirror state rewritten to the dagents prefix, copied while shared; A26.
- Fable, spec: darkmem isolation behavioural test; A26.
- Fable, spec: read isolation with pre-seeded dforge state; A7.
- Fable, spec: `DR_TEST_BASH` and `DR_TEST_ALL` stay shared.
- Fable, spec: skills stay invocable under stand-down; READMEs state the limit.
- Fable, spec: disable commands print `--scope local` first; A11.
- Fable, spec: marker deleted when no conflict, guard matches `fork`; A27.
- Fable, spec: node missing fails open silently; A14.
- Fable, spec: prose-only ports record `text-only` instead of a test; A4.
- Fable, spec: `5-only` rows checked mechanically, other `n/a` rows carry a reason; A3 is a merge-time command.
- Fable, spec: per-port targeted suites, full suite at task boundaries.
- Fable, spec: green invariant starts at the rename commit; baseline failures dispositioned.
- Fable, spec: §7 adds the plugin selector, wait-job coverage, per-plugin `validateSchema`, and dagents tsc and plugin test.
- Fable, spec: root README row and `docs/migration.md` entry.
- Fable, spec: copy by `git read-tree`; A1 is tree-hash equality.
- Fable, spec: A5 compares the agent set with the tag's, not a count.
- Fable, spec: version-qualified origin text kept or reworded; A6.
- Fable, spec: port commits one per fix, in source order.
- Fable, spec: guard blind spots listed (MDM, registry, plist; Codex trust).
- Fable, spec: `.gitattributes` lines gain dagents twins.
- Fable, spec: A23 lists dflow 1.0.0; A11 covers all three enabled.
- Fable, spec: the Goal names its two isolation exceptions.
- Fable, spec: `dagents-rename.mjs` stays with a test; the mod uses `$.process.run`.
