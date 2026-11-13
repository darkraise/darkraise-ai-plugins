import { expect, mock, test } from 'claude-code/testing'

import { accountColor } from './account.mjs'
import { cellWidth } from './meter.mjs'

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

const BAND = {
  plugin: 'dflow',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isCollapsed: false,
    isWorking: false,
    maxRows: 3,
    bodyColumns: 100,
    scroll: { offset: 0, bodyRows: 3 },
    view: {},
  },
} as const

const PANE = {
  plugin: 'dflow',
  component: 'Pane',
  requestId: 'dflow-hud',
  props: {
    title: 'dflow',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 20 },
    view: {},
  },
} as const

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
    // A compaction leaves at least one message, or the engine skips the hook.
    return { messages: e.messages?.length ? e.messages : [{ role: 'user', text: 'Summary.', toolUses: [] }] }
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

const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
const TURN = { answer: 'done', durationMs: 1, isAborted: false, reason: 'answer' } as const

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

test('/dflow:hud cycles band, pane, off and keeps the choice', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) } })
  await $.session.start(START)

  expect((await $.command.run({ command: 'dflow:hud' })).text).toBe('dflow HUD: pane')
  expect(w.stored.mode).toBe('pane')
  expect(w.calls).toContain('open dflow-hud')

  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ key: 'plan-headline' }))?.text).toBe('4/7 · 1 blocked')
  expect((await pane.find({ key: 'next' }))?.text).toBe('Next  /dflow:build — Task 5: Wire the meter')
  await pane.unmount()

  expect((await $.command.run({ command: 'dflow:hud' })).text).toBe('dflow HUD: off')
  expect(w.calls).toContain('close dflow-hud')
  expect((await $.command.run({ command: 'dflow:hud', args: 'sideways' })).text).toBe(
    'Usage: /dflow:hud [band|pane|off]',
  )
  expect((await $.command.run({ command: 'dflow:hud', args: 'band' })).text).toBe(
    'dflow HUD: band',
  )
})

test('a fresh reset flag is cleared at the end of a turn; a stale one is left', async ($, on) => {
  const files: Record<string, string> = {
    '/repo/.dflow/hud.json': JSON.stringify(HUD),
    '/repo/.dflow/reset.json': JSON.stringify({ plan: 'meter', at: '2026-11-12T11:59:00.000Z' }),
  }
  world(on, { files })
  await $.session.start(START)
  await $.turn.complete({ ...TURN, turnId: 't1' })
  expect(files['/repo/.dflow/reset.json']).toBe('{}')

  files['/repo/.dflow/reset.json'] = JSON.stringify({ plan: 'meter', at: '2026-11-12T09:00:00.000Z' })
  await $.turn.complete({ ...TURN, turnId: 't2' })
  expect(JSON.parse(files['/repo/.dflow/reset.json']).plan).toBe('meter')

  files['/repo/.dflow/reset.json'] = JSON.stringify({ plan: 'meter', at: '2026-11-12T11:59:30.000Z' })
  await $.turn.complete({ ...TURN, turnId: 't3', agentId: 'a1' })
  expect(JSON.parse(files['/repo/.dflow/reset.json']).plan).toBe('meter')

  // A flag another session asked for is that session's to act on.
  files['/repo/.dflow/reset.json'] = JSON.stringify({ plan: 'meter', session: 's2', at: '2026-11-12T11:59:30.000Z' })
  await $.turn.complete({ ...TURN, turnId: 't4' })
  expect(JSON.parse(files['/repo/.dflow/reset.json']).session).toBe('s2')

  files['/repo/.dflow/reset.json'] = JSON.stringify({ plan: 'meter', session: 's1', at: '2026-11-12T11:59:30.000Z' })
  await $.turn.complete({ ...TURN, turnId: 't5' })
  expect(files['/repo/.dflow/reset.json']).toBe('{}')
})

test('with no dflow directory the mod draws nothing and writes nothing', async ($, on) => {
  const w = world(on, { files: {}, hasState: false })
  on('ui.render', ($: any, e: any) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })
  await $.session.start(START)

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('engine')
  await ui.unmount()
  expect(w.calls.filter(call => call.startsWith('write'))).toEqual([])
})

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

test('before hud.json exists the pane says how to start and the band draws nothing', async ($, on) => {
  world(on, { files: {} })
  on('ui.render', ($: any, e: any) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })
  await $.session.start(START)
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await band.findAll({ type: 'Text' })).map((one: any) => one.text)).toEqual(['engine'])
  await band.unmount()
  await $.command.run({ command: 'dflow:hud', args: 'pane' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const texts = (await pane.findAll({ type: 'Text' })).map((one: any) => one.text)
  expect(texts).toEqual(['dflow has no state in this repository yet.', 'Run /dflow:init, then /dflow:plan.'])
})

test('a Hud read earlier is dropped once hud.json is gone', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify({ ...HUD, plan: { ...HUD.plan, approved: '2026-11-12' } }) } })
  on('ui.render', ($: any, e: any) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })
  await $.session.start(START)
  delete w.files[HUD_FILE]
  w.sessionId = 's2'
  await w.clock!.advance(2000)
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await band.findAll({ type: 'Text' })).map((one: any) => one.text)).toEqual(['engine'])
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
  const texts = await pane.findAll({ type: 'Text' })
  const rows = (await pane.findAll({ type: 'Box' })).filter((one: any) => /^(plan|workers|checks)-row-\d+$/.test(String(one.key)))
  expect(rows.length).toBeGreaterThan(8)
  for (const row of rows) {
    expect(texts.some((one: any) => one.text === row.text && one.props.wrap === 'truncate-end')).toBe(true)
    expect(cellWidth(row.text)).toBeLessThanOrEqual(36)
  }
  expect((await pane.find({ key: 'plan-headline' }))?.text).toBe('19/40 · 1 blocked')
})

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

test('mode off runs no git read beyond locating the root', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) }, porcelain: '# branch.head feat/x\n', remoteUrl: 'git@github.com:darkraise/shop.git' })
  w.stored.mode = 'off'
  await $.session.start(START)
  await w.clock!.advance(20000)
  expect(w.calls.filter(call => call.startsWith('git ') && !call.includes('rev-parse'))).toEqual([])
})

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

test('a checkout without .dflow runs no git status', async ($, on) => {
  const w = world(on, { files: {}, hasState: false, porcelain: '# branch.head feat/x\n' })
  await $.session.start(START)
  await w.clock!.advance(20000)
  expect(w.calls.filter(call => call.includes(GIT_STATUS))).toEqual([])
})

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
  expect(w.calls.filter(call => call === 'command /dflow:build')).toHaveLength(1)
  expect(w.calls.some(call => call.startsWith('submit'))).toBe(false)
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
