import { atom, read, update } from 'claude-code'
import type { EngineInterface, PromptOrigin, Register, RenderChildren, RenderInput, Timer, TurnUsage } from 'claude-code'

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
  activeRunOwner,
  autoRunFor,
  agentGroups,
  bar,
  billingLabel,
  budgetFor,
  collapsedFrom,
  collapsedToggled,
  commandLine,
  denseLine,
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
  isDagents,
  gitMessageTexts,
  gitTextFiles,
  isAbsolutePath,
  isPlanTail,
  isServiceCommand,
  kTokens,
  levelOf,
  limitForecast,
  limitLabel,
  modelName,
  namedPlan,
  nowLine,
  parseFinish,
  parseLedger,
  planCandidates,
  planTasks,
  planFromTodos,
  planWithUpdate,
  positive,
  rampColor,
  reconcileStep,
  remoteRuns,
  repoFromPorcelain,
  repoName,
  resumeOfferOf,
  markerOf,
  promptRegisters,
  hasUnresolvedRows,
  runList,
  shellAge,
  runsCut,
  runsWidth,
  SECTIONS,
  BAND_SEGMENTS,
  seatBarCells,
  seatCounts,
  seatDenial,
  fastModeLine,
  guardLine,
  bandLines,
  bandLinesFrom,
  bandLineToggled,
  sectionsFrom,
  sectionsToggled,
  sparkline,
  stackedRuns,
  statMissing,
  stringsIn,
  tasksEnded,
  termColor,
  themeColor,
  track,
  turnsToBudget,
  windowElapsed,
  warnShare,
  writesGitText,
} from './lib'
import type { AgentGroupKey, BandInput, BandSegment, DenseInput, Run, Section, TrackPart } from './lib'
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
  redact,
} from './notify'
import type { NotifyEvent, NotifyKind, NotifyPlace, SendResult } from './notify'
import { CELL_PX, avatarSvg, bandMetersSvg, gaugeTileSvg, gaugeSvg, labelledMeterSvg, meterSvg, paint, seatSvg, segmentsSvg, stackSvg, svgWidth, trendSvg } from './svg'
import type { BandMeter, PanelLine, PanelRun, Segment } from './svg'

const PANE = 'dagents'
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
  'Finish the task in flight through its completion line, then hand off with the dagents handoff skill. Start no new task.'
function resumePrompt(): string {
  if (S.latestName === null) return `Resume the work with the dagents resume-execution skill. Before anything else, claim the handoff it reads with dagents' \`scripts/handoff claim\`.`
  return `Resume the work in ${S.latestName} with the dagents resume-execution skill. Before anything else, claim it with dagents' \`scripts/handoff claim\` on that file.`
}
// A handoff older than this is not offered for resuming.
const RESUME_WITHIN = 3 * 86_400_000
// What an auto run's compaction keeps (reference/auto-run.md).
const AUTO_COMPACT_INSTRUCTIONS =
  'Preserve verbatim: the worktree path; the plan, ledger, handoff and auto-run state file paths; the current HEAD; the auto run pending decisions; and Ruling: lines, keeping rulings only for the task in flight and plan-wide rulings. Give one line per finished task, or point to the ledger. Name the task in progress and its fix round. Keep the summary to at most 1,500 words.'
// A failed stage is tried again after this long; a live turn or background work defers it as long.
const AUTO_RETRY_MS = 5_000
// The restored default model is written this many times at most, each write
// watched this long for the engine to read it back.
const RESTORE_WRITES = 3
const RESTORE_WAIT_MS = 3_000
const RESTORE_POLL_MS = 500
type AutoStage = 'compact' | 'continue' | 'clear' | 'resume' | 'switch'
// The pending action the state file holds while each stage is due.
const AUTO_STAGE_PENDING: Record<AutoStage, string> = {
  compact: 'compact',
  continue: 'after-compact',
  clear: 'clear',
  resume: 'resume',
  switch: 'switch',
}
function autoContinuePrompt(root: string, plan: string | null): string {
  const where = plan === null ? '' : ` for plan ${plan}, through the After compaction steps of the execution skill its Execution line names`
  return `Continue the auto run: run \`bash "${root}/scripts/auto-run" after-compact\` first, then continue the phase \`bash "${root}/scripts/auto-run" status\` names${where}, as reference/auto-run.md §After a compaction says.`
}
// The watchdog's period, and how long background work may defer a pending
// stage before that books a failure. A bound run idle STALL_MS since its last
// turn ended, stage ran or nudge went is stalled.
const WATCHDOG_MS = 60_000
const DEFER_CAP_MS = 1_800_000
const STALL_MS = 180_000
// An API-error ending is prompted again after this long.
const API_ERROR_RETRY_MS = 30_000
// How long a bound run may go with no live turn while only background work
// holds it before the watchdog asks the session to look at that work, and how
// many such prompts in a row may find the same launches running before the
// pending stage's failure is booked in place of a further prompt.
const RECONCILE_MS = 1_200_000
const RECONCILE_CAP = 3
// How long a Done held for background work waits, once the work ends, for the turn its notification wakes.
const RELEASE_GRACE_MS = 5_000
// The prompt.submit origins that are the person's own request, or auto run's.
const NEW_CHAIN_ORIGINS = new Set<PromptOrigin['kind']>(['composer', 'bridge', 'sdk', 'channel', 'slack-ping', 'plugin'])
// While the cockpit is drawn its files are checked every POLL_MS, git and the context breakdown every DETAIL_EVERY ticks.
const POLL_MS = 2_000
const DETAIL_EVERY = 5
// The pending actions whose stage the watchdog arms again when no timer holds
// it; a pending resume resubmits the run's first prompt.
const WATCHED_STAGES: Readonly<Record<string, AutoStage>> = { compact: 'compact', clear: 'clear', resume: 'resume', switch: 'switch' }
function apiErrorPrompt(root: string): string {
  return `The last turn ended on an API error. Run \`bash "${root}/scripts/auto-run" status\`, continue the phase it names, and end the turn as reference/auto-run.md §Ending a turn says.`
}
function stallPrompt(root: string): string {
  return `The auto run stalled: the last turn ended without its sentinel line. Run \`bash "${root}/scripts/auto-run" status\`, continue the phase it names, and end the turn as reference/auto-run.md §Ending a turn says.`
}
function reconcilePrompt(root: string): string {
  return `Background work has run 20 minutes since the last turn with no notification. Run \`bash "${root}/scripts/in-flight"\`. Stop with TaskStop each launch idle 30 minutes or more, and record a \`Ruling:\` line naming the task it served and that its result is void; leave the others running. Then continue the run, and end the turn again if only waiting remains.`
}
// The tools that wait on the person by their nature: their dialog is the question.
const ASKING_TOOLS = ['AskUserQuestion', 'ExitPlanMode']
// The endings of a main turn that asks the person to pick: dagents's finish menu and its confirmations.
const ASKING_ENDS = /(Which option\?|Type 'discard' to confirm\.?|Ask me then: show the finish menu\.?)$/
// Permission modes in which an "ask" is settled without the person.
const UNATTENDED_MODES = ['auto', 'bypassPermissions', 'dontAsk']
// The skills that run a plan's tasks in this session.
const RUN_SKILLS = ['dagents:subagent-driven-development', 'dagents:executing-plans', 'dagents:resume-execution']
// The tools that move the session into or out of a worktree.
const WORKTREE_TOOLS = ['EnterWorktree', 'ExitWorktree']
// The tools a review seat's write guard looks at.
const REVIEW_WRITE_TOOLS = ['Write', 'Edit', 'NotebookEdit']
const PATH_BODY = /[^\s'"`<>()|*?[\]{},;]*/.source
const PATH_STOP = /(?![\w-]|\.[\w-])/.source
// `whole` is an absolute path as a dispatch prompt spells it: not begun inside
// a relative path, not ending before more of a name. `tail` is the rest of
// one, read from just past a root matched literally.
const pathShape = (suffix: string) => ({
  whole: new RegExp(`(?<![\\w.~/\\\\-])(?:/|[A-Za-z]:[\\\\/])${PATH_BODY}${suffix}${PATH_STOP}`, 'g'),
  tail: new RegExp(`^[\\\\/]${PATH_BODY}${suffix}${PATH_STOP}`),
})
const REPORT_PATH = pathShape('-report\\.md')
const PROMPT_PATH = pathShape('-prompt\\.md')
// Every judge prompt template names its report on this line; a prompt also
// names reports the judge only reads.
const REPORT_LINE = /^\s*Write your full report to /
// The same line in a prompt, its phrase free to wrap: the text after it, to the line's end.
const REPORT_LINES = /(?:^|\n)[ \t]*Write\s+your\s+full\s+report\s+to\s+(\S[^\n]*)/g
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
// The band segments the desktop band writes as text rather than draws as meters.
const BAND_WORDS: readonly BandSegment[] = ['model', 'effort', 'style', 'turn', 'run', 'cost', 'time']
// The desktop's panel fill: a faint gray that lifts a card off the pane in
// the light theme and the dark alike.
const CARD = '#8080800f'
// How the desktop's run bar colors a task by its state.
const RUN_SEGMENTS: Record<string, Segment> = { complete: 'done', deferred: 'done', assigned: 'active', waiting: 'active', blocked: 'blocked' }
const GIT_STATUS = ['git', '--no-optional-locks', '-c', 'core.fsmonitor=false', 'status', '--porcelain=v2', '--branch']

const budget = atom({ plugin: 'dagents', key: 'budget' } as const, null)
const usage = atom({ plugin: 'dagents', key: 'usage' } as const, null)
const breakdown = atom({ plugin: 'dagents', key: 'breakdown' } as const, null)
const seats = atom({ plugin: 'dagents', key: 'seats' } as const, [])
const spawns = atom({ plugin: 'dagents', key: 'spawns' } as const, [])
const shells = atom({ plugin: 'dagents', key: 'shells' } as const, [])
const remote = atom({ plugin: 'dagents', key: 'remote' } as const, { clients: [], setting: null })
const plan = atom({ plugin: 'dagents', key: 'plan' } as const, [])
const repo = atom({ plugin: 'dagents', key: 'repo' } as const, null)
const refusals = atom({ plugin: 'dagents', key: 'refusals' } as const, [])
const isNudged = atom({ plugin: 'dagents', key: 'isNudged' } as const, false)
const isPlanSession = atom({ plugin: 'dagents', key: 'isPlanSession' } as const, false)
const isFastMode = atom({ plugin: 'dagents', key: 'isFastMode' } as const, false)
const isFastSession = atom({ plugin: 'dagents', key: 'isFastSession' } as const, false)
const isRunSession = atom({ plugin: 'dagents', key: 'isRunSession' } as const, false)
const autoRun = atom({ plugin: 'dagents', key: 'autoRun' } as const, null)
const autoRunLeft = atom({ plugin: 'dagents', key: 'autoRunLeft' } as const, false)
const boundPlan = atom({ plugin: 'dagents', key: 'boundPlan' } as const, null)
const alerted = atom({ plugin: 'dagents', key: 'alerted' } as const, [])
const trend = atom({ plugin: 'dagents', key: 'trend' } as const, [])
const view = atom({ plugin: 'dagents', key: 'view' } as const, 'cockpit')
const account = atom({ plugin: 'dagents', key: 'account' } as const, null)
const sessionRead = atom({ plugin: 'dagents', key: 'sessionRead' } as const, null)
const place = atom({ plugin: 'dagents', key: 'place' } as const, null)
const engine = atom({ plugin: 'dagents', key: 'engine' } as const, { model: null, effort: null, cache: null, style: null })
const IDLE: CockpitActivity = { kind: 'idle', since: 0, turnStartedAt: null, step: 0, tool: null, agent: null, detail: null, lastTurnMs: null, endedAt: null, isSent: false }
const activity = atom({ plugin: 'dagents', key: 'activity' } as const, IDLE)
const turnTokens = atom({ plugin: 'dagents', key: 'turnTokens' } as const, [])
const run = atom({ plugin: 'dagents', key: 'run' } as const, null)
const finish = atom({ plugin: 'dagents', key: 'finish' } as const, null)
const resumeOffer = atom({ plugin: 'dagents', key: 'resumeOffer' } as const, null)
const resumeDismissed = atom({ plugin: 'dagents', key: 'resumeDismissed' } as const, null)
const settings = atom({ plugin: 'dagents', key: 'settings' } as const, null)
const SETTINGS_VIEW: CockpitSettingsView = { tab: '', isHelpShown: true, editing: null, error: null, isConfirmingReset: false }
const settingsView = atom({ plugin: 'dagents', key: 'settingsView' } as const, SETTINGS_VIEW)
const notifier = atom({ plugin: 'dagents', key: 'notifier' } as const, {
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
  density: string
  sections: string
  collapsed: string
  breakdownRows: number
  openAtStart: boolean
  limitAlertAt: number
  notifyOn: string
  notifyAfter: number
  notifyAskAfter: number
  notifyDetail: string
  bandLine1: string
  bandLine2: string
}

/** What the budget reading is judged by. */
type Tuning = { handoffTokens: number; nudgeModel: boolean; warnAt: number; isRelaxed: boolean }

/** The options with their defaults filled in, and what the pane derives from them. */
type Live = Omit<Options, 'layout' | 'density'> & {
  layout: 'auto' | 'full' | 'compact'
  density: 'detailed' | 'dense'
  tuning: Tuning
  shown: Section[]
  shownCollapsed: Section[]
  bandLayout: [BandSegment[], BandSegment[]]
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
    density: densitySetting = 'detailed',
    sections = '',
    collapsed = '',
    breakdownRows = 6,
    openAtStart = true,
    limitAlertAt = 90,
    notifyOn = '',
    notifyAfter = 60,
    notifyAskAfter = 20,
    notifyDetail = 'full',
    bandLine1 = '',
    bandLine2 = '',
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
    density: densitySetting === 'dense' ? 'dense' : 'detailed',
    sections,
    collapsed,
    breakdownRows,
    openAtStart,
    limitAlertAt,
    notifyOn,
    notifyAfter,
    notifyAskAfter,
    notifyDetail,
    bandLine1,
    bandLine2,
    tuning: { handoffTokens, nudgeModel, warnAt: warnShare(warnAt), isRelaxed: handoffMode === 'relaxed' },
    shown: sectionsFrom(sections),
    shownCollapsed: collapsedFrom(collapsed),
    bandLayout: bandLinesFrom(bandLine1, bandLine2),
    isMinimized: layout === 'compact',
  }
}

/** The options in force now: the settings atom once written, else the defaults. */
async function live($: EngineInterface): Promise<Live> {
  return liveFrom(((await read($, settings)) ?? {}) as Partial<Options>)
}

/** Points the notifier at the options' events, detail and wait. */
function applyNotify(o: Live) {
  S.kinds = notifyKindsFrom(o.notifyOn)
  S.isBrief = o.notifyDetail === 'brief'
  S.notifyAskAfter = o.notifyAskAfter
}

// $ exists only once a hook runs, and the engine loads only hooks written as
// function literals, so the workflow guard's standalone check runs in the
// first hook and every hook awaits it at its top. While another workflow
// plugin shares the session, each hook passes its event on untouched, and the
// band above the prompt and the pane draw the guard line alone.
let guardCheck: Promise<string | null> | null = null

function guardNow($: EngineInterface): Promise<string | null> {
  guardCheck ??= $.process
    .run(['node', `${$.plugin.root}/scripts/workflow-guard.mjs`, '--host', 'claude', '--self', 'dagents'], { timeoutMs: 5_000 })
    .then(
      ran => {
        // A check that timed out or failed to start decides nothing: the next hook asks again.
        if (ran.exitCode === null) guardCheck = null
        return guardLine(ran, $.plugin.root)
      },
      () => {
        guardCheck = null
        return guardLine(null, $.plugin.root)
      },
    )
  return guardCheck
}

/** True while another workflow plugin shares the session: each hook then passes its event on. */
async function standsDown($: EngineInterface): Promise<boolean> {
  return (await guardNow($)) !== null
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    // A new session reads the plugins enabled now (a /clear or /resume fires no
    // session.start, so the check made before it stands); timers an earlier
    // session armed stop.
    guardCheck = null
    if ((await guardNow($)) !== null) {
      S.watchdog?.cancel()
      S.watchdog = null
      S.poll?.cancel()
      S.poll = null
      return next(e)
    }
    S.permissionMode = null
    S.watchedSince = await $.clock.now()
    S.reconciledAt = null
    resetSessionGuards()
    // The timers first: a read below that fails must not leave the session unwatched.
    S.watchdog?.cancel()
    S.watchdog = $.clock.every(WATCHDOG_MS, () => void watchdogTick($).catch(() => undefined))
    S.poll?.cancel()
    S.poll = $.clock.every(POLL_MS, () => void pollTick($).catch(() => undefined))
    await readSession($, true)
    await sweepSnapshots($).catch((error: unknown) => $.ui.toast(`dagents: the check for model switch snapshots other sessions left failed: ${error instanceof Error ? error.message : String(error)}.`))

    return next(e)
  })

  on('command.run', { command: 'dagents:cockpit' }, async ($, e) => {
    const conflict = await guardNow($)
    if (conflict !== null) return { text: conflict }
    const o = await live($)
    const words = e.args.trim().split(/\s+/)
    if (words[0]?.toLowerCase() === 'notify') return notifyCommand($, words.slice(1))
    const wantsSettings = e.args.trim().toLowerCase() === 'settings'
    if (!wantsSettings && e.args.trim() !== '') {
      return { text: `Unknown argument "${e.args.trim()}". Usage: /dagents:cockpit [settings | notify test | notify mention <id>]` }
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
    if (await standsDown($)) return next(e)
    const done = await next(e)
    const o = await live($)
    const now = await $.clock.now()
    const startedAt = (await read($, usage))?.startedAt ?? (await $.session.usage()).startedAt
    const reading: CockpitUsage = { startedAt, readAt: now, limits: limitsOf(e.rateLimits) }
    S.limits = reading.limits
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
    if (await standsDown($)) return next(e)
    const ended = e.reason === 'clear' ? null : await endedEvent($, e.sessionId)
    S.ticker?.cancel()
    S.ticker = null
    // The process goes on after /clear and /resume and no session.start re-arms
    // the timers: keep them, so the poll reads the next session, and start its
    // stall grace now.
    if (e.reason === 'clear' || e.reason === 'resume') S.watchedSince = await $.clock.now()
    else {
      S.watchdog?.cancel()
      S.watchdog = null
      S.poll?.cancel()
      S.poll = null
    }
    S.releaseTimer?.cancel()
    S.releaseTimer = null
    S.heldDone = null
    // A wait of the ended session would ping for it later and, while it is
    // held, keep endWait from restoring the next session's activity.
    for (const wait of S.waits.values()) wait.timer?.cancel()
    S.waits.clear()
    S.waitFrom = null
    S.isMainTurn = false
    await setActivity($, () => IDLE)
    const result = await next(e)
    // Last, so a slow webhook cannot use up the bound every plugin's end hook shares.
    if (ended !== null) await notify($, ended)
    return result
  }).catch(($, e, next) => next(e))

  // A compaction leaves no reading until the next response: drop the stale
  // one and re-arm the note, so it does not stay latched.
  on('session.compact', async ($, e, next) => {
    if (await standsDown($)) return next(e)
    const startedAt = await $.clock.now()
    const done = await next(e)
    if (e.agentId === undefined && e.trigger !== 'precompute' && 'messages' in done && done.messages !== undefined) {
      await update($, budget, () => null)
      await update($, isNudged, () => false)
      await markHandoff($, false)
      // The turns before a compaction say nothing about the context after it.
      await update($, turnTokens, () => [])
      // The estimate stands in until the next response; the old one is the window before.
      await readBreakdown($)
      // The engine's or the person's compaction: the run's rule still applies after it.
      if ((e.trigger === 'auto' || e.trigger === 'manual') && !S.isPaneCompacting) await bookAutoCompaction($, false, await secondsSince($, startedAt))
    }

    return done
  }).catch(($, e, next) => next(e))

  on('agent.spawn', async ($, e, next) => {
    if (await standsDown($)) return next(e)
    const denial = seatDenial(e, (await read($, isPlanSession)) && !(await read($, isFastMode)))
    if (denial !== null) {
      const refusal: CockpitRefusal = { at: await $.clock.now(), tool: 'Agent', line: denial }
      await update($, refusals, list => [...list, refusal].slice(-20))
      return { deny: denial }
    }
    const started = await next(e)
    if (started.deny !== undefined || started.agentId === undefined) return started
    if (isDagents(e.subagentType)) {
      await update($, isPlanSession, () => true)
      await flushSettingNote($)
      if (e.subagentType.split(':')[1]?.startsWith('impl-')) await markRunSession($)
    }
    const spawn: CockpitSpawn = {
      agentId: started.agentId,
      seat: e.subagentType,
      model: started.model,
      description: e.description,
      ...(e.name === undefined ? {} : { name: e.name }),
      isDone: false,
      outcome: null,
      startedAt: await $.clock.now(),
      ...(isJudgeSeat(e.subagentType) ? await judgeReports($, e.prompt) : {}),
    }
    await update($, spawns, list => trimmedSpawns([...list, spawn]))
    await syncTicker($)

    return started
  }).catch(($, e, next) => next(e))

  // Remote Control clients joining and leaving; the terminal raises neither.
  on('session.attach', async ($, e, next) => {
    if (await standsDown($)) return next(e)
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
    if (await standsDown($)) return next(e)
    const expanded = await next(e)
    if (isDagents(e.skill)) {
      await update($, isPlanSession, () => true)
      await flushSettingNote($)
    }
    if (RUN_SKILLS.includes(e.skill)) await markRunSession($)
    return expanded
  }).catch(($, e, next) => next(e))

  on('ui.close', { id: PANE }, async ($, e, next) => {
    if (await standsDown($)) return next(e)
    if (e.origin.kind === 'person') S.isClosedByPerson = true
    await flushSettingNote($)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.detach', async ($, e, next) => {
    if (await standsDown($)) return next(e)
    const left = await next(e)
    await update($, remote, now => ({ ...now, clients: now.clients.filter(one => one.id !== e.clientId) }))
    return left
  }).catch(($, e, next) => next(e))

  // A background shell's end arrives as its task notification, kept as a row
  // of the loop that started it: the main conversation's, or a subagent's,
  // which no prompt.submit announces.
  on('session.append', async ($, e, next) => {
    if (await standsDown($)) return next(e)
    const kept = await next(e)
    if (e.message.role === 'user') {
      const text = e.message.content.map(block => (block.type === 'text' ? block.text : '')).join('\n')
      if (text.includes('<task-notification>')) await endShells($, text)
    } else if (e.message.role === 'assistant' && e.agentId === undefined) {
      const fast = fastModeLine(e.message.content.map(block => (block.type === 'text' ? block.text : '')).join('\n'))
      if (fast === 'session') await update($, isFastSession, () => true)
      if (fast === false) await update($, isFastSession, () => false)
      if (fast !== null) await update($, isFastMode, () => fast !== false)
    }
    return kept
  }).catch(($, e, next) => next(e))

  // A prompt from the person, or auto run's, starts a new chain: the Done held
  // for the last one is dropped. A wake-up keeps it, and so does an origin not
  // listed, since a Done covering more work beats a lost one.
  on('prompt.submit', async ($, e, next) => {
    if (await standsDown($)) return next(e)
    if (e.origin !== undefined && NEW_CHAIN_ORIGINS.has(e.origin.kind)) S.heldDone = null
    // A plain `Process: fast` covers its own request only; a new one from the
    // person ends it, unless a `Process: fast (session)` line is in force.
    if ((e.origin === undefined || NEW_CHAIN_ORIGINS.has(e.origin.kind)) && !(await read($, isFastSession))) await update($, isFastMode, () => false)
    return next(e)
  }).catch(($, e, next) => next(e))

  // A main turn begins: the Now row starts its clock.
  on('turn.start', async ($, e, next) => {
    if (await standsDown($)) return next(e)
    if (e.agentId !== undefined) return next(e)
    S.isMainTurn = true
    S.releaseTimer?.cancel()
    S.releaseTimer = null
    await flushSettingNote($)
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

  // The function-hook tool.check carries no permission mode; the classic hook
  // inputs do, so the mode the session runs in now is read from them.
  on('classic.UserPromptSubmit', async ($, e, next) => {
    if (await standsDown($)) return next(e)
    if (typeof e.permission_mode === 'string' && e.permission_mode !== '') S.permissionMode = e.permission_mode
    return next(e)
  })
  // A subagent's request carries the subagent's mode, not the session's.
  on('classic.PermissionRequest', async ($, e, next) => {
    if (await standsDown($)) return next(e)
    if (e.agent_id === undefined && typeof e.permission_mode === 'string' && e.permission_mode !== '') S.permissionMode = e.permission_mode
    return next(e)
  })

  // Watches the permission decision, never changes it: an "ask" on a call
  // means the person is about to be asked, unless the mode settles it alone.
  on('tool.check', async ($, e, next) => {
    if (await standsDown($)) return next(e)
    const decided = await next(e)
    const id = e.tool_use_id
    const isUnattended = S.permissionMode === null ? S.isUnattended : UNATTENDED_MODES.includes(S.permissionMode)
    if (decided.decision !== 'ask' || id === undefined || isUnattended || ASKING_TOOLS.includes(e.tool) || S.waits.has(id)) return decided
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
  // so an approval waiting on it was given. Drawing may not write state, so
  // the wait settles once this draw is done.
  on('ui.render', { component: 'ToolProgress' }, async ($, e, next) => {
    if (await standsDown($)) return next(e)
    const id = e.props.tool_use_id
    if (S.waits.has(id)) $.clock.after(0, () => void endWait($, id, '✓ Approved'))
    return next(e)
  })

  // The model and effort the main loop's requests go out with, as the status
  // line shows them.
  on('turn.step', async function* ($, raw, next) {
    const e = await launched($, raw)
    if (await standsDown($)) return yield* next(e)
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
    if (await standsDown($)) return next(e)
    const done = await next(e)
    if (e.agentId === undefined) {
      S.isMainTurn = false
      await trackAutoRun($)
      if (e.reason === 'error') await bookApiError($)
      else if (e.reason === 'answer' && S.isApiErrorBooked) {
        S.isApiErrorBooked = false
        await autoRunCall($, await $.session.id(), ['api-error', '--clear'])
      }
      S.compactWindow = await readCompactWindow($)
      await readStyle($)
      await readRun($)
      await onBudget($, await refresh($, (await live($)).tuning, S.compactWindow))
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
      const isHeld = e.reason === 'answer' && (await holdsDone($))
      const turnStartedAt = (await read($, activity)).turnStartedAt ?? stamp - e.durationMs
      if (e.reason !== 'answer') S.heldDone = null
      // A later turn that says nothing keeps the answer the chain last gave.
      else if (isHeld) S.heldDone = { startedAt: S.heldDone?.startedAt ?? turnStartedAt, heldAt: stamp, answer: e.answer.trim() === '' ? (S.heldDone?.answer ?? e.answer) : e.answer }
      await readRemote($)
      await setActivity($, now => ({
        ...IDLE,
        kind: failed ? 'failed' : e.reason === 'aborted' ? 'interrupted' : isHeld ? 'background' : 'idle',
        since: now.since,
        lastTurnMs: e.durationMs,
        endedAt: stamp,
        detail: why,
      }))
      if (failed) {
        await notify(
          $,
          {
            kind: 'error',
            title: `❌ Turn failed${why === null ? '' : `: ${why}`}`,
            detail: `After ${duration(e.durationMs) || '<1m'}. Send a prompt to continue.`,
            isPlain: true,
            fields: await turnFields($),
          },
          undefined,
          async () => void (await update($, activity, now => ({ ...now, isSent: true }))),
        )
      } else if (e.reason === 'answer' && S.questionSentAt !== null && S.questionSentAt >= turnStartedAt) {
        // The ledger's waiting line already said what the turn asks.
        S.heldDone = null
      } else if (e.reason === 'answer' && ASKING_ENDS.test(e.answer.trim())) {
        S.heldDone = null
        await notify(
          $,
          { kind: 'question', title: '❓ Claude is asking', detail: excerpt(e.answer, 300), fields: await turnFields($) },
          undefined,
          async () => void (await update($, activity, now => ({ ...now, isSent: true }))),
        )
      } else if (e.reason === 'answer' && !isHeld) {
        await sendDone($, e.answer, e.durationMs)
      }
      if (e.reason === 'answer') await armAutoRun($, e.answer)
      return done
    }
    const agentId = e.agentId
    // A notification for a finished subagent's loop may never arrive: its
    // shells end with it, recorded spawn or not.
    await update($, shells, list => list.filter(one => one.agentId !== agentId))
    const list = await read($, spawns)
    const spawn = list.find(one => one.agentId === agentId)
    if (spawn === undefined) {
      await syncTicker($)
      return done
    }
    const outcome: 'done' | 'failed' = e.reason === 'answer' ? 'done' : 'failed'
    await update($, spawns, all => all.map(one => (one.agentId === agentId ? { ...one, isDone: true, outcome } : one)))
    for (const [id, wait] of [...S.waits]) if (wait.agentId === agentId) await endWait($, id, '⏹ Agent ended')
    await syncTicker($)
    await settleBackground($)
    if (e.usage !== undefined) await update($, seats, all => addRun(all, spawn.seat, e.usage as TurnUsage))
    await notify($, {
      kind: 'agent',
      title: `🤖 ${shortSeat(spawn.seat)} finished`,
      detail: spawn.description,
      fields: [{ name: 'Took', value: elapsed(e.durationMs) }],
    })

    return done
  })

  on('attribution.text', { kind: 'commit' }, async ($, e, next) => (!(await standsDown($)) && (await live($)).guardAttribution ? { text: '' } : next(e)))
  on('attribution.text', { kind: 'pr' }, async ($, e, next) => (!(await standsDown($)) && (await live($)).guardAttribution ? { text: '' } : next(e)))

  // One hook for every tool: the attribution guard judges before anything
  // runs, and the main loop's budget and plan are read after each call, the
  // only point its context grows between turns.
  on('tool.call', async ($, e, next) => {
    if (await standsDown($)) return next(e)
    const tool = String(e.tool)
    if (e.agentId !== undefined && REVIEW_WRITE_TOOLS.includes(tool)) {
      const denial = await judgeWriteDenial($, tool, e)
      if (denial !== null) {
        try {
          const refusal: CockpitRefusal = { at: await $.clock.now(), tool, line: denial }
          await update($, refusals, list => [...list, refusal].slice(-20))
        } catch {
          // The refusal stands unlisted: the .catch below knows no judge
          // that only $.agent.list() names.
        }
        return { deny: denial }
      }
    }
    const line = (await live($)).guardAttribution ? await attributionLine($, tool, e) : undefined
    if (line !== undefined) {
      const refusal: CockpitRefusal = { at: await $.clock.now(), tool, line }
      await update($, refusals, list => [...list, refusal].slice(-20))
      return { deny: `dagents: this project keeps AI attribution out of git. Remove "${line}" and try again.` }
    }
    const id = e.tool_use_id
    // The guards have judged. What follows before next() only feeds the pane,
    // and a throw here would reach the .catch below, which refuses the call.
    try {
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
      // The response asking for this call already measured the window: show it while the tool
      // runs. Only shown: the note and the alert wait for the ledger this call may write.
      if (e.agentId === undefined) await refresh($, (await live($)).tuning, S.compactWindow, { isShownOnly: true })
    } catch {
      // The pane misses this call; the tool still runs.
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
    const skill = tool === 'Skill' ? String((e as { skill?: unknown }).skill ?? '') : ''
    if (isDagents(skill)) {
      await update($, isPlanSession, () => true)
      await flushSettingNote($)
    }
    if (RUN_SKILLS.includes(skill)) await markRunSession($)
    if (ran.deny === undefined && !ran.isError) await trackShells($, tool, e, ran.result)
    if (e.agentId === undefined) {
      if (ran.deny === undefined && !ran.isError) await trackPlan($, tool, e, ran.result)
      // A run starts, stops and changes regime through the model's own calls.
      await trackAutoRun($)
      // A worktree move takes the session's ledger with it.
      // A shell cd moves it too, as using-git-worktrees' fallback does.
      const isMove = ran.deny === undefined && !ran.isError && (WORKTREE_TOOLS.includes(tool) || (tool === 'Bash' && (await hasMoved($))))
      if (isMove) await readPlace($)
      // The Run card follows the plan this session last named to a plan script.
      let isRebound = false
      if (tool === 'Bash' && ran.deny === undefined && !ran.isError) {
        const named = namedPlan(String((e as { command?: unknown }).command ?? ''))
        if (named !== null && (await read($, boundPlan)) !== named) {
          await update($, boundPlan, () => named)
          isRebound = true
        }
      }
      // The controller writes its ledger with its own tool calls; read it
      // before the budget, which measures a plan's tail by it.
      if (isMove || isRebound || touchesRun(e)) await readRun($)
      await onBudget($, await refresh($, (await live($)).tuning, S.compactWindow))
    }

    return ran
  }).catch(async ($, e, next) => {
    if (!next.called && e.agentId !== undefined && REVIEW_WRITE_TOOLS.includes(String(e.tool)) && isJudgeSeat((await read($, spawns)).find(one => one.agentId === e.agentId)?.seat)) {
      return { deny: `dagents: the review-seat write guard could not check this write (${next.error.message || next.error.kind}); it is refused.` }
    }
    if (next.called) return next(e)
    const tool = String(e.tool)
    const isJudged = tool === 'Bash' ? writesGitText(String((e as { command?: unknown }).command ?? '')) : isGitWriteTool(tool)
    if (!isJudged) return next(e)
    const isGuarded = await live($).then(
      settings => settings.guardAttribution,
      () => true,
    )
    return isGuarded ? { deny: 'dagents: its attribution guard failed; set guardAttribution off to lift it.' } : next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const conflict = await guardNow($)
    if (conflict !== null) {
      const { Text } = $.ui.resolve(e)
      return <Text color="yellow">{conflict}</Text>
    }
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
      if (!(await setOption($, 'layout', 'compact'))) return
      // Under claude plugin test this plugin's own $.ui.close did not run its ui.close hook, so the waiting note goes here.
      await flushSettingNote($)
      await $.ui.close({ id: PANE })
    }
    const head = await read($, budget)
    const spend = await read($, usage)
    const rows = await read($, breakdown)
    const estimate = head === null ? (rows?.total ?? null) : null
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
    const isRunLeft = !autoNow?.active && (await read($, autoRunLeft))
    const isDense = o.density === 'dense'
    const actions = (
      <Box key="actions" flexDirection="row" flexWrap="wrap" columnGap={1}>
        {isRunLeft && (
          <Text key="auto-left" color="yellow">
            auto run left by a closed session — run scripts/auto-run stop --stale
          </Text>
        )}
        {autoNow?.active && (
          <Text key="auto-line" color="magenta">
            {`Auto run · ${autoNow.phase} · ${autoNow.regime} · ${autoNow.compactions} ${autoNow.compactions === 1 ? 'compaction' : 'compactions'} · ${autoNow.resumes} ${autoNow.resumes === 1 ? 'resume' : 'resumes'}`}
          </Text>
        )}
        {autoNow?.active && autoNow.mismatch !== null && (
          <Text key="auto-mismatch" color="warning">
            {`version mismatch — run ${autoNow.mismatch.run}, this call ${autoNow.mismatch.call}`}
          </Text>
        )}
        {autoNow?.active && button('pane-stop-auto', '■ Stop auto', () => void stopAutoRun($), { isCompact: isDense })}
        {canHandOff && !autoNow?.active && button('pane-handoff', '↪ Hand off', () => $.prompt.submit({ text: HANDOFF_PROMPT, asUser: true }), { hotkey: 'h', isMain: isNearHandoff, isCompact: isDense })}
        {button('pane-compact', '⇣ Compact', () => compactFromPane($), { hotkey: 'c', isCompact: isDense })}
      </Box>
    )
    // The pane's own buttons, in a row below the account: they act on the pane, not the context.
    const controls = (
      <Box key="pane-controls" flexDirection="row" flexWrap="wrap" columnGap={1}>
        {button('pane-density', isDense ? '☰ Detailed' : '≡ Dense', () => setOption($, 'density', isDense ? 'detailed' : 'dense'), { hotkey: 'd', isCompact: isDense })}
        {button('pane-settings', '⚙ Settings', () => showSettings($), { hotkey: 's', isCompact: isDense })}
        {canMinimize && (isDesktop || !isCompact) && button('pane-minimize', '▁ Minimize', minimize, { hotkey: 'm', isCompact: isDense })}
      </Box>
    )

    if ((await read($, view)) === 'settings') {
      // Each press saves to ~/.dagents/config.json and puts the value in force, so the rows below always show what is saved.
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
        <Box key={key} flexDirection="row" flexWrap="wrap" columnGap={isDesktop ? 'xs' : 1} rowGap={isDesktop ? 'xs' : undefined} flexShrink={1}>
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
                // A save ends a pending reset like any other press, but the
                // field stays mounted: closing it here would drop the text of
                // an entry that is then refused.
                await update($, settingsView, now => ({ ...now, isConfirmingReset: false }))
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
                !canType && notes.url === null && <Text key="set-notify-url-cli" dimColor>set it in /dagents:cockpit settings in a terminal, or with DAGENTS_NOTIFY_URL</Text>,
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
      // Every press but the one that asked for it ends an edit, a webhook or
      // mention field's included, or a pending reset.
      const show = async (change: Partial<CockpitSettingsView>) => {
        if ((await read($, notifier)).editing !== null) await update($, notifier, now => ({ ...now, editing: null, error: null }))
        await update($, settingsView, now => ({ ...now, editing: null, error: null, isConfirmingReset: false, ...change }))
      }
      const save = async (key: string, value: SettingValue) => {
        if (state.editing !== null || state.isConfirmingReset) await show({})
        return set(key, value)
      }
      // A segment's chip on either line: on adds it last there and moves it off the other.
      const bandChips = (index: 0 | 1) => {
        const key = `set-bandLine${index + 1}`
        const line = o.bandLayout[index]
        return (
          <Box key={`${key}-chips`} flexDirection="column" flexShrink={1}>
            <Text key={`${key}-order`} dimColor wrap="truncate-end">
              {line.length === 0 ? 'hidden' : line.join(' · ')}
            </Text>
            {chips(
              key,
              BAND_SEGMENTS,
              name => line.includes(name as BandSegment),
              name => name,
              async name => {
                const [one, two] = bandLineToggled(o.bandLayout, index, name as BandSegment)
                if (one !== o.bandLine1) await save('bandLine1', one)
                if (two !== o.bandLine2) await save('bandLine2', two)
              },
            )}
          </Box>
        )
      }
      const custom: Record<string, RenderChildren> = {
        bandLine1: bandChips(0),
        bandLine2: bandChips(1),
        sections: chips(
          'set-section',
          SECTIONS,
          name => o.shown.includes(name as Section),
          name => name,
          name => save('sections', sectionsToggled(o.shown, name as Section)),
        ),
        collapsed: chips(
          'set-collapsed',
          SECTIONS,
          name => o.shownCollapsed.includes(name as Section),
          name => name,
          name => save('collapsed', collapsedToggled(o.shownCollapsed, name as Section)),
        ),
        notifyOn: chips(
          'set-notify-kind',
          NOTIFY_KINDS,
          kind => S.kinds.includes(kind as NotifyKind),
          kind => kindLabel(kind as NotifyKind),
          kind => save('notifyOn', notifyKindsToggled(S.kinds, kind as NotifyKind)),
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
    const work = { shells: background.filter(one => (one.agentId ?? null) === null), agents: running.length }
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
      return drawBand(
        $,
        e,
        async () => {
          if ((await setOption($, 'layout', isInline ? 'full' : 'auto')) && isInline) await $.ui.open(paneFor('full'))
        },
        e.props.bodyColumns,
      )
    }

    if (isDense) {
      // A task waiting on the person is the one to name: the row is all the dense layout has.
      const waiting = summary?.tasks.find(task => task.state === 'waiting') ?? null
      const inFlight = summary?.tasks.find(task => task.state === 'assigned') ?? null
      const current =
        waiting !== null ? `? Task ${waiting.n} waiting${waiting.question === null ? '' : `: ${waiting.question}`}`
        : inFlight === null ? null
        : `Task ${inFlight.n}${inFlight.title === '' ? '' : `: ${inFlight.title}`}`
      const dense: DenseInput = {
        email: who?.email ?? null,
        billing,
        remote: remoteRuns(remoteNow.clients, remoteNow.setting),
        context: head === null ? null : { tokens: head.tokens, limit: head.limit },
        estimate,
        turnsLeft: head === null ? null : turnsToBudget(await read($, turnTokens), head.limit),
        limits,
        shells: background,
        agents: running.map(one => shortSeat(one.seat)),
        run: summary === null || summary.total === 0 ? null : { done: summary.done, total: summary.total, current },
        todos: items.length === 0 ? null : { done: doneCount, total: items.length, current: items.find(item => item.status === 'in_progress')?.text ?? null },
        repo: git,
        refused: refused.length,
        isGuardOn: o.guardAttribution,
        now,
      }
      const rows = o.shown.flatMap(name => {
        const runs = denseLine(name, dense)
        return runs === null ? [] : [{ key: `dense-${name}`, runs: runsCut(runs, room) }]
      })
      return (
        <Box flexDirection="column">
          {resumeCard}
          <Box key="dense-now" flexDirection="row" alignItems="center" columnGap={1}>
            <Box key="dense-now-text" flexGrow={1} flexShrink={1}>
              <Text key="now" wrap="truncate-end">
                {drawRuns('now', nowLine(actNow, now, work))}
              </Text>
            </Box>
          </Box>
          {!rows.some(row => row.key === 'dense-account') && controls}
          {rows.map(row => [
            <Box key={row.key}>
              <Text wrap="truncate-end">{drawRuns(row.key, row.runs)}</Text>
            </Box>,
            row.key === 'dense-account' && controls,
          ])}
          {actions}
        </Box>
      )
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
    const seatText = (seat: CockpitSeat) => seatCounts(totalIn(seat), cacheShare(seat), seat.output)
    // The details sit INDENT cells in: the bar takes what the counts leave.
    const seatBar = (seat: CockpitSeat) => seatBarCells(inner - INDENT, seatText(seat))
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
    }
    // The breakdown is an estimate the session has from its start, a reading or not.
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

    const engineNow = await read($, engine)
    const turnsLeft = head === null ? null : turnsToBudget(await read($, turnTokens), head.limit)
    const isFinishingPast = head !== null && head.isFinishing && head.tokens >= head.limit
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
          if (task.state === 'deferred') {
            return (
              <Text key={`plan-${task.n}`} dimColor wrap="truncate-end">
                ⏭ {label} · deferred
              </Text>
            )
          }
          if (task.state === 'waiting') {
            return (
              <Box key={`plan-${task.n}`} flexDirection="column">
                <Text color={BUTTON_MAIN} bold wrap="truncate-end">
                  ? {label}
                </Text>
                {task.question !== null && (
                  <Box paddingLeft={INDENT}>
                    <Text color={BUTTON_MAIN} wrap="truncate-end">
                      {task.question}
                    </Text>
                  </Box>
                )}
              </Box>
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
            {estimate === null ? 'no reading yet' : `≈${kTokens(estimate)} estimated`}
          </Text>
        ) : (
          <Text key="ctx-head">
            <Text color={rampColor((head.tokens / head.limit) * 100)} bold>
              {Math.round((head.tokens / head.limit) * 100)}% of handoff
            </Text>
            {turnsLeft !== null && !isFinishingPast && (
              <Text color={turnsLeft <= 3 ? '#ffaf5f' : undefined} bold={turnsLeft <= 3} dimColor={turnsLeft > 3}>
                {' '}
                · ≈{turnsLeft} {turnsLeft === 1 ? 'turn' : 'turns'}
              </Text>
            )}
            {isFinishingPast && <Text dimColor> · finishing</Text>}
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
              <Text>{clip(commandLine(shell.command), Math.max(10, inner - 10))}</Text>
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
                  {seatBar(seat) > 0 && <Text color="magenta">{bar(totalIn(seat) / mostIn, seatBar(seat)).replace(/▱+$/, rest => ' '.repeat(rest.length))} </Text>}
                  <Text bold>{seatText(seat).slice(0, seatText(seat).indexOf(' '))}</Text>
                  <Text dimColor>{seatText(seat).slice(seatText(seat).indexOf(' '))}</Text>
                </Text>
              </Box>
            )),
          ),
      ),
      // In a dagents run the card reads the run's ledger instead: the
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
        )
        ) : (
          finishNow !== null &&
          finishLine(finishNow).length > 0 &&
          section(
            'plan',
            'Plan',
            'yellow',
            <Text key="plan-head" dimColor>
              no plan
            </Text>,
            <Text key="plan-finish" wrap="truncate-end">
              {drawRuns('plan-finish-runs', finishLine(finishNow))}
            </Text>,
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
      guard: section(
        'guard',
        'Guard',
        'red',
        refused.length > 0 ? (
          <Text key="guard-head" color="red" bold>
            {refused.length} refused
          </Text>
        ) : (
          <Text key="guard-head" dimColor>
            {o.guardAttribution ? 'on · none refused' : 'off'}
          </Text>
        ),
        refused.slice(-3).map((refusal, index) => (
          <Text key={`guard-${refusal.at}-${index}`} wrap="truncate-end">
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
          const breakdownLines: PanelLine[] = []
          if (breakdownShown.length > 0) {
            const colorOf = (index: number) => BREAKDOWN_COLORS[index % BREAKDOWN_COLORS.length] ?? BREAKDOWN_COLORS[0]
            const used = breakdownShown.reduce((sum, row) => sum + row.tokens, 0)
            breakdownLines.push({ kind: 'picture', svg: stackSvg(breakdownShown.map(row => row.tokens), breakdownShown.map((_, index) => colorOf(index)), width, 8) })
            for (const [index, row] of breakdownShown.entries()) {
              breakdownLines.push({
                kind: 'text',
                left: [{ text: '■ ', color: paint(colorOf(index)) }, { text: row.name }],
                right: [{ text: kTokens(row.tokens), bold: true }, { text: `${String(Math.round((row.tokens / Math.max(1, used)) * 100)).padStart(4)}%`, dim: true, mono: true }],
              })
            }
          }
          if (head === null) {
            return panel('context', 'Context', 'cyan', [{ text: estimate === null ? 'no reading yet' : `≈${kTokens(estimate)} estimated` }], breakdownLines, actions)
          }
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
          lines.push(...breakdownLines)
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
            background.map(shell => ({ kind: 'text', left: [{ text: `$ ${commandLine(shell.command)}`, mono: true }], right: [{ text: elapsed(now - shell.startedAt), mono: true, dim: true }] })),
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
                right: [{ text: seatCounts(totalIn(seat), cacheShare(seat), seat.output), mono: true, dim: true }],
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
            if (finishNow !== null && finishLine(finishNow).length > 0) lines.push({ kind: 'chips', chips: [{ ...pill(finishLine(finishNow).map(run => run.text).join('')), color: 'yellow' }] })
            for (const task of runList(summary.tasks, 6)) {
              const label = `Task ${task.n}${task.title === '' ? '' : `: ${task.title}`}`
              const meta =
                task.state === 'complete' ? (task.isClean ? 'reviewed clean' : null)
                : task.state === 'deferred' ? 'deferred'
                : task.state === 'waiting' ? task.question
                : task.state === 'blocked' ? `BLOCKED${task.reason === null ? '' : ` · ${task.reason}`}`
                : task.state === 'assigned' && (task.round !== null || task.seat !== null)
                  ? [task.round === null ? 'implementing' : `round ${task.round}`, task.seat === null ? null : shortSeat(task.seat)].filter(Boolean).join(' · ')
                  : null
              const icon: PanelRun =
                task.state === 'complete' ? { text: '✓', color: 'green' }
                : task.state === 'deferred' ? { text: '⏭', faint: true }
                : task.state === 'waiting' ? { text: '?', color: 'magenta' }
                : task.state === 'blocked' ? { text: '✗', color: 'red' }
                : task.state === 'assigned' ? { text: '▸', color: 'blue' }
                : { text: '○', faint: true }
              lines.push({
                kind: 'text',
                left: [
                  { ...icon, text: `${icon.text}  ` },
                  {
                    text: label,
                    bold: task.state === 'assigned' || task.state === 'blocked' || task.state === 'waiting',
                    color: task.state === 'blocked' ? 'red' : task.state === 'waiting' ? 'magenta' : undefined,
                    dim: task.state === 'pending' || task.state === 'deferred',
                  },
                ],
              })
              const metaColor = task.state === 'blocked' ? 'red' : task.state === 'waiting' ? 'magenta' : undefined
              if (meta !== null) lines.push({ kind: 'text', small: true, indent: 18, left: [{ text: meta, color: metaColor, dim: metaColor === undefined }] })
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
            return finishChips.length > 0 && panel('plan', 'Plan', 'yellow', [{ text: 'no plan' }], finishChips)
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
        guard: panel(
          'guard',
          'Guard',
          'red',
          refused.length > 0 ? [{ text: `${refused.length} refused`, color: 'red' }] : [{ text: o.guardAttribution ? 'on · none refused' : 'off', dim: true }],
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
          {controls}
          <Box key="now-row" flexDirection="row" alignItems="center" columnGap={1}>
            <Box key="now-box" flexGrow={1} flexShrink={1}>
              <Text key="now" wrap="truncate-end">
                {drawRuns('now', nowLine(actNow, now, work))}
              </Text>
            </Box>
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
          {drawRuns('now', nowLine(actNow, now, work))}
        </Text>
        {!o.shown.includes('account') && controls}
        {o.shown.map(name => (name === 'account' ? [byName[name], controls] : byName[name]))}
        {!o.shown.includes('context') && actions}
      </Box>
    )
  })

  // Minimized, the band sits above the prompt in place of the pane. A handoff
  // to resume rides above it, or alone while the pane is open.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const conflict = await guardNow($)
    if (conflict !== null) {
      const { Text } = $.ui.resolve(e)
      return <Text color="yellow">{conflict}</Text>
    }
    const o = await live($)
    const offer = await offerNow($, await $.clock.now())
    const band = o.isMinimized ? await drawBand($, e, () => expand($, e.viewport?.isFullscreen === true), e.props.bodyColumns) : null
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
            {`↻ Resumable work · ${handedOff((await $.clock.now()) - offer.at)}${offer.isRechecked ? '' : ' · not rechecked'}`}
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

/** The minimized cockpit's band, `room` cells wide: drawn in the pane or above the prompt. */
async function drawBand($: EngineInterface, e: RenderInput<'Pane' | 'AbovePrompt'>, onExpand: () => unknown, room: number) {
  const table = $.ui.resolve(e)
  const { Box, Button, Text } = table
  const Svg = e.surface === 'desktop' && 'Svg' in table ? table.Svg : undefined
  const isDesktop = Svg !== undefined
  const now = await $.clock.now()
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
  const layout = (await live($)).bandLayout
  const engineNow = await read($, engine)
  const doing = await read($, activity)
  const inFlight = summary === null || summary.isFinished ? [] : summary.tasks.filter(task => task.state === 'assigned' && task.round !== null)
  const band: BandInput = {
    lines: layout,
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
    model: engineNow.model,
    effort: engineNow.effort,
    style: engineNow.style ?? null,
    cache: engineNow.cache,
    usd: head?.usd ?? null,
    turn:
      doing.kind === 'running'
        ? { kind: 'running', since: doing.turnStartedAt ?? doing.since, tool: doing.tool }
        : doing.kind === 'waiting' || doing.kind === 'asking' || doing.kind === 'failed'
          ? { kind: doing.kind, since: doing.since, tool: null }
          : null,
    run:
      summary === null || summary.isFinished
        ? null
        : { done: summary.done, total: summary.total, round: inFlight.length === 1 ? (inFlight[0]?.round ?? null) : null, blocked: summary.tasks.filter(task => task.state === 'blocked').length },
    isBackground: doing.kind === 'background',
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
    const picked = [...layout[0], ...layout[1]]
    const meters: BandMeter[] = [
      ...(head === null || !picked.includes('ctx')
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
      ...band.limits.filter(limit => picked.includes(limitLabel(limit.kind) as BandSegment)).map((limit): BandMeter => {
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
      ...(engineNow.cache === null || !picked.includes('cache')
        ? []
        : [{ key: 'Cache', percent: engineNow.cache * 100, share: engineNow.cache, color: rampColor(100 - engineNow.cache * 100), tick: null, note: [] }]),
    ]
    // The picked readings that are words, not meters, in the order picked.
    const said = bandLines({ ...band, lines: [picked.filter(name => BAND_WORDS.includes(name)), []] }, 0)[0]
    const facts: PanelRun[] = [
      ...(running.length === 0 || !picked.includes('agents') ? [] : [{ text: '● ', color: 'green' }, { text: `${running.length} ${running.length === 1 ? 'agent' : 'agents'} running` }, { text: '   ' }]),
      ...(background.length === 0 || !picked.includes('shells')
        ? []
        : [{ text: '$ ', color: 'yellow', mono: true }, { text: `${background.length} ${background.length === 1 ? 'shell' : 'shells'}` }, { text: ` · longest ${shellAge(band.shells.longest)}`, dim: true }, { text: '   ' }]),
      ...(where === null || !picked.includes('dir') ? [] : [{ text: where.root === null ? (where.cwd.split(/[\\/]/).pop() ?? where.cwd) : repoName(where.remote ?? null, where.root), bold: true }]),
    ]
    const chips: PanelRun[] =
      git === null || !picked.includes('git')
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
      ...(said.length > 0 ? [{ kind: 'text', left: said } as PanelLine] : []),
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
  // The handoff mark last written beside the turn stamp, as `<session>:<due>`.
  handoffMark: '',
  // Saved or environment values the settings in force ignored, for the settings view.
  settingProblems: [] as string[],
  // The session read's steps that threw: the slow poll tick runs each again.
  sessionUnread: [] as (() => Promise<unknown>)[],
  // The problem line for a settings file that does not parse (C15), while it does not; null otherwise.
  brokenConfig: null as string | null,
  // Keys something outside the settings file forces, with the words their rows show.
  locks: {} as Record<string, string>,
  // Skill-enforced settings changed since the model was last told, with their new values.
  changed: {} as Record<string, SettingValue>,
  // Claude keys this session saved: the engine's settings snapshot may not show another process's write at once.
  claudeSaved: {} as Record<string, SettingValue | undefined>,
  kinds: [] as NotifyKind[],
  isBrief: false,
  notifyAskAfter: 20,
  where: { host: null, tmux: null, primary: null, checkout: null } as {
    host: string | null
    tmux: string | null
    primary: string | null
    // The work tree the session is in: a linked worktree's own, where
    // $.session.repo() names the main working tree.
    checkout: string | null
  },
  // An approval or question the person has not answered yet, by tool call: its
  // timer, the Discord message sent for it (edited once it is answered), and
  // the subagent whose approval it is.
  waits: new Map<string, { timer: Timer | null; messageId: string | null; event: NotifyEvent; agentId: string | null }>(),
  // The activity the first open wait replaced, given back when the last wait
  // ends outside a main turn.
  waitFrom: null as CockpitActivity | null,
  ticker: null as Timer | null,
  isTurnLive: false,
  // Whether a main-loop turn is running; a subagent's approval wait does not set it, as it does isTurnLive.
  isMainTurn: false,
  isBudgetSent: false,
  // The pane's Compact runs: it books its compaction itself.
  isPaneCompacting: false,
  // Ledger events already seen, by the plan the ledger names; the first read
  // of a plan's ledger only records them, so a reload, a re-read or a resumed
  // plan sends nothing twice.
  ledgerSeen: new Map<string, Set<string>>(),
  // When sendLedgerEvents last sent a task's waiting question: that turn's Done is the question.
  questionSentAt: null as number | null,
  // The settings' default mode is unattended; read only until an event carries the session's mode.
  isUnattended: false,
  // The permission mode the last classic hook input carried; null before one.
  permissionMode: null as string | null,
  // Whether this Claude Code draws a Button's label from styled children,
  // so the hotkey's letter can be underlined in it.
  canUnderline: null as boolean | null,
  // The person closed the pane this session: a desktop joining reopens nothing.
  isClosedByPerson: false,
  // The auto run's scheduled stage, at most one.
  autoTimer: null as Timer | null,
  // True while autoAct runs a stage, a long compaction included, and when it
  // last finished one: a prompt it just submitted has not started its turn yet.
  autoBusy: false,
  autoActedAt: null as number | null,
  // When this session started: one with no turn yet ages from it.
  watchedSince: null as number | null,
  // The model and effort of the auto run's launch command, for the session it
  // cleared into: that session's main-loop requests go out on them, so the
  // person's settings never change. Kept outside $.state, which /clear wipes.
  launch: null as { session: string; model: string; effort: Effort | null } | null,
  // When background work began deferring the pending stage; null while nothing
  // does or a turn is live.
  autoDeferredSince: null as number | null,
  // When the last stalled call failed: the watchdog waits STALL_MS before the next.
  stallFailedAt: null as number | null,
  // A main turn of the bound run ended on an API error the run booked: the next
  // turn that answers clears the count. The timer sends the re-prompt.
  isApiErrorBooked: false,
  apiErrorTimer: null as Timer | null,
  // When the watchdog last submitted a reconcile prompt, and how many in a row
  // found the same launches running under the same pending action.
  reconciledAt: null as number | null,
  reconcileSeen: { key: '', count: 0 },
  // The watchdog's timer, every WATCHDOG_MS.
  watchdog: null as Timer | null,
  // Each handoff read for the offer, by path: the modification time it was
  // read at, its text and its age (its marker's at, else the file's time).
  offerTexts: new Map<string, { mtime: number; text: string; at: number; subject: string | null }>(),
  // The cache key of the last offer run started (handoff list, then next-step
  // --print --handoff per candidate), and whether one is in flight: one at a
  // time, never awaited.
  offerRanKey: null as string | null,
  isOfferRunning: false,
  // A Done held while the main conversation's background work runs: when its
  // chain of turns began, when a turn last ended with the work pending, and
  // that turn's answer, which a Done released with no turn carries.
  heldDone: null as { startedAt: number; heldAt: number; answer: string } | null,
  // Sends the held Done if no turn starts within RELEASE_GRACE_MS of the work ending.
  releaseTimer: null as Timer | null,
  // The last rate-limit windows read and the limits already alerted: /clear empties $.state but not these.
  limits: [] as CockpitUsage['limits'],
  alerted: [] as string[],
  // The poll's timer, whether a tick is running, how many ran, and when the slower readings last ran.
  poll: null as Timer | null,
  isPolling: false,
  polls: 0,
  // The settings' autoCompactWindow, read at the start and after each main
  // turn rather than on every tool call.
  compactWindow: undefined as number | undefined,
  detailAt: 0,
  // The settings file's modification time and the engine's settings, as last put in force.
  seen: { config: null as number | null, claude: '' },
  // The ledger, its modification time and its plan's, as the run was last read; the plan file found then.
  runKey: '',
  runPlan: null as string | null,
  runReads: 0,
  // The absolute path of the handoff the resume offer last named.
  latestName: null as string | null,
  // The ledger directory's workspaces and its modification time when listed.
  ledgerDirs: { base: '', at: null as number | null, names: [] as string[] },
  // Discord messages go out one at a time; the tail of the queue.
  outbox: Promise.resolve() as Promise<void>,
}

async function endedEvent($: EngineInterface, sessionId: string): Promise<NotifyEvent> {
  const head = await read($, budget)
  const started = (await read($, usage))?.startedAt
  const stamp = await $.clock.now()
  return {
    kind: 'session',
    title: '🏁 Session ended',
    detail: `claude --resume ${sessionId}`,
    isPlain: true,
    fields: [
      ...(started === undefined ? [] : [{ name: 'Took', value: elapsed(stamp - started) }]),
      ...(head?.usd == null ? [] : [{ name: 'Cost', value: `$${head.usd.toFixed(2)}` }]),
    ],
  }
}

// How long a hook waits for its Discord message before it goes on; the
// message still goes out, behind the ones queued before it.
const NOTIFY_WAIT_MS = 1000
// How long one Discord request may stay unanswered before the queue moves on.
const SEND_LIMIT_MS = 8000

/**
 * Queues one event for Discord when it is on, and waits no longer than
 * NOTIFY_WAIT_MS for it, so a slow or hung webhook never holds a hook. The
 * messages go out one at a time in order. `onSent` runs when Discord took it,
 * given the message id, whether or not the caller still waits.
 */
async function notify($: EngineInterface, event: NotifyEvent, editId?: string, onSent?: (id: string) => Promise<void>): Promise<void> {
  if (!S.kinds.includes(event.kind)) return
  const job = S.outbox.then(() => deliver($, event, editId, onSent)).catch(() => undefined)
  S.outbox = job
  let timer = null as Timer | null
  const late = new Promise<void>(resolve => {
    timer = $.clock.after(NOTIFY_WAIT_MS, resolve)
  })
  await Promise.race([job, late])
  timer?.cancel()
}

// Sends one queued event; the message id goes to `onSent` when Discord took it.
async function deliver($: EngineInterface, event: NotifyEvent, editId?: string, onSent?: (id: string) => Promise<void>) {
  const state = await read($, notifier)
  if (state.url === null) return
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
    if (sent.id !== null) await onSent?.(sent.id)
    return
  }
  // A failed send shows in the settings' Discord row, never as a pop-up.
  await update($, notifier, now => ({ ...now, last: { at: stamp, text: sent.reason, isError: true } }))
}

/**
 * Sends a turn's Done, timed from the start of the held chain when one is
 * held, else from the turn alone; one under notifyAfter sends nothing. With
 * no answer of its own it carries the held turn's.
 */
async function sendDone($: EngineInterface, answer: string, durationMs: number) {
  const held = S.heldDone
  S.heldDone = null
  const took = held === null ? durationMs : (await $.clock.now()) - held.startedAt
  if (took < Math.max(0, (await live($)).notifyAfter) * 1000) return
  const text = answer.trim() === '' ? (held?.answer ?? '') : answer
  await notify(
    $,
    {
      kind: 'done',
      title: `✅ Done in ${elapsed(took)}`,
      detail: text.trim() === '' ? undefined : excerpt(text, 300),
      fields: await turnFields($),
    },
    undefined,
    async () => void (await update($, activity, now => ({ ...now, isSent: true }))),
  )
}

/**
 * Whether the main conversation still waits on work it sent to the background:
 * its own shells short of a service, or a subagent still running. Given
 * `since`, only work started at or after it counts.
 */
async function isMainBackground($: EngineInterface, since = -Infinity): Promise<boolean> {
  if ((await read($, spawns)).some(one => !one.isDone && one.startedAt >= since)) return true
  return (await read($, shells)).some(one => (one.agentId ?? null) === null && !isServiceCommand(one.command) && one.startedAt >= since)
}

/**
 * Whether background work holds a Done. No hold outlasts DEFER_CAP_MS, so work
 * already running that long holds none: it also bounds a row whose end was
 * never heard.
 */
async function holdsDone($: EngineInterface): Promise<boolean> {
  return isMainBackground($, (await $.clock.now()) - DEFER_CAP_MS)
}

/**
 * The background work ended with no turn live: the Now row goes idle, and a
 * held Done waits RELEASE_GRACE_MS for the turn the work's notification wakes.
 */
async function settleBackground($: EngineInterface) {
  if ((await read($, activity)).kind !== 'background' || (await holdsDone($))) return
  await setActivity($, now => ({ ...now, kind: 'idle' }))
  S.releaseTimer?.cancel()
  S.releaseTimer = $.clock.after(RELEASE_GRACE_MS, () => void releaseHeld($).catch(() => undefined))
}

async function releaseHeld($: EngineInterface) {
  S.releaseTimer = null
  if (S.heldDone !== null && !S.isMainTurn) await sendDone($, '', 0)
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
  const before = await read($, activity)
  if (before.kind !== 'waiting' && before.kind !== 'asking') S.waitFrom = before
  await setActivity($, now => ({ ...now, kind, since: stamp, detail: event.detail ?? null, isSent: false }))
  const send = async () => {
    const wait = S.waits.get(id)
    if (wait === undefined) return
    wait.timer = null
    await notify($, event, undefined, async messageId => {
      wait.messageId = messageId
      await update($, activity, now => (now.kind === kind ? { ...now, isSent: true } : now))
    })
  }
  const delay = Math.max(0, S.notifyAskAfter) * 1000
  S.waits.set(id, { timer: delay === 0 ? null : $.clock.after(delay, () => void send()), messageId: null, event, agentId })
  if (delay === 0) await send()
}

// Back to running once nothing S.waits on the person, or, after the main
// turn ended, back to how it ended: a subagent's wait never leaves a turn
// live that no turn will end, which would hold the auto run's stages.
async function endWait($: EngineInterface, id: string, outcome: string) {
  await settleWait($, id, outcome)
  if (S.waits.size > 0) return
  const before = S.waitFrom
  S.waitFrom = null
  const kind = S.isMainTurn ? 'running' : S.heldDone !== null ? 'background' : null
  await setActivity($, now => {
    if (now.kind !== 'waiting' && now.kind !== 'asking') return now
    if (kind !== null) return { ...now, kind, detail: null, isSent: false }
    if (before === null || before.kind === 'running') return { ...now, kind: 'idle', detail: null, isSent: false }
    return { ...now, kind: before.kind, since: before.since, detail: before.detail, isSent: before.isSent }
  })
  if (kind === 'background') await settleBackground($)
}

// The auto run state file in the primary checkout; null when there is none.
async function autoRunText($: EngineInterface): Promise<string | null> {
  const root = S.where.primary ?? (await read($, place))?.root ?? null
  if (root === null) return null
  const text = await $.fs.read(`${root}/.dagents/sdd/auto-run.json`).catch(() => null)
  return typeof text === 'string' ? text : null
}

// The auto run state file's run, as the run bound to this session; null when
// there is none or another session owns it.
async function readAutoRun($: EngineInterface): Promise<CockpitAutoRun | null> {
  const text = await autoRunText($)
  return text === null ? null : autoRunFor(text, await $.session.id())
}

// Whether a session's cockpit still beats, by the heartbeat beat() writes,
// as ar_is_stale judges it (session_gone in scripts/lib/session-live.sh,
// AR_BEAT_SECONDS). The engine gives a mod no process id or signal API, so the
// beat's age is all there is. A beat up to BEAT_SECONDS ahead is clock skew
// and reads as now.
// No beat file is a dead session; null, unknown, is a beat that reads as no
// time (a write caught midway), a beat file that exists but cannot be read,
// or a check that failed, which callers must not act on as a death.
const BEAT_SECONDS = 180
async function isSessionAlive($: EngineInterface, sid: string): Promise<boolean | null> {
  try {
    const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
    if (!home) return null
    const path = `${home.replace(/[\\/]+$/, '')}/.claude/dagents/sessions/cockpit/${sid.replace(/[^A-Za-z0-9]/g, '-')}`
    const text = await $.fs.read(path).catch(() => null)
    if (text === null) return (await $.fs.exists(path)) ? null : false
    const first = String(text).split(/\r?\n/)[0]?.trim() ?? ''
    if (!/^[0-9]+$/.test(first)) return null
    const age = Math.floor((await $.clock.now()) / 1000) - Number(first)
    return age >= -BEAT_SECONDS && age <= BEAT_SECONDS
  } catch {
    return null
  }
}

// Runs scripts/auto-run as `sessionId` in the session's checkout, where its
// handoff lives; resolves its exit code, 1 when it could not run.
async function autoRunCall($: EngineInterface, sessionId: string, args: string[]): Promise<number> {
  const session = S.where.checkout
  const isGone = session !== null && session !== S.where.primary && (await $.fs.stat(session).catch(() => null))?.kind !== 'dir'
  const checkout = (isGone ? S.where.primary : session) ?? S.where.primary ?? '.'
  // The directory travels in argv: no cockpit call passes $.process.run a cwd.
  const argv = ['bash', '-c', 'cd -- "$1" && shift && exec bash "$@"', 'auto-run', checkout, `${$.plugin.root}/scripts/auto-run`, '--session', sessionId, ...args]
  const ran = await $.process.run(argv, { timeoutMs: 15_000 }).catch(() => null)
  return ran?.exitCode ?? 1
}

// Keeps the pane's copy of the bound run, and says once on Discord when the
// run stopped with a reason.
async function trackAutoRun($: EngineInterface) {
  const text = await autoRunText($)
  const id = await $.session.id()
  const now = text === null ? null : autoRunFor(text, id)
  const owner = now === null && text !== null ? activeRunOwner(text) : null
  const isLeft = owner !== null && owner !== id && (await isSessionAlive($, owner)) === false
  if ((await read($, autoRunLeft)) !== isLeft) await update($, autoRunLeft, () => isLeft)
  const before = await read($, autoRun)
  if (JSON.stringify(now) === JSON.stringify(before)) return
  await update($, autoRun, () => now)
  // The run moved the ledger the offer's cache key leaves out: recompute once it ends.
  if (before?.active === true && now?.active !== true) S.offerRanKey = null
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
// or switch: `auto-run clear --phase`, then the same path as clear.
// Each attempt first re-checks that the stage is still due and the session
// idle. A failure is booked and the failed stage tried again; the script stops
// the run at the second (exit 5).
async function autoAct($: EngineInterface, stage: AutoStage) {
  S.autoTimer = null
  // The watchdog arms nothing while a stage is in flight.
  S.autoBusy = true
  try {
    await autoStage($, stage)
  } finally {
    S.autoBusy = false
    S.autoActedAt = await $.clock.now()
  }
}

// A launch that never reports would hold the stage forever: book it as a
// failure, so the second one stops the run with a reason.
async function bookStageFailure($: EngineInterface, stage: AutoStage, why: string) {
  S.autoDeferredSince = null
  const owner = await $.session.id()
  const code = await autoRunCall($, owner, ['failure', '--reason', why])
  if (code === 0) scheduleAutoAct($, stage, AUTO_RETRY_MS)
  else if (code === 5) await endStoppedRun($)
  else await endUnboundRun($, owner, `${why}, and the failure could not be booked (exit ${code})`)
}

async function autoStage($: EngineInterface, stage: AutoStage) {
  const auto = await readAutoRun($)
  if (auto === null || !auto.active || auto.pending !== AUTO_STAGE_PENDING[stage]) {
    // The run stopped or moved on: its deferral, if any, ends with it.
    S.autoDeferredSince = null
    return
  }
  const isBackground = await isMainBackground($)
  if (S.isTurnLive || isBackground) {
    const stamp = await $.clock.now()
    // Only background work with no turn live counts toward the cap: a live
    // turn restarts it.
    S.autoDeferredSince = S.isTurnLive ? null : (S.autoDeferredSince ?? stamp)
    if (S.autoDeferredSince === null || stamp - S.autoDeferredSince < DEFER_CAP_MS) {
      scheduleAutoAct($, stage, AUTO_RETRY_MS)
      return
    }
    await bookStageFailure($, stage, `a background launch kept the ${stage} waiting 30 minutes`)
    return
  }
  S.autoDeferredSince = null
  let bound = await $.session.id()
  let at: AutoStage = stage
  try {
    if (at === 'compact') {
      const startedAt = await $.clock.now()
      const done = await $.session.compact({ instructions: AUTO_COMPACT_INSTRUCTIONS })
      if ('skip' in done && typeof done.skip === 'string') throw new Error(done.skip)
      await update($, budget, () => null)
      await update($, isNudged, () => false)
      await markHandoff($, false)
      // The compaction happened: never repeat it. Unbooked, pending stays
      // compact and no later stage would run, so stop the run instead. Exit 5
      // is the script's own stop: the compaction cap was reached.
      const booked = await autoRunCall($, bound, compactedArgs(await secondsSince($, startedAt)))
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
      const cleared = await autoRunCall($, bound, ['clear', '--phase'])
      if (cleared !== 0) throw new Error(`the phase clear exited ${cleared}`)
      at = 'clear'
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
    // /model and /effort would save the launch values as the person's
    // defaults; the turn.step hook sends this session's requests on them instead.
    if (auto.launch !== null) S.launch = { session: bound, model: auto.launch.model, effort: effortOf(auto.launch.effort) }
    await $.prompt.submit({ text: auto.resumePrompt ?? resumePrompt(), asUser: true })
    await autoRunCall($, bound, ['resumed'])
    await trackAutoRun($)
  } catch (error) {
    const why = error instanceof Error ? error.message : String(error)
    const action = at === 'compact' || at === 'continue' ? 'compact' : at === 'switch' ? 'switch' : 'clear'
    const code = await autoRunCall($, bound, ['failure', '--reason', `the cockpit could not ${action}: ${why}`])
    if (code === 0) scheduleAutoAct($, at, AUTO_RETRY_MS)
    else if (code === 5) await endStoppedRun($)
    // Unbooked, nothing would retry the stage: stop rather than stall unseen.
    else await endUnboundRun($, bound, `the cockpit could not ${action} and could not book the failure (exit ${code})`)
  }
}

type Effort = 'low' | 'medium' | 'high' | 'xhigh' | 'max'

function effortOf(value: string): Effort | null {
  return (['low', 'medium', 'high', 'xhigh', 'max'] as const).find(level => level === value) ?? null
}

// The step as the auto run's launch command would send it: a main-loop request
// of the session the run cleared into goes out on the launch model and effort.
async function launched<E extends { agentId?: string; model: string; effort?: unknown }>($: EngineInterface, e: E): Promise<E> {
  const launch = S.launch
  if (launch === null || e.agentId !== undefined || launch.session !== (await $.session.id())) return e
  return { ...e, model: launch.model, ...(launch.effort === null ? {} : { effort: launch.effort }) } as E
}

// What /model and /effort save as the user's defaults, as the engine has them
// loaded; null when the settings cannot be read, so nothing is restored from a guess.
async function userDefaults($: EngineInterface): Promise<SavedDefaults | null> {
  const user = (await $.settings.read({ source: 'user' }).catch(() => null)) as Record<string, unknown> | null
  if (user === null) return null
  return { model: user.model ?? null, modelSettings: user.modelSettings ?? null, effortLevel: user.effortLevel ?? null }
}

// The user's defaults as /model and /effort save them, in this key order: the
// restore's read-back compares JSON text.
type SavedDefaults = { model: unknown; modelSettings: unknown; effortLevel: unknown }

// A mod cannot delete a file: dagents-config.mjs does it. Whether it did.
async function dropSnapshot($: EngineInterface, name: string): Promise<boolean> {
  const ran = await $.process.run(['node', `${$.plugin.root}/scripts/lib/dagents-config.mjs`, 'drop-snapshot', name], { timeoutMs: 15_000 }).catch(() => null)
  return ran?.exitCode === 0
}

function undroppedToast(session: string, file: string): string {
  return `dagents: could not drop the model switch snapshot of session ${session}, ${file}; the next session start tries again.`
}

// The snapshots sessions of earlier versions left, which switched models with
// /model and /effort. A live writer's is still in use. A dead one's defaults go
// back while its launch model is still the default, the sign that nothing
// changed them since; otherwise they are stale and only dropped.
async function sweepSnapshots($: EngineInterface) {
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
  if (!home) return
  const dir = `${home.replace(/[\\/]+$/, '')}/.claude/dagents/sessions/saved-defaults`
  const own = (await $.session.id()).replace(/[^A-Za-z0-9]/g, '-')
  for (const entry of await $.fs.list(dir).catch(() => [])) {
    if (!entry.name.endsWith('.json')) continue
    const name = entry.name.slice(0, -'.json'.length)
    if (name === own) continue
    const text = await $.fs.read(`${dir}/${entry.name}`).catch(() => null)
    if (text === null) continue
    const snapshot = snapshotOf(String(text))
    if (snapshot === null) {
      $.ui.toast(
        (await dropSnapshot($, name))
          ? `dagents: dropped an unreadable model switch snapshot, ${entry.name}.`
          : `dagents: could not drop an unreadable model switch snapshot, ${entry.name}; the next session start tries again.`,
      )
      continue
    }
    if ((await isSessionAlive($, snapshot.session)) !== false) continue
    const now = await userDefaults($)
    if (now === null) continue
    if (now.model === snapshot.launchModel) {
      if (!(await restoreUserDefaults($, snapshot.saved))) {
        $.ui.toast(`dagents: could not put back the default model that session ${snapshot.session} switched from; it stays ${snapshot.launchModel}, and its snapshot is kept for the next session start to try again.`)
      } else if (!(await dropSnapshot($, name))) {
        $.ui.toast(undroppedToast(snapshot.session, entry.name))
      }
    } else {
      $.ui.toast(
        (await dropSnapshot($, name))
          ? `dagents: dropped the model switch snapshot of session ${snapshot.session}: your default model is no longer ${snapshot.launchModel}.`
          : undroppedToast(snapshot.session, entry.name),
      )
    }
  }
}

function snapshotOf(text: string): { session: string; launchModel: string; saved: SavedDefaults } | null {
  let parsed: unknown
  try {
    parsed = JSON.parse(text)
  } catch {
    return null
  }
  const s = (typeof parsed === 'object' && parsed !== null ? parsed : {}) as Record<string, unknown>
  const saved = (typeof s.saved === 'object' && s.saved !== null ? s.saved : null) as Record<string, unknown> | null
  if (typeof s.session !== 'string' || typeof s.launchModel !== 'string' || saved === null) return null
  return { session: s.session, launchModel: s.launchModel, saved: { model: saved.model ?? null, modelSettings: saved.modelSettings ?? null, effortLevel: saved.effortLevel ?? null } }
}

// Whether node starts: the restore below runs dagents-config.mjs with it.
async function nodeRuns($: EngineInterface): Promise<boolean> {
  const ran = await $.process.run(['node', '--version'], { timeoutMs: 5_000 }).catch(() => null)
  return ran?.exitCode === 0
}

// /model and /effort save their values as the user's defaults for every new
// session; the cleared session keeps running on them after the file is put back.
// The engine never reloads a write that lands right after its own save, and its
// next settings write would save the launch model again, so the restore counts
// only once the engine reads it back; a later write is outside that window.
async function restoreUserDefaults($: EngineInterface, saved: SavedDefaults): Promise<boolean> {
  for (let write = 0; write < RESTORE_WRITES; write++) {
    const ran = await $.process
      .run(['node', `${$.plugin.root}/scripts/lib/dagents-config.mjs`, 'claude-restore', JSON.stringify(saved)], { timeoutMs: 15_000 })
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
  try {
    const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
    if (!home) return
    const id = (await $.session.id()).replace(/[^A-Za-z0-9]/g, '-')
    const seconds = Math.floor((await $.clock.now()) / 1000)
    await $.fs.write(`${home.replace(/[\\/]+$/, '')}/.claude/dagents/sessions/cockpit/${id}`, `${seconds}\n`)
  } catch {
    // A beat that cannot be written is skipped; the watchdog's tick goes on.
  }
}

// A main turn of the bound run that ended on an API error (the transcript's last
// model record says isApiErrorMessage) is booked apart from stalls, and the
// session is prompted again from a timer, never inside the turn's hook. The
// tenth in a row stops the run, as the stall cap does.
async function bookApiError($: EngineInterface) {
  const auto = await readAutoRun($)
  if (auto === null || !auto.active || !(await endedOnApiError($))) return
  const code = await autoRunCall($, await $.session.id(), ['api-error'])
  if (code !== 0 && code !== 5) return
  S.autoActedAt = await $.clock.now()
  S.isApiErrorBooked = code === 0
  S.apiErrorTimer?.cancel()
  S.apiErrorTimer = $.clock.after(code === 5 ? 0 : API_ERROR_RETRY_MS, () => {
    S.apiErrorTimer = null
    if (code === 5) void endStoppedRun($).catch(() => undefined)
    else void retryAfterApiError($).catch(() => undefined)
  })
}

// The run can stop, or a turn start, while the retry waits.
async function retryAfterApiError($: EngineInterface) {
  if (S.isTurnLive) return
  const auto = await readAutoRun($)
  if (auto === null || !auto.active || S.isTurnLive) return
  await $.prompt.submit({ text: apiErrorPrompt($.plugin.root), asUser: true }).catch(() => undefined)
}

// Whether the session transcript's last model record is an API error; only
// the file's tail is read. The transcript is the one the session-start hook
// recorded for this session.
async function endedOnApiError($: EngineInterface): Promise<boolean> {
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
  if (!home) return false
  const session = await $.session.id()
  const record = await $.fs.read(`${home.replace(/[\\/]+$/, '')}/.claude/dagents/sessions/by-id/${session.replace(/[^A-Za-z0-9]/g, '-')}.json`).catch(() => null)
  let path: unknown = null
  try {
    path = record === null ? null : (JSON.parse(String(record)) as { transcript_path?: unknown }).transcript_path
  } catch {
    return false
  }
  if (typeof path !== 'string' || path === '') return false
  const ran = await $.process.run(['bash', '-c', 'tail -c 262144 -- "$1"', 'tail', path], { timeoutMs: 10_000 }).catch(() => null)
  if (ran === null || ran.exitCode !== 0) return false
  for (const line of ran.stdout.split('\n').reverse()) {
    let entry: { type?: unknown; isApiErrorMessage?: unknown }
    try {
      entry = JSON.parse(line) as typeof entry
    } catch {
      continue
    }
    if (entry.type === 'assistant') return entry.isApiErrorMessage === true
  }
  return false
}

// Each WATCHDOG_MS: the heartbeat, then a wake-up for a bound run nothing
// else will carry on. A turn that ended on an error, or without its sentinel
// and unheld, arms no stage, and a pending stage can lose its timer. Never
// while a turn, background work, a stage or an Esc holds the session, and
// never within STALL_MS of the latest of this session's start, its last
// turn's end, the last stage and the last nudge.
async function watchdogTick($: EngineInterface) {
  await beat($)
  if (S.heldDone !== null && !S.isMainTurn && (await $.clock.now()) - S.heldDone.heldAt > DEFER_CAP_MS) {
    if ((await read($, activity)).kind === 'background') await setActivity($, now => ({ ...now, kind: 'idle' }))
    await sendDone($, '', 0)
  }
  if (S.isTurnLive || S.autoBusy) return
  const auto = await readAutoRun($)
  if (auto === null || !auto.active) return
  if (await isMainBackground($)) {
    await reconcileBackground($, auto)
    return
  }
  const now = await read($, activity)
  if (now.kind !== 'idle' && now.kind !== 'failed') return
  const last = Math.max(S.watchedSince ?? 0, now.endedAt ?? 0, S.autoActedAt ?? 0, (auto.stalledAt ?? 0) * 1000)
  if ((await $.clock.now()) - last <= STALL_MS) return
  const stage = WATCHED_STAGES[auto.pending ?? '']
  if (stage !== undefined) {
    if (S.autoTimer === null) {
      S.autoDeferredSince = null
      scheduleAutoAct($, stage, 0)
    }
    return
  }
  const stamp = await $.clock.now()
  if (S.stallFailedAt !== null && stamp - S.stallFailedAt <= STALL_MS) return
  const code = await autoRunCall($, await $.session.id(), ['stalled'])
  S.stallFailedAt = code === 0 || code === 5 ? null : stamp
  if (code === 5) await endStoppedRun($)
  else if (code === 0 && !S.isTurnLive) await $.prompt.submit({ text: stallPrompt($.plugin.root), asUser: true }).catch(() => undefined)
}

async function backgroundKey($: EngineInterface): Promise<string> {
  const agents = (await read($, spawns)).filter(one => !one.isDone).map(one => `a:${one.agentId}`)
  const commands = (await read($, shells)).filter(one => (one.agentId ?? null) === null && !isServiceCommand(one.command)).map(one => `s:${one.id}`)
  return [...agents, ...commands].sort().join(',')
}

// A bound run with no live turn that only background work holds: a launch that
// hangs never notifies, so each RECONCILE_MS the session is asked to look at
// its launches. That prompt's turn restarts autoStage's deferral clock, so a
// stage held by work that never changes is failed here instead, once
// RECONCILE_CAP prompts in a row found the same launches running.
async function reconcileBackground($: EngineInterface, auto: CockpitAutoRun) {
  const now = await read($, activity)
  if (now.kind !== 'idle' && now.kind !== 'background' && now.kind !== 'failed') return
  const stamp = await $.clock.now()
  const last = Math.max(S.watchedSince ?? 0, now.endedAt ?? 0, S.reconciledAt ?? 0)
  if (stamp - last <= RECONCILE_MS) return
  const stage = WATCHED_STAGES[auto.pending ?? '']
  const step = reconcileStep(S.reconcileSeen, `${auto.pending ?? ''}|${await backgroundKey($)}`, stage !== undefined, RECONCILE_CAP)
  S.reconciledAt = stamp
  S.reconcileSeen = step.seen
  if (step.action === 'fail' && stage !== undefined) {
    await bookStageFailure($, stage, `${RECONCILE_CAP} reconcile prompts left the ${stage} waiting on background work`)
    return
  }
  if (S.isTurnLive) return
  const isSent = await $.prompt.submit({ text: reconcilePrompt($.plugin.root), asUser: true }).then(
    () => true,
    () => false,
  )
  if (isSent) await autoRunCall($, await $.session.id(), ['total', 'reconcilePrompts'])
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

// auto-run compacted, with the compaction's duration once it reached a second.
function compactedArgs(seconds: number): string[] {
  return seconds > 0 ? ['compacted', '--seconds', String(seconds)] : ['compacted']
}

async function secondsSince($: EngineInterface, startedAt: number): Promise<number> {
  return Math.max(0, Math.round(((await $.clock.now()) - startedAt) / 1000))
}

// The person's compaction from the pane, booked as /compact is. The mod's own
// session.compact hook did not see it under claude plugin test; where it
// does, it leaves the booking to this.
async function compactFromPane($: EngineInterface) {
  S.isPaneCompacting = true
  try {
    const startedAt = await $.clock.now()
    const done = await $.session.compact()
    if (!('skip' in done)) await bookAutoCompaction($, true, await secondsSince($, startedAt))
  } finally {
    S.isPaneCompacting = false
  }
}

// A compaction the cockpit did not make, booked so the run's rule applies after it.
async function bookAutoCompaction($: EngineInterface, fromPane = false, seconds = 0) {
  const auto = await readAutoRun($)
  // A pending clear or switch supersedes the compaction: booking it would drop
  // that stage. A pending handoff still needs its clear, and a pending compact
  // is the cockpit's own stage, which books itself unless the pane ran it first.
  if (auto === null || !auto.active || ['clear', 'switch', 'handoff'].includes(auto.pending ?? '')) return
  if (auto.pending === 'compact' && !fromPane) return
  const code = await autoRunCall($, await $.session.id(), compactedArgs(seconds))
  // Exit 5: the compaction cap stopped the run.
  if (code === 5) await endStoppedRun($)
  // The pane did the compact stage's work, so only its continue prompt is left.
  else if (code === 0 && auto.pending === 'compact') {
    await trackAutoRun($)
    scheduleAutoAct($, 'continue', 0)
  }
}

async function stopAutoRun($: EngineInterface) {
  S.apiErrorTimer?.cancel()
  S.apiErrorTimer = null
  await autoRunCall($, await $.session.id(), ['stop', '--reason', 'owner pressed Stop auto'])
  await trackAutoRun($)
  // The resume offer is not recomputed during a run: recompute it now.
  await readRun($)
}

// A node that cannot start: the engine's "failed to start", or a shell's
// "node: not found" (exit 127). Any other stderr is the script's own, ENOENT
// included.
const NO_NODE = /failed to start|\bnode: (?:command )?not found/i
// The engine's rejection for a run still going at its timeoutMs (Claude Code
// 2.1.299: "…aborted: still running after 5000ms"); a command that cannot
// start rejects "…failed to start: ENOENT…" instead.
const TIMED_OUT = /still running after/i

// finish.json for the newest ledger's slug, or the no-plan one: it stays in
// the workspace of the worktree that ran the plan, so the session's checkout
// is read first, then the primary; the primary's path when neither has one.
async function finishPath($: EngineInterface, checkouts: readonly string[], slug: string | null): Promise<string> {
  const paths: string[] = []
  for (const dir of checkouts) {
    paths.push(slug === null ? `${dir}/.dagents/sdd/finish.json` : `${dir}/.dagents/sdd/${slug}/finish.json`)
  }
  for (const path of paths) {
    if ((await $.fs.stat(path).catch(() => null))?.kind === 'file') return path
  }
  return paths[paths.length - 1] ?? ''
}

// A handoff the offer may name, as read from the session's checkout.
type OfferHandoff = { path: string; key: string; mtime: number; text: string; at: number; subject: string | null }
// A handoff's claim file as read here: its session, and whether that
// session's cockpit still beats (null: unknown, or no claim).
type OfferClaim = { session: string | null; isAlive: boolean | null }

// The offer is the newest handoff of the session's checkout that is
// unclaimed or claimed by a gone session other than this one, as `handoff
// list --checkout` judges it, and that `next-step --print --handoff`
// recomputes to something to resume; exit 6 tries the next newest. The runs
// are started detached, so no turn or tool hook waits on them; one chain at a
// time; again only when a handoff, its claim (content, time and the
// claimant's liveness) or a file the block is computed from changes; and
// never while the offer cannot show. Until a chain resolves, the offer the
// last one produced stands. A handoff is read again only when it changes: its
// marker dates the offer, so editing the notes keeps a dismissal.
async function readResumeOffer(
  $: EngineInterface,
  here: string,
  dir: string,
  places: readonly { root: string; docsDir: string }[],
  primary: string,
) {
  const now = await $.clock.now()
  const fresh = (await offerHandoffs($, dir)).filter(one => now - one.at < RESUME_WITHIN).sort((a, b) => b.at - a.at)
  if (fresh.length === 0) {
    if ((await read($, resumeOffer)) !== null) await update($, resumeOffer, () => null)
    return
  }
  if ((await read($, isPlanSession)) || (await read($, autoRun))?.active) return
  const claims = new Map<string, OfferClaim>()
  const claimKeys: string[] = []
  for (const key of new Set(fresh.map(one => one.key))) {
    const path = `${primary}/.dagents/handoff/claims/${key}`
    const info = await $.fs.stat(path).catch(() => null)
    const text = info === null ? null : await $.fs.read(path).catch(() => null)
    const session = typeof text === 'string' ? (/^session=(\S+)/m.exec(text)?.[1] ?? null) : null
    const isAlive = session === null ? null : await isSessionAlive($, session)
    claims.set(key, { session, isAlive })
    claimKeys.push(`${key}=${info?.mtimeMs ?? '-'}:${text ?? ''}:${isAlive}`)
  }
  const handoffKeys = fresh.map(one => `${one.path}=${one.mtime}`)
  const runKey = [...handoffKeys, ...claimKeys, ...(await offerTimes($, places, fresh.map(one => one.subject)))].join('\t')
  if (S.isOfferRunning || S.offerRanKey === runKey) return
  S.offerRanKey = runKey
  S.isOfferRunning = true
  void offerChain($, here, fresh, claims, places)
    .then(async offer => {
      if (JSON.stringify(await read($, resumeOffer)) !== JSON.stringify(offer)) await update($, resumeOffer, () => offer)
    })
    .catch(() => undefined)
    .finally(() => {
      S.isOfferRunning = false
    })
}

// Every handoff file in this directory, read again only when it changes.
async function offerHandoffs($: EngineInterface, dir: string): Promise<OfferHandoff[]> {
  const found: OfferHandoff[] = []
  for (const entry of (await $.fs.list(dir).catch(() => null)) ?? []) {
    const key = entry.name.slice(0, -3)
    // The key rule of scripts/lib/roots.sh: an older layout's file is not a
    // handoff, and `scripts/handoff claim` refuses it.
    if (!entry.name.endsWith('.md') || !/^[A-Za-z0-9._-]+$/.test(key) || key === 'latest') continue
    const path = `${dir}/${entry.name}`
    const info = await $.fs.stat(path).catch(() => null)
    if (info?.kind !== 'file') continue
    let known = S.offerTexts.get(path)
    if (known?.mtime !== info.mtimeMs) {
      const text = await $.fs.read(path).catch(() => null)
      if (typeof text !== 'string') continue
      const mark = markerOf(text)
      known = { mtime: info.mtimeMs, text, at: mark?.at ?? Math.floor(info.mtimeMs / 1000) * 1000, subject: mark?.subject ?? null }
      S.offerTexts.set(path, known)
    }
    found.push({ path, key, ...known })
  }
  return found
}

// Runs a script of the plugin in `dir`, detached from every hook; null when
// it could not run or outran its 20 seconds.
async function runScript($: EngineInterface, dir: string, script: string, args: string[]) {
  // The directory travels in argv: no cockpit call passes $.process.run a cwd.
  const argv = ['bash', '-c', 'cd -- "$1" && shift && exec bash "$@"', script, dir, `${$.plugin.root}/scripts/${script}`, ...args]
  return $.process.run(argv, { timeoutMs: 20_000 }).catch(() => null)
}

// The offer one chain settles on: each candidate newest first, until
// next-step gives one to resume. The chain stops at the handoff last
// dismissed or resumed (Resume dismisses it too), so neither brings an older
// handoff up in its place, in a band that does not name which one it offers.
async function offerChain(
  $: EngineInterface,
  here: string,
  fresh: readonly OfferHandoff[],
  claims: ReadonlyMap<string, OfferClaim>,
  places: readonly { root: string; docsDir: string }[],
): Promise<CockpitResumeOffer | null> {
  const own = await $.session.id().catch(() => null)
  const listed = new Map<string, string>()
  const ran = await runScript($, here, 'handoff', ['list', '--checkout', here])
  for (const line of ran?.exitCode === 0 ? ran.stdout.split(/\r?\n/) : []) {
    const fields = line.split('\t')
    if (fields.length >= 5 && fields[1]) listed.set(fields[1], fields[4] ?? '')
  }
  const dismissed = await read($, resumeDismissed)
  for (const one of fresh) {
    if (dismissed === one.at) return null
    // The listing judges a claim; a key it does not name (it failed, or the
    // file is newer than it) is judged from the claim file read here.
    const claim = listed.get(one.key)
    const local = claims.get(one.key)
    const isOpen =
      claim === undefined
        ? local?.session == null || (local.session !== own && local.isAlive === false)
        : claim === 'unclaimed' || (/^claimed \S+ gone$/.test(claim) && claim.split(' ')[1] !== own?.slice(0, 8))
    if (!isOpen) continue
    const recomputed = await runScript($, here, 'next-step', ['--print', '--handoff', one.path])
    const offer = await offerFrom($, recomputed, one, places)
    if (offer === null) continue
    S.latestName = one.path
    return offer
  }
  return null
}

// The modification times a recomputed block depends on: completed.md,
// roadmap.md, each register, the plans directory and each handoff's subject
// plan. The subject's ledger is left out: the offer is hidden in a plan session.
async function offerTimes(
  $: EngineInterface,
  places: readonly { root: string; docsDir: string }[],
  subjects: readonly (string | null)[],
): Promise<string[]> {
  const where = (name: string) => planCandidates(name, places)
  const named = [...new Set(subjects.filter((subject): subject is string => subject !== null))]
  const paths = [...where('docs/dagents/plans/completed.md'), ...where('docs/dagents/roadmap.md'), ...where('docs/dagents/plans'), ...named.flatMap(where)]
  for (const dir of where('docs/dagents/registers')) {
    for (const entry of (await $.fs.list(dir).catch(() => null)) ?? []) {
      if (entry.name.endsWith('.md')) paths.push(`${dir}/${entry.name}`)
    }
  }
  const stats = await Promise.all(paths.map(path => $.fs.stat(path).catch(() => null)))
  return paths.map((path, index) => `${path}=${stats[index]?.mtimeMs ?? '-'}`)
}

// What a finished run offers: the recomputed block on exit 0, nothing on exit
// 6, and otherwise the stored note, marked as not rechecked. A stored ruling
// handoff is withdrawn once every register its prompt names is readable and
// fully resolved, since nothing rewrites the note when the last row closes.
async function offerFrom(
  $: EngineInterface,
  ran: { exitCode: number; stdout: string } | null,
  stored: { text: string; at: number },
  places: readonly { root: string; docsDir: string }[],
): Promise<CockpitResumeOffer | null> {
  if (ran?.exitCode === 6) return null
  if (ran?.exitCode === 0) {
    const found = resumeOfferOf(ran.stdout)
    return found === null ? null : { at: markerOf(ran.stdout)?.at ?? stored.at, next: found.next, prompt: found.prompt, isRechecked: true }
  }
  const found = resumeOfferOf(stored.text)
  if (found === null) return null
  // A register name resolves as a plan name does: the first checkout holding it.
  const registers: string[] = []
  for (const name of found.prompt === null ? [] : promptRegisters(found.prompt)) {
    const candidates = planCandidates(name, places)
    let chosen = candidates[0] ?? name
    for (const candidate of candidates) {
      if ((await $.fs.stat(candidate).catch(() => null))?.kind === 'file') {
        chosen = candidate
        break
      }
    }
    registers.push(chosen)
  }
  let isSettled = registers.length > 0
  for (const path of registers) {
    const text = await $.fs.read(path).catch(() => null)
    if (typeof text !== 'string' || hasUnresolvedRows(text)) {
      isSettled = false
      break
    }
  }
  return isSettled ? null : { at: stored.at, next: found.next, prompt: found.prompt, isRechecked: false }
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
  await $.prompt.submit({ text: offer.prompt ?? resumePrompt(), asUser: true })
}

// The run's ledger, its plan's tasks, and the newest handoff: the ledgers and
// the handoff under the session worktree's .dagents/, as sdd-workspace and
// next-step write them.
async function readRun($: EngineInterface) {
  // A poll tick's read and a tool call's can overlap: only the latest writes.
  const reading = ++S.runReads
  const session = S.where.checkout ?? (await read($, place))?.root ?? null
  const root = S.where.primary ?? session
  if (root === null) return
  // A removed worktree took its handoff with it: the primary's stands in.
  const isGone = session !== null && session !== root && (await $.fs.stat(session).catch(() => null))?.kind !== 'dir'
  const here = isGone ? root : (session ?? root)
  const state = `${here}/.dagents`
  const checkouts = [...new Set([session, root].filter((dir): dir is string => dir !== null))]
  const places = checkouts.map(dir => ({ root: dir, docsDir: `${dir}/docs/dagents` }))
  try {
    await readResumeOffer($, here, `${state}/handoff`, places, root)
    const base = `${session ?? root}/.dagents/sdd`
    const bound = await read($, boundPlan)
    let newest: { slug: string; path: string; at: number } | null = null
    if (bound !== null) newest = await boundLedger($, base, bound)
    else {
      for (const name of await ledgerDirs($, base)) {
        const info = await $.fs.stat(`${base}/${name}/progress.md`).catch(() => null)
        if (info?.kind === 'file' && (newest === null || info.mtimeMs > newest.at)) newest = { slug: name, path: `${base}/${name}/progress.md`, at: info.mtimeMs }
      }
    }
    await readFinish($, await finishPath($, checkouts, newest?.slug ?? null))
    const startedAt = (await read($, usage))?.startedAt ?? (await $.session.usage().catch(() => null))?.startedAt ?? 0
    const isOlder = newest !== null && newest.at < startedAt
    const clear = async () => {
      if ((await read($, run)) !== null) await update($, run, () => null)
    }
    // A ledger counts once this session works on it, or when it is the one
    // the session started next to.
    if (newest === null || (!(await read($, isPlanSession)) && isOlder)) {
      if (reading !== S.runReads) return
      S.runKey = ''
      return clear()
    }
    const planStat = S.runPlan === null ? null : await $.fs.stat(S.runPlan).catch(() => null)
    const runKey = `${newest.path}:${newest.at}:${planStat?.mtimeMs ?? ''}`
    // The key stays set while the card shows its run, or a run set aside as history.
    if (runKey === S.runKey) return
    const ledger = parseLedger(String(await $.fs.read(newest.path)))
    let titles: { n: number; title: string }[] = []
    let planPath: string | null = null
    if (ledger.plan !== null) {
      for (const candidate of planCandidates(ledger.plan, places)) {
        try {
          titles = planTasks(String(await $.fs.read(candidate)))
          if (titles.length > 0) {
            planPath = candidate
            break
          }
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
          question: known?.question ?? null,
        }
      }),
      // A deferred task is done with as far as the run is concerned.
      done: ledger.tasks.filter(one => one.state === 'complete' || one.state === 'deferred').length,
      total: numbers.length,
      isFinished: ledger.isFinished,
      isPlanRead: planPath !== null,
    }
    if (reading !== S.runReads) return
    // A plan the ledger names but no checkout holds yet is looked for again at the next read.
    S.runKey = ledger.plan !== null && planPath === null ? '' : runKey
    S.runPlan = planPath
    // A run whose every task was done before this session started is history:
    // a new session starts with no Run card.
    if (isOlder && (summary.isFinished || (summary.total > 0 && summary.done === summary.total))) return clear()
    if (JSON.stringify(await read($, run)) !== JSON.stringify(summary)) await update($, run, () => summary)
    await sendLedgerEvents($, summary)
  } catch {
    // No readable ledger: the Plan card stays as it is.
  }
}

// The ledger of the plan this session named, in the workspace sdd-workspace
// names for the plan file.
async function boundLedger($: EngineInterface, base: string, plan: string): Promise<{ slug: string; path: string; at: number } | null> {
  const slug = (plan.split(/[\\/]/).pop() ?? '').replace(/\.md$/, '')
  if (slug === '') return null
  const path = `${base}/${slug}/progress.md`
  const info = await $.fs.stat(path).catch(() => null)
  return info?.kind === 'file' ? { slug, path, at: info.mtimeMs } : null
}

// The ledger directory's workspaces, listed again only when its modification
// time changes or cannot be read. Appending to a ledger changes no
// directory's time, so each progress.md is still stat'ed at every read.
async function ledgerDirs($: EngineInterface, base: string): Promise<string[]> {
  const info = await $.fs.stat(base).catch(() => null)
  const at = info?.kind === 'dir' ? info.mtimeMs : null
  if (at !== null && S.ledgerDirs.base === base && S.ledgerDirs.at === at) return S.ledgerDirs.names
  const entries = await $.fs.list(base).catch(() => null)
  const names = (entries ?? []).filter(entry => entry.kind === 'dir').map(entry => entry.name)
  S.ledgerDirs = at !== null && entries !== null ? { base, at, names } : { base: '', at: null, names: [] }
  return names
}

// The finish action dagents asked for before the run, from the run's
// finish.json, or the one beside the workspaces for work without a plan.
async function readFinish($: EngineInterface, path: string) {
  const text = await $.fs.read(path).catch(() => null)
  const next: CockpitFinish | null = text === null ? null : parseFinish(String(text))
  if (JSON.stringify(await read($, finish)) === JSON.stringify(next)) return
  await update($, finish, () => next)
  await syncTicker($)
}

// A task that became blocked, waiting, deferred or complete since the last read, said once.
async function sendLedgerEvents($: EngineInterface, summary: CockpitRun) {
  const keys = summary.tasks.flatMap(task =>
    task.state === 'blocked' ? [`blocked:${task.n}:${task.reason ?? ''}`]
    : task.state === 'waiting' ? [`waiting:${task.n}:${task.question ?? ''}`]
    : task.state === 'deferred' ? [`deferred:${task.n}`]
    : task.state === 'complete' ? [`complete:${task.n}`]
    : [],
  )
  if (summary.isFinished) keys.push('finished')
  const seen = S.ledgerSeen.get(summary.plan ?? '')
  if (seen === undefined) {
    S.ledgerSeen.set(summary.plan ?? '', new Set(keys))
    return
  }
  for (const key of keys) {
    if (seen.has(key)) continue
    seen.add(key)
    await markRunSession($)
    const [what, n] = key.split(':')
    const task = summary.tasks.find(one => String(one.n) === n)
    if (what === 'blocked' && task !== undefined) {
      await notify($, {
        kind: 'blocked',
        title: `🛑 Task ${task.n} blocked`,
        detail: task.reason ?? undefined,
        fields: [{ name: 'Run', value: `${summary.done}/${summary.total}` }],
      })
    } else if (what === 'waiting' && task !== undefined) {
      S.questionSentAt = await $.clock.now()
      await notify($, {
        kind: 'question',
        title: `❓ Task ${task.n} waiting on you`,
        detail: task.question ?? undefined,
        fields: [{ name: 'Run', value: `${summary.done}/${summary.total}` }],
      })
    } else if (what === 'deferred' && task !== undefined) {
      await notify($, {
        kind: 'task',
        title: `⏭ Task ${task.n} deferred`,
        detail: task.title || undefined,
        fields: [{ name: 'Run', value: `${summary.done}/${summary.total}` }],
      })
    } else if (what === 'complete' && task !== undefined) {
      await notify($, {
        kind: 'task',
        title: `✅ Task ${task.n} complete${task.isClean ? ', review clean' : ''}`,
        detail: task.title || undefined,
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
    const fromEnv = ((await $.env.get('DAGENTS_NOTIFY_URL')) || (await $.env.get('DAGENTS_COCKPIT_NOTIFY_URL')) || '').trim()
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
  // A worktree's .dagents/ lives in the primary checkout: the work tree of the
  // common git directory's parent, as ar_primary_root (scripts/lib/auto-run.sh)
  // finds it, so a layout the scripts resolve no primary for (a submodule)
  // has none here either.
  const common = await firstLine(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'])
  const parent = common === null ? '' : common.replace(/[\\/]+$/, '').replace(/[\\/][^\\/]*$/, '')
  S.where.primary = parent === '' ? null : await firstLine(['git', '-C', parent, 'rev-parse', '--show-toplevel'])
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
    { kind: 'done', title: '🔔 Test from dagents', detail: 'Notifications reach this channel.', isPlain: true },
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
  if (verb === 'mention') {
    const problem = await saveMention($, rest.join(' '))
    return { text: problem ?? 'Discord mention saved.' }
  }
  const state = await read($, notifier)
  return {
    text: state.url === null ? 'No Discord webhook is set. Set one in /dagents:cockpit settings (Notifications) in a terminal, or with DAGENTS_NOTIFY_URL.' : `Discord webhook: ${maskWebhook(state.url)}${state.isFromEnv ? ' (from the environment)' : ''}.`,
  }
}


// Reads the status line's figures (free without a breakdown) and, past the
// budget in a dagents session, tells the model once.
async function refresh(
  $: EngineInterface,
  tuning: Tuning,
  compactWindow: number | undefined,
  { isShownOnly = false } = {},
): Promise<{ now: CockpitBudget; isPast: boolean } | undefined> {
  const { handoffTokens, nudgeModel } = tuning
  const figures = await $.session.usage()
  const tokens = figures.context.tokens
  const window = figures.context.window
  // A window the host does not know would make every share of it infinite and the budget zero.
  if (tokens === undefined || !(window > 0)) return
  const auto = await read($, autoRun)
  const isAuto = auto !== null && auto.active
  // A plan's last tasks and its final phase never hand off, as the budget line
  // measures them: strict keeps the handoff budget and runs past it to finish
  // the plan, relaxed measures against the final-phase limit.
  const summary = await read($, run)
  // Only a session running the plan: a finished plan's ledger written anew at
  // the start would otherwise read as this session's.
  const isTail = summary !== null && isPlanTail(summary) && (await read($, isRunSession))
  const limit = isAuto
    ? autoLimitFor(auto.regime, handoffTokens, window, compactWindow)
    : tuning.isRelaxed
      ? finalLimitFor(window, compactWindow)
      : budgetFor(handoffTokens, undefined, window, compactWindow)
  // Relaxed mode measures the tail against the final-phase limit, but a plan
  // with every task complete is in its final phase, which never hands off.
  const isFinishing = !isAuto && isTail && (!tuning.isRelaxed || summary?.isFinished === true || (summary !== null && summary.isPlanRead && summary.total > 0 && summary.done >= summary.total))
  const usd = figures.cost?.usd ?? null
  const before = await read($, budget)
  if (
    before?.tokens !== tokens ||
    before.limit !== limit ||
    before.usd !== usd ||
    before.window !== window ||
    before.compactWindow !== (compactWindow ?? null) ||
    before.isFinishing !== isFinishing
  ) {
    const now: CockpitBudget = { tokens, limit, window, compactWindow: compactWindow ?? null, usd, isFinishing }
    await update($, budget, () => now)
    if (before?.tokens !== tokens) await update($, trend, readings => [...readings, tokens].slice(-TREND_LENGTH))
  }

  if (isShownOnly) return
  const level = levelOf(tokens, limit, tuning.warnAt)
  // Finishing the plan past the budget is no handoff.
  const isPast = level === 'handoff' && !isFinishing
  const reading = { now: { tokens, limit, window, compactWindow: compactWindow ?? null, usd, isFinishing }, isPast }
  // An auto run compacts at its limit rather than handing off: no note.
  const isToldHere = nudgeModel && !isAuto && (await read($, isPlanSession)) && !(await read($, isFastMode))
  if (!isPast) {
    if (await read($, isNudged)) await update($, isNudged, () => false)
  } else if (isToldHere && !(await read($, isNudged))) {
    await update($, isNudged, () => true)
    const note = `dagents: budget: ${kTokens(tokens)} of ${kTokens(limit)} — handoff. ${HANDOFF_PROMPT}`
    try {
      await $.session.append({ message: { type: 'user', content: [{ type: 'text', text: note }] } })
    } catch {
      // The host would not take the row: say it to the person instead.
      $.ui.toast(note)
    }
  }
  await markHandoff($, isToldHere && (await read($, isNudged)))
  return reading
}

// scripts/turn-end.sh holds every turn that ends without the next-step block
// while this file beside the turn stamp says `due`.
async function markHandoff($: EngineInterface, isDue: boolean) {
  try {
    const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
    if (!home) return
    const session = (await $.session.id()).replace(/[^A-Za-z0-9]/g, '-')
    const mark = `${session}:${isDue}`
    if (S.handoffMark === mark) return
    await $.fs.write(`${home.replace(/[\\/]+$/, '')}/.claude/dagents/sessions/turns/${session}.handoff`, isDue ? 'due' : '')
    S.handoffMark = mark
  } catch {
    // Unwritten, the stop is not held: the note still stands in the transcript.
  }
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

/** ~/.dagents/config.json, or null when no home directory is set. */
async function configFile($: EngineInterface): Promise<string | null> {
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
  return home ? `${home.replace(/[\\/]+$/, '')}/.dagents/config.json` : null
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

/**
 * Puts a settings file in force: the atom every hook reads through live(), the
 * locked rows, and the notifier. `mtime` is the file's time taken before it was
 * read; absent, the file is timed now.
 */
async function applySettings($: EngineInterface, file: SettingsFile, mtime?: number | null) {
  // $.env.get takes only a literal name: each variable the schema names is listed.
  const env = { DAGENTS_BUDGET: await $.env.get('DAGENTS_BUDGET'), DAGENTS_LENS_CAP: await $.env.get('DAGENTS_LENS_CAP'), DAGENTS_LENS_MINOR_FROM: await $.env.get('DAGENTS_LENS_MINOR_FROM') }
  const userRead = await $.settings.read({ source: 'user' }).catch(() => null)
  const mergedRead = await $.settings.read().catch(() => null)
  const engineUser = (userRead ?? {}) as Record<string, unknown>
  // The engine's snapshot can predate a save: until it shows the saved value the reads are overlaid, then the save is dropped, so a project or managed override or a later hand edit shows through.
  for (const [key, saved] of Object.entries(S.claudeSaved)) if (engineUser[key] === saved) delete S.claudeSaved[key]
  const merged = { ...((mergedRead ?? {}) as Record<string, unknown>), ...S.claudeSaved }
  const user = { ...engineUser, ...S.claudeSaved }
  const values = resolveSettings(SCHEMA, file, env, merged)
  S.settingProblems = [...(S.brokenConfig === null ? [] : [S.brokenConfig]), ...settingProblems(SCHEMA, file, env)]
  const locks = { ...envLocks(SCHEMA, env), ...claudeLocks(SCHEMA, merged, user) }
  S.locks = locks
  await update($, settings, () => values)
  applyNotify(liveFrom(values as Partial<Options>))
  // What was applied is what the poll compares with, so a change landing during these reads is put in force at its next tick.
  S.seen = { config: mtime === undefined ? (await configStamp($)).mtime : mtime, claude: JSON.stringify([userRead, mergedRead]) }
}

/** The first run: dr-cockpit's options, imported into the new file. */
async function importSettings($: EngineInterface, path: string): Promise<SettingsFile> {
  if (await nodeRuns($)) {
    // dagents-config imports before any command, creating the file with a hard
    // link that never replaces one saved meanwhile. `get --json` prints the
    // resolved values, not the file, so its output is not used.
    await $.process.run(['node', `${$.plugin.root}/scripts/lib/dagents-config.mjs`, 'get', '--json'], { timeoutMs: 15_000 }).catch(() => null)
    // A run that failed before creating the file falls through to the import below; otherwise a later save would create the file without dr-cockpit's options and shut out the import for good.
    if (await $.fs.exists(path).catch(() => false)) return (await readSettingsFile($, path)) ?? {}
  }
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

/** Reads ~/.dagents/config.json into force, importing the pre-2.0 settings on the first run. */
async function loadSettings($: EngineInterface) {
  S.claudeSaved = {}
  S.changed = {}
  S.brokenConfig = null
  const { path, mtime } = await configStamp($)
  if (path === null) return applySettings($, {}, null)
  let file = await readSettingsFile($, path)
  let readAt: number | null | undefined = mtime
  if (file !== null && Object.keys(file).length === 0 && !(await $.fs.exists(path).catch(() => false))) {
    file = await importSettings($, path)
    readAt = undefined
  }
  if (file === null) S.brokenConfig = `dagents: ${path} is not a JSON object; every setting reads its default and notifyOn reads none until it parses`
  await applySettings($, inForce(file), readAt)
  await importWebhook($).catch(() => undefined)
}

// What a settings file puts in force: a file that does not parse sends no notification, as dagents-config's workflow line says.
function inForce(file: SettingsFile | null): SettingsFile {
  return file ?? (S.brokenConfig === null ? {} : { notifyOn: 'none' })
}

/** Saves one setting and puts it in force, saying why if it could not; resolves whether it was saved. */
async function setOption($: EngineInterface, key: string, value: SettingValue): Promise<boolean> {
  const spec = SCHEMA[key]
  const { path, mtime } = await configStamp($)
  const file = path === null ? null : await readSettingsFile($, path)
  try {
    if (spec?.target === 'claude') {
      // Claude's settings file holds far more than these keys, so only dagents-config, which rewrites it in one rename, writes it.
      const ran = await $.process.run(['node', `${$.plugin.root}/scripts/lib/dagents-config.mjs`, 'set', key, String(value)], { timeoutMs: 15_000 })
      if (ran.exitCode !== 0) throw new Error(ran.stderr.trim().replace(/^dagents-config: /, '') || `dagents-config exited ${ran.exitCode}`)
      // dagents-config removes a floored key saved as 0, so the user file then lacks it.
      const saved = spec.floor !== undefined && value === 0 ? undefined : value
      S.claudeSaved[key] = saved
      await applySettings($, inForce(file), mtime)
      void claudeReadBack($, key, saved)
      return true
    }
    if (path === null) throw new Error('no home directory is set')
    if (file === null) throw new Error(`${path} is not a JSON object; fix or remove it`)
    const next = settingWritten(SCHEMA, file, key, value)
    if (await isSetByNode($, key, value)) {
      const savedAt = (await configStamp($)).mtime
      const saved = await readSettingsFile($, path)
      if (saved === null) throw new Error(`${path} could not be read after saving`)
      await applySettings($, saved, savedAt)
    } else {
      await $.fs.write(path, `${JSON.stringify(next, null, 2)}\n`)
      await applySettings($, next)
    }
    if (spec?.enforcedBy === 'skill') S.changed[key] = value
    return true
  } catch (error) {
    $.ui.toast(`dagents: ${key} not saved: ${error instanceof Error ? error.message : String(error)}`)
    return false
  }
}

// dagents-config writes under ~/.dagents/.lock, the lock every other writer of
// the file takes, so a save cannot drop another session's. False when node
// cannot start: the direct write is then all there is.
async function isSetByNode($: EngineInterface, key: string, value: SettingValue): Promise<boolean> {
  let ran
  try {
    ran = await $.process.run(['node', `${$.plugin.root}/scripts/lib/dagents-config.mjs`, 'set', key, String(value)], { timeoutMs: 15_000 })
  } catch (error) {
    if (NO_NODE.test(String(error))) return false
    throw error
  }
  if (ran.exitCode === 0) return true
  if (NO_NODE.test(ran.stderr)) return false
  throw new Error(ran.stderr.trim().replace(/^dagents-config: /, '') || `dagents-config exited ${ran.exitCode}`)
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

async function markRunSession($: EngineInterface) {
  if (!(await read($, isRunSession))) await update($, isRunSession, () => true)
}

/** Tells the model, once, which skill-enforced settings changed; outside a dagents session the change waits for one. */
async function flushSettingNote($: EngineInterface) {
  const sent = { ...S.changed }
  const keys = Object.keys(sent)
  if (keys.length === 0 || !(await read($, isPlanSession))) return
  const note = `dagents settings changed: ${keys.map(key => `${key}=${String(sent[key])}`).join('; ')}. Each replaces the matching question or default in the skills.`
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

/** The settings file's path and modification time; the time is null when there is no file. */
async function configStamp($: EngineInterface): Promise<{ path: string | null; mtime: number | null }> {
  const path = await configFile($)
  const stat = path === null ? null : await $.fs.stat(path).catch(() => null)
  return { path, mtime: stat?.kind === 'file' ? stat.mtimeMs : null }
}

/** The engine's user and merged settings as one string, to compare between ticks. */
async function engineSettings($: EngineInterface): Promise<string> {
  const user = await $.settings.read({ source: 'user' }).catch(() => null)
  const merged = await $.settings.read().catch(() => null)
  return JSON.stringify([user, merged])
}

/**
 * Reads every section, then marks the session read.
 * session.start runs it once per process, opening or shutting the pane first;
 * the poll runs it again in a session /clear or /resume carried the process
 * into, whose values the host keeps apart and no session.start announces, and
 * leaves the pane as the person left it.
 */
// The counts that hold within one session: the reconcile prompts and the
// background-work deferral.
function resetSessionGuards() {
  S.reconcileSeen = { key: '', count: 0 }
  S.autoDeferredSince = null
}

async function readSession($: EngineInterface, isStart: boolean) {
  const id = await $.session.id().catch(() => null)
  // These caches outlive a /clear or /resume, and the values they stand for do
  // not: read again, or the resume offer stays unwritten.
  S.offerTexts.clear()
  S.offerRanKey = null
  // Each read fills its own section: one that throws leaves only that section
  // unread, and a slow poll tick reads that one again, not the whole session,
  // whose caches the reset above would otherwise clear on every retry.
  const unread: (() => Promise<unknown>)[] = []
  const step = async (part: () => Promise<unknown>, isRetried = true) => {
    try {
      await part()
    } catch {
      if (isRetried) unread.push(part)
    }
  }
  await step(() => loadSettings($))
  // Open first: the reads below run processes, and each fills its section as it lands.
  // Not retried: a pane opening long after the start would come from nowhere.
  await step(async () => {
    const o = await live($)
    if (isStart && o.isMinimized) {
      if ((await read($, view)) !== 'settings') await shutPane($)
    } else if (isStart && o.openAtStart) void $.ui.open(paneFor(o.layout))
  }, false)
  await step(async () => {
    S.compactWindow = await readCompactWindow($)
    await onBudget($, await refresh($, (await live($)).tuning, S.compactWindow))
  })
  await step(() => seedUsage($))
  await step(() => readAccount($))
  await step(() => readPlace($))
  await step(() => readBreakdown($))
  await step(() => readEngine($))
  await step(() => readWhere($))
  await step(() => readNotifier($))
  S.runKey = ''
  // The run first: the resume offer is not recomputed while one is active.
  await step(() => trackAutoRun($))
  await step(() => readRun($))
  await step(() => beat($))
  await step(() => readVersion($))
  await step(() => readRemote($))
  S.sessionUnread = unread
  // '' when the id could not be read: the poll adopts the first id it reads.
  await update($, sessionRead, () => id ?? '')
}

/**
 * One poll tick: first a session the cockpit has not read, which a /clear or
 * /resume leaves with no values or another id, and at a slow tick the steps
 * of its read that failed; then nothing unless the pane is
 * placed or the cockpit minimized; then changed settings and the run, and
 * every DETAIL_EVERY ticks the slower readings and the auto run.
 */
async function pollTick($: EngineInterface) {
  if (S.isPolling) return
  S.isPolling = true
  try {
    const seen = await read($, sessionRead)
    const id = await $.session.id().catch(() => null)
    if (seen === null || (id !== null && seen !== '' && id !== seen)) {
      // A /resume carries the process into another session, whose own counts start at zero.
      resetSessionGuards()
      await readSession($, false)
      return
    }
    if (seen === '' && id !== null) await update($, sessionRead, () => id)
    S.polls += 1
    const isSlowTick = S.polls % DETAIL_EVERY === 0
    if (isSlowTick && S.sessionUnread.length > 0) {
      const parts = S.sessionUnread
      S.sessionUnread = []
      for (const part of parts) await part().catch(() => S.sessionUnread.push(part))
    }
    if (!(await live($)).isMinimized && !(await isPaneUp($))) {
      // The resume band draws without the pane, so its offer is read again on
      // the slow ticks: a claim taken or released elsewhere reaches it.
      if (isSlowTick) await readRun($)
      return
    }
    await rereadSettings($)
    await readRun($)
    if (!isSlowTick) return
    if ((await $.clock.now()) - S.detailAt >= DETAIL_EVERY * POLL_MS) await refreshDetail($)
    await trackAutoRun($)
  } finally {
    S.isPolling = false
  }
}

/** Puts the settings in force again when the file or the engine's settings changed; a file that is not a JSON object keeps the values in force. */
// The engine can write its own settings over a save that lands right after
// one of its own, so a Claude key is read back as restoreUserDefaults reads
// the defaults. Unseen after the wait, the save is no longer shown as saved.
// It runs apart from the press, which would otherwise wait out the polls.
async function claudeReadBack($: EngineInterface, key: string, value: SettingValue | undefined) {
  try {
    let user: Record<string, unknown> | null = null
    for (let waited = 0; ; waited += RESTORE_POLL_MS) {
      user = (await $.settings.read({ source: 'user' }).catch(() => null)) as Record<string, unknown> | null
      if (user !== null && user[key] === value) return
      if (waited >= RESTORE_WAIT_MS) break
      await $.clock.sleep(RESTORE_POLL_MS)
    }
    // An unreadable engine says nothing; a later save of the key owns the overlay.
    if (user === null || !(key in S.claudeSaved) || S.claudeSaved[key] !== value) return
    const engine = user[key]
    delete S.claudeSaved[key]
    const { path, mtime } = await configStamp($)
    const file = path === null ? {} : await readSettingsFile($, path)
    await applySettings($, inForce(file), mtime)
    // The terminal host cuts a toast after three 40-column lines, so the remedy
    // comes before anything else and no path, which alone can fill a line, is named.
    $.ui.toast(`dagents: ${key} did not stick (the engine kept ${engine === undefined ? 'no value' : JSON.stringify(engine)}). Set it again, or edit Claude's settings.json.`)
  } catch {
    // The read-back is a courtesy: a failure leaves the save shown as saved.
  }
}

async function rereadSettings($: EngineInterface) {
  const { path, mtime } = await configStamp($)
  const claude = await engineSettings($)
  if (mtime === S.seen.config && claude === S.seen.claude) return
  const file = path === null ? {} : await readSettingsFile($, path)
  if (file === null) {
    S.seen = { config: mtime, claude }
    // A file that never parsed this session keeps its problem line until it does.
    if (S.brokenConfig !== null) return
    const problem = `${path} is not a JSON object; the settings in force are kept`
    if (!S.settingProblems.includes(problem)) S.settingProblems = [...S.settingProblems, problem]
    $.ui.invalidate('ui.render')
    return
  }
  S.brokenConfig = null
  const before = (await live($)).layout
  const was = ((await read($, settings)) ?? {}) as Record<string, SettingValue | undefined>
  await applySettings($, file, mtime)
  // A skill-enforced key saved outside the pane reaches the session as a pane save does.
  const values = ((await read($, settings)) ?? {}) as Record<string, SettingValue | undefined>
  for (const [key, spec] of Object.entries(SCHEMA)) if (spec.enforcedBy === 'skill' && values[key] !== was[key] && values[key] !== undefined) S.changed[key] = values[key]
  await reseatPane($, before)
}

/**
 * Seats the cockpit for a layout saved outside the pane (dagents-config or
 * another session), as the pane's own controls do when they save it: the band
 * in the pane's place, or the pane in the band's, or the open pane asked for
 * the new layout's rows. The settings view is left where it is.
 */
async function reseatPane($: EngineInterface, before: Live['layout']) {
  const o = await live($)
  if (o.layout === before || (await read($, view)) === 'settings') return
  if (o.isMinimized) await shutPane($)
  else if (before === 'compact' || (await isPaneUp($))) await $.ui.open(paneFor(o.layout))
}

// The pane's slower readings: the /context breakdown, estimated locally, and
// the working tree's git state. Read while the pane is up, never per tool call.
async function refreshDetail($: EngineInterface) {
  S.detailAt = await $.clock.now()
  await readPlace($)
  await readBreakdown($)
  try {
    const ran = await $.process.run(GIT_STATUS, { timeoutMs: 3000 })
    const state = ran.exitCode === 0 ? repoFromPorcelain(ran.stdout) : null
    if (JSON.stringify(await read($, repo)) !== JSON.stringify(state)) await update($, repo, () => state)
  } catch (error) {
    // A large repository can outrun the timeout: its last reading stands rather than a blank card.
    if (!TIMED_OUT.test(String(error)) && (await read($, repo)) !== null) await update($, repo, () => null)
  }
}

/** The /context breakdown, estimated locally: no process, and there before any response. */
async function readBreakdown($: EngineInterface) {
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
        total: detail.totalTokens,
      }
      if (JSON.stringify(await read($, breakdown)) !== JSON.stringify(next)) await update($, breakdown, () => next)
    }
  } catch {
    // No breakdown on this host: the pane shows the totals alone.
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

function limitsOf(windows: readonly { kind: string; percentUsed: number; resetsAt?: string }[]): CockpitUsage['limits'] {
  return windows.map(limit => ({
    kind: limit.kind,
    percent: limit.percentUsed,
    resetsAt: limit.resetsAt === undefined ? null : Date.parse(limit.resetsAt) || null,
  }))
}

/**
 * Fills the Usage section when no measurement has: a new session after /clear
 * holds none until its first turn ends. The limits are the usage op's, else
 * the last read ones whose window has not reset.
 */
async function seedUsage($: EngineInterface) {
  if ((await read($, usage)) !== null) return
  try {
    const figures = await $.session.usage()
    const now = await $.clock.now()
    const fresh = limitsOf(figures.rateLimits)
    const limits = fresh.length > 0 ? fresh : S.limits.filter(limit => limit.resetsAt === null || limit.resetsAt > now)
    if (limits.length === 0) return
    S.limits = limits
    await update($, usage, () => ({ startedAt: figures.startedAt, readAt: now, limits }))
  } catch {
    // No reading yet: the section waits for the first measurement.
  }
}

/** Whether the session's directory differs from the one the place was read in. */
async function hasMoved($: EngineInterface): Promise<boolean> {
  const cwd = await $.session.cwd().catch(() => null)
  return cwd !== null && cwd !== (await read($, place))?.cwd
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
  const top = await $.process.run(['git', 'rev-parse', '--show-toplevel'], { timeoutMs: 2000 }).catch(() => null)
  S.where.checkout = top?.exitCode === 0 ? (top.stdout.split('\n')[0] ?? '').trim() || null : null
}

// Until the first request goes out: the session's model and the effort setting.
async function readEngine($: EngineInterface) {
  try {
    const model = await $.session.model()
    const effort = effortFor(model, (await $.settings.read()) as SettingsEffort)
    await update($, engine, now => ({ ...now, model: now.model ?? model, effort: now.effort ?? effort }))
  } catch {
    // The first request fills them in.
  }
  await readStyle($)
}

// The output style from the merged settings; "default", or none set, is null.
async function readStyle($: EngineInterface) {
  try {
    const setting = ((await $.settings.read()) as { outputStyle?: unknown }).outputStyle
    const style = typeof setting === 'string' && setting !== '' && setting.toLowerCase() !== 'default' ? setting : null
    if ((await read($, engine)).style !== style) await update($, engine, now => ({ ...now, style }))
  } catch {
    // The band shows no style.
  }
}

type SettingsEffort = { effortLevel?: unknown; modelSettings?: Record<string, { effortLevel?: unknown } | undefined> }

/**
 * The effort a model starts with: its own modelSettings entry, under its id or
 * the id with a context suffix such as [1m], else the global effortLevel.
 */
function effortFor(model: string, settings: SettingsEffort): string | null {
  const own = settings.modelSettings ?? {}
  const key = Object.keys(own).find(one => one === model) ?? Object.keys(own).find(one => one.startsWith(`${model}[`) || model.startsWith(`${one}[`))
  const level = (key === undefined ? undefined : own[key]?.effortLevel) ?? settings.effortLevel
  return typeof level === 'string' ? level : null
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
  const said = [...(await read($, alerted)), ...S.alerted]
  const crossed: CockpitUsage['limits'] = []
  for (const limit of reading.limits) {
    const key = `${limit.kind}@${limit.resetsAt ?? ''}`
    if (limit.percent < at || said.includes(key)) continue
    S.alerted = [...S.alerted, key].slice(-20)
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
    const { base } = await $.session.version()
    S.canUnderline = isAtLeast(base, UNDERLINE_SINCE)
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
  await settleBackground($)
}

// A Bash call that went to the background (asked for, Ctrl+B, or its
// timeout) is a running shell until its notification or a stop names it.
async function trackShells($: EngineInterface, tool: string, e: object, result: unknown) {
  if (tool === 'Bash') {
    const id = (result as { backgroundTaskId?: unknown } | undefined)?.backgroundTaskId
    if (typeof id !== 'string' || id === '') return
    const shell: CockpitShell = { id, command: String((e as { command?: unknown }).command ?? ''), startedAt: await $.clock.now(), agentId: (e as { agentId?: string }).agentId ?? null }
    await update($, shells, list => [...list.filter(one => one.id !== id), shell].slice(-20))
    await syncTicker($)
    return
  }
  if (tool === 'TaskStop') {
    const input = e as { task_id?: unknown; shell_id?: unknown }
    const id = (result as { task_id?: unknown } | undefined)?.task_id ?? input.task_id ?? input.shell_id
    if (typeof id === 'string') {
      await update($, shells, list => list.filter(one => one.id !== id))
      await update($, spawns, all => all.map(one => ((one.agentId === id || one.name === id) && !one.isDone ? { ...one, isDone: true, outcome: 'failed' as const } : one)))
      await syncTicker($)
      await settleBackground($)
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

function isJudgeSeat(seat: string | undefined): boolean {
  return seat !== undefined && isDagents(seat) && seat.slice(seat.indexOf(':') + 1).startsWith('judge-')
}

// Past 50 records the oldest finished ones go; a running one stays, as the
// review-seat write guard reads its reports.
function trimmedSpawns(list: CockpitSpawn[]): CockpitSpawn[] {
  let excess = list.length - 50
  return list.filter(one => {
    if (excess <= 0 || !one.isDone) return true
    excess--
    return false
  })
}

// Windows is told from the roots: the engine names no platform.
function isDriveHost(): boolean {
  return [S.where.checkout, S.where.primary].some(dir => dir !== null && /^[A-Za-z]:\//.test(dir.replace(/\\/g, '/')))
}

// A `..` segment is refused, not resolved: `<dir>/x/../f` is not `<dir>/f`
// when x is a symbolic link, which the guard cannot see.
function canonPath(path: string): string | null {
  let rest = path.replace(/\\/g, '/')
  let drive = ''
  const letter = isDriveHost() ? (/^\/([A-Za-z])\//.exec(rest) ?? /^([A-Za-z]):\//.exec(rest)) : null
  if (letter !== null) {
    drive = `${(letter[1] ?? '').toLowerCase()}:`
    rest = rest.slice(2)
  }
  if (!rest.startsWith('/')) return null
  const segments = rest.split('/').filter(one => one !== '' && one !== '.')
  if (segments.includes('..')) return null
  return `${drive}/${segments.join('/')}`
}

// Only a drive host spells a canonical path with a drive letter.
function pathKey(canon: string): string {
  return /^[a-z]:\//.test(canon) ? canon.toLowerCase() : canon
}

// Every worktree counts, not only the two the session knows: its directory
// can sit in the primary checkout while the work and the report are in a
// worktree, and S.where follows it only after the next shell call.
async function reviewDirs($: EngineInterface): Promise<string[]> {
  const listed = await $.process.run(['git', 'worktree', 'list', '--porcelain'], { timeoutMs: 2000 }).catch(() => null)
  const worktrees = listed?.exitCode === 0 ? listed.stdout.split('\n').flatMap(line => (line.startsWith('worktree ') ? [line.slice('worktree '.length).trim()] : [])) : []
  // The session's directory last: a report under it is found while S.where is
  // unset and git cannot list the worktrees.
  const cwd = await $.session.cwd().catch(() => null)
  return [...new Set([S.where.checkout, S.where.primary, ...worktrees, cwd].filter((dir): dir is string => typeof dir === 'string' && dir !== ''))]
}

function rootsOf(dirs: readonly string[]): string[] {
  return dirs.flatMap(dir => {
    const root = canonPath(`${dir}/.dagents`)
    return root === null ? [] : [root]
  })
}

function rootOf(canon: string, roots: readonly string[]): string | undefined {
  const key = pathKey(canon)
  return roots.find(root => key.startsWith(`${pathKey(root)}/`))
}

// Each root is also matched literally, in either slash, so a path under a root
// that holds spaces or parentheses is captured whole; below the root a path
// still stops at them, as the shape's tail says.
function pathsIn(text: string, dirs: readonly string[], shape: ReturnType<typeof pathShape>): string[] {
  const roots = rootsOf(dirs)
  const found: string[] = []
  const add = (path: string) => {
    const canon = canonPath(path)
    if (canon !== null && rootOf(canon, roots) !== undefined && !found.includes(path)) found.push(path)
  }
  for (const [path] of text.matchAll(shape.whole)) add(path)
  for (const dir of dirs) {
    const raw = `${dir}/.dagents`
    for (const spelling of new Set([raw, raw.replace(/\\/g, '/'), raw.replace(/\//g, '\\')])) {
      const literal = spelling.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      const head = new RegExp(`(?<![\\w.~/\\\\-])${literal}`, /^[A-Za-z]:/.test(spelling) ? 'gi' : 'g')
      for (const at of text.matchAll(head)) {
        const tail = shape.tail.exec(text.slice(at.index + at[0].length))
        if (tail !== null) add(at[0] + tail[0])
      }
    }
  }
  return found
}

// The implementer's report (task-<N>-report.md), which a review dispatch also
// names, is never a judge's to write.
function reportPathsIn(text: string, dirs: readonly string[]): string[] {
  return pathsIn(text, dirs, REPORT_PATH).filter(path => !/[\\/]task-\d+-report\.md$/i.test(path))
}

// The documented dispatch is only a pointer to the prompt file, so a dispatch
// that names no report is answered from the prompt files it names. The roots
// are kept with the paths: the session may move before the judge writes.
async function judgeReports($: EngineInterface, prompt: string): Promise<{ reports: string[]; reportRoots: string[] }> {
  const dirs = await reviewDirs($)
  const reportRoots = rootsOf(dirs)
  // A prompt that names its report on the report line allows only that line's
  // paths: a re-review prompt also names the prior round's report to read. A
  // report line naming no path leaves the lookup below to answer.
  const onLine = [...new Set([...prompt.matchAll(REPORT_LINES)].flatMap(match => reportPathsIn(match[1] ?? '', dirs)))]
  if (onLine.length > 0) return { reports: onLine, reportRoots }
  const named = reportPathsIn(prompt, dirs)
  if (named.length > 0) return { reports: named, reportRoots }
  const reports = new Set<string>()
  for (const file of pathsIn(prompt, dirs, PROMPT_PATH)) {
    const text = await $.fs.read(canonPath(file) ?? file).catch(() => '')
    for (const line of text.split('\n').filter(one => REPORT_LINE.test(one))) {
      for (const path of reportPathsIn(line, dirs)) reports.add(path)
    }
  }
  return { reports: [...reports], reportRoots }
}

// The root is trusted as an existing directory; each path below it down to
// the target must not be a symbolic link. A stat rejection that statMissing
// does not read as a missing path refuses. A rejection with no code is
// checked against its directory's listing: a path the listing names exists,
// so it refuses. The walk stops at the first missing path, as nothing below it
// exists.
async function isNamedReport($: EngineInterface, target: string, allowed: readonly string[], roots: readonly string[]): Promise<boolean> {
  const canon = canonPath(target)
  if (canon === null) return false
  const key = pathKey(canon)
  const isAllowed = allowed.some(path => {
    const one = canonPath(path)
    return one !== null && pathKey(one) === key
  })
  if (!isAllowed) return false
  const root = rootOf(canon, roots)
  if (root === undefined) return false
  const parts = canon.split('/')
  let isAboveDir = true
  for (let at = root.split('/').length + 1; at <= parts.length; at++) {
    let info: Awaited<ReturnType<EngineInterface['fs']['stat']>>
    try {
      info = await $.fs.stat(parts.slice(0, at).join('/'))
    } catch (error) {
      if (!statMissing(error, isAboveDir)) return false
      if (typeof (error as { code?: unknown } | null)?.code === 'string') return true
      const name = parts[at - 1] ?? ''
      const listed = await $.fs.list(parts.slice(0, at - 1).join('/')).catch(() => [])
      return !listed.some(entry => entry.name === name)
    }
    if (info.isLink === true) return false
    isAboveDir = info.kind === 'dir'
  }
  return true
}

// A failing agent list refuses no write of a loop the spawn record does not
// call a judge's; for one it does, the hook's .catch refuses the write.
async function judgeWriteDenial($: EngineInterface, tool: string, e: { agentId?: string }): Promise<string | null> {
  const spawn = (await read($, spawns)).find(one => one.agentId === e.agentId)
  const isRecordedJudge = isJudgeSeat(spawn?.seat)
  const agents = await $.agent.list().catch(error => {
    if (isRecordedJudge) throw error
    return null
  })
  if (agents === null) return null
  if (!isRecordedJudge && !isJudgeSeat(agents.find(one => one.id === e.agentId)?.type)) return null
  try {
    const paths = e as { file_path?: unknown; notebook_path?: unknown }
    const named = tool === 'NotebookEdit' ? paths.notebook_path : paths.file_path
    const target = typeof named === 'string' ? named : ''
    const allowed = spawn?.reports ?? []
    if (await isNamedReport($, target, allowed, spawn?.reportRoots ?? [])) return null
    return `dagents: a review seat writes only the report file its dispatch names (${allowed.length === 0 ? 'none' : allowed.join(', ')}); ${target} is not one.`
  } catch (error) {
    return `dagents: the review-seat write guard could not check this write (${error instanceof Error && error.message !== '' ? error.message : String(error)}); it is refused.`
  }
}

async function attributionLine($: EngineInterface, tool: string, e: object): Promise<string | undefined> {
  if (tool === 'Bash') {
    const command = String((e as { command?: unknown }).command ?? '')
    if (!writesGitText(command)) return undefined
    // Only the text the command writes is read, unless the command may give
    // its message text those words do not show (gitMessageTexts): then the
    // whole command is read, as it is when a message file is not there yet.
    const { texts, isWhole } = gitMessageTexts(command)
    for (const text of texts) {
      const inline = attributionIn(text)
      if (inline !== undefined) return inline
    }
    // A relative file is read from the session's directory: a cd earlier in
    // the command is not followed. Only a regular file is read: this hook runs
    // before the tool, and a read of /dev/stdin or a pipe would wait on input
    // the command has not yet given.
    let isUnseen = isWhole
    const cwd = await $.session.cwd().catch(() => null)
    for (const file of gitTextFiles(command)) {
      const path = isAbsolutePath(file) || cwd === null ? file : `${cwd.replace(/[\\/]+$/, '')}/${file}`
      const text = (await $.fs.stat(path).catch(() => null))?.kind === 'file' ? await $.fs.read(path).catch(() => null) : null
      if (text === null) {
        isUnseen = true
        continue
      }
      const line = attributionIn(String(text))
      if (line !== undefined) return line
    }
    return isUnseen ? attributionIn(command, true) : undefined
  }
  if (!isGitWriteTool(tool)) return undefined
  for (const text of stringsIn(e)) {
    const line = attributionIn(text)
    if (line !== undefined) return line
  }
  return undefined
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
  return seat.replace(/^dagents:/, '')
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

// Whether a call's command or file names a .dagents path or finish-choice, as a ledger write or the finish choice does.
function touchesRun(e: object): boolean {
  const args = e as Record<string, unknown>
  return ['command', 'file_path', 'notebook_path', 'path'].some(key => {
    const value = args[key]
    return typeof value === 'string' && /\.dagents|finish-choice/.test(value)
  })
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

// The promise's value, or null once `ms` pass first.
async function within<T>($: EngineInterface, work: Promise<T>, ms: number): Promise<T | null> {
  let timer = null as Timer | null
  const late = new Promise<null>(resolve => {
    timer = $.clock.after(ms, () => resolve(null))
  })
  try {
    return await Promise.race([work, late])
  } finally {
    timer?.cancel()
  }
}

/**
 * Posts a body to the webhook, or with `id` edits that message, waiting out
 * one rate limit and giving up on a request left unanswered. Never throws.
 */
async function sendDiscord($: EngineInterface, url: string, body: Record<string, unknown>, id?: string): Promise<SendResult> {
  const base = url.trim().replace(/\/$/, '')
  const target = id === undefined ? `${base}?wait=true` : `${base}/messages/${id}`
  const init = { method: id === undefined ? 'POST' : 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const answer = await within($, $.http.fetch(target, init), SEND_LIMIT_MS)
      if (answer === null) return { isSent: false, reason: 'Discord did not answer' }
      if (answer.status === 429 && attempt === 0) {
        let wait = NaN
        try {
          wait = Number((JSON.parse(answer.text || '{}') as { retry_after?: unknown }).retry_after)
        } catch {
          // A proxy's HTML page: wait the default second.
        }
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
      // A host's fetch error may quote the URL, and the reason is shown and
      // returned as command text, which the transcript keeps.
      return { isSent: false, reason: redact(error instanceof Error ? error.message : String(error)) }
    }
  }
  return { isSent: false, reason: 'Discord is rate limiting' }
}
