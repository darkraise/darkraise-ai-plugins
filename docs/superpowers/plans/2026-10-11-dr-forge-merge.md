# dr-forge merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.
> **External executors:** codex

**Goal:** Merge `dr-cockpit` into `dr-superpowers` as one plugin, `dr-forge` 2.0.0, with one settings file the cockpit edits and the scripts read, and behaviour otherwise unchanged.

**Architecture:** `plugins/dr-superpowers` is renamed to `plugins/dr-forge` and the cockpit's hooks module moves into it under `hooks/cockpit/`, loaded from the same `hooks/hooks.json` as the command hooks. Settings are declared once in `config/schema.mjs`, stored in `~/.dr-forge/config.json`, and read by the cockpit (through a `$.state` atom it rewrites on save) and by `scripts/forge-config`. Repository paths move to `.forge/` and `docs/forge/`, resolved through one rule that keeps a pre-2.0 `.superpowers/` or `docs/superpowers/` in use where only that exists.

**Tech Stack:** Bash, Node.js 22 (ES modules, `node:test`), TypeScript/TSX hooks module for the Claude Code mod API (2.1.295+), `jq`, git.

**Spec:** `docs/superpowers/specs/2026-10-11-dr-forge-merge-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — 7 of 20 tasks are heavy and are delegated with the 10 Executor tasks; Tasks 9, 14 and 20 are self-implemented (highest total 4), raised to high because tasks are delegated; Task 20 needs your human partner at a terminal.

**Plan review:** 2026-10-11 — dr-superpowers:judge-opus — executability 15 / coherence 15 / coverage 13 / assumptions 14 (round 2)

**Parallelism:** sequential — the rename, the cockpit move and the settings work edit the same manifests, README and skill files; the spec's Execution strategy is sequential.

## Global Constraints

- Plugin name `dr-forge`, directory `plugins/dr-forge`, version `2.0.0` in both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`; the Claude marketplace version goes from `0.5.0` to `0.6.0`.
- The Codex manifest keeps `"hooks": {}`; the cockpit stays Claude-only.
- Never edit historical files: `docs/superpowers/plans/`, `docs/superpowers/specs/`, `docs/superpowers/notes/`, `docs/superpowers/registers/` (other than this plan's register through `scripts/register`), `evals/tiers/results/`, `evals/tiers/cases/`. Never touch the untracked `docs/superpowers/notes/2026-09-23-opus-5-5-effort-eval-design.md`.
- Commits: `<type>(<scope>): <subject>` (subject ≤ 50 chars, imperative), author `Darkraise <quangtc94@gmail.com>`, no `Co-Authored-By`, `Claude-Session` or "Generated with" lines.
- Scripts and plan steps use `grep`, never `rg` (here `rg` is a shell function, not a binary).
- Bash must keep running under Git Bash on Windows (CI runs Windows shards): no GNU-only flags in scripts, `cygpath` handling in tests as the neighbouring tests do.
- Bound every test and CLI run with `timeout`, and stop every process a step starts.
- Mod code (`hooks/cockpit/*.ts*`): `$` is passed only to functions declared at the top of the file or imported from another file; a hook is an inline function or a top-level function, never a `const` closure inside `register`. Run `claude plugin test plugins/dr-forge` after every change to the mod.
- Path rule, everywhere it is implemented: use the new directory (`.forge`, `docs/forge`) unless it does not exist and the pre-2.0 one (`.superpowers`, `docs/superpowers`) does.
- Environment names: the `DR_FORGE_*` name is read first and the pre-2.0 name only when the new one is unset or empty (`DR_FORGE_BUDGET`/`DR_SUPERPOWERS_BUDGET`, `DR_FORGE_JQ`/`DR_SUPERPOWERS_JQ`, `DR_FORGE_BUDGET_CALLER`/`DR_SUPERPOWERS_BUDGET_CALLER`, `DR_FORGE_SESSION_ID`/`DR_SUPERPOWERS_SESSION_ID`, `DR_FORGE_NOTIFY_URL`/`DR_COCKPIT_NOTIFY_URL`). The plugin only ever sets the new names.
- Do not change `plugins/dr-status`, `plugins/dcc-darkraise-ui` or `plugins/dcc-darkraise-win32ui`.

## Contracts

- **Directory and namespace.** `plugins/dr-forge`; every maintained reference to a skill or agent is `dr-forge:<name>`. `dr-superpowers:` is a legacy prefix that only `plugins/dr-forge/reference/legacy-names.md`, `plugins/dr-forge/hooks/cockpit/lib.ts` and `plugins/dr-forge/tests/cockpit.test.ts` may spell.
- **`scripts/lib/forge-dir.sh`.** `forge_dir state|docs [ROOT]` prints `ROOT/.forge` or `ROOT/.superpowers` (state), `ROOT/docs/forge` or `ROOT/docs/superpowers` (docs) by the path rule; ROOT defaults to `.`; another kind prints an error and returns 2. `forge_dir_rel state|docs [ROOT]` prints the same path relative to ROOT (`.forge`, `docs/superpowers`, …).
- **`scripts/forge-path`.** `forge-path state|docs [RELATIVE]` prints `forge_dir` of the current checkout's top level (`git rev-parse --show-toplevel`, else the working directory), with `/RELATIVE` appended when given; exit 2 on usage. Skills locate files with it.
- **`<state>` and `<docs>`.** In skills, references, criteria and agents, the placeholders for the repository's state and docs directories; `bash <plugin-root>/scripts/forge-path state|docs [RELATIVE]` resolves them.
- **`scripts/lib/forge-env.sh`.** Sourcing it sets `DR_FORGE_BUDGET`, `DR_FORGE_JQ` and `DR_FORGE_BUDGET_CALLER` from their pre-2.0 names when unset or empty. Sourced by `scripts/lib/context.sh` and `scripts/lib/snapshot.sh`.
- **`config/schema.mjs`.** `export default { <key>: SettingSpec, … }` where SettingSpec is `{ type: 'boolean'|'number'|'enum'|'string', default, group: 'Cockpit'|'Context'|'Notifications'|'Workflow', title, description, target: 'forge'|'claude', env?, min?, max?, step?, values? }`. The key `darkmem` is reserved and never a schema key.
- **`~/.dr-forge/config.json`.** A JSON object: schema keys whose value differs from the default, plus the reserved `darkmem` object (`url`, `api_key_env`, `repos`), which every writer keeps unchanged.
- **`scripts/forge-config`.** `get KEY` prints the resolved value; `get --json` prints every resolved value as one JSON object; `set KEY VALUE`; `unset KEY`. Every command first runs the one-time import when the file is absent. Exit 0 success, 2 usage / unknown key / invalid value, 1 I/O failure or a file that is not a JSON object. Resolution: the key's `env` variable (for `DR_FORGE_BUDGET`, then `DR_SUPERPOWERS_BUDGET`), then the file, then the default.
- **`scripts/lib/forge-config.mjs` exports:** `configPath(env)`, `isValid(spec, value)`, `fromText(spec, text)`, `readFile(file)`, `resolve(env, warn)`, `setValue(key, text, env)`, `unsetValue(key, env)`, `importLegacy(env)`, `main(argv, env, out)`, `SettingError`.
- **`hooks/cockpit/config.ts` exports:** types `SettingValue`, `SettingSpec`, `Schema`, `SettingsFile`, `SettingRow`; `SCHEMA`; `isValidSetting(spec, value)`; `settingFromText(spec, text)`; `resolveSettings(schema, file, env)`; `settingProblems(schema, file, env)` (one line per ignored value); `settingWritten(schema, file, key, value)`; `importedSettings(schema, claudeSettings, oldForge)`; from Task 16 also `schemaRows(schema, values, custom)`.
- **Cockpit state.** `S.settingProblems: string[]` (Task 15) and `S.stateLeaf: string` (Task 17) beside the atom. Atom `settings` (`{ plugin: 'dr-forge', key: 'settings' }`, value `Record<string, boolean | number | string> | null`) declared in `plugins/dr-forge/types/index.d.ts`; top-level `liveFrom(values)`, `live($)`, `applyNotify(o)` in `register.tsx` (Task 14); `configFile($)`, `readSettingsFile($, path)`, `applySettings($, file)`, `loadSettings($)` (Task 15).
- **`scripts/lib/darkmem-config.mjs` exports (Task 10):** `forgeHome(env)`, `preferNew(next, old)`, `forgeDir(kind, root)` with kind `'docs'|'state'`, alongside the existing `resolveMode`, `runKey`, `primaryRoot`, `ConfigError`.
- **`scripts/validate-repository.mjs` exports:** `validateRepository(root)` (sync, as today) and `validateSchema(root)` (async, Task 11); the CLI prints both lists.

## Assumptions (evidence)

- One `hooks/hooks.json` holding `"modules"` and command `"hooks"` validates and loads both at runtime: scratch plugin, `claude plugin validate` and headless `claude -p --plugin-dir` on Claude Code 2.1.296, 2026-10-11 (both a module `session.start` hook and a command `SessionStart` hook wrote their marker files).
- A mod imports `../../config/schema.mjs` from `hooks/cockpit/`; a mod cannot import `.json`: probe with `claude plugin validate` and `claude plugin test` on 2026-10-11; the mod reference (`plugin-authoring` skill, reference.md line 14) lists the loadable suffixes.
- `$.fs.write` writes a whole file with no rename, `$.settings.read({ source: 'user' })` is read-only, `$.env.get` takes only a string literal, `$.store` is per plugin: engine types for 2.1.296 (`fs`, `settings`, `env`, `store` nouns), read 2026-10-11. The cockpit's own writes are therefore not atomic; `forge-config.mjs` writes atomically.
- Saving an option today reloads the mod only because `$.config.set` writes the mod's own `/config` row; nothing else reloads it, hence the settings atom in Tasks 14-15: `plugins/dr-cockpit/hooks/register.tsx` `setOption` (around line 2278) and its session.start comment.
- The test kit answers `$.fs` and `$.env` only through the test's own hooks and feeds `test(name, { options })` only into `userConfig`: mod reference.md line 81; fixture `world()` and `signedIn()` in `plugins/dr-cockpit/tests/cockpit.test.ts` (lines 140-260).
- dr-cockpit's store file is `<config dir>/plugins/store/dr-cockpit_darkraise-<hash>.json`, a flat object keyed by store key (`notifyUrl`, `notifyMention`): key paths inspected with `jq` in `~/.claude` and `~/.claude-alt`, 2026-10-11.
- `scripts/test-all.mjs` runs the cockpit test only where a `claude` CLI answers outside Windows (Task 3); CI's Linux job has no CLI on PATH and keeps its own pinned-CLI step (`.github/workflows/validate.yml`), so the test still runs there.
- Bash tests whose fixtures already create `.superpowers/` or `docs/superpowers/` keep passing unchanged under the path rule; only tests that expect a fresh checkout to get `.superpowers/` change: path rule, and `grep -rlE '\.superpowers|docs/superpowers' plugins/dr-superpowers/tests` (25 files), 2026-10-11.
- Cockpit baseline: `claude plugin test plugins/dr-cockpit` → 100 pass, 0 fail (2026-10-11).
- `scripts/forge-config` running before the mod writes the settings file first, so the mod's webhook import keys off a store flag rather than the file's absence (Task 16).
- `forge_dir` takes the root it resolves under; which root (primary checkout or worktree) stays each caller's existing choice, so a worktree still resolves against its primary checkout wherever it did, as `repo-audit.test.sh` and `snapshot.test.sh` already check. The spec's worktree case is covered there rather than in `forge-dir.test.sh`.
- The spec's manual check (Verification step 5) needs an interactive session, so it is Task 20, run inline by the controller with your human partner; the Stop hook's hold is covered by `tests/turn-end.test.sh` rather than by hand. The module-and-command-hook loading it guards was probed headlessly on 2026-10-11.
- The workflow's Bash budget keeps reading only `DR_FORGE_BUDGET` (or `DR_SUPERPOWERS_BUDGET`) and its rule, not the settings file's `handoffTokens`, exactly as today's scripts ignore the cockpit's option: Spec 1 changes no behaviour, and joining the two is register row 5 ("Budget and handoff"), deferred to Spec 2.
- The tier-eval harness replays historical snapshots: `evals/tiers/build-case.mjs:18` creates `.superpowers/sdd/eval` inside each one, so the path rule keeps every replayed script on the old directory, and `evals/tiers/lib/claude.mjs:13` loads agents by file name, so a brief's `dr-superpowers:` names are only text (resolved by `legacy-names.md`). Task 3 changes only the harness's own plugin path and slug rule.
- The mod has no exclusive create, so the cockpit's first-run import (Task 16) can race a `forge-config` started in the same instant; both import the same machine's pre-2.0 settings and the later write wins. `forge-config` itself imports through `fs.linkSync`, so two CLI runs never both land (Task 12 tests it).
- Plan review round 2 scored coverage 13 (borderline): its one Important finding (skills writing new-path documents) was fixed by Task 18's placeholders, and the remaining Minor items were fixed or are the accepted mod-side import race above; no further round runs at the cap.
- A pre-2.0 tier-eval manifest names a start commit without `plugins/dr-forge`, so `evals/tiers/run-grid.mjs` refuses it after the rename; a new repetition rebuilds the manifest (Task 3 documents it).

## Task index

1. Rename the plugin directory and namespace
2. Distribution contract for dr-forge
3. Test runner, CI loop and eval harness paths
4. Move the cockpit into dr-forge
5. Cockpit accepts the pre-2.0 prefix and names
6. Bash environment names with fallbacks
7. The forge_dir resolver
8. Scripts resolve the state directory
9. Scripts resolve the docs directory
10. darkmem home, config fallback, mirror and roots
11. Settings schema and its validator check
12. The forge-config command
13. Cockpit settings module
14. Cockpit options read at runtime
15. Cockpit options from the settings file
16. Settings view drawn from the schema, and first-run import
17. Cockpit reads the state directory through the rule
18. Skills and references resolve the directories
19. Documentation and dr-cockpit retirement
20. Manual runtime check

---

### Task 1: Rename the plugin directory and namespace

**Files:**
- Modify (move): `plugins/dr-superpowers/` → `plugins/dr-forge/` (every file but `LICENSES/` and `reference/legacy-names.md` is rewritten by one command)

**Interfaces:**
- Consumes: none
- Produces: Contracts → **Directory and namespace** (except legacy-names.md, which Task 2 rewrites)

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 0 - spec 0 - coupling 3 - risk 2 = 5

- [ ] **Step 1: Move the directory**

```bash
git mv plugins/dr-superpowers plugins/dr-forge
```

- [ ] **Step 2: Rename the plugin name and namespace inside it**

The first substitution fixes the two possessives (`dr-superpowers' rule`); the second skips `~/.dr-superpowers` (Task 10 owns it) and dated file names such as `2026-09-11-dr-superpowers-fork-design.md`, which cite historical specs and plans that keep their names. `DR_SUPERPOWERS_*` and `.superpowers` paths do not match and are left for Tasks 6-9.

```bash
grep -rlZ --exclude-dir=LICENSES -e 'dr-superpowers' plugins/dr-forge \
  | grep -zv '/reference/legacy-names\.md$' \
  | xargs -0 perl -pi -e "s/dr-superpowers' /dr-forge's /g; s/(?<!\.)(?<!\d-)dr-superpowers/dr-forge/g"
```

- [ ] **Step 3: Check nothing else spells the old name**

Run: `grep -rn --exclude-dir=LICENSES 'dr-superpowers' plugins/dr-forge | grep -v '/reference/legacy-names\.md:' | grep -v '\.dr-superpowers' | grep -vE '[0-9]{4}-[0-9]{2}-[0-9]{2}-dr-superpowers'`
Expected: no output (the dated historical file names are the only other matches, and they stay). Then `grep -n '"name"\|"version"' plugins/dr-forge/.claude-plugin/plugin.json plugins/dr-forge/.codex-plugin/plugin.json` shows `"name": "dr-forge"` in both (versions change in Task 2).

- [ ] **Step 4: Run the plugin's suites**

`scripts/test-all.mjs` still points at the old path until Task 3, so run them directly:

```bash
fails=0; for t in plugins/dr-forge/tests/*.test.sh; do timeout 600 bash "$t" > /dev/null 2>&1 || { echo "FAIL $t"; fails=$((fails + 1)); }; done; echo "failures: $fails"
```

Expected: `failures: 0`. A failing suite is rerun alone (`timeout 600 bash <file>`) to read its output; a failure caused by a name the rename missed is fixed in the plugin, never by restoring `dr-superpowers`.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dr-superpowers plugins/dr-forge
git commit -m "refactor(dr-forge): rename dr-superpowers to dr-forge"
```

### Task 2: Distribution contract for dr-forge

**Files:**
- Modify: `plugins/dr-forge/reference/legacy-names.md`
- Modify: `scripts/validate-repository.mjs`
- Modify: `.claude-plugin/marketplace.json`, `.agents/plugins/marketplace.json`
- Modify: `plugins/dr-forge/.claude-plugin/plugin.json`, `plugins/dr-forge/.codex-plugin/plugin.json`
- Test: `tests/repository-layout.test.mjs`

**Interfaces:**
- Consumes: Contracts → **Directory and namespace** (Task 1)
- Produces: the catalogs and validator rules every later task's `node scripts/validate-repository.mjs` run checks

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

Rename the plugin throughout `tests/repository-layout.test.mjs`:

```bash
perl -pi -e 's/dr-superpowers/dr-forge/g' tests/repository-layout.test.mjs
```

That renames every path (including the bundled-link test's `` `plugins${sep}dr-forge${sep}skills…` `` expectation), the placeholder fixture (`dr-forge:impl-<model>-<effort>`, `dr-forge:judge-fable`, `dr-forge:writing-plans`, which must keep resolving) and the unresolved-reference row (`see dr-forge:no-such-skill`, `/unresolved dr-forge reference no-such-skill/`). Then:

- The first test becomes `test('Claude offers four maintained plugins', …)` asserting `['dcc-darkraise-ui', 'dcc-darkraise-win32ui', 'dr-forge', 'dr-status']` (after the rename it still lists `dr-cockpit`).
- The Codex test's list is now `['dcc-darkraise-ui', 'dcc-darkraise-win32ui', 'dr-forge']`; check it.
- Add this row to the broken-contract table, after `'legacy name reference'` — the one intentional old-name fixture in the file:

```js
    ['pre-2.0 plugin prefix', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dr-forge/reference/stray.md'), 'see dr-superpowers:brainstorming\n'); }, /legacy plugin-name reference/],
```

Check: `grep -n 'dr-cockpit\|dr-superpowers' tests/repository-layout.test.mjs` prints only that row.

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 node --test tests/repository-layout.test.mjs`
Expected: FAIL on catalog membership and the validator rows.

- [ ] **Step 3: Rewrite legacy-names.md**

```bash
perl -pi -e 's/^Plans, ledgers, and notes written before dr-superpowers 1\.2\.0 name skills and$/Plans, ledgers, and notes written before dr-forge 2.0.0 name skills and/; s/(?<!\.)(?<!\d-)dr-superpowers/dr-forge/g unless /^  `dcc-superpower-companions:`, or `dr-superpowers:`\.$/' plugins/dr-forge/reference/legacy-names.md
```

The Rule bullet spans lines 12-13 (`- Resolve by suffix, whatever old prefix precedes it: \`superpowers:\`,` / `  \`dcc-superpower-companions:\`, or \`dr-superpowers:\`.`); the guard keeps its second line, which already lists the new legacy prefix. Check: `grep -n 'dr-superpowers' plugins/dr-forge/reference/legacy-names.md` prints exactly line 13 (verified on a copy, 2026-10-11).

- [ ] **Step 4: Update the validator**

In `scripts/validate-repository.mjs`:

```js
const names = ['dcc-darkraise-ui', 'dcc-darkraise-win32ui', 'dr-forge', 'dr-status'];
const claudeOnly = ['dr-status'];
```

Replace the two `entry.name === 'dr-superpowers'` checks and their message with `dr-forge`:

```js
        if (entry.name === 'dr-forge' && (JSON.stringify(manifest.hooks) !== '{}')) errors.push(`${entry.name}: explicit empty Codex hooks required`);
```

```js
      if (client === 'claude' && entry.name === 'dr-forge' && manifest.dependencies?.length) {
        errors.push('dr-forge: standalone plugin must not declare dependencies');
      }
```

Replace the legacy block's pattern, allowance and resolution:

```js
  const legacyPattern = /(?:^|[^\w-])superpowers:|dr-superpowers:|dcc-superpower-companions:/;
  const legacyAllowed = new Set(['plugins/dr-forge/reference/legacy-names.md']);
```

```js
          for (const match of line.matchAll(/dr-forge:([a-z0-9-]+)/g)) {
            // A name followed by `<` is a template placeholder such as impl-<model>-<effort>.
            if (line[match.index + match[0].length] === '<') continue;
            const name = match[1];
            if (!existsSync(resolve(root, 'plugins/dr-forge/skills', name)) &&
                !existsSync(resolve(root, 'plugins/dr-forge/agents', `${name}.md`))) {
              errors.push(`${rel}:${index + 1}: unresolved dr-forge reference ${name}`);
            }
          }
```

- [ ] **Step 5: Update the manifests and catalogs**

Both `plugins/dr-forge/.claude-plugin/plugin.json` and `plugins/dr-forge/.codex-plugin/plugin.json`: `"version": "2.0.0"` and

```json
  "description": "Brainstorm, plan and execute with scored tasks, tiered implementers, criteria-based review and an external Codex executor; on Claude Code a cockpit pane shows the session, the run, context against its handoff budget, usage limits and the repo, with Discord notifications and an attribution guard. A standalone fork of superpowers 6.3.0.",
```

Add `"mod"`, `"context-window"`, `"handoff"`, `"rate-limits"`, `"discord"` to the end of the Claude manifest's `keywords`.

`.claude-plugin/marketplace.json`: `"version": "0.6.0"`; remove the `dr-superpowers` and `dr-cockpit` entries and add, first in `plugins`:

```json
    {
      "name": "dr-forge",
      "source": "./plugins/dr-forge",
      "description": "Brainstorm, plan and execute with scored tasks, tiered implementers, criteria-based review and an external Codex executor; on Claude Code a cockpit pane shows the session, the run, context against its handoff budget, usage limits and the repo, with Discord notifications and an attribution guard. A standalone fork of superpowers 6.3.0.",
      "category": "workflow",
      "keywords": [
        "superpowers",
        "subagents",
        "planning",
        "effort",
        "model-selection",
        "verification",
        "code-review",
        "codex",
        "external-executors",
        "mod",
        "context-window",
        "handoff",
        "rate-limits",
        "discord"
      ]
    },
```

`.agents/plugins/marketplace.json`: the `dr-superpowers` entry becomes

```json
    {
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_USE"
      },
      "name": "dr-forge",
      "category": "Development",
      "source": {
        "source": "local",
        "path": "./plugins/dr-forge"
      }
    },
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `timeout 120 node --test tests/repository-layout.test.mjs && timeout 60 node scripts/validate-repository.mjs`
Expected: all tests pass; the validator prints `Repository catalogs, manifests, versions, and bundled links are valid.`

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-forge/reference/legacy-names.md scripts/validate-repository.mjs .claude-plugin/marketplace.json .agents/plugins/marketplace.json plugins/dr-forge/.claude-plugin/plugin.json plugins/dr-forge/.codex-plugin/plugin.json tests/repository-layout.test.mjs
git commit -m "feat(dr-forge): publish dr-forge 2.0.0 in both catalogs"
```

### Task 3: Test runner, CI loop and eval harness paths

**Files:**
- Modify: `scripts/test-all.mjs`, `.github/workflows/validate.yml`
- Modify: `evals/tiers/lib/sh.mjs`, `evals/tiers/run-grid.mjs`, `evals/tiers/build-manifest.mjs`, `evals/tiers/README.md`, `evals/tiers/lib/cases.mjs`
- Test: `evals/tiers/tests/fixture.mjs`, `evals/tiers/tests/manifest.test.mjs`, `evals/tiers/tests/grid.test.mjs`, `evals/tiers/tests/cases.test.mjs`

**Interfaces:**
- Consumes: Contracts → **Directory and namespace** (Task 1)
- Produces: `node scripts/test-all.mjs` runs `plugins/dr-forge/tests/*.test.sh`

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

In `evals/tiers/tests/cases.test.mjs` the slug test becomes:

```js
test('slug drops the date and the plugin prefix', () => {
  assert.deepEqual(
    [slug('docs/superpowers/plans/2026-09-15-dr-superpowers-review-routing.md'), slug('docs/forge/plans/2026-11-01-dr-forge-settings.md'), slug(PLAN)],
    ['review-routing', 'settings', 'fixture'],
  );
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 120 node --test evals/tiers/tests/cases.test.mjs`
Expected: FAIL — `dr-forge-settings` is not stripped.

- [ ] **Step 3: Point everything at the new path**

- `evals/tiers/lib/cases.mjs` `slug`: `.replace(/^dr-(?:superpowers|forge)-/, '')`. Leave the comment above (line 18) as it is: it describes the plans' history.
- `evals/tiers/lib/sh.mjs`: `export const PLUGIN = resolve(REPO, 'plugins/dr-forge');`
- `evals/tiers/run-grid.mjs` lines 33-34 and `evals/tiers/build-manifest.mjs` lines 12-13: `plugins/dr-superpowers` → `plugins/dr-forge` (both the git pathspec and the message).
- `evals/tiers/tests/fixture.mjs`: `'**Implementer:** dr-forge:impl-sonnet-low'` and `'plugins/dr-forge/marker.txt'`; `manifest.test.mjs` and `grid.test.mjs`: every `plugins/dr-superpowers` → `plugins/dr-forge`, including the regexes (`/plugins\/dr-forge has uncommitted changes/`).
- `evals/tiers/README.md`: line 3 `a dr-forge assignment row`; line 33 `2 when \`plugins/dr-forge\` differs from the manifest's start commit.` and add after that paragraph: `A manifest built before dr-forge 2.0.0 names a start commit without \`plugins/dr-forge\`, so \`run-grid.mjs\` refuses it; build a new manifest for a new repetition.` Leave line 6's spec path unchanged.
- `scripts/test-all.mjs`: both `plugins/dr-superpowers/tests` → `plugins/dr-forge/tests`, and the cockpit test joins the jobs when a `claude` CLI is on PATH (CI's Linux job has none and keeps its own pinned-CLI step; Windows cannot spawn `claude.cmd` without a shell). `spawnSync` is already imported; before `const jobs = [` add:

```js
// The cockpit's tests need the claude CLI; CI runs them in their own pinned-CLI step.
const hasClaude = !options.list && process.platform !== 'win32' && spawnSync('claude', ['--version'], { stdio: 'ignore', timeout: 5000 }).status === 0;
```

  and as the last entry of `jobs`: `...(hasClaude ? [['claude', ['plugin', 'test', 'plugins/dr-forge'], 300]] : []),`
- `.github/workflows/validate.yml`: `for plugin in dr-status dr-forge dcc-darkraise-ui dcc-darkraise-win32ui; do`.

Run: `grep -rn 'dr-superpowers' scripts/test-all.mjs .github/workflows/validate.yml evals/tiers --include='*.mjs' --include='*.yml' --include='README.md' | grep -v '/results/\|/cases/'`
Expected: only `evals/tiers/lib/cases.mjs` (the line-18 comment and the slug regex), `evals/tiers/tests/cases.test.mjs` (the historical `2026-09-15-dr-superpowers-review-routing.md` slug fixture, kept on purpose) and the README's line-6 spec path.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test evals/tiers/tests/*.test.mjs && timeout 30 node scripts/test-all.mjs --list | grep -c 'plugins/dr-forge/tests'`
Expected: all eval tests pass; the count is the number of `plugins/dr-forge/tests/*.test.sh` files (`ls plugins/dr-forge/tests/*.test.sh | wc -l`).

- [ ] **Step 5: Commit**

```bash
git add scripts/test-all.mjs .github/workflows/validate.yml evals/tiers/lib evals/tiers/run-grid.mjs evals/tiers/build-manifest.mjs evals/tiers/README.md evals/tiers/tests
git commit -m "chore(dr-forge): point runners and evals at dr-forge"
```

### Task 4: Move the cockpit into dr-forge

**Files:**
- Modify (move): `plugins/dr-cockpit/hooks/{register.tsx,lib.ts,notify.ts,svg.ts}` → `plugins/dr-forge/hooks/cockpit/`
- Modify (move): `plugins/dr-cockpit/tests/cockpit.test.ts` → `plugins/dr-forge/tests/cockpit.test.ts`
- Modify (move): `plugins/dr-cockpit/types/index.d.ts` → `plugins/dr-forge/types/index.d.ts`
- Modify: `plugins/dr-forge/hooks/hooks.json`, `plugins/dr-forge/.claude-plugin/plugin.json`, `.github/workflows/validate.yml`
- Delete: `plugins/dr-cockpit/.claude-plugin/plugin.json`, `plugins/dr-cockpit/hooks/hooks.json` (the README stays until Task 19)

**Interfaces:**
- Consumes: Contracts → **Directory and namespace** (Task 1)
- Produces: the cockpit at `plugins/dr-forge/hooks/cockpit/`, its state contract under `'dr-forge'`, its test at `plugins/dr-forge/tests/cockpit.test.ts`

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Move the files**

```bash
mkdir -p plugins/dr-forge/hooks/cockpit plugins/dr-forge/types
git mv plugins/dr-cockpit/hooks/register.tsx plugins/dr-cockpit/hooks/lib.ts plugins/dr-cockpit/hooks/notify.ts plugins/dr-cockpit/hooks/svg.ts plugins/dr-forge/hooks/cockpit/
git mv plugins/dr-cockpit/tests/cockpit.test.ts plugins/dr-forge/tests/cockpit.test.ts
git mv plugins/dr-cockpit/types/index.d.ts plugins/dr-forge/types/index.d.ts
git rm -q plugins/dr-cockpit/.claude-plugin/plugin.json plugins/dr-cockpit/hooks/hooks.json
```

- [ ] **Step 2: Fix the imports and the names**

```bash
perl -pi -e "s{from '\.\./types'}{from '../../types'}g" plugins/dr-forge/hooks/cockpit/register.tsx plugins/dr-forge/hooks/cockpit/lib.ts
perl -pi -e "s{from '\.\./hooks/(lib|notify|svg|register)'}{from '../hooks/cockpit/\$1'}g" plugins/dr-forge/tests/cockpit.test.ts
perl -pi -e 's/dr-cockpit/dr-forge/g; s/(?<!\.)dr-superpowers/dr-forge/g' plugins/dr-forge/hooks/cockpit/*.ts plugins/dr-forge/hooks/cockpit/*.tsx plugins/dr-forge/tests/cockpit.test.ts plugins/dr-forge/types/index.d.ts
```

This renames the state atoms, the pane id, toasts, `config.set` keys (`dr-forge.<key>`) and the `PluginState` key together, so the test expectations move with them. `DR_COCKPIT_NOTIFY_URL` is upper case and stays (Task 5 adds the new name). Check: `grep -rn 'dr-cockpit\|dr-superpowers' plugins/dr-forge/hooks plugins/dr-forge/tests/cockpit.test.ts plugins/dr-forge/types` → no output.

- [ ] **Step 3: Load the module beside the command hooks**

`plugins/dr-forge/hooks/hooks.json` becomes:

```json
{
  "description": "Loads the cockpit mod, injects the dr-forge entry point at session start, persists the session's transcript path for budget tooling, appends a compaction snapshot after compaction, and holds a stop once when a turn that advanced a plan ends without the finishing menu or the next step.",
  "modules": ["./cockpit/register.tsx"],
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh\"",
            "shell": "bash",
            "async": false
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/turn-start.sh\"",
            "shell": "bash",
            "async": false
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/turn-end.sh\"",
            "shell": "bash",
            "async": false
          }
        ]
      }
    ]
  }
}
```

In `plugins/dr-forge/.claude-plugin/plugin.json` add, after `"keywords"`, `"types": "./types/index.d.ts"` and the whole `"userConfig"` object copied verbatim from `git show HEAD:plugins/dr-cockpit/.claude-plugin/plugin.json` (Task 15 removes it again; until then the cockpit keeps reading `/config`).

- [ ] **Step 4: Move the CI mod step**

In `.github/workflows/validate.yml`: the loop becomes `for plugin in dr-status dcc-darkraise-ui dcc-darkraise-win32ui; do` (the old pinned CLI predates mods), and the mod step becomes:

```yaml
      # Mods (hooks modules) need a newer CLI than the pinned validator above.
      - name: Validate and test dr-forge
        timeout-minutes: 3
        run: |
          timeout 60s npx --yes @anthropic-ai/claude-code@2.1.295 plugin validate plugins/dr-forge
          timeout 90s npx --yes @anthropic-ai/claude-code@2.1.295 plugin test plugins/dr-forge
```

- [ ] **Step 5: Run the checks**

Run: `timeout 60 claude plugin validate plugins/dr-forge && timeout 300 claude plugin test plugins/dr-forge && timeout 60 node scripts/validate-repository.mjs`
Expected: validation passes (warnings allowed); `100 pass, 0 fail`; the repository validator prints its valid line.

Then the same two checks on the release CI pins, which the 2026-10-11 probes (2.1.296) did not cover:

```bash
timeout 300 npx --yes @anthropic-ai/claude-code@2.1.295 plugin validate plugins/dr-forge
timeout 300 npx --yes @anthropic-ai/claude-code@2.1.295 plugin test plugins/dr-forge
```

Expected: both pass. If 2.1.295 refuses `modules` beside `hooks` in one `hooks.json`, stop and report it: the remedy (moving the command hooks into `plugin.json`, or raising the CI pin to 2.1.296) is a decision for the controller, not this task.

- [ ] **Step 6: Commit**

```bash
git add -A plugins/dr-cockpit plugins/dr-forge .github/workflows/validate.yml
git commit -m "feat(dr-forge): move the cockpit mod into dr-forge"
```

### Task 5: Cockpit accepts the pre-2.0 prefix and names

**Files:**
- Modify: `plugins/dr-forge/hooks/cockpit/lib.ts`, `plugins/dr-forge/hooks/cockpit/register.tsx`
- Modify: `scripts/validate-repository.mjs`, `plugins/dr-forge/reference/legacy-names.md`
- Test: `plugins/dr-forge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: Task 4's cockpit files
- Produces: Contracts → **Directory and namespace** (the two cockpit files allowed to spell `dr-superpowers:`)

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 2 - spec 1 - coupling 0 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

Add `isSuperpowers` to the `../hooks/cockpit/lib` import list in `plugins/dr-forge/tests/cockpit.test.ts`, and add near the other `lib` unit tests:

```ts
test('a dr-forge and a pre-2.0 dr-superpowers name both mark a workflow session', () => {
  expect(isSuperpowers('dr-forge:brainstorming')).toBe(true)
  expect(isSuperpowers('dr-superpowers:brainstorming')).toBe(true)
  expect(isSuperpowers('feature-dev:code-reviewer')).toBe(false)
})
```

Find the test that sets `DR_COCKPIT_NOTIFY_URL` in its `env` (`grep -n 'DR_COCKPIT_NOTIFY_URL' plugins/dr-forge/tests/cockpit.test.ts`) and add two copies beside it with the same setup and assertions: one whose env sets only `DR_FORGE_NOTIFY_URL` (same webhook, same outcome), and one that sets `DR_FORGE_NOTIFY_URL` to the webhook and `DR_COCKPIT_NOTIFY_URL` to a different valid webhook (`https://discord.com/api/webhooks/2/old`), asserting the message goes to the `DR_FORGE_NOTIFY_URL` one.

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 300 claude plugin test plugins/dr-forge`
Expected: FAIL — `dr-superpowers:brainstorming` is not counted, and `DR_FORGE_NOTIFY_URL` is ignored.

- [ ] **Step 3: Implement**

`lib.ts`:

```ts
/** Whether a subagent type or skill name belongs to dr-forge, under its name or the pre-2.0 dr-superpowers. */
export function isSuperpowers(name: string): boolean {
  return name.startsWith('dr-forge:') || name.startsWith('dr-superpowers:')
}
```

In the budget comment at the top of `lib.ts`, `DR_SUPERPOWERS_BUDGET` becomes `DR_FORGE_BUDGET (or the pre-2.0 DR_SUPERPOWERS_BUDGET)`.

`register.tsx`:
- the seat-name helper (search `seat.replace(`): `return seat.replace(/^dr-(?:forge|superpowers):/, '')`
- `readNotifier`: `const fromEnv = ((await $.env.get('DR_FORGE_NOTIFY_URL')) || (await $.env.get('DR_COCKPIT_NOTIFY_URL')) || '').trim()`
- the two texts naming the variable (`from DR_COCKPIT_NOTIFY_URL` in the settings view and `(from DR_COCKPIT_NOTIFY_URL)` in the `/cockpit notify` answer) say `from the environment`
- the budget (search `budgetFor(`): `budgetFor(handoffTokens, (await $.env.get('DR_FORGE_BUDGET')) || (await $.env.get('DR_SUPERPOWERS_BUDGET')), window, compactWindow)`, keeping its other arguments as they are

`scripts/validate-repository.mjs`:

```js
  const legacyAllowed = new Set([
    'plugins/dr-forge/reference/legacy-names.md',
    'plugins/dr-forge/hooks/cockpit/lib.ts',
    'plugins/dr-forge/tests/cockpit.test.ts',
  ]);
```

`plugins/dr-forge/reference/legacy-names.md`: the paragraph on lines 7-8,

```markdown
This is the only file in the maintained plugins allowed to spell the old
prefixes literally; `scripts/validate-repository.mjs` enforces that.
```

becomes (one paragraph, wrapped as you like) `This is the only document in the maintained plugins allowed to spell the old prefixes literally; the cockpit's \`hooks/cockpit/lib.ts\` and its test also spell \`dr-superpowers:\` to recognise pre-2.0 sessions. \`scripts/validate-repository.mjs\` enforces both.`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 claude plugin test plugins/dr-forge && timeout 60 node scripts/validate-repository.mjs && timeout 120 node --test tests/repository-layout.test.mjs`
Expected: all pass; the validator prints its valid line.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/hooks/cockpit/lib.ts plugins/dr-forge/hooks/cockpit/register.tsx plugins/dr-forge/tests/cockpit.test.ts scripts/validate-repository.mjs plugins/dr-forge/reference/legacy-names.md
git commit -m "feat(dr-forge): keep pre-2.0 names working in the cockpit"
```

### Task 6: Bash environment names with fallbacks

**Files:**
- Create: `plugins/dr-forge/scripts/lib/forge-env.sh`
- Modify: `plugins/dr-forge/scripts/lib/context.sh`, `plugins/dr-forge/scripts/lib/snapshot.sh`, `plugins/dr-forge/scripts/task-brief`, `plugins/dr-forge/scripts/review-package`, `plugins/dr-forge/scripts/lib/darkmem-config.mjs`, `plugins/dr-forge/reference/session-budget.md`
- Test: `plugins/dr-forge/tests/context-size.test.sh`, `plugins/dr-forge/tests/budget-line.test.sh`, `plugins/dr-forge/tests/snapshot.test.sh`, `plugins/dr-forge/tests/repo-audit.test.sh`, `plugins/dr-forge/tests/darkmem-sync/*.mjs`

**Interfaces:**
- Consumes: none
- Produces: Contracts → **`scripts/lib/forge-env.sh`**

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

Rename the variables in the tests:

```bash
perl -pi -e 's/DR_SUPERPOWERS_(BUDGET_CALLER|BUDGET|JQ|SESSION_ID)/DR_FORGE_$1/g' plugins/dr-forge/tests/context-size.test.sh plugins/dr-forge/tests/budget-line.test.sh plugins/dr-forge/tests/snapshot.test.sh plugins/dr-forge/tests/repo-audit.test.sh plugins/dr-forge/tests/darkmem-sync/*.mjs
```

In `tests/context-size.test.sh` the `unset` line (line 31) becomes `unset DR_FORGE_BUDGET DR_FORGE_JQ DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID`, and after the `# --- budget override ---` case add:

```bash
DR_SUPERPOWERS_BUDGET=300000 run
check "pre-2.0 override name still applies" "$out" "budget: 285k of 300k (95%) — ok — source: record"
DR_FORGE_BUDGET=380000 DR_SUPERPOWERS_BUDGET=300000 run
check "the dr-forge name wins" "$out" "budget: 285k of 380k (75%) — ok — source: record"
```

In `tests/darkmem-sync/config.test.mjs` add:

```js
test("the pre-2.0 session id variable still declares the run, behind the new one", () => {
  const cwd = makeRepo();
  const HOME = scratch("dms-home-");
  assert.equal(runKey({ cwd, env: { HOME, DR_SUPERPOWERS_SESSION_ID: "old-1" } }), "old-1");
  assert.equal(runKey({ cwd, env: { HOME, DR_FORGE_SESSION_ID: "new-1", DR_SUPERPOWERS_SESSION_ID: "old-1" } }), "new-1");
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 600 bash plugins/dr-forge/tests/context-size.test.sh; timeout 600 bash plugins/dr-forge/tests/darkmem-sync.test.sh`
Expected: FAIL — the scripts still read only the old names.

- [ ] **Step 3: Implement**

`plugins/dr-forge/scripts/lib/forge-env.sh`:

```bash
# Sourced. The pre-2.0 DR_SUPERPOWERS_* names still apply wherever the
# DR_FORGE_* name is unset or empty; the plugin itself sets only the new names.
: "${DR_FORGE_BUDGET:=${DR_SUPERPOWERS_BUDGET:-}}"
: "${DR_FORGE_JQ:=${DR_SUPERPOWERS_JQ:-}}"
: "${DR_FORGE_BUDGET_CALLER:=${DR_SUPERPOWERS_BUDGET_CALLER:-}}"
```

Then:

```bash
perl -pi -e 's/DR_SUPERPOWERS_(BUDGET_CALLER|BUDGET|JQ)/DR_FORGE_$1/g' plugins/dr-forge/scripts/lib/context.sh plugins/dr-forge/scripts/lib/snapshot.sh plugins/dr-forge/scripts/task-brief plugins/dr-forge/scripts/review-package plugins/dr-forge/reference/session-budget.md
```

Source the new file in `scripts/lib/context.sh` directly above `ctx_jq() {` and in `scripts/lib/snapshot.sh` above its first function:

```bash
. "$(dirname "${BASH_SOURCE[0]}")/forge-env.sh"
```

In `scripts/lib/darkmem-config.mjs` `runKey`: `const declared = env.DR_FORGE_SESSION_ID?.trim() || env.DR_SUPERPOWERS_SESSION_ID?.trim();` and its comment names `DR_FORGE_SESSION_ID (or the pre-2.0 DR_SUPERPOWERS_SESSION_ID)`.

In `reference/session-budget.md`, below the table that names `DR_FORGE_BUDGET`, add: `The pre-2.0 names \`DR_SUPERPOWERS_BUDGET\` and \`DR_SUPERPOWERS_JQ\` still apply when the \`DR_FORGE_\` name is unset.`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `for t in context-size budget-line snapshot repo-audit darkmem-sync; do timeout 600 bash plugins/dr-forge/tests/$t.test.sh > /dev/null 2>&1 || echo "FAIL $t"; done; echo finished`
Expected: `finished` with no FAIL line. Then `grep -rn 'DR_SUPERPOWERS_' plugins/dr-forge/scripts plugins/dr-forge/reference` lists only `forge-env.sh`, `darkmem-config.mjs` and the new session-budget sentence.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts plugins/dr-forge/reference/session-budget.md plugins/dr-forge/tests
git commit -m "feat(dr-forge): read DR_FORGE_* names with fallbacks"
```

### Task 7: The forge_dir resolver

**Files:**
- Create: `plugins/dr-forge/scripts/lib/forge-dir.sh`, `plugins/dr-forge/scripts/forge-path`
- Test: `plugins/dr-forge/tests/forge-dir.test.sh`

**Interfaces:**
- Consumes: none
- Produces: Contracts → **`scripts/lib/forge-dir.sh`**, **`scripts/forge-path`**

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

`plugins/dr-forge/tests/forge-dir.test.sh`:

```bash
#!/usr/bin/env bash
# forge_dir: the new directory unless only the pre-2.0 one exists.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/lib/forge-dir.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then pass=$((pass + 1))
  else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"
mkdir -p "$R"

check "neither: state" "$(forge_dir state "$R")" "$R/.forge"
check "neither: docs" "$(forge_dir docs "$R")" "$R/docs/forge"

mkdir -p "$R/.superpowers" "$R/docs/superpowers"
check "only old: state" "$(forge_dir state "$R")" "$R/.superpowers"
check "only old: docs" "$(forge_dir docs "$R")" "$R/docs/superpowers"
check "only old: relative state" "$(forge_dir_rel state "$R")" ".superpowers"
check "only old: relative docs" "$(forge_dir_rel docs "$R")" "docs/superpowers"

mkdir -p "$R/.forge" "$R/docs/forge"
check "both: state" "$(forge_dir state "$R")" "$R/.forge"
check "both: docs" "$(forge_dir docs "$R")" "$R/docs/forge"

rm -rf "$R/.superpowers" "$R/docs/superpowers"
check "only new: state" "$(forge_dir state "$R")" "$R/.forge"
check "only new: relative docs" "$(forge_dir_rel docs "$R")" "docs/forge"

check "default root" "$(cd "$R" && forge_dir state)" "./.forge"
check "default root, relative" "$(cd "$R" && forge_dir_rel state)" ".forge"

forge_dir other "$R" > /dev/null 2>&1
check "unknown kind: exit 2" "$?" "2"

# --- forge-path: the directory for the repository at hand ---
G="$TMP/git"
git init -q "$G"
TOP=$(cd "$G" && git rev-parse --show-toplevel)
check "forge-path: new checkout" "$(cd "$G" && bash "$HERE/../scripts/forge-path" docs specs)" "$TOP/docs/forge/specs"
mkdir -p "$G/.superpowers"
check "forge-path: pre-2.0 state" "$(cd "$G" && bash "$HERE/../scripts/forge-path" state)" "$TOP/.superpowers"
(cd "$G" && bash "$HERE/../scripts/forge-path" > /dev/null 2>&1)
check "forge-path: usage exit 2" "$?" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 60 bash plugins/dr-forge/tests/forge-dir.test.sh`
Expected: FAIL — `forge-dir.sh` does not exist.

- [ ] **Step 3: Write the implementation**

`plugins/dr-forge/scripts/lib/forge-dir.sh`:

```bash
# Sourced. A repository's dr-forge directories: .forge/ and docs/forge/, unless
# only the pre-2.0 .superpowers/ or docs/superpowers/ exists, which stays in use
# so a checkout from before dr-forge 2.0.0 keeps its ledgers, handoffs and docs.

# forge_dir state|docs [ROOT] — the directory under ROOT (default: .).
forge_dir() {
  local root=${2:-.} new old
  case ${1:-} in
    state) new=.forge old=.superpowers ;;
    docs) new=docs/forge old=docs/superpowers ;;
    *) printf 'forge_dir: unknown kind %s (state or docs)\n' "${1:-}" >&2; return 2 ;;
  esac
  if [ ! -e "$root/$new" ] && [ -e "$root/$old" ]; then
    printf '%s/%s\n' "$root" "$old"
  else
    printf '%s/%s\n' "$root" "$new"
  fi
}

# forge_dir_rel state|docs [ROOT] — the same directory, relative to ROOT.
forge_dir_rel() {
  local dir
  dir=$(forge_dir "$@") || return
  printf '%s\n' "${dir#"${2:-.}"/}"
}
```

`plugins/dr-forge/scripts/forge-path` (mode 755):

```bash
#!/usr/bin/env bash
# forge-path state|docs [RELATIVE] — this repository's dr-forge directory, or a
# path under it: .forge/ and docs/forge/, or the pre-2.0 .superpowers/ and
# docs/superpowers/ where only those exist. Resolved under the checkout at hand.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/forge-dir.sh"
[ $# -ge 1 ] && [ $# -le 2 ] || { echo "usage: forge-path state|docs [RELATIVE]" >&2; exit 2; }
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
dir=$(forge_dir "$1" "$root") || exit 2
if [ $# -eq 2 ]; then printf '%s/%s\n' "$dir" "$2"; else printf '%s\n' "$dir"; fi
```

- [ ] **Step 4: Run it to verify it passes**

Run: `chmod +x plugins/dr-forge/scripts/forge-path && timeout 60 bash plugins/dr-forge/tests/forge-dir.test.sh`
Expected: `16 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/forge-dir.sh plugins/dr-forge/scripts/forge-path plugins/dr-forge/tests/forge-dir.test.sh
git commit -m "feat(dr-forge): add the forge_dir path resolver"
```

### Task 8: Scripts resolve the state directory

**Files:**
- Modify: `plugins/dr-forge/scripts/lib/plan.sh`, `plugins/dr-forge/scripts/lib/context.sh`, `plugins/dr-forge/scripts/lib/snapshot.sh`, `plugins/dr-forge/scripts/lib/task-state.sh`, `plugins/dr-forge/scripts/plan-revise`, `plugins/dr-forge/scripts/task-brief`, `plugins/dr-forge/scripts/next-step`, `plugins/dr-forge/scripts/finish-choice`, `plugins/dr-forge/scripts/run-codex-task.sh`, `plugins/dr-forge/scripts/turn-end.sh`, `plugins/dr-forge/scripts/repo-audit`, `plugins/dr-forge/scripts/sdd-workspace`
- Create: `plugins/dr-forge/tests/forge-state.test.sh`
- Test: existing suites whose fresh-checkout expectations name `.superpowers/`

**Interfaces:**
- Consumes: Contracts → **`scripts/lib/forge-dir.sh`** (Task 7)
- Produces: every script writes and reads the state directory by the path rule

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing test**

`plugins/dr-forge/tests/forge-state.test.sh`:

```bash
#!/usr/bin/env bash
# The state directory the scripts write: .forge/ in a new checkout, the
# pre-2.0 .superpowers/ where only that exists.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../scripts"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then pass=$((pass + 1))
  else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

checkout() { # checkout DIR — a repository with one committed plan, docs/p.md
  git init -q "$1"
  mkdir -p "$1/docs"
  printf '# Plan\n' > "$1/docs/p.md"
  git -C "$1" add docs/p.md
  git -C "$1" -c user.name=t -c user.email=t@example.com commit -q -m plan
}

checkout "$TMP/new"
top=$(cd "$TMP/new" && pwd)
dir=$(cd "$TMP/new" && bash "$SCRIPTS/sdd-workspace" docs/p.md)
check "new checkout: workspace" "${dir#"$top"}" "/.forge/sdd/p"
(cd "$TMP/new" && bash "$SCRIPTS/finish-choice" set pr --base main > /dev/null)
check "new checkout: finish choice" "$([ -f "$TMP/new/.forge/sdd/finish.json" ] && echo yes)" "yes"

checkout "$TMP/old"
mkdir -p "$TMP/old/.superpowers"
top=$(cd "$TMP/old" && pwd)
dir=$(cd "$TMP/old" && bash "$SCRIPTS/sdd-workspace" docs/p.md)
check "pre-2.0 checkout: workspace" "${dir#"$top"}" "/.superpowers/sdd/p"
(cd "$TMP/old" && bash "$SCRIPTS/finish-choice" set pr --base main > /dev/null)
check "pre-2.0 checkout: finish choice" "$([ -f "$TMP/old/.superpowers/sdd/finish.json" ] && echo yes)" "yes"
check "pre-2.0 checkout: no .forge" "$([ -e "$TMP/old/.forge" ] && echo yes || echo no)" "no"

# A worktree resolves under its own root, as sdd-workspace always did: a new
# worktree has neither directory, so it gets .forge/.
git -C "$TMP/old" worktree add -q -b wt "$TMP/wt"
top=$(cd "$TMP/wt" && pwd)
dir=$(cd "$TMP/wt" && bash "$SCRIPTS/sdd-workspace" docs/p.md)
check "worktree: workspace under the worktree" "${dir#"$top"}" "/.forge/sdd/p"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 120 bash plugins/dr-forge/tests/forge-state.test.sh`
Expected: FAIL — a new checkout gets `.superpowers/sdd/p`.

- [ ] **Step 3: Source the resolver**

Add `. "$(dirname "${BASH_SOURCE[0]}")/forge-dir.sh"` at the top of `scripts/lib/plan.sh`, `scripts/lib/context.sh` and `scripts/lib/snapshot.sh` (after their header comments). `sdd-workspace`, `plan-revise`, `task-brief`, `next-step`, `repo-audit` and `review-package` already source `lib/plan.sh`, so they get it from there. The two that source no such library add one line: `scripts/finish-choice` → `. "$HERE/lib/forge-dir.sh"` directly below its `HERE=` line, and `scripts/turn-end.sh` → `. "${SCRIPT_DIR}/lib/forge-dir.sh"` directly above its existing `. "${SCRIPT_DIR}/lib/in-flight.sh"` line.

- [ ] **Step 4: Replace every state path**

Each `<root>/.superpowers` becomes `$(forge_dir state "<root>")`, the root unchanged:

| File:line (before) | After |
|---|---|
| `plan-revise:155` `f="$wt/.superpowers/sdd/$slug/progress.md"` | `f="$(forge_dir state "$wt")/sdd/$slug/progress.md"` |
| `task-brief:97` `ledger="$(git rev-parse --show-toplevel 2>/dev/null \|\| true)/.superpowers/sdd/…"` | `ledger="$(forge_dir state "$(git rev-parse --show-toplevel 2>/dev/null \|\| true)")/sdd/$(basename "$plan" .md)/progress.md"` |
| `next-step:170` `ledger_file="$root/.superpowers/sdd/$slug/progress.md"` | `ledger_file="$(forge_dir state "$root")/sdd/$slug/progress.md"` |
| `next-step:422` `handoff="$primary/.superpowers/handoff/latest.md"` | `handoff="$(forge_dir state "$primary")/handoff/latest.md"` |
| `next-step:142,145,154` the literal `` `.superpowers/handoff/latest.md` `` in printed text | `` `$(forge_dir_rel state "$primary")/handoff/latest.md` `` (compute `primary` before these lines if it is set later; it is the same primary checkout as line 422) |
| `finish-choice:49` `dir="$root/.superpowers/sdd"` | `dir="$(forge_dir state "$root")/sdd"` |
| `sdd-workspace:38` `base="$root/.superpowers/sdd"` | `base="$(forge_dir state "$root")/sdd"` |
| `turn-end.sh:32` and `:83` `"$root/.superpowers/sdd"` | `"$(forge_dir state "$root")/sdd"` (compute once into `sdd=` and use it on both lines) |
| `lib/plan.sh:324` `file="$top/.superpowers/sdd/…"` | `file="$(forge_dir state "$top")/sdd/$(basename "$1" .md)/progress.md"` |
| `lib/plan.sh:418-419` `"$root/.superpowers/sdd/$slug/amendments.md"` (twice) | `"$(forge_dir state "$root")/sdd/$slug/amendments.md"` |
| `repo-audit:55` `for ledger in "$wt"/.superpowers/sdd/*/progress.md` | `for ledger in "$(forge_dir state "$wt")"/sdd/*/progress.md` |
| `repo-audit:97` `latest="$primary/.superpowers/handoff/latest.md"` | `latest="$(forge_dir state "$primary")/handoff/latest.md"` |
| `lib/context.sh:289` and `:382` `"$primary/.superpowers/sdd"` | `"$(forge_dir state "$primary")/sdd"` |
| `lib/snapshot.sh:18` and `:28` | as `repo-audit:97` and `:55` |
| `run-codex-task.sh:145` `case "$report" in "$cwd"/.superpowers/*) ;;` | `case "$report" in "$cwd"/.forge/*|"$cwd"/.superpowers/*) ;;` and the message says `ignored .forge workspace` |
| `lib/task-state.sh:138` `…\|.superpowers\|.superpowers/*) return 2 ;;` | add `\|.forge\|.forge/*` before `)` |

Comments that name the directory say `.forge/ (.superpowers/ in a pre-2.0 checkout)`. Then: `grep -rn '\.superpowers' plugins/dr-forge/scripts | grep -v 'forge-dir.sh\|darkmem\|^[^:]*:[0-9]*:\s*#'` lists only the two guard lines in `run-codex-task.sh` and `task-state.sh` (the darkmem files are Task 10's).

- [ ] **Step 5: Run every suite and fix fresh-checkout expectations**

Run: `timeout 900 node scripts/test-all.mjs`
Expected: every suite passes. A suite that fails because a new checkout now gets `.forge/…` where its assertion says `.superpowers/…` is updated to `.forge/…` — only where its fixture created no `.superpowers/` first; a fixture that creates `.superpowers/` must keep passing unchanged.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-forge/scripts plugins/dr-forge/tests
git commit -m "feat(dr-forge): resolve the state directory by rule"
```

### Task 9: Scripts resolve the docs directory

**Files:**
- Modify: `plugins/dr-forge/scripts/session-start.sh`, `plugins/dr-forge/scripts/lib/register.sh`, `plugins/dr-forge/scripts/lib/roadmap.sh`, `plugins/dr-forge/scripts/roadmap`, `plugins/dr-forge/scripts/next-step`
- Test: `plugins/dr-forge/tests/roadmap.test.sh`, `plugins/dr-forge/tests/register.test.sh`

**Interfaces:**
- Consumes: Contracts → **`scripts/lib/forge-dir.sh`** (Task 7)
- Produces: every script reads the docs directory by the path rule

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/roadmap.test.sh`, directly after the line `check "close: the written roadmap checks clean" "$RC" "0"`, add (the first checkout has every milestone closed by then, so its copy does too):

```bash
# --- a dr-forge checkout keeps its roadmap in docs/forge ---
FROOT="$TMP/forge"
git init -q -b main "$FROOT"
mkdir -p "$FROOT/docs"
cp -R "$D" "$FROOT/docs/forge"
for f in "$FROOT"/docs/forge/roadmap.md "$FROOT"/docs/forge/registers/*.md; do
  sed 's#docs/superpowers/#docs/forge/#g' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
run bash "$RM" status --root "$FROOT" --line
check "docs/forge: the hook line names its roadmap" "$OUT" "Roadmap: every milestone is closed (docs/forge/roadmap.md)."
run bash "$RM" check --root "$FROOT"
check "docs/forge: the roadmap checks clean" "$RC" "0"
```

In `tests/register.test.sh`, directly after `check "register_files: no directory prints nothing" "$(register_files "$TMP/absent")" ""`, add:

```bash
mkdir -p "$TMP/forge/docs/forge/registers"
reg "$TMP/forge/docs/forge/registers/one.md" '| 1 | A | - | - | open | - |'
check "register_files: a docs/forge checkout" "$(register_files "$TMP/forge" | xargs -n1 basename)" "one.md"
```

The existing assertions on `docs/superpowers` checkouts (including `Roadmap: every milestone is closed (docs/superpowers/roadmap.md).`) stay as they are: their fixtures create `docs/superpowers/`, so the rule keeps it.

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 600 bash plugins/dr-forge/tests/roadmap.test.sh; timeout 600 bash plugins/dr-forge/tests/register.test.sh`
Expected: FAIL on the three new checks only.

- [ ] **Step 3: Implement**

`lib/register.sh`: directly after its header comment, `. "$(dirname "${BASH_SOURCE[0]}")/forge-dir.sh"` (`lib/roadmap.sh` sources `register.sh`, and `scripts/roadmap` and `next-step` source `lib/roadmap.sh`, so they all get it). `session-start.sh`: `. "${SCRIPT_DIR}/lib/forge-dir.sh"` directly below its `PLUGIN_ROOT=` line.

| File (before) | After |
|---|---|
| `session-start.sh` `if [ -n "$roadmap_root" ] && [ -f "$roadmap_root/docs/superpowers/roadmap.md" ]; then` | `if [ -n "$roadmap_root" ] && [ -f "$(forge_dir docs "$roadmap_root")/roadmap.md" ]; then` |
| `lib/register.sh` `local dir="$1/docs/superpowers/registers" f` | `local dir f`<br>`dir="$(forge_dir docs "$1")/registers"` |
| `lib/roadmap.sh` `local f="$1/docs/superpowers/roadmap.md"` | `local f`<br>`f="$(forge_dir docs "$1")/roadmap.md"` |
| `lib/roadmap.sh` `printf 'Roadmap: every milestone is closed (docs/superpowers/roadmap.md).\n'` | `printf 'Roadmap: every milestone is closed (%s/roadmap.md).\n' "$(forge_dir_rel docs "$root")"` |
| `roadmap` `FILE="$root/docs/superpowers/roadmap.md"` | `FILE="$(forge_dir docs "$root")/roadmap.md"` |
| `next-step` ``prompt="Close milestone $ms_id ($ms_name) of \`docs/superpowers/roadmap.md\` with dr-forge:closing-a-milestone."`` | ``prompt="Close milestone $ms_id ($ms_name) of \`$(forge_dir_rel docs "$root")/roadmap.md\` with dr-forge:closing-a-milestone."`` |
| `next-step` ``next_line="Nothing — every milestone in \`docs/superpowers/roadmap.md\` is closed."`` | ``next_line="Nothing — every milestone in \`$(forge_dir_rel docs "$root")/roadmap.md\` is closed."`` |

(`roadmap_line` already has `local root=$1`; in `next-step` the same `$root` is the one `roadmap_file "$root"` used a few lines above.)

Then `grep -rn 'docs/superpowers' plugins/dr-forge/scripts | grep -v 'forge-dir.sh\|darkmem\|^[^:]*:[0-9]*:\s*#'` → no output (the darkmem files are Task 10's).

- [ ] **Step 4: Run every suite**

Run: `timeout 900 node scripts/test-all.mjs`
Expected: every suite passes. A suite that fails because a fresh checkout (one whose fixture creates no `docs/superpowers/`) now names `docs/forge/…` where its assertion says `docs/superpowers/…` gets its assertion changed to `docs/forge/…`; a fixture that creates `docs/superpowers/` must keep passing unchanged.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts plugins/dr-forge/tests
git commit -m "feat(dr-forge): resolve the docs directory by rule"
```

### Task 10: darkmem home, config fallback, mirror and roots

**Files:**
- Modify: `plugins/dr-forge/scripts/lib/darkmem-config.mjs`, `plugins/dr-forge/scripts/lib/darkmem-import.mjs`, `plugins/dr-forge/scripts/lib/darkmem-mirror.mjs`, `plugins/dr-forge/scripts/darkmem-sync` (comments)
- Test: `plugins/dr-forge/tests/darkmem-sync/helpers.mjs`, `plugins/dr-forge/tests/darkmem-sync/config.test.mjs`, `plugins/dr-forge/tests/darkmem-sync/mirror.test.mjs`

**Interfaces:**
- Consumes: the path rule (Global Constraints)
- Produces: Contracts → **`scripts/lib/darkmem-config.mjs` exports**

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

`helpers.mjs` `makeHome` gains a `legacy` option and writes the new home by default:

```js
// A HOME whose ~/.dr-forge/config.json (with legacy: true, the pre-2.0
// ~/.dr-superpowers/config.json) maps `repo` to `project`.
// `config` replaces the file's content (a string is written verbatim); null
// writes no file at all.
export function makeHome({ repo, url = "http://127.0.0.1:9", project = "proj", config, legacy = false } = {}) {
  const home = scratch("dms-home-");
  const dir = path.join(home, legacy ? ".dr-superpowers" : ".dr-forge");
  const body = config !== undefined ? config : { darkmem: { url, api_key_env: "DARKMEM_API_KEY", repos: { [repo]: { project } } } };
  if (body !== null) {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "config.json"), typeof body === "string" ? body : JSON.stringify(body));
  }
  const env = {
    ...process.env,
    HOME: home,
    DARKMEM_API_KEY: KEY,
    DR_FORGE_SESSION_ID: "sess-1",
    DARKMEM_SYNC_TIMEOUT_MS: "3000",
  };
  const mirror = path.join(dir, "mirror", project);
  return { home, env, mirror, docsRoot: path.join(mirror, "superpowers"), workRoot: path.join(mirror, "work") };
}
```

In `config.test.mjs`, the first test expects `path.join(repo, "docs", "forge")` and `path.join(repo, ".forge")`; the second test's `mirror` is `path.join(home, ".dr-forge", "mirror", "proj")`. Add:

```js
test("a pre-2.0 checkout keeps its docs/superpowers and .superpowers", () => {
  const repo = makeRepo();
  fs.mkdirSync(path.join(repo, "docs", "superpowers"), { recursive: true });
  fs.mkdirSync(path.join(repo, ".superpowers"), { recursive: true });
  const { env } = makeHome({ repo, config: null });
  const mode = resolveMode({ cwd: repo, env });
  assert.equal(mode.docsRoot, path.join(repo, "docs", "superpowers"));
  assert.equal(mode.workRoot, path.join(repo, ".superpowers"));
});

test("the pre-2.0 config and mirror are used until the new ones exist", () => {
  const repo = makeRepo();
  const { home, env } = makeHome({ repo, legacy: true });
  const old = path.join(home, ".dr-superpowers", "mirror", "proj");
  fs.mkdirSync(old, { recursive: true });
  const mode = resolveMode({ cwd: repo, env });
  assert.equal(mode.mode, "darkmem");
  assert.equal(mode.mirror, old);
  const next = path.join(home, ".dr-forge", "mirror", "proj");
  fs.mkdirSync(next, { recursive: true });
  assert.equal(resolveMode({ cwd: repo, env }).mirror, next);
});

test("the new config wins over the pre-2.0 one", () => {
  const repo = makeRepo();
  const { home, env } = makeHome({ repo, legacy: true });
  fs.mkdirSync(path.join(home, ".dr-forge"), { recursive: true });
  fs.writeFileSync(path.join(home, ".dr-forge", "config.json"), JSON.stringify({ layout: "compact" }));
  assert.equal(resolveMode({ cwd: repo, env }).mode, "local");
});
```

In `mirror.test.mjs`, beside the existing `pathToUri` assertion for a mirror path, add:

```js
  assert.equal(pathToUri("docs/forge/plans/p1.md"), "superpowers/plans/p1.md");
  assert.equal(pathToUri("/r/docs/forge/specs/s.md"), "superpowers/specs/s.md");
```

(darkmem's own URIs keep their `superpowers/` prefix; only the repository side gains `docs/forge/`.)

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 600 bash plugins/dr-forge/tests/darkmem-sync.test.sh`
Expected: FAIL — the code still reads `~/.dr-superpowers` and `docs/superpowers`.

- [ ] **Step 3: Implement**

In `darkmem-config.mjs` replace `superpowersHome` and the header comment:

```js
// dr-forge's darkmem mode for one repository (darkmem mirror spec §1): the
// mapping in ~/.dr-forge/config.json (the pre-2.0 ~/.dr-superpowers/config.json
// until the new file exists), the API key from the environment variable the
// file names, the mirror's two roots, and the run key a sync declares. No
// mapping, or no key, is local mode.
```

```js
export function forgeHome(env = process.env) {
  return path.join(homeOf(env), ".dr-forge");
}

function legacyHome(env) {
  return path.join(homeOf(env), ".dr-superpowers");
}

// The new path, unless it does not exist and the pre-2.0 one does.
export function preferNew(next, old) {
  return !fs.existsSync(next) && fs.existsSync(old) ? old : next;
}

// A repository's dr-forge directory: docs/forge/ or .forge/, or the pre-2.0
// docs/superpowers/ or .superpowers/ where only that exists.
export function forgeDir(kind, root) {
  return kind === "docs"
    ? preferNew(path.join(root, "docs", "forge"), path.join(root, "docs", "superpowers"))
    : preferNew(path.join(root, ".forge"), path.join(root, ".superpowers"));
}
```

In `resolveMode`: `docsRoot: repoRoot ? forgeDir("docs", repoRoot) : null,` and `workRoot: repoRoot ? forgeDir("state", repoRoot) : null,`; `const file = preferNew(path.join(forgeHome(env), "config.json"), path.join(legacyHome(env), "config.json"));`; `const mirror = preferNew(path.join(forgeHome(env), "mirror", project), path.join(legacyHome(env), "mirror", project));`.

In `darkmem-mirror.mjs` `pathToUri`, accept both repository layouts and update its comment:

```js
// The darkmem uri a path names: what follows its `superpowers/` segment (a
// pre-2.0 repository path or a mirror path) or its `docs/forge/` segment.
export function pathToUri(file) {
  const match = String(file).replace(/\\/g, "/").match(/(?:^|\/)(?:superpowers|docs\/forge)\/(.+)$/);
  return match ? `${DOC_PREFIX}/${match[1]}` : null;
}
```

In `darkmem-import.mjs` `importRepository`: `const roots = { docsRoot: forgeDir("docs", cfg.repoRoot), workRoot: forgeDir("state", cfg.repoRoot) };` importing `forgeDir` from `./darkmem-config.mjs`. In `scripts/darkmem-sync`'s header comments, `~/.dr-superpowers/` becomes `~/.dr-forge/ (~/.dr-superpowers/ before 2.0)`.

Run: `grep -rn 'superpowersHome' plugins/dr-forge` → no output.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dr-forge/tests/darkmem-sync.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts plugins/dr-forge/tests/darkmem-sync
git commit -m "feat(dr-forge): move darkmem home with a pre-2.0 fallback"
```

### Task 11: Settings schema and its validator check

**Files:**
- Create: `plugins/dr-forge/config/schema.mjs`
- Modify: `scripts/validate-repository.mjs`
- Test: `tests/repository-layout.test.mjs`

**Interfaces:**
- Consumes: none
- Produces: Contracts → **`config/schema.mjs`**; `validateSchema(root)` in Contracts → **`scripts/validate-repository.mjs` exports**

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing tests**

Append to `tests/repository-layout.test.mjs`:

```js
test('the settings schema is valid, and broken schemas are caught', async () => {
  const { validateSchema } = await import('../scripts/validate-repository.mjs');
  assert.deepEqual(await validateSchema(root), []);
  // Each case gets its own directory: Node caches a module by its URL, so a
  // rewritten file at one path would be imported once.
  const broken = async text => {
    const dir = mkdtempSync(resolve(tmpdir(), 'dr-schema-'));
    try {
      mkdirSync(resolve(dir, 'plugins/dr-forge/config'), { recursive: true });
      writeFileSync(resolve(dir, 'plugins/dr-forge/config/schema.mjs'), text);
      return (await validateSchema(dir)).join('\n');
    } finally { rmSync(dir, { recursive: true, force: true }); }
  };
  const real = readFileSync(resolve(root, 'plugins/dr-forge/config/schema.mjs'), 'utf8');
  assert.match(await broken(real.replace("default: 'auto'", "default: 'tiles'")), /schema layout: default does not fit its type/);
  assert.match(await broken("export default { darkmem: { type: 'string', default: '', group: 'Cockpit', title: 't', description: 'd', target: 'forge' } }\n"), /schema darkmem: the key is reserved/);
  assert.match(await broken('export default [];\n'), /must default-export an object/);
  assert.match(await broken("export default { n: { type: 'number', default: Infinity, group: 'Cockpit', title: 't', description: 'd', target: 'forge' } }\n"), /schema n: default does not fit its type/);
});
```

Add `mkdirSync` to the file's `node:fs` import.

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 120 node --test tests/repository-layout.test.mjs`
Expected: FAIL — `validateSchema` is not exported.

- [ ] **Step 3: Write the schema**

`plugins/dr-forge/config/schema.mjs`:

```js
// Every dr-forge setting: its type, default, the settings-view group and text,
// and where it is stored. An ES module rather than JSON because a Claude Code
// mod imports only code files; the cockpit, scripts/lib/forge-config.mjs and
// scripts/validate-repository.mjs all import it. Values live in
// ~/.dr-forge/config.json, whose `darkmem` key is reserved for the darkmem mapping.
export default {
  openAtStart: {
    type: 'boolean', default: true, group: 'Cockpit', target: 'forge',
    title: 'Open the pane at session start',
    description: 'Open the cockpit when a session starts. Claude Code shows it once the terminal is 144 columns wide, 110 once you have opened it before; /cockpit opens it at any width.',
  },
  layout: {
    type: 'enum', values: ['auto', 'full', 'compact'], default: 'auto', group: 'Cockpit', target: 'forge',
    title: 'Pane layout',
    description: 'auto: the full layout docked beside the transcript, the band when the pane sits above the prompt. full: always the full layout. compact: minimized, the band above the prompt; Minimize sets it and Expand sets auto.',
  },
  sections: {
    type: 'string', default: '', group: 'Cockpit', target: 'forge',
    title: 'Pane sections',
    description: 'Which sections the full pane shows, in order, comma-separated: account, context, usage, shells, agents, plan, repo, guard. Empty shows all eight.',
  },
  breakdownRows: {
    type: 'number', default: 6, min: 0, max: 12, step: 1, group: 'Cockpit', target: 'forge',
    title: 'Context breakdown rows',
    description: 'How many /context categories the Context section lists, largest first, up to 12. 0 hides the breakdown.',
  },
  guardAttribution: {
    type: 'boolean', default: true, group: 'Cockpit', target: 'forge',
    title: 'Keep AI attribution out of git',
    description: 'Drop the commit trailer and pull request footer Claude Code asks for, and refuse commits and pull requests that still carry AI attribution.',
  },
  handoffTokens: {
    type: 'number', default: 0, min: 0, max: 2_000_000, step: 50_000, env: 'DR_FORGE_BUDGET', group: 'Context', target: 'forge',
    title: 'Handoff budget (tokens)',
    description: "Context size at which the cockpit says hand off. 0 follows dr-forge's rule: 93% of the smaller of autoCompactWindow and the model's window, minus 140,000. DR_FORGE_BUDGET overrides it.",
  },
  warnAt: {
    type: 'number', default: 80, min: 1, max: 99, step: 5, group: 'Context', target: 'forge',
    title: 'Warn at (% of the handoff budget)',
    description: 'Where Hand off takes the accent color, as a share of the handoff budget, 1 to 99.',
  },
  nudgeModel: {
    type: 'boolean', default: true, group: 'Context', target: 'forge',
    title: 'Tell the model at the budget',
    description: 'In a session running dr-forge, add one note to the conversation when the main session crosses its handoff budget.',
  },
  limitAlertAt: {
    type: 'number', default: 90, min: 0, max: 100, step: 5, group: 'Notifications', target: 'forge',
    title: 'Discord usage limit alert (%)',
    description: 'Send the Discord limit message once when the 5-hour or 7-day limit crosses this share, again after it resets. 0 turns it off.',
  },
  notifyOn: {
    type: 'string', default: '', group: 'Notifications', target: 'forge',
    title: 'Discord: events to send',
    description: 'Comma-separated: ask, question, done, error, blocked, budget, limit, task, session, agent. Empty sends ask, question, done, error, blocked, budget and limit; none sends nothing.',
  },
  notifyAfter: {
    type: 'number', default: 60, min: 0, max: 3600, step: 15, group: 'Notifications', target: 'forge',
    title: 'Discord: done after (seconds)',
    description: 'A finished turn is sent only when it ran at least this long. 0 sends every turn.',
  },
  notifyAskAfter: {
    type: 'number', default: 20, min: 0, max: 600, step: 10, group: 'Notifications', target: 'forge',
    title: 'Discord: approval after (seconds)',
    description: 'An approval or question is sent only when it is still unanswered after this long. 0 sends at once.',
  },
  notifyDetail: {
    type: 'enum', values: ['full', 'brief'], default: 'full', group: 'Notifications', target: 'forge',
    title: 'Discord: detail',
    description: 'full sends command, question and answer excerpts (secrets masked); brief sends titles and figures only.',
  },
};
```

- [ ] **Step 4: Add the validator check**

In `scripts/validate-repository.mjs` import `pathToFileURL` from `node:url` beside `fileURLToPath`, add after `validateRepository`:

```js
const GROUPS = ['Cockpit', 'Context', 'Notifications', 'Workflow'];

export async function validateSchema(root) {
  const rel = 'plugins/dr-forge/config/schema.mjs';
  let schema;
  try { schema = (await import(pathToFileURL(resolve(root, rel)).href)).default; }
  catch (error) { return [`${rel}: ${error.message}`]; }
  if (!schema || typeof schema !== 'object' || Array.isArray(schema)) return [`${rel}: must default-export an object`];
  const errors = [];
  for (const [key, spec] of Object.entries(schema)) {
    const at = `schema ${key}`;
    if (key === 'darkmem') { errors.push(`${at}: the key is reserved for the darkmem mapping`); continue; }
    if (!['boolean', 'number', 'enum', 'string'].includes(spec?.type)) { errors.push(`${at}: type must be boolean, number, enum or string`); continue; }
    if (!GROUPS.includes(spec.group)) errors.push(`${at}: group must be one of ${GROUPS.join(', ')}`);
    if (typeof spec.title !== 'string' || !spec.title) errors.push(`${at}: title is required`);
    if (typeof spec.description !== 'string' || !spec.description) errors.push(`${at}: description is required`);
    if (!['forge', 'claude'].includes(spec.target)) errors.push(`${at}: target must be forge or claude`);
    if (spec.env !== undefined && !/^[A-Z][A-Z0-9_]*$/.test(spec.env)) errors.push(`${at}: env must name an environment variable`);
    if (spec.step !== undefined && !(typeof spec.step === 'number' && spec.step > 0)) errors.push(`${at}: step must be a positive number`);
    const fits = spec.type === 'boolean' ? typeof spec.default === 'boolean'
      : spec.type === 'number' ? Number.isFinite(spec.default) && (spec.min === undefined || (Number.isFinite(spec.min) && spec.default >= spec.min)) && (spec.max === undefined || (Number.isFinite(spec.max) && spec.default <= spec.max))
      : spec.type === 'enum' ? Array.isArray(spec.values) && spec.values.length > 0 && spec.values.includes(spec.default)
      : typeof spec.default === 'string';
    if (!fits) errors.push(`${at}: default does not fit its type`);
  }
  return errors;
}
```

and the CLI block becomes:

```js
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = process.argv[2] ?? fileURLToPath(new URL('../', import.meta.url));
  const errors = [...validateRepository(root), ...await validateSchema(root)];
  if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1; }
  else console.log('Repository catalogs, manifests, versions, bundled links and the settings schema are valid.');
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 120 node --test tests/repository-layout.test.mjs && timeout 60 node scripts/validate-repository.mjs && timeout 60 claude plugin validate plugins/dr-forge`
Expected: all pass; the validator prints the new valid line.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-forge/config/schema.mjs scripts/validate-repository.mjs tests/repository-layout.test.mjs
git commit -m "feat(dr-forge): declare settings in one schema"
```

### Task 12: The forge-config command

**Files:**
- Create: `plugins/dr-forge/scripts/forge-config`, `plugins/dr-forge/scripts/lib/forge-config.mjs`
- Test: `plugins/dr-forge/tests/forge-config.test.sh`

**Interfaces:**
- Consumes: Contracts → **`config/schema.mjs`** (Task 11)
- Produces: Contracts → **`scripts/forge-config`**, **`scripts/lib/forge-config.mjs` exports**

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

`plugins/dr-forge/tests/forge-config.test.sh`:

```bash
#!/usr/bin/env bash
# forge-config: environment over file over default, set/unset, refusals, and
# the one-time import of the pre-2.0 settings.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="$HERE/../scripts/forge-config"
command -v node > /dev/null 2>&1 || { echo "forge-config tests: node is required but not on PATH" >&2; exit 2; }

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then pass=$((pass + 1))
  else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
if command -v cygpath > /dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
unset CLAUDE_CONFIG_DIR DR_FORGE_BUDGET DR_SUPERPOWERS_BUDGET
fc() { bash "$CMD" "$@" 2> "$TMP/stderr"; }
fresh() { export HOME="$TMP/home-$1"; mkdir -p "$HOME"; FILE="$HOME/.dr-forge/config.json"; }

# --- defaults, set, get, unset ---
fresh a
check "default" "$(fc get warnAt)" "80"
check "first run writes the file" "$(cat "$FILE" | tr -d ' \n')" "{}"
fc set warnAt 70; check "set: exit 0" "$?" "0"
check "set then get" "$(fc get warnAt)" "70"
fc set layout compact
check "get --json" "$(fc get --json | node -e 'const v = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log(v.warnAt, v.layout, v.openAtStart)')" "70 compact true"
fc set warnAt 80
check "a default value is not stored" "$(node -e 'console.log(Object.keys(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))).join(","))' "$FILE")" "layout"
fc unset layout
check "unset" "$(fc get layout)" "auto"

# --- refusals leave the file unchanged ---
before=$(cat "$FILE")
fc set nope 1; check "unknown key: exit 2" "$?" "2"
fc set warnAt 500; check "out of range: exit 2" "$?" "2"
fc set layout tiles; check "not an option: exit 2" "$?" "2"
fc set guardAttribution maybe; check "not a boolean: exit 2" "$?" "2"
fc get; check "usage: exit 2" "$?" "2"
fc get constructor; check "an inherited name is unknown: exit 2" "$?" "2"
fc unset toString; check "unset of an inherited name: exit 2" "$?" "2"
check "refusals change nothing" "$(cat "$FILE")" "$before"

# --- environment over file ---
fc set handoffTokens 300000
check "file value" "$(fc get handoffTokens)" "300000"
check "DR_FORGE_BUDGET wins" "$(DR_FORGE_BUDGET=400000 fc get handoffTokens)" "400000"
check "pre-2.0 DR_SUPERPOWERS_BUDGET applies" "$(DR_SUPERPOWERS_BUDGET=450000 fc get handoffTokens)" "450000"
check "an invalid override is ignored" "$(DR_FORGE_BUDGET=junk fc get handoffTokens)" "300000"
check "and warned about" "$(grep -c 'DR_FORGE_BUDGET' "$TMP/stderr")" "1"

# --- a file that is not JSON is refused, not overwritten ---
printf 'not json' > "$FILE"
fc set warnAt 70; check "bad file: exit 1" "$?" "1"
check "bad file kept" "$(cat "$FILE")" "not json"

# --- one-time import ---
fresh b
mkdir -p "$HOME/.claude" "$HOME/.dr-superpowers"
printf '%s' '{"pluginConfigs":{"dr-cockpit@darkraise":{"options":{"layout":"compact","warnAt":80,"breakdownRows":"x"}}}}' > "$HOME/.claude/settings.json"
printf '%s' '{"darkmem":{"url":"http://d.test","api_key_env":"DM_KEY","repos":{"/r":{"project":"p"}}}}' > "$HOME/.dr-superpowers/config.json"
fc get layout > /dev/null
DM='{"url":"http://d.test","api_key_env":"DM_KEY","repos":{"/r":{"project":"p"}}}'
check "import: options and darkmem" "$(node -e 'const v = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); console.log(JSON.stringify(v))' "$FILE")" "{\"layout\":\"compact\",\"darkmem\":$DM}"
fc set warnAt 70
fc unset warnAt
fc set notifyDetail brief
check "set and unset keep the darkmem mapping whole" "$(node -e 'console.log(JSON.stringify(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).darkmem))' "$FILE")" "$DM"
printf '%s' '{"pluginConfigs":{"dr-cockpit@darkraise":{"options":{"layout":"full"}}}}' > "$HOME/.claude/settings.json"
check "import runs once" "$(fc get layout)" "compact"

# --- CLAUDE_CONFIG_DIR names the settings to import ---
fresh c
mkdir -p "$TMP/alt"
printf '%s' '{"pluginConfigs":{"dr-cockpit@darkraise":{"options":{"notifyDetail":"brief"}}}}' > "$TMP/alt/settings.json"
check "import from CLAUDE_CONFIG_DIR" "$(CLAUDE_CONFIG_DIR="$TMP/alt" fc get notifyDetail)" "brief"

# --- two first runs at once: exactly one import lands, whole ---
fresh d
mkdir -p "$TMP/c1" "$TMP/c2"
printf '%s' '{"pluginConfigs":{"dr-cockpit@darkraise":{"options":{"layout":"compact"}}}}' > "$TMP/c1/settings.json"
printf '%s' '{"pluginConfigs":{"dr-cockpit@darkraise":{"options":{"layout":"full","warnAt":70}}}}' > "$TMP/c2/settings.json"
CLAUDE_CONFIG_DIR="$TMP/c1" bash "$CMD" get layout > /dev/null 2>&1 &
p1=$!
CLAUDE_CONFIG_DIR="$TMP/c2" bash "$CMD" get layout > /dev/null 2>&1 &
p2=$!
wait "$p1" "$p2"
case $(tr -d ' \n' < "$FILE") in '{"layout":"compact"}'|'{"layout":"full","warnAt":70}') whole=yes ;; *) whole=no ;; esac
check "concurrent first runs: one whole import" "$whole" "yes"
check "concurrent first runs: no temporary file left" "$(ls "$HOME/.dr-forge" | grep -c '\.import$')" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 120 bash plugins/dr-forge/tests/forge-config.test.sh`
Expected: FAIL — `scripts/forge-config` does not exist.

- [ ] **Step 3: Write the command**

`plugins/dr-forge/scripts/forge-config` (mode 755):

```bash
#!/usr/bin/env bash
# dr-forge's settings: forge-config get KEY | get --json | set KEY VALUE | unset KEY
# The schema is config/schema.mjs; values live in ~/.dr-forge/config.json.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v node > /dev/null 2>&1 || { echo "forge-config: node is required but not on PATH" >&2; exit 2; }
exec node "$HERE/lib/forge-config.mjs" "$@"
```

`plugins/dr-forge/scripts/lib/forge-config.mjs`:

```js
// dr-forge's settings: their schema (config/schema.mjs), the values in
// ~/.dr-forge/config.json, and the environment variable a key names, which wins
// over both. The first command on a machine imports the pre-2.0 settings once.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import SCHEMA from "../../config/schema.mjs";

export class SettingError extends Error {}

// A pre-2.0 environment name still read when the new one is unset.
const LEGACY_ENV = { DR_FORGE_BUDGET: "DR_SUPERPOWERS_BUDGET" };
const USAGE = "usage: forge-config get KEY | get --json | set KEY VALUE | unset KEY";

function homeOf(env) {
  return env.HOME || os.homedir();
}

export function configPath(env = process.env) {
  return path.join(homeOf(env), ".dr-forge", "config.json");
}

// A value as the file holds it: exactly the schema's type.
export function isValid(spec, value) {
  switch (spec.type) {
    case "boolean": return typeof value === "boolean";
    case "number": return typeof value === "number" && Number.isFinite(value)
      && (spec.min === undefined || value >= spec.min) && (spec.max === undefined || value <= spec.max);
    case "enum": return typeof value === "string" && spec.values.includes(value);
    case "string": return typeof value === "string";
    default: return false;
  }
}

// A value as a command line or an environment variable spells it; undefined when it does not fit.
export function fromText(spec, text) {
  const value = spec.type === "boolean" ? (text === "true" ? true : text === "false" ? false : undefined)
    : spec.type === "number" ? (text.trim() === "" ? undefined : Number(text))
    : text;
  return value !== undefined && isValid(spec, value) ? value : undefined;
}

// The file's object, or null when it does not exist. Anything else unreadable throws.
export function readFile(file) {
  let text;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    throw new Error(`${file} is not valid JSON; fix or remove it`);
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error(`${file} must hold a JSON object`);
  return data;
}

function writeFile(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temp, `${JSON.stringify(data, null, 2)}\n`);
  fs.renameSync(temp, file);
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

function need(key) {
  if (!Object.hasOwn(SCHEMA, key)) throw new SettingError(`unknown setting ${key}`);
  return SCHEMA[key];
}

export function resolve(env = process.env, warn = message => process.stderr.write(`forge-config: ${message}\n`)) {
  const file = configPath(env);
  const data = readFile(file) ?? {};
  const values = {};
  for (const [key, spec] of Object.entries(SCHEMA)) {
    const name = spec.env === undefined ? undefined : env[spec.env] ? spec.env : LEGACY_ENV[spec.env];
    const raw = name === undefined ? undefined : env[name];
    if (raw !== undefined && raw !== "") {
      const value = fromText(spec, raw);
      if (value !== undefined) { values[key] = value; continue; }
      warn(`${name}=${raw} is not a valid ${key}; ignored`);
    }
    if (key in data) {
      if (isValid(spec, data[key])) { values[key] = data[key]; continue; }
      warn(`${key} in ${file} is not valid; ignored`);
    }
    values[key] = spec.default;
  }
  return values;
}

export function setValue(key, text, env = process.env) {
  const spec = need(key);
  const value = fromText(spec, text);
  if (value === undefined) throw new SettingError(`${text} is not a valid ${key}`);
  const file = configPath(env);
  const data = readFile(file) ?? {};
  if (value === spec.default) delete data[key];
  else data[key] = value;
  writeFile(file, data);
  return value;
}

export function unsetValue(key, env = process.env) {
  need(key);
  const file = configPath(env);
  const data = readFile(file) ?? {};
  delete data[key];
  writeFile(file, data);
}

// Once per machine, while ~/.dr-forge/config.json does not exist: dr-cockpit's
// options from the Claude settings file and the darkmem mapping from
// ~/.dr-superpowers/config.json. The old files stay in place.
export function importLegacy(env = process.env) {
  const file = configPath(env);
  if (fs.existsSync(file)) return false;
  const data = {};
  const claudeDir = env.CLAUDE_CONFIG_DIR || path.join(homeOf(env), ".claude");
  const options = readJson(path.join(claudeDir, "settings.json"))?.pluginConfigs?.["dr-cockpit@darkraise"]?.options;
  if (options && typeof options === "object") {
    for (const [key, spec] of Object.entries(SCHEMA)) {
      if (key in options && isValid(spec, options[key]) && options[key] !== spec.default) data[key] = options[key];
    }
  }
  const darkmem = readJson(path.join(homeOf(env), ".dr-superpowers", "config.json"))?.darkmem;
  if (darkmem && typeof darkmem === "object" && !Array.isArray(darkmem)) data.darkmem = darkmem;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}.import`;
  fs.writeFileSync(temp, `${JSON.stringify(data, null, 2)}\n`);
  try {
    // A hard link creates the file only if nobody did first, so of two first
    // runs at once exactly one import lands, whole.
    fs.linkSync(temp, file);
    return true;
  } catch (error) {
    if (error.code === "EEXIST") return false;
    throw error;
  } finally {
    fs.rmSync(temp, { force: true });
  }
}

export function main(argv, env = process.env, out = process.stdout) {
  const [command, ...rest] = argv;
  try {
    importLegacy(env);
    if (command === "get" && rest.length === 1 && rest[0] === "--json") {
      out.write(`${JSON.stringify(resolve(env))}\n`);
      return 0;
    }
    if (command === "get" && rest.length === 1) {
      need(rest[0]);
      out.write(`${resolve(env)[rest[0]]}\n`);
      return 0;
    }
    if (command === "set" && rest.length === 2) { setValue(rest[0], rest[1], env); return 0; }
    if (command === "unset" && rest.length === 1) { unsetValue(rest[0], env); return 0; }
    process.stderr.write(`${USAGE}\n`);
    return 2;
  } catch (error) {
    process.stderr.write(`forge-config: ${error.message}\n`);
    return error instanceof SettingError ? 2 : 1;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `chmod +x plugins/dr-forge/scripts/forge-config && timeout 120 bash plugins/dr-forge/tests/forge-config.test.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/forge-config plugins/dr-forge/scripts/lib/forge-config.mjs plugins/dr-forge/tests/forge-config.test.sh
git commit -m "feat(dr-forge): add the forge-config command"
```

### Task 13: Cockpit settings module

**Files:**
- Create: `plugins/dr-forge/hooks/cockpit/config.ts`
- Test: `plugins/dr-forge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: Contracts → **`config/schema.mjs`** (Task 11)
- Produces: Contracts → **`hooks/cockpit/config.ts` exports** (all but `HAND_BUILT_SETTINGS` and `schemaRows`, which Task 16 adds)

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-forge/tests/cockpit.test.ts` add the import

```ts
import type { Schema } from '../hooks/cockpit/config'
import { SCHEMA, importedSettings, isValidSetting, resolveSettings, settingProblems, settingWritten } from '../hooks/cockpit/config'
```

and the tests:

```ts
describe('settings file', () => {
  const FAKE: Schema = {
    layout: { type: 'enum', values: ['auto', 'full', 'compact'], default: 'auto', group: 'Cockpit', title: 'Layout', description: 'd', target: 'forge' },
    warnAt: { type: 'number', default: 80, min: 1, max: 99, group: 'Context', title: 'Warn', description: 'd', target: 'forge' },
    handoffTokens: { type: 'number', default: 0, min: 0, max: 2_000_000, env: 'DR_FORGE_BUDGET', group: 'Context', title: 'Budget', description: 'd', target: 'forge' },
    nudgeModel: { type: 'boolean', default: true, group: 'Context', title: 'Nudge', description: 'd', target: 'forge' },
  }

  test('resolves the environment, then the file, then the default', () => {
    expect(resolveSettings(FAKE, { layout: 'full', warnAt: 500, handoffTokens: 300_000 }, { DR_FORGE_BUDGET: '400000' })).toEqual({
      layout: 'full',
      warnAt: 80,
      handoffTokens: 400_000,
      nudgeModel: true,
    })
  })

  test('ignores an environment value that does not fit', () => {
    expect(resolveSettings(FAKE, { handoffTokens: 300_000 }, { DR_FORGE_BUDGET: 'junk' }).handoffTokens).toBe(300_000)
  })

  test('says which values it ignored', () => {
    expect(settingProblems(FAKE, { warnAt: 500, layout: 'full' }, { DR_FORGE_BUDGET: 'junk' })).toEqual([
      'warnAt in ~/.dr-forge/config.json is not valid; ignored',
      'DR_FORGE_BUDGET=junk is not a valid handoffTokens; ignored',
    ])
    expect(settingProblems(FAKE, { layout: 'full' }, {})).toEqual([])
  })

  test('a saved value drops its default and keeps darkmem', () => {
    const darkmem = { url: 'http://d.test', repos: {} }
    expect(settingWritten(FAKE, { darkmem, warnAt: 70 }, 'warnAt', 80)).toEqual({ darkmem })
    expect(settingWritten(FAKE, { darkmem }, 'layout', 'compact')).toEqual({ darkmem, layout: 'compact' })
  })

  test('refuses an unknown key and a value that does not fit', () => {
    expect(() => settingWritten(FAKE, {}, 'nope', true)).toThrow('unknown setting nope')
    expect(() => settingWritten(FAKE, {}, 'layout', 'tiles')).toThrow('tiles is not a valid layout')
  })

  test('imports dr-cockpit options that differ from their defaults, and the darkmem mapping', () => {
    const claude = { pluginConfigs: { 'dr-cockpit@darkraise': { options: { layout: 'compact', warnAt: 80, nudgeModel: 'yes' } } } }
    const darkmem = { url: 'http://d.test', api_key_env: 'DARKMEM_API_KEY', repos: {} }
    expect(importedSettings(FAKE, claude, { darkmem })).toEqual({ layout: 'compact', darkmem })
    expect(importedSettings(FAKE, {}, null)).toEqual({})
  })

  test('every default in the real schema fits its own type', () => {
    for (const spec of Object.values(SCHEMA)) expect(isValidSetting(spec, spec.default)).toBe(true)
  })
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 300 claude plugin test plugins/dr-forge`
Expected: FAIL — `../hooks/cockpit/config` does not exist.

- [ ] **Step 3: Write the module**

`plugins/dr-forge/hooks/cockpit/config.ts`:

```ts
import RAW from '../../config/schema.mjs'

/** A setting's value as the settings file holds it. */
export type SettingValue = boolean | number | string

/** One setting as config/schema.mjs declares it. */
export type SettingSpec = {
  type: 'boolean' | 'number' | 'enum' | 'string'
  default: SettingValue
  group: string
  title: string
  description: string
  target: 'forge' | 'claude'
  env?: string
  min?: number
  max?: number
  step?: number
  values?: readonly string[]
}

export type Schema = Readonly<Record<string, SettingSpec>>

/** ~/.dr-forge/config.json as parsed: schema keys and the reserved darkmem object. */
export type SettingsFile = Record<string, unknown>

export const SCHEMA: Schema = RAW as unknown as Schema

/** Whether a value fits a setting exactly as the file must hold it. */
export function isValidSetting(spec: SettingSpec, value: unknown): value is SettingValue {
  switch (spec.type) {
    case 'boolean':
      return typeof value === 'boolean'
    case 'number':
      return (
        typeof value === 'number' &&
        Number.isFinite(value) &&
        (spec.min === undefined || value >= spec.min) &&
        (spec.max === undefined || value <= spec.max)
      )
    case 'enum':
      return typeof value === 'string' && (spec.values ?? []).includes(value)
    case 'string':
      return typeof value === 'string'
  }
}

/** A value as an environment variable spells it; undefined when it does not fit. */
export function settingFromText(spec: SettingSpec, text: string): SettingValue | undefined {
  const value =
    spec.type === 'boolean'
      ? text === 'true'
        ? true
        : text === 'false'
          ? false
          : undefined
      : spec.type === 'number'
        ? text.trim() === ''
          ? undefined
          : Number(text)
        : text
  return value !== undefined && isValidSetting(spec, value) ? value : undefined
}

/** Every setting in force: the environment variable a key names, then the file, then the default. */
export function resolveSettings(
  schema: Schema,
  file: SettingsFile,
  env: Readonly<Record<string, string | undefined>>,
): Record<string, SettingValue> {
  const values: Record<string, SettingValue> = {}
  for (const [key, spec] of Object.entries(schema)) {
    const raw = spec.env === undefined ? undefined : env[spec.env]
    const fromEnv = raw === undefined || raw === '' ? undefined : settingFromText(spec, raw)
    const stored = file[key]
    values[key] = fromEnv ?? (isValidSetting(spec, stored) ? stored : spec.default)
  }
  return values
}

/** One line for each environment or file value that does not fit its setting and is therefore ignored. */
export function settingProblems(
  schema: Schema,
  file: SettingsFile,
  env: Readonly<Record<string, string | undefined>>,
): string[] {
  const problems: string[] = []
  for (const [key, spec] of Object.entries(schema)) {
    const raw = spec.env === undefined ? undefined : env[spec.env]
    if (raw !== undefined && raw !== '' && settingFromText(spec, raw) === undefined) {
      problems.push(`${spec.env}=${raw} is not a valid ${key}; ignored`)
    }
    if (Object.prototype.hasOwnProperty.call(file, key) && !isValidSetting(spec, file[key])) {
      problems.push(`${key} in ~/.dr-forge/config.json is not valid; ignored`)
    }
  }
  return problems
}

/** The file after one setting is saved: a value equal to its default is dropped, everything else kept. */
export function settingWritten(schema: Schema, file: SettingsFile, key: string, value: SettingValue): SettingsFile {
  const spec = schema[key]
  if (spec === undefined) throw new Error(`unknown setting ${key}`)
  if (!isValidSetting(spec, value)) throw new Error(`${String(value)} is not a valid ${key}`)
  const next: SettingsFile = { ...file }
  if (value === spec.default) delete next[key]
  else next[key] = value
  return next
}

/** The first run's file: dr-cockpit's options that differ from their defaults, and dr-superpowers' darkmem mapping. */
export function importedSettings(schema: Schema, claudeSettings: unknown, oldForge: unknown): SettingsFile {
  const file: SettingsFile = {}
  const options = objectAt(objectAt(objectAt(claudeSettings, 'pluginConfigs'), 'dr-cockpit@darkraise'), 'options')
  for (const [key, spec] of Object.entries(schema)) {
    const value = options?.[key]
    if (isValidSetting(spec, value) && value !== spec.default) file[key] = value
  }
  const darkmem = objectAt(oldForge, 'darkmem')
  if (darkmem !== undefined) file.darkmem = darkmem
  return file
}

function objectAt(value: unknown, key: string): Record<string, unknown> | undefined {
  if (value === null || typeof value !== 'object') return undefined
  const inner = (value as Record<string, unknown>)[key]
  return inner !== null && typeof inner === 'object' && !Array.isArray(inner) ? (inner as Record<string, unknown>) : undefined
}
```

- [ ] **Step 4: Run them to verify they pass**

Run: `timeout 300 claude plugin test plugins/dr-forge && timeout 60 claude plugin validate plugins/dr-forge`
Expected: all tests pass; validation passes.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/hooks/cockpit/config.ts plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): add the cockpit's settings module"
```

### Task 14: Cockpit options read at runtime

**Files:**
- Modify: `plugins/dr-forge/hooks/cockpit/register.tsx`
- Modify: `plugins/dr-forge/types/index.d.ts`

**Interfaces:**
- Consumes: Task 4's cockpit files
- Produces: Contracts → **Cockpit state** (`settings` atom, `liveFrom`, `live`, `applyNotify`)

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 2 = 3

A pure refactor: the options still come from the engine, but every hook reads them through `live($)`, so Task 15 can swap the source without touching the hooks. The suite is the test.

- [ ] **Step 1: Record the baseline**

Run: `timeout 300 claude plugin test plugins/dr-forge`
Expected: all pass (note the count; it must not change).

- [ ] **Step 2: Declare the atom**

In `plugins/dr-forge/types/index.d.ts`, inside `interface PluginState { 'dr-forge': { … } }`, add:

```ts
      /** The settings in force, resolved from the settings file; null until read. */
      settings: Record<string, boolean | number | string> | null
```

In `register.tsx`, beside the other atoms:

```ts
const settings = atom({ plugin: 'dr-forge', key: 'settings' } as const, null)
```

- [ ] **Step 3: Add the top-level helpers**

After `type Tuning = …` in `register.tsx`:

```ts
/** The options with their defaults filled in, and what the pane derives from them. */
type Live = Omit<Options, 'layout'> & {
  layout: 'auto' | 'full' | 'compact'
  tuning: Tuning
  shown: Section[]
  isMinimized: boolean
}

function liveFrom(values: Partial<Options>): Live {
  const {
    handoffTokens = 0,
    nudgeModel = true,
    guardAttribution = true,
    warnAt = 80,
    layout: layoutSetting = 'auto',
    sections = '',
    breakdownRows = 6,
    openAtStart = true,
    limitAlertAt = 90,
    notifyOn = '',
    notifyAfter = 60,
    notifyAskAfter = 20,
    notifyDetail = 'full',
  } = values
  // Anything but the three words reads as auto.
  const layout = layoutSetting === 'full' || layoutSetting === 'compact' ? layoutSetting : 'auto'
  return {
    handoffTokens,
    nudgeModel,
    guardAttribution,
    warnAt,
    layout,
    sections,
    breakdownRows,
    openAtStart,
    limitAlertAt,
    notifyOn,
    notifyAfter,
    notifyAskAfter,
    notifyDetail,
    tuning: { handoffTokens, nudgeModel, warnAt: warnShare(warnAt) },
    shown: sectionsFrom(sections),
    isMinimized: layout === 'compact',
  }
}

/** The options in force now: the settings atom once written, else what Claude Code passed at load. */
async function live($: EngineInterface): Promise<Live> {
  return liveFrom(((await read($, settings)) ?? S.loaded) as Partial<Options>)
}

/** Points the notifier at the options' events, detail and wait. */
function applyNotify(o: Live) {
  S.kinds = o.notifyOn === 'none' ? [] : notifyKindsFrom(o.notifyOn)
  S.isBrief = o.notifyDetail === 'brief'
  S.notifyAskAfter = o.notifyAskAfter
}
```

Add `loaded: {} as Partial<Options>,` to `const S = { … }` (with the comment `// What Claude Code passed at load, until the settings atom is written.`).

- [ ] **Step 4: Replace the load-time options in `register`**

The destructuring block and the derived constants at the top of `register` (from `const {` through `S.notifyAskAfter = notifyAskAfter`) become:

```ts
  S.loaded = options as Partial<Options>
  applyNotify(liveFrom(S.loaded))
  // The settings' autoCompactWindow, read at the start and after each main
  // turn rather than on every tool call.
  let compactWindow: number | undefined
```

Then make exactly these edits, hook by hook. "Insert" lines go where stated; every other row replaces one existing line (matched by its text) with the new text. Quoted setting keys passed to `set(…)`, `setOption(…)`, `number(…)`, `toggle(…)` or `choices(…)` (`'layout'`, `'notifyAfter'`, …) never change.

**`on('session.start', …)`** — insert `    const o = await live($)` directly after the `await $.command.register({ … })` call (Task 15 puts the settings load immediately above it).

| Before | After |
|---|---|
| `    await onBudget($, await refresh($, tuning, compactWindow))` | `    await onBudget($, await refresh($, o.tuning, compactWindow))` |
| `    if (isMinimized) {` | `    if (o.isMinimized) {` |
| `    } else if (openAtStart) void $.ui.open(paneArgs)` | `    } else if (o.openAtStart) void $.ui.open(paneFor(o.layout))` |

**`on('command.run', { command: 'cockpit' }, …)`** — insert `    const o = await live($)` as the hook's first statement.

| Before | After |
|---|---|
| `      : isMinimized` | `      : o.isMinimized` |
| `        : await $.ui.open(paneArgs)` | `        : await $.ui.open(paneFor(o.layout))` |

**`on('session.measure', …)`** — insert `    const o = await live($)` directly after `const done = await next(e)`.

| Before | After |
|---|---|
| `    if (limitAlertAt > 0) {` | `    if (o.limitAlertAt > 0) {` |
| `      for (const limit of await alertLimits($, reading, limitAlertAt)) {` | `      for (const limit of await alertLimits($, reading, o.limitAlertAt)) {` |
| `    if (isMinimized \|\| (await isPaneUp($))) await refreshDetail($)` | `    if (o.isMinimized \|\| (await isPaneUp($))) await refreshDetail($)` |

**`on('session.attach', …)`** — insert `    const o = await live($)` directly after `const joined = await next(e)`.

| Before | After |
|---|---|
| `    if (openAtStart && !isMinimized && e.surface === 'desktop' && !S.isClosedByPerson && !(await isPaneUp($))) void $.ui.open(paneArgs)` | `    if (o.openAtStart && !o.isMinimized && e.surface === 'desktop' && !S.isClosedByPerson && !(await isPaneUp($))) void $.ui.open(paneFor(o.layout))` |

**`on('turn.complete', …)`**

| Before | After |
|---|---|
| `      await onBudget($, await refresh($, tuning, compactWindow))` | `      await onBudget($, await refresh($, (await live($)).tuning, compactWindow))` |
| `      } else if (e.reason === 'answer' && e.durationMs >= Math.max(0, notifyAfter) * 1000) {` | `      } else if (e.reason === 'answer' && e.durationMs >= Math.max(0, (await live($)).notifyAfter) * 1000) {` |

**The attribution block** — `if (guardAttribution) { on('attribution.text', { kind: 'commit' }, …); on('attribution.text', { kind: 'pr' }, …) }` becomes two unconditional hooks, so turning the guard off no longer needs a reload:

```ts
  on('attribution.text', { kind: 'commit' }, async ($, e, next) => ((await live($)).guardAttribution ? { text: '' } : next(e)))
  on('attribution.text', { kind: 'pr' }, async ($, e, next) => ((await live($)).guardAttribution ? { text: '' } : next(e)))
```

**`on('tool.call', …)` and its `.catch`**

| Before | After |
|---|---|
| `    const line = guardAttribution ? attributionLine(tool, e) : undefined` | `    const line = (await live($)).guardAttribution ? attributionLine(tool, e) : undefined` |
| `      await onBudget($, await refresh($, tuning, compactWindow))` | `      await onBudget($, await refresh($, (await live($)).tuning, compactWindow))` |
| `  }).catch(($, e, next) =>` | `  }).catch(async ($, e, next) =>` |
| `    next.called \|\| !guardAttribution ? next(e) : { deny: 'dr-forge: its attribution guard failed.' },` | `    next.called \|\| !(await live($)).guardAttribution ? next(e) : { deny: 'dr-forge: its attribution guard failed.' },` |

**`on('ui.render', { component: 'Pane', requestId: PANE }, …)`** — insert `    const o = await live($)` directly after `const table = $.ui.resolve(e)`. Closures inside this hook (`minimize`, every `onPress`, the settings helpers) use this `o`.

| Before | After |
|---|---|
| `    const isCompact = isMinimized \|\| (layout === 'auto' && e.props.placement === 'inline')` | `    const isCompact = o.isMinimized \|\| (o.layout === 'auto' && e.props.placement === 'inline')` |
| `    const isNearHandoff = head !== null && levelOf(head.tokens, head.limit, tuning.warnAt) !== 'quiet'` | `    const isNearHandoff = head !== null && levelOf(head.tokens, head.limit, o.tuning.warnAt) !== 'quiet'` |
| `              notifyAfter > 0 ? \`${notifyAfter}s\` : 'any',` | `              o.notifyAfter > 0 ? \`${o.notifyAfter}s\` : 'any',` |
| `              () => set('notifyAfter', stepped(notifyAfter, notifyAfter > 60 ? -60 : -15, 0, 3600)),` | `              () => set('notifyAfter', stepped(o.notifyAfter, o.notifyAfter > 60 ? -60 : -15, 0, 3600)),` |
| `              () => set('notifyAfter', stepped(notifyAfter, notifyAfter >= 60 ? 60 : 15, 0, 3600)),` | `              () => set('notifyAfter', stepped(o.notifyAfter, o.notifyAfter >= 60 ? 60 : 15, 0, 3600)),` |
| `` `${notifyAskAfter}s`, `` | `` `${o.notifyAskAfter}s`, `` |
| `              () => set('notifyAskAfter', stepped(notifyAskAfter, -10, 0, 600)),` | `              () => set('notifyAskAfter', stepped(o.notifyAskAfter, -10, 0, 600)),` |
| `              () => set('notifyAskAfter', stepped(notifyAskAfter, 10, 0, 600)),` | `              () => set('notifyAskAfter', stepped(o.notifyAskAfter, 10, 0, 600)),` |
| `            {toggle('openAtStart', 'Show at start', openAtStart)}` | `            {toggle('openAtStart', 'Show at start', o.openAtStart)}` |
| `            {choices('layout', 'Layout', ['auto', 'full', 'compact'] as const, layout)}` | `            {choices('layout', 'Layout', ['auto', 'full', 'compact'] as const, o.layout)}` |
| `              name => shown.includes(name as Section),` | `              name => o.shown.includes(name as Section),` |
| `              name => set('sections', sectionsToggled(shown, name as Section)),` | `              name => set('sections', sectionsToggled(o.shown, name as Section)),` |
| `              handoffTokens > 0 ? kTokens(handoffTokens) : 'auto',` | `              o.handoffTokens > 0 ? kTokens(o.handoffTokens) : 'auto',` |
| `              () => set('handoffTokens', stepped(handoffTokens, -HANDOFF_STEP, 0, MAX_HANDOFF)),` | `              () => set('handoffTokens', stepped(o.handoffTokens, -HANDOFF_STEP, 0, MAX_HANDOFF)),` |
| `              () => set('handoffTokens', stepped(handoffTokens, HANDOFF_STEP, 0, MAX_HANDOFF)),` | `              () => set('handoffTokens', stepped(o.handoffTokens, HANDOFF_STEP, 0, MAX_HANDOFF)),` |
| `` `${warnPercent}%`, `` | `` `${o.warnAt}%`, `` |
| `              () => set('warnAt', stepped(warnPercent, -5, 5, 95)),` | `              () => set('warnAt', stepped(o.warnAt, -5, 5, 95)),` |
| `              () => set('warnAt', stepped(warnPercent, 5, 5, 95)),` | `              () => set('warnAt', stepped(o.warnAt, 5, 5, 95)),` |
| `              limitAlertAt > 0 ? \`${limitAlertAt}%\` : 'off',` | `              o.limitAlertAt > 0 ? \`${o.limitAlertAt}%\` : 'off',` |
| `              () => set('limitAlertAt', stepped(limitAlertAt, -5, 0, 100)),` | `              () => set('limitAlertAt', stepped(o.limitAlertAt, -5, 0, 100)),` |
| `              () => set('limitAlertAt', stepped(limitAlertAt, 5, 0, 100)),` | `              () => set('limitAlertAt', stepped(o.limitAlertAt, 5, 0, 100)),` |
| `              String(breakdownRows),` | `              String(o.breakdownRows),` |
| `              () => set('breakdownRows', stepped(breakdownRows, -1, 0, MAX_BREAKDOWN_ROWS)),` | `              () => set('breakdownRows', stepped(o.breakdownRows, -1, 0, MAX_BREAKDOWN_ROWS)),` |
| `              () => set('breakdownRows', stepped(breakdownRows, 1, 0, MAX_BREAKDOWN_ROWS)),` | `              () => set('breakdownRows', stepped(o.breakdownRows, 1, 0, MAX_BREAKDOWN_ROWS)),` |
| `            {toggle('nudgeModel', 'Handoff note', nudgeModel)}` | `            {toggle('nudgeModel', 'Handoff note', o.nudgeModel)}` |
| `            {toggle('guardAttribution', 'Attr. guard', guardAttribution)}` | `            {toggle('guardAttribution', 'Attr. guard', o.guardAttribution)}` |
| `                if (isMinimized) await $.ui.close({ id: PANE })` | `                if (o.isMinimized) await $.ui.close({ id: PANE })` |
| `    const breakdownShown = (rows?.rows ?? []).slice(0, Math.max(0, Math.min(MAX_BREAKDOWN_ROWS, breakdownRows)))` | `    const breakdownShown = (rows?.rows ?? []).slice(0, Math.max(0, Math.min(MAX_BREAKDOWN_ROWS, o.breakdownRows)))` |
| `          {shown.includes('account') && panels.account}` | `          {o.shown.includes('account') && panels.account}` |
| `          {shown.filter(name => name !== 'account').map(name => panels[name])}` | `          {o.shown.filter(name => name !== 'account').map(name => panels[name])}` |
| `          {!shown.includes('context') && actions}` (twice) | `          {!o.shown.includes('context') && actions}` |
| `        {shown.map(name => byName[name])}` | `        {o.shown.map(name => byName[name])}` |

**`on('ui.render', { component: 'AbovePrompt' }, …)`** becomes:

```ts
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const o = await live($)
    return !o.isMinimized || e.props.hasSurvey ? next(e) : drawBand($, e, () => expand($, e.viewport?.isFullscreen === true))
  })
```

Check: `grep -nwE 'paneArgs|warnPercent|sectionList|tuning|shown|isMinimized' plugins/dr-forge/hooks/cockpit/register.tsx | grep -v 'o\.\(tuning\|shown\|isMinimized\)\|tuning:\|isMinimized:\|shown:\|tuning\.\|: Tuning\|Tuning ='` lists nothing inside `register` (the matches left are in `liveFrom`, `refresh`'s parameter and type declarations).

- [ ] **Step 5: Run the suite**

Run: `timeout 60 claude plugin validate plugins/dr-forge && timeout 300 claude plugin test plugins/dr-forge`
Expected: validation passes; the same count as Step 1, all pass. A "hooks module did not load … is not a function declared at the top of this file" failure means `$` reached a closure: move that helper to the top level.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-forge/hooks/cockpit/register.tsx plugins/dr-forge/types/index.d.ts
git commit -m "refactor(dr-forge): read cockpit options at runtime"
```

### Task 15: Cockpit options from the settings file

**Files:**
- Modify: `plugins/dr-forge/hooks/cockpit/register.tsx`
- Modify: `plugins/dr-forge/.claude-plugin/plugin.json` (remove `userConfig`)
- Test: `plugins/dr-forge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: Contracts → **Cockpit state** (Task 14), **`hooks/cockpit/config.ts` exports** (Task 13)
- Produces: Contracts → **Cockpit state** (`configFile`, `readSettingsFile`, `applySettings`, `loadSettings`)

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Move the tests to a settings file**

In `plugins/dr-forge/tests/cockpit.test.ts`:

```ts
const CONFIG = '/home/me/.dr-forge/config.json'

/** A settings file holding these values, as files for signedIn. */
function configured(values: Record<string, unknown>): NonNullable<World['files']> {
  return { [CONFIG]: { text: JSON.stringify(values) } }
}
```

Add to `type World`:

```ts
  /** ~/.dr-forge/config.json's values; set, HOME is /home/me and world answers reads of the file. */
  config?: Record<string, unknown>
  /** Every write fails, as on a read-only file system. */
  isReadOnly?: boolean
```

In `world()`: `mock.env(on, { ...(w.config === undefined ? {} : { HOME: '/home/me' }), ...(w.env ?? {}) })`; the `fs.write` hook throws `new Error('EROFS: read-only file system')` when `w.isReadOnly`; and, when `w.config !== undefined`:

```ts
  if (w.config !== undefined) {
    on('fs.read', (_$, e) => {
      if (e.path === CONFIG) return { value: w.written?.[CONFIG] ?? JSON.stringify(w.config) }
      throw new Error('ENOENT')
    })
  }
```

Then convert every test that passes `{ options: { … } }`: drop the options argument, pass the same values as `config` to `world` (or through `signedIn(on, { ...configured({ … }), …files })` in a test that calls `signedIn`, never both), and call `await $.session.start(START)` right after the fixture setup when the test does not already start the session. Convert the `config.set` tests to file assertions, for example `writes each press through /config` becomes:

```ts
  for (const surface of SURFACES) {
    test(`writes each press to the settings file on ${surface}`, async ($, on) => {
      const written: Record<string, string> = {}
      world(on, { tokens: 284_000, config: { openAtStart: false }, written })
      await $.session.start(START)
      await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 'turn-0', reason: 'answer' })
      const ui = await $.ui.mount({ ...PANE, surface })
      await ui.press({ key: 'pane-settings' })
      await ui.press({ key: 'set-openAtStart-toggle' })
      await ui.press({ key: 'set-warnAt-more' })
      await ui.press({ key: 'set-layout-compact' })
      await ui.press({ key: 'set-section-guard' })
      expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({
        warnAt: 85,
        layout: 'compact',
        sections: 'account,context,usage,shells,agents,plan,repo',
      })
      await ui.press({ key: 'settings-back' })
      expect(await ui.find({ key: 'pane-settings' })).toBeDefined()
    })
  }
```

and `says when a setting is refused` uses `world(on, { tokens: 284_000, toasts, config: {}, isReadOnly: true })` and expects `toasts.some(text => text.startsWith('dr-forge: guardAttribution not saved:'))` to be true. The other `config.set` tests (Minimize, Expand, the band's Expand, Back) assert the `layout` in `JSON.parse(written[CONFIG])` instead of the `config.set` call. Add:

```ts
  test('a settings file that is not JSON is left alone', async ($, on) => {
    const toasts: string[] = []
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, toasts, written, config: {} })
    on('fs.read', (_$, e) => (e.path === CONFIG ? { value: 'not json' } : Promise.reject(new Error('ENOENT'))))
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'set-guardAttribution-toggle' })
    expect(written[CONFIG]).toBeUndefined()
    expect(toasts.some(text => text.startsWith('dr-forge: guardAttribution not saved:'))).toBe(true)
  })
```

If the kit calls the test's later `fs.read` hook after world's, drop `config: {}` from that test's `world` call and keep only its own hook plus `env: { HOME: '/home/me' }`.

Add three more tests to the settings describe block:

```ts
  test('the first session opens the way the saved settings say', async ($, on) => {
    const opened: string[] = []
    world(on, { tokens: 284_000, opened, config: { layout: 'compact' } })
    await $.session.start(START)
    expect(opened).toEqual([])
  })

  test('a budget override above the schema maximum is ignored', async ($, on) => {
    world(on, { tokens: 340_000, config: {}, env: { DR_FORGE_BUDGET: '3000000' } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^73%$/ })).toBeDefined()
  })

  test('the settings view says which saved values it ignored', async ($, on) => {
    world(on, { tokens: 284_000, config: { warnAt: 500 } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    expect(await ui.find({ type: 'Text', text: /warnAt in ~\/\.dr-forge\/config\.json is not valid; ignored/ })).toBeDefined()
  })
```

(`opened` is the World field the pane-opening tests already use; 340k of the rule's 465k budget is the 73% the `warnAt` test reads.)

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 300 claude plugin test plugins/dr-forge`
Expected: FAIL — the mod still reads `/config` options, so the file values have no effect and nothing is written to it.

- [ ] **Step 3: Read and write the file**

Import from `./config`: `SCHEMA`, `resolveSettings`, `settingProblems`, `settingWritten` and the types `SettingValue`, `SettingsFile`. Add `settingProblems: [] as string[],` to `S` (comment: `// Saved or environment values the settings in force ignored, for the settings view.`). Add top-level functions:

```ts
/** ~/.dr-forge/config.json, or null when no home directory is set. */
async function configFile($: EngineInterface): Promise<string | null> {
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
  return home ? `${home.replace(/[\\/]+$/, '')}/.dr-forge/config.json` : null
}

/** The settings file's object: {} when it does not exist, null when it exists but is not a JSON object. */
async function readSettingsFile($: EngineInterface, path: string): Promise<SettingsFile | null> {
  let text: string
  try {
    text = String(await $.fs.read(path))
  } catch {
    return (await $.fs.exists(path).catch(() => false)) ? null : {}
  }
  try {
    const data: unknown = JSON.parse(text)
    return data !== null && typeof data === 'object' && !Array.isArray(data) ? (data as SettingsFile) : null
  } catch {
    return null
  }
}

/** Puts a settings file in force: the atom every hook reads through live(), and the notifier. */
async function applySettings($: EngineInterface, file: SettingsFile) {
  const budget = (await $.env.get('DR_FORGE_BUDGET')) || (await $.env.get('DR_SUPERPOWERS_BUDGET'))
  const values = resolveSettings(SCHEMA, file, { DR_FORGE_BUDGET: budget })
  S.settingProblems = settingProblems(SCHEMA, file, { DR_FORGE_BUDGET: budget })
  await update($, settings, () => values)
  applyNotify(liveFrom(values as Partial<Options>))
}

/** Reads ~/.dr-forge/config.json into force; a missing or unreadable file means the defaults. */
async function loadSettings($: EngineInterface) {
  const path = await configFile($)
  await applySettings($, (path === null ? {} : await readSettingsFile($, path)) ?? {})
}
```

`setOption` becomes:

```ts
/** Saves one setting to ~/.dr-forge/config.json and puts it in force, saying why if it could not; resolves whether it was saved. */
async function setOption($: EngineInterface, key: string, value: SettingValue): Promise<boolean> {
  const path = await configFile($)
  const file = path === null ? null : await readSettingsFile($, path)
  try {
    if (path === null) throw new Error('no home directory is set')
    if (file === null) throw new Error(`${path} is not a JSON object; fix or remove it`)
    const next = settingWritten(SCHEMA, file, key, value)
    await $.fs.write(path, `${JSON.stringify(next, null, 2)}\n`)
    await applySettings($, next)
    return true
  } catch (error) {
    $.ui.toast(`dr-forge: ${key} not saved: ${error instanceof Error ? error.message : String(error)}`)
    return false
  }
}
```

Callers pass the value they pass today (`ConfigValue` widened to `SettingValue` in the view's `set` helper).

In `register`: drop the `options` parameter use (`export const register: Register = on => {`), delete `S.loaded = options as Partial<Options>` and `applyNotify(liveFrom(S.loaded))`, and insert `    await loadSettings($)` in the `session.start` hook directly above the `const o = await live($)` line Task 14 placed after `$.command.register(…)`, so `o` holds the saved settings. In `refresh`, the budget now comes only from the resolved setting (which already applied `DR_FORGE_BUDGET` and rejected values outside the schema): `const limit = budgetFor(handoffTokens, undefined, window, compactWindow)`, deleting the two `$.env.get` budget reads Task 5 put there. Delete the session.start comment that begins "Saving a setting reloads the mod" (a save no longer reloads it) but keep the code it explains. Remove `loaded` from `S` and make `live` read `liveFrom(((await read($, settings)) ?? {}) as Partial<Options>)`. The settings view's footer text becomes `Saved to ~/.dr-forge/config.json.` and, directly below it, `{S.settingProblems.map((problem, index) => <Text key={`set-problem-${index}`} color="yellow">⚠ {problem}</Text>)}`.

In `plugins/dr-forge/.claude-plugin/plugin.json` delete the `"userConfig"` object.

- [ ] **Step 4: Run them to verify they pass**

Run: `timeout 60 claude plugin validate plugins/dr-forge && timeout 300 claude plugin test plugins/dr-forge && timeout 60 node scripts/validate-repository.mjs`
Expected: validation passes, every test passes, the repository validator prints its valid line. `grep -n "config.set\|dr-forge\.\${key}" plugins/dr-forge/hooks/cockpit/register.tsx` → no output.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/hooks/cockpit/register.tsx plugins/dr-forge/.claude-plugin/plugin.json plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): keep cockpit settings in ~/.dr-forge"
```

### Task 16: Settings view drawn from the schema, and first-run import

**Files:**
- Modify: `plugins/dr-forge/hooks/cockpit/config.ts`, `plugins/dr-forge/hooks/cockpit/register.tsx`
- Test: `plugins/dr-forge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: Contracts → **Cockpit state** (Task 15), **`hooks/cockpit/config.ts` exports** (Task 13)
- Produces: `SettingRow` and `schemaRows` in Contracts → **`hooks/cockpit/config.ts` exports**

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5

The settings view walks the schema group by group (Cockpit, Context, Notifications), one row per key. A key with a control of its own today keeps it (same label, keys and hotkeys); any other key gets a control chosen by its type. Then the first session imports the pre-2.0 settings.

- [ ] **Step 1: Write the failing tests**

Add `schemaRows` to the `../hooks/cockpit/config` import, and inside `describe('settings file', …)`:

```ts
  test('a row for each setting without a control of its own, in schema order', () => {
    const rows = schemaRows(FAKE, { layout: 'full', warnAt: 70 }, new Set(['layout']))
    expect(rows.map(row => [row.key, row.kind, row.value])).toEqual([
      ['warnAt', 'stepper', 70],
      ['handoffTokens', 'stepper', 0],
      ['nudgeModel', 'toggle', true],
    ])
    expect(rows[0]).toMatchObject({ group: 'Context', min: 1, max: 99, step: 1 })
  })
```

In the pane tests' settings describe block:

```ts
  // The control each setting is drawn with; a schema key missing here, or a
  // control the view stops drawing, fails the test.
  const CONTROL: Record<string, string> = {
    openAtStart: 'set-openAtStart-toggle',
    layout: 'set-layout-auto',
    sections: 'set-section-account',
    breakdownRows: 'set-breakdownRows-more',
    guardAttribution: 'set-guardAttribution-toggle',
    handoffTokens: 'set-handoffTokens-more',
    warnAt: 'set-warnAt-more',
    nudgeModel: 'set-nudgeModel-toggle',
    limitAlertAt: 'set-limitAlertAt-more',
    notifyOn: 'set-notify-kind-ask',
    notifyAfter: 'set-notifyAfter-more',
    notifyAskAfter: 'set-notifyAskAfter-more',
    notifyDetail: 'set-notifyDetail-full',
  }

  test('draws every setting under its schema group', async ($, on) => {
    world(on, { tokens: 284_000, config: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    expect(Object.keys(CONTROL).sort()).toEqual(Object.keys(SCHEMA).sort())
    for (const key of Object.values(CONTROL)) expect(await ui.find({ key })).toBeDefined()
    for (const group of ['Cockpit', 'Context']) expect(await ui.find({ type: 'Text', text: group })).toBeDefined()
    expect(await ui.find({ key: 'set-group-Notifications' })).toBeDefined()
  })

  const STORE_FILE = '/home/me/.claude/plugins/store/dr-cockpit_darkraise-abc123.json'
  const OLD_FORGE = '/home/me/.dr-superpowers/config.json'
  const DARKMEM = { url: 'http://d.test', repos: {} }
  const OLD_FILES = {
    [STORE_FILE]: JSON.stringify({ notifyUrl: 'https://discord.com/api/webhooks/1/abc', notifyMention: '42' }),
    [OLD_FORGE]: JSON.stringify({ darkmem: DARKMEM }),
  }
  /** A file system that keeps what the plugin writes, over these starting files. */
  function disk(on: On, written: Record<string, string>, files: Record<string, string>) {
    on('fs.read', (_$, e) => {
      const text = written[e.path] ?? files[e.path]
      if (text === undefined) throw new Error('ENOENT')
      return { value: text }
    })
    on('fs.exists', (_$, e) => ({ value: e.path in written || e.path in files }))
  }
  const legacy = (warnAt: number) => ({ pluginConfigs: { 'dr-cockpit@darkraise': { options: { warnAt } } } })
  // world's fs.list names the store file through `files`.
  const LISTED = { [STORE_FILE]: { text: '' } }

  test('the first session imports the cockpit options, darkmem and the webhook', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, written, env: { HOME: '/home/me' }, settings: legacy(70), files: LISTED })
    disk(on, written, OLD_FILES)
    await $.session.start(START)
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ warnAt: 70, darkmem: DARKMEM })
    expect(await $.store.get('notifyUrl')).toBe('https://discord.com/api/webhooks/1/abc')
    expect(await $.store.get('notifyMention')).toBe('42')
  })

  test('a later session imports nothing again', async ($, on) => {
    const written: Record<string, string> = {}
    const w: World = { tokens: 284_000, written, env: { HOME: '/home/me' }, settings: legacy(70), files: LISTED }
    world(on, w)
    disk(on, written, OLD_FILES)
    await $.session.start(START)
    w.settings = legacy(60)
    await $.store.delete('notifyUrl')
    await $.session.start(START)
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ warnAt: 70, darkmem: DARKMEM })
    expect(await $.store.get('notifyUrl')).toBeUndefined()
  })

  test('a webhook already set is kept', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, written, env: { HOME: '/home/me' }, settings: legacy(70), files: LISTED })
    disk(on, written, OLD_FILES)
    await $.store.set('notifyUrl', 'https://discord.com/api/webhooks/2/mine')
    await $.session.start(START)
    expect(await $.store.get('notifyUrl')).toBe('https://discord.com/api/webhooks/2/mine')
  })

  test('a settings file forge-config wrote first is kept, and the webhook still comes over', async ($, on) => {
    const written: Record<string, string> = { [CONFIG]: JSON.stringify({ layout: 'full' }) }
    world(on, { tokens: 284_000, written, env: { HOME: '/home/me' }, settings: legacy(70), files: LISTED })
    disk(on, written, OLD_FILES)
    await $.session.start(START)
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ layout: 'full' })
    expect(await $.store.get('notifyUrl')).toBe('https://discord.com/api/webhooks/1/abc')
  })
```

(`settings` feeds `$.settings.read` through world's `settings.read` hook, which reads `w.settings` on each call. The store tests use the test's `$.store` the way the existing webhook tests do — `grep -n "store\." plugins/dr-forge/tests/cockpit.test.ts`; if those tests reach the plugin's store another way, use theirs.)

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 300 claude plugin test plugins/dr-forge`
Expected: FAIL — `schemaRows`, the group headers and the import do not exist.

- [ ] **Step 3: Add the rows to config.ts**

```ts
/** One settings-view row drawn from the schema. */
export type SettingRow = {
  key: string
  group: string
  title: string
  kind: 'toggle' | 'choices' | 'stepper' | 'text'
  value: SettingValue
  values: readonly string[]
  min: number
  max: number
  step: number
}

/** A row for each setting the view has no control of its own for, in schema order. */
export function schemaRows(
  schema: Schema,
  values: Readonly<Record<string, SettingValue>>,
  custom: ReadonlySet<string>,
): SettingRow[] {
  return Object.entries(schema)
    .filter(([key]) => !custom.has(key))
    .map(([key, spec]) => ({
      key,
      group: spec.group,
      title: spec.title,
      kind: spec.type === 'boolean' ? 'toggle' : spec.type === 'enum' ? 'choices' : spec.type === 'number' ? 'stepper' : 'text',
      value: values[key] ?? spec.default,
      values: spec.values ?? [],
      min: spec.min ?? 0,
      max: spec.max ?? Number.MAX_SAFE_INTEGER,
      step: spec.step ?? 1,
    }))
}
```

- [ ] **Step 4: Draw the view from the schema**

In `register.tsx` the `./config` import becomes:

```ts
import { SCHEMA, importedSettings, resolveSettings, schemaRows, settingProblems, settingWritten } from './config'
import type { SettingRow, SettingValue, SettingsFile } from './config'
```

In the settings view, the `set` helper and the `toggle`, `choices` and `number` helpers take `key: string` (not `keyof Options`), and `set` takes `value: SettingValue`:

```ts
      const set = (key: string, value: SettingValue) => setOption($, key, value)
```

`notifyRows` is renamed `webhookRows` and keeps only the inside of today's `set-notify-rows` box — the Webhook row, the last-send line and the Mention row — as a fragment:

```tsx
      const webhookRows = (
        <Box key="set-notify-webhook" flexDirection="column">
          {/* today's Webhook row, last-send line and Mention row, unchanged */}
        </Box>
      )
```

(the "Notifications (Discord)" heading, the `Send on` chips and the `Done after`, `Ask after` and `Detail` rows move into `custom` below). Then, in place of today's `return (<Box flexDirection="column"><Text bold>Settings</Text> … </Box>)` block up to and including the `settings-actions` box:

```tsx
      const custom: Record<string, RenderChildren> = {
        openAtStart: toggle('openAtStart', 'Show at start', o.openAtStart),
        layout: choices('layout', 'Layout', ['auto', 'full', 'compact'] as const, o.layout),
        sections: (
          <Box key="set-sections-block" flexDirection="column">
            <Text key="set-sections">Sections</Text>
            {/* Under their label, wrapping to the pane's width. */}
            {chips(
              'set-section',
              SECTIONS,
              name => o.shown.includes(name as Section),
              name => name,
              name => set('sections', sectionsToggled(o.shown, name as Section)),
            )}
          </Box>
        ),
        breakdownRows: number(
          'breakdownRows',
          'Context rows',
          String(o.breakdownRows),
          () => set('breakdownRows', stepped(o.breakdownRows, -1, 0, MAX_BREAKDOWN_ROWS)),
          () => set('breakdownRows', stepped(o.breakdownRows, 1, 0, MAX_BREAKDOWN_ROWS)),
        ),
        guardAttribution: toggle('guardAttribution', 'Attr. guard', o.guardAttribution),
        handoffTokens: number(
          'handoffTokens',
          'Handoff budget',
          o.handoffTokens > 0 ? kTokens(o.handoffTokens) : 'auto',
          () => set('handoffTokens', stepped(o.handoffTokens, -HANDOFF_STEP, 0, MAX_HANDOFF)),
          () => set('handoffTokens', stepped(o.handoffTokens, HANDOFF_STEP, 0, MAX_HANDOFF)),
        ),
        warnAt: number(
          'warnAt',
          'Warn at',
          `${o.warnAt}%`,
          () => set('warnAt', stepped(o.warnAt, -5, 5, 95)),
          () => set('warnAt', stepped(o.warnAt, 5, 5, 95)),
        ),
        nudgeModel: toggle('nudgeModel', 'Handoff note', o.nudgeModel),
        limitAlertAt: number(
          'limitAlertAt',
          'Limit alert at',
          o.limitAlertAt > 0 ? `${o.limitAlertAt}%` : 'off',
          () => set('limitAlertAt', stepped(o.limitAlertAt, -5, 0, 100)),
          () => set('limitAlertAt', stepped(o.limitAlertAt, 5, 0, 100)),
        ),
        notifyOn: (
          <Box key="set-notify-on-block" flexDirection="column">
            <Text key="set-notify-on">Send on</Text>
            {chips(
              'set-notify-kind',
              NOTIFY_KINDS,
              kind => S.kinds.includes(kind as NotifyKind),
              kind => kindLabel(kind as NotifyKind),
              kind => set('notifyOn', notifyKindsToggled(S.kinds, kind as NotifyKind)),
            )}
          </Box>
        ),
        notifyAfter: number(
          'notifyAfter',
          'Done after',
          o.notifyAfter > 0 ? `${o.notifyAfter}s` : 'any',
          () => set('notifyAfter', stepped(o.notifyAfter, o.notifyAfter > 60 ? -60 : -15, 0, 3600)),
          () => set('notifyAfter', stepped(o.notifyAfter, o.notifyAfter >= 60 ? 60 : 15, 0, 3600)),
        ),
        notifyAskAfter: number(
          'notifyAskAfter',
          'Ask after',
          `${o.notifyAskAfter}s`,
          () => set('notifyAskAfter', stepped(o.notifyAskAfter, -10, 0, 600)),
          () => set('notifyAskAfter', stepped(o.notifyAskAfter, 10, 0, 600)),
        ),
        notifyDetail: choices('notifyDetail', 'Detail', ['full', 'brief'] as const, S.isBrief ? 'brief' : 'full'),
      }
      const typed = schemaRows(SCHEMA, (await read($, settings)) ?? {}, new Set(Object.keys(custom)))
      const drawTyped = (one: SettingRow) =>
        one.kind === 'toggle'
          ? toggle(one.key, one.title, one.value === true)
          : one.kind === 'choices'
            ? choices(one.key, one.title, one.values, String(one.value))
            : one.kind === 'stepper'
              ? number(
                  one.key,
                  one.title,
                  String(one.value),
                  () => set(one.key, stepped(Number(one.value), -one.step, one.min, one.max)),
                  () => set(one.key, stepped(Number(one.value), one.step, one.min, one.max)),
                )
              : row(`set-${one.key}`, one.title, <Text key={`set-${one.key}-value`} dimColor>{`${String(one.value) || '(empty)'} · forge-config set ${one.key}`}</Text>)
      const groups = [...new Set(Object.values(SCHEMA).map(spec => spec.group))]

      return (
        <Box flexDirection="column">
          <Text bold>Settings</Text>
          {groups.map(group => (
            <Box key={`set-group-${group}`} flexDirection="column">
              {group === 'Notifications' ? (
                <Text bold>
                  Notifications <Text dimColor>(Discord)</Text>
                </Text>
              ) : (
                <Text bold>{group}</Text>
              )}
              <Box key={`set-group-${group}-rows`} flexDirection="column" paddingLeft={INDENT}>
                {group === 'Notifications' && webhookRows}
                {Object.entries(SCHEMA)
                  .filter(([, spec]) => spec.group === group)
                  .map(([key]) => custom[key] ?? typed.filter(one => one.key === key).map(drawTyped))}
              </Box>
            </Box>
          ))}
          <Text dimColor>Saved to ~/.dr-forge/config.json.</Text>
          {S.settingProblems.map((problem, index) => (
            <Text key={`set-problem-${index}`} color="yellow">
              ⚠ {problem}
            </Text>
          ))}
          {/* today's settings-actions box with the Back button, unchanged */}
        </Box>
      )
```

`stepped` must accept the typed rows' bounds as numbers (it already takes `(value, step, min, max)`). With today's schema every key has a control of its own, so `typed` is empty; Spec 2's Workflow group arrives through it.

- [ ] **Step 5: Import once**

Add a store key constant `const STORE_IMPORTED = 'webhookImported'` beside `STORE_URL`, and these top-level functions:

```ts
/** The first run: dr-cockpit's options and dr-superpowers' darkmem mapping, written to the new file. */
async function importSettings($: EngineInterface, path: string): Promise<SettingsFile> {
  const claude = await $.settings.read({ source: 'user' }).catch(() => ({}))
  const home = path.slice(0, -'/.dr-forge/config.json'.length)
  const old = await $.fs
    .read(`${home}/.dr-superpowers/config.json`)
    .then(text => JSON.parse(String(text)) as unknown)
    .catch(() => null)
  const file = importedSettings(SCHEMA, claude, old)
  await $.fs.write(path, `${JSON.stringify(file, null, 2)}\n`).catch(() => undefined)
  return file
}

/** Once per machine: dr-cockpit's Discord webhook and mention, from its store file into this plugin's store. */
async function importWebhook($: EngineInterface) {
  if ((await $.store.get(STORE_IMPORTED)) === true) return
  await $.store.set(STORE_IMPORTED, true)
  if ((await $.store.get(STORE_URL)) !== undefined) return
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
  const configDir = (await $.env.get('CLAUDE_CONFIG_DIR')) || (home ? `${home.replace(/[\\/]+$/, '')}/.claude` : '')
  if (!configDir) return
  const dir = `${configDir}/plugins/store`
  const entry = (await $.fs.list(dir).catch(() => [])).find(one => one.name.startsWith('dr-cockpit_darkraise-') && one.name.endsWith('.json'))
  if (entry === undefined) return
  const old = await $.fs
    .read(`${dir}/${entry.name}`)
    .then(text => JSON.parse(String(text)) as Record<string, unknown>)
    .catch(() => null)
  if (old === null) return
  if (typeof old.notifyUrl === 'string' && isDiscordWebhook(old.notifyUrl)) await $.store.set(STORE_URL, old.notifyUrl)
  if (typeof old.notifyMention === 'string') await $.store.set(STORE_MENTION, old.notifyMention)
}
```

`loadSettings` becomes:

```ts
/** Reads ~/.dr-forge/config.json into force, importing the pre-2.0 settings on the first run. */
async function loadSettings($: EngineInterface) {
  const path = await configFile($)
  if (path === null) return applySettings($, {})
  let file = await readSettingsFile($, path)
  if (file !== null && Object.keys(file).length === 0 && !(await $.fs.exists(path).catch(() => false))) {
    file = await importSettings($, path)
  }
  await applySettings($, file ?? {})
  await importWebhook($).catch(() => undefined)
}
```

`loadSettings` already runs before `readNotifier` in `session.start`, so an imported webhook shows in the same session. The mod cannot create a file exclusively (`$.fs` has no rename or exclusive create), so a cockpit and a `forge-config` starting in the same instant may both import; both write the same machine's pre-2.0 settings, and the later write wins.

- [ ] **Step 6: Run them to verify they pass**

Run: `timeout 60 claude plugin validate plugins/dr-forge && timeout 300 claude plugin test plugins/dr-forge`
Expected: validation passes; every test passes, including the existing `writes each press to the settings file` and Back tests.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-forge/hooks/cockpit/config.ts plugins/dr-forge/hooks/cockpit/register.tsx plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): draw settings from the schema, import once"
```

### Task 17: Cockpit reads the state directory through the rule

**Files:**
- Modify: `plugins/dr-forge/hooks/cockpit/lib.ts`, `plugins/dr-forge/hooks/cockpit/register.tsx`
- Test: `plugins/dr-forge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: the path rule (Global Constraints)
- Produces: `stateLeaf(names)` in `lib.ts`

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

Add `stateLeaf` to the `../hooks/cockpit/lib` import and:

```ts
test('the state directory is .forge unless only .superpowers exists', () => {
  expect(stateLeaf(new Set())).toBe('.forge')
  expect(stateLeaf(new Set(['.superpowers']))).toBe('.superpowers')
  expect(stateLeaf(new Set(['.forge', '.superpowers']))).toBe('.forge')
})
```

Find the Run-card test that serves a ledger at `/home/me/code/shop/.superpowers/sdd/<run>/progress.md` (`grep -n "superpowers/sdd" plugins/dr-forge/tests/cockpit.test.ts`) and add a copy whose files live under `/home/me/code/shop/.forge/sdd/<run>/`, with the same assertions. Find the Resume test (`grep -n "pane-resume" plugins/dr-forge/tests/cockpit.test.ts`): it keeps its `.superpowers/handoff/latest.md` file and now also asserts the submitted prompt names `.superpowers/handoff/latest.md`; add a copy with the handoff at `.forge/handoff/latest.md` asserting the prompt names `.forge/handoff/latest.md`.

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 300 claude plugin test plugins/dr-forge`
Expected: FAIL — `stateLeaf` does not exist and `.forge/` ledgers are not read.

- [ ] **Step 3: Implement**

`lib.ts`:

```ts
/** The repository's state directory name, as scripts/lib/forge-dir.sh picks it: .forge unless only .superpowers exists. */
export function stateLeaf(names: ReadonlySet<string>): string {
  return !names.has('.forge') && names.has('.superpowers') ? '.superpowers' : '.forge'
}
```

`register.tsx`: add `stateLeaf,` to its `import { … } from './lib'` list (beside `isSuperpowers`), add `stateLeaf: '.forge',` to `S` (comment: `// The state directory's name in the primary checkout, as last read.`) and the top-level function

```ts
/** The state directory under a checkout: .forge, or the pre-2.0 .superpowers where only that exists. */
async function stateDirOf($: EngineInterface, root: string): Promise<string> {
  const names = new Set((await $.fs.list(root).catch(() => [])).map(entry => entry.name))
  S.stateLeaf = stateLeaf(names)
  return `${root}/${S.stateLeaf}`
}
```

In `readRun`: `const state = await stateDirOf($, root)` after the `root === null` return, then `` `${state}/handoff/latest.md` `` and `` const base = `${state}/sdd` ``. Replace the `RESUME_PROMPT` constant with

```ts
function resumePrompt(): string {
  return `Resume the work in ${S.stateLeaf}/handoff/latest.md with the dr-forge resume-execution skill.`
}
```

and its use with `resumePrompt()`. The `tool.call` re-read test becomes `/\.forge|\.superpowers|finish-choice/`. The comments naming `.superpowers/` say `.forge/ (.superpowers/ before 2.0)`.

- [ ] **Step 4: Run them to verify they pass**

Run: `timeout 60 claude plugin validate plugins/dr-forge && timeout 300 claude plugin test plugins/dr-forge`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/hooks/cockpit/lib.ts plugins/dr-forge/hooks/cockpit/register.tsx plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): read .forge or .superpowers in the cockpit"
```

### Task 18: Skills and references resolve the directories

**Files:**
- Modify: every file under `plugins/dr-forge/skills/`, `plugins/dr-forge/reference/`, `plugins/dr-forge/criteria/`, `plugins/dr-forge/agents/` that names `.superpowers` or `docs/superpowers` (one substitution to the `<state>`/`<docs>` placeholders), except `reference/legacy-names.md`
- Modify: `plugins/dr-forge/reference/project-state.md`, `plugins/dr-forge/skills/using-superpowers/SKILL.md`

**Interfaces:**
- Consumes: Tasks 8-9 (scripts already resolve by rule); Contracts → **`scripts/forge-path`** (Task 7)
- Produces: Contracts → **`<state>` and `<docs>`**

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Name the two directories by placeholder**

Every reader and writer in the skills names the directories `<state>` and `<docs>`, resolved at run time, so a skill never creates `docs/forge/` in a repository that keeps `docs/superpowers/` (this one included):

```bash
grep -rlZ -e '\.superpowers' -e 'docs/superpowers' plugins/dr-forge/skills plugins/dr-forge/reference plugins/dr-forge/criteria plugins/dr-forge/agents \
  | grep -zv '/reference/legacy-names\.md$' \
  | xargs -0 perl -pi -e 's{docs/superpowers(?!/(?:specs|plans|notes|registers)/\d{4}-)}{<docs>}g; s{(?<![\w-])\.superpowers}{<state>}g'
```

The lookahead keeps citations of dated historical files (`docs/superpowers/specs/2026-09-11-…`), which keep their paths. So `**Save plans to:** \`docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md\`` becomes `**Save plans to:** \`<docs>/plans/YYYY-MM-DD-<feature-name>.md\``, and `.superpowers/handoff/latest.md` becomes `<state>/handoff/latest.md`. Check: `grep -rn '\.superpowers\|docs/superpowers\|docs/forge\|\.forge/' plugins/dr-forge/skills plugins/dr-forge/reference plugins/dr-forge/criteria plugins/dr-forge/agents | grep -v legacy-names | grep -vE 'docs/superpowers/(specs|plans|notes|registers)/[0-9]{4}-'` → no output.

- [ ] **Step 2: Define the placeholders**

In `plugins/dr-forge/skills/using-superpowers/SKILL.md`, under `## Session Budget`, add the bullet:

```markdown
- `<state>` and `<docs>` in these skills are this repository's dr-forge directories: `.forge/` and `docs/forge/`, or `.superpowers/` and `docs/superpowers/` where only those exist. Resolve them before reading or writing under them with `bash <plugin-root>/scripts/forge-path state|docs [RELATIVE]`, which prints the absolute path ([project-state.md](../../reference/project-state.md)).
```

Append to `plugins/dr-forge/reference/project-state.md`:

```markdown
## Where `<state>` and `<docs>` are

`<state>` is `.forge/` and `<docs>` is `docs/forge/`, except in a repository that
has `.superpowers/` or `docs/superpowers/` and not the new directory: there the
old one stays in use, for writing as well as reading, so a pre-2.0 checkout never
splits across both. Every script resolves its paths through
`scripts/lib/forge-dir.sh`; a skill resolves them with
`bash <plugin-root>/scripts/forge-path state|docs [RELATIVE]` before it reads or
writes, never by spelling either path.
```

- [ ] **Step 3: Check the placeholders read well**

Run: `grep -rnc '<docs>\|<state>' plugins/dr-forge/skills plugins/dr-forge/reference plugins/dr-forge/criteria plugins/dr-forge/agents | grep -v ':0$' | wc -l` and read three of the changed sentences (for example `skills/writing-plans/SKILL.md`'s "Save plans to", `skills/handoff/SKILL.md`'s `latest.md` path and `skills/running-gates/SKILL.md`'s manifest path): each must still read as an instruction with the placeholder in place of the directory.

- [ ] **Step 4: Run the checks**

Run: `timeout 60 node scripts/validate-repository.mjs && timeout 900 node scripts/test-all.mjs`
Expected: the validator prints its valid line; every suite passes. A suite that greps skill text for `.superpowers` or `docs/superpowers` is updated to the new text.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/skills plugins/dr-forge/reference plugins/dr-forge/criteria plugins/dr-forge/agents plugins/dr-forge/tests
git commit -m "docs(dr-forge): resolve state and docs dirs in skills"
```

### Task 19: Documentation and dr-cockpit retirement

**Files:**
- Modify: `README.md`, `plugins/dr-forge/README.md`, `CLAUDE.md`, `tests/marketplace-smoke.ps1`, `docs/testing/dual-client-marketplace-validation.md`, `.gitignore`
- Delete: `plugins/dr-cockpit/` (its README is merged first)

**Interfaces:**
- Consumes: every earlier task
- Produces: none

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 2 - spec 1 - coupling 0 - risk 0 = 3

- [ ] **Step 1: Merge the plugin READMEs**

`plugins/dr-forge/README.md` keeps its workflow content (already renamed by Task 1), with its operational instructions moved to the new names: `~/.dr-superpowers/config.json` and `~/.dr-superpowers/mirror/` become `~/.dr-forge/config.json` and `~/.dr-forge/mirror/` (adding once, where the darkmem setup is described: "Before 2.0 these lived under `~/.dr-superpowers/`, which is still read until the new file exists."), `.superpowers/` becomes `.forge/` and `docs/superpowers/` becomes `docs/forge/` except in citations of dated historical files: `perl -pi -e 's{docs/superpowers(?!/(?:specs|plans|notes|registers)/\d{4}-)}{docs/forge}g; s{(?<![\w-])\.superpowers}{.forge}g' plugins/dr-forge/README.md` (the README is for people, so it names the real directories, not the skills' `<state>`/`<docs>` placeholders), and any `dr-cockpit` mention becomes "the cockpit". It gains a `## Cockpit` section built from `plugins/dr-cockpit/README.md`'s "What it does" through "Settings" sections, with these changes: the plugin is `dr-forge`; "Settings" says the values are edited in the settings view, with `bash <plugin-root>/scripts/forge-config set <key> <value>`, or in `~/.dr-forge/config.json`, and the `pluginConfigs` JSON example is replaced by

```json
{ "layout": "compact", "sections": "context,usage,plan", "warnAt": 70 }
```

with its table of options unchanged except `handoffTokens`, whose text says `DR_FORGE_BUDGET` overrides it (`DR_SUPERPOWERS_BUDGET` still read); the Discord section names `DR_FORGE_NOTIFY_URL` (`DR_COCKPIT_NOTIFY_URL` still read); the Install section is the dr-forge one; the Development section uses `plugins/dr-forge`. Add a `## Migrating from dr-superpowers and dr-cockpit` section:

```markdown
## Migrating from dr-superpowers and dr-cockpit

dr-forge 2.0.0 replaces both plugins. Uninstall them and install dr-forge:

    /plugin uninstall dr-superpowers@darkraise
    /plugin uninstall dr-cockpit@darkraise
    /plugin install dr-forge@darkraise

The first session imports the cockpit's options and the darkmem mapping into
`~/.dr-forge/config.json`, and the cockpit's Discord webhook and mention into
dr-forge's own plugin store, once; the old files stay. Plans written for
dr-superpowers, which name its agents and skills under the old plugin name,
still run. A repository's `.superpowers/` and `docs/superpowers/` keep working
until you move them to `.forge/` and `docs/forge/`.
```

- [ ] **Step 2: Update the repository documents**

- `plugins/dr-forge/README.md`: the `## Cockpit` section opens with the sentence from `plugins/dr-cockpit/README.md` line 7, reworded: `Claude Code only. Built and tested against Claude Code 2.1.295 to 2.1.296; the mod API is early access and may change between releases.` (if Task 4 raised the CI pin to 2.1.296, say `2.1.296` alone). In `README.md`, `dr-cockpit is built against Claude Code 2.1.292 to 2.1.295` becomes `The cockpit is built against Claude Code 2.1.295 to 2.1.296` (same proviso).
- `README.md`: the two plugin bullets, the two table rows, the two install lines and the "Using dr-superpowers"/"Using dr-cockpit" sections become one dr-forge bullet, row (Claude Code: Yes, Codex: Yes, the cockpit Claude Code only), install line and `## Using dr-forge` section (the workflow text, then the cockpit text as `### The cockpit`), with links to `plugins/dr-forge/README.md`; the settings example at the old line 286 becomes the `~/.dr-forge/config.json` example above; the Codex paragraph says Codex lists `dr-forge` and the two UI plugins, and `dr-status` is Claude Code only. Image alt texts say dr-forge.
- `CLAUDE.md` Conventions: the Claude catalog line lists `dr-forge`, `dr-status`, `dcc-darkraise-ui`, `dcc-darkraise-win32ui`; "`dr-status` is Claude-only: no `.codex-plugin` manifest."; "`dr-forge` carries a mod (`hooks/cockpit/`); test it with `claude plugin test plugins/dr-forge`."; the Codex catalog lists `dr-forge` and the two UI plugins. Validation: `claude plugin test plugins/dr-forge`.
- `tests/marketplace-smoke.ps1`: every `dr-superpowers` → `dr-forge` (paths, names, expected lists sorted: `dcc-darkraise-ui,dcc-darkraise-win32ui,dr-forge`).
- `docs/testing/dual-client-marketplace-validation.md`: `dr-superpowers` → `dr-forge`.
- `.gitignore`: under the Superpowers comment, add `.forge/` and make the comment `# dr-forge agent scratch (ledgers, briefs, review packages); .superpowers/ before 2.0`.

Then `git rm -r -q plugins/dr-cockpit`.

Check: `grep -rn 'dr-cockpit\|dr-superpowers' README.md CLAUDE.md tests/marketplace-smoke.ps1 docs/testing .github plugins/dr-forge/README.md | grep -v 'uninstall dr-\|Migrating from\|written for\|DR_COCKPIT_NOTIFY_URL\|DR_SUPERPOWERS_BUDGET\|\.dr-superpowers\|[0-9]-dr-superpowers'` → no output, and `grep -c 'dr-superpowers:' plugins/dr-forge/README.md` → `0` (the validator allows that literal only in `legacy-names.md` and the cockpit's two files). `tests/repository-layout.test.mjs` and `evals/tiers/tests/cases.test.mjs` keep their one intentional old-name fixture each.

- [ ] **Step 3: Run the verification gate**

```bash
timeout 60 node scripts/validate-repository.mjs
timeout 900 node scripts/test-all.mjs
timeout 90 claude plugin validate .
timeout 60 claude plugin validate plugins/dr-forge
timeout 60 claude plugin validate plugins/dr-status
timeout 300 claude plugin test plugins/dr-forge
```

Expected: every command exits 0. Then confirm nothing is left running: `pgrep -af 'test-all|claude plugin' || echo none`.

- [ ] **Step 4: Commit**

```bash
git add -A README.md CLAUDE.md tests/marketplace-smoke.ps1 docs/testing/dual-client-marketplace-validation.md .gitignore plugins/dr-forge/README.md plugins/dr-cockpit
git commit -m "docs(dr-forge): document dr-forge and retire dr-cockpit"
```

### Task 20: Manual runtime check

**Files:**
- None: the outcome is a ledger line.

**Interfaces:**
- Consumes: every earlier task
- Produces: none

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

Inline mode runs this task in the controller's session, because it needs your human partner at a terminal; no subagent or executor can open an interactive Claude Code session.

- [ ] **Step 1: Ask for the check**

Ask your human partner to run, in a scratch git repository, with `dr-superpowers` and `dr-cockpit` disabled for that session:

```bash
claude --plugin-dir /root/repositories/darkraise-ai-plugins/plugins/dr-forge
```

and to report each of these observations:

1. The cockpit opens (the pane, or the band above the prompt when the saved layout is compact).
2. `/cockpit settings` shows the groups Cockpit, Context and Notifications, with the values imported from their dr-cockpit settings (for example their layout and sections).
3. Asked "Which skill does your session-start context introduce, by its full name, and what is its Plugin root line?", Claude answers `dr-forge:using-superpowers` and a path ending in `plugins/dr-forge`.
4. `ls ~/.dr-forge/config.json` exists and `bash /root/repositories/darkraise-ai-plugins/plugins/dr-forge/scripts/forge-config get --json` prints the same values the settings view shows.

The Stop hook's hold is covered by `tests/turn-end.test.sh`, and loading the mod beside the command hooks was probed on 2026-10-11.

- [ ] **Step 2: Record the outcome**

Append to the ledger `Task 20: manual check — 1 <ok|what was seen> · 2 <…> · 3 <…> · 4 <…>`. Every item ok: `Task 20: complete`. Any item not ok: the task is BLOCKED with what was seen, for your human partner to rule on; nothing merges before that.
