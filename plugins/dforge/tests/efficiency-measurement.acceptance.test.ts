import { describe, expect, mock, test } from 'claude-code/testing'
import type { On, RenderElement } from 'claude-code'
import API_ERROR_RECORDS from './fixtures/api-error-transcript.mjs'

// Acceptance tests for the efficiency-measurement-and-polish spec, A17's
// cockpit half: a turn that ends with reason `error` whose last assistant record
// carries isApiErrorMessage is re-prompted within 60 seconds and booked through
// `auto-run api-error` (never as a stall); an empty answer without that record
// stays a stall; the first answer after the errors clears the count. The cockpit
// is reached only through the engine's events; the auto-run script is
// simulated by its documented verbs, and the transcript is the one the session
// record names.

const START = { cwd: '/home/me/code/shop/web', surface: 'terminal', isInteractive: true } as never
const AUTO = '/home/me/code/shop/.dforge/sdd/auto-run.json'
const RECORD = '/home/me/.claude/dforge/sessions/by-id/sess-1.json'
const TRANSCRIPT = '/home/me/.claude/projects/p/sess-1.jsonl'
// Records copied from a real session transcript around a turn that ended on an API error.
const ERROR_TEXT = API_ERROR_RECORDS.map(one => JSON.stringify(one)).join('\n') + '\n'
const NO_ERROR_TEXT = `${JSON.stringify(API_ERROR_RECORDS[0])}\n`

type World = { prompts: string[]; autoRuns: string[]; transcript: string; state: { text: string } }

function runState(): { text: string } {
  return {
    text: JSON.stringify({
      active: true, session: 'sess-1', phase: 'execute', regime: 'normal', pending: null, plan: 'docs/plan.md',
      compactions: 0, resumes: 0, failures: 0, stalls: 0, apiErrors: 0, rebind: false, setupDue: false, stopped: null, resumePrompt: null, launch: null,
    }),
  }
}

function world(on: On, w: World) {
  mock.env(on, { HOME: '/home/me' })
  const clock = mock.clock(on, { now: 1_000_000 })
  on('command.register', () => ({ value: undefined }) as never)
  on('session.start', (_$, e) => e as never)
  on('session.usage', () => ({ value: { startedAt: 0, context: { tokens: 100_000, window: 650_000 }, rateLimits: [], cost: { usd: 1.5 } } }))
  on('settings.read', () => ({ value: { effortLevel: 'xhigh' } }))
  on('tool.call', () => ({ result: 'ok', text: 'ok' }) as never)
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
  on('session.compact', (_$, e) => ({ messages: e.messages ?? [{ role: 'user', text: 'Summary.', toolUses: [] }] }))
  on('command.run', () => ({ text: '' }) as never)
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('session.id', () => ({ value: 'sess-1' }))
  on('session.cwd', () => ({ value: '/home/me/code/shop/web' }))
  on('session.repo', () => ({ value: { root: '/home/me/code/shop', remote: null, internal: false, name: null } }))
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
  on('fs.read', (_$, e) => {
    if (e.path === AUTO) return { value: w.state.text }
    if (e.path === RECORD) return { value: JSON.stringify({ session_id: 'sess-1', transcript_path: TRANSCRIPT }) }
    if (e.path === TRANSCRIPT) return { value: w.transcript }
    if (e.path === '/home/me/.claude.json') {
      return { value: JSON.stringify({ oauthAccount: { emailAddress: 'me@example.com', displayName: 'Me', organizationName: 'Acme', organizationRole: 'admin', billingType: 'stripe_subscription' } }) }
    }
    throw new Error('ENOENT')
  })
  on('fs.stat', (_$, e) => {
    if (e.path === AUTO) return { value: { kind: 'file', size: w.state.text.length, mtimeMs: 0, isLink: false } }
    if (e.path === TRANSCRIPT) return { value: { kind: 'file', size: w.transcript.length, mtimeMs: 0, isLink: false } }
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
    const result = (exitCode: number, stdout = '') => ({ value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } })
    if (argv.includes(TRANSCRIPT)) return result(0, w.transcript)
    const script = '/scripts/auto-run '
    if (argv.includes(script)) {
      const call = argv.slice(argv.indexOf(script) + script.length)
      w.autoRuns.push(call)
      const verb = call.split(' ')[2] ?? ''
      const state = JSON.parse(w.state.text) as Record<string, unknown>
      if (verb === 'stalled') Object.assign(state, { stalls: Number(state.stalls ?? 0) + 1, stalledAt: Math.floor(clock.now() / 1000) })
      if (verb === 'api-error' && call.includes('--clear')) state.apiErrors = 0
      else if (verb === 'api-error') state.apiErrors = Number(state.apiErrors ?? 0) + 1
      w.state.text = JSON.stringify(state)
      return result(0)
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

const fresh = (transcript: string): World => ({ prompts: [], autoRuns: [], transcript, state: runState() })
const apiErrorCalls = (w: World) => w.autoRuns.filter(call => call.includes(' api-error') && !call.includes('--clear'))
const clearCalls = (w: World) => w.autoRuns.filter(call => call.includes(' api-error --clear'))
const stalledCalls = (w: World) => w.autoRuns.filter(call => call.includes(' stalled'))

describe('efficiency-measurement: API-error endings (A17)', () => {
  test('A17: a turn ending on an API error with the record is re-prompted within 60 seconds and booked as an api-error, not a stall', async ($, on) => {
    const w = fresh(ERROR_TEXT)
    const clock = world(on, w)
    await $.session.start(START)
    await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'error' })
    await clock.advance(60_000)
    expect(apiErrorCalls(w)).toHaveLength(1)
    expect(w.prompts).toHaveLength(1)
    expect(stalledCalls(w)).toEqual([])
    expect((JSON.parse(w.state.text) as { stalls: number }).stalls).toBe(0)
    expect((JSON.parse(w.state.text) as { apiErrors: number }).apiErrors).toBe(1)
  })

  test('A17: an empty answer without the API-error record still counts as a stall', async ($, on) => {
    const w = fresh(NO_ERROR_TEXT)
    const clock = world(on, w)
    await $.session.start(START)
    await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(240_000)
    expect(stalledCalls(w).length).toBeGreaterThan(0)
    expect(apiErrorCalls(w)).toEqual([])
  })

  test('A17: an error ending whose last record is not the API-error record is no api-error', async ($, on) => {
    const w = fresh(NO_ERROR_TEXT)
    const clock = world(on, w)
    await $.session.start(START)
    await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'error' })
    await clock.advance(240_000)
    expect(apiErrorCalls(w)).toEqual([])
  })

  test('A17: the first main turn that ends with reason answer clears the count', async ($, on) => {
    const w = fresh(ERROR_TEXT)
    const clock = world(on, w)
    await $.session.start(START)
    await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'error' })
    await clock.advance(60_000)
    expect(clearCalls(w)).toEqual([])
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't2', reason: 'answer' })
    await $.turn.complete({ answer: 'Task 4: complete.', durationMs: 1, isAborted: false, turnId: 't3', reason: 'answer' })
    expect(clearCalls(w).length).toBeGreaterThanOrEqual(1)
    expect((JSON.parse(w.state.text) as { apiErrors: number }).apiErrors).toBe(0)
  })
})
