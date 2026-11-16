import { describe, expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'
import type { On, RenderElement, SessionMessage } from 'claude-code'

// Acceptance tests for docs/dforge/specs/2026-11-09-clean-session-phases-design.md,
// the cockpit statements (A1, A2, A13). They reach the cockpit only through the
// engine's events: the auto-run state file it reads, the scripts/auto-run calls
// it makes, the commands it runs and the prompts it submits. The auto-run
// script is simulated by its documented exit codes and state changes.

const START = { cwd: '/home/me/code/shop/web', surface: 'terminal', isInteractive: true } as never
const SUMMARY: SessionMessage = { role: 'user', text: 'Summary.', toolUses: [] }
const AUTO = '/home/me/code/shop/.dforge/sdd/auto-run.json'
const SWITCH_ANSWER = 'Plan saved.\n\nAuto run: switching'
const FIRST_PROMPT = 'Execute docs/plan.md with dforge:subagent-driven-development.'
const FAILURE_CAP = 2

type World = {
  prompts: string[]
  autoRuns: string[]
  compacts: string[]
  commands: string[]
  sessionId: string
  /** Exit codes by auto-run verb; a verb not listed exits 0. */
  exits: Record<string, number>
  autoFile: { text: string }
}

function switchState(fields: Record<string, unknown> = {}) {
  return {
    text: JSON.stringify({
      active: true,
      session: 'sess-1',
      phase: 'execute',
      regime: 'normal',
      pending: 'switch',
      plan: 'docs/plan.md',
      compactions: 0,
      resumes: 0,
      failures: 0,
      rebind: false,
      setupDue: true,
      stopped: null,
      resumePrompt: FIRST_PROMPT,
      launch: { model: 'sonnet', effort: 'high' },
      ...fields,
    }),
  }
}

const stateOf = (w: World) => JSON.parse(w.autoFile.text) as Record<string, unknown>

function world(on: On, w: World) {
  mock.env(on, { HOME: '/home/me' })
  const clock = mock.clock(on, { now: 1_000_000 })
  on('command.register', () => ({ value: undefined }) as never)
  on('session.start', (_$, e) => e as never)
  on('session.usage', () => ({ value: { startedAt: 0, context: { tokens: 284_000, window: 650_000 }, rateLimits: [], cost: { usd: 1.5 } } }))
  on('settings.read', () => ({ value: { effortLevel: 'xhigh' } }))
  on('tool.call', () => ({ result: 'ok', text: 'ok' }) as never)
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'agent-1' }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('prompt.submit', (_$, e) => {
    w.prompts.push(e.text)
    return { text: e.text }
  })
  on('session.attach', (_$, e) => ({ clientId: e.clientId }))
  on('session.detach', (_$, e) => ({ clientId: e.clientId }))
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('config.list', () => ({ value: [] }) as never)
  on('ui.open', () => ({ value: { isPlaced: true } }) as never)
  on('ui.close', () => ({ value: undefined }) as never)
  on('ui.panes', () => ({ value: [] }))
  on('session.compact', (_$, e) => {
    w.compacts.push(`${e.trigger}:${(e as { instructions?: string }).instructions ?? ''}`)
    return { messages: e.messages ?? [SUMMARY] }
  })
  on('command.run', (_$, e) => {
    w.commands.push(e.args === '' ? `/${e.command}` : `/${e.command} ${e.args}`)
    if (e.command === 'clear') w.sessionId = 'sess-2'
    return { text: '' } as never
  })
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('session.id', () => ({ value: w.sessionId }))
  on('session.cwd', () => ({ value: '/home/me/code/shop/web' }))
  on('session.repo', () => ({ value: { root: '/home/me/code/shop', remote: null, internal: false, name: null } }))
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
  on('fs.read', (_$, e) => {
    if (e.path === AUTO) return { value: w.autoFile.text }
    if (e.path === '/home/me/.claude.json') {
      return { value: JSON.stringify({ oauthAccount: { emailAddress: 'me@example.com', displayName: 'Me', organizationName: 'Acme', organizationRole: 'admin', billingType: 'stripe_subscription' } }) }
    }
    throw new Error('ENOENT')
  })
  on('fs.stat', (_$, e) => {
    if (e.path === AUTO) return { value: { kind: 'file', size: w.autoFile.text.length, mtimeMs: 0, isLink: false } }
    throw new Error('ENOENT')
  })
  on('fs.list', () => {
    throw new Error('ENOENT')
  })
  on('fs.write', () => ({ value: undefined }))
  on('http.fetch', () => ({ value: { status: 200, ok: true, headers: {}, text: '{"id":"m1"}' } }))
  on('session.append', (_$, e, next) => next(e))
  on('ui.toast', () => ({ value: undefined }))
  on('process.run', (_$, e) => {
    const argv = e.argv.join(' ')
    const script = '/scripts/auto-run '
    const result = (exitCode: number, stdout = '') => ({ value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } })
    if (argv.includes(script)) {
      const call = argv.slice(argv.indexOf(script) + script.length)
      w.autoRuns.push(call)
      const words = call.split(' ')
      const verb = words[2] ?? ''
      const exitCode = verb === 'failure' ? 0 : (w.exits[verb] ?? 0)
      const state = stateOf(w)
      if (verb === 'clear' && exitCode === 0) Object.assign(state, { pending: 'clear', rebind: true })
      if (verb === 'rebind') Object.assign(state, { session: words[4], pending: 'resume' })
      if (verb === 'resumed' && state.pending === 'resume') state.pending = null
      if (verb === 'compacted') Object.assign(state, { pending: 'after-compact', compactions: Number(state.compactions) + 1 })
      if (verb === 'failure') {
        state.failures = Number(state.failures ?? 0) + 1
        if (Number(state.failures) >= FAILURE_CAP) {
          Object.assign(state, { active: false, pending: null, stopped: call.split(' --reason ')[1] ?? null })
          w.autoFile.text = JSON.stringify(state)
          return result(5)
        }
      }
      w.autoFile.text = JSON.stringify(state)
      return result(exitCode)
    }
    if (argv === 'node --version') return result(0, 'v24.18.0\n')
    const toplevel = /^git -C (.+) rev-parse --show-toplevel$/.exec(argv)
    if (toplevel !== null) return result(0, `${toplevel[1]}\n`)
    if (argv === 'git rev-parse --show-toplevel') return result(0, '/home/me/code/shop\n')
    if (argv.startsWith('git rev-parse')) return result(0, '/home/me/code/shop/.git\n')
    return result(0, '# branch.oid abc1234def\n# branch.head main\n')
  })
  on('ui.render', ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    if (e.component === 'PromptHint') return h(Text, {}, e.props.tail ?? '') as RenderElement
    return h(Box, { key: 'engine' }) as RenderElement
  })
  return clock
}

const fresh = (state: { text: string }, exits: Record<string, number> = {}): World => ({
  prompts: [],
  autoRuns: [],
  compacts: [],
  commands: [],
  sessionId: 'sess-1',
  exits,
  autoFile: state,
})

/** Lets timers at the current instant fire and their work finish. */
async function settle(clock: ReturnType<typeof world>) {
  for (let i = 0; i < 10; i++) await clock.advance(1)
}

const finishSwitchTurn = ($: Parameters<TestBody>[0]) =>
  $.turn.complete({ answer: SWITCH_ANSWER, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' } as never)

const clearCalls = (w: World) => w.autoRuns.filter(call => call.endsWith(' clear --phase'))
const failureCalls = (w: World) => w.autoRuns.filter(call => call.includes(' failure '))

describe('clean-session-phases: the switch clears the session', () => {
  test('A1: with switch pending the cockpit clears, binds the new session and submits the first prompt on the launch model and effort', async ($, on) => {
    const w = fresh(switchState())
    const clock = world(on, w)
    await $.session.start(START)
    await finishSwitchTurn($)
    await settle(clock)
    expect(w.commands).toEqual(['/clear', '/model sonnet', '/effort high'])
    expect(w.autoRuns).toContain('--session sess-1 clear --phase')
    expect(w.autoRuns).toContain('--session sess-2 rebind --to sess-2')
    expect(w.prompts).toEqual([FIRST_PROMPT])
    expect(stateOf(w).session).toBe('sess-2')
    expect(stateOf(w).pending).toBeNull()
  })

  test('A2: with switch pending the cockpit makes no compaction call and the prompt carries no after-compact instruction', async ($, on) => {
    const w = fresh(switchState())
    const clock = world(on, w)
    await $.session.start(START)
    await finishSwitchTurn($)
    await settle(clock)
    await clock.advance(60_000)
    await settle(clock)
    expect(w.prompts).toEqual([FIRST_PROMPT])
    expect(w.compacts).toEqual([])
    expect(w.commands.filter(command => /compact/i.test(command))).toEqual([])
    expect(w.autoRuns.filter(call => call.split(' ')[2] === 'compacted')).toEqual([])
    expect(w.autoRuns.filter(call => /compact/i.test(call))).toEqual([])
    for (const prompt of w.prompts) expect(prompt).not.toMatch(/after-compact|compact/i)
  })

  test('A2: an engine compaction over a pending switch is not booked as a compaction', async ($, on) => {
    const w = fresh(switchState())
    world(on, w)
    await $.session.start(START)
    await $.session.compact({ trigger: 'auto', messages: [SUMMARY] })
    expect(w.autoRuns.filter(call => call.split(' ')[2] === 'compacted')).toEqual([])
    expect(stateOf(w).pending).toBe('switch')
  })

  test('A13: a first clear --phase failure books one failure and retries; a second failure stops the run with a reason naming the switch', async ($, on) => {
    const w = fresh(switchState(), { clear: 1 })
    const clock = world(on, w)
    await $.session.start(START)
    await finishSwitchTurn($)
    await settle(clock)
    expect(clearCalls(w)).toHaveLength(1)
    expect(failureCalls(w)).toHaveLength(1)
    expect(failureCalls(w)[0]).toMatch(/--reason .*switch/i)
    expect(stateOf(w).pending).toBe('switch')
    expect(stateOf(w).active).toBe(true)
    expect(w.compacts).toEqual([])
    expect(w.prompts).toEqual([])
    for (let second = 0; second < 60 && clearCalls(w).length < 2; second++) {
      await clock.advance(1_000)
      await settle(clock)
    }
    expect(clearCalls(w)).toHaveLength(2)
    expect(failureCalls(w)).toHaveLength(2)
    expect(failureCalls(w)[1]).toMatch(/--reason .*switch/i)
    expect(stateOf(w).active).toBe(false)
    expect(String(stateOf(w).stopped)).toMatch(/switch/i)
    expect(w.commands).toEqual([])
    expect(w.compacts).toEqual([])
  })

  test('A13: a second failure is not followed by a third clear attempt', async ($, on) => {
    const w = fresh(switchState(), { clear: 1 })
    const clock = world(on, w)
    await $.session.start(START)
    await finishSwitchTurn($)
    await settle(clock)
    for (let second = 0; second < 90; second++) {
      await clock.advance(1_000)
      await settle(clock)
    }
    expect(clearCalls(w)).toHaveLength(2)
    expect(failureCalls(w)).toHaveLength(2)
  })
})
