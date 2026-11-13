# dflow HUD Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redraw the dflow HUD mod in the dforge cockpit's design: framed colored cards (Account, Plan, Context with its breakdown, Usage, Checks, Board, Workers, Repo), a framed two-line band, buttons with hotkeys, collapsing, a dense layout, a Sections view and a resumable-work offer.

**Architecture:** Pure `.mjs` modules under `plugins/dflow/hooks/hud/` turn plain values into card models made of runs (`{ text, color?, bold?, dim?, underline? }`); `register.tsx` reads the engine and the files into atoms on the poll, and its render hooks only map models to Box/Text/Button. Helpers come from the cockpit's `plugins/dforge/hooks/cockpit/lib.ts`, copied and adapted, since plugins never import each other.

**Tech Stack:** Claude Code mod API (`claude-code`, `claude-code/testing`), TSX for the mod, plain ES modules for the pure code, `node:test` for the Node suite.

**Spec:** `docs/dforge/specs/2026-11-13-dflow-hud-overhaul-design.md`

**Execution:** inline — `claude --model opus --effort high` — the highest self-implemented total is 6 (impl-opus-high)

**Parallelism:** sequential — inline execution

**Task check:** `timeout 300 node --test plugins/dflow/tests/*.test.mjs && timeout 120 /root/.local/bin/claude plugin test plugins/dflow` — impact selection: every task changes only `plugins/dflow`, and its two suites ran in 19 s and under 1 s on 2026-11-13

**Integration check:** `timeout 1500 node scripts/test-all.mjs --jobs 6 && timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate . && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge && timeout 60 /root/.local/bin/claude plugin validate plugins/dflow`

**CI:** `.github/workflows/validate.yml .github/workflows/release.yml` — platforms: uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/validate-repository.mjs`; `node scripts/test-all.mjs`; `claude plugin validate .`; `claude plugin validate plugins/dflow`; `claude plugin test plugins/dflow`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: uutils (ubuntu-latest), Windows Git Bash

**Plan review:** 2026-11-13 — dforge:judge-opus — executability 8 / coherence 11 / coverage 11 / assumptions 13 (round 1)

## Global Constraints

- The HUD is a view: no read or draw failure reaches the engine; every hook body that reads or writes is wrapped as today's `refresh` is.
- The render hooks (`ui.render` for `AbovePrompt` and `Pane`) do no file, process or network call: they read atoms only (spec OP-5).
- The context governor keeps working in every mode, `off` included: the per-session context file (`contextFile(sessionId)`) and the reset-and-resume after `dflow done` behave exactly as before this plan.
- The HUD draws only in a checkout whose git root holds `.dflow`; elsewhere the band calls `next(e)` and the pane shows `dflow has no state in this repository yet.` and `Run /dflow:init, then /dflow:plan.` dim.
- The pane opens as `{ id: 'dflow-hud', title: 'dflow', columns: 56 }`.
- Widths are counted in terminal cells with `cellWidth` (an emoji or CJK character counts two); a row that does not fit is cut with `runsCut` and ends in `…`; every pane `Text` sets `wrap="truncate-end"`.
- Colors: Account the account color, Plan `yellow`, Context `cyan`, Usage `blue`, Checks `red`, Board `white`, Workers `magenta`, Repo `green`; the ramp `success` (<50%), `warning` (<75%), `#ff8700` (<90%), `error`; button frames `inactive` at rest and `permission` (the accent) on the main button; breakdown colors `cyan, magenta, yellow, green, blue, red` in that order.
- Copy is fixed by the spec's design and contract sections; a string in a task's test is the exact string to draw.
- `hud.json` task states are `todo`, `wip`, `done`, `review` and `blocked`; a current task in `todo` reads `ready`, in `wip` reads `in progress`; a `review` task counts as done (`✓`).
- The mod must pass `claude plugin test plugins/dflow` on Claude Code 2.1.306 (CI pins it) and 2.1.323 (this host); use only engine calls the dforge cockpit already uses.
- Never import from `plugins/dforge`; copy and adapt. Keep the cockpit's names where the spec does not rename them.
- Stage only the paths a task's **Files:** block names. `register.tsx`, `register.test.tsx`, `view.mjs`, `tests/hud.test.mjs`, `plugins/dflow/README.md` and `docs/dflow/design.md` carried the owner's uncommitted changes when the run started; their hunks go into the first task commit that touches each file, and that commit's body says so. Never stage any other dirty path.
- Windows Git Bash: a native program given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset) — convert the path with `cygpath -m` before the call, and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
- Windows Git Bash: the same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches — normalise both sides with `cygpath -m`, or compare with `-ef`.
- Windows Git Bash: files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep — pipe through `tr -d '\r'` before comparing or parsing (in `repoFromPorcelain`, split on `/\r?\n/`).
- Windows Git Bash: `awk -v name=value` processes backslash escapes in the value — pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails — import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): a lock built on `mkdir` failing when the directory exists does not exclude a second process — create the lock file with `set -C` (noclobber), or use `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started, so the command's children keep running — run the command in its own process group (`setsid`) and signal the group.

## Contracts

**Runs and cards** (all pure modules):
- `Run = { text: string, color?: string, bold?: boolean, dim?: boolean, underline?: boolean }`; a run carries only the keys that apply (no `undefined` values), so tests compare with `deepStrictEqual`.
- `Card = { key: SectionKey, title: string, color: string, headline: Run[], rows: Run[][] }`; each row's text is exactly what the tests pin; a sub-row that belongs to the row above it (a task's `verify failed` or `blocked:` line, an Account detail line, a breakdown category, a limit's reset line) starts with its indent spaces as the tests show.
- `SectionKey = 'account' | 'plan' | 'context' | 'usage' | 'checks' | 'board' | 'workers' | 'repo'`.

**`plugins/dflow/hooks/hud/meter.mjs`** (Task 2): `kTokens(n)`, `duration(ms)`, `rampColor(percent)`, `limitLabel(kind)`, `bar(share, width)`, `track(share, width, marks)` → `{ text, kind: 'fill'|'empty'|'mark', mark? }[]`, `trackRuns(parts, color, markColors)` → `Run[]` (fill `{ text, color }`, empty `{ text, dim: true }`, mark `{ text, color: markColors[mark] ?? color, bold: true }`), `sparkline(values)`, `stackedRuns(values, width)`, `windowElapsed(kind, resetsAt, now)`, `limitForecast(kind, percent, resetsAt, now)`, `cellWidth(text)`, `runsWidth(runs)`, `runsCut(runs, width)`, `isAtLeast(version, least)` — each the cockpit's function of the same name in `plugins/dforge/hooks/cockpit/lib.ts` except `trackRuns`.

**`plugins/dflow/hooks/hud/view.mjs`** (kept: `MODES`, `RESET_FRESH_MS`, `RESET_INSTRUCTIONS`, `nextMode`, `isFreshReset`, `isResetFor`, `contextFile`; removed in Task 4 and Task 10: `tokens`, `bar`, `bandText`, `paneRows`):
- Task 3: `SECTIONS` (the eight keys in pane order), `nowRow(hud)` → `Run[]`, `taskWindow(tasks, currentNumber, size)` → `{ above, aboveDone, rows, below, belowDone }`, `planCard(hud, width = 50)`, `checksCard(hud)`, `boardCard(hud)`, `workersCard(hud)` → `Card | null`, `nextRow(hud)` → `Run[]`, `collapsedFrom(value)` → `SectionKey[]`.
- Task 5: `contextCard({ hud, context, breakdown, readings, width })` → `Card | null`, where `context = { tokens?, window }`, `breakdown = { rows: { name, tokens }[], compactAt: number | null, total: number | null } | null`, `readings: number[]`.
- Task 6: `accountCard({ account, engine, remote })` → `Card`.
- Task 7: `usageCard({ usage, now, width })` → `Card | null`, where `usage = { limits: { kind, percent, resetsAt: number | null }[], usd: number | null, startedAt: number } | null`.
- Task 8: `repoCard({ repo, where })` → `Card`, where `where = { cwd, root, home, remote }`.
- Task 9: `denseLines(input, width)` → `Run[][]`, `input = { hud, account, remote, context, usage, now, repo, where, shown }`.
- Task 11: `sectionsFrom(value)`, `sectionsArg(text)` → `SectionKey[] | null`, `sectionsToggled(list, key)`, `sectionsMoved(list, key, delta)`.
- Task 12: `resumeOffer(hud)` → `{ title, next } | null`, `isOfferOver(start, hud)` → boolean.

**`plugins/dflow/hooks/hud/account.mjs`** (Task 6): `accountKey(configDir, home)`, `accountColor(key)`, `billingLabel(billing)`, `modelName(id)`, `deviceName(surface)`, `remoteRuns(clients, setting)`, `accountFrom(claudeJson, configDir, home)` → `{ email, name, organization, role, billing, key, color }`.

**`plugins/dflow/hooks/hud/repo.mjs`** (Task 8): `repoFromPorcelain(text)` → `{ branch, ahead, behind, changed, untracked } | null`, `repoName(remote, root)`, `shortDir(cwd, home)`.

**`plugins/dflow/hooks/hud/band.mjs`** (Task 10): `BAND_TIERS`, `bandLines(input, tier)` → `[Run[], Run[]]`, `fitBand(input, width)` → `[Run[], Run[]]`, `bandWarning(hud)` → `Run[]`, `bandTop(input)` → `Run[]`; `input = { hud, where, repo, engine, account, remote, context, usage, now }`.

**Drawing helpers** (`register.tsx`): `drawButton(table, key, label, onPress, look)` with `look = { hotkey?: string, isMain?: boolean, isOff?: boolean, isCompact?: boolean }` (Task 1): `isMain` puts the frame in `permission`, `isOff` dims the label, `isCompact` drops the rounded Box and draws the Button on one line with the same underlined letter and hidden twin; `drawCard(table, card, isCollapsed, onToggle, extra?)` (Task 4): `extra` is a list of elements (buttons) drawn after the rows, also when the card is collapsed.

**Element keys** (`register.tsx`, read by the tests): card Box `<key>`, title Button `<key>-title`, headline Text `<key>-headline`, row Text `<key>-row-<i>`; buttons `pane-minimize`, `pane-density`, `pane-sections`, `context-compact`, `band-expand`, `resume-go`, `resume-dismiss`, `band-resume-go`, `band-resume-dismiss`, `sections-<key>-switch`, `sections-<key>-up`, `sections-<key>-down`, `sections-reset`, `sections-back`; a boxed button's frame Box `<button key>-box` and its hidden hotkey twin `<button key>-hotkey`; the Now row Text `now`, the Next row Text `next`, dense lines `dense-<SectionKey>` (for example `dense-usage`) and `dense-next`, band rows `band-top`, `band-line-0`, `band-line-1`, `band-warning`.

**Store keys** (mod store): `mode` (`band`|`pane`|`off`), `density` (`detailed`|`dense`), `collapsed` (`SectionKey[]`), `sections` (`SectionKey[]`).

**Test fixture** `world(on, w)` in `plugins/dflow/hooks/hud/register.test.tsx` (Task 1), with `HUD`, `HUD_FILE`, `START`, `TURN`, `BAND`, `PANE` constants; later tasks pass more `World` fields.

## Assumptions (evidence)

- `hud.json` already carries `plan.approved`, `plan.tasks` (number, title, state, run), `checks` and `workers` (task, path, branch, base): `plugins/dflow/lib/status.mjs:72-85` and `plugins/dflow/lib/commands/parallel.mjs:93`, read 2026-11-13. The CLI does not change.
- `$.session.usage()` returns `rateLimits` (`kind`, `percentUsed`, `resetsAt` ISO) and `cost`, and with `{ breakdown: 'summary' }` a local `context.breakdown` (`categories`, `totalTokens`, `isAutoCompactEnabled`, `autoCompactThreshold`): `SessionUsage` in `plugins/dflow/.claude-plugin/types/claude-code/index.d.ts` and `plugins/dforge/hooks/cockpit/register.tsx:3786-3801`, read 2026-11-13.
- The harness offers `mock.clock(on, { now })` with `advance(ms)`, `mock.env(on, vars)`, `ui.press({ key })`, `ui.find({ key | type | text })` and `ui.findAll`: `claude-code/testing` types and `plugins/dforge/tests/cockpit.test.ts`, read 2026-11-13.
- Button hotkeys and the underlined label behave on 2.1.323 as on the cockpit's 2.1.299-2.1.306: unverified — Task 1 verifies it.
- The owner chose in-place work with their uncommitted changes present (spec `## Decisions`), so the four dirty HUD files' existing hunks ride in this plan's commits (Global Constraints).

## Task index

1. Buttons and the mode flow
2. Meter and text helpers
3. Card models for the plan, checks, board and workers
4. The framed pane with collapsible cards
5. The Context card with its breakdown and Compact
6. The Account card
7. The Usage card
8. The Repo card and the git reading
9. The dense layout and saved preferences
10. The framed band
11. The Sections view
12. Resumable work
13. Documentation
14. Proof of the HUD in a nested session

---

### Task 1: Buttons and the mode flow

**Files:**
- Modify: `plugins/dflow/hooks/hud/register.tsx` (the `command.run` hook, `setMode`, the `Pane` render hook)
- Test: `plugins/dflow/hooks/hud/register.test.tsx`

**Interfaces:**
- Consumes: none
- Produces: the `drawButton` helper and the `world` fixture (Contracts: Element keys, Test fixture)

**UI/UX:** UI-11, UX-1, UX-5

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Replace the file's `engine` function and its call sites with this fixture, and add the three tests below. The four existing tests keep their assertions, calling `world(on, { files })` (or `{ files: {}, hasState: false }`) and reading `w.calls` and `w.stored` where they read `calls` and `stored`, with two changes the fixture's recording of git calls needs: in `the band shows the plan, progress, task and context`, `expect(calls[0]).toBe(...)` becomes `expect(w.calls).toContain(...)` with the same string; in `with no dflow directory the mod draws nothing and writes nothing`, `expect(calls.length).toBe(0)` becomes `expect(w.calls.filter(call => call.startsWith('write'))).toEqual([])`.

```tsx
import { expect, mock, test } from 'claude-code/testing'

const HUD_FILE = '/repo/.dflow/hud.json'
const NOW = Date.parse('2026-11-12T12:00:00.000Z')

type World = {
  files: Record<string, string>
  hasState?: boolean
  tokens?: number
  window?: number
  rateLimits?: { kind: string; percentUsed: number; resetsAt?: string }[]
  usd?: number
  startedAt?: number
  breakdown?: unknown
  porcelain?: string
  remoteUrl?: string | null
  env?: Record<string, string>
  settings?: Record<string, unknown>
  model?: string
  version?: string
  isPaneUp?: boolean
  sessionId?: string
  remoteControl?: string
  compactFailures?: number
  calls: string[]
  stored: Record<string, unknown>
  clock?: { advance: (ms: number) => Promise<void> }
}

// The engine beneath the mod: every call the HUD makes is recorded in w.calls.
function world(on: any, given: Partial<World> & { files: Record<string, string> }): World {
  const w: World = { calls: [], stored: {}, ...given }
  w.clock = mock.clock(on, { now: NOW })
  // The host's CLAUDE_CONFIG_DIR must not reach the mod: it would move the account file.
  mock.env(on, { HOME: '/home/me', CLAUDE_CONFIG_DIR: '', ...(w.env ?? {}) })
  on('session.start', (_: unknown, e: any) => ({ cwd: e.cwd }))
  on('turn.complete', (_: unknown, e: any) => ({ text: e.answer }))
  on('process.run', (_: unknown, e: any) => {
    const argv = e.argv.join(' ')
    w.calls.push(argv)
    if (argv.includes('rev-parse')) return { value: { exitCode: 0, stdout: '/repo\n', stderr: '' } }
    if (argv.includes('status')) return { value: { exitCode: w.porcelain === undefined ? 1 : 0, stdout: w.porcelain ?? '', stderr: '' } }
    if (argv.includes('get-url')) return { value: { exitCode: w.remoteUrl ? 0 : 2, stdout: `${w.remoteUrl ?? ''}\n`, stderr: '' } }
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })
  on('session.id', () => ({ value: w.sessionId ?? 's1' }))
  on('session.usage', (_: unknown, e: any) => {
    w.calls.push(e?.breakdown ? 'usage breakdown' : 'usage')
    return {
      value: {
        startedAt: w.startedAt ?? NOW - 2 * 3_600_000,
        context: { tokens: w.tokens ?? 118000, window: w.window ?? 1000000, ...(e?.breakdown && w.breakdown ? { breakdown: w.breakdown } : {}) },
        rateLimits: w.rateLimits ?? [],
        ...(w.usd === undefined ? {} : { cost: { usd: w.usd } }),
      },
    }
  })
  on('session.model', () => ({ value: w.model ?? 'claude-opus-5-5' }))
  on('session.version', () => ({ value: { version: w.version ?? '2.1.323', base: w.version ?? '2.1.323' } }))
  on('settings.read', () => ({ value: w.settings ?? {} }))
  on('config.list', () => ({ value: w.remoteControl === undefined ? [] : [{ key: 'remoteControl', label: 'Remote Control', kind: 'choice', value: w.remoteControl, provider: { kind: 'engine' }, isLocked: false }] }))
  on('fs.exists', (_: unknown, e: any) => {
    w.calls.push(`exists ${e.path}`)
    return { value: (w.hasState ?? true) && (e.path === '/repo/.dflow' || e.path in w.files) }
  })
  on('fs.read', (_: unknown, e: any) => {
    w.calls.push(`read ${e.path}`)
    if (!(e.path in w.files)) throw new Error('ENOENT')
    return { value: w.files[e.path] }
  })
  on('fs.write', (_: unknown, e: any) => {
    w.calls.push(`write ${e.path} ${e.text}`)
    w.files[e.path] = e.text
    return { value: undefined }
  })
  on('store.get', (_: unknown, e: any) => {
    w.calls.push(`store.get ${e.key}`)
    return { value: w.stored[e.key] }
  })
  on('store.set', (_: unknown, e: any) => {
    w.stored[e.key] = e.value
    return { value: undefined }
  })
  on('ui.open', (_: unknown, e: any) => {
    w.calls.push(`open ${e.id}`)
    w.isPaneUp = true
    return { value: { isPlaced: true } }
  })
  on('ui.close', (_: unknown, e: any) => {
    w.calls.push(`close ${e.id}`)
    w.isPaneUp = false
    return { value: undefined }
  })
  on('ui.panes', () => ({ value: w.isPaneUp ? [{ id: 'dflow-hud', title: 'dflow', isShown: true, isFocused: false, isPlaced: true }] : [] }))
  on('ui.toast', (_: unknown, e: any) => {
    w.calls.push(`toast ${typeof e === 'string' ? e : e.text}`)
    return { value: undefined }
  })
  on('session.compact', (_: unknown, e: any) => {
    w.calls.push(`compact ${e.instructions ?? ''}`)
    if ((w.compactFailures ?? 0) > 0) {
      w.compactFailures = (w.compactFailures ?? 1) - 1
      throw new Error('busy')
    }
    return { messages: [] }
  })
  on('prompt.submit', (_: unknown, e: any) => {
    w.calls.push(`submit ${e.text}`)
    return { text: e.text }
  })
  on('command.run', (_: unknown, e: any) => {
    w.calls.push(`command /${e.command}`)
    return { text: '' }
  })
  return w
}
```

```tsx
test('Minimize puts the HUD in the band and closes the pane; its hotkey letter is underlined', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) } })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ key: 'pane-minimize-hotkey' }))?.props).toMatchObject({ hotkey: 'm' })
  expect((await pane.find({ type: 'Text', text: 'M' }))?.props.underline).toBe(true)
  await pane.press({ key: 'pane-minimize' })
  expect(w.stored.mode).toBe('band')
  expect(w.calls).toContain('close dflow-hud')
})

test('before Claude Code 2.1.295 the hotkey rides on the button itself', async ($, on) => {
  world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) }, version: '2.1.290' })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ key: 'pane-minimize' }))?.props).toMatchObject({ label: '▁ Minimize', hotkey: 'm' })
  expect(await pane.find({ key: 'pane-minimize-hotkey' })).toBeUndefined()
})

test('/dflow:hud reopens a pane the person closed, and a new session keeps the mode', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) } })
  await $.session.start(START)
  expect((await $.command.run({ command: 'dflow:hud', args: 'pane' })).text).toBe('dflow HUD: pane')
  w.isPaneUp = false
  expect((await $.command.run({ command: 'dflow:hud' })).text).toBe('dflow HUD: pane')
  expect(w.calls.filter(call => call === 'open dflow-hud').length).toBe(2)
  expect((await $.command.run({ command: 'dflow:hud' })).text).toBe('dflow HUD: off')
  expect(w.calls.some(call => call.startsWith('submit'))).toBe(false)
  w.stored.mode = 'pane'
  w.sessionId = 's2'
  await w.clock!.advance(2000)
  expect(w.calls.filter(call => call === 'open dflow-hud').length).toBe(3)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: FAIL — `pane-minimize-hotkey` is not found, and the cycle answers `dflow HUD: off` for a closed pane.

- [ ] **Step 3: Implement**

1. In `register.tsx`, add a module-level `drawButton(table, key, label, onPress, look: { hotkey?, isMain?, isOff?, isCompact? })` ported from the cockpit's `button` closure (`plugins/dforge/hooks/cockpit/register.tsx:842-876`): from 2.1.295 a rounded Box (`borderColor` `permission` when `isMain`, else `inactive`) holding a plain Button whose label's hotkey letter is a `<Text underline>`, plus a hidden twin `<Box display="none">` with a Button carrying `hotkey` keyed `<key>-hotkey`; before 2.1.295 the boxed Button carries `hotkey` itself and no twin; `isCompact` draws the same Button without the rounded Box (one line), still with the underlined letter and the hidden twin from 2.1.295. Read `canUnderline` in `readState` on a session-id change (never in a render hook) with `$.session.version()` and `isAtLeast(base, '2.1.295')` (inline the cockpit's `isAtLeast` from `lib.ts:1251` until Task 2 moves it to `meter.mjs`); keep it in a module variable the render hooks read.
2. In the `Pane` render hook, draw a controls row Box (`flexDirection="row" columnGap={1}`) with **▁ Minimize** (`pane-minimize`, hotkey `m`) above the existing rows. Pressing it runs `setMode($, 'band')`.
3. In the `command.run` hook: with no argument, while the stored mode is `pane` and `$.ui.panes()` has no placed `dflow-hud`, reopen the pane (`setMode($, 'pane')`) and answer `dflow HUD: pane`; otherwise cycle as before.
4. `setMode` opens the pane as `{ id: 'dflow-hud', title: 'dflow', columns: 56 }`.
5. On a session-id change in `readState`, after `loadMode`, open the pane when the mode is `pane` and it is not up.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: PASS, all tests

- [ ] **Step 5: Commit**

```bash
git add plugins/dflow/hooks/hud/register.tsx plugins/dflow/hooks/hud/register.test.tsx
git commit -m "feat(dflow): add HUD buttons and the reopen cycle" -m "Also carries the owner's uncommitted per-session context changes in these two files."
```

### Task 2: Meter and text helpers

**Files:**
- Create: `plugins/dflow/hooks/hud/meter.mjs`
- Modify: `plugins/dflow/hooks/hud/register.tsx` (import `isAtLeast`)
- Test: `plugins/dflow/tests/hud.test.mjs`

**Interfaces:**
- Consumes: none
- Produces: `meter.mjs` (Contracts)

**UI/UX:** UI-5, UI-6, UI-14

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 1 - coupling 2 - risk 0 = 4

- [ ] **Step 1: Write the failing test**

Add to `plugins/dflow/tests/hud.test.mjs`:

```js
import { bar as meterBar, cellWidth, duration, isAtLeast, kTokens, limitForecast, limitLabel, rampColor, runsCut, sparkline, stackedRuns, track, trackRuns, windowElapsed } from '../hooks/hud/meter.mjs';

const H = 3_600_000;

test('meter text, colors and labels', () => {
  assert.deepEqual([kTokens(118000), kTokens(999_499), kTokens(999_500), kTokens(967_000)], ['118k', '999k', '1.0M', '967k']);
  assert.deepEqual([duration(59_000), duration(12 * 60_000), duration(220 * 60_000), duration((2 * 1440 + 4 * 60) * 60_000)], ['', '12m', '3h40m', '2d4h']);
  assert.deepEqual([rampColor(49), rampColor(50), rampColor(75), rampColor(90)], ['success', 'warning', '#ff8700', 'error']);
  assert.deepEqual([limitLabel('five_hour'), limitLabel('seven_day'), limitLabel('spend_limit')], ['5h', '7d', 'spend']);
  assert.deepEqual([isAtLeast('2.1.323', '2.1.295'), isAtLeast('2.1.290', '2.1.295'), isAtLeast(undefined, '2.1.295')], [true, false, false]);
});

test('a meter fills to its share and each mark lands on its cell', () => {
  const parts = track(0.118, 40, [{ at: 0.15, glyph: '┃', name: 'reset' }, { at: 0.967, glyph: '┊', name: 'compact' }]);
  const cells = [...parts.map(part => part.text).join('')];
  assert.equal(cells.length, 40);
  assert.equal(cells[6], '┃');
  assert.equal(cells[38], '┊');
  assert.equal(cells.filter(cell => cell === '▰').length, 5);
  assert.equal(meterBar(0.999, 10), '▰▰▰▰▰▰▰▰▰▱');
  const runs = trackRuns(parts, 'success', { reset: 'error' });
  assert.deepStrictEqual(runs.find(run => run.text === '┃'), { text: '┃', color: 'error', bold: true });
  assert.deepStrictEqual(runs.find(run => run.text === '┊'), { text: '┊', color: 'success', bold: true });
  assert.deepStrictEqual(runs[0], { text: '▰▰▰▰▰', color: 'success' });
  assert.equal(runs[1].dim, true);
});

test('sparkline, stacked runs, window share and pace', () => {
  assert.deepEqual([sparkline([100000, 118000]), sparkline([1, 2, 3]), sparkline([5, 5])], ['▁█', '▁▅█', '▄▄']);
  const runs = stackedRuns([318, 41, 9, 6, 4, 2], 50);
  assert.equal(runs.reduce((sum, run) => sum + run, 0), 50);
  assert.ok(runs.every(run => run >= 1));
  const now = 1_000_000_000_000;
  assert.equal(Math.round(windowElapsed('five_hour', now + 3.4 * H, now) * 100), 32);
  assert.equal(windowElapsed('spend_limit', now + H, now), null);
  assert.equal(limitForecast('five_hour', 23, now + (3 * H + 40 * 60_000), now), 'pace');
  assert.equal(typeof limitForecast('seven_day', 61, now + (2 * 24 + 19) * H, now), 'number');
  assert.equal(limitForecast('five_hour', 23, now + (4 * H + 55 * 60_000), now), null);
});

test('widths count terminal cells and a cut row ends in an ellipsis', () => {
  assert.deepEqual([cellWidth('🚀'), cellWidth('é'), cellWidth('Task 5')], [2, 1, 6]);
  assert.deepStrictEqual(runsCut([{ text: 'abcdef', bold: true }], 4), [{ text: 'abc', bold: true }, { text: '…', dim: true }]);
  assert.deepStrictEqual(runsCut([{ text: 'ab🚀' }], 3), [{ text: 'ab' }, { text: '…', dim: true }]);
  assert.deepStrictEqual(runsCut([{ text: 'abc' }], 3), [{ text: 'abc' }]);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 node --test plugins/dflow/tests/hud.test.mjs`
Expected: FAIL with `Cannot find module '../hooks/hud/meter.mjs'`

- [ ] **Step 3: Implement**

1. Create `meter.mjs` as plain JavaScript with no imports. Port from `plugins/dforge/hooks/cockpit/lib.ts`, dropping the types: `kTokens` (:125), `bar` (:237), `rampColor` (:245), `duration` (:252), `limitLabel` (:267), `sparkline` (:320), `track` (:336), `stackedRuns` (:357), `windowElapsed` (:383, with its `WINDOW_MS`), `limitForecast` (:891), `cellWidth` with `ZERO_CELLS`, `TWO_CELLS` and `EMOJI` (:677-696), `runsWidth` (:699), `runsCut` (:704), `isAtLeast` (:1251).
2. Add `trackRuns(parts, color, markColors)` as Contracts states. Every run object carries only the keys that apply.
3. In `register.tsx`, import `isAtLeast` from `./meter.mjs` and delete the inlined copy from Task 1.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 node --test plugins/dflow/tests/hud.test.mjs && timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dflow/hooks/hud/meter.mjs plugins/dflow/tests/hud.test.mjs plugins/dflow/hooks/hud/register.tsx
git commit -m "feat(dflow): port the cockpit's meter helpers" -m "Also carries the owner's uncommitted changes in tests/hud.test.mjs."
```

### Task 3: Card models for the plan, checks, board and workers

**Files:**
- Modify: `plugins/dflow/hooks/hud/view.mjs`
- Modify: `plugins/dflow/types/index.d.ts` (the `Hud` type)
- Test: `plugins/dflow/tests/hud.test.mjs`

**Interfaces:**
- Consumes: `meter.mjs` (Contracts)
- Produces: the Task 3 functions of `view.mjs` and the `Run` and `Card` shapes (Contracts)

**UI/UX:** UI-2, UI-4, UI-7, UI-8, UI-9, UX-6

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Add to `plugins/dflow/tests/hud.test.mjs`:

```js
import { SECTIONS, boardCard, checksCard, collapsedFrom, nextRow, nowRow, planCard, taskWindow, workersCard } from '../hooks/hud/view.mjs';

const text = runs => runs.map(run => run.text).join('');
const rowsOf = card => card.rows.map(text);
const PLAN_HUD = {
  branch: 'feat/x',
  next: '/dflow:build — Task 5: Wire the meter',
  plan: {
    title: 'Rate-limit meter', file: 'docs/dflow/plans/meter.md', done: 4, total: 7,
    current: { number: 5, title: 'Wire the meter', state: 'wip', attempts: 1 },
    blocked: [{ number: 6, reason: 'no API key' }],
    tasks: [
      ...[1, 2, 3, 4].map(number => ({ number, title: `Step ${number}`, state: 'done', run: 'inline' })),
      { number: 5, title: 'Wire the meter', state: 'wip', run: 'inline' },
      { number: 6, title: 'Cache the reading', state: 'blocked', run: 'inline' },
      { number: 7, title: 'Draw the meter', state: 'todo', run: 'worker' },
    ],
  },
  gates: null,
  review: { recorded: null, open: 2, blocking: 1 },
  board: { counts: { todo: 3, doing: 1, blocked: 1 }, row: { number: 12, state: 'doing' } },
  sync: { enabled: true, queued: 3 },
  context: { resetAt: 150000 },
  workers: [{ task: 7, path: '.dflow/workers/7', branch: 'dflow/w7' }],
  checks: ['Task 2 is ticked without a recorded `dflow done`'],
};
const forty = Array.from({ length: 40 }, (_, index) => ({ number: index + 1, title: `T${index + 1}`, state: index < 19 ? 'done' : index === 19 ? 'wip' : 'todo', run: 'inline' }));

test('the Now row names the state of the plan', () => {
  assert.equal(text(nowRow(PLAN_HUD)), '● Task 5 in progress · verify failed 1×');
  assert.equal(text(nowRow({ ...PLAN_HUD, plan: { ...PLAN_HUD.plan, current: { number: 5, title: 't', state: 'todo', attempts: 0 } } })), '● Task 5 ready');
  assert.equal(text(nowRow({ ...PLAN_HUD, plan: { ...PLAN_HUD.plan, done: 7, current: null } })), '✓ All 7 tasks done');
  assert.equal(text(nowRow({ ...PLAN_HUD, plan: { ...PLAN_HUD.plan, current: null } })), '✗ Every remaining task is blocked');
  assert.equal(text(nowRow({ ...PLAN_HUD, plan: null })), '○ No active plan on feat/x');
});

test('the task window centres on the current task and counts what it cuts', () => {
  const window = taskWindow(forty, 20, 8);
  assert.deepEqual([window.rows[0].number, window.rows.at(-1).number, window.above, window.aboveDone, window.below, window.belowDone], [16, 23, 15, true, 17, false]);
  const card = planCard({ ...PLAN_HUD, plan: { ...PLAN_HUD.plan, done: 19, total: 40, current: { number: 20, title: 'T20', state: 'wip', attempts: 0 }, blocked: [], tasks: forty } });
  assert.equal(rowsOf(card).filter(row => /^[✓▸✗○] Task/.test(row)).length, 8);
  assert.ok(rowsOf(card).includes('… 15 more done'));
  assert.ok(rowsOf(card).includes('… 17 more'));
});

test('the Plan card lists tasks with their glyphs, details and checks', () => {
  const card = planCard(PLAN_HUD);
  assert.deepEqual([card.key, card.title, card.color, text(card.headline)], ['plan', 'Plan', 'yellow', '4/7 · 1 blocked']);
  assert.equal(card.headline.find(run => run.text.includes('blocked')).color, 'red');
  const rows = rowsOf(card);
  for (const row of ['Rate-limit meter', 'docs/dflow/plans/meter.md', '✓ Task 4: Step 4', '▸ Task 5: Wire the meter', '  verify failed 1×', '✗ Task 6: Cache the reading', '  blocked: no API key', '○ Task 7: Draw the meter · worker', '⚠ Task 2 is ticked without a recorded `dflow done`']) assert.ok(rows.includes(row), row);
  assert.equal(text(planCard({ ...PLAN_HUD, plan: { ...PLAN_HUD.plan, done: 7, current: null, blocked: [] } }).headline), '✓ done');
  const none = planCard({ ...PLAN_HUD, plan: null });
  assert.deepEqual([text(none.headline), rowsOf(none)], ['', ['No active plan on feat/x.']]);
  assert.deepEqual(rowsOf(planCard({ ...PLAN_HUD, plan: { ...PLAN_HUD.plan, done: 0, total: 0, current: null, blocked: [], tasks: [] } })).slice(0, 2), ['Rate-limit meter', 'docs/dflow/plans/meter.md']);
});

test('the Checks card puts the worst reading in its headline', () => {
  const headline = hud => text(checksCard(hud).headline);
  assert.equal(checksCard({ ...PLAN_HUD, plan: null }), null);
  assert.equal(headline(PLAN_HUD), '● 1 blocking');
  assert.equal(headline({ ...PLAN_HUD, gates: { ok: false, stale: false, failed: ['lint', 'test'] } }), '✗ failed');
  assert.equal(headline({ ...PLAN_HUD, review: { recorded: null, open: 0, blocking: 0 }, gates: { ok: true, stale: true, failed: [] } }), 'stale');
  assert.equal(headline({ ...PLAN_HUD, review: { recorded: { tier: 2 }, open: 0, blocking: 0 }, gates: { ok: true, stale: false, failed: [] } }), '✓ passed');
  assert.equal(headline({ ...PLAN_HUD, review: { recorded: null, open: 0, blocking: 0 } }), 'not run');
  assert.deepEqual(rowsOf(checksCard({ ...PLAN_HUD, gates: { ok: false, stale: false, failed: ['lint', 'test'] } })), ['Gates   ✗ failed: lint, test', 'Review  not run · 2 open, 1 blocking']);
  assert.deepEqual(rowsOf(checksCard({ ...PLAN_HUD, review: { recorded: { tier: 1 }, open: 2, blocking: 1 } })), ['Gates   not run', 'Review  tier 1 recorded · 2 open, 1 blocking']);
  assert.equal(rowsOf(checksCard({ ...PLAN_HUD, gates: { ok: true, stale: false, failed: [] } }))[0], 'Gates   ✓ passed');
  assert.equal(rowsOf(checksCard({ ...PLAN_HUD, gates: { ok: true, stale: true, failed: [] } }))[0], 'Gates   ✓ passed · stale, the head moved');
});

test('the Board card reads darkmem in five states', () => {
  const card = boardCard(PLAN_HUD);
  assert.deepEqual([text(card.headline), rowsOf(card)[0]], ['#12 doing', '3 todo · 1 doing · 1 blocked']);
  const sync = fields => rowsOf(boardCard({ ...PLAN_HUD, sync: { enabled: true, queued: 3, ...fields } })).at(-1);
  assert.deepEqual(
    [sync({ queued: 0 }), sync({}), sync({ error: 'x', offline: true }), sync({ error: 'x', offline: false }), sync({ refused: 1 }), sync({ conflict: 'c' })],
    ['darkmem ● synced · 0 queued', 'darkmem ◐ 3 queued', 'darkmem ○ offline · 3 queued', 'darkmem ✗ refused: run dflow sync push · 3 queued', 'darkmem ✗ refused: run dflow sync push · 3 queued', 'darkmem ✗ conflict: run dflow sync pull'],
  );
  assert.equal(boardCard({ ...PLAN_HUD, board: null, sync: { enabled: false } }), null);
  assert.deepEqual(rowsOf(boardCard({ ...PLAN_HUD, board: null })), ['darkmem ◐ 3 queued']);
  assert.equal(text(boardCard({ ...PLAN_HUD, board: { counts: { todo: 3, done: 1 }, row: null } }).headline), '4 rows');
});

test('the Workers card, the Next row and the stored collapse list', () => {
  const card = workersCard({ ...PLAN_HUD, workers: [{ task: 6, branch: 'dflow/w6' }, { task: 7, branch: 'dflow/w7' }] });
  assert.deepEqual([text(card.headline), rowsOf(card)], ['● 2 running', ['● Task 6: Cache the reading  dflow/w6', '● Task 7: Draw the meter  dflow/w7']]);
  assert.equal(workersCard({ ...PLAN_HUD, workers: [] }), null);
  assert.equal(text(nextRow(PLAN_HUD)), 'Next  /dflow:build — Task 5: Wire the meter');
  assert.deepEqual(SECTIONS, ['account', 'plan', 'context', 'usage', 'checks', 'board', 'workers', 'repo']);
  assert.deepEqual([collapsedFrom(['plan', 'nope', 'plan', 'repo']), collapsedFrom('plan'), collapsedFrom(undefined)], [['plan', 'repo'], [], []]);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 node --test plugins/dflow/tests/hud.test.mjs`
Expected: FAIL with `does not provide an export named 'SECTIONS'`

- [ ] **Step 3: Implement**

1. In `view.mjs`, import from `./meter.mjs` and add the Task 3 functions of Contracts. Glyph colors: `✓` `green`, `▸` `cyan` bold, `✗` `red`, `○` row `dim: true`, `⚠` row `yellow`, `verify failed N×` `yellow`, the Now row's `●` `cyan`, `✓` `green`, `✗` `red`, `○` row dim; `Next` bold.
2. `taskWindow(tasks, currentNumber, size)`: `start = clamp(indexOf(current) - floor(size / 2), 0, max(0, n - size))`; with no current task, centre on the first task that is not done or review. `aboveDone`/`belowDone` are true when every cut task on that side is `done` or `review`. Overflow rows read `… N more done` when that side is all done, else `… N more`, dim, above or below the window.
3. `planCard(hud, width = 50)` rows in order: title (bold), file (dim), a `bar(done / total, width)` meter row only when `total > 0` (fill `green`, empty dim), the overflow-above row, the task rows with each detail row directly under its task (current: `  verify failed N×` when attempts > 0; blocked: `  blocked: <reason>` from `plan.blocked`), the overflow-below row, then the `⚠` rows from `hud.checks`. Headline: `✓ done` (green) when `done === total > 0`, else `done/total` plus `· N blocked` in red when any.
4. `checksCard`: headline precedence `✗ failed` (red) → `● N blocking` (red) → `stale` (yellow) → `✓ passed` (green) → `not run` (dim). Rows: `Gates   ✓ passed`, `Gates   ✓ passed · stale, the head moved`, `Gates   ✗ failed: <names>` or `Gates   not run`; `Review  tier N recorded` or `Review  not run`, plus ` · N open, N blocking` while findings are open.
5. `boardCard`: headline `#<row> <state>` when the plan has a board row, else `<sum of counts> rows`, else empty; rows the counts in `hud.board.counts` order joined with ` · `, then the darkmem row while `sync.enabled`; the five readings as the test shows (`◐`/`○` yellow, `✗` red, `●` green).
6. `workersCard`: rows `● Task N: <title from plan.tasks>` then two spaces and the branch dim; headline `● N running` magenta.
7. `collapsedFrom(value)`: an array filtered to known keys, deduplicated; anything else `[]`.
8. In `types/index.d.ts`, add to `Hud`: `checks: string[]`; to `plan`: `approved: string | null` and `tasks: { number: number; title: string; state: string; run?: string }[]`; to `workers` items: `path?: string; branch?: string`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 node --test plugins/dflow/tests/hud.test.mjs && timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dflow/hooks/hud/view.mjs plugins/dflow/types/index.d.ts plugins/dflow/tests/hud.test.mjs
git commit -m "feat(dflow): model the HUD's plan, checks and board cards" -m "Also carries the owner's uncommitted changes in view.mjs."
```

### Task 4: The framed pane with collapsible cards

**Files:**
- Modify: `plugins/dflow/hooks/hud/register.tsx` (the `Pane` render hook)
- Modify: `plugins/dflow/hooks/hud/view.mjs` (remove `paneRows`)
- Test: `plugins/dflow/hooks/hud/register.test.tsx`
- Test: `plugins/dflow/tests/hud.test.mjs`

**Interfaces:**
- Consumes: Task 3 functions, `drawButton`, `world` (Contracts)
- Produces: `drawCard` and the card element keys (Contracts: Element keys)

**UI/UX:** UI-1, UI-15, UX-2, UX-7, UX-8, UX-10

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5

- [ ] **Step 1: Write the failing test**

In `register.test.tsx`, replace the `HUD` constant with this literal:

```tsx
const HUD = {
  branch: 'feat/x',
  next: '/dflow:build — Task 5: Wire the meter',
  plan: {
    title: 'Rate-limit meter',
    file: 'docs/dflow/plans/meter.md',
    approved: null,
    done: 4,
    total: 7,
    current: { number: 5, title: 'Wire the meter', state: 'wip', attempts: 1 },
    blocked: [{ number: 6, reason: 'no API key' }],
    tasks: [
      ...[1, 2, 3, 4].map(number => ({ number, title: `Step ${number}`, state: 'done', run: 'inline' })),
      { number: 5, title: 'Wire the meter', state: 'wip', run: 'inline' },
      { number: 6, title: 'Cache the reading', state: 'blocked', run: 'inline' },
      { number: 7, title: 'Draw the meter', state: 'todo', run: 'worker' },
    ],
  },
  gates: null,
  review: { recorded: null, open: 2, blocking: 1 },
  board: { counts: { doing: 1, open: 3 }, row: { number: 12, state: 'doing' } },
  sync: { enabled: false },
  context: { resetAt: 150000 },
  workers: [{ task: 7, path: '.dflow/workers/7', branch: 'dflow/w7' }],
  checks: [],
}
```

Then replace the three `pane.find` assertions of `/dflow:hud cycles band, pane, off and keeps the choice` with `expect((await pane.find({ key: 'plan-headline' }))?.text).toBe('4/7 · 1 blocked')` and `expect((await pane.find({ key: 'next' }))?.text).toBe('Next  /dflow:build — Task 5: Wire the meter')`, and add:

```tsx
const order = async (ui: any, patterns: RegExp[]) => {
  const texts: string[] = (await ui.findAll({ type: 'Text' })).map((one: any) => one.text)
  return patterns.map(pattern => texts.findIndex(text => pattern.test(text)))
}

test('the pane draws the Now row, the cards in order and the Next row', async ($, on) => {
  world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) } })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const at = await order(pane, [/^● Task 5 in progress/, /^▾ Plan$/, /^▾ Checks$/, /^▾ Board$/, /^▾ Workers$/, /^Next {2}/])
  expect(at.every(index => index >= 0)).toBe(true)
  expect([...at].sort((a, b) => a - b)).toEqual(at)
  expect((await pane.find({ key: 'plan' }))?.props).toMatchObject({ borderStyle: 'round', borderColor: 'yellow' })
  expect((await pane.find({ key: 'checks-headline' }))?.text).toBe('● 1 blocking')
})

test('a card title collapses the card and the choice is stored', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) } })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await pane.press({ key: 'plan-title' })
  expect((await pane.find({ key: 'plan-title' }))?.props.label).toBe('▸ Plan')
  expect((await pane.find({ key: 'plan-headline' }))?.text).toBe('4/7 · 1 blocked')
  expect(await pane.find({ key: 'plan-row-0' })).toBeUndefined()
  expect(w.stored.collapsed).toEqual(['plan'])
  await pane.press({ key: 'plan-title' })
  expect((await pane.find({ key: 'plan-row-0' }))?.text).toBe('Rate-limit meter')
  expect(w.stored.collapsed).toEqual([])
})

test('a rewritten hud.json shows within a poll; a broken one keeps the last view', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) } })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  w.files[HUD_FILE] = JSON.stringify({ ...HUD, plan: { ...HUD.plan, done: 5 } })
  await w.clock!.advance(2000)
  let pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ key: 'plan-headline' }))?.text).toBe('5/7 · 1 blocked')
  await pane.unmount()
  w.files[HUD_FILE] = '{"plan": '
  await w.clock!.advance(2000)
  pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ key: 'plan-headline' }))?.text).toBe('5/7 · 1 blocked')
})

test('outside a dflow checkout the pane says how to start', async ($, on) => {
  world(on, { files: {}, hasState: false })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const texts = (await pane.findAll({ type: 'Text' })).map((one: any) => one.text)
  expect(texts).toEqual(['dflow has no state in this repository yet.', 'Run /dflow:init, then /dflow:plan.'])
})

test('worst-case data is cut to the pane, never wrapped', async ($, on) => {
  const long = (n: number) => 'x'.repeat(n)
  const WORST = {
    ...HUD,
    branch: `feature/${long(72)}`,
    plan: {
      ...HUD.plan,
      title: long(120), done: 19, total: 40,
      current: { number: 20, title: `🚀 é ñ ü ${long(110)}`, state: 'wip', attempts: 3 },
      blocked: [{ number: 21, reason: long(200) }],
      tasks: Array.from({ length: 40 }, (_, i) => ({
        number: i + 1,
        title: i === 18 ? 'aVeryLongUnbrokenIdentifierThatHasNoSpacesAnywhereInItAtAll_0123456789abcdef0123456' : i === 19 ? `🚀 é ñ ü ${long(110)}` : long(120),
        state: i < 19 ? 'done' : i === 19 ? 'wip' : i === 20 ? 'blocked' : 'todo',
        run: i === 21 ? 'worker' : 'inline',
      })),
    },
    gates: { ok: false, stale: false, failed: ['lint', 'unit-tests', 'integration-tests', 'e2e', 'typecheck'] },
    workers: Array.from({ length: 12 }, (_, i) => ({ task: 22 + i, branch: `dflow/w${22 + i}` })),
  }
  world(on, { files: { [HUD_FILE]: JSON.stringify(WORST) } })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, props: { ...PANE.props, bodyColumns: 40 }, surface: 'terminal' })
  const rows = (await pane.findAll({ type: 'Text' })).filter((one: any) => /^(plan|workers|checks)-row-\d+$/.test(String(one.key)))
  expect(rows.length).toBeGreaterThan(8)
  for (const row of rows) {
    expect(row.props.wrap).toBe('truncate-end')
    expect(cellWidth(row.text)).toBeLessThanOrEqual(36)
  }
  expect((await pane.find({ key: 'plan-headline' }))?.text).toBe('19/40 · 1 blocked')
})
```

Add `import { cellWidth } from './meter.mjs'` at the top of the file.

In `hud.test.mjs`, delete the `paneRows` assertions and the `paneRows` import from `the band fits its width and the mode cycles`.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: FAIL — no element keyed `plan-headline`

- [ ] **Step 3: Implement**

1. In `register.tsx`, add `drawRuns(key, runs)` (one `<Text>` per run with its `color`, `bold`, `dimColor`, `underline`) and `drawCard(table, card, isCollapsed, onToggle, extra?)`: a Box keyed `card.key` with `flexDirection="column" borderStyle="round" borderColor={card.color} paddingX={1}`; a head row Box (`justifyContent="space-between"`) holding the title Button keyed `<key>-title` (label `▾ Title` or `▸ Title`, `plain`, its label text in the card color, bold) and the headline `<Text key="<key>-headline" wrap="truncate-end">`; then, unless collapsed, each row as `<Text key="<key>-row-<i>" wrap="truncate-end">`, cut with `runsCut` to the card's inner width (`bodyColumns - 4`). `extra` (buttons) is drawn after the rows even when collapsed.
2. Add a `collapsed` atom loaded from the store key `collapsed` through `collapsedFrom` on a session change; a title press toggles the key, saves the list, and invalidates `ui.render`.
3. The `Pane` render hook draws, in order: `<Text key="now">` from `nowRow`, the controls row, the Plan (`planCard(hud, bodyColumns - 4)`), Checks, Board and Workers cards that are not `null`, and `<Text key="next">` from `nextRow`. With no state it draws the two no-state lines, each a `<Text dimColor>`, and nothing else (no controls row).
4. `readState` keeps the last good `Hud` when the file does not parse (as today) and invalidates `ui.render` on a change.
5. Delete `paneRows`, `syncText` and `contextText` from `view.mjs` (`fit`, `taskText`, `tokens`, `bar` and `bandText` stay until Task 10).
6. Bump the `hudAtom` shape tag from `hud-1` to `hud-2`, since `Hud` gained fields: a value stored by the old mod must be declined, not drawn.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 node --test plugins/dflow/tests/*.test.mjs && timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dflow/hooks/hud/register.tsx plugins/dflow/hooks/hud/view.mjs plugins/dflow/hooks/hud/register.test.tsx plugins/dflow/tests/hud.test.mjs
git commit -m "feat(dflow): draw the HUD pane as collapsible cards"
```

### Task 5: The Context card with its breakdown and Compact

**Files:**
- Modify: `plugins/dflow/hooks/hud/view.mjs` (add `contextCard`)
- Modify: `plugins/dflow/hooks/hud/register.tsx` (readings, breakdown, Compact)
- Modify: `plugins/dflow/types/index.d.ts` (the breakdown and readings atoms)
- Test: `plugins/dflow/tests/hud.test.mjs`
- Test: `plugins/dflow/hooks/hud/register.test.tsx`

**Interfaces:**
- Consumes: `meter.mjs`, `drawCard`, `drawButton`, `world` (Contracts)
- Produces: `contextCard` (Contracts)

**UI/UX:** UI-5, UI-11, UX-4, UX-5

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Add to `hud.test.mjs`:

```js
import { contextCard } from '../hooks/hud/view.mjs';

const BREAKDOWN = { rows: [['Messages', 318000], ['System tools', 41000], ['System prompt', 9000], ['Memory files', 6000], ['Skills', 4000], ['Custom agents', 2000], ['MCP tools', 1000]].map(([name, tokens]) => ({ name, tokens })), compactAt: null, total: 381000 };

test('the Context card reads the window against the reset point', () => {
  const card = contextCard({ hud: PLAN_HUD, context: { tokens: 118000, window: 1000000 }, breakdown: null, readings: [], width: 50 });
  assert.deepEqual([card.key, card.color, text(card.headline)], ['context', 'cyan', '79% of reset']);
  assert.equal(card.headline[0].color, '#ff8700');
  const meter = [...text(card.rows[0])];
  assert.equal(meter.length, 50);
  assert.equal(meter[7], '┃');
  assert.equal(text(card.rows[1]), '118k of 1.0M ┃ resets at 150k');
  const compacting = contextCard({ hud: PLAN_HUD, context: { tokens: 118000, window: 1000000 }, breakdown: { ...BREAKDOWN, compactAt: 967000 }, readings: [100000, 118000], width: 50 });
  assert.equal([...text(compacting.rows[0])][48], '┊');
  assert.equal(text(compacting.rows[1]), '118k of 1.0M ┃ resets at 150k ┊ compacts 967k');
  assert.equal(text(compacting.rows[2]), 'trend ▁█ +18k');
});

test('the breakdown lists the six largest categories under a stacked bar', () => {
  const card = contextCard({ hud: PLAN_HUD, context: { tokens: 118000, window: 1000000 }, breakdown: BREAKDOWN, readings: [], width: 50 });
  const stack = card.rows[2];
  assert.equal(stack.reduce((sum, run) => sum + run.text.length, 0), 50);
  assert.deepEqual(stack.map(run => run.color), ['cyan', 'magenta', 'yellow', 'green', 'blue', 'red']);
  const rows = card.rows.slice(3).map(text);
  assert.equal(rows.length, 6);
  assert.match(rows[0], /^ {2}■ Messages +318k +84%$/);
  assert.ok(!rows.some(row => row.includes('MCP tools')));
});

test('before a reading the Context card shows the estimate', () => {
  const card = contextCard({ hud: PLAN_HUD, context: { window: 1000000 }, breakdown: { ...BREAKDOWN, total: 37000 }, readings: [], width: 50 });
  assert.equal(text(card.headline), '≈37k estimated');
  assert.ok(!card.rows.some(row => text(row).includes('▰')));
  assert.equal(text(contextCard({ hud: PLAN_HUD, context: { window: 1000000 }, breakdown: null, readings: [], width: 50 }).headline), 'no reading yet');
  assert.equal(contextCard({ hud: { ...PLAN_HUD, context: null }, context: null, breakdown: null, readings: [], width: 50 }), null);
  const unset = contextCard({ hud: { ...PLAN_HUD, context: null }, context: { tokens: 118000, window: 1000000 }, breakdown: null, readings: [], width: 50 });
  assert.equal(text(unset.headline), '118k of 1.0M');
  assert.ok(!text(unset.rows[0]).includes('┃'));
  assert.equal(text(unset.rows[1]), '118k of 1.0M');
});
```

Add to `register.test.tsx`:

```tsx
const RESET = 'A dflow build is in progress'
const BREAKDOWN_READING = {
  categories: [['Messages', 318000], ['System tools', 41000], ['System prompt', 9000]].map(([name, tokens]) => ({ name, tokens, kind: 'used' })),
  totalTokens: 368000,
  isAutoCompactEnabled: true,
  autoCompactThreshold: 967000,
}

test('Compact compacts with the reset instructions and turns to the accent past the reset point', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) }, tokens: 160000 })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ key: 'context-compact-box' }))?.props.borderColor).toBe('permission')
  expect((await pane.find({ key: 'context-compact-hotkey' }))?.props.hotkey).toBe('c')
  await pane.press({ key: 'context-compact' })
  expect(w.calls.find(call => call.startsWith('compact'))).toContain(RESET)
})

test('Compact without a plan sends no instructions; two failures toast once', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify({ ...HUD, plan: null }) }, tokens: 90000, compactFailures: 2 })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ key: 'context-compact-box' }))?.props.borderColor).toBe('inactive')
  const pressing = pane.press({ key: 'context-compact' })
  await w.clock!.advance(0)
  await w.clock!.advance(2000)
  await pressing
  expect(w.calls.filter(call => call.startsWith('compact'))).toEqual(['compact ', 'compact '])
  expect(w.calls.filter(call => call.startsWith('toast'))).toEqual(['toast dflow: could not compact; run /compact'])
})

test('in mode off a fresh reset flag still compacts and resumes the build', async ($, on) => {
  const w = world(on, {
    files: {
      [HUD_FILE]: JSON.stringify(HUD),
      '/repo/.dflow/reset.json': JSON.stringify({ plan: 'meter', session: 's1', at: '2026-11-12T11:59:30.000Z' }),
    },
  })
  w.stored.mode = 'off'
  await $.session.start(START)
  await $.turn.complete({ ...TURN, turnId: 't1' })
  await w.clock!.advance(300)
  await w.clock!.advance(0)
  const compact = w.calls.findIndex(call => call.startsWith('compact') && call.includes(RESET))
  expect(compact).toBeGreaterThanOrEqual(0)
  expect(w.calls.indexOf('command /dflow:build')).toBeGreaterThan(compact)
})

test('the breakdown is read for an open Context card only, and the trend follows turns', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) }, breakdown: BREAKDOWN_READING })
  await $.session.start(START)
  await w.clock!.advance(10000)
  expect(w.calls).not.toContain('usage breakdown')
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  expect(w.calls).toContain('usage breakdown')
  w.tokens = 100000
  await $.turn.complete({ ...TURN, turnId: 't1' })
  w.tokens = 118000
  await $.turn.complete({ ...TURN, turnId: 't2' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ type: 'Text', text: /^trend/ }))?.text).toBe('trend ▁█ +18k')
  expect((await pane.find({ type: 'Text', text: /compacts 967k$/ }))).toBeDefined()
  await pane.press({ key: 'context-title' })
  const before = w.calls.filter(call => call === 'usage breakdown').length
  await w.clock!.advance(10000)
  expect(w.calls.filter(call => call === 'usage breakdown').length).toBe(before)
  expect(await pane.find({ key: 'context-compact' })).toBeDefined()
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 node --test plugins/dflow/tests/hud.test.mjs`
Expected: FAIL with `does not provide an export named 'contextCard'`

- [ ] **Step 3: Implement**

1. `contextCard({ hud, context, breakdown, readings, width })` in `view.mjs`: `null` when there is no reading, no `hud.context.resetAt` and no breakdown. With a reading but no `resetAt` (the CLI writes `context: null` when it has no size): the headline `<kTokens(tokens)> of <kTokens(window)>` dim, the meter in `rampColor(tokens / window * 100)` with no `┃`, and the legend without the ` ┃ resets at` part. With a reading: the headline `<round(tokens / resetAt * 100)>% of reset` in `rampColor` of that percent; row 0 `trackRuns(track(tokens / window, width, marks), ramp, { reset: ramp, compact: 'gray' })` with marks `┃` at `resetAt / window` (name `reset`) and `┊` at `compactAt / window` (name `compact`) when `compactAt` is set; row 1 the legend runs (`118k` bold, ` of 1.0M` dim, ` ┃ resets at 150k` in the ramp color, ` ┊ compacts 967k` dim when set); row 2 `trend <sparkline of the last width - 16 readings> ±<kTokens(last - previous)>` once two readings exist (sparkline `cyan`, the rest dim; `−` for a fall). Without a reading the headline is `≈<kTokens(total)> estimated` (dim) or `no reading yet` (dim), with no meter or legend. Then, when the breakdown has rows: the top six by tokens as a stacked row (one run per category, `'█'.repeat(stackedRuns(...)[i])`, colors from Global Constraints) and one detail row each: `  ■ ` in its color, the name padded to 20, the tokens `padStart(5)` bold, the share of the six rows' sum, `Math.round`ed, `padStart(4)` + `%` dim.
2. In `register.tsx`: a `readings` atom (last 40 context tokens, pushed at each main-loop `turn.complete`); a `breakdown` atom read with `$.session.usage({ breakdown: 'summary' })` as the cockpit's `readBreakdown` does (`register.tsx:3787-3801`, categories of kind `used` with tokens > 0, `compactAt` only when `isAutoCompactEnabled`), when the pane opens and every fifth poll after, only while the mode is `pane` and the pane is up (`$.ui.panes()`), the density is not `dense`, `context` is not collapsed (and, from Task 11, shown).
3. The Context card is drawn after Plan; its `extra` is **⇣ Compact** (`context-compact`, hotkey `c`, `isMain` once tokens ≥ `resetAt`). Pressing it calls `$.session.compact({ instructions: RESET_INSTRUCTIONS })` with a plan active, `$.session.compact({})` without; on a throw, `$.clock.sleep(2000)` and one retry; a second throw toasts `dflow: could not compact; run /compact`. `compactAndResume` uses the same retry helper with its own toast text, unchanged: `dflow: could not compact; run /compact, then /dflow:build`.
4. Add the `breakdown` and `readings` atom types to `PluginState` in `types/index.d.ts`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 node --test plugins/dflow/tests/*.test.mjs && timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dflow/hooks/hud/view.mjs plugins/dflow/hooks/hud/register.tsx plugins/dflow/types/index.d.ts plugins/dflow/tests/hud.test.mjs plugins/dflow/hooks/hud/register.test.tsx
git commit -m "feat(dflow): add the Context card with breakdown and Compact"
```

### Task 6: The Account card

**Files:**
- Create: `plugins/dflow/hooks/hud/account.mjs`
- Modify: `plugins/dflow/hooks/hud/view.mjs` (add `accountCard`)
- Modify: `plugins/dflow/hooks/hud/register.tsx` (account, model, effort, Remote)
- Modify: `plugins/dflow/types/index.d.ts`
- Test: `plugins/dflow/tests/hud.test.mjs`
- Test: `plugins/dflow/hooks/hud/register.test.tsx`

**Interfaces:**
- Consumes: `drawCard`, `world` (Contracts)
- Produces: `account.mjs`, `accountCard` (Contracts)

**UI/UX:** UI-3, UX-7

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 1 = 5

- [ ] **Step 1: Write the failing test**

Add to `hud.test.mjs`:

```js
import { accountColor, accountFrom, accountKey, billingLabel, modelName, remoteRuns } from '../hooks/hud/account.mjs';
import { accountCard } from '../hooks/hud/view.mjs';

const CLAUDE_JSON = { oauthAccount: { emailAddress: 'you@example.com', displayName: 'You', organizationName: 'Acme', organizationRole: 'admin', billingType: 'stripe_subscription' } };

test('the account comes from .claude.json with a color of its own', () => {
  const account = accountFrom(CLAUDE_JSON, '', '/home/me');
  assert.deepEqual([account.email, account.name, account.organization, account.role, account.billing, account.key], ['you@example.com', 'You', 'Acme', 'admin', 'stripe_subscription', '~/.claude']);
  assert.equal(account.color, accountColor('~/.claude'));
  assert.equal(accountKey('/home/me/.claude-alt', '/home/me'), '~/.claude-alt');
  assert.deepEqual([billingLabel('stripe_subscription'), billingLabel(null), modelName('claude-opus-5-5[1m]')], ['subscription', null, 'Opus 5.5']);
  assert.equal(accountFrom({}, '', '/home/me').email, null);
  assert.deepEqual([remoteRuns([{ surface: 'mobile' }], null), remoteRuns([], 'true'), remoteRuns([], null)].map(text), ['● connected · phone', '○ on · no device yet', '○ not connected']);
});

test('the Account card lists who, which model and where', () => {
  const card = accountCard({ account: accountFrom(CLAUDE_JSON, '', '/home/me'), engine: { model: 'claude-opus-5-5', effort: 'xhigh' }, remote: { clients: [{ surface: 'mobile' }], setting: null } });
  assert.deepEqual([card.key, card.title, text(card.headline)], ['account', 'Account', 'subscription']);
  assert.deepEqual(rowsOf(card), ['● you@example.com', '  You · Acme (admin)', '  Opus 5.5 · xhigh effort', '  Remote ● connected · phone', '  config ~/.claude']);
  const bare = accountCard({ account: accountFrom({}, '', '/home/me'), engine: { model: 'claude-opus-5-5', effort: 'xhigh' }, remote: { clients: [], setting: null } });
  assert.deepEqual(rowsOf(bare), ['  config ~/.claude']);
});
```

Add to `register.test.tsx`:

```tsx
test('the Account card reads the account file, the model, the effort and Remote Control', async ($, on) => {
  const w = world(on, {
    files: { [HUD_FILE]: JSON.stringify(HUD), '/home/me/.claude.json': JSON.stringify({ oauthAccount: { emailAddress: 'you@example.com', billingType: 'stripe_subscription' } }) },
    settings: { effortLevel: 'xhigh' },
    remoteControl: 'true',
  })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ key: 'account-headline' }))?.text).toBe('subscription')
  expect((await pane.find({ key: 'account-row-0' }))?.text).toBe('● you@example.com')
  expect((await pane.find({ key: 'account-row-1' }))?.text).toBe('  Opus 5.5 · xhigh effort')
  expect((await pane.find({ key: 'account-row-2' }))?.text).toBe('  Remote ○ on · no device yet')
  expect(w.calls).toContain('read /home/me/.claude.json')
})

test('mode off reads no account file but still writes the context size', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) } })
  w.stored.mode = 'off'
  await $.session.start(START)
  await w.clock!.advance(10000)
  expect(w.calls.some(call => call.includes('.claude.json'))).toBe(false)
  expect(w.calls.some(call => call.startsWith('write /repo/.dflow/context/s1.json'))).toBe(true)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 node --test plugins/dflow/tests/hud.test.mjs`
Expected: FAIL with `Cannot find module '../hooks/hud/account.mjs'`

- [ ] **Step 3: Implement**

1. `account.mjs`: port `accountKey` (:765, with `slashes` :822), `ACCOUNT_COLORS` and `accountColor` (:773-780), `billingLabel` (:783), `modelName`, `deviceName` and `remoteRuns` (:1365-1380) from the cockpit's `lib.ts`; add `accountFrom(claudeJson, configDir, home)` as the cockpit's `readAccount` builds its value (`register.tsx:3813-3830`), every missing string `null`, `key = accountKey(configDir || \`${home}/.claude\`, home)`.
2. `accountCard({ account, engine, remote })`: color `account.color`; headline `billingLabel(billing)` dim, or empty; with no email, the single row `  config <key>` (the spec's error handling); otherwise rows in order, each left out when its value is missing: `● <email>` (the `●` in the account color), `  <name> · <organization> (<role>)` (the parts that exist), `  <modelName(model)> · <effort> effort`, `  Remote ` + `remoteRuns(...)`, `  config <key>`.
3. In `register.tsx`: an `account` atom read with `$.env.get('HOME')` (or `USERPROFILE`), `$.env.get('CLAUDE_CONFIG_DIR')` and `$.fs.read` of `<configDir or HOME>/.claude.json` the first time the mode is `band` or `pane` in a session (never while `off`); an `engine` atom with the model and effort from each main-loop `turn.step` (`e.model`, `e.effort`, only when `e.agentId` is undefined; an observing generator hook as the cockpit's at `register.tsx:628-636`), falling back before the first step to `$.session.model()` and `$.settings.read()`'s `effortLevel` (the cockpit's `readEngine`, `register.tsx:3870-3880`); a `remote` atom from `session.attach`/`session.detach` (`clientId`, `surface`; `register.tsx:524-560`) and the `remoteControl` row of `$.config.list()` (`readRemote`, `register.tsx:3985-3990`). Draw the Account card first, above the controls row.
4. Add the atom types to `types/index.d.ts`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 node --test plugins/dflow/tests/*.test.mjs && timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dflow/hooks/hud/account.mjs plugins/dflow/hooks/hud/view.mjs plugins/dflow/hooks/hud/register.tsx plugins/dflow/types/index.d.ts plugins/dflow/tests/hud.test.mjs plugins/dflow/hooks/hud/register.test.tsx
git commit -m "feat(dflow): add the HUD's Account card"
```

### Task 7: The Usage card

**Files:**
- Modify: `plugins/dflow/hooks/hud/view.mjs` (add `usageCard`)
- Modify: `plugins/dflow/hooks/hud/register.tsx` (the usage atom)
- Modify: `plugins/dflow/types/index.d.ts`
- Test: `plugins/dflow/tests/hud.test.mjs`
- Test: `plugins/dflow/hooks/hud/register.test.tsx`

**Interfaces:**
- Consumes: `meter.mjs`, `drawCard`, `world` (Contracts)
- Produces: `usageCard` (Contracts)

**UI/UX:** UI-6

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5

- [ ] **Step 1: Write the failing test**

Add to `hud.test.mjs`:

```js
import { usageCard } from '../hooks/hud/view.mjs';

test('the Usage card draws each window with its share, reset and pace', () => {
  const now = 1_000_000_000_000;
  const card = usageCard({ usage: { limits: [{ kind: 'five_hour', percent: 23, resetsAt: now + 3 * H + 40 * 60_000 }, { kind: 'seven_day', percent: 61, resetsAt: now + (2 * 24 + 19) * H }, { kind: 'spend_limit', percent: 42, resetsAt: null }], usd: 4.86, startedAt: now - 2 * H }, now, width: 50 });
  assert.deepEqual([card.key, card.color, text(card.headline)], ['usage', 'blue', '$4.86 · $2.43/h']);
  const rows = rowsOf(card);
  assert.match(rows[0], /^5h {2}[▰▱┊]+ {2}23%$/);
  assert.ok(rows[0].includes('┊'));
  assert.equal(rows[1], '    resets in 3h40m · on pace');
  assert.match(rows[3], /^ {4}resets in 2d19h · out in \d+d\d+h$/);
  assert.equal(rows[4], 'spend 42%');
  assert.equal(card.rows[1].at(-1).color, 'green');
  const young = usageCard({ usage: { limits: [{ kind: 'five_hour', percent: 2, resetsAt: now + 4 * H + 55 * 60_000 }], usd: null, startedAt: now }, now, width: 50 });
  assert.equal(rowsOf(young)[1], '    resets in 4h55m');
});

test('the Usage card without windows shows the cost alone, and nothing without either', () => {
  const now = 1_000_000_000_000;
  const card = usageCard({ usage: { limits: [], usd: 4.8, startedAt: now - 2 * H }, now, width: 50 });
  assert.deepEqual([text(card.headline), card.rows], ['$4.80 · $2.40/h', []]);
  assert.equal(usageCard({ usage: { limits: [], usd: null, startedAt: now }, now, width: 50 }), null);
  assert.equal(usageCard({ usage: null, now, width: 50 }), null);
});
```

Add to `register.test.tsx`:

```tsx
test('the Usage card shows the limits and cost the engine reports', async ($, on) => {
  world(on, {
    files: { [HUD_FILE]: JSON.stringify(HUD) },
    usd: 4.8,
    rateLimits: [{ kind: 'five_hour', percentUsed: 23, resetsAt: new Date(NOW + 3 * 3_600_000 + 40 * 60_000).toISOString() }],
  })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ key: 'usage-headline' }))?.text).toBe('$4.80 · $2.40/h')
  expect((await pane.find({ key: 'usage-row-1' }))?.text).toBe('    resets in 3h40m · on pace')
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 node --test plugins/dflow/tests/hud.test.mjs`
Expected: FAIL with `does not provide an export named 'usageCard'`

- [ ] **Step 3: Implement**

1. `usageCard({ usage, now, width })`: `null` without usage, or with no limits and no `usd`. Headline `$<usd.toFixed(2)> · $<(usd / hours since startedAt).toFixed(2)>/h` dim (the rate left out under a minute of session). For `five_hour` and `seven_day`, in that order: a row `<limitLabel>  ` + `trackRuns(track(percent / 100, width - 10, [{ at: windowElapsed(...), glyph: '┊', name: 'elapsed' }]), rampColor(percent), { elapsed: 'gray' })` + `  <round(percent)>%` in the ramp color; then `    resets in <duration(resetsAt - now)>` dim, plus ` · on pace` (green) when `limitForecast` is `'pace'` or ` · out in <duration>` (`#ff8700`) when it is a number. Any other window is one row `<limitLabel> <round(percent)>%`.
2. In `register.tsx`, a `usage` atom set on each poll from the same `$.session.usage()` call: `limits` from `rateLimits` (`percentUsed`, `Date.parse(resetsAt)` or `null`), `usd` from `cost?.usd ?? null`, `startedAt`. Draw the Usage card after Context. Add the atom type.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 node --test plugins/dflow/tests/*.test.mjs && timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dflow/hooks/hud/view.mjs plugins/dflow/hooks/hud/register.tsx plugins/dflow/types/index.d.ts plugins/dflow/tests/hud.test.mjs plugins/dflow/hooks/hud/register.test.tsx
git commit -m "feat(dflow): add the HUD's Usage card"
```

### Task 8: The Repo card and the git reading

**Files:**
- Create: `plugins/dflow/hooks/hud/repo.mjs`
- Modify: `plugins/dflow/hooks/hud/view.mjs` (add `repoCard`)
- Modify: `plugins/dflow/hooks/hud/register.tsx` (git polling)
- Modify: `plugins/dflow/types/index.d.ts`
- Test: `plugins/dflow/tests/hud.test.mjs`
- Test: `plugins/dflow/hooks/hud/register.test.tsx`

**Interfaces:**
- Consumes: `drawCard`, `world` (Contracts)
- Produces: `repo.mjs`, `repoCard` (Contracts)

**UI/UX:** UI-10, UX-7

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 1 = 5

- [ ] **Step 1: Write the failing test**

Add to `hud.test.mjs`:

```js
import { repoFromPorcelain, repoName, shortDir } from '../hooks/hud/repo.mjs';
import { repoCard } from '../hooks/hud/view.mjs';

const PORCELAIN = '# branch.oid abc1234def\n# branch.head feat/x\n# branch.ab +3 -1\n1 .M N... 100644 100644 100644 a b src/a.mjs\r\n1 M. N... 100644 100644 100644 a b src/b.mjs\n? notes.txt\n';

test('git porcelain, the repository name and the folder', () => {
  assert.deepEqual(repoFromPorcelain(PORCELAIN), { branch: 'feat/x', ahead: 3, behind: 1, changed: 2, untracked: 1 });
  assert.equal(repoFromPorcelain('# branch.oid abc1234def\n# branch.head (detached)\n').branch, '@abc1234');
  assert.equal(repoFromPorcelain(''), null);
  assert.deepEqual([repoName('git@github.com:darkraise/shop.git', '/x/shop'), repoName('https://github.com/darkraise/shop', '/x'), repoName(null, '/home/me/code/shop')], ['darkraise/shop', 'darkraise/shop', 'shop']);
  assert.deepEqual([shortDir('/home/me/code/shop', '/home/me'), shortDir('C:\\Users\\me\\shop', 'C:\\Users\\me'), shortDir('/srv/shop', '/home/me')], ['~/code/shop', '~/shop', '/srv/shop']);
});

test('the Repo card reads dirty or clean', () => {
  const where = { cwd: '/home/me/code/shop', root: '/home/me/code/shop', home: '/home/me', remote: 'git@github.com:darkraise/shop.git' };
  const card = repoCard({ repo: repoFromPorcelain(PORCELAIN), where });
  assert.deepEqual([card.key, card.color, text(card.headline)], ['repo', 'green', '● dirty']);
  assert.deepEqual(rowsOf(card), ['repo darkraise/shop', 'dir  ~/code/shop', '⎇ feat/x ↑3 ↓1', '~2 changed ?1 untracked']);
  const clean = repoCard({ repo: { branch: 'main', ahead: 0, behind: 0, changed: 0, untracked: 0 }, where: { ...where, remote: null } });
  assert.deepEqual([text(clean.headline), rowsOf(clean)], ['✓ clean', ['repo shop', 'dir  ~/code/shop', '⎇ main', 'clean']]);
  assert.deepEqual(rowsOf(repoCard({ repo: null, where })), ['dir  ~/code/shop']);
});
```

Add to `register.test.tsx`:

```tsx
const GIT_STATUS = '--no-optional-locks -c core.fsmonitor=false status --porcelain=v2 --branch'

test('git status runs every ten seconds while shown and never while off', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) }, porcelain: '# branch.head feat/x\n# branch.ab +3 -0\n', remoteUrl: 'git@github.com:darkraise/shop.git' })
  await $.session.start(START)
  await w.clock!.advance(10000)
  expect(w.calls.filter(call => call.includes(GIT_STATUS)).length).toBeGreaterThanOrEqual(1)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ key: 'repo-row-0' }))?.text).toBe('repo darkraise/shop')
  expect((await pane.find({ key: 'repo-headline' }))?.text).toBe('✓ clean')
  w.porcelain = undefined
  await w.clock!.advance(10000)
  await pane.unmount()
  const after = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await after.find({ key: 'repo-headline' }))?.text).toBe('✓ clean')
  await after.unmount()
  await $.command.run({ command: 'dflow:hud', args: 'off' })
  const before = w.calls.filter(call => call.includes(GIT_STATUS)).length
  await w.clock!.advance(20000)
  expect(w.calls.filter(call => call.includes(GIT_STATUS)).length).toBe(before)
})
```

Add the full-order test, now that every card exists:

```tsx
test('the pane draws every card in order, each framed in its color', async ($, on) => {
  world(on, {
    files: { [HUD_FILE]: JSON.stringify(HUD), '/home/me/.claude.json': JSON.stringify({ oauthAccount: { emailAddress: 'you@example.com' } }) },
    usd: 1,
    porcelain: '# branch.head feat/x\n',
  })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const at = await order(pane, [/^● Task 5/, /^▾ Account$/, /^M$/, /^▾ Plan$/, /^▾ Context$/, /^▾ Usage$/, /^▾ Checks$/, /^▾ Board$/, /^▾ Workers$/, /^▾ Repo$/, /^Next {2}/])
  expect(at.every(index => index >= 0)).toBe(true)
  expect([...at].sort((a, b) => a - b)).toEqual(at)
  const colors: Record<string, string> = { plan: 'yellow', context: 'cyan', usage: 'blue', checks: 'red', board: 'white', workers: 'magenta', repo: 'green' }
  for (const [key, color] of Object.entries(colors)) expect((await pane.find({ key }))?.props).toMatchObject({ borderStyle: 'round', borderColor: color })
  expect((await pane.find({ key: 'account' }))?.props.borderColor).toBe(accountColor('~/.claude'))
})
```

Add `import { accountColor } from './account.mjs'` at the top of `register.test.tsx`.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 node --test plugins/dflow/tests/hud.test.mjs`
Expected: FAIL with `Cannot find module '../hooks/hud/repo.mjs'`

- [ ] **Step 3: Implement**

1. `repo.mjs`: port `repoFromPorcelain` (`lib.ts:297`, splitting on `/\r?\n/`), `repoName` (:847) and `slashes` (:822); add `shortDir(cwd, home)`: both through `slashes`, `~` + the rest when `cwd` is `home` or under it, else `cwd` as given.
2. `repoCard({ repo, where })`: color `green`; headline `● dirty` (yellow) when `changed + untracked > 0`, `✓ clean` (green) otherwise, empty with no reading; rows, with a git reading, `repo <repoName(remote, root)>`, then always `dir  <shortDir>`, then with a reading `⎇ <branch>` + ` ↑N` / ` ↓N` when nonzero, and `~N changed ?N untracked` (the nonzero parts) or `clean`.
3. In `register.tsx`, a `repo` atom and a `where` atom (`cwd` from `session.start`, `root`, `HOME`, the remote URL from `git remote get-url origin` once per session switch). Every fifth poll, while the mode is `band` or `pane`, run `git --no-optional-locks -c core.fsmonitor=false status --porcelain=v2 --branch` with `timeoutMs: 3000` in the root and keep the last good reading on a failure. Draw the Repo card last.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 node --test plugins/dflow/tests/*.test.mjs && timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dflow/hooks/hud/repo.mjs plugins/dflow/hooks/hud/view.mjs plugins/dflow/hooks/hud/register.tsx plugins/dflow/types/index.d.ts plugins/dflow/tests/hud.test.mjs plugins/dflow/hooks/hud/register.test.tsx
git commit -m "feat(dflow): add the HUD's Repo card"
```

### Task 9: The dense layout and saved preferences

**Files:**
- Modify: `plugins/dflow/hooks/hud/view.mjs` (add `denseLines`)
- Modify: `plugins/dflow/hooks/hud/register.tsx` (density, preferences on a session switch)
- Test: `plugins/dflow/tests/hud.test.mjs`
- Test: `plugins/dflow/hooks/hud/register.test.tsx`

**Interfaces:**
- Consumes: the card functions of Tasks 3 and 5-8, `drawButton`, `world` (Contracts)
- Produces: `denseLines` (Contracts)

**UI/UX:** UI-12, UX-3, UX-9

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Add to `hud.test.mjs`:

```js
import { denseLines } from '../hooks/hud/view.mjs';

test('the dense layout is one labelled line per card', () => {
  const now = 1_000_000_000_000;
  const input = {
    hud: PLAN_HUD,
    account: accountFrom(CLAUDE_JSON, '', '/home/me'),
    remote: { clients: [{ surface: 'mobile' }], setting: null },
    context: { tokens: 118000, window: 1000000 },
    usage: { limits: [{ kind: 'five_hour', percent: 23, resetsAt: now + 3 * H + 40 * 60_000 }, { kind: 'seven_day', percent: 61, resetsAt: now + 4 * 24 * H }], usd: 4.85, startedAt: now - 2 * H },
    now,
    repo: repoFromPorcelain(PORCELAIN),
    where: { cwd: '/home/me/code/shop', root: '/home/me/code/shop', home: '/home/me', remote: null },
    shown: ['account', 'plan', 'context', 'usage', 'checks', 'board', 'workers', 'repo'],
  };
  const lines = denseLines(input, 56).map(text);
  assert.deepEqual(lines.map(line => line.split(' ')[0]), ['acct', 'plan', 'ctx', 'lim', 'chk', 'board', 'work', 'repo', 'next']);
  assert.equal(lines[0], 'acct  you@example.com · subscription · Remote ●');
  assert.match(lines[1], /^plan  [▰▱]{8} 4\/7 · Task 5 · 1 blocked$/);
  assert.match(lines[2], /^ctx   [▰▱┃]{8} 79% of reset · 118k$/);
  assert.equal(lines[4], 'chk   gates not run · review 1 blocking');
  assert.equal(lines[6], 'work  Task 7');
  assert.equal(lines[7], 'repo  ⎇ feat/x* ↑3 ↓1 ~2 ?1');
  assert.ok(denseLines({ ...input, hud: { ...PLAN_HUD, workers: [] } }, 56).every(line => !text(line).startsWith('work')));
  assert.ok(denseLines(input, 30).every(line => cellWidth(text(line)) <= 30));
  assert.deepEqual(denseLines({ ...input, shown: ['repo', 'plan'] }, 56).map(line => text(line).split(' ')[0]), ['repo', 'plan', 'next']);
  const noReset = denseLines({ ...input, hud: { ...PLAN_HUD, context: null } }, 56).map(text).find(line => line.startsWith('ctx'));
  assert.match(noReset, /^ctx {3}[▰▱]{8} 118k of 1\.0M$/);
});
```

Add to `register.test.tsx`:

```tsx
test('Dense draws one line per card and Detailed brings the cards back', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) } })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ key: 'pane-density-hotkey' }))?.props.hotkey).toBe('d')
  await pane.press({ key: 'pane-density' })
  expect(w.stored.density).toBe('dense')
  expect((await pane.find({ key: 'dense-plan' }))?.text).toMatch(/^plan {2}/)
  expect(await pane.find({ key: 'plan' })).toBeUndefined()
  expect((await pane.find({ key: 'pane-density' }))?.props.label).toBe('☰ Detailed')
  const before = w.calls.filter(call => call === 'usage breakdown').length
  await w.clock!.advance(10000)
  expect(w.calls.filter(call => call === 'usage breakdown').length).toBe(before)
  await pane.press({ key: 'pane-density' })
  expect(w.stored.density).toBe('detailed')
  expect(await pane.find({ key: 'plan' })).toBeDefined()
})

test('mode, density and collapsed cards hold across a session switch', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) } })
  w.stored.mode = 'pane'
  w.stored.density = 'dense'
  w.stored.collapsed = ['repo']
  await $.session.start(START)
  w.sessionId = 's2'
  w.stored.density = 'detailed'
  await w.clock!.advance(2000)
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ key: 'repo-title' }))?.props.label).toBe('▸ Repo')
  expect(await pane.find({ key: 'plan' })).toBeDefined()
  expect(w.isPaneUp).toBe(true)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 node --test plugins/dflow/tests/hud.test.mjs`
Expected: FAIL with `does not provide an export named 'denseLines'`

- [ ] **Step 3: Implement**

1. `denseLines(input, width)`: for each key in `input.shown` with something to show, one `Run[]` led by its label padded to 6 (`acct `, `plan `, `ctx  `, `lim  `, `chk  `, `board `, `work `, `repo `; the label bold), then always `next  <hud.next>`; each cut with `runsCut` to `width`. Contents: account `<email> · <billing> · Remote ●|○`; plan `bar(done / total, 8) done/total` + ` · Task N` + ` · N blocked` (red); ctx an 8-cell track with `┃`, `<pct>% of reset · <kTokens>` (without `resetAt`: the track with no `┃`, then `<kTokens(tokens)> of <kTokens(window)>`); lim `5h <p>% on pace|out in … · 7d <p>% · $<usd>`; chk `gates <✗ names | ✓ passed | not run> · review <N blocking | tier N | not run>`; board `#<row> <state> · darkmem <queued> queued` (or the conflict text); work `Task N, Task M`; repo `⎇ <branch>` + `*` when dirty + ` ↑N ↓N ~N ?N` (nonzero parts).
2. In `register.tsx`: a `density` atom from the store key `density` (`detailed` default). The controls row gains **≡ Dense** (`pane-density`, hotkey `d`) before Minimize; in the dense layout it reads **☰ Detailed**, and the controls row draws its buttons with `isCompact` (no box, underlined letter, hidden hotkey twin) on one line, **⇣ Compact** joining it. The dense pane draws the Now row, the controls line, each dense line as `<Text key="dense-<key>">` (`dense-next` for the last) and nothing else. The breakdown is not read in the dense layout.
3. On a session-id change, reload `mode`, `density` and `collapsed` from the store before drawing; open the pane when the stored mode is `pane`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 node --test plugins/dflow/tests/*.test.mjs && timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dflow/hooks/hud/view.mjs plugins/dflow/hooks/hud/register.tsx plugins/dflow/tests/hud.test.mjs plugins/dflow/hooks/hud/register.test.tsx
git commit -m "feat(dflow): add the HUD's dense layout"
```

### Task 10: The framed band

**Files:**
- Create: `plugins/dflow/hooks/hud/band.mjs`
- Modify: `plugins/dflow/hooks/hud/register.tsx` (the `AbovePrompt` render hook, Expand)
- Modify: `plugins/dflow/hooks/hud/view.mjs` (remove `bandText`, `tokens`, `bar`)
- Test: `plugins/dflow/tests/hud.test.mjs`
- Test: `plugins/dflow/hooks/hud/register.test.tsx`

**Interfaces:**
- Consumes: `meter.mjs`, `account.mjs`, `repo.mjs`, the atoms of Tasks 5-8, `world` (Contracts)
- Produces: `band.mjs` (Contracts)

**UI/UX:** UI-13, UI-14, UX-1

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

In `hud.test.mjs`, delete the test `the band fits its width and the mode cycles`, change the file's first `view.mjs` import line to `import { isFreshReset, isResetFor, nextMode } from '../hooks/hud/view.mjs';` (no second `nextMode` import), and add these tests, which keep its `nextMode` assertions:

```js
import { BAND_TIERS, bandLines, bandTop, bandWarning, fitBand } from '../hooks/hud/band.mjs';

const BAND_INPUT = {
  hud: PLAN_HUD,
  where: { cwd: '/home/me/code/shop', root: '/home/me/code/shop', home: '/home/me', remote: 'git@github.com:darkraise/shop.git' },
  repo: repoFromPorcelain(PORCELAIN),
  engine: { model: 'claude-opus-5-5', effort: 'xhigh' },
  account: accountFrom(CLAUDE_JSON, '', '/home/me'),
  remote: { clients: [{ surface: 'mobile' }], setting: null },
  context: { tokens: 118000, window: 1000000 },
  usage: { limits: [{ kind: 'five_hour', percent: 23, resetsAt: 1_000_000_000_000 + 3 * H + 40 * 60_000 }, { kind: 'seven_day', percent: 61, resetsAt: 1_000_000_000_000 + 4 * 24 * H }], usd: 1.2, startedAt: 1_000_000_000_000 - H },
  now: 1_000_000_000_000,
};

test('the band carries the folder, model, plan and workers, then the readings', () => {
  const [one, two] = bandLines(BAND_INPUT, 0).map(text);
  for (const part of ['~/code/shop', '⎇ feat/x', '↑3', 'Opus 5.5', 'xhigh', 'dflow 4/7 · Task 5', '● 1 worker']) assert.ok(one.includes(part), part);
  for (const part of ['ctx ', '79%', '5h ', '23% on pace', '7d ', '61%', '$1.20']) assert.ok(two.includes(part), part);
  assert.ok(!bandLines({ ...BAND_INPUT, hud: { ...PLAN_HUD, plan: null } }, 0).map(text)[0].includes('dflow'));
  assert.equal(text(bandTop(BAND_INPUT)), 'you@example.com · subscription · Remote ● connected');
});

test('each band line shrinks a tier at a time until it fits', () => {
  for (const width of [196, 116, 76, 44]) {
    for (const line of fitBand(BAND_INPUT, width)) assert.ok(cellWidth(text(line)) <= width, `${width}: ${text(line)}`);
  }
  const widths = Array.from({ length: BAND_TIERS }, (_, tier) => cellWidth(text(bandLines(BAND_INPUT, tier)[1])));
  assert.deepEqual([...widths].sort((a, b) => b - a), widths);
  assert.ok(text(fitBand(BAND_INPUT, 44)[0]).startsWith('shop'));
  const noReset = text(bandLines({ ...BAND_INPUT, hud: { ...PLAN_HUD, context: null } }, 0)[1]);
  assert.ok(noReset.startsWith('ctx ') && noReset.includes('118k of 1.0M') && !noReset.includes('NaN') && !noReset.includes('┃'));
});

test('a blocked task, failed gates or a darkmem conflict make a warning line', () => {
  assert.deepEqual(bandWarning({ ...PLAN_HUD, sync: { enabled: false } }).map(run => run.text).join(''), '✗ Task 6 blocked');
  const all = bandWarning({ ...PLAN_HUD, gates: { ok: false, stale: false, failed: ['lint'] }, sync: { enabled: true, conflict: 'c' } });
  assert.equal(text(all), '✗ Task 6 blocked · ✗ gates failed · ✗ darkmem conflict');
  assert.ok(all.filter(run => run.text !== ' · ').every(run => run.color === 'red'));
  assert.deepEqual(bandWarning({ ...PLAN_HUD, plan: { ...PLAN_HUD.plan, blocked: [] }, sync: { enabled: false } }), []);
  assert.deepEqual(['band', 'pane', 'off'].map(mode => nextMode(mode, '')), ['pane', 'off', 'band']);
  assert.deepEqual([nextMode('band', 'off'), nextMode('band', 'sideways')], ['off', null]);
});
```

In `register.test.tsx`, replace the test `the band shows the plan, progress, task and context` with:

```tsx
test('the band is framed in the account color with Expand on its top rule', async ($, on) => {
  const w = world(on, {
    files: { [HUD_FILE]: JSON.stringify(HUD), '/home/me/.claude.json': JSON.stringify({ oauthAccount: { emailAddress: 'you@example.com', billingType: 'stripe_subscription' } }) },
    porcelain: '# branch.head feat/x\n',
  })
  await $.session.start(START)
  await w.clock!.advance(10000)
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Text', text: /^╭─ you@example\.com · subscription/ })).toBeDefined()
  const rows = (await band.findAll({ type: 'Text' })).map((one: any) => one.text).filter((text: string) => /^[│╰].*[│╯]$/.test(text))
  expect(rows.length).toBe(4)
  for (const row of rows) expect([...row].length).toBe(BAND.props.bodyColumns)
  expect((await band.find({ key: 'band-line-0' }))?.text).toContain('dflow 4/7 · Task 5')
  expect((await band.find({ key: 'band-warning' }))?.text).toContain('✗ Task 6 blocked')
  expect((await band.find({ key: 'band-expand' }))?.props.hotkey).toBeUndefined()
  await band.press({ key: 'band-expand' })
  expect(w.stored.mode).toBe('pane')
  expect(w.calls).toContain('open dflow-hud')
  expect(w.calls).toContain('write /repo/.dflow/context/s1.json {"session":"s1","tokens":118000,"window":1000000,"at":"2026-11-12T12:00:00.000Z"}')
})

test('below 48 columns the band drops its frame', async ($, on) => {
  world(on, { files: { [HUD_FILE]: JSON.stringify(HUD), '/home/me/.claude.json': JSON.stringify({ oauthAccount: { emailAddress: 'you@example.com' } }) } })
  await $.session.start(START)
  const band = await $.ui.mount({ ...BAND, props: { ...BAND.props, bodyColumns: 47 }, surface: 'terminal' })
  const texts = (await band.findAll({ type: 'Text' })).map((one: any) => one.text)
  expect(texts.some((text: string) => /^[╭│╰]/.test(text))).toBe(false)
  expect(texts[0]).toMatch(/^you@example\.com/)
  for (const text of texts) expect([...text].length).toBeLessThanOrEqual(47)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 node --test plugins/dflow/tests/hud.test.mjs`
Expected: FAIL with `Cannot find module '../hooks/hud/band.mjs'`

- [ ] **Step 3: Implement**

1. `band.mjs`, modelled on the cockpit's `bandLines` and `fitBand` (`lib.ts:492-685`). Line 1 holds: the folder with `⎇ <branch>`, `*` when dirty and ` ↑N ↓N ~N ?N` (nonzero parts); `modelName(model)` and the effort; `dflow <done>/<total> · Task <n>` while a plan is active; `● N worker(s)` while any. Line 2 holds: `ctx ` + a meter with `┃` at `resetAt / window` + ` <pct>%` (without `hud.context.resetAt`: the meter with no `┃` + ` <kTokens(tokens)> of <kTokens(window)>`, and from tier 2 ` <kTokens(tokens)>` alone); `5h` and `7d`, each a meter with `┊` at the elapsed share + ` <pct>%` + ` on pace` or ` out in <duration>` + ` · <reset duration>`; `$<usd>`. `BAND_TIERS = 6`, each tier keeping the steps before it, in the spec's order:

   | Tier | Change |
   |---|---|
   | 0 | meters 8 cells, separators `  ·  `, the folder as `shortDir(where.cwd, home)` |
   | 1 | meters 4 cells, separators ` · ` |
   | 2 | no meters: the percent alone |
   | 3 | no reset durations, no `on pace` or `out in` |
   | 4 | the folder becomes the root folder's name, `repoName(null, root)` |
   | 5 | no model and no effort |

   `fitBand` takes, per line, the first tier whose `runsWidth ≤ width`, else `runsCut` of tier 5. `bandTop` = email, billing label and Remote, joined by ` · `, Remote short as the cockpit's band has it: `Remote ● connected` (green) with a device attached, `Remote ○ on` (green) when the setting is `true`, else `Remote ○ not connected` (dim). `bandWarning(hud)` = the red runs the test shows (`✗ Task N blocked` or `✗ N tasks blocked`, `✗ gates failed`, `✗ darkmem conflict` or `✗ darkmem refused`), joined by ` · ` (dim), empty when none holds.
2. In `register.tsx`, the `AbovePrompt` hook (mode `band`, a `.dflow` checkout, no survey) draws, keyed as Contracts says: with `bodyColumns ≥ 48`, `band-top` as `╭─ ` + the top runs cut to fit + `─` fill + ` ` + the **Expand** Button (`band-expand`, no hotkey, sets mode `pane`) + ` ─╮`; `band-line-0`, `band-line-1` (and `band-warning` when not empty) as `│ ` + the fitted runs padded to `bodyColumns - 4` cells + ` │`; and `╰` + `─` × (`bodyColumns - 2`) + `╯`, every frame glyph in `account.color`. Below 48 columns: a first row with the email and **Expand**, then the lines unframed, each cut to `bodyColumns`. The band draws with or without a plan, and only once a `Hud` has been read (before that it calls `next(e)`).
3. Delete `bandText`, `tokens` and `bar` from `view.mjs`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 node --test plugins/dflow/tests/*.test.mjs && timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dflow/hooks/hud/band.mjs plugins/dflow/hooks/hud/register.tsx plugins/dflow/hooks/hud/view.mjs plugins/dflow/tests/hud.test.mjs plugins/dflow/hooks/hud/register.test.tsx
git commit -m "feat(dflow): frame the HUD band in the cockpit's design"
```

### Task 11: The Sections view

**Files:**
- Modify: `plugins/dflow/hooks/hud/view.mjs` (the sections functions)
- Modify: `plugins/dflow/hooks/hud/register.tsx` (the Sections view, `/dflow:hud sections`)
- Modify: `plugins/dflow/types/index.d.ts`
- Test: `plugins/dflow/tests/hud.test.mjs`
- Test: `plugins/dflow/hooks/hud/register.test.tsx`

**Interfaces:**
- Consumes: `SECTIONS`, `drawButton`, `world` (Contracts)
- Produces: the Task 11 functions (Contracts)

**UI/UX:** UI-16, UX-11

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Add to `hud.test.mjs`:

```js
import { sectionsArg, sectionsFrom, sectionsMoved, sectionsToggled } from '../hooks/hud/view.mjs';

test('the sections list is parsed, toggled and moved', () => {
  assert.deepEqual(sectionsFrom(undefined), SECTIONS);
  assert.deepEqual(sectionsFrom([]), SECTIONS);
  assert.deepEqual(sectionsFrom(['repo', 'nope', 'plan', 'repo']), ['repo', 'plan']);
  assert.deepEqual(sectionsArg('plan, context,repo'), ['plan', 'context', 'repo']);
  assert.equal(sectionsArg('plan,shells'), null);
  assert.equal(sectionsArg(''), null);
  assert.deepEqual(sectionsToggled(['plan', 'context'], 'context'), ['plan']);
  assert.deepEqual(sectionsToggled(['plan', 'context'], 'repo'), ['plan', 'context', 'repo']);
  assert.deepEqual(sectionsMoved(['plan', 'context', 'repo'], 'plan', 1), ['context', 'plan', 'repo']);
  assert.deepEqual(sectionsMoved(['plan', 'context'], 'plan', -1), ['plan', 'context']);
});
```

Add to `register.test.tsx`:

```tsx
test('the Sections view hides, moves and resets the cards', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) }, usd: 1 })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ key: 'pane-sections-hotkey' }))?.props.hotkey).toBe('s')
  await pane.press({ key: 'pane-sections' })
  expect(await pane.find({ key: 'sections-account-up' })).toBeUndefined()
  expect(await pane.find({ key: 'sections-account-down' })).toBeDefined()
  await pane.press({ key: 'sections-usage-switch' })
  expect(w.stored.sections).not.toContain('usage')
  expect(await pane.find({ key: 'sections-usage-down' })).toBeUndefined()
  await pane.press({ key: 'sections-plan-down' })
  expect((w.stored.sections as string[]).slice(0, 3)).toEqual(['account', 'context', 'plan'])
  expect((await pane.find({ key: 'sections-back-hotkey' }))?.props.hotkey).toBe('b')
  await pane.press({ key: 'sections-back' })
  expect(await pane.find({ key: 'usage' })).toBeUndefined()
  await pane.press({ key: 'pane-density' })
  expect(await pane.find({ key: 'dense-usage' })).toBeUndefined()
  await pane.press({ key: 'pane-density' })
  await pane.press({ key: 'pane-sections' })
  await pane.press({ key: 'sections-reset' })
  expect(w.stored.sections).toEqual(['account', 'plan', 'context', 'usage', 'checks', 'board', 'workers', 'repo'])
  for (const key of ['account', 'plan', 'usage', 'checks', 'board', 'workers', 'repo']) await pane.press({ key: `sections-${key}-switch` })
  expect(w.stored.sections).toEqual(['context'])
  await pane.press({ key: 'sections-context-switch' })
  expect(w.stored.sections).toEqual(['context'])
  expect((await pane.find({ key: 'sections-context-switch' }))?.props.dimColor).toBe(true)
  await pane.press({ key: 'sections-reset' })
  await pane.press({ key: 'sections-context-switch' })
  await pane.press({ key: 'sections-back' })
  const reads = w.calls.filter(call => call === 'usage breakdown').length
  await w.clock!.advance(10000)
  expect(w.calls.filter(call => call === 'usage breakdown').length).toBe(reads)
})

test('/dflow:hud sections sets the list or names the valid cards', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) } })
  await $.session.start(START)
  expect((await $.command.run({ command: 'dflow:hud', args: 'sections plan,context,repo' })).text).toBe('dflow HUD sections: plan, context, repo')
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await pane.find({ key: 'checks' })).toBeUndefined()
  expect((await $.command.run({ command: 'dflow:hud', args: 'sections plan,shells' })).text).toBe('Sections: account, plan, context, usage, checks, board, workers, repo')
  expect(w.stored.sections).toEqual(['plan', 'context', 'repo'])
  w.isPaneUp = false
  await $.command.run({ command: 'dflow:hud', args: 'sections' })
  expect(w.isPaneUp).toBe(true)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 node --test plugins/dflow/tests/hud.test.mjs`
Expected: FAIL with `does not provide an export named 'sectionsArg'`

- [ ] **Step 3: Implement**

1. In `view.mjs`: `sectionsFrom(value)` (known keys, deduplicated, in the given order; empty or not an array → `SECTIONS`); `sectionsArg(text)` (comma-separated, trimmed; `null` when empty or any name is unknown); `sectionsToggled(list, key)` (remove when present, else append); `sectionsMoved(list, key, delta)` (swap with the neighbour; unchanged at an end).
2. In `register.tsx`: a `sections` atom from the store key `sections`; the detailed and dense layouts draw only shown cards, in its order (the Now, controls and Next rows always). A `view` atom (`cards` | `sections`). **⚙ Sections** (`pane-sections`, hotkey `s`) in the controls row between Dense and Minimize sets `view` to `sections`. The Sections view draws `⚙ Sections` bold, `Which cards the pane shows, in order.` dim, then per shown card a row with the switch Button (`sections-<key>-switch`, label `● On`, the label in `permission`), the card title, **↑** (`sections-<key>-up`, not on the first) and **↓** (`sections-<key>-down`, not on the last); then per hidden card, in `SECTIONS` order, the switch (`○ Off`, dim) and title only; then **Reset** (`sections-reset`, saves `SECTIONS`) and **Back** (`sections-back`, hotkey `b`; returns to `cards`, and closes the pane when it was opened for the view from mode `band`). Each press saves `sections` and invalidates `ui.render`. The last shown card cannot be turned off: its switch is drawn dim (`isOff`) and pressing it changes nothing, so the list is never empty (an empty stored list means the default). The breakdown read in Task 5 also requires `context` shown.
3. `command.run`: `sections` with no list opens the pane (`setMode($, 'pane')` when the mode is not `pane` or the pane is not up) on the Sections view and answers `dflow HUD: sections`; `sections <list>` saves it and answers `dflow HUD sections: <a, b, c>`; a bad list answers `Sections: account, plan, context, usage, checks, board, workers, repo` and changes nothing. The usage line becomes `Usage: /dflow:hud [band|pane|off|sections [<cards>]]`.
4. Add the atom types.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 node --test plugins/dflow/tests/*.test.mjs && timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dflow/hooks/hud/view.mjs plugins/dflow/hooks/hud/register.tsx plugins/dflow/types/index.d.ts plugins/dflow/tests/hud.test.mjs plugins/dflow/hooks/hud/register.test.tsx
git commit -m "feat(dflow): add the HUD's Sections view"
```

### Task 12: Resumable work

**Files:**
- Modify: `plugins/dflow/hooks/hud/view.mjs` (add `resumeOffer`, `isOfferOver`)
- Modify: `plugins/dflow/hooks/hud/register.tsx` (the offer, the resume card and band row)
- Modify: `plugins/dflow/types/index.d.ts`
- Test: `plugins/dflow/tests/hud.test.mjs`
- Test: `plugins/dflow/hooks/hud/register.test.tsx`

**Interfaces:**
- Consumes: `drawButton`, `world` (Contracts)
- Produces: `resumeOffer`, `isOfferOver` (Contracts)

**UI/UX:** UI-17, UX-12, UX-5

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Add to `hud.test.mjs`:

```js
import { isOfferOver, resumeOffer } from '../hooks/hud/view.mjs';

test('an approved, unfinished plan with a current task is offered for resuming', () => {
  const approved = { ...PLAN_HUD, plan: { ...PLAN_HUD.plan, approved: '2026-11-12' } };
  assert.deepEqual(resumeOffer(approved), { title: 'Rate-limit meter', next: 'Task 5: Wire the meter (in progress)' });
  assert.equal(resumeOffer({ ...approved, plan: { ...approved.plan, current: { number: 7, title: 'Draw the meter', state: 'todo' } } }).next, 'Task 7: Draw the meter (ready)');
  assert.equal(resumeOffer(PLAN_HUD), null);
  assert.equal(resumeOffer({ ...approved, plan: { ...approved.plan, done: 7, current: null } }), null);
  assert.equal(resumeOffer({ ...approved, plan: { ...approved.plan, current: null } }), null);
  assert.equal(resumeOffer({ ...approved, plan: null }), null);
  assert.equal(isOfferOver(approved, approved), false);
  assert.equal(isOfferOver(approved, { ...approved, plan: { ...approved.plan, done: 5 } }), true);
  assert.equal(isOfferOver(approved, { ...approved, plan: { ...approved.plan, current: { ...approved.plan.current, number: 6 } } }), true);
});
```

Add to `register.test.tsx` (`HUD` itself stays unapproved, so no earlier test sees an offer):

```tsx
const RESUMABLE = { ...HUD, plan: { ...HUD.plan, approved: '2026-11-12' } }

test('a session starting on an unfinished plan offers to resume it in the pane and the band', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(RESUMABLE) } })
  await $.session.start(START)
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await band.find({ type: 'Text', text: /↻ Resumable work · Rate-limit meter/ }))?.text).toContain('Next: Task 5: Wire the meter')
  expect((await band.find({ key: 'band-resume-go' }))?.props.hotkey).toBeUndefined()
  await band.unmount()
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ key: 'resume-go-hotkey' }))?.props.hotkey).toBe('r')
  const texts = (await pane.findAll({ type: 'Text' })).map((one: any) => one.text)
  expect(texts.findIndex((text: string) => text.startsWith('↻ Resumable work'))).toBeLessThan(texts.findIndex((text: string) => text.startsWith('● Task 5')))
  await pane.press({ key: 'resume-go' })
  expect(w.calls.filter(call => call === 'submit /dflow:build')).toHaveLength(1)
  expect(await pane.find({ key: 'resume-go' })).toBeUndefined()
  const after = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await after.find({ key: 'band-resume-go' })).toBeUndefined()
})

test('Dismiss removes the offer without submitting anything', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(RESUMABLE) } })
  await $.session.start(START)
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await band.press({ key: 'band-resume-dismiss' })
  expect(await band.find({ key: 'band-resume-go' })).toBeUndefined()
  expect(w.calls.some(call => call.startsWith('submit'))).toBe(false)
  await band.unmount()
  await $.session.compact({ trigger: 'manual', messages: [] })
  await w.clock!.advance(2000)
  const later = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await later.find({ key: 'band-resume-go' })).toBeUndefined()
})

test('no offer after a build runs, progress moves, or for an unapproved plan', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(RESUMABLE) } })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:build' })
  let band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ key: 'band-resume-go' })).toBeUndefined()
  await band.unmount()
  await $.session.compact({ trigger: 'manual', messages: [] })
  await w.clock!.advance(2000)
  band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ key: 'band-resume-go' })).toBeUndefined()
  await band.unmount()
  w.sessionId = 's2'
  await w.clock!.advance(2000)
  band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ key: 'band-resume-go' })).toBeDefined()
  await band.unmount()
  w.files[HUD_FILE] = JSON.stringify({ ...RESUMABLE, plan: { ...RESUMABLE.plan, done: 5 } })
  await w.clock!.advance(2000)
  band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ key: 'band-resume-go' })).toBeUndefined()
  await band.unmount()
  w.files[HUD_FILE] = JSON.stringify(HUD)
  w.sessionId = 's3'
  await w.clock!.advance(2000)
  band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ key: 'band-resume-go' })).toBeUndefined()
})

test('drawing the band and the pane makes no file, process or usage call', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) } })
  await $.session.start(START)
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const before = w.calls.length
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await pane.unmount()
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await band.unmount()
  expect(w.calls.slice(before)).toEqual([])
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 node --test plugins/dflow/tests/hud.test.mjs`
Expected: FAIL with `does not provide an export named 'resumeOffer'`

- [ ] **Step 3: Implement**

1. `resumeOffer(hud)`: `null` unless `plan.approved`, `plan.done < plan.total` and `plan.current`; else `{ title: plan.title, next: 'Task N: <title> (<in progress | ready>)' }`. `isOfferOver(start, hud)`: true when `hud.plan` is null, its `done` differs from `start.plan.done`, or its current task number differs.
2. In `register.tsx`, an `offer` atom (`{ title, next, start } | null`) set from `resumeOffer` at session start and on a session-id change (after `hud.json` is read), never on a compaction. It is cleared, for the session, by **Resume**, **Dismiss**, a `command.run` of `dflow:build` (an observing hook that calls `next(e)`), or a poll where `isOfferOver(start, hud)` holds.
3. The pane (both layouts) draws, above the Now row, a Box with `borderStyle="round" borderColor="permission"`: `↻ Resumable work · <title>` bold in `permission`, `Next: <next>`, then **Resume** (`resume-go`, hotkey `r`, `isMain`) and **Dismiss** (`resume-dismiss`). In mode `band` the `AbovePrompt` hook draws above the band one framed row in `permission`: `↻ Resumable work · <title> — Next: <next>` (without the parenthesis), **Resume** (`band-resume-go`) and **Dismiss** (`band-resume-dismiss`), no hotkeys. **Resume** calls `$.prompt.submit({ text: '/dflow:build', asUser: true })` once and clears the offer. Mode `off` draws nothing.
4. Add the atom type.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 node --test plugins/dflow/tests/*.test.mjs && timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dflow/hooks/hud/view.mjs plugins/dflow/hooks/hud/register.tsx plugins/dflow/types/index.d.ts plugins/dflow/tests/hud.test.mjs plugins/dflow/hooks/hud/register.test.tsx
git commit -m "feat(dflow): offer to resume an unfinished plan"
```

### Task 13: Documentation

**Files:**
- Modify: `plugins/dflow/README.md` (the `## HUD` section)
- Modify: `docs/dflow/design.md` (`## 14. HUD`)
- Modify: `plugins/dflow/skills/hud/SKILL.md` (the `description` and `argument-hint` lines)

**Interfaces:**
- Consumes: none
- Produces: none

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 1 - spec 1 - coupling 0 - risk 0 = 2

- [ ] **Step 1: No new test, because the README and design prose are read by no script, and the skill's frontmatter fields `plugins/dflow/tests/skills.test.mjs::SKILLS` reads (name, `disable-model-invocation`) do not change**

- [ ] **Step 2: Run the existing checks before editing**

Run: `timeout 300 node --test plugins/dflow/tests/skills.test.mjs`
Expected: PASS

- [ ] **Step 3: Implement**

1. `plugins/dflow/README.md` `## HUD`: replace the paragraph with: the modes (`/dflow:hud` cycles band, pane, off, and reopens a pane closed by hand; `/dflow:hud band|pane|off`; `/dflow:hud sections [<cards>]`); the pane's cards in order with one line each, as the spec's card table says; the buttons and hotkeys (`c` Compact, `d` Dense/Detailed, `s` Sections, `m` Minimize, `r` Resume, `b` Back); the band's two lines and its warning line; the resumable-work offer; that it draws only in a checkout with `.dflow`; and the cost (no model tokens; git every ten seconds and the breakdown only while shown).
2. `docs/dflow/design.md` `## 14. HUD`: replace the mockup and bullets with the spec's band mockup and the pane outline (the Now row, the eight cards, the Next row), and the modes, keeping the paragraphs about the `hud` skill and the context governor.
3. `skills/hud/SKILL.md`: `description` becomes `Show or switch the dflow HUD - a framed band above the prompt or a pane of cards with the account, plan, context, usage, checks, board, workers and repo. \`/dflow:hud [band|pane|off|sections [<cards>]]\`.`; `argument-hint` becomes `"[band|pane|off|sections [<cards>]]"`.

- [ ] **Step 4: Run the checks**

Run: `timeout 300 node --test plugins/dflow/tests/skills.test.mjs && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate plugins/dflow`
Expected: PASS, and both validators report no error

- [ ] **Step 5: Commit**

```bash
git add plugins/dflow/README.md docs/dflow/design.md plugins/dflow/skills/hud/SKILL.md
git commit -m "docs(dflow): describe the overhauled HUD" -m "Also carries the owner's uncommitted changes in README.md and design.md."
```

### Task 14: Proof of the HUD in a nested session

**Files:**
- Create: `docs/dforge/ui-ux/proofs/2026-11-13-dflow-hud.md`
- Create: `plugins/dflow/tests/fixtures/hud-worst.json`
- Create: `docs/dforge/ui-ux/proofs/2026-11-13-dflow-hud.judge.md` (the judge seat writes it)
- Create: `.dforge/ui-ux/dflow-hud/*.ansi` (captures, not committed)

**Interfaces:**
- Consumes: every earlier task
- Produces: none

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 0 = 4

- [ ] **Step 1: No new test, because this task proves the demo statements A31, A33 and A35 in the running UI; every `test` statement has its own test in Tasks 1-12**

- [ ] **Step 2: Run the suites the proof stands on**

Run: `timeout 300 node --test plugins/dflow/tests/*.test.mjs && timeout 120 /root/.local/bin/claude plugin test plugins/dflow`
Expected: PASS

- [ ] **Step 3: Walk the HUD**

1. Create `plugins/dflow/tests/fixtures/hud-worst.json` holding the spec's UX-10 worst case: a 40-task plan (Tasks 1-19 `done`, Task 20 `wip` with `attempts: 3`, Task 21 `blocked`, Task 22 `todo` with `run: "worker"`, the rest `todo`), titles of 120 characters, Task 20's title holding `🚀` and `é ñ ü`, Task 19's title the unbroken identifier `aVeryLongUnbrokenIdentifierThatHasNoSpacesAnywhereInItAtAll_0123456789abcdef0123456`, Task 21's reason 200 characters, `done: 19`, `total: 40`, `approved: "2026-11-12"`, 12 workers on Tasks 22-33 with branches `dflow/w22`…`dflow/w33`, gates `{ "ok": false, "stale": false, "failed": ["lint", "unit-tests", "integration-tests", "e2e", "typecheck"] }`, board counts for `todo`, `doing`, `review`, `blocked`, `done`, `dropped`, sync `{ "enabled": true, "queued": 3, "conflict": "board row 12" }`, the 80-character branch `feature/an-eighty-character-branch-name-that-keeps-going-and-going-to-test-cut-x`, `context: { "resetAt": 150000 }`, `checks: []`, `review: { "recorded": null, "open": 0, "blocking": 0 }`.
2. Follow `dforge:ui-ux`'s walkthrough with the profile `docs/dforge/ui-ux/profile.md` and the memory note on nested sessions: in a throwaway copy of a dflow fixture repository (made with `plugins/dflow/tests/helpers.mjs`'s `makeProject` layout, never this repository), start `/root/.local/bin/claude --plugin-dir plugins/dflow` in tmux at 200x60 and at 120x40, seed `.dflow/hud.json` with each state (plan running, all done, blocked with gates failed and a darkmem conflict, no plan, and `plugins/dflow/tests/fixtures/hud-worst.json`), with the throwaway repository checked out on the fixture's 80-character branch and a `CLAUDE_CONFIG_DIR` whose `.claude.json` holds a 60-character `oauthAccount.emailAddress` (the nested-session memory note's settings isolation), and capture with `tmux capture-pane -e -p` to `.dforge/ui-ux/dflow-hud/<state>-<size>.ansi`: the band, the pane (`/dflow:hud pane`), a collapsed card, the dense layout, the Sections view, and the resume offer after `/clear`.
3. Write the proof report from the template the walkthrough names: `**Contract:** feature`, the spec's `## UI/UX contract` IDs, one Results row per ID with its capture paths or test names, OP-3 checked on a `NO_COLOR=1` capture, A33 (no Status button) and A35 (no Discord or settings beyond Sections) noted on the pane captures.
4. Run `bash /root/.claude-alt2/plugins/cache/darkraise/dforge/4.17.1/scripts/ui-proof stamp docs/dforge/ui-ux/proofs/2026-11-13-dflow-hud.md`, then dispatch the judge seat the walkthrough names on the report.
5. Kill the tmux session and every process the walkthrough started.

- [ ] **Step 4: Run the gate**

Run: `bash /root/.claude-alt2/plugins/cache/darkraise/dforge/4.17.1/scripts/ui-proof check --base e562459b --spec docs/dforge/specs/2026-11-13-dflow-hud-overhaul-design.md`
Expected: exit 0

- [ ] **Step 5: Commit**

```bash
git add docs/dforge/ui-ux/proofs/2026-11-13-dflow-hud.md docs/dforge/ui-ux/proofs/2026-11-13-dflow-hud.judge.md plugins/dflow/tests/fixtures/hud-worst.json
git commit -m "docs(dflow): prove the overhauled HUD"
```
