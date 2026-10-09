import { atom, read, update } from 'claude-code'
import type { ConfigValue, EngineInterface, Register, RenderChildren, TurnUsage } from 'claude-code'

import type {
  CockpitAccount,
  CockpitBreakdown,
  CockpitBudget,
  CockpitPlanItem,
  CockpitRefusal,
  CockpitSeat,
  CockpitSpawn,
  CockpitUsage,
} from '../types'
import {
  accountKey,
  attributionIn,
  bar,
  billingLabel,
  budgetFor,
  duration,
  fitStatus,
  isGitWriteTool,
  isSuperpowers,
  kTokens,
  levelOf,
  limitLabel,
  modelName,
  planFromTodos,
  planWithUpdate,
  positive,
  rampColor,
  repoFromPorcelain,
  runsWidth,
  SECTIONS,
  sectionsFrom,
  sectionsToggled,
  sparkline,
  stackedRuns,
  stepped,
  termColor,
  track,
  windowElapsed,
  warnShare,
  writesGitText,
} from './lib'
import type { Run, Section, StatusInput, TrackPart } from './lib'

const PANE = 'dr-cockpit'
const PANE_COLUMNS = 56
const INDENT = 2
// The rows the compact layout asks for above the prompt: the framed two
// lines and the buttons.
const COMPACT_ROWS = 5
// The most /context categories the pane lists (breakdownRows caps it lower).
const MAX_BREAKDOWN_ROWS = 12
// Below this the strip drops its frame, as dr-status does.
const FRAME_MIN_COLUMNS = 48
const HANDOFF_PROMPT =
  'Finish the task in flight through its completion line, then hand off with the dr-superpowers handoff skill. Start no new task.'
// How many context readings the trend line keeps.
const TREND_LENGTH = 40
// The colors the context breakdown cycles through, largest category first.
const BREAKDOWN_COLORS = ['cyan', 'magenta', 'yellow', 'green', 'blue', 'red'] as const
// The handoff budget's step and ceiling in the settings view.
const HANDOFF_STEP = 50_000
const MAX_HANDOFF = 2_000_000
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
const trend = atom({ plugin: 'dr-cockpit', key: 'trend' } as const, [])
const view = atom({ plugin: 'dr-cockpit', key: 'view' } as const, 'cockpit')
const account = atom({ plugin: 'dr-cockpit', key: 'account' } as const, null)
const place = atom({ plugin: 'dr-cockpit', key: 'place' } as const, null)
const engine = atom({ plugin: 'dr-cockpit', key: 'engine' } as const, { model: null, effort: null, cache: null })

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
      argumentHint: '[settings]',
    })
    compactWindow = await readCompactWindow($)
    await refresh($, tuning, compactWindow)
    await readAccount($)
    await readPlace($)
    await readEngine($)
    // Unasked, the engine seats the pane from 144 columns and holds it below.
    if (openAtStart) void $.ui.open(paneArgs)

    return next(e)
  })

  on('command.run', { command: 'cockpit' }, async ($, e) => {
    const wantsSettings = e.args.trim().toLowerCase() === 'settings'
    await update($, view, () => (wantsSettings ? 'settings' : 'cockpit'))
    await readAccount($)
    // The settings take the keyboard and as many rows as they need.
    const opened = await $.ui.open(wantsSettings ? { id: PANE, title: 'Cockpit', columns: PANE_COLUMNS, focus: true } : paneArgs)
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

  // The model and effort the main loop's requests go out with, as the status
  // line shows them.
  on('turn.step', async function* ($, e, next) {
    if (e.agentId === undefined) {
      const effort = typeof e.effort === 'string' ? e.effort : null
      const before = await read($, engine)
      if (before.model !== e.model || before.effort !== effort) await update($, engine, now => ({ ...now, model: e.model, effort }))
    }
    return yield* next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined) {
      compactWindow = await readCompactWindow($)
      await refresh($, tuning, compactWindow)
      const turnUsage = e.usage as TurnUsage | undefined
      if (turnUsage !== undefined) {
        const cache = cacheOf(turnUsage)
        await update($, engine, now => ({ ...now, cache }))
      }
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
        <Button key="pane-settings" label="Settings" hotkey="s" onPress={() => update($, view, () => 'settings')} />
      </Box>
    )

    if ((await read($, view)) === 'settings') {
      // Each press writes the setting as /config would; Claude Code then
      // reloads the mod with it, so the rows below always show what is saved.
      const set = (key: keyof Options, value: ConfigValue) => setOption($, key, value)
      const row = (key: string, label: string, ...controls: RenderChildren[]) => (
        <Box key={key} flexDirection="row" flexWrap="wrap">
          <Text>{label.padEnd(16)}</Text>
          {controls}
        </Box>
      )
      const toggle = (key: keyof Options, label: string, isOn: boolean) =>
        row(
          `set-${key}`,
          label,
          <Button key={`set-${key}-toggle`} label={isOn ? 'On' : 'Off'} variant={isOn ? 'primary' : 'secondary'} onPress={() => set(key, !isOn)} />,
        )
      const number = (key: keyof Options, label: string, value: string, onLess: () => unknown, onMore: () => unknown) =>
        row(
          `set-${key}`,
          label,
          <Text key={`set-${key}-value`} bold>
            {value.padEnd(6)}
          </Text>,
          <Button key={`set-${key}-less`} label="-" onPress={onLess} />,
          <Button key={`set-${key}-more`} label="+" onPress={onMore} />,
        )

      return (
        <Box flexDirection="column">
          <Text bold>Settings</Text>
          <Box flexDirection="column" paddingLeft={INDENT}>
            {toggle('openAtStart', 'Show at start', openAtStart)}
            {row(
              'set-layout',
              'Layout',
              ...(['auto', 'full', 'compact'] as const).map(choice => (
                <Button
                  key={`set-layout-${choice}`}
                  label={choice}
                  variant={layout === choice ? 'primary' : 'secondary'}
                  onPress={() => set('layout', choice)}
                />
              )),
            )}
            <Text key="set-sections">Sections</Text>
            {/* Three to a line, under their label, so they fit a docked pane. */}
            <Box key="set-sections-list" flexDirection="column" paddingLeft={INDENT}>
              {[SECTIONS.slice(0, 3), SECTIONS.slice(3, 6), SECTIONS.slice(6)].map((line, index) => (
                <Box key={`set-sections-${index}`} flexDirection="row">
                  {line.map(name => (
                    <Button
                      key={`set-section-${name}`}
                      label={`${shown.includes(name) ? '✓' : '○'} ${name}`}
                      variant={shown.includes(name) ? 'primary' : 'secondary'}
                      onPress={() => set('sections', sectionsToggled(shown, name))}
                    />
                  ))}
                </Box>
              ))}
            </Box>
            {number(
              'handoffTokens',
              'Handoff budget',
              handoffTokens > 0 ? kTokens(handoffTokens) : 'auto',
              () => set('handoffTokens', stepped(handoffTokens, -HANDOFF_STEP, 0, MAX_HANDOFF)),
              () => set('handoffTokens', stepped(handoffTokens, HANDOFF_STEP, 0, MAX_HANDOFF)),
            )}
            {number(
              'warnAt',
              'Band at',
              `${warnPercent}%`,
              () => set('warnAt', stepped(warnPercent, -5, 5, 95)),
              () => set('warnAt', stepped(warnPercent, 5, 5, 95)),
            )}
            {number(
              'limitAlertAt',
              'Limit alert at',
              limitAlertAt > 0 ? `${limitAlertAt}%` : 'off',
              () => set('limitAlertAt', stepped(limitAlertAt, -5, 0, 100)),
              () => set('limitAlertAt', stepped(limitAlertAt, 5, 0, 100)),
            )}
            {number(
              'breakdownRows',
              'Context rows',
              String(breakdownRows),
              () => set('breakdownRows', stepped(breakdownRows, -1, 0, MAX_BREAKDOWN_ROWS)),
              () => set('breakdownRows', stepped(breakdownRows, 1, 0, MAX_BREAKDOWN_ROWS)),
            )}
            {toggle('showHint', 'Hint reading', showHint)}
            {toggle('nudgeModel', 'Handoff note', nudgeModel)}
            {toggle('guardAttribution', 'Attr. guard', guardAttribution)}
          </Box>
          <Text dimColor>Saved to your user settings, like /config.</Text>
          <Box key="settings-actions">
            <Button key="settings-back" label="Back" hotkey="b" onPress={() => update($, view, () => 'cockpit')} />
          </Box>
        </Box>
      )
    }
    const running = all.filter(one => !one.isDone)
    const finished = all.filter(one => one.isDone)
    const doneCount = items.filter(item => item.status === 'completed').length
    const current = items.find(item => item.status === 'in_progress') ?? items.find(item => item.status === 'pending')
    const limits = spend?.limits ?? []
    const cost = head?.usd == null ? null : `$${head.usd.toFixed(2)}`

    const who = await read($, account)
    const tint = termColor(who?.color)

    if (isCompact) {
      // dr-status' two lines, framed in the account's color with its email on
      // the top rule, and the cockpit's buttons under them. Each line shrinks
      // on its own until it fits.
      const where = await read($, place)
      const engineNow = await read($, engine)
      const isFramed = room >= FRAME_MIN_COLUMNS
      const status: StatusInput = {
        cwd: where?.cwd ?? null,
        root: where?.root ?? null,
        home: where?.home ?? null,
        repo: git,
        model: engineNow.model,
        effort: engineNow.effort,
        context: head === null ? null : { tokens: head.tokens, window: head.window },
        cache: engineNow.cache,
        usd: head?.usd ?? null,
        limits,
        now,
      }
      const width = isFramed ? room - 4 : room
      const { lines } = fitStatus(status, width)
      const drawRuns = (key: string, runs: Run[]) =>
        runs.map((run, index) => (
          <Text key={`${key}-${index}`} color={run.color} bold={run.bold} dimColor={run.dim}>
            {run.text}
          </Text>
        ))
      const row = (key: string, runs: Run[]) =>
        isFramed ? (
          <Text key={key} wrap="truncate-end">
            <Text color={tint}>{'│ '}</Text>
            {drawRuns(key, runs)}
            {' '.repeat(Math.max(0, width - runsWidth(runs)))}
            <Text color={tint}>{' │'}</Text>
          </Text>
        ) : (
          <Text key={key} wrap="truncate-end">
            {drawRuns(key, runs)}
          </Text>
        )
      const title = who?.email == null ? '' : [...who.email].slice(0, Math.max(0, room - 6)).join('')

      return (
        <Box flexDirection="column">
          {isFramed && (
            <Text key="frame-top" color={tint} wrap="truncate-end">
              {title === '' ? '╭' + '─'.repeat(room - 2) : '╭─ '}
              {title !== '' && <Text bold>{title}</Text>}
              {title === '' ? '╮' : ` ${'─'.repeat(Math.max(0, room - 5 - [...title].length))}╮`}
            </Text>
          )}
          {/* Without a frame to carry it, the email takes a line of its own. */}
          {!isFramed && who?.email != null && (
            <Text key="status-email" color={tint} bold wrap="truncate-end">
              {who.email}
            </Text>
          )}
          {row('status-1', lines[0])}
          {row('status-2', lines[1])}
          {isFramed && (
            <Text key="frame-bottom" color={tint}>
              {'╰' + '─'.repeat(room - 2) + '╯'}
            </Text>
          )}
          {actions}
        </Box>
      )
    }

    // Each section is a card: a rounded frame in its own color, its title and
    // headline on the first line, its rows below, and a row's details two cells in.
    const inner = Math.max(20, room - 4)
    const wide = Math.max(10, inner - 2 * INDENT)
    const section = (key: string, title: string, color: string, headline: RenderChildren, ...body: RenderChildren[]) => (
      <Box key={key} flexDirection="column" borderStyle="round" borderColor={color} paddingX={1}>
        <Box key={`${key}-head`} flexDirection="row" justifyContent="space-between">
          <Text color={color} bold>
            {title}
          </Text>
          {headline}
        </Box>
        {body}
      </Box>
    )
    const details = (key: string, ...body: RenderChildren[]) => (
      <Box key={key} flexDirection="column" paddingLeft={INDENT}>
        {body}
      </Box>
    )
    // A meter with marks on it, its filled cells in the ramp color.
    const drawTrack = (key: string, percent: number, parts: TrackPart[], marks: Record<string, string>) => (
      <Text key={key}>
        {parts.map((part, index) =>
          part.kind === 'mark' ? (
            <Text key={`${key}-${index}`} color={marks[part.mark ?? ''] ?? 'white'} bold>
              {part.text}
            </Text>
          ) : (
            <Text key={`${key}-${index}`} color={part.kind === 'fill' ? rampColor(percent) : undefined} dimColor={part.kind === 'empty'}>
              {part.text}
            </Text>
          ),
        )}
      </Text>
    )
    const recent = [...running, ...finished.slice(-Math.max(0, 6 - running.length))]
    const shownItems = planWindow(items, 8)
    const sortedSeats = [...list].sort((a, b) => totalIn(b) - totalIn(a))
    const mostIn = Math.max(1, ...sortedSeats.map(totalIn))
    const breakdownShown = (rows?.rows ?? []).slice(0, Math.max(0, Math.min(MAX_BREAKDOWN_ROWS, breakdownRows)))
    const readings = await read($, trend)

    // The context track runs over the whole window: filled to the reading,
    // with the handoff line and the compaction point marked on it.
    const contextBody: RenderChildren[] = []
    if (head !== null) {
      const percent = (head.tokens / head.limit) * 100
      const compactAt = rows?.compactAt ?? null
      contextBody.push(
        drawTrack(
          'ctx-track',
          percent,
          track(head.tokens / head.window, inner, [
            ...(compactAt === null ? [] : [{ at: compactAt / head.window, glyph: '┊', name: 'compact' }]),
            { at: head.limit / head.window, glyph: '┃', name: 'handoff' },
          ]),
          { handoff: rampColor(percent), compact: 'gray' },
        ),
        <Text key="ctx-legend" wrap="truncate-end">
          <Text bold>{kTokens(head.tokens)}</Text>
          <Text dimColor> of {kTokens(head.window)}</Text>
          <Text color={rampColor(percent)}> ┃ handoff {kTokens(head.limit)}</Text>
          {compactAt !== null && <Text dimColor> ┊ compacts {kTokens(compactAt)}</Text>}
        </Text>,
      )
      if (readings.length > 1) {
        const change = (readings[readings.length - 1] ?? 0) - (readings[readings.length - 2] ?? 0)
        contextBody.push(
          <Text key="ctx-trend" wrap="truncate-end">
            <Text dimColor>trend </Text>
            <Text color="cyan">{sparkline(readings.slice(-Math.max(4, inner - 16)))}</Text>
            <Text dimColor>
              {' '}
              {change >= 0 ? '+' : '−'}
              {kTokens(Math.abs(change))}
            </Text>
          </Text>,
        )
      }
      if (breakdownShown.length > 0) {
        const runs = stackedRuns(
          breakdownShown.map(row => row.tokens),
          inner,
        )
        const colorOf = (index: number) => BREAKDOWN_COLORS[index % BREAKDOWN_COLORS.length]
        const used = breakdownShown.reduce((sum, row) => sum + row.tokens, 0)
        contextBody.push(
          <Text key="ctx-stack">
            {breakdownShown.map((row, index) => (
              <Text key={`ctx-stack-${row.name}`} color={colorOf(index)}>
                {'█'.repeat(runs[index] ?? 0)}
              </Text>
            ))}
          </Text>,
          details(
            'ctx-rows',
            breakdownShown.map((row, index) => (
              <Text key={`ctx-row-${row.name}`} wrap="truncate-end">
                <Text color={colorOf(index)}>■ </Text>
                {row.name.padEnd(Math.min(20, Math.max(8, wide - 14)))}
                <Text bold> {kTokens(row.tokens).padStart(5)}</Text>
                <Text dimColor> {String(Math.round((row.tokens / Math.max(1, used)) * 100)).padStart(3)}%</Text>
              </Text>
            )),
          ),
        )
      }
    }

    const engineNow = await read($, engine)
    const billing = billingLabel(who?.billing ?? null)
    const byName: Record<Section, RenderChildren> = {
      // Who the session runs as, framed in the color dr-status gives the account.
      account:
        who !== null &&
        section(
          'account',
          'Account',
          tint ?? 'blue',
          <Text key="account-head" dimColor>
            {billing ?? ''}
          </Text>,
          <Text key="account-email" wrap="truncate-end">
            <Text color={tint} bold>
              ● {who.email ?? 'not signed in'}
            </Text>
          </Text>,
          details(
            'account-rows',
            (who.name !== null || who.organization !== null) && (
              <Text key="account-org" wrap="truncate-end">
                {who.name ?? ''}
                {who.name !== null && who.organization !== null ? <Text dimColor> · </Text> : ''}
                {who.organization ?? ''}
                {who.role !== null && <Text dimColor> ({who.role})</Text>}
              </Text>
            ),
            engineNow.model !== null && (
              <Text key="account-model" wrap="truncate-end">
                <Text color="cyan" bold>
                  {modelName(engineNow.model)}
                </Text>
                {engineNow.effort !== null && <Text dimColor> · {engineNow.effort} effort</Text>}
              </Text>
            ),
            <Text key="account-dir" dimColor wrap="truncate-end">
              config {who.key}
            </Text>,
          ),
        ),
      context: section(
        'context',
        'Context',
        'cyan',
        head === null ? (
          <Text key="ctx-head" dimColor>
            no reading yet
          </Text>
        ) : (
          <Text key="ctx-head" color={rampColor((head.tokens / head.limit) * 100)} bold>
            {Math.round((head.tokens / head.limit) * 100)}% of handoff
          </Text>
        ),
        ...contextBody,
        actions,
      ),
      usage: section(
        'usage',
        'Usage',
        'blue',
        <Text key="usage-head" bold>
          {cost ?? ''}
          <Text dimColor>{head?.usd == null ? '' : costRate(head.usd, spend?.startedAt, now)}</Text>
        </Text>,
        limits.length === 0 && (
          <Text key="limits-none" dimColor>
            No limit reading yet.
          </Text>
        ),
        limits.map(limit => {
          // The pace mark: how far through its window the limit is, so a fill
          // past the mark is spending faster than the window refills.
          const elapsed = windowElapsed(limit.kind, limit.resetsAt, now)
          const width = Math.max(6, inner - 14)
          return (
            <Box key={`limit-${limit.kind}`} flexDirection="column">
              <Text>
                <Text dimColor>{limitLabel(limit.kind).padEnd(4)}</Text>
                {drawTrack(
                  `limit-${limit.kind}-track`,
                  limit.percent,
                  track(limit.percent / 100, width, elapsed === null ? [] : [{ at: elapsed, glyph: '┊', name: 'pace' }]),
                  { pace: 'white' },
                )}
                <Text color={rampColor(limit.percent)} bold>
                  {' '}
                  {String(Math.round(limit.percent)).padStart(3)}%
                </Text>
              </Text>
              {limit.resetsAt !== null && (
                <Text dimColor>
                  {'    '}resets in {duration(limit.resetsAt - now) || 'now'}
                  {elapsed === null ? '' : ` · ${Math.round(elapsed * 100)}% of the window gone`}
                </Text>
              )}
            </Box>
          )
        }),
      ),
      agents: section(
        'agents',
        'Agents',
        'magenta',
        <Text key="agents-head">
          {running.length > 0 && <Text color="cyan">● {running.length} running </Text>}
          {finished.length > 0 && <Text color="green">✓ {finished.length}</Text>}
        </Text>,
        all.length === 0 && (
          <Text key="agents-none" dimColor>
            No subagents yet.
          </Text>
        ),
        recent.map(spawn => (
          <Text key={`spawn-${spawn.agentId}`} wrap="truncate-end">
            <Text color={spawn.isDone ? 'green' : 'cyan'}>{spawn.isDone ? '✓' : '●'} </Text>
            <Text bold={!spawn.isDone} dimColor={spawn.isDone}>
              {shortSeat(spawn.seat)}
            </Text>
            <Text dimColor={spawn.isDone}> {spawn.description}</Text>
            {!spawn.isDone && <Text color="cyan"> {duration(now - spawn.startedAt) || '<1m'}</Text>}
          </Text>
        )),
        sortedSeats.length > 0 && (
          <Text key="seats" dimColor>
            Seats by input
          </Text>
        ),
        sortedSeats.length > 0 &&
          details(
            'seat-rows',
            sortedSeats.map(seat => (
              <Box key={`seat-${seat.seat}`} flexDirection="column">
                <Text wrap="truncate-end">
                  {shortSeat(seat.seat)}
                  <Text dimColor> ×{seat.runs}</Text>
                </Text>
                <Text wrap="truncate-end">
                  <Text color="magenta">{bar(totalIn(seat) / mostIn, Math.max(6, wide - 26)).replace(/▱+$/, rest => ' '.repeat(rest.length))}</Text>
                  <Text bold> {kTokens(totalIn(seat))}</Text>
                  <Text dimColor>
                    {' '}
                    in · {cacheShare(seat)}% cached · {kTokens(seat.output)} out
                  </Text>
                </Text>
              </Box>
            )),
          ),
      ),
      plan:
        items.length > 0 &&
        section(
          'plan',
          'Plan',
          'yellow',
          <Text key="plan-head" bold>
            {doneCount}/{items.length}
          </Text>,
          <Text key="plan-progress" color="yellow">
            {bar(doneCount / items.length, inner)}
          </Text>,
          shownItems.map(item => (
            <Text key={`plan-${item.id}`} wrap="truncate-end">
              <Text color={item.status === 'completed' ? 'green' : item.status === 'in_progress' ? 'yellow' : undefined} dimColor={item.status === 'pending'}>
                {item.status === 'completed' ? '✓' : item.status === 'in_progress' ? '▸' : '○'}{' '}
              </Text>
              <Text dimColor={item.status === 'completed'} bold={item.status === 'in_progress'}>
                {item.text}
              </Text>
            </Text>
          )),
        ),
      repo:
        git !== null &&
        section(
          'repo',
          'Repo',
          'green',
          <Text key="repo-head" color={git.changed + git.untracked === 0 ? 'green' : 'yellow'}>
            {git.changed + git.untracked === 0 ? '● clean' : '● dirty'}
          </Text>,
          <Text key="repo" wrap="truncate-end">
            <Text color="magenta" bold>
              ⎇ {git.branch}
            </Text>
            {git.ahead > 0 && <Text color="green"> ↑{git.ahead}</Text>}
            {git.behind > 0 && <Text color="red"> ↓{git.behind}</Text>}
          </Text>,
          git.changed + git.untracked > 0 && (
            <Text key="repo-changes" wrap="truncate-end">
              {git.changed > 0 && <Text color="yellow">~{git.changed} changed </Text>}
              {git.untracked > 0 && <Text dimColor>?{git.untracked} untracked</Text>}
            </Text>
          ),
        ),
      guard:
        refused.length > 0 &&
        section(
          'guard',
          'Guard',
          'red',
          <Text key="guard-head" color="red" bold>
            {refused.length} refused
          </Text>,
          refused.slice(-3).map(refusal => (
            <Text key={`guard-${refusal.at}`} wrap="truncate-end">
              <Text color="red">✗ </Text>
              {refusal.tool}
              <Text dimColor>: {refusal.line}</Text>
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
    if (before?.tokens !== tokens) await update($, trend, readings => [...readings, tokens].slice(-TREND_LENGTH))
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
/** Writes one of the mod's own settings as /config would, saying why if refused. */
async function setOption($: EngineInterface, key: string, value: ConfigValue) {
  const saved = await $.config.set({ key: `dr-cockpit.${key}`, value })
  if (saved.deny !== undefined) $.ui.toast(`dr-cockpit: ${key} not saved: ${saved.deny}`)
}

async function refreshDetail($: EngineInterface) {
  await readPlace($)
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

/**
 * The account as dr-status reads it: the email and organization from the
 * account's .claude.json (CLAUDE_CONFIG_DIR's, else the home one), and the frame
 * color from dr-status' own config, keyed by the config directory.
 */
async function readAccount($: EngineInterface) {
  try {
    const home = (await $.env.get('HOME')) ?? (await $.env.get('USERPROFILE'))
    if (home === undefined || home === '') return
    const configDir = await $.env.get('CLAUDE_CONFIG_DIR')
    const state = await readJson($, configDir ? `${configDir}/.claude.json` : `${home}/.claude.json`)
    const oauth = (state?.oauthAccount ?? {}) as Record<string, unknown>
    const key = accountKey(configDir || `${home}/.claude`, home)
    const config = await readJson($, (await $.env.get('DCC_STATUSLINE_CONFIG')) || `${home}/.claude/dcc-statusline.json`)
    const accounts = (config?.accounts ?? {}) as Record<string, { color?: unknown }>
    const color = accounts[key]?.color
    const text = (value: unknown) => (typeof value === 'string' && value !== '' ? value : null)
    const next: CockpitAccount = {
      email: text(oauth.emailAddress),
      name: text(oauth.displayName),
      organization: text(oauth.organizationName),
      role: text(oauth.organizationRole),
      billing: text(oauth.billingType),
      key,
      color: typeof color === 'string' || typeof color === 'number' ? String(color) : null,
    }
    await update($, account, () => next)
  } catch {
    // No account to show: the pane leaves it out.
  }
}

async function readJson($: EngineInterface, path: string): Promise<Record<string, unknown> | null> {
  try {
    const value: unknown = JSON.parse(String(await $.fs.read(path)))
    return value !== null && typeof value === 'object' ? (value as Record<string, unknown>) : null
  } catch {
    return null
  }
}

async function readPlace($: EngineInterface) {
  try {
    const cwd = await $.session.cwd()
    const repoAt = await $.session.repo().catch(() => null)
    const home = ((await $.env.get('HOME')) ?? (await $.env.get('USERPROFILE'))) || null
    const before = await read($, place)
    if (before?.cwd !== cwd || before.root !== (repoAt?.root ?? null) || before.home !== home) {
      await update($, place, () => ({ cwd, root: repoAt?.root ?? null, home }))
    }
  } catch {
    // No working directory on this host: the strip starts at the branch.
  }
}

// Until the first request goes out: the session's model and the effort setting.
async function readEngine($: EngineInterface) {
  try {
    const model = await $.session.model()
    const effortLevel = ((await $.settings.read()) as { effortLevel?: unknown }).effortLevel
    const effort = typeof effortLevel === 'string' ? effortLevel : null
    await update($, engine, now => ({ ...now, model: now.model ?? model, effort: now.effort ?? effort }))
  } catch {
    // The first request fills them in.
  }
}

function cacheOf(usage: TurnUsage): number | null {
  const total = usage.input_tokens + usage.cache_read_input_tokens + usage.cache_creation_input_tokens
  return total > 0 ? usage.cache_read_input_tokens / total : null
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
