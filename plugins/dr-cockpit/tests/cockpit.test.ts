import { describe, expect, mock, test } from 'claude-code/testing'
import type { On, RenderElement } from 'claude-code'

import { attributionIn, budgetFor, levelOf, writesGitText } from '../hooks/lib'

const SURFACES = ['terminal', 'desktop'] as const
const BAND = {
  plugin: 'dr-cockpit',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 3, bodyColumns: 100, scroll: { offset: 0, bodyRows: 3 }, view: {} },
} as const
const PANE = {
  plugin: 'dr-cockpit',
  component: 'Pane',
  requestId: 'dr-cockpit',
  props: { title: 'Cockpit', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const

// The engine beneath the plugin: a context of `tokens` in a 650k window, every
// tool call answered, every toast recorded in `toasts`.
function world(on: On, tokens: number, toasts: string[] = []) {
  mock.env(on, {})
  on('session.usage', () => ({ value: { startedAt: 0, context: { tokens, window: 650_000 }, rateLimits: [], cost: { usd: 1.5 } } }))
  on('tool.call', () => ({ result: 'ok', text: 'ok' }))
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'agent-1' }))
  on('turn.complete', () => ({ text: '' }))
  on('ui.toast', (_$, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  // What the engine would draw itself where the plugin leaves a site alone.
  on('ui.render', ($, e) => {
    const { Box } = $.ui.resolve(e)
    return h(Box, { key: 'engine' }) as RenderElement
  })
}

describe('budget rule', () => {
  test('follows the setting, then the env, then dr-superpowers', () => {
    expect(budgetFor(200_000, '465000', 650_000)).toBe(200_000)
    expect(budgetFor(0, '465000', 650_000)).toBe(465_000)
    expect(budgetFor(0, undefined, 650_000)).toBe(464_500)
    expect(budgetFor(0, 'junk', 200_000)).toBe(100_000)
    expect(levelOf(300_000, 465_000)).toBe('quiet')
    expect(levelOf(400_000, 465_000)).toBe('warn')
    expect(levelOf(465_000, 465_000)).toBe('handoff')
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

  test('blanks the commit trailer and PR footer the engine composes', async ($, on) => {
    world(on, 10_000)
    expect((await $.attribution.text({ kind: 'commit', text: 'Co-Authored-By: Claude' })).text).toBe('')
    expect((await $.attribution.text({ kind: 'pr', text: 'Generated with Claude Code' })).text).toBe('')
  })

  test('refuses a commit carrying a trailer and lets a clean one run', async ($, on) => {
    world(on, 10_000)
    const dirty = await $.tool.call({
      tool: 'Bash',
      command: 'git commit -m "fix" -m "Claude-Session: https://claude.ai/code/session_1"',
    })
    expect(dirty.deny ?? dirty.text).toMatch(/keeps AI attribution out of git/)
    const clean = await $.tool.call({ tool: 'Bash', command: 'git commit -m "fix: tidy"' })
    expect(clean.deny).toBeUndefined()
  })

  test('is off when configured off', { options: { guardAttribution: false } }, async ($, on) => {
    world(on, 10_000)
    const ran = await $.tool.call({ tool: 'Bash', command: 'git commit -m "x" -m "Claude-Session: y"' })
    expect(ran.deny).toBeUndefined()
  })
})

describe('handoff band', () => {
  test('stays empty well under the budget', async ($, on) => {
    world(on, 100_000)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...BAND, surface })
      expect(await ui.find({ text: /handoff/i })).toBeUndefined()
      await ui.unmount()
    }
  })

  test('warns near the budget and hides on request', async ($, on) => {
    world(on, 400_000)
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

  // The kit does not route a plugin's own $.session.append to the test's
  // hooks, so the append fails here and the note reaches the toast fallback,
  // which carries the same text.
  test('in a plan session, offers the handoff and sends the note once', async ($, on) => {
    const notes: string[] = []
    world(on, 470_000, notes)
    await $.tool.call({ tool: 'Skill', skill: 'dr-superpowers:subagent-driven-development' })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes).toEqual([expect.stringMatching(/budget: 470k of 465k — handoff/)])
    const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Hand off: 470k of 465k/ })).toBeDefined()
    expect(await ui.find({ key: 'handoff' })).toBeDefined()
    expect(await ui.find({ key: 'hide' })).toBeUndefined()
  })

  test('stays quiet to the model outside a plan session', async ($, on) => {
    const notes: string[] = []
    world(on, 470_000, notes)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes).toEqual([])
  })
})

describe('cockpit pane', () => {
  test('sums a seat once its subagent finishes', async ($, on) => {
    world(on, 50_000)
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
      expect(await ui.find({ type: 'Text', text: /impl-sonnet-low ×1 · in 40k \(\s*75% cached\) · out 3k/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /done impl-sonnet-low: Task 3/ })).toBeDefined()
      await ui.unmount()
    }
  })
})
