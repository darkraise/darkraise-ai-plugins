import { describe, expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'
import type { On, RenderElement } from 'claude-code'

// Acceptance tests for docs/dforge/specs/2026-11-25-auto-run-cleanup-and-long-runs-design.md,
// the cockpit statements of plan 1 (A2, A10, A11, A12, A14, A44). They reach
// the cockpit only through the engine's events: the files it reads (the
// session's run binding, the auto-run state file, a plan's ledger), the
// scripts/auto-run calls it makes (the directory travels in argv), the
// commands it runs, the prompts it submits and the rows it appends. The
// script is simulated by its documented behaviour: `due` books a compaction
// and prints `due: limit=<n> hard=<n> pending=<action>` (exit 6 when it
// booked), state-only verbs work from any directory, `clear` refuses a
// directory outside the run's checkout with exit 7, `cd-prefix` prints
// `cd '<checkout>' && ` for a run outside the session's starting directory.

const HOME = '/home/me'
const A_ROOT = '/home/me/code/other'
const B_ROOT = '/home/me/code/shop'
const A_CWD = `${A_ROOT}/web`
const B_CWD = `${B_ROOT}/web`
const START_IN = (cwd: string) => ({ cwd, surface: 'terminal', isInteractive: true }) as never
const BINDING = (id: string) => `${HOME}/.claude/dforge/sessions/run/${id}.json`
const AUTO = `${B_ROOT}/.dforge/sdd/auto-run.json`
const FIRST_PROMPT = 'Execute docs/plan.md with dforge:executing-plans.'
const SENTINEL = (stage: string) => `Stage done.\n\nAuto run: ${stage}`
const CD_B = `cd '${B_ROOT}' &&`

type World = {
  /** Where the session started and the root of the repository it started in. */
  cwd: string
  root: string
  tokens: number
  window: number
  sessionId: string
  /** What scripts/auto-run due answers: the run's limit and hard. */
  due: { limit: number; hard: number }
  files: Record<string, { text: string }>
  rows: { type: string; text: string }[]
  prompts: string[]
  commands: string[]
  compacts: string[]
  /** Every scripts/auto-run call: the directory it ran in, the words after the script, the exit code. */
  calls: { dir: string; words: string[]; exit: number }[]
  /** What the script prints for cd-prefix. */
  cdPrefix: string
  unknown: string[]
}

const runState = (fields: Record<string, unknown> = {}) => ({
  text: JSON.stringify({
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
    setupDue: false,
    stopped: null,
    resumePrompt: FIRST_PROMPT,
    launch: { model: 'sonnet', effort: 'high' },
    ...fields,
  }),
})

const binding = (primary: string) => ({ text: JSON.stringify({ primary, nonce: 'n-1', at: 1 }) })

const primaryOf = (dir: string) => (dir.startsWith(B_ROOT) ? B_ROOT : dir.startsWith(A_ROOT) ? A_ROOT : dir)
const stateOf = (w: World) => JSON.parse(w.files[AUTO]!.text) as Record<string, unknown>

function world(on: On, w: World) {
  mock.env(on, { HOME })
  const clock = mock.clock(on, { now: 1_000_000 })
  const result = (exitCode: number, stdout = '') => ({ value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } })
  on('command.register', () => ({ value: undefined }) as never)
  on('session.start', (_$, e) => e as never)
  on('session.usage', () => ({ value: { startedAt: 0, context: { tokens: w.tokens, window: w.window }, rateLimits: [], cost: { usd: 1.5 } } }))
  on('settings.read', () => ({ value: { effortLevel: 'xhigh', autoCompactWindow: 800_000 } }))
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
    w.compacts.push(String(e.trigger))
    return { messages: e.messages ?? [{ role: 'user', text: 'Summary.', toolUses: [] }] }
  })
  on('command.run', (_$, e) => {
    w.commands.push(e.args === '' ? `/${e.command}` : `/${e.command} ${e.args}`)
    if (e.command === 'clear') w.sessionId = 'sess-2'
    return { text: '' } as never
  })
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('session.id', () => ({ value: w.sessionId }))
  on('session.cwd', () => ({ value: w.cwd }))
  on('session.repo', () => ({ value: { root: w.root, remote: null, internal: false, name: null } }))
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
  on('fs.read', (_$, e) => {
    const file = w.files[e.path]
    if (file !== undefined) return { value: file.text }
    if (e.path === `${HOME}/.claude.json`) {
      return { value: JSON.stringify({ oauthAccount: { emailAddress: 'me@example.com', displayName: 'Me', organizationName: 'Acme', organizationRole: 'admin', billingType: 'stripe_subscription' } }) }
    }
    throw new Error('ENOENT')
  })
  on('fs.stat', (_$, e) => {
    const file = w.files[e.path]
    if (file !== undefined) return { value: { kind: 'file', size: file.text.length, mtimeMs: 2_000_000, isLink: false } }
    if (e.path === B_ROOT || e.path === A_ROOT || e.path === w.cwd) return { value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false } }
    throw new Error('ENOENT')
  })
  on('fs.list', (_$, e) => {
    const prefix = `${e.path.replace(/\/$/, '')}/`
    const names = new Set<string>()
    for (const path of Object.keys(w.files)) if (path.startsWith(prefix)) names.add(path.slice(prefix.length).split('/')[0]!)
    if (names.size === 0) throw new Error('ENOENT')
    return { value: [...names].map(name => ({ name, kind: w.files[`${prefix}${name}`] !== undefined ? 'file' : 'dir' })) } as never
  })
  on('fs.write', (_$, e) => {
    w.files[e.path] = { text: e.text }
    return { value: undefined }
  })
  on('http.fetch', () => ({ value: { status: 200, ok: true, headers: {}, text: '{"id":"m1"}' } }))
  on('session.append', (_$, e, next) => {
    const message = (e as { message?: { type?: string; content?: { type: string; text?: string }[] } }).message
    const text = message?.content?.map(part => part.text ?? '').join('') ?? ''
    w.rows.push({ type: message?.type ?? '', text })
    return next(e)
  })
  on('ui.toast', () => ({ value: undefined }))
  on('process.run', (_$, e) => {
    const argv = e.argv
    const script = argv.findIndex(word => word.endsWith('/scripts/auto-run'))
    if (script > 0) {
      const dir = argv[script - 1]!
      const words = argv.slice(script + 1)
      const verb = words[2] ?? ''
      const finish = (exit: number, stdout = '') => {
        w.calls.push({ dir, words: words.slice(2), exit })
        return result(exit, stdout)
      }
      if (!(AUTO in w.files)) return finish(3)
      const state = stateOf(w)
      const save = () => {
        w.files[AUTO] = { text: JSON.stringify(state) }
      }
      if (verb === 'cd-prefix') return finish(0, w.cdPrefix)
      if (verb === 'due') {
        const tokens = Number(words[4])
        const isDue = tokens >= w.due.limit && state.pending === null
        if (isDue) state.pending = 'compact'
        save()
        return finish(isDue ? 6 : 0, `due: limit=${w.due.limit} hard=${w.due.hard} pending=${String(state.pending ?? 'none')}\n`)
      }
      if (verb === 'compacted') {
        Object.assign(state, { pending: 'after-compact', compactions: Number(state.compactions) + 1 })
        save()
        return finish(0)
      }
      if (verb === 'clear') {
        if (primaryOf(dir) !== B_ROOT) return finish(7, `auto-run: run this from the run's checkout: cd '${B_ROOT}' && …\n`)
        Object.assign(state, { pending: 'clear', rebind: true })
        save()
        return finish(0)
      }
      if (verb === 'rebind') {
        if (primaryOf(dir) !== B_ROOT) return finish(4, 'auto-run: no clear is waiting for its session\n')
        Object.assign(state, { session: words[4], pending: 'resume', rebind: false })
        w.files[BINDING(String(words[4]))] = binding(B_ROOT)
        save()
        return finish(0)
      }
      if (verb === 'resumed') {
        if (state.pending === 'resume') state.pending = null
        save()
        return finish(0)
      }
      if (verb === 'after-compact') {
        state.pending = null
        save()
        return finish(0, 'continue — 100k after compaction; regime normal\n')
      }
      return finish(0)
    }
    const text = argv.join(' ')
    if (text === 'node --version') return result(0, 'v24.18.0\n')
    const toplevel = /^git -C (.+) rev-parse --show-toplevel$/.exec(text)
    if (toplevel !== null) return result(0, `${primaryOf(toplevel[1]!)}\n`)
    if (text === 'git rev-parse --show-toplevel') return result(0, `${w.root}\n`)
    const common = /^git -C (.+) rev-parse /.exec(text)
    if (common !== null) return result(0, `${primaryOf(common[1]!)}/.git\n`)
    if (text.startsWith('git rev-parse')) return result(0, `${w.root}/.git\n`)
    if (text.startsWith('git ')) return result(0, '# branch.oid abc1234def\n# branch.head main\n')
    w.unknown.push(text)
    return result(0, '')
  })
  on('ui.render', ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    if (e.component === 'PromptHint') return h(Text, {}, e.props.tail ?? '') as RenderElement
    return h(Box, { key: 'engine' }) as RenderElement
  })
  return clock
}

const fresh = (fields: Partial<World> = {}, run: { text: string } | null = runState()): World => ({
  cwd: A_CWD,
  root: A_ROOT,
  tokens: 100_000,
  window: 1_000_000,
  sessionId: 'sess-1',
  due: { limit: 300_000, hard: 375_000 },
  files: run === null ? {} : { [AUTO]: run, [BINDING('sess-1')]: binding(B_ROOT) },
  rows: [],
  prompts: [],
  commands: [],
  compacts: [],
  calls: [],
  cdPrefix: '',
  unknown: [],
  ...fields,
})

async function settle(clock: ReturnType<typeof world>) {
  for (let i = 0; i < 10; i++) await clock.advance(1)
}

const notes = (w: World) => w.rows.filter(row => row.type === 'user' && row.text.startsWith('dforge: budget:')).map(row => row.text)
const bash = ($: Parameters<TestBody>[0]) => $.tool.call({ tool: 'Bash', command: 'ls' })
const callsOf = (w: World, verb: string) => w.calls.filter(call => call.words[0] === verb)
const said = ($: Parameters<TestBody>[0], text: string) =>
  $.session.append({ message: { type: 'assistant', role: 'assistant', content: [{ type: 'text', text }] }, door: 'response', origin: { kind: 'model' }, uuid: 'fm-1' } as never)
// Fast mode, as reference/fast-mode.md says it is entered: a `Process: fast` line
// the main session writes after the current prompt.
const goFast = async ($: Parameters<TestBody>[0]) => {
  await $.turn.start({ text: 'Fix the typo in the README.', turnId: 'fast-1' })
  await said($, 'Process: fast — a one-line fix')
}
const answer = ($: Parameters<TestBody>[0], text: string) =>
  $.turn.complete({ answer: text, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' } as never)
// A cockpit started in a session: the first tick reads the binding.
async function begin($: Parameters<TestBody>[0], on: On, w: World) {
  const clock = world(on, w)
  await $.session.start(START_IN(w.cwd))
  await settle(clock)
  await clock.advance(5_000)
  return clock
}

describe('auto-run-cleanup-and-long-runs: the cockpit follows the binding (A2)', () => {
  test('A2: a main turn ending on the pending sentinel schedules the stage while the session is in another repository', async ($, on) => {
    const w = fresh({ tokens: 310_000 }, runState({ pending: 'compact' }))
    const clock = await begin($, on, w)
    await answer($, SENTINEL('compacting'))
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    const compacted = callsOf(w, 'compacted')
    expect(compacted).toHaveLength(1)
    expect(compacted[0]!.exit).toBe(0)
    expect(stateOf(w).compactions).toBe(1)
  })

  test("A2: the cockpit's run read returns B's run: the same turn, with the binding removed, schedules nothing", async ($, on) => {
    const w = fresh({ tokens: 310_000 }, runState({ pending: 'compact' }))
    delete w.files[BINDING('sess-1')]
    const clock = await begin($, on, w)
    await answer($, SENTINEL('compacting'))
    await settle(clock)
    expect(w.compacts).toEqual([])
    expect(w.calls).toEqual([])
  })

  test('A2: due books the compaction in B and succeeds', async ($, on) => {
    const w = fresh({ tokens: 310_000 })
    await begin($, on, w)
    await bash($)
    const due = callsOf(w, 'due')
    expect(due.length).toBeGreaterThanOrEqual(1)
    expect(due.every(call => call.exit === 0 || call.exit === 6)).toBe(true)
    expect(due.every(call => primaryOf(call.dir) === B_ROOT || primaryOf(call.dir) === A_ROOT)).toBe(true)
    expect(stateOf(w).pending).toBe('compact')
  })

  test('A2: the switch calls clear --phase in the run\'s checkout and rebinds the new session, both succeeding', async ($, on) => {
    const w = fresh({}, runState({ pending: 'switch', setupDue: true }))
    const clock = await begin($, on, w)
    await answer($, SENTINEL('switching'))
    await settle(clock)
    const clears = callsOf(w, 'clear')
    expect(clears).toHaveLength(1)
    expect(clears[0]!.words).toEqual(['clear', '--phase'])
    expect(primaryOf(clears[0]!.dir)).toBe(B_ROOT)
    expect(clears[0]!.exit).toBe(0)
    expect(w.commands).toEqual(['/clear'])
    const rebinds = callsOf(w, 'rebind')
    expect(rebinds).toHaveLength(1)
    expect(rebinds[0]!.words).toEqual(['rebind', '--to', 'sess-2'])
    expect(primaryOf(rebinds[0]!.dir)).toBe(B_ROOT)
    expect(rebinds[0]!.exit).toBe(0)
    expect(stateOf(w).session).toBe('sess-2')
    expect(w.prompts).toEqual([FIRST_PROMPT])
  })
})

describe('auto-run-cleanup-and-long-runs: the note at the limit (A10)', () => {
  const PHASES = ['spec', 'plan', 'execute', 'final', 'finish'] as const
  const limitText = /\b(312k|312,000|312000)\b/
  for (const phase of PHASES)
    test(`A10: in ${phase}, a main response past the limit books compact and appends exactly one note with the script's limit`, async ($, on) => {
      const w = fresh({ tokens: 330_000, due: { limit: 312_000, hard: 390_000 } }, runState({ phase }))
      await begin($, on, w)
      await bash($)
      expect(stateOf(w).pending).toBe('compact')
      expect(notes(w)).toHaveLength(1)
      expect(notes(w)[0]).toMatch(limitText)
      expect(notes(w)[0]).toMatch(/330k/)
      w.tokens = 340_000
      await bash($)
      await bash($)
      expect(notes(w)).toHaveLength(1)
    })

  test('A10: in fast mode an auto run still gets the note', async ($, on) => {
    const w = fresh({ tokens: 330_000, due: { limit: 312_000, hard: 390_000 } })
    await begin($, on, w)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:brainstorming' })
    await goFast($)
    await bash($)
    expect(stateOf(w).pending).toBe('compact')
    expect(notes(w)).toHaveLength(1)
    expect(notes(w)[0]).toMatch(limitText)
  })

  test('A10: a compaction re-arms the note', async ($, on) => {
    const w = fresh({ tokens: 330_000, due: { limit: 312_000, hard: 390_000 } })
    const clock = await begin($, on, w)
    await bash($)
    expect(notes(w)).toHaveLength(1)
    await answer($, SENTINEL('compacting'))
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    const state = stateOf(w)
    w.files[AUTO] = { text: JSON.stringify({ ...state, pending: null }) }
    w.tokens = 320_000
    await bash($)
    expect(notes(w)).toHaveLength(2)
  })

  test('A10: the limit in the note follows the script when it changes with the phase', async ($, on) => {
    const w = fresh({ tokens: 380_000, due: { limit: 375_000, hard: 375_000 } }, runState({ phase: 'plan', regime: 'high' }))
    await begin($, on, w)
    await bash($)
    expect(notes(w)).toHaveLength(1)
    expect(notes(w)[0]).toMatch(/375k/)
    expect(notes(w)[0]).not.toMatch(/720k|604k/)
  })
})

describe('auto-run-cleanup-and-long-runs: no compaction before the step in hand is recorded (A11)', () => {
  for (const phase of ['execute', 'final'] as const)
    test(`A11: in ${phase} no note tells the session to compact before recording the step, and the cockpit compacts nothing mid-step`, async ($, on) => {
      const w = fresh({ tokens: 310_000, due: { limit: 300_000, hard: 375_000 } }, runState({ phase }))
      await begin($, on, w)
      for (const tokens of [310_000, 375_000, 380_000, 450_000, 700_000, 900_000]) {
        w.tokens = tokens
        await bash($)
      }
      expect(notes(w).length).toBeGreaterThanOrEqual(1)
      for (const note of notes(w)) {
        expect(note).toMatch(/record it, then end the turn on `Auto run: compacting`/)
        expect(note).not.toMatch(/compact (now|immediately)|now compact|stop (now|what you)|without finishing|before (you )?(finish|record)/i)
      }
      expect(w.compacts).toEqual([])
      expect(w.commands.filter(command => /compact/i.test(command))).toEqual([])
      expect(w.prompts).toEqual([])
    })
})

describe('auto-run-cleanup-and-long-runs: strict mode outside an auto run (A12)', () => {
  const PLAN = `# Plan\n\n${[1, 2, 3, 4, 5].map(n => `### Task ${n}: Step ${n}\n`).join('\n')}`
  const ledger = (done: number) =>
    [
      '# SDD ledger — plan: docs/plans/p.md',
      ...Array.from({ length: done }, (_, i) => `Task ${i + 1}: complete (commits a..b, review clean) — done: x; verified: y; remaining: none; discovered: none; assumptions: none`),
    ].join('\n')
  for (const [name, done] of [
    ['the tail', 3],
    ['the final phase', 5],
  ] as const)
    test(`A12: in ${name} the cockpit sends one note, at hard (375k of a 300k budget)`, async ($, on) => {
      const w = fresh({ cwd: B_CWD, root: B_ROOT, tokens: 100_000, window: 800_000 }, null)
      w.files = {
        [`${B_ROOT}/.dforge/sdd/p/progress.md`]: { text: ledger(done) },
        [`${B_ROOT}/docs/plans/p.md`]: { text: PLAN },
        [`${HOME}/.dforge/config.json`]: { text: JSON.stringify({ handoffTokens: 300_000 }) },
      }
      await begin($, on, w)
      await $.tool.call({ tool: 'Skill', skill: 'dforge:executing-plans' })
      for (const tokens of [310_000, 350_000, 374_000]) {
        w.tokens = tokens
        await bash($)
        expect(notes(w)).toEqual([])
      }
      w.tokens = 375_000
      await bash($)
      expect(notes(w)).toHaveLength(1)
      expect(notes(w)[0]).toMatch(/375k/)
      expect(notes(w)[0]).toMatch(/handoff/i)
      w.tokens = 390_000
      await bash($)
      await bash($)
      expect(notes(w)).toHaveLength(1)
    })
})

describe('auto-run-cleanup-and-long-runs: notes only when due (A14)', () => {
  test('A14: below the limit no note is appended and nothing becomes pending', async ($, on) => {
    const w = fresh({ tokens: 290_000 })
    await begin($, on, w)
    await bash($)
    await bash($)
    expect(notes(w)).toEqual([])
    expect(stateOf(w).pending).toBeNull()
    expect(w.compacts).toEqual([])
  })

  for (const tokens of [300_000, 465_000, 700_000, 900_000])
    test(`A14: outside an auto run a session in fast mode gets no note at ${tokens / 1000}k`, async ($, on) => {
      const w = fresh({ cwd: B_CWD, root: B_ROOT, tokens: 100_000, window: 1_000_000 }, null)
      await begin($, on, w)
      await $.tool.call({ tool: 'Skill', skill: 'dforge:brainstorming' })
      await goFast($)
      w.tokens = tokens
      await bash($)
      await bash($)
      expect(notes(w)).toEqual([])
    })

  test('A14: the same session outside fast mode is told at 900k, so the silence above is the fast mode and not a quiet cockpit', async ($, on) => {
    const w = fresh({ cwd: B_CWD, root: B_ROOT, tokens: 100_000, window: 1_000_000 }, null)
    await begin($, on, w)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:brainstorming' })
    w.tokens = 900_000
    await bash($)
    expect(notes(w).length).toBeGreaterThanOrEqual(1)
  })
})

describe('auto-run-cleanup-and-long-runs: prompts name the run\'s checkout (A44)', () => {
  const afterCompaction = async ($: Parameters<TestBody>[0], on: On, w: World) => {
    const clock = await begin($, on, w)
    await answer($, SENTINEL('compacting'))
    await settle(clock)
    await clock.advance(5_000)
    await settle(clock)
    return w.prompts
  }

  test("A44: with the run bound and its checkout outside the session's starting directory the after-compaction prompt contains cd '<checkout>' &&", async ($, on) => {
    const w = fresh({ tokens: 310_000, cdPrefix: `${CD_B} ` }, runState({ pending: 'compact' }))
    const prompts = await afterCompaction($, on, w)
    expect(w.compacts).toHaveLength(1)
    expect(prompts.length).toBeGreaterThanOrEqual(1)
    expect(prompts.some(prompt => prompt.includes(CD_B))).toBe(true)
  })

  test("A44: with the checkout inside the session's starting directory the prompt has no cd prefix", async ($, on) => {
    const w = fresh({ cwd: B_CWD, root: B_ROOT, tokens: 310_000, cdPrefix: '' }, runState({ pending: 'compact' }))
    const prompts = await afterCompaction($, on, w)
    expect(w.compacts).toHaveLength(1)
    expect(prompts.length).toBeGreaterThanOrEqual(1)
    expect(prompts.some(prompt => prompt.includes(CD_B))).toBe(false)
  })
})
