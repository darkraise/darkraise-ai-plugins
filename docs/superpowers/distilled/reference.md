# Reference

Measured facts about the tools and engine this repository builds on, with when and how each was measured.

What each finished plan left open, review by review, is split out by area into [plan-history-reference.md](plan-history-reference.md).

## Claude Code mod engine

### One `hooks/hooks.json` may carry both `"modules"` and command `"hooks"`
Both load at runtime and `claude plugin validate` passes
Measured: headless `claude -p --plugin-dir`, Claude Code 2.1.296
Authority: probe
Verified: 2026-10-11
Source: docs/superpowers/notes/2026-10-11-dr-forge-plan-research.md@e7f93ca

### The engine API as of Claude Code 2.1.296
- `$.fs.read/write/list/exists/stat` take absolute paths; `write` is whole-file with no rename, so a mod's writes are not atomic (a Node script such as `forge-config.mjs` writes temp + rename and is).
- `$.settings.read({ source: 'user' })` is read-only; `SettingsSource` is `'user' | 'project' | 'local' | 'flag' | 'policy'`.
- `$.env.get` needs a string-literal name.
- `$.store` is per plugin.
- A mod has no self-reload; `$.config.set` on the mod's own `/config` row was what reloaded it.
Measured: the types file the plugin-authoring skill writes, 2.1.296
Authority: engine type declarations
Verified: 2026-10-11
Source: docs/superpowers/notes/2026-10-11-dr-forge-plan-research.md@e7f93ca

### The mod test harness
- It answers `$.fs` and `$.env` only through the test's own hooks.
- `test(name, { options })` feeds `userConfig` only.
- On 2026-10-11 the cockpit tests' fixture `world(on, w)` hooked `fs.stat/list/write` from `w.files`/`w.written`, and `signedIn(on, files)` hooked `fs.read`, throwing ENOENT for unknown paths; about 25 tests passed `{ options: {...} }` and 5 hooked `config.set`.
- Baseline then: `claude plugin test plugins/dr-cockpit` → 100 pass.
Measured: reading `plugins/dr-cockpit/tests/cockpit.test.ts` and a test run
Authority: the test file and its run
Verified: 2026-10-11
Source: docs/superpowers/notes/2026-10-11-dr-forge-plan-research.md@e7f93ca

### The retired dr-cockpit plugin's store file
`<config dir>/plugins/store/dr-cockpit_darkraise-<hash>.json`, a flat object keyed by store key (`notifyUrl`, `notifyMention`); the same name under `~/.claude` and `~/.claude-alt`
Measured: inspection of key paths only, not values
Authority: the files on this machine
Verified: 2026-10-11
Source: docs/superpowers/notes/2026-10-11-dr-forge-plan-research.md@e7f93ca

## CI and test runners

### CI runs the mod apart from the shell and Node suites
`.github/workflows/validate.yml` runs the mod's validate and test in its own step with claude-code@2.1.295; `scripts/test-all.mjs` runs only bash and Node suites. The dr-forge merge kept that split, a recorded deviation from its spec's "test-all runs the cockpit test"
Measured: reading the workflow and runner
Authority: the files
Verified: 2026-10-11
Source: docs/superpowers/notes/2026-10-11-dr-forge-plan-research.md@e7f93ca

## darkmem

### darkmem configuration and mirror location before dr-forge
The darkmem config is a nested `darkmem` object; the mirror lived at `~/.dr-superpowers/mirror/<project>`
Measured: reading the config code
Authority: `darkmem-config.mjs`
Verified: 2026-10-11
Source: docs/superpowers/notes/2026-10-11-dr-forge-plan-research.md@e7f93ca

### darkmem work-log entries take per-entry `properties`
darkmem's `WorklogEntryIn` accepts `properties` on each entry (`backend/app/schemas/worklog.py:68` in the darkmem repository)
Measured: reading darkmem's schema
Authority: darkmem source
Verified: 2026-10-13
Source: docs/superpowers/notes/2026-10-13-darkmem-store-options-plan1-inventory.md@3a2bdd5
