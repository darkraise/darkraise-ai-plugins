import { describe, expect, mock, test } from 'claude-code/testing'
import type { CommandRunInput, On, RenderElement, SessionMeasureInput, SessionMessage } from 'claude-code'

import {
  accountKey,
  attributionIn,
  bar,
  billingLabel,
  budgetFor,
  duration,
  elapsed,
  fitStatus,
  isAtLeast,
  levelOf,
  limitForecast,
  modelName,
  nowBadge,
  nowLine,
  parseLedger,
  planTasks,
  planWithUpdate,
  repoFromPorcelain,
  runsWidth,
  sectionsToggled,
  sparkline,
  stackedRuns,
  statusLines,
  stepped,
  termColor,
  track,
  turnsToBudget,
  windowElapsed,
  writesGitText,
} from '../hooks/lib'
import type { ActivityInput } from '../hooks/lib'
import {
  discordBody,
  excerpt,
  isDiscordWebhook,
  maskWebhook,
  mentionId,
  notifyKindsFrom,
  notifyKindsToggled,
  redact,
} from '../hooks/notify'

const SURFACES = ['terminal', 'desktop'] as const
const BAND = {
  plugin: 'dr-cockpit',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 3, bodyColumns: 100, scroll: { offset: 0, bodyRows: 3 }, view: {} },
} as const
const HINT = {
  plugin: 'dr-cockpit',
  component: 'PromptHint',
  props: { isDraft: false, isWorking: false, hint: '? for shortcuts' },
} as const
const PANE = {
  plugin: 'dr-cockpit',
  component: 'Pane',
  requestId: 'dr-cockpit',
  props: { title: 'Cockpit', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
} as const
const PORCELAIN = '# branch.oid abc1234def\n# branch.head feat/pane\n# branch.ab +2 -1\n1 .M N... 100644 100644 100644 a b src/a.ts\n? notes.md\n'

// The /context breakdown, as a summary estimate answers it.
const BREAKDOWN = {
  categories: [
    { name: 'Messages', tokens: 180_000, kind: 'used', color: '', isDeferred: false },
    { name: 'System tools', tokens: 38_000, kind: 'used', color: '', isDeferred: false },
    { name: 'Free space', tokens: 300_000, kind: 'free', color: '', isDeferred: false },
  ],
  isAutoCompactEnabled: true,
  autoCompactThreshold: 604_000,
} as never
const INLINE = { ...PANE, props: { ...PANE.props, placement: 'inline', bodyColumns: 100 } } as const
const MEASURE: SessionMeasureInput = {
  context: { tokens: 284_000, window: 650_000 },
  rateLimits: [
    { kind: 'five_hour', percentUsed: 23 },
    { kind: 'seven_day', percentUsed: 61 },
  ],
  cost: { usd: 1.5 },
  changed: ['context', 'rateLimits'],
}

// The person typing /cockpit at a wide fullscreen terminal.
const COCKPIT: CommandRunInput = {
  command: 'cockpit',
  args: '',
  origin: { kind: 'composer' },
  presentation: { isFullscreen: true, columns: 160 },
}

// A terminal session starting in the repository.
const START = { cwd: '/home/me/code/shop/web', surface: 'terminal', isInteractive: true } as never

// What a compaction leaves: one row standing for the conversation.
const SUMMARY: SessionMessage = { role: 'user', text: 'Summary.', toolUses: [] }

type World = {
  tokens: number | undefined
  window?: number
  settings?: Record<string, unknown>
  toasts?: string[]
  notes?: string[]
  env?: Record<string, string>
  /** Files the plugin reads, by path, with their modification time. */
  files?: Record<string, { text: string; mtimeMs?: number }>
  /** What the plugin writes, by path. */
  written?: Record<string, string>
  /** Each request the plugin sends through $.http.fetch. */
  fetches?: { url: string; method: string; body: Record<string, unknown> }[]
  /** How Claude Code answers the pane opening; placed unless said. */
  open?: { isPlaced: true } | { isPlaced: false; reason: string }
  /** The Claude Code release the engine reports; absent, `$.session.version()` fails. */
  version?: string
  /** Tools that answer in their own way, by name. */
  tools?: Record<string, () => Promise<{ result: unknown; text: string }> | { result: unknown; text: string }>
}

// The engine beneath the plugin: a context of `w.tokens` (read on each call,
// so a test moves it) in a 650k window, every tool call answered, every toast
// and every row the plugin appends recorded in `w.notes`.
function world(on: On, w: World) {
  mock.env(on, w.env ?? {})
  const clock = mock.clock(on, { now: 1_000_000 })
  on('command.register', () => ({ value: undefined }) as never)
  on('session.start', (_$, e) => e as never)
  on('session.usage', (_$, e) => ({
    value: {
      startedAt: 0,
      context: {
        tokens: w.tokens,
        window: w.window ?? 650_000,
        ...(e.breakdown === undefined ? {} : { breakdown: BREAKDOWN }),
      },
      rateLimits: [],
      cost: { usd: 1.5 },
    },
  }))
  on('settings.read', () => ({ value: w.settings ?? {} }))
  on('tool.call', (_$, e) => w.tools?.[String(e.tool)]?.() ?? { result: 'ok', text: 'ok' })
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'agent-1' }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('session.version', () => {
    if (w.version === undefined) throw new Error('no version')
    return { value: { version: w.version, base: w.version } }
  })
  on('ui.open', () => ({ value: w.open ?? { isPlaced: true } }))
  on('session.compact', (_$, e) => ({ messages: e.messages }))
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('process.run', (_$, e) => {
    const argv = e.argv.join(' ')
    const stdout = argv === 'hostname' ? 'devbox\n' : argv.startsWith('git rev-parse') ? '/home/me/code/shop/.git\n' : PORCELAIN
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('session.id', () => ({ value: 'sess-1' }))
  on('fs.stat', (_$, e) => {
    const file = w.files?.[e.path]
    if (file === undefined) throw new Error('ENOENT')
    return { value: { kind: 'file', size: file.text.length, mtimeMs: file.mtimeMs ?? 0, isLink: false } }
  })
  on('fs.list', (_$, e) => {
    const prefix = `${e.path}/`
    const names = new Set(
      Object.keys(w.files ?? {})
        .filter(path => path.startsWith(prefix))
        .map(path => path.slice(prefix.length).split('/')[0] ?? ''),
    )
    if (names.size === 0) throw new Error('ENOENT')
    return { value: [...names].map(name => ({ name, kind: 'dir', size: 0, mtimeMs: 0, isLink: false })) }
  })
  on('fs.write', (_$, e) => {
    if (w.written !== undefined) w.written[e.path] = e.text
    return { value: undefined }
  })
  on('http.fetch', (_$, e) => {
    w.fetches?.push({ url: e.url, method: e.init?.method ?? 'GET', body: JSON.parse(e.init?.body ?? '{}') as Record<string, unknown> })
    return { value: { status: 200, ok: true, headers: {}, text: '{"id":"m1"}' } }
  })
  on('ui.panes', () => ({ value: [{ id: 'dr-cockpit', title: 'Cockpit', isShown: true, isFocused: false, isPlaced: true }] }))
  on('session.append', (_$, e, next) => {
    const part = (e.message as { content?: { text?: string }[] }).content?.[0]
    if (part?.text !== undefined) w.notes?.push(part.text)
    return next(e)
  })
  on('ui.toast', (_$, e) => {
    w.toasts?.push(e.text)
    w.notes?.push(e.text)
    return { value: undefined }
  })
  // What the engine would draw itself where the plugin leaves a site alone.
  on('ui.render', ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    if (e.component === 'PromptHint') return h(Text, {}, e.props.tail ?? '') as RenderElement
    return h(Box, { key: 'engine' }) as RenderElement
  })
  return clock
}

// A signed-in account with a frame color in dr-status' config, working in a
// repository under home.
const SIGNED_IN = { tokens: 284_000, env: { HOME: '/home/me' }, settings: { effortLevel: 'xhigh' } }
function signedIn(on: On, files: World['files'] = {}) {
  on('fs.read', (_$, e) => {
    const file = files[e.path]
    if (file !== undefined) return { value: file.text }
    if (e.path === '/home/me/.claude.json') {
      return {
        value: JSON.stringify({
          oauthAccount: {
            emailAddress: 'me@example.com',
            displayName: 'Me',
            organizationName: 'Acme',
            organizationRole: 'admin',
            billingType: 'stripe_subscription',
          },
        }),
      }
    }
    if (e.path === '/home/me/.claude/dcc-statusline.json') return { value: JSON.stringify({ accounts: { '~/.claude': { color: '141' } } }) }
    throw new Error('ENOENT')
  })
  on('session.cwd', () => ({ value: '/home/me/code/shop/web' }))
  on('session.repo', () => ({ value: { root: '/home/me/code/shop', remote: null, internal: false, name: null } }))
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
}

describe('budget rule', () => {
  test('follows the setting, then the env, then dr-superpowers', () => {
    expect(budgetFor(200_000, '465000', 650_000)).toBe(200_000)
    expect(budgetFor(0, '465000', 650_000)).toBe(465_000)
    expect(budgetFor(0, undefined, 650_000)).toBe(464_500)
    expect(budgetFor(0, 'junk', 200_000)).toBe(46_000)
    expect(budgetFor(0, undefined, 100_000)).toBe(20_000)
    expect(levelOf(300_000, 465_000)).toBe('quiet')
    expect(levelOf(400_000, 465_000)).toBe('warn')
    expect(levelOf(465_000, 465_000)).toBe('handoff')
  })

  test('measures against the compaction window when it is smaller', () => {
    expect(budgetFor(0, undefined, 1_000_000, 800_000)).toBe(604_000)
    expect(budgetFor(0, undefined, 650_000, 800_000)).toBe(464_500)
  })

  test('reads autoCompactWindow from the settings', async ($, on) => {
    world(on, { tokens: 610_000, window: 1_000_000, settings: { autoCompactWindow: 800_000 } })
    await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 'turn-0', reason: 'answer' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /610k of 1\.0M ┃ handoff 604k/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^101% of handoff$/ })).toBeDefined()
  })
})

describe('pane helpers', () => {
  test('draw meters, durations and git state', () => {
    expect(bar(0.5, 10)).toBe('▰▰▰▰▰▱▱▱▱▱')
    expect(bar(0.99, 10)).toBe('▰▰▰▰▰▰▰▰▰▱')
    expect(bar(1.4, 4)).toBe('▰▰▰▰')
    expect(duration(13_200_000)).toBe('3h40m')
    expect(duration(190_800_000)).toBe('2d5h')
    expect(duration(-5)).toBe('')
    expect(repoFromPorcelain(PORCELAIN)).toEqual({ branch: 'feat/pane', ahead: 2, behind: 1, changed: 1, untracked: 1 })
    expect(repoFromPorcelain('# branch.oid abc1234def\n# branch.head (detached)\n')?.branch).toBe('@abc1234')
    expect(repoFromPorcelain('')).toBeNull()
  })

  test('update and drop tasks', () => {
    const items = [
      { id: '1', text: 'one', status: 'pending' as const },
      { id: '2', text: 'two', status: 'pending' as const },
    ]
    expect(planWithUpdate(items, '1', { status: 'completed' })[0]?.status).toBe('completed')
    expect(planWithUpdate(items, '2', { status: 'deleted' })).toHaveLength(1)
  })
})

describe('attribution guard', () => {
  test('finds AI attribution and leaves human co-authors alone', () => {
    expect(attributionIn('fix\n\nCo-Authored-By: Claude Opus <noreply@anthropic.com>')).toMatch(/Co-Authored-By/)
    expect(attributionIn('body\n🤖 Generated with [Claude Code](https://claude.com/claude-code)')).toMatch(/Generated/)
    expect(attributionIn('fix\n\nCo-Authored-By: Jane <jane@example.com>')).toBeUndefined()
    expect(writesGitText('git -C repo commit -m "x"')).toBe(true)
    expect(writesGitText('git log --oneline')).toBe(false)
  })

  test('names the line without the quoting around it', () => {
    expect(attributionIn('git commit -m "fix" -m "Claude-Session: https://x/1"')).toBe('Claude-Session: https://x/1')
    expect(attributionIn(JSON.stringify({ body: 'Fix\n\nGenerated with Claude Code\nmore' }))).toBe(
      'Generated with Claude Code',
    )
  })

  test('blanks the commit trailer and PR footer the engine composes', async ($, on) => {
    world(on, { tokens: 10_000 })
    expect((await $.attribution.text({ kind: 'commit', text: 'Co-Authored-By: Claude' })).text).toBe('')
    expect((await $.attribution.text({ kind: 'pr', text: 'Generated with Claude Code' })).text).toBe('')
  })

  test('refuses a commit carrying a trailer, lets a clean one run, and lists the refusal', async ($, on) => {
    world(on, { tokens: 10_000 })
    const dirty = await $.tool.call({
      tool: 'Bash',
      command: 'git commit -m "fix" -m "Claude-Session: https://claude.ai/code/session_1"',
    })
    expect(dirty.deny ?? dirty.text).toMatch(/keeps AI attribution out of git/)
    const clean = await $.tool.call({ tool: 'Bash', command: 'git commit -m "fix: tidy"' })
    expect(clean.deny).toBeUndefined()
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /✗ Bash: Claude-Session/ })).toBeDefined()
  })

  test('is off when configured off', { options: { guardAttribution: false } }, async ($, on) => {
    world(on, { tokens: 10_000 })
    const ran = await $.tool.call({ tool: 'Bash', command: 'git commit -m "x" -m "Claude-Session: y"' })
    expect(ran.deny).toBeUndefined()
  })
})

describe('handoff reading', () => {
  test('shows in no band and no hint line, past the budget too', async ($, on) => {
    world(on, { tokens: 470_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    for (const surface of SURFACES) {
      const band = await $.ui.mount({ ...BAND, surface })
      expect(await band.find({ text: /hand ?off/i })).toBeUndefined()
      await band.unmount()
      const hint = await $.ui.mount({ ...HINT, surface })
      expect(await hint.find({ text: /handoff/ })).toBeUndefined()
      await hint.unmount()
    }
  })

  test('joins the strip above the prompt once the context nears the budget', async ($, on) => {
    const w: World = { ...SIGNED_IN, tokens: 284_000 }
    world(on, w)
    signedIn(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    let ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^handoff $/ })).toBeUndefined()
    await ui.unmount()

    w.tokens = 400_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^handoff $/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^86%$/ })).toBeDefined()
  })

  test('in a plan session, offers the handoff in the pane and sends the note once', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 470_000, notes })
    await $.tool.call({ tool: 'Skill', skill: 'dr-superpowers:subagent-driven-development' })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes).toHaveLength(1)
    expect(notes[0]).toMatch(/budget: 470k of 465k — handoff/)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ key: 'pane-handoff' })).toBeDefined()
  })

  test('stays quiet to the model outside a plan session', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 470_000, notes })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes).toEqual([])
  })

  test('clears after a compaction and re-arms the note', async ($, on) => {
    const notes: string[] = []
    const w: World = { tokens: 470_000, notes }
    world(on, w)
    await $.tool.call({ tool: 'Skill', skill: 'dr-superpowers:subagent-driven-development' })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes).toHaveLength(1)

    await $.session.compact({ trigger: 'manual', messages: [SUMMARY] })
    w.tokens = undefined
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const cleared = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await cleared.find({ type: 'Text', text: /no reading yet/ })).toBeDefined()
    await cleared.unmount()

    w.tokens = 480_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes).toHaveLength(2)
  })
})

describe('cockpit pane', () => {
  test('sums a seat once its subagent finishes', async ($, on) => {
    world(on, { tokens: 50_000 })
    await $.agent.spawn({
      tool_use_id: 'toolu_1',
      prompt: 'Implement task 3',
      description: 'Task 3',
      subagentType: 'dr-superpowers:impl-sonnet-low',
      provider: { plugin: 'dr-superpowers', tier: 'user' },
      parentModel: 'claude-opus-5-5',
      background: false,
      fork: false,
    })
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...PANE, surface })
      expect(await ui.find({ type: 'Text', text: /● impl-sonnet-low Task 3/ })).toBeDefined()
      await ui.unmount()
    }
    await $.turn.complete({
      answer: 'done',
      durationMs: 1000,
      isAborted: false,
      turnId: 'turn-1',
      agentId: 'agent-1',
      reason: 'answer',
      usage: {
        model: 'claude-sonnet-5-5',
        input_tokens: 2_000,
        cache_read_input_tokens: 30_000,
        cache_creation_input_tokens: 8_000,
        output_tokens: 3_000,
      },
    })
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...PANE, surface })
      expect(await ui.find({ type: 'Text', text: /40k in · 75% cached · 3k out/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /✓ impl-sonnet-low Task 3/ })).toBeDefined()
      await ui.unmount()
    }
  })

  test('shows the context, limits, cost and repo', async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure({
      context: { tokens: 284_000, window: 650_000 },
      rateLimits: [{ kind: 'five_hour', percentUsed: 23 }],
      cost: { usd: 1.5 },
      changed: ['context', 'rateLimits'],
    })
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...PANE, surface })
      expect(await ui.find({ type: 'Text', text: /61%/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /284k of 650k ┃ handoff 465k/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /23%/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /\$1\.50/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /feat\/pane/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /~1 changed \?1 untracked/ })).toBeDefined()
      expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
      // Rows sit two cells in under their section, details two more.
      expect(JSON.stringify(await ui.drawn())).toContain('"paddingLeft":2')
      await ui.unmount()
    }
  })

  test('follows the todo list and the task list', async ($, on) => {
    on('tool.call', { tool: 'TaskCreate' }, () => ({ result: { task: { id: '7', subject: 'Ship it' } }, text: 'ok' }))
    world(on, { tokens: 50_000 })
    await $.tool.call({
      tool: 'TodoWrite',
      todos: [
        { content: 'Read the plan', status: 'completed', activeForm: 'Reading' },
        { content: 'Write the pane', status: 'in_progress', activeForm: 'Writing' },
        { content: 'Open the PR', status: 'pending', activeForm: 'Opening' },
      ],
    })
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^1\/3$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /▸ Write the pane/ })).toBeDefined()
    await ui.unmount()

    await $.tool.call({ tool: 'TaskCreate', subject: 'Ship it', description: 'Ship the pane' })
    await $.tool.call({ tool: 'TaskUpdate', taskId: '7', status: 'completed' })
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^2\/4$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /✓ Ship it/ })).toBeDefined()
  })
})

describe('settings', () => {
  test('warnAt moves where the strip shows the handoff', { options: { warnAt: 70 } }, async ($, on) => {
    world(on, { tokens: 340_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^73%$/ })).toBeDefined()
  })

  test('sections picks and orders the pane', { options: { sections: 'plan, repo' } }, async ($, on) => {
    world(on, { tokens: 50_000 })
    await $.tool.call({
      tool: 'TodoWrite',
      todos: [{ content: 'Write the pane', status: 'in_progress', activeForm: 'Writing' }],
    })
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Context' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: 'Usage' })).toBeUndefined()
    const drawn = JSON.stringify(await ui.drawn())
    expect(drawn.indexOf('"Plan"')).toBeGreaterThan(-1)
    expect(drawn.indexOf('"Plan"')).toBeLessThan(drawn.indexOf('feat/pane'))
    // Without the Context section the buttons still show, at the end.
    expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
  })

  test('breakdownRows limits the context rows', { options: { breakdownRows: 1 } }, async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Messages/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /System tools/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /compacts 604k/ })).toBeDefined()
  })

  test('limitAlertAt toasts once per window', async ($, on) => {
    const toasts: string[] = []
    world(on, { tokens: 50_000, toasts })
    const high = { ...MEASURE, rateLimits: [{ kind: 'five_hour', percentUsed: 92, resetsAt: '2026-10-08T12:00:00Z' }] }
    await $.session.measure(high)
    await $.session.measure(high)
    expect(toasts.filter(text => /5h limit at 92%/.test(text))).toHaveLength(1)
    await $.session.measure({ ...high, rateLimits: [{ kind: 'five_hour', percentUsed: 95, resetsAt: '2026-10-08T17:00:00Z' }] })
    expect(toasts.filter(text => /5h limit at/.test(text))).toHaveLength(2)
  })

  test('limitAlertAt 0 stays quiet', { options: { limitAlertAt: 0 } }, async ($, on) => {
    const toasts: string[] = []
    world(on, { tokens: 50_000, toasts })
    await $.session.measure({ ...MEASURE, rateLimits: [{ kind: 'five_hour', percentUsed: 99 }] })
    expect(toasts).toEqual([])
  })
})

describe('compact layout', () => {
  test('draws dr-status\' two lines in the account\'s frame, with the buttons', async ($, on) => {
    world(on, SIGNED_IN)
    signedIn(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.tool.call({
      tool: 'TodoWrite',
      todos: [{ content: 'Write the pane', status: 'in_progress', activeForm: 'Writing' }],
    })
    await $.session.measure(MEASURE)
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...INLINE, surface })
      expect(await ui.find({ type: 'Text', text: 'Context' })).toBeUndefined()
      expect(await ui.find({ type: 'Text', text: /^╭─ me@example\.com ─{81}╮$/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /~\/code\/shop\/web.*feat\/pane\* ↑2 ↓1 \?1.*Opus 5\.5.*xhigh/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /ctx ▰+▱+ 44% · 284k.*\$1\.50.*5h ▰+▱+ 23%.*7d ▰+▱+ 61%/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /Plan/ })).toBeUndefined()
      expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
      await ui.unmount()
    }
  })

  test('drops the frame below 48 columns, the email on a line of its own', async ($, on) => {
    world(on, SIGNED_IN)
    signedIn(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...INLINE, props: { ...INLINE.props, bodyColumns: 40 }, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /╭/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: 'me@example.com' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^shop\/web · feat\/pane\* · Opus · xhigh$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^ctx 44% · \$1\.50 · 5h 23% · 7d 61%$/ })).toBeDefined()
  })

  test('is used docked too when asked', { options: { layout: 'compact' } }, async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Context' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /ctx ▰+▱+ 44% · 284k/ })).toBeDefined()
  })

  test('full keeps the sections above the prompt', { options: { layout: 'full' } }, async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Context' })).toBeDefined()
  })

  test('an unknown layout reads as auto', { options: { layout: 'tiles' } }, async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const docked = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await docked.find({ type: 'Text', text: 'Context' })).toBeDefined()
    await docked.unmount()
    const inline = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await inline.find({ type: 'Text', text: 'Context' })).toBeUndefined()
  })
})

describe('/cockpit', () => {
  test('says the pane opened when Claude Code draws it', async ($, on) => {
    world(on, { tokens: 284_000 })
    const answer = await $.command.run(COCKPIT)
    expect(answer.text).toBe('Cockpit pane opened.')
  })

  test('says why when Claude Code holds the pane back', async ($, on) => {
    world(on, { tokens: 284_000, open: { isPlaced: false, reason: 'this desktop app places no panes' } })
    const answer = await $.command.run(COCKPIT)
    expect(answer.text).toBe('Cockpit pane is waiting: this desktop app places no panes')
  })
})

describe('buttons', () => {
  test('wear a rounded box, the accent on the one that matters', { options: { handoffTokens: 400_000 } }, async ($, on) => {
    const w: World = { ...SIGNED_IN, tokens: 200_000 }
    world(on, w)
    signedIn(on)
    await $.tool.call({ tool: 'Skill', skill: 'dr-superpowers:subagent-driven-development' })
    await $.session.start(START)
    await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 't', reason: 'answer' })
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect((await ui.find({ key: 'pane-handoff-box' }))?.props).toMatchObject({ borderStyle: 'round', borderColor: 'inactive' })
    expect((await ui.find({ key: 'pane-handoff' }))?.props).toMatchObject({ hotkey: 'h', plain: true })
    await ui.unmount()
    // Past warnAt, Hand off is the one to press.
    w.tokens = 350_000
    await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 't2', reason: 'answer' })
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect((await ui.find({ key: 'pane-handoff-box' }))?.props.borderColor).toBe('permission')
    expect((await ui.find({ key: 'pane-compact-box' }))?.props.borderColor).toBe('inactive')
  })

  test('underline the hotkey letter where Claude Code draws styled labels', async ($, on) => {
    world(on, { ...SIGNED_IN, version: '2.1.295' })
    signedIn(on)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    const compact = await ui.find({ key: 'pane-compact' })
    expect(compact?.props).toMatchObject({ label: 'Compact', plain: true })
    expect(compact?.props.hotkey).toBeUndefined()
    expect(JSON.stringify(compact?.children)).toContain('{"type":"Text","props":{"underline":true},"children":["C"]}')
    // The hotkey rides on a hidden twin that presses the same thing.
    expect((await ui.find({ key: 'pane-settings-hotkey-box' }))?.props.display).toBe('none')
    expect((await ui.find({ key: 'pane-settings-hotkey' }))?.props.hotkey).toBe('s')
    await ui.press({ key: 'pane-settings-hotkey' })
    expect((await ui.find({ key: 'settings-back' }))?.props.label).toBe('Back')
    expect((await ui.find({ key: 'settings-back-hotkey' }))?.props.hotkey).toBe('b')
  })

  test('keep the "c: " prefix on an older Claude Code', async ($, on) => {
    world(on, { ...SIGNED_IN, version: '2.1.292' })
    signedIn(on)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect((await ui.find({ key: 'pane-compact' }))?.props).toMatchObject({ hotkey: 'c', plain: true })
    expect(await ui.find({ key: 'pane-compact-hotkey' })).toBeUndefined()
    expect(isAtLeast('2.1.300-dev', '2.1.295')).toBe(true)
    expect(isAtLeast('2.2.0', '2.1.295')).toBe(true)
    expect(isAtLeast('2.1.294', '2.1.295')).toBe(false)
    expect(isAtLeast(undefined, '2.1.295')).toBe(false)
  })

  test('read as on, chosen or off in the settings', async ($, on) => {
    world(on, { tokens: 50_000 })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    expect((await ui.find({ key: 'set-layout-auto-box' }))?.props.borderColor).toBe('permission')
    expect((await ui.find({ key: 'set-layout-full' }))?.props.dimColor).toBe(true)
    expect((await ui.find({ key: 'set-openAtStart-toggle' }))?.props.label).toBe('● On')
    expect((await ui.find({ key: 'set-notify-kind-task' }))?.props).toMatchObject({ label: '○ task', dimColor: true })
    expect((await ui.find({ key: 'settings-back' }))?.props.hotkey).toBe('b')
  })
})

describe('settings view', () => {
  test('toggles sections without losing the order or the last one', () => {
    expect(sectionsToggled(['account', 'context', 'usage', 'agents', 'plan', 'repo', 'guard'], 'repo')).toBe('account,context,usage,agents,plan,guard')
    expect(sectionsToggled(['plan', 'context'], 'usage')).toBe('plan,context,usage')
    expect(sectionsToggled(['account', 'context', 'usage', 'agents', 'plan', 'repo'], 'guard')).toBe('')
    expect(sectionsToggled(['plan'], 'plan')).toBe('plan')
    expect(stepped(90, 5, 0, 100)).toBe(95)
    expect(stepped(100, 5, 0, 100)).toBe(100)
    expect(stepped(0, -5, 0, 100)).toBe(0)
  })

  test('/cockpit settings opens the settings', async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.command.run({ ...COCKPIT, args: 'settings' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Settings' })).toBeDefined()
    expect(await ui.find({ type: 'Button', key: 'set-openAtStart-toggle' })).toBeDefined()
  })

  for (const surface of SURFACES) {
    test(`writes each press through /config on ${surface}`, { options: { openAtStart: false, warnAt: 80 } }, async ($, on) => {
      const writes: [string, unknown][] = []
      world(on, { tokens: 284_000 })
      on('config.set', (_$, e) => {
        writes.push([e.key, e.value])
        return { value: e.value }
      })
      await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 'turn-0', reason: 'answer' })
      const ui = await $.ui.mount({ ...PANE, surface })
      await ui.press({ key: 'pane-settings' })
      await ui.press({ key: 'set-openAtStart-toggle' })
      await ui.press({ key: 'set-warnAt-more' })
      await ui.press({ key: 'set-layout-compact' })
      await ui.press({ key: 'set-section-guard' })
      expect(writes).toEqual([
        ['dr-cockpit.openAtStart', true],
        ['dr-cockpit.warnAt', 85],
        ['dr-cockpit.layout', 'compact'],
        ['dr-cockpit.sections', 'account,context,usage,agents,plan,repo'],
      ])
      await ui.press({ key: 'settings-back' })
      expect(await ui.find({ type: 'Text', text: 'Context' })).toBeDefined()
    })
  }

  test('says when a setting is refused', async ($, on) => {
    const toasts: string[] = []
    world(on, { tokens: 284_000, toasts })
    on('config.set', () => ({ deny: 'managed settings own it' }))
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'set-guardAttribution-toggle' })
    expect(toasts).toContain('dr-cockpit: guardAttribution not saved: managed settings own it')
  })
})

describe('pane graphics', () => {
  test('draw sparklines, marked tracks, stacked bars and window pace', () => {
    expect(sparkline([0, 50, 100])).toBe('▁▅█')
    expect(sparkline([7, 7])).toBe('▄▄')
    expect(track(0.5, 10, [{ at: 0.8, glyph: '┃', name: 'handoff' }])).toEqual([
      { text: '▰▰▰▰▰', kind: 'fill' },
      { text: '▱▱▱', kind: 'empty' },
      { text: '┃', kind: 'mark', mark: 'handoff' },
      { text: '▱', kind: 'empty' },
    ])
    expect(stackedRuns([180, 38, 1], 20)).toEqual([15, 4, 1])
    expect(stackedRuns([0, 0], 10)).toEqual([0, 0])
    expect(windowElapsed('five_hour', 1_000_000 + 3_600_000, 1_000_000)).toBe(0.8)
    expect(windowElapsed('spend_limit', 5, 1)).toBeNull()
  })

  test('keeps a trend of the context readings', async ($, on) => {
    const w: World = { tokens: 100_000 }
    world(on, w)
    await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 'turn-0', reason: 'answer' })
    w.tokens = 160_000
    await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 'turn-1', reason: 'answer' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: '▁█' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /\+60k/ })).toBeDefined()
  })
})

describe('account', () => {
  test('keys, colors, names and billing read as dr-status reads them', () => {
    expect(accountKey('/home/me/.claude', '/home/me')).toBe('~/.claude')
    expect(accountKey('C:\\Users\\me\\.claude-work', 'C:\\Users\\me')).toBe('~/.claude-work')
    expect(accountKey('/srv/claude', '/home/me')).toBe('/srv/claude')
    expect(termColor('141')).toBe('#af87ff')
    expect(termColor('orange')).toBe('#ff8700')
    expect(termColor('cyan')).toBe('cyan')
    expect(termColor('')).toBeUndefined()
    expect(modelName('claude-opus-5-5[1m]')).toBe('Opus 5.5')
    expect(modelName('claude-sonnet-4-5-20250929', true)).toBe('Sonnet')
    expect(billingLabel('stripe_subscription')).toBe('subscription')
  })

  test('shows a card with the email, organization, model and config directory', async ($, on) => {
    world(on, SIGNED_IN)
    signedIn(on)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Account' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /● me@example\.com/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Me · Acme \(admin\)/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Opus 5\.5 · xhigh effort/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'config ~/.claude' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'subscription' })).toBeDefined()
  })

  test('leaves the card out when no account is found', async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Account' })).toBeUndefined()
  })
})

describe('status strip', () => {
  const input = {
    cwd: '/home/me/code/shop/web/src',
    root: '/home/me/code/shop',
    home: '/home/me',
    repo: { branch: 'feat/a-rather-long-branch-name', ahead: 2, behind: 0, changed: 1, untracked: 2 },
    model: 'claude-opus-5-5',
    effort: 'high',
    context: { tokens: 94_000, window: 200_000 },
    cache: 0.93,
    usd: 1.2,
    limits: [{ kind: 'five_hour', percent: 23, resetsAt: 1_000_000 + 13_200_000 }],
    now: 1_000_000,
    email: null,
  }
  const text = (runs: { text: string }[]) => runs.map(run => run.text).join('')

  test('draws the fullest tier the way dr-status does', () => {
    const [one, two] = statusLines(input, 0)
    expect(text(one)).toBe('~/code/shop/web/src  ·  feat/a-rather-long-branch-name* ↑2 ?2  ·  Opus 5.5  ·  high')
    expect(text(two)).toBe('ctx ▰▰▰▰▰▱▱▱▱▱ 47% · 94k  ·  cache ▰▰▰▰▰▰▰▰▰▱ 93%  ·  $1.20  ·  5h ▰▰▱▱▱▱▱▱ 23% · 3h40m')
  })

  test('steps down a tier at a time until both lines fit', () => {
    const fits = (width: number) => fitStatus(input, width)
    expect(fits(200).tiers).toEqual([0, 0])
    expect(fits(76).tiers).toEqual([1, 1])
    expect(text(fits(76).lines[0])).toBe('shop/web/src  ·  feat/a-rather-long-branch-name* ↑2 ?2  ·  Opus 5.5  ·  high')
    expect(fits(75).tiers).toEqual([2, 2])
    expect(text(fits(60).lines[0])).toBe('shop/…/src · feat/a-rather-long-branch-name* · Opus · high')
    expect(text(fits(60).lines[1])).toBe('ctx ▰▰▱▱ 47% · cache ▰▰▰▱ 93% · $1.20 · 5h ▰▱▱ 23%')
    // Each line steps down on its own: the meters keep their bars beside a long first line.
    expect(fits(57).tiers).toEqual([3, 2])
    const last = fits(30)
    expect(last.tiers).toEqual([3, 3])
    expect(last.lines.every(line => runsWidth(line) <= 30)).toBe(true)
    expect(text(last.lines[0]).endsWith('…')).toBe(true)
  })
})

const WEBHOOK = 'https://discord.com/api/webhooks/123456789012/abcDEF_token-x'
const IDLE: ActivityInput = { kind: 'idle', since: 0, turnStartedAt: null, step: 0, tool: null, agent: null, detail: null, lastTurnMs: null, endedAt: null, isSent: false }
const flat = (runs: { text: string }[]) => runs.map(run => run.text).join('')

describe('forecasts', () => {
  test('count the turns left to the budget from recent growth', () => {
    expect(turnsToBudget([100_000, 120_000], 465_000)).toBeNull()
    expect(turnsToBudget([100_000, 120_000, 140_000, 160_000], 465_000)).toBe(16)
    // A compaction's drop is not growth.
    expect(turnsToBudget([300_000, 40_000, 60_000, 80_000], 465_000)).toBe(20)
    expect(turnsToBudget([400_000, 420_000, 470_000], 465_000)).toBeNull()
    expect(turnsToBudget([200_000, 200_000, 200_000], 465_000)).toBeNull()
  })

  test('say whether a limit lasts to its reset at the pace so far', () => {
    const hour = 3_600_000
    // Two hours into five, at 60%: 100% comes in 1h20m, before the reset.
    expect(limitForecast('five_hour', 60, 3 * hour, 0)).toBe((40 / 60) * 2 * hour)
    // Two hours in at 20%: it lasts.
    expect(limitForecast('five_hour', 20, 3 * hour, 0)).toBe('pace')
    // Too young a window, or one of unknown length, says nothing.
    expect(limitForecast('five_hour', 20, 5 * hour - 60_000, 0)).toBeNull()
    expect(limitForecast('spend_limit', 50, hour, 0)).toBeNull()
  })

  test('mark the context card and the limit meters', async ($, on) => {
    const w: World = { tokens: 100_000 }
    world(on, w)
    for (const tokens of [100_000, 300_000, 400_000]) {
      w.tokens = tokens
      await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 't', reason: 'answer' })
    }
    // 1h50m left of 5h at 78%: it runs out in about 53m.
    await $.session.measure({ ...MEASURE, rateLimits: [{ kind: 'five_hour', percentUsed: 78, resetsAt: new Date(1_000_000 + 6_600_000).toISOString() }] })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /≈1 turn$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /runs out in 53m, before reset/ })).toBeDefined()
  })
})

describe('now row', () => {
  test('reads each state on one line', () => {
    const at = 200_000
    expect(flat(nowLine({ ...IDLE }, at))).toBe('○ idle')
    expect(flat(nowLine({ ...IDLE, kind: 'running', since: 66_000, turnStartedAt: 66_000, step: 18, tool: 'Bash', agent: 'impl-sonnet-low' }, at))).toBe(
      '● running 2m14s · step 18 · Bash in impl-sonnet-low',
    )
    expect(flat(nowLine({ ...IDLE, kind: 'waiting', since: 158_000, detail: 'Bash: git push', isSent: true }, at))).toBe('⏳ approve? Bash: git push · 42s · Discord ✓')
    expect(flat(nowLine({ ...IDLE, kind: 'idle', lastTurnMs: 760_000, endedAt: 20_000 }, at))).toBe('○ idle · last turn 12m40s · ended 3m ago')
    expect(flat(nowBadge({ ...IDLE }, at))).toBe('')
    expect(flat(nowBadge({ ...IDLE, kind: 'running', since: 66_000, turnStartedAt: 66_000, tool: 'Bash' }, at))).toBe('● 2m14s · Bash')
    expect(elapsed(3_725_000)).toBe('1h02m')
  })

  test('follows a turn from start to end, and its tool calls', async ($, on) => {
    const w: World = { tokens: 50_000 }
    const clock = world(on, w)
    w.tools = {
      Read: async () => {
        await clock.sleep(5_000)
        return { result: 'ok', text: 'ok' }
      },
    }
    await $.turn.start({ text: 'go', turnId: 't1' })
    const reading = $.tool.call({ tool: 'Read', file_path: 'a.md' })
    await clock.advance(2_000)
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /running 2s · Read/ })).toBeDefined()
    await ui.unmount()
    await clock.advance(4_000)
    await reading
    await $.turn.complete({ answer: 'ok', durationMs: 6_000, isAborted: false, turnId: 't1', reason: 'answer' })
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /○ idle · last turn 6s/ })).toBeDefined()
  })

  test('rides on the strip\'s top rule while a turn runs', async ($, on) => {
    world(on, SIGNED_IN)
    signedIn(on)
    await $.session.start(START)
    await $.turn.start({ text: 'go', turnId: 't1' })
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^╭─ me@example\.com ─{74} ● 0s ─╮$/ })).toBeDefined()
  })
})

describe('discord', () => {
  test('knows a webhook, masks it, and reads a mention', () => {
    expect(isDiscordWebhook(WEBHOOK)).toBe(true)
    expect(isDiscordWebhook('https://ptb.discord.com/api/webhooks/1/x')).toBe(true)
    expect(isDiscordWebhook('https://example.com/api/webhooks/1/x')).toBe(false)
    expect(maskWebhook(WEBHOOK)).toBe('discord.com/…/1234…/••••')
    expect(mentionId('<@123456789>')).toBe('123456789')
    expect(mentionId('me')).toBeNull()
  })

  test('masks secrets and cuts excerpts', () => {
    expect(redact('curl -H "Authorization: Bearer abcdefghijkl" x')).toBe('curl -H "Authorization: Bearer [token]" x')
    expect(redact('export GH=ghp_abcdefghijklmnopqrstuvwxyz0123')).toBe('export GH=[token]')
    expect(redact('API_KEY=hunter2 make')).toBe('API_KEY=[hidden] make')
    expect(redact(`post ${WEBHOOK}`)).toBe('post [webhook]')
    expect(excerpt('a'.repeat(20), 10)).toBe(`${'a'.repeat(9)}…`)
  })

  test('picks kinds and keeps the default set as the empty setting', () => {
    expect(notifyKindsFrom('')).toEqual(['ask', 'question', 'done', 'error', 'blocked', 'budget', 'limit'])
    expect(notifyKindsFrom('done, nope, done')).toEqual(['done'])
    expect(notifyKindsToggled(notifyKindsFrom(''), 'agent')).toBe('ask,question,done,error,blocked,budget,limit,agent')
    expect(notifyKindsToggled(['ask', 'question', 'done', 'error', 'blocked', 'budget', 'limit', 'agent'], 'agent')).toBe('')
    expect(notifyKindsToggled(['done'], 'done')).toBe('none')
  })

  test('mentions the person only for what needs them', () => {
    const place = { host: 'devbox', repo: 'shop', branch: 'feat/x', tmux: 'work', account: '~/.claude' }
    const ping = discordBody({ kind: 'ask', title: '⏳ Waiting for approval', detail: 'Bash: git push' }, place, { mention: '42424242', isBrief: false, now: 0 })
    expect(ping.content).toBe('<@42424242>')
    expect(ping.allowed_mentions).toEqual({ parse: [], users: ['42424242'] })
    const embed = (ping.embeds as Record<string, unknown>[])[0]
    expect(embed?.author).toEqual({ name: 'devbox · shop' })
    expect(embed?.footer).toEqual({ text: 'dr-cockpit · ~/.claude · tmux work' })
    expect(embed?.description).toBe('Bash: git push')
    const quiet = discordBody({ kind: 'done', title: '✅ Done', detail: 'the answer' }, place, { mention: '42424242', isBrief: true, now: 0 })
    expect(quiet.content).toBeUndefined()
    expect(quiet.flags).toBe(4096)
    expect((quiet.embeds as Record<string, unknown>[])[0]?.description).toBeUndefined()
  })

  test('sends a long turn\'s end, and nothing without a webhook', { options: { notifyAfter: 60 } }, async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches })
    mock.store(on, { notifyUrl: WEBHOOK })
    await $.session.start(START)
    await $.turn.start({ text: 'go', turnId: 't1' })
    await $.turn.complete({ answer: 'quick', durationMs: 5_000, isAborted: false, turnId: 't1', reason: 'answer' })
    expect(fetches).toHaveLength(0)
    await $.turn.start({ text: 'go', turnId: 't2' })
    await $.turn.complete({ answer: 'Done. API_KEY=hunter2', durationMs: 125_000, isAborted: false, turnId: 't2', reason: 'answer' })
    expect(fetches).toHaveLength(1)
    expect(fetches[0]?.url).toBe(`${WEBHOOK}?wait=true`)
    const embed = (fetches[0]?.body.embeds as Record<string, unknown>[])[0]
    expect(embed?.title).toBe('✅ Done in 2m05s')
    expect(embed?.description).toBe('Done. API_KEY=[hidden]')
    expect(embed?.author).toEqual({ name: 'devbox · shop' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Discord ✓/ })).toBeUndefined()
  })

  test('says nothing when no webhook is set', { options: { notifyAfter: 0 } }, async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches })
    mock.store(on, {})
    await $.session.start(START)
    await $.turn.complete({ answer: 'ok', durationMs: 5_000, isAborted: false, turnId: 't1', reason: 'answer' })
    expect(fetches).toEqual([])
  })

  test('asks for an answer, then edits the message once it comes', { options: { notifyAskAfter: 0 } }, async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches })
    mock.store(on, { notifyUrl: WEBHOOK, notifyMention: '42424242' })
    await $.session.start(START)
    await $.turn.start({ text: 'go', turnId: 't1' })
    await $.tool.call({ tool: 'AskUserQuestion', questions: [{ question: 'Which layout?', header: 'Layout', multiSelect: false, options: [{ label: 'Compact', description: '' }, { label: 'Full', description: '' }] }] })
    expect(fetches.map(one => one.method)).toEqual(['POST', 'PATCH'])
    expect(fetches[0]?.body.content).toBe('<@42424242>')
    const asked = (fetches[0]?.body.embeds as Record<string, unknown>[])[0]
    expect(asked?.title).toBe('❓ Claude is asking')
    expect(asked?.description).toBe('Which layout?\n1. Compact  2. Full')
    expect(fetches[1]?.url).toBe(`${WEBHOOK}/messages/m1`)
    expect((fetches[1]?.body.embeds as Record<string, unknown>[])[0]?.title).toBe('✓ Answered')
  })

  test('says when a turn fails', async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches })
    mock.store(on, { notifyUrl: WEBHOOK })
    await $.session.start(START)
    await $.turn.start({ text: 'go', turnId: 't1' })
    await $.turn.complete({ answer: 'API Error: 529 overloaded', durationMs: 360_000, isAborted: false, turnId: 't1', reason: 'error' })
    expect((fetches[0]?.body.embeds as Record<string, unknown>[])[0]?.title).toBe('❌ Turn failed: API Error: 529 overloaded')
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /✗ last turn failed/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Discord ✓/ })).toBeDefined()
  })

  test('takes the webhook in the settings view and shows it masked', async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches })
    mock.store(on, {})
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    expect(await ui.find({ type: 'Text', text: /not set/ })).toBeDefined()
    await ui.press({ key: 'set-notify-url-edit' })
    await ui.input({ key: 'set-notify-url-input', text: 'https://example.com/hook', kind: 'submit' })
    expect(await ui.find({ type: 'Text', text: /not a Discord webhook URL/ })).toBeDefined()
    await ui.input({ key: 'set-notify-url-input', text: WEBHOOK, kind: 'submit' })
    expect(await ui.find({ type: 'Text', text: /discord\.com\/…\/1234…\/••••/ })).toBeDefined()
    await ui.press({ key: 'set-notify-test' })
    expect(fetches[0]?.url).toBe(`${WEBHOOK}?wait=true`)
    expect(JSON.stringify(await ui.drawn())).not.toContain('abcDEF_token')
  })

  test('/cockpit notify sets, tests and refuses', async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches })
    mock.store(on, {})
    await $.session.start(START)
    expect((await $.command.run({ ...COCKPIT, args: 'notify url https://example.com/x' })).text).toBe('not a Discord webhook URL')
    expect((await $.command.run({ ...COCKPIT, args: `notify url ${WEBHOOK}` })).text).toBe('Discord webhook saved.')
    expect((await $.command.run({ ...COCKPIT, args: 'notify test' })).text).toBe('Test message sent to Discord.')
    expect(fetches).toHaveLength(1)
  })
})

describe('run card', () => {
  const LEDGER = [
    '# SDD ledger — plan: docs/plans/p.md',
    'Task 1: implementer dr-superpowers:impl-sonnet-low (assigned; base abc1234)',
    'Task 1: complete (commits a..b, review clean) — done: x; verified: y; remaining: none; discovered: none; assumptions: none',
    'Task 2: implementer dr-superpowers:impl-sonnet-low (assigned; base def5678)',
    'Task 2: fix round 2/5 (1 addressed, 1 open — meter width; commits c..d; fresh)',
  ].join('\n')
  const PLAN = '# Plan\n\n### Task 1: Add the helpers\n\n### Task 2: Draw the card\n\n### Task 3: Ship it\n'
  const runFiles = (ledger: string): World['files'] => ({
    '/home/me/code/shop/.superpowers/sdd/p/progress.md': { text: ledger, mtimeMs: 2_000_000 },
    '/home/me/code/shop/docs/plans/p.md': { text: PLAN },
  })

  test('reads the ledger and the plan', () => {
    const ledger = parseLedger(`${LEDGER}\nGroup 3-4: review round 1/5 (open)\nTask 5: BLOCKED — impl exhausted — pick a rule\nFinal review: clean (commits a..b)`)
    expect(ledger.plan).toBe('docs/plans/p.md')
    expect(ledger.tasks.map(task => [task.n, task.state, task.round])).toEqual([
      [1, 'complete', null],
      [2, 'assigned', '2/5'],
      [3, 'assigned', '1/5'],
      [4, 'assigned', '1/5'],
      [5, 'blocked', null],
    ])
    expect(ledger.tasks[0]?.isClean).toBe(true)
    expect(ledger.tasks[4]?.reason).toBe('impl exhausted — pick a rule')
    expect(ledger.isFinished).toBe(true)
    expect(planTasks(PLAN)).toEqual([
      { n: 1, title: 'Add the helpers' },
      { n: 2, title: 'Draw the card' },
      { n: 3, title: 'Ship it' },
    ])
  })

  test('replaces the plan card in a dr-superpowers run', async ($, on) => {
    const files = runFiles(LEDGER)
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-superpowers:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Run' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^round 2\/5$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^1\/3$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers · clean/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /round 2\/5 · impl-sonnet-low/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Task 3: Ship it/ })).toBeDefined()
  })

  test('says a blocked task once, in red and on Discord', async ($, on) => {
    const files = runFiles(LEDGER)
    const fetches: World['fetches'] = []
    world(on, { ...SIGNED_IN, files, fetches })
    signedIn(on, files)
    mock.store(on, { notifyUrl: WEBHOOK })
    await $.tool.call({ tool: 'Skill', skill: 'dr-superpowers:subagent-driven-development' })
    await $.session.start(START)
    expect(fetches).toHaveLength(0)
    const ledger = files?.['/home/me/code/shop/.superpowers/sdd/p/progress.md']
    if (ledger !== undefined) ledger.text += '\nTask 2: BLOCKED — impl exhausted — pick a meter width rule'
    await $.tool.call({ tool: 'Bash', command: 'echo x >> .superpowers/sdd/p/progress.md' })
    await $.tool.call({ tool: 'Bash', command: 'cat .superpowers/sdd/p/progress.md' })
    expect(fetches).toHaveLength(1)
    expect((fetches[0]?.body.embeds as Record<string, unknown>[])[0]?.title).toBe('🛑 Task 2 blocked')
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^1 blocked$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /BLOCKED · impl exhausted/ })).toBeDefined()
  })

  test('offers Resume when a recent handoff waits', async ($, on) => {
    const files: World['files'] = { '/home/me/code/shop/.superpowers/handoff/latest.md': { text: '# Handoff', mtimeMs: 900_000 } }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ key: 'pane-resume' })).toBeDefined()
  })
})

describe('state file', () => {
  test('tells dr-status what the turn and the run are doing', async ($, on) => {
    const written: Record<string, string> = {}
    const clock = world(on, { ...SIGNED_IN, written })
    signedIn(on)
    await $.session.start(START)
    await $.turn.start({ text: 'go', turnId: 't1' })
    await clock.advance(600)
    const state = JSON.parse(written['/home/me/.claude/dr-cockpit/state/sess-1.json'] ?? '{}') as { activity?: { kind?: string; since?: number }; updatedAt?: number }
    expect(state.activity).toEqual({ kind: 'running', since: 1000, tool: null })
    expect(state.updatedAt).toBe(1000)
  })
})
