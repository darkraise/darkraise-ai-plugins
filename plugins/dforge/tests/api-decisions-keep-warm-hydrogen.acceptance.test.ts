import { describe, expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'
import type { On, RenderElement } from 'claude-code'

// Acceptance tests for docs/dforge/specs/2026-11-14-api-decisions-keep-warm-hydrogen-design.md,
// the cockpit keep-warm statements (A21 to A24). They reach the cockpit only through the
// engine's events: the settings file it reads, the auto-run state file, the tool calls that
// start background shells, the turns it is told about and the prompts and webhook requests
// it sends. The engine is simulated by the documented behaviour of those events.

const START = { cwd: '/home/me/code/shop/web', surface: 'terminal', isInteractive: true } as never
const CONFIG = '/home/me/.dforge/config.json'
const AUTO = '/home/me/code/shop/.dforge/sdd/auto-run.json'
const MIN = 60_000
const KEEP_WARM =
  'Keep-warm: background work is still running and the prompt cache is about to expire. Reply with the single line `Still waiting.` and end the turn. Start nothing and call no tool.'
const SHELL = { result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b7k2' }, text: 'Running in the background' }
const ENDED = '<task-notification>\n<task-id>b7k2</task-id>\n<status>completed</status>\n<summary>done</summary>\n</task-notification>'
const WEBHOOK = 'https://discord.com/api/webhooks/123456789012/abcDEF_token-x'

type World = {
  prompts: string[]
  fetches: { url: string; body: Record<string, unknown> }[]
  config: Record<string, unknown>
  files: Record<string, string>
}

const boundRun = JSON.stringify({
  active: true,
  session: 'sess-1',
  phase: 'execute',
  regime: 'normal',
  pending: null,
  plan: 'docs/plan.md',
  compactions: 0,
  resumes: 0,
  failures: 0,
  rebind: false,
  stopped: null,
  resumePrompt: null,
  launch: null,
})

function world(on: On, w: World) {
  mock.env(on, { HOME: '/home/me' })
  const clock = mock.clock(on, { now: 1_000_000 })
  on('command.register', () => ({ value: undefined }) as never)
  on('session.start', (_$, e) => e as never)
  on('session.usage', () => ({ value: { startedAt: 0, context: { tokens: 50_000, window: 650_000 }, rateLimits: [], cost: { usd: 1.5 } } }))
  on('settings.read', () => ({ value: { effortLevel: 'xhigh' } }))
  on('tool.call', (_$, e) => (e.tool === 'Bash' ? SHELL : { result: 'ok', text: 'ok' }) as never)
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'agent-1' }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('prompt.submit', (_$, e) => {
    w.prompts.push(e.text)
    return { text: e.text }
  })
  on('prompt.read', () => ({ value: { text: '', cursor: 0 } }))
  on('session.attach', (_$, e) => ({ clientId: e.clientId }))
  on('session.detach', (_$, e) => ({ clientId: e.clientId }))
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('config.list', () => ({ value: [] }) as never)
  on('ui.open', () => ({ value: { isPlaced: true } }) as never)
  on('ui.close', () => ({ value: undefined }) as never)
  on('ui.panes', () => ({ value: [] }))
  on('session.compact', (_$, e) => ({ messages: e.messages ?? [] }))
  on('command.run', () => ({ text: '' }) as never)
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('session.id', () => ({ value: 'sess-1' }))
  on('session.cwd', () => ({ value: '/home/me/code/shop/web' }))
  on('session.repo', () => ({ value: { root: '/home/me/code/shop', remote: null, internal: false, name: null } }))
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
  const allFiles = () => ({ ...w.files, [CONFIG]: JSON.stringify(w.config) })
  on('fs.exists', (_$, e) => ({ value: e.path in allFiles() }))
  on('fs.read', (_$, e) => {
    const text = (allFiles() as Record<string, string | undefined>)[e.path]
    if (text !== undefined) return { value: text }
    if (e.path === '/home/me/.claude.json') {
      return { value: JSON.stringify({ oauthAccount: { emailAddress: 'me@example.com', displayName: 'Me', organizationName: 'Acme', organizationRole: 'admin', billingType: 'stripe_subscription' } }) }
    }
    throw new Error('ENOENT')
  })
  on('fs.stat', (_$, e) => {
    const text = (allFiles() as Record<string, string | undefined>)[e.path]
    if (text === undefined) throw new Error('ENOENT')
    return { value: { kind: 'file', size: text.length, mtimeMs: 0, isLink: false } }
  })
  on('fs.list', () => {
    throw new Error('ENOENT')
  })
  on('fs.write', () => ({ value: undefined }))
  on('http.fetch', (_$, e) => {
    w.fetches.push({ url: e.url, body: JSON.parse(String(e.init?.body ?? '{}')) as Record<string, unknown> })
    return { value: { status: 200, ok: true, headers: {}, text: '{"id":"m1"}' } }
  })
  on('session.append', (_$, e, next) => next(e))
  on('ui.toast', () => ({ value: undefined }))
  on('process.run', (_$, e) => {
    const argv = e.argv.join(' ')
    const result = (exitCode: number, stdout = '') => ({ value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } })
    if (argv.includes('/scripts/auto-run ')) return result(0)
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

const fresh = (config: Record<string, unknown>): World => ({ prompts: [], fetches: [], config, files: {} })
const keepWarmsOf = (w: World) => w.prompts.filter(one => one === KEEP_WARM)
type Clock = ReturnType<typeof world>

// A turn that sends a command to the background and ends with the command still running.
async function beginWaiting($: Parameters<TestBody>[0], command = 'npm test') {
  await $.session.start(START)
  await $.turn.start({ text: 'run it', turnId: 't1' })
  await $.tool.call({ tool: 'Bash', command, run_in_background: true } as never)
  await $.turn.complete({ answer: 'Started it.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
}

// The turn the engine starts for the cockpit's own submitted prompt.
async function keepWarmTurn($: Parameters<TestBody>[0], clock: Clock, turnId: string) {
  await $.turn.start({ text: KEEP_WARM, turnId })
  await clock.advance(2_000)
  await $.turn.complete({ answer: 'Still waiting.', durationMs: 2_000, isAborted: false, turnId, reason: 'answer' })
}

// A turn of another origin: the person's prompt, or a task notification, and the turn it starts.
async function otherTurn($: Parameters<TestBody>[0], origin: 'composer' | 'task-notification', turnId: string) {
  await $.prompt.submit({ text: 'status?', origin: { kind: origin }, wait: false } as never)
  await $.turn.start({ text: 'status?', turnId })
  await $.turn.complete({ answer: 'Still running.', durationMs: 1, isAborted: false, turnId, reason: 'answer' })
}

const notified = (text: string) =>
  ({
    message: { type: 'user', role: 'user', content: [{ type: 'text', text }] },
    door: 'prompt',
    origin: { kind: 'task-notification' },
    uuid: `row-${text.length}`,
  }) as never

describe('api-decisions-keep-warm-hydrogen: keep-warm', () => {
  test('A21: with keepWarm=50 and a main-loop background shell running, the keep-warm prompt goes once after 50 minutes and once more per further 50', async ($, on) => {
    const w = fresh({ keepWarm: 50 })
    const clock = world(on, w)
    await beginWaiting($)
    await clock.advance(49 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(0)
    await clock.advance(2 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(1)
    await keepWarmTurn($, clock, 'k1')
    await clock.advance(47 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(1)
    await clock.advance(4 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(2)
    await keepWarmTurn($, clock, 'k2')
    await clock.advance(51 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(3)
  })

  test('A22: no keep-warm prompt when keepWarm is 0', async ($, on) => {
    const w = fresh({ keepWarm: 0 })
    const clock = world(on, w)
    await beginWaiting($)
    await clock.advance(180 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(0)
  })

  test('A22: no keep-warm prompt while an auto run is bound to the session', async ($, on) => {
    const w = fresh({ keepWarm: 50 })
    w.files[AUTO] = boundRun
    const clock = world(on, w)
    await beginWaiting($)
    await clock.advance(180 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(0)
  })

  test('A22: no keep-warm prompt while a turn is live', async ($, on) => {
    const w = fresh({ keepWarm: 50 })
    const clock = world(on, w)
    await beginWaiting($)
    await $.turn.start({ text: 'and the docs?', turnId: 't2' })
    await clock.advance(100 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(0)
    await $.turn.complete({ answer: 'Docs done.', durationMs: 1, isAborted: false, turnId: 't2', reason: 'answer' })
    await clock.advance(51 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(1)
  })

  test('A22: no keep-warm prompt while the session waits on the person', async ($, on) => {
    const w = fresh({ keepWarm: 50 })
    on('tool.check', (_$, e, next) => (e.tool_use_id === 'toolu_9' ? { decision: 'ask' } : next(e)))
    const clock = world(on, w)
    await beginWaiting($)
    await $.turn.start({ text: 'list the files', turnId: 't2' })
    await $.tool.check({ tool: 'Bash', input: { command: 'ls' }, tool_use_id: 'toolu_9' })
    await clock.advance(100 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(0)
    await $.tool.call({ tool: 'Bash', command: 'ls', tool_use_id: 'toolu_9' } as never)
    await $.turn.complete({ answer: 'Listed.', durationMs: 1, isAborted: false, turnId: 't2', reason: 'answer' })
    await clock.advance(51 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(1)
  })

  test('A22: no keep-warm prompt when only a service command runs in the background', async ($, on) => {
    const w = fresh({ keepWarm: 50 })
    const clock = world(on, w)
    await beginWaiting($, 'npm run dev')
    await clock.advance(180 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(0)
  })

  test('A22: no keep-warm prompt when no background work runs', async ($, on) => {
    const w = fresh({ keepWarm: 50 })
    const clock = world(on, w)
    await $.session.start(START)
    await $.turn.start({ text: 'hello', turnId: 't1' })
    await $.turn.complete({ answer: 'Hello.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(180 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(0)
  })

  test('A22: no seventh keep-warm prompt after six with no turn of another origin between', async ($, on) => {
    const w = fresh({ keepWarm: 4 })
    const clock = world(on, w)
    await beginWaiting($)
    for (let i = 1; i <= 10; i++) {
      await clock.advance(5 * MIN)
      if (keepWarmsOf(w).length === i) await keepWarmTurn($, clock, `k${i}`)
    }
    expect(keepWarmsOf(w)).toHaveLength(6)
    await clock.advance(120 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(6)
  })

  for (const origin of ['composer', 'task-notification'] as const)
    test(`A23: a ${origin} turn resets the keep-warm count, so a later wait sends six again and no more`, async ($, on) => {
      const w = fresh({ keepWarm: 4 })
      const clock = world(on, w)
      await beginWaiting($)
      for (let i = 1; i <= 8; i++) {
        await clock.advance(5 * MIN)
        if (keepWarmsOf(w).length === i) await keepWarmTurn($, clock, `k${i}`)
      }
      expect(keepWarmsOf(w)).toHaveLength(6)
      await otherTurn($, origin, 'u1')
      for (let i = 7; i <= 16; i++) {
        await clock.advance(5 * MIN)
        if (keepWarmsOf(w).length === i) await keepWarmTurn($, clock, `k${i}`)
      }
      expect(keepWarmsOf(w)).toHaveLength(12)
    })

  test('A24: a keep-warm turn leaves the held Done in place and does not become its text', async ($, on) => {
    const w = fresh({ keepWarm: 4, notifyAfter: 0 })
    const clock = world(on, w)
    mock.store(on, { notifyUrl: WEBHOOK })
    await beginWaiting($, 'node codex-companion.mjs review')
    await clock.advance(5 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(1)
    await keepWarmTurn($, clock, 'k1')
    expect(w.fetches).toHaveLength(0)
    await $.session.append(notified(ENDED))
    await clock.advance(6_000)
    expect(w.fetches).toHaveLength(1)
    const embed = (w.fetches[0]?.body.embeds as Record<string, unknown>[])[0]
    expect(embed?.description).toBe('Started it.')
    expect(JSON.stringify(w.fetches[0]?.body)).not.toContain('Still waiting.')
  })

  test('A24: a keep-warm turn sends no Done notification of its own', async ($, on) => {
    const w = fresh({ keepWarm: 50, notifyAfter: 0 })
    const clock = world(on, w)
    mock.store(on, { notifyUrl: WEBHOOK })
    await beginWaiting($)
    await clock.advance(51 * MIN)
    expect(keepWarmsOf(w)).toHaveLength(1)
    const before = w.fetches.length
    await keepWarmTurn($, clock, 'k1')
    await clock.advance(30_000)
    expect(w.fetches).toHaveLength(before)
  })
})
