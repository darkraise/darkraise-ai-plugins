import { expect, mock, test } from 'claude-code/testing'

const HUD = {
  branch: 'feat/x',
  next: '/dflow:build — Task 5: Wire the meter',
  plan: {
    title: 'Rate-limit meter',
    file: 'docs/dflow/plans/meter.md',
    done: 4,
    total: 7,
    current: { number: 5, title: 'Wire the meter', state: 'wip', attempts: 1 },
    blocked: [{ number: 6, reason: 'no API key' }],
  },
  gates: null,
  review: { recorded: null, open: 0, blocking: 0 },
  board: { counts: { doing: 1, open: 3 }, row: { number: 12, state: 'doing' } },
  sync: { enabled: false },
  context: { resetAt: 150000 },
  workers: [],
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

const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
const TURN = { answer: 'done', durationMs: 1, isAborted: false, reason: 'answer' } as const

test('the band shows the plan, progress, task and context', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) } })
  await $.session.start(START)

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  const line = await ui.find({ type: 'Text', text: /dflow/ })
  expect(line?.text).toBe(
    'dflow ▸ Rate-limit meter · █████░░░ 4/7 · Task 5 wip · verify failed 1× · 1 blocked · ctx 118k/150k',
  )
  await ui.unmount()

  expect(w.calls).toContain(
    'write /repo/.dflow/context/s1.json {"session":"s1","tokens":118000,"window":1000000,"at":"2026-11-12T12:00:00.000Z"}',
  )
})

test('/dflow:hud cycles band, pane, off and keeps the choice', async ($, on) => {
  const w = world(on, { files: { [HUD_FILE]: JSON.stringify(HUD) } })
  await $.session.start(START)

  expect((await $.command.run({ command: 'dflow:hud' })).text).toBe('dflow HUD: pane')
  expect(w.stored.mode).toBe('pane')
  expect(w.calls).toContain('open dflow-hud')

  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ type: 'Text', text: /^Plan/ }))?.text).toBe(
    'Plan     ████████░░░░░░ 4/7 · Task 5 wip · verify failed 1×',
  )
  expect((await pane.find({ type: 'Text', text: /^Blocked/ }))?.text).toBe(
    'Blocked  Task 6: no API key',
  )
  expect((await pane.find({ type: 'Text', text: /^Next/ }))?.text).toBe(
    'Next     /dflow:build — Task 5: Wire the meter',
  )
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
