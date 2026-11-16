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
  point is each plugin's SessionStart hook. Settings are never changed.
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
  manifest version, so dagents ships as 1.0.0. dflow's guard commit makes it
  1.1.0.

## Goal

Three plugins in one marketplace, at most one of which is active in a session:
**dforge 5** (the current reviewer-panel workflow), **dagents 1.0** (the dforge
4.17.1 agent workflow: implementer agents, subagent mode, external executor
lanes, parallel waves, group review, revising-plans) carrying every version-5
fix for a defect it shares, and **dflow**. None of them reads or writes the
others' files, settings, environment variables or darkmem documents.

## Design

### 1. Creating dagents

1. `git archive dforge-v4.17.1 plugins/dforge` extracted to `plugins/dagents`:
   the copy is byte-identical to the tag, committed alone.
2. The manifests (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`)
   take `"name": "dagents"`, `"version": "1.0.0"`, a description naming the
   agent workflow, and the dagents homepage. Committed alone.
3. The version-5 fixes are ported (§2) while the tree still uses dforge
   identifiers internally, so each fix applies with only a directory change.
4. The identifier rename (§3) runs once, after the last port.

### 2. Backporting the fixes

- **The backport register** `docs/dforge/registers/2026-11-16-dagents-backport.md`
  holds one row per non-merge commit in `dforge-v4.17.1..<base>` that touches
  `plugins/dforge/`, where `<base>` is the `main` commit the branch starts from
  (283 commits at `d85f6776`). The commit's hash and subject are the row's
  Item, so no commit can be lost.
- Each row ends `done`, with the dagents commit in its Note, or `n/a`, with one
  of these classes in its Note:
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
  source.
- The full dagents suite stays green after each port.

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
| Environment | `DFORGE_*` | `DAGENTS_*` |
| darkmem | client `dforge`, document prefix `dforge/` | `dagents`, `dagents/` |
| Commands and messages | `/dforge:…`, `dforge: …` prefixes | `/dagents:…`, `dagents: …` |

The word `dforge` survives in `plugins/dagents` only where dagents must name
dforge itself: the 4.x migration (§4), the guard's sibling list (§5), the
README's origin note, and the older dr-forge and dr-superpowers translations
the migrate script carries. `validate-repository.mjs` gets that file allowlist.

### 4. Migrating a dforge 4.x project

dagents' migrate skill and `dagents-migrate` gain a `from dforge 4.x` move
beside the existing older-layout moves:

- **What it moves:** in the checkout and every worktree, `docs/dforge/` →
  `docs/dagents/` and `.dforge/` → `.dagents/`. `dforge:` references in active
  plans, ledgers and handoffs are rewritten to `dagents:`. Once per home,
  `~/.dforge/config.json` and `~/.dforge/stores.json` → `~/.dagents/`.
- **How it runs:** a dry run first, then one confirmation, then the move. It
  refuses, and moves nothing, when the target already exists, when the tree is
  dirty, or when a run or a ledger is in flight. Files are moved, not copied.
- **darkmem:** for a project whose documents live in darkmem, the move rewrites
  each `dforge/…` document to `dagents/…`, verifies every copy, and only then
  deletes the originals (A13).
- **Detection:** dagents' session start and `repo-audit` report "dforge 4.x
  layout found" only when dagents is active and a project has `docs/dforge/` or
  `.dforge/`. dforge 5 never reports it, because dforge owns those names.

### 5. The workflow guard

- **One file, three copies.** `scripts/workflow-guard.mjs` is shipped
  byte-identical in dforge, dagents and dflow, because plugins never import
  each other. `validate-repository.mjs` fails when the copies differ.
- **Detection.** For each sibling `<name>@darkraise`, the guard computes the
  effective enabled value with Claude Code's precedence: managed settings, then
  project-local `.claude/settings.local.json`, project `.claude/settings.json`,
  and user `${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json`. A sibling counts as
  active when that value is `true` and
  `${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/installed_plugins.json` records it.
  The guard cannot see `--settings` or `--plugin-dir`, and the README says so.
- **Stand-down.** On a conflict, the plugin's SessionStart hook prints one
  block instead of its normal injection. The block names every active
  workflow plugin and the exact `claude plugin disable <name>@darkraise
  --scope <scope>` commands, then writes a stand-down marker keyed by the
  session id in the plugin's own data directory (`CLAUDE_PLUGIN_DATA`). Every other hook of that plugin exits 0 at once when the marker
  exists. Its mod (cockpit or HUD) renders one line pointing to the block. All
  active workflow plugins stand down, so none runs half-loaded.
- **Standalone check.** `node <plugin-root>/scripts/workflow-guard.mjs` prints
  the active workflow plugins with the scope that enables each. It exits 0 for
  zero or one and 3 for a conflict, and it writes nothing.
- **Codex.** dforge and dagents have no Codex hooks, so on Codex the entry
  skill's `codex-tools.md` step runs the standalone check first. That check
  reads `[plugins."<name>@darkraise"] enabled` from `~/.codex/config.toml` and
  the project's `.codex/config.toml`.

### 6. dforge 5 and dflow

- dforge: the guard, its README section, a README line pointing the 4.x agent
  workflow to dagents, and nothing else. The version is left to the release
  workflow.
- dflow: the guard, wired into its SessionStart hook, its other hooks and its
  HUD mod.

### 7. Repository wiring

- Both marketplace catalogs list dagents. `validate-repository.mjs` names it
  (Codex rules as for dforge: explicit empty Codex hooks, no dependencies).
- `scripts/test-all.mjs` and `scripts/test-shards.mjs` run dagents' suites and
  `claude plugin test plugins/dagents`. Shard weights are measured, not copied
  from dforge's. The Windows shard count rises when a shard would exceed its
  job timeout.
- `.github/workflows/validate.yml` gets a "Validate and test dagents" step.
- Project `CLAUDE.md` Validation names `plugins/dagents` beside dforge and dflow.

## Acceptance

A1. [test, high] `plugins/dagents` at the copy commit is byte-identical to `plugins/dforge` at tag `dforge-v4.17.1` (`git diff --stat dforge-v4.17.1:plugins/dforge <copy>:plugins/dagents` is empty).
A2. [test, high] Both dagents manifests carry `"name": "dagents"` and `"version": "1.0.0"`; both marketplace catalogs list dagents with source `./plugins/dagents`; `claude plugin validate plugins/dagents` and the marketplace validation pass.
A3. [test, high] Every non-merge commit in `dforge-v4.17.1..<base>` touching `plugins/dforge/` is a row of the backport register, and `register open` on it exits 0 at the end: each row is `done` naming a dagents commit, or `n/a` with a class from §2.
A4. [test, high] For each `done` row, the ported regression test (or, for a fix that shipped without one, a new test reproducing the defect) passes in dagents and fails on the 4.17.1 copy.
A5. [test, neg, high] dagents has none of version 5's features: no reviewer-panel runner, no API-ruling rungs, no `task-close`, no per-session state file; its 16 `impl-*` agents, subagent-driven-development, revising-plans and Executor-line routing are present.
A6. [test, neg, high] Outside the §3 allowlist, `rg -i dforge plugins/dagents` finds nothing.
A7. [test, neg, high] With dagents active, a full session-start, task-brief, next-step and turn-end cycle in a temporary project and home creates nothing named `.dforge`, `docs/dforge`, `~/.dforge` or `~/.claude/dforge`, and reads no `DFORGE_*` variable (a set `DFORGE_BUDGET` changes nothing).
A8. [test, high] The full dagents suite, `claude plugin test plugins/dagents` and `tsc --noEmit -p plugins/dagents` pass.
A9. [test, high] dagents migrate on a fixture dforge 4.x project with a worktree moves `docs/dforge`, `.dforge` and the home config to the dagents names, rewrites `dforge:` references in active plans, ledgers and handoffs, and leaves no dforge-named file behind.
A10. [test, neg, high] The migrate dry run writes nothing, and the move refuses, writing nothing, when `docs/dagents` already exists, the tree is dirty, or a ledger is in flight.
A11. [test, high] With two of dforge, dagents and dflow enabled at any settings scope and both installed, each plugin's SessionStart prints the conflict block naming both and the disable commands with the right scopes, and none of its other hooks writes or prints anything for the rest of the session.
A12. [test, neg, high] The guard never writes a settings file or `installed_plugins.json`, under a conflict or not.
A13. [test, medium] Migrating a project whose documents live in darkmem rewrites each `dforge/…` document to `dagents/…` and deletes the dforge originals only after every copy reads back equal. Q: should migrate touch darkmem at all, or move local files only and tell you to move the darkmem documents by hand?
A14. [test, high] A sibling enabled in user settings but disabled in project settings, or enabled but not installed, is not a conflict; managed `false` overrides every other scope.
A15. [test, high] The standalone check exits 0 with one or no workflow plugin active, exits 3 with two or more, and prints each active plugin with its enabling scope.
A16. [test, high] The three copies of `workflow-guard.mjs` are byte-identical, and `validate-repository.mjs` fails on a fixture where one differs.
A17. [test, neg, high] A session with exactly one workflow plugin active behaves as before: no guard output, no marker, and every existing dforge and dflow suite passes unchanged.
A18. [demo, medium] On Codex with dforge and dagents both enabled, the first turn runs the standalone check and stops with the conflict message. Q: is a skill-text check (no hook) acceptable on Codex, where neither plugin has hooks?
A19. [test, high] Every job of `Validate marketplace` passes for the pushed commit, including all Windows shards, within the existing job timeouts.

## Riskiest assumption

The mechanical rename of the 4.17.1 tree (4,037 `dforge` references in 260
files) yields a working plugin once its suite and `claude plugin test` pass.
Some references are load-bearing in ways a token replacement can break: a
string compared against Claude Code's own output, a skill name a test pins, or
an older-layout translation that must keep saying dforge. unverified — the
plan's first task verifies it, by running the copy's suite before any port and
again right after a trial rename, ahead of the backport.

## Out of scope

- Any change to dforge 5's behaviour beyond the guard and its README.
- Retiring or deprecating dforge 4.x installs in place: an installed dforge
  4.17.1 upgrades to 5.0.0 through the normal update path, and a user who wants
  the 4.x workflow installs dagents and runs its migrate.
- This repository's own `docs/dforge/` records, which belong to its dforge use.
