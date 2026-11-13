import { expect, test } from 'claude-code/testing'

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

// Each hook stands for the engine beneath the mod.
function engine(on: any, files: Record<string, string>, hasState = true) {
  const calls: string[] = []
  const stored: Record<string, unknown> = {}

  on('session.start', (_: unknown, e: any) => ({ cwd: e.cwd }))
  on('turn.complete', (_: unknown, e: any) => ({ text: e.answer }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: '/repo\n', stderr: '' } }))
  on('session.id', () => ({ value: 's1' }))
  on('session.usage', () => ({
    value: { startedAt: 0, context: { tokens: 118000, window: 1000000 }, rateLimits: [] },
  }))
  on('clock.now', () => ({ value: Date.parse('2026-11-12T12:00:00.000Z') }))
  // No timer fires in a test: the poll and the compaction are not under test.
  on('clock.every', () => ({ deny: 'no timers in tests' }))
  on('clock.after', () => ({ deny: 'no timers in tests' }))
  on('fs.exists', (_: unknown, e: any) => ({
    value: hasState && (e.path === '/repo/.dflow' || e.path in files),
  }))
  on('fs.read', (_: unknown, e: any) => ({ value: files[e.path] }))
  on('fs.write', (_: unknown, e: any) => {
    calls.push(`write ${e.path} ${e.text}`)
    files[e.path] = e.text

    return { value: undefined }
  })
  on('store.get', (_: unknown, e: any) => ({ value: stored[e.key] }))
  on('store.set', (_: unknown, e: any) => {
    stored[e.key] = e.value

    return { value: undefined }
  })
  on('ui.open', (_: unknown, e: any) => {
    calls.push(`open ${e.id}`)

    return { value: { isPlaced: true } }
  })
  on('ui.close', (_: unknown, e: any) => {
    calls.push(`close ${e.id}`)

    return { value: undefined }
  })

  return { calls, stored }
}

const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
const TURN = { answer: 'done', durationMs: 1, isAborted: false, reason: 'answer' } as const

test('the band shows the plan, progress, task and context', async ($, on) => {
  const { calls } = engine(on, { '/repo/.dflow/hud.json': JSON.stringify(HUD) })
  await $.session.start(START)

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  const line = await ui.find({ type: 'Text', text: /dflow/ })
  expect(line?.text).toBe(
    'dflow ▸ Rate-limit meter · █████░░░ 4/7 · Task 5 wip · verify failed 1× · 1 blocked · ctx 118k/150k',
  )
  await ui.unmount()

  expect(calls[0]).toBe(
    'write /repo/.dflow/context/s1.json {"session":"s1","tokens":118000,"window":1000000,"at":"2026-11-12T12:00:00.000Z"}',
  )
})

test('/dflow:hud cycles band, pane, off and keeps the choice', async ($, on) => {
  const { calls, stored } = engine(on, { '/repo/.dflow/hud.json': JSON.stringify(HUD) })
  await $.session.start(START)

  expect((await $.command.run({ command: 'dflow:hud' })).text).toBe('dflow HUD: pane')
  expect(stored.mode).toBe('pane')
  expect(calls).toContain('open dflow-hud')

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
  expect(calls).toContain('close dflow-hud')
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
  engine(on, files)
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
  const { calls } = engine(on, {}, false)
  on('ui.render', ($: any, e: any) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })
  await $.session.start(START)

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('engine')
  await ui.unmount()
  expect(calls.length).toBe(0)
})
