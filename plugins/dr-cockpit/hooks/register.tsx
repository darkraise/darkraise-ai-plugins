import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderChildren, TurnUsage } from 'claude-code'

import type {
  CockpitBreakdown,
  CockpitBudget,
  CockpitPlanItem,
  CockpitRefusal,
  CockpitSeat,
  CockpitSpawn,
  CockpitUsage,
} from '../types'
import {
  attributionIn,
  bar,
  budgetFor,
  duration,
  isGitWriteTool,
  isSuperpowers,
  kTokens,
  levelOf,
  limitLabel,
  planFromTodos,
  planWithUpdate,
  positive,
  rampColor,
  repoFromPorcelain,
  sectionsFrom,
  warnShare,
  writesGitText,
} from './lib'
import type { Section } from './lib'

const PANE = 'dr-cockpit'
const PANE_COLUMNS = 56
const INDENT = 2
// The rows the compact layout asks for above the prompt.
const COMPACT_ROWS = 8
// The most /context categories the pane lists (breakdownRows caps it lower).
const MAX_BREAKDOWN_ROWS = 12
// Room the compact layout needs to keep context and usage on one line.
const ONE_LINE_COLUMNS = 90
const HANDOFF_PROMPT =
  'Finish the task in flight through its completion line, then hand off with the dr-superpowers handoff skill. Start no new task.'
const GIT_STATUS = ['git', '--no-optional-locks', '-c', 'core.fsmonitor=false', 'status', '--porcelain=v2', '--branch']

const budget = atom({ plugin: 'dr-cockpit', key: 'budget' } as const, null)
const usage = atom({ plugin: 'dr-cockpit', key: 'usage' } as const, null)
const breakdown = atom({ plugin: 'dr-cockpit', key: 'breakdown' } as const, null)
const seats = atom({ plugin: 'dr-cockpit', key: 'seats' } as const, [])
const spawns = atom({ plugin: 'dr-cockpit', key: 'spawns' } as const, [])
const plan = atom({ plugin: 'dr-cockpit', key: 'plan' } as const, [])
const repo = atom({ plugin: 'dr-cockpit', key: 'repo' } as const, null)
const refusals = atom({ plugin: 'dr-cockpit', key: 'refusals' } as const, [])
const isBandHidden = atom({ plugin: 'dr-cockpit', key: 'isBandHidden' } as const, false)
const isNudged = atom({ plugin: 'dr-cockpit', key: 'isNudged' } as const, false)
const isPlanSession = atom({ plugin: 'dr-cockpit', key: 'isPlanSession' } as const, false)
const alerted = atom({ plugin: 'dr-cockpit', key: 'alerted' } as const, [])

type Options = {
  handoffTokens: number
  nudgeModel: boolean
  guardAttribution: boolean
  showHint: boolean
  warnAt: number
  layout: string
  sections: string
  breakdownRows: number
  openAtStart: boolean
  limitAlertAt: number
}

/** What the budget reading is judged by. */
type Tuning = { handoffTokens: number; nudgeModel: boolean; warnAt: number }

export const register: Register = (on, options) => {
  const {
    handoffTokens = 0,
    nudgeModel = true,
    guardAttribution = true,
    showHint = true,
    warnAt: warnPercent = 80,
    layout: layoutSetting = 'auto',
    sections: sectionList = '',
    breakdownRows = 6,
    openAtStart = true,
    limitAlertAt = 90,
  } = options as Partial<Options>
  // A plain string in the manifest (older validators refuse a picker), so
  // anything but the three words reads as auto.
  const layout = layoutSetting === 'full' || layoutSetting === 'compact' ? layoutSetting : 'auto'
  const tuning: Tuning = { handoffTokens, nudgeModel, warnAt: warnShare(warnPercent) }
  const shown = sectionsFrom(sectionList)
  const paneArgs = { id: PANE, title: 'Cockpit', columns: PANE_COLUMNS, ...(layout === 'full' ? {} : { rows: COMPACT_ROWS }) }
  // The settings' autoCompactWindow, read at the start and after each main
  // turn rather than on every tool call.
  let compactWindow: number | undefined

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'cockpit',
      description: 'Show context, usage, subagents, the plan and the repo in a pane',
    })
    compactWindow = await readCompactWindow($)
    await refresh($, tuning, compactWindow)
    // Unasked, the engine seats the pane from 144 columns and holds it below.
    if (openAtStart) void $.ui.open(paneArgs)

    return next(e)
  })

  on('command.run', { command: 'cockpit' }, async $ => {
    const opened = await $.ui.open(paneArgs)
    await refreshDetail($)

    // A surface that seats no panes (an older desktop) holds it undrawn: say
    // why rather than claim it opened.
    return { text: opened.isPlaced ? 'Cockpit pane opened.' : `Cockpit pane is waiting: ${opened.reason}` }
  })

  on('session.measure', async ($, e, next) => {
    const done = await next(e)
    const now = await $.clock.now()
    const startedAt = (await read($, usage))?.startedAt ?? (await $.session.usage()).startedAt
    const reading: CockpitUsage = {
      startedAt,
      readAt: now,
      limits: e.rateLimits.map(limit => ({
        kind: limit.kind,
        percent: limit.percentUsed,
        resetsAt: limit.resetsAt === undefined ? null : Date.parse(limit.resetsAt) || null,
      })),
    }
    await update($, usage, () => reading)
    if (limitAlertAt > 0) await alertLimits($, reading, limitAlertAt)
    if (await isPaneUp($)) await refreshDetail($)

    return done
  })

  // A compaction leaves no reading until the next response: drop the stale
  // one and re-arm the note and Hide, so neither stays latched.
  on('session.compact', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined && e.trigger !== 'precompute' && 'messages' in done && done.messages !== undefined) {
      await update($, budget, () => null)
      await update($, isNudged, () => false)
      await update($, isBandHidden, () => false)
    }

    return done
  }).catch(($, e, next) => next(e))

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
      startedAt: await $.clock.now(),
    }
    await update($, spawns, list => [...list, spawn].slice(-50))

    return started
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined) {
      compactWindow = await readCompactWindow($)
      await refresh($, tuning, compactWindow)
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
  // runs, and the main loop's budget and plan are read after each call, the
  // only point its context grows between turns.
  on('tool.call', async ($, e, next) => {
    const tool = String(e.tool)
    const line = guardAttribution ? attributionLine(tool, e) : undefined
    if (line !== undefined) {
      const refusal: CockpitRefusal = { at: await $.clock.now(), tool, line }
      await update($, refusals, list => [...list, refusal].slice(-20))
      return { deny: `dr-cockpit: this project keeps AI attribution out of git. Remove "${line}" and try again.` }
    }
    const ran = await next(e)
    if (tool === 'Skill' && isSuperpowers(String((e as { skill?: unknown }).skill ?? ''))) {
      await update($, isPlanSession, () => true)
    }
    if (e.agentId === undefined) {
      if (ran.deny === undefined && !ran.isError) await trackPlan($, tool, e, ran.result)
      await refresh($, tuning, compactWindow)
    }

    return ran
  }).catch(($, e, next) =>
    next.called || !guardAttribution ? next(e) : { deny: 'dr-cockpit: its attribution guard failed.' },
  )

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const now = await read($, budget)
    if (e.props.hasSurvey || now === null) return next(e)
    const level = levelOf(now.tokens, now.limit, tuning.warnAt)
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

  // The quiet, always-there reading: a dim tail on the hint line under the
  // prompt, so the band only has to speak up near the budget.
  if (showHint) {
    on('ui.render', { component: 'PromptHint' }, async ($, e, next) => {
      const now = await read($, budget)
      if (now === null) return next(e)
      const reading = `${kTokens(now.tokens)}/${kTokens(now.limit)} handoff`
      const tail = e.props.tail === undefined ? reading : `${e.props.tail} · ${reading}`

      return next({ ...e, props: { ...e.props, tail } })
    })
  }

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const now = await $.clock.now()
    const room = e.props.bodyColumns
    const isCompact = layout === 'compact' || (layout === 'auto' && e.props.placement === 'inline')
    // Room for the label, percentage and suffix beside the bar, inside the indent.
    const meterWidth = isCompact ? 8 : Math.max(6, Math.min(20, room - INDENT - 30))
    const head = await read($, budget)
    const spend = await read($, usage)
    const rows = await read($, breakdown)
    const list = await read($, seats)
    const all = await read($, spawns)
    const items = await read($, plan)
    const git = await read($, repo)
    const refused = await read($, refusals)
    const canHandOff = await read($, isPlanSession)

    const meter = (key: string, label: string, percent: number, suffix: string, width = meterWidth) => (
      <Text key={key}>
        <Text dimColor>{label.padEnd(isCompact ? label.length + 1 : 4)}</Text>
        <Text color={rampColor(percent)}>{bar(percent / 100, width)}</Text>
        <Text color={rampColor(percent)} bold>
          {' '}
          {Math.round(percent)}%
        </Text>
        {suffix !== '' && <Text dimColor> · {suffix}</Text>}
      </Text>
    )
    const actions = (
      <Box key="actions">
        {canHandOff && (
          <Button
            key="pane-handoff"
            label="Hand off"
            hotkey="h"
            onPress={() => $.prompt.submit({ text: HANDOFF_PROMPT, asUser: true })}
          />
        )}
        <Button key="pane-compact" label="Compact" hotkey="c" onPress={() => $.session.compact()} />
      </Box>
    )
    const running = all.filter(one => !one.isDone)
    const finished = all.filter(one => one.isDone)
    const doneCount = items.filter(item => item.status === 'completed').length
    const current = items.find(item => item.status === 'in_progress') ?? items.find(item => item.status === 'pending')
    const limits = spend?.limits ?? []
    const cost = head?.usd == null ? null : `$${head.usd.toFixed(2)}`

    if (isCompact) {
      // One row per section, for the strip above the prompt.
      const contextMeter =
        head === null
          ? null
          : meter('ctx', 'ctx', (head.tokens / head.limit) * 100, `${kTokens(head.tokens)}/${kTokens(head.limit)}`)
      const isOneLine = room >= ONE_LINE_COLUMNS
      // Beside the context meter the limits keep short bars; on a line of
      // their own they get the full compact width.
      const limitMeters = limits.map(limit =>
        meter(`limit-${limit.kind}`, limitLabel(limit.kind), limit.percent, '', isOneLine ? 4 : meterWidth),
      )
      const joined = (key: string, parts: RenderChildren[]) => (
        <Text key={key} wrap="truncate-end">
          {parts.filter(part => part !== null && part !== false).flatMap((part, index) =>
            index === 0 ? [part] : [<Text dimColor>{' · '}</Text>, part],
          )}
        </Text>
      )
      const wantsUsage = shown.includes('usage')
      const byName: Record<Section, RenderChildren> = {
        context: joined('c-context', [
          contextMeter,
          ...(wantsUsage && isOneLine ? limitMeters : []),
          wantsUsage && cost !== null ? <Text>{cost}</Text> : null,
        ]),
        usage: isOneLine || limitMeters.length === 0 ? null : joined('c-usage', limitMeters),
        agents:
          running.length + finished.length === 0 ? null : (
            <Text key="c-agents" wrap="truncate-end">
              {running[0] === undefined
                ? `✓ ${finished.length} done`
                : `▸ ${shortSeat(running[0].seat)}: ${running[0].description} · ${duration(now - running[0].startedAt) || '<1m'}`}
              <Text dimColor>
                {running.length > 1 ? `  +${running.length - 1} running` : ''}
                {running[0] !== undefined && finished.length > 0 ? `  +${finished.length} done` : ''}
              </Text>
            </Text>
          ),
        plan:
          items.length === 0 ? null : (
            <Text key="c-plan" wrap="truncate-end">
              <Text bold>
                Plan {doneCount}/{items.length}
              </Text>
              {current === undefined ? '' : ` ▸ ${current.text}`}
            </Text>
          ),
        repo:
          git === null ? null : (
            <Text key="c-repo" wrap="truncate-end">
              <Text color="magenta" bold>
                {git.branch}
              </Text>
              {git.ahead > 0 ? ` ↑${git.ahead}` : ''}
              {git.behind > 0 ? ` ↓${git.behind}` : ''}
              <Text dimColor>{repoChanges(git)}</Text>
            </Text>
          ),
        guard:
          refused.length === 0 ? null : (
            <Text key="c-guard" color="yellow" wrap="truncate-end">
              guard refused {refused.length === 1 ? '1 git write' : `${refused.length} git writes`}
            </Text>
          ),
      }

      return (
        <Box flexDirection="column">
          {shown.map(name => byName[name])}
          {actions}
        </Box>
      )
    }

    // Three levels: a section's title, its rows two cells in, and a row's
    // details two cells further.
    const section = (key: string, title: string, ...body: RenderChildren[]) => (
      <Box key={key} flexDirection="column">
        <Text bold>{title}</Text>
        <Box flexDirection="column" paddingLeft={INDENT}>
          {body}
        </Box>
      </Box>
    )
    const details = (key: string, ...body: RenderChildren[]) => (
      <Box key={key} flexDirection="column" paddingLeft={INDENT}>
        {body}
      </Box>
    )
    const recent = [...running, ...finished.slice(-Math.max(0, 6 - running.length))]
    const shownItems = planWindow(items, 8)
    const sortedSeats = [...list].sort((a, b) => totalIn(b) - totalIn(a))
    const breakdownShown = (rows?.rows ?? []).slice(0, Math.max(0, Math.min(MAX_BREAKDOWN_ROWS, breakdownRows)))

    const byName: Record<Section, RenderChildren> = {
      context: section(
        'context',
        'Context',
        head === null ? (
          <Text key="ctx-none" dimColor>
            No reading yet.
          </Text>
        ) : (
          meter('ctx', 'ctx', (head.tokens / head.limit) * 100, `${kTokens(head.tokens)} of ${kTokens(head.limit)} handoff`)
        ),
        head !== null &&
          details(
            'ctx-details',
            <Text key="ctx-window" dimColor>
              window {kTokens(head.window)}
              {rows?.compactAt != null ? ` · compacts at ${kTokens(rows.compactAt)}` : ''}
              {head.compactWindow !== null && rows?.compactAt == null
                ? ` · compact window ${kTokens(head.compactWindow)}`
                : ''}
            </Text>,
            breakdownShown.map(row => (
              <Text key={`ctx-row-${row.name}`} dimColor>
                {row.name.padEnd(Math.min(22, Math.max(8, room - 16)))} {kTokens(row.tokens).padStart(5)}
              </Text>
            )),
          ),
        actions,
      ),
      usage: section(
        'usage',
        'Usage',
        limits.map(limit =>
          meter(
            `limit-${limit.kind}`,
            limitLabel(limit.kind),
            limit.percent,
            limit.resetsAt === null ? '' : `resets in ${duration(limit.resetsAt - now) || 'now'}`,
          ),
        ),
        <Text key="cost" dimColor={cost === null}>
          {head?.usd == null
            ? 'No cost reading.'
            : `${cost} this session` + costRate(head.usd, spend?.startedAt, now)}
        </Text>,
      ),
      agents: section(
        'agents',
        'Agents',
        all.length === 0 && (
          <Text key="agents-none" dimColor>
            No subagents yet.
          </Text>
        ),
        recent.map(spawn => (
          <Text key={`spawn-${spawn.agentId}`} dimColor={spawn.isDone} wrap="truncate-end">
            {spawn.isDone ? '✓' : '▸'} {shortSeat(spawn.seat)}: {spawn.description}
            {spawn.isDone ? '' : ` · ${duration(now - spawn.startedAt) || '<1m'}`}
          </Text>
        )),
        sortedSeats.length > 0 && (
          <Text key="seats" dimColor>
            Seats
          </Text>
        ),
        sortedSeats.length > 0 &&
          details(
            'seat-rows',
            sortedSeats.map(seat => (
              <Text key={`seat-${seat.seat}`} wrap="truncate-end">
                {shortSeat(seat.seat)} ×{seat.runs} · in {kTokens(totalIn(seat))} ({cacheShare(seat)}% cached) · out{' '}
                {kTokens(seat.output)}
              </Text>
            )),
          ),
      ),
      plan:
        items.length > 0 &&
        section(
          'plan',
          `Plan · ${doneCount} of ${items.length} done`,
          shownItems.map(item => (
            <Text
              key={`plan-${item.id}`}
              dimColor={item.status === 'completed'}
              bold={item.status === 'in_progress'}
              wrap="truncate-end"
            >
              {item.status === 'completed' ? '✓' : item.status === 'in_progress' ? '▸' : '○'} {item.text}
            </Text>
          )),
        ),
      repo:
        git !== null &&
        section(
          'repo',
          'Repo',
          <Text key="repo" wrap="truncate-end">
            <Text color="magenta" bold>
              {git.branch}
            </Text>
            {git.ahead > 0 ? ` ↑${git.ahead}` : ''}
            {git.behind > 0 ? ` ↓${git.behind}` : ''}
            <Text dimColor>{repoChanges(git)}</Text>
          </Text>,
        ),
      guard:
        refused.length > 0 &&
        section(
          'guard',
          'Guard',
          refused.slice(-3).map(refusal => (
            <Text key={`guard-${refusal.at}`} color="yellow" wrap="truncate-end">
              refused {refusal.tool}: {refusal.line}
            </Text>
          )),
        ),
    }

    return (
      <Box flexDirection="column">
        {shown.map(name => byName[name])}
        {!shown.includes('context') && actions}
      </Box>
    )
  })
}

// Reads the status line's figures (free without a breakdown) and, past the
// budget in a dr-superpowers session, tells the model once.
async function refresh($: EngineInterface, tuning: Tuning, compactWindow: number | undefined) {
  const { handoffTokens, nudgeModel } = tuning
  const figures = await $.session.usage()
  const tokens = figures.context.tokens
  if (tokens === undefined) return
  const window = figures.context.window
  const limit = budgetFor(handoffTokens, await $.env.get('DR_SUPERPOWERS_BUDGET'), window, compactWindow)
  const usd = figures.cost?.usd ?? null
  const before = await read($, budget)
  if (
    before?.tokens !== tokens ||
    before.limit !== limit ||
    before.usd !== usd ||
    before.window !== window ||
    before.compactWindow !== (compactWindow ?? null)
  ) {
    const now: CockpitBudget = { tokens, limit, window, compactWindow: compactWindow ?? null, usd }
    await update($, budget, () => now)
  }

  const level = levelOf(tokens, limit, tuning.warnAt)
  if (level === 'quiet') {
    // Back under (a compaction, /clear): show the warning again next time.
    if (await read($, isBandHidden)) await update($, isBandHidden, () => false)
  }
  if (level !== 'handoff') {
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

// The pane's slower readings: the /context breakdown, estimated locally, and
// the working tree's git state. Read while the pane is up, never per tool call.
async function refreshDetail($: EngineInterface) {
  try {
    const figures = await $.session.usage({ breakdown: 'summary' })
    const detail = figures.context.breakdown
    if (detail !== undefined) {
      const next: CockpitBreakdown = {
        rows: detail.categories
          .filter(row => row.kind === 'used' && row.tokens > 0)
          .sort((a, b) => b.tokens - a.tokens)
          .slice(0, MAX_BREAKDOWN_ROWS)
          .map(row => ({ name: row.name, tokens: row.tokens })),
        compactAt: detail.isAutoCompactEnabled ? (detail.autoCompactThreshold ?? null) : null,
      }
      await update($, breakdown, () => next)
    }
  } catch {
    // No breakdown on this host: the pane shows the totals alone.
  }
  try {
    const ran = await $.process.run(GIT_STATUS, { timeoutMs: 3000 })
    const state = ran.exitCode === 0 ? repoFromPorcelain(ran.stdout) : null
    await update($, repo, () => state)
  } catch {
    await update($, repo, () => null)
  }
}

async function readCompactWindow($: EngineInterface): Promise<number | undefined> {
  try {
    return positive(((await $.settings.read()) as { autoCompactWindow?: unknown }).autoCompactWindow)
  } catch {
    return undefined
  }
}

// Says once per window and reset when a rate limit crosses the alert line.
async function alertLimits($: EngineInterface, reading: CockpitUsage, at: number) {
  const said = await read($, alerted)
  for (const limit of reading.limits) {
    const key = `${limit.kind}@${limit.resetsAt ?? ''}`
    if (limit.percent < at || said.includes(key)) continue
    await update($, alerted, list => [...list, key].slice(-20))
    const reset = limit.resetsAt === null ? '' : ` · resets in ${duration(limit.resetsAt - reading.readAt) || 'now'}`
    $.ui.toast(`dr-cockpit: ${limitLabel(limit.kind)} limit at ${Math.round(limit.percent)}%${reset}`)
  }
}

async function isPaneUp($: EngineInterface): Promise<boolean> {
  try {
    return (await $.ui.panes()).some(pane => pane.id === PANE && pane.isPlaced)
  } catch {
    return false
  }
}

// Follows the main loop's todo list (TodoWrite) or task list (TaskCreate and
// TaskUpdate), whichever the session uses.
async function trackPlan($: EngineInterface, tool: string, e: object, result: unknown) {
  if (tool === 'TodoWrite') {
    const todos = (e as { todos?: unknown }).todos
    if (Array.isArray(todos)) await update($, plan, () => planFromTodos(todos) as CockpitPlanItem[])
    return
  }
  if (tool === 'TaskCreate') {
    const id = (result as { task?: { id?: unknown } } | undefined)?.task?.id
    const subject = (e as { subject?: unknown }).subject
    if (typeof id !== 'string' || typeof subject !== 'string') return
    const item: CockpitPlanItem = { id, text: subject, status: 'pending' }
    await update($, plan, list => [...list.filter(one => one.id !== id), item].slice(-100))
    return
  }
  if (tool === 'TaskUpdate') {
    const { taskId, subject, status } = e as { taskId?: unknown; subject?: unknown; status?: unknown }
    if (typeof taskId !== 'string') return
    await update($, plan, list =>
      planWithUpdate(list, taskId, {
        subject: typeof subject === 'string' ? subject : undefined,
        status: isPlanStatus(status) ? status : undefined,
      }) as CockpitPlanItem[],
    )
  }
}

function isPlanStatus(value: unknown): value is CockpitPlanItem['status'] | 'deleted' {
  return value === 'pending' || value === 'in_progress' || value === 'completed' || value === 'deleted'
}

// The items around the one in progress, so a long plan shows where it is.
function planWindow(items: readonly CockpitPlanItem[], size: number): CockpitPlanItem[] {
  if (items.length <= size) return [...items]
  const at = items.findIndex(item => item.status !== 'completed')
  const start = Math.max(0, Math.min((at === -1 ? items.length : at) - 2, items.length - size))
  return items.slice(start, start + size)
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

function repoChanges(git: { changed: number; untracked: number }): string {
  if (git.changed + git.untracked === 0) return ' · clean'
  return ` · ${git.changed} changed` + (git.untracked > 0 ? ` · ${git.untracked} untracked` : '')
}

function shortSeat(seat: string): string {
  return seat.replace(/^dr-superpowers:/, '')
}

function costRate(usd: number, startedAt: number | undefined, now: number): string {
  if (startedAt === undefined) return ''
  const hours = (now - startedAt) / 3_600_000
  return hours >= 0.25 ? ` · $${(usd / hours).toFixed(2)}/h` : ''
}

function totalIn(seat: CockpitSeat): number {
  return seat.input + seat.cacheRead + seat.cacheWrite
}

function cacheShare(seat: CockpitSeat): number {
  const total = totalIn(seat)
  return total === 0 ? 0 : Math.round((seat.cacheRead / total) * 100)
}
