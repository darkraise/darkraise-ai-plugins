import { describe, expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'
import type { On, RenderElement, SessionMessage } from 'claude-code'

// Acceptance tests for docs/dforge/specs/2026-10-26-task-loop-steps-design.md,
// the cockpit statements (A12, A13). They reach the watchdog only through the
// engine's events: a bound auto run is the auto-run state file naming the
// session, background work is an Agent or Bash launch with run_in_background,
// and a submitted reconcile prompt is what the engine's prompt.submit receives.

const START = { cwd: '/home/me/code/shop/web', surface: 'terminal', isInteractive: true } as never
const SUMMARY: SessionMessage = { role: 'user', text: 'Summary.', toolUses: [] }
const AUTO = '/home/me/code/shop/.dforge/sdd/auto-run.json'
const SENTINEL = 'Task 3: complete.\n\nAuto run: compacting'
const MIN = 60_000

type World = {
  prompts: string[]
  autoRuns: string[]
  compacts: string[]
  /** The auto-run state file, or none when no auto run exists. */
  autoFile?: { text: string }
}

function autoState(fields: Record<string, unknown> = {}) {
  return {
    text: JSON.stringify({
      active: true,
      session: 'sess-1',
      phase: 'execute',
      regime: 'normal',
      pending: null,
      plan: 'docs/plan.md',
      compactions: 0,
      resumes: 0,
      stopped: null,
      resumePrompt: null,
      launch: null,
      ...fields,
    }),
  }
}

function world(on: On, w: World) {
  mock.env(on, { HOME: '/home/me' })
  const clock = mock.clock(on, { now: 1_000_000 })
  on('command.register', () => ({ value: undefined }) as never)
  on('session.start', (_$, e) => e as never)
  on('session.usage', () => ({ value: { startedAt: 0, context: { tokens: 284_000, window: 650_000 }, rateLimits: [], cost: { usd: 1.5 } } }))
  on('settings.read', () => ({ value: { effortLevel: 'xhigh' } }))
  on('tool.call', () => ({ result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b9w1' }, text: 'Running in the background' }))
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
  on('command.run', () => ({ text: '' }) as never)
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('session.id', () => ({ value: 'sess-1' }))
  on('session.cwd', () => ({ value: '/home/me/code/shop/web' }))
  on('session.repo', () => ({ value: { root: '/home/me/code/shop', remote: null, internal: false, name: null } }))
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
  on('fs.read', (_$, e) => {
    if (e.path === AUTO && w.autoFile !== undefined) return { value: w.autoFile.text }
    if (e.path === '/home/me/.claude.json') {
      return { value: JSON.stringify({ oauthAccount: { emailAddress: 'me@example.com', displayName: 'Me', organizationName: 'Acme', organizationRole: 'admin', billingType: 'stripe_subscription' } }) }
    }
    throw new Error('ENOENT')
  })
  on('fs.stat', (_$, e) => {
    if (e.path === AUTO && w.autoFile !== undefined) return { value: { kind: 'file', size: w.autoFile.text.length, mtimeMs: 0, isLink: false } }
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
    const ok = { value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    if (argv.includes(script)) {
      const call = argv.slice(argv.indexOf(script) + script.length)
      w.autoRuns.push(call)
      const word = call.split(' ')[2] ?? ''
      if (w.autoFile !== undefined) {
        const state = JSON.parse(w.autoFile.text) as Record<string, unknown>
        if (word === 'compacted') Object.assign(state, { pending: 'after-compact', compactions: Number(state.compactions) + 1 })
        if (word === 'stalled') Object.assign(state, { stalls: Number(state.stalls ?? 0) + 1, stalledAt: Math.floor(clock.now() / 1000) })
        w.autoFile.text = JSON.stringify(state)
      }
      return ok
    }
    if (argv === 'node --version') return { value: { exitCode: 0, stdout: 'v24.18.0\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    const toplevel = /^git -C (.+) rev-parse --show-toplevel$/.exec(argv)
    if (toplevel !== null) return { value: { exitCode: 0, stdout: `${toplevel[1]}\n`, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    if (argv === 'git rev-parse --show-toplevel') return { value: { exitCode: 0, stdout: '/home/me/code/shop\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    if (argv.startsWith('git rev-parse')) return { value: { exitCode: 0, stdout: '/home/me/code/shop/.git\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    return { value: { exitCode: 0, stdout: '# branch.oid abc1234def\n# branch.head main\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.render', ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    if (e.component === 'PromptHint') return h(Text, {}, e.props.tail ?? '') as RenderElement
    return h(Box, { key: 'engine' }) as RenderElement
  })
  return clock
}

const fresh = (autoFile?: { text: string }): World => ({ prompts: [], autoRuns: [], compacts: [], autoFile })

/** Lets timers at the current instant fire and their work finish. */
async function settle(clock: ReturnType<typeof world>) {
  for (let i = 0; i < 10; i++) await clock.advance(1)
}

const failures = (w: World) => w.autoRuns.filter(call => call.includes(' failure '))

const launchAgent = ($: Parameters<TestBody>[0]) =>
  $.agent.spawn({
    tool_use_id: 'toolu_1',
    prompt: 'Implement task 4',
    description: 'Task 4',
    subagentType: 'dforge:impl-sonnet-low',
    provider: { plugin: 'dforge', tier: 'user' },
    parentModel: 'claude-opus-5-5',
    background: true,
    fork: false,
  })

const answer = (turnId: string, text = 'Waiting for the implementer.') =>
  ({ answer: text, durationMs: 1, isAborted: false, turnId, reason: 'answer' }) as never

describe('task-loop steps: the cockpit reconcile prompt', () => {
  for (const holder of ['agent', 'shell'] as const) {
    test(`A12: one reconcile prompt after 20 minutes of only a background ${holder} holding a bound run, and no second within 20 minutes`, async ($, on) => {
      const w = fresh(autoState())
      const clock = world(on, w)
      await $.session.start(START)
      if (holder === 'agent') await launchAgent($)
      else await $.tool.call({ tool: 'Bash', command: 'npm test', run_in_background: true } as never)
      await $.turn.complete(answer('t1'))
      await clock.advance(19 * MIN)
      await settle(clock)
      expect(w.prompts).toEqual([])
      for (let minute = 0; minute < 6 && w.prompts.length === 0; minute++) {
        await clock.advance(MIN)
        await settle(clock)
      }
      expect(w.prompts).toHaveLength(1)
      expect(w.prompts[0]).toContain('scripts/in-flight')
      expect(w.prompts[0]).toMatch(/idle 30 minutes or more/)
      expect(w.prompts[0]).toMatch(/20 minutes/)
      await clock.advance(19 * MIN)
      await settle(clock)
      expect(w.prompts).toHaveLength(1)
    })
  }

  test('A12: a bound run with no stage pending is reconciled too', async ($, on) => {
    const w = fresh(autoState({ pending: null }))
    const clock = world(on, w)
    await $.session.start(START)
    await launchAgent($)
    await $.turn.complete(answer('t1'))
    await clock.advance(25 * MIN)
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts[0]).toContain('scripts/in-flight')
  })

  test('A13: no reconcile prompt outside an auto run', async ($, on) => {
    const inactive = fresh(autoState({ active: false }))
    const clock = world(on, inactive)
    await $.session.start(START)
    await launchAgent($)
    await $.turn.complete(answer('t1'))
    await clock.advance(40 * MIN)
    expect(inactive.prompts).toEqual([])
  })

  test('A13: no reconcile prompt when no auto run exists', async ($, on) => {
    const w = fresh(undefined)
    const clock = world(on, w)
    await $.session.start(START)
    await launchAgent($)
    await $.turn.complete(answer('t1'))
    await clock.advance(40 * MIN)
    expect(w.prompts).toEqual([])
  })

  test('A13: no reconcile prompt while a turn is live', async ($, on) => {
    const w = fresh(autoState())
    const clock = world(on, w)
    await $.session.start(START)
    await launchAgent($)
    await $.turn.complete(answer('t1'))
    await $.turn.start({ text: 'How is Task 4 going?', turnId: 't2' })
    await clock.advance(40 * MIN)
    expect(w.prompts).toEqual([])
    await $.turn.complete(answer('t2', 'Still waiting.'))
    await clock.advance(25 * MIN)
    expect(w.prompts).toHaveLength(1)
  })

  test("A13: with a stage pending, the reconcile prompt comes before the stage's 30-minute failure", async ($, on) => {
    const w = fresh(autoState({ pending: 'compact' }))
    const clock = world(on, w)
    await $.session.start(START)
    await launchAgent($)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' } as never)
    await settle(clock)
    await clock.advance(19 * MIN)
    expect(w.prompts).toEqual([])
    expect(failures(w)).toEqual([])
    await clock.advance(3 * MIN)
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts[0]).toContain('scripts/in-flight')
    expect(failures(w)).toEqual([])
    expect(w.compacts).toEqual([])
  })

  test('A13: the third consecutive reconcile with nothing stopped books the failure instead of a fourth prompt', async ($, on) => {
    const w = fresh(autoState({ pending: 'compact' }))
    const clock = world(on, w)
    await $.session.start(START)
    await launchAgent($)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' } as never)
    await settle(clock)
    // Waits in one-minute steps for the next prompt, or a failure, for at most 30 minutes.
    const untilNext = async () => {
      const seen = w.prompts.length
      for (let minute = 0; minute < 30 && w.prompts.length === seen && failures(w).length === 0; minute++) {
        await clock.advance(MIN)
        await settle(clock)
      }
    }
    for (let round = 1; round <= 3; round++) {
      await untilNext()
      expect(w.prompts).toHaveLength(round)
      expect(failures(w)).toEqual([])
      // The reconcile turn: it runs, stops nothing, and ends with the launch still running.
      await $.turn.start({ text: w.prompts[round - 1]!, turnId: `r${round}` })
      await clock.advance(2 * MIN)
      await $.turn.complete(answer(`r${round}`, 'Nothing is idle for 30 minutes; still waiting.'))
    }
    await untilNext()
    expect(w.prompts).toHaveLength(3)
    expect(failures(w)).toHaveLength(1)
  })
})
