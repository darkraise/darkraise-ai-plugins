import { describe, expect, test } from 'claude-code/testing'
import { mock } from 'claude-code/testing'
import type { On } from 'claude-code'

import { seatDenial } from '../hooks/cockpit/lib'

// Acceptance tests for docs/dagents/specs/2026-10-25-typed-seats-and-drafting-design.md,
// the cockpit statements (A1-A4, A8). They reach the hook only through the
// engine's agent.spawn surface: a session becomes a dagents session by running
// a dagents skill, and the denial is read from the cockpit pane's refusals.

const START = { cwd: '/home/me/code/shop/web', surface: 'terminal', isInteractive: true } as never
const PANE = {
  plugin: 'dagents',
  component: 'Pane',
  requestId: 'dagents',
  surface: 'terminal',
  props: { title: 'Cockpit', isFocused: false, bodyColumns: 200, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
} as const

function world(on: On) {
  mock.env(on, {})
  mock.clock(on, { now: 1_000_000 })
  on('command.register', () => ({ value: undefined }) as never)
  on('session.start', (_$, e) => e as never)
  on('session.usage', () => ({
    value: { startedAt: 0, context: { tokens: 10_000, window: 650_000 }, rateLimits: [], cost: { usd: 1.5 } },
  }))
  on('settings.read', () => ({ value: {} }))
  on('tool.call', () => ({ result: 'ok', text: 'ok' }))
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'agent-1' }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('session.attach', (_$, e) => ({ clientId: e.clientId }))
  on('session.detach', (_$, e) => ({ clientId: e.clientId }))
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.open', () => ({ value: { isPlaced: true } }) as never)
  on('ui.close', () => ({ value: undefined }) as never)
  on('process.run', () => ({ value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
}

let n = 0
const spawn = (fields: Record<string, unknown>) =>
  ({
    tool_use_id: `toolu_${++n}`,
    prompt: 'Do the work',
    description: 'Look around',
    subagentType: 'general-purpose',
    provider: { plugin: 'engine', tier: 'core' },
    parentModel: 'claude-opus-5-5',
    background: false,
    fork: false,
    ...fields,
  }) as never

const REASON = /^dagents: /

describe('typed seats and drafting: acceptance', () => {
  test('A1: an untyped general-purpose or claude spawn is denied, naming a judge seat, an impl seat and model "sonnet"', async ($, on) => {
    world(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dagents:subagent-driven-development' })
    for (const subagentType of ['general-purpose', 'claude']) {
      const out = await $.agent.spawn(spawn({ subagentType }))
      expect(out.deny).toMatch(REASON)
      expect(out.deny).toMatch(/dagents:judge-sonnet-high/)
      expect(out.deny).toMatch(/dagents:impl-sonnet-medium/)
      expect(out.deny).toContain('model: "sonnet"')
    }
  })

  test('A2: general-purpose with a model, any dagents: agent and a typed built-in are not denied', async ($, on) => {
    world(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dagents:subagent-driven-development' })
    // The session is a dagents session: the untyped spawn is denied.
    expect((await $.agent.spawn(spawn({}))).deny).toBeDefined()
    expect((await $.agent.spawn(spawn({ model: 'sonnet' }))).deny).toBeUndefined()
    expect((await $.agent.spawn(spawn({ model: 'opus' }))).deny).toBeUndefined()
    expect((await $.agent.spawn(spawn({ subagentType: 'claude', model: 'sonnet' }))).deny).toBeUndefined()
    for (const subagentType of ['dagents:judge-opus', 'dagents:judge-sonnet-high', 'dagents:impl-sonnet-medium']) {
      expect((await $.agent.spawn(spawn({ subagentType }))).deny).toBeUndefined()
    }
    for (const subagentType of ['Explore', 'Plan']) expect((await $.agent.spawn(spawn({ subagentType }))).deny).toBeUndefined()
  })

  test('A3: nothing is denied before a dagents skill or agent ran', async ($, on) => {
    world(on)
    await $.session.start(START)
    expect((await $.agent.spawn(spawn({}))).deny).toBeUndefined()
    expect((await $.agent.spawn(spawn({ subagentType: 'claude' }))).deny).toBeUndefined()
    expect((await $.agent.spawn(spawn({ subagentType: 'fork', fork: true }))).deny).toBeUndefined()
    // A non-dagents skill does not make the session a dagents session.
    await $.tool.call({ tool: 'Skill', skill: 'simplify' })
    expect((await $.agent.spawn(spawn({}))).deny).toBeUndefined()
  })

  test('A3: in a dagents session nothing is denied from a subagent loop, a workflow agent, a teammate or a resume', async ($, on) => {
    world(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dagents:subagent-driven-development' })
    expect((await $.agent.spawn(spawn({}))).deny).toBeDefined()
    expect((await $.agent.spawn(spawn({ parentAgentId: 'agent-1' }))).deny).toBeUndefined()
    expect((await $.agent.spawn(spawn({ parentAgentId: 'agent-1', subagentType: 'fork', fork: true }))).deny).toBeUndefined()
    expect((await $.agent.spawn(spawn({ workflow: { runId: 'wf_1', agentIndex: 1 } }))).deny).toBeUndefined()
    expect((await $.agent.spawn(spawn({ isTeammate: true }))).deny).toBeUndefined()
    expect((await $.agent.spawn(spawn({ resume: { agentId: 'agent-1' } }))).deny).toBeUndefined()
  })

  test('A3: a spawn of a dagents agent makes the session a dagents session', async ($, on) => {
    world(on)
    await $.session.start(START)
    expect((await $.agent.spawn(spawn({}))).deny).toBeUndefined()
    expect((await $.agent.spawn(spawn({ subagentType: 'dagents:judge-opus' }))).deny).toBeUndefined()
    expect((await $.agent.spawn(spawn({}))).deny).toMatch(REASON)
  })

  test('A4: a fork is denied in a dagents session, and a drafting-named fork too while forks do not draft', async ($, on) => {
    world(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dagents:writing-plans' })
    for (const description of ['Verify the register rows', 'Draft plan tasks 1-2', 'Draft plan tasks 3-4']) {
      const out = await $.agent.spawn(spawn({ subagentType: 'fork', fork: true, description }))
      expect(out.deny).toMatch(REASON)
      expect(out.deny).toMatch(/fork/i)
    }
    // A fork with an explicit model is still a fork.
    expect((await $.agent.spawn(spawn({ subagentType: 'fork', fork: true, model: 'sonnet' }))).deny).toMatch(REASON)
  })

  test('A4: every fork is denied, a drafting one included', () => {
    const base = { subagentType: 'fork', fork: true, description: 'Draft plan tasks 1-2' }
    for (const description of ['Draft plan tasks 1-2', 'Draft plan tasks 5-6', 'Verify the register rows', 'Consolidate findings', 'Please draft plan tasks 1-2']) {
      expect(seatDenial({ ...base, description }, true)).toMatch(REASON)
    }
  })

  test('A8: a denied spawn is listed in the cockpit refusals with tool Agent and the deny reason', async ($, on) => {
    world(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dagents:subagent-driven-development' })
    const denied = await $.agent.spawn(spawn({}))
    expect(denied.deny).toMatch(REASON)
    const ui = await $.ui.mount(PANE as never)
    const row = await ui.find({ type: 'Text', text: /✗ Agent: / })
    expect(row).toBeDefined()
    // The line carries the reason's opening words, which name the remedy.
    expect(await ui.find({ type: 'Text', text: /✗ Agent: dagents: name a seat/ })).toBeDefined()
  })

  test('A8: an allowed spawn adds no refusal', async ($, on) => {
    world(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dagents:subagent-driven-development' })
    expect((await $.agent.spawn(spawn({ model: 'sonnet' }))).deny).toBeUndefined()
    const ui = await $.ui.mount(PANE as never)
    expect(await ui.find({ type: 'Text', text: /✗ Agent:/ })).toBeUndefined()
  })
})
