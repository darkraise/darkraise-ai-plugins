# dr-forge settings view and workflow controls — design

**Date:** 2026-10-12
**Plugin:** `plugins/dr-forge` (2.0.0 → 2.1.0)
**Status:** awaiting owner review
**Execution strategy:** parallel — once the schema and `forge-config` exist,
the settings view, the scripts and the skills touch different files and consume
nothing from each other.
**Register:** `docs/superpowers/registers/2026-10-12-forge-settings.md`; inherits
rows 3-11, 19 and 20 of `docs/superpowers/registers/2026-10-11-dr-forge.md`.

## Problem

The dr-forge merge (`docs/superpowers/specs/2026-10-11-dr-forge-merge-design.md`)
gave the workflow one settings file and a settings view, and deferred the
workflow's own controls to this spec. Two things are missing.

The settings view is one column of five group cards. Eleven of its thirteen rows
are written by hand in `hooks/cockpit/register.tsx`; the schema's descriptions
are never drawn; nothing can be reset to its default; a value forced by
`DR_FORGE_BUDGET` still shows a stepper that saves a value with no effect; and
a free-text key can only be set from a terminal.

The workflow has no settings. Whether Codex is used, how strictly the handoff
budget is kept, what happens when the finish menu goes unanswered, how much
process a request gets and whether work is isolated in a worktree are all fixed
in scripts and skill text.

## Decisions

Owner answers, 2026-10-12 session:

- The view revamp covers navigation, an explanation of each setting, better
  controls and visual polish.
- Navigation is a row of group tabs with one group shown.
- The workflow controls are the four families chosen on 2026-10-11 (finish
  defaults, budget and handoff, execution routing, process depth) plus a
  worktree default. Fix-round limits and a model-tier ceiling are out.
- Process depth covers path bias, design approvals, the spec review stop and
  the clarifying-question style.
- A script enforces a setting wherever a script already makes the decision; the
  rest reach the model through one line injected at session start.
- The settings stay in the one global file, `~/.dr-forge/config.json`.

Design choices the owner confirmed:

- Relaxed handoff means "measure every task against the final-phase limit".
- Codex gets two on/off switches, not on/off/auto: the gate cannot be forced
  past a missing login or an exhausted quota, so "on" and "auto" would not
  differ.
- One `finishAction` key covers both the default action and "do not ask".

## Settings

### Schema fields

Each entry of `config/schema.mjs` keeps `type`, `default`, `group`, `title`,
`description`, `target`, `env`, `min`, `max`, `step` and `values`, and gains:

- `label` (required): the row label in the view, at most 16 characters. The
  thirteen existing keys take the labels the view hand-writes today
  ("Show at start", "Handoff budget", …), with "Attr. guard" spelled
  "AI attribution".
- `unit` (numbers, optional): `%`, `s`, `min` or `k` (thousands of tokens).
- `zero` (numbers, optional): the word shown at 0 (`auto`, `off`, `any`,
  `hidden`, `unset`).
- `floor` (numbers, optional): the smallest value allowed other than 0, for a
  key where 0 means unset. A value is valid when it is 0 or lies in
  `floor..max`.

A number setting is a whole number; every validator refuses a fraction.
- `enforcedBy` (optional): `script` or `skill`. A `skill` key appears in the
  `forge-config workflow` line and raises the mid-session note. A key the mod
  itself applies, or that belongs to Claude, omits the field.

`group` now takes six values, in this order: `Cockpit`, `Context`, `Workflow`,
`Process`, `Finish`, `Notifications`.

### New keys

All defaults reproduce the behaviour of 2.0.0.

| Group | Key | Type and values (default first) | Target | Enforced by | Effect |
|---|---|---|---|---|---|
| Context | `handoffMode` | enum `strict`, `relaxed` | forge | script | `strict`: hand off at the task budget. `relaxed`: every task is measured against the final-phase limit. |
| Context | `autoCompactWindow` | number, 0 or 100,000 to 1,000,000, step 50,000, unit `k`, zero `unset` | claude | - | Claude's `autoCompactWindow`; 0 removes the key. |
| Context | `autoCompactEnabled` | boolean, `true` | claude | - | Claude's `autoCompactEnabled`. |
| Workflow | `codexLane` | boolean, `true` | forge | script | `false`: `codex-gate` reports `lane=false`. |
| Workflow | `codexReview` | boolean, `true` | forge | script | `false`: `codex-gate` reports `review=false`. |
| Workflow | `executionStrategy` | enum `ask`, `sequential`, `parallel` | forge | skill | Anything but `ask` replaces brainstorming's execution-strategy question. `parallel` falls back to sequential when the design cannot name two parts that share no file, and on a Codex host. |
| Workflow | `executionMode` | enum `auto`, `inline`, `subagent` | forge | skill | `auto`: writing-plans' current rule. `inline` and `subagent` fix the plan's `**Execution:**` line. `inline` also makes the plan sequential, whatever the execution strategy says, because an inline session implements every task itself; such a plan still delegates its heavy tasks and every task with an `**Executor:**` line. |
| Workflow | `worktree` | enum `ask`, `always`, `never` | forge | skill | Replaces using-git-worktrees' consent question. `never` does not stop parallel waves isolating each task. |
| Process | `processBias` | enum `standard`, `lighter`, `heavier` | forge | skill | `lighter`: the architectural path only when a trigger plainly holds; doubt resolves to bounded. `heavier`: doubt resolves to architectural. A request for a spec and the irreducible-risk trigger hold under every value. |
| Process | `designApproval` | enum `sections`, `whole` | forge | skill | `whole`: the design is presented in full with one approval question. |
| Process | `specReview` | boolean, `true` | forge | skill | `false`: after the spec self-review, brainstorming goes to writing-plans without the user review gate. The design approval before the spec is unaffected. |
| Process | `questionStyle` | enum `single`, `batched` | forge | skill | `batched`: all clarifying questions go in one message. |
| Finish | `finishAction` | enum `ask`, `merge`, `pr`, `keep`, `wait` | forge | script | Anything but `ask` skips the finish question before the first task and records that action. |
| Finish | `finishTimeout` | number, 30, 5 to 240, step 5, unit `min` | forge | script | Minutes the finish menu waits before the recorded action runs. |

The existing thirteen keys keep their names, defaults and stored values. Their
groups stay `Cockpit` (`openAtStart`, `layout`, `sections`, `breakdownRows`,
`guardAttribution`), `Context` (`handoffTokens`, `warnAt`, `nudgeModel`) and
`Notifications` (the five Discord keys).

### Precedence

A `CLAUDE.md` or a direct request outranks a setting, and a setting outranks a
skill's built-in default. No setting removes the approval gate before
implementation.

## Settings view

A working mock of this section is published at
https://claude.ai/artifact/D3Q7SA2CRgdKkHnk9XmbFM (owner-private).

### Layout

```
Settings
[1 Cockpit] 2 Context  3 Workflow
 4 Process  5 Finish   6 Notifications

Context                              2 changed
 Handoff budget   auto    −  +  Edit
   Context size at which the cockpit says hand off.
 Handoff mode     strict  relaxed                 *
   strict hands off at the task budget. relaxed ...
   default strict                          Reset
 ...

Back   Hide help   Reset group
~/.dr-forge/config.json
```

- **Tabs.** One compact Button per group in schema order, hotkeys `1` to `6`,
  the open one drawn as the primary variant; the row wraps on a narrow pane.
- **Group header.** The group's name and `N changed` or `all defaults`.
- **One card** around the open group, replacing the five stacked cards.
- **Footer.** `Back` (`b`), `Hide help`/`Show help` (`i`), `Reset group` (`r`),
  the settings file's path, and the `settingProblems` lines as today.

The open tab, the help toggle, the row being edited and its error are session
state in a new `settingsView` value of `PluginState['dr-forge']`
(`types/index.d.ts`): `{ tab: string; isHelpShown: boolean; editing: string | null; error: string | null; isConfirmingReset: boolean }`.
The view opens on the first group with help shown.

### Rows

Every row is drawn from its schema entry: `label` padded to a 16-column label column,
then the control, then `*` when the value differs from the default.

| Type | Control |
|---|---|
| boolean | One toggle Button: `● On` / `○ Off`. |
| enum | One Button per value, the chosen one highlighted. Not the engine's `Select`: Buttons take one press and exist on the mobile surface. |
| number | The value (through `unit` and `zero`), `−`, `+`, and `Edit`. `Edit` draws an `Input`; Enter saves, and an entry outside the allowed range shows `Enter a whole number from <min> to <max>` and saves nothing. A trailing `k` multiplies by 1,000. On a key with a `floor`, `+` from 0 goes to the floor and `−` from the floor goes to 0. `Edit` is absent where the surface has no `Input`. |
| string | An `Input` behind `Edit` where the surface has one, else the value and the `forge-config set <key>` hint as today. No schema key draws this way now. |

Three rows stay hand-written because they are not plain values, with today's
behaviour: the `sections` and `notifyOn` chip lists, and the Discord webhook and
mention rows at the top of the Notifications tab.

Below a row:

- its `description`, dimmed and wrapped, while help is shown;
- when changed, `default <value>` and a `Reset` Button, which writes the
  default: a forge key leaves `~/.dr-forge/config.json`, and a Claude key
  follows the write rules under Claude's settings file.

**Locked rows.** A row whose value is forced from outside the file shows the
value in force and its source, with no controls:

- a key whose `env` variable is set and valid (`DR_FORGE_BUDGET`, or the legacy
  `DR_SUPERPOWERS_BUDGET`): `set by DR_FORGE_BUDGET`;
- a `target: claude` key whose merged value (`$.settings.read()`) differs from
  the user source's (`$.settings.read({ source: 'user' })`):
  `set by a project or managed settings file`.

This closes merge-register row 11.

**Reset group** is offered while a row of the open group differs from its
default. It turns into `Confirm reset` and `Cancel`; the confirmation resets
every changed row of the group (a locked row is never one). Any other press,
and reopening the settings, cancels it.

### Structure

- `hooks/cockpit/settings-view.tsx` (new): the view, as a function
  `drawSettings(table, model, actions)` that `register.tsx` calls where the
  inline block is today. The engine refuses to pass `$` across an import, so
  the module takes the element table from `$.ui.resolve(e)`, a row model and
  one callback per press; `register.tsx` builds the callbacks.
- `hooks/cockpit/config.ts`: the pure row model.
  - `tabsOf(schema): string[]`
  - `rowOf(key, spec, value, lock): ViewRow` with `label`, `kind`, `shown`
    (the value as text), `isChanged`, `lockedBy`; `rowsOf(schema, values, group, locks)`
  - `shownValue(spec, value): string`
  - `typedNumber(spec, text): number | undefined` and `rangeText(spec)`
  - `steppedSetting(spec, value, direction)`: the next multiple of `step`,
    kept in range
  - `envLocks` and `claudeLocks`
  - `isValidSetting` learns `floor`.
- `register.tsx` keeps `setOption`, `applySettings` and `loadSettings`, and
  loses the 220-line settings block and the `custom` map.

Probed 2026-10-12 on Claude Code 2.1.296: a second `.tsx` module that draws
with JSX validates and loads (127 tests pass with it imported); the same module
taking `$` fails validation.

## Enforcement

### Reading a setting from a script

Bash scripts call `bash "$HERE/forge-config" get <key>` (through a helper in
`scripts/lib/forge-env.sh`, `forge_setting KEY DEFAULT`). A failing call (no
Node, an unreadable file) yields the default, so a damaged settings file never
blocks a task, a budget line or the finish menu. The helper sets
`DR_FORGE_NO_IMPORT=1`, so reading a setting never creates the settings file,
and `DR_FORGE_NO_SETTINGS=1` makes it answer the default outright, for a test
suite that runs against the real home directory.

### Script-enforced keys

- **`codexLane`, `codexReview` in `scripts/codex-gate`.** After the trust check
  sets `review` and `lane`, a switch that is `false` forces its field to
  `false`. The forced values go into the session file the gate writes, which is
  what `review-route` and the executor scripts read, and into the gate's line.
  With both `false` the gate skips the Codex probe and reports
  `usable=false reason=setting … source=setting`; an answer cached with that
  reason is never reused once a switch is back on. With one `false` and the other surface open,
  `reason` is unchanged. The repository constraint "the Codex executor lane is
  on" (`docs/superpowers/distilled/constraints.md`) still holds: it binds the
  planner to the gate's answer, and the switch changes that answer.
- **`handoffMode` in `scripts/lib/context.sh`.** In `relaxed`, a plain
  `ctx_line` and a `wave` measure against the final-phase limit; the label
  reads `budget (relaxed)` or `budget (relaxed, wave of N)`, and a wave still
  reserves one task margin per extra task. `final`, `tail` and `plan` are
  unchanged (`tail` already uses that limit).
- **`handoffTokens` in `scripts/lib/context.sh`.** The task budget is
  `DR_FORGE_BUDGET`, else the `handoffTokens` setting when above 0, else the
  rule, so the scripts and the pane read one budget (merge-register row 5). `DR_FORGE_BUDGET` and `handoffTokens` do not move the final-phase
  limit, so in `relaxed` they have no effect on the verdict; the
  `handoffTokens` row's description says so. The cockpit's copy of the rule
  (`hooks/cockpit/lib.ts`) uses the same limit in `relaxed`, so the pane's
  meter, the Hand off accent, the handoff note and the scripts agree.
- **`finishAction`, `finishTimeout` in `scripts/finish-choice`.** `get`, when
  no choice is recorded and `finishAction` is not `ask`, records that action
  with `base` null and `"source": "setting"` and prints it; the skills' rule
  "skip the question when `finish-choice get` prints a choice" then applies
  unchanged, and finishing determines the base branch at Step 3 as it already
  does for a null base. A recorded choice always wins over the setting. The
  setting applies to every run with no recorded choice, a resumed one included:
  today such a run's menu waits for ever, and with an action configured it no
  longer does. `arm` without `--minutes` waits `finishTimeout` minutes.

### Skill-enforced keys

`scripts/forge-config workflow` prints one line naming every `enforcedBy: skill`
key whose resolved value differs from its default, or nothing when none does:

```
dr-forge settings in force (each replaces the matching question or default in the skills): worktree=always; designApproval=whole
```

- **Session start.** `scripts/session-start.sh` appends that line after the
  entry point and the roadmap line, for every source including `compact`. It is
  subtracted from the compaction snapshot's room as the roadmap line is. The
  entry-point skill is not edited: it has 75 bytes under its 5,100-byte cap.
- **Skills.** Each skill names its key at the decision point and says what each
  value does; with no settings line in context it runs
  `scripts/forge-config workflow` first. Codex has no session-start hook, so
  this is its only path.
  - `brainstorming`: `processBias` (Three Paths), `questionStyle`
    (clarifying questions), `designApproval` (Presenting the design),
    `executionStrategy` (Choosing the execution strategy), `specReview` (User
    Review Gate).
  - `writing-plans`: `executionMode` (the `**Execution:**` line), and the
    execution-strategy question it asks when a spec carries no line.
  - `using-git-worktrees`: `worktree` (Step 0 consent).
  - `subagent-driven-development`, `executing-plans`,
    `finishing-a-development-branch`, `using-git-worktrees` and
    `reference/finish-preference.md`: "30 minutes" becomes the configured wait,
    and the finish question is described as skipped when `finish-choice get`
    prints a choice from the setting.
- **Mid-session change.** When `setOption` saves an `enforcedBy: skill` key,
  the cockpit remembers it and, when the settings close (Back, or the pane
  closing), adds one note to the conversation through the mechanism the handoff
  note uses: `dr-forge settings changed: <key>=<value>; … Each replaces the
  matching question or default in the skills.`, with the latest value of each
  key. Outside a session running dr-forge (`isPlanSession`) the note waits
  until the session becomes one, and a note the session refuses stays pending
  for the next close.

## Claude's settings file

`autoCompactWindow` and `autoCompactEnabled` live in the user settings file:
`$CLAUDE_CONFIG_DIR/settings.json`, else `~/.claude/settings.json`.

- **Read.** `forge-config get` and `get --json` resolve a `target: claude` key
  from that file, then the schema default (`0` for an absent
  `autoCompactWindow`, `true` for an absent `autoCompactEnabled`). The cockpit
  reads the merged value through `$.settings.read()`.
- **Write.** `scripts/lib/forge-config.mjs` is the only writer. `set` and
  `unset` re-read the file, change the one key, and write a temporary file in
  the same directory then rename it. Every other key, and the key order, is
  kept. A value equal to "unset" (`autoCompactWindow` 0) deletes the key;
  `autoCompactEnabled` is always written explicitly.
- **Refusals.** When the file exists but is not a JSON object, nothing is
  written and the command exits 1 naming the file. A missing file is created
  holding the one key.
- **Symlinks.** The write goes to the file's real path, so a symlinked settings
  file stays a symlink.
- **From the cockpit.** `setOption` routes a `target: claude` key to
  `node <$.plugin.root>/scripts/lib/forge-config.mjs set` through
  `$.process.run`, then re-reads the settings. Probed 2026-10-12: that call
  validates in a top-level function of `register.tsx`.
- The write keeps the file's mode, since Claude's settings file may be private.
- The view's description says the value applies from the next session. The
  budget scripts read the file on every run, so the handoff budget follows at
  once.

`~/.dr-forge/config.json` never holds a `target: claude` key; `settingWritten`
and `forge-config` refuse to put one there.

## Repository changes

- `config/schema.mjs`: the new fields on all 27 keys and the 14 new keys.
- `scripts/validate-repository.mjs`: every key has a `label` of at most 16
  characters; `unit`, `zero`, `floor`, `enforcedBy` and `group` take only the
  values above.
- `scripts/lib/forge-config.mjs`, `scripts/forge-config`: `floor`, the
  `workflow` command, the Claude target.
- `scripts/lib/forge-env.sh`: `forge_setting`.
- `scripts/codex-gate`, `scripts/lib/context.sh`, `scripts/finish-choice`,
  `scripts/session-start.sh`: as under Enforcement.
- `hooks/cockpit/`: `settings-view.tsx` (new), `config.ts`, `register.tsx`,
  `lib.ts`; `types/index.d.ts`.
- Skills and references: as listed under Skill-enforced keys, plus
  `reference/session-budget.md` (the relaxed mode, a row in its Numbers table).
- `README.md`: the Settings section describes the tabs and lists all 27 keys.
- `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`: 2.1.0.

## Parallel decomposition

| Order | Part | Owns | Consumes |
|---|---|---|---|
| 1 | Foundation | `config/schema.mjs`; `scripts/lib/forge-config.mjs` (`workflow`); `scripts/lib/forge-env.sh`; `scripts/validate-repository.mjs`; `tests/forge-config.test.sh` | - |
| 2, alone | Claude settings write | The Claude target and `floor` in `scripts/lib/forge-config.mjs`; the two Claude keys in `config/schema.mjs`; `tests/forge-config.test.sh` | Foundation |
| 3, wave | View | `hooks/cockpit/settings-view.tsx`, `register.tsx`, `config.ts` (row model), `lib.ts`; `types/index.d.ts`; `tests/cockpit.test.ts` | Foundation, part 2 |
| 3, wave | Scripts | `scripts/codex-gate`, `scripts/lib/context.sh`, `scripts/finish-choice`; `tests/codex-gate.test.sh`, `tests/context-size.test.sh`, `tests/budget-line.test.sh`, `tests/finish-choice.test.sh`; `reference/session-budget.md` | Foundation |
| 3, wave | Skills | `scripts/session-start.sh`; `tests/hook.test.sh`; the `SKILL.md` of `brainstorming`, `writing-plans`, `using-git-worktrees`, `subagent-driven-development`, `executing-plans` and `finishing-a-development-branch`; `reference/finish-preference.md`; `tests/settings-skills.test.sh` (new) | Foundation |
| 4 | Release | `README.md`; both manifests; `scripts/test-shards.mjs` if a new test needs a weight; full validation | all |

Part 2 runs alone because it carries the data-loss risk. The three wave parts
may run together: each file has one owner, and none consumes another's output.
The plan may still run them one at a time: the repository's Codex-lane ruling
gives every task that passes the lane gate to Codex, and such a task runs
alone in its wave.
The View part implements the relaxed limit in `hooks/cockpit/lib.ts` and the
Scripts part implements it in `scripts/lib/context.sh`, both from the rule
stated under Enforcement; `tests/cockpit.test.ts` and
`tests/budget-line.test.sh` each assert the same worked figure (680,000 at an
800,000 window), which is what keeps the two copies equal.

**Test isolation.** Every shell test builds its own temporary `HOME` and
`CLAUDE_CONFIG_DIR`; `tests/cockpit.test.ts` runs inside `claude plugin test`
against stubbed `$.fs` and `$.process`. No ports, databases or fixed paths are
shared.

## Testing

- `tests/forge-config.test.sh`: each new key's default, a valid and an invalid
  value; `floor` (50,000 refused, 0 and 100,000 accepted for
  `autoCompactWindow`); `workflow` prints nothing at defaults and the changed
  `skill` keys otherwise; a Claude-target `set` keeps every other key and the
  key order; `unset` and `set 0` remove the key; an unparseable file is refused
  and left byte-identical; a symlinked file stays a symlink; a `target: claude`
  key never lands in `~/.dr-forge/config.json`.
- `tests/cockpit.test.ts`: every schema key is drawn in exactly one tab;
  `rowOf` for changed, default, env-locked and settings-locked values;
  `shownValue` for each `unit` and `zero`; `typedNumber` for in-range,
  out-of-range, `k` and non-numeric text; Reset and the two-press group reset;
  the relaxed limit; a `skill` key's change raises one note and a `script`
  key's raises none; the Claude-target route.
- `tests/codex-gate.test.sh`: each switch off alone, both off (no probe),
  both on unchanged, and the session file's fields.
- `tests/context-size.test.sh`, `tests/budget-line.test.sh`: relaxed verdicts
  for a plain task, a tail and a wave; `final` and `plan` unchanged; strict
  unchanged.
- `tests/finish-choice.test.sh`: `get` records the configured action once; a
  recorded choice wins; `ask` still exits 3; `arm` uses `finishTimeout` and
  `--minutes` overrides it.
- `tests/hook.test.sh`: the settings line present with a changed `skill` key,
  absent at defaults, and the output under 10,000 characters with the
  compaction snapshot.
- `tests/settings-skills.test.sh`: each skill listed under Skill-enforced keys
  names its keys, and neither those skills nor
  `reference/finish-preference.md` still says a fixed "30 minutes" for the
  finish menu.

## Verification

1. `node scripts/validate-repository.mjs` passes.
2. The maintained test suites pass (`node scripts/test-all.mjs`).
3. `claude plugin validate` passes on the marketplace and every Claude plugin.
4. `claude plugin test plugins/dr-forge` passes.
5. Manual, by the owner: `claude --plugin-dir plugins/dr-forge`, `/cockpit
   settings`. The tabs switch with `1` to `6`; a changed row shows `*`, its
   default and Reset; `DR_FORGE_BUDGET=465000` locks the handoff budget row;
   changing `autoCompactWindow` leaves every other key of
   `~/.claude/settings.json` intact. The pane's look cannot be asserted by a
   test.

All test and CLI runs are bounded, and every process the validation starts is
stopped.

## Out of scope

- Per-project settings: the one-file decision of 2026-10-11 stands.
- Fix-round limits, the final review's depth and a model-tier ceiling.
- Merging the three copies of the setting type check (merge-register row 20).
- Merge-register rows 12 to 18, which do not concern settings.
- A Codex-side settings view: Codex reads the same file through `forge-config`.
