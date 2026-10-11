# dr-forge settings view and workflow controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.
> **External executors:** codex

**Goal:** Give dr-forge 2.1.0 a tabbed settings view drawn entirely from the schema and fourteen workflow settings that the scripts and skills obey.

**Architecture:** Every setting is declared once in `config/schema.mjs` with the row fields the view needs. `scripts/forge-config` stays the one command that resolves and writes settings, and becomes the only writer of Claude's own settings file. Scripts that already make a decision read their setting through one helper (`forge_setting`); decisions that live in skill text arrive as one line (`forge-config workflow`) injected at session start. The cockpit's view moves into its own module that receives the element table, a row model and callbacks.

**Tech Stack:** Bash, Node.js 22 (ES modules, `node:test`), TypeScript/TSX hooks module for the Claude Code mod API (2.1.296), `jq`, git.

**Spec:** `docs/superpowers/specs/2026-10-12-dr-forge-settings-design.md`

**Execution:** subagent — `claude --model sonnet --effort high` — a waves plan always runs in subagent mode.

**Plan review:** 2026-10-12 — dr-superpowers:judge-opus — executability 17 / coherence 18 / coverage 18 / assumptions 16 (round 2)

**Parallelism:** waves — 1 | 2 | 3 | 4-7 | 8 | 9 | 10 | 11 | 12 | 13

**Integration check:** `timeout 1800 node scripts/test-all.mjs`

**Worktree setup:** none

## Global Constraints

- All paths are relative to the repository root. The plugin is `plugins/dr-forge`; it goes from `2.0.0` to `2.1.0` in both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`, in Task 13 only.
- Defaults reproduce 2.0.0: with no setting changed, no script, skill or pane behaves differently.
- A script reads a setting only through `forge_setting KEY DEFAULT` (Contracts). A failing `forge-config` yields the default; a settings file that cannot be read never fails a task, a budget line or the finish menu.
- `~/.dr-forge/config.json` never holds a `target: 'claude'` key. `scripts/lib/forge-config.mjs` is the only writer of Claude's settings file.
- A test whose assertions depend on a setting exports `HOME` to a directory under its own `mktemp -d` first. `forge_setting` never creates the settings file (Contracts), and a suite that must keep the real `HOME` exports `DR_FORGE_NO_SETTINGS=1`, under which every `forge_setting` call answers its default. No test shares a port, a database or a fixed path with another.
- Number settings are whole numbers: both validators refuse a fraction.
- Where a Run line pipes into `tail` or `grep`, the Expected text is the pass condition; a step that needs the command's exit status reads `${PIPESTATUS[0]}`, never `$?` after the pipe.
- Mod code (`plugins/dr-forge/hooks/cockpit/*.ts*`): `$` is passed only to functions declared at the top of `register.tsx`; it never crosses an import. A hook is an inline function or a top-level function, never a `const` closure inside `register`. Run `timeout 420 claude plugin test plugins/dr-forge` after every change to the mod.
- Never edit historical files: `docs/superpowers/plans/` (other than this plan), `docs/superpowers/specs/`, `docs/superpowers/notes/`. Registers change only through `scripts/register`. Never touch the untracked `docs/superpowers/notes/2026-09-23-opus-5-5-effort-eval-design.md`.
- Commits: `<type>(<scope>): <subject>` (subject at most 50 characters, imperative), author `Darkraise <quangtc94@gmail.com>`, no `Co-Authored-By`, `Claude-Session` or "Generated with" lines.
- Scripts and plan steps use `grep`, never `rg` (here `rg` is a shell function, not a binary).
- Bash keeps running under Git Bash on Windows: no GNU-only flags in scripts, `cygpath` handling in tests as the neighbouring tests do.
- Bound every test and CLI run with `timeout`, and stop every process a step starts.
- Comments say why, never what, and never name this plan or its tasks.

## Contracts

- **Schema entry (`plugins/dr-forge/config/schema.mjs`).** `{ type: 'boolean'|'number'|'enum'|'string', default, group, label, title, description, target: 'forge'|'claude', env?, min?, max?, step?, values?, unit?, zero?, floor?, enforcedBy? }`. `group` is one of `Cockpit`, `Context`, `Workflow`, `Process`, `Finish`, `Notifications`, and the groups appear in that order. `label` is at most 16 characters. `unit` is `k` (thousands of tokens), `%`, `s` or `min`. `zero` is the word shown at 0, one of `auto`, `off`, `any`, `hidden`, `unset`. A number setting is a whole number. `floor` is the smallest value allowed other than 0 (a number with `floor` is valid when it is 0 or in `floor..max`). `enforcedBy` is `script` or `skill`.
- **Keys added by Task 1** (group, type, default): `handoffMode` (Context, enum `strict|relaxed`, `strict`, script); `codexLane`, `codexReview` (Workflow, boolean, `true`, script); `executionStrategy` (Workflow, enum `ask|sequential|parallel`, `ask`, skill); `executionMode` (Workflow, enum `auto|inline|subagent`, `auto`, skill); `worktree` (Workflow, enum `ask|always|never`, `ask`, skill); `processBias` (Process, enum `standard|lighter|heavier`, `standard`, skill); `designApproval` (Process, enum `sections|whole`, `sections`, skill); `specReview` (Process, boolean, `true`, skill); `questionStyle` (Process, enum `single|batched`, `single`, skill); `finishAction` (Finish, enum `ask|merge|pr|keep|wait`, `ask`, script); `finishTimeout` (Finish, number 5 to 240, `30`, script).
- **Keys added by Task 3** (`target: 'claude'`): `autoCompactWindow` (Context, number, `0`, `min: 0`, `floor: 100000`, `max: 1000000`, `step: 50000`); `autoCompactEnabled` (Context, boolean, `true`).
- **`scripts/forge-config workflow`** (Task 2). Prints one line naming every `enforcedBy: 'skill'` key whose resolved value differs from its default, in schema order, or nothing when none does; exit 0. The line is exactly `dr-forge settings in force (each replaces the matching question or default in the skills): <key>=<value>; <key>=<value>`. An argument is a usage error, exit 2.
- **`forge_setting KEY DEFAULT`** (Task 2, `plugins/dr-forge/scripts/lib/forge-env.sh`). Prints the value `forge-config get KEY` prints, or `DEFAULT` when that command fails or prints nothing. Never returns non-zero. It runs the command with `DR_FORGE_NO_IMPORT=1`, under which `forge-config` skips the one-time import and so never creates `~/.dr-forge/config.json`. With `DR_FORGE_NO_SETTINGS` set it prints `DEFAULT` without running anything.
- **Claude target in `forge-config`** (Task 3). `get` and `get --json` resolve a `target: 'claude'` key from `$CLAUDE_CONFIG_DIR/settings.json`, else `~/.claude/settings.json`, then the default; an unreadable file is warned about on stderr and read as empty. `set KEY VALUE` and `unset KEY` change that one key in that file: every other key and the key order kept, written to a temporary file and renamed, through a symlink to the real file, with the file's mode kept. `set autoCompactWindow 0` and `unset` delete the key. A file that exists but is not a JSON object is not written: exit 1. Exit 2 on an invalid value, as for any key.
- **`codex-gate` line** (Task 4). Unchanged shape; `source` is `probe`, `cache` or `setting`. With `codexReview` false `review=false`; with `codexLane` false `lane=false`; with both false `usable=false reason=setting review=false lane=false resets_at=- source=setting` and no probe.
- **Budget lines** (Task 6). With `handoffMode` `relaxed`, a plain line is labelled `budget (relaxed)` and a wave line `budget (relaxed, wave of N)`, both measured against the final-phase limit (the wave less one task margin of 140,000 per extra task). `final`, `tail` and `plan` lines are unchanged. In `strict`, the task budget is `DR_FORGE_BUDGET`, else the `handoffTokens` setting when above 0, else the rule.
- **`finish-choice`** (Task 7). `get` and `arm`, when no choice is recorded and `finishAction` is `merge`, `pr`, `keep` or `wait`, first write `{"action": <it>, "base": null, "chosenAt": <now>, "source": "setting"}`. `arm` without `--minutes` waits `finishTimeout` minutes.
- **`plugins/dr-forge/hooks/cockpit/config.ts` exports added by Task 8.** `SettingSpec` gains `label: string`, `unit?: 'k' | '%' | 's' | 'min'`, `zero?: string`, `floor?: number`, `enforcedBy?: 'script' | 'skill'`. `type ViewRow = { key: string; group: string; label: string; description: string; kind: 'toggle' | 'choices' | 'stepper' | 'text'; value: SettingValue; shown: string; shownDefault: string; values: readonly string[]; isChanged: boolean; lockedBy: string | null }`. Functions: `tabsOf(schema): string[]`; `shownValue(spec, value): string`; `typedNumber(spec, text): number | undefined`; `rangeText(spec): string`; `steppedSetting(spec, value, direction: 1 | -1): number`; `rowOf(key, spec, value, lockedBy?): ViewRow`; `rowsOf(schema, values, group, locks?): ViewRow[]`; `envLocks(schema, env): Record<string, string>`; `claudeLocks(schema, merged, user): Record<string, string>`. `resolveSettings(schema, file, env, claude?)` takes a `target: 'claude'` key from `claude`. `settingWritten` throws `<key> is stored in Claude's settings file` for a `target: 'claude'` key.
- **`plugins/dr-forge/hooks/cockpit/settings-view.tsx`** (Task 9). `drawSettings(table, model: SettingsModel, act: SettingsActions): RenderChildren`, where `table` is what `$.ui.resolve(e)` returns. Element keys: tabs `settings-tab-<Group>`; a row's block `set-<key>-block` and label `set-<key>-label`; controls `set-<key>-toggle`, `set-<key>-<choice>`, `set-<key>-less`, `set-<key>-more`, `set-<key>-edit`, `set-<key>-input`, `set-<key>-cancel`, `set-<key>-reset`; footer `settings-back` (hotkey `b`), `settings-help` (`i`), `settings-reset` (`r`), `settings-reset-confirm`, `settings-reset-cancel`. A changed row draws `set-<key>-mark`, whether the schema or the caller draws its control. **Reset group** is offered while a row of the open group differs from its default and resets those rows; a locked row is never one of them.
- **Cockpit state** (Task 9). Atom `settingsView` (`{ plugin: 'dr-forge', key: 'settingsView' }`) of type `CockpitSettingsView = { tab: string; isHelpShown: boolean; editing: string | null; error: string | null; isConfirmingReset: boolean }`, declared in `plugins/dr-forge/types/index.d.ts`. Top-level `showSettings($)` in `register.tsx` opens the settings with no edit or reset pending. From Task 11, `S.locks: Record<string, string>`, `S.changed: Record<string, SettingValue>` and `S.claudeSaved: Record<string, SettingValue>` in `register.tsx`.
- **`finalLimitFor(window, compactWindow?)`** (Task 10, `plugins/dr-forge/hooks/cockpit/lib.ts`): `Math.floor(min(window, compactWindow) * 0.85)`; 680,000 for a 1,000,000 window with `autoCompactWindow` 800,000, the same figure `tests/budget-line.test.sh` asserts for the scripts.

## Assumptions (evidence)

- A mod loads a second `.tsx` module that draws with JSX when it receives the element table and callbacks: scratch copy with `hooks/cockpit/settings-view.tsx` imported from `register.tsx`, `claude plugin validate` passed and `claude plugin test` ran 127 pass, 0 fail, Claude Code 2.1.296, 2026-10-12.
- `$` may not cross an import: the same probe passing `$` to the imported function failed validation with "$ is followed only into a function declared in this same file, never across an import", 2026-10-12. The view module therefore takes no `$`.
- `$.process.run(['node', `${$.plugin.root}/scripts/lib/forge-config.mjs`, …])` inside a top-level function validates: scratch probe, `claude plugin validate` passed, 2026-10-12. `$.plugin.root` is "the plugin's directory (the one holding plugin.json), absolute" in the engine types for 2.1.296.
- Cockpit baseline: `claude plugin test plugins/dr-forge` → 127 pass, 0 fail (2026-10-12, on the probe copy of the unchanged suite).
- `tests/cockpit.test.ts` has a `CONTROL` map that must name every schema key (`draws every setting under its schema group`, line 703), so Tasks 1 and 3 extend it and Task 9 replaces that test: `plugins/dr-forge/tests/cockpit.test.ts:703-730`.
- The test kit finds a Box by key and feeds a text field: `ui.find({ key: 'set-group-Notifications' })` and `ui.input({ key, text, kind: 'submit' })` in `plugins/dr-forge/tests/cockpit.test.ts:729` and `:1701`.
- `scripts/codex-gate` writes `review` and `lane` into the session file on every call, cache hit or probe, and that file is what the other scripts read: `plugins/dr-forge/scripts/codex-gate:78-96`, `plugins/dr-forge/scripts/lib/executor-session.sh` (`executor_session_on`).
- The Bash budget reads only `DR_FORGE_BUDGET` today (`plugins/dr-forge/scripts/lib/context.sh`, `ctx_line`); joining it with the `handoffTokens` setting was deferred to this plan (merge-register row 5), so Task 6 adds it.
- Both auto-compaction keys live in the user settings file: `grep autoCompact ~/.claude/settings.json` printed `"autoCompactEnabled": true` and `"autoCompactWindow": 800000`, 2026-10-12. The engine documents 100,000 to 1,000,000 for `autoCompactWindow` (engine types, agent definition field).
- An unknown model's window is 1,000,000 in `ctx_model_window`, so a test transcript with model `m` and `autoCompactWindow` 800,000 has a final-phase limit of 680,000: `plugins/dr-forge/scripts/lib/context.sh:144-149`.
- The generic stepper moves to the next multiple of the schema's `step`, so `notifyAfter` steps by 15 seconds throughout (today 60 above one minute); typing the value with Edit replaces the long walk. No test presses that stepper.
- Task 9's file score counts three shapes: the view module, `register.tsx` with its one-type state contract in `types/index.d.ts`, and the test file.
- The check "the command runs with path conversion off" (Task 2) exercises the wrapper's path conversion only under Git Bash; on Linux it passes either way, so the Windows CI shards are what confirm it. `dr_native_path` uses `cygpath -m`, as `plugins/dr-forge/scripts/lib/native-path.sh` already does for the Codex scripts.
- unverified — Task 11 verifies it: that a test hook on `session.append` which throws makes `$.session.append` reject inside the mod. Task 11 Step 4 runs the retry test; if the kit swallows the throw, the test's first expectation (no note) still holds and its last fails, and the fix is to have the hook return without calling `next(e)` and skip recording the note.
- Whether `$.settings.read()` reflects a write another process made to Claude's settings file within the same session is unknown, so the cockpit overlays the values it saved itself (`S.claudeSaved`, Task 11) rather than rely on it; Task 13's manual check looks at the real behaviour.
- The spec's Reset group acts on the rows that differ from their defaults, as the mock the owner reviewed did; a default-valued row has nothing to reset.
- A plan fixed to `subagent` or `inline` by the `executionMode` setting can make `plan-lint` warn that the Execution line disputes the majority rule; that warning is the documented behaviour for an overridden line.
- The Codex lane is on by `docs/superpowers/distilled/constraints.md`, the gate printed `lane=true` and the roster reported `codex` usable (2026-10-12), so every task passing the lane gate carries an `**Executor:**` line. Such a task runs alone in its wave, which leaves one wave of four Claude tasks (4-7); the owner may remove Executor lines to widen the waves.

## Task index

1. Schema: row fields, groups and workflow keys
2. The workflow line and forge_setting
3. Claude's settings file as a target
4. Codex switches in the session gate
5. Settings line at session start
6. Handoff mode and the budget setting in the budget scripts
7. Finish settings in finish-choice
8. Settings row model
9. Tabbed settings view
10. Relaxed handoff limit in the cockpit
11. Claude keys, locked rows and the settings note
12. Skills obey the workflow settings
13. Release 2.1.0

---

### Task 1: Schema: row fields, groups and workflow keys

**Files:**
- Modify: `plugins/dr-forge/config/schema.mjs`
- Modify: `scripts/validate-repository.mjs:122-146`
- Test: `tests/repository-layout.test.mjs`, `plugins/dr-forge/tests/forge-config.test.sh`, `plugins/dr-forge/tests/cockpit.test.ts:703-717`

**Interfaces:**
- Consumes: nothing.
- Produces: Contracts "Schema entry" and "Keys added by Task 1".

**Items:** 2, 3

**Depends on:** none

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/repository-layout.test.mjs`, inside `test('the settings schema is valid, and broken schemas are caught', …)`, add after the last `assert.match` line:

```js
  const entry = extra => `export default { n: { type: 'number', default: 0, min: 0, max: 10, group: 'Cockpit', label: 'N', title: 't', description: 'd', target: 'forge', ${extra} } }\n`;
  assert.match(await broken(real.replace("label: 'Layout'", "label: 'A label that is far too long'")), /schema layout: label is required, at most 16 characters/);
  assert.match(await broken(real.replace("group: 'Finish'", "group: 'Elsewhere'")), /group must be one of Cockpit, Context, Workflow, Process, Finish, Notifications/);
  assert.match(await broken(entry("unit: 'parsecs'")), /schema n: unit must be one of k, %, s, min, on a number/);
  assert.match(await broken(entry("zero: 'nil'")), /schema n: zero must be one of auto, off, any, hidden, unset, on a number/);
  assert.match(await broken(entry('floor: 5').replace('default: 0', 'default: 3')), /schema n: default does not fit its type/);
  assert.match(await broken(entry('step: 1').replace('default: 0', 'default: 2.5')), /schema n: default does not fit its type/);
  assert.match(await broken(entry("enforcedBy: 'luck'")), /schema n: enforcedBy must be script or skill/);
  assert.match(await broken(entry('floor: 50')), /schema n: floor must lie between 1 and max, on a number whose min is 0/);
  assert.equal(await broken(entry('floor: 5')), '');
```

In `plugins/dr-forge/tests/forge-config.test.sh`, add before the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"`:

```bash
# --- the workflow keys: defaults and refusals ---
fresh w
check "workflow keys: defaults" "$(fc get --json | node -e 'const v = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log([v.handoffMode, v.codexLane, v.codexReview, v.executionStrategy, v.executionMode, v.worktree, v.processBias, v.designApproval, v.specReview, v.questionStyle, v.finishAction, v.finishTimeout].join(" "))')" \
  "strict true true ask auto ask standard sections true single ask 30"
# Each key: its default, a value it accepts, and one it refuses.
while read -r key default valid invalid; do
  fresh "m-$key"
  check "$key: default" "$(fc get "$key")" "$default"
  fc set "$key" "$valid"; check "$key: a valid value: exit 0" "$?" "0"
  check "$key: the value is read back" "$(fc get "$key")" "$valid"
  fc set "$key" "$invalid"; check "$key: an invalid value: exit 2" "$?" "2"
  check "$key: a refusal keeps the value" "$(fc get "$key")" "$valid"
done <<'ROWS'
handoffMode strict relaxed loose
codexLane true false maybe
codexReview true false 0
executionStrategy ask parallel fast
executionMode auto subagent agent
worktree ask always sometimes
processBias standard heavier heavy
designApproval sections whole none
specReview true false no
questionStyle single batched many
finishAction ask merge discard
finishTimeout 30 45 3
ROWS
```

In `plugins/dr-forge/tests/cockpit.test.ts`, add these entries to the `CONTROL` map, after `notifyDetail: 'set-notifyDetail-full',`:

```ts
    handoffMode: 'set-handoffMode-strict',
    codexLane: 'set-codexLane-toggle',
    codexReview: 'set-codexReview-toggle',
    executionStrategy: 'set-executionStrategy-ask',
    executionMode: 'set-executionMode-auto',
    worktree: 'set-worktree-ask',
    processBias: 'set-processBias-standard',
    designApproval: 'set-designApproval-sections',
    specReview: 'set-specReview-toggle',
    questionStyle: 'set-questionStyle-single',
    finishAction: 'set-finishAction-ask',
    finishTimeout: 'set-finishTimeout-more',
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 120 node --test tests/repository-layout.test.mjs 2>&1 | tail -15`
Expected: FAIL in "the settings schema is valid, and broken schemas are caught" (the label assertion does not match).

Run: `timeout 120 bash plugins/dr-forge/tests/forge-config.test.sh | tail -8`
Expected: FAIL lines for "workflow keys: defaults" and the lines after it.

- [ ] **Step 3: Replace the schema**

Replace the whole of `plugins/dr-forge/config/schema.mjs` with:

```js
// Every dr-forge setting: its type, default, the settings-view group and text,
// and where it is stored. An ES module rather than JSON because a Claude Code
// mod imports only code files; the cockpit, scripts/lib/forge-config.mjs and
// scripts/validate-repository.mjs all import it. Values live in
// ~/.dr-forge/config.json, whose `darkmem` key is reserved for the darkmem mapping.
//
// The groups are the settings view's tabs, in the order they first appear here.
// label is the row's label there (at most 16 characters); unit and zero say how
// a number reads (`k` is thousands of tokens, zero the word shown at 0).
// enforcedBy names what obeys a workflow key: `script`, the script that already
// makes the decision, or `skill`, through the `forge-config workflow` line.
export default {
  openAtStart: {
    type: 'boolean', default: true, group: 'Cockpit', target: 'forge',
    label: 'Show at start', title: 'Open the pane at session start',
    description: 'Open the cockpit when a session starts. Claude Code shows it once the terminal is 144 columns wide, 110 once you have opened it before; /cockpit opens it at any width.',
  },
  layout: {
    type: 'enum', values: ['auto', 'full', 'compact'], default: 'auto', group: 'Cockpit', target: 'forge',
    label: 'Layout', title: 'Pane layout',
    description: 'auto: the full layout docked beside the transcript, the band when the pane sits above the prompt. full: always the full layout. compact: minimized, the band above the prompt; Minimize sets it and Expand sets auto.',
  },
  sections: {
    type: 'string', default: '', group: 'Cockpit', target: 'forge',
    label: 'Sections', title: 'Pane sections',
    description: 'Which sections the full pane shows, in order, comma-separated: account, context, usage, shells, agents, plan, repo, guard. Empty shows all eight.',
  },
  breakdownRows: {
    type: 'number', default: 6, min: 0, max: 12, step: 1, zero: 'hidden', group: 'Cockpit', target: 'forge',
    label: 'Context rows', title: 'Context breakdown rows',
    description: 'How many /context categories the Context section lists, largest first, up to 12. 0 hides the breakdown.',
  },
  guardAttribution: {
    type: 'boolean', default: true, group: 'Cockpit', target: 'forge',
    label: 'AI attribution', title: 'Keep AI attribution out of git',
    description: 'Drop the commit trailer and pull request footer Claude Code asks for, and refuse commits and pull requests that still carry AI attribution.',
  },
  handoffTokens: {
    type: 'number', default: 0, min: 0, max: 2_000_000, step: 50_000, unit: 'k', zero: 'auto', env: 'DR_FORGE_BUDGET', group: 'Context', target: 'forge',
    label: 'Handoff budget', title: 'Handoff budget (tokens)',
    description: "Context size at which the cockpit and the budget scripts say hand off. 0 follows dr-forge's rule: 93% of the smaller of autoCompactWindow and the model's window, minus 140,000. DR_FORGE_BUDGET overrides it; relaxed handoff mode ignores it.",
  },
  handoffMode: {
    type: 'enum', values: ['strict', 'relaxed'], default: 'strict', enforcedBy: 'script', group: 'Context', target: 'forge',
    label: 'Handoff mode', title: 'Handoff mode',
    description: 'strict hands off at the handoff budget. relaxed measures every task against the final-phase limit, 85% of the window, and the handoff budget then has no effect.',
  },
  warnAt: {
    type: 'number', default: 80, min: 1, max: 99, step: 5, unit: '%', group: 'Context', target: 'forge',
    label: 'Warn at', title: 'Warn at (% of the handoff budget)',
    description: 'Where Hand off takes the accent color, as a share of the handoff budget, 1 to 99.',
  },
  nudgeModel: {
    type: 'boolean', default: true, group: 'Context', target: 'forge',
    label: 'Handoff note', title: 'Tell the model at the budget',
    description: 'In a session running dr-forge, add one note to the conversation when the main session crosses its handoff budget.',
  },
  codexLane: {
    type: 'boolean', default: true, enforcedBy: 'script', group: 'Workflow', target: 'forge',
    label: 'Codex tasks', title: 'Give tasks to Codex',
    description: 'Give plan tasks to Codex when its gate passes. Off keeps every task on Claude.',
  },
  codexReview: {
    type: 'boolean', default: true, enforcedBy: 'script', group: 'Workflow', target: 'forge',
    label: 'Codex reviews', title: 'Let Codex review',
    description: 'Let Codex take review seats when its gate passes. Off keeps every review on Claude.',
  },
  executionStrategy: {
    type: 'enum', values: ['ask', 'sequential', 'parallel'], default: 'ask', enforcedBy: 'skill', group: 'Workflow', target: 'forge',
    label: 'Strategy', title: 'Execution strategy',
    description: 'How a plan executes. ask keeps the question; parallel falls back to sequential when the parts share files, and on Codex.',
  },
  executionMode: {
    type: 'enum', values: ['auto', 'inline', 'subagent'], default: 'auto', enforcedBy: 'skill', group: 'Workflow', target: 'forge',
    label: 'Execution mode', title: 'Execution mode',
    description: "Who implements plan tasks. auto follows the planner's rule; inline and subagent fix the plan's Execution line, and inline also makes the plan sequential.",
  },
  worktree: {
    type: 'enum', values: ['ask', 'always', 'never'], default: 'ask', enforcedBy: 'skill', group: 'Workflow', target: 'forge',
    label: 'Worktree', title: 'Worktree',
    description: 'Whether work is isolated in a git worktree before it starts. ask keeps the consent question.',
  },
  processBias: {
    type: 'enum', values: ['standard', 'lighter', 'heavier'], default: 'standard', enforcedBy: 'skill', group: 'Process', target: 'forge',
    label: 'Path bias', title: 'Path bias',
    description: 'How readily a request gets a written spec and plan. lighter resolves doubt to a short in-chat design; heavier resolves it to a spec.',
  },
  designApproval: {
    type: 'enum', values: ['sections', 'whole'], default: 'sections', enforcedBy: 'skill', group: 'Process', target: 'forge',
    label: 'Design approval', title: 'Design approval',
    description: 'sections approves each design section in turn; whole presents the design once with one approval.',
  },
  specReview: {
    type: 'boolean', default: true, enforcedBy: 'skill', group: 'Process', target: 'forge',
    label: 'Spec review stop', title: 'Stop for spec review',
    description: 'Stop for you to review the written spec before the plan is written. Off goes straight to the plan after the self-review.',
  },
  questionStyle: {
    type: 'enum', values: ['single', 'batched'], default: 'single', enforcedBy: 'skill', group: 'Process', target: 'forge',
    label: 'Questions', title: 'Clarifying questions',
    description: 'single asks one clarifying question per message; batched asks them all in one message.',
  },
  finishAction: {
    type: 'enum', values: ['ask', 'merge', 'pr', 'keep', 'wait'], default: 'ask', enforcedBy: 'script', group: 'Finish', target: 'forge',
    label: 'When done', title: 'When the finish menu goes unanswered',
    description: 'ask keeps the question before the first task. Any other value skips it: merge, pr or keep runs after the wait below; wait never acts.',
  },
  finishTimeout: {
    type: 'number', default: 30, min: 5, max: 240, step: 5, unit: 'min', enforcedBy: 'script', group: 'Finish', target: 'forge',
    label: 'Menu waits', title: 'Finish menu wait (minutes)',
    description: 'How long the finish menu waits before the action above runs.',
  },
  limitAlertAt: {
    type: 'number', default: 90, min: 0, max: 100, step: 5, unit: '%', zero: 'off', group: 'Notifications', target: 'forge',
    label: 'Limit alert at', title: 'Discord usage limit alert (%)',
    description: 'Send the Discord limit message once when the 5-hour or 7-day limit crosses this share, again after it resets. 0 turns it off.',
  },
  notifyOn: {
    type: 'string', default: '', group: 'Notifications', target: 'forge',
    label: 'Send on', title: 'Discord: events to send',
    description: 'Comma-separated: ask, question, done, error, blocked, budget, limit, task, session, agent. Empty sends ask, question, done, error, blocked, budget and limit; none sends nothing.',
  },
  notifyAfter: {
    type: 'number', default: 60, min: 0, max: 3600, step: 15, unit: 's', zero: 'any', group: 'Notifications', target: 'forge',
    label: 'Done after', title: 'Discord: done after (seconds)',
    description: 'A finished turn is sent only when it ran at least this long. 0 sends every turn.',
  },
  notifyAskAfter: {
    type: 'number', default: 20, min: 0, max: 600, step: 10, unit: 's', group: 'Notifications', target: 'forge',
    label: 'Ask after', title: 'Discord: approval after (seconds)',
    description: 'An approval or question is sent only when it is still unanswered after this long. 0 sends at once.',
  },
  notifyDetail: {
    type: 'enum', values: ['full', 'brief'], default: 'full', group: 'Notifications', target: 'forge',
    label: 'Detail', title: 'Discord: detail',
    description: 'full sends command, question and answer excerpts (secrets masked); brief sends titles and figures only.',
  },
};
```

- [ ] **Step 4: Teach the validator the new fields**

In `scripts/validate-repository.mjs`, replace the line `const GROUPS = ['Cockpit', 'Context', 'Notifications', 'Workflow'];` with:

```js
const GROUPS = ['Cockpit', 'Context', 'Workflow', 'Process', 'Finish', 'Notifications'];
const UNITS = ['k', '%', 's', 'min'];
const ZEROS = ['auto', 'off', 'any', 'hidden', 'unset'];
```

In `validateSchema`, add after the line that checks `spec.step`:

```js
    if (typeof spec.label !== 'string' || !spec.label || spec.label.length > 16) errors.push(`${at}: label is required, at most 16 characters`);
    if (spec.unit !== undefined && !(spec.type === 'number' && UNITS.includes(spec.unit))) errors.push(`${at}: unit must be one of ${UNITS.join(', ')}, on a number`);
    if (spec.zero !== undefined && !(spec.type === 'number' && ZEROS.includes(spec.zero))) errors.push(`${at}: zero must be one of ${ZEROS.join(', ')}, on a number`);
    if (spec.enforcedBy !== undefined && !['script', 'skill'].includes(spec.enforcedBy)) errors.push(`${at}: enforcedBy must be script or skill`);
    if (spec.floor !== undefined && !(spec.type === 'number' && spec.min === 0 && Number.isFinite(spec.floor) && spec.floor >= 1 && (spec.max === undefined || spec.floor <= spec.max))) errors.push(`${at}: floor must lie between 1 and max, on a number whose min is 0`);
```

Replace the line ``    if (!fits) errors.push(`${at}: default does not fit its type`);`` with:

```js
    // A number setting is whole, and a floored one has no values between 0 and its floor.
    const whole = spec.type !== 'number' || (Number.isInteger(spec.default) && (spec.floor === undefined || spec.default === 0 || spec.default >= spec.floor));
    if (!fits || !whole) errors.push(`${at}: default does not fit its type`);
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 120 node --test tests/repository-layout.test.mjs 2>&1 | tail -6`
Expected: `# fail 0`

Run: `timeout 120 bash plugins/dr-forge/tests/forge-config.test.sh | tail -3`
Expected: a line ending `0 failed`

Run: `timeout 60 node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

Run: `timeout 420 claude plugin test plugins/dr-forge 2>&1 | tail -4`
Expected: `127 pass` and `0 fail` (the current view draws the new keys with its generic controls).

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-forge/config/schema.mjs scripts/validate-repository.mjs tests/repository-layout.test.mjs plugins/dr-forge/tests/forge-config.test.sh plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): add workflow keys to the schema"
```

---

### Task 2: The workflow line and forge_setting

**Files:**
- Modify: `plugins/dr-forge/scripts/lib/forge-config.mjs`, `plugins/dr-forge/scripts/forge-config` (its header line and its last line)
- Modify: `plugins/dr-forge/scripts/lib/forge-env.sh`
- Test: `plugins/dr-forge/tests/forge-config.test.sh`

**Interfaces:**
- Consumes: Contracts "Keys added by Task 1" (`enforcedBy`).
- Produces: Contracts "`scripts/forge-config workflow`" and "`forge_setting KEY DEFAULT`".

**Items:** 2

**Depends on:** Task 1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-forge/tests/forge-config.test.sh`, add before the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"`:

```bash
# --- the workflow line: the skill-enforced keys that differ from their defaults ---
fresh x
check "workflow: nothing at the defaults" "$(fc workflow)" ""
fc workflow > /dev/null; check "workflow: exit 0" "$?" "0"
fc set designApproval whole; fc set worktree always; fc set codexLane false; fc set finishAction merge
check "workflow: only skill keys, in schema order" "$(fc workflow)" \
  "dr-forge settings in force (each replaces the matching question or default in the skills): worktree=always; designApproval=whole"
fc workflow extra; check "workflow takes no argument: exit 2" "$?" "2"

# --- forge_setting: the value in force, or the default when the command cannot answer ---
. "$HERE/../scripts/lib/forge-env.sh"
check "forge_setting reads the file" "$(forge_setting worktree ask)" "always"
check "forge_setting: an unknown key gives the default" "$(forge_setting nope fallback)" "fallback"
printf 'not json' > "$FILE"
check "forge_setting: a broken file gives the default" "$(forge_setting worktree ask)" "ask"
forge_setting worktree ask > /dev/null; check "forge_setting never fails" "$?" "0"
fresh y
check "forge_setting: a first read answers the default" "$(forge_setting worktree ask)" "ask"
check "forge_setting: a read never creates the settings file" "$([ -e "$FILE" ] && echo created || echo absent)" "absent"
fc set worktree never
check "DR_FORGE_NO_SETTINGS answers the default" "$(DR_FORGE_NO_SETTINGS=1 forge_setting worktree ask)" "ask"
# Git Bash with path conversion off hands node the module path as written.
check "the command runs with path conversion off" "$(MSYS_NO_PATHCONV=1 fc get worktree)" "never"
# A number setting is a whole number.
fc set finishTimeout 5.5; check "a fraction: exit 2" "$?" "2"
fc set warnAt 72.5; check "a fraction of an older key: exit 2" "$?" "2"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 bash plugins/dr-forge/tests/forge-config.test.sh | tail -12`
Expected: FAIL for "workflow: only skill keys, in schema order" and "forge_setting reads the file" (`forge_setting: command not found` on stderr).

- [ ] **Step 3: Add the workflow command**

In `plugins/dr-forge/scripts/lib/forge-config.mjs`, replace the `USAGE` line with:

```js
const USAGE = "usage: forge-config get KEY | get --json | set KEY VALUE | unset KEY | workflow";
```

Add after the `resolve` function:

```js
// One line naming the skill-enforced keys that differ from their defaults, for
// the session-start hook and the skills; empty when every one is at its default.
export function workflowLine(env = process.env) {
  const values = resolve(env, () => {});
  const parts = Object.entries(SCHEMA)
    .filter(([key, spec]) => spec.enforcedBy === "skill" && values[key] !== spec.default)
    .map(([key]) => `${key}=${values[key]}`);
  return parts.length === 0 ? "" : `dr-forge settings in force (each replaces the matching question or default in the skills): ${parts.join("; ")}`;
}
```

In `main`, add before the line `process.stderr.write(`${USAGE}\n`);`:

```js
    if (command === "workflow" && rest.length === 0) {
      const line = workflowLine(env);
      if (line) out.write(`${line}\n`);
      return 0;
    }
```

In `main`, replace the line `    importLegacy(env);` with:

```js
    // A script reading one setting must not be what creates the settings file.
    if (!env.DR_FORGE_NO_IMPORT) importLegacy(env);
```

In `isValid`, replace `Number.isFinite(value)` with `Number.isInteger(value)` in the `case "number":` arm.

In `plugins/dr-forge/scripts/forge-config`, replace line 2 with:

```bash
# dr-forge's settings: forge-config get KEY | get --json | set KEY VALUE | unset KEY | workflow
```

and replace its last line, `exec node "$HERE/lib/forge-config.mjs" "$@"`, with:

```bash
. "$HERE/lib/native-path.sh"
# With path conversion off (MSYS_NO_PATHCONV=1, as the budget tests export), Git
# Bash would hand node a POSIX module path that Windows cannot resolve.
exec node "$(dr_native_path "$HERE/lib/forge-config.mjs")" "$@"
```

- [ ] **Step 4: Add forge_setting**

Append to `plugins/dr-forge/scripts/lib/forge-env.sh`:

```bash

_FORGE_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# forge_setting KEY DEFAULT - the setting in force (scripts/forge-config), or
# DEFAULT when the command cannot answer: no Node, an unknown key, or a settings
# file that cannot be read. A setting must never be what fails its caller, and
# reading one never creates the settings file (DR_FORGE_NO_IMPORT).
# DR_FORGE_NO_SETTINGS answers DEFAULT outright, for a test suite that runs
# against the real home directory.
forge_setting() {
  local value=""
  if [ -z "${DR_FORGE_NO_SETTINGS:-}" ]; then
    value=$(DR_FORGE_NO_IMPORT=1 bash "$_FORGE_ENV_DIR/../forge-config" get "$1" 2>/dev/null | tr -d '\r') || value=""
  fi
  [ -n "$value" ] || value=$2
  printf '%s' "$value"
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 120 bash plugins/dr-forge/tests/forge-config.test.sh | tail -3`
Expected: a line ending `0 failed`

Run: `timeout 300 bash plugins/dr-forge/tests/context-size.test.sh | tail -2`
Expected: a line ending `0 failed` (`context.sh` sources `forge-env.sh`).

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-forge/scripts/lib/forge-config.mjs plugins/dr-forge/scripts/forge-config plugins/dr-forge/scripts/lib/forge-env.sh plugins/dr-forge/tests/forge-config.test.sh
git commit -m "feat(dr-forge): add the workflow settings line"
```

---

### Task 3: Claude's settings file as a target

**Files:**
- Modify: `plugins/dr-forge/config/schema.mjs` (after the `nudgeModel` entry)
- Modify: `plugins/dr-forge/scripts/lib/forge-config.mjs`
- Test: `plugins/dr-forge/tests/forge-config.test.sh`, `plugins/dr-forge/tests/cockpit.test.ts` (the `CONTROL` map)

**Interfaces:**
- Consumes: Contracts "Schema entry" (`floor`, `target`).
- Produces: Contracts "Keys added by Task 3" and "Claude target in `forge-config`".

**Items:** 2

**Depends on:** Task 1, Task 2

**Implementer:** dr-superpowers:impl-opus-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 3 = 6

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-forge/tests/forge-config.test.sh`, add before the section `# --- the workflow line` (Task 2 sources `forge-env.sh` and breaks the file after it, so this section goes above):

```bash
# --- Claude's own settings file: one key changed, everything else kept ---
fresh k
keys() { node -e 'console.log(Object.keys(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))).join(","))' "$1"; }
at() { node -e 'console.log(JSON.stringify(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))[process.argv[2]]))' "$1" "$2"; }
mkdir -p "$HOME/.claude"
CS="$HOME/.claude/settings.json"
check "claude: defaults with no file" "$(fc get autoCompactWindow) $(fc get autoCompactEnabled)" "0 true"
printf '%s\n' '{"permissions":{"allow":["Bash(ls:*)"]},"autoCompactWindow":650000,"hooks":{}}' > "$CS"
check "claude: read from the settings file" "$(fc get autoCompactWindow)" "650000"
fc set autoCompactWindow 800000; check "claude set: exit 0" "$?" "0"
check "claude set: the value" "$(at "$CS" autoCompactWindow)" "800000"
check "claude set: every other key and the order kept" "$(keys "$CS")" "permissions,autoCompactWindow,hooks"
check "claude set: the permissions untouched" "$(at "$CS" permissions)" '{"allow":["Bash(ls:*)"]}'
check "claude set: nothing in the forge file" "$(keys "$FILE")" ""
fc set autoCompactWindow 50000; check "claude: below the floor: exit 2" "$?" "2"
fc set autoCompactWindow 1050000; check "claude: above the maximum: exit 2" "$?" "2"
check "claude: a refusal changes nothing" "$(at "$CS" autoCompactWindow)" "800000"
fc set autoCompactEnabled false
check "claude: a new key goes last" "$(keys "$CS")" "permissions,autoCompactWindow,hooks,autoCompactEnabled"
fc set autoCompactEnabled true
check "claude: the default boolean is written, not dropped" "$(at "$CS" autoCompactEnabled)" "true"
fc set autoCompactWindow 0
check "claude: 0 removes the key" "$(keys "$CS")" "permissions,hooks,autoCompactEnabled"
fc unset autoCompactEnabled
check "claude: unset removes the key" "$(keys "$CS")" "permissions,hooks"
check "claude: get --json carries both" "$(fc get --json | node -e 'const v = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log(v.autoCompactWindow, v.autoCompactEnabled, v.warnAt)')" "0 true 80"

# A file that cannot be parsed is never replaced, and the forge keys still resolve.
printf 'not json' > "$CS"
fc set autoCompactWindow 800000; check "claude: an unparseable file: exit 1" "$?" "1"
check "claude: an unparseable file is left byte-identical" "$(cat "$CS")" "not json"
check "claude: the file is named" "$(grep -c 'settings.json is not valid JSON' "$TMP/stderr")" "1"
check "claude: forge keys still resolve" "$(fc get warnAt)" "80"
check "claude: the unreadable file reads as the default" "$(fc get autoCompactWindow)" "0"
rm -f "$CS"
fc set autoCompactWindow 800000
check "claude: a missing file is created with the one key" "$(tr -d ' \n' < "$CS")" '{"autoCompactWindow":800000}'
check "claude: no temporary file left" "$(ls "$HOME/.claude" | grep -c '\.tmp$')" "0"

# CLAUDE_CONFIG_DIR names the file.
mkdir -p "$TMP/alt-k"
printf '%s\n' '{"model":"opus"}' > "$TMP/alt-k/settings.json"
CLAUDE_CONFIG_DIR="$TMP/alt-k" fc set autoCompactWindow 500000
check "claude: CLAUDE_CONFIG_DIR is written" "$(keys "$TMP/alt-k/settings.json")" "model,autoCompactWindow"
check "claude: the home file is left alone" "$(at "$CS" autoCompactWindow)" "800000"

# A symlinked settings file stays a symlink, and its mode is kept. Neither holds on Windows.
if ! command -v cygpath > /dev/null 2>&1; then
  mkdir -p "$TMP/dotfiles"
  printf '%s\n' '{"model":"opus"}' > "$TMP/dotfiles/settings.json"
  chmod 600 "$TMP/dotfiles/settings.json"
  rm -f "$CS"; ln -s "$TMP/dotfiles/settings.json" "$CS"
  fc set autoCompactWindow 700000
  check "claude: a symlink stays a symlink" "$([ -L "$CS" ] && echo yes || echo no)" "yes"
  check "claude: the real file is written" "$(keys "$TMP/dotfiles/settings.json")" "model,autoCompactWindow"
  check "claude: the mode is kept" "$(node -e 'console.log((require("fs").statSync(process.argv[1]).mode & 0o777).toString(8))' "$TMP/dotfiles/settings.json")" "600"
  # A link whose destination does not exist yet is written through, not replaced.
  rm -f "$CS"; ln -s "$TMP/dotfiles/later.json" "$CS"
  fc set autoCompactWindow 600000
  check "claude: a dangling symlink stays a symlink" "$([ -L "$CS" ] && echo yes || echo no)" "yes"
  check "claude: its destination is created" "$(tr -d ' \n' < "$TMP/dotfiles/later.json")" '{"autoCompactWindow":600000}'
fi

# Each Claude key: its default, a value it accepts, and one it refuses.
while read -r key default valid invalid; do
  fresh "m-$key"
  check "$key: default" "$(fc get "$key")" "$default"
  fc set "$key" "$valid"; check "$key: a valid value: exit 0" "$?" "0"
  check "$key: the value is read back" "$(fc get "$key")" "$valid"
  fc set "$key" "$invalid"; check "$key: an invalid value: exit 2" "$?" "2"
  check "$key: a refusal keeps the value" "$(fc get "$key")" "$valid"
done <<'ROWS'
autoCompactWindow 0 100000 99999
autoCompactEnabled true false maybe
ROWS
```

In `plugins/dr-forge/tests/cockpit.test.ts`, add to the `CONTROL` map after the `finishTimeout` entry:

```ts
    autoCompactWindow: 'set-autoCompactWindow-more',
    autoCompactEnabled: 'set-autoCompactEnabled-toggle',
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 bash plugins/dr-forge/tests/forge-config.test.sh | tail -40`
Expected: FAIL for "claude: defaults with no file" (`unknown setting autoCompactWindow`) and every line after it in the section.

- [ ] **Step 3: Add the two keys**

In `plugins/dr-forge/config/schema.mjs`, add after the closing `},` of the `nudgeModel` entry:

```js
  autoCompactWindow: {
    type: 'number', default: 0, min: 0, floor: 100_000, max: 1_000_000, step: 50_000, unit: 'k', zero: 'unset', group: 'Context', target: 'claude',
    label: 'Auto-compact at', title: "Claude's auto-compaction window (tokens)",
    description: "Claude's autoCompactWindow: 0 leaves it unset, else 100,000 to 1,000,000. Stored in Claude's settings file; applies from the next session.",
  },
  autoCompactEnabled: {
    type: 'boolean', default: true, group: 'Context', target: 'claude',
    label: 'Auto-compact', title: "Claude's auto-compaction",
    description: "Claude's autoCompactEnabled. Stored in Claude's settings file; applies from the next session.",
  },
```

- [ ] **Step 4: Teach forge-config the Claude target**

In `plugins/dr-forge/scripts/lib/forge-config.mjs`:

Replace the header comment (the first three lines) with:

```js
// dr-forge's settings: their schema (config/schema.mjs), the values in
// ~/.dr-forge/config.json, and the environment variable a key names, which wins
// over both. A key whose target is `claude` lives in Claude's own user settings
// file instead, and this module is its only writer. The first command on a
// machine imports the pre-2.0 settings once.
```

Replace the `case "number":` arm of `isValid` (both of its lines) with:

```js
    case "number":
      if (typeof value !== "number" || !Number.isInteger(value)) return false;
      // A floor leaves 0 as the one value below it: "unset".
      if (spec.floor !== undefined) return value === 0 || (value >= spec.floor && (spec.max === undefined || value <= spec.max));
      return (spec.min === undefined || value >= spec.min) && (spec.max === undefined || value <= spec.max);
```

Replace the whole `writeFile` function with:

```js
// Replaces a file in one rename, keeping the mode it had: Claude's settings
// file may be private, and a temporary file would otherwise take the umask's.
function writeFile(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  let mode;
  try {
    mode = fs.statSync(file).mode & 0o777;
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const temp = `${file}.${process.pid}.tmp`;
  try {
    // Created with the mode it will keep, so the contents are never readable
    // more widely than the file they replace; chmod then undoes the umask.
    fs.rmSync(temp, { force: true });
    fs.writeFileSync(temp, `${JSON.stringify(data, null, 2)}\n`, mode === undefined ? undefined : { mode });
    if (mode !== undefined) fs.chmodSync(temp, mode);
    fs.renameSync(temp, file);
  } catch (error) {
    fs.rmSync(temp, { force: true });
    throw error;
  }
}

function claudeDir(env) {
  return env.CLAUDE_CONFIG_DIR || path.join(homeOf(env), ".claude");
}

export function claudeSettingsPath(env = process.env) {
  return path.join(claudeDir(env), "settings.json");
}

// Claude's user settings as far as they can be read: a file that cannot be
// parsed is warned about and read as empty, so the forge keys still resolve.
function claudeValues(env, warn) {
  try {
    return readFile(claudeSettingsPath(env)) ?? {};
  } catch (error) {
    warn(error.message);
    return {};
  }
}

// The file a write lands on: where a symlink points, even when that
// destination does not exist yet, so a rename never replaces the link itself.
function realTarget(file) {
  try {
    return fs.realpathSync(file);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  try {
    return path.resolve(path.dirname(file), fs.readlinkSync(file));
  } catch {
    return file;
  }
}

// Changes one key of Claude's user settings and nothing else; `undefined`
// removes it. The write goes to the file a symlink points at, so a settings
// file kept in a dotfiles repository stays a link. A file that is not a JSON
// object throws before anything is written.
function writeClaude(env, key, value) {
  const file = realTarget(claudeSettingsPath(env));
  const data = readFile(file) ?? {};
  if (value === undefined) delete data[key];
  else data[key] = value;
  writeFile(file, data);
}
```

Replace the whole `resolve` function with:

```js
export function resolve(env = process.env, warn = message => process.stderr.write(`forge-config: ${message}\n`)) {
  const file = configPath(env);
  const data = readFile(file) ?? {};
  let claude;
  const values = {};
  for (const [key, spec] of Object.entries(SCHEMA)) {
    if (spec.target === "claude") {
      claude ??= claudeValues(env, warn);
      if (Object.hasOwn(claude, key)) {
        if (isValid(spec, claude[key])) { values[key] = claude[key]; continue; }
        warn(`${key} in ${claudeSettingsPath(env)} is not valid; ignored`);
      }
      values[key] = spec.default;
      continue;
    }
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
```

Replace the whole `setValue` and `unsetValue` functions with:

```js
export function setValue(key, text, env = process.env) {
  const spec = need(key);
  const value = fromText(spec, text);
  if (value === undefined) throw new SettingError(`${text} is not a valid ${key}`);
  if (spec.target === "claude") {
    // 0 on a floored key means "unset"; any other value is written as given,
    // a default included, because Claude's own default is not ours to assume.
    writeClaude(env, key, spec.floor !== undefined && value === 0 ? undefined : value);
    return value;
  }
  const file = configPath(env);
  const data = readFile(file) ?? {};
  if (value === spec.default) delete data[key];
  else data[key] = value;
  writeFile(file, data);
  return value;
}

export function unsetValue(key, env = process.env) {
  const spec = need(key);
  if (spec.target === "claude") { writeClaude(env, key, undefined); return; }
  const file = configPath(env);
  const data = readFile(file) ?? {};
  delete data[key];
  writeFile(file, data);
}
```

In `importLegacy`, replace the two lines

```js
  const claudeDir = env.CLAUDE_CONFIG_DIR || path.join(homeOf(env), ".claude");
  const options = readJson(path.join(claudeDir, "settings.json"))?.pluginConfigs?.["dr-cockpit@darkraise"]?.options;
```

with:

```js
  const options = readJson(claudeSettingsPath(env))?.pluginConfigs?.["dr-cockpit@darkraise"]?.options;
```

and in the loop below them replace `if (key in options && isValid(spec, options[key]) && options[key] !== spec.default) data[key] = options[key];` with:

```js
      if (spec.target === "forge" && key in options && isValid(spec, options[key]) && options[key] !== spec.default) data[key] = options[key];
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 120 bash plugins/dr-forge/tests/forge-config.test.sh | tail -3`
Expected: a line ending `0 failed`

Run: `timeout 60 node scripts/validate-repository.mjs`
Expected: the "are valid." line.

Run: `timeout 420 claude plugin test plugins/dr-forge 2>&1 | tail -4`
Expected: `127 pass` and `0 fail`

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-forge/config/schema.mjs plugins/dr-forge/scripts/lib/forge-config.mjs plugins/dr-forge/tests/forge-config.test.sh plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): write Claude's auto-compact keys"
```

---

### Task 4: Codex switches in the session gate

**Files:**
- Modify: `plugins/dr-forge/scripts/codex-gate`
- Test: `plugins/dr-forge/tests/codex-gate.test.sh`

**Interfaces:**
- Consumes: Contracts "`forge_setting KEY DEFAULT`"; keys `codexLane`, `codexReview`.
- Produces: Contracts "`codex-gate` line".

**Items:** 2

**Depends on:** Task 1, Task 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-forge/tests/codex-gate.test.sh`, add after the line `trap 'rm -rf "$TMP"' EXIT`:

```bash
# The gate reads ~/.dr-forge/config.json; a temporary home keeps the real one out.
export HOME="$TMP/home"
mkdir -p "$HOME"
```

Add before the comment line `# The quota answer is cached only until its reset time.`:

```bash
# --- the settings switch either surface off ----------------------------------
# codexReview and codexLane come from ~/.dr-forge/config.json. With both off
# nothing may use Codex, so the gate answers without starting a client.
mkdir -p "$HOME/.dr-forge"
setting() { printf '%s\n' "$1" > "$HOME/.dr-forge/config.json"; }
jq '.trust = {"calibration":"pass","smoke":"pass"}' "$TMP/policy.bak" > "$POLICY"
setting '{"codexLane":false}'
fresh; gate usable
check "codexLane off closes the lane only" "$out" \
  "codex-gate usable=true reason=ok review=true lane=false resets_at=- source=probe"
check "the session file carries the closed lane" "$(field review)/$(field lane)" "true/false"
setting '{"codexReview":false}'
gate usable
check "codexReview off closes the review seats only, from the cache too" "$out" \
  "codex-gate usable=true reason=ok review=false lane=true resets_at=- source=cache"
setting '{"codexLane":false,"codexReview":false}'
fresh; gate usable
check "both off answers without a probe" "$out" \
  "codex-gate usable=false reason=setting review=false lane=false resets_at=- source=setting"
check "both off starts no client" "$(cat "$TMP/log" 2>/dev/null | grep -c connect)" "0"
check "both off is written for the readers" "$(field usable)/$(field reason)" "false/setting"
setting '{}'
gate usable
check "switching Codex back on probes again" "$out" \
  "codex-gate usable=true reason=ok review=true lane=true resets_at=- source=probe"
cp "$TMP/policy.bak" "$POLICY"
rm -f "$HOME/.dr-forge/config.json"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dr-forge/tests/codex-gate.test.sh | grep -c '^FAIL'`
Expected: `7` (all seven new checks fail: the gate ignores the settings).

- [ ] **Step 3: Read the switches in the gate**

In `plugins/dr-forge/scripts/codex-gate`:

Replace the header line `# Output: codex-gate usable=<bool> reason=<r> review=<bool> lane=<bool> resets_at=<iso|-> source=<probe|cache>` with:

```bash
# Output: codex-gate usable=<bool> reason=<r> review=<bool> lane=<bool> resets_at=<iso|-> source=<probe|cache|setting>
#
# The codexReview and codexLane settings (scripts/forge-config) switch a surface
# off whatever the probe says; with both off the gate answers `reason=setting`
# without probing.
```

Add after the line `. "$HERE/lib/native-path.sh"`:

```bash
. "$HERE/lib/forge-env.sh"
```

Replace the three lines

```bash
usable="" reason="" resets="" epoch="" version="" source=probe
file=$(executor_session_file codex) || file=""
if [ "$refresh" -eq 0 ] && [ -n "$file" ] && [ -r "$file" ]; then
```

with:

```bash
want_review=$(forge_setting codexReview true)
want_lane=$(forge_setting codexLane true)

usable="" reason="" resets="" epoch="" version="" source=probe
file=$(executor_session_file codex) || file=""
if [ "$want_review" = false ] && [ "$want_lane" = false ]; then
  usable=false reason=setting source=setting
fi
if [ "$source" = probe ] && [ "$refresh" -eq 0 ] && [ -n "$file" ] && [ -r "$file" ]; then
```

Replace the two lines

```bash
  if [ "$c_usable" = true ] \
     || { [ "$c_usable" = false ] && { [ -z "$c_epoch" ] || [ "$c_epoch" -gt "$(date -u +%s)" ]; }; }; then
```

with:

```bash
  # An answer the settings forced says nothing about Codex itself, so it is
  # never reused once a switch is back on.
  if [ "$c_reason" != setting ] && { [ "$c_usable" = true ] \
     || { [ "$c_usable" = false ] && { [ -z "$c_epoch" ] || [ "$c_epoch" -gt "$(date -u +%s)" ]; }; }; }; then
```

Add after the `fi` that closes the block beginning `if [ "$usable" = true ] && [ -n "$file" ]; then` (the trust block):

```bash
[ "$want_review" = true ] || review=false
[ "$want_lane" = true ] || lane=false
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 bash plugins/dr-forge/tests/codex-gate.test.sh | tail -2`
Expected: a line ending `0 failed`

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/codex-gate plugins/dr-forge/tests/codex-gate.test.sh
git commit -m "feat(dr-forge): let settings switch Codex off"
```

---

### Task 5: Settings line at session start

**Files:**
- Modify: `plugins/dr-forge/scripts/session-start.sh`
- Test: `plugins/dr-forge/tests/hook.test.sh`

**Interfaces:**
- Consumes: Contracts "`scripts/forge-config workflow`".
- Produces: the line in every session's injected context, which Task 12's skills read.

**Items:** 2

**Depends on:** Task 1, Task 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-forge/tests/hook.test.sh`, add before the comment line `# --- hooks.json wiring ---`:

```bash
# --- workflow settings ride in every session as one line ---
if command -v node >/dev/null 2>&1; then
  HOME_S="$TMP/s"; mkdir -p "$HOME_S/.dr-forge"
  s_ctx=$(payload | HOME="$HOME_S" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
  check "settings: nothing injected at the defaults" "$(grep -c '^dr-forge settings in force' <<<"$s_ctx")" "0"
  printf '{"worktree":"always","designApproval":"whole","codexLane":false}\n' > "$HOME_S/.dr-forge/config.json"
  s_out=$(payload | HOME="$HOME_S" bash "$SCRIPT" 2>/dev/null)
  check "settings: output stays valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$s_out" && echo yes || echo no)" "yes"
  check "settings: the changed skill keys are injected" \
    "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$s_out" | grep -c '^dr-forge settings in force (each replaces the matching question or default in the skills): worktree=always; designApproval=whole$')" "1"
  s_ctx=$(compact_payload | HOME="$HOME_S" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
  check "settings: the line survives compaction" "$(grep -c '^dr-forge settings in force' <<<"$s_ctx")" "1"
  check "settings: still under the 10,000-character hook cap" "$([ "${#s_ctx}" -lt 10000 ] && echo yes || echo no)" "yes"
  printf 'not json' > "$HOME_S/.dr-forge/config.json"
  s_out=$(payload | HOME="$HOME_S" bash "$SCRIPT" 2>/dev/null); status=$?
  check "settings: a broken file still exits 0" "$status" "0"
  check "settings: a broken file injects no line" \
    "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$s_out" | grep -c '^dr-forge settings in force')" "0"
  check "settings: a broken file keeps the entry point" \
    "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$s_out" | grep -c 'dr-forge:using-superpowers')" "1"
fi
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dr-forge/tests/hook.test.sh | grep '^FAIL'`
Expected: two FAIL lines, "settings: the changed skill keys are injected" and "settings: the line survives compaction".

- [ ] **Step 3: Inject the line**

In `plugins/dr-forge/scripts/session-start.sh`, add before the comment that begins `# The compact source is detected without jq`:

```bash
# The workflow settings that differ from their defaults, as one line the skills
# read where they would otherwise ask (scripts/forge-config workflow). Without
# Node, or with a settings file that cannot be read, nothing is added.
settings_line=$(bash "${SCRIPT_DIR}/forge-config" workflow 2>/dev/null \
  | head -n 1 | tr -d '\001-\010\013\014\016-\037\r' || true)
if [ -n "$settings_line" ]; then
  context="${context}\n\n$(escape_for_json "$settings_line")"
fi
```

Replace the line `  cap=$(( 9500 - ${#content} - 400 - ${#roadmap_line} ))` with:

```bash
  cap=$(( 9500 - ${#content} - 400 - ${#roadmap_line} - ${#settings_line} ))
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 bash plugins/dr-forge/tests/hook.test.sh | tail -2`
Expected: a line ending `0 failed`

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/session-start.sh plugins/dr-forge/tests/hook.test.sh
git commit -m "feat(dr-forge): inject workflow settings at start"
```

---

### Task 6: Handoff mode and the budget setting in the budget scripts

**Files:**
- Modify: `plugins/dr-forge/scripts/lib/context.sh` (`ctx_plan_budget`, `ctx_line`)
- Modify: `plugins/dr-forge/reference/session-budget.md`
- Test: `plugins/dr-forge/tests/context-size.test.sh`, `plugins/dr-forge/tests/budget-line.test.sh`, `plugins/dr-forge/tests/inline-mode.test.sh`

**Interfaces:**
- Consumes: Contracts "`forge_setting KEY DEFAULT`"; keys `handoffMode`, `handoffTokens`.
- Produces: Contracts "Budget lines".

**Items:** 2

**Depends on:** Task 1, Task 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-forge/tests/context-size.test.sh`, add before the comment line `# --- two sessions in one checkout: each measures its own transcript ---`:

```bash
# --- the handoffMode and handoffTokens settings ---
# Relaxed measures a plain task and a wave against the final-phase limit (553k
# is 85% of the 650k window); the final, tail and plan checks do not move.
cp "$T" "$TMP/t.keep"; cp "$SESS/$KEY.json" "$TMP/record.keep"
settings 650000
mkdir -p "$HOME/.dr-forge"
printf '{"handoffMode":"relaxed"}\n' > "$HOME/.dr-forge/config.json"
asst 500000 > "$T"; record s-1 "$T"
run
check "relaxed: exit 0 under the final-phase limit" "$status" "0"
check "relaxed: line" "$out" "budget (relaxed): 500k of 553k (90%) — ok — source: record"
run --wave 2
check "relaxed wave: exit 5" "$status" "5"
check "relaxed wave: one task margin reserved" "$out" "budget (relaxed, wave of 2): 500k of 413k (121%) — handoff — source: record"
run --final
check "relaxed: the final check is unchanged" "$out" "budget (final): 500k of 553k (90%) — ok — source: record"
run --tail 1
check "relaxed: the tail check is unchanged" "$out" "budget (last task): 500k of 553k (90%) — ok — source: record"
run --plan
check "relaxed: the plan check is unchanged" "$out" "budget (plan): 500k of 553k (90%) — ok — source: record"
asst 560000 > "$T"
run
check "relaxed: past the final-phase limit: exit 5" "$status" "5"
check "relaxed: past the final-phase limit: line" "$out" "budget (relaxed): 560k of 553k (101%) — handoff — source: record"
# The handoffTokens setting pins the task budget; DR_FORGE_BUDGET still wins.
printf '{"handoffTokens":300000}\n' > "$HOME/.dr-forge/config.json"
asst 285000 > "$T"
run
check "handoffTokens pins the task budget" "$out" "budget: 285k of 300k (95%) — ok — source: record"
export DR_FORGE_BUDGET=600000
run
check "DR_FORGE_BUDGET wins over the setting" "$out" "budget: 285k of 600k (47%) — ok — source: record"
unset DR_FORGE_BUDGET
printf 'not json' > "$HOME/.dr-forge/config.json"
run
check "a broken settings file falls back to the rule" "$out" "budget: 285k of 465k (61%) — ok — source: record"
rm -f "$HOME/.dr-forge/config.json"
cp "$TMP/t.keep" "$T"; cp "$TMP/record.keep" "$SESS/$KEY.json"
```

In `plugins/dr-forge/tests/budget-line.test.sh`, add before the comment line `# --- a missing task still fails the way it did ---`:

```bash
# --- relaxed handoff: a task brief measures against the final-phase limit ---
mkdir -p "$HOME/.dr-forge"
printf '{"handoffMode":"relaxed"}\n' > "$HOME/.dr-forge/config.json"
out=$(bash "$P/scripts/task-brief" docs/plan.md 1 2>/dev/null)
check "task-brief: relaxed measures against the final-phase limit" "$(tail -n 1 <<<"$out")" \
  "budget (relaxed): 500k of 553k (90%) — ok — source: record"
# 680k at an 800k window: the figure the cockpit's finalLimitFor asserts too.
printf '{"autoCompactWindow": 800000}\n' > "$HOME/.claude/settings.json"
out=$(bash "$P/scripts/task-brief" docs/plan.md 1 2>/dev/null)
check "task-brief: relaxed at an 800k window" "$(tail -n 1 <<<"$out")" \
  "budget (relaxed): 500k of 680k (73%) — ok — source: record"
printf '{"autoCompactWindow": 650000}\n' > "$HOME/.claude/settings.json"
rm -f "$HOME/.dr-forge/config.json"
```

`plugins/dr-forge/tests/inline-mode.test.sh` runs `task-brief` against the real home directory, where a developer's own `handoffMode` or `handoffTokens` would now reach the budget code. Add after its line `export CODEX_HOME="$HERE/no-such-codex-home"`:

```bash
# The budget lines asserted here are the defaults'; the suite keeps the real
# home, so the settings in it are kept out by name.
export DR_FORGE_NO_SETTINGS=1
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash plugins/dr-forge/tests/context-size.test.sh | grep -c '^FAIL'`
Expected: `5` ("relaxed: exit 0 under the final-phase limit", the three relaxed lines and "handoffTokens pins the task budget"; the other seven already hold).

Run: `timeout 300 bash plugins/dr-forge/tests/budget-line.test.sh | grep -c '^FAIL'`
Expected: `2`

- [ ] **Step 3: Read the settings in the budget code**

In `plugins/dr-forge/scripts/lib/context.sh`:

Add before the comment `# ctx_plan_budget MODEL — the limit for writing the plan after the spec:`:

```bash
# ctx_pinned_budget — the task budget someone pinned: DR_FORGE_BUDGET, else the
# handoffTokens setting; empty when neither names a positive number. The
# environment is read here, not through the setting, so a machine without Node
# keeps its override.
ctx_pinned_budget() {
  local pinned
  case ${DR_FORGE_BUDGET:-} in
    ''|*[!0-9]*) pinned="" ;;
    *) pinned=$DR_FORGE_BUDGET; [ "$pinned" -gt 0 ] || pinned="" ;;
  esac
  if [ -z "$pinned" ]; then
    pinned=$(forge_setting handoffTokens 0)
    case $pinned in ''|*[!0-9]*|0) pinned="" ;; esac
  fi
  printf '%s' "$pinned"
}

```

In `ctx_plan_budget`, replace the five lines

```bash
  case ${DR_FORGE_BUDGET:-} in
    ''|*[!0-9]*) task="" ;;
    *) task=$DR_FORGE_BUDGET; [ "$task" -gt 0 ] || task="" ;;
  esac
  [ -n "$task" ] || task=$(ctx_budget "$1")
```

with:

```bash
  task=$(ctx_pinned_budget)
  [ -n "$task" ] || task=$(ctx_budget "$1")
```

Replace the comment above `ctx_line` (the eight lines beginning `# ctx_line [final | tail R | plan | wave W]`) with:

```bash
# ctx_line [final | tail R | plan | wave W] — print the budget line; return 0 ok, 5
# handoff, 3 unknown. With final, measure against the final-phase limit instead
# of the task budget; tail R does the same before one of a plan's last R tasks
# (CTX_TAIL_TASKS), so the tail of a plan and its final phase share one limit.
# With wave W, reserve one task's worst growth for each of the W - 1
# tasks that run beside the first, so a parallel wave that starts under its
# budget lands before compaction just as one task does
# (reference/parallel-waves.md). With the handoffMode setting at relaxed, a
# plain task and a wave measure against the final-phase limit too, and the
# label says so.
```

In `ctx_line`, add after the block

```bash
  if [ "${1:-}" = wave ]; then
    label="budget (wave of ${2:-1})"
    extra=$(( (${2:-1} - 1) * CTX_TASK_MARGIN ))
  fi
```

these lines:

```bash
  if [ "$limit" = task ] && [ "$(forge_setting handoffMode strict)" = relaxed ]; then
    limit=relaxed
    if [ "${1:-}" = wave ]; then label="budget (relaxed, wave of ${2:-1})"; else label="budget (relaxed)"; fi
  fi
```

Replace the block

```bash
  else
    case ${DR_FORGE_BUDGET:-} in
      ''|*[!0-9]*) ;;
      *) [ "$DR_FORGE_BUDGET" -gt 0 ] && budget=$DR_FORGE_BUDGET ;;
    esac
    [ -n "$budget" ] || budget=$(ctx_budget "$model")
    budget=$(( budget - extra ))
    [ "$budget" -gt 0 ] || budget=1
  fi
```

with:

```bash
  elif [ "$limit" = relaxed ]; then
    budget=$(( $(ctx_final_budget "$model") - extra ))
    [ "$budget" -gt 0 ] || budget=1
  else
    budget=$(ctx_pinned_budget)
    [ -n "$budget" ] || budget=$(ctx_budget "$model")
    budget=$(( budget - extra ))
    [ "$budget" -gt 0 ] || budget=1
  fi
```

- [ ] **Step 4: Document it**

In `plugins/dr-forge/reference/session-budget.md`, in the Numbers table, replace the cell text `` `DR_FORGE_BUDGET` overrides `` in the "Handoff budget" row with `` `DR_FORGE_BUDGET` overrides, then the `handoffTokens` setting ``, and add this row directly below the "Final-phase limit" row:

```markdown
| Relaxed handoff | With the `handoffMode` setting at `relaxed`, a plain task and a wave are measured against the final-phase limit (a wave less 140,000 per extra task) and the line reads `budget (relaxed)`; the pinned budget then has no effect. A worst-case fix loop late in such a session may compact, and the compaction snapshot carries it on | Owner ruling, 2026-10-12 |
```

Add to the budget-line examples (the first fenced block under "## The budget line") one line at the end:

```
budget (relaxed): 512k of 680k (75%) — ok — source: record
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 300 bash plugins/dr-forge/tests/context-size.test.sh | tail -2`
Expected: a line ending `0 failed`

Run: `timeout 300 bash plugins/dr-forge/tests/budget-line.test.sh | tail -2`
Expected: a line ending `0 failed`

Run: `timeout 300 bash plugins/dr-forge/tests/review-route.test.sh | tail -2`
Expected: a line ending `0 failed` (it asserts phrases of `session-budget.md`).

Run: `timeout 300 bash plugins/dr-forge/tests/inline-mode.test.sh | tail -2`
Expected: a line ending `0 failed`

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-forge/scripts/lib/context.sh plugins/dr-forge/reference/session-budget.md plugins/dr-forge/tests/context-size.test.sh plugins/dr-forge/tests/budget-line.test.sh plugins/dr-forge/tests/inline-mode.test.sh
git commit -m "feat(dr-forge): add relaxed handoff to the budget"
```

---

### Task 7: Finish settings in finish-choice

**Files:**
- Modify: `plugins/dr-forge/scripts/finish-choice`
- Test: `plugins/dr-forge/tests/finish-choice.test.sh`

**Interfaces:**
- Consumes: Contracts "`forge_setting KEY DEFAULT`"; keys `finishAction`, `finishTimeout`.
- Produces: Contracts "`finish-choice`".

**Items:** 2

**Depends on:** Task 1, Task 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-forge/tests/finish-choice.test.sh`, add after the line `trap 'rm -rf "$TMP"' EXIT`:

```bash
# finish-choice reads ~/.dr-forge/config.json; a temporary home keeps the real one out.
export HOME="$TMP/home"
mkdir -p "$HOME"
```

Add before the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"`:

```bash
# --- the finishAction and finishTimeout settings ---
mkdir -p "$HOME/.dr-forge" docs/plans
for name in s r a w; do printf '# Plan\n' > "docs/plans/$name.md"; done
fc get --plan docs/plans/s.md >/dev/null 2>&1
check "setting ask: nothing chosen still exits 3" "$?" "3"
printf '{"finishAction":"merge","finishTimeout":45}\n' > "$HOME/.dr-forge/config.json"
out=$(FINISH_CHOICE_NOW=$T0 fc get --plan docs/plans/s.md)
check "setting: get exits 0" "$?" "0"
check "setting: get records the configured action" \
  "$(jq -r '[.action, (.base | tostring), .source, (.chosenAt | tostring)] | join(" ")' .forge/sdd/s/finish.json)" "merge null setting $T0"
has "setting: get prints the choice" "$out" '"action": "merge"'
FINISH_CHOICE_NOW=$T0 fc arm --plan docs/plans/s.md >/dev/null
check "setting: arm waits finishTimeout minutes" "$(jq -r '.dueAt - .armedAt' .forge/sdd/s/finish.json)" "2700"
FINISH_CHOICE_NOW=$T0 fc arm --minutes 10 --plan docs/plans/s.md >/dev/null
check "setting: --minutes still overrides" "$(jq -r '.dueAt - .armedAt' .forge/sdd/s/finish.json)" "600"
fc set keep --plan docs/plans/r.md >/dev/null
check "a recorded choice wins over the setting" "$(fc get --plan docs/plans/r.md | jq -r '[.action, (.source // "asked")] | join(" ")')" "keep asked"
FINISH_CHOICE_NOW=$T0 fc arm --plan docs/plans/a.md >/dev/null
check "arm with nothing chosen records the setting first" "$(jq -r '[.action, .source] | join(" ")' .forge/sdd/a/finish.json)" "merge setting"
printf '{"finishAction":"wait"}\n' > "$HOME/.dr-forge/config.json"
check "setting wait: recorded" "$(fc get --plan docs/plans/w.md | jq -r .action)" "wait"
fc arm --plan docs/plans/w.md >/dev/null 2>&1
check "setting wait: nothing to arm" "$?" "3"
rm -f "$HOME/.dr-forge/config.json"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 bash plugins/dr-forge/tests/finish-choice.test.sh | grep -c '^FAIL'`
Expected: `7` ("setting ask: nothing chosen still exits 3", "a recorded choice wins over the setting" and "setting wait: nothing to arm" already hold; the other seven fail).

- [ ] **Step 3: Read the settings in finish-choice**

In `plugins/dr-forge/scripts/finish-choice`:

Replace the three header lines

```bash
#   set ACTION [--base BRANCH]  record the choice: merge | pr | keep | wait
#   get                         print the file; exit 3 when nothing is chosen
#   arm [--minutes N]           start the clock as the menu is shown (default
#                               30); print the cron line, the due time and the
```

with:

```bash
#   set ACTION [--base BRANCH]  record the choice: merge | pr | keep | wait
#   get                         print the file; exit 3 when nothing is chosen.
#                               With nothing chosen and the finishAction setting
#                               at anything but ask, record that action first.
#   arm [--minutes N]           start the clock as the menu is shown (default:
#                               the finishTimeout setting, 30 unless changed);
#                               print the cron line, the due time and the
```

Add after the line `. "$HERE/lib/forge-dir.sh"`:

```bash
. "$HERE/lib/forge-env.sh"
```

Add after the `need_file() { … }` line:

```bash
# With nothing chosen, the finishAction setting stands in for the answer
# (anything but ask). It is recorded like an answer, so the run keeps one
# choice even if the setting changes while it runs; the base branch is left
# for finishing to determine.
from_setting() {
  [ ! -s "$file" ] || return 0
  local action
  action=$(forge_setting finishAction ask)
  valid_action "$action" || return 0
  jq -n --arg action "$action" --argjson now "$now" \
    '{action: $action, base: null, chosenAt: $now, source: "setting"}' > "$file"
}
```

Replace the `get)` arm

```bash
  get)
    need_file
    cat "$file"
    ;;
```

with:

```bash
  get)
    from_setting
    need_file
    cat "$file"
    ;;
```

In the `arm)` arm, replace the two lines

```bash
    need_file
    minutes=30
```

with:

```bash
    from_setting
    need_file
    minutes=$(forge_setting finishTimeout 30)
    [[ $minutes =~ ^[1-9][0-9]*$ ]] || minutes=30
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 120 bash plugins/dr-forge/tests/finish-choice.test.sh | tail -2`
Expected: a line ending `0 failed`

Run: `timeout 120 bash plugins/dr-forge/tests/forge-state.test.sh | tail -2`
Expected: a line ending `0 failed` (it runs `finish-choice set`).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/finish-choice plugins/dr-forge/tests/finish-choice.test.sh
git commit -m "feat(dr-forge): add finish defaults from settings"
```

---

### Task 8: Settings row model

**Files:**
- Modify: `plugins/dr-forge/hooks/cockpit/config.ts`
- Test: `plugins/dr-forge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: Contracts "Schema entry".
- Produces: Contracts "`plugins/dr-forge/hooks/cockpit/config.ts` exports added by Task 8".

**Items:** 1

**Depends on:** Task 1, Task 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-forge/tests/cockpit.test.ts`, replace the two import lines for `../hooks/cockpit/config` with:

```ts
import type { Schema, SettingSpec } from '../hooks/cockpit/config'
import {
  SCHEMA,
  claudeLocks,
  envLocks,
  importedSettings,
  isValidSetting,
  rangeText,
  resolveSettings,
  rowOf,
  rowsOf,
  schemaRows,
  settingProblems,
  settingWritten,
  shownValue,
  steppedSetting,
  tabsOf,
  typedNumber,
} from '../hooks/cockpit/config'
```

In the `FAKE` schema of `describe('settings file', …)`, add a `label` to each of the four entries, directly after `group: '…',`: `label: 'Layout',` for `layout`, `label: 'Warn at',` for `warnAt`, `label: 'Handoff budget',` for `handoffTokens`, `label: 'Handoff note',` for `nudgeModel`.

Add at the end of the file:

```ts
describe('settings rows', () => {
  const ROWS: Schema = {
    layout: { type: 'enum', values: ['auto', 'full', 'compact'], default: 'auto', group: 'Cockpit', label: 'Layout', title: 'Layout', description: 'd', target: 'forge' },
    warnAt: { type: 'number', default: 80, min: 1, max: 99, step: 5, unit: '%', group: 'Context', label: 'Warn at', title: 'Warn', description: 'd', target: 'forge' },
    budget: { type: 'number', default: 0, min: 0, max: 2_000_000, step: 50_000, unit: 'k', zero: 'auto', env: 'DR_FORGE_BUDGET', group: 'Context', label: 'Handoff budget', title: 'Budget', description: 'd', target: 'forge' },
    note: { type: 'boolean', default: true, group: 'Context', label: 'Handoff note', title: 'Note', description: 'd', target: 'forge' },
    compactAt: { type: 'number', default: 0, min: 0, floor: 100_000, max: 1_000_000, step: 50_000, unit: 'k', zero: 'unset', group: 'Context', label: 'Auto-compact at', title: 'Compact', description: 'd', target: 'claude' },
    wait: { type: 'number', default: 30, min: 5, max: 240, step: 5, unit: 'min', group: 'Finish', label: 'Menu waits', title: 'Wait', description: 'd', target: 'forge' },
  }
  const spec = (key: string) => ROWS[key] as SettingSpec

  test('the tabs are the groups in schema order', () => {
    expect(tabsOf(ROWS)).toEqual(['Cockpit', 'Context', 'Finish'])
    expect(tabsOf(SCHEMA)).toEqual(['Cockpit', 'Context', 'Workflow', 'Process', 'Finish', 'Notifications'])
  })

  test('a value reads through its unit and zero word', () => {
    expect(shownValue(spec('warnAt'), 70)).toBe('70%')
    expect(shownValue(spec('budget'), 0)).toBe('auto')
    expect(shownValue(spec('budget'), 465_000)).toBe('465k')
    expect(shownValue(spec('wait'), 45)).toBe('45 min')
    expect(shownValue(spec('note'), false)).toBe('off')
    expect(shownValue(spec('layout'), 'full')).toBe('full')
  })

  test('a typed number is whole, in range, and may end in k', () => {
    expect(typedNumber(spec('warnAt'), ' 65 ')).toBe(65)
    expect(typedNumber(spec('warnAt'), '500')).toBeUndefined()
    expect(typedNumber(spec('warnAt'), '6.5')).toBeUndefined()
    expect(typedNumber(spec('warnAt'), 'many')).toBeUndefined()
    expect(typedNumber(spec('budget'), '465k')).toBe(465_000)
    expect(typedNumber(spec('budget'), '0.5K')).toBe(500)
    expect(typedNumber(spec('compactAt'), '0')).toBe(0)
    expect(typedNumber(spec('compactAt'), '50000')).toBeUndefined()
    expect(typedNumber(spec('compactAt'), '100k')).toBe(100_000)
    expect(rangeText(spec('warnAt'))).toBe('Enter a whole number from 1 to 99')
    expect(rangeText(spec('compactAt'))).toBe('Enter 0 or a whole number from 100,000 to 1,000,000')
  })

  test('a step moves to the next multiple, stays in range, and jumps a floor', () => {
    expect(steppedSetting(spec('warnAt'), 80, 1)).toBe(85)
    expect(steppedSetting(spec('warnAt'), 97, 1)).toBe(99)
    expect(steppedSetting(spec('warnAt'), 99, -1)).toBe(95)
    expect(steppedSetting(spec('warnAt'), 1, -1)).toBe(1)
    expect(steppedSetting(spec('warnAt'), 1, 1)).toBe(5)
    expect(steppedSetting(spec('compactAt'), 0, 1)).toBe(100_000)
    expect(steppedSetting(spec('compactAt'), 0, -1)).toBe(0)
    expect(steppedSetting(spec('compactAt'), 100_000, -1)).toBe(0)
    expect(steppedSetting(spec('compactAt'), 100_000, 1)).toBe(150_000)
    expect(steppedSetting(spec('compactAt'), 1_000_000, 1)).toBe(1_000_000)
  })

  test('a row carries what the view draws', () => {
    expect(rowOf('warnAt', spec('warnAt'), 70)).toEqual({
      key: 'warnAt',
      group: 'Context',
      label: 'Warn at',
      description: 'd',
      kind: 'stepper',
      value: 70,
      shown: '70%',
      shownDefault: '80%',
      values: [],
      isChanged: true,
      lockedBy: null,
    })
    expect(rowOf('layout', spec('layout'), 'auto')).toMatchObject({ kind: 'choices', values: ['auto', 'full', 'compact'], isChanged: false })
    expect(rowOf('budget', spec('budget'), 465_000, 'set by DR_FORGE_BUDGET')).toMatchObject({ shown: '465k', isChanged: false, lockedBy: 'set by DR_FORGE_BUDGET' })
    expect(rowsOf(ROWS, { warnAt: 70 }, 'Context', { budget: 'set by DR_FORGE_BUDGET' }).map(row => [row.key, row.isChanged, row.lockedBy])).toEqual([
      ['warnAt', true, null],
      ['budget', false, 'set by DR_FORGE_BUDGET'],
      ['note', false, null],
      ['compactAt', false, null],
    ])
  })

  test('says which keys something outside the file forces', () => {
    expect(envLocks(ROWS, { DR_FORGE_BUDGET: '400000' })).toEqual({ budget: 'set by DR_FORGE_BUDGET' })
    expect(envLocks(ROWS, { DR_FORGE_BUDGET: 'junk' })).toEqual({})
    expect(envLocks(ROWS, {})).toEqual({})
    expect(claudeLocks(ROWS, { compactAt: 500_000 }, { compactAt: 650_000 })).toEqual({ compactAt: 'set by a project or managed settings file' })
    expect(claudeLocks(ROWS, { compactAt: 650_000 }, { compactAt: 650_000 })).toEqual({})
    expect(claudeLocks(ROWS, {}, {})).toEqual({})
  })

  test('a Claude key resolves from the Claude settings and never enters the forge file', () => {
    expect(resolveSettings(ROWS, { compactAt: 300_000 }, {}, { compactAt: 650_000 }).compactAt).toBe(650_000)
    expect(resolveSettings(ROWS, { compactAt: 300_000 }, {}, { compactAt: 50_000 }).compactAt).toBe(0)
    expect(resolveSettings(ROWS, { compactAt: 300_000 }, {}).compactAt).toBe(0)
    expect(settingProblems(ROWS, { compactAt: 'x' }, {})).toEqual([])
    expect(() => settingWritten(ROWS, {}, 'compactAt', 650_000)).toThrow("compactAt is stored in Claude's settings file")
    expect(importedSettings(ROWS, { pluginConfigs: { 'dr-cockpit@darkraise': { options: { compactAt: 650_000, warnAt: 70 } } } }, null)).toEqual({ warnAt: 70 })
    expect(isValidSetting(spec('compactAt'), 0)).toBe(true)
    expect(isValidSetting(spec('compactAt'), 99_999)).toBe(false)
    expect(isValidSetting(spec('wait'), 5.5)).toBe(false)
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 420 claude plugin test plugins/dr-forge 2>&1 | tail -6`
Expected: the run fails to load the test file or reports failures: `tabsOf` and the other new names are not exported from `hooks/cockpit/config`.

- [ ] **Step 3: Write the row model**

In `plugins/dr-forge/hooks/cockpit/config.ts`:

Replace the `SettingSpec` type with:

```ts
/** One setting as config/schema.mjs declares it. */
export type SettingSpec = {
  type: 'boolean' | 'number' | 'enum' | 'string'
  default: SettingValue
  group: string
  /** The row's label in the settings view. */
  label: string
  title: string
  description: string
  target: 'forge' | 'claude'
  env?: string
  min?: number
  max?: number
  step?: number
  values?: readonly string[]
  /** How a number reads: thousands of tokens, a percentage, seconds or minutes. */
  unit?: 'k' | '%' | 's' | 'min'
  /** The word shown at 0. */
  zero?: string
  /** The smallest value allowed other than 0, on a number where 0 means unset. */
  floor?: number
  enforcedBy?: 'script' | 'skill'
}
```

Replace the `case 'number':` arm of `isValidSetting` (its seven lines, from `case 'number':` through the closing `)`) with:

```ts
    case 'number':
      // A number setting is whole, as scripts/lib/forge-config.mjs holds it too.
      if (typeof value !== 'number' || !Number.isInteger(value)) return false
      // A floor leaves 0 as the one value below it: "unset".
      if (spec.floor !== undefined) return value === 0 || (value >= spec.floor && (spec.max === undefined || value <= spec.max))
      return (spec.min === undefined || value >= spec.min) && (spec.max === undefined || value <= spec.max)
```

Replace the whole `resolveSettings` function, with its comment, with:

```ts
/**
 * Every setting in force. A forge key: the environment variable it names, then the file, then the default.
 * A Claude key: Claude's own settings as the engine merged them, then the default.
 */
export function resolveSettings(
  schema: Schema,
  file: SettingsFile,
  env: Readonly<Record<string, string | undefined>>,
  claude: Readonly<Record<string, unknown>> = {},
): Record<string, SettingValue> {
  const values: Record<string, SettingValue> = {}
  for (const [key, spec] of Object.entries(schema)) {
    if (spec.target === 'claude') {
      const held = claude[key]
      values[key] = isValidSetting(spec, held) ? held : spec.default
      continue
    }
    const raw = spec.env === undefined ? undefined : env[spec.env]
    const fromEnv = raw === undefined || raw === '' ? undefined : settingFromText(spec, raw)
    const stored = file[key]
    values[key] = fromEnv ?? (isValidSetting(spec, stored) ? stored : spec.default)
  }
  return values
}
```

In `settingProblems`, replace the line `if (Object.prototype.hasOwnProperty.call(file, key) && !isValidSetting(spec, file[key])) {` with:

```ts
    if (spec.target === 'forge' && Object.prototype.hasOwnProperty.call(file, key) && !isValidSetting(spec, file[key])) {
```

In `settingWritten`, add after the line `if (spec === undefined) throw new Error(`unknown setting ${key}`)`:

```ts
  if (spec.target === 'claude') throw new Error(`${key} is stored in Claude's settings file`)
```

In `importedSettings`, replace the line `if (isValidSetting(spec, value) && value !== spec.default) file[key] = value` with:

```ts
    if (spec.target === 'forge' && isValidSetting(spec, value) && value !== spec.default) file[key] = value
```

Add before the final `function objectAt(` helper:

```ts
/** One settings-view row, drawn from the schema and the value in force. */
export type ViewRow = {
  key: string
  group: string
  label: string
  description: string
  kind: 'toggle' | 'choices' | 'stepper' | 'text'
  value: SettingValue
  /** The value as its row reads, through the unit and the zero word. */
  shown: string
  /** The default the same way, for the line under a changed row. */
  shownDefault: string
  values: readonly string[]
  isChanged: boolean
  /** What forces the value from outside the file; such a row draws no controls. */
  lockedBy: string | null
}

/** The view's tabs: the schema's groups in the order they first appear. */
export function tabsOf(schema: Schema): string[] {
  return [...new Set(Object.values(schema).map(spec => spec.group))]
}

/** A value as its row reads: on or off, a number through its unit and zero word, anything else as text. */
export function shownValue(spec: SettingSpec, value: SettingValue): string {
  if (spec.type === 'boolean') return value === true ? 'on' : 'off'
  if (spec.type !== 'number' || typeof value !== 'number') return String(value)
  if (value === 0 && spec.zero !== undefined) return spec.zero
  if (spec.unit === 'k') return `${value / 1000}k`
  if (spec.unit === 'min') return `${value} min`
  return `${value}${spec.unit ?? ''}`
}

/** A number typed into a row: whole, with a trailing k for thousands; undefined when it does not fit the setting. */
export function typedNumber(spec: SettingSpec, text: string): number | undefined {
  const typed = text.trim().toLowerCase()
  const value = /^\d+(\.\d+)?k$/.test(typed) ? Number(typed.slice(0, -1)) * 1000 : /^\d+$/.test(typed) ? Number(typed) : Number.NaN
  return Number.isInteger(value) && isValidSetting(spec, value) ? value : undefined
}

// The mod's runtime is not promised a locale, so the digits are grouped by hand.
function grouped(n: number): string {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
}

/** What a typed number must be, for the row's refusal. */
export function rangeText(spec: SettingSpec): string {
  const to = grouped(spec.max ?? Number.MAX_SAFE_INTEGER)
  return spec.floor === undefined
    ? `Enter a whole number from ${grouped(spec.min ?? 0)} to ${to}`
    : `Enter 0 or a whole number from ${grouped(spec.floor)} to ${to}`
}

/** One press of − (-1) or + (1): the next multiple of the step, kept in range; a floor is entered from 0 and left to 0. */
export function steppedSetting(spec: SettingSpec, value: number, direction: 1 | -1): number {
  const step = spec.step ?? 1
  const next = direction > 0 ? Math.floor(value / step) * step + step : Math.ceil(value / step) * step - step
  if (spec.floor !== undefined) {
    if (direction > 0 && value < spec.floor) return spec.floor
    if (direction < 0 && next < spec.floor) return 0
  }
  return Math.min(spec.max ?? Number.MAX_SAFE_INTEGER, Math.max(spec.min ?? 0, next))
}

/** A setting's row. A locked row is never "changed": the file is not what holds its value. */
export function rowOf(key: string, spec: SettingSpec, value: SettingValue, lockedBy: string | null = null): ViewRow {
  return {
    key,
    group: spec.group,
    label: spec.label,
    description: spec.description,
    kind: spec.type === 'boolean' ? 'toggle' : spec.type === 'enum' ? 'choices' : spec.type === 'number' ? 'stepper' : 'text',
    value,
    shown: shownValue(spec, value),
    shownDefault: shownValue(spec, spec.default),
    values: spec.values ?? [],
    isChanged: lockedBy === null && value !== spec.default,
    lockedBy,
  }
}

/** A group's rows in schema order. */
export function rowsOf(
  schema: Schema,
  values: Readonly<Record<string, SettingValue>>,
  group: string,
  locks: Readonly<Record<string, string>> = {},
): ViewRow[] {
  return Object.entries(schema)
    .filter(([, spec]) => spec.group === group)
    .map(([key, spec]) => rowOf(key, spec, values[key] ?? spec.default, locks[key] ?? null))
}

/** The keys an environment variable forces, each with the words its row shows. */
export function envLocks(schema: Schema, env: Readonly<Record<string, string | undefined>>): Record<string, string> {
  const locks: Record<string, string> = {}
  for (const [key, spec] of Object.entries(schema)) {
    const raw = spec.env === undefined ? undefined : env[spec.env]
    if (spec.env !== undefined && raw !== undefined && raw !== '' && settingFromText(spec, raw) !== undefined) locks[key] = `set by ${spec.env}`
  }
  return locks
}

/** The Claude keys a project or managed settings file overrides: the merged value is not the user file's. */
export function claudeLocks(schema: Schema, merged: Readonly<Record<string, unknown>>, user: Readonly<Record<string, unknown>>): Record<string, string> {
  const locks: Record<string, string> = {}
  for (const [key, spec] of Object.entries(schema)) {
    if (spec.target === 'claude' && merged[key] !== undefined && merged[key] !== user[key]) locks[key] = 'set by a project or managed settings file'
  }
  return locks
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 420 claude plugin test plugins/dr-forge 2>&1 | tail -4`
Expected: `134 pass` and `0 fail` (127 plus the seven new tests).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/hooks/cockpit/config.ts plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): add the settings row model"
```

---

### Task 9: Tabbed settings view

**Files:**
- Create: `plugins/dr-forge/hooks/cockpit/settings-view.tsx`
- Modify: `plugins/dr-forge/hooks/cockpit/register.tsx` (imports at lines 3-17 and 70-71, constants at 127-129, the atoms near line 156, the settings block at lines 665-888)
- Modify: `plugins/dr-forge/hooks/cockpit/config.ts` (delete `SettingRow` and `schemaRows`)
- Modify: `plugins/dr-forge/types/index.d.ts`
- Test: `plugins/dr-forge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: Contracts "`plugins/dr-forge/hooks/cockpit/config.ts` exports added by Task 8".
- Produces: Contracts "`plugins/dr-forge/hooks/cockpit/settings-view.tsx`" and "Cockpit state" (`settingsView`).

**Items:** 1

**Depends on:** Task 8

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Rewrite the tests the new view changes, and add its own**

In `plugins/dr-forge/tests/cockpit.test.ts`:

1. In the config import list, delete the line `  schemaRows,`.

2. Delete the `CONTROL` map with its two-line comment, and the test `draws every setting under its schema group` that follows it. In their place write:

```ts
  test('every setting has a row in exactly one tab', async ($, on) => {
    world(on, { tokens: 284_000, config: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    const seen: string[] = []
    for (const tab of tabsOf(SCHEMA)) {
      await ui.press({ key: `settings-tab-${tab}` })
      for (const key of Object.keys(SCHEMA)) if ((await ui.find({ key: `set-${key}-label` })) !== undefined) seen.push(key)
    }
    expect(seen.sort()).toEqual(Object.keys(SCHEMA).sort())
  })
```

3. In the test `read as on, chosen or off in the settings`, add the line `    await ui.press({ key: 'settings-tab-Notifications' })` directly before the line that expects `set-notify-kind-task`.

4. In the test `` `writes each press to the settings file on ${surface}` ``, replace the four `ui.press` lines that follow `await ui.press({ key: 'pane-settings' })` with:

```ts
      await ui.press({ key: 'set-openAtStart-toggle' })
      await ui.press({ key: 'set-layout-compact' })
      await ui.press({ key: 'set-section-guard' })
      await ui.press({ key: 'settings-tab-Context' })
      await ui.press({ key: 'set-warnAt-more' })
```

5. In the test `takes the webhook in the settings view and shows it masked`, add the line `    await ui.press({ key: 'settings-tab-Notifications' })` directly after `await ui.press({ key: 'pane-settings' })`.

6. In `describe('settings file', …)`, delete the test `a row for each setting without a control of its own, in schema order`.

7. Add inside `describe('settings view', …)`, before its closing `})`:

```ts
  test('shows one group at a time and switches with the tabs', async ($, on) => {
    world(on, { tokens: 284_000, config: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    expect(await ui.find({ key: 'set-openAtStart-toggle' })).toBeDefined()
    expect(await ui.find({ key: 'set-warnAt-more' })).toBeUndefined()
    expect((await ui.find({ key: 'settings-tab-Cockpit' }))?.props).toMatchObject({ variant: 'primary', hotkey: '1' })
    expect(await ui.find({ type: 'Text', text: 'all defaults' })).toBeDefined()
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ key: 'set-warnAt-more' })).toBeDefined()
    expect(await ui.find({ key: 'set-openAtStart-toggle' })).toBeUndefined()
    expect((await ui.find({ key: 'settings-tab-Context' }))?.props).toMatchObject({ variant: 'primary', hotkey: '2' })
  })

  test('describes each setting until help is hidden', async ($, on) => {
    world(on, { tokens: 284_000, config: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    expect(await ui.find({ type: 'Text', text: /^Open the cockpit when a session starts\./ })).toBeDefined()
    await ui.press({ key: 'settings-help' })
    expect(await ui.find({ type: 'Text', text: /^Open the cockpit when a session starts\./ })).toBeUndefined()
    expect((await ui.find({ key: 'settings-help' }))?.props).toMatchObject({ label: 'Show help', hotkey: 'i' })
  })

  test('a changed row shows its default and resets', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: { warnAt: 70 }, written })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: '1 changed' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'default 80%' })).toBeDefined()
    await ui.press({ key: 'set-warnAt-reset' })
    expect(JSON.parse(written[CONFIG] ?? 'null')).toEqual({})
    expect(await ui.find({ key: 'set-warnAt-reset' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: 'all defaults' })).toBeDefined()
  })

  test('a typed number is saved, and one out of range is refused', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: {}, written })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    await ui.press({ key: 'set-warnAt-edit' })
    await ui.input({ key: 'set-warnAt-input', text: '500', kind: 'submit' })
    expect(await ui.find({ type: 'Text', text: /Enter a whole number from 1 to 99/ })).toBeDefined()
    expect(written[CONFIG]).toBeUndefined()
    await ui.input({ key: 'set-warnAt-input', text: '65', kind: 'submit' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ warnAt: 65 })
    expect(await ui.find({ key: 'set-warnAt-input' })).toBeUndefined()
  })

  test('a group resets only after a second press', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: { warnAt: 70, nudgeModel: false, layout: 'full' }, written })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    await ui.press({ key: 'settings-reset' })
    expect(written[CONFIG]).toBeUndefined()
    await ui.press({ key: 'settings-reset-cancel' })
    expect(await ui.find({ key: 'settings-reset-confirm' })).toBeUndefined()
    await ui.press({ key: 'settings-reset' })
    await ui.press({ key: 'settings-reset-confirm' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ layout: 'full' })
    expect(await ui.find({ key: 'settings-reset' })).toBeUndefined()
  })

  test('a changed chip list is marked, and any other press or a reopening ends a pending reset', async ($, on) => {
    world(on, { tokens: 284_000, config: { sections: 'plan,repo' }, written: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    expect(await ui.find({ key: 'set-sections-mark' })).toBeDefined()
    expect(await ui.find({ key: 'set-layout-mark' })).toBeUndefined()
    await ui.press({ key: 'settings-reset' })
    expect(await ui.find({ key: 'settings-reset-confirm' })).toBeDefined()
    await ui.press({ key: 'set-section-usage' })
    expect(await ui.find({ key: 'settings-reset-confirm' })).toBeUndefined()
    await ui.press({ key: 'settings-reset' })
    await $.command.run({ ...COCKPIT, args: 'settings' })
    expect(await ui.find({ key: 'settings-reset-confirm' })).toBeUndefined()
    expect(await ui.find({ key: 'settings-reset' })).toBeDefined()
  })
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 420 claude plugin test plugins/dr-forge 2>&1 | grep -c '^(fail)'`
Expected: a count of 9 or more: the six new tests, `every setting has a row in exactly one tab`, and the tests that now press a `settings-tab-…` key the current view does not draw.

- [ ] **Step 3: Write the view module**

Create `plugins/dr-forge/hooks/cockpit/settings-view.tsx`:

```tsx
import type { EngineInterface, RenderChildren } from 'claude-code'

import type { SettingValue, ViewRow } from './config'

// The engine refuses to pass `$` across an import, so this module draws from
// the surface's element table and reports every press through a callback.
type Elements = ReturnType<EngineInterface['ui']['resolve']>

const LABEL_WIDTH = 16
const INDENT = 2
const CARD = '#8080800f'
const ACCENT = 'permission'

/** What the settings view shows. */
export type SettingsModel = {
  tabs: readonly string[]
  tab: string
  /** Drawn dim beside the open group's name. */
  hint: string | null
  rows: readonly ViewRow[]
  isHelpShown: boolean
  /** The key whose value is being typed, and why the last entry was refused. */
  editing: string | null
  error: string | null
  isConfirmingReset: boolean
  /** Whether the surface has a text field. */
  canType: boolean
  /** Saved or environment values the settings in force ignored. */
  problems: readonly string[]
  /** Rows the caller draws itself, by key, in place of the schema's control. */
  custom: Readonly<Record<string, RenderChildren>>
  /** Drawn above the open group's rows. */
  top: RenderChildren
}

/** What each press does. */
export type SettingsActions = {
  openTab: (tab: string) => unknown
  set: (key: string, value: SettingValue) => unknown
  step: (key: string, direction: 1 | -1) => unknown
  edit: (key: string | null) => unknown
  submit: (key: string, text: string) => unknown
  reset: (key: string) => unknown
  toggleHelp: () => unknown
  askResetGroup: () => unknown
  resetGroup: () => unknown
  cancelReset: () => unknown
  back: () => unknown
}

/** The cockpit's settings: a tab for each group, the open group's rows, and the footer. */
export function drawSettings(table: Elements, model: SettingsModel, act: SettingsActions): RenderChildren {
  const { Box, Button, Text } = table
  const Input = 'Input' in table ? table.Input : undefined
  const press = (key: string, label: string, onPress: () => unknown, look: { hotkey?: string; isMain?: boolean; isOff?: boolean } = {}) => (
    <Button key={key} label={label} hotkey={look.hotkey} variant={look.isMain ? 'primary' : undefined} dimColor={look.isOff} onPress={onPress} />
  )

  const control = (row: ViewRow): RenderChildren => {
    if (row.lockedBy !== null) {
      return [
        <Text key={`set-${row.key}-value`} bold>{`${row.shown} `}</Text>,
        <Text key={`set-${row.key}-lock`} dimColor>
          {row.lockedBy}
        </Text>,
      ]
    }
    if (row.kind === 'toggle') {
      const isOn = row.value === true
      return press(`set-${row.key}-toggle`, isOn ? '● On' : '○ Off', () => act.set(row.key, !isOn), { isMain: isOn, isOff: !isOn })
    }
    if (row.kind === 'choices') {
      return row.values.map(choice =>
        press(`set-${row.key}-${choice}`, choice, () => act.set(row.key, choice), { isMain: row.value === choice, isOff: row.value !== choice }),
      )
    }
    if (model.editing === row.key && Input !== undefined) {
      return [
        <Input key={`set-${row.key}-input`} value={String(row.value)} submitLabel="save" autoFocus onSubmit={(text: string) => act.submit(row.key, text)} />,
        press(`set-${row.key}-cancel`, 'Cancel', () => act.edit(null)),
      ]
    }
    const edit = model.canType && press(`set-${row.key}-edit`, 'Edit', () => act.edit(row.key), { isOff: true })
    if (row.kind === 'stepper') {
      return [
        <Text key={`set-${row.key}-value`} bold>
          {row.shown.padEnd(7)}
        </Text>,
        press(`set-${row.key}-less`, '−', () => act.step(row.key, -1)),
        press(`set-${row.key}-more`, '+', () => act.step(row.key, 1)),
        edit,
      ]
    }
    return [
      <Text key={`set-${row.key}-value`} dimColor={row.shown === ''}>{`${row.shown || '(empty)'} `}</Text>,
      edit || (
        <Text key={`set-${row.key}-cli`} dimColor>
          {`forge-config set ${row.key}`}
        </Text>
      ),
    ]
  }

  // Under a row: its description while help is shown, and its default with a Reset once it differs.
  const below = (row: ViewRow): RenderChildren => [
    model.isHelpShown && (
      <Box key={`set-${row.key}-help`} paddingLeft={INDENT}>
        <Text dimColor wrap="wrap">
          {row.description}
        </Text>
      </Box>
    ),
    row.isChanged && (
      <Box key={`set-${row.key}-default`} flexDirection="row" columnGap={1} paddingLeft={INDENT}>
        <Text key={`set-${row.key}-default-text`} dimColor>{row.shownDefault === '' ? 'changed from the default' : `default ${row.shownDefault}`}</Text>
        {press(`set-${row.key}-reset`, 'Reset', () => act.reset(row.key))}
      </Box>
    ),
  ]

  const mark = (row: ViewRow): RenderChildren =>
    row.isChanged && (
      <Text key={`set-${row.key}-mark`} color="yellow" bold>
        *
      </Text>
    )

  // A row the caller draws itself still gets the mark, the help and the default line.
  const drawRow = (row: ViewRow): RenderChildren => (
    <Box key={`set-${row.key}-block`} flexDirection="column">
      {model.custom[row.key] !== undefined ? (
        <Box key={`set-${row.key}`} flexDirection="row" columnGap={1}>
          {model.custom[row.key]}
          {mark(row)}
        </Box>
      ) : (
        <Box key={`set-${row.key}`} flexDirection="row" flexWrap="wrap" alignItems="center" columnGap={1}>
          <Text key={`set-${row.key}-label`}>{row.label.padEnd(LABEL_WIDTH)}</Text>
          {control(row)}
          {mark(row)}
        </Box>
      )}
      {model.editing === row.key && model.error !== null && (
        <Text key={`set-${row.key}-error`} color="red">{`${' '.repeat(INDENT)}✗ ${model.error}`}</Text>
      )}
      {below(row)}
    </Box>
  )

  const changed = model.rows.filter(row => row.isChanged).length
  return (
    <Box flexDirection="column">
      <Text bold>Settings</Text>
      <Box key="settings-tabs" flexDirection="row" flexWrap="wrap" columnGap={1}>
        {model.tabs.map((tab, index) =>
          press(`settings-tab-${tab}`, tab, () => act.openTab(tab), { hotkey: index < 9 ? String(index + 1) : undefined, isMain: tab === model.tab, isOff: tab !== model.tab }),
        )}
      </Box>
      <Box key={`set-group-${model.tab}`} flexDirection="column" borderStyle="round" borderColor="subtle" backgroundColor={CARD} paddingX={1}>
        <Box key="set-group-head" flexDirection="row" columnGap={1}>
          <Text bold color={ACCENT}>
            {model.tab}
          </Text>
          {model.hint !== null && (
            <Text key="set-group-hint" dimColor>
              {model.hint}
            </Text>
          )}
          <Text key="set-group-changed" dimColor>
            {changed === 0 ? 'all defaults' : `${changed} changed`}
          </Text>
        </Box>
        {model.top}
        {model.rows.map(drawRow)}
      </Box>
      {model.problems.map((problem, index) => (
        <Text key={`set-problem-${index}`} color="yellow">
          ⚠ {problem}
        </Text>
      ))}
      <Box key="settings-actions" flexDirection="row" flexWrap="wrap" columnGap={1}>
        {press('settings-back', 'Back', act.back, { hotkey: 'b' })}
        {press('settings-help', model.isHelpShown ? 'Hide help' : 'Show help', act.toggleHelp, { hotkey: 'i' })}
        {model.isConfirmingReset
          ? [press('settings-reset-confirm', 'Confirm reset', act.resetGroup, { hotkey: 'r', isMain: true }), press('settings-reset-cancel', 'Cancel', act.cancelReset)]
          : changed > 0 && press('settings-reset', 'Reset group', act.askResetGroup, { hotkey: 'r' })}
      </Box>
      <Text dimColor>Saved to ~/.dr-forge/config.json.</Text>
    </Box>
  )
}
```

- [ ] **Step 4: Declare the view's state**

In `plugins/dr-forge/types/index.d.ts`, add before the line `declare module 'claude-code' {`:

```ts
/** The settings view's own state: the open tab, and what is being typed or confirmed. */
export type CockpitSettingsView = {
  /** The open group; empty opens the first. */
  tab: string
  isHelpShown: boolean
  /** The key whose value is being typed. */
  editing: string | null
  /** Why the typed value was refused. */
  error: string | null
  isConfirmingReset: boolean
}

```

and add after the line `      view: 'cockpit' | 'settings'`:

```ts
      settingsView: CockpitSettingsView
```

- [ ] **Step 5: Wire the view into the pane**

In `plugins/dr-forge/hooks/cockpit/register.tsx`:

1. In the `import type { … } from '../../types'` list, add `  CockpitSettingsView,` after `  CockpitSeat,`.

2. Replace the two lines

```ts
import { SCHEMA, importedSettings, resolveSettings, schemaRows, settingProblems, settingWritten } from './config'
import type { SettingRow, SettingValue, SettingsFile } from './config'
```

with:

```ts
import { SCHEMA, importedSettings, rangeText, resolveSettings, rowsOf, settingProblems, settingWritten, steppedSetting, tabsOf, typedNumber } from './config'
import type { SettingValue, SettingsFile } from './config'
import { drawSettings } from './settings-view'
```

3. In the import list from `'./lib'`, delete the line `  stepped,`.

4. Delete these three lines:

```ts
// The handoff budget's step and ceiling in the settings view.
const HANDOFF_STEP = 50_000
const MAX_HANDOFF = 2_000_000
```

5. Add after the line `const settings = atom({ plugin: 'dr-forge', key: 'settings' } as const, null)`:

```ts
const SETTINGS_VIEW: CockpitSettingsView = { tab: '', isHelpShown: true, editing: null, error: null, isConfirmingReset: false }
const settingsView = atom({ plugin: 'dr-forge', key: 'settingsView' } as const, SETTINGS_VIEW)
```

6. Inside the block `if ((await read($, view)) === 'settings') { … }` of the `Pane` render hook:

   - In the `row` helper, replace `<Text>{label.padEnd(15)}</Text>` with `<Text>{label.padEnd(16)}</Text>`, and in `webhookRows` replace `{' '.repeat(16)}` with `{' '.repeat(17)}`, so the webhook rows line up with the schema rows.
   - Delete the three helpers `toggle`, `choices` and `number` (each a `const … =` statement; `number` ends at the `)` after `compact(`set-${key}-more`, '+', onMore),`).
   - Keep `set`, `row`, `chips`, the `elements`/`Input`/`canType` lines, `notes`, `field`, `edit` and `webhookRows` as they are.
   - Replace the `compact` helper (its two lines) with the version below. The webhook rows and the chip lists are drawn with it, so their presses end a pending reset or an open edit just as the view's own controls do; `state` and `show` are declared further down the same block and are read only when a button is pressed.

```tsx
      const compact = (key: string, label: string, onPress: () => unknown, look: { hotkey?: string; isMain?: boolean; isOff?: boolean } = {}) =>
        button(
          key,
          label,
          async () => {
            if (state.editing !== null || state.isConfirmingReset) await show({})
            return onPress()
          },
          { ...look, isCompact: true },
        )
```

   - Replace everything from the line `const custom: Record<string, RenderChildren> = {` through the block's closing `}` (the line before `const running = all.filter(one => !one.isDone)`) with:

```tsx
      const state = await read($, settingsView)
      const values = (await read($, settings)) ?? {}
      const tabs = tabsOf(SCHEMA)
      const tab = tabs.includes(state.tab) ? state.tab : (tabs[0] ?? '')
      const rows = rowsOf(SCHEMA, values, tab)
      // Every press but the one that asked for it ends an edit or a pending reset.
      const show = (change: Partial<CockpitSettingsView>) =>
        update($, settingsView, now => ({ ...now, editing: null, error: null, isConfirmingReset: false, ...change }))
      const save = async (key: string, value: SettingValue) => {
        if (state.editing !== null || state.isConfirmingReset) await show({})
        return set(key, value)
      }
      const custom: Record<string, RenderChildren> = {
        sections: (
          <Box key="set-sections-chips" flexDirection="column">
            <Text key="set-sections-label">Sections</Text>
            {/* Under their label, wrapping to the pane's width. */}
            {chips(
              'set-section',
              SECTIONS,
              name => o.shown.includes(name as Section),
              name => name,
              name => save('sections', sectionsToggled(o.shown, name as Section)),
            )}
          </Box>
        ),
        notifyOn: (
          <Box key="set-notifyOn-chips" flexDirection="column">
            <Text key="set-notifyOn-label">Send on</Text>
            {chips(
              'set-notify-kind',
              NOTIFY_KINDS,
              kind => S.kinds.includes(kind as NotifyKind),
              kind => kindLabel(kind as NotifyKind),
              kind => save('notifyOn', notifyKindsToggled(S.kinds, kind as NotifyKind)),
            )}
          </Box>
        ),
      }

      return drawSettings(
        elements,
        {
          tabs,
          tab,
          hint: tab === 'Notifications' ? '(Discord)' : null,
          rows,
          isHelpShown: state.isHelpShown,
          editing: state.editing,
          error: state.error,
          isConfirmingReset: state.isConfirmingReset,
          canType,
          problems: S.settingProblems,
          custom,
          top: tab === 'Notifications' ? webhookRows : null,
        },
        {
          openTab: next => show({ tab: next }),
          set: save,
          step: (key, direction) => {
            const spec = SCHEMA[key]
            return spec === undefined ? undefined : save(key, steppedSetting(spec, Number(values[key] ?? spec.default), direction))
          },
          edit: key => show({ editing: key }),
          submit: async (key, text) => {
            const spec = SCHEMA[key]
            if (spec === undefined) return
            const value = spec.type === 'number' ? typedNumber(spec, text) : text
            if (value === undefined) {
              await update($, settingsView, now => ({ ...now, error: rangeText(spec) }))
              return
            }
            if (await set(key, value)) await show({})
          },
          reset: key => {
            const spec = SCHEMA[key]
            return spec === undefined ? undefined : save(key, spec.default)
          },
          toggleHelp: () => show({ isHelpShown: !state.isHelpShown }),
          askResetGroup: () => show({ isConfirmingReset: true }),
          resetGroup: async () => {
            for (const one of rows) {
              const spec = SCHEMA[one.key]
              if (one.isChanged && spec !== undefined) await set(one.key, spec.default)
            }
            await show({})
          },
          cancelReset: () => show({}),
          back: async () => {
            await show({})
            await update($, view, () => 'cockpit')
            // Minimized, the settings were all the pane was open for.
            if (o.isMinimized) await $.ui.close({ id: PANE })
          },
        },
      )
    }
```

7. The settings always open with no edit or reset pending. Add before the comment `/** ~/.dr-forge/config.json, or null when no home directory is set. */`:

```ts
/** Opens the settings afresh: no half-typed value or pending reset survives a close. */
async function showSettings($: EngineInterface) {
  await update($, settingsView, now => ({ ...now, editing: null, error: null, isConfirmingReset: false }))
  await update($, view, () => 'settings')
}

```

   In the pane's actions, replace `button('pane-settings', 'Settings', () => update($, view, () => 'settings'), { hotkey: 's' })` with `button('pane-settings', 'Settings', () => showSettings($), { hotkey: 's' })`. In the `command.run` hook, replace the line `    await update($, view, () => (wantsSettings ? 'settings' : 'cockpit'))` with:

```ts
    if (wantsSettings) await showSettings($)
    else await update($, view, () => 'cockpit')
```

8. In `plugins/dr-forge/hooks/cockpit/config.ts`, delete the `SettingRow` type with its comment and the whole `schemaRows` function with its comment.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `timeout 120 claude plugin validate plugins/dr-forge 2>&1 | tail -2`
Expected: `✔ Validation passed`

Run: `timeout 420 claude plugin test plugins/dr-forge 2>&1 | tail -4`
Expected: `139 pass` and `0 fail` (134, less the two deleted tests, plus the seven new ones).

Run: `grep -n "schemaRows\|SettingRow\|HANDOFF_STEP\|MAX_HANDOFF" plugins/dr-forge/hooks/cockpit/*.ts plugins/dr-forge/hooks/cockpit/*.tsx plugins/dr-forge/tests/cockpit.test.ts`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-forge/hooks/cockpit/settings-view.tsx plugins/dr-forge/hooks/cockpit/register.tsx plugins/dr-forge/hooks/cockpit/config.ts plugins/dr-forge/types/index.d.ts plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): rebuild the settings view as tabs"
```

---

### Task 10: Relaxed handoff limit in the cockpit

**Files:**
- Modify: `plugins/dr-forge/hooks/cockpit/lib.ts` (after `budgetFor`)
- Modify: `plugins/dr-forge/hooks/cockpit/register.tsx` (`Options`, `Tuning`, `liveFrom`, `refresh`)
- Test: `plugins/dr-forge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: key `handoffMode`.
- Produces: Contracts "`finalLimitFor(window, compactWindow?)`".

**Items:** 2

**Depends on:** Task 1, Task 9

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-forge/tests/cockpit.test.ts`, add `  finalLimitFor,` to the import list from `'../hooks/cockpit/lib'`, after `  elapsed,`. Add inside `describe('settings', …)`, after the test `warnAt moves where the strip shows the handoff`:

```ts
  test('relaxed handoff measures the context against the final-phase limit', async ($, on) => {
    // The same worked figure tests/budget-line.test.sh asserts for the scripts.
    expect(finalLimitFor(1_000_000, 800_000)).toBe(680_000)
    expect(finalLimitFor(650_000)).toBe(552_500)
    expect(finalLimitFor(650_000, 0)).toBe(552_500)
    // 276,250 is half of 85% of the 650k window; strict would read 59%.
    world(on, { tokens: 276_250, config: { handoffMode: 'relaxed' } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^50%$/ })).toBeDefined()
  })
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 420 claude plugin test plugins/dr-forge 2>&1 | tail -6`
Expected: the test file fails to load or the new test fails: `finalLimitFor` is not exported from `hooks/cockpit/lib`.

- [ ] **Step 3: Add the limit and use it**

In `plugins/dr-forge/hooks/cockpit/lib.ts`, add after the `budgetFor` function:

```ts
/**
 * The final-phase limit (reference/session-budget.md): 85% of min(autoCompactWindow, window).
 * Relaxed handoff measures every task against it.
 */
export function finalLimitFor(window: number, compactWindow?: number): number {
  const room = compactWindow !== undefined && compactWindow > 0 ? Math.min(window, compactWindow) : window
  return Math.floor(room * 0.85)
}
```

In `plugins/dr-forge/hooks/cockpit/register.tsx`:

1. In the import list from `'./lib'`, add `  finalLimitFor,` after `  elapsed,`.

2. In the `Options` type, add after `  handoffTokens: number`:

```ts
  handoffMode: string
```

3. Replace the `Tuning` type line with:

```ts
type Tuning = { handoffTokens: number; nudgeModel: boolean; warnAt: number; isRelaxed: boolean }
```

4. In `liveFrom`, add `    handoffMode = 'strict',` after `    handoffTokens = 0,` in the destructuring, add `    handoffMode,` after `    handoffTokens,` in the returned object, and replace the line `    tuning: { handoffTokens, nudgeModel, warnAt: warnShare(warnAt) },` with:

```ts
    tuning: { handoffTokens, nudgeModel, warnAt: warnShare(warnAt), isRelaxed: handoffMode === 'relaxed' },
```

5. In `refresh`, replace the line `  const limit = budgetFor(handoffTokens, undefined, window, compactWindow)` with:

```ts
  const limit = tuning.isRelaxed ? finalLimitFor(window, compactWindow) : budgetFor(handoffTokens, undefined, window, compactWindow)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 420 claude plugin test plugins/dr-forge 2>&1 | tail -4`
Expected: `140 pass` and `0 fail`

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/hooks/cockpit/lib.ts plugins/dr-forge/hooks/cockpit/register.tsx plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): show the relaxed limit in the pane"
```

---

### Task 11: Claude keys, locked rows and the settings note

**Files:**
- Modify: `plugins/dr-forge/hooks/cockpit/register.tsx` (`S`, `applySettings`, `setOption`, the settings block, the `ui.close` hook, where `isPlanSession` is set)
- Test: `plugins/dr-forge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: Contracts "Claude target in `forge-config`"; `envLocks`, `claudeLocks` and the four-argument `resolveSettings` from Task 8; the `back` action from Task 9.
- Produces: Contracts "Cockpit state" (`S.locks`, `S.changed`).

**Items:** 1, 2

**Depends on:** Task 3, Task 8, Task 9, Task 10

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-forge/tests/cockpit.test.ts`:

1. In the `World` type, add after the `settings?: Record<string, unknown>` line:

```ts
  /** What the user's own Claude settings file holds, when it differs from the merged `settings`. */
  userSettings?: Record<string, unknown>
  /** Each forge-config command the plugin runs, as one line. */
  runs?: string[]
  /** forge-config refuses, as on a Claude settings file it cannot parse. */
  isForgeConfigRefusing?: boolean
  /** The session refuses every row the plugin appends. */
  isAppendFailing?: boolean
```

2. In `world`, replace the line `  on('settings.read', () => ({ value: w.settings ?? {} }))` with:

```ts
  on('settings.read', (_$, e) => ({ value: e?.source === 'user' && w.userSettings !== undefined ? w.userSettings : (w.settings ?? {}) }))
```

3. In `world`, in the `process.run` hook, add as its first statements (before `const stdout = …`, after `const argv = e.argv.join(' ')`):

```ts
    if (argv.includes('/scripts/lib/forge-config.mjs ')) {
      w.runs?.push(argv)
      const stderr = w.isForgeConfigRefusing ? 'forge-config: /home/me/.claude/settings.json is not valid JSON; fix or remove it\n' : ''
      return { value: { exitCode: w.isForgeConfigRefusing ? 1 : 0, stdout: '', stderr, isStdoutTruncated: false, isStderrTruncated: false } }
    }
```

4. In `world`, in the `session.append` hook, add as its first statement:

```ts
    if (w.isAppendFailing) throw new Error('append refused')
```

5. Add at the end of the file:

```ts
describe('settings held outside the file', () => {
  const NOTE = 'dr-forge settings changed'

  test('a value the environment forces shows locked, and a group reset leaves it alone', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: { warnAt: 70, handoffTokens: 300_000 }, written, env: { DR_FORGE_BUDGET: '465000' } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: 'set by DR_FORGE_BUDGET' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^465k/ })).toBeDefined()
    expect(await ui.find({ key: 'set-handoffTokens-more' })).toBeUndefined()
    expect(await ui.find({ key: 'set-warnAt-more' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: '1 changed' })).toBeDefined()
    await ui.press({ key: 'settings-reset' })
    await ui.press({ key: 'settings-reset-confirm' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ handoffTokens: 300_000 })
  })

  test('the pre-2.0 variable is named when it is the one set', async ($, on) => {
    world(on, { tokens: 284_000, config: {}, env: { DR_SUPERPOWERS_BUDGET: '465000' } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: 'set by DR_SUPERPOWERS_BUDGET' })).toBeDefined()
  })

  test('a Claude key is saved through forge-config, never into the forge file', async ($, on) => {
    const written: Record<string, string> = {}
    const runs: string[] = []
    world(on, { tokens: 284_000, config: {}, written, runs, settings: { autoCompactWindow: 650_000 } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: /^650k/ })).toBeDefined()
    await ui.press({ key: 'set-autoCompactWindow-more' })
    expect(runs).toHaveLength(1)
    expect(runs[0]).toMatch(/^node .*\/scripts\/lib\/forge-config\.mjs set autoCompactWindow 700000$/)
    // The row shows what was saved, and the next step starts from it.
    expect(await ui.find({ type: 'Text', text: /^700k/ })).toBeDefined()
    await ui.press({ key: 'set-autoCompactWindow-more' })
    expect(runs[1]).toMatch(/ set autoCompactWindow 750000$/)
    await ui.press({ key: 'set-autoCompactWindow-reset' })
    expect(runs[2]).toMatch(/ set autoCompactWindow 0$/)
    expect(await ui.find({ type: 'Text', text: /^unset/ })).toBeDefined()
    await ui.press({ key: 'set-autoCompactEnabled-toggle' })
    expect(runs[3]).toMatch(/ set autoCompactEnabled false$/)
    expect(written[CONFIG]).toBeUndefined()
  })

  test('says why a Claude key was not saved', async ($, on) => {
    const toasts: string[] = []
    world(on, { tokens: 284_000, config: {}, toasts, isForgeConfigRefusing: true })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    await ui.press({ key: 'set-autoCompactWindow-more' })
    expect(toasts).toContain('dr-forge: autoCompactWindow not saved: /home/me/.claude/settings.json is not valid JSON; fix or remove it')
  })

  test('a Claude key a project or managed file overrides shows locked', async ($, on) => {
    world(on, { tokens: 284_000, config: {}, settings: { autoCompactWindow: 500_000 }, userSettings: { autoCompactWindow: 650_000 } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: 'set by a project or managed settings file' })).toBeDefined()
    expect(await ui.find({ key: 'set-autoCompactWindow-more' })).toBeUndefined()
  })

  test('a changed skill setting is told to the model once, when the settings close', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 50_000, config: {}, notes, written: {} })
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Workflow' })
    await ui.press({ key: 'set-worktree-always' })
    await ui.press({ key: 'set-worktree-never' })
    await ui.press({ key: 'set-codexLane-toggle' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dr-forge settings changed: worktree=never. Each replaces the matching question or default in the skills.',
    ])
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toHaveLength(1)
  })

  test('a note the session refuses is sent at the next close', async ($, on) => {
    const notes: string[] = []
    const w: World = { tokens: 50_000, config: {}, notes, written: {}, isAppendFailing: true }
    world(on, w)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Workflow' })
    await ui.press({ key: 'set-worktree-always' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    w.isAppendFailing = false
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dr-forge settings changed: worktree=always. Each replaces the matching question or default in the skills.',
    ])
  })

  test('outside a dr-forge session the note waits for one', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 50_000, config: {}, notes, written: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Process' })
    await ui.press({ key: 'set-designApproval-whole' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:brainstorming' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dr-forge settings changed: designApproval=whole. Each replaces the matching question or default in the skills.',
    ])
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 420 claude plugin test plugins/dr-forge 2>&1 | grep -c '^(fail)'`
Expected: `8` (the eight new tests).

- [ ] **Step 3: Resolve, lock and route**

In `plugins/dr-forge/hooks/cockpit/register.tsx`:

1. In the import from `'./config'`, add `claudeLocks` and `envLocks`:

```ts
import { SCHEMA, claudeLocks, envLocks, importedSettings, rangeText, resolveSettings, rowsOf, settingProblems, settingWritten, steppedSetting, tabsOf, typedNumber } from './config'
```

2. In the `S` object, add after the `settingProblems: [] as string[],` line:

```ts
  // Keys something outside the settings file forces, with the words their rows show.
  locks: {} as Record<string, string>,
  // Skill-enforced settings changed since the model was last told, with their new values.
  changed: {} as Record<string, SettingValue>,
  // Claude keys this session saved: the engine's settings snapshot may not show another process's write at once.
  claudeSaved: {} as Record<string, SettingValue>,
```

   In `loadSettings`, add as its first statement `  S.claudeSaved = {}`, so a new session starts from what Claude's settings hold.

3. Replace the whole `applySettings` function, with its comment, with:

```ts
/** Puts a settings file in force: the atom every hook reads through live(), the locked rows, and the notifier. */
async function applySettings($: EngineInterface, file: SettingsFile) {
  const forge = await $.env.get('DR_FORGE_BUDGET')
  const legacy = await $.env.get('DR_SUPERPOWERS_BUDGET')
  const env = { DR_FORGE_BUDGET: forge || legacy }
  const merged = { ...(((await $.settings.read().catch(() => ({}))) ?? {}) as Record<string, unknown>), ...S.claudeSaved }
  const user = { ...(((await $.settings.read({ source: 'user' }).catch(() => ({}))) ?? {}) as Record<string, unknown>), ...S.claudeSaved }
  const values = resolveSettings(SCHEMA, file, env, merged)
  S.settingProblems = settingProblems(SCHEMA, file, env)
  const locks = { ...envLocks(SCHEMA, env), ...claudeLocks(SCHEMA, merged, user) }
  if (!forge && legacy && locks.handoffTokens !== undefined) locks.handoffTokens = 'set by DR_SUPERPOWERS_BUDGET'
  S.locks = locks
  await update($, settings, () => values)
  applyNotify(liveFrom(values as Partial<Options>))
}
```

4. Replace the whole `setOption` function, with its comment, with:

```ts
/** Saves one setting and puts it in force, saying why if it could not; resolves whether it was saved. */
async function setOption($: EngineInterface, key: string, value: SettingValue): Promise<boolean> {
  const spec = SCHEMA[key]
  const path = await configFile($)
  const file = path === null ? null : await readSettingsFile($, path)
  try {
    if (spec?.target === 'claude') {
      // Claude's settings file holds far more than these keys, so only forge-config, which rewrites it in one rename, writes it.
      const ran = await $.process.run(['node', `${$.plugin.root}/scripts/lib/forge-config.mjs`, 'set', key, String(value)])
      if (ran.exitCode !== 0) throw new Error(ran.stderr.trim().replace(/^forge-config: /, '') || `forge-config exited ${ran.exitCode}`)
      S.claudeSaved[key] = value
      await applySettings($, file ?? {})
      return true
    }
    if (path === null) throw new Error('no home directory is set')
    if (file === null) throw new Error(`${path} is not a JSON object; fix or remove it`)
    const next = settingWritten(SCHEMA, file, key, value)
    await $.fs.write(path, `${JSON.stringify(next, null, 2)}\n`)
    await applySettings($, next)
    if (spec?.enforcedBy === 'skill') S.changed[key] = value
    return true
  } catch (error) {
    $.ui.toast(`dr-forge: ${key} not saved: ${error instanceof Error ? error.message : String(error)}`)
    return false
  }
}

/** Tells the model, once, which skill-enforced settings changed; outside a dr-forge session the change waits for one. */
async function flushSettingNote($: EngineInterface) {
  const sent = { ...S.changed }
  const keys = Object.keys(sent)
  if (keys.length === 0 || !(await read($, isPlanSession))) return
  const note = `dr-forge settings changed: ${keys.map(key => `${key}=${String(sent[key])}`).join('; ')}. Each replaces the matching question or default in the skills.`
  try {
    await $.session.append({ message: { type: 'user', content: [{ type: 'text', text: note }] } })
  } catch {
    // The host would not take the row: the changes stay pending for the next close.
    return
  }
  // A key changed again while the row was being appended stays pending.
  for (const key of keys) if (S.changed[key] === sent[key]) delete S.changed[key]
}
```

5. In the settings block of the `Pane` render hook, replace the line `      const rows = rowsOf(SCHEMA, values, tab)` with:

```ts
      const rows = rowsOf(SCHEMA, values, tab, S.locks)
```

and in the `back` action add `await flushSettingNote($)` as its second statement:

```ts
          back: async () => {
            await show({})
            await flushSettingNote($)
            await update($, view, () => 'cockpit')
            // Minimized, the settings were all the pane was open for.
            if (o.isMinimized) await $.ui.close({ id: PANE })
          },
```

6. In the hook `on('ui.close', { id: PANE }, …)`, add `    await flushSettingNote($)` as the line before `return next(e)`.

7. The session becomes a dr-forge session in two places. In the `tool.call` hook, add directly after the line `      await update($, isPlanSession, () => true)`:

```ts
      await flushSettingNote($)
```

   In the `agent.spawn` hook, replace the line `    if (isSuperpowers(e.subagentType)) await update($, isPlanSession, () => true)` with:

```ts
    if (isSuperpowers(e.subagentType)) {
      await update($, isPlanSession, () => true)
      await flushSettingNote($)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 120 claude plugin validate plugins/dr-forge 2>&1 | tail -2`
Expected: `✔ Validation passed`

Run: `timeout 420 claude plugin test plugins/dr-forge 2>&1 | tail -4`
Expected: `148 pass` and `0 fail`

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/hooks/cockpit/register.tsx plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): lock forced rows and note changes"
```

---

### Task 12: Skills obey the workflow settings

**Files:**
- Modify: `plugins/dr-forge/skills/brainstorming/SKILL.md`, `plugins/dr-forge/skills/writing-plans/SKILL.md`, `plugins/dr-forge/skills/using-git-worktrees/SKILL.md`, `plugins/dr-forge/skills/executing-plans/SKILL.md`, `plugins/dr-forge/skills/subagent-driven-development/SKILL.md`, `plugins/dr-forge/skills/finishing-a-development-branch/SKILL.md`
- Modify: `plugins/dr-forge/reference/finish-preference.md`
- Create: `plugins/dr-forge/tests/settings-skills.test.sh`

**Interfaces:**
- Consumes: Contracts "`scripts/forge-config workflow`", "`finish-choice`" and the skill-enforced keys of Task 1.
- Produces: nothing another task consumes.

**Items:** 2, 3

**Depends on:** Task 1, Task 2, Task 5, Task 7

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-forge/tests/settings-skills.test.sh`:

```bash
#!/usr/bin/env bash
# A skill-enforced setting is only as good as the skill text that names it:
# each key must be named where its decision is made, and no skill may still
# state the finish menu's wait as a fixed number.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
command -v node > /dev/null 2>&1 || { echo "settings-skills tests: node is required but not on PATH" >&2; exit 2; }

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" "yes"
}

B="$P/skills/brainstorming/SKILL.md"
W="$P/skills/writing-plans/SKILL.md"
G="$P/skills/using-git-worktrees/SKILL.md"
F="$P/reference/finish-preference.md"

# Each check is a whole instruction, not a keyword: where the settings come
# from, what outranks them, and what each value changes at its decision point.
names "brainstorming has a Settings section" "$B" '## Settings'
names "brainstorming loads the settings when no line is in context" "$B" '`scripts/forge-config workflow` once before your first question'
names "brainstorming: instructions outrank a setting, and the gate stays" "$B" 'setting, and no setting removes the approval gate.'
names "brainstorming: processBias" "$B" 'plainly holds; doubt resolves to bounded.'
names "brainstorming: questionStyle" "$B" '`questionStyle=batched`: ask all the clarifying questions in one message'
names "brainstorming: designApproval" "$B" '`designApproval=whole`: present every design section in one message and ask'
names "brainstorming: executionStrategy" "$B" 'the execution-strategy question; record the value as the answer.'
names "brainstorming: an inline plan is sequential" "$B" 'and when `executionMode=inline`, which makes the plan sequential.'
names "brainstorming: specReview" "$B" '`specReview=false`: after the spec self-review block, skip the User Review'
names "brainstorming: the path rule points at processBias" "$B" '(`processBias` moves where doubt lands; see Settings). The'
names "brainstorming: the question rule points at questionStyle" "$B" '(`questionStyle=batched` asks them all in one message; see Settings)'
names "brainstorming: the strategy question is skipped by the setting" "$B" 'When `executionStrategy` is `sequential` or `parallel` (see Settings), skip the'
names "brainstorming: the section rule points at designApproval" "$B" 'with `designApproval=whole`, present every section in one message and ask once (see Settings)'
names "brainstorming: the review gate is skipped by the setting" "$B" 'With `specReview=false` (see Settings), skip this gate and go to Implementation.'
names "writing-plans loads the settings when no line is in context" "$W" 'run `scripts/forge-config workflow` before you choose the Execution line'
names "writing-plans: instructions outrank a setting" "$W" 'own instructions outrank a setting.'
names "writing-plans: executionMode fixes the line" "$W" 'line when it is `inline` or `subagent`, in place of the majority rule.'
names "writing-plans: an inline plan is sequential" "$W" '`**Parallelism:** sequential — executionMode is inline`'
names "writing-plans: executionStrategy answers the question" "$W" 'that value and do not ask. On a Codex host do not ask:'
names "using-git-worktrees loads the settings when no line is in context" "$G" 'run `scripts/forge-config workflow` when no such line is in context'
names "using-git-worktrees: what each value does" "$G" '`worktree=always` creates the worktree without asking, `worktree=never` works in place and skips to Step 2'
names "using-git-worktrees: the setting decides only when no preference was stated" "$G" 'If not, the `worktree` setting decides'
names "finish-preference: finishAction" "$F" 'finishAction'
names "finish-preference: finishTimeout" "$F" 'finishTimeout'
names "finish-preference: a setting's choice has no base branch" "$F" '`base` is null'

# Every skill-enforced key in the schema is named by at least one skill.
keys=$(node -e 'const { pathToFileURL } = require("url"); import(pathToFileURL(process.argv[1]).href).then(m => console.log(Object.entries(m.default).filter(([, spec]) => spec.enforcedBy === "skill").map(([key]) => key).join(" ")))' "$P/config/schema.mjs")
check "the schema has skill-enforced keys" "$([ -n "$keys" ] && echo yes || echo no)" "yes"
for key in $keys; do
  check "a skill names $key" "$(grep -lF -- "$key" "$P"/skills/*/SKILL.md | head -n 1 | grep -c .)" "1"
done

# The finish menu's wait is a setting now: 30 minutes may appear only as its default.
for file in "$P/skills/executing-plans/SKILL.md" "$P/skills/subagent-driven-development/SKILL.md" "$G" \
  "$P/skills/finishing-a-development-branch/SKILL.md" "$F"; do
  check "${file#"$P"/} states no fixed finish wait" "$(grep '30 minutes' "$file" | grep -vc 'by default')" "0"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 bash plugins/dr-forge/tests/settings-skills.test.sh | tail -3`
Expected: a line ending with a non-zero `failed` count: the `names` checks for the new instructions and the five fixed-wait checks fail, because none of that text exists yet. Each `names` string is a whole instruction, so deleting any one of them from its skill later turns its check red.

- [ ] **Step 3: Edit brainstorming**

In `plugins/dr-forge/skills/brainstorming/SKILL.md`:

1. Add this section directly before the line `## Anti-Pattern: "Too Simple To Need Approval"`:

```markdown
## Settings

The workflow settings in force arrive as one line at session start, `dr-forge
settings in force (…): key=value; …`. With no such line in context, run
`scripts/forge-config workflow` once before your first question; it prints the
same line, or nothing when every setting is at its default. A key the line does
not name is at its default. Your human partner's own instructions outrank a
setting, and no setting removes the approval gate.

- `processBias=lighter`: take the architectural path only when a trigger
  plainly holds; doubt resolves to bounded. `processBias=heavier`: doubt
  resolves to architectural. A request for a spec and the irreducible-risk
  trigger hold under either.
- `questionStyle=batched`: ask all the clarifying questions in one message
  instead of one per message.
- `designApproval=whole`: present every design section in one message and ask
  for approval once, instead of after each section.
- `executionStrategy=sequential` or `executionStrategy=parallel`: do not ask
  the execution-strategy question; record the value as the answer. `parallel`
  still becomes sequential when you cannot name two parts that share no file,
  on a Codex host,
  and when `executionMode=inline`, which makes the plan sequential.
- `specReview=false`: after the spec self-review block, skip the User Review
  Gate and go on to Implementation.

```

2. Replace `Doubt means check the trigger list, not jump to the heavier path. The` with:

```markdown
Doubt means check the trigger list, not jump to the heavier path
(`processBias` moves where doubt lands; see Settings). The
```

3. Replace the line `- Only one question per message - if a topic needs more exploration, break it into multiple questions` with:

```markdown
- Only one question per message - if a topic needs more exploration, break it into multiple questions (`questionStyle=batched` asks them all in one message; see Settings)
```

4. Replace the two lines

```markdown
Once the approach is settled and before you present the design, ask your human
partner one multiple-choice question, on its own:
```

with:

```markdown
When `executionStrategy` is `sequential` or `parallel` (see Settings), skip the
question and record that value. Otherwise, once the approach is settled and
before you present the design, ask your human partner one multiple-choice
question, on its own:
```

5. Replace the line `- Ask after each section whether it looks right so far` with:

```markdown
- Ask after each section whether it looks right so far; with `designApproval=whole`, present every section in one message and ask once (see Settings)
```

6. Replace the line `After posting the self-review block, ask the user to review the written spec before proceeding:` with:

```markdown
With `specReview=false` (see Settings), skip this gate and go to Implementation. Otherwise, after posting the self-review block, ask the user to review the written spec before proceeding:
```

- [ ] **Step 4: Edit writing-plans and using-git-worktrees**

In `plugins/dr-forge/skills/writing-plans/SKILL.md`:

1. Add directly before the line `**Choosing the Execution line.** The plan decides its execution mode:`:

```markdown
**Read the settings first.** Two workflow settings shape a plan,
`executionMode` and `executionStrategy`. They arrive in the session-start line
`dr-forge settings in force (…)`. With no such line in context,
run `scripts/forge-config workflow` before you choose the Execution line
or ask the strategy question; it prints nothing when both are at their
defaults. A key the line does not name is at its default, and your human partner's
own instructions outrank a setting.

```

2. Add after the bullet that ends `  their reasons.` (the "Your human partner may override the line" bullet under "Choosing the Execution line"):

```markdown
- The `executionMode` setting fixes the
  line when it is `inline` or `subagent`, in place of the majority rule.
  `inline` also makes the plan sequential, whatever the spec's
  `**Execution strategy:**` line or the `executionStrategy` setting says,
  because an inline session implements every task itself: write
  `**Parallelism:** sequential — executionMode is inline`
  and group no waves. An inline plan still delegates its heavy tasks and every
  task carrying an `**Executor:**` line.
```

3. Replace `before you draft any task, and wait for the answer. On a Codex host do not ask:` with:

```markdown
before you draft any task, and wait for the answer; when the `executionStrategy`
setting is `sequential` or `parallel` (dr-forge:brainstorming §Settings), take
that value and do not ask. On a Codex host do not ask:
```

In `plugins/dr-forge/skills/using-git-worktrees/SKILL.md`:

1. Replace the line `Has the user already indicated their worktree preference in your instructions? If not, ask for consent before creating a worktree:` with:

```markdown
Has the user already indicated their worktree preference in your instructions? If not, the `worktree` setting decides (read it from the session-start line `dr-forge settings in force (…)`, or run `scripts/forge-config workflow` when no such line is in context): `worktree=always` creates the worktree without asking, `worktree=never` works in place and skips to Step 2, and `ask`, the default and the value when the line does not name the key, asks for consent before creating a worktree:
```

2. Replace `for 30 minutes. See [finish-preference.md](../../reference/finish-preference.md).` with:

```markdown
for the configured wait (the `finishTimeout` setting, 30 minutes by default). See
[finish-preference.md](../../reference/finish-preference.md).
```

- [ ] **Step 5: Edit the finish wording**

In both `plugins/dr-forge/skills/executing-plans/SKILL.md` and `plugins/dr-forge/skills/subagent-driven-development/SKILL.md`, replace the two lines

```markdown
ask what finishing should do if its menu goes unanswered for 30 minutes,
record the answer, and start work in the same turn. Skip it when
```

with:

```markdown
ask what finishing should do if its menu goes unanswered for the configured
wait, record the answer, and start work in the same turn. Skip it when
```

and in both replace `already prints a choice, or when` with:

```markdown
already prints a choice (it does so unasked when the `finishAction` setting
names an action), or when
```

In `plugins/dr-forge/skills/finishing-a-development-branch/SKILL.md`, replace `and only after 30 minutes unanswered.` with `and only after the configured wait goes unanswered.`

In `plugins/dr-forge/reference/finish-preference.md`:

1. Replace the line `unanswered for 30 minutes. An answer to the menu inside those 30 minutes always` with:

```markdown
unanswered for the configured wait. An answer to the menu inside that wait always
```

2. Add directly before the line `## When to ask`:

```markdown
## The settings

Two settings (`scripts/forge-config`, or the cockpit's Finish tab) shape this:

- `finishAction`: `ask`, the default, keeps the question below. With `merge`,
  `pr`, `keep` or `wait`, `scripts/finish-choice get` records and prints that
  action whenever nothing is chosen yet, so the question is never asked: the
  "skip the question when `get` prints a choice" rule already covers it. A
  choice recorded this way has no base branch (`base` is null): determine it
  when the wake fires, as finishing Step 3 does.
- `finishTimeout`: how many minutes the menu waits, 30 minutes by default.
  `scripts/finish-choice arm` uses it; wherever this file says `<N> minutes`,
  N is `bash <plugin-root>/scripts/forge-config get finishTimeout`.

```

3. Replace the line `your answer. If it gets none within 30 minutes, what should I do?` with:

```markdown
your answer. If it gets none within <N> minutes, what should I do?
```

4. Replace `Any answer to the menu inside the 30 minutes, whichever option it names, is` with `Any answer to the menu inside the wait, whichever option it names, is`.

5. Replace ``message with `No answer within 30 minutes, so I went with <option>, as chosen`` with ``message with `No answer within <N> minutes, so I went with <option>, as chosen``.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `timeout 120 bash plugins/dr-forge/tests/settings-skills.test.sh | tail -2`
Expected: a line ending `0 failed`

Run: `for t in review-route inline-mode working-directory turn-end; do timeout 600 bash plugins/dr-forge/tests/$t.test.sh | tail -1; done`
Expected: four lines, each ending `0 failed` (these assert phrases of the skills edited here).

Run: `timeout 60 node scripts/validate-repository.mjs`
Expected: the "are valid." line.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-forge/skills/brainstorming/SKILL.md plugins/dr-forge/skills/writing-plans/SKILL.md plugins/dr-forge/skills/using-git-worktrees/SKILL.md plugins/dr-forge/skills/executing-plans/SKILL.md plugins/dr-forge/skills/subagent-driven-development/SKILL.md plugins/dr-forge/skills/finishing-a-development-branch/SKILL.md plugins/dr-forge/reference/finish-preference.md plugins/dr-forge/tests/settings-skills.test.sh
git commit -m "feat(dr-forge): make the skills obey settings"
```

---

### Task 13: Release 2.1.0

**Files:**
- Modify: `plugins/dr-forge/README.md` (the Settings section near line 643, and the finish wording near lines 360, 366 and 536)
- Modify: `plugins/dr-forge/.claude-plugin/plugin.json`, `plugins/dr-forge/.codex-plugin/plugin.json` (`version`)
- Modify (through `scripts/register` only): `docs/superpowers/registers/2026-10-11-dr-forge.md`

**Interfaces:**
- Consumes: everything above; changes no behaviour.
- Produces: nothing.

**Items:** 1, 2, 3

**Depends on:** Task 1, Task 2, Task 3, Task 4, Task 5, Task 6, Task 7, Task 8, Task 9, Task 10, Task 11, Task 12

**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 1 - spec 1 - coupling 0 - risk 0 = 2

- [ ] **Step 1: Bump the version**

In `plugins/dr-forge/.claude-plugin/plugin.json` and `plugins/dr-forge/.codex-plugin/plugin.json`, replace `"version": "2.0.0"` with `"version": "2.1.0"`.

Run: `timeout 60 node scripts/validate-repository.mjs`
Expected: the "are valid." line (the two manifests must agree).

- [ ] **Step 2: Rewrite the README's Settings section**

In `plugins/dr-forge/README.md`, replace everything from the line `### Settings` up to, and not including, the line `### Install` with:

````markdown
### Settings

Open the settings with **Settings** in the pane or `/cockpit settings`. They are
one tab per group: press `1` to `6` to switch, `i` to hide or show each
setting's description, and `b` to go back. A row whose value differs from its
default is marked `*` and shows the default with a **Reset**; `r` resets the
whole tab after a second press. Numbers step with `−` and `+` or take a typed
value with **Edit**. A value forced from outside (an environment variable, or
a project or managed Claude settings file) shows what forces it and no
controls.

The same settings can be set with
`bash <plugin-root>/scripts/forge-config set <key> <value>` or by editing
`~/.dr-forge/config.json`:

```json
{ "layout": "compact", "handoffMode": "relaxed", "finishAction": "pr" }
```

`forge-config get --json` prints every value in force, and
`forge-config workflow` prints the line the skills read.

| Tab | Option | Default | Effect |
| --- | --- | --- | --- |
| Cockpit | `openAtStart` | `true` | Open the pane when a session starts. Claude Code shows it once the terminal is 144 columns wide (110 once you have opened it before); `/cockpit` opens it at any width. |
| Cockpit | `layout` | `auto` | `auto`: the full layout docked beside the transcript, the band in a pane above the prompt. `full`: always the full layout. `compact`: minimized, no pane and the band above the prompt. **Minimize** sets `compact`, **Expand** sets `auto` (`full` where the pane does not dock). |
| Cockpit | `sections` | empty | The pane's sections and their order, comma-separated: `account`, `context`, `usage`, `shells`, `agents`, `plan`, `repo`, `guard`. Empty shows all eight. The band always draws its own lines. |
| Cockpit | `breakdownRows` | `6` | How many `/context` categories the Context section lists, largest first, up to 12. `0` hides them. |
| Cockpit | `guardAttribution` | `true` | Blank the engine's attribution text and refuse git writes that carry it. |
| Context | `handoffTokens` | `0` | The handoff budget in tokens, for the pane and the budget scripts alike. `0` follows dr-forge's own rule: 93% of the smaller of `autoCompactWindow` and the model's window, minus 140,000. `DR_FORGE_BUDGET` overrides it (`DR_SUPERPOWERS_BUDGET` still read). |
| Context | `handoffMode` | `strict` | `strict` hands off at the handoff budget. `relaxed` measures every task against the final-phase limit, 85% of the window, so a session carries a plan further; a worst-case fix loop late in such a session may compact, and the compaction snapshot carries it on. |
| Context | `warnAt` | `80` | Where **Hand off** takes the accent color, as a percentage of the handoff budget (1-99). |
| Context | `nudgeModel` | `true` | Add the one note to the conversation at the budget, in `dr-forge` sessions. |
| Context | `autoCompactWindow` | `0` | Claude's own `autoCompactWindow`, written to Claude's user settings file: `0` leaves it unset, else 100,000 to 1,000,000. Applies from the next session. |
| Context | `autoCompactEnabled` | `true` | Claude's own `autoCompactEnabled`, written to the same file. Applies from the next session. |
| Workflow | `codexLane` | `true` | Give plan tasks to Codex when its gate passes. `false` makes `scripts/codex-gate` report `lane=false`. |
| Workflow | `codexReview` | `true` | Let Codex take review seats when its gate passes. `false` makes the gate report `review=false`; with both off it does not probe Codex at all. |
| Workflow | `executionStrategy` | `ask` | `sequential` or `parallel` answers the "how should the plan execute" question. `parallel` still falls back to sequential when the parts share files, and on Codex. |
| Workflow | `executionMode` | `auto` | `auto` follows the planner's rule; `inline` and `subagent` fix the plan's Execution line, and `inline` also makes the plan sequential. |
| Workflow | `worktree` | `ask` | `always` isolates work in a git worktree without asking, `never` works in place, `ask` keeps the consent question. |
| Process | `processBias` | `standard` | How readily a request gets a written spec and plan: `lighter` resolves doubt to a short in-chat design, `heavier` to a spec. |
| Process | `designApproval` | `sections` | `sections` approves each design section in turn; `whole` presents the design once with one approval. |
| Process | `specReview` | `true` | Stop for you to review the written spec before the plan is written. |
| Process | `questionStyle` | `single` | `single` asks one clarifying question per message; `batched` asks them all in one. |
| Finish | `finishAction` | `ask` | What happens when the finish menu goes unanswered. `ask` keeps the question before the first task; `merge`, `pr` or `keep` skips it and runs after the wait; `wait` skips it and never acts. |
| Finish | `finishTimeout` | `30` | Minutes the finish menu waits before that action runs (5-240). |
| Notifications | `limitAlertAt` | `90` | The share at which a usage limit sends the Discord `limit` message, in percent. `0` turns it off. |
| Notifications | `notifyOn` | empty | The Discord events to send, comma-separated (see above). Empty sends the default set; `none` sends nothing. |
| Notifications | `notifyAfter` | `60` | Seconds a turn must run before `done` sends. `0` sends every turn. |
| Notifications | `notifyAskAfter` | `20` | Seconds an approval or question waits before it sends. `0` sends at once. |
| Notifications | `notifyDetail` | `full` | `full` includes command and answer excerpts; `brief` sends titles and fields only. |

The cockpit settings (Cockpit, Context, Notifications) apply at once, except
the two Claude keys, which Claude reads at its next session start. A
Workflow or Process setting reaches the skills through one line injected at
session start; when you change one mid-session, the cockpit adds a note to the
conversation as the settings close. The Codex switches, the handoff mode and
the finish settings are read by the scripts each time they run. Your own
instructions always outrank a setting, and no setting removes the approval
before implementation.

````

- [ ] **Step 3: Update the finish wording elsewhere in the README**

In `plugins/dr-forge/README.md`:

1. Replace `if its menu goes unanswered for 30 minutes (merge locally, push and open a pull` with `if its menu goes unanswered for the configured wait, 30 minutes by default (merge locally, push and open a pull`.
2. Replace `menu inside the 30 minutes disarms the wake and wins; otherwise the wake` with `menu inside that wait disarms the wake and wins; otherwise the wake`.
3. Replace `  30 minutes (`⏱ Finish push and open a PR · in 23m`) and says once it was` with `  wait (`⏱ Finish push and open a PR · in 23m`) and says once it was`.
4. Add after the paragraph that item 2 edits (it ends with the sentence about the cockpit Run card): a new paragraph

```markdown
With the `finishAction` setting at `merge`, `pr`, `keep` or `wait`, the run does
not ask that question: `scripts/finish-choice` records the configured action
the first time it is read, and `finishTimeout` sets the wait.
```

- [ ] **Step 4: Run the full validation**

Run: `timeout 60 node scripts/validate-repository.mjs`
Expected: the "are valid." line.

Run: `log=$(mktemp); timeout 1800 node scripts/test-all.mjs > "$log" 2>&1; echo "exit=$?"; tail -15 "$log"; grep -c '^FAIL' "$log"; rm -f "$log"`
Expected: `exit=0`, and `0` from the `grep -c`.

Run: `timeout 120 claude plugin validate . 2>&1 | tail -2`
Expected: `✔ Validation passed`

Run: `for p in dr-forge dr-status dcc-darkraise-ui dcc-darkraise-win32ui; do timeout 120 claude plugin validate plugins/$p 2>&1 | tail -1; done`
Expected: four lines `✔ Validation passed`

Run: `timeout 420 claude plugin test plugins/dr-forge 2>&1 | tail -4`
Expected: `148 pass` and `0 fail`

Run: `git status --short`
Expected: only `plugins/dr-forge/README.md` and the two manifests modified, and the untracked `docs/superpowers/notes/2026-09-23-opus-5-5-effort-eval-design.md`; no stray process is left running (`pgrep -fl "claude plugin test"` prints nothing).

- [ ] **Step 5: Close the inherited register rows**

The merge register deferred these rows to this work. Run, from the repository root:

```bash
for id in 3 4 5 6 7 8 9 10 11; do
  timeout 30 bash plugins/dr-forge/scripts/register set docs/superpowers/registers/2026-10-11-dr-forge.md "$id" done \
    --note "docs/superpowers/plans/2026-10-12-dr-forge-settings.md"
done
timeout 30 bash plugins/dr-forge/scripts/register set docs/superpowers/registers/2026-10-11-dr-forge.md 19 verify \
  --note "view rebuilt by docs/superpowers/plans/2026-10-12-dr-forge-settings.md; the owner confirms the look by hand"
timeout 30 bash plugins/dr-forge/scripts/register check docs/superpowers/registers/2026-10-11-dr-forge.md
```

Expected: `register: 0 errors`. Row 19 (the view's look) waits for the owner's inspection, and row 20 stays deferred.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-forge/README.md plugins/dr-forge/.claude-plugin/plugin.json plugins/dr-forge/.codex-plugin/plugin.json docs/superpowers/registers/2026-10-11-dr-forge.md
git commit -m "docs(dr-forge): document settings, release 2.1.0"
```

- [ ] **Step 7: Report the manual check**

The pane's look cannot be asserted by a test, so do not claim it verified. End the task's report with this list for the owner, who runs `claude --plugin-dir plugins/dr-forge` in a terminal at least 144 columns wide and then `/cockpit settings`:

1. Six tabs show; `1` to `6` switch them, and the open one is highlighted.
2. `i` hides and shows the descriptions; `b` returns to the cockpit.
3. On Context, press `+` on **Warn at**: the row gains `*`, `default 80%` and **Reset**; **Reset** removes them.
4. **Edit** on **Warn at**, type `500`, Enter: the range message shows and nothing is saved; type `65`, Enter: it saves.
5. Start the session with `DR_FORGE_BUDGET=465000`: **Handoff budget** shows `465k set by DR_FORGE_BUDGET` and no controls.
6. Press `+` on **Auto-compact at**: `~/.claude/settings.json` gains or changes only `autoCompactWindow`, every other key is intact, and the row shows the new value at once.
7. On Workflow, change **Worktree**, press `b`: in a session that has used a dr-forge skill, one `dr-forge settings changed: …` note appears in the conversation.
8. The rows line up in one label column on every tab, on a docked pane and on a narrow one.

Row 19 of the merge register closes when the owner accepts this list.
