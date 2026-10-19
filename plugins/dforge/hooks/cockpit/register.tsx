import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderChildren, RenderInput, Timer, TurnUsage } from 'claude-code'

import type {
  CockpitAccount,
  CockpitActivity,
  CockpitAutoRun,
  CockpitBreakdown,
  CockpitBudget,
  CockpitFinish,
  CockpitPlanItem,
  CockpitRefusal,
  CockpitResumeOffer,
  CockpitRoots,
  CockpitRun,
  CockpitSeat,
  CockpitSettingsView,
  CockpitShell,
  CockpitSpawn,
  CockpitUsage,
} from '../../types'
import {
  accountColor,
  accountKey,
  attributionIn,
  autoLimitFor,
  autoRunFor,
  agentGroups,
  bar,
  billingLabel,
  budgetFor,
  collapsedFrom,
  collapsedToggled,
  duration,
  elapsed,
  endsOnSentinel,
  finalLimitFor,
  finishLine,
  fitBand,
  folderRuns,
  handedOff,
  isAtLeast,
  isGitWriteTool,
  isDforge,
  kTokens,
  levelOf,
  limitForecast,
  limitLabel,
  modelName,
  nowLine,
  parseFinish,
  parseLedger,
  parseModeLines,
  planCandidates,
  planTasks,
  planFromTodos,
  planWithUpdate,
  positive,
  rampColor,
  remoteRuns,
  repoFromPorcelain,
  repoName,
  resumeOfferOf,
  runList,
  shellAge,
  runsWidth,
  SECTIONS,
  sectionsFrom,
  sectionsToggled,
  sparkline,
  stackedRuns,
  tasksEnded,
  termColor,
  themeColor,
  track,
  turnsToBudget,
  windowElapsed,
  warnShare,
  writesGitText,
} from './lib'
import type { AgentGroupKey, BandInput, Run, Section, TrackPart } from './lib'
import { SCHEMA, claudeLocks, envLocks, importedSettings, rangeText, resolveSettings, rowsOf, settingProblems, settingWritten, steppedSetting, tabsOf, typedNumber } from './config'
import type { SettingValue, SettingsFile } from './config'
import { nativeLine, nativeRun } from './native'
import { drawSettings } from './settings-view'
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
import { CELL_PX, avatarSvg, bandMetersSvg, gaugeTileSvg, gaugeSvg, labelledMeterSvg, meterSvg, paint, seatSvg, segmentsSvg, stackSvg, svgWidth, trendSvg } from './svg'
import type { BandMeter, PanelLine, PanelRun, Segment } from './svg'

const PANE = 'dforge'
const PANE_COLUMNS = 56
const INDENT = 2
// A button's rounded frame: the accent on the one that matters, gray at rest.
const BUTTON_MAIN = 'permission'
const BUTTON_REST = 'inactive'
// The rows the band asks for: its frame, two lines and a warning.
const COMPACT_ROWS = 5
// The first Claude Code that takes styled children in a Button.
const UNDERLINE_SINCE = '2.1.295'
// The most /context categories the pane lists (breakdownRows caps it lower).
const MAX_BREAKDOWN_ROWS = 12
// Below this the band drops its frame.
const FRAME_MIN_COLUMNS = 48
const HANDOFF_PROMPT =
  'Finish the task in flight through its completion line, then hand off with the dforge handoff skill. Start no new task.'
function resumePrompt(): string {
  return `Resume the work in ${S.latestName ?? '.dforge/handoff/latest.md'} with the dforge resume-execution skill.`
}
// A handoff older than this is not offered for resuming.
const RESUME_WITHIN = 3 * 86_400_000
// What an auto run's compaction keeps (reference/auto-run.md).
const AUTO_COMPACT_INSTRUCTIONS =
  'Preserve verbatim: the worktree path; the plan, ledger, handoff and auto-run state file paths; the current HEAD; every Ruling: line; and the auto run pending decisions. Name the task in progress and its fix round.'
// What the switch's compaction keeps: once the plan is saved, the spec and the
// plan hold what the design conversation decided.
const AUTO_SWITCH_INSTRUCTIONS =
  "Preserve verbatim: the spec, plan, register and auto-run state file paths; the base branch; the current HEAD. Drop the design conversation: the spec and the plan hold what it decided. No task has started and no execution worktree exists yet; execution begins at the execution skill's Setup."
// A failed stage is tried again after this long; a live turn or background work defers it as long.
const AUTO_RETRY_MS = 5_000
// The restored default model is written this many times at most, each write
// watched this long for the engine to read it back.
const RESTORE_WRITES = 3
const RESTORE_WAIT_MS = 3_000
const RESTORE_POLL_MS = 500
type AutoStage = 'compact' | 'continue' | 'clear' | 'resume' | 'switch' | 'switch-resume'
// The pending action the state file holds while each stage is due.
const AUTO_STAGE_PENDING: Record<AutoStage, string> = {
  compact: 'compact',
  continue: 'after-compact',
  clear: 'clear',
  resume: 'resume',
  switch: 'switch',
  'switch-resume': 'switch-resume',
}
function autoContinuePrompt(root: string, plan: string | null): string {
  const where = plan === null ? '' : ` for plan ${plan}, through the After compaction steps of the execution skill its Execution line names`
  return `Continue the auto run: run \`bash ${root}/scripts/auto-run after-compact\` first, then continue the phase \`bash ${root}/scripts/auto-run status\` names${where}, as reference/auto-run.md §After a compaction says.`
}
// The watchdog's period, and how long background work may defer a pending
// stage before that books a failure.
const WATCHDOG_MS = 60_000
const DEFER_CAP_MS = 1_800_000
// The tools that wait on the person by their nature: their dialog is the question.
const ASKING_TOOLS = ['AskUserQuestion', 'ExitPlanMode']
// Permission modes in which an "ask" is settled without the person.
const UNATTENDED_MODES = ['auto', 'bypassPermissions', 'dontAsk']
// How many main-turn context readings the forecast keeps.
const TURN_READINGS = 12
const STORE_URL = 'notifyUrl'
const STORE_MENTION = 'notifyMention'
const STORE_IMPORTED = 'webhookImported'
// How many context readings the trend line keeps.
const TREND_LENGTH = 40
// The colors the context breakdown cycles through, largest category first.
const BREAKDOWN_COLORS = ['cyan', 'magenta', 'yellow', 'green', 'blue', 'red'] as const
// The usage windows the desktop draws as gauges, in order.
const GAUGED: readonly string[] = ['five_hour', 'seven_day']
// The desktop's panel fill: a faint gray that lifts a card off the pane in
// the light theme and the dark alike.
const CARD = '#8080800f'
// How the desktop's run bar colors a task by its state.
const RUN_SEGMENTS: Record<string, Segment> = { complete: 'done', assigned: 'active', blocked: 'blocked' }
const GIT_STATUS = ['git', '--no-optional-locks', '-c', 'core.fsmonitor=false', 'status', '--porcelain=v2', '--branch']

const budget = atom({ plugin: 'dforge', key: 'budget' } as const, null)
const usage = atom({ plugin: 'dforge', key: 'usage' } as const, null)
const breakdown = atom({ plugin: 'dforge', key: 'breakdown' } as const, null)
const seats = atom({ plugin: 'dforge', key: 'seats' } as const, [])
const spawns = atom({ plugin: 'dforge', key: 'spawns' } as const, [])
const shells = atom({ plugin: 'dforge', key: 'shells' } as const, [])
const remote = atom({ plugin: 'dforge', key: 'remote' } as const, { clients: [], setting: null })
const plan = atom({ plugin: 'dforge', key: 'plan' } as const, [])
const repo = atom({ plugin: 'dforge', key: 'repo' } as const, null)
const refusals = atom({ plugin: 'dforge', key: 'refusals' } as const, [])
const isNudged = atom({ plugin: 'dforge', key: 'isNudged' } as const, false)
const isPlanSession = atom({ plugin: 'dforge', key: 'isPlanSession' } as const, false)
const autoRun = atom({ plugin: 'dforge', key: 'autoRun' } as const, null)
const alerted = atom({ plugin: 'dforge', key: 'alerted' } as const, [])
const trend = atom({ plugin: 'dforge', key: 'trend' } as const, [])
const view = atom({ plugin: 'dforge', key: 'view' } as const, 'cockpit')
const account = atom({ plugin: 'dforge', key: 'account' } as const, null)
const place = atom({ plugin: 'dforge', key: 'place' } as const, null)
const engine = atom({ plugin: 'dforge', key: 'engine' } as const, { model: null, effort: null, cache: null })
const IDLE: CockpitActivity = { kind: 'idle', since: 0, turnStartedAt: null, step: 0, tool: null, agent: null, detail: null, lastTurnMs: null, endedAt: null, isSent: false }
const activity = atom({ plugin: 'dforge', key: 'activity' } as const, IDLE)
const turnTokens = atom({ plugin: 'dforge', key: 'turnTokens' } as const, [])
const run = atom({ plugin: 'dforge', key: 'run' } as const, null)
const finish = atom({ plugin: 'dforge', key: 'finish' } as const, null)
const handoffAt = atom({ plugin: 'dforge', key: 'handoffAt' } as const, null)
const resumeOffer = atom({ plugin: 'dforge', key: 'resumeOffer' } as const, null)
const resumeDismissed = atom({ plugin: 'dforge', key: 'resumeDismissed' } as const, null)
const rootsNote = atom({ plugin: 'dforge', key: 'rootsNote' } as const, null)
const settings = atom({ plugin: 'dforge', key: 'settings' } as const, null)
const SETTINGS_VIEW: CockpitSettingsView = { tab: '', isHelpShown: true, editing: null, error: null, isConfirmingReset: false }
const settingsView = atom({ plugin: 'dforge', key: 'settingsView' } as const, SETTINGS_VIEW)
const notifier = atom({ plugin: 'dforge', key: 'notifier' } as const, {
  url: null,
  isFromEnv: false,
  mention: null,
  editing: null,
  error: null,
  last: null,
})

type Options = {
  handoffTokens: number
  handoffMode: string
  nudgeModel: boolean
  guardAttribution: boolean
  warnAt: number
  layout: string
  sections: string
  collapsed: string
  breakdownRows: number
  openAtStart: boolean
  limitAlertAt: number
  notifyOn: string
  notifyAfter: number
  notifyAskAfter: number
  notifyDetail: string
}

/** What the budget reading is judged by. */
type Tuning = { handoffTokens: number; nudgeModel: boolean; warnAt: number; isRelaxed: boolean }

/** The options with their defaults filled in, and what the pane derives from them. */
type Live = Omit<Options, 'layout'> & {
  layout: 'auto' | 'full' | 'compact'
  tuning: Tuning
  shown: Section[]
  shownCollapsed: Section[]
  isMinimized: boolean
}

function liveFrom(values: Partial<Options>): Live {
  const {
    handoffTokens = 0,
    handoffMode = 'strict',
    nudgeModel = true,
    guardAttribution = true,
    warnAt = 80,
    layout: layoutSetting = 'auto',
    sections = '',
    collapsed = '',
    breakdownRows = 6,
    openAtStart = true,
    limitAlertAt = 90,
    notifyOn = '',
    notifyAfter = 60,
    notifyAskAfter = 20,
    notifyDetail = 'full',
  } = values
  // Anything but the three words reads as auto.
  const layout = layoutSetting === 'full' || layoutSetting === 'compact' ? layoutSetting : 'auto'
  return {
    handoffTokens,
    handoffMode,
    nudgeModel,
    guardAttribution,
    warnAt,
    layout,
    sections,
    collapsed,
    breakdownRows,
    openAtStart,
    limitAlertAt,
    notifyOn,
    notifyAfter,
    notifyAskAfter,
    notifyDetail,
    tuning: { handoffTokens, nudgeModel, warnAt: warnShare(warnAt), isRelaxed: handoffMode === 'relaxed' },
    shown: sectionsFrom(sections),
    shownCollapsed: collapsedFrom(collapsed),
    isMinimized: layout === 'compact',
  }
}

/** The options in force now: the settings atom once written, else the defaults. */
async function live($: EngineInterface): Promise<Live> {
  return liveFrom(((await read($, settings)) ?? {}) as Partial<Options>)
}

/** Points the notifier at the options' events, detail and wait. */
function applyNotify(o: Live) {
  S.kinds = o.notifyOn === 'none' ? [] : notifyKindsFrom(o.notifyOn)
  S.isBrief = o.notifyDetail === 'brief'
  S.notifyAskAfter = o.notifyAskAfter
}

export const register: Register = on => {
  // The settings' autoCompactWindow, read at the start and after each main
  // turn rather than on every tool call.
  let compactWindow: number | undefined

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'cockpit',
      description: 'Show context, usage, subagents, the plan and the repo in a pane',
      argumentHint: '[settings | notify test | notify url <url> | notify mention <id>]',
    })
    await loadSettings($)
    const o = await live($)
    compactWindow = await readCompactWindow($)
    await onBudget($, await refresh($, o.tuning, compactWindow))
    await readAccount($)
    await readPlace($)
    await readEngine($)
    await readWhere($)
    await readNotifier($)
    await readRun($)
    await trackAutoRun($)
    await beat($)
    S.watchdog?.cancel()
    S.watchdog = $.clock.every(WATCHDOG_MS, () => void watchdogTick($))
    await readVersion($)
    await readRemote($)
    if (o.isMinimized) {
      if ((await read($, view)) !== 'settings') await shutPane($)
    } else if (o.openAtStart) void $.ui.open(paneFor(o.layout))

    return next(e)
  })

  on('command.run', { command: 'cockpit' }, async ($, e) => {
    const o = await live($)
    const words = e.args.trim().split(/\s+/)
    if (words[0]?.toLowerCase() === 'notify') return notifyCommand($, words.slice(1))
    const wantsSettings = e.args.trim().toLowerCase() === 'settings'
    if (!wantsSettings && e.args.trim() !== '') {
      return { text: `Unknown argument "${e.args.trim()}". Usage: /cockpit [settings | notify test | notify url <url> | notify mention <id>]` }
    }
    if (wantsSettings) await showSettings($)
    else {
      await flushSettingNote($)
      await update($, view, () => 'cockpit')
    }
    await readAccount($)
    // The settings take the keyboard and as many rows as they need.
    const opened = wantsSettings
      ? await $.ui.open({ id: PANE, title: 'Cockpit', columns: PANE_COLUMNS, focus: true })
      : o.isMinimized
        ? await expand($, e.presentation.isFullscreen === true)
        : await $.ui.open(paneFor(o.layout))
    await refreshDetail($)

    // A surface that seats no panes (an older desktop) holds it undrawn: say
    // why rather than claim it opened.
    return { text: opened.isPlaced ? 'Cockpit pane opened.' : `Cockpit pane is waiting: ${opened.reason}` }
  })

  on('session.measure', async ($, e, next) => {
    const done = await next(e)
    const o = await live($)
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
    if (o.limitAlertAt > 0) {
      for (const limit of await alertLimits($, reading, o.limitAlertAt)) {
        await notify($, {
          kind: 'limit',
          title: `📊 ${limitLabel(limit.kind)} limit at ${Math.round(limit.percent)}%`,
          detail: limit.resetsAt === null ? undefined : `Resets in ${duration(limit.resetsAt - now) || 'under a minute'}.`,
          isPlain: true,
        })
      }
    }
    if (o.isMinimized || (await isPaneUp($))) await refreshDetail($)

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
    return next(e)
  }).catch(($, e, next) => next(e))

  // A compaction leaves no reading until the next response: drop the stale
  // one and re-arm the note, so it does not stay latched.
  on('session.compact', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined && e.trigger !== 'precompute' && 'messages' in done && done.messages !== undefined) {
      await update($, budget, () => null)
      await update($, isNudged, () => false)
      // The engine's or the person's compaction: the run's rule still applies after it.
      if (e.trigger === 'auto' || e.trigger === 'manual') await bookAutoCompaction($)
    }

    return done
  }).catch(($, e, next) => next(e))

  on('agent.spawn', async ($, e, next) => {
    const started = await next(e)
    if (started.deny !== undefined || started.agentId === undefined) return started
    if (isDforge(e.subagentType)) {
      await update($, isPlanSession, () => true)
      await flushSettingNote($)
    }
    const spawn: CockpitSpawn = {
      agentId: started.agentId,
      seat: e.subagentType,
      model: started.model,
      description: e.description,
      isDone: false,
      outcome: null,
      startedAt: await $.clock.now(),
    }
    await update($, spawns, list => [...list, spawn].slice(-50))
    await syncTicker($)

    return started
  }).catch(($, e, next) => next(e))

  // Remote Control clients joining and leaving; the terminal raises neither.
  on('session.attach', async ($, e, next) => {
    const joined = await next(e)
    const o = await live($)
    await update($, remote, now => ({ ...now, clients: [...now.clients.filter(one => one.id !== e.clientId), { id: e.clientId, surface: e.surface }] }))
    // A desktop session's start can come before its window joins: show the
    // pane once it has, unless the person closed it.
    if (o.openAtStart && !o.isMinimized && e.surface === 'desktop' && !S.isClosedByPerson && !(await isPaneUp($))) void $.ui.open(paneFor(o.layout))
    return joined
  }).catch(($, e, next) => next(e))

  // A skill typed as a slash command makes no Skill tool call; its prompt is expanded on every path.
  on('skill.prompt', async ($, e, next) => {
    const expanded = await next(e)
    if (isDforge(e.skill)) {
      await update($, isPlanSession, () => true)
      await flushSettingNote($)
    }
    return expanded
  }).catch(($, e, next) => next(e))

  on('ui.close', { id: PANE }, async ($, e, next) => {
    if (e.origin.kind === 'person') S.isClosedByPerson = true
    await flushSettingNote($)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.detach', async ($, e, next) => {
    const left = await next(e)
    await update($, remote, now => ({ ...now, clients: now.clients.filter(one => one.id !== e.clientId) }))
    return left
  }).catch(($, e, next) => next(e))

  // A background shell's end arrives as its task notification, kept as a row
  // of the loop that started it: the main conversation's, or a subagent's,
  // which no prompt.submit announces.
  on('session.append', async ($, e, next) => {
    const kept = await next(e)
    if (e.message.role === 'user') {
      const text = e.message.content.map(block => (block.type === 'text' ? block.text : '')).join('\n')
      if (text.includes('<task-notification>')) await endShells($, text)
    }
    return kept
  }).catch(($, e, next) => next(e))

  // A main turn begins: the Now row starts its clock.
  on('turn.start', async ($, e, next) => {
    const stamp = await $.clock.now()
    for (const [id, wait] of [...S.waits]) if (wait.agentId === null) await settleWait($, id, '⏹ Turn ended')
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
    }, e.agentId ?? null)
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
      await trackAutoRun($)
      compactWindow = await readCompactWindow($)
      await onBudget($, await refresh($, (await live($)).tuning, compactWindow))
      const turnUsage = e.usage as TurnUsage | undefined
      if (turnUsage !== undefined) {
        const cache = cacheOf(turnUsage)
        await update($, engine, now => ({ ...now, cache }))
      }
      const head = await read($, budget)
      if (head !== null) await update($, turnTokens, list => [...list, head.tokens].slice(-TURN_READINGS))
      for (const [id, wait] of [...S.waits]) if (wait.agentId === null) await settleWait($, id, '⏹ Turn ended')
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
      } else if (e.reason === 'answer' && e.durationMs >= Math.max(0, (await live($)).notifyAfter) * 1000) {
        const messageId = await notify($, {
          kind: 'done',
          title: `✅ Done in ${elapsed(e.durationMs)}`,
          detail: e.answer.trim() === '' ? undefined : excerpt(e.answer, 300),
          fields: await turnFields($),
        })
        if (messageId !== null) await update($, activity, now => ({ ...now, isSent: true }))
      }
      if (e.reason === 'answer') await armAutoRun($, e.answer)
      return done
    }
    const agentId = e.agentId
    const list = await read($, spawns)
    const spawn = list.find(one => one.agentId === agentId)
    if (spawn === undefined) return done
    const outcome = e.reason === 'answer' ? 'done' : 'failed'
    await update($, spawns, all => all.map(one => (one.agentId === agentId ? { ...one, isDone: true, outcome } : one)))
    for (const [id, wait] of [...S.waits]) if (wait.agentId === agentId) await endWait($, id, '⏹ Agent ended')
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

  on('attribution.text', { kind: 'commit' }, async ($, e, next) => ((await live($)).guardAttribution ? { text: '' } : next(e)))
  on('attribution.text', { kind: 'pr' }, async ($, e, next) => ((await live($)).guardAttribution ? { text: '' } : next(e)))

  // One hook for every tool: the attribution guard judges before anything
  // runs, and the main loop's budget and plan are read after each call, the
  // only point its context grows between turns.
  on('tool.call', async ($, e, next) => {
    const tool = String(e.tool)
    const line = (await live($)).guardAttribution ? attributionLine(tool, e) : undefined
    if (line !== undefined) {
      const refusal: CockpitRefusal = { at: await $.clock.now(), tool, line }
      await update($, refusals, list => [...list, refusal].slice(-20))
      return { deny: `dforge: this project keeps AI attribution out of git. Remove "${line}" and try again.` }
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
      }, null)
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
    if (tool === 'Skill' && isDforge(String((e as { skill?: unknown }).skill ?? ''))) {
      await update($, isPlanSession, () => true)
      await flushSettingNote($)
    }
    if (ran.deny === undefined && !ran.isError) await trackShells($, tool, e, ran.result)
    if (e.agentId === undefined) {
      if (ran.deny === undefined && !ran.isError) await trackPlan($, tool, e, ran.result)
      // A run starts, stops and changes regime through the model's own calls.
      await trackAutoRun($)
      await onBudget($, await refresh($, (await live($)).tuning, compactWindow))
      // The controller writes its ledger with its own tool calls.
      if (/\.dforge|\.dforge|finish-choice/.test(JSON.stringify(e))) await readRun($)
    }

    return ran
  }).catch(async ($, e, next) =>
    next.called || !(await live($)).guardAttribution ? next(e) : { deny: 'dforge: its attribution guard failed.' },
  )

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const table = $.ui.resolve(e)
    const o = await live($)
    const { Box, Button, Text } = table
    // The desktop draws vectors: its cards carry real meters and charts where
    // the terminal spells them in glyphs.
    const Svg = e.surface === 'desktop' && 'Svg' in table ? table.Svg : undefined
    const isDesktop = Svg !== undefined
    const now = await $.clock.now()
    const room = e.props.bodyColumns
    const isCompact = o.isMinimized || (o.layout === 'auto' && e.props.placement === 'inline')
    // Only these two surfaces draw the band above the prompt.
    const canMinimize = e.surface === 'terminal' || e.surface === 'desktop'
    const minimize = async () => {
      if (await setOption($, 'layout', 'compact')) await $.ui.close({ id: PANE })
    }
    const head = await read($, budget)
    const spend = await read($, usage)
    const rows = await read($, breakdown)
    const list = await read($, seats)
    const all = await read($, spawns)
    const background = await read($, shells)
    const remoteNow = await read($, remote)
    const items = await read($, plan)
    const git = await read($, repo)
    const placeNow = await read($, place)
    const refused = await read($, refusals)
    const canHandOff = await read($, isPlanSession)
    const act = await read($, activity)
    const summary = await read($, run)
    const finishNow = await read($, finish)
    const rootsNow = await read($, rootsNote)
    const offer = await offerNow($, now)
    const drawRuns = (key: string, runs: Run[]) =>
      runs.map((one, index) => (
        <Text key={`${key}-${index}`} color={one.color} bold={one.bold} dimColor={one.dim}>
          {one.text}
        </Text>
      ))

    // Every control is a button in a rounded box: gray at rest, the accent on
    // the one that matters (`isMain`), dim when it reads as off.
    if (S.canUnderline === null) await readVersion($)
    const button = (key: string, label: string, onPress: () => unknown, look: { hotkey?: string; isMain?: boolean; isOff?: boolean; isCompact?: boolean } = {}) => {
      // The desktop draws its own buttons, the main one in its primary look. A compact
      // button is that one on the terminal too: a single line, not a three-line box.
      if (isDesktop || look.isCompact) {
        return <Button key={key} label={label} hotkey={look.hotkey} variant={look.isMain ? 'primary' : undefined} dimColor={look.isOff} onPress={onPress} />
      }
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
    const isNearHandoff = head !== null && levelOf(head.tokens, head.limit, o.tuning.warnAt) !== 'quiet'
    const resumeCard = offer !== null && (
      <Box key="resume-card" flexDirection="column" borderStyle="round" borderColor={BUTTON_MAIN} paddingX={1}>
        <Text key="resume-title" color={BUTTON_MAIN} bold wrap="truncate-end">
          {`↻ Resumable work · ${handedOff(now - offer.at)}`}
        </Text>
        <Text key="resume-next" wrap="truncate-end">{`Next: ${offer.next}`}</Text>
        <Box key="resume-actions" flexDirection="row">
          {button('pane-resume', 'Resume', () => resume($, offer), { hotkey: 'r', isMain: true })}
        </Box>
      </Box>
    )
    const autoNow = await read($, autoRun)
    const actions = (
      <Box key="actions" flexDirection="row" flexWrap="wrap" columnGap={1}>
        {autoNow?.active && (
          <Text key="auto-line" color="magenta">
            {`Auto run · ${autoNow.phase} · ${autoNow.regime} · ${autoNow.compactions} ${autoNow.compactions === 1 ? 'compaction' : 'compactions'} · ${autoNow.resumes} ${autoNow.resumes === 1 ? 'resume' : 'resumes'}`}
          </Text>
        )}
        {autoNow?.active && button('pane-stop-auto', 'Stop auto', () => void stopAutoRun($))}
        {canHandOff && !autoNow?.active && button('pane-handoff', 'Hand off', () => $.prompt.submit({ text: HANDOFF_PROMPT, asUser: true }), { hotkey: 'h', isMain: isNearHandoff })}
        {button('pane-compact', 'Compact', () => $.session.compact(), { hotkey: 'c' })}
        {button('pane-settings', 'Settings', () => showSettings($), { hotkey: 's' })}
        {canMinimize && !isDesktop && !isCompact && button('pane-minimize', 'Minimize', minimize, { hotkey: 'm' })}
      </Box>
    )

    if ((await read($, view)) === 'settings') {
      // Each press saves to ~/.dforge/config.json and puts the value in force, so the rows below always show what is saved.
      const set = (key: string, value: SettingValue) => setOption($, key, value)
      const compact = (key: string, label: string, onPress: () => unknown, look: { hotkey?: string; isMain?: boolean; isOff?: boolean } = {}) =>
        button(
          key,
          label,
          async () => {
            if (state.editing !== null || state.isConfirmingReset) await show({})
            return onPress()
          },
          { ...look, isCompact: true },
        )
      // The desktop spaces these rows by its own scale, as the settings view does.
      const row = (key: string, label: string, ...controls: RenderChildren[]) => (
        <Box key={key} flexDirection="row" columnGap={isDesktop ? 'sm' : 1}>
          <Box key={`${key}-label`} width={16} flexShrink={0}>
            <Text>{label}</Text>
          </Box>
          <Box key={`${key}-controls`} flexDirection="row" flexWrap="wrap" alignItems="center" columnGap={isDesktop ? 'sm' : 1} rowGap={isDesktop ? 'xs' : undefined} flexShrink={1}>
            {controls}
          </Box>
        </Box>
      )
      const chips = (key: string, names: readonly string[], isOn: (name: string) => boolean, label: (name: string) => string, onPress: (name: string) => unknown) => (
        <Box key={key} flexDirection="row" flexWrap="wrap" columnGap={isDesktop ? 'xs' : 1} rowGap={isDesktop ? 'xs' : undefined} paddingLeft={isDesktop ? undefined : INDENT}>
          {names.map(name => compact(`${key}-${name}`, `${isOn(name) ? '✓' : '○'} ${label(name)}`, () => onPress(name), { isOff: !isOn(name) }))}
        </Box>
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
              {compact(`set-notify-${key}-cancel-button`, 'Cancel', () => update($, notifier, now => ({ ...now, editing: null, error: null })))}
            </Box>
          </Box>
        )
      const edit = (key: 'url' | 'mention') => openField($, `set-notify-${key}-input`, () => update($, notifier, now => ({ ...now, editing: key, error: null })))
      const webhookRows = (
        <Box key="set-notify-webhook" flexDirection="column">
          {notes.editing === 'url' && canType
            ? row('set-notify-url', 'Webhook', field('url', 'https://discord.com/api/webhooks/…', value => saveWebhook($, value)))
            : row(
                'set-notify-url',
                'Webhook',
                notes.url === null ? <Text key="set-notify-url-none" dimColor>not set </Text> : <Text key="set-notify-url-set" wrap="truncate-end"><Text color="green">✓ </Text>{maskWebhook(notes.url)} </Text>,
                notes.isFromEnv && <Text key="set-notify-url-env" dimColor>from the environment</Text>,
                notes.url !== null && compact('set-notify-test', 'Send test', () => sendTest($), { isMain: true }),
                !notes.isFromEnv && canType && compact('set-notify-url-edit', notes.url === null ? 'Set' : 'Change', () => edit('url'), { isMain: notes.url === null }),
                !notes.isFromEnv && notes.url !== null && compact('set-notify-url-remove', 'Remove', () => saveWebhook($, '')),
                !canType && notes.url === null && <Text key="set-notify-url-cli" dimColor>set it from a terminal: /cockpit notify url</Text>,
              )}
          {notes.last !== null && (
            <Text key="set-notify-last" color={notes.last.isError ? 'red' : 'green'} wrap="truncate-end">
              {' '.repeat(17)}
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
                canType && compact('set-notify-mention-edit', notes.mention === null ? 'Set' : 'Change', () => edit('mention')),
              )}
        </Box>
      )

      const state = await read($, settingsView)
      const values = (await read($, settings)) ?? {}
      const tabs = tabsOf(SCHEMA)
      const tab = tabs.includes(state.tab) ? state.tab : (tabs[0] ?? '')
      const rows = rowsOf(SCHEMA, values, tab, S.locks)
      // Every press but the one that asked for it ends an edit or a pending reset.
      const show = (change: Partial<CockpitSettingsView>) =>
        update($, settingsView, now => ({ ...now, editing: null, error: null, isConfirmingReset: false, ...change }))
      const save = async (key: string, value: SettingValue) => {
        if (state.editing !== null || state.isConfirmingReset) await show({})
        return set(key, value)
      }
      const custom: Record<string, RenderChildren> = {
        sections: (
          <Box key="set-sections-chips" flexDirection="column">
            <Box key="set-sections-label"><Text>Sections</Text></Box>
            {/* Under their label, wrapping to the pane's width. */}
            {chips(
              'set-section',
              SECTIONS,
              name => o.shown.includes(name as Section),
              name => name,
              name => save('sections', sectionsToggled(o.shown, name as Section)),
            )}
          </Box>
        ),
        collapsed: (
          <Box key="set-collapsed-chips" flexDirection="column">
            <Box key="set-collapsed-label"><Text>Collapsed</Text></Box>
            {chips(
              'set-collapsed',
              SECTIONS,
              name => o.shownCollapsed.includes(name as Section),
              name => name,
              name => save('collapsed', collapsedToggled(o.shownCollapsed, name as Section)),
            )}
          </Box>
        ),
        notifyOn: (
          <Box key="set-notifyOn-chips" flexDirection="column">
            <Box key="set-notifyOn-label"><Text>Send on</Text></Box>
            {chips(
              'set-notify-kind',
              NOTIFY_KINDS,
              kind => S.kinds.includes(kind as NotifyKind),
              kind => kindLabel(kind as NotifyKind),
              kind => save('notifyOn', notifyKindsToggled(S.kinds, kind as NotifyKind)),
            )}
          </Box>
        ),
      }

      return drawSettings(
        elements,
        {
          tabs,
          tab,
          hint: tab === 'Notifications' ? '(Discord)' : null,
          rows,
          isHelpShown: state.isHelpShown,
          editing: state.editing,
          error: state.error,
          isConfirmingReset: state.isConfirmingReset,
          canType,
          isDesktop,
          problems: S.settingProblems,
          custom,
          top: tab === 'Notifications' ? webhookRows : null,
        },
        {
          openTab: next => show({ tab: next }),
          set: save,
          step: (key, direction) => {
            const spec = SCHEMA[key]
            return spec === undefined ? undefined : save(key, steppedSetting(spec, Number(values[key] ?? spec.default), direction))
          },
          edit: key => (key === null ? show({ editing: null }) : openField($, `set-${key}-input`, () => show({ editing: key }))),
          submit: async (key, text) => {
            const spec = SCHEMA[key]
            if (spec === undefined) return
            const value = spec.type === 'number' ? typedNumber(spec, text) : text
            if (value === undefined) {
              await update($, settingsView, now => ({ ...now, editing: key, error: rangeText(spec) }))
              return
            }
            if (await set(key, value)) await show({})
          },
          reset: key => {
            const spec = SCHEMA[key]
            return spec === undefined ? undefined : save(key, spec.default)
          },
          toggleHelp: () => show({ isHelpShown: !state.isHelpShown }),
          askResetGroup: () => show({ isConfirmingReset: true }),
          resetGroup: async () => {
            for (const one of rows) {
              const spec = SCHEMA[one.key]
              if (one.isChanged && spec !== undefined) await set(one.key, spec.default)
            }
            await show({})
          },
          cancelReset: () => show({}),
          back: async () => {
            await show({})
            await flushSettingNote($)
            await update($, view, () => 'cockpit')
            // Minimized, the settings were all the pane was open for.
            if (o.isMinimized) await $.ui.close({ id: PANE })
          },
        },
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
    const failedCount = finished.filter(one => one.outcome === 'failed').length
    const doneCount = items.filter(item => item.status === 'completed').length
    const limits = spend?.limits ?? []
    const cost = head?.usd == null ? null : `$${head.usd.toFixed(2)}`

    const who = await read($, account)
    const tint = termColor(who?.color)
    const billing = billingLabel(who?.billing ?? null)
    const picture = (key: string, source: string, alt: string) => Svg !== undefined && <Svg key={key} source={source} alt={alt} />

    // Minimize shuts the pane for the band above the prompt and Expand opens
    // it again; each writes the layout setting, so the next session opens the
    // same way. A band drawn in the pane itself only changes the layout.
    // Saving the layout does not reload the mod, so an inline pane, opened for the
    // band's rows, has to be asked for the full pane.
    if (isCompact) {
      const isInline = e.props.placement === 'inline'
      return drawBand($, e, async () => {
        if ((await setOption($, 'layout', isInline ? 'full' : 'auto')) && isInline) await $.ui.open(paneFor('full'))
      })
    }

    // Each section is a card: a rounded frame in its own color, its title and
    // headline on the first line, its rows below, and a row's details two cells in.
    // Its title collapses it to that line, saved in the collapsed setting; a
    // collapsed Context card keeps its buttons.
    const inner = Math.max(20, room - 4)
    const wide = Math.max(10, inner - 2 * INDENT)
    const toggle = (name: Section) => setOption($, 'collapsed', collapsedToggled(o.shownCollapsed, name))
    const section = (key: Section, title: string, color: string, headline: RenderChildren, ...body: RenderChildren[]) => {
      const isCollapsed = o.shownCollapsed.includes(key)
      const label = `${isCollapsed ? '▸' : '▾'} ${title}`
      return (
        <Box key={key} flexDirection="column" borderStyle="round" borderColor={color} paddingX={1}>
          <Box key={`${key}-head`} flexDirection="row" justifyContent="space-between">
            {S.canUnderline ? (
              <Button key={`${key}-title`} label={label} plain hover={{ bold: true }} onPress={() => toggle(key)}>
                <Text color={color} bold>
                  {label}
                </Text>
              </Button>
            ) : (
              <Button key={`${key}-title`} label={label} plain hover={{ bold: true }} onPress={() => toggle(key)} />
            )}
            {headline}
          </Box>
          {isCollapsed ? body.filter(part => part === actions) : body}
        </Box>
      )
    }
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
    const groups = agentGroups(all, [...S.waits.values()].flatMap(wait => (wait.agentId === null ? [] : [wait.agentId])))
    const shownItems = planWindow(items, 8)
    const sortedSeats = [...list].sort((a, b) => totalIn(b) - totalIn(a))
    const mostIn = Math.max(1, ...sortedSeats.map(totalIn))
    const breakdownShown = (rows?.rows ?? []).slice(0, Math.max(0, Math.min(MAX_BREAKDOWN_ROWS, o.breakdownRows)))
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
    const turnsLeft = head === null ? null : turnsToBudget(await read($, turnTokens), head.limit)
    // Why the plan section reads checkout paths rather than the roots.
    const rootsLine = rootsNow !== null && (
      <Text key="plan-roots" color="red" wrap="truncate-end">
        {rootsNow}
      </Text>
    )
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
        rootsLine,
        finishNow !== null && finishLine(finishNow).length > 0 && (
          <Text key="plan-finish" wrap="truncate-end">
            {drawRuns('plan-finish-runs', finishLine(finishNow))}
          </Text>
        ),
        runList(summary.tasks, 6).map(task => {
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
    // How far each gauged window has run, for the usage panel's note.
    const gaugedPace = GAUGED.flatMap(kind =>
      limits
        .filter(limit => limit.kind === kind)
        .flatMap(limit => {
          const gone = windowElapsed(limit.kind, limit.resetsAt, now)
          return gone === null ? [] : [`${Math.round(gone * 100)}% of ${limitLabel(limit.kind)}`]
        }),
    )
    const byName: Record<Section, RenderChildren> = {
      // Who the session runs as, framed in the account's color.
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
              <Text>{clip(shell.command.split('\n')[0]!, Math.max(10, inner - 10))}</Text>
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
          {finished.length > failedCount && <Text color="green">✓ {finished.length - failedCount} </Text>}
          {failedCount > 0 && <Text color="red">✗ {failedCount}</Text>}
        </Text>,
        all.length === 0 && (
          <Text key="agents-none" dimColor>
            No subagents yet.
          </Text>
        ),
        groups.flatMap(group => [
          <Text key={`agents-${group.key}`} color={AGENT_MARKS[group.key].color} bold>
            {`${group.name} · ${group.spawns.length}`}
          </Text>,
          ...group.spawns.map(spawn => (
            <Text key={`spawn-${spawn.agentId}`} wrap="truncate-end">
              <Text color={AGENT_MARKS[group.key].color}>{AGENT_MARKS[group.key].mark} </Text>
              <Text bold={!spawn.isDone} dimColor={spawn.isDone}>
                {shortSeat(spawn.seat)}
              </Text>
              <Text dimColor={spawn.isDone}> {spawn.description}</Text>
              {!spawn.isDone && <Text color="cyan"> {elapsed(now - spawn.startedAt)}</Text>}
            </Text>
          )),
        ]),
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
      // In a dforge run the card reads the run's ledger instead: the
      // round in flight, reviews that came back clean, and blocked tasks.
      plan:
        summary !== null && summary.total > 0 ? (
          runCard()
        ) : items.length > 0 ? (
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
          finishNow !== null && finishLine(finishNow).length > 0 && (
            <Text key="plan-finish" wrap="truncate-end">
              {drawRuns('plan-finish-runs', finishLine(finishNow))}
            </Text>
          ),
          rootsLine,
        )
        ) : (
          (rootsLine !== false || (finishNow !== null && finishLine(finishNow).length > 0)) &&
          section(
            'plan',
            'Plan',
            rootsLine !== false ? 'red' : 'yellow',
            <Text key="plan-head" dimColor>
              {rootsLine !== false ? 'checkout paths' : 'no plan'}
            </Text>,
            finishNow !== null && finishLine(finishNow).length > 0 && (
              <Text key="plan-finish" wrap="truncate-end">
                {drawRuns('plan-finish-runs', finishLine(finishNow))}
              </Text>
            ),
            rootsLine,
          )
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
          placeNow !== null && placeNow.root !== null && (
            <Text key="repo-name" wrap="truncate-end">
              <Text dimColor>repo </Text>
              <Text bold>{repoName(placeNow.remote ?? null, placeNow.root)}</Text>
            </Text>
          ),
          placeNow !== null && (
            <Text key="repo-cwd" wrap="truncate-start">
              <Text dimColor>dir  </Text>
              {drawRuns('repo-cwd-runs', folderRuns(placeNow.cwd, placeNow.root, placeNow.home))}
            </Text>
          ),
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

    if (isDesktop) {
      // The flight deck: the account, what Claude is doing, then gauges for
      // the context and the two usage windows, then a panel per section. A
      // panel's rows are the desktop's own text in its theme's colors, its
      // charts drawings; its title collapses it as the terminal's does.
      const width = svgWidth(inner)
      const panel = (key: Section, title: string, lamp: string, right: PanelRun[], lines: PanelLine[], ...native: RenderChildren[]) => {
        const isCollapsed = o.shownCollapsed.includes(key)
        const label = `${isCollapsed ? '▸' : '▾'} ${title}`
        return (
          <Box key={key} flexDirection="column" borderStyle="round" borderColor="subtle" backgroundColor={CARD} paddingX="md" paddingY="sm" gap="xs">
            <Box key={`${key}-head`} flexDirection="row" justifyContent="space-between" alignItems="center" columnGap="sm">
              <Button key={`${key}-title`} label={label} plain onPress={() => toggle(key)}>
                <Text size="heading" weight="semibold" color={themeColor(lamp)}>
                  {label}
                </Text>
              </Button>
              <Box key={`${key}-headline`} flexShrink={1}>
                <Text size="footnote" wrap="truncate-end">
                  {right.map((run, index) => nativeRun(table, `${key}-headline-${index}`, { ...run, dim: run.color === undefined ? true : run.dim }))}
                </Text>
              </Box>
            </Box>
            {!isCollapsed && lines.map((line, index) => nativeLine(table, `${key}-line-${index}`, line))}
            {native.length > 0 && (
              <Box key={`${key}-native`} flexDirection="column">
                {native}
              </Box>
            )}
          </Box>
        )
      }
      const panels: Record<Section, RenderChildren> = {
        account: who !== null && panel('account', 'Account', tint ?? 'blue', [{ text: billing ?? '' }], [
          {
            kind: 'badge',
            svg: avatarSvg(who.name ?? who.email ?? '?', tint, 28),
            lines: [
              [{ text: who.email ?? 'not signed in', bold: true }],
              [{ text: [who.name, who.organization].filter(Boolean).join(' · ') + (who.role !== null ? ` (${who.role})` : ''), dim: true }],
            ],
          },
          {
            kind: 'chips',
            chips: [
              ...(engineNow.model !== null ? [pill(modelName(engineNow.model), 'cyan')] : []),
              ...(engineNow.model !== null && engineNow.effort !== null ? [pill(`${engineNow.effort} effort`)] : []),
              (() => {
                const runs = remoteRuns(remoteNow.clients, remoteNow.setting)
                const isOn = runs.some(run => run.color === 'green')
                return { text: `Remote ${runs.map(run => run.text).join('')}`, color: isOn ? 'green' : undefined, dim: !isOn, chip: true }
              })(),
              { text: `config ${who.key}`, dim: true, chip: true },
            ],
          },
        ]),
        context: (() => {
          if (head === null) return panel('context', 'Context', 'cyan', [{ text: 'no reading yet' }], [], actions)
          const percent = (head.tokens / head.limit) * 100
          const compactAt = rows?.compactAt ?? null
          const lines: PanelLine[] = [
            {
              kind: 'picture',
              svg: labelledMeterSvg(
                head.tokens / head.window,
                width,
                rampColor(percent),
                [...(compactAt === null ? [] : [{ at: compactAt / head.window, isDashed: true }]), { at: head.limit / head.window }],
                // The ends are placed first, so the handoff slides clear of them.
                [
                  { at: 0, text: `${kTokens(head.tokens)} / ${kTokens(head.window)}` },
                  ...(compactAt === null ? [] : [{ at: compactAt / head.window, text: `compacts ${kTokens(compactAt)}` }]),
                  { at: head.limit / head.window, text: `handoff ${kTokens(head.limit)}`, color: rampColor(percent) },
                ],
              ),
              alt: `${kTokens(head.tokens)} of ${kTokens(head.window)} tokens, handoff at ${kTokens(head.limit)}`,
            },
          ]
          if (readings.length > 1) {
            const change = (readings[readings.length - 1] ?? 0) - (readings[readings.length - 2] ?? 0)
            const count = Math.min(24, readings.length)
            const label = `${change >= 0 ? '+' : '−'}${kTokens(Math.abs(change))}`
            lines.push({
              kind: 'picture',
              svg: trendSvg(readings.slice(-24), width, 'cyan', 40, { top: `${label} · ${count} turns` }),
              alt: `Context over the last ${count} readings, ${label} on the last`,
            })
          }
          if (breakdownShown.length > 0) {
            const colorOf = (index: number) => BREAKDOWN_COLORS[index % BREAKDOWN_COLORS.length] ?? BREAKDOWN_COLORS[0]
            const used = breakdownShown.reduce((sum, row) => sum + row.tokens, 0)
            lines.push({ kind: 'picture', svg: stackSvg(breakdownShown.map(row => row.tokens), breakdownShown.map((_, index) => colorOf(index)), width, 8) })
            for (const [index, row] of breakdownShown.entries()) {
              lines.push({
                kind: 'text',
                left: [{ text: '■ ', color: paint(colorOf(index)) }, { text: row.name }],
                right: [{ text: kTokens(row.tokens), bold: true }, { text: `${String(Math.round((row.tokens / Math.max(1, used)) * 100)).padStart(4)}%`, dim: true, mono: true }],
              })
            }
          }
          return panel('context', 'Context', 'cyan', [{ text: `${kTokens(head.tokens)} of ${kTokens(head.window)}` }], lines, actions)
        })(),
        usage: panel(
          'usage',
          'Usage',
          'blue',
          [{ text: [cost, head?.usd == null ? '' : costRate(head.usd, spend?.startedAt, now).replace(/^ · /, '')].filter(Boolean).join(' · ') }],
          [
            ...(limits.length === 0 ? [{ kind: 'text', left: [{ text: 'No limit reading yet.', dim: true }] } as PanelLine] : []),
            // A window with no gauge (a gateway's spend limit) keeps its meter here.
            ...limits
              .filter(limit => !GAUGED.includes(limit.kind))
              .flatMap((limit): PanelLine[] => [
                { kind: 'text', left: [{ text: limitLabel(limit.kind), dim: true }], right: [{ text: `${Math.round(limit.percent)}%`, color: rampColor(limit.percent), bold: true }] },
                { kind: 'picture', svg: meterSvg(limit.percent / 100, width, rampColor(limit.percent)) },
                ...(limit.resetsAt === null ? [] : [{ kind: 'text', small: true, left: [{ text: `resets in ${duration(limit.resetsAt - now) || 'now'}`, dim: true }] } as PanelLine]),
              ]),
            ...(gaugedPace.length > 0 ? [{ kind: 'text', small: true, wrap: true, left: [{ text: `The gauges' ticks mark how far each window has run: ${gaugedPace.join(', ')}.`, dim: true }] } as PanelLine] : []),
          ],
        ),
        shells:
          background.length > 0 &&
          panel(
            'shells',
            'Shells',
            'yellow',
            [{ text: `${background.length} running` }],
            background.map(shell => ({ kind: 'text', left: [{ text: `$ ${shell.command.split('\n')[0]}`, mono: true }], right: [{ text: elapsed(now - shell.startedAt), mono: true, dim: true }] })),
          ),
        agents: panel(
          'agents',
          'Agents',
          'magenta',
          [{ text: [running.length > 0 ? `${running.length} running` : '', finished.length > failedCount ? `${finished.length - failedCount} done` : '', failedCount > 0 ? `${failedCount} failed` : ''].filter(Boolean).join(' · ') }],
          [
            ...(all.length === 0 ? [{ kind: 'text', left: [{ text: 'No subagents yet.', dim: true }] } as PanelLine] : []),
            ...groups.flatMap((group): PanelLine[] => [
              { kind: 'text', small: true, left: [{ text: `${group.name} · ${group.spawns.length}`, color: AGENT_MARKS[group.key].color, bold: true }] },
              ...group.spawns.map(
                (spawn): PanelLine => ({
                  kind: 'text',
                  left: [
                    { text: `${AGENT_MARKS[group.key].mark}  `, color: AGENT_MARKS[group.key].color },
                    pill(shortSeat(spawn.seat)),
                    { text: `  ${spawn.description}`, dim: spawn.isDone },
                  ],
                  right: spawn.isDone ? [] : [{ text: elapsed(now - spawn.startedAt), mono: true, dim: true }],
                }),
              ),
            ]),
            // Each seat's counts over a bar of its input, the part served from
            // the prompt cache lighter.
            ...sortedSeats.flatMap((seat): PanelLine[] => [
              {
                kind: 'text',
                small: true,
                left: [{ text: shortSeat(seat.seat) }, { text: ` ×${seat.runs}`, dim: true }],
                right: [{ text: `${kTokens(totalIn(seat))} in · ${cacheShare(seat)}% cached · ${kTokens(seat.output)} out`, mono: true, dim: true }],
              },
              { kind: 'picture', svg: seatSvg(totalIn(seat) / mostIn, cacheShare(seat) / 100, width, 'magenta') },
            ]),
          ],
        ),
        plan: (() => {
          if (summary !== null && summary.total > 0) {
            const blocked = summary.tasks.filter(task => task.state === 'blocked')
            const round = runRound(summary)
            const lines: PanelLine[] = [{ kind: 'picture', svg: segmentsSvg(summary.tasks.map(task => RUN_SEGMENTS[task.state] ?? 'todo'), width, 6) }]
            if (summary.plan !== null) lines.push({ kind: 'text', small: true, left: [{ text: summary.plan, mono: true, dim: true }] })
            if (rootsNow !== null) lines.push({ kind: 'text', small: true, left: [{ text: rootsNow, color: 'red' }] })
            if (finishNow !== null && finishLine(finishNow).length > 0) lines.push({ kind: 'chips', chips: [{ ...pill(finishLine(finishNow).map(run => run.text).join('')), color: 'yellow' }] })
            for (const task of runList(summary.tasks, 6)) {
              const label = `Task ${task.n}${task.title === '' ? '' : `: ${task.title}`}`
              const meta =
                task.state === 'complete' ? (task.isClean ? 'reviewed clean' : null)
                : task.state === 'blocked' ? `BLOCKED${task.reason === null ? '' : ` · ${task.reason}`}`
                : task.state === 'assigned' && (task.round !== null || task.seat !== null)
                  ? [task.round === null ? 'implementing' : `round ${task.round}`, task.seat === null ? null : shortSeat(task.seat)].filter(Boolean).join(' · ')
                  : null
              const icon: PanelRun =
                task.state === 'complete' ? { text: '✓', color: 'green' }
                : task.state === 'blocked' ? { text: '✗', color: 'red' }
                : task.state === 'assigned' ? { text: '▸', color: 'blue' }
                : { text: '○', faint: true }
              lines.push({
                kind: 'text',
                left: [
                  { ...icon, text: `${icon.text}  ` },
                  { text: label, bold: task.state === 'assigned' || task.state === 'blocked', color: task.state === 'blocked' ? 'red' : undefined, dim: task.state === 'pending' },
                ],
              })
              if (meta !== null) lines.push({ kind: 'text', small: true, indent: 18, left: [{ text: meta, color: task.state === 'blocked' ? 'red' : undefined, dim: task.state !== 'blocked' }] })
            }
            if (summary.isFinished) lines.push({ kind: 'text', left: [{ text: 'Final review clean.', color: 'green' }] })
            return panel(
              'plan',
              'Run',
              blocked.length > 0 ? 'red' : 'yellow',
              [...(blocked.length > 0 ? [{ text: `${blocked.length} blocked · `, color: 'red' }] : []), { text: [round === null ? '' : `round ${round}`, `${summary.done}/${summary.total}`].filter(Boolean).join(' · ') }],
              lines,
            )
          }
          const finishChips: PanelLine[] = finishNow !== null && finishLine(finishNow).length > 0 ? [{ kind: 'chips', chips: [{ ...pill(finishLine(finishNow).map(run => run.text).join('')), color: 'yellow' }] }] : []
          if (items.length === 0) {
            return (rootsNow !== null || finishChips.length > 0) && panel('plan', 'Plan', rootsNow !== null ? 'red' : 'yellow', [{ text: rootsNow !== null ? 'checkout paths' : 'no plan' }], [
              ...finishChips,
              ...(rootsNow !== null ? [{ kind: 'text', small: true, left: [{ text: rootsNow, color: 'red' }] } as PanelLine] : []),
            ])
          }
          return panel('plan', 'Plan', 'yellow', [{ text: `${doneCount}/${items.length}` }], [
            { kind: 'picture', svg: segmentsSvg(items.map(item => (item.status === 'completed' ? 'done' : item.status === 'in_progress' ? 'active' : 'todo')), width, 6) },
            ...shownItems.map(
              (item): PanelLine => ({
                kind: 'text',
                left: [
                  item.status === 'completed' ? { text: '✓  ', color: 'green' } : item.status === 'in_progress' ? { text: '▸  ', color: 'blue' } : { text: '○  ', faint: true },
                  { text: item.text, dim: item.status === 'completed', bold: item.status === 'in_progress' },
                ],
              }),
            ),
            ...finishChips,
            ...(rootsNow !== null ? [{ kind: 'text', small: true, left: [{ text: rootsNow, color: 'red' }] } as PanelLine] : []),
          ])
        })(),
        repo:
          git !== null &&
          panel(
            'repo',
            'Repo',
            'green',
            [{ text: git.changed + git.untracked === 0 ? '● clean' : '● dirty', color: git.changed + git.untracked === 0 ? 'green' : 'yellow' }],
            [
              ...(placeNow !== null && placeNow.root !== null ? [{ kind: 'text', left: [{ text: repoName(placeNow.remote ?? null, placeNow.root), bold: true }] } as PanelLine] : []),
              ...(placeNow !== null
                ? [{ kind: 'text', small: true, left: folderRuns(placeNow.cwd, placeNow.root, placeNow.home).map(run => ({ ...run, mono: true, color: undefined, faint: run.dim, dim: false })) } as PanelLine]
                : []),
              {
                kind: 'chips',
                chips: [
                  pill(`⎇ ${git.branch}`, 'magenta'),
                  ...(git.ahead > 0 ? [pill(`↑${git.ahead}`, 'green')] : []),
                  ...(git.behind > 0 ? [pill(`↓${git.behind}`, 'red')] : []),
                  ...(git.changed > 0 ? [pill(`~${git.changed} changed`, 'yellow')] : []),
                  ...(git.untracked > 0 ? [pill(`?${git.untracked} untracked`)] : []),
                ],
              },
            ],
          ),
        guard:
          refused.length > 0 &&
          panel(
            'guard',
            'Guard',
            'red',
            [{ text: `${refused.length} refused`, color: 'red' }],
            refused.slice(-3).map(refusal => ({ kind: 'text', left: [{ text: '✗  ', color: 'red' }, { text: refusal.tool }, { text: `: ${refusal.line}`, dim: true }] })),
          ),
      }
      const gauged = GAUGED.flatMap(kind => limits.filter(limit => limit.kind === kind))
      const tiles: { dial: string; key: string; notes: PanelRun[][]; alt: string }[] = []
      if (head !== null) {
        const share = head.tokens / head.limit
        tiles.push({
          dial: gaugeSvg(share, rampColor(share * 100), 120, `${Math.round(share * 100)}%`, null, true),
          key: 'Context',
          alt: `${Math.round(share * 100)}% of the handoff budget`,
          notes: [[{ text: `of handoff${turnsLeft === null ? '' : ` · ≈${turnsLeft} ${turnsLeft === 1 ? 'turn' : 'turns'}`}`, color: turnsLeft !== null && turnsLeft <= 3 ? 'warning' : undefined }]],
        })
      }
      for (const limit of gauged) {
        const forecast = limitForecast(limit.kind, limit.percent, limit.resetsAt, now)
        tiles.push({
          dial: gaugeSvg(limit.percent / 100, rampColor(limit.percent), 90, `${Math.round(limit.percent)}%`, windowElapsed(limit.kind, limit.resetsAt, now), true),
          key: limitLabel(limit.kind),
          alt: `${limitLabel(limit.kind)} limit ${Math.round(limit.percent)}% used`,
          notes: [
            ...(limit.resetsAt === null ? [] : [[{ text: `resets ${duration(limit.resetsAt - now) || 'now'}` }]]),
            ...(forecast === 'pace' ? [[{ text: 'on pace', color: 'green' }]] : []),
            ...(typeof forecast === 'number' ? [[{ text: `out in ${duration(forecast) || '<1m'}`, color: 'yellow' }]] : []),
          ],
        })
      }
      // The gauges sit in framed tiles that line up with the panels: a row of
      // tiles fills the body exactly (frames, padding and gaps included), and
      // a body too narrow for every dial puts the context on its own row, then
      // each tile on its own.
      const share = (tile: (typeof tiles)[number]) => (tile.key === 'Context' ? 1.35 : 1)
      const least = (tile: (typeof tiles)[number]) => (tile.key === 'Context' ? 16 : 12) + 5
      const fits = (row: typeof tiles) => {
        const total = row.reduce((sum, tile) => sum + share(tile), 0)
        return row.every(tile => Math.floor(((room - row.length + 1) * share(tile)) / total) >= least(tile))
      }
      const gaugeRows = fits(tiles) ? [tiles] : tiles[0]?.key === 'Context' && fits(tiles.slice(1)) ? [tiles.slice(0, 1), tiles.slice(1)] : tiles.map(tile => [tile])
      // Tiles grow from nothing by their shares, so they split whatever the
      // row really measures; each drawing is sized from the columns a tile
      // gets, a column short to leave slack for rounding.
      const gaugeRow = (row: typeof tiles, at: number) => {
        const avail = room - row.length + 1
        const total = row.reduce((sum, tile) => sum + share(tile), 0)
        return (
          <Box key={`gauges-${at}`} flexDirection="row" columnGap={1}>
            {row.map(tile => (
              <Box key={`gauge-${tile.key}`} width={0} flexGrow={share(tile)} flexDirection="column" alignItems="center" borderStyle="round" borderColor="subtle" backgroundColor={CARD} paddingX={1}>
                {picture(
                  `gauge-${tile.key}-dial`,
                  gaugeTileSvg(tile, Math.round((Math.floor((avail * share(tile)) / total) - 5) * CELL_PX)),
                  [tile.alt, ...tile.notes.map(note => note.map(run => run.text).join(''))].join(', '),
                )}
              </Box>
            ))}
          </Box>
        )
      }
      return (
        <Box flexDirection="column" gap="md">
          {resumeCard}
          {o.shown.includes('account') && panels.account}
          <Box key="now-row" flexDirection="row" alignItems="center" columnGap={1}>
            <Box key="now-box" flexGrow={1} flexShrink={1}>
              <Text key="now" wrap="truncate-end">
                {drawRuns('now', nowLine(actNow, now))}
              </Text>
            </Box>
            {button('pane-minimize', 'Minimize', minimize, { hotkey: 'm' })}
          </Box>
          {tiles.length > 0 && (
            <Box key="gauges" flexDirection="column" gap="md">
              {gaugeRows.map(gaugeRow)}
            </Box>
          )}
          {o.shown.filter(name => name !== 'account').map(name => panels[name])}
          {!o.shown.includes('context') && actions}
        </Box>
      )
    }

    return (
      <Box flexDirection="column">
        {resumeCard}
        <Text key="now" wrap="truncate-end">
          {drawRuns('now', nowLine(actNow, now))}
        </Text>
        {o.shown.map(name => byName[name])}
        {!o.shown.includes('context') && actions}
      </Box>
    )
  })

  // Minimized, the band sits above the prompt in place of the pane. A handoff
  // to resume rides above it, or alone while the pane is open.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const o = await live($)
    const offer = await offerNow($, await $.clock.now())
    const band = o.isMinimized ? await drawBand($, e, () => expand($, e.viewport?.isFullscreen === true)) : null
    if (offer === null) return band ?? next(e)
    const { Box } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {await drawResumeBand($, e, offer)}
        {band}
      </Box>
    )
  })
}

/** One framed line above the prompt: the handoff to resume, Resume and Dismiss. */
async function drawResumeBand($: EngineInterface, e: RenderInput<'AbovePrompt'>, offer: CockpitResumeOffer) {
  const { Box, Button, Text } = $.ui.resolve(e)
  // No hotkeys: the prompt holds the focus here, and a letter would be typed.
  return (
    <Box key="resume-band" flexDirection="row" alignItems="center" columnGap={1} borderStyle="round" borderColor={BUTTON_MAIN} paddingX={1}>
      <Box key="resume-band-text" flexGrow={1} flexShrink={1}>
        <Text key="resume-band-line" wrap="truncate-end">
          <Text color={BUTTON_MAIN} bold>
            {`↻ Resumable work · ${handedOff((await $.clock.now()) - offer.at)}`}
          </Text>
          <Text dimColor>{` — Next: ${offer.next}`}</Text>
        </Text>
      </Box>
      <Button key="band-resume" label="Resume" variant="primary" onPress={() => resume($, offer)} />
      <Button key="band-resume-dismiss" label="Dismiss" plain dimColor hover={{ bold: true }} onPress={() => update($, resumeDismissed, () => offer.at)} />
    </Box>
  )
}

const pill = (text: string, color?: string): PanelRun => ({ text, color, chip: true })

// Each Agents group's mark and color, on its title and its rows.
const AGENT_MARKS: Record<AgentGroupKey, { mark: string; color: string }> = {
  waiting: { mark: '⏳', color: 'yellow' },
  working: { mark: '●', color: 'cyan' },
  failed: { mark: '✗', color: 'red' },
  done: { mark: '✓', color: 'green' },
}

/** The minimized cockpit's band, drawn in the pane or above the prompt. */
async function drawBand($: EngineInterface, e: RenderInput<'Pane' | 'AbovePrompt'>, onExpand: () => unknown) {
  const table = $.ui.resolve(e)
  const { Box, Button, Text } = table
  const Svg = e.surface === 'desktop' && 'Svg' in table ? table.Svg : undefined
  const isDesktop = Svg !== undefined
  const now = await $.clock.now()
  const room = e.props.bodyColumns
  const head = await read($, budget)
  const limits = (await read($, usage))?.limits ?? []
  const running = (await read($, spawns)).filter(one => !one.isDone)
  const background = await read($, shells)
  const remoteNow = await read($, remote)
  const git = await read($, repo)
  const refused = await read($, refusals)
  const summary = await read($, run)
  const who = await read($, account)
  const tint = termColor(who?.color)
  const billing = billingLabel(who?.billing ?? null)
  const drawRuns = (key: string, runs: Run[]) =>
    runs.map((one, index) => (
      <Text key={`${key}-${index}`} color={one.color} bold={one.bold} dimColor={one.dim}>
        {one.text}
      </Text>
    ))
  const picture = (key: string, source: string, alt: string) => Svg !== undefined && <Svg key={key} source={source} alt={alt} />
  // The band: the account on the top rule, then the readings with their
  // pace, then what runs beside the turn and where. Each line shrinks on
  // its own until it fits.
  const where = await read($, place)
  const turnsNow = head === null ? null : turnsToBudget(await read($, turnTokens), head.limit)
  const band: BandInput = {
    cwd: where?.cwd ?? null,
    root: where?.root ?? null,
    home: where?.home ?? null,
    repo: git,
    context: head === null ? null : { tokens: head.tokens, limit: head.limit, window: head.window },
    turnsLeft: turnsNow,
    limits: GAUGED.flatMap(kind => limits.filter(limit => limit.kind === kind)),
    agents: running.length,
    shells: { count: background.length, longest: background.reduce((most, shell) => Math.max(most, now - shell.startedAt), 0) },
    now,
  }
  const blocked = summary?.tasks.filter(task => task.state === 'blocked') ?? []
  const warning: Run[] = [
    ...(blocked.length === 0
      ? []
      : [{ text: '✗ ', color: 'red', bold: true }, { text: blocked.length === 1 ? `Task ${blocked[0]?.n} blocked` : `${blocked.length} tasks blocked`, color: 'red' }]),
    ...(blocked.length > 0 && refused.length > 0 ? [{ text: '  ·  ', dim: true }] : []),
    ...(refused.length === 0 ? [] : [{ text: '✗ ', color: 'red', bold: true }, { text: `${refused.length} refused`, color: 'red' }]),
  ]
  const remoteBand: Run[] =
    remoteNow.clients.length > 0
      ? [{ text: 'Remote ● ', color: 'green' }, { text: 'connected', color: 'green' }]
      : remoteNow.setting === 'true'
        ? [{ text: 'Remote ○ on', color: 'green' }]
        : [{ text: 'Remote ○ not connected', dim: true }]

  if (isDesktop) {
    const w = svgWidth(room - 4)
    const meters: BandMeter[] = [
      ...(head === null
        ? []
        : [
            {
              key: 'Context',
              percent: (head.tokens / head.limit) * 100,
              share: head.tokens / head.window,
              color: rampColor((head.tokens / head.limit) * 100),
              tick: head.limit / head.window,
              note: turnsNow === null ? [] : [{ text: `≈${turnsNow} ${turnsNow === 1 ? 'turn' : 'turns'}`, color: turnsNow <= 3 ? 'warning' : undefined }],
            },
          ]),
      ...band.limits.map((limit): BandMeter => {
        const forecast = limitForecast(limit.kind, limit.percent, limit.resetsAt, now)
        return {
          key: limitLabel(limit.kind),
          percent: limit.percent,
          share: limit.percent / 100,
          color: rampColor(limit.percent),
          tick: windowElapsed(limit.kind, limit.resetsAt, now),
          note:
            forecast === 'pace'
              ? [{ text: 'on pace', color: 'green' }]
              : typeof forecast === 'number'
                ? [{ text: `out in ${duration(forecast) || '<1m'}`, color: 'yellow' }]
                : limit.resetsAt === null
                  ? []
                  : [{ text: `resets ${duration(limit.resetsAt - now) || 'now'}` }],
        }
      }),
    ]
    const facts: PanelRun[] = [
      ...(running.length === 0 ? [] : [{ text: '● ', color: 'green' }, { text: `${running.length} ${running.length === 1 ? 'agent' : 'agents'} running` }, { text: '   ' }]),
      ...(background.length === 0
        ? []
        : [{ text: '$ ', color: 'yellow', mono: true }, { text: `${background.length} ${background.length === 1 ? 'shell' : 'shells'}` }, { text: ` · longest ${shellAge(band.shells.longest)}`, dim: true }, { text: '   ' }]),
      ...(where === null ? [] : [{ text: where.root === null ? (where.cwd.split(/[\\/]/).pop() ?? where.cwd) : repoName(where.remote ?? null, where.root), bold: true }]),
    ]
    const chips: PanelRun[] =
      git === null
        ? []
        : [
            pill(`⎇ ${git.branch}${git.ahead > 0 ? ` ↑${git.ahead}` : ''}${git.behind > 0 ? ` ↓${git.behind}` : ''}`, 'magenta'),
            ...(git.changed > 0 ? [pill(`~${git.changed} changed`, 'yellow')] : []),
            ...(git.untracked > 0 ? [pill(`?${git.untracked} untracked`)] : []),
          ]
    const head0: PanelLine[] = [
      {
        kind: 'text',
        left: [
          { text: who?.email ?? 'not signed in', bold: true },
          ...(billing === null ? [] : [{ text: ` · ${billing}`, dim: true }]),
          { text: '  ' },
          pill(remoteBand.map(run => run.text).join(''), remoteNow.clients.length > 0 || remoteNow.setting === 'true' ? 'green' : undefined),
        ],
      },
    ]
    const rest: PanelLine[] = [
      ...(facts.length > 0 ? [{ kind: 'text', left: facts } as PanelLine] : []),
      ...(chips.length > 0 ? [{ kind: 'chips', chips } as PanelLine] : []),
      ...(warning.length > 0 ? [{ kind: 'text', left: warning.map(run => ({ ...run, color: run.color === undefined ? undefined : 'red' })) } as PanelLine] : []),
    ]
    return (
      <Box key="band" flexDirection="column" borderStyle="round" borderColor="subtle" backgroundColor={CARD} paddingX={1}>
        <Box key="band-top" flexDirection="row" alignItems="center" columnGap={1}>
          <Box key="band-who" flexGrow={1} flexShrink={1}>
            {head0.map((line, index) => nativeLine(table, `band-who-${index}`, line))}
          </Box>
          <Button key="band-expand" label="Expand" hotkey="e" onPress={onExpand} />
        </Box>
        {meters.length > 0 && (
          <Box key="band-meters" paddingX={1}>
            {picture(
              'band-meters-line',
              bandMetersSvg(meters, w - 18),
              meters.map(meter => [`${meter.key} ${Math.round(meter.percent)}%`, ...meter.note.map(run => run.text)].join(', ')).join('\n'),
            )}
          </Box>
        )}
        {rest.map((line, index) => nativeLine(table, `band-rest-${index}`, line))}
      </Box>
    )
  }

  const isFramed = room >= FRAME_MIN_COLUMNS
  const width = isFramed ? room - 4 : room
  const [one, two] = fitBand(band, width)
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
  // A bare button on the top rule, so the band keeps its height.
  const expand = <Button key="band-expand" label="Expand" plain hover={{ bold: true }} onPress={onExpand} />
  const email = who?.email ?? ''
  // What rides on the top rule, dropped from the end while it does not fit;
  // only the parts that are known are joined.
  const joined = (parts: Run[][]): Run[] => parts.flatMap((runs, index) => (index === 0 ? runs : [{ text: ' · ', dim: true }, ...runs]))
  const emailPart: Run[][] = email === '' ? [] : [[{ text: email, bold: true }]]
  const billingPart: Run[][] = billing === null ? [] : [[{ text: billing, dim: true }]]
  const remotePart: Run[][] = remoteBand.length === 0 ? [] : [remoteBand]
  const tops: Run[][] = [
    joined([...emailPart, ...billingPart, ...remotePart]),
    joined([...emailPart, ...remotePart]),
    joined(emailPart),
    [],
  ]
  // "╭─ " + top + " " + dashes + " Expand ─╮"
  const room0 = room - 3 - 1 - 1 - 6 - 3
  const top = tops.find(runs => runsWidth(runs) <= room0 - 1) ?? []
  const dashes = Math.max(1, room0 - runsWidth(top) - (top.length > 0 ? 0 : -1))
  const lines = [one, two].filter(line => line.length > 0)

  return (
    <Box flexDirection="column">
      {isFramed ? (
        <Box key="frame-top" flexDirection="row">
          <Text key="frame-top-left" color={tint} wrap="truncate-end">
            {top.length > 0 ? '╭─ ' : '╭─'}
            {top.length > 0 && drawRuns('frame-top-runs', top)}
            {top.length > 0 ? ' ' : ''}
            {'─'.repeat(dashes)}{' '}
          </Text>
          {expand}
          <Text key="frame-top-right" color={tint}>
            {' ─╮'}
          </Text>
        </Box>
      ) : (
        <Box key="band-head" flexDirection="row" columnGap={1}>
          <Text key="band-email" color={tint} bold wrap="truncate-end">
            {email}
          </Text>
          {expand}
        </Box>
      )}
      {lines.map((line, index) => row(`band-${index + 1}`, line))}
      {warning.length > 0 && row('band-warning', warning)}
      {isFramed && (
        <Text key="frame-bottom" color={tint} wrap="truncate-end">
          {'╰' + '─'.repeat(Math.max(0, room - 2)) + '╯'}
        </Text>
      )}
    </Box>
  )
}

// What the hooks share beyond $.state: settings read at load, facts read at
// the start, and the timers and S.waits in flight. A reload starts it over.
const S = {
  // Saved or environment values the settings in force ignored, for the settings view.
  settingProblems: [] as string[],
  // Keys something outside the settings file forces, with the words their rows show.
  locks: {} as Record<string, string>,
  // Skill-enforced settings changed since the model was last told, with their new values.
  changed: {} as Record<string, SettingValue>,
  // Claude keys this session saved: the engine's settings snapshot may not show another process's write at once.
  claudeSaved: {} as Record<string, SettingValue | undefined>,
  kinds: [] as NotifyKind[],
  isBrief: false,
  notifyAskAfter: 20,
  where: { host: null, tmux: null, primary: null } as {
    host: string | null
    tmux: string | null
    primary: string | null
  },
  // An approval or question the person has not answered yet, by tool call: its
  // timer, the Discord message sent for it (edited once it is answered), and
  // the subagent whose approval it is.
  waits: new Map<string, { timer: Timer | null; messageId: string | null; event: NotifyEvent; agentId: string | null }>(),
  ticker: null as Timer | null,
  isTurnLive: false,
  isBudgetSent: false,
  // Ledger events already seen, so a reload or a re-read sends nothing twice.
  ledgerSeen: null as Set<string> | null,
  isUnattended: false,
  // Whether this Claude Code draws a Button's label from styled children,
  // so the hotkey's letter can be underlined in it.
  canUnderline: null as boolean | null,
  // The person closed the pane this session: a desktop joining reopens nothing.
  isClosedByPerson: false,
  // The auto run's scheduled stage, at most one.
  autoTimer: null as Timer | null,
  // When background work began deferring the pending stage; null while nothing does.
  autoDeferredSince: null as number | null,
  // The watchdog's timer, every WATCHDOG_MS.
  watchdog: null as Timer | null,
  // The roots --mode last named, and the primary checkout and stores.json
  // modification time they were read for.
  roots: { key: '', value: null } as { key: string; value: CockpitRoots | null },
  // latest.md's absolute path while progress is in darkmem; null while it is
  // in the checkout, where the resume prompt names it by its state directory.
  latestName: null as string | null,
  // The latest.md path and modification time the resume offer was read for.
  offerRead: '',
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
  // A failed send shows in the settings' Discord row, never as a pop-up.
  await update($, notifier, now => ({ ...now, last: { at: stamp, text: sent.reason, isError: true } }))
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
}

// The pane's clock: a redraw a second while a turn runs, a background shell
// runs or a subagent works, so their timers count seconds.
async function syncTicker($: EngineInterface) {
  const now = await read($, activity)
  S.isTurnLive = now.kind === 'running' || now.kind === 'waiting' || now.kind === 'asking'
  const isTicking =
    S.isTurnLive || (await read($, shells)).length > 0 || (await read($, spawns)).some(one => !one.isDone)
  if (isTicking && S.ticker === null) {
    S.ticker = $.clock.every(1000, () => $.ui.invalidate('ui.render'))
  } else if (!isTicking && S.ticker !== null) {
    S.ticker.cancel()
    S.ticker = null
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
async function startWait($: EngineInterface, id: string, kind: 'waiting' | 'asking', event: NotifyEvent, agentId: string | null) {
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
  S.waits.set(id, { timer: delay === 0 ? null : $.clock.after(delay, () => void send()), messageId: null, event, agentId })
  if (delay === 0) await send()
}

// Back to running once nothing S.waits on the person.
async function endWait($: EngineInterface, id: string, outcome: string) {
  await settleWait($, id, outcome)
  if (S.waits.size > 0) return
  await setActivity($, now => (now.kind === 'waiting' || now.kind === 'asking' ? { ...now, kind: 'running', detail: null, isSent: false } : now))
}

// The auto run state file in the primary checkout, as the run bound to this
// session; null when there is none or another session owns it.
async function readAutoRun($: EngineInterface): Promise<CockpitAutoRun | null> {
  const root = S.where.primary ?? (await read($, place))?.root ?? null
  if (root === null) return null
  const text = await $.fs.read(`${root}/.dforge/sdd/auto-run.json`).catch(() => null)
  if (typeof text !== 'string') return null
  return autoRunFor(text, await $.session.id())
}

// Runs scripts/auto-run as `sessionId`; resolves its exit code, 1 when it could not run.
async function autoRunCall($: EngineInterface, sessionId: string, args: string[]): Promise<number> {
  const ran = await $.process.run(['bash', `${$.plugin.root}/scripts/auto-run`, '--session', sessionId, ...args], { timeoutMs: 15_000 }).catch(() => null)
  return ran?.exitCode ?? 1
}

// Keeps the pane's copy of the bound run, and says once on Discord when the
// run stopped with a reason.
async function trackAutoRun($: EngineInterface) {
  const now = await readAutoRun($)
  const before = await read($, autoRun)
  if (JSON.stringify(now) === JSON.stringify(before)) return
  await update($, autoRun, () => now)
  if (before?.active === true && now !== null && !now.active && now.stopped !== null) {
    await notify($, { kind: 'blocked', title: '⛔ Auto run stopped', detail: now.stopped, isPlain: true })
  }
}

// A main turn of the bound run ended on the sentinel its pending action asks
// for: schedule the stage from a timer, so it never runs inside this hook
// (compact and /clear refuse there).
async function armAutoRun($: EngineInterface, answer: string) {
  const auto = await readAutoRun($)
  if (auto === null || !auto.active || !endsOnSentinel(answer, auto.pending)) return
  // A stage armed now starts its own deferral, whatever the timer it replaces had.
  S.autoDeferredSince = null
  scheduleAutoAct($, auto.pending === 'clear' ? 'clear' : auto.pending === 'switch' ? 'switch' : 'compact', 0)
}

function scheduleAutoAct($: EngineInterface, stage: AutoStage, ms: number) {
  S.autoTimer?.cancel()
  S.autoTimer = $.clock.after(ms, () => void autoAct($, stage))
}

// Carries the bound run through its pending stages: compact, then the
// continue prompt; or clear, rebind, model and effort, then the first prompt;
// or switch: compact, then model and effort and the first prompt in the same
// session.
// Each attempt first re-checks that the stage is still due and the session
// idle. A failure is booked and the failed stage tried again; the script stops
// the run at the second (exit 5).
async function autoAct($: EngineInterface, stage: AutoStage) {
  S.autoTimer = null
  const auto = await readAutoRun($)
  if (auto === null || !auto.active || auto.pending !== AUTO_STAGE_PENDING[stage]) {
    // The run stopped or moved on: its deferral, if any, ends with it.
    S.autoDeferredSince = null
    return
  }
  const isBackground = (await read($, spawns)).some(one => !one.isDone) || (await read($, shells)).length > 0
  if (S.isTurnLive || isBackground) {
    const stamp = await $.clock.now()
    S.autoDeferredSince = isBackground ? (S.autoDeferredSince ?? stamp) : null
    if (S.autoDeferredSince === null || stamp - S.autoDeferredSince < DEFER_CAP_MS) {
      scheduleAutoAct($, stage, AUTO_RETRY_MS)
      return
    }
    // A launch that never reports would hold the stage forever: book it as a
    // failure, so the second one stops the run with a reason.
    S.autoDeferredSince = null
    const owner = await $.session.id()
    const why = `a background launch kept the ${stage} waiting 30 minutes`
    const code = await autoRunCall($, owner, ['failure', '--reason', why])
    if (code === 0) scheduleAutoAct($, stage, AUTO_RETRY_MS)
    else if (code === 5) await endStoppedRun($)
    else await endUnboundRun($, owner, `${why}, and the failure could not be booked (exit ${code})`)
    return
  }
  S.autoDeferredSince = null
  let bound = await $.session.id()
  let at: AutoStage = stage
  try {
    if (at === 'compact') {
      const done = await $.session.compact({ instructions: AUTO_COMPACT_INSTRUCTIONS })
      if ('skip' in done && typeof done.skip === 'string') throw new Error(done.skip)
      await update($, budget, () => null)
      await update($, isNudged, () => false)
      // The compaction happened: never repeat it. Unbooked, pending stays
      // compact and no later stage would run, so stop the run instead. Exit 5
      // is the script's own stop: the compaction cap was reached.
      const booked = await autoRunCall($, bound, ['compacted'])
      if (booked === 5) {
        await endStoppedRun($)
        return
      }
      if (booked !== 0) {
        await endUnboundRun($, bound, 'the cockpit compacted but could not book it')
        return
      }
      await trackAutoRun($)
      at = 'continue'
    }
    if (at === 'continue') {
      await $.prompt.submit({ text: autoContinuePrompt($.plugin.root, auto.plan), asUser: true })
      // Clears a failure booked before this retry; pending stays after-compact.
      await autoRunCall($, bound, ['resumed'])
      return
    }
    if (at === 'switch') {
      const done = await $.session.compact({ instructions: AUTO_SWITCH_INSTRUCTIONS })
      if ('skip' in done && typeof done.skip === 'string') throw new Error(done.skip)
      await update($, budget, () => null)
      await update($, isNudged, () => false)
      // As for compact: the compaction happened, so it is never repeated.
      if ((await autoRunCall($, bound, ['compacted', '--switch'])) !== 0) {
        await endUnboundRun($, bound, 'the cockpit compacted for the switch but could not book it')
        return
      }
      await trackAutoRun($)
      at = 'switch-resume'
    }
    if (at === 'clear') {
      await $.command.run({ command: 'clear' })
      const cleared = await $.session.id()
      if ((await autoRunCall($, cleared, ['rebind', '--to', cleared])) !== 0) {
        // The run is still bound to the session /clear ended: stop it from there.
        await endUnboundRun($, bound, 'the cleared session could not be bound')
        return
      }
      bound = cleared
      at = 'resume'
    }
    const refused: string[] = []
    let isRestored = true
    let isKept = false
    if (auto.launch !== null) {
      // /model and /effort save the user's defaults: run them only when those
      // can be read now and put back after (the restore runs node).
      const saved = await userDefaults($)
      if (saved !== null && (await nodeRuns($))) {
        for (const [command, args] of [['model', auto.launch.model], ['effort', auto.launch.effort]] as const) {
          await $.command.run({ command, args }).catch(() => refused.push(`/${command} ${args}`))
        }
        isRestored = await restoreUserDefaults($, saved)
        if (!isRestored) {
          await notify($, { kind: 'blocked', title: '⛔ Default model not restored', detail: `/model and /effort left the auto run's launch model as the default in ${await userSettingsPath($)}.`, isPlain: true })
        }
      } else isKept = true
    }
    const notes: string[] = []
    if (isKept) notes.push(`The cockpit kept this session on ${await $.session.model()} because it could not put back your default model afterwards.`)
    if (refused.length > 0) notes.push(`The cockpit could not run ${refused.join(' or ')}; this session runs on ${await $.session.model()}.`)
    if (!isRestored) notes.push('The cockpit could not put back the default model and effort that /model and /effort saved in your user settings.')
    const note = notes.length === 0 ? '' : `\n\n${notes.join(' ')} Record that with scripts/auto-run ruling add.`
    const lead = at === 'switch-resume' ? `Run \`bash ${$.plugin.root}/scripts/auto-run after-compact\` first. ` : ''
    await $.prompt.submit({ text: `${lead}${auto.resumePrompt ?? resumePrompt()}${note}`, asUser: true })
    // After a switch an unbooked resume leaves switch-resume pending, which no
    // stage retries; the prompt is already submitted, so stop rather than resend it.
    if ((await autoRunCall($, bound, ['resumed'])) !== 0 && at === 'switch-resume') {
      await endUnboundRun($, bound, 'the cockpit switched but could not book it')
      return
    }
    await trackAutoRun($)
  } catch (error) {
    const why = error instanceof Error ? error.message : String(error)
    const action = at === 'compact' || at === 'continue' ? 'compact' : at === 'switch' || at === 'switch-resume' ? 'switch' : 'clear'
    const code = await autoRunCall($, bound, ['failure', '--reason', `the cockpit could not ${action}: ${why}`])
    if (code === 0) scheduleAutoAct($, at, AUTO_RETRY_MS)
    else if (code === 5) await endStoppedRun($)
    // Unbooked, nothing would retry the stage: stop rather than stall unseen.
    else await endUnboundRun($, bound, `the cockpit could not ${action} and could not book the failure (exit ${code})`)
  }
}

// What /model and /effort save as the user's defaults, as the engine has them
// loaded; null when the settings cannot be read, so nothing is restored from a guess.
async function userDefaults($: EngineInterface): Promise<{ model: unknown; modelSettings: unknown } | null> {
  const user = (await $.settings.read({ source: 'user' }).catch(() => null)) as Record<string, unknown> | null
  if (user === null) return null
  return { model: user.model ?? null, modelSettings: user.modelSettings ?? null }
}

// Whether node starts: the restore below runs dforge-config.mjs with it.
async function nodeRuns($: EngineInterface): Promise<boolean> {
  const ran = await $.process.run(['node', '--version'], { timeoutMs: 5_000 }).catch(() => null)
  return ran?.exitCode === 0
}

// The user settings file /model and /effort write, for the notice that names it.
async function userSettingsPath($: EngineInterface): Promise<string> {
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
  const configDir = (await $.env.get('CLAUDE_CONFIG_DIR')) || (home ? `${home.replace(/[\\/]+$/, '')}/.claude` : '~/.claude')
  return `${configDir}/settings.json`
}

// /model and /effort save their values as the user's defaults for every new
// session; the cleared session keeps running on them after the file is put back.
// The engine never reloads a write that lands right after its own save, and its
// next settings write would save the launch model again, so the restore counts
// only once the engine reads it back; a later write is outside that window.
async function restoreUserDefaults($: EngineInterface, saved: { model: unknown; modelSettings: unknown }): Promise<boolean> {
  for (let write = 0; write < RESTORE_WRITES; write++) {
    const ran = await $.process
      .run(['node', `${$.plugin.root}/scripts/lib/dforge-config.mjs`, 'claude-restore', JSON.stringify(saved)], { timeoutMs: 15_000 })
      .catch(() => null)
    if (ran?.exitCode !== 0) return false
    for (let waited = 0; ; waited += RESTORE_POLL_MS) {
      if (JSON.stringify(await userDefaults($)) === JSON.stringify(saved)) return true
      if (waited >= RESTORE_WAIT_MS) break
      await $.clock.sleep(RESTORE_POLL_MS)
    }
  }
  return false
}

// The heartbeat scripts/auto-run reads (reference/auto-run.md §Starting): the
// epoch seconds of the last beat, in a file named for this session's id with
// each character outside A-Za-z0-9 a dash.
async function beat($: EngineInterface) {
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
  if (!home) return
  const id = (await $.session.id()).replace(/[^A-Za-z0-9]/g, '-')
  const seconds = Math.floor((await $.clock.now()) / 1000)
  await $.fs.write(`${home.replace(/[\\/]+$/, '')}/.claude/dforge/sessions/cockpit/${id}`, `${seconds}\n`).catch(() => undefined)
}

// Each WATCHDOG_MS: the heartbeat.
async function watchdogTick($: EngineInterface) {
  await beat($)
}

// The run stopped while the session was idle: record it, and give the model a
// turn to end the run as the attended flow would.
async function endStoppedRun($: EngineInterface) {
  await trackAutoRun($)
  const reason = (await read($, autoRun))?.stopped ?? 'the cockpit could not act'
  await $.prompt.submit({ text: `The auto run stopped: ${reason}. End as reference/auto-run.md §Stopping says.`, asUser: true }).catch(() => undefined)
}

// The state file cannot be trusted to record the stop (the run moved to
// another session, or the script failed): stop the run as the session that
// owned it, best effort, and say so here without reading the file back.
async function endUnboundRun($: EngineInterface, owner: string, reason: string) {
  await autoRunCall($, owner, ['stop', '--reason', reason])
  await update($, autoRun, () => null)
  await notify($, { kind: 'blocked', title: '⛔ Auto run stopped', detail: reason, isPlain: true })
  await $.prompt.submit({ text: `The auto run stopped: ${reason}. End as reference/auto-run.md §Stopping says.`, asUser: true }).catch(() => undefined)
}

// A compaction the cockpit did not make, booked so the run's rule applies after it.
async function bookAutoCompaction($: EngineInterface) {
  const auto = await readAutoRun($)
  // A pending clear or switch supersedes the compaction: booking it would drop
  // that stage. A pending handoff still needs its clear, and a pending compact
  // is the cockpit's own stage, which books itself.
  if (auto === null || !auto.active || ['clear', 'switch', 'switch-resume', 'handoff', 'compact'].includes(auto.pending ?? '')) return
  // Exit 5: the compaction cap stopped the run.
  if ((await autoRunCall($, await $.session.id(), ['compacted'])) === 5) await endStoppedRun($)
}

async function stopAutoRun($: EngineInterface) {
  await autoRunCall($, await $.session.id(), ['stop', '--reason', 'owner pressed Stop auto'])
  await trackAutoRun($)
}

// The roots darkmem-config.mjs --mode names for the primary checkout (store
// options spec §7.3). Read again when the checkout or ~/.dforge/stores.json
// changes, so the session that ran a move sees the new roots. Null keeps the
// checkout paths: silently without node or mode lines, with a note in the
// pane when the run fails or outruns its 5 seconds.
const NO_NODE = /ENOENT|not found/i
// The engine's rejection for a run still going at its timeoutMs (Claude Code
// 2.1.299: "…aborted: still running after 5000ms"); a command that cannot
// start rejects "…failed to start: ENOENT…" instead.
const TIMED_OUT = /still running after/i

async function readRoots($: EngineInterface, primary: string): Promise<CockpitRoots | null> {
  const home = (await read($, place))?.home ?? null
  const stores = home === null ? null : await $.fs.stat(`${home}/.dforge/stores.json`).catch(() => null)
  const key = `${primary}|${stores?.mtimeMs ?? 'none'}`
  if (S.roots.key === key) return S.roots.value
  let value: CockpitRoots | null = null
  let note: string | null = null
  try {
    const ran = await $.process.run(['node', `${$.plugin.root}/scripts/lib/darkmem-config.mjs`, '--mode', primary], { timeoutMs: 5000 })
    if (ran.exitCode === 0) value = parseModeLines(ran.stdout)
    else if (!NO_NODE.test(ran.stderr)) {
      note = ran.stderr.split(/\r?\n/).map(line => line.trim()).find(Boolean) ?? `darkmem-config.mjs --mode exited ${ran.exitCode}`
    }
  } catch (error) {
    // run rejects only when the command cannot start or outlives timeoutMs;
    // any other wording, a later engine's included, keeps the paths silently.
    if (TIMED_OUT.test(String(error))) note = 'darkmem-config.mjs --mode gave no answer within 5 seconds'
  }
  S.roots = { key, value }
  if ((await read($, rootsNote)) !== note) await update($, rootsNote, () => note)
  return value
}

// finish.json for the newest ledger's slug, or the no-plan one: it stays in
// the workspace of the worktree that ran the plan, so the session's checkout
// is read first, then the primary; the primary's path when neither has one.
async function finishPath($: EngineInterface, checkouts: readonly string[], slug: string | null): Promise<string> {
  const paths: string[] = []
  for (const dir of checkouts) {
    paths.push(slug === null ? `${dir}/.dforge/sdd/finish.json` : `${dir}/.dforge/sdd/${slug}/finish.json`)
  }
  for (const path of paths) {
    if ((await $.fs.stat(path).catch(() => null))?.kind === 'file') return path
  }
  return paths[paths.length - 1] ?? ''
}

// The note is read again only when it changes: readRun runs at every turn.
async function readResumeOffer($: EngineInterface, latest: string, at: number | null) {
  const key = `${latest}\t${at}`
  if (S.offerRead === key) return
  S.offerRead = key
  const text = at === null ? null : await $.fs.read(latest).catch(() => null)
  const found = typeof text === 'string' ? resumeOfferOf(text) : null
  const offer: CockpitResumeOffer | null = found === null || at === null ? null : { at, next: found.next }
  if (JSON.stringify(await read($, resumeOffer)) !== JSON.stringify(offer)) await update($, resumeOffer, () => offer)
}

/** The handoff the resume card and band offer now; null while nothing is to resume. */
async function offerNow($: EngineInterface, now: number): Promise<CockpitResumeOffer | null> {
  const offer = await read($, resumeOffer)
  if (offer === null || now - offer.at >= RESUME_WITHIN) return null
  if ((await read($, resumeDismissed)) === offer.at || (await read($, isPlanSession)) || (await read($, autoRun))?.active) return null
  return offer
}

async function resume($: EngineInterface, offer: CockpitResumeOffer) {
  await update($, resumeDismissed, () => offer.at)
  await $.prompt.submit({ text: resumePrompt(), asUser: true })
}

// The run's ledger, its plan's tasks, and the newest handoff, read where the
// roots put them (store options spec §7.3): the primary checkout's .dforge/
// while progress is local, the darkmem mirror while it is not.
async function readRun($: EngineInterface) {
  const session = (await read($, place))?.root ?? null
  const root = S.where.primary ?? session
  if (root === null) return
  const state = `${root}/.dforge`
  const roots = await readRoots($, root)
  const latest = roots?.progress.latestFile ?? `${state}/handoff/latest.md`
  S.latestName = roots?.progress.store === 'darkmem' ? latest : null
  const checkouts = [...new Set([session, root].filter((dir): dir is string => dir !== null))]
  try {
    const handoff = await $.fs.stat(latest).catch(() => null)
    const handoffTime = handoff?.kind === 'file' ? handoff.mtimeMs : null
    if ((await read($, handoffAt)) !== handoffTime) await update($, handoffAt, () => handoffTime)
    await readResumeOffer($, latest, handoffTime)
    const base = roots?.progress.ledgerRoot ?? `${state}/sdd`
    const entries = await $.fs.list(base).catch(() => [])
    let newest: { slug: string; path: string; at: number } | null = null
    for (const entry of entries) {
      if (entry.kind !== 'dir') continue
      const info = await $.fs.stat(`${base}/${entry.name}/progress.md`).catch(() => null)
      if (info?.kind === 'file' && (newest === null || info.mtimeMs > newest.at)) newest = { slug: entry.name, path: `${base}/${entry.name}/progress.md`, at: info.mtimeMs }
    }
    await readFinish($, await finishPath($, checkouts, newest?.slug ?? null))
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
      const places: { root: string; docsDir: string }[] = []
      for (const dir of checkouts) places.push({ root: dir, docsDir: `${dir}/docs/dforge` })
      for (const candidate of planCandidates(ledger.plan, roots?.docs ?? null, places)) {
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
    await sendLedgerEvents($, summary)
  } catch {
    // No readable ledger: the Plan card stays as it is.
  }
}

// The finish action dforge asked for before the run, from the run's
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
    const fromEnv = ((await $.env.get('DFORGE_NOTIFY_URL')) || (await $.env.get('DR_COCKPIT_NOTIFY_URL')) || '').trim()
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
  // A worktree's .dforge/ lives in the primary checkout.
  const common = await firstLine(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'])
  S.where.primary = common === null ? null : common.replace(/[\\/]\.git[\\/]?$/, '') || null
}

// The context crossed its handoff budget: said once per crossing.
async function onBudget($: EngineInterface, reading: { now: CockpitBudget; isPast: boolean } | undefined) {
  if (reading === undefined) return
  if ((await read($, autoRun))?.active) {
    // A run compacts at its own limit: the crossing it passes does not count.
    S.isBudgetSent = false
    return
  }
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
    { kind: 'done', title: '🔔 Test from dforge', detail: 'Notifications reach this channel.', isPlain: true },
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
    text: state.url === null ? 'No Discord webhook is set. /cockpit notify url <url> sets one.' : `Discord webhook: ${maskWebhook(state.url)}${state.isFromEnv ? ' (from the environment)' : ''}.`,
  }
}


// Reads the status line's figures (free without a breakdown) and, past the
// budget in a dforge session, tells the model once.
async function refresh($: EngineInterface, tuning: Tuning, compactWindow: number | undefined): Promise<{ now: CockpitBudget; isPast: boolean } | undefined> {
  const { handoffTokens, nudgeModel } = tuning
  const figures = await $.session.usage()
  const tokens = figures.context.tokens
  if (tokens === undefined) return
  const window = figures.context.window
  const auto = await read($, autoRun)
  const isAuto = auto !== null && auto.active
  const limit = isAuto
    ? autoLimitFor(auto.regime, handoffTokens, window, compactWindow)
    : tuning.isRelaxed
      ? finalLimitFor(window, compactWindow)
      : budgetFor(handoffTokens, undefined, window, compactWindow)
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
  // An auto run compacts at its limit rather than handing off: no note.
  if (!nudgeModel || isAuto || (await read($, isNudged)) || !(await read($, isPlanSession))) return reading
  await update($, isNudged, () => true)
  const note = `dforge: budget: ${kTokens(tokens)} of ${kTokens(limit)} — handoff. ${HANDOFF_PROMPT}`
  try {
    await $.session.append({ message: { type: 'user', content: [{ type: 'text', text: note }] } })
  } catch {
    // The host would not take the row: say it to the person instead.
    $.ui.toast(note)
  }
  return reading
}

/** What the pane asks the surface for under a layout: the band's rows unless it is full. */
function paneFor(layout: string) {
  return { id: PANE, title: 'Cockpit', columns: PANE_COLUMNS, ...(layout === 'full' ? {} : { rows: COMPACT_ROWS }) }
}

/**
 * Opens the pane from the minimized band. Called from the person's press or
 * command and before the setting is written, so the pane seats at any width.
 */
async function expand($: EngineInterface, isDocking: boolean) {
  const to = isDocking ? 'auto' : 'full'
  await update($, view, () => 'cockpit')
  const opened = await $.ui.open(paneFor(to))
  await setOption($, 'layout', to)
  return opened
}

/** Opens the settings afresh: no half-typed value or pending reset survives a close. */
async function showSettings($: EngineInterface) {
  await update($, settingsView, now => ({ ...now, editing: null, error: null, isConfirmingReset: false }))
  await update($, view, () => 'settings')
}

/** ~/.dforge/config.json, or null when no home directory is set. */
async function configFile($: EngineInterface): Promise<string | null> {
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
  return home ? `${home.replace(/[\\/]+$/, '')}/.dforge/config.json` : null
}

/** The settings file's object: {} when it does not exist, null when it exists but is not a JSON object. */
async function readSettingsFile($: EngineInterface, path: string): Promise<SettingsFile | null> {
  let text: string
  try {
    text = String(await $.fs.read(path))
  } catch {
    return (await $.fs.exists(path).catch(() => false)) ? null : {}
  }
  try {
    const data: unknown = JSON.parse(text)
    return data !== null && typeof data === 'object' && !Array.isArray(data) ? (data as SettingsFile) : null
  } catch {
    return null
  }
}

/** Puts a settings file in force: the atom every hook reads through live(), the locked rows, and the notifier. */
async function applySettings($: EngineInterface, file: SettingsFile) {
  const env = { DFORGE_BUDGET: await $.env.get('DFORGE_BUDGET') }
  const engineUser = ((await $.settings.read({ source: 'user' }).catch(() => ({}))) ?? {}) as Record<string, unknown>
  // The engine's snapshot can predate a save: until it shows the saved value the merged read is overlaid too, then a project or managed override shows through.
  const awaited = Object.fromEntries(Object.entries(S.claudeSaved).filter(([key, saved]) => engineUser[key] !== saved))
  const merged = { ...(((await $.settings.read().catch(() => ({}))) ?? {}) as Record<string, unknown>), ...awaited }
  const user = { ...engineUser, ...S.claudeSaved }
  const values = resolveSettings(SCHEMA, file, env, merged)
  S.settingProblems = settingProblems(SCHEMA, file, env)
  const locks = { ...envLocks(SCHEMA, env), ...claudeLocks(SCHEMA, merged, user) }
  S.locks = locks
  await update($, settings, () => values)
  applyNotify(liveFrom(values as Partial<Options>))
}

/** The first run: dr-cockpit's options, written to the new file. */
async function importSettings($: EngineInterface, path: string): Promise<SettingsFile> {
  const claude = await $.settings.read({ source: 'user' }).catch(() => ({}))
  const file = importedSettings(SCHEMA, claude)
  // The mod has no exclusive create: a file saved while the reads above ran is kept.
  if (await $.fs.exists(path).catch(() => false)) return (await readSettingsFile($, path)) ?? file
  await $.fs.write(path, `${JSON.stringify(file, null, 2)}\n`).catch(() => undefined)
  return file
}

/** Once per machine: dr-cockpit's Discord webhook and mention, from its store file into this plugin's store. */
async function importWebhook($: EngineInterface) {
  if ((await $.store.get(STORE_IMPORTED)) === true) return
  await $.store.set(STORE_IMPORTED, true)
  if ((await $.store.get(STORE_URL)) !== undefined) return
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
  const configDir = (await $.env.get('CLAUDE_CONFIG_DIR')) || (home ? `${home.replace(/[\\/]+$/, '')}/.claude` : '')
  if (!configDir) return
  const dir = `${configDir}/plugins/store`
  const entry = (await $.fs.list(dir).catch(() => [])).find(one => one.name.startsWith('dr-cockpit_darkraise-') && one.name.endsWith('.json'))
  if (entry === undefined) return
  const old = await $.fs
    .read(`${dir}/${entry.name}`)
    .then(text => JSON.parse(String(text)) as Record<string, unknown>)
    .catch(() => null)
  if (old === null) return
  if (typeof old.notifyUrl === 'string' && isDiscordWebhook(old.notifyUrl)) await $.store.set(STORE_URL, old.notifyUrl)
  if (typeof old.notifyMention === 'string') await $.store.set(STORE_MENTION, old.notifyMention)
}

/** Reads ~/.dforge/config.json into force, importing the pre-2.0 settings on the first run. */
async function loadSettings($: EngineInterface) {
  S.claudeSaved = {}
  S.changed = {}
  const path = await configFile($)
  if (path === null) return applySettings($, {})
  let file = await readSettingsFile($, path)
  if (file !== null && Object.keys(file).length === 0 && !(await $.fs.exists(path).catch(() => false))) {
    file = await importSettings($, path)
  }
  await applySettings($, file ?? {})
  await importWebhook($).catch(() => undefined)
}

/** Saves one setting and puts it in force, saying why if it could not; resolves whether it was saved. */
async function setOption($: EngineInterface, key: string, value: SettingValue): Promise<boolean> {
  const spec = SCHEMA[key]
  const path = await configFile($)
  const file = path === null ? null : await readSettingsFile($, path)
  try {
    if (spec?.target === 'claude') {
      // Claude's settings file holds far more than these keys, so only dforge-config, which rewrites it in one rename, writes it.
      const ran = await $.process.run(['node', `${$.plugin.root}/scripts/lib/dforge-config.mjs`, 'set', key, String(value)])
      if (ran.exitCode !== 0) throw new Error(ran.stderr.trim().replace(/^dforge-config: /, '') || `dforge-config exited ${ran.exitCode}`)
      // dforge-config removes a floored key saved as 0, so the user file then lacks it.
      S.claudeSaved[key] = spec.floor !== undefined && value === 0 ? undefined : value
      await applySettings($, file ?? {})
      return true
    }
    if (path === null) throw new Error('no home directory is set')
    if (file === null) throw new Error(`${path} is not a JSON object; fix or remove it`)
    const next = settingWritten(SCHEMA, file, key, value)
    await $.fs.write(path, `${JSON.stringify(next, null, 2)}\n`)
    await applySettings($, next)
    if (spec?.enforcedBy === 'skill') S.changed[key] = value
    return true
  } catch (error) {
    $.ui.toast(`dforge: ${key} not saved: ${error instanceof Error ? error.message : String(error)}`)
    return false
  }
}

/**
 * Draws a field in place of the pressed button and moves the keyboard into it.
 * autoFocus acts only when the pane takes the keys, so without the move typing
 * reaches the prompt. The move is asked first: it waits for the field's drawing.
 */
async function openField($: EngineInterface, key: string, open: () => Promise<unknown>) {
  const focusing = $.ui.focus({ requestId: PANE, key }).catch(() => undefined)
  await open()
  await focusing
}

/** Tells the model, once, which skill-enforced settings changed; outside a dforge session the change waits for one. */
async function flushSettingNote($: EngineInterface) {
  const sent = { ...S.changed }
  const keys = Object.keys(sent)
  if (keys.length === 0 || !(await read($, isPlanSession))) return
  const note = `dforge settings changed: ${keys.map(key => `${key}=${String(sent[key])}`).join('; ')}. Each replaces the matching question or default in the skills.`
  try {
    const appended = await $.session.append({ message: { type: 'user', content: [{ type: 'text', text: note }] } })
    if (appended.deny !== undefined) return
  } catch {
    // The host would not take the row: the changes stay pending for the next close.
    return
  }
  // A key changed again while the row was being appended stays pending.
  for (const key of keys) if (S.changed[key] === sent[key]) delete S.changed[key]
}

// The pane's slower readings: the /context breakdown, estimated locally, and
// the working tree's git state. Read while the pane is up, never per tool call.
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
 * The account: the email and organization from the account's .claude.json
 * (CLAUDE_CONFIG_DIR's, else the home one), and a frame color picked from the
 * config directory, so each account keeps its own.
 */
async function readAccount($: EngineInterface) {
  try {
    const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
    if (home === undefined || home === '') return
    const configDir = await $.env.get('CLAUDE_CONFIG_DIR')
    const state = await readJson($, configDir ? `${configDir}/.claude.json` : `${home}/.claude.json`)
    const oauth = (state?.oauthAccount ?? {}) as Record<string, unknown>
    const key = accountKey(configDir || `${home}/.claude`, home)
    const text = (value: unknown) => (typeof value === 'string' && value !== '' ? value : null)
    const next: CockpitAccount = {
      email: text(oauth.emailAddress),
      name: text(oauth.displayName),
      organization: text(oauth.organizationName),
      role: text(oauth.organizationRole),
      billing: text(oauth.billingType),
      key,
      color: accountColor(key),
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
    const home = ((await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))) || null
    const before = await read($, place)
    const next = { cwd, root: repoAt?.root ?? null, remote: repoAt?.remote ?? null, home }
    if (before?.cwd !== next.cwd || before.root !== next.root || (before.remote ?? null) !== next.remote || before.home !== next.home) {
      await update($, place, () => next)
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

// The limits that crossed the alert line, once per window and reset, for the
// Discord message; the pane's own gauges show them, so nothing pops up.
async function alertLimits($: EngineInterface, reading: CockpitUsage, at: number) {
  const said = await read($, alerted)
  const crossed: CockpitUsage['limits'] = []
  for (const limit of reading.limits) {
    const key = `${limit.kind}@${limit.resetsAt ?? ''}`
    if (limit.percent < at || said.includes(key)) continue
    await update($, alerted, list => [...list, key].slice(-20))
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

/** Closes the pane when it is open, drawn or still waiting for room. */
async function shutPane($: EngineInterface) {
  try {
    if ((await $.ui.panes()).some(pane => pane.id === PANE)) await $.ui.close({ id: PANE })
  } catch {
    // No pane to close on this host.
  }
}

async function readVersion($: EngineInterface) {
  try {
    S.canUnderline = isAtLeast((await $.session.version()).base, UNDERLINE_SINCE)
  } catch {
    S.canUnderline = false
  }
}

function clip(text: string, width: number): string {
  const chars = [...text]
  return chars.length <= width ? text : chars.slice(0, width - 1).join('') + '…'
}

// The shells a task notification says ended leave the card.
async function endShells($: EngineInterface, text: string) {
  const ended = new Set(tasksEnded(text).map(one => one.id))
  if (ended.size === 0 || !(await read($, shells)).some(one => ended.has(one.id))) return
  await update($, shells, list => list.filter(one => !ended.has(one.id)))
  await syncTicker($)
}

// A Bash call that went to the background (asked for, Ctrl+B, or its
// timeout) is a running shell until its notification or a stop names it.
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

function shortSeat(seat: string): string {
  return seat.replace(/^dforge:/, '')
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

// The round of the task in flight, as the ledger writes it ("2/5"), for the Run card's head.
function runRound(summary: CockpitRun): string | null {
  return summary.tasks.find(task => task.state === 'assigned' && task.round !== null)?.round ?? null
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
