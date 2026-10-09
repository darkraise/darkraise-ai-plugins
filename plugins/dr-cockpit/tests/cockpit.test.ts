import { describe, expect, mock, test } from 'claude-code/testing'
import type { CommandRunInput, On, RenderElement, SessionMeasureInput, SessionMessage } from 'claude-code'

import {
  attributionIn,
  bar,
  budgetFor,
  duration,
  levelOf,
  planWithUpdate,
  repoFromPorcelain,
  sectionsToggled,
  sparkline,
  stackedRuns,
  stepped,
  track,
  windowElapsed,
  writesGitText,
} from '../hooks/lib'

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

// What a compaction leaves: one row standing for the conversation.
const SUMMARY: SessionMessage = { role: 'user', text: 'Summary.', toolUses: [] }

type World = {
  tokens: number | undefined
  window?: number
  settings?: Record<string, unknown>
  toasts?: string[]
  notes?: string[]
}

// The engine beneath the plugin: a context of `w.tokens` (read on each call,
// so a test moves it) in a 650k window, every tool call answered, every toast
// and every row the plugin appends recorded in `w.notes`.
function world(on: On, w: World) {
  mock.env(on, {})
  mock.clock(on, { now: 1_000_000 })
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
  on('tool.call', () => ({ result: 'ok', text: 'ok' }))
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'agent-1' }))
  on('turn.complete', () => ({ text: '' }))
  on('session.compact', (_$, e) => ({ messages: e.messages }))
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('process.run', () => ({
    value: { exitCode: 0, stdout: PORCELAIN, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
  }))
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
    const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Hand off: 610k of 604k/ })).toBeDefined()
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

describe('handoff band', () => {
  test('stays empty well under the budget', async ($, on) => {
    world(on, { tokens: 100_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...BAND, surface })
      expect(await ui.find({ text: /handoff/i })).toBeUndefined()
      await ui.unmount()
    }
  })

  test('warns near the budget and hides on request', async ($, on) => {
    world(on, { tokens: 400_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...BAND, surface })
      expect(await ui.find({ type: 'Text', text: /Nearing handoff: 400k of 465k \(86%\)/ })).toBeDefined()
      expect(await ui.find({ key: 'handoff' })).toBeUndefined()
      await ui.unmount()
    }
    const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
    await ui.press({ key: 'hide' })
    expect(await ui.find({ text: /handoff/i })).toBeUndefined()
  })

  test('in a plan session, offers the handoff and sends the note once', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 470_000, notes })
    await $.tool.call({ tool: 'Skill', skill: 'dr-superpowers:subagent-driven-development' })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes).toHaveLength(1)
    expect(notes[0]).toMatch(/budget: 470k of 465k — handoff/)
    const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Hand off: 470k of 465k/ })).toBeDefined()
    expect(await ui.find({ key: 'handoff' })).toBeDefined()
    expect(await ui.find({ key: 'hide' })).toBeUndefined()
  })

  test('stays quiet to the model outside a plan session', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 470_000, notes })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes).toEqual([])
  })

  test('clears after a compaction and re-arms the note and Hide', async ($, on) => {
    const notes: string[] = []
    const w: World = { tokens: 400_000, notes }
    world(on, w)
    await $.tool.call({ tool: 'Skill', skill: 'dr-superpowers:subagent-driven-development' })
    const warn = await $.ui.mount({ ...BAND, surface: 'terminal' })
    await warn.press({ key: 'hide' })
    await warn.unmount()

    w.tokens = 470_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes).toHaveLength(1)

    await $.session.compact({ trigger: 'manual', messages: [SUMMARY] })
    w.tokens = undefined
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const cleared = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await cleared.find({ text: /hand off/i })).toBeUndefined()
    await cleared.unmount()

    w.tokens = 400_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const back = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await back.find({ type: 'Text', text: /Nearing handoff: 400k/ })).toBeDefined()
    await back.unmount()

    w.tokens = 480_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes).toHaveLength(2)
  })
})

describe('hint line', () => {
  test('carries the reading under the prompt', async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...HINT, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: '284k/465k handoff' })).toBeDefined()
  })

  test('is off when configured off', { options: { showHint: false } }, async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...HINT, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /handoff/ })).toBeUndefined()
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
  test('warnAt moves the band', { options: { warnAt: 70 } }, async ($, on) => {
    world(on, { tokens: 340_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Nearing handoff: 340k of 465k \(73%\)/ })).toBeDefined()
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
  test('fits the strip above the prompt', async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.tool.call({
      tool: 'TodoWrite',
      todos: [
        { content: 'Read the plan', status: 'completed', activeForm: 'Reading' },
        { content: 'Write the pane', status: 'in_progress', activeForm: 'Writing' },
      ],
    })
    await $.session.measure(MEASURE)
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...INLINE, surface })
      expect(await ui.find({ type: 'Text', text: 'Context' })).toBeUndefined()
      expect(await ui.find({ type: 'Text', text: /284k\/465k/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /Plan 1\/2/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /▸ Write the pane/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /feat\/pane/ })).toBeDefined()
      expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
      await ui.unmount()
    }
  })

  test('is used docked too when asked', { options: { layout: 'compact' } }, async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Context' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /284k\/465k/ })).toBeDefined()
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
    on('ui.open', () => ({ value: { isPlaced: true } }))
    const answer = await $.command.run(COCKPIT)
    expect(answer.text).toBe('Cockpit pane opened.')
  })

  test('says why when Claude Code holds the pane back', async ($, on) => {
    world(on, { tokens: 284_000 })
    on('ui.open', () => ({ value: { isPlaced: false, reason: 'this desktop app places no panes' } }))
    const answer = await $.command.run(COCKPIT)
    expect(answer.text).toBe('Cockpit pane is waiting: this desktop app places no panes')
  })
})

describe('settings view', () => {
  test('toggles sections without losing the order or the last one', () => {
    expect(sectionsToggled(['context', 'usage', 'agents', 'plan', 'repo', 'guard'], 'repo')).toBe('context,usage,agents,plan,guard')
    expect(sectionsToggled(['plan', 'context'], 'usage')).toBe('plan,context,usage')
    expect(sectionsToggled(['context', 'usage', 'agents', 'plan', 'repo'], 'guard')).toBe('')
    expect(sectionsToggled(['plan'], 'plan')).toBe('plan')
    expect(stepped(90, 5, 0, 100)).toBe(95)
    expect(stepped(100, 5, 0, 100)).toBe(100)
    expect(stepped(0, -5, 0, 100)).toBe(0)
  })

  test('/cockpit settings opens the settings', async ($, on) => {
    world(on, { tokens: 284_000 })
    on('ui.open', () => ({ value: { isPlaced: true } }))
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
        ['dr-cockpit.sections', 'context,usage,agents,plan,repo'],
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
    await ui.press({ key: 'set-showHint-toggle' })
    expect(toasts).toContain('dr-cockpit: showHint not saved: managed settings own it')
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
