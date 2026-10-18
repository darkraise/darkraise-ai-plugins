# Cockpit Native Desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

> **External executors:** codex

**Goal:** Cockpit sections collapse from their titles on both surfaces; on the Claude Code desktop app the panels, the band and the settings screen draw with the app's own text, theme colors, spacing and controls; and the Agents section groups subagents by state.

**Architecture:** A `collapsed` setting and two `lib.ts` helpers drive a title `Button` on every section. A new `hooks/cockpit/native.tsx` turns the existing `PanelLine`/`PanelRun` row descriptions into desktop `Box`/`Text` elements, colored through `themeColor`; the desktop panels and band switch to it and the whole-panel SVG drawing in `svg.ts` is deleted. The settings view draws `Select` and open `Input` controls on the desktop, and `agentGroups` sorts the spawn records into Waiting on you, Working, Failed and Done using each spawn's new `outcome` and the subagent named by an open approval wait.

**Tech Stack:** The TypeScript/TSX cockpit mod in `plugins/dforge/hooks/cockpit/` (Claude Code 2.1.302 mod API), tested by `claude plugin test`; a Node.js ESM settings schema; Markdown docs.

**Spec:** `docs/superpowers/specs/2026-10-17-cockpit-native-desktop-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — 1 of 9 tasks is heavy (Task 9, total 5) and seven carry a Codex `**Executor:**` line, so eight tasks are delegated; the one self-implemented task (Task 5) totals 4 (`impl-sonnet-medium`, effort medium), raised to high because tasks are delegated

**Plan review:** 2026-10-18 — codex gpt-6-astra / xhigh — executability 18 / coherence 16 / coverage 17 / assumptions 16 (round 1)

**Parallelism:** sequential — the spec's Execution strategy is sequential: collapsing, the native panels and the agent groups all edit `hooks/cockpit/register.tsx`

## Global Constraints

- Work in a worktree branched from local `main` (local `main` runs ahead of `origin/main`): `git worktree add .claude/worktrees/cockpit-native-desktop -b cockpit-native-desktop main`. This plan and its spec must be on local `main` first: before Task 1, `ls docs/superpowers/plans/2026-10-17-cockpit-native-desktop.md` in the worktree must list the file, or stop. Do not push.
- Never edit anything under `docs/superpowers/`: it is history (the register row is set by the execution skill's own scripts, not by hand).
- Never commit anything under `.superpowers/`; Task 1's probe lives there, untracked.
- Run each command on its own line; do not chain commands that mention git with `&&`, `;` or a pipe (the worktree guard refuses them).
- Run the cockpit suite from the worktree root under a bound, with the host's `CLAUDE_CONFIG_DIR` removed: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`. It has no filter: every run executes the whole of `tests/cockpit.test.ts` (about 15 seconds). In this host's Bash `claude` is a shell function that exits 127: call `/root/.local/bin/claude`.
- Every edit step is an exact replacement: the "replace" text must occur exactly once in the named file. Text that is not found, or found more than once, is a stop: report BLOCKED with the file and the text. Never paraphrase an edit, and apply a task's edits in the order written.
- The finish-without-wait plan (`docs/superpowers/plans/2026-10-17-finish-without-wait.md`) may run before or after this one; it edits the same files but none of the text this plan replaces. Test counts quoted below are for main 67b40b8; `0 fail` is the check.
- Commits: `<type>(<scope>): <subject>`, subject at most 50 characters, imperative, no period; author and committer `Darkraise <quangtc94@gmail.com>` (the repository's `user.name`/`user.email`); no `Co-Authored-By:`, `Claude-Session:` or "Generated with" line, nor any other AI attribution.
- No version bump in any manifest: a release is a separate commit the owner asks for.
- English only. Match the surrounding code: no new comments beyond those written in the steps.
- Stop every process a check starts; nothing in this plan starts a long-lived one. The owner's probe session in Task 1 is theirs to close.

## Contracts

- **C1 The `collapsed` setting.** `config/schema.mjs` key `collapsed`: `type: 'string'`, `default: ''`, `group: 'Cockpit'`, `target: 'dforge'`, label `Collapsed`, title `Collapsed sections`, description `Sections drawn as their title row only, comma-separated: account, context, usage, shells, agents, plan, repo, guard. Empty expands all eight.` In `hooks/cockpit/lib.ts`: `collapsedFrom(text: string): Section[]` (known names, each once, in `SECTIONS` order; `''` gives `[]`) and `collapsedToggled(collapsed: readonly Section[], name: Section): string` (adds or removes `name`, the setting text in `SECTIONS` order joined by `,`, `''` when none).
- **C2 Collapsing in the pane.** `register.tsx`'s `Options` gains `collapsed: string`, `Live` gains `shownCollapsed: Section[]` (`collapsedFrom(collapsed)`), and the pane's render scope defines `toggle(name: Section)`, which saves `collapsedToggled(o.shownCollapsed, name)` through `setOption($, 'collapsed', …)`. Each section's title is a `Button` keyed `<section>-title` (`account`, `context`, `usage`, `shells`, `agents`, `plan`, `repo`, `guard`), `plain`, labelled `▾ <Title>` when expanded and `▸ <Title>` when collapsed. A collapsed section draws only its head row, except that a collapsed Context keeps its buttons on both surfaces: the terminal card keeps its `actions` row, and the desktop panel keeps its `native` children (Task 5's `panel` helper draws them whether or not it is collapsed). The settings Cockpit tab's Collapsed chips are keyed `set-collapsed-<section>`.
- **C3 Native rows.** `lib.ts`: `themeColor(name: string | undefined): string | undefined` maps `green → success`, `red → error`, `yellow → warning`, `cyan → suggestion`, `blue → suggestion`, `magenta → planMode`, `gray → subtle`, `white → text`, and passes anything else through. `hooks/cockpit/native.tsx`: `nativeRun(table: Elements, key: string, run: PanelRun): RenderChildren` and `nativeLine(table: Elements, key: string, line: PanelLine): RenderChildren`, where `Elements = ReturnType<EngineInterface['ui']['resolve']>`. A `text` line is a row `Box` keyed `key` holding `Box`es keyed `<key>-left` and `<key>-right`; a `badge` line's text column is keyed `<key>-lines`. `PanelLine` and `PanelRun` stay in `hooks/cockpit/svg.ts`.
- **C4 Desktop keys.** A desktop panel's headline `Box` is `<section>-headline` and its rows are `<section>-line-<index>` (so a text row's halves are `<section>-line-<index>-left` and `-right`); the band's head rows are `band-who-<index>` and its other rows `band-rest-<index>`. The desktop root `Box` and the `gauges` `Box` carry `gap="md"`.
- **C5 Desktop settings.** `SettingsModel` (`hooks/cockpit/settings-view.tsx`) gains `isDesktop: boolean`; the native controls draw when `model.isDesktop && 'Select' in table`. Keys: `set-<key>-select` (toggle and choices rows), `set-<key>-input` (number and text rows, always shown), `set-<key>-block` (the row), `set-<key>-error` (a refusal, below the input). A refused submit sets the view state's `editing` to that key.
- **C6 Agent groups.** `lib.ts`: `type AgentGroupKey = 'waiting' | 'working' | 'failed' | 'done'` and `agentGroups<T extends { agentId: string; isDone: boolean; outcome?: 'done' | 'failed' | null }>(spawns: readonly T[], waiting: readonly string[], shown = 6): { key: AgentGroupKey; name: string; spawns: T[] }[]`, in the order `Waiting on you`, `Working`, `Failed`, `Done`, an empty group left out; the ended spawns are the most recent ones in the rows the running ones leave of `shown` (none once the running ones fill it), and an ended spawn without `outcome: 'failed'` is done.
- **C7 Spawn outcome and wait owner.** `CockpitSpawn` (`types/index.d.ts`) gains `outcome: 'done' | 'failed' | null`; a subagent's `turn.complete` sets `done` for `reason: 'answer'` and `failed` otherwise. Each `S.waits` entry gains `agentId: string | null`, and `startWait($, id, kind, event, agentId)` takes it as a fifth argument (the subagent's id from `tool.check`, `null` for the main loop's questions). Group headings read `<name> · <count>`; rows lead with `⏳`, `●`, `✗` or `✓` (`AGENT_MARKS`).
- **C8 Test helpers.** `tests/cockpit.test.ts`: `boxTexts(ui)` returns every `Box`'s joined text (Task 5); `World` gains `agentIds?: string[]`, handed out in turn by the stub `agent.spawn` (Task 9).
- **C9 The probe.** A standalone plugin `cockpit-probe` at `.superpowers/cockpit-probe/` in the worktree (untracked, never enrolled in a catalog), with the command `/cockpit-probe`.

## Assumptions (evidence)

- **The plan's edits are the passing prototype.** On 2026-10-18 every edit in Tasks 2-9 was replayed in order on a copy of `plugins/dforge` at main 67b40b8, with `claude plugin test` after each task: 220, 222, 225, 226, 226, 227, 228 and 229 pass, 0 fail. Each task's test edits alone, on the previous task's code, failed exactly as its "verify the new tests fail" step says. The final code matches the prototype in `.superpowers/handoff/cockpit-prototype/` except for deliberate changes: `themeColor` sits above `termColor`'s doc comment instead of between it and its function; `agentGroups` keeps no ended spawn once the running ones fill `shown` (the prototype's, and today's, `slice(-Math.max(0, shown - running.length))` keeps every ended spawn when it reaches `slice(-0)`; Task 8's test fails without the fix, checked 2026-10-18); the desktop settings' custom rows, chips, tabs and footer use named-step spacing both ways; Task 5's test also collapses and expands Repo's rows; and Task 9's test answers the approval by running the call (`$.tool.call`) instead of mounting `ToolProgress`. The whole validation (validator, `node scripts/test-all.mjs`, five `plugin validate`, `plugin test`) passed on a scratch worktree holding the plan's final code on 2026-10-18.
- **The prototype's Task 7 patch lacked its `register.tsx` half.** As handed off, the prototype ran 226 pass and 1 fail (`lists subagents waiting on you, working, failed and done`, run 2026-10-18); Task 9's `register.tsx` edits were written and verified this session.
- **The desktop app draws `Text size`/`weight`, theme-key colors and named-step spacing as the 2.1.302 typings say.** unverified — Task 1 verifies it: the owner checks the probe in the desktop app before Task 2 starts.
- **The drawn tree keeps keys only on `Box`, `Button`, `Input` and `Select`.** The prototype's assertions rely on it (handoff of 2026-10-18), which is why desktop rows are found through `boxTexts` and `<key>-left`/`-right` `Box`es.
- **`native.tsx` can be unit-tested with a stand-in table.** On 2026-10-18 `nativeLine({ Box: 'Box', Text: 'Text', Svg: 'Svg' } as never, …)` inside `claude plugin test` returned plain `{ type, props, children }` objects; `$.ui.resolve` is not available on a test's `$` (`TypeError: $.ui.resolve is not a function`).
- **Nothing type-checks the mod.** `claude plugin test` and `claude plugin validate` run no type check and `which tsc` printed nothing on 2026-10-18, so the code is given verbatim and type-only slips would not surface; `themeColor` returns `string | undefined` (the spec's `Color` accepts a raw string) because `lib.ts` imports no engine types.
- **`claude plugin test` has no test filter.** Its `--help` (2026-10-18) lists only `dir`.
- **`isDesktop`, `table` and `setOption` are in the pane's render scope.** `register.tsx:638` (`const table = $.ui.resolve(e)`), `register.tsx:644` (`const isDesktop = Svg !== undefined`), `register.tsx:2852` (`async function setOption`) on main 67b40b8.
- **The Context `actions` row is one element.** The terminal `section` helper keeps `body.filter(part => part === actions)` when collapsed; `actions` is the constant the Context card already passes (verified by Task 3's test that a collapsed Context still draws `pane-compact`).
- **No README check binds schema keys.** `scripts/validate-repository.mjs` validates the schema's shape only (`validateSchema`, read 2026-10-18), so Task 2 adds the key without its README row, which Task 3 writes.
- **Codex executes the lane-eligible tasks.** `codex-gate` printed `usable=true reason=ok review=true lane=true resets_at=- source=probe` on 2026-10-18, and `docs/superpowers/distilled/constraints.md` ("The Codex executor lane is on") ticks `codex` without asking. Tasks 5 and 9 (risk 2) fall outside the lane gate.
- **An approval wait lasts until its call returns.** `tool.call` runs the permission prompt inside `next(e)` and ends the wait after it, as `✓ Approved` or `✗ Denied` (`register.tsx`'s `tool.call` hook on main 67b40b8), so an approved subagent call that runs a long time stays under Waiting on you until it returns; the Now row's "waiting for approval" has the same lifetime today. The only earlier signal is the `ToolProgress` pill, whose `endWait` throws during render (below). Task 9 tests the call-return path; an earlier, render-safe end of the wait is out of this plan's scope.
- **A dropdown value outside its options never reaches `onSelect`.** On 2026-10-18, with the toggle's `onSelect` as written in Task 7, `ui.select({ key: 'set-openAtStart-select', value: 'maybe' })` wrote nothing to the settings file, so the toggle needs no guard against other strings; the spec's "a `Select` value outside the row's values is ignored" holds.
- **A10 and A11 are demos.** They run in the execution skill's acceptance QA at the end of the run, in the desktop app, not in a task. A known bug outside this plan: the `ToolProgress` render hook's `endWait` throws `state.set: denied … while ui.render is being dispatched` (handoff of 2026-10-18); no task depends on that path.

## Task index

1. Probe the desktop app with the owner
2. Add the collapsed setting and its helpers
3. Collapse terminal sections from their titles
4. Add the native row drawing
5. Draw the desktop panels natively
6. Draw the desktop band natively and drop the panel drawing
7. Use the desktop controls in settings
8. Add the agent state groups
9. List agents by state

---

### Task 1: Probe the desktop app with the owner

**Files:**
- Create: `.superpowers/cockpit-probe/.claude-plugin/plugin.json`
- Create: `.superpowers/cockpit-probe/hooks/hooks.json`
- Create: `.superpowers/cockpit-probe/hooks/probe.tsx`
- Test: `.superpowers/cockpit-probe/tests/probe.test.ts`

**Interfaces:**
- Consumes: none
- Produces: C9, and the owner's verdict on the spec's riskiest assumption

**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 0 = 2

All paths are under the worktree root, in the git-ignored `.superpowers/` folder. Nothing in this task is committed.

- [ ] **Step 1: Write the failing test**

Create `.superpowers/cockpit-probe/tests/probe.test.ts`:

```ts
import { expect, test } from 'claude-code/testing'

const PANE = { plugin: 'cockpit-probe', component: 'Pane', requestId: 'cockpit-probe', props: { title: 'Probe', isFocused: false, bodyColumns: 56, placement: 'dock', scroll: { offset: 0, bodyRows: 80 }, view: {} } } as const

test('the desktop table takes every probe element', async ($, on) => {
  on('ui.open', () => ({ value: { isPlaced: true } }))
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  const drawn = await ui.drawn()
  expect(drawn).toMatchObject({ type: 'Box', props: { gap: 'md' } })
  expect((await ui.find({ key: 'collapse-title' }))?.children[0]).toMatchObject({ type: 'Text', props: { size: 'heading', weight: 'semibold' } })
  expect((await ui.find({ key: 'runs-left-box' }))?.text).toBe('●  impl-sonnet-low  Implement task 3 with a description long enough to be cut at the end')
  expect(await ui.find({ key: 'collapse-body' })).toBeDefined()
  await ui.press({ key: 'collapse-title' })
  expect(await ui.find({ key: 'collapse-body' })).toBeUndefined()
  expect((await ui.find({ key: 'collapse-title' }))?.props.label).toBe('▸ Collapsible')
  await ui.select({ key: 'probe-select', value: 'false' })
  expect((await ui.find({ key: 'controls-state' }))?.text).toBe('selected false · typed (nothing)')
  await ui.input({ key: 'probe-input', text: '42' })
  expect((await ui.find({ key: 'controls-state' }))?.text).toBe('selected false · typed 42')
})

test('the terminal table draws it too', async ($, on) => {
  on('ui.open', () => ({ value: { isPlaced: true } }))
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ key: 'probe-select' })).toBeDefined()
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 120 /root/.local/bin/claude plugin test .superpowers/cockpit-probe`

Expected: FAIL — `claude plugin test: …/cockpit-probe: no hooks module to load; there is no hooks/hooks.json naming one in "modules"`.

- [ ] **Step 3: Write the probe**

Create `.superpowers/cockpit-probe/.claude-plugin/plugin.json`:

```json
{
  "name": "cockpit-probe",
  "description": "Draws one pane of native desktop text, colors, spacing and controls for an owner check.",
  "version": "0.0.1",
  "author": { "name": "Darkraise" }
}
```

Create `.superpowers/cockpit-probe/hooks/hooks.json`:

```json
{
  "description": "Loads the probe pane.",
  "modules": ["./probe.tsx"]
}
```

Create `.superpowers/cockpit-probe/hooks/probe.tsx`:

```tsx
import type { Register, RenderChildren } from 'claude-code'

const PANE = 'cockpit-probe'
const CARD = '#8080800f'
const SIZES = ['caption', 'footnote', 'body', 'heading', 'title'] as const
const WEIGHTS = ['regular', 'medium', 'semibold', 'bold'] as const
const KEYS = ['text', 'subtle', 'success', 'error', 'warning', 'suggestion', 'planMode', 'permission', 'claude'] as const
const GAPS = ['xs', 'sm', 'md', 'lg', 'xl'] as const

// What the probe's controls last set; a reload starts it over.
const P = { isCollapsed: false, choice: 'true', typed: '' }

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'cockpit-probe', description: 'Open the native desktop probe pane' })
    return next(e)
  })

  on('command.run', { command: 'cockpit-probe' }, async $ => {
    const opened = await $.ui.open({ id: PANE, title: 'Probe', columns: 56 })
    return { text: opened.isPlaced ? 'Probe pane opened.' : `Probe pane is waiting: ${opened.reason}` }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const table = $.ui.resolve(e)
    const Select = 'Select' in table ? table.Select : undefined
    const Input = 'Input' in table ? table.Input : undefined
    const card = (key: string, title: string, ...body: RenderChildren[]) => (
      <Box key={key} flexDirection="column" borderStyle="round" borderColor="subtle" backgroundColor={CARD} paddingX="md" paddingY="sm" gap="xs">
        <Text key={`${key}-title`} size="heading" weight="semibold">
          {title}
        </Text>
        {body}
      </Box>
    )
    const label = `${P.isCollapsed ? '▸' : '▾'} Collapsible`
    return (
      <Box flexDirection="column" gap="md">
        <Text key="surface" dimColor>{`surface: ${e.surface}`}</Text>
        {card('sizes', '1. Sizes', ...SIZES.map(size => <Text key={`size-${size}`} size={size}>{`size ${size}`}</Text>))}
        {card('weights', '2. Weights', ...WEIGHTS.map(weight => <Text key={`weight-${weight}`} weight={weight}>{`weight ${weight}`}</Text>))}
        {card(
          'colors',
          '3. Theme colors (switch light and dark)',
          ...KEYS.map(name => <Text key={`color-${name}`} color={name}>{`color ${name}`}</Text>),
          <Text key="color-dim" dimColor>dimColor</Text>,
          <Text key="color-mono" mono>mono 0123456789</Text>,
        )}
        {card(
          'runs',
          '4. A row of runs and pills',
          <Box key="runs-row" flexDirection="row" justifyContent="space-between" columnGap="sm">
            <Box key="runs-left-box" flexGrow={1} flexShrink={1}>
              <Text key="runs-left" wrap="truncate-end">
                <Text key="runs-left-0" color="success">{'●  '}</Text>
                <Text key="runs-left-1" size="caption" backgroundColor="subtle">impl-sonnet-low</Text>
                <Text key="runs-left-2">{'  Implement task 3 with a description long enough to be cut at the end'}</Text>
              </Text>
            </Box>
            <Text key="runs-right" size="footnote" dimColor mono>
              12m
            </Text>
          </Box>,
          <Box key="chips" flexDirection="row" flexWrap="wrap" gap="xs">
            <Text key="chip-0" size="caption" backgroundColor="subtle" color="suggestion">Opus 5.5</Text>
            <Text key="chip-1" size="caption" backgroundColor="subtle">xhigh effort</Text>
            <Text key="chip-2" size="caption" backgroundColor="subtle" color="success">Remote ○ on</Text>
          </Box>,
        )}
        {card(
          'gaps',
          '5. Gaps xs to xl between three rows',
          ...GAPS.map(gap => (
            <Box key={`gap-${gap}`} flexDirection="column" gap={gap} borderStyle="round" borderColor="subtle" paddingX="sm">
              <Text key={`gap-${gap}-a`} size="footnote">{`gap ${gap}: row one`}</Text>
              <Text key={`gap-${gap}-b`} size="footnote">row two</Text>
              <Text key={`gap-${gap}-c`} size="footnote">row three</Text>
            </Box>
          )),
        )}
        <Box key="collapse" flexDirection="column" borderStyle="round" borderColor="subtle" backgroundColor={CARD} paddingX="md" paddingY="sm" gap="xs">
          <Box key="collapse-head" flexDirection="row" justifyContent="space-between" alignItems="center" columnGap="sm">
            <Button
              key="collapse-title"
              label={label}
              plain
              onPress={() => {
                P.isCollapsed = !P.isCollapsed
                $.ui.invalidate('ui.render')
              }}
            >
              <Text key="collapse-title-text" size="heading" weight="semibold" color="suggestion">
                {label}
              </Text>
            </Button>
            <Text key="collapse-headline" size="footnote" dimColor>
              6. press the title
            </Text>
          </Box>
          {!P.isCollapsed && (
            <Box key="collapse-body">
              <Text>This row hides while collapsed.</Text>
            </Box>
          )}
        </Box>
        {card(
          'controls',
          '7. Controls',
          Select !== undefined && (
            <Select
              key="probe-select"
              label="Toggle"
              options={[
                { value: 'true', label: 'On' },
                { value: 'false', label: 'Off' },
              ]}
              value={P.choice}
              onSelect={(value: string) => {
                P.choice = value
                $.ui.invalidate('ui.render')
              }}
            />
          ),
          Input !== undefined && (
            <Input
              key="probe-input"
              label="Number"
              value={P.typed}
              submitLabel="save"
              onSubmit={(text: string) => {
                P.typed = text
                $.ui.invalidate('ui.render')
              }}
            />
          ),
          <Box key="controls-state">
            <Text size="footnote" dimColor>{`selected ${P.choice} · typed ${P.typed || '(nothing)'}`}</Text>
          </Box>,
        )}
      </Box>
    )
  })
}
```

- [ ] **Step 4: Run the test and validate the probe**

Run: `env -u CLAUDE_CONFIG_DIR timeout 120 /root/.local/bin/claude plugin test .superpowers/cockpit-probe`

Expected: PASS — `2 pass`, `0 fail`.

Run: `timeout 120 /root/.local/bin/claude plugin validate .superpowers/cockpit-probe`

Expected: `✔ Validation passed`.

- [ ] **Step 5: Owner check (the controller does this, not the implementer)**

Stop and ask the owner, in plain text, giving the probe's absolute path:

> Please open the probe in the Claude Code desktop app: run `/root/.local/bin/claude --plugin-dir <worktree>/.superpowers/cockpit-probe` in a terminal on this host, connect it with Remote Control, open the session in the desktop app's Code tab, and type `/cockpit-probe`. In the pane, check: (1) the five sizes differ; (2) the four weights differ; (3) the theme colors change when you switch the app between light and dark; (4) the row's seat and the chips sit on soft pills and the long row is cut with `…`; (5) the gaps grow from xs to xl; (6) pressing `▾ Collapsible` hides its row and shows `▸ Collapsible`; (7) the Toggle dropdown and the Number field update the line below them. Reply "pass", or the numbers that look wrong.

On "pass", record it in the ledger and go on to Task 2. Any other answer is a stop: the spec's riskiest assumption failed, so report BLOCKED with the owner's words and do not start Task 2.

---

### Task 2: Add the collapsed setting and its helpers

**Files:**
- Modify: `plugins/dforge/config/schema.mjs` (a `collapsed` key after `sections`)
- Modify: `plugins/dforge/hooks/cockpit/lib.ts` (after `sectionsToggled`)
- Test: `plugins/dforge/tests/cockpit.test.ts` (the lib import list; the `settings view` describe)

**Interfaces:**
- Consumes: none
- Produces: C1

**Items:** 5

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  budgetFor,
```

with:

```ts
  budgetFor,
  collapsedFrom,
  collapsedToggled,
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
    expect(sectionsToggled(['plan'], 'plan')).toBe('plan')
  })
```

with:

```ts
    expect(sectionsToggled(['plan'], 'plan')).toBe('plan')
  })

  test('collapses sections in their own order, each once', () => {
    expect(collapsedFrom('repo, usage, nope, usage')).toEqual(['usage', 'repo'])
    expect(collapsedFrom('')).toEqual([])
    expect(collapsedToggled(['usage', 'repo'], 'context')).toBe('context,usage,repo')
    expect(collapsedToggled(['usage', 'repo'], 'usage')).toBe('repo')
    expect(collapsedToggled(['usage'], 'usage')).toBe('')
  })
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: FAIL — the file does not load: `Export named 'collapsedFrom' not found in module '…/hooks/cockpit/lib.ts'`.

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/config/schema.mjs`, replace:

```js
  breakdownRows: {
```

with:

```js
  collapsed: {
    type: 'string', default: '', group: 'Cockpit', target: 'dforge',
    label: 'Collapsed', title: 'Collapsed sections',
    description: 'Sections drawn as their title row only, comma-separated: account, context, usage, shells, agents, plan, repo, guard. Empty expands all eight.',
  },
  breakdownRows: {
```

In `plugins/dforge/hooks/cockpit/lib.ts`, replace:

```ts
/** 465000 → "465k"; 1234567 → "1.2M". */
```

with:

```ts
/** The collapsed setting, "repo, usage" → ['usage', 'repo']: known names, each once, in SECTIONS order. */
export function collapsedFrom(text: string): Section[] {
  const names = text.split(/[\s,]+/).map(name => name.trim().toLowerCase())
  return SECTIONS.filter(name => names.includes(name))
}

/** The collapsed setting after collapsing or expanding one section, in SECTIONS order; empty when none is collapsed. */
export function collapsedToggled(collapsed: readonly Section[], name: Section): string {
  const next = collapsed.includes(name) ? collapsed.filter(one => one !== name) : [...collapsed, name]
  return SECTIONS.filter(one => next.includes(one)).join(',')
}

/** 465000 → "465k"; 1234567 → "1.2M". */
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: PASS — `0 fail` (on main 67b40b8 the count reads `220 pass`; a different count is fine if nothing fails).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/config/schema.mjs plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): add the collapsed setting"
```

---

### Task 3: Collapse terminal sections from their titles

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx` (the lib import list, `Options`, `Live`, `liveFrom`, the settings view's `custom` rows, the terminal `section` helper)
- Modify: `plugins/dforge/README.md` (the settings table, a Collapsing paragraph before **Minimize**)
- Test: `plugins/dforge/tests/cockpit.test.ts` (18 title assertions, two new tests, one assertion in the `buttons` describe)

**Interfaces:**
- Consumes: C1
- Produces: C2

**Items:** 5

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
    expect(collapsedToggled(['usage'], 'usage')).toBe('')
  })
```

with:

```ts
    expect(collapsedToggled(['usage'], 'usage')).toBe('')
  })

  test('the Collapsed chips save the collapsed setting', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: {}, written })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    expect((await ui.find({ key: 'set-collapsed-usage' }))?.props).toMatchObject({ label: '○ usage', dimColor: true })
    await ui.press({ key: 'set-collapsed-usage' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ collapsed: 'usage' })
    expect((await ui.find({ key: 'set-collapsed-usage' }))?.props.label).toBe('✓ usage')
  })
```

Rewrite the 18 section-title assertions (each section title is now a `Button` labelled `▾ <Title>`). Save this script outside the repository as `${TMPDIR:-/tmp}/titles.mjs` (any scratch path works):

```js
import { readFileSync, writeFileSync } from 'node:fs'
const file = process.argv[2]
let text = readFileSync(file, 'utf8')
const before = text
text = text.replace(/find\(\{ type: 'Text', text: '(Account|Context|Usage|Run)' \}\)/g, "find({ type: 'Button', text: '▾ $1' })")
text = text.replace("find({ type: 'Text', text: /^Agents$/ })", "find({ type: 'Button', text: '▾ Agents' })")
text = text.replaceAll(`indexOf('"Plan"')`, `indexOf('"▾ Plan"')`)
const changed = before.split('\n').filter((line, i) => line !== text.split('\n')[i]).length
console.log(`${changed} lines changed`)
writeFileSync(file, text)
```

Run it from the worktree root and expect `18 lines changed`:

```bash
node "${TMPDIR:-/tmp}/titles.mjs" plugins/dforge/tests/cockpit.test.ts
```

Any other count is a stop: report BLOCKED with the count.

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
    expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
  })

  test('breakdownRows limits the context rows', async ($, on) => {
```

with:

```ts
    expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
  })

  test('collapsed draws a section as its title row, and its title toggles it', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: { collapsed: 'usage,context' }, written })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    // Usage keeps its title and headline and loses every row.
    expect((await ui.find({ key: 'usage-title' }))?.props).toMatchObject({ label: '▸ Usage', plain: true })
    expect(await ui.find({ type: 'Text', text: /^\$1\.50/ })).toBeDefined()
    expect(await ui.find({ key: 'limit-five_hour' })).toBeUndefined()
    // Context loses its meter but keeps its buttons.
    expect(await ui.find({ type: 'Text', text: /handoff 465k/ })).toBeUndefined()
    expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
    await ui.press({ key: 'usage-title' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ collapsed: 'context' })
    expect((await ui.find({ key: 'usage-title' }))?.props.label).toBe('▾ Usage')
    expect(await ui.find({ key: 'limit-five_hour' })).toBeDefined()
    await ui.press({ key: 'repo-title' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ collapsed: 'context,repo' })
  })

  test('breakdownRows limits the context rows', async ($, on) => {
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
    expect(JSON.stringify(compact?.children)).toContain('{"type":"Text","props":{"underline":true},"children":["C"]}')
```

with:

```ts
    expect(JSON.stringify(compact?.children)).toContain('{"type":"Text","props":{"underline":true},"children":["C"]}')
    // A section's title is drawn in its card's color.
    expect((await ui.find({ key: 'context-title' }))?.children[0]).toMatchObject({ type: 'Text', props: { color: 'cyan', bold: true }, children: ['▾ Context'] })
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: FAIL — 12 tests fail, among them `settings > collapsed draws a section as its title row, and its title toggles it`, `settings view > the Collapsed chips save the collapsed setting` and `buttons > underline the hotkey letter where Claude Code draws styled labels`; the other nine are the rewritten title assertions (`account`, `run card`, `cockpit roots`, `minimized band`, `shells and remote`, `settings > sections picks and orders the pane`).

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
  budgetFor,
```

with:

```tsx
  budgetFor,
  collapsedFrom,
  collapsedToggled,
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
  sections: string
```

with:

```tsx
  sections: string
  collapsed: string
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
  shown: Section[]
```

with:

```tsx
  shown: Section[]
  shownCollapsed: Section[]
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
    sections = '',
```

with:

```tsx
    sections = '',
    collapsed = '',
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
    sections,
```

with:

```tsx
    sections,
    collapsed,
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
    shown: sectionsFrom(sections),
```

with:

```tsx
    shown: sectionsFrom(sections),
    shownCollapsed: collapsedFrom(collapsed),
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
        notifyOn: (
```

with:

```tsx
        collapsed: (
          <Box key="set-collapsed-chips" flexDirection="column">
            <Box key="set-collapsed-label"><Text>Collapsed</Text></Box>
            {chips(
              'set-collapsed',
              SECTIONS,
              name => o.shownCollapsed.includes(name as Section),
              name => name,
              name => save('collapsed', collapsedToggled(o.shownCollapsed, name as Section)),
            )}
          </Box>
        ),
        notifyOn: (
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
    const inner = Math.max(20, room - 4)
    const wide = Math.max(10, inner - 2 * INDENT)
    const section = (key: string, title: string, color: string, headline: RenderChildren, ...body: RenderChildren[]) => (
      <Box key={key} flexDirection="column" borderStyle="round" borderColor={color} paddingX={1}>
        <Box key={`${key}-head`} flexDirection="row" justifyContent="space-between">
          <Text color={color} bold>
            {title}
          </Text>
          {headline}
        </Box>
        {body}
      </Box>
    )
```

with:

```tsx
    // Its title collapses it to that line, saved in the collapsed setting; a
    // collapsed Context card keeps its buttons.
    const inner = Math.max(20, room - 4)
    const wide = Math.max(10, inner - 2 * INDENT)
    const toggle = (name: Section) => setOption($, 'collapsed', collapsedToggled(o.shownCollapsed, name))
    const section = (key: Section, title: string, color: string, headline: RenderChildren, ...body: RenderChildren[]) => {
      const isCollapsed = o.shownCollapsed.includes(key)
      const label = `${isCollapsed ? '▸' : '▾'} ${title}`
      return (
        <Box key={key} flexDirection="column" borderStyle="round" borderColor={color} paddingX={1}>
          <Box key={`${key}-head`} flexDirection="row" justifyContent="space-between">
            {S.canUnderline ? (
              <Button key={`${key}-title`} label={label} plain hover={{ bold: true }} onPress={() => toggle(key)}>
                <Text color={color} bold>
                  {label}
                </Text>
              </Button>
            ) : (
              <Button key={`${key}-title`} label={label} plain hover={{ bold: true }} onPress={() => toggle(key)} />
            )}
            {headline}
          </Box>
          {isCollapsed ? body.filter(part => part === actions) : body}
        </Box>
      )
    }
```

- [ ] **Step 4: Update the README**

In `plugins/dforge/README.md`, replace:

```markdown
| Cockpit | `sections` | empty | The pane's sections and their order, comma-separated: `account`, `context`, `usage`, `shells`, `agents`, `plan`, `repo`, `guard`. Empty shows all eight. The band always draws its own lines. |
```

with:

```markdown
| Cockpit | `sections` | empty | The pane's sections and their order, comma-separated: `account`, `context`, `usage`, `shells`, `agents`, `plan`, `repo`, `guard`. Empty shows all eight. The band always draws its own lines. |
| Cockpit | `collapsed` | empty | Sections drawn as their title row and headline only, comma-separated, from the same eight names. Pressing a section's title collapses or expands it and saves this setting. Empty expands all eight. |
```

In `plugins/dforge/README.md`, replace:

```markdown
**Minimize** (`m`) closes the pane and draws the cockpit as a band directly
```

with:

```markdown
**Collapsing.** Each section's title is a button: `▾ Usage` collapses the
section to its title row and headline, and `▸ Usage` expands it again. Each
press saves the `collapsed` setting, so the next session opens the same way. A
collapsed Context section keeps its buttons, and the resumable-work card never
collapses.

**Minimize** (`m`) closes the pane and draws the cockpit as a band directly
```

- [ ] **Step 5: Run the suite to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: PASS — `0 fail` (on main 67b40b8 the count reads `222 pass`; a different count is fine if nothing fails).

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/README.md plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): collapse sections from their titles"
```

---

### Task 4: Add the native row drawing

**Files:**
- Create: `plugins/dforge/hooks/cockpit/native.tsx`
- Modify: `plugins/dforge/hooks/cockpit/lib.ts` (before `termColor`)
- Test: `plugins/dforge/tests/cockpit.test.ts` (the lib import list, a native import, a `native rows` describe before `pane graphics`)

**Interfaces:**
- Consumes: none (it reads `PanelLine` and `PanelRun` from `hooks/cockpit/svg.ts`, unchanged)
- Produces: C3

**Items:** 5

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  termColor,
```

with:

```ts
  termColor,
  themeColor,
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
} from '../hooks/cockpit/config'
import { avatarSvg,
```

with:

```ts
} from '../hooks/cockpit/config'
import { nativeLine, nativeRun } from '../hooks/cockpit/native'
import { avatarSvg,
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
describe('pane graphics', () => {
```

with:

```ts
describe('native rows', () => {
  // A stand-in element table: what native.tsx draws comes back as plain
  // objects. A Text keeps no key, as on a real surface.
  const TABLE = { Box: 'Box', Text: 'Text', Svg: 'Svg' } as never
  const PICTURE = '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>'

  test('maps the named colors to theme keys and passes the rest through', () => {
    expect(['green', 'red', 'yellow', 'cyan', 'blue', 'magenta', 'gray', 'white'].map(name => themeColor(name))).toEqual(['success', 'error', 'warning', 'suggestion', 'suggestion', 'planMode', 'subtle', 'text'])
    expect(themeColor('#ff8700')).toBe('#ff8700')
    expect(themeColor('permission')).toBe('permission')
    expect(themeColor(undefined)).toBeUndefined()
  })

  test('draws a run as the desktop text, a chip on a pill', () => {
    expect(nativeRun(TABLE, 'run', { text: '12m', color: 'green', bold: true, mono: true })).toEqual({ type: 'Text', props: { color: 'success', weight: 'semibold', mono: true }, children: ['12m'] })
    expect(nativeRun(TABLE, 'run', { text: 'Opus 5.5', color: 'cyan', chip: true })).toEqual({ type: 'Text', props: { color: 'suggestion', size: 'caption', backgroundColor: 'subtle' }, children: ['Opus 5.5'] })
    expect(nativeRun(TABLE, 'run', { text: 'done', faint: true })).toEqual({ type: 'Text', props: { dimColor: true }, children: ['done'] })
  })

  test('draws each kind of panel line', () => {
    // Text: its left cut at the end beside its right, an indent in cells.
    expect(nativeLine(TABLE, 'row', { kind: 'text', small: true, indent: 15, left: [{ text: 'a' }], right: [{ text: 'b' }] })).toEqual({
      type: 'Box',
      props: { key: 'row', flexDirection: 'row', justifyContent: 'space-between', columnGap: 'sm', paddingLeft: 2 },
      children: [
        { type: 'Box', props: { key: 'row-left', flexGrow: 1, flexShrink: 1 }, children: [{ type: 'Text', props: { size: 'footnote', wrap: 'truncate-end' }, children: [{ type: 'Text', children: ['a'] }] }] },
        { type: 'Box', props: { key: 'row-right', flexShrink: 0 }, children: [{ type: 'Text', props: { size: 'footnote' }, children: [{ type: 'Text', children: ['b'] }] }] },
      ],
    })
    expect(nativeLine(TABLE, 'note', { kind: 'text', wrap: true, left: [{ text: 'a long note' }] })).toMatchObject({ children: [{ children: [{ props: { wrap: 'wrap' } }] }] })
    expect(nativeLine(TABLE, 'chips', { kind: 'chips', chips: [{ text: 'one' }, { text: 'two', color: 'red' }] })).toEqual({
      type: 'Box',
      props: { key: 'chips', flexDirection: 'row', flexWrap: 'wrap', gap: 'xs' },
      children: [
        { type: 'Text', props: { size: 'caption', backgroundColor: 'subtle' }, children: ['one'] },
        { type: 'Text', props: { color: 'error', size: 'caption', backgroundColor: 'subtle' }, children: ['two'] },
      ],
    })
    const badge = nativeLine(TABLE, 'who', { kind: 'badge', svg: PICTURE, lines: [[{ text: 'me@example.com' }], [{ text: 'Me' }]] })
    expect(badge).toMatchObject({ type: 'Box', props: { key: 'who', flexDirection: 'row' }, children: [{ type: 'Svg', props: { source: PICTURE } }, { type: 'Box', props: { key: 'who-lines' } }] })
    expect((badge as { children: { children?: unknown[] }[] }).children[1]?.children).toMatchObject([{ type: 'Text', props: { wrap: 'truncate-end' } }, { type: 'Text', props: { size: 'footnote' } }])
    expect(nativeLine(TABLE, 'bar', { kind: 'picture', svg: PICTURE, alt: 'a bar' })).toEqual({ type: 'Svg', props: { source: PICTURE, alt: 'a bar' } })
    // A surface without pictures draws none.
    expect(nativeLine({ Box: 'Box', Text: 'Text' } as never, 'bar', { kind: 'picture', svg: PICTURE })).toBe(false)
  })
})

describe('pane graphics', () => {
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: FAIL — the file does not load: `../hooks/cockpit/native` does not exist and `themeColor` is not exported.

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/hooks/cockpit/lib.ts`, replace:

```ts
/** A terminal color: a 256-color number becomes hex, orange its own hex, a name stays. */
```

with:

```ts
// The named colors the rows use, as the theme keys that mean the same.
const THEME_KEYS: Record<string, string> = { green: 'success', red: 'error', yellow: 'warning', cyan: 'suggestion', blue: 'suggestion', magenta: 'planMode', gray: 'subtle', white: 'text' }

/** A named color as the theme key that means the same, so the desktop's theme draws it; a theme key, a hex or any other name passes through. */
export function themeColor(name: string | undefined): string | undefined {
  return name === undefined ? undefined : (THEME_KEYS[name] ?? name)
}

/** A terminal color: a 256-color number becomes hex, orange its own hex, a name stays. */
```

Create `plugins/dforge/hooks/cockpit/native.tsx`:

```tsx
import type { EngineInterface, RenderChildren } from 'claude-code'

import { themeColor } from './lib'
import type { PanelLine, PanelRun } from './svg'

// The engine refuses to pass `$` across an import, so this module draws from
// the surface's element table, as settings-view.tsx does.
type Elements = ReturnType<EngineInterface['ui']['resolve']>

/** One run as the desktop's own text: a theme color, dim or faint dimmed, bold semibold, a chip on a soft pill. */
export function nativeRun(table: Elements, key: string, run: PanelRun): RenderChildren {
  const { Text } = table
  return (
    <Text
      key={key}
      color={themeColor(run.color)}
      dimColor={run.dim || run.faint ? true : undefined}
      weight={run.bold ? 'semibold' : undefined}
      mono={run.mono ? true : undefined}
      size={run.chip ? 'caption' : undefined}
      backgroundColor={run.chip ? 'subtle' : undefined}
    >
      {run.text}
    </Text>
  )
}

/** One panel row as the desktop's own elements, keyed `key`; a row's pixel indent becomes cells. */
export function nativeLine(table: Elements, key: string, line: PanelLine): RenderChildren {
  const { Box, Text } = table
  const Svg = 'Svg' in table ? table.Svg : undefined
  const runs = (part: string, list: readonly PanelRun[]) => list.map((run, index) => nativeRun(table, `${key}-${part}-${index}`, run))
  if (line.kind === 'picture') return Svg !== undefined && <Svg key={key} source={line.svg} alt={line.alt ?? ''} />
  if (line.kind === 'chips') {
    return (
      <Box key={key} flexDirection="row" flexWrap="wrap" gap="xs">
        {line.chips.map((chip, index) => nativeRun(table, `${key}-${index}`, { ...chip, chip: true }))}
      </Box>
    )
  }
  if (line.kind === 'badge') {
    return (
      <Box key={key} flexDirection="row" alignItems="center" columnGap="sm">
        {Svg !== undefined && <Svg key={`${key}-svg`} source={line.svg} alt="" />}
        <Box key={`${key}-lines`} flexDirection="column" flexShrink={1}>
          {line.lines.map((one, row) => (
            <Text key={`${key}-${row}`} size={row === 0 ? undefined : 'footnote'} wrap="truncate-end">
              {runs(String(row), one)}
            </Text>
          ))}
        </Box>
      </Box>
    )
  }
  const size = line.small ? 'footnote' : undefined
  const right = line.right ?? []
  return (
    <Box key={key} flexDirection="row" justifyContent="space-between" columnGap="sm" paddingLeft={line.indent === undefined ? undefined : Math.round(line.indent / 7.5)}>
      <Box key={`${key}-left`} flexGrow={1} flexShrink={1}>
        <Text size={size} wrap={line.wrap ? 'wrap' : 'truncate-end'}>
          {runs('left', line.left)}
        </Text>
      </Box>
      {right.length > 0 && (
        <Box key={`${key}-right`} flexShrink={0}>
          <Text size={size}>{runs('right', right)}</Text>
        </Box>
      )}
    </Box>
  )
}
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: PASS — `0 fail` (on main 67b40b8 the count reads `225 pass`; a different count is fine if nothing fails).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/hooks/cockpit/native.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): add native panel rows"
```

---

### Task 5: Draw the desktop panels natively

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx` (the lib and native imports, the desktop `panel` helper, the desktop root and gauges `Box`)
- Modify: `plugins/dforge/README.md` (the desktop flight-deck paragraph)
- Test: `plugins/dforge/tests/cockpit.test.ts` (a `boxTexts` helper; the `cockpit pane`, `desktop` and `flight deck` describes)

**Interfaces:**
- Consumes: C2, C3
- Produces: C4 (the panel keys) and `boxTexts` (C8)

**Items:** 5

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
const runsText = (runs: Run[]) => runs.map(one => one.text).join('')
```

with:

```ts
const runsText = (runs: Run[]) => runs.map(one => one.text).join('')
// Every Box's text, its strings joined: a desktop row's left and right halves
// are Boxes of their own, and the engine keeps no key on a Text.
const boxTexts = async (ui: { findAll: (query: { type: string }) => Promise<{ text: string }[]> }) => (await ui.findAll({ type: 'Box' })).map(one => one.text)
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
      // The desktop draws its panels as pictures, their words in each one's alt.
      if (surface === 'desktop') expect(JSON.stringify(await ui.drawn())).toMatch(/●  impl-sonnet-low  Task 3/)
```

with:

```ts
      // The desktop draws its panels' rows as its own text.
      if (surface === 'desktop') expect(await boxTexts(ui)).toContain('●  impl-sonnet-low  Task 3')
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
        const drawn = JSON.stringify(await ui.drawn())
        expect(drawn).toContain('impl-sonnet-low ×1 40k in · 75% cached · 3k out')
        expect(drawn).toContain('✓  impl-sonnet-low  Task 3')
```

with:

```ts
        const texts = await boxTexts(ui)
        expect(texts).toContain('impl-sonnet-low ×1')
        expect(texts).toContain('40k in · 75% cached · 3k out')
        expect(texts).toContain('✓  impl-sonnet-low  Task 3')
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
        // The desktop draws its panels as pictures, naming their figures and
        // the repo's chips in each one's alt.
        expect(drawn).toContain('Usage: $1.50')
        expect(drawn).toContain('61% of the handoff budget')
        expect(drawn).toContain('5h limit 23% used')
        expect(drawn).toContain('284k of 650k tokens, handoff at 465k')
        expect(drawn).toContain('⎇ feat/pane, ↑2, ↓1, ~1 changed, ?1 untracked')
```

with:

```ts
        // The desktop draws its panels' rows and chips as its own text, its
        // gauges and meters as pictures that name their figures in the alt.
        expect((await ui.find({ key: 'usage-headline' }))?.text).toMatch(/^\$1\.50/)
        expect(drawn).toContain('61% of the handoff budget')
        expect(drawn).toContain('5h limit 23% used')
        expect(drawn).toContain('284k of 650k tokens, handoff at 465k')
        for (const chip of ['⎇ feat/pane', '↑2', '↓1', '~1 changed', '?1 untracked']) expect(drawn).toContain(`"children":["${chip}"]`)
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  test('opens the pane when the desktop joins', async ($, on) => {
```

with:

```ts
  test('a collapsed panel draws its title and headline alone, and its title toggles it', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: { collapsed: 'usage,context' }, written })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
    expect((await ui.find({ key: 'usage-title' }))?.props.label).toBe('▸ Usage')
    expect((await ui.find({ key: 'usage-headline' }))?.text).toMatch(/^\$1\.50/)
    // A collapsed Context keeps its buttons and drops its meter.
    const meterAlt = async () => (await ui.findAll({ type: 'Svg' })).map(one => one.props.alt).filter(alt => alt === '284k of 650k tokens, handoff at 465k')
    expect(await meterAlt()).toEqual([])
    expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
    await ui.press({ key: 'context-title' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ collapsed: 'usage' })
    expect((await ui.find({ key: 'context-title' }))?.props.label).toBe('▾ Context')
    expect(await meterAlt()).toHaveLength(1)
    // Repo's rows go with its title and come back with it.
    expect(await ui.find({ key: 'repo-line-0' })).toBeDefined()
    await ui.press({ key: 'repo-title' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ collapsed: 'usage,repo' })
    expect(await ui.find({ key: 'repo-line-0' })).toBeUndefined()
    expect(await ui.find({ key: 'repo-headline' })).toBeDefined()
    await ui.press({ key: 'repo-title' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ collapsed: 'usage' })
    expect(await ui.find({ key: 'repo-line-0' })).toBeDefined()
  })

  test('opens the pane when the desktop joins', async ($, on) => {
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
    expect(drawn).toStartWith('{"type":"Box","props":{"flexDirection":"column","rowGap":1}')
    expect(drawn).toContain('"key":"usage","flexDirection":"column","borderStyle":"round","borderColor":"subtle","backgroundColor":"#8080800f"')
    expect(drawn).toContain('@media (prefers-color-scheme: dark)')
    expect(drawn).toContain('Opus 5.5, xhigh effort, Remote ○ on · no device yet, config ~/.claude')
    // Usage leaves the windows to their gauges and says what the ticks mean.
    expect(drawn).toContain("The gauges' ticks mark how far each window has run: 27% of 5h, 49% of 7d.")
    expect(drawn).not.toContain('of the window gone')
    expect(drawn).toContain('Shells: 2 running')
    expect(drawn).toContain('$ npm run dev 0s')
    // Each seat's counts sit on a row above its bar, with no title or caption.
    expect(drawn).toContain('judge-opus ×1 64k in · 72% cached · 3k out')
    expect(drawn).not.toContain('Seats by input')
    expect(drawn).not.toContain('prompt cache.')
    // The window's labels slide clear of each other rather than drop out.
    expect(drawn).toContain('>compacts 604k</text>')
    expect(drawn).toContain('>handoff 465k</text>')
    expect(drawn).toContain('+14k · 7 turns</text>')
    expect(drawn).toContain('Run: 1 blocked · round 2/5 · 1/6')
```

with:

```ts
    expect(drawn).toStartWith('{"type":"Box","props":{"flexDirection":"column","gap":"md"}')
    expect(drawn).toContain('"key":"usage","flexDirection":"column","borderStyle":"round","borderColor":"subtle","backgroundColor":"#8080800f","paddingX":"md","paddingY":"sm","gap":"xs"')
    expect(drawn).toContain('@media (prefers-color-scheme: dark)')
    // Titles, rows and pills are the desktop's own text in theme colors.
    expect((await ui.find({ key: 'usage-title' }))?.children[0]).toMatchObject({ type: 'Text', props: { size: 'heading', weight: 'semibold', color: 'suggestion' }, children: ['▾ Usage'] })
    expect(drawn).toContain('{"type":"Text","props":{"color":"suggestion","size":"caption","backgroundColor":"subtle"},"children":["Opus 5.5"]}')
    for (const chip of ['xhigh effort', 'Remote ○ on · no device yet', 'config ~/.claude']) expect(drawn).toContain(`"children":["${chip}"]`)
    // No picture stands in for a panel's rows; the gauges stay pictures.
    const alts = (await ui.findAll({ type: 'Svg' })).map(one => String(one.props.alt))
    for (const alt of alts) expect(alt).not.toMatch(/Opus 5\.5|npm run dev|judge-opus|Task 4|feat\/pane|running/)
    expect(alts).toContain('5h limit 23% used, resets 3h40m, on pace')
    // A badge row holds its picture beside its lines; a small row is a
    // footnote, a wrapped one wraps, and an indent is counted in cells.
    expect((await ui.find({ key: 'account-line-0' }))?.children[0]).toMatchObject({ type: 'Svg' })
    expect(drawn).toContain('"size":"footnote","wrap":"wrap"')
    expect(drawn).toContain('"columnGap":"sm","paddingLeft":2}')
    // Usage leaves the windows to their gauges and says what the ticks mean.
    expect(drawn).toContain("The gauges' ticks mark how far each window has run: 27% of 5h, 49% of 7d.")
    expect(drawn).not.toContain('of the window gone')
    expect((await ui.find({ key: 'shells-headline' }))?.text).toBe('2 running')
    expect((await ui.find({ key: 'shells-line-0-left' }))?.text).toBe('$ npm run dev')
    expect((await ui.find({ key: 'shells-line-0-right' }))?.text).toBe('0s')
    // Each seat's counts sit on a row above its bar, with no title or caption.
    expect(await boxTexts(ui)).toContain('judge-opus ×1')
    expect(await boxTexts(ui)).toContain('64k in · 72% cached · 3k out')
    expect(drawn).not.toContain('Seats by input')
    expect(drawn).not.toContain('prompt cache.')
    // The window's labels slide clear of each other rather than drop out.
    expect(drawn).toContain('>compacts 604k</text>')
    expect(drawn).toContain('>handoff 465k</text>')
    expect(drawn).toContain('+14k · 7 turns</text>')
    expect((await ui.find({ key: 'plan-headline' }))?.text).toBe('1 blocked · round 2/5 · 1/6')
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: FAIL — 4 tests fail: `cockpit pane > sums a seat once its subagent finishes`, `cockpit pane > shows the context, limits, cost and repo`, `desktop > a collapsed panel draws its title and headline alone, and its title toggles it`, `flight deck > draws every panel the way the approved preview does`.

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
  termColor,
```

with:

```tsx
  termColor,
  themeColor,
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
import type { SettingValue, SettingsFile } from './config'
```

with:

```tsx
import type { SettingValue, SettingsFile } from './config'
import { nativeLine, nativeRun } from './native'
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
      // the context and the two usage windows, then a panel per section. Each
      // panel's rows are one drawing laid out at the preview's sizes and gaps
      // (desktop text has one size and whole-line spacing); its buttons stay
      // the desktop's own.
      const width = svgWidth(inner)
      const panel = (key: string, title: string, lamp: string, right: PanelRun[], lines: PanelLine[], ...native: RenderChildren[]) => {
        const all: PanelLine[] = [{ kind: 'head', lamp, title, right }, ...lines]
        return (
          <Box key={key} flexDirection="column" borderStyle="round" borderColor="subtle" backgroundColor={CARD} paddingX={1}>
            {picture(`${key}-panel`, panelSvg(all, width), panelText(all))}
            {native.length > 0 && (
              <Box key={`${key}-native`} flexDirection="column" paddingBottom={1}>
```

with:

```tsx
      // the context and the two usage windows, then a panel per section. A
      // panel's rows are the desktop's own text in its theme's colors, its
      // charts drawings; its title collapses it as the terminal's does.
      const width = svgWidth(inner)
      const panel = (key: Section, title: string, lamp: string, right: PanelRun[], lines: PanelLine[], ...native: RenderChildren[]) => {
        const isCollapsed = o.shownCollapsed.includes(key)
        const label = `${isCollapsed ? '▸' : '▾'} ${title}`
        return (
          <Box key={key} flexDirection="column" borderStyle="round" borderColor="subtle" backgroundColor={CARD} paddingX="md" paddingY="sm" gap="xs">
            <Box key={`${key}-head`} flexDirection="row" justifyContent="space-between" alignItems="center" columnGap="sm">
              <Button key={`${key}-title`} label={label} plain onPress={() => toggle(key)}>
                <Text size="heading" weight="semibold" color={themeColor(lamp)}>
                  {label}
                </Text>
              </Button>
              <Box key={`${key}-headline`} flexShrink={1}>
                <Text size="footnote" wrap="truncate-end">
                  {right.map((run, index) => nativeRun(table, `${key}-headline-${index}`, { ...run, dim: run.color === undefined ? true : run.dim }))}
                </Text>
              </Box>
            </Box>
            {!isCollapsed && lines.map((line, index) => nativeLine(table, `${key}-line-${index}`, line))}
            {native.length > 0 && (
              <Box key={`${key}-native`} flexDirection="column">
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
        <Box flexDirection="column" rowGap={1}>
```

with:

```tsx
        <Box flexDirection="column" gap="md">
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
            <Box key="gauges" flexDirection="column" rowGap={1}>
```

with:

```tsx
            <Box key="gauges" flexDirection="column" gap="md">
```

- [ ] **Step 4: Update the README**

In `plugins/dforge/README.md`, replace:

```markdown
tile. Every other section follows as a softly filled panel with a colored
lamp; the usage panel says how far each window has run. The desktop's own text
has one size and spaces rows a whole line apart, so each panel's rows, chips
and charts are drawn as one picture at their own sizes and gaps, its text in
your system's light or dark tones (its words are in the picture's alt text).
The buttons are the desktop's own.
```

with:

```markdown
tile. Every other section follows as a softly filled panel, a space apart,
its title in the section's color; the usage panel says how far each window has
run. Titles, rows and chips are the desktop's own text in your theme's colors,
so switching the app between light and dark recolors them; the gauges, bars
and meters are drawings. A panel's title collapses it, as in the terminal.
The buttons are the desktop's own.
```

- [ ] **Step 5: Run the suite to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: PASS — `0 fail` (on main 67b40b8 the count reads `226 pass`; a different count is fine if nothing fails).

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/README.md plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): draw desktop panels natively"
```

---

### Task 6: Draw the desktop band natively and drop the panel drawing

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx` (the svg import, `drawBand`'s desktop card)
- Modify: `plugins/dforge/hooks/cockpit/svg.ts` (the `head` line kind, `GAP`, `PAD`, `wrapRuns`, `drawRunsAt`, `panelText`, `panelSvg`, the section comment)
- Test: `plugins/dforge/tests/cockpit.test.ts` (the svg import, the `desktop` describe's panel drawing part, the `minimized band` desktop assertions)

**Interfaces:**
- Consumes: C3
- Produces: C4 (the band keys)

**Items:** 5

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
    // A panel lays its lines out in pixels: the header, text cut to fit
    // beside its right side, pills, wrapped notes and drawings placed whole.
    const lines = [
      { kind: 'head', lamp: 'cyan', title: 'Context', right: [{ text: '284k of 650k' }] },
      { kind: 'text', left: [{ text: 'a very long command line that will not fit in the room it has' }], right: [{ text: '12:04', mono: true }] },
      { kind: 'chips', chips: [{ text: 'Opus 5.5', color: 'cyan' }, { text: 'xhigh effort' }] },
      { kind: 'text', wrap: true, small: true, left: [{ text: 'one two three four five six seven eight nine ten eleven twelve', dim: true }] },
      { kind: 'picture', svg: seatSvg(1, 0.5, 120, 'magenta'), alt: 'a seat' },
      { kind: 'picture', svg: seatSvg(0.5, 0.5, 120, 'magenta') },
    ] as const
    const drawnPanel = panelSvg(lines as never, 120)
    expect(drawnPanel).toContain('>CONTEXT</text>')
    expect(drawnPanel).toContain('text-anchor="end"')
    expect(drawnPanel).toContain('…</tspan>')
    expect(drawnPanel).toContain('class="pill"')
    expect(drawnPanel).toContain('@media (prefers-color-scheme: dark)')
    expect(drawnPanel.match(/<text /g)?.length).toBeGreaterThan(6)
    // Two placed drawings keep their clip paths apart.
    const clips = [...drawnPanel.matchAll(/<clipPath id="([^"]+)"/g)].map(match => match[1])
    expect(new Set(clips).size).toBe(2)
    expect(panelText(lines as never)).toBe(
      'Context: 284k of 650k\na very long command line that will not fit in the room it has 12:04\nOpus 5.5, xhigh effort\none two three four five six seven eight nine ten eleven twelve\na seat',
    )
```

with:

```ts

```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
import { avatarSvg, bandMetersSvg, gaugeTileSvg, gaugeSvg, labelledMeterSvg, meterSvg, paint, panelSvg, panelText, seatSvg, segmentsSvg, stackSvg, svgWidth, trendSvg } from '../hooks/cockpit/svg'
```

with:

```ts
import { avatarSvg, bandMetersSvg, gaugeTileSvg, gaugeSvg, labelledMeterSvg, meterSvg, paint, seatSvg, segmentsSvg, stackSvg, svgWidth, trendSvg } from '../hooks/cockpit/svg'
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
    expect(drawn).toContain('me@example.com · subscription')
    expect(drawn).toContain('5h 23%')
    expect(drawn).toContain('1 shell · longest 0s')
```

with:

```ts
    // The band's head and rows are the desktop's own text, its meters one picture.
    expect((await desk.find({ key: 'band-who-0-left' }))?.text).toMatch(/^me@example\.com · subscription  Remote/)
    expect((await desk.find({ key: 'band-rest-0-left' }))?.text).toContain('$ 1 shell · longest 0s')
    expect((await desk.findAll({ type: 'Svg' })).map(one => one.props.alt)).toEqual([expect.stringContaining('5h 23%')])
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: FAIL — 1 test fails: `minimized band > draws the band in the account's frame, with Expand on the top rule`.

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
import { avatarSvg, bandMetersSvg, gaugeTileSvg, gaugeSvg, labelledMeterSvg, meterSvg, panelSvg, panelText, seatSvg, segmentsSvg, stackSvg, svgWidth, trendSvg } from './svg'
```

with:

```tsx
import { avatarSvg, bandMetersSvg, gaugeTileSvg, gaugeSvg, labelledMeterSvg, meterSvg, seatSvg, segmentsSvg, stackSvg, svgWidth, trendSvg } from './svg'
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
          <Box key="band-who" flexGrow={1}>
            {picture('band-who-line', panelSvg(head0, svgWidth(room - 16)), panelText(head0))}
```

with:

```tsx
          <Box key="band-who" flexGrow={1} flexShrink={1}>
            {head0.map((line, index) => nativeLine(table, `band-who-${index}`, line))}
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
        {rest.length > 0 && picture('band-rest', panelSvg(rest, w), panelText(rest))}
```

with:

```tsx
        {rest.map((line, index) => nativeLine(table, `band-rest-${index}`, line))}
```

In `plugins/dforge/hooks/cockpit/svg.ts`, replace:

```ts
  /** The panel's header: a lamp, the title in small capitals, and its headline at the right. */
  | { kind: 'head'; lamp: string; title: string; right: PanelRun[] }
```

with:

```ts

```

In `plugins/dforge/hooks/cockpit/svg.ts`, replace:

```ts
      if (line.kind === 'head') return [line.title, say(line.right)].filter(Boolean).join(': ')
```

with:

```ts

```

In `plugins/dforge/hooks/cockpit/svg.ts`, replace:

```ts
    if (line.kind === 'head') {
      const right = cut(line.right, SMALL, width / 2)
      out += `<circle cx="4" cy="${n(y + 7)}" r="4" fill="${paint(line.lamp)}"/>`
      out += `<text x="15" y="${n(y + 10.5)}" class="faint" font-family="${MONO}" font-size="10.5" font-weight="600" letter-spacing="0.84">${esc(line.title.toUpperCase())}</text>`
      out += drawRunsAt(right.map(run => ({ ...run, dim: run.color === undefined ? true : run.dim })), width, y + 11, SMALL, 'end')
      y += 14
      return
    }
```

with:

```ts

```

In `plugins/dforge/hooks/cockpit/svg.ts`, replace:

```ts
// Panels drawn whole. The desktop's native text has one size and spaces rows
// by whole lines, so each panel's rows are laid out here in pixels instead,
// at the preview's sizes and gaps. Text takes the page's light or dark tones
// from the system setting; the accents are the drawings' own mid tones.
```

with:

```ts
// The rows a panel describes, which native.tsx draws as the desktop's own
// text, and the type the gauge tiles and the band's meters set in their
// drawings: the page's light or dark tones from the system setting, the
// accents the drawings' own mid tones.
```

In `plugins/dforge/hooks/cockpit/svg.ts`, replace:

```ts
const GAP = 6
const PAD = 9
```

with:

```ts

```

In `plugins/dforge/hooks/cockpit/svg.ts`, replace:

```ts
/** Runs broken into lines no wider than `room`, at spaces where it can. */
function wrapRuns(runs: readonly PanelRun[], size: number, room: number): PanelRun[][] {
  const lines: PanelRun[][] = [[]]
  let used = 0
  for (const run of runs) {
    for (const word of run.text.split(/(?<= )/)) {
      const width = measure(word, size, Boolean(run.mono))
      if (used + width > room && used > 0) {
        lines.push([])
        used = 0
      }
      lines[lines.length - 1]?.push({ ...run, text: used === 0 ? word.trimStart() : word })
      used += width
    }
  }
  // Pieces of one run on one line go back together, so the page spaces them.
  return lines.map(line =>
    line.reduce<PanelRun[]>((kept, run) => {
      const last = kept[kept.length - 1]
      if (last !== undefined && last.color === run.color && last.bold === run.bold && last.dim === run.dim && last.faint === run.faint && last.mono === run.mono && !last.chip && !run.chip) {
        kept[kept.length - 1] = { ...last, text: last.text + run.text }
      } else kept.push(run)
      return kept
    }, []),
  )
}

```

with:

```ts

```

In `plugins/dforge/hooks/cockpit/svg.ts`, replace:

```ts
/**
 * The runs on the baseline `y`, from `x` on (or ending at `x`). Plain runs
 * share one text element, so the page sets their spacing itself; a chip's
 * pill is placed by its measured width.
 */
function drawRunsAt(runs: readonly PanelRun[], x: number, y: number, size: number, anchor: 'start' | 'end' = 'start'): string {
  const line = (parts: readonly PanelRun[], at: number, end = false) =>
    parts.length === 0 ? '' : `<text x="${n(at)}" y="${n(y)}"${end ? ' text-anchor="end"' : ''} xml:space="preserve">${parts.map(run => tspan(run, size)).join('')}</text>`
  if (anchor === 'end') return line(runs, x, true)
  let at = x
  let out = ''
  let group: PanelRun[] = []
  const flush = () => {
    out += line(group, at)
    at += group.reduce((sum, run) => sum + runWidth(run, size), 0)
    group = []
  }
  for (const run of runs) {
    if (!run.chip) {
      group.push(run)
      continue
    }
    flush()
    const runSize = sizeOf(run, size)
    const width = runWidth(run, size)
    const height = runSize + 7
    out += `<rect class="pill" x="${n(at)}" y="${n(y - size * 0.35 - height / 2)}" width="${n(width)}" height="${n(height)}" rx="${n(height / 2)}"/>`
    out += `<text x="${n(at + PILL_X)}" y="${n(y - (size - runSize) * 0.35)}" xml:space="preserve">${tspan({ ...run, chip: false }, runSize + (run.mono ? 1 : 0))}</text>`
    at += width
  }
  flush()
  return out
}

```

with:

```ts

```

In `plugins/dforge/hooks/cockpit/svg.ts`, replace:

```ts
/** What a panel's lines say, as words, for the drawing's `alt`. */
export function panelText(lines: readonly PanelLine[]): string {
  const say = (runs: readonly PanelRun[] = []) => runs.map(run => run.text).join('')
  return lines
    .map(line => {
      if (line.kind === 'text') return [say(line.left), say(line.right)].filter(Boolean).join(' ')
      if (line.kind === 'chips') return line.chips.map(chip => chip.text).join(', ')
      if (line.kind === 'badge') return line.lines.map(say).join(' · ')
      return line.alt ?? ''
    })
    .filter(Boolean)
    .join('\n')
}

/** A panel's lines laid out `width` pixels wide at the preview's sizes and gaps. */
export function panelSvg(lines: readonly PanelLine[], width: number, pad = PAD): string {
  nested = 0
  let y = pad
  let out = ''
  lines.forEach((line, index) => {
    if (index > 0) y += GAP
    if (line.kind === 'picture') {
      const placed = place(line.svg, line.indent ?? 0, y)
      out += placed.svg
      y += placed.height
      return
    }
    if (line.kind === 'chips') {
      let x = 0
      const height = SMALL + 7
      line.chips.forEach(chip => {
        const run = { ...chip, chip: true }
        const chipWidth = Math.min(runWidth(run, SMALL), width)
        if (x > 0 && x + chipWidth > width) {
          x = 0
          y += height + 5
        }
        out += drawRunsAt(cut([run], SMALL, width), x, y + height / 2 + SMALL * 0.35, SMALL)
        x += chipWidth + 5
      })
      y += height
      return
    }
    if (line.kind === 'badge') {
      const placed = place(line.svg, 0, y)
      const gap = 9
      const textHeight = line.lines.length * 17
      const top = y + Math.max(0, (placed.height - textHeight) / 2)
      out += placed.svg
      line.lines.forEach((runs, row) => {
        const size = row === 0 ? BODY : SMALL
        out += drawRunsAt(cut(runs, size, width - placed.width - gap), placed.width + gap, top + row * 17 + 13, size)
      })
      y += Math.max(placed.height, textHeight)
      return
    }
    const size = line.small ? SMALL : BODY
    const lineHeight = line.small ? 16 : 18
    const indent = line.indent ?? 0
    const right = line.right ?? []
    const rightWidth = right.reduce((sum, run) => sum + runWidth(run, size), 0)
    const room = width - indent - (rightWidth > 0 ? rightWidth + 10 : 0)
    const hasChip = line.left.some(run => run.chip)
    const rows = line.wrap ? wrapRuns(line.left, size, room) : [cut(line.left, size, room)]
    const each = hasChip ? lineHeight + 4 : lineHeight
    rows.forEach((runs, row) => {
      const base = y + row * each + each / 2 + size * 0.35
      out += drawRunsAt(runs, indent, base, size)
      if (row === 0 && rightWidth > 0) out += drawRunsAt(right, width, base, size, 'end')
    })
    y += rows.length * each
  })
  y += pad
  return svg(width, Math.ceil(y), THEME + out)
}

```

with:

```ts

```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: PASS — `0 fail` (on main 67b40b8 the count reads `226 pass`; a different count is fine if nothing fails).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/hooks/cockpit/svg.ts plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): draw the desktop band natively"
```

---

### Task 7: Use the desktop controls in settings

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/settings-view.tsx` (`SettingsModel`, `drawSettings`)
- Modify: `plugins/dforge/hooks/cockpit/register.tsx` (the settings model, `submit`'s refusal, the settings `row` and `chips` helpers)
- Modify: `plugins/dforge/README.md` (the Settings view paragraph, the switch sentence before it)
- Test: `plugins/dforge/tests/cockpit.test.ts` (the `settings view` describe)

**Interfaces:**
- Consumes: none
- Produces: C5

**Items:** 5

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
      await ui.press({ key: 'set-openAtStart-toggle' })
      await ui.press({ key: 'set-layout-compact' })
```

with:

```ts
      if (surface === 'desktop') {
        await ui.select({ key: 'set-openAtStart-select', value: 'true' })
        await ui.select({ key: 'set-layout-select', value: 'compact' })
      } else {
        await ui.press({ key: 'set-openAtStart-toggle' })
        await ui.press({ key: 'set-layout-compact' })
      }
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  test('a group resets only after a second press', async ($, on) => {
```

with:

```ts
  test('the desktop draws dropdowns and open fields, and a refused entry below its field', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: {}, written })
    await $.session.start(START)
    const desk = await $.ui.mount({ ...PANE, surface: 'desktop' })
    await desk.press({ key: 'pane-settings' })
    expect((await desk.find({ key: 'set-openAtStart-select' }))?.props).toMatchObject({ value: 'true', options: [{ value: 'true', label: 'On' }, { value: 'false', label: 'Off' }] })
    expect((await desk.find({ key: 'set-layout-select' }))?.props).toMatchObject({ value: 'auto', options: [{ value: 'auto' }, { value: 'full' }, { value: 'compact' }] })
    expect(await desk.find({ key: 'set-layout-full' })).toBeUndefined()
    // Wrapping rows are spaced by the desktop's own steps both ways.
    expect((await desk.find({ key: 'settings-tabs' }))?.props).toMatchObject({ columnGap: 'sm', rowGap: 'sm' })
    expect((await desk.find({ key: 'set-section' }))?.props).toMatchObject({ columnGap: 'xs', rowGap: 'xs' })
    expect((await desk.find({ key: 'set-section' }))?.props.paddingLeft).toBeUndefined()
    await desk.select({ key: 'set-openAtStart-select', value: 'false' })
    await desk.select({ key: 'set-layout-select', value: 'full' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ openAtStart: false, layout: 'full' })
    await desk.press({ key: 'settings-tab-Context' })
    expect((await desk.find({ key: 'set-warnAt-input' }))?.props).toMatchObject({ label: 'Warn at', value: '80' })
    expect(await desk.find({ key: 'set-warnAt-edit' })).toBeUndefined()
    await desk.input({ key: 'set-warnAt-input', text: '500' })
    const block = JSON.stringify(await desk.find({ key: 'set-warnAt-block' }))
    expect(block).toContain('✗ Enter a whole number from 1 to 99')
    expect(block.indexOf('"set-warnAt-error"')).toBeGreaterThan(block.indexOf('"set-warnAt-input"'))
    await desk.input({ key: 'set-warnAt-input', text: '65' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ openAtStart: false, layout: 'full', warnAt: 65 })
    expect(await desk.find({ key: 'set-warnAt-error' })).toBeUndefined()
    await desk.unmount()
    const term = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await term.find({ type: 'Select' })).toBeUndefined()
    expect(await term.find({ key: 'set-warnAt-edit' })).toBeDefined()
  })

  test('a group resets only after a second press', async ($, on) => {
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: FAIL — 2 tests fail: `settings view > writes each press to the settings file on desktop` and `settings view > the desktop draws dropdowns and open fields, and a refused entry below its field`.

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
          canType,
```

with:

```tsx
          canType,
          isDesktop,
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
              await update($, settingsView, now => ({ ...now, error: rangeText(spec) }))
```

with:

```tsx
              await update($, settingsView, now => ({ ...now, editing: key, error: rangeText(spec) }))
```

In `plugins/dforge/hooks/cockpit/settings-view.tsx`, replace:

```tsx
  canType: boolean
```

with:

```tsx
  canType: boolean
  /** The desktop app: its own dropdowns and fields, spaced by its own scale. */
  isDesktop: boolean
```

In `plugins/dforge/hooks/cockpit/settings-view.tsx`, replace:

```tsx
  const Input = 'Input' in table ? table.Input : undefined
```

with:

```tsx
  const Input = 'Input' in table ? table.Input : undefined
  const Select = model.isDesktop && 'Select' in table ? table.Select : undefined
  const isNative = Select !== undefined
```

In `plugins/dforge/hooks/cockpit/settings-view.tsx`, replace:

```tsx
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
```

with:

```tsx
  // The desktop's own controls: a dropdown for a switch or a choice, an open
  // field for a number or text, a refused entry's reason below its field.
  const nativeControl = (row: ViewRow): RenderChildren => {
    if (Select === undefined || row.lockedBy !== null) return control(row)
    if (row.kind === 'toggle') {
      return (
        <Select
          key={`set-${row.key}-select`}
          options={[
            { value: 'true', label: 'On' },
            { value: 'false', label: 'Off' },
          ]}
          value={String(row.value === true)}
          onSelect={(value: string) => act.set(row.key, value === 'true')}
        />
      )
    }
    if (row.kind === 'choices') {
      return <Select key={`set-${row.key}-select`} options={row.values.map(value => ({ value }))} value={String(row.value)} onSelect={(value: string) => act.set(row.key, value)} />
    }
    const field = Input !== undefined && (
      <Input key={`set-${row.key}-input`} label={row.label} value={String(row.value)} submitLabel="save" onSubmit={(text: string) => act.submit(row.key, text)} />
    )
    if (row.kind === 'stepper') return [field, press(`set-${row.key}-less`, '−', () => act.step(row.key, -1)), press(`set-${row.key}-more`, '+', () => act.step(row.key, 1))]
    return field
  }

  // A desktop row: its label over its description and its control.
  const drawNativeRow = (row: ViewRow): RenderChildren => (
    <Box key={`set-${row.key}-block`} flexDirection="column" gap="xs">
      {model.custom[row.key] !== undefined ? (
        <Box key={`set-${row.key}`} flexDirection="row" columnGap="sm">
          {model.custom[row.key]}
          {mark(row)}
        </Box>
      ) : (
        <Box key={`set-${row.key}-label`} flexDirection="row" columnGap="sm">
          <Text weight="medium">{row.label}</Text>
          {mark(row)}
        </Box>
      )}
      {model.isHelpShown && (
        <Box key={`set-${row.key}-help`}>
          <Text size="footnote" dimColor wrap="wrap">
            {row.description}
          </Text>
        </Box>
      )}
      {model.custom[row.key] === undefined && (
        <Box key={`set-${row.key}-controls`} flexDirection="row" flexWrap="wrap" alignItems="center" columnGap="sm">
          {nativeControl(row)}
        </Box>
      )}
      {model.editing === row.key && model.error !== null && (
        <Box key={`set-${row.key}-error`}>
          <Text color="error">{`✗ ${model.error}`}</Text>
        </Box>
      )}
      {row.isChanged && (
        <Box key={`set-${row.key}-default`} flexDirection="row" alignItems="center" columnGap="sm">
          <Text size="footnote" dimColor>
            {row.shownDefault === '' ? 'changed from the default' : `default ${row.shownDefault}`}
          </Text>
          {press(`set-${row.key}-reset`, 'Reset', () => act.reset(row.key))}
        </Box>
      )}
    </Box>
  )

  const changed = model.rows.filter(row => row.isChanged).length
  return (
    <Box flexDirection="column" gap={isNative ? 'md' : undefined}>
      <Text bold>Settings</Text>
      <Box key="settings-tabs" flexDirection="row" flexWrap="wrap" columnGap={isNative ? 'sm' : 1} rowGap={isNative ? 'sm' : undefined}>
        {model.tabs.map((tab, index) =>
          press(`settings-tab-${tab}`, tab, () => act.openTab(tab), { hotkey: index < 9 ? String(index + 1) : undefined, isMain: tab === model.tab, isOff: tab !== model.tab }),
        )}
      </Box>
      <Box
        key={`set-group-${model.tab}`}
        flexDirection="column"
        borderStyle="round"
        borderColor="subtle"
        backgroundColor={CARD}
        paddingX={isNative ? 'md' : 1}
        paddingY={isNative ? 'sm' : undefined}
        gap={isNative ? 'md' : undefined}
      >
        <Box key="set-group-head" flexDirection="row" alignItems="center" columnGap={isNative ? 'sm' : 1}>
          {isNative ? (
            <Text size="title" weight="semibold" color={ACCENT}>
              {model.tab}
            </Text>
          ) : (
            <Text bold color={ACCENT}>
              {model.tab}
            </Text>
          )}
```

In `plugins/dforge/hooks/cockpit/settings-view.tsx`, replace:

```tsx
        {model.rows.map(drawRow)}
      </Box>
      {model.problems.map((problem, index) => (
        <Text key={`set-problem-${index}`} color="yellow">
          ⚠ {problem}
        </Text>
      ))}
      <Box key="settings-actions" flexDirection="row" flexWrap="wrap" columnGap={1}>
```

with:

```tsx
        {model.rows.map(isNative ? drawNativeRow : drawRow)}
      </Box>
      {model.problems.map((problem, index) => (
        <Text key={`set-problem-${index}`} color="yellow">
          ⚠ {problem}
        </Text>
      ))}
      <Box key="settings-actions" flexDirection="row" flexWrap="wrap" columnGap={isNative ? 'sm' : 1} rowGap={isNative ? 'sm' : undefined}>
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
      const row = (key: string, label: string, ...controls: RenderChildren[]) => (
        <Box key={key} flexDirection="row" columnGap={1}>
          <Box key={`${key}-label`} width={16} flexShrink={0}>
            <Text>{label}</Text>
          </Box>
          <Box key={`${key}-controls`} flexDirection="row" flexWrap="wrap" alignItems="center" columnGap={1} flexShrink={1}>
            {controls}
          </Box>
        </Box>
      )
      const chips = (key: string, names: readonly string[], isOn: (name: string) => boolean, label: (name: string) => string, onPress: (name: string) => unknown) => (
        <Box key={key} flexDirection="row" flexWrap="wrap" columnGap={1} paddingLeft={INDENT}>
```

with:

```tsx
      // The desktop spaces these rows by its own scale, as the settings view does.
      const row = (key: string, label: string, ...controls: RenderChildren[]) => (
        <Box key={key} flexDirection="row" columnGap={isDesktop ? 'sm' : 1}>
          <Box key={`${key}-label`} width={16} flexShrink={0}>
            <Text>{label}</Text>
          </Box>
          <Box key={`${key}-controls`} flexDirection="row" flexWrap="wrap" alignItems="center" columnGap={isDesktop ? 'sm' : 1} rowGap={isDesktop ? 'xs' : undefined} flexShrink={1}>
            {controls}
          </Box>
        </Box>
      )
      const chips = (key: string, names: readonly string[], isOn: (name: string) => boolean, label: (name: string) => string, onPress: (name: string) => unknown) => (
        <Box key={key} flexDirection="row" flexWrap="wrap" columnGap={isDesktop ? 'xs' : 1} rowGap={isDesktop ? 'xs' : undefined} paddingLeft={isDesktop ? undefined : INDENT}>
```

- [ ] **Step 4: Update the README**

In `plugins/dforge/README.md`, replace:

```markdown
the setting to `~/.dforge/config.json`, and the pane redraws with it. **Back** (`b`)
returns to the cockpit.
```

with:

```markdown
the setting to `~/.dforge/config.json`, and the pane redraws with it. **Back** (`b`)
returns to the cockpit. In the desktop app each switch and choice is a
dropdown, and each number and text setting an open field that saves when you
submit it (a number keeps its `−` and `+` steps); an entry out of range shows
why below its field.
```

In `plugins/dforge/README.md`, replace:

```markdown
In the settings view a switch reads
```

with:

```markdown
In the terminal's settings view a switch reads
```

- [ ] **Step 5: Run the suite to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: PASS — `0 fail` (on main 67b40b8 the count reads `227 pass`; a different count is fine if nothing fails).

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/README.md plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/hooks/cockpit/settings-view.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): use desktop controls in settings"
```

---

### Task 8: Add the agent state groups

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/lib.ts` (after `collapsedToggled`)
- Test: `plugins/dforge/tests/cockpit.test.ts` (the lib import list, the `cockpit pane` describe)

**Interfaces:**
- Consumes: C1 (its edit anchors below `collapsedToggled`)
- Produces: C6

**Items:** 5

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  accountKey,
```

with:

```ts
  accountKey,
  agentGroups,
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  test('shows the context, limits, cost and repo', async ($, on) => {
```

with:

```ts
  test('groups agents in order, an ended record without an outcome done', () => {
    const one = (agentId: string, isDone: boolean, outcome?: 'done' | 'failed' | null) => ({ agentId, isDone, outcome })
    const keys = (spawns: ReturnType<typeof one>[], waiting: string[]) => agentGroups(spawns, waiting).map(group => [group.key, group.name, group.spawns.map(spawn => spawn.agentId)])
    expect(keys([one('a', false, null), one('b', false, null), one('c', true, 'failed'), one('d', true)], ['a'])).toEqual([
      ['waiting', 'Waiting on you', ['a']],
      ['working', 'Working', ['b']],
      ['failed', 'Failed', ['c']],
      ['done', 'Done', ['d']],
    ])
    // A wait left open on an ended agent never keeps it waiting.
    expect(keys([one('a', true, 'done')], ['a'])).toEqual([['done', 'Done', ['a']]])
    // The ended ones take only the rows the running ones leave.
    const many = ['r1', 'r2', 'r3', 'r4', 'r5', 'r6'].map(id => one(id, false, null))
    expect(keys([one('old', true, 'done'), ...many], [])).toEqual([['working', 'Working', ['r1', 'r2', 'r3', 'r4', 'r5', 'r6']]])
    expect(keys([one('d1', true, 'done'), one('d2', true, 'failed'), one('d3', true, 'done'), one('r', false, null)], []).map(group => group[2])).toEqual([['r'], ['d2'], ['d1', 'd3']])
    expect(agentGroups([one('d1', true, 'done'), one('d2', true, 'done'), one('r', false, null)], [], 2).map(group => group.spawns.map(spawn => spawn.agentId))).toEqual([['r'], ['d2']])
  })

  test('shows the context, limits, cost and repo', async ($, on) => {
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: FAIL — the file does not load: `Export named 'agentGroups' not found in module '…/hooks/cockpit/lib.ts'`.

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/hooks/cockpit/lib.ts`, replace:

```ts
/** 465000 → "465k"; 1234567 → "1.2M". */
```

with:

```ts
export type AgentGroupKey = 'waiting' | 'working' | 'failed' | 'done'
const AGENT_GROUPS: readonly { key: AgentGroupKey; name: string }[] = [
  { key: 'waiting', name: 'Waiting on you' },
  { key: 'working', name: 'Working' },
  { key: 'failed', name: 'Failed' },
  { key: 'done', name: 'Done' },
]

/**
 * The Agents section's groups in order, each left out while empty: the
 * running agents an open approval names, the other running ones, then the
 * recent ended ones (up to `shown` rows with the running) as failed or done.
 * A record without an outcome that ended reads as done.
 */
export function agentGroups<T extends { agentId: string; isDone: boolean; outcome?: 'done' | 'failed' | null }>(
  spawns: readonly T[],
  waiting: readonly string[],
  shown = 6,
): { key: AgentGroupKey; name: string; spawns: T[] }[] {
  const running = spawns.filter(one => !one.isDone)
  const room = Math.max(0, shown - running.length)
  // slice(-0) would keep every ended agent.
  const ended = room === 0 ? [] : spawns.filter(one => one.isDone).slice(-room)
  const members: Record<AgentGroupKey, T[]> = {
    waiting: running.filter(one => waiting.includes(one.agentId)),
    working: running.filter(one => !waiting.includes(one.agentId)),
    failed: ended.filter(one => one.outcome === 'failed'),
    done: ended.filter(one => one.outcome !== 'failed'),
  }
  return AGENT_GROUPS.map(group => ({ ...group, spawns: members[group.key] })).filter(group => group.spawns.length > 0)
}

/** 465000 → "465k"; 1234567 → "1.2M". */
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: PASS — `0 fail` (on main 67b40b8 the count reads `228 pass`; a different count is fine if nothing fails).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): add agent state groups"
```

---

### Task 9: List agents by state

**Files:**
- Modify: `plugins/dforge/types/index.d.ts` (`CockpitSpawn`)
- Modify: `plugins/dforge/hooks/cockpit/register.tsx` (the lib imports, `agent.spawn`, `tool.check`, the subagent `turn.complete`, the asking `tool.call` wait, the Agents card and panel, `AGENT_MARKS`, `S.waits`, `startWait`)
- Modify: `plugins/dforge/README.md` (the **Agents** bullet)
- Test: `plugins/dforge/tests/cockpit.test.ts` (`World`, `world`'s `agent.spawn`, the `cockpit pane` describe)

**Interfaces:**
- Consumes: C6, C8
- Produces: C7

**Items:** 5

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  primary?: string
```

with:

```ts
  primary?: string
  /** The agent ids the spawns get, in turn; `agent-1` once they run out. */
  agentIds?: string[]
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'agent-1' }))
```

with:

```ts
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: w.agentIds?.shift() ?? 'agent-1' }))
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
    expect(agentGroups([one('d1', true, 'done'), one('d2', true, 'done'), one('r', false, null)], [], 2).map(group => group.spawns.map(spawn => spawn.agentId))).toEqual([['r'], ['d2']])
  })
```

with:

```ts
    expect(agentGroups([one('d1', true, 'done'), one('d2', true, 'done'), one('r', false, null)], [], 2).map(group => group.spawns.map(spawn => spawn.agentId))).toEqual([['r'], ['d2']])
  })

  test('lists subagents waiting on you, working, failed and done', async ($, on) => {
    world(on, { tokens: 50_000, agentIds: ['agent-1', 'agent-2', 'agent-3', 'agent-4'] })
    on('tool.check', () => ({ decision: 'ask' }))
    await $.session.start(START)
    await $.turn.start({ text: 'go', turnId: 't1' })
    for (const n of [1, 2, 3, 4]) {
      await $.agent.spawn({ tool_use_id: `toolu_${n}`, prompt: 'Implement', description: `Task ${n}`, subagentType: 'dforge:impl-sonnet-low', provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: false, fork: false })
    }
    await $.turn.complete({ answer: '', durationMs: 1000, isAborted: false, turnId: 'turn-3', agentId: 'agent-3', reason: 'error' })
    await $.turn.complete({ answer: 'done', durationMs: 1000, isAborted: false, turnId: 'turn-4', agentId: 'agent-4', reason: 'answer' })
    // Task 1's subagent asks to run a command; Task 2's keeps working.
    await $.tool.check({ tool: 'Bash', input: { command: 'rm -rf build' }, tool_use_id: 'toolu_9', agentId: 'agent-1' })
    const order = async (ui: { findAll: (query: { type: string }) => Promise<{ text: string }[]> }, surface: string, patterns: RegExp[]) => {
      const texts = surface === 'desktop' ? await boxTexts(ui) : (await ui.findAll({ type: 'Text' })).map(one => one.text)
      return patterns.map(pattern => texts.findIndex(text => pattern.test(text)))
    }
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...PANE, surface })
      const at = await order(ui, surface, [
        /^Waiting on you · 1$/, /^⏳ +impl-sonnet-low +Task 1/,
        /^Working · 1$/, /^● +impl-sonnet-low +Task 2/,
        /^Failed · 1$/, /^✗ +impl-sonnet-low +Task 3/,
        /^Done · 1$/, /^✓ +impl-sonnet-low +Task 4/,
      ])
      expect(at.every(index => index >= 0)).toBe(true)
      expect([...at].sort((a, b) => a - b)).toEqual(at)
      await ui.unmount()
    }
    // The approval is given: the call runs, and Task 1's subagent is working again.
    await $.tool.call({ tool: 'Bash', command: 'rm -rf build', tool_use_id: 'toolu_9', agentId: 'agent-1' } as never)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await order(ui, 'terminal', [/^Waiting on you/, /^Working · 2$/])).toEqual([-1, expect.any(Number)])
    expect((await order(ui, 'terminal', [/^Working · 2$/]))[0]).toBeGreaterThan(-1)
  })
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: FAIL — 1 test fails: `cockpit pane > lists subagents waiting on you, working, failed and done`.

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/types/index.d.ts`, replace:

```ts
  isDone: boolean
```

with:

```ts
  isDone: boolean
  /** How it ended: null while it runs, `failed` for an aborted, refused or failed end; absent on a record saved before it was kept. */
  outcome: 'done' | 'failed' | null
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
  autoRunFor,
```

with:

```tsx
  autoRunFor,
  agentGroups,
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
import type { BandInput, Run, Section, TrackPart } from './lib'
```

with:

```tsx
import type { AgentGroupKey, BandInput, Run, Section, TrackPart } from './lib'
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
      isDone: false,
```

with:

```tsx
      isDone: false,
      outcome: null,
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
      fields: [...(seat === null ? [] : [{ name: 'Agent', value: shortSeat(seat) }]), ...(await turnFields($)).slice(0, 1)],
    })
```

with:

```tsx
      fields: [...(seat === null ? [] : [{ name: 'Agent', value: shortSeat(seat) }]), ...(await turnFields($)).slice(0, 1)],
    }, e.agentId ?? null)
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
    await update($, spawns, all => all.map(one => (one.agentId === agentId ? { ...one, isDone: true } : one)))
```

with:

```tsx
    const outcome = e.reason === 'answer' ? 'done' : 'failed'
    await update($, spawns, all => all.map(one => (one.agentId === agentId ? { ...one, isDone: true, outcome } : one)))
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
        fields: (await turnFields($)).slice(0, 1),
      })
```

with:

```tsx
        fields: (await turnFields($)).slice(0, 1),
      }, null)
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
    const recent = [...running, ...finished.slice(-Math.max(0, 6 - running.length))]
```

with:

```tsx
    const groups = agentGroups(all, [...S.waits.values()].flatMap(wait => (wait.agentId === null ? [] : [wait.agentId])))
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
        recent.map(spawn => (
          <Text key={`spawn-${spawn.agentId}`} wrap="truncate-end">
            <Text color={spawn.isDone ? 'green' : 'cyan'}>{spawn.isDone ? '✓' : '●'} </Text>
            <Text bold={!spawn.isDone} dimColor={spawn.isDone}>
              {shortSeat(spawn.seat)}
            </Text>
            <Text dimColor={spawn.isDone}> {spawn.description}</Text>
            {!spawn.isDone && <Text color="cyan"> {elapsed(now - spawn.startedAt)}</Text>}
          </Text>
        )),
```

with:

```tsx
        groups.flatMap(group => [
          <Text key={`agents-${group.key}`} color={AGENT_MARKS[group.key].color} bold>
            {`${group.name} · ${group.spawns.length}`}
          </Text>,
          ...group.spawns.map(spawn => (
            <Text key={`spawn-${spawn.agentId}`} wrap="truncate-end">
              <Text color={AGENT_MARKS[group.key].color}>{AGENT_MARKS[group.key].mark} </Text>
              <Text bold={!spawn.isDone} dimColor={spawn.isDone}>
                {shortSeat(spawn.seat)}
              </Text>
              <Text dimColor={spawn.isDone}> {spawn.description}</Text>
              {!spawn.isDone && <Text color="cyan"> {elapsed(now - spawn.startedAt)}</Text>}
            </Text>
          )),
        ]),
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
            ...recent.map(
              (spawn): PanelLine => ({
                kind: 'text',
                left: [
                  { text: spawn.isDone ? '✓  ' : '●  ', color: spawn.isDone ? undefined : 'green', faint: spawn.isDone },
                  pill(shortSeat(spawn.seat)),
                  { text: `  ${spawn.description}`, dim: spawn.isDone },
                ],
                right: spawn.isDone ? [] : [{ text: elapsed(now - spawn.startedAt), mono: true, dim: true }],
              }),
            ),
```

with:

```tsx
            ...groups.flatMap((group): PanelLine[] => [
              { kind: 'text', small: true, left: [{ text: `${group.name} · ${group.spawns.length}`, color: AGENT_MARKS[group.key].color, bold: true }] },
              ...group.spawns.map(
                (spawn): PanelLine => ({
                  kind: 'text',
                  left: [
                    { text: `${AGENT_MARKS[group.key].mark}  `, color: AGENT_MARKS[group.key].color },
                    pill(shortSeat(spawn.seat)),
                    { text: `  ${spawn.description}`, dim: spawn.isDone },
                  ],
                  right: spawn.isDone ? [] : [{ text: elapsed(now - spawn.startedAt), mono: true, dim: true }],
                }),
              ),
            ]),
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
/** The minimized cockpit's band, drawn in the pane or above the prompt. */
```

with:

```tsx
// Each Agents group's mark and color, on its title and its rows.
const AGENT_MARKS: Record<AgentGroupKey, { mark: string; color: string }> = {
  waiting: { mark: '⏳', color: 'yellow' },
  working: { mark: '●', color: 'cyan' },
  failed: { mark: '✗', color: 'red' },
  done: { mark: '✓', color: 'green' },
}

/** The minimized cockpit's band, drawn in the pane or above the prompt. */
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
  waits: new Map<string, { timer: Timer | null; messageId: string | null; event: NotifyEvent }>(),
```

with:

```tsx
  // Each open wait on the person, by tool call; `agentId` names the subagent whose approval it is.
  waits: new Map<string, { timer: Timer | null; messageId: string | null; event: NotifyEvent; agentId: string | null }>(),
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
async function startWait($: EngineInterface, id: string, kind: 'waiting' | 'asking', event: NotifyEvent) {
```

with:

```tsx
async function startWait($: EngineInterface, id: string, kind: 'waiting' | 'asking', event: NotifyEvent, agentId: string | null) {
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```tsx
  S.waits.set(id, { timer: delay === 0 ? null : $.clock.after(delay, () => void send()), messageId: null, event })
```

with:

```tsx
  S.waits.set(id, { timer: delay === 0 ? null : $.clock.after(delay, () => void send()), messageId: null, event, agentId })
```

- [ ] **Step 4: Update the README**

In `plugins/dforge/README.md`, replace:

```markdown
- **Agents** lists the subagents running, each timed to the second, and those
  recently finished, then each subagent type (seat) with its runs, input
  tokens, the share served from the prompt cache and output tokens. Use it to see where a plan's tokens go.
```

with:

```markdown
- **Agents** lists the subagents in four groups, each with its count and left
  out while empty: **Waiting on you** (a subagent with an approval open),
  **Working**, **Failed** (it ended aborted, refused or with an error) and
  **Done** (recently finished). Running ones are timed to the second. Then
  each subagent type (seat) with its runs, input tokens, the share served from
  the prompt cache and output tokens. Use it to see where a plan's tokens go.
```

- [ ] **Step 5: Run the suite to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: PASS — `0 fail` (on main 67b40b8 the count reads `229 pass`; a different count is fine if nothing fails).

- [ ] **Step 6: Run the full validation**

Run each command on its own line from the worktree root:

```bash
env -u CLAUDE_CONFIG_DIR timeout 300 node scripts/validate-repository.mjs
env -u CLAUDE_CONFIG_DIR timeout --kill-after=10s 690s node scripts/test-all.mjs
timeout 120 /root/.local/bin/claude plugin validate .
timeout 120 /root/.local/bin/claude plugin validate plugins/dforge
timeout 120 /root/.local/bin/claude plugin validate plugins/dr-status
timeout 120 /root/.local/bin/claude plugin validate plugins/darkraise-ui
timeout 120 /root/.local/bin/claude plugin validate plugins/darkraise-win32ui
env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge
```

Expected: the validator prints `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`; `test-all.mjs` reports every suite passing; each `plugin validate` prints `✔ Validation passed`; `plugin test` reports `0 fail`. A failure is a stop: report it with its output.

- [ ] **Step 7: Commit**

```bash
git add plugins/dforge/README.md plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts plugins/dforge/types/index.d.ts
git commit -m "feat(cockpit): list agents by state"
```

