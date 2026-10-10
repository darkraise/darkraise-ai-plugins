import { atom, read, update } from 'claude-code'
import type { ConfigValue, EngineInterface, Register, RenderChildren, Timer, TurnUsage } from 'claude-code'

import type {
  CockpitAccount,
  CockpitActivity,
  CockpitBreakdown,
  CockpitBudget,
  CockpitFinish,
  CockpitPlanItem,
  CockpitRefusal,
  CockpitRun,
  CockpitSeat,
  CockpitShell,
  CockpitSpawn,
  CockpitUsage,
} from '../types'
import {
  accountKey,
  attributionIn,
  backgroundBadge,
  bar,
  billingLabel,
  budgetFor,
  duration,
  elapsed,
  finishLine,
  fitStatus,
  isAtLeast,
  isFinishArmed,
  isGitWriteTool,
  isSuperpowers,
  kTokens,
  levelOf,
  limitForecast,
  limitLabel,
  modelName,
  nowBadge,
  nowLine,
  parseFinish,
  parseLedger,
  planTasks,
  planFromTodos,
  planWithUpdate,
  positive,
  rampColor,
  remoteRuns,
  repoFromPorcelain,
  roundNumber,
  runsWidth,
  SECTIONS,
  sectionsFrom,
  sectionsToggled,
  sparkline,
  stackedRuns,
  stepped,
  tasksEnded,
  termColor,
  track,
  turnsToBudget,
  windowElapsed,
  warnShare,
  writesGitText,
} from './lib'
import type { Run, Section, StatusInput, TrackPart } from './lib'
import {
  discordBody,
  excerpt,
  isDiscordWebhook,
  maskWebhook,
  mentionId,
  NOTIFY_KINDS,
  notifyKindsFrom,
  notifyKindsToggled,
} from './notify'
import type { NotifyEvent, NotifyKind, NotifyPlace, SendResult } from './notify'

const PANE = 'dr-cockpit'
const PANE_COLUMNS = 56
const INDENT = 2
// A button's rounded frame: the accent on the one that matters, gray at rest.
const BUTTON_MAIN = 'permission'
const BUTTON_REST = 'inactive'
// The rows the compact layout asks for above the prompt: the framed two
// lines, and the buttons in their boxes.
const COMPACT_ROWS = 7
// The first Claude Code that takes styled children in a Button.
const UNDERLINE_SINCE = '2.1.295'
// The most /context categories the pane lists (breakdownRows caps it lower).
const MAX_BREAKDOWN_ROWS = 12
// Below this the strip drops its frame, as dr-status does.
const FRAME_MIN_COLUMNS = 48
const HANDOFF_PROMPT =
  'Finish the task in flight through its completion line, then hand off with the dr-superpowers handoff skill. Start no new task.'
const RESUME_PROMPT = 'Resume the work in .superpowers/handoff/latest.md with the dr-superpowers resume-execution skill.'
// A handoff older than this is not offered for resuming.
const RESUME_WITHIN = 3 * 86_400_000
// The tools that wait on the person by their nature: their dialog is the question.
const ASKING_TOOLS = ['AskUserQuestion', 'ExitPlanMode']
// Permission modes in which an "ask" is settled without the person.
const UNATTENDED_MODES = ['auto', 'bypassPermissions', 'dontAsk']
// How often the state file is rewritten while a turn runs, so dr-status can
// tell a live turn from one whose session went away.
const HEARTBEAT_MS = 30_000
// How many main-turn context readings the forecast keeps.
const TURN_READINGS = 12
const STORE_URL = 'notifyUrl'
const STORE_MENTION = 'notifyMention'
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
const shells = atom({ plugin: 'dr-cockpit', key: 'shells' } as const, [])
const remote = atom({ plugin: 'dr-cockpit', key: 'remote' } as const, { clients: [], setting: null })
const plan = atom({ plugin: 'dr-cockpit', key: 'plan' } as const, [])
const repo = atom({ plugin: 'dr-cockpit', key: 'repo' } as const, null)
const refusals = atom({ plugin: 'dr-cockpit', key: 'refusals' } as const, [])
const isNudged = atom({ plugin: 'dr-cockpit', key: 'isNudged' } as const, false)
const isPlanSession = atom({ plugin: 'dr-cockpit', key: 'isPlanSession' } as const, false)
const alerted = atom({ plugin: 'dr-cockpit', key: 'alerted' } as const, [])
const trend = atom({ plugin: 'dr-cockpit', key: 'trend' } as const, [])
const view = atom({ plugin: 'dr-cockpit', key: 'view' } as const, 'cockpit')
const account = atom({ plugin: 'dr-cockpit', key: 'account' } as const, null)
const place = atom({ plugin: 'dr-cockpit', key: 'place' } as const, null)
const engine = atom({ plugin: 'dr-cockpit', key: 'engine' } as const, { model: null, effort: null, cache: null })
const IDLE: CockpitActivity = { kind: 'idle', since: 0, turnStartedAt: null, step: 0, tool: null, agent: null, detail: null, lastTurnMs: null, endedAt: null, isSent: false }
const activity = atom({ plugin: 'dr-cockpit', key: 'activity' } as const, IDLE)
const turnTokens = atom({ plugin: 'dr-cockpit', key: 'turnTokens' } as const, [])
const run = atom({ plugin: 'dr-cockpit', key: 'run' } as const, null)
const finish = atom({ plugin: 'dr-cockpit', key: 'finish' } as const, null)
const handoffAt = atom({ plugin: 'dr-cockpit', key: 'handoffAt' } as const, null)
const notifier = atom({ plugin: 'dr-cockpit', key: 'notifier' } as const, {
  url: null,
  isFromEnv: false,
  mention: null,
  editing: null,
  error: null,
  last: null,
})

type Options = {
  handoffTokens: number
  nudgeModel: boolean
  guardAttribution: boolean
  warnAt: number
  layout: string
  sections: string
  breakdownRows: number
  openAtStart: boolean
  limitAlertAt: number
  notifyOn: string
  notifyAfter: number
  notifyAskAfter: number
  notifyDetail: string
}

/** What the budget reading is judged by. */
type Tuning = { handoffTokens: number; nudgeModel: boolean; warnAt: number }

export const register: Register = (on, options) => {
  const {
    handoffTokens = 0,
    nudgeModel = true,
    guardAttribution = true,
    warnAt: warnPercent = 80,
    layout: layoutSetting = 'auto',
    sections: sectionList = '',
    breakdownRows = 6,
    openAtStart = true,
    limitAlertAt = 90,
    notifyOn = '',
    notifyAfter = 60,
    notifyAskAfter = 20,
    notifyDetail = 'full',
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
  S.kinds = notifyOn === 'none' ? [] : notifyKindsFrom(notifyOn)
  S.isBrief = notifyDetail === 'brief'
  S.notifyAskAfter = notifyAskAfter

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'cockpit',
      description: 'Show context, usage, subagents, the plan and the repo in a pane',
      argumentHint: '[settings]',
    })
    compactWindow = await readCompactWindow($)
    await onBudget($, await refresh($, tuning, compactWindow))
    await readAccount($)
    await readPlace($)
    await readEngine($)
    await readWhere($)
    await readNotifier($)
    await readRun($)
    await readVersion($)
    await readRemote($)
    // Unasked, the engine seats the pane from 144 columns and holds it below.
    if (openAtStart) void $.ui.open(paneArgs)

    return next(e)
  })

  on('command.run', { command: 'cockpit' }, async ($, e) => {
    const words = e.args.trim().split(/\s+/)
    if (words[0]?.toLowerCase() === 'notify') return notifyCommand($, words.slice(1))
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
    if (limitAlertAt > 0) {
      for (const limit of await alertLimits($, reading, limitAlertAt)) {
        await notify($, {
          kind: 'limit',
          title: `📊 ${limitLabel(limit.kind)} limit at ${Math.round(limit.percent)}%`,
          detail: limit.resetsAt === null ? undefined : `Resets in ${duration(limit.resetsAt - now) || 'under a minute'}.`,
          isPlain: true,
        })
      }
    }
    if (await isPaneUp($)) await refreshDetail($)

    return done
  })

  on('session.end', async ($, e, next) => {
    if (e.reason !== 'clear') {
      const head = await read($, budget)
      const started = (await read($, usage))?.startedAt
      const stamp = await $.clock.now()
      await notify($, {
        kind: 'session',
        title: '🏁 Session ended',
        detail: `claude --resume ${e.sessionId}`,
        isPlain: true,
        fields: [
          ...(started === undefined ? [] : [{ name: 'Took', value: elapsed(stamp - started) }]),
          ...(head?.usd == null ? [] : [{ name: 'Cost', value: `$${head.usd.toFixed(2)}` }]),
        ],
      })
    }
    S.ticker?.cancel()
    S.ticker = null
    await setActivity($, () => IDLE)
    await writeState($)
    return next(e)
  }).catch(($, e, next) => next(e))

  // A compaction leaves no reading until the next response: drop the stale
  // one and re-arm the note, so it does not stay latched.
  on('session.compact', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined && e.trigger !== 'precompute' && 'messages' in done && done.messages !== undefined) {
      await update($, budget, () => null)
      await update($, isNudged, () => false)
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
    await syncTicker($)

    return started
  })

  // Remote Control clients joining and leaving; the terminal raises neither.
  on('session.attach', async ($, e, next) => {
    const joined = await next(e)
    await update($, remote, now => ({ ...now, clients: [...now.clients.filter(one => one.id !== e.clientId), { id: e.clientId, surface: e.surface }] }))
    return joined
  }).catch(($, e, next) => next(e))

  on('session.detach', async ($, e, next) => {
    const left = await next(e)
    await update($, remote, now => ({ ...now, clients: now.clients.filter(one => one.id !== e.clientId) }))
    return left
  }).catch(($, e, next) => next(e))

  // A background shell's end arrives as its task notification.
  on('prompt.submit', async ($, e, next) => {
    if (e.origin.kind === 'task-notification') {
      const ended = new Set(tasksEnded(e.text).map(one => one.id))
      if (ended.size > 0) {
        await update($, shells, list => list.filter(one => !ended.has(one.id)))
        await syncTicker($)
      }
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  // A main turn begins: the Now row starts its clock.
  on('turn.start', async ($, e, next) => {
    const stamp = await $.clock.now()
    for (const id of [...S.waits.keys()]) await settleWait($, id, '⏹ Turn ended')
    await setActivity($, now => ({
      ...IDLE,
      kind: 'running',
      since: stamp,
      turnStartedAt: stamp,
      lastTurnMs: now.lastTurnMs,
    }))
    return next(e)
  })

  // Watches the permission decision, never changes it: an "ask" on a call
  // means the person is about to be asked, unless the mode settles it alone.
  on('tool.check', async ($, e, next) => {
    const decided = await next(e)
    const id = e.tool_use_id
    if (decided.decision !== 'ask' || id === undefined || S.isUnattended || ASKING_TOOLS.includes(e.tool) || S.waits.has(id)) return decided
    const seat = e.agentId === undefined ? null : ((await read($, spawns)).find(one => one.agentId === e.agentId)?.seat ?? null)
    await startWait($, id, 'waiting', {
      kind: 'ask',
      title: '⏳ Waiting for approval',
      detail: `${e.tool}${callSummary(e.tool, e.input) === '' ? '' : `: ${excerpt(callSummary(e.tool, e.input), 200)}`}`,
      fields: [...(seat === null ? [] : [{ name: 'Agent', value: shortSeat(seat) }]), ...(await turnFields($)).slice(0, 1)],
    })
    return decided
  }).catch(($, e, next) => next(e))

  // The background pill under a Bash call is drawn only once the call runs,
  // so an approval waiting on it was given.
  on('ui.render', { component: 'ToolProgress' }, async ($, e, next) => {
    if (S.waits.has(e.props.tool_use_id)) await endWait($, e.props.tool_use_id, '✓ Approved')
    return next(e)
  })

  // The model and effort the main loop's requests go out with, as the status
  // line shows them.
  on('turn.step', async function* ($, e, next) {
    if (e.agentId === undefined) {
      const effort = typeof e.effort === 'string' ? e.effort : null
      const before = await read($, engine)
      if (before.model !== e.model || before.effort !== effort) await update($, engine, now => ({ ...now, model: e.model, effort }))
      const step = e.index + 1
      await update($, activity, now => (now.kind === 'idle' || now.kind === 'failed' || now.step === step ? now : { ...now, step }))
    }
    return yield* next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined) {
      compactWindow = await readCompactWindow($)
      await onBudget($, await refresh($, tuning, compactWindow))
      const turnUsage = e.usage as TurnUsage | undefined
      if (turnUsage !== undefined) {
        const cache = cacheOf(turnUsage)
        await update($, engine, now => ({ ...now, cache }))
      }
      const head = await read($, budget)
      if (head !== null) await update($, turnTokens, list => [...list, head.tokens].slice(-TURN_READINGS))
      for (const id of [...S.waits.keys()]) await settleWait($, id, '⏹ Turn ended')
      const stamp = await $.clock.now()
      const failed = e.reason === 'error' || e.reason === 'refusal'
      const why = failed ? failureOf(e) : null
      await readRemote($)
      await setActivity($, now => ({
        ...IDLE,
        kind: failed ? 'failed' : e.reason === 'aborted' ? 'interrupted' : 'idle',
        since: now.since,
        lastTurnMs: e.durationMs,
        endedAt: stamp,
        detail: why,
      }))
      await readRun($)
      if (failed) {
        const messageId = await notify($, {
          kind: 'error',
          title: `❌ Turn failed${why === null ? '' : `: ${why}`}`,
          detail: `After ${duration(e.durationMs) || '<1m'}. Send a prompt to continue.`,
          isPlain: true,
          fields: await turnFields($),
        })
        if (messageId !== null) await update($, activity, now => ({ ...now, isSent: true }))
      } else if (e.reason === 'answer' && e.durationMs >= Math.max(0, notifyAfter) * 1000) {
        const messageId = await notify($, {
          kind: 'done',
          title: `✅ Done in ${elapsed(e.durationMs)}`,
          detail: e.answer.trim() === '' ? undefined : excerpt(e.answer, 300),
          fields: await turnFields($),
        })
        if (messageId !== null) await update($, activity, now => ({ ...now, isSent: true }))
      }
      return done
    }
    const agentId = e.agentId
    const list = await read($, spawns)
    const spawn = list.find(one => one.agentId === agentId)
    if (spawn === undefined) return done
    await update($, spawns, all => all.map(one => (one.agentId === agentId ? { ...one, isDone: true } : one)))
    await syncTicker($)
    if (e.usage !== undefined) await update($, seats, all => addRun(all, spawn.seat, e.usage as TurnUsage))
    await notify($, {
      kind: 'agent',
      title: `🤖 ${shortSeat(spawn.seat)} finished`,
      detail: spawn.description,
      isPlain: true,
      fields: [{ name: 'Took', value: elapsed(e.durationMs) }],
    })

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
    const id = e.tool_use_id
    const seat = e.agentId === undefined ? null : ((await read($, spawns)).find(one => one.agentId === e.agentId)?.seat ?? null)
    if ((await read($, activity)).kind === 'running') await setActivity($, now => ({ ...now, tool, agent: seat === null ? null : shortSeat(seat) }))
    if (id !== undefined && e.agentId === undefined && ASKING_TOOLS.includes(tool)) {
      await startWait($, id, 'asking', {
        kind: 'question',
        title: tool === 'ExitPlanMode' ? '📋 Plan ready for review' : '❓ Claude is asking',
        detail: questionOf(e) || undefined,
        fields: (await turnFields($)).slice(0, 1),
      })
    }
    let ran: Awaited<ReturnType<typeof next>>
    try {
      ran = await next(e)
    } catch (error) {
      if (id !== undefined && S.waits.has(id)) await endWait($, id, '⏹ Interrupted')
      throw error
    }
    if (id !== undefined && S.waits.has(id)) {
      await endWait($, id, ran.deny !== undefined ? '✗ Denied' : ASKING_TOOLS.includes(tool) ? '✓ Answered' : '✓ Approved')
    }
    if ((await read($, activity)).tool === tool) await setActivity($, now => (now.kind === 'running' ? { ...now, tool: null, agent: null } : now))
    if (tool === 'Skill' && isSuperpowers(String((e as { skill?: unknown }).skill ?? ''))) {
      await update($, isPlanSession, () => true)
    }
    if (ran.deny === undefined && !ran.isError) await trackShells($, tool, e, ran.result)
    if (e.agentId === undefined) {
      if (ran.deny === undefined && !ran.isError) await trackPlan($, tool, e, ran.result)
      await onBudget($, await refresh($, tuning, compactWindow))
      // The controller writes its ledger with its own tool calls.
      if (/\.superpowers|finish-choice/.test(JSON.stringify(e))) await readRun($)
    }

    return ran
  }).catch(($, e, next) =>
    next.called || !guardAttribution ? next(e) : { deny: 'dr-cockpit: its attribution guard failed.' },
  )

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const now = await $.clock.now()
    const room = e.props.bodyColumns
    const isCompact = layout === 'compact' || (layout === 'auto' && e.props.placement === 'inline')
    const head = await read($, budget)
    const spend = await read($, usage)
    const rows = await read($, breakdown)
    const list = await read($, seats)
    const all = await read($, spawns)
    const background = await read($, shells)
    const remoteNow = await read($, remote)
    const items = await read($, plan)
    const git = await read($, repo)
    const refused = await read($, refusals)
    const canHandOff = await read($, isPlanSession)
    const act = await read($, activity)
    const summary = await read($, run)
    const finishNow = await read($, finish)
    const handoffTime = await read($, handoffAt)
    const canResume = !canHandOff && handoffTime !== null && now - handoffTime < RESUME_WITHIN
    const drawRuns = (key: string, runs: Run[]) =>
      runs.map((one, index) => (
        <Text key={`${key}-${index}`} color={one.color} bold={one.bold} dimColor={one.dim}>
          {one.text}
        </Text>
      ))

    // Every control is a button in a rounded box: gray at rest, the accent on
    // the one that matters (`isMain`), dim when it reads as off.
    if (S.canUnderline === null) await readVersion($)
    const button = (key: string, label: string, onPress: () => unknown, look: { hotkey?: string; isMain?: boolean; isOff?: boolean } = {}) => {
      // The hotkey's letter is underlined in the label, as a desktop app marks
      // one; a hidden twin holds the hotkey, since a Button with one draws "c: "
      // before its label. Older Claude Code draws that prefix instead.
      if (!S.canUnderline) {
        return (
          <Box key={`${key}-box`} borderStyle="round" borderColor={look.isMain ? BUTTON_MAIN : BUTTON_REST} paddingX={1}>
            <Button key={key} label={label} hotkey={look.hotkey} plain dimColor={look.isOff} hover={{ bold: true }} onPress={onPress} />
          </Box>
        )
      }
      const at = look.hotkey === undefined ? -1 : label.toLowerCase().indexOf(look.hotkey)
      return (
        <Box key={`${key}-box`} borderStyle="round" borderColor={look.isMain ? BUTTON_MAIN : BUTTON_REST} paddingX={1}>
          {at < 0 ? (
            <Button key={key} label={label} plain dimColor={look.isOff} hover={{ bold: true }} onPress={onPress} />
          ) : (
            <Button key={key} label={label} plain dimColor={look.isOff} hover={{ bold: true }} onPress={onPress}>
              {label.slice(0, at)}
              <Text underline>{label.slice(at, at + 1)}</Text>
              {label.slice(at + 1)}
            </Button>
          )}
          {at >= 0 && (
            <Box key={`${key}-hotkey-box`} display="none">
              <Button key={`${key}-hotkey`} label={label} hotkey={look.hotkey} plain onPress={onPress} />
            </Box>
          )}
        </Box>
      )
    }
    const isNearHandoff = head !== null && levelOf(head.tokens, head.limit, tuning.warnAt) !== 'quiet'
    const actions = (
      <Box key="actions" flexDirection="row" flexWrap="wrap" columnGap={1}>
        {canHandOff && button('pane-handoff', 'Hand off', () => $.prompt.submit({ text: HANDOFF_PROMPT, asUser: true }), { hotkey: 'h', isMain: isNearHandoff })}
        {canResume && button('pane-resume', 'Resume', () => $.prompt.submit({ text: RESUME_PROMPT, asUser: true }), { hotkey: 'r', isMain: true })}
        {button('pane-compact', 'Compact', () => $.session.compact(), { hotkey: 'c' })}
        {button('pane-settings', 'Settings', () => update($, view, () => 'settings'), { hotkey: 's' })}
      </Box>
    )

    if ((await read($, view)) === 'settings') {
      // Each press writes the setting as /config would; Claude Code then
      // reloads the mod with it, so the rows below always show what is saved.
      const set = (key: keyof Options, value: ConfigValue) => setOption($, key, value)
      const row = (key: string, label: string, ...controls: RenderChildren[]) => (
        <Box key={key} flexDirection="row" flexWrap="wrap" alignItems="center" columnGap={1}>
          <Text>{label.padEnd(15)}</Text>
          {controls}
        </Box>
      )
      const toggle = (key: keyof Options, label: string, isOn: boolean) =>
        row(`set-${key}`, label, button(`set-${key}-toggle`, isOn ? '● On' : '○ Off', () => set(key, !isOn), { isMain: isOn, isOff: !isOn }))
      const choices = <T extends string>(key: keyof Options, label: string, all: readonly T[], chosen: T) =>
        row(`set-${key}`, label, ...all.map(choice => button(`set-${key}-${choice}`, choice, () => set(key, choice), { isMain: chosen === choice, isOff: chosen !== choice })))
      const chips = (key: string, names: readonly string[], isOn: (name: string) => boolean, label: (name: string) => string, onPress: (name: string) => unknown) => (
        <Box key={key} flexDirection="row" flexWrap="wrap" columnGap={1} paddingLeft={INDENT}>
          {names.map(name => button(`${key}-${name}`, `${isOn(name) ? '✓' : '○'} ${label(name)}`, () => onPress(name), { isOff: !isOn(name) }))}
        </Box>
      )
      const number = (key: keyof Options, label: string, value: string, onLess: () => unknown, onMore: () => unknown) =>
        row(
          `set-${key}`,
          label,
          <Text key={`set-${key}-value`} bold>
            {value.padEnd(6)}
          </Text>,
          button(`set-${key}-less`, '−', onLess),
          button(`set-${key}-more`, '+', onMore),
        )

      // A surface without text fields (the mobile app) sets the webhook from a terminal.
      const elements = $.ui.resolve(e)
      const Input = 'Input' in elements ? elements.Input : undefined
      const canType = Input !== undefined
      const notes = await read($, notifier)
      const field = (key: 'url' | 'mention', placeholder: string, onSave: (value: string) => Promise<string | null>) =>
        Input !== undefined && (
          <Box key={`set-notify-${key}-field`} flexDirection="column" flexGrow={1}>
            <Input
              key={`set-notify-${key}-input`}
              placeholder={placeholder}
              submitLabel="save"
              autoFocus
              onSubmit={async (value: string) => {
                const problem = await onSave(value)
                await update($, notifier, now => ({ ...now, editing: problem === null ? null : key, error: problem }))
              }}
            />
            {notes.error !== null && <Text color="red">✗ {notes.error}</Text>}
            <Box key={`set-notify-${key}-cancel`}>
              {button(`set-notify-${key}-cancel-button`, 'Cancel', () => update($, notifier, now => ({ ...now, editing: null, error: null })))}
            </Box>
          </Box>
        )
      const edit = (key: 'url' | 'mention') => update($, notifier, now => ({ ...now, editing: key, error: null }))
      const notifyRows = (
        <Box key="set-notify" flexDirection="column">
          <Text bold>
            Notifications <Text dimColor>(Discord)</Text>
          </Text>
          <Box key="set-notify-rows" flexDirection="column" paddingLeft={INDENT}>
            {notes.editing === 'url' && canType
              ? row('set-notify-url', 'Webhook', field('url', 'https://discord.com/api/webhooks/…', value => saveWebhook($, value)))
              : row(
                  'set-notify-url',
                  'Webhook',
                  notes.url === null ? <Text key="set-notify-url-none" dimColor>not set </Text> : <Text key="set-notify-url-set"><Text color="green">✓ </Text>{maskWebhook(notes.url)} </Text>,
                  notes.isFromEnv && <Text key="set-notify-url-env" dimColor>from DR_COCKPIT_NOTIFY_URL</Text>,
                  notes.url !== null && button('set-notify-test', 'Send test', () => sendTest($), { isMain: true }),
                  !notes.isFromEnv && canType && button('set-notify-url-edit', notes.url === null ? 'Set' : 'Change', () => edit('url'), { isMain: notes.url === null }),
                  !notes.isFromEnv && notes.url !== null && button('set-notify-url-remove', 'Remove', () => saveWebhook($, '')),
                  !canType && notes.url === null && <Text key="set-notify-url-cli" dimColor>set it from a terminal: /cockpit notify url</Text>,
                )}
            {notes.last !== null && (
              <Text key="set-notify-last" color={notes.last.isError ? 'red' : 'green'} wrap="truncate-end">
                {' '.repeat(16)}
                {notes.last.isError ? '✗ ' : '✓ '}
                {notes.last.text}
              </Text>
            )}
            {notes.editing === 'mention' && canType
              ? row('set-notify-mention', 'Mention', field('mention', 'your Discord user id', value => saveMention($, value)))
              : row(
                  'set-notify-mention',
                  'Mention',
                  <Text key="set-notify-mention-value" dimColor={notes.mention === null}>
                    {notes.mention === null ? 'nobody ' : `${notes.mention.slice(0, 10)}… `}
                  </Text>,
                  canType && button('set-notify-mention-edit', notes.mention === null ? 'Set' : 'Change', () => edit('mention')),
                )}
            <Text key="set-notify-on">Send on</Text>
            {chips(
              'set-notify-kind',
              NOTIFY_KINDS,
              kind => S.kinds.includes(kind as NotifyKind),
              kind => kindLabel(kind as NotifyKind),
              kind => set('notifyOn', notifyKindsToggled(S.kinds, kind as NotifyKind)),
            )}
            {number(
              'notifyAfter',
              'Done after',
              notifyAfter > 0 ? `${notifyAfter}s` : 'any',
              () => set('notifyAfter', stepped(notifyAfter, notifyAfter > 60 ? -60 : -15, 0, 3600)),
              () => set('notifyAfter', stepped(notifyAfter, notifyAfter >= 60 ? 60 : 15, 0, 3600)),
            )}
            {number(
              'notifyAskAfter',
              'Ask after',
              `${notifyAskAfter}s`,
              () => set('notifyAskAfter', stepped(notifyAskAfter, -10, 0, 600)),
              () => set('notifyAskAfter', stepped(notifyAskAfter, 10, 0, 600)),
            )}
            {choices('notifyDetail', 'Detail', ['full', 'brief'] as const, S.isBrief ? 'brief' : 'full')}
          </Box>
        </Box>
      )

      return (
        <Box flexDirection="column">
          <Text bold>Settings</Text>
          <Box flexDirection="column" paddingLeft={INDENT}>
            {toggle('openAtStart', 'Show at start', openAtStart)}
            {choices('layout', 'Layout', ['auto', 'full', 'compact'] as const, layout)}
            <Text key="set-sections">Sections</Text>
            {/* Under their label, wrapping to the pane's width. */}
            {chips(
              'set-section',
              SECTIONS,
              name => shown.includes(name as Section),
              name => name,
              name => set('sections', sectionsToggled(shown, name as Section)),
            )}
            {number(
              'handoffTokens',
              'Handoff budget',
              handoffTokens > 0 ? kTokens(handoffTokens) : 'auto',
              () => set('handoffTokens', stepped(handoffTokens, -HANDOFF_STEP, 0, MAX_HANDOFF)),
              () => set('handoffTokens', stepped(handoffTokens, HANDOFF_STEP, 0, MAX_HANDOFF)),
            )}
            {number(
              'warnAt',
              'Warn at',
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
            {toggle('nudgeModel', 'Handoff note', nudgeModel)}
            {toggle('guardAttribution', 'Attr. guard', guardAttribution)}
          </Box>
          {notifyRows}
          <Text dimColor>Saved to your user settings, like /config.</Text>
          <Box key="settings-actions">
            {button('settings-back', 'Back', () => update($, view, () => 'cockpit'), { hotkey: 'b' })}
          </Box>
        </Box>
      )
    }
    const running = all.filter(one => !one.isDone)
    // After Esc, what kept going: background shells and agents survive it.
    const kept = [
      background.length > 0 ? `${background.length} ${background.length === 1 ? 'shell' : 'shells'}` : '',
      running.length > 0 ? `${running.length} ${running.length === 1 ? 'agent' : 'agents'}` : '',
    ].filter(Boolean)
    const actNow = act.kind === 'interrupted' ? { ...act, detail: kept.length === 0 ? 'nothing left running' : `${kept.join(' and ')} still running` } : act
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
        handoff: head === null ? null : { tokens: head.tokens, limit: head.limit, warnAt: tuning.warnAt },
        run: summary === null || summary.total === 0 ? null : { done: summary.done, total: summary.total, round: roundNumber(runRound(summary)) },
      }
      const width = isFramed ? room - 4 : room
      const { lines } = fitStatus(status, width)
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
      // The turn's activity rides on the top rule, so the strip keeps its height.
      const left = title === '' ? 2 : 4 + [...title].length
      const fullBadge = nowBadge(actNow, now)
      const lowBadge = backgroundBadge(background.length, remoteNow.clients)
      const lowFits = lowBadge.length > 0 && room - runsWidth(lowBadge) - 6 >= 2
      const badge = room - left - runsWidth(fullBadge) - 4 >= 2 ? fullBadge : []
      const dashes = Math.max(0, room - left - (badge.length > 0 ? runsWidth(badge) + 4 : 1))

      return (
        <Box flexDirection="column">
          {isFramed && (
            <Text key="frame-top" color={tint} wrap="truncate-end">
              {title === '' ? '╭─' : '╭─ '}
              {title !== '' && <Text bold>{title}</Text>}
              {title === '' ? '' : ' '}
              {'─'.repeat(dashes)}
              {badge.length > 0 && ' '}
              {badge.length > 0 && drawRuns('frame-badge', badge)}
              {badge.length > 0 ? ' ─╮' : '╮'}
            </Text>
          )}
          {/* Without a frame to carry it, the email takes a line of its own. */}
          {!isFramed && who?.email != null && (
            <Text key="status-email" color={tint} bold wrap="truncate-end">
              {who.email}
            </Text>
          )}
          {!isFramed && fullBadge.length > 0 && (
            <Text key="status-now" wrap="truncate-end">
              {drawRuns('status-now', fullBadge)}
            </Text>
          )}
          {row('status-1', lines[0])}
          {row('status-2', lines[1])}
          {isFramed && (
            <Text key="frame-bottom" color={tint} wrap="truncate-end">
              {lowFits ? '╰─ ' : '╰' + '─'.repeat(room - 2) + '╯'}
              {lowFits && drawRuns('frame-low', lowBadge)}
              {lowFits && ' ' + '─'.repeat(Math.max(0, room - runsWidth(lowBadge) - 5)) + '╯'}
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
    const turnsLeft = head === null ? null : turnsToBudget(await read($, turnTokens), head.limit)
    const runCard = () => {
      if (summary === null) return null
      const blocked = summary.tasks.filter(task => task.state === 'blocked')
      const round = runRound(summary)
      const color = blocked.length > 0 ? 'red' : 'yellow'
      return section(
        'plan',
        'Run',
        color,
        <Text key="plan-head">
          {blocked.length > 0 ? (
            <Text color="red" bold>
              {blocked.length} blocked
            </Text>
          ) : (
            round !== null && <Text dimColor>round {round}</Text>
          )}
          {(blocked.length > 0 || round !== null) && <Text dimColor> · </Text>}
          <Text bold>
            {summary.done}/{summary.total}
          </Text>
        </Text>,
        <Text key="plan-progress" color={color}>
          {bar(summary.done / summary.total, inner)}
        </Text>,
        summary.plan !== null && (
          <Text key="plan-path" dimColor wrap="truncate-end">
            plan {summary.plan}
          </Text>
        ),
        finishNow !== null && finishLine(finishNow, now).length > 0 && (
          <Text key="plan-finish" wrap="truncate-end">
            {drawRuns('plan-finish-runs', finishLine(finishNow, now))}
          </Text>
        ),
        runWindow(summary.tasks, 6).map(task => {
          const label = `Task ${task.n}${task.title === '' ? '' : `: ${task.title}`}`
          if (task.state === 'complete') {
            return (
              <Text key={`plan-${task.n}`} wrap="truncate-end">
                <Text color="green">✓ </Text>
                <Text dimColor>
                  {label}
                  {task.isClean ? ' · clean' : ''}
                </Text>
              </Text>
            )
          }
          if (task.state === 'blocked') {
            return (
              <Box key={`plan-${task.n}`} flexDirection="column">
                <Text color="red" bold wrap="truncate-end">
                  ✗ {label}
                </Text>
                <Box paddingLeft={INDENT}>
                  <Text color="red">BLOCKED{task.reason === null ? '' : ` · ${task.reason}`}</Text>
                </Box>
              </Box>
            )
          }
          if (task.state === 'assigned') {
            return (
              <Box key={`plan-${task.n}`} flexDirection="column">
                <Text wrap="truncate-end">
                  <Text color="yellow">▸ </Text>
                  <Text bold>{label}</Text>
                </Text>
                {(task.round !== null || task.seat !== null) && (
                  <Text dimColor wrap="truncate-end">
                    {'  '}
                    {[task.round === null ? 'implementing' : `round ${task.round}`, task.seat === null ? null : shortSeat(task.seat)].filter(Boolean).join(' · ')}
                  </Text>
                )}
              </Box>
            )
          }
          return (
            <Text key={`plan-${task.n}`} wrap="truncate-end">
              <Text dimColor>○ </Text>
              {label}
            </Text>
          )
        }),
        summary.isFinished && (
          <Text key="plan-finished" color="green">
            Final review clean.
          </Text>
        ),
      )
    }
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
            <Text key="account-remote" wrap="truncate-end">
              <Text dimColor>Remote </Text>
              {drawRuns('account-remote', remoteRuns(remoteNow.clients, remoteNow.setting))}
            </Text>,
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
          <Text key="ctx-head">
            <Text color={rampColor((head.tokens / head.limit) * 100)} bold>
              {Math.round((head.tokens / head.limit) * 100)}% of handoff
            </Text>
            {turnsLeft !== null && (
              <Text color={turnsLeft <= 3 ? '#ffaf5f' : undefined} bold={turnsLeft <= 3} dimColor={turnsLeft > 3}>
                {' '}
                · ≈{turnsLeft} {turnsLeft === 1 ? 'turn' : 'turns'}
              </Text>
            )}
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
          const gone = windowElapsed(limit.kind, limit.resetsAt, now)
          const forecast = limitForecast(limit.kind, limit.percent, limit.resetsAt, now)
          const width = Math.max(6, inner - 14)
          return (
            <Box key={`limit-${limit.kind}`} flexDirection="column">
              <Text>
                <Text dimColor>{limitLabel(limit.kind).padEnd(4)}</Text>
                {drawTrack(
                  `limit-${limit.kind}-track`,
                  limit.percent,
                  track(limit.percent / 100, width, gone === null ? [] : [{ at: gone, glyph: '┊', name: 'pace' }]),
                  { pace: 'white' },
                )}
                <Text color={rampColor(limit.percent)} bold>
                  {' '}
                  {String(Math.round(limit.percent)).padStart(3)}%
                </Text>
              </Text>
              {limit.resetsAt !== null && (
                <Text wrap="truncate-end">
                  <Text dimColor>
                    {'    '}resets in {duration(limit.resetsAt - now) || 'now'}
                    {forecast === null && gone !== null ? ` · ${Math.round(gone * 100)}% of the window gone` : ''}
                    {forecast === 'pace' ? ' · on pace' : ''}
                  </Text>
                  {typeof forecast === 'number' && (
                    <Text color="#ffaf5f" bold>
                      {' '}
                      · runs out in {duration(forecast) || '<1m'}, before reset
                    </Text>
                  )}
                </Text>
              )}
            </Box>
          )
        }),
      ),
      // The background shells still running, each with its command and age;
      // the card is left out while there are none.
      shells:
        background.length > 0 &&
        section(
          'shells',
          'Shells',
          'yellow',
          <Text key="shells-head" color="yellow">
            $ {background.length} running
          </Text>,
          background.map(shell => (
            <Text key={`shell-${shell.id}`} wrap="truncate-end">
              <Text color="yellow" bold>
                ${' '}
              </Text>
              <Text>{clip(shell.command.split('\n')[0], Math.max(10, inner - 10))}</Text>
              <Text color="yellow"> {elapsed(now - shell.startedAt)}</Text>
            </Text>
          )),
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
            {!spawn.isDone && <Text color="cyan"> {elapsed(now - spawn.startedAt)}</Text>}
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
      // In a dr-superpowers run the card reads the run's ledger instead: the
      // round in flight, reviews that came back clean, and blocked tasks.
      plan:
        summary !== null && summary.total > 0 ? (
          runCard()
        ) : items.length > 0 &&
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
          finishNow !== null && finishLine(finishNow, now).length > 0 && (
            <Text key="plan-finish" wrap="truncate-end">
              {drawRuns('plan-finish-runs', finishLine(finishNow, now))}
            </Text>
          ),
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
        <Text key="now" wrap="truncate-end">
          {drawRuns('now', nowLine(actNow, now))}
        </Text>
        {shown.map(name => byName[name])}
        {!shown.includes('context') && actions}
      </Box>
    )
  })
}

// What the hooks share beyond $.state: settings read at load, facts read at
// the start, and the timers and S.waits in flight. A reload starts it over.
const S = {
  kinds: [] as NotifyKind[],
  isBrief: false,
  notifyAskAfter: 20,
  where: { host: null, tmux: null, primary: null, sessionId: null, configDir: null } as {
    host: string | null
    tmux: string | null
    primary: string | null
    sessionId: string | null
    configDir: string | null
  },
  // An approval or question the person has not answered yet: its timer, and
  // the Discord message sent for it, edited once it is answered.
  waits: new Map<string, { timer: Timer | null; messageId: string | null; event: NotifyEvent }>(),
  ticker: null as Timer | null,
  ticks: 0,
  isTurnLive: false,
  isBudgetSent: false,
  // Ledger events already seen, so a reload or a re-read sends nothing twice.
  ledgerSeen: null as Set<string> | null,
  stateTimer: null as Timer | null,
  lastState: '',
  isUnattended: false,
  // Whether this Claude Code draws a Button's label from styled children,
  // so the hotkey's letter can be underlined in it.
  canUnderline: null as boolean | null,
}

// Sends one event to Discord when it is on and a webhook is set; resolves
// the message id, or null.
async function notify($: EngineInterface, event: NotifyEvent, editId?: string): Promise<string | null> {
  if (!S.kinds.includes(event.kind)) return null
  const state = await read($, notifier)
  if (state.url === null) return null
  const git = await read($, repo)
  const at = await read($, place)
  const who = await read($, account)
  const root = S.where.primary ?? at?.root ?? null
  const placeNow: NotifyPlace = {
    host: S.where.host,
    repo: root === null ? null : (root.replace(/[\\/]+$/, '').split(/[\\/]/).pop() ?? null),
    branch: git?.branch ?? null,
    tmux: S.where.tmux,
    account: who?.key ?? null,
  }
  const body = discordBody(event, placeNow, { mention: state.mention, isBrief: S.isBrief, now: await $.clock.now() })
  const sent = await sendDiscord($, state.url, body, editId)
  const stamp = await $.clock.now()
  if (sent.isSent) {
    await update($, notifier, now => ({ ...now, last: { at: stamp, text: `sent ${event.kind}`, isError: false } }))
    return sent.id
  }
  const before = (await read($, notifier)).last
  await update($, notifier, now => ({ ...now, last: { at: stamp, text: sent.reason, isError: true } }))
  // Said once, not on every event, until a send works again.
  if (before?.isError !== true) $.ui.toast(`dr-cockpit: Discord notification failed: ${sent.reason}`)
  return null
}

// The context, cost and plan fields most messages carry.
async function turnFields($: EngineInterface): Promise<{ name: string; value: string }[]> {
  const head = await read($, budget)
  const items = await read($, plan)
  const summary = await read($, run)
  const fields: { name: string; value: string }[] = []
  if (head !== null) fields.push({ name: 'Context', value: `${kTokens(head.tokens)} · ${Math.round((head.tokens / head.limit) * 100)}% of handoff` })
  if (head?.usd != null) fields.push({ name: 'Cost', value: `$${head.usd.toFixed(2)}` })
  if (summary !== null && summary.total > 0) fields.push({ name: 'Run', value: `${summary.done}/${summary.total}` })
  else if (items.length > 0) fields.push({ name: 'Plan', value: `${items.filter(item => item.status === 'completed').length}/${items.length}` })
  return fields
}

async function setActivity($: EngineInterface, change: (now: CockpitActivity) => CockpitActivity) {
  await update($, activity, change)
  await syncTicker($)
  scheduleState($)
}

// The pane's clock: a redraw a second while a turn runs, a background shell
// runs or a subagent works, so their timers count seconds; and while a turn
// runs, the state file's heartbeat.
async function syncTicker($: EngineInterface) {
  const now = await read($, activity)
  S.isTurnLive = now.kind === 'running' || now.kind === 'waiting' || now.kind === 'asking'
  const isTicking =
    S.isTurnLive || (await read($, shells)).length > 0 || (await read($, spawns)).some(one => !one.isDone) || isFinishArmed(await read($, finish))
  if (isTicking && S.ticker === null) {
    S.ticks = 0
    S.ticker = $.clock.every(1000, () => {
      S.ticks++
      $.ui.invalidate('ui.render')
      if (S.isTurnLive && (S.ticks * 1000) % HEARTBEAT_MS === 0) scheduleState($, true)
    })
  } else if (!isTicking && S.ticker !== null) {
    S.ticker.cancel()
    S.ticker = null
  }
}

// The state file dr-status reads: written at most twice a second, and only
// when it changed, unless a heartbeat asks.
function scheduleState($: EngineInterface, isHeartbeat = false) {
  if (S.where.sessionId === null || S.where.configDir === null) return
  if (isHeartbeat) S.lastState = ''
  if (S.stateTimer !== null) return
  S.stateTimer = $.clock.after(500, () => {
    S.stateTimer = null
    void writeState($)
  })
}

async function writeState($: EngineInterface) {
  try {
    const now = await read($, activity)
    const summary = await read($, run)
    const body = {
      v: 1,
      activity: {
        kind: now.kind,
        since: Math.floor((now.kind === 'idle' || now.kind === 'failed' ? (now.endedAt ?? now.since) : now.since) / 1000),
        tool: now.tool,
      },
      run:
        summary === null || summary.total === 0
          ? null
          : {
              done: summary.done,
              total: summary.total,
              round: roundNumber(summary.tasks.find(task => task.state === 'assigned' && task.round !== null)?.round ?? null),
              blocked: summary.tasks.filter(task => task.state === 'blocked').length,
            },
    }
    const text = JSON.stringify(body)
    if (text === S.lastState) return
    S.lastState = text
    const stamp = Math.floor((await $.clock.now()) / 1000)
    await $.fs.write(`${S.where.configDir}/dr-cockpit/state/${S.where.sessionId}.json`, JSON.stringify({ ...body, updatedAt: stamp }) + '\n')
  } catch {
    // No state file: dr-status shows its own segments alone.
  }
}

// An approval or question was answered (or the turn ended): stop its timer
// and edit its message to say how it went.
async function settleWait($: EngineInterface, id: string, outcome: string) {
  const wait = S.waits.get(id)
  if (wait === undefined) return
  S.waits.delete(id)
  wait.timer?.cancel()
  if (wait.messageId !== null) {
    await notify($, { ...wait.event, title: outcome }, wait.messageId)
  }
}

// Starts waiting on the person: the Now row says so at once, Discord after
// notifyAskAfter seconds if it is still unanswered.
async function startWait($: EngineInterface, id: string, kind: 'waiting' | 'asking', event: NotifyEvent) {
  const stamp = await $.clock.now()
  await setActivity($, now => ({ ...now, kind, since: stamp, detail: event.detail ?? null, isSent: false }))
  const send = async () => {
    const wait = S.waits.get(id)
    if (wait === undefined) return
    wait.timer = null
    const messageId = await notify($, event)
    if (messageId === null) return
    wait.messageId = messageId
    await update($, activity, now => (now.kind === kind ? { ...now, isSent: true } : now))
  }
  const delay = Math.max(0, S.notifyAskAfter) * 1000
  S.waits.set(id, { timer: delay === 0 ? null : $.clock.after(delay, () => void send()), messageId: null, event })
  if (delay === 0) await send()
}

// Back to running once nothing S.waits on the person.
async function endWait($: EngineInterface, id: string, outcome: string) {
  await settleWait($, id, outcome)
  if (S.waits.size > 0) return
  await setActivity($, now => (now.kind === 'waiting' || now.kind === 'asking' ? { ...now, kind: 'running', detail: null, isSent: false } : now))
}

// The run's ledger, its plan's tasks, and the newest handoff: read from the
// primary checkout, S.where dr-superpowers keeps .superpowers/.
async function readRun($: EngineInterface) {
  const root = S.where.primary ?? (await read($, place))?.root ?? null
  if (root === null) return
  try {
    const handoff = await $.fs.stat(`${root}/.superpowers/handoff/latest.md`).catch(() => null)
    const handoffTime = handoff?.kind === 'file' ? handoff.mtimeMs : null
    if ((await read($, handoffAt)) !== handoffTime) await update($, handoffAt, () => handoffTime)
    const base = `${root}/.superpowers/sdd`
    const entries = await $.fs.list(base).catch(() => [])
    let newest: { path: string; at: number } | null = null
    for (const entry of entries) {
      if (entry.kind !== 'dir') continue
      const info = await $.fs.stat(`${base}/${entry.name}/progress.md`).catch(() => null)
      if (info?.kind === 'file' && (newest === null || info.mtimeMs > newest.at)) newest = { path: `${base}/${entry.name}/progress.md`, at: info.mtimeMs }
    }
    await readFinish($, newest === null ? `${base}/finish.json` : newest.path.replace(/progress\.md$/, 'finish.json'))
    const startedAt = (await read($, usage))?.startedAt ?? (await $.session.usage().catch(() => null))?.startedAt ?? 0
    const isOlder = newest !== null && newest.at < startedAt
    const clear = async () => {
      if ((await read($, run)) !== null) await update($, run, () => null)
    }
    // A ledger counts once this session works on it, or when it is the one
    // the session started next to.
    if (newest === null || (!(await read($, isPlanSession)) && isOlder)) return clear()
    const ledger = parseLedger(String(await $.fs.read(newest.path)))
    let titles: { n: number; title: string }[] = []
    if (ledger.plan !== null) {
      const planPath = ledger.plan.startsWith('/') ? ledger.plan : null
      for (const candidate of planPath === null ? [(await read($, place))?.root, root].filter(Boolean).map(dir => `${dir}/${ledger.plan}`) : [planPath]) {
        try {
          titles = planTasks(String(await $.fs.read(candidate)))
          if (titles.length > 0) break
        } catch {
          // Try the next checkout.
        }
      }
    }
    const numbers = [...new Set([...titles.map(one => one.n), ...ledger.tasks.map(one => one.n)])].sort((a, b) => a - b)
    const summary: CockpitRun = {
      plan: ledger.plan,
      tasks: numbers.map(n => {
        const known = ledger.tasks.find(one => one.n === n)
        return {
          n,
          title: titles.find(one => one.n === n)?.title ?? '',
          state: known?.state ?? 'pending',
          round: known?.round ?? null,
          seat: known?.seat ?? null,
          isClean: known?.isClean ?? false,
          reason: known?.reason ?? null,
        }
      }),
      done: ledger.tasks.filter(one => one.state === 'complete').length,
      total: numbers.length,
      isFinished: ledger.isFinished,
    }
    // A run whose every task was done before this session started is history:
    // a new session starts with no Run card.
    if (isOlder && (summary.isFinished || (summary.total > 0 && summary.done === summary.total))) return clear()
    await update($, run, () => summary)
    scheduleState($)
    await sendLedgerEvents($, summary)
  } catch {
    // No readable ledger: the Plan card stays as it is.
  }
}

// The finish action dr-superpowers asked for before the run, from the run's
// finish.json, or the one beside the workspaces for work without a plan.
async function readFinish($: EngineInterface, path: string) {
  const text = await $.fs.read(path).catch(() => null)
  const next: CockpitFinish | null = text === null ? null : parseFinish(String(text))
  if (JSON.stringify(await read($, finish)) === JSON.stringify(next)) return
  await update($, finish, () => next)
  await syncTicker($)
}

// A task that became blocked or complete since the last read, said once.
async function sendLedgerEvents($: EngineInterface, summary: CockpitRun) {
  const keys = summary.tasks.flatMap(task =>
    task.state === 'blocked' ? [`blocked:${task.n}:${task.reason ?? ''}`] : task.state === 'complete' ? [`complete:${task.n}`] : [],
  )
  if (summary.isFinished) keys.push('finished')
  if (S.ledgerSeen === null) {
    S.ledgerSeen = new Set(keys)
    return
  }
  for (const key of keys) {
    if (S.ledgerSeen.has(key)) continue
    S.ledgerSeen.add(key)
    const [what, n] = key.split(':')
    const task = summary.tasks.find(one => String(one.n) === n)
    if (what === 'blocked' && task !== undefined) {
      await notify($, {
        kind: 'blocked',
        title: `🛑 Task ${task.n} blocked`,
        detail: task.reason ?? undefined,
        fields: [{ name: 'Run', value: `${summary.done}/${summary.total}` }],
      })
    } else if (what === 'complete' && task !== undefined) {
      await notify($, {
        kind: 'task',
        title: `✅ Task ${task.n} complete${task.isClean ? ', review clean' : ''}`,
        detail: task.title || undefined,
        isPlain: true,
        fields: [{ name: 'Run', value: `${summary.done}/${summary.total}` }],
      })
    } else if (what === 'finished') {
      await notify($, { kind: 'task', title: '🏁 Final review clean', fields: [{ name: 'Run', value: `${summary.done}/${summary.total}` }] })
    }
  }
}

// The webhook and mention, from the environment or the mod's own store.
async function readNotifier($: EngineInterface) {
  try {
    const fromEnv = ((await $.env.get('DR_COCKPIT_NOTIFY_URL')) ?? '').trim()
    const stored = await $.store.get(STORE_URL)
    const url = isDiscordWebhook(fromEnv) ? fromEnv : typeof stored === 'string' && isDiscordWebhook(stored) ? stored : null
    const mention = await $.store.get(STORE_MENTION)
    await update($, notifier, now => ({
      ...now,
      url,
      isFromEnv: isDiscordWebhook(fromEnv),
      mention: typeof mention === 'string' ? mentionId(mention) : null,
    }))
  } catch {
    // No store on this host: notifications stay off.
  }
}

// Where the messages come from and S.where the state file goes, read once.
async function readWhere($: EngineInterface) {
  try {
    S.where.sessionId = await $.session.id()
  } catch {
    S.where.sessionId = null
  }
  const home = (await $.env.get('HOME')) ?? (await $.env.get('USERPROFILE')) ?? ''
  const configDir = (await $.env.get('CLAUDE_CONFIG_DIR')) || (home === '' ? '' : `${home}/.claude`)
  S.where.configDir = configDir === '' ? null : configDir.replace(/[\\/]+$/, '')
  try {
    const settings = (await $.settings.read()) as { permissions?: { defaultMode?: unknown } }
    S.isUnattended = UNATTENDED_MODES.includes(String(settings.permissions?.defaultMode ?? ''))
  } catch {
    S.isUnattended = false
  }
  const firstLine = async (argv: string[]) => {
    try {
      const ran = await $.process.run(argv, { timeoutMs: 2000 })
      const line = ran.exitCode === 0 ? (ran.stdout.split('\n')[0] ?? '').trim() : ''
      return line === '' ? null : line
    } catch {
      return null
    }
  }
  S.where.host = (await $.env.get('HOSTNAME')) || (await firstLine(['hostname']))
  S.where.tmux = (await $.env.get('TMUX')) ? await firstLine(['tmux', 'display-message', '-p', '#S']) : null
  // A worktree's .superpowers/ lives in the primary checkout.
  const common = await firstLine(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'])
  S.where.primary = common === null ? null : common.replace(/[\\/]\.git[\\/]?$/, '') || null
}

// The context crossed its handoff budget: said once per crossing.
async function onBudget($: EngineInterface, reading: { now: CockpitBudget; isPast: boolean } | undefined) {
  if (reading === undefined) return
  const { now, isPast } = reading
  if (!isPast) {
    S.isBudgetSent = false
    return
  }
  if (S.isBudgetSent) return
  S.isBudgetSent = true
  await notify($, {
    kind: 'budget',
    title: '🔶 Handoff budget reached',
    detail: `${kTokens(now.tokens)} of ${kTokens(now.limit)}.${(await read($, isPlanSession)) ? ' The controller hands off after the task in flight.' : ''}`,
    isPlain: true,
  })
}

// Saves the webhook, or says why not; an empty value removes it.
async function saveWebhook($: EngineInterface, value: string): Promise<string | null> {
  const url = value.trim()
  if (url !== '' && !isDiscordWebhook(url)) return 'not a Discord webhook URL'
  try {
    if (url === '') await $.store.delete(STORE_URL)
    else await $.store.set(STORE_URL, url)
  } catch (error) {
    return error instanceof Error ? error.message : 'could not be saved'
  }
  await readNotifier($)
  return null
}

async function saveMention($: EngineInterface, value: string): Promise<string | null> {
  const id = mentionId(value)
  if (value.trim() !== '' && id === null) return 'not a Discord user id (digits only)'
  try {
    if (id === null) await $.store.delete(STORE_MENTION)
    else await $.store.set(STORE_MENTION, id)
  } catch (error) {
    return error instanceof Error ? error.message : 'could not be saved'
  }
  await readNotifier($)
  return null
}

async function sendTest($: EngineInterface): Promise<string> {
  const state = await read($, notifier)
  if (state.url === null) return 'No Discord webhook is set.'
  const body = discordBody(
    { kind: 'done', title: '🔔 Test from dr-cockpit', detail: 'Notifications reach this channel.', isPlain: true },
    { host: S.where.host, repo: null, branch: null, tmux: S.where.tmux, account: (await read($, account))?.key ?? null },
    { mention: null, isBrief: S.isBrief, now: await $.clock.now() },
  )
  const sent = await sendDiscord($, state.url, body)
  const stamp = await $.clock.now()
  await update($, notifier, now => ({ ...now, last: { at: stamp, text: sent.isSent ? 'test sent' : sent.reason, isError: !sent.isSent } }))
  return sent.isSent ? 'Test message sent to Discord.' : `Test message not sent: ${sent.reason}`
}

async function notifyCommand($: EngineInterface, words: string[]): Promise<{ text: string }> {
  const [verb = '', ...rest] = words
  if (verb === 'test') return { text: await sendTest($) }
  if (verb === 'url') {
    const problem = await saveWebhook($, rest.join(' '))
    return { text: problem ?? (rest.join('').trim() === '' ? 'Discord webhook removed.' : 'Discord webhook saved.') }
  }
  if (verb === 'mention') {
    const problem = await saveMention($, rest.join(' '))
    return { text: problem ?? 'Discord mention saved.' }
  }
  const state = await read($, notifier)
  return {
    text: state.url === null ? 'No Discord webhook is set. /cockpit notify url <url> sets one.' : `Discord webhook: ${maskWebhook(state.url)}${state.isFromEnv ? ' (from DR_COCKPIT_NOTIFY_URL)' : ''}.`,
  }
}


// Reads the status line's figures (free without a breakdown) and, past the
// budget in a dr-superpowers session, tells the model once.
async function refresh($: EngineInterface, tuning: Tuning, compactWindow: number | undefined): Promise<{ now: CockpitBudget; isPast: boolean } | undefined> {
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
  const reading = { now: { tokens, limit, window, compactWindow: compactWindow ?? null, usd }, isPast: level === 'handoff' }
  if (level !== 'handoff') {
    if (await read($, isNudged)) await update($, isNudged, () => false)
    return reading
  }
  if (!nudgeModel || (await read($, isNudged)) || !(await read($, isPlanSession))) return reading
  await update($, isNudged, () => true)
  const note = `dr-cockpit: budget: ${kTokens(tokens)} of ${kTokens(limit)} — handoff. ${HANDOFF_PROMPT}`
  try {
    await $.session.append({ message: { type: 'user', content: [{ type: 'text', text: note }] } })
  } catch {
    // The host would not take the row: say it to the person instead.
    $.ui.toast(note)
  }
  return reading
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
  const crossed: CockpitUsage['limits'] = []
  for (const limit of reading.limits) {
    const key = `${limit.kind}@${limit.resetsAt ?? ''}`
    if (limit.percent < at || said.includes(key)) continue
    await update($, alerted, list => [...list, key].slice(-20))
    const reset = limit.resetsAt === null ? '' : ` · resets in ${duration(limit.resetsAt - reading.readAt) || 'now'}`
    $.ui.toast(`dr-cockpit: ${limitLabel(limit.kind)} limit at ${Math.round(limit.percent)}%${reset}`)
    crossed.push(limit)
  }
  return crossed
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
async function readVersion($: EngineInterface) {
  try {
    S.canUnderline = isAtLeast((await $.session.version()).base, UNDERLINE_SINCE)
  } catch {
    S.canUnderline = false
  }
}

// A Bash call that went to the background (asked for, Ctrl+B, or its
// timeout) is a running shell until its notification or a stop names it.
function clip(text: string, width: number): string {
  const chars = [...text]
  return chars.length <= width ? text : chars.slice(0, width - 1).join('') + '…'
}

async function trackShells($: EngineInterface, tool: string, e: object, result: unknown) {
  if (tool === 'Bash') {
    const id = (result as { backgroundTaskId?: unknown } | undefined)?.backgroundTaskId
    if (typeof id !== 'string' || id === '') return
    const shell: CockpitShell = { id, command: String((e as { command?: unknown }).command ?? ''), startedAt: await $.clock.now() }
    await update($, shells, list => [...list.filter(one => one.id !== id), shell].slice(-20))
    await syncTicker($)
    return
  }
  if (tool === 'TaskStop' || tool === 'KillShell' || tool === 'KillBash') {
    const input = e as { task_id?: unknown; shell_id?: unknown }
    const id = (result as { task_id?: unknown } | undefined)?.task_id ?? input.task_id ?? input.shell_id
    if (typeof id === 'string') {
      await update($, shells, list => list.filter(one => one.id !== id))
      await syncTicker($)
    }
  }
}

// The /config row "Enable Remote Control for all sessions", and the remote
// clients already attached when the session starts.
async function readRemote($: EngineInterface) {
  try {
    const row = (await $.config.list()).find(one => one.key === 'remoteControl')
    const setting = row === undefined ? null : String(row.value)
    const before = await read($, remote)
    if (before.setting !== setting) await update($, remote, now => ({ ...now, setting }))
    if (before.clients.length === 0) {
      const away = (await $.session.surfaces()).filter(one => one !== 'terminal')
      if (away.length > 0) await update($, remote, now => ({ ...now, clients: away.map(surface => ({ id: `${surface}:default`, surface })) }))
    }
  } catch {
    // Attach events still fill it in.
  }
}

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

// The round of the task in flight, as a number, for the strip.
function runRound(summary: CockpitRun): string | null {
  return summary.tasks.find(task => task.state === 'assigned' && task.round !== null)?.round ?? null
}

// The run's tasks around the one in flight, so a long plan shows where it is.
function runWindow(tasks: CockpitRun['tasks'], size: number): CockpitRun['tasks'] {
  if (tasks.length <= size) return [...tasks]
  const at = tasks.findIndex(task => task.state !== 'complete')
  const start = Math.max(0, Math.min((at === -1 ? tasks.length : at) - 2, tasks.length - size))
  return tasks.slice(start, start + size)
}

// What a call asks permission for, in a line: the command, the file, or the URL.
function callSummary(tool: string, input: unknown): string {
  const args = (input ?? {}) as Record<string, unknown>
  for (const key of ['command', 'file_path', 'notebook_path', 'url', 'path', 'pattern']) {
    const value = args[key]
    if (typeof value === 'string' && value !== '') return value.split('\n')[0] ?? ''
  }
  return ''
}

// The question an AskUserQuestion call puts, or the plan ExitPlanMode shows, cut short.
function questionOf(e: object): string {
  const args = e as { questions?: { question?: unknown; options?: { label?: unknown }[] }[]; plan?: unknown }
  const first = args.questions?.[0]
  if (first !== undefined && typeof first.question === 'string') {
    const labels = (first.options ?? []).map(option => option.label).filter((label): label is string => typeof label === 'string')
    return excerpt(`${first.question}${labels.length > 0 ? `\n${labels.map((label, index) => `${index + 1}. ${label}`).join('  ')}` : ''}`, 500)
  }
  return typeof args.plan === 'string' ? excerpt(args.plan, 300) : ''
}

// Why a turn failed, in a few words.
function failureOf(e: object): string | null {
  const refusal = (e as { refusal?: { explanation?: unknown; category?: unknown } }).refusal
  if (refusal !== undefined) return typeof refusal.explanation === 'string' ? excerpt(refusal.explanation, 80) : 'refused'
  const answer = String((e as { answer?: unknown }).answer ?? '').trim()
  return answer === '' ? 'API error' : excerpt(answer.split('\n')[0] ?? '', 80)
}

function kindLabel(kind: NotifyKind): string {
  return kind === 'ask' ? 'approval' : kind
}

/**
 * Posts a body to the webhook, or with `id` edits that message, waiting out
 * one rate limit. Never throws.
 */
async function sendDiscord($: EngineInterface, url: string, body: Record<string, unknown>, id?: string): Promise<SendResult> {
  const base = url.trim().replace(/\/$/, '')
  const target = id === undefined ? `${base}?wait=true` : `${base}/messages/${id}`
  const init = { method: id === undefined ? 'POST' : 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const answer = await $.http.fetch(target, init)
      if (answer.status === 429 && attempt === 0) {
        const wait = Number((JSON.parse(answer.text || '{}') as { retry_after?: unknown }).retry_after)
        await $.clock.sleep(Math.min(10_000, Math.max(250, (Number.isFinite(wait) ? wait : 1) * 1000)))
        continue
      }
      if (!answer.ok) return { isSent: false, reason: `Discord answered ${answer.status}` }
      try {
        const sent = JSON.parse(answer.text || '{}') as { id?: unknown }
        return { isSent: true, id: typeof sent.id === 'string' ? sent.id : (id ?? null) }
      } catch {
        return { isSent: true, id: id ?? null }
      }
    } catch (error) {
      return { isSent: false, reason: error instanceof Error ? error.message : String(error) }
    }
  }
  return { isSent: false, reason: 'Discord is rate limiting' }
}
