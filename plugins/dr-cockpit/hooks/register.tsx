import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, TurnUsage } from 'claude-code'

import type { CockpitBudget, CockpitSeat, CockpitSpawn } from '../types'
import {
  attributionIn,
  budgetFor,
  isGitWriteTool,
  isSuperpowers,
  kTokens,
  levelOf,
  writesGitText,
} from './lib'

const PANE = 'dr-cockpit'
const HANDOFF_PROMPT =
  'Finish the task in flight through its completion line, then hand off with the dr-superpowers handoff skill. Start no new task.'

const budget = atom({ plugin: 'dr-cockpit', key: 'budget' } as const, null)
const seats = atom({ plugin: 'dr-cockpit', key: 'seats' } as const, [])
const spawns = atom({ plugin: 'dr-cockpit', key: 'spawns' } as const, [])
const isBandHidden = atom({ plugin: 'dr-cockpit', key: 'isBandHidden' } as const, false)
const isNudged = atom({ plugin: 'dr-cockpit', key: 'isNudged' } as const, false)
const isPlanSession = atom({ plugin: 'dr-cockpit', key: 'isPlanSession' } as const, false)

type Options = { handoffTokens: number; nudgeModel: boolean; guardAttribution: boolean }

export const register: Register = (on, options) => {
  const { handoffTokens = 0, nudgeModel = true, guardAttribution = true } = options as Partial<Options>

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'cockpit',
      description: 'Show subagent seats, their token use and the handoff budget in a pane',
    })
    await refresh($, handoffTokens, nudgeModel)

    return next(e)
  })

  on('command.run', { command: 'cockpit' }, async $ => {
    await $.ui.open({ id: PANE, title: 'Cockpit' })

    return { text: 'Cockpit pane opened.' }
  })

  on('agent.spawn', async ($, e, next) => {
    const started = await next(e)
    if (started.deny !== undefined || started.agentId === undefined) return started
    if (isSuperpowers(e.subagentType)) await update($, isPlanSession, () => true)
    const spawn: CockpitSpawn = {
      agentId: started.agentId,
      seat: e.subagentType,
      model: started.model,
      description: e.description,
      isDone: false,
    }
    await update($, spawns, list => [...list, spawn].slice(-50))

    return started
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined) {
      await refresh($, handoffTokens, nudgeModel)
      return done
    }
    const agentId = e.agentId
    const list = await read($, spawns)
    const spawn = list.find(one => one.agentId === agentId)
    if (spawn === undefined) return done
    await update($, spawns, all => all.map(one => (one.agentId === agentId ? { ...one, isDone: true } : one)))
    if (e.usage !== undefined) await update($, seats, all => addRun(all, spawn.seat, e.usage as TurnUsage))

    return done
  })

  if (guardAttribution) {
    on('attribution.text', { kind: 'commit' }, () => ({ text: '' }))
    on('attribution.text', { kind: 'pr' }, () => ({ text: '' }))
  }

  // One hook for every tool: the attribution guard judges before anything
  // runs, and the main loop's budget is read after each call, the only point
  // its context grows between turns.
  on('tool.call', async ($, e, next) => {
    const tool = String(e.tool)
    const line = guardAttribution ? attributionLine(tool, e) : undefined
    if (line !== undefined) {
      return { deny: `dr-cockpit: this project keeps AI attribution out of git. Remove "${line}" and try again.` }
    }
    const ran = await next(e)
    if (tool === 'Skill' && isSuperpowers(String((e as { skill?: unknown }).skill ?? ''))) {
      await update($, isPlanSession, () => true)
    }
    if (e.agentId === undefined) await refresh($, handoffTokens, nudgeModel)

    return ran
  }).catch(($, e, next) =>
    next.called || !guardAttribution ? next(e) : { deny: 'dr-cockpit: its attribution guard failed.' },
  )

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const now = await read($, budget)
    if (e.props.hasSurvey || now === null) return next(e)
    const level = levelOf(now.tokens, now.limit)
    // Hide quiets the warning only; past the budget the band always shows.
    if (level === 'quiet' || (level === 'warn' && (await read($, isBandHidden)))) return next(e)

    const { Box, Button, Text } = $.ui.resolve(e)
    const percent = Math.round((now.tokens / now.limit) * 100)
    const canHandOff = await read($, isPlanSession)

    return (
      <Box key="cockpit-band">
        <Text color={level === 'handoff' ? 'red' : 'yellow'} bold={level === 'handoff'}>
          {level === 'handoff' ? 'Hand off: ' : 'Nearing handoff: '}
          {kTokens(now.tokens)} of {kTokens(now.limit)} ({percent}%){' '}
        </Text>
        {canHandOff && (
          <Button
            key="handoff"
            label="Hand off"
            variant="primary"
            onPress={() => $.prompt.submit({ text: HANDOFF_PROMPT, asUser: true })}
          />
        )}
        {level === 'warn' && <Button key="hide" label="Hide" onPress={() => update($, isBandHidden, () => true)} />}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const now = await read($, budget)
    const list = await read($, seats)
    const recent = (await read($, spawns)).slice(-8)

    return (
      <Box flexDirection="column">
        <Text bold>Main session</Text>
        <Text dimColor>
          {now === null
            ? 'No reading yet.'
            : `${kTokens(now.tokens)} of ${kTokens(now.limit)} handoff budget` +
              (now.usd === null ? '' : ` · $${now.usd.toFixed(2)} so far`)}
        </Text>
        <Text bold>Seats</Text>
        {list.length === 0 && <Text dimColor>No subagent has finished yet.</Text>}
        {[...list]
          .sort((a, b) => totalIn(b) - totalIn(a))
          .map(seat => (
            <Text key={`seat-${seat.seat}`}>
              {seat.seat.replace(/^dr-superpowers:/, '')} ×{seat.runs} · in {kTokens(totalIn(seat))} (
              {cacheShare(seat)}% cached) · out {kTokens(seat.output)}
            </Text>
          ))}
        <Text bold>Recent</Text>
        {recent.length === 0 && <Text dimColor>No subagents yet.</Text>}
        {recent.map(spawn => (
          <Text key={`spawn-${spawn.agentId}`} dimColor={spawn.isDone}>
            {spawn.isDone ? 'done' : 'runs'} {spawn.seat.replace(/^dr-superpowers:/, '')}: {spawn.description}
          </Text>
        ))}
      </Box>
    )
  })
}

// Reads the status line's figures (free without a breakdown) and, past the
// budget in a dr-superpowers session, tells the model once.
async function refresh($: EngineInterface, handoffTokens: number, nudgeModel: boolean) {
  const usage = await $.session.usage()
  const tokens = usage.context.tokens
  if (tokens === undefined) return
  const limit = budgetFor(handoffTokens, await $.env.get('DR_SUPERPOWERS_BUDGET'), usage.context.window)
  const now: CockpitBudget = { tokens, limit, usd: usage.cost?.usd ?? null }
  await update($, budget, () => now)

  const level = levelOf(tokens, limit)
  if (level !== 'handoff') {
    // A compaction or /clear brought it back under: arm the note again.
    if (await read($, isNudged)) await update($, isNudged, () => false)
    return
  }
  if (!nudgeModel || (await read($, isNudged)) || !(await read($, isPlanSession))) return
  await update($, isNudged, () => true)
  const note = `dr-cockpit: budget: ${kTokens(tokens)} of ${kTokens(limit)} — handoff. ${HANDOFF_PROMPT}`
  try {
    await $.session.append({ message: { type: 'user', content: [{ type: 'text', text: note }] } })
  } catch {
    // The host would not take the row: say it to the person instead.
    $.ui.toast(note)
  }
}

function attributionLine(tool: string, e: object): string | undefined {
  if (tool === 'Bash') {
    const command = String((e as { command?: unknown }).command ?? '')
    return writesGitText(command) ? attributionIn(command) : undefined
  }
  return isGitWriteTool(tool) ? attributionIn(JSON.stringify(e)) : undefined
}

function addRun(all: CockpitSeat[], seat: string, usage: TurnUsage): CockpitSeat[] {
  const found = all.find(one => one.seat === seat)
  const base: CockpitSeat = found ?? { seat, runs: 0, input: 0, cacheRead: 0, cacheWrite: 0, output: 0 }
  const next: CockpitSeat = {
    seat,
    runs: base.runs + 1,
    input: base.input + usage.input_tokens,
    cacheRead: base.cacheRead + usage.cache_read_input_tokens,
    cacheWrite: base.cacheWrite + usage.cache_creation_input_tokens,
    output: base.output + usage.output_tokens,
  }

  return found ? all.map(one => (one.seat === seat ? next : one)) : [...all, next]
}

function totalIn(seat: CockpitSeat): number {
  return seat.input + seat.cacheRead + seat.cacheWrite
}

function cacheShare(seat: CockpitSeat): number {
  const total = totalIn(seat)
  return total === 0 ? 0 : Math.round((seat.cacheRead / total) * 100)
}
