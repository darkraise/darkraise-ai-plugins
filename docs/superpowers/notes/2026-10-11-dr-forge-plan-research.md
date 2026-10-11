# dr-forge merge — plan research (draft for writing-plans)

**Spec:** `docs/superpowers/specs/2026-10-11-dr-forge-merge-design.md` (approved)
**Register:** `docs/superpowers/registers/2026-10-11-dr-forge.md` (rows 1-2 this
plan; rows 3-10 are Spec 2: set them `deferred --note "Spec 2: development-process controls"`)
**Plan to write:** `docs/superpowers/plans/2026-10-11-dr-forge-merge.md`
**Execution:** inline — `claude --model sonnet --effort high` (8 of 19 tasks
heavy; only Task 14 is self-implemented, total 4 → medium, raised to high
because tasks are delegated). **Parallelism:** sequential (spec says so).
Codex gate 2026-10-11: `usable=true lane=true source=probe` → every task with
total 2-4 and risk ≤1 gets `**Executor:** codex gpt-6.1-sol / <low|medium|high>`.

## Verified facts (cite in Assumptions)

- One `hooks/hooks.json` with both `"modules"` and command `"hooks"` passes
  `claude plugin validate` and loads both at runtime: headless
  `claude -p --plugin-dir` on Claude Code 2.1.296, 2026-10-11.
- A mod may `import SCHEMA from '../../config/schema.mjs'` (outside `hooks/`);
  validate and `claude plugin test` pass (probe 2026-10-11). A mod cannot import
  `.json`. Spec amended to `config/schema.mjs`.
- Engine API (types file written by the plugin-authoring skill, 2.1.296):
  `$.fs.read/write/list/exists/stat` take absolute paths, write is whole-file
  (no rename → mod writes are not atomic; forge-config.mjs is); `$.settings.read({ source: 'user' })`
  is read-only (`SettingsSource = 'user'|'project'|'local'|'flag'|'policy'`);
  `$.env.get` needs a string-literal name; `$.store` is per plugin; there is no
  self-reload — `$.config.set` on the mod's own `/config` row is what reloads it today.
- Old cockpit store: `<config dir>/plugins/store/dr-cockpit_darkraise-<hash>.json`,
  a flat object keyed by store key (`notifyUrl`, `notifyMention`); same name in
  `~/.claude` and `~/.claude-alt` (inspected key paths only).
- Tests: the harness answers `$.fs`/`$.env` only through the test's own hooks;
  `test(name, { options })` feeds `userConfig` only. Fixture `world(on, w)` in
  `plugins/dr-cockpit/tests/cockpit.test.ts` (~line 140) hooks `fs.stat/list/write`
  from `w.files`/`w.written`; `signedIn(on, files)` hooks `fs.read` and throws ENOENT
  for unknown paths. ~25 tests pass `{ options: {...} }`; 5 hook `config.set`.
- Cockpit baseline: `claude plugin test plugins/dr-cockpit` → 100 pass (2026-10-11).
- CI (`.github/workflows/validate.yml`) runs the mod's validate+test in its own
  step with claude-code@2.1.295; `scripts/test-all.mjs` runs only bash/node suites.
  Plan keeps that split (deviation from spec's "test-all runs the cockpit test" — note it).
- darkmem config is a nested `darkmem` object; mirror at `~/.dr-superpowers/mirror/<project>`.
- `rg` is a shell function here: use `grep` in scripts and plan steps.

## Mod-specific rules

- `$` may only go to top-level functions; hooks must be inline or top-level
  (memory `mod-hooks-need-top-level-functions`). Run `claude plugin test` after each refactor.
- Options used at register time (76 uses, lines 179-207 + body of
  `register.tsx`). `if (guardAttribution) { on('attribution.text', ...) }` at ~483
  must become always-registered hooks that check the live option.

## Tasks (score: files-spec-coupling-risk = total → agent [executor])

1. **Rename the plugin directory and namespace** 0-0-3-2=5 → impl-sonnet-high.
   `git mv plugins/dr-superpowers plugins/dr-forge`; then over every file except
   `LICENSES/` and `reference/legacy-names.md`:
   `perl -pi -e "s/dr-superpowers' /dr-forge's /g; s/(?<!\.)dr-superpowers/dr-forge/g"`
   (leaves `~/.dr-superpowers`, `DR_SUPERPOWERS_*`, `.superpowers` for later tasks).
   Check: zero `dr-superpowers` left except legacy-names and `.dr-superpowers`; run
   each `plugins/dr-forge/tests/*.test.sh` with `timeout 600` (test-all paths break until Task 3).
2. **Distribution contract** 2-0-1-2=5 → impl-sonnet-high. legacy-names.md: intro
   "before dr-forge 2.0.0"; resolution targets `dr-superpowers:` → `dr-forge:`
   (keep the "Resolve by suffix … `dr-superpowers:`" bullet). Validator: names
   `['dcc-darkraise-ui','dcc-darkraise-win32ui','dr-forge','dr-status']`,
   claudeOnly `['dr-status']`; Codex empty-hooks and no-dependencies rules → dr-forge;
   resolve `dr-forge:<name>` against `plugins/dr-forge/{skills,agents}`; legacy pattern
   `/(?:^|[^\w-])superpowers:|dr-superpowers:|dcc-superpower-companions:/`, allowed only in
   `plugins/dr-forge/reference/legacy-names.md`. Catalogs: drop dr-superpowers and
   dr-cockpit, add dr-forge (merged description/keywords, category workflow /
   Development); marketplace version 0.5.0 → 0.6.0; both manifests 2.0.0 with the merged
   description. `tests/repository-layout.test.mjs`: lists, paths, error text, and a row
   for a stray `dr-superpowers:brainstorming`.
3. **Test runner, CI loop, eval harness paths** 2-0-1-0=3 → impl-sonnet-medium
   [codex medium]. `scripts/test-all.mjs` path; validate.yml loop name; evals:
   `lib/sh.mjs` PLUGIN, `run-grid.mjs:33-34`, `build-manifest.mjs:12-13`, README lines
   3 and 33 (+ note: a manifest built before 2.0.0 is refused, rebuild it), tests
   (`fixture.mjs` 15/59, `manifest.test.mjs` 36-40, `grid.test.mjs` 45-47);
   `lib/cases.mjs` slug regex → `/^dr-(?:superpowers|forge)-/` (keep the line-18
   comment) and a `dr-forge-` slug assertion in `cases.test.mjs`. Never edit
   `evals/tiers/results/` or `cases/`.
4. **Move the cockpit into dr-forge** 2-0-1-2=5 → impl-sonnet-high.
   `git mv` hooks/{register.tsx,lib.ts,notify.ts,svg.ts} → `plugins/dr-forge/hooks/cockpit/`,
   `tests/cockpit.test.ts` → `plugins/dr-forge/tests/`, `types/` → `plugins/dr-forge/types/`;
   imports `'../types'` → `'../../types'`, test imports `'../hooks/X'` → `'../hooks/cockpit/X'`;
   perl `dr-cockpit`/`dr-superpowers` → `dr-forge` in moved files (atoms, PANE id,
   toasts, `config.set` keys, PluginState key); hooks.json gets
   `"modules": ["./cockpit/register.tsx"]` and the spec's description; plugin.json gets
   `"types"` and cockpit's `userConfig` (removed again in Task 15); CI mod step →
   plugins/dr-forge, drop dr-forge from the old-CLI loop. Keep `plugins/dr-cockpit/README.md`
   until Task 19.
5. **Cockpit old prefix and env names** 1-0-0-1=2 → impl-sonnet-low [codex low].
   `isSuperpowers` accepts `dr-forge:` and `dr-superpowers:`; seat strip both;
   `DR_FORGE_NOTIFY_URL` then `DR_COCKPIT_NOTIFY_URL`; `DR_FORGE_BUDGET` then
   `DR_SUPERPOWERS_BUDGET` (register.tsx ~2101, ~2225, lib.ts comment); tests.
6. **Bash env names with fallbacks** 2-0-0-1=3 → impl-sonnet-medium [codex medium].
   New `scripts/lib/forge-env.sh`: `: "${DR_FORGE_BUDGET:=${DR_SUPERPOWERS_BUDGET:-}}"`
   (same for JQ, BUDGET_CALLER), sourced by context.sh and snapshot.sh, which then
   use `DR_FORGE_*`; task-brief:107 and review-package:54 set `DR_FORGE_BUDGET_CALLER`;
   darkmem-config `runKey` reads `DR_FORGE_SESSION_ID` then the old name;
   `reference/session-budget.md` names. Tests: rename in tests, plus in
   `context-size.test.sh` (~line 97) `DR_SUPERPOWERS_BUDGET=300000` still gives
   "285k of 300k (95%)" and `DR_FORGE_BUDGET=380000 DR_SUPERPOWERS_BUDGET=300000` gives
   "budget: 285k of 380k (75%) — ok — source: record"; unset both names at line 31.
7. **forge_dir resolver** 1-0-2-0=3 → impl-sonnet-medium [codex medium].
   `scripts/lib/forge-dir.sh`: `forge_dir state|docs [ROOT=.]` prints `ROOT/.forge`
   (`docs/forge`) unless only `.superpowers` (`docs/superpowers`) exists; exit 2 on
   another kind; `forge_dir_rel` prints it relative to ROOT. `tests/forge-dir.test.sh`
   (check/pass/fail style, `printf '\n%d passed, %d failed\n'`): neither/old/both/new rows,
   relative, default root, bad kind.
8. **Scripts resolve the state directory** 1-1-1-2=5 → impl-sonnet-high. Sites:
   plan-revise:155, task-brief:97, next-step:142/145/154/170/422, finish-choice:49,
   run-codex-task.sh:145 (allow `.forge/*` and `.superpowers/*`), turn-end.sh:32/83,
   task-state.sh:138 (guard both), plan.sh:324/418-419, repo-audit:55/97,
   context.sh:289/382, sdd-workspace:38, snapshot.sh:18/28. plan.sh and context.sh
   source forge-dir.sh; others source it directly. Update tests that expect a fresh
   repo to get `.superpowers/`; new `tests/forge-state.test.sh`: sdd-workspace and
   `finish-choice set pr --base main` in a fresh repo → `.forge/sdd/…`, in a repo with
   `.superpowers/` → `.superpowers/sdd/…`.
9. **Scripts resolve the docs directory** 1-1-1-2=5 → impl-sonnet-high. Sites:
   session-start.sh:81, register.sh:91, roadmap.sh:17/112, roadmap:60, next-step:318/321;
   tests for a fresh repo (docs/forge) and an old one (docs/superpowers).
10. **darkmem home, config fallback, mirror and roots** 2-0-1-2=5 → impl-sonnet-high.
    darkmem-config.mjs: `forgeHome` (`~/.dr-forge`), `preferNew(next, old)`,
    `forgeDir(kind, root)`; config file `preferNew(~/.dr-forge/config.json,
    ~/.dr-superpowers/config.json)`; mirror the same; local `docsRoot/workRoot` via
    `forgeDir`; darkmem-import.mjs:113 roots via `forgeDir`. helpers.mjs `makeHome`
    writes `.dr-forge` (option `legacy: true` writes the old home); config.test.mjs:
    first test expects docs/forge and .forge; new cases: only old config → darkmem mode;
    both → new wins; only old mirror → old mirror; both → new.
11. **Settings schema and validator check** 1-0-2-0=3 → impl-sonnet-medium [codex medium].
    `plugins/dr-forge/config/schema.mjs` default-exports the 13 cockpit keys
    (titles/descriptions from cockpit's userConfig; groups Cockpit: openAtStart, layout,
    sections, breakdownRows, guardAttribution; Context: handoffTokens (env
    DR_FORGE_BUDGET, 0-2000000 step 50000), warnAt (1-99 step 5), nudgeModel;
    Notifications: limitAlertAt (0-100 step 5), notifyOn, notifyAfter (0-3600 step 15),
    notifyAskAfter (0-600 step 10), notifyDetail enum full|brief; layout enum
    auto|full|compact; breakdownRows 0-12 step 1; all `target: 'forge'`).
    Validator: new `export async function validateSchema(root)` (CLI main awaits it after
    `validateRepository`): type in boolean|number|enum|string, group in
    Cockpit|Context|Notifications|Workflow, title/description non-empty, target forge|claude,
    env `/^[A-Z][A-Z0-9_]*$/`, default fits type/min/max/values, step > 0, key `darkmem`
    reserved. Layout test: clean schema → [], a copy with a bad default → error.
12. **forge-config command** 1-0-1-1=3 → impl-sonnet-medium [codex medium].
    `scripts/forge-config` (bash → `exec node lib/forge-config.mjs`) and
    `scripts/lib/forge-config.mjs`: `configPath(env)`, `isValid(spec, v)`,
    `fromText(spec, text)`, `readFile` (null when missing, throws on bad JSON),
    atomic `writeFile` (temp + rename), `resolve(env, warn)` (env incl.
    `LEGACY_ENV = { DR_FORGE_BUDGET: 'DR_SUPERPOWERS_BUDGET' }` → file → default, warn on
    invalid), `setValue` (removes a value equal to the default; keeps `darkmem`),
    `unsetValue`, `importLegacy(env)` (only when the file is absent: cockpit options from
    `$CLAUDE_CONFIG_DIR|~/.claude/settings.json` `pluginConfigs["dr-cockpit@darkraise"].options`
    that are valid and non-default, plus `darkmem` from `~/.dr-superpowers/config.json`;
    writes `{}` at least), `main(argv)` runs `importLegacy` first; exits 0 / 2
    (usage, unknown key, invalid value) / 1 (I/O, bad JSON). `tests/forge-config.test.sh`
    per spec §Testing with a temp HOME.
13. **Cockpit settings module** 1-0-1-0=2 → impl-sonnet-low [codex low].
    `hooks/cockpit/config.ts` (pure): `SettingValue`, `SettingSpec`, `Schema`,
    `SettingsFile`, `SCHEMA` (typed re-export of schema.mjs; add
    `config/schema.d.mts` only if validate/tsc needs a declaration), `isValidSetting`,
    `settingFromText`, `resolveSettings(schema, file, env)`, `settingWritten(schema,
    file, key, value)` (throws on unknown/invalid; drops defaults; keeps `darkmem`),
    `importedSettings(schema, claudeSettings, oldForge)`; unit tests in cockpit.test.ts.
14. **Cockpit options read at runtime** 1-1-0-2=4 → impl-sonnet-medium (self-implemented).
    Pure refactor, tests unchanged: atom `settings` (`Record<string, boolean|number|string> | null`,
    declared in types/index.d.ts under 'dr-forge'); top-level `liveFrom(values)` (the
    current destructuring + derived `layout`, `tuning`, `shown`, `isMinimized`),
    `live($)` = `liveFrom((await read($, settings)) ?? S.loaded)`, `applyNotify(o)`;
    register stores `S.loaded = options`; each hook starts `const o = await live($)`;
    mapping: tuning→o.tuning, shown→o.shown, paneArgs→paneFor(o.layout),
    isMinimized→o.isMinimized, layout→o.layout, warnPercent→o.warnAt, others→o.<name>;
    AbovePrompt hook and the tool.call `.catch` become async; attribution.text hooks
    always registered, returning `{ text: '' }` only when `o.guardAttribution`.
15. **Cockpit options from the settings file** 1-1-1-2=5 → impl-sonnet-high.
    `configFile($)` (HOME or USERPROFILE + `/.dr-forge/config.json`), `readSettingsFile`
    ({} when missing, null when it exists but is unreadable/not an object — use
    `$.fs.exists` to tell), `applySettings($, file)` (resolve with env map
    `DR_FORGE_BUDGET ?? DR_SUPERPOWERS_BUDGET`, update atom, applyNotify), `loadSettings($)`
    first in session.start; `setOption` reads, `settingWritten`, writes, applies, toasts
    `dr-forge: <key> not saved: <reason>` on failure; footer text "Saved to
    ~/.dr-forge/config.json."; plugin.json drops `userConfig`; register ignores options.
    Tests: `CONFIG = '/home/me/.dr-forge/config.json'`; World gains `config` (world hooks
    fs.read for CONFIG returning `w.written?.[CONFIG] ?? JSON.stringify(w.config)`, adds
    HOME) and `isReadOnly` (fs.write throws); tests using signedIn pass config through its
    files; replace every `{ options }` and `config.set` assertion with file assertions.
16. **Settings view generic rows and first-run import** 1-1-1-2=5 → impl-sonnet-high.
    config.ts: `HAND_BUILT_SETTINGS` (the 13 keys), `SettingRow`, `schemaRows(schema,
    values, handBuilt)` (toggle|choices|stepper|text). View draws extra groups after the
    hand-built rows (widen helper key types to string; text rows show the value and
    `forge-config set <key>`). loadSettings: when the file does not exist,
    `importSettings` (`$.settings.read({ source: 'user' })`, old
    `~/.dr-superpowers/config.json`, `importedSettings`, write). `importWebhook` once per
    store flag (new key `webhookImported`): skip if `notifyUrl` set; list
    `<CLAUDE_CONFIG_DIR|HOME/.claude>/plugins/store`, file `dr-cockpit_darkraise-*.json`,
    copy a valid `notifyUrl` and string `notifyMention`; run before readNotifier. Tests:
    schemaRows on a fake schema; every SCHEMA key hand-built or a row; import from fixture
    settings and store file; no import when a webhook is already set or the flag is set.
17. **Cockpit reads the state directory through the resolver** 1-0-1-1=3 →
    impl-sonnet-medium [codex medium]. lib.ts `stateLeaf(names)` ('.forge' unless only
    '.superpowers'); register `stateDirOf($, root)` via `$.fs.list(root)` (tests serve
    fs.list from w.files); readRun handoff and sdd paths; `S.stateLeaf` for the resume
    prompt; tool.call regex `/\.forge|\.superpowers|finish-choice/`; tests for both layouts.
18. **Skills and references name the new paths** 1-0-1-1=3 → impl-sonnet-medium
    [codex medium]. perl `\.superpowers` → `.forge`, `docs/superpowers` → `docs/forge`
    over skills/, reference/, criteria/, agents/ (not legacy-names.md); state the fallback
    rule once in `reference/project-state.md`; run validator and test-all.
19. **Documentation and dr-cockpit retirement** 2-1-0-0=3 → impl-sonnet-medium
    [codex medium]. Root README (one dr-forge section, install, migration note),
    `plugins/dr-forge/README.md` (workflow + cockpit sections; settings in the view,
    `scripts/forge-config` and the file, no pluginConfigs), CLAUDE.md lines,
    `tests/marketplace-smoke.ps1`, `docs/testing/dual-client-marketplace-validation.md`,
    `.gitignore` adds `.forge/`, `git rm -r plugins/dr-cockpit`. Then the spec's
    Verification gate.

## Items

Tasks 1-10 and 17-19 carry `**Items:** 1`; Tasks 11-16 carry `**Items:** 2`.
