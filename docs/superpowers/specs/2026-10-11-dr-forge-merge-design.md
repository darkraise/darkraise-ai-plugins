# dr-forge merge — design

**Date:** 2026-10-11
**Plugins:** `plugins/dr-superpowers`, `plugins/dr-cockpit` → `plugins/dr-forge`
**Status:** approved for implementation
**Execution strategy:** sequential — the rename, the cockpit move and the
settings import edit the same manifests, README and skill files.

## Problem

`dr-superpowers` (the development workflow: skills, agents, bash scripts and
hooks, on Claude Code and Codex) and `dr-cockpit` (a Claude Code mod drawing a
pane of the session, the run and the repo) ship separately but are already
coupled: the cockpit reads the workflow's ledger, handoff file and finish
choice, and copies its handoff-budget rule. Their settings live in three
places — cockpit's `pluginConfigs["dr-cockpit@darkraise"]`, the workflow's
`~/.dr-superpowers/config.json` (darkmem-sync) and environment variables such as
`DR_SUPERPOWERS_BUDGET` — and the workflow has no user-facing settings at all.

The owner wants one plugin, **dr-forge**, whose cockpit is the workflow's
interface and whose settings view configures the workflow. This spec covers the
merge and rename with behaviour unchanged, plus the settings foundation. The new
development-process controls are a second spec built on that foundation (see
Out of scope).

## Decisions

- Name: `dr-forge`, version 2.0.0. The `dr-superpowers:` namespace is renamed.
- Settings: one global file, `~/.dr-forge/config.json`, shared by every Claude
  config directory and by Codex.
- Repository paths: write `.forge/` and `docs/forge/`; read `.superpowers/` and
  `docs/superpowers/` when the new path is absent.
- Retirement: `dr-superpowers` and `dr-cockpit` leave both catalogs with no
  stub and no detection of a still-enabled old install. Their settings are
  imported once.

## Layout

```
plugins/dr-forge/
  .claude-plugin/plugin.json   name dr-forge, 2.0.0, "types", no userConfig
  .codex-plugin/plugin.json    name dr-forge, 2.0.0, skills, "hooks": {}
  agents/ criteria/ reference/ skills/ scripts/ LICENSES/   from dr-superpowers
  hooks/hooks.json             modules + the three command hooks
  hooks/cockpit/               register.tsx lib.ts notify.ts svg.ts
  config/schema.mjs            every setting
  types/index.d.ts             from dr-cockpit
  tests/                       dr-superpowers tests, cockpit.test.ts, new tests
  README.md                    one document for workflow and cockpit
```

`hooks/hooks.json`:

```json
{
  "description": "Loads the cockpit mod, injects the dr-forge entry point at session start, persists the transcript path, appends a compaction snapshot, and holds a stop once when a turn that advanced a plan ends without the finishing menu or the next step.",
  "modules": ["./cockpit/register.tsx"],
  "hooks": { "SessionStart": [...], "UserPromptSubmit": [...], "Stop": [...] }
}
```

`claude plugin validate` accepts `modules` and `hooks` in one file, and a
headless `claude -p --plugin-dir` session on Claude Code 2.1.296 ran both a
module's `session.start` hook and a command `SessionStart` hook from one such
file (probed 2026-10-11).

On Codex the manifest's `"hooks": {}` keeps both the mod and the command hooks
out, as today. Codex gets the skills and scripts, and reads the same settings
file.

`plugins/dr-superpowers/` and `plugins/dr-cockpit/` are removed once their
content has moved.

## Namespace

- Every `dr-superpowers:` reference in maintained files becomes `dr-forge:`:
  skills, agents (`dr-forge:impl-sonnet-low` and the rest), criteria,
  reference, scripts, tests, README and the cockpit's prompts.
- `reference/legacy-names.md` adds `dr-superpowers:` as a legacy prefix; its
  tables resolve each suffix to `dr-forge:<suffix>`. It stays the only
  maintained file allowed to spell a legacy prefix.
- The cockpit treats a session as a workflow session when it loaded a skill or
  started an agent under either `dr-forge:` or `dr-superpowers:`. Seat names
  strip either prefix.
- Historical plans, specs, notes and registers are not edited.

## Repository paths

One resolver, implemented once in bash (`scripts/lib/forge-dir.sh`, function
`forge_dir state|docs [root]`) and mirrored in `hooks/cockpit/lib.ts`:

| New path exists | Old path exists | Result |
|---|---|---|
| yes | any | new |
| no | no | new |
| no | yes | old |

`state` maps to `.forge/` / `.superpowers/`; `docs` to `docs/forge/` /
`docs/superpowers/`. Every script that builds either path calls the resolver.
Skills keep naming the new paths (`.forge/…`, `docs/forge/…`) and
`reference/project-state.md` states the fallback rule once; where a skill needs
the actual path of an existing file it takes it from a script's output, never
by spelling the old path. A worktree resolves against its primary checkout, as
the cockpit does today.

This repository's own `docs/superpowers/` stays put and is read through the
fallback.

## Environment variables

New names are read first, old names as a fallback:

| New | Fallback |
|---|---|
| `DR_FORGE_BUDGET` | `DR_SUPERPOWERS_BUDGET` |
| `DR_FORGE_JQ` | `DR_SUPERPOWERS_JQ` |
| `DR_FORGE_SESSION_ID` | `DR_SUPERPOWERS_SESSION_ID` |
| `DR_FORGE_BUDGET_CALLER` | `DR_SUPERPOWERS_BUDGET_CALLER` |
| `DR_FORGE_NOTIFY_URL` | `DR_COCKPIT_NOTIFY_URL` |

Anything the plugin itself exports uses the new name only.

## Settings

### Schema

`config/schema.mjs` default-exports an object keyed by setting name. It is an
ES module rather than JSON because a mod imports only code files; the mod,
`scripts/lib/forge-config.mjs` and `scripts/validate-repository.mjs` all import
it directly (probed 2026-10-11 with `claude plugin validate` and
`claude plugin test`). Each entry has:

- `type`: `boolean`, `number` (with `min`/`max`), `enum` (with `values`) or
  `string`;
- `default`;
- `group`: the settings-view group (`Cockpit`, `Context`, `Notifications`,
  `Workflow`);
- `title` and `description`: the settings-view text;
- `target`: `forge` (stored in `~/.dr-forge/config.json`) or `claude` (stored in
  the session's Claude settings file; no key uses it in this spec);
- `env` (optional): the environment variable that overrides it.

This spec's keys are cockpit's current thirteen options (`handoffTokens`,
`nudgeModel`, `guardAttribution`, `warnAt`, `layout`, `sections`,
`breakdownRows`, `openAtStart`, `limitAlertAt`, `notifyOn`, `notifyAfter`,
`notifyAskAfter`, `notifyDetail`) with their current defaults. `handoffTokens`
carries `env: DR_FORGE_BUDGET`.

### Store

`~/.dr-forge/config.json` holds the schema keys whose values differ from the
default, at the top level, plus one reserved `darkmem` object that is not in the
schema: the existing darkmem mapping (`url`, `api_key_env`, `repos`), edited by
hand as today and never drawn in the settings view. `forge-config` and the
cockpit preserve `darkmem` untouched when they write. Resolution order for a
schema key: environment variable, then file, then schema default. A value that
fails its type is ignored with one warning and the next source wins.

The home directory is `~/.dr-forge/`. `scripts/lib/darkmem-config.mjs` reads
its mapping from `~/.dr-forge/config.json`, or from
`~/.dr-superpowers/config.json` while the new file does not exist (darkmem-sync
may run before anything has imported), and resolves the mirror
(`<home>/mirror/<project>/`) by the resolver table under Repository paths:
`~/.dr-forge/mirror/<project>` when it exists or `~/.dr-superpowers/mirror/<project>`
does not, else the old one. Its `docsRoot` and `workRoot` come from
`forge_dir`'s rule rather than the hardcoded `docs/superpowers` and
`.superpowers`.

- `scripts/forge-config get <key>` prints the resolved value;
  `get --json` prints every resolved value; `set <key> <value>` validates and
  writes atomically (temporary file and rename); `unset <key>` removes it.
  Exit 2 on an unknown key or invalid value.
- The cockpit reads the file at session start and after each of its own
  writes, and writes through the same rules in TypeScript (one module,
  `hooks/cockpit/config.ts`, validated against the schema).
- `.claude-plugin/plugin.json` drops `userConfig`: the settings no longer appear
  in `/config`. The cockpit's settings view and `scripts/forge-config` are the
  two editors.

The Discord webhook and mention stay secrets in the engine store
(`$.store`, keys `notifyUrl` and `notifyMention`), never in the settings file.

### Settings view

The cockpit's settings view is drawn from the schema: groups in schema order,
one row per key, the control chosen by `type`. Rows the view draws today keep
their look and hotkeys. The Discord webhook controls stay as they are.

### One-time import

When `~/.dr-forge/config.json` does not exist, the first of the mod or
`scripts/forge-config` to run creates it from:

1. `pluginConfigs["dr-cockpit@darkraise"].options` in the session's Claude
   settings file (`$CLAUDE_CONFIG_DIR/settings.json`, else
   `~/.claude/settings.json`), keeping values that differ from the default;
2. the `darkmem` object of `~/.dr-superpowers/config.json`, copied verbatim.

The mod additionally copies `notifyUrl` and `notifyMention` from
`<config dir>/plugins/store/dr-cockpit_darkraise-*.json` into its own store
when its own store has no `notifyUrl`. If the file is absent or unreadable,
nothing is copied and the settings view shows no webhook.

Old files are left in place. The import runs once per machine: the first Claude
account to start wins, and another account's cockpit options are not merged.

## Repository changes

- `.claude-plugin/marketplace.json`: `dr-forge` (category `workflow`, the
  merged description and keywords), `dr-status`, the two UI plugins; version
  bumped.
- `.agents/plugins/marketplace.json`: `dr-forge` and the two UI plugins.
- `CLAUDE.md`: the catalog lines name `dr-forge`; only `dr-status` is
  Claude-only; `dr-forge` carries a mod, tested with
  `claude plugin test plugins/dr-forge`; validation names `plugins/dr-forge`.
- `README.md`: one dr-forge section replacing the two, with install and the
  migration note (uninstall the old plugins; settings import once).
- `scripts/validate-repository.mjs`: the name lists; the Codex empty-hooks and
  no-dependencies rules move to `dr-forge`; `dr-forge:<name>` resolves against
  `plugins/dr-forge/skills` and `agents`; the legacy pattern adds
  `dr-superpowers:`, allowed only in `plugins/dr-forge/reference/legacy-names.md`;
  every schema key has `type`, `default`, `group`, `title` and `target`, and
  its default passes its own type.
- `scripts/test-all.mjs`: runs `plugins/dr-forge/tests/*.test.sh` and the
  cockpit test.
- `tests/repository-layout.test.mjs`, `tests/marketplace-smoke.ps1`,
  `docs/testing/dual-client-marketplace-validation.md`: the new plugin set.
- `evals/tiers`: harness code and fixtures (`*.mjs`, `tests/`, `README.md`)
  take the new path and prefix. `results/` and `cases/` are recorded data and
  are not edited; the harness maps the old prefix when it reads them.

## Testing

Sized like the neighbouring tests:

- `tests/forge-dir.test.sh`: the four rows of the resolver table, and a
  worktree resolving against its primary checkout.
- `tests/forge-config.test.sh`: precedence (environment, file, default); `set`
  then `get`; `unset`; an unknown key and an invalid value exit 2 and leave the
  file unchanged; the import from a fixture `settings.json` and a fixture
  `~/.dr-superpowers/config.json`, run against a temporary `HOME`; a second run
  does not import again; a `set` keeps the `darkmem` object byte-for-byte.
- `tests/darkmem-sync.test.sh` (existing): add a case where only
  `~/.dr-superpowers/mirror/<project>` exists and is used, and one where both
  exist and the new one wins.
- `tests/cockpit.test.ts`: the settings view lists every schema key in its
  group; a session that loaded `dr-forge:brainstorming` and one that loaded
  `dr-superpowers:brainstorming` are both workflow sessions; the webhook import
  copies from a fixture store file and skips when one is already set.
- Existing suites pass after the rename with only path and prefix edits.

## Verification

Each command runs with a timeout, and every process it starts is stopped
before the run ends:

1. `node scripts/validate-repository.mjs`
2. `node scripts/test-all.mjs`
3. `claude plugin validate` on the repository root, `plugins/dr-forge` and
   `plugins/dr-status`
4. `claude plugin test plugins/dr-forge`
5. Manual: `claude --plugin-dir plugins/dr-forge` in a scratch repository with
   the old plugins disabled. The cockpit pane opens; the session-start context
   names `dr-forge:using-superpowers`; a turn that writes a ledger and ends
   without the next step is held by the Stop hook; the settings view shows the
   imported values.

## Out of scope

The second spec, built on this schema, adds the development-process controls:
skipping the finish question in favour of a default action and its timeout; the
Codex lane on, off or auto; a strict or relaxed handoff budget (relaxed
finishes the current plan phase, under a hard ceiling below auto-compaction);
default execution strategy and mode; process-depth bias and per-section
approval; and Claude's `autoCompactWindow` and `autoCompactEnabled`, written
to the session's own Claude settings file (`target: claude`).

Also out of scope: moving this repository's `docs/superpowers/`, and renaming
`dr-status`.
