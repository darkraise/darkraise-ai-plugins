import { describe, expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'
import type { CommandRunInput, On, RenderElement, SessionMeasureInput, SessionMessage } from 'claude-code'

import {
  accountColor,
  accountKey,
  agentGroups,
  autoLimitFor,
  autoRunFor,
  isAbsolutePath,
  isDforge,
  gitTextFiles,
  isPlanTail,
  kTokens,
  attributionIn,
  bar,
  billingLabel,
  bottomRule,
  budgetFor,
  cellWidth,
  collapsedFrom,
  collapsedToggled,
  denseLine,
  duration,
  elapsed,
  endsOnSentinel,
  finalLimitFor,
  finishLine,
  bandLines,
  fitBand,
  folderRuns,
  handedOff,
  isAtLeast,
  isServiceCommand,
  levelOf,
  limitForecast,
  modelName,
  MODE_LABEL_RESERVE,
  nowLine,
  parseFinish,
  parseLedger,
  parseModeLines,
  planCandidates,
  planTasks,
  planWithUpdate,
  remoteRuns,
  repoFromPorcelain,
  repoName,
  resumeOfferOf,
  runList,
  runsWidth,
  runsCut,
  sectionsToggled,
  sparkline,
  stackedRuns,
  shellAge,
  tasksEnded,
  termColor,
  themeColor,
  track,
  turnsToBudget,
  windowElapsed,
  writesGitText,
} from '../hooks/cockpit/lib'
import type { ActivityInput, DenseInput, Run } from '../hooks/cockpit/lib'
import {
  discordBody,
  excerpt,
  isDiscordWebhook,
  maskWebhook,
  mentionId,
  notifyKindsFrom,
  notifyKindsToggled,
  redact,
} from '../hooks/cockpit/notify'
import type { Schema, SettingSpec, SettingsFile } from '../hooks/cockpit/config'
import {
  SCHEMA,
  claudeLocks,
  envLocks,
  importedSettings,
  isValidSetting,
  rangeText,
  resolveSettings,
  rowOf,
  rowsOf,
  settingProblems,
  settingWritten,
  shownValue,
  steppedSetting,
  tabsOf,
  typedNumber,
} from '../hooks/cockpit/config'
import { nativeLine, nativeRun } from '../hooks/cockpit/native'
import { drawSettings } from '../hooks/cockpit/settings-view'
import { avatarSvg, bandMetersSvg, gaugeTileSvg, gaugeSvg, labelledMeterSvg, meterSvg, paint, seatSvg, segmentsSvg, stackSvg, svgWidth, trendSvg } from '../hooks/cockpit/svg'

const SURFACES = ['terminal', 'desktop'] as const
const runsText = (runs: Run[]) => runs.map(one => one.text).join('')
// Every Box's text, its strings joined: a desktop row's left and right halves
// are Boxes of their own, and the engine keeps no key on a Text.
const boxTexts = async (ui: { findAll: (query: { type: string }) => Promise<{ text: string }[]> }) => (await ui.findAll({ type: 'Box' })).map(one => one.text)
const BAND = {
  plugin: 'dforge',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 3, bodyColumns: 100, scroll: { offset: 0, bodyRows: 3 }, view: {} },
} as const
const HINT = {
  plugin: 'dforge',
  component: 'PromptHint',
  props: { isDraft: false, isWorking: false, hint: '? for shortcuts' },
} as const
const PANE = {
  plugin: 'dforge',
  component: 'Pane',
  requestId: 'dforge',
  props: { title: 'Cockpit', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
} as const
// Where a minimized cockpit draws: below the prompt on the terminal, above it on the desktop.
const minimized = (surface: (typeof SURFACES)[number], viewport = { columns: 120, rows: 40, isFullscreen: false }) =>
  surface === 'terminal' ? { ...HINT, surface, viewport } : { ...BAND, surface, viewport }
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

// Handoff notes as scripts/next-step writes them: a next session to start, or none.
const RESUMABLE = [
  '# Handoff',
  '',
  '## Next session',
  '',
  '**Status:** Plan `docs/dforge/plans/2026-10-14-band.md`: 3 of 6 tasks complete.',
  '**Next:** Task 4 — wire the band into the pane.',
  '',
  'Launch in `/home/me/code/shop`:',
  '',
  '```',
  'claude --model opus',
  '```',
  '',
  'Paste as the first prompt:',
  '',
  '```',
  'Execute docs/dforge/plans/2026-10-14-band.md.',
  '```',
  '',
  '## State',
  '',
  'Worktree: /home/me/code/shop-wt',
  '',
].join('\n')
const FINISHED = '# Handoff\n\n## Next session\n\n**Status:** Plan `docs/dforge/plans/x.md` is complete.\n**Next:** Nothing — the plan records no follow-on work.\n'
const BLOCKED =
  '# Handoff\n\n## Next session\n\n**Status:** Plan `docs/dforge/plans/x.md`: 2 of 5 tasks complete; Task 3 is BLOCKED (needs a key).\n**Next:** Your human partner decides: needs a key.\n'

// What a compaction leaves: one row standing for the conversation.
const SUMMARY: SessionMessage = { role: 'user', text: 'Summary.', toolUses: [] }

const CONFIG = '/home/me/.dforge/config.json'

/** A settings file holding these values, as files for signedIn. */
function configured(values: Record<string, unknown>): NonNullable<World['files']> {
  return { [CONFIG]: { text: JSON.stringify(values) } }
}

type World = {
  tokens: number | undefined
  window?: number
  startedAt?: number
  settings?: Record<string, unknown>
  /** What the user's own Claude settings file holds, when it differs from the merged `settings`. */
  userSettings?: Record<string, unknown>
  /** Each dforge-config command the plugin runs, as one line. */
  runs?: string[]
  /** dforge-config refuses, as on a Claude settings file it cannot parse. */
  isDforgeConfigRefusing?: boolean
  /** How many claude-restore writes the engine misses, as one landing right after its own save. */
  missedRestores?: number
  /** The session refuses every row the plugin appends. */
  isAppendFailing?: boolean
  toasts?: string[]
  notes?: string[]
  env?: Record<string, string>
  /** Files the plugin reads, by path, with their modification time. */
  files?: Record<string, { text: string; mtimeMs?: number; kind?: 'file' | 'dir' | 'other' }>
  /** What the plugin writes, by path. */
  written?: Record<string, string>
  /** Each request the plugin sends through $.http.fetch. */
  prompts?: string[]
  fetches?: { url: string; method: string; body: Record<string, unknown> }[]
  /** How Claude Code answers the pane opening; placed unless said. */
  open?: { isPlaced: true } | { isPlaced: false; reason: string }
  opened?: string[]
  /** The rows each pane open asked for; undefined asks for the full pane. */
  openedRows?: (number | undefined)[]
  /** Each pane the plugin closes, by id. */
  closed?: string[]
  isPaneShut?: boolean
  /** The Claude Code release the engine reports; absent, `$.session.version()` fails. */
  version?: string
  /** The /config row "Enable Remote Control for all sessions"; absent unless said. */
  remoteControl?: string
  /** Tools that answer in their own way, by name. */
  tools?: Record<string, () => Promise<{ result: unknown; text: string }> | { result: unknown; text: string }>
  /** ~/.dforge/config.json's values; set, HOME is /home/me and world answers reads of the file. */
  config?: Record<string, unknown>
  /** Every write fails, as on a read-only file system. */
  isReadOnly?: boolean
  /** The session id `$.session.id()` answers; `sess-1` unless said. A /clear sets `sess-2`. */
  sessionId?: string
  /** Each compaction the engine runs, as `<trigger>:<instructions>`. */
  compacts?: string[]
  /** Every compaction is vetoed, as a PreCompact hook would. */
  isCompactVetoed?: boolean
  /** Each slash command the plugin runs, as typed. */
  commands?: string[]
  /** Slash commands that refuse to run, by name. */
  refusedCommands?: string[]
  /** How many prompt submissions fail before one goes through. */
  submitFailures?: number
  /** Each scripts/auto-run call, after the script's path. */
  autoRuns?: string[]
  /** The exit code of an auto-run command, by its command word; 0 unless said. */
  autoRunExits?: Record<string, number>
  /** The auto-run state file the fake script updates, as the real one would. */
  autoFile?: { text: string }
  /** What `darkmem-config.mjs --mode` answers; `missing` rejects as a missing node does. Git porcelain with exit 0 unless said. */
  modeOut?: { exitCode: number; stdout: string; stderr: string } | 'missing' | 'rejects' | 'timeout'
  /** The directory each `--mode` call names. */
  modeRuns?: string[]
  /** The primary checkout `git rev-parse --git-common-dir` points into; the session's repository unless said. */
  primary?: string
  /** The agent ids the spawns get, in turn; `agent-1` once they run out. */
  agentIds?: string[]
  /** `node --version` cannot start, as on a machine without node. */
  isNodeMissing?: boolean
  /** Reading the user settings rejects. */
  isUserSettingsUnreadable?: boolean
  /** How long each compaction takes, in the clock's milliseconds; at once unless said. */
  compactMs?: number
  /** `git status` outruns its timeout, or cannot start. */
  gitStatusOut?: 'timeout' | 'missing'
  /** Each git command the plugin runs, as one line. */
  gitRuns?: string[]
  /** What `git rev-parse --git-common-dir` answers; `<primary>/.git` unless said. */
  commonDir?: string
  /** Runs inside each scripts/auto-run call, given its command word, before the call answers. */
  onAutoRun?: (word: string) => unknown
  /** How many `$.session.id()` calls fail before one answers. */
  sessionIdFailures?: number
  /** Runs after each settings read has taken its answer, given the source it named. */
  afterSettingsRead?: (source: string | undefined) => void
}

// The engine beneath the plugin: a context of `w.tokens` (read on each call,
// so a test moves it) in a 650k window, every tool call answered, every toast
// and every row the plugin appends recorded in `w.notes`.
function world(on: On, w: World) {
  mock.env(on, { ...(w.config === undefined ? {} : { HOME: '/home/me' }), ...(w.env ?? {}) })
  const clock = mock.clock(on, { now: 1_000_000 })
  on('command.register', () => ({ value: undefined }) as never)
  on('session.start', (_$, e) => e as never)
  on('session.usage', (_$, e) => ({
    value: {
      startedAt: w.startedAt ?? 0,
      context: {
        tokens: w.tokens,
        window: w.window ?? 650_000,
        ...(e.breakdown === undefined ? {} : { breakdown: BREAKDOWN }),
      },
      rateLimits: [],
      cost: { usd: 1.5 },
    },
  }))
  on('settings.read', (_$, e) => {
    if (e?.source === 'user' && w.isUserSettingsUnreadable) throw new Error('EACCES: the user settings cannot be read')
    const value = e?.source === 'user' && w.userSettings !== undefined ? w.userSettings : (w.settings ?? {})
    w.afterSettingsRead?.(e?.source)
    return { value }
  })
  on('tool.call', (_$, e) => w.tools?.[String(e.tool)]?.() ?? { result: 'ok', text: 'ok' })
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: w.agentIds?.shift() ?? 'agent-1' }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('session.version', () => {
    if (w.version === undefined) throw new Error('no version')
    return { value: { version: w.version, base: w.version } }
  })
  on('prompt.submit', (_$, e) => {
    if ((w.submitFailures ?? 0) > 0) {
      w.submitFailures = (w.submitFailures ?? 1) - 1
      throw new Error('busy')
    }
    w.prompts?.push(e.text)
    return { text: e.text }
  })
  on('session.attach', (_$, e) => ({ clientId: e.clientId }))
  on('session.detach', (_$, e) => ({ clientId: e.clientId }))
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('config.list', () => ({
    value:
      w.remoteControl === undefined
        ? []
        : [{ key: 'remoteControl', label: 'Enable Remote Control for all sessions', kind: 'choice', value: w.remoteControl, provider: { kind: 'engine' }, isLocked: false }],
  }) as never)
  on('ui.open', (_$, e) => {
    w.opened?.push(e.id)
    w.openedRows?.push(e.rows)
    return { value: w.open ?? { isPlaced: true } }
  })
  on('ui.close', (_$, e) => {
    w.closed?.push(e.id)
    return { value: undefined } as never
  })
  on('session.compact', (_$, e) => {
    w.compacts?.push(`${e.trigger}:${(e as { instructions?: string }).instructions ?? ''}`)
    const done = w.isCompactVetoed ? ({ skip: 'vetoed' } as never) : { messages: e.messages ?? [SUMMARY] }
    return w.compactMs === undefined ? done : clock.sleep(w.compactMs).then(() => done)
  })
  on('command.run', (_$, e) => {
    if (w.refusedCommands?.includes(e.command)) throw new Error(`/${e.command} refused`)
    w.commands?.push(e.args === '' ? `/${e.command}` : `/${e.command} ${e.args}`)
    if (e.command === 'clear') w.sessionId = 'sess-2'
    if (e.command === 'model' && w.userSettings !== undefined) w.userSettings = { ...w.userSettings, model: e.args }
    if (e.command === 'effort' && w.userSettings !== undefined) {
      w.userSettings = { ...w.userSettings, modelSettings: { ...(w.userSettings.modelSettings as object | undefined), 'claude-sonnet-5-5': { effortLevel: e.args } } }
    }
    return { text: '' } as never
  })
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('process.run', (_$, e) => {
    const argv = e.argv.join(' ')
    const script = '/scripts/auto-run '
    if (argv.includes(script)) {
      const call = argv.slice(argv.indexOf(script) + script.length)
      w.autoRuns?.push(call)
      const words = call.split(' ')
      const word = words[2] ?? ''
      const exitCode = w.autoRunExits?.[word] ?? 0
      if (w.autoFile !== undefined) {
        const state = JSON.parse(w.autoFile.text) as Record<string, unknown>
        if (exitCode === 0 && word === 'compacted') Object.assign(state, { pending: words[3] === '--switch' ? 'switch-resume' : 'after-compact', compactions: Number(state.compactions) + 1 })
        if (exitCode === 0 && word === 'rebind') Object.assign(state, { session: words[4], pending: 'resume', regime: 'normal' })
        if (exitCode === 0 && word === 'resumed' && state.pending === 'resume') state.pending = null
        else if (exitCode === 0 && word === 'resumed' && state.pending === 'switch-resume') state.pending = 'after-compact'
        if (exitCode === 0 && word === 'stop') Object.assign(state, { active: false, stopped: call.split(' --reason ')[1] ?? null, pending: null })
        if (exitCode === 5 && word === 'failure') Object.assign(state, { active: false, stopped: 'the cockpit could not compact twice', pending: null })
        if (exitCode === 5 && word === 'compacted') Object.assign(state, { active: false, stopped: '3 compactions without a completed task', pending: null })
        if (exitCode === 0 && word === 'stalled') Object.assign(state, { stalls: Number(state.stalls ?? 0) + 1, stalledAt: Math.floor(clock.now() / 1000) })
        if (exitCode === 5 && word === 'stalled') Object.assign(state, { active: false, stopped: '3 stalls without a completed task', pending: null })
        w.autoFile.text = JSON.stringify(state)
      }
      const answer = { value: { exitCode, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
      const during = w.onAutoRun?.(word)
      return during instanceof Promise ? during.then(() => answer) : answer
    }
    if (argv.includes('/scripts/lib/dforge-config.mjs ')) {
      w.runs?.push(argv)
      // dforge-config's first run creates the settings file with dr-cockpit's
      // options (importLegacy), unless the file exists or it refuses.
      if (e.argv.includes('get') && w.config === undefined && !w.isDforgeConfigRefusing && w.written !== undefined && !(CONFIG in w.written)) {
        w.written[CONFIG] = `${JSON.stringify(importedSettings(SCHEMA, w.userSettings ?? w.settings ?? {}), null, 2)}\n`
      }
      const restore = e.argv[e.argv.indexOf('claude-restore') + 1]
      if (e.argv.includes('claude-restore') && !w.isDforgeConfigRefusing && w.userSettings !== undefined) {
        if ((w.missedRestores ?? 0) > 0) w.missedRestores = (w.missedRestores ?? 0) - 1
        else {
          const next: Record<string, unknown> = { ...w.userSettings }
          for (const [key, value] of Object.entries(JSON.parse(restore!) as Record<string, unknown>)) {
            if (value === null) delete next[key]
            else next[key] = value
          }
          w.userSettings = next
        }
      }
      // A dforge-target set rewrites the settings file as the cockpit's own
      // fallback write would, and fails as that write does.
      const at = e.argv.indexOf('set')
      const setKey = at < 0 ? undefined : e.argv[at + 1]
      const setSpec = setKey === undefined ? undefined : SCHEMA[setKey]
      if (setKey !== undefined && setSpec !== undefined && setSpec.target !== 'claude') {
        if (w.isNodeMissing) return { deny: 'dforge: $.process.run(node) failed to start: ENOENT: Executable not found in $PATH: "node"' }
        if (w.isReadOnly) return { value: { exitCode: 1, stdout: '', stderr: 'dforge-config: EROFS: read-only file system\n', isStdoutTruncated: false, isStderrTruncated: false } }
        const text = e.argv[at + 2] ?? ''
        const value = setSpec.type === 'boolean' ? text === 'true' : setSpec.type === 'number' ? Number(text) : text
        const current = w.written?.[CONFIG] ?? w.files?.[CONFIG]?.text ?? (w.config === undefined ? '{}' : JSON.stringify(w.config))
        const next = settingWritten(SCHEMA, JSON.parse(current) as SettingsFile, setKey, value)
        if (w.written !== undefined) w.written[CONFIG] = `${JSON.stringify(next, null, 2)}\n`
        else w.config = next
        if (w.files?.[CONFIG] !== undefined) w.files[CONFIG].text = JSON.stringify(next)
      }
      const stderr = w.isDforgeConfigRefusing ? 'dforge-config: /home/me/.claude/settings.json is not valid JSON; fix or remove it\n' : ''
      return { value: { exitCode: w.isDforgeConfigRefusing ? 1 : 0, stdout: '', stderr, isStdoutTruncated: false, isStderrTruncated: false } }
    }
    if (argv.includes('/scripts/lib/darkmem-config.mjs ')) {
      w.modeRuns?.push(e.argv[e.argv.length - 1] ?? '')
      if (w.modeOut === 'missing') {
        return clock.advance(5_000).then(() => ({ deny: 'dforge: $.process.run(node) failed to start: ENOENT: Executable not found in $PATH: "node"' }))
      }
      if (w.modeOut === 'rejects') return { deny: 'the engine refused to start the process' }
      if (w.modeOut === 'timeout') return { deny: 'dforge: $.process.run(node) aborted: still running after 5000ms' }
      const out = w.modeOut ?? { exitCode: 0, stdout: PORCELAIN, stderr: '' }
      return { value: { ...out, isStdoutTruncated: false, isStderrTruncated: false } }
    }
    if (argv === 'node --version') {
      if (w.isNodeMissing) return { deny: 'dforge: $.process.run(node) failed to start: ENOENT: Executable not found in $PATH: "node"' }
      return { value: { exitCode: 0, stdout: 'v24.18.0\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    }
    if (argv.startsWith('git --no-optional-locks') && w.gitStatusOut === 'timeout') return { deny: 'dforge: $.process.run(git) aborted: still running after 3000ms' }
    if (argv.startsWith('git --no-optional-locks') && w.gitStatusOut === 'missing') return { deny: 'dforge: $.process.run(git) failed to start: ENOENT' }
    if (argv.startsWith('git ')) w.gitRuns?.push(argv)
    const common = w.commonDir ?? `${w.primary ?? '/home/me/code/shop'}/.git`
    // A directory is a work tree when the common directory is its .git: a
    // primary checkout is; a submodule's modules directory is not.
    const toplevel = /^git -C (.+) rev-parse --show-toplevel$/.exec(argv)
    if (toplevel !== null) {
      const isTree = `${toplevel[1]}/.git` === common
      return {
        value: {
          exitCode: isTree ? 0 : 128,
          stdout: isTree ? `${toplevel[1]}\n` : '',
          stderr: isTree ? '' : 'fatal: not a git repository (or any of the parent directories): .git\n',
          isStdoutTruncated: false,
          isStderrTruncated: false,
        },
      }
    }
    const stdout = argv === 'hostname' ? 'devbox\n' : argv.startsWith('git rev-parse') ? `${common}\n` : PORCELAIN
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('session.id', () => {
    if ((w.sessionIdFailures ?? 0) > 0) {
      w.sessionIdFailures = (w.sessionIdFailures ?? 1) - 1
      throw new Error('no session id')
    }
    return { value: w.sessionId ?? 'sess-1' }
  })
  on('fs.stat', (_$, e) => {
    const file = w.files?.[e.path]
    if (file === undefined) throw new Error('ENOENT')
    return { value: { kind: file.kind ?? 'file', size: file.text.length, mtimeMs: file.mtimeMs ?? 0, isLink: false } }
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
    if (w.isReadOnly) throw new Error('EROFS: read-only file system')
    if (w.written !== undefined) w.written[e.path] = e.text
    return { value: undefined }
  })
  if (w.config !== undefined) {
    on('fs.exists', (_$, e) => ({ value: e.path === CONFIG || e.path in (w.written ?? {}) || e.path in (w.files ?? {}) }))
    on('fs.read', (_$, e) => {
      if (e.path === CONFIG) return { value: w.written?.[CONFIG] ?? JSON.stringify(w.config) }
      throw new Error('ENOENT')
    })
  }
  on('http.fetch', (_$, e) => {
    w.fetches?.push({ url: e.url, method: e.init?.method ?? 'GET', body: JSON.parse(e.init?.body ?? '{}') as Record<string, unknown> })
    return { value: { status: 200, ok: true, headers: {}, text: '{"id":"m1"}' } }
  })
  on('ui.panes', () => ({ value: w.isPaneShut ? [] : [{ id: 'dforge', title: 'Cockpit', isShown: true, isFocused: false, isPlaced: true }] }))
  on('session.append', (_$, e, next) => {
    if (w.isAppendFailing) return { deny: 'append refused' }
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

// A signed-in account working in a repository under home.
const SIGNED_IN = { tokens: 284_000, env: { HOME: '/home/me' }, settings: { effortLevel: 'xhigh' } }
function signedIn(on: On, files: World['files'] = {}, reads?: string[]) {
  on('fs.read', (_$, e) => {
    reads?.push(e.path)
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
    throw new Error('ENOENT')
  })
  on('session.cwd', () => ({ value: '/home/me/code/shop/web' }))
  on('session.repo', () => ({ value: { root: '/home/me/code/shop', remote: null, internal: false, name: null } }))
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
}

test('only a dforge name marks a workflow session', () => {
  expect(isDforge('dforge:brainstorming')).toBe(true)
  expect(isDforge('dr-superpowers:brainstorming')).toBe(false)
  expect(isDforge('feature-dev:code-reviewer')).toBe(false)
})

describe('budget rule', () => {
  test('follows the setting, then the env, then dforge', () => {
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
    expect([kTokens(465_000), kTokens(999_499), kTokens(999_500), kTokens(1_234_567)]).toEqual(['465k', '999k', '1.0M', '1.2M'])
    expect(duration(190_800_000)).toBe('2d5h')
    expect(duration(-5)).toBe('')
    expect(duration(59_999)).toBe('')
    expect(duration(60_000)).toBe('1m')
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

describe('windows paths', () => {
  test('a plan path is absolute from a slash or a drive letter', () => {
    expect(isAbsolutePath('/repo/docs/plan.md')).toBe(true)
    expect(isAbsolutePath('C:\\repo\\docs\\plan.md')).toBe(true)
    expect(isAbsolutePath('d:/repo/docs/plan.md')).toBe(true)
    expect(isAbsolutePath('\\\\host\\share\\plan.md')).toBe(true)
    expect(isAbsolutePath('docs/plan.md')).toBe(false)
    expect(isAbsolutePath('docs\\plan.md')).toBe(false)
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

  test('names the files a commit or pull request takes its text from', () => {
    expect(gitTextFiles('git commit -F msg.txt && git push')).toEqual(['msg.txt'])
    expect(gitTextFiles('git -C repo commit --file="/tmp/a b.txt"; gh pr create --body-file body.md -t x')).toEqual(['/tmp/a b.txt', 'body.md'])
    expect(gitTextFiles('git commit -F - <<EOF\nx\nEOF')).toEqual([])
    expect(gitTextFiles('grep -F needle file && git commit -m x')).toEqual([])
  })

  test('refuses a commit whose message file carries a trailer', async ($, on) => {
    const files: World['files'] = {
      '/home/me/code/shop/web/msg.txt': { text: 'fix: tidy\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n' },
      '/tmp/clean.md': { text: 'A clean body.' },
    }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    const dirty = await $.tool.call({ tool: 'Bash', command: 'git commit -F msg.txt' })
    expect(dirty.deny).toBe('dforge: this project keeps AI attribution out of git. Remove "Co-Authored-By: Claude <noreply@anthropic.com>" and try again.')
    const clean = await $.tool.call({ tool: 'Bash', command: 'gh pr create --title x --body-file /tmp/clean.md' })
    expect(clean.deny).toBeUndefined()
  })

  test('never reads a message file that is not a regular file', async ($, on) => {
    const files: World['files'] = { '/dev/stdin': { text: 'Co-Authored-By: Claude <noreply@anthropic.com>\n', kind: 'other' } }
    const reads: string[] = []
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files, reads)
    const ran = await $.tool.call({ tool: 'Bash', command: "git commit -F /dev/stdin <<'EOF'\nfix: tidy\nEOF" })
    expect(ran.deny).toBeUndefined()
    expect(reads).not.toContain('/dev/stdin')
  })

  test('is off when configured off', async ($, on) => {
    world(on, { tokens: 10_000, config: { guardAttribution: false } })
    await $.session.start(START)
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

  test('the band reads the context against the budget', async ($, on) => {
    const w: World = { ...SIGNED_IN, tokens: 284_000 }
    world(on, w)
    signedIn(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    let ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^61%$/ })).toBeDefined()
    await ui.unmount()

    w.tokens = 400_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^86%$/ })).toBeDefined()
  })

  test('in a plan session, offers the handoff in the pane and sends the note once', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 470_000, notes })
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
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
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
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
      subagentType: 'dforge:impl-sonnet-low',
      provider: { plugin: 'dforge', tier: 'user' },
      parentModel: 'claude-opus-5-5',
      background: false,
      fork: false,
    })
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...PANE, surface })
      // The desktop draws its panels' rows as its own text.
      if (surface === 'desktop') expect(await boxTexts(ui)).toContain('●  impl-sonnet-low  Task 3')
      else expect(await ui.find({ type: 'Text', text: /● impl-sonnet-low Task 3/ })).toBeDefined()
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
      if (surface === 'desktop') {
        const texts = await boxTexts(ui)
        expect(texts).toContain('impl-sonnet-low ×1')
        expect(texts).toContain('40k in · 75% cached · 3k out')
        expect(texts).toContain('✓  impl-sonnet-low  Task 3')
      } else {
        expect(await ui.find({ type: 'Text', text: /40k in · 75% cached · 3k out/ })).toBeDefined()
        expect(await ui.find({ type: 'Text', text: /✓ impl-sonnet-low Task 3/ })).toBeDefined()
      }
      await ui.unmount()
    }
  })

  test('groups agents in order, an ended record without an outcome done', () => {
    const one = (agentId: string, isDone: boolean, outcome?: 'done' | 'failed' | null) => ({ agentId, isDone, outcome })
    const keys = (spawns: ReturnType<typeof one>[], waiting: string[]) => agentGroups(spawns, waiting).map(group => [group.key, group.name, group.spawns.map(spawn => spawn.agentId)])
    expect(keys([one('a', false, null), one('b', false, null), one('c', true, 'failed'), one('d', true)], ['a'])).toEqual([
      ['waiting', 'Waiting on you', ['a']],
      ['working', 'Working', ['b']],
      ['failed', 'Failed', ['c']],
      ['done', 'Done', ['d']],
    ])
    // A wait left open on an ended agent never keeps it waiting.
    expect(keys([one('a', true, 'done')], ['a'])).toEqual([['done', 'Done', ['a']]])
    // The ended ones take only the rows the running ones leave.
    const many = ['r1', 'r2', 'r3', 'r4', 'r5', 'r6'].map(id => one(id, false, null))
    expect(keys([one('old', true, 'done'), ...many], [])).toEqual([['working', 'Working', ['r1', 'r2', 'r3', 'r4', 'r5', 'r6']]])
    expect(keys([one('d1', true, 'done'), one('d2', true, 'failed'), one('d3', true, 'done'), one('r', false, null)], []).map(group => group[2])).toEqual([['r'], ['d2'], ['d1', 'd3']])
    expect(agentGroups([one('d1', true, 'done'), one('d2', true, 'done'), one('r', false, null)], [], 2).map(group => group.spawns.map(spawn => spawn.agentId))).toEqual([['r'], ['d2']])
  })

  test('keeps every running agent when more run than are shown, and no ended one', () => {
    const ended = [{ agentId: 'd1', isDone: true, outcome: 'done' as const }, { agentId: 'd2', isDone: true, outcome: 'failed' as const }]
    const running = ['r1', 'r2', 'r3', 'r4', 'r5', 'r6', 'r7'].map(agentId => ({ agentId, isDone: false }))
    const keys = (shown?: number) => agentGroups([...ended, ...running], [], shown).map(group => [group.key, group.spawns.map(spawn => spawn.agentId)])
    expect(keys()).toEqual([['working', ['r1', 'r2', 'r3', 'r4', 'r5', 'r6', 'r7']]])
    expect(keys(2)).toEqual([['working', ['r1', 'r2', 'r3', 'r4', 'r5', 'r6', 'r7']]])
  })

  test('lists subagents waiting on you, working, failed and done', async ($, on) => {
    world(on, { tokens: 50_000, agentIds: ['agent-1', 'agent-2', 'agent-3', 'agent-4'] })
    on('tool.check', () => ({ decision: 'ask' }))
    await $.session.start(START)
    await $.turn.start({ text: 'go', turnId: 't1' })
    for (const n of [1, 2, 3, 4]) {
      await $.agent.spawn({ tool_use_id: `toolu_${n}`, prompt: 'Implement', description: `Task ${n}`, subagentType: 'dforge:impl-sonnet-low', provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: false, fork: false })
    }
    await $.turn.complete({ answer: '', durationMs: 1000, isAborted: false, turnId: 'turn-3', agentId: 'agent-3', reason: 'error' })
    await $.turn.complete({ answer: 'done', durationMs: 1000, isAborted: false, turnId: 'turn-4', agentId: 'agent-4', reason: 'answer' })
    // Task 1's subagent asks to run a command; Task 2's keeps working.
    await $.tool.check({ tool: 'Bash', input: { command: 'rm -rf build' }, tool_use_id: 'toolu_9', agentId: 'agent-1' })
    // The main loop ending a turn and starting another leaves that approval open.
    await $.turn.complete({ answer: 'ok', durationMs: 1000, isAborted: false, turnId: 'turn-5', reason: 'answer' })
    await $.turn.start({ text: 'next', turnId: 't2' })
    const order = async (ui: { findAll: (query: { type: string }) => Promise<{ text: string }[]> }, surface: string, patterns: RegExp[]) => {
      const texts = surface === 'desktop' ? await boxTexts(ui) : (await ui.findAll({ type: 'Text' })).map(one => one.text)
      return patterns.map(pattern => texts.findIndex(text => pattern.test(text)))
    }
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...PANE, surface })
      const at = await order(ui, surface, [
        /^Waiting on you · 1$/, /^⏳ +impl-sonnet-low +Task 1/,
        /^Working · 1$/, /^● +impl-sonnet-low +Task 2/,
        /^Failed · 1$/, /^✗ +impl-sonnet-low +Task 3/,
        /^Done · 1$/, /^✓ +impl-sonnet-low +Task 4/,
      ])
      expect(at.every(index => index >= 0)).toBe(true)
      expect([...at].sort((a, b) => a - b)).toEqual(at)
      // The headline counts a failed agent apart from a finished one.
      if (surface === 'desktop') expect((await ui.find({ key: 'agents-headline' }))?.text).toBe('2 running · 1 done · 1 failed')
      else {
        expect(await ui.find({ type: 'Text', text: /✓ 1/ })).toBeDefined()
        expect(await ui.find({ type: 'Text', text: /✗ 1/ })).toBeDefined()
      }
      await ui.unmount()
    }
    // The approval is given: the call runs, and Task 1's subagent is working again.
    await $.tool.call({ tool: 'Bash', command: 'rm -rf build', tool_use_id: 'toolu_9', agentId: 'agent-1' } as never)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await order(ui, 'terminal', [/^Waiting on you/, /^Working · 2$/])).toEqual([-1, expect.any(Number)])
    expect((await order(ui, 'terminal', [/^Working · 2$/]))[0]).toBeGreaterThan(-1)
  })

  test('the background pill under an approved call settles its wait after the draw', async ($, on) => {
    const clock = world(on, { tokens: 50_000 })
    on('tool.check', () => ({ decision: 'ask' }))
    await $.session.start(START)
    await $.turn.start({ text: 'go', turnId: 't1' })
    await $.tool.check({ tool: 'Bash', input: { command: 'npm test' }, tool_use_id: 'toolu_1' } as never)
    const now = async () => {
      const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
      const isWaiting = (await ui.find({ type: 'Text', text: /approve\?/ })) !== undefined
      const isRunning = (await ui.find({ type: 'Text', text: /running \d/ })) !== undefined
      await ui.unmount()
      return isWaiting ? 'waiting' : isRunning ? 'running' : 'neither'
    }
    expect(await now()).toBe('waiting')
    const pill = await $.ui.mount({ plugin: 'dforge', surface: 'terminal', component: 'ToolProgress', props: { tool_use_id: 'toolu_1', kind: 'background_hint', hint: '(ctrl+b to run in background)' } })
    await pill.unmount()
    await clock.advance(1)
    expect(await now()).toBe('running')
  })

  test('the desktop context legend squares carry the stack bar colors', async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.session.start(START)
    await $.session.measure({ ...MEASURE, breakdown: true } as never)
    const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
    const squares = (await ui.findAll({ type: 'Text' })).filter(one => one.text === '■ ').map(one => one.props.color)
    expect(squares).toEqual(['#1fa8c9', '#c056d6'])
    await ui.unmount()
  })

  test('shows the context, limits, cost and repo', async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure({
      context: { tokens: 284_000, window: 650_000 },
      rateLimits: [{ kind: 'five_hour', percentUsed: 23 }],
      cost: { usd: 1.5 },
      changed: ['context', 'rateLimits'],
    })
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...PANE, surface })
      const drawn = JSON.stringify(await ui.drawn())
      expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
      if (surface === 'desktop') {
        // The desktop draws its panels' rows and chips as its own text, its
        // gauges and meters as pictures that name their figures in the alt.
        expect((await ui.find({ key: 'usage-headline' }))?.text).toMatch(/^\$1\.50/)
        expect(drawn).toContain('61% of the handoff budget')
        expect(drawn).toContain('5h limit 23% used')
        expect(drawn).toContain('284k of 650k tokens, handoff at 465k')
        for (const chip of ['⎇ feat/pane', '↑2', '↓1', '~1 changed', '?1 untracked']) expect(drawn).toContain(`"children":["${chip}"]`)
      } else {
        expect(await ui.find({ type: 'Text', text: /\$1\.50/ })).toBeDefined()
        expect(await ui.find({ type: 'Text', text: /feat\/pane/ })).toBeDefined()
        expect(await ui.find({ type: 'Text', text: /23%/ })).toBeDefined()
        expect(await ui.find({ type: 'Text', text: /61%/ })).toBeDefined()
        expect(await ui.find({ type: 'Text', text: /284k of 650k ┃ handoff 465k/ })).toBeDefined()
        expect(await ui.find({ type: 'Text', text: /~1 changed \?1 untracked/ })).toBeDefined()
        // Rows sit two cells in under their section, details two more.
        expect(drawn).toContain('"paddingLeft":2')
      }
      await ui.unmount()
    }
  })

  test('names the repository and the working folder', async ($, on) => {
    expect(repoName('git@github.com:darkraise/darkraise-ai-plugins.git', '/x')).toBe('darkraise/darkraise-ai-plugins')
    expect(repoName('https://gitlab.example.com/group/sub/app.git/', '/x')).toBe('sub/app')
    expect(repoName('ssh://git@host:2222/team/app', '/x')).toBe('team/app')
    expect(repoName(null, 'C:\\code\\shop')).toBe('shop')
    expect(runsText(folderRuns('/home/me/code/shop/web', '/home/me/code/shop', '/home/me'))).toBe('~/code/shop/web')
    world(on, { tokens: 284_000 })
    on('session.cwd', () => ({ value: '/home/me/code/shop/web' }))
    on('session.repo', () => ({ value: { root: '/home/me/code/shop', remote: 'git@github.com:acme/shop.git', internal: false, name: null } }))
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure({
      context: { tokens: 284_000, window: 650_000 },
      rateLimits: [{ kind: 'five_hour', percentUsed: 23 }],
      cost: { usd: 1.5 },
      changed: ['context', 'rateLimits'],
    })
    const ui = await $.ui.mount({ ...PANE, props: { ...PANE.props, scroll: { offset: 0, bodyRows: 120 } }, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^repo acme\/shop$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^dir {2}\/home\/me\/code\/shop\/web$/ })).toBeDefined()
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
  test('warnAt moves where the strip shows the handoff', async ($, on) => {
    world(on, { tokens: 340_000, config: { warnAt: 70 } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^73%$/ })).toBeDefined()
  })

  test('relaxed handoff measures the context against the final-phase limit', async ($, on) => {
    // The same worked figure tests/budget-line.test.sh asserts for the scripts.
    expect(finalLimitFor(1_000_000, 800_000)).toBe(680_000)
    expect(finalLimitFor(650_000)).toBe(552_500)
    expect(finalLimitFor(650_000, 0)).toBe(552_500)
    // 276,250 is half of 85% of the 650k window; strict would read 59%.
    world(on, { tokens: 276_250, config: { handoffMode: 'relaxed' } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^50%$/ })).toBeDefined()
  })

  test('strict handoff reads the same context against the handoff budget', async ($, on) => {
    // 276,250 of the 464,500 budget: 59%, where relaxed reads 50%.
    world(on, { tokens: 276_250, config: { handoffMode: 'strict' } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^59%$/ })).toBeDefined()
  })

  test('relaxed handoff warns and hands off against the final-phase limit', async ($, on) => {
    const notes: string[] = []
    const w: World = { tokens: 440_000, notes, config: { handoffMode: 'relaxed' } }
    world(on, w)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    // 440,000 of 552,500 is under warnAt's 80%: Hand off is not the one to press.
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect((await ui.find({ key: 'pane-handoff-box' }))?.props.borderColor).toBe('inactive')
    await ui.unmount()
    // Past the strict budget and warnAt, short of the limit: the warning, no note.
    w.tokens = 470_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect((await ui.find({ key: 'pane-handoff-box' }))?.props.borderColor).toBe('permission')
    await ui.unmount()
    expect(notes.filter(text => /— handoff\./.test(text))).toEqual([])
    w.tokens = 560_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes.filter(text => /— handoff\./.test(text))).toEqual([expect.stringMatching(/^dforge: budget: 560k of 553k — handoff\. /)])
  })

  test('sections picks and orders the pane', async ($, on) => {
    world(on, { tokens: 50_000, config: { sections: 'plan, repo' } })
    await $.session.start(START)
    await $.tool.call({
      tool: 'TodoWrite',
      todos: [{ content: 'Write the pane', status: 'in_progress', activeForm: 'Writing' }],
    })
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Context' })).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▸ Context' })).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▾ Usage' })).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▸ Usage' })).toBeUndefined()
    const drawn = JSON.stringify(await ui.drawn())
    expect(drawn.indexOf('"▾ Plan"')).toBeGreaterThan(-1)
    expect(drawn.indexOf('"▾ Plan"')).toBeLessThan(drawn.indexOf('feat/pane'))
    // Without the Context section the buttons still show, at the end.
    expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
  })

  test('collapsed draws a section as its title row, and its title toggles it', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: { collapsed: 'usage,context' }, written })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    // Usage keeps its title and headline and loses every row.
    expect((await ui.find({ key: 'usage-title' }))?.props).toMatchObject({ label: '▸ Usage', plain: true })
    expect(await ui.find({ type: 'Text', text: /^\$1\.50/ })).toBeDefined()
    expect(await ui.find({ key: 'limit-five_hour' })).toBeUndefined()
    // Context loses its meter but keeps its buttons.
    expect(await ui.find({ type: 'Text', text: /handoff 465k/ })).toBeUndefined()
    expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
    await ui.press({ key: 'usage-title' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ collapsed: 'context' })
    expect((await ui.find({ key: 'usage-title' }))?.props.label).toBe('▾ Usage')
    expect(await ui.find({ key: 'limit-five_hour' })).toBeDefined()
    await ui.press({ key: 'repo-title' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ collapsed: 'context,repo' })
  })

  test('a collapsed title is a bare label on a Claude Code without styled labels', async ($, on) => {
    world(on, { tokens: 284_000, config: { collapsed: 'usage,context' }, version: '2.1.292' })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    const title = await ui.find({ key: 'usage-title' })
    expect(title?.props).toMatchObject({ label: '▸ Usage', plain: true })
    expect(title?.children).toEqual([])
    expect(await ui.find({ type: 'Text', text: /^\$1\.50/ })).toBeDefined()
    expect(await ui.find({ key: 'limit-five_hour' })).toBeUndefined()
    expect((await ui.find({ key: 'context-title' }))?.children).toEqual([])
    expect(await ui.find({ type: 'Text', text: /handoff 465k/ })).toBeUndefined()
    expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
  })

  test('a collapsed title is drawn in its card color where Claude Code styles labels', async ($, on) => {
    world(on, { tokens: 284_000, config: { collapsed: 'usage,context' }, version: '2.1.295' })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect((await ui.find({ key: 'usage-title' }))?.children[0]).toMatchObject({ type: 'Text', props: { color: 'blue', bold: true }, children: ['▸ Usage'] })
    expect(await ui.find({ type: 'Text', text: /^\$1\.50/ })).toBeDefined()
    expect(await ui.find({ key: 'limit-five_hour' })).toBeUndefined()
    expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
  })

  test('breakdownRows limits the context rows', async ($, on) => {
    world(on, { tokens: 284_000, config: { breakdownRows: 1 } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Messages/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /System tools/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /compacts 604k/ })).toBeDefined()
  })

  test('a limit past the alert line never pops up', async ($, on) => {
    const toasts: string[] = []
    world(on, { tokens: 50_000, toasts })
    const high = { ...MEASURE, rateLimits: [{ kind: 'five_hour', percentUsed: 92, resetsAt: '2026-10-08T12:00:00Z' }] }
    await $.session.measure(high)
    await $.session.measure(high)
    expect(toasts).toEqual([])
  })

  test('limitAlertAt 0 stays quiet', async ($, on) => {
    const toasts: string[] = []
    world(on, { tokens: 50_000, toasts, config: { limitAlertAt: 0 } })
    await $.session.start(START)
    await $.session.measure({ ...MEASURE, rateLimits: [{ kind: 'five_hour', percentUsed: 99 }] })
    expect(toasts).toEqual([])
  })

  test('the first session opens the way the saved settings say', async ($, on) => {
    const opened: string[] = []
    world(on, { tokens: 284_000, opened, config: { layout: 'compact' } })
    await $.session.start(START)
    expect(opened).toEqual([])
  })

  test('a budget override above the schema maximum is ignored', async ($, on) => {
    world(on, { tokens: 340_000, config: {}, env: { DFORGE_BUDGET: '3000000' } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^73%$/ })).toBeDefined()
  })

  test('the pre-2.0 budget name is not read', async ($, on) => {
    world(on, { tokens: 340_000, config: {}, env: { DR_SUPERPOWERS_BUDGET: '400000' } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^73%$/ })).toBeDefined()
  })

  test('DFORGE_BUDGET sets the budget', async ($, on) => {
    world(on, { tokens: 340_000, config: {}, env: { DFORGE_BUDGET: '500000' } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^68%$/ })).toBeDefined()
  })

  test('the settings view says which saved values it ignored', async ($, on) => {
    world(on, { tokens: 284_000, config: { warnAt: 500 } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    expect(await ui.find({ type: 'Text', text: /warnAt in ~\/\.dforge\/config\.json is not valid; ignored/ })).toBeDefined()
  })

  test('every setting has a row in exactly one tab', async ($, on) => {
    world(on, { tokens: 284_000, config: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    const seen: string[] = []
    for (const tab of tabsOf(SCHEMA)) {
      await ui.press({ key: `settings-tab-${tab}` })
      for (const key of Object.keys(SCHEMA)) if ((await ui.find({ key: `set-${key}-label` })) !== undefined) seen.push(key)
    }
    expect(seen.sort()).toEqual(Object.keys(SCHEMA).sort())
  })

  const STORE_FILE = '/home/me/.claude/plugins/store/dr-cockpit_darkraise-abc123.json'
  const OLD_DFORGE = '/home/me/.dr-superpowers/config.json'
  const DARKMEM = { url: 'http://d.test', repos: {} }
  const OLD_FILES = {
    [STORE_FILE]: JSON.stringify({ notifyUrl: 'https://discord.com/api/webhooks/1/abc', notifyMention: '42' }),
    [OLD_DFORGE]: JSON.stringify({ darkmem: DARKMEM }),
  }
  /** A file system that keeps what the plugin writes, over these starting files. */
  function disk(on: On, written: Record<string, string>, files: Record<string, string>) {
    on('fs.read', (_$, e) => {
      const text = written[e.path] ?? files[e.path]
      if (text === undefined) throw new Error('ENOENT')
      return { value: text }
    })
    on('fs.exists', (_$, e) => ({ value: e.path in written || e.path in files }))
  }
  /** The plugin's store, kept in memory where the test can read it; the test's own `$` has no store noun. */
  function memory(on: On, entries: Record<string, unknown> = {}) {
    const kept = new Map(Object.entries(entries))
    on('store.get', (_$, e) => ({ value: kept.get(e.key) }))
    on('store.set', (_$, e) => {
      kept.set(e.key, e.value)
      return { value: undefined }
    })
    on('store.delete', (_$, e) => {
      kept.delete(e.key)
      return { value: undefined }
    })
    on('store.keys', () => ({ value: [...kept.keys()] }))
    return kept
  }
  const legacy = (warnAt: number) => ({ pluginConfigs: { 'dr-cockpit@darkraise': { options: { warnAt } } } })
  // world's fs.list names the store file through `files`.
  const LISTED = { [STORE_FILE]: { text: '' } }

  test('the first session imports the cockpit options and the webhook, not the pre-2.0 darkmem mapping', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, written, env: { HOME: '/home/me' }, settings: legacy(70), files: LISTED })
    disk(on, written, OLD_FILES)
    const store = memory(on)
    await $.session.start(START)
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ warnAt: 70 })
    expect(store.get('notifyUrl')).toBe('https://discord.com/api/webhooks/1/abc')
    expect(store.get('notifyMention')).toBe('42')
  })

  test('a later session imports nothing again', async ($, on) => {
    const written: Record<string, string> = {}
    const w: World = { tokens: 284_000, written, env: { HOME: '/home/me' }, settings: legacy(70), files: LISTED }
    world(on, w)
    disk(on, written, OLD_FILES)
    const store = memory(on)
    await $.session.start(START)
    w.settings = legacy(60)
    store.delete('notifyUrl')
    await $.session.start(START)
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ warnAt: 70 })
    expect(store.get('notifyUrl')).toBeUndefined()
  })

  test('a webhook already set is kept', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, written, env: { HOME: '/home/me' }, settings: legacy(70), files: LISTED })
    disk(on, written, OLD_FILES)
    const store = memory(on)
    store.set('notifyUrl', 'https://discord.com/api/webhooks/2/mine')
    await $.session.start(START)
    expect(store.get('notifyUrl')).toBe('https://discord.com/api/webhooks/2/mine')
  })

  test('the first session leaves the import to dforge-config and reads the file it made', async ($, on) => {
    const written: Record<string, string> = {}
    const runs: string[] = []
    world(on, { tokens: 284_000, written, runs, env: { HOME: '/home/me' }, settings: legacy(70), files: LISTED })
    disk(on, written, OLD_FILES)
    memory(on)
    await $.session.start(START)
    expect(runs).toEqual([expect.stringMatching(/^node .*\/scripts\/lib\/dforge-config\.mjs get --json$/)])
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ warnAt: 70 })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: /^70%\s*$/ })).toBeDefined()
  })

  test('without node the first session writes the import itself', async ($, on) => {
    const written: Record<string, string> = {}
    const runs: string[] = []
    world(on, { tokens: 284_000, written, runs, isNodeMissing: true, env: { HOME: '/home/me' }, settings: legacy(70), files: LISTED })
    disk(on, written, OLD_FILES)
    memory(on)
    await $.session.start(START)
    expect(runs).toEqual([])
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ warnAt: 70 })
  })

  test('when dforge-config fails before creating the file the first session writes the import itself', async ($, on) => {
    const written: Record<string, string> = {}
    const runs: string[] = []
    world(on, { tokens: 284_000, written, runs, isDforgeConfigRefusing: true, env: { HOME: '/home/me' }, settings: legacy(70), files: LISTED })
    disk(on, written, OLD_FILES)
    memory(on)
    await $.session.start(START)
    expect(runs[0]).toMatch(/^node .*\/scripts\/lib\/dforge-config\.mjs get --json$/)
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ warnAt: 70 })
  })

  test('a settings file dforge-config wrote first is kept, and the webhook still comes over', async ($, on) => {
    const written: Record<string, string> = { [CONFIG]: JSON.stringify({ layout: 'full' }) }
    world(on, { tokens: 284_000, written, env: { HOME: '/home/me' }, settings: legacy(70), files: LISTED })
    disk(on, written, OLD_FILES)
    const store = memory(on)
    await $.session.start(START)
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ layout: 'full' })
    expect(store.get('notifyUrl')).toBe('https://discord.com/api/webhooks/1/abc')
  })
})

describe('minimized band', () => {
  test('draws the band in the account\'s frame, with Expand on the top rule', async ($, on) => {
    const shell = { result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b7k2' }, text: 'Running in the background' }
    world(on, { ...SIGNED_IN, tools: { Bash: () => shell } })
    signedIn(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true } as never)
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Context' })).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▸ Context' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /^╭─ me@example\.com · subscription · Remote ○ not connected ─+ $/ })).toBeDefined()
    expect(await ui.find({ key: 'band-expand' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /ctx ▰+▱*┃?▱* 61%.*5h ▰+▱*┊?▱* 23%.*7d .* 61%/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /\$ 1 shell · longest 0s.*~\/code\/shop\/web ⎇ feat\/pane\* ↑2 ↓1 ~1 \?1/ })).toBeDefined()
    // No buttons beside Expand, and no commands.
    expect(await ui.find({ key: 'pane-compact' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /npm run dev/ })).toBeUndefined()
    await ui.unmount()
    const desk = await $.ui.mount({ ...INLINE, surface: 'desktop' })
    const drawn = JSON.stringify(await desk.drawn())
    // The band's head and rows are the desktop's own text, its meters one picture.
    expect((await desk.find({ key: 'band-who-0-left' }))?.text).toMatch(/^me@example\.com · subscription  Remote/)
    expect((await desk.find({ key: 'band-rest-0-left' }))?.text).toContain('$ 1 shell · longest 0s')
    expect((await desk.findAll({ type: 'Svg' })).map(one => one.props.alt)).toEqual([expect.stringContaining('5h 23%')])
    expect(drawn).not.toContain('npm run dev')
    expect(await desk.find({ key: 'band-expand' })).toBeDefined()
  })

  test('drops the frame below 48 columns, the email beside Expand', async ($, on) => {
    world(on, SIGNED_IN)
    signedIn(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...INLINE, props: { ...INLINE.props, bodyColumns: 40 }, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /╭/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: 'me@example.com' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^ctx 61% ≈?.*· 5h 23%.*· 7d 61%/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /shop\/web ⎇ feat\/pane\*/ })).toBeDefined()
  })

  test('says what is blocked or refused on a line of its own', async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.tool.call({ tool: 'Bash', command: 'git commit -m "x" -m "Co-Authored-By: Claude <noreply@anthropic.com>"' })
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /✗ 1 refused/ })).toBeDefined()
  })

  test('draws below the prompt on the terminal, the hint set into its bottom rule', async ($, on) => {
    world(on, SIGNED_IN)
    signedIn(on, configured({ layout: 'compact' }))
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure(MEASURE)
    const above = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await above.find({ key: 'band-expand' })).toBeUndefined()
    await above.unmount()
    const box = await $.ui.mount(minimized('terminal'))
    expect(await box.find({ key: 'band-expand' })).toBeDefined()
    expect(await box.find({ type: 'Text', text: /^╭─ me@example\.com/ })).toBeDefined()
    expect(await box.find({ type: 'Text', text: /^╰─ \? for shortcuts ─+╯$/ })).toBeDefined()
    const rows = (await box.findAll({ type: 'Text' })).map(one => one.text).filter(text => /^[│╰].*[│╯]$/.test(text))
    expect(rows.length).toBeGreaterThan(2)
    for (const row of rows) expect([...row].length).toBe(120 - 2 - MODE_LABEL_RESERVE)
  })

  test('stays above the prompt on a terminal older than the box below it', async ($, on) => {
    world(on, { ...SIGNED_IN, version: '2.1.303' })
    signedIn(on, configured({ layout: 'compact' }))
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure(MEASURE)
    const above = await $.ui.mount({ ...BAND, surface: 'terminal', viewport: { columns: 120, rows: 40, isFullscreen: false } })
    expect(await above.find({ key: 'band-expand' })).toBeDefined()
    await above.unmount()
    const hint = await $.ui.mount(minimized('terminal'))
    expect(await hint.find({ key: 'band-expand' })).toBeUndefined()
    expect(await hint.find({ type: 'Text', text: /me@example\.com/ })).toBeUndefined()
  })

  test('takes unframed lines below the prompt when no width is reported', async ($, on) => {
    world(on, SIGNED_IN)
    signedIn(on, configured({ layout: 'compact' }))
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const box = await $.ui.mount({ ...HINT, surface: 'terminal' })
    expect(await box.find({ type: 'Text', text: /╭/ })).toBeUndefined()
    expect(await box.find({ type: 'Text', text: 'me@example.com' })).toBeDefined()
    expect(await box.find({ type: 'Text', text: '? for shortcuts' })).toBeDefined()
  })

  test('leads its second line with ◐ while background work runs', async ($, on) => {
    const shell = { result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b7k2' }, text: 'Running in the background' }
    world(on, { ...SIGNED_IN, tools: { Bash: () => shell } })
    signedIn(on, configured({ layout: 'compact' }))
    await $.session.start(START)
    await $.turn.start({ text: 'go', turnId: 't1' })
    await $.tool.call({ tool: 'Bash', command: 'npm test', run_in_background: true } as never)
    await $.turn.complete({ answer: 'ok', durationMs: 1_000, isAborted: false, turnId: 't1', reason: 'answer' })
    const box = await $.ui.mount(minimized('terminal'))
    expect(await box.find({ type: 'Text', text: /^│ ◐ \$ 1 shell/ })).toBeDefined()
  })

  test('is used docked too when minimized', async ($, on) => {
    world(on, { tokens: 284_000, config: { layout: 'compact' } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Context' })).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▸ Context' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /ctx ▰+▱*┃?▱* 61%/ })).toBeDefined()
  })

  for (const surface of SURFACES) {
    test(`Minimize closes the pane and saves the layout on ${surface}`, async ($, on) => {
      const written: Record<string, string> = {}
      const closed: string[] = []
      const openedRows: (number | undefined)[] = []
      world(on, { tokens: 284_000, closed, written, openedRows, config: {} })
      await $.session.start(START)
      await $.tool.call({ tool: 'Bash', command: 'ls' })
      const full = await $.ui.mount({ ...PANE, surface })
      await full.press({ key: 'pane-minimize' })
      expect(closed).toEqual(['dforge'])
      expect(JSON.parse(written[CONFIG] ?? '{}').layout).toBe('compact')
      await full.unmount()
      const inline = await $.ui.mount({ ...INLINE, surface })
      expect(await inline.find({ key: 'pane-minimize' })).toBeUndefined()
      openedRows.length = 0
      await inline.press({ key: 'band-expand' })
      expect(JSON.parse(written[CONFIG] ?? '{}').layout).toBe('full')
      // Saving does not reload the mod, so the pane opened for the band's rows is asked for the full one.
      expect(openedRows).toEqual([undefined])
    })

    test(`draws the minimized band on ${surface}`, async ($, on) => {
      world(on, SIGNED_IN)
      signedIn(on, configured({ layout: 'compact' }))
      await $.session.start(START)
      await $.tool.call({ tool: 'Bash', command: 'ls' })
      await $.session.measure(MEASURE)
      const band = await $.ui.mount(minimized(surface))
      expect(await band.find({ key: 'band-expand' })).toBeDefined()
      const drawn = JSON.stringify(await band.drawn())
      expect(drawn).toContain('me@example.com')
      expect(drawn).toContain('5h')
    })

    test(`Expand on the minimized band opens the pane on ${surface}`, async ($, on) => {
      const written: Record<string, string> = {}
      const opened: string[] = []
      world(on, { tokens: 284_000, opened, written, config: { layout: 'compact' } })
      await $.session.start(START)
      await $.tool.call({ tool: 'Bash', command: 'ls' })
      // Left on the settings view, as closing the settings pane by hand leaves it.
      await $.command.run({ ...COCKPIT, args: 'settings' })
      opened.length = 0
      const docking = await $.ui.mount(minimized(surface, { columns: 160, rows: 50, isFullscreen: true }))
      await docking.press({ key: 'band-expand' })
      expect(opened).toEqual(['dforge'])
      // auto is the default, so saving it drops the key.
      expect(JSON.parse(written[CONFIG] ?? '{"layout":"unwritten"}').layout).toBeUndefined()
      await docking.unmount()
      const pane = await $.ui.mount({ ...PANE, surface })
      expect(await pane.find({ type: 'Text', text: 'Settings' })).toBeUndefined()
      await pane.unmount()
      // Minimized again for the next session, which reads the file afresh.
      written[CONFIG] = JSON.stringify({ layout: 'compact' })
      await $.session.start(START)
      const main = await $.ui.mount(minimized(surface, { columns: 100, rows: 50, isFullscreen: false }))
      await main.press({ key: 'band-expand' })
      expect(JSON.parse(written[CONFIG] ?? '{}').layout).toBe('full')
    })

    test(`draws nothing above the prompt while expanded on ${surface}`, async ($, on) => {
      world(on, { tokens: 284_000 })
      await $.tool.call({ tool: 'Bash', command: 'ls' })
      const band = await $.ui.mount({ ...BAND, surface })
      expect(await band.find({ key: 'band-expand' })).toBeUndefined()
    })
  }

  test('leaves the slot above the prompt to a survey', async ($, on) => {
    world(on, { tokens: 284_000, config: { layout: 'compact' } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const band = await $.ui.mount({ ...BAND, props: { ...BAND.props, hasSurvey: true }, surface: 'desktop' })
    expect(await band.find({ key: 'band-expand' })).toBeUndefined()
  })

  test('offers no Minimize where no band is drawn above the prompt', async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...PANE, surface: 'mobile' })
    expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
    expect(await ui.find({ key: 'pane-minimize' })).toBeUndefined()
  })

  test('a minimized session opens no pane and closes one left up', async ($, on) => {
    const opened: string[] = []
    const closed: string[] = []
    world(on, { tokens: 284_000, opened, closed, config: { layout: 'compact' } })
    await $.session.start(START)
    await $.session.attach({ surface: 'desktop', clientId: 'desktop:default' } as never)
    expect(opened).toEqual([])
    expect(closed).toEqual(['dforge'])
  })

  // Saving a setting writes the file and updates the settings atom.
  test('a setting saved from a minimized cockpit keeps its settings open', async ($, on) => {
    const closed: string[] = []
    world(on, { tokens: 284_000, closed, config: { layout: 'compact' } })
    await $.command.run({ ...COCKPIT, args: 'settings' })
    await $.session.start(START)
    expect(closed).toEqual([])
  })

  test('a minimized session with no pane up closes nothing', async ($, on) => {
    const opened: string[] = []
    const closed: string[] = []
    world(on, { tokens: 284_000, opened, closed, isPaneShut: true, config: { layout: 'compact' } })
    await $.session.start(START)
    await $.session.attach({ surface: 'desktop', clientId: 'desktop:default' } as never)
    expect(opened).toEqual([])
    expect(closed).toEqual([])
  })

  test('keeps the repo reading fresh while minimized', async ($, on) => {
    world(on, { ...SIGNED_IN, isPaneShut: true })
    signedIn(on, configured({ layout: 'compact' }))
    await $.session.start(START)
    await $.session.measure(MEASURE)
    const band = await $.ui.mount(minimized('terminal'))
    expect(await band.find({ type: 'Text', text: /⎇ feat\/pane\*/ })).toBeDefined()
  })

  test('/cockpit expands a minimized cockpit', async ($, on) => {
    const written: Record<string, string> = {}
    const opened: string[] = []
    world(on, { tokens: 284_000, opened, written, config: { layout: 'compact' } })
    await $.session.start(START)
    opened.length = 0
    await $.command.run(COCKPIT)
    expect(opened).toEqual(['dforge'])
    // auto is the default, so saving it leaves an object without the key.
    expect(JSON.parse(written[CONFIG] ?? '{"layout":"unwritten"}')).toEqual({})
  })

  for (const [layout, want] of [
    ['compact', ['dforge']],
    ['auto', []],
  ] as const) {
    test(`Back from the settings ${want.length > 0 ? 'closes the pane' : 'keeps the pane'} with layout ${layout}`, async ($, on) => {
      const closed: string[] = []
      world(on, { tokens: 284_000, closed, config: { layout } })
      await $.session.start(START)
      closed.length = 0
      await $.command.run({ ...COCKPIT, args: 'settings' })
      const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
      await ui.press({ key: 'settings-back' })
      expect(closed).toEqual([...want])
    })
  }

  test('full keeps the sections above the prompt', async ($, on) => {
    world(on, { tokens: 284_000, config: { layout: 'full' } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Context' })).toBeDefined()
  })

  test('an unknown layout reads as auto', async ($, on) => {
    world(on, { tokens: 284_000, config: { layout: 'tiles' } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const docked = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await docked.find({ type: 'Button', text: '▾ Context' })).toBeDefined()
    await docked.unmount()
    const inline = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await inline.find({ type: 'Button', text: '▾ Context' })).toBeUndefined()
    expect(await inline.find({ type: 'Button', text: '▸ Context' })).toBeUndefined()
  })
})

describe('repo card', () => {
  test('keeps the last reading when git status outruns its timeout, not when git is gone', async ($, on) => {
    const w: World = { ...SIGNED_IN }
    const clock = world(on, w)
    signedIn(on)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    const isShown = async () => JSON.stringify(await ui.drawn()).includes('feat/pane')
    await clock.advance(12_000)
    expect(await isShown()).toBe(true)
    w.gitStatusOut = 'timeout'
    await clock.advance(12_000)
    expect(await isShown()).toBe(true)
    w.gitStatusOut = 'missing'
    await clock.advance(12_000)
    expect(await isShown()).toBe(false)
  })
})

describe('dense pane', () => {
  const SHELL = { result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b7k2' }, text: 'Running in the background' }

  test('draws one line per shown section, and Detailed switches back', async ($, on) => {
    const written: Record<string, string> = {}
    const files = configured({ density: 'dense', sections: 'context,usage,shells,agents,repo' })
    world(on, { ...SIGNED_IN, written, files, tools: { Bash: () => SHELL } })
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true } as never)
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Context' })).toBeUndefined()
    expect((await ui.find({ key: 'dense-context' }))?.text).toMatch(/^ctx  ▰+▱* 61% 284k\/465k/)
    expect((await ui.find({ key: 'dense-usage' }))?.text).toMatch(/^lim  5h ▰+▱* 23% · 7d ▰+▱* 61%$/)
    expect((await ui.find({ key: 'dense-shells' }))?.text).toBe('$    1 shell · npm run dev · 0s')
    expect(await ui.find({ key: 'dense-agents' })).toBeUndefined()
    expect((await ui.find({ key: 'dense-repo' }))?.text).toBe('⎇    feat/pane ↑2 ↓1 · ~1 changed · ?1')
    expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
    await ui.press({ key: 'pane-density' })
    expect(JSON.parse(written[CONFIG] ?? '{}').density).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▾ Context' })).toBeDefined()
  })

  test('Dense saves the setting', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, written, config: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-density' })
    expect(JSON.parse(written[CONFIG] ?? '{}').density).toBe('dense')
    expect(await ui.find({ key: 'dense-context' })).toBeDefined()
  })

  test('saves through dforge-config, under the lock every writer of the file takes', async ($, on) => {
    const written: Record<string, string> = {}
    const runs: string[] = []
    world(on, { tokens: 284_000, written, runs, config: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-density' })
    expect(runs.filter(run => run.includes(' set '))).toEqual([expect.stringMatching(/^node .*\/scripts\/lib\/dforge-config\.mjs set density dense$/)])
    expect(JSON.parse(written[CONFIG] ?? '{}').density).toBe('dense')
    expect(await ui.find({ key: 'dense-context' })).toBeDefined()
  })

  test('without node a save writes the settings file itself', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, written, config: {}, isNodeMissing: true })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-density' })
    expect(JSON.parse(written[CONFIG] ?? '{}').density).toBe('dense')
    expect(await ui.find({ key: 'dense-context' })).toBeDefined()
  })

  test('draws the same rows as text on the desktop', async ($, on) => {
    world(on, SIGNED_IN)
    signedIn(on, configured({ density: 'dense' }))
    await $.session.start(START)
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
    expect(await ui.find({ key: 'dense-context' })).toBeDefined()
    expect(await ui.findAll({ type: 'Svg' })).toEqual([])
    expect(await ui.find({ key: 'pane-minimize' })).toBeDefined()
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

  test('answers an unknown argument with its usage and opens nothing', async ($, on) => {
    const opened: string[] = []
    world(on, { tokens: 284_000, opened })
    const answer = await $.command.run({ ...COCKPIT, args: 'bogus' })
    expect(answer.text).toBe('Unknown argument "bogus". Usage: /cockpit [settings | notify test | notify url <url> | notify mention <id>]')
    expect(opened).toEqual([])
  })
})

describe('buttons', () => {
  test('wear a rounded box, the accent on the one that matters', async ($, on) => {
    const w: World = { ...SIGNED_IN, tokens: 200_000 }
    world(on, w)
    signedIn(on, configured({ handoffTokens: 400_000 }))
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
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
    // A section's title is drawn in its card's color.
    expect((await ui.find({ key: 'context-title' }))?.children[0]).toMatchObject({ type: 'Text', props: { color: 'cyan', bold: true }, children: ['▾ Context'] })
    // The hotkey rides on a hidden twin that presses the same thing.
    expect((await ui.find({ key: 'pane-settings-hotkey-box' }))?.props.display).toBe('none')
    expect((await ui.find({ key: 'pane-settings-hotkey' }))?.props.hotkey).toBe('s')
    await ui.press({ key: 'pane-settings-hotkey' })
    // The settings controls are single-line buttons, the hotkey on the button itself.
    expect((await ui.find({ key: 'settings-back' }))?.props).toMatchObject({ label: 'Back', hotkey: 'b' })
    expect(await ui.find({ key: 'settings-back-box' })).toBeUndefined()
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
    expect((await ui.find({ key: 'set-layout-auto' }))?.props).toMatchObject({ variant: 'primary' })
    expect((await ui.find({ key: 'set-layout-auto' }))?.props.dimColor).not.toBe(true)
    expect(await ui.find({ key: 'set-layout-auto-box' })).toBeUndefined()
    expect((await ui.find({ key: 'set-layout-full' }))?.props.dimColor).toBe(true)
    expect((await ui.find({ key: 'set-openAtStart-toggle' }))?.props.label).toBe('● On')
    await ui.press({ key: 'settings-tab-Notifications' })
    expect((await ui.find({ key: 'set-notify-kind-task' }))?.props).toMatchObject({ label: '○ task', dimColor: true })
    expect((await ui.find({ key: 'settings-back' }))?.props.hotkey).toBe('b')
  })
})

describe('settings view', () => {
  test('toggles sections without losing the order or the last one', () => {
    expect(sectionsToggled(['account', 'context', 'usage', 'shells', 'agents', 'plan', 'repo', 'guard'], 'repo')).toBe('account,context,usage,shells,agents,plan,guard')
    expect(sectionsToggled(['plan', 'context'], 'usage')).toBe('plan,context,usage')
    expect(sectionsToggled(['account', 'context', 'usage', 'shells', 'agents', 'plan', 'repo'], 'guard')).toBe('')
    expect(sectionsToggled(['plan'], 'plan')).toBe('plan')
  })

  test('collapses sections in their own order, each once', () => {
    expect(collapsedFrom('repo, usage, nope, usage')).toEqual(['usage', 'repo'])
    expect(collapsedFrom('')).toEqual([])
    expect(collapsedToggled(['usage', 'repo'], 'context')).toBe('context,usage,repo')
    expect(collapsedToggled(['usage', 'repo'], 'usage')).toBe('repo')
    expect(collapsedToggled(['usage'], 'usage')).toBe('')
  })

  test('the Collapsed chips save the collapsed setting', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: {}, written })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    expect((await ui.find({ key: 'set-collapsed-usage' }))?.props).toMatchObject({ label: '○ usage', dimColor: true })
    await ui.press({ key: 'set-collapsed-usage' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ collapsed: 'usage' })
    expect((await ui.find({ key: 'set-collapsed-usage' }))?.props.label).toBe('✓ usage')
  })

  test('/cockpit settings opens the settings', async ($, on) => {
    world(on, { tokens: 284_000 })
    await $.command.run({ ...COCKPIT, args: 'settings' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Settings' })).toBeDefined()
    expect(await ui.find({ type: 'Button', key: 'set-openAtStart-toggle' })).toBeDefined()
  })

  for (const surface of SURFACES) {
    test(`writes each press to the settings file on ${surface}`, async ($, on) => {
      const written: Record<string, string> = {}
      world(on, { tokens: 284_000, config: { openAtStart: false }, written })
      await $.session.start(START)
      await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 'turn-0', reason: 'answer' })
      const ui = await $.ui.mount({ ...PANE, surface })
      await ui.press({ key: 'pane-settings' })
      if (surface === 'desktop') {
        await ui.select({ key: 'set-openAtStart-select', value: 'true' })
        await ui.select({ key: 'set-layout-select', value: 'compact' })
      } else {
        await ui.press({ key: 'set-openAtStart-toggle' })
        await ui.press({ key: 'set-layout-compact' })
      }
      await ui.press({ key: 'set-section-guard' })
      await ui.press({ key: 'settings-tab-Context' })
      await ui.press({ key: 'set-warnAt-more' })
      expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({
        warnAt: 85,
        layout: 'compact',
        sections: 'account,context,usage,shells,agents,plan,repo',
      })
      await ui.press({ key: 'settings-back' })
      // The layout saved above is compact, so Back returns to the band.
      expect(await ui.find({ key: 'band-expand' })).toBeDefined()
    })
  }

  test('says when a setting is refused', async ($, on) => {
    const toasts: string[] = []
    world(on, { tokens: 284_000, toasts, config: {}, isReadOnly: true })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'set-guardAttribution-toggle' })
    expect(toasts.some(text => text.startsWith('dforge: guardAttribution not saved:'))).toBe(true)
  })

  test('a settings file that is not JSON is left alone', async ($, on) => {
    const toasts: string[] = []
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, toasts, written, env: { HOME: '/home/me' } })
    on('fs.read', (_$, e) => (e.path === CONFIG ? { value: 'not json' } : Promise.reject(new Error('ENOENT'))))
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'set-guardAttribution-toggle' })
    expect(written[CONFIG]).toBeUndefined()
    expect(toasts.some(text => text.startsWith('dforge: guardAttribution not saved:'))).toBe(true)
  })

  test('shows one group at a time and switches with the tabs', async ($, on) => {
    world(on, { tokens: 284_000, config: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    expect(await ui.find({ key: 'set-openAtStart-toggle' })).toBeDefined()
    expect(await ui.find({ key: 'set-warnAt-more' })).toBeUndefined()
    expect((await ui.find({ key: 'settings-tab-Cockpit' }))?.props).toMatchObject({ variant: 'primary', hotkey: '1' })
    expect(await ui.find({ type: 'Text', text: 'all defaults' })).toBeDefined()
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ key: 'set-warnAt-more' })).toBeDefined()
    expect(await ui.find({ key: 'set-openAtStart-toggle' })).toBeUndefined()
    expect((await ui.find({ key: 'settings-tab-Context' }))?.props).toMatchObject({ variant: 'primary', hotkey: '2' })
  })

  test('describes each setting until help is hidden', async ($, on) => {
    world(on, { tokens: 284_000, config: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    expect(await ui.find({ type: 'Text', text: /^Open the cockpit when a session starts\./ })).toBeDefined()
    await ui.press({ key: 'settings-help' })
    expect(await ui.find({ type: 'Text', text: /^Open the cockpit when a session starts\./ })).toBeUndefined()
    expect((await ui.find({ key: 'settings-help' }))?.props).toMatchObject({ label: 'Show help', hotkey: 'i' })
  })

  test('a changed row shows its default and resets', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: { warnAt: 70 }, written })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: '1 changed' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'default 80%' })).toBeDefined()
    await ui.press({ key: 'set-warnAt-reset' })
    expect(JSON.parse(written[CONFIG] ?? 'null')).toEqual({})
    expect(await ui.find({ key: 'set-warnAt-reset' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: 'all defaults' })).toBeDefined()
  })

  test('a typed number is saved, and one out of range is refused', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: {}, written })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    await ui.press({ key: 'set-warnAt-edit' })
    // The field starts empty, so what is typed replaces the value instead of following it.
    const field = await ui.find({ key: 'set-warnAt-input' })
    expect(field?.props.value).toBeUndefined()
    expect(field?.props.placeholder).toBe('80')
    await ui.input({ key: 'set-warnAt-input', text: '500', kind: 'submit' })
    expect(await ui.find({ type: 'Text', text: /Enter a whole number from 1 to 99/ })).toBeDefined()
    expect(written[CONFIG]).toBeUndefined()
    await ui.input({ key: 'set-warnAt-input', text: '65', kind: 'submit' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ warnAt: 65 })
    expect(await ui.find({ key: 'set-warnAt-input' })).toBeUndefined()
  })

  test('the desktop draws dropdowns and open fields, and a refused entry below its field', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: {}, written })
    await $.session.start(START)
    const desk = await $.ui.mount({ ...PANE, surface: 'desktop' })
    await desk.press({ key: 'pane-settings' })
    expect((await desk.find({ key: 'set-openAtStart-select' }))?.props).toMatchObject({ value: 'true', options: [{ value: 'true', label: 'On' }, { value: 'false', label: 'Off' }] })
    expect((await desk.find({ key: 'set-layout-select' }))?.props).toMatchObject({ value: 'auto', options: [{ value: 'auto' }, { value: 'full' }, { value: 'compact' }] })
    expect(await desk.find({ key: 'set-layout-full' })).toBeUndefined()
    // Wrapping rows are spaced by the desktop's own steps both ways.
    expect((await desk.find({ key: 'settings-tabs' }))?.props).toMatchObject({ columnGap: 'sm', rowGap: 'sm' })
    expect((await desk.find({ key: 'set-section' }))?.props).toMatchObject({ columnGap: 'xs', rowGap: 'xs' })
    expect((await desk.find({ key: 'set-section' }))?.props.paddingLeft).toBeUndefined()
    await desk.select({ key: 'set-openAtStart-select', value: 'false' })
    await desk.select({ key: 'set-layout-select', value: 'full' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ openAtStart: false, layout: 'full' })
    await desk.press({ key: 'settings-tab-Context' })
    expect((await desk.find({ key: 'set-warnAt-input' }))?.props).toMatchObject({ label: 'Warn at', value: '80' })
    expect(await desk.find({ key: 'set-warnAt-edit' })).toBeUndefined()
    await desk.input({ key: 'set-warnAt-input', text: '500' })
    const block = JSON.stringify(await desk.find({ key: 'set-warnAt-block' }))
    expect(block).toContain('✗ Enter a whole number from 1 to 99')
    expect(block.indexOf('"set-warnAt-error"')).toBeGreaterThan(block.indexOf('"set-warnAt-input"'))
    await desk.input({ key: 'set-warnAt-input', text: '65' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ openAtStart: false, layout: 'full', warnAt: 65 })
    expect(await desk.find({ key: 'set-warnAt-error' })).toBeUndefined()
    await desk.unmount()
    const term = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await term.find({ type: 'Select' })).toBeUndefined()
    expect(await term.find({ key: 'set-warnAt-edit' })).toBeDefined()
  })

  test('the desktop draws a locked row as text and a custom row with its mark and default', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: { sections: 'plan,repo', handoffTokens: 300_000 }, written, env: { DFORGE_BUDGET: '465000' } })
    await $.session.start(START)
    const desk = await $.ui.mount({ ...PANE, surface: 'desktop' })
    await desk.press({ key: 'pane-settings' })
    // Sections is the pane's own chips: no dropdown or field, but the mark and the default still show.
    expect((await desk.find({ key: 'set-sections' }))?.props).toMatchObject({ flexDirection: 'row', columnGap: 'sm' })
    expect(await desk.find({ key: 'set-section-usage' })).toBeDefined()
    expect(await desk.find({ key: 'set-sections-controls' })).toBeUndefined()
    expect(await desk.find({ key: 'set-sections-input' })).toBeUndefined()
    expect(await desk.find({ key: 'set-sections-mark' })).toBeDefined()
    expect((await desk.find({ key: 'set-sections-default' }))?.text).toBe('changed from the defaultReset')
    await desk.press({ key: 'set-section-usage' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ sections: 'plan,repo,usage', handoffTokens: 300_000 })
    await desk.press({ key: 'settings-tab-Context' })
    // The budget is forced by the environment: its value and the reason, nothing to change.
    expect((await desk.find({ key: 'set-handoffTokens-controls' }))?.text).toBe('465k set by DFORGE_BUDGET')
    expect(await desk.find({ key: 'set-handoffTokens-input' })).toBeUndefined()
    expect(await desk.find({ key: 'set-handoffTokens-less' })).toBeUndefined()
    expect(await desk.find({ key: 'set-handoffTokens-mark' })).toBeUndefined()
    expect(await desk.find({ key: 'set-handoffTokens-default' })).toBeUndefined()
    expect(await desk.find({ key: 'set-warnAt-input' })).toBeDefined()
  })

  test('every variable the schema names locks its row', async ($, on) => {
    const named = Object.entries(SCHEMA).filter(([, spec]) => spec.env !== undefined)
    world(on, { tokens: 284_000, config: { lensCap: 3 }, env: Object.fromEntries(named.map(([, spec]) => [spec.env, String(spec.max)])) })
    await $.session.start(START)
    const desk = await $.ui.mount({ ...PANE, surface: 'desktop' })
    await desk.press({ key: 'pane-settings' })
    for (const [key, spec] of named) {
      await desk.press({ key: `settings-tab-${spec.group}` })
      expect((await desk.find({ key: `set-${key}-controls` }))?.text).toMatch(new RegExp(` set by ${spec.env}$`))
    }
  })

  test('the desktop draws a free-text row as an open field alone', () => {
    const TABLE = { Box: 'Box', Text: 'Text', Button: 'Button', Input: 'Input', Select: 'Select' } as never
    const spec = { type: 'string', default: '', group: 'Cockpit', target: 'dforge', label: 'Note', title: 'A note', description: 'Free text.' } as never
    const model = { tabs: ['Cockpit'], tab: 'Cockpit', hint: null, rows: [rowOf('note', spec, 'hello')], isHelpShown: false, editing: null, error: null, isConfirmingReset: false, canType: true, isDesktop: true, problems: [], custom: {}, top: null }
    const found: { props: Record<string, unknown> }[] = []
    const walk = (node: unknown) => {
      if (Array.isArray(node)) node.forEach(walk)
      else if (node !== null && typeof node === 'object') {
        const one = node as { props?: Record<string, unknown>; children?: unknown }
        if (typeof one.props?.key === 'string') found.push(one as { props: Record<string, unknown> })
        walk(one.children)
      }
    }
    const act = Object.fromEntries(['openTab', 'set', 'step', 'edit', 'submit', 'reset', 'toggleHelp', 'askResetGroup', 'resetGroup', 'cancelReset', 'back'].map(name => [name, () => undefined])) as never
    walk(drawSettings(TABLE, model, act))
    const keys = found.map(one => one.props.key)
    expect(found.find(one => one.props.key === 'set-note-input')).toMatchObject({ props: { label: 'Note', value: 'hello', submitLabel: 'save' } })
    expect(keys.filter(key => /^set-note-(select|edit|less|more)/.test(String(key)))).toEqual([])
  })

  test('a group resets only after a second press', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: { warnAt: 70, nudgeModel: false, layout: 'full' }, written })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    await ui.press({ key: 'settings-reset' })
    expect(written[CONFIG]).toBeUndefined()
    await ui.press({ key: 'settings-reset-cancel' })
    expect(await ui.find({ key: 'settings-reset-confirm' })).toBeUndefined()
    await ui.press({ key: 'settings-reset' })
    await ui.press({ key: 'settings-reset-confirm' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ layout: 'full' })
    expect(await ui.find({ key: 'settings-reset' })).toBeUndefined()
  })

  test('a changed chip list is marked, and any other press or a reopening ends a pending reset', async ($, on) => {
    world(on, { tokens: 284_000, config: { sections: 'plan,repo' }, written: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    expect(await ui.find({ key: 'set-sections-mark' })).toBeDefined()
    expect(await ui.find({ key: 'set-layout-mark' })).toBeUndefined()
    await ui.press({ key: 'settings-reset' })
    expect(await ui.find({ key: 'settings-reset-confirm' })).toBeDefined()
    await ui.press({ key: 'set-section-usage' })
    expect(await ui.find({ key: 'settings-reset-confirm' })).toBeUndefined()
    await ui.press({ key: 'settings-reset' })
    await $.command.run({ ...COCKPIT, args: 'settings' })
    expect(await ui.find({ key: 'settings-reset-confirm' })).toBeUndefined()
    expect(await ui.find({ key: 'settings-reset' })).toBeDefined()
  })
})

describe('desktop', () => {
  test('draws meters, a trend, a stack, run segments and a badge as SVG', () => {
    expect(paint('cyan')).toBe('#1fa8c9')
    expect(paint('#ff8700')).toBe('#ff8700')
    expect(paint('promptBorder')).toBe('#8a8a99')
    expect(svgWidth(10)).toBe(120)
    expect(svgWidth(56)).toBe(420)
    const meter = meterSvg(0.25, 200, 'success', [{ at: 0.5 }, { at: 0.75, isDashed: true }])
    expect(meter).toStartWith('<svg xmlns="http://www.w3.org/2000/svg" width="200" height="12"')
    expect(meter).toContain('width="50" height="8" rx="4" fill="#3fb36b"')
    expect(meter).toContain('<line x1="100"')
    expect(meter).toContain('stroke-dasharray="2 2"')
    expect(meterSvg(0, 200, 'red')).not.toContain('#e5534b')
    expect(trendSvg([1], 100, 'cyan')).not.toContain('<path')
    expect(trendSvg([1, 3, 2], 100, 'cyan')).toContain('<circle cx="96"')
    expect(stackSvg([3, 1], ['cyan', 'magenta'], 100)).toContain('<rect x="75" y="0" width="25" height="10" fill="#c056d6"/>')
    const segments = segmentsSvg(['done', 'active', 'todo', 'blocked'], 100)
    expect(segments.match(/<rect /g)).toHaveLength(4)
    expect(segments).toContain('#4f7cff')
    expect(segments).toContain('#e5534b')
    expect(avatarSvg('<me>', undefined)).toContain('>&#60;</text>')
    const named = labelledMeterSvg(0.4, 300, 'cyan', [{ at: 0.6 }], [
      { at: 0, text: '412k / 1.0M' },
      { at: 0.6, text: 'handoff 604k' },
      { at: 0.62, text: 'compacts 620k' },
    ])
    expect(named).toContain('text-anchor="start"')
    expect(named).toContain('>handoff 604k</text>')
    expect(named).not.toContain('compacts 620k')
    // A label that would overlap its neighbour slides clear instead.
    const slid = labelledMeterSvg(0.44, 300, 'cyan', [{ at: 0.72 }], [
      { at: 0, text: '284k / 650k' },
      { at: 0.92, text: 'compacts 600k' },
      { at: 0.72, text: 'handoff 465k' },
    ])
    expect(slid).toContain('>handoff 465k</text>')
    expect(slid).toContain('>compacts 600k</text>')
    expect(slid.indexOf('handoff')).toBeGreaterThan(slid.indexOf('compacts'))
    expect(trendSvg([1, 3], 100, 'cyan', 40, { top: '+2k', bottom: '2 turns' })).toContain('>+2k</text>')
    const dial = gaugeSvg(0.5, 'warning', 100, '50%', 0.25)
    expect(dial).toContain('fill="#d4a017">50%</text>')
    expect(dial.match(/<path /g)).toHaveLength(2)
    expect(dial).toContain('<line ')
    expect(gaugeSvg(0, 'success', 100, '0%').match(/<path /g)).toHaveLength(1)
    const row = gaugeTileSvg({ dial: gaugeSvg(0.5, 'warning', 100, '50%', null, true), key: 'Context', notes: [[{ text: 'of handoff' }]] }, 140)
    expect(row).toContain('class="fg">50%</text>')
    expect(row).toContain('>CONTEXT</text>')
    const seat = seatSvg(0.5, 0.8, 200, 'magenta')
    expect(seat).toContain('fill-opacity="0.45"')
    expect(seat).not.toContain('<text')
  })

  test('draws the cards with vectors and native buttons on desktop alone', async ($, on) => {
    const w: World = { tokens: 100_000, env: { HOME: '/home/me' }, files: { '/home/me/.claude.json': { text: '{"oauthAccount":{"emailAddress":"me@example.com"}}' } } }
    world(on, w)
    await $.session.start(START)
    await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 'turn-0', reason: 'answer' })
    w.tokens = 160_000
    await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 'turn-1', reason: 'answer' })
    await $.session.measure(MEASURE)
    const desk = await $.ui.mount({ ...PANE, surface: 'desktop' })
    const drawn = JSON.stringify(await desk.drawn())
    // Each panel and the gauges are one drawing, saying in its alt what it shows.
    expect(drawn).toContain('160k of 650k tokens, handoff at 465k')
    expect(drawn).toContain('Context over the last 2 readings, +60k on the last')
    expect(drawn).toContain('5h limit 23% used')
    expect(drawn).toContain('34% of the handoff budget')
    // The flight deck: the account first, then the activity, then the gauges.
    expect(drawn.indexOf('"key":"account"')).toBeGreaterThan(-1)
    expect(drawn.indexOf('"key":"account"')).toBeLessThan(drawn.indexOf('"key":"gauges"'))
    expect(drawn.indexOf('"key":"gauges"')).toBeLessThan(drawn.indexOf('"key":"context"'))
    expect(drawn).toContain('handoff 465k')
    expect(await desk.find({ type: 'Text', text: /trend/ })).toBeUndefined()
    expect(await desk.find({ type: 'Text', text: '▁█' })).toBeUndefined()
    expect(await desk.find({ key: 'pane-compact' })).toBeDefined()
    expect(await desk.find({ key: 'pane-compact-box' })).toBeUndefined()
    await desk.unmount()
    const term = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await term.find({ type: 'Svg' })).toBeUndefined()
    expect(await term.find({ key: 'pane-compact-box' })).toBeDefined()
  })

  test('a collapsed panel draws its title and headline alone, and its title toggles it', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: { collapsed: 'usage,context' }, written })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
    expect((await ui.find({ key: 'usage-title' }))?.props.label).toBe('▸ Usage')
    expect((await ui.find({ key: 'usage-headline' }))?.text).toMatch(/^\$1\.50/)
    expect(await ui.find({ key: 'usage-line-0' })).toBeUndefined()
    // A collapsed Context keeps its buttons and drops its meter.
    const meterAlt = async () => (await ui.findAll({ type: 'Svg' })).map(one => one.props.alt).filter(alt => alt === '284k of 650k tokens, handoff at 465k')
    expect(await meterAlt()).toEqual([])
    expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
    await ui.press({ key: 'context-title' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ collapsed: 'usage' })
    expect((await ui.find({ key: 'context-title' }))?.props.label).toBe('▾ Context')
    expect(await meterAlt()).toHaveLength(1)
    // Repo's rows go with its title and come back with it.
    expect(await ui.find({ key: 'repo-line-0' })).toBeDefined()
    await ui.press({ key: 'repo-title' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ collapsed: 'usage,repo' })
    expect(await ui.find({ key: 'repo-line-0' })).toBeUndefined()
    expect(await ui.find({ key: 'repo-headline' })).toBeDefined()
    await ui.press({ key: 'repo-title' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ collapsed: 'usage' })
    expect(await ui.find({ key: 'repo-line-0' })).toBeDefined()
  })

  test('opens the pane when the desktop joins', async ($, on) => {
    const opened: string[] = []
    world(on, { tokens: 100_000, opened, isPaneShut: true })
    await $.session.attach({ surface: 'mobile', clientId: 'mobile:default' } as never)
    expect(opened).toEqual([])
    await $.session.attach({ surface: 'desktop', clientId: 'desktop:default' } as never)
    expect(opened).toEqual(['dforge'])
  })

  test('leaves the pane shut on a desktop joining when Show at start is off', async ($, on) => {
    const opened: string[] = []
    world(on, { tokens: 100_000, opened, isPaneShut: true, config: { openAtStart: false } })
    await $.session.start(START)
    await $.session.attach({ surface: 'desktop', clientId: 'desktop:default' } as never)
    expect(opened).toEqual([])
  })
})

describe('native rows', () => {
  // A stand-in element table: what native.tsx draws comes back as plain
  // objects. A Text keeps no key, as on a real surface.
  const TABLE = { Box: 'Box', Text: 'Text', Svg: 'Svg' } as never
  const PICTURE = '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>'

  test('maps the named colors to theme keys and passes the rest through', () => {
    expect(['green', 'red', 'yellow', 'cyan', 'blue', 'magenta', 'gray', 'white'].map(name => themeColor(name))).toEqual(['success', 'error', 'warning', 'suggestion', 'suggestion', 'planMode', 'subtle', 'text'])
    expect(themeColor('#ff8700')).toBe('#ff8700')
    expect(themeColor('permission')).toBe('permission')
    expect(themeColor(undefined)).toBeUndefined()
  })

  test('draws a run as the desktop text, a chip on a pill', () => {
    expect(nativeRun(TABLE, 'run', { text: '12m', color: 'green', bold: true, mono: true })).toEqual({ type: 'Text', props: { color: 'success', weight: 'semibold', mono: true }, children: ['12m'] })
    expect(nativeRun(TABLE, 'run', { text: 'Opus 5.5', color: 'cyan', chip: true })).toEqual({ type: 'Text', props: { color: 'suggestion', size: 'caption', backgroundColor: 'subtle' }, children: ['Opus 5.5'] })
    expect(nativeRun(TABLE, 'run', { text: 'done', faint: true })).toEqual({ type: 'Text', props: { dimColor: true }, children: ['done'] })
  })

  test('draws each kind of panel line', () => {
    // Text: its left cut at the end beside its right, an indent in cells.
    expect(nativeLine(TABLE, 'row', { kind: 'text', small: true, indent: 15, left: [{ text: 'a' }], right: [{ text: 'b' }] })).toEqual({
      type: 'Box',
      props: { key: 'row', flexDirection: 'row', justifyContent: 'space-between', columnGap: 'sm', paddingLeft: 2 },
      children: [
        { type: 'Box', props: { key: 'row-left', flexGrow: 1, flexShrink: 1 }, children: [{ type: 'Text', props: { size: 'footnote', wrap: 'truncate-end' }, children: [{ type: 'Text', children: ['a'] }] }] },
        { type: 'Box', props: { key: 'row-right', flexShrink: 0 }, children: [{ type: 'Text', props: { size: 'footnote' }, children: [{ type: 'Text', children: ['b'] }] }] },
      ],
    })
    expect(nativeLine(TABLE, 'note', { kind: 'text', wrap: true, left: [{ text: 'a long note' }] })).toMatchObject({ children: [{ children: [{ props: { wrap: 'wrap' } }] }] })
    expect(nativeLine(TABLE, 'chips', { kind: 'chips', chips: [{ text: 'one' }, { text: 'two', color: 'red' }] })).toEqual({
      type: 'Box',
      props: { key: 'chips', flexDirection: 'row', flexWrap: 'wrap', gap: 'xs' },
      children: [
        { type: 'Text', props: { size: 'caption', backgroundColor: 'subtle' }, children: ['one'] },
        { type: 'Text', props: { color: 'error', size: 'caption', backgroundColor: 'subtle' }, children: ['two'] },
      ],
    })
    const badge = nativeLine(TABLE, 'who', { kind: 'badge', svg: PICTURE, lines: [[{ text: 'me@example.com' }], [{ text: 'Me' }]] })
    expect(badge).toMatchObject({ type: 'Box', props: { key: 'who', flexDirection: 'row' }, children: [{ type: 'Svg', props: { source: PICTURE } }, { type: 'Box', props: { key: 'who-lines' } }] })
    expect((badge as { children: { children?: unknown[] }[] }).children[1]?.children).toMatchObject([{ type: 'Text', props: { wrap: 'truncate-end' } }, { type: 'Text', props: { size: 'footnote' } }])
    expect(nativeLine(TABLE, 'bar', { kind: 'picture', svg: PICTURE, alt: 'a bar' })).toEqual({ type: 'Svg', props: { source: PICTURE, alt: 'a bar' } })
    // A surface without pictures draws none.
    expect(nativeLine({ Box: 'Box', Text: 'Text' } as never, 'bar', { kind: 'picture', svg: PICTURE })).toBe(false)
  })

  test('draws a text line without its right half or indent, and a badge without pictures', () => {
    // No right half draws no box for it, and no indent no padding; a dim run is dimmed.
    expect(nativeLine(TABLE, 'row', { kind: 'text', left: [{ text: 'a', dim: true }] })).toEqual({
      type: 'Box',
      props: { key: 'row', flexDirection: 'row', justifyContent: 'space-between', columnGap: 'sm' },
      children: [{ type: 'Box', props: { key: 'row-left', flexGrow: 1, flexShrink: 1 }, children: [{ type: 'Text', props: { wrap: 'truncate-end' }, children: [{ type: 'Text', props: { dimColor: true }, children: ['a'] }] }] }],
    })
    expect(nativeLine({ Box: 'Box', Text: 'Text' } as never, 'who', { kind: 'badge', svg: PICTURE, lines: [[{ text: 'me@example.com' }], [{ text: 'Me' }]] })).toEqual({
      type: 'Box',
      props: { key: 'who', flexDirection: 'row', alignItems: 'center', columnGap: 'sm' },
      children: [
        {
          type: 'Box',
          props: { key: 'who-lines', flexDirection: 'column', flexShrink: 1 },
          children: [
            { type: 'Text', props: { wrap: 'truncate-end' }, children: [{ type: 'Text', children: ['me@example.com'] }] },
            { type: 'Text', props: { size: 'footnote', wrap: 'truncate-end' }, children: [{ type: 'Text', children: ['Me'] }] },
          ],
        },
      ],
    })
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
  test('keys, colors, names and billing', () => {
    expect(accountKey('/home/me/.claude', '/home/me')).toBe('~/.claude')
    expect(accountKey('C:\\Users\\me\\.claude-work', 'C:\\Users\\me')).toBe('~/.claude-work')
    expect(accountKey('/srv/claude', '/home/me')).toBe('/srv/claude')
    expect(termColor('141')).toBe('#af87ff')
    expect(accountColor('~/.claude')).toBe(accountColor('~/.claude'))
    expect(new Set(['~/.claude', '~/.claude-work', '~/.claude-2', '/srv/claude'].map(accountColor)).size).toBeGreaterThan(1)
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
    expect(await ui.find({ type: 'Button', text: '▾ Account' })).toBeDefined()
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
    expect(await ui.find({ type: 'Button', text: '▾ Account' })).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▸ Account' })).toBeUndefined()
  })
})

describe('band lines', () => {
  const hour = 3_600_000
  const input = {
    cwd: '/home/me/code/shop/web/src',
    root: '/home/me/code/shop',
    home: '/home/me',
    repo: { branch: 'feat/a-rather-long-branch-name', ahead: 2, behind: 1, changed: 1, untracked: 2 },
    context: { tokens: 284_000, limit: 465_000, window: 650_000 },
    turnsLeft: 9,
    limits: [
      { kind: 'five_hour', percent: 23, resetsAt: 2 * hour },
      { kind: 'seven_day', percent: 61, resetsAt: 86 * hour },
    ],
    agents: 1,
    shells: { count: 2, longest: 12 * 60_000 },
    now: 0,
  }
  const text = (runs: { text: string }[]) => runs.map(run => run.text).join('')

  test('draws the fullest tier with pace, agents, shells and the repo', () => {
    const [one, two] = bandLines(input, 0)
    expect(text(one)).toBe('ctx ▰▰▰▰▱▱▱┃▱▱ 61% · ≈9 turns  ·  5h ▰▰▱▱┊▱▱▱ 23% on pace · 2h0m  ·  7d ▰▰▰┊▰▱▱▱ 61% out in 2d4h')
    expect(text(two)).toBe('● 1 agent  ·  $ 2 shells · longest 12m  ·  ~/code/shop/web/src ⎇ feat/a-rather-long-branch-name* ↑2 ↓1 ~1 ?2')
  })

  test('measures and cuts a row by terminal cells', () => {
    expect(runsWidth([{ text: '⏳ approve? ' }, { text: 'e\u0301' }])).toBe(13)
    expect(runsCut([{ text: 'ok ' }, { text: '日本語のブランチ' }], 8)).toEqual([{ text: 'ok ' }, { text: '日本' }, { text: '…', dim: true }])
  })

  test('measures an emoji its presentation selector asks for as two cells', () => {
    expect(cellWidth('⚠️')).toBe(2)
    expect(cellWidth('⚠')).toBe(1)
    expect(cellWidth('✅')).toBe(2)
    expect(cellWidth('a\ufe0f')).toBe(1)
    expect(runsWidth([{ text: '⚠️ low' }])).toBe(6)
    expect(runsWidth(runsCut([{ text: 'ab⚠️cd' }], 4))).toBeLessThanOrEqual(4)
  })

  test('steps each line down until it fits, never naming a command', () => {
    for (const width of [160, 90, 60, 40, 24]) {
      const [one, two] = fitBand(input, width)
      expect(runsWidth(one)).toBeLessThanOrEqual(width)
      expect(runsWidth(two)).toBeLessThanOrEqual(width)
    }
    expect(text(fitBand(input, 40)[0])).toBe('ctx 61% ≈9t · 5h 23% ✓ · 7d 61% 2d4h')
    expect(text(bandLines(input, 3)[1])).toBe('● 1 · $ 2 · shop ⎇ feat/a-rather-l…*')
    expect(shellAge(42_000)).toBe('42s')
    expect(shellAge(12 * 60_000)).toBe('12m')
  })

  test('leaves out what is not running', () => {
    const [, two] = bandLines({ ...input, agents: 0, shells: { count: 0, longest: 0 } }, 0)
    expect(text(two)).toBe('~/code/shop/web/src ⎇ feat/a-rather-long-branch-name* ↑2 ↓1 ~1 ?2')
    const meters = bandMetersSvg([{ key: 'Context', percent: 61, share: 0.44, color: 'yellow', tick: 0.72, note: [{ text: '≈9 turns' }] }], 300)
    expect(meters).toContain('>CONTEXT</text>')
    expect(meters).toContain('61%')
  })

  test('leads line 2 with ◐ while background work runs', () => {
    expect(text(bandLines({ ...input, isBackground: true }, 0)[1])).toBe('◐ ● 1 agent  ·  $ 2 shells · longest 12m  ·  ~/code/shop/web/src ⎇ feat/a-rather-long-branch-name* ↑2 ↓1 ~1 ?2')
    expect(text(bandLines({ ...input, isBackground: false }, 0)[1])).toBe('● 1 agent  ·  $ 2 shells · longest 12m  ·  ~/code/shop/web/src ⎇ feat/a-rather-long-branch-name* ↑2 ↓1 ~1 ?2')
  })

  test('sets a label into the bottom rule, cut to fit', () => {
    const whole = (rule: { lead: string; label: string; tail: string }) => rule.lead + rule.label + rule.tail
    expect(whole(bottomRule('? for shortcuts', 30))).toBe(`╰─ ? for shortcuts ${'─'.repeat(10)}╯`)
    expect(whole(bottomRule('esc to interrupt and more', 20))).toBe('╰─ esc to interr… ─╯')
    expect(whole(bottomRule(null, 10))).toBe('╰────────╯')
    expect(whole(bottomRule('  ', 10))).toBe('╰────────╯')
    for (const width of [10, 20, 30]) expect([...whole(bottomRule('esc to interrupt and more', width))].length).toBe(width)
    expect(whole(bottomRule('日本語のヒント', 14))).toBe('╰─ 日本語… ──╯')
    for (const width of [12, 20, 30]) expect(cellWidth(whole(bottomRule('日本語のヒントです', width)))).toBe(width)
    expect(MODE_LABEL_RESERVE).toBe(29)
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
    expect(elapsed(3_725_000)).toBe('1h02m')
  })

  test('reads the background state with what still runs', () => {
    const at = 200_000
    const two = { shells: [{ command: 'npm test', startedAt: 140_000 }, { command: 'node codex-companion.mjs review --background\nsecond line', startedAt: 20_000 }], agents: 1 }
    expect(flat(nowLine({ ...IDLE, kind: 'background' }, at, two))).toBe('◐ background · 2 shells · npm test · 3m · 1 agent')
    const long = { shells: [{ command: 'node codex-companion.mjs review --background', startedAt: 20_000 }], agents: 0 }
    expect(flat(nowLine({ ...IDLE, kind: 'background' }, at, long))).toBe('◐ background · 1 shell · node codex-companion.mjs review --backg… · 3m')
    expect(flat(nowLine({ ...IDLE, kind: 'background' }, at, { shells: [], agents: 2 }))).toBe('◐ background · 2 agents')
    expect(flat(nowLine({ ...IDLE, kind: 'background', isSent: true }, at, { shells: [], agents: 1 }))).toBe('◐ background · 1 agent · Discord ✓')
  })

  test('tells a service from a job that ends', () => {
    for (const command of ['npm run dev', 'pnpm dev', 'yarn start', 'npm run dev:api', 'vite --port 3000', 'npx next dev', 'python3 -m http.server 8000', 'docker compose up', 'tail -f app.log', 'jest --watch', 'jest --watchAll', 'cargo watch -x run', 'cd web && npm run dev', 'PORT=3000 npm start'])
      expect(isServiceCommand(command)).toBe(true)
    for (const command of ['npm test', 'npm run build', 'vite build', 'vitest', 'docker compose up -d', 'npm run start:build', 'node codex-companion.mjs review', 'echo "npm run dev"', 'make\nnpm run dev'])
      expect(isServiceCommand(command)).toBe(false)
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
})

describe('dense rows', () => {
  const INPUT: DenseInput = {
    email: 'me@example.com',
    billing: 'subscription',
    remote: [{ text: '○ not connected' }],
    context: { tokens: 284_000, limit: 465_000 },
    turnsLeft: 8,
    limits: [
      { kind: 'five_hour', percent: 23 },
      { kind: 'seven_day', percent: 61 },
      { kind: 'spend_limit', percent: 5 },
    ],
    shells: [
      { command: 'npm test', startedAt: 100_000 },
      { command: 'node codex-companion.mjs review --background\nmore', startedAt: 160_000 },
    ],
    agents: ['impl-sonnet-medium', 'judge-opus'],
    run: { done: 3, total: 5, current: 'Task 4: Draw the card' },
    todos: null,
    repo: { branch: 'main', ahead: 2, behind: 0, changed: 3, untracked: 1 },
    refused: 0,
    now: 340_000,
  }

  test('draw one line per section', () => {
    expect(flat(denseLine('account', INPUT) ?? [])).toBe('acct me@example.com · subscription · Remote ○ not connected')
    expect(flat(denseLine('context', INPUT) ?? [])).toBe('ctx  ▰▰▰▰▰▰▱▱▱▱ 61% 284k/465k · ≈8 turns')
    expect(flat(denseLine('usage', INPUT) ?? [])).toBe('lim  5h ▰▱▱▱▱▱ 23% · 7d ▰▰▰▰▱▱ 61%')
    expect(flat(denseLine('shells', INPUT) ?? [])).toBe('$    2 shells · node codex-companion.mjs review --backg… · 3m')
    expect(flat(denseLine('agents', INPUT) ?? [])).toBe('agt  2 running · impl-sonnet-medium, judge-opus')
    expect(flat(denseLine('plan', INPUT) ?? [])).toBe('plan ▰▰▰▱▱ 3/5 · Task 4: Draw the card')
    expect(flat(denseLine('repo', INPUT) ?? [])).toBe('⎇    main ↑2 · ~3 changed · ?1')
    expect(denseLine('guard', INPUT)).toBeNull()
    expect(flat(denseLine('guard', { ...INPUT, refused: 2 }) ?? [])).toBe('grd  ✗ 2 refused')
  })

  test('leave out what has nothing to show, and say when nothing was read yet', () => {
    const empty: DenseInput = { ...INPUT, email: null, context: null, limits: [], shells: [], agents: [], run: null, todos: null, repo: null }
    expect(denseLine('account', empty)).toBeNull()
    expect(flat(denseLine('context', empty) ?? [])).toBe('ctx  no reading yet')
    expect(flat(denseLine('usage', empty) ?? [])).toBe('lim  no reading yet')
    for (const section of ['shells', 'agents', 'plan', 'repo', 'guard'] as const) expect(denseLine(section, empty)).toBeNull()
    expect(flat(denseLine('plan', { ...empty, todos: { done: 1, total: 4, current: 'Write the tests' } }) ?? [])).toBe('plan ▰▱▱▱ 1/4 · Write the tests')
  })
})

describe('shells and remote', () => {
  const SHELL = { result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b7k2' }, text: 'Running in the background' }
  const ENDED = '<task-notification>\n<task-id>b7k2</task-id>\n<status>completed</status>\n<summary>done</summary>\n</task-notification>'
  // The notification row a loop keeps: the main conversation's, or a subagent's.
  const notified = (text: string, agentId?: string) =>
    ({
      message: { type: 'user', role: 'user', content: [{ type: 'text', text }] },
      door: 'prompt',
      origin: { kind: 'task-notification' },
      uuid: `row-${text.length}`,
      ...(agentId === undefined ? {} : { agentId }),
    }) as never

  test('reads task ends and names devices', () => {
    expect(tasksEnded(ENDED)).toEqual([{ id: 'b7k2', status: 'completed' }])
    expect(tasksEnded('no tasks here')).toEqual([])
    expect(runsText(remoteRuns([{ surface: 'mobile' }], 'false'))).toBe('● connected · phone')
    expect(runsText(remoteRuns([{ surface: 'mobile' }, { surface: 'mobile' }], null))).toBe('● connected · 2 phones')
    expect(runsText(remoteRuns([], 'true'))).toBe('○ on · no device yet')
    expect(runsText(remoteRuns([], 'default'))).toBe('○ not connected')
  })

  test('list a background shell until its notification ends it', async ($, on) => {
    const clock = world(on, { ...SIGNED_IN, tools: { Bash: () => SHELL } })
    signedIn(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true } as never)
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    // Shells is a card of its own, ahead of Agents, and Agents lists no shell.
    expect((await ui.find({ key: 'shells' }))?.props.borderColor).toBe('yellow')
    expect(await ui.find({ type: 'Text', text: /^\$ npm run dev 0s$/ })).toBeDefined()
    expect(await ui.find({ type: 'Button', text: '▾ Agents' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /No subagents yet\./ })).toBeDefined()
    // Idle, the pane still ticks each second while the shell runs.
    await clock.advance(65_000)
    expect(await ui.find({ type: 'Text', text: /^\$ npm run dev 1m05s$/ })).toBeDefined()
    await ui.unmount()
    await $.session.append(notified(ENDED))
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^\$ npm run dev/ })).toBeUndefined()
    // With no shell left the card goes.
    expect(await ui.find({ key: 'shells' })).toBeUndefined()
  })

  test('drop a shell a subagent started once its notification reaches the subagent', async ($, on) => {
    world(on, { ...SIGNED_IN, tools: { Bash: () => SHELL } })
    signedIn(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'npm test', run_in_background: true, agentId: 'agent-1' } as never)
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^\$ npm test/ })).toBeDefined()
    await ui.unmount()
    await $.session.append(notified(`[SYSTEM NOTIFICATION - NOT USER INPUT]\n\n${ENDED}`, 'agent-1'))
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ key: 'shells' })).toBeUndefined()
  })

  test("drops a subagent's shells when the subagent ends", async ($, on) => {
    world(on, { ...SIGNED_IN, tools: { Bash: () => SHELL } })
    signedIn(on)
    await $.session.start(START)
    await $.agent.spawn({ tool_use_id: 'toolu_1', prompt: 'Implement', description: 'Task 1', subagentType: 'dforge:impl-sonnet-low', provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: true, fork: false })
    await $.tool.call({ tool: 'Bash', command: 'npm test', run_in_background: true, agentId: 'agent-1' } as never)
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^\$ npm test/ })).toBeDefined()
    await ui.unmount()
    await $.turn.complete({ answer: 'ok', durationMs: 1_000, isAborted: false, turnId: 'a1', reason: 'answer', agentId: 'agent-1' })
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ key: 'shells' })).toBeUndefined()
  })

  test('a stop naming a background agent ends its spawn', async ($, on) => {
    world(on, { ...SIGNED_IN, tools: { TaskStop: () => ({ result: { task_id: 'agent-1' }, text: 'stopped' }) } })
    signedIn(on)
    await $.session.start(START)
    await $.agent.spawn({ tool_use_id: 'toolu_1', prompt: 'Review', description: 'Review the branch', subagentType: 'dforge:judge-opus', provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: true, fork: false })
    await $.tool.call({ tool: 'TaskStop', task_id: 'agent-1' } as never)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^Failed · 1$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^Working · / })).toBeUndefined()
  })

  describe('a Done held for background work', () => {
    const titles = (fetches: NonNullable<World['fetches']>) => fetches.map(one => (one.body.embeds as Record<string, unknown>[] | undefined)?.[0]?.title)
    // A turn that sends a shell to the background and ends 30 s later, the shell still running.
    const hold = async ($: Parameters<TestBody>[0], on: On, fetches: NonNullable<World['fetches']>) => {
      const clock = world(on, { tokens: 50_000, fetches, config: { notifyAfter: 60 }, tools: { Bash: () => SHELL } })
      mock.store(on, { notifyUrl: WEBHOOK })
      await $.session.start(START)
      await $.turn.start({ text: 'review it', turnId: 't1' })
      await $.tool.call({ tool: 'Bash', command: 'node codex-companion.mjs review', run_in_background: true } as never)
      await clock.advance(30_000)
      await $.turn.complete({ answer: 'Started the review.', durationMs: 30_000, isAborted: false, turnId: 't1', reason: 'answer' })
      return clock
    }

    test('shows the background state and sends one Done after the woken turn', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = await hold($, on, fetches)
      expect(fetches).toHaveLength(0)
      const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
      expect(await ui.find({ type: 'Text', text: /◐ background · 1 shell · node codex-companion\.mjs review · 30s/ })).toBeDefined()
      await ui.unmount()
      await clock.advance(90_000)
      await $.session.append(notified(`[SYSTEM NOTIFICATION - NOT USER INPUT]\n\n${ENDED}`))
      await $.turn.start({ text: '', turnId: 't2' })
      await clock.advance(5_000)
      await $.turn.complete({ answer: 'Review clean.', durationMs: 5_000, isAborted: false, turnId: 't2', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 2m05s'])
    })

    test('sends the held Done once the grace passes with no turn', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = await hold($, on, fetches)
      await clock.advance(90_000)
      await $.session.append(notified(ENDED))
      await clock.advance(4_000)
      expect(fetches).toHaveLength(0)
      await clock.advance(2_000)
      expect(titles(fetches)).toEqual(['✅ Done in 2m05s'])
      const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
      expect(await ui.find({ type: 'Text', text: /^○ idle/ })).toBeDefined()
    })

    test('the turn the work wakes sends no second Done once the grace sent it', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = await hold($, on, fetches)
      await clock.advance(90_000)
      await $.session.append(notified(ENDED))
      await clock.advance(6_000)
      expect(titles(fetches)).toEqual(['✅ Done in 2m05s'])
      await $.turn.start({ text: '', turnId: 't2' })
      await clock.advance(70_000)
      await $.turn.complete({ answer: 'Review clean.', durationMs: 70_000, isAborted: false, turnId: 't2', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 2m05s'])
      await $.prompt.submit({ text: 'what next?', origin: { kind: 'composer' }, wait: false } as never)
      await $.turn.start({ text: 'what next?', turnId: 't3' })
      await clock.advance(70_000)
      await $.turn.complete({ answer: 'Nothing left.', durationMs: 70_000, isAborted: false, turnId: 't3', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 2m05s', '✅ Done in 1m10s'])
    })

    test('the turn the work wakes sends no second Done once the watchdog sent it', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = await hold($, on, fetches)
      await clock.advance(1_860_000)
      expect(titles(fetches)).toEqual(['✅ Done in 31m00s'])
      await $.session.append(notified(ENDED))
      await $.turn.start({ text: '', turnId: 't2' })
      await clock.advance(70_000)
      await $.turn.complete({ answer: 'Review clean.', durationMs: 70_000, isAborted: false, turnId: 't2', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 31m00s'])
    })

    test('a turn starting in the grace carries the held Done', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = await hold($, on, fetches)
      await clock.advance(90_000)
      await $.session.append(notified(ENDED))
      await clock.advance(1_000)
      await $.turn.start({ text: '', turnId: 't2' })
      await clock.advance(10_000)
      expect(fetches).toHaveLength(0)
      await $.turn.complete({ answer: 'Review clean.', durationMs: 10_000, isAborted: false, turnId: 't2', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 2m11s'])
    })

    test('a typed prompt starts a new chain', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = await hold($, on, fetches)
      await clock.advance(60_000)
      await $.prompt.submit({ text: 'what next?', origin: { kind: 'composer' }, wait: false } as never)
      await $.turn.start({ text: 'what next?', turnId: 't2' })
      await clock.advance(10_000)
      await $.turn.complete({ answer: 'Waiting on the review.', durationMs: 10_000, isAborted: false, turnId: 't2', reason: 'answer' })
      expect(fetches).toHaveLength(0)
      await clock.advance(60_000)
      await $.session.append(notified(ENDED))
      await $.turn.start({ text: '', turnId: 't3' })
      await clock.advance(5_000)
      await $.turn.complete({ answer: 'Review clean.', durationMs: 5_000, isAborted: false, turnId: 't3', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 1m15s'])
    })

    test("auto run's prompt starts a new chain", async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = await hold($, on, fetches)
      await clock.advance(60_000)
      await $.prompt.submit({ text: 'Continue the plan.', origin: { kind: 'plugin', name: 'dforge', asUser: true }, wait: false } as never)
      await $.turn.start({ text: '', turnId: 't2' })
      await clock.advance(10_000)
      await $.turn.complete({ answer: 'Waiting on the review.', durationMs: 10_000, isAborted: false, turnId: 't2', reason: 'answer' })
      await clock.advance(60_000)
      await $.session.append(notified(ENDED))
      await $.turn.start({ text: '', turnId: 't3' })
      await clock.advance(5_000)
      await $.turn.complete({ answer: 'Review clean.', durationMs: 5_000, isAborted: false, turnId: 't3', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 1m15s'])
    })

    test('a wake-up keeps the chain whatever its text', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = await hold($, on, fetches)
      await clock.advance(90_000)
      await $.session.append(notified(ENDED))
      await $.prompt.submit({ text: 'The review finished.', origin: { kind: 'task-notification' }, wait: false } as never)
      await $.turn.start({ text: 'The review finished.', turnId: 't2' })
      await clock.advance(5_000)
      await $.turn.complete({ answer: 'Review clean.', durationMs: 5_000, isAborted: false, turnId: 't2', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 2m05s'])
    })

    test('a shell older than the cap holds nothing', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = world(on, { tokens: 50_000, fetches, config: { notifyAfter: 0 }, tools: { Bash: () => SHELL } })
      mock.store(on, { notifyUrl: WEBHOOK })
      await $.session.start(START)
      await $.tool.call({ tool: 'Bash', command: 'node codex-companion.mjs review', run_in_background: true } as never)
      await clock.advance(31 * 60_000)
      await $.turn.start({ text: 'what next?', turnId: 't1' })
      await $.turn.complete({ answer: 'Nothing left.', durationMs: 5_000, isAborted: false, turnId: 't1', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 5s'])
      const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
      expect(await ui.find({ type: 'Text', text: /^○ idle/ })).toBeDefined()
    })

    test('a service shell holds nothing', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      world(on, { tokens: 50_000, fetches, config: { notifyAfter: 0 }, tools: { Bash: () => SHELL } })
      mock.store(on, { notifyUrl: WEBHOOK })
      await $.session.start(START)
      await $.turn.start({ text: 'start the app', turnId: 't1' })
      await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true } as never)
      await $.turn.complete({ answer: 'Running on :5173.', durationMs: 5_000, isAborted: false, turnId: 't1', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 5s'])
      const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
      expect(await ui.find({ type: 'Text', text: /^○ idle/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /^\$ npm run dev/ })).toBeDefined()
    })

    test('a service beside a held job releases with the job', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const ids = ['b7k2', 'b9d1']
      const clock = world(on, { tokens: 50_000, fetches, config: { notifyAfter: 60 }, tools: { Bash: () => ({ ...SHELL, result: { ...SHELL.result, backgroundTaskId: ids.shift() } }) } })
      mock.store(on, { notifyUrl: WEBHOOK })
      await $.session.start(START)
      await $.turn.start({ text: 'review it', turnId: 't1' })
      await $.tool.call({ tool: 'Bash', command: 'node codex-companion.mjs review', run_in_background: true } as never)
      await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true } as never)
      await clock.advance(30_000)
      await $.turn.complete({ answer: 'Started the review.', durationMs: 30_000, isAborted: false, turnId: 't1', reason: 'answer' })
      expect(fetches).toHaveLength(0)
      await clock.advance(90_000)
      await $.session.append(notified(ENDED))
      await clock.advance(6_000)
      expect(titles(fetches)).toEqual(['✅ Done in 2m05s'])
    })

    test("a subagent's shell holds nothing", async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      world(on, { tokens: 50_000, fetches, config: { notifyAfter: 0 }, tools: { Bash: () => SHELL } })
      mock.store(on, { notifyUrl: WEBHOOK })
      await $.session.start(START)
      await $.turn.start({ text: 'go', turnId: 't1' })
      await $.tool.call({ tool: 'Bash', command: 'npm test', run_in_background: true, agentId: 'agent-1' } as never)
      await $.turn.complete({ answer: 'ok', durationMs: 5_000, isAborted: false, turnId: 't1', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 5s'])
    })

    test('the watchdog sends a hold older than the cap', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = await hold($, on, fetches)
      await clock.advance(1_800_000)
      expect(fetches).toHaveLength(0)
      await clock.advance(60_000)
      expect(titles(fetches)).toEqual(['✅ Done in 31m00s'])
    })

    test('a session ending in the grace sends no Done', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      on('session.end', (_$, e) => e as never)
      const clock = await hold($, on, fetches)
      await clock.advance(90_000)
      await $.session.append(notified(ENDED))
      await $.session.end({ reason: 'other', sessionId: 'sess-1' } as never)
      await clock.advance(10_000)
      expect(fetches).toHaveLength(0)
    })

    test("a subagent's approval after the turn does not stall the release", async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      on('tool.check', () => ({ decision: 'ask' }))
      const clock = await hold($, on, fetches)
      await clock.advance(90_000)
      await $.tool.check({ tool: 'Bash', input: { command: 'ls' }, tool_use_id: 'toolu_9', agentId: 'agent-1' })
      await $.tool.call({ tool: 'Bash', command: 'ls', tool_use_id: 'toolu_9', agentId: 'agent-1' } as never)
      await $.session.append(notified(ENDED))
      await clock.advance(5_000)
      expect(titles(fetches)).toEqual(['✅ Done in 2m05s'])
    })

    test('the shell ending under a subagent approval still releases once it is answered', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      on('tool.check', () => ({ decision: 'ask' }))
      const clock = await hold($, on, fetches)
      await clock.advance(90_000)
      await $.tool.check({ tool: 'Bash', input: { command: 'ls' }, tool_use_id: 'toolu_9', agentId: 'agent-1' })
      await $.session.append(notified(ENDED))
      await clock.advance(5_000)
      expect(fetches).toHaveLength(0)
      await $.tool.call({ tool: 'Bash', command: 'ls', tool_use_id: 'toolu_9', agentId: 'agent-1' } as never)
      await clock.advance(5_000)
      expect(titles(fetches)).toEqual(['✅ Done in 2m10s'])
    })
  })

  test('drop a shell TaskStop stopped', async ($, on) => {
    world(on, { ...SIGNED_IN, tools: { Bash: () => SHELL, TaskStop: () => ({ result: { message: 'stopped', task_id: 'b7k2', task_type: 'local_bash' }, text: 'stopped' }) } })
    signedIn(on)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true } as never)
    await $.tool.call({ tool: 'TaskStop', task_id: 'b7k2' } as never)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^\$ npm run dev/ })).toBeUndefined()
  })

  test('show Remote Control in the account card and on the band', async ($, on) => {
    world(on, { ...SIGNED_IN, remoteControl: 'true', tools: { Bash: () => SHELL } })
    signedIn(on)
    await $.session.start(START)
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Remote ○ on · no device yet/ })).toBeDefined()
    await ui.unmount()
    await $.session.attach({ surface: 'mobile', clientId: 'mobile:default' } as never)
    await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true } as never)
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Remote ● connected · phone/ })).toBeDefined()
    await ui.unmount()
    ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^╭─ me@example\.com · subscription · Remote ● connected ─+ $/ })).toBeDefined()
    await ui.unmount()
    await $.session.detach({ surface: 'mobile', clientId: 'mobile:default' } as never)
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Remote ○ on · no device yet/ })).toBeDefined()
  })

  test('start the band\'s top rule with Remote when no email is known', async ($, on) => {
    world(on, { ...SIGNED_IN, remoteControl: 'true' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^╭─ Remote ○ on ─+ $/ })).toBeDefined()
  })

  test('say Remote is not connected on the band as the pane does', async ($, on) => {
    world(on, { ...SIGNED_IN })
    signedIn(on)
    await $.session.start(START)
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Remote ○ not connected/ })).toBeDefined()
    await ui.unmount()
    ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^╭─ me@example\.com · subscription · Remote ○ not connected ─+ $/ })).toBeDefined()
  })

  test('say what kept running after Esc', async ($, on) => {
    world(on, { ...SIGNED_IN, tools: { Bash: () => SHELL } })
    signedIn(on)
    await $.session.start(START)
    await $.turn.start({ text: 'go', turnId: 't1' })
    await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true } as never)
    await $.turn.complete({ answer: '', durationMs: 3_000, isAborted: true, turnId: 't1', reason: 'aborted' } as never)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^■ interrupted · 1 shell still running · just now$/ })).toBeDefined()
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
    expect(redact('{"password":"hunter2","api_key": "a\\"b", "n": 1}')).toBe('{"password":[hidden],"api_key": [hidden], "n": 1}')
    expect(redact('curl -d \'{\\"token\\":\\"abc\\"}\' x')).toBe('curl -d \'{\\"token\\":[hidden] x')
    expect(redact('GITHUB_TOKEN=abc123 gh pr list')).toBe('GITHUB_TOKEN=[hidden] gh pr list')
    expect(redact("{'api_key': 'a\\'b', 'n': 1}")).toBe("{'api_key': [hidden], 'n': 1}")
    expect(redact('max_tokens: 4096')).toBe('max_tokens: 4096')
    expect(redact(`post ${WEBHOOK}`)).toBe('post [webhook]')
    expect(excerpt('a'.repeat(20), 10)).toBe(`${'a'.repeat(9)}…`)
  })

  test('picks kinds and keeps the default set as the empty setting', () => {
    expect(notifyKindsFrom('')).toEqual(['ask', 'question', 'done', 'error', 'blocked', 'budget', 'limit'])
    expect(notifyKindsFrom('done, nope, done')).toEqual(['done'])
    expect(notifyKindsFrom('none')).toEqual([])
    expect(notifyKindsFrom(' None ')).toEqual([])
    expect(notifyKindsFrom('off')).toEqual([])
    expect(notifyKindsFrom(notifyKindsToggled(['done'], 'done'))).toEqual([])
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
    expect(embed?.footer).toEqual({ text: 'dforge · ~/.claude · tmux work' })
    expect(embed?.description).toBe('Bash: git push')
    const quiet = discordBody({ kind: 'done', title: '✅ Done', detail: 'the answer' }, place, { mention: '42424242', isBrief: true, now: 0 })
    expect(quiet.content).toBeUndefined()
    expect(quiet.flags).toBe(4096)
    expect((quiet.embeds as Record<string, unknown>[])[0]?.description).toBeUndefined()
  })

  test('sends a long turn\'s end, and nothing without a webhook', async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches, config: { notifyAfter: 60 } })
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

  test('says nothing when no webhook is set', async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches, config: { notifyAfter: 0 } })
    mock.store(on, {})
    await $.session.start(START)
    await $.turn.complete({ answer: 'ok', durationMs: 5_000, isAborted: false, turnId: 't1', reason: 'answer' })
    expect(fetches).toEqual([])
  })

  test('asks for an answer, then edits the message once it comes', async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches, config: { notifyAskAfter: 0 } })
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
    await ui.press({ key: 'settings-tab-Notifications' })
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

  test('keeps the webhook field mounted while a save is out, so a refused entry keeps its text', async ($, on) => {
    world(on, { tokens: 50_000 })
    const kept = new Map<string, unknown>()
    let release: () => void = () => {}
    const gate = new Promise<void>(resolve => {
      release = resolve
    })
    on('store.get', (_$, e) => ({ value: kept.get(e.key) }))
    on('store.set', async (_$, e) => {
      await gate
      kept.set(e.key, e.value)
      return { value: undefined }
    })
    on('store.delete', () => ({ value: undefined }))
    on('store.keys', () => ({ value: [...kept.keys()] }))
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Notifications' })
    await ui.press({ key: 'set-notify-url-edit' })
    const submitted = ui.input({ key: 'set-notify-url-input', text: WEBHOOK, kind: 'submit' })
    await ui.advance(50)
    expect(await ui.find({ key: 'set-notify-url-input' })).toBeDefined()
    release()
    await submitted
    expect(await ui.find({ key: 'set-notify-url-input' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /discord\.com\/…\/1234…\/••••/ })).toBeDefined()
  })

  test('an invalid webhook keeps its field open with the error', async ($, on) => {
    world(on, { tokens: 50_000 })
    mock.store(on, {})
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Notifications' })
    await ui.press({ key: 'set-notify-url-edit' })
    await ui.input({ key: 'set-notify-url-input', text: 'https://example.com/hook', kind: 'submit' })
    expect(await ui.find({ key: 'set-notify-url-input' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /not a Discord webhook URL/ })).toBeDefined()
  })

  test('keeps one editor open on the Notifications tab', async ($, on) => {
    world(on, { tokens: 50_000 })
    mock.store(on, {})
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Notifications' })
    await ui.press({ key: 'set-notify-url-edit' })
    expect(await ui.find({ key: 'set-notify-url-input' })).toBeDefined()
    await ui.press({ key: 'set-notifyAfter-edit' })
    expect(await ui.find({ key: 'set-notifyAfter-input' })).toBeDefined()
    expect(await ui.find({ key: 'set-notify-url-input' })).toBeUndefined()
  })

  test('Reset group closes an open webhook field', async ($, on) => {
    world(on, { tokens: 50_000, config: { notifyAfter: 0 }, written: {} })
    mock.store(on, {})
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Notifications' })
    await ui.press({ key: 'set-notify-url-edit' })
    await ui.press({ key: 'settings-reset' })
    expect(await ui.find({ key: 'settings-reset-confirm' })).toBeDefined()
    expect(await ui.find({ key: 'set-notify-url-input' })).toBeUndefined()
    // Opening the field again ends the pending reset, and a save keeps it ended.
    await ui.press({ key: 'set-notify-url-edit' })
    expect(await ui.find({ key: 'settings-reset-confirm' })).toBeUndefined()
    await ui.input({ key: 'set-notify-url-input', text: WEBHOOK, kind: 'submit' })
    expect(await ui.find({ key: 'settings-reset-confirm' })).toBeUndefined()
    expect(await ui.find({ key: 'settings-reset' })).toBeDefined()
  })

  test('sends to the webhook named by DFORGE_NOTIFY_URL alone', async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches, config: { notifyAfter: 0 }, env: { DFORGE_NOTIFY_URL: WEBHOOK } })
    mock.store(on, {})
    await $.session.start(START)
    await $.turn.complete({ answer: 'ok', durationMs: 5_000, isAborted: false, turnId: 't1', reason: 'answer' })
    expect(fetches).toHaveLength(1)
    expect(fetches[0]?.url).toBe(`${WEBHOOK}?wait=true`)
  })

  test('sends to the webhook named by DR_COCKPIT_NOTIFY_URL when DFORGE_NOTIFY_URL is unset', async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches, config: { notifyAfter: 0 }, env: { DR_COCKPIT_NOTIFY_URL: WEBHOOK } })
    mock.store(on, {})
    await $.session.start(START)
    await $.turn.complete({ answer: 'ok', durationMs: 5_000, isAborted: false, turnId: 't1', reason: 'answer' })
    expect(fetches).toHaveLength(1)
    expect(fetches[0]?.url).toBe(`${WEBHOOK}?wait=true`)
  })

  test('prefers DFORGE_NOTIFY_URL over DR_COCKPIT_NOTIFY_URL', async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches, config: { notifyAfter: 0 }, env: { DFORGE_NOTIFY_URL: WEBHOOK, DR_COCKPIT_NOTIFY_URL: 'https://discord.com/api/webhooks/2/old' } })
    mock.store(on, {})
    await $.session.start(START)
    await $.turn.complete({ answer: 'ok', durationMs: 5_000, isAborted: false, turnId: 't1', reason: 'answer' })
    expect(fetches).toHaveLength(1)
    expect(fetches[0]?.url).toBe(`${WEBHOOK}?wait=true`)
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
    'Task 1: implementer dforge:impl-sonnet-low (assigned; base abc1234)',
    'Task 1: complete (commits a..b, review clean) — done: x; verified: y; remaining: none; discovered: none; assumptions: none',
    'Task 2: implementer dforge:impl-sonnet-low (assigned; base def5678)',
    'Task 2: fix round 2/5 (1 addressed, 1 open — meter width; commits c..d; fresh)',
  ].join('\n')
  const PLAN = '# Plan\n\n### Task 1: Add the helpers\n\n### Task 2: Draw the card\n\n### Task 3: Ship it\n'
  const runFiles = (ledger: string): World['files'] => ({
    '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: ledger, mtimeMs: 2_000_000 },
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

  test('reads no task heading inside a fence, as plan.sh does', () => {
    const plan = ['# Plan', '', '````md', '```', '### Task 99: Example', '```', '````', '~~~', '## Task 98: Also an example', '~~~', '#### Task 1: Real', '# Task 2: Top level', '  ### Task 3: Indented'].join('\n')
    expect(planTasks(plan)).toEqual([
      { n: 1, title: 'Real' },
      { n: 2, title: 'Top level' },
    ])
  })

  test('reads a task number only where it ends, as plan.sh does', () => {
    const plan = ['# Plan', '### Task 10x: Not a task', '### Task 7th: Nor this', '### Task 4', '### Task 5. Dotted', '### Task 6 - Dashed'].join('\n')
    expect(planTasks(plan)).toEqual([
      { n: 4, title: '' },
      { n: 5, title: 'Dotted' },
      { n: 6, title: 'Dashed' },
    ])
  })

  test('starts no task from a Ruling, parked or deferred line', () => {
    const ledger = parseLedger(`${LEDGER}\nTask 1: Ruling: the meter — kept\nTask 3: parked — width — Ruling: fine\nTask 4: minor (deferred): rename\nTask 5: escalated inline -> subagent — two rounds`)
    expect(ledger.tasks.map(task => [task.n, task.state])).toEqual([
      [1, 'complete'],
      [2, 'assigned'],
    ])
  })

  test('lists running, blocked and pending tasks before done ones', () => {
    const states = ['complete', 'assigned', 'pending', 'blocked', 'pending', 'complete', 'assigned', 'pending'] as const
    const tasks = states.map((state, i) => ({ n: i + 1, state }))
    expect(runList(tasks, 6).map(task => task.n)).toEqual([2, 7, 4, 3, 5, 8])
    expect(runList(tasks.slice(0, 3), 6).map(task => task.n)).toEqual([2, 3, 1])
  })

  test('replaces the plan card in a dforge run', async ($, on) => {
    const files = runFiles(LEDGER)
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Run' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^round 2\/5$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^1\/3$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers · clean/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /round 2\/5 · impl-sonnet-low/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Task 3: Ship it/ })).toBeDefined()
    const drawn = JSON.stringify(await ui.drawn())
    expect(drawn.indexOf('Task 2: Draw the card')).toBeLessThan(drawn.indexOf('Task 3: Ship it'))
    expect(drawn.indexOf('Task 3: Ship it')).toBeLessThan(drawn.indexOf('Task 1: Add the helpers'))
  })

  test('reads an unchanged ledger no more, however many ticks pass', async ($, on) => {
    const files = runFiles(LEDGER) ?? {}
    const reads: string[] = []
    const clock = world(on, { ...SIGNED_IN, files })
    signedIn(on, files, reads)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    await clock.advance(4_000)
    const ledgerReads = () => reads.filter(path => path.endsWith('/progress.md')).length
    const before = ledgerReads()
    await clock.advance(10_000)
    expect(ledgerReads()).toBe(before)
  })

  test('reads a finished ledger from before the session once', async ($, on) => {
    const files = runFiles(`${LEDGER}\nFinal review: clean (commits a..b)`) ?? {}
    const reads: string[] = []
    const clock = world(on, { ...SIGNED_IN, files, startedAt: 3_000_000 })
    signedIn(on, files, reads)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    await clock.advance(4_000)
    const ledgerReads = () => reads.filter(path => path.endsWith('/progress.md')).length
    const before = ledgerReads()
    await clock.advance(10_000)
    expect(ledgerReads()).toBe(before)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Run' })).toBeUndefined()
  })

  test("reads the ledger after a call naming it, not after one whose content does", async ($, on) => {
    const files = runFiles(LEDGER) ?? {}
    const reads: string[] = []
    world(on, { ...SIGNED_IN, files, isPaneShut: true })
    signedIn(on, files, reads)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const stats = () => reads.filter(path => path.endsWith('/progress.md')).length
    files['/home/me/code/shop/.dforge/sdd/p/progress.md']!.mtimeMs = 2_100_000
    const before = stats()
    await $.tool.call({ tool: 'Write', file_path: '/home/me/notes.md', content: 'see .dforge/sdd/p/progress.md' } as never)
    expect(stats()).toBe(before)
    await $.tool.call({ tool: 'Edit', file_path: '/home/me/code/shop/.dforge/sdd/p/progress.md', old_string: 'a', new_string: 'b' } as never)
    expect(stats()).toBe(before + 1)
  })

  test('reads a plan created after its ledger within one poll tick', async ($, on) => {
    const files: NonNullable<World['files']> = { '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 } }
    const clock = world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    await clock.advance(4_000)
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Run' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Add the helpers/ })).toBeUndefined()
    await ui.unmount()
    files['/home/me/code/shop/docs/plans/p.md'] = { text: PLAN }
    await clock.advance(2_000)
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers · clean/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Task 3: Ship it/ })).toBeDefined()
  })

  test('picks up a ledger change within one poll tick', async ($, on) => {
    const files = runFiles(LEDGER) ?? {}
    const clock = world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    await clock.advance(4_000)
    files['/home/me/code/shop/.dforge/sdd/p/progress.md'] = {
      text: `${LEDGER}\nTask 2: complete (commits c..e, review clean) — done: x; verified: y; remaining: none; discovered: none; assumptions: none`,
      mtimeMs: 2_100_000,
    }
    await clock.advance(2_000)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^2\/3$/ })).toBeDefined()
  })

  test('reads no ledger left under the pre-3.0 .superpowers', async ($, on) => {
    const files: World['files'] = {
      '/home/me/code/shop/.superpowers/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
      '/home/me/code/shop/docs/plans/p.md': { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^round 2\/5$/ })).toBeUndefined()
  })

  test('says a blocked task once, in red and on Discord', async ($, on) => {
    const files = runFiles(LEDGER)
    const fetches: World['fetches'] = []
    world(on, { ...SIGNED_IN, files, fetches })
    signedIn(on, files)
    mock.store(on, { notifyUrl: WEBHOOK })
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    expect(fetches).toHaveLength(0)
    const ledger = files?.['/home/me/code/shop/.dforge/sdd/p/progress.md']
    if (ledger !== undefined) ledger.text += '\nTask 2: BLOCKED — impl exhausted — pick a meter width rule'
    await $.tool.call({ tool: 'Bash', command: 'echo x >> .dforge/sdd/p/progress.md' })
    await $.tool.call({ tool: 'Bash', command: 'cat .dforge/sdd/p/progress.md' })
    expect(fetches).toHaveLength(1)
    expect((fetches[0]?.body.embeds as Record<string, unknown>[])[0]?.title).toBe('🛑 Task 2 blocked')
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^1 blocked$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /BLOCKED · impl exhausted/ })).toBeDefined()
  })

  test("says a second plan's tasks though the first had the same numbers", async ($, on) => {
    const files = { ...runFiles(LEDGER), [CONFIG]: { text: JSON.stringify({ notifyOn: 'task' }) } }
    const fetches: World['fetches'] = []
    world(on, { ...SIGNED_IN, files, fetches })
    signedIn(on, files)
    mock.store(on, { notifyUrl: WEBHOOK })
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const next = '# SDD ledger — plan: docs/plans/q.md\nTask 1: implementer dforge:impl-sonnet-low (assigned; base abc1234)'
    files['/home/me/code/shop/.dforge/sdd/q/progress.md'] = { text: next, mtimeMs: 2_100_000 }
    await $.tool.call({ tool: 'Bash', command: 'cat .dforge/sdd/q/progress.md' })
    files['/home/me/code/shop/.dforge/sdd/q/progress.md'] = { text: `${next}\nTask 1: complete (commits a..b, review clean) — done: x`, mtimeMs: 2_200_000 }
    await $.tool.call({ tool: 'Bash', command: 'cat .dforge/sdd/q/progress.md' })
    expect(fetches.map(one => (one.body.embeds as Record<string, unknown>[])[0]?.title)).toEqual(['✅ Task 1 complete, review clean'])
  })

  test("masks a secret in a blocked task's reason", async ($, on) => {
    const files = runFiles(LEDGER) ?? {}
    const fetches: World['fetches'] = []
    world(on, { ...SIGNED_IN, files, fetches })
    signedIn(on, files)
    mock.store(on, { notifyUrl: WEBHOOK })
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    files['/home/me/code/shop/.dforge/sdd/p/progress.md']!.text += '\nTask 2: BLOCKED — impl exhausted — rotate password=hunter2'
    await $.tool.call({ tool: 'Bash', command: 'cat .dforge/sdd/p/progress.md' })
    expect((fetches[0]?.body.embeds as Record<string, unknown>[])[0]?.description).toBe('impl exhausted — rotate password=[hidden]')
  })

  test('a brief message names no task title and no agent description', async ($, on) => {
    const files = { ...runFiles(LEDGER), [CONFIG]: { text: JSON.stringify({ notifyOn: 'task,agent', notifyDetail: 'brief' }) } }
    const fetches: World['fetches'] = []
    world(on, { ...SIGNED_IN, files, fetches })
    signedIn(on, files)
    mock.store(on, { notifyUrl: WEBHOOK })
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    files['/home/me/code/shop/.dforge/sdd/p/progress.md']!.text += '\nTask 2: complete (commits c..e, review clean) — done: x'
    await $.tool.call({ tool: 'Bash', command: 'cat .dforge/sdd/p/progress.md' })
    await $.agent.spawn({ tool_use_id: 'toolu_1', prompt: 'Implement', description: 'Migrate the billing secrets', subagentType: 'dforge:impl-sonnet-low', provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: true, fork: false })
    await $.turn.complete({ answer: 'ok', durationMs: 1_000, isAborted: false, turnId: 'a1', reason: 'answer', agentId: 'agent-1' })
    const embeds = fetches.map(one => (one.body.embeds as Record<string, unknown>[])[0])
    expect(embeds.map(embed => embed?.title)).toEqual(['✅ Task 2 complete, review clean', '🤖 impl-sonnet-low finished'])
    expect(embeds.map(embed => embed?.description)).toEqual([undefined, undefined])
  })

  test('the desktop band draws its git chips and its blocked and refused warning as rows', async ($, on) => {
    const files = runFiles(`${LEDGER}\nTask 2: BLOCKED — impl exhausted — pick a meter width rule`)
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'cat .dforge/sdd/p/progress.md' })
    await $.tool.call({ tool: 'Bash', command: 'git commit -m "x" -m "Co-Authored-By: Claude <noreply@anthropic.com>"' })
    await $.session.measure(MEASURE)
    const desk = await $.ui.mount({ ...INLINE, surface: 'desktop' })
    // The chips follow the facts row, each on a pill: the branch, then the changes.
    const chips = await desk.find({ key: 'band-rest-1' })
    expect(chips?.props).toMatchObject({ flexDirection: 'row', flexWrap: 'wrap', gap: 'xs' })
    expect(chips?.children).toMatchObject([
      { type: 'Text', props: { color: 'planMode', size: 'caption', backgroundColor: 'subtle' }, children: ['⎇ feat/pane ↑2 ↓1'] },
      { type: 'Text', props: { color: 'warning', size: 'caption', backgroundColor: 'subtle' }, children: ['~1 changed'] },
      { type: 'Text', props: { size: 'caption', backgroundColor: 'subtle' }, children: ['?1 untracked'] },
    ])
    // The warning is one red line below them, its separator dim.
    const warning = await desk.find({ key: 'band-rest-2-left' })
    expect(warning?.text).toBe('✗ Task 2 blocked  ·  ✗ 1 refused')
    expect(JSON.stringify(warning?.children)).toContain('{"type":"Text","props":{"color":"error"},"children":["Task 2 blocked"]}')
    expect(JSON.stringify(warning?.children)).toContain('{"type":"Text","props":{"dimColor":true},"children":["  ·  "]}')
    expect(JSON.stringify(warning?.children)).toContain('{"type":"Text","props":{"color":"error"},"children":["1 refused"]}')
    expect(await desk.find({ key: 'band-rest-3' })).toBeUndefined()
  })

  test('clears a run finished before the session started', async ($, on) => {
    const done = [
      '# SDD ledger — plan: docs/plans/p.md',
      ...[1, 2, 3].map(n => `Task ${n}: complete (commits a..b, review clean) — done: x; verified: y; remaining: none; discovered: none; assumptions: none`),
    ].join('\n')
    const files = runFiles(done)
    world(on, { ...SIGNED_IN, files, startedAt: 3_000_000 })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:brainstorming' })
    await $.session.start(START)
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Run' })).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▸ Run' })).toBeUndefined()
    await ui.unmount()
    // A run still open from before keeps its card.
    const ledger = files?.['/home/me/code/shop/.dforge/sdd/p/progress.md']
    if (ledger !== undefined) ledger.text = LEDGER
    await $.tool.call({ tool: 'Bash', command: 'cat .dforge/sdd/p/progress.md' })
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Run' })).toBeDefined()
  })

  // Five tasks in the 650k window: the handoff budget is 464,500 and the
  // final-phase limit 552,500. A plan's last two tasks and its final phase
  // measure against the latter, as scripts/lib/context.sh's tail does.
  const TAIL_PLAN = `# Plan\n\n${[1, 2, 3, 4, 5].map(n => `### Task ${n}: Step ${n}\n`).join('\n')}`
  const tailLedger = (done: number, isFinished: boolean) =>
    [
      '# SDD ledger — plan: docs/plans/p.md',
      ...Array.from({ length: done }, (_, i) => `Task ${i + 1}: complete (commits a..b, review clean) — done: x; verified: y; remaining: none; discovered: none; assumptions: none`),
      ...(isFinished ? ['Final review: clean (commits a..b)'] : []),
    ].join('\n')

  test('a run is at its tail with two tasks left or fewer, or once its final review is clean', () => {
    expect(isPlanTail({ done: 2, total: 5, isFinished: false })).toBe(false)
    expect(isPlanTail({ done: 3, total: 5, isFinished: false })).toBe(true)
    expect(isPlanTail({ done: 5, total: 5, isFinished: false })).toBe(true)
    expect(isPlanTail({ done: 0, total: 0, isFinished: false })).toBe(false)
    expect(isPlanTail({ done: 0, total: 0, isFinished: true })).toBe(true)
  })

  for (const [name, done, isFinished, tokens, note] of [
    ['three tasks left', 2, false, 500_000, /^dforge: budget: 500k of 465k — handoff\. /],
    ['two tasks left', 3, false, 500_000, null],
    ['every task complete', 5, false, 500_000, null],
    ['the final review clean', 5, true, 500_000, null],
    ['two tasks left, past the final-phase limit', 3, false, 560_000, /^dforge: budget: 560k of 553k — handoff\. /],
  ] as const) {
    test(`the handoff note with ${name} at ${tokens / 1000}k`, async ($, on) => {
      const notes: string[] = []
      const files: World['files'] = {
        '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: tailLedger(done, isFinished), mtimeMs: 2_000_000 },
        '/home/me/code/shop/docs/plans/p.md': { text: TAIL_PLAN },
      }
      world(on, { ...SIGNED_IN, tokens, notes, files })
      signedIn(on, files)
      // The session start reads the ledger; the Skill call makes it a plan session.
      await $.session.start(START)
      await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
      const sent = notes.filter(text => /— handoff\./.test(text))
      if (note === null) expect(sent).toEqual([])
      else expect(sent).toEqual([expect.stringMatching(note)])
    })
  }

  test('a ledger write that reaches the tail is read before the budget in the same call', async ($, on) => {
    const notes: string[] = []
    const files: World['files'] = {
      '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: tailLedger(2, false), mtimeMs: 2_000_000 },
      '/home/me/code/shop/docs/plans/p.md': { text: TAIL_PLAN },
    }
    const w: World = { ...SIGNED_IN, tokens: 400_000, notes, files }
    world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    // One call both completes Task 3 (two tasks left) and crosses the 465k budget.
    files['/home/me/code/shop/.dforge/sdd/p/progress.md'] = { text: tailLedger(3, false), mtimeMs: 2_100_000 }
    w.tokens = 500_000
    await $.tool.call({ tool: 'Bash', command: 'echo "Task 3: complete" >> .dforge/sdd/p/progress.md' })
    expect(notes.filter(text => /— handoff\./.test(text))).toEqual([])
  })

  test('a recorded finish choice starts no once-a-second redraw', async ($, on) => {
    const files = {
      ...runFiles(LEDGER),
      '/home/me/code/shop/.dforge/sdd/p/finish.json': { text: '{"action":"merge","base":"main","chosenAt":900,"armedAt":1000,"dueAt":2800}' },
    }
    let redraws = 0
    const clock = world(on, { ...SIGNED_IN, files })
    on('ui.invalidate', () => {
      redraws++
      return { value: undefined } as never
    })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    await clock.advance(5_000)
    expect(redraws).toBe(0)
    // A live turn does tick: the count above would have seen a ticker.
    await $.turn.start({ text: 'go', turnId: 't1' })
    await clock.advance(2_000)
    expect(redraws).toBeGreaterThan(0)
  })

  test('reads the finish choice', () => {
    const chosen = parseFinish('{"action":"pr","base":"main","chosenAt":900}')
    expect(chosen).toEqual({ action: 'pr', base: 'main', answer: null })
    expect(parseFinish('{"action":"merge","base":"main","chosenAt":900,"armedAt":1000,"dueAt":2800,"job":"cron-7","firedAt":2800}')).toEqual({ action: 'merge', base: 'main', answer: null })
    expect(parseFinish('{"action":"later"}')).toBeNull()
    expect(parseFinish('{broken')).toBeNull()
    if (chosen === null) return
    expect(runsText(finishLine(chosen))).toBe('Finish push and open a PR when done')
    expect(runsText(finishLine({ ...chosen, action: 'merge' }))).toBe('Finish merge into main when done')
    expect(runsText(finishLine({ ...chosen, action: 'merge', base: null }))).toBe('Finish merge into the base branch when done')
    expect(runsText(finishLine({ ...chosen, action: 'keep' }))).toBe('Finish keep the branch when done')
    expect(runsText(finishLine({ ...chosen, action: 'wait' }))).toBe('Finish ask me when done')
    expect(finishLine({ ...chosen, answer: 'keep' })).toEqual([])
  })

  test('shows the finish choice on the Run card', async ($, on) => {
    const files = {
      ...runFiles(LEDGER),
      '/home/me/code/shop/.dforge/sdd/p/finish.json': { text: '{"action":"pr","base":"main","chosenAt":900,"armedAt":1000,"dueAt":2800}' },
    }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    // A file an older version armed shows the choice, with no countdown.
    expect(await ui.find({ type: 'Text', text: /Finish push and open a PR when done/ })).toBeDefined()
    expect(JSON.stringify(await ui.drawn())).not.toContain('⏱')
  })

  test('shows the finish choice for work without a plan or a todo list', async ($, on) => {
    const files = { '/home/me/code/shop/.dforge/sdd/finish.json': { text: '{"action":"pr","base":"main","chosenAt":900,"armedAt":1000,"dueAt":2800}' } }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Finish push and open a PR when done/ })).toBeDefined()
    await ui.unmount()
    const desk = await $.ui.mount({ ...PANE, surface: 'desktop' })
    const drawn = JSON.stringify(await desk.drawn())
    expect(drawn).toContain('Finish push and open a PR when done')
    expect(drawn).not.toContain('⏱')
  })

  test('offers no Resume for a handoff left under the pre-3.0 .superpowers', async ($, on) => {
    const files: World['files'] = { '/home/me/code/shop/.superpowers/handoff/latest.md': { text: RESUMABLE, mtimeMs: 900_000 } }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ key: 'pane-resume' })).toBeUndefined()
  })

  test('offers Resume for a handoff under .dforge', async ($, on) => {
    const files: World['files'] = { '/home/me/code/shop/.dforge/handoff/latest.md': { text: RESUMABLE, mtimeMs: 900_000 } }
    const prompts: string[] = []
    world(on, { ...SIGNED_IN, files, prompts })
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ key: 'pane-resume' })).toBeDefined()
    await ui.press({ key: 'pane-resume' })
    expect(prompts).toEqual([expect.stringContaining('.dforge/handoff/latest.md')])
  })
})

describe('resume offer', () => {
  const LATEST = '/home/me/code/shop/.dforge/handoff/latest.md'
  const COMPACT = configured({ layout: 'compact' })
  const start = async ($: Parameters<TestBody>[0], on: On, text: string, more: World['files'] = {}, mtimeMs = 900_000) => {
    const files: World['files'] = { [LATEST]: { text, mtimeMs }, ...more }
    const prompts: string[] = []
    world(on, { ...SIGNED_IN, files, prompts })
    signedIn(on, files)
    await $.session.start(START)
    return prompts
  }

  test('reads the next action of a handoff that has a first prompt', () => {
    expect(resumeOfferOf(RESUMABLE)).toEqual({ next: 'Task 4 — wire the band into the pane.' })
  })

  test('says a handoff under a minute old was just handed off', () => {
    expect(handedOff(59_999)).toBe('handed off just now')
    expect(handedOff(100_000)).toBe('handed off 1m ago')
  })

  test('reads no offer from a finished, blocked or bare handoff', () => {
    expect(resumeOfferOf(FINISHED)).toBeNull()
    expect(resumeOfferOf(BLOCKED)).toBeNull()
    expect(resumeOfferOf('# Handoff')).toBeNull()
  })

  test('reads no offer from a first prompt outside the Next session block', () => {
    expect(resumeOfferOf(`${FINISHED}\n## Notes\n\nPaste as the first prompt:\n\n\`\`\`\nold\n\`\`\`\n`)).toBeNull()
  })

  test('draws a resume card at the top of the pane', async ($, on) => {
    await start($, on, RESUMABLE)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ key: 'resume-card' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Resumable work · handed off 1m ago/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Next: Task 4 — wire the band into the pane\./ })).toBeDefined()
    expect(await ui.find({ key: 'pane-resume' })).toBeDefined()
  })

  for (const surface of SURFACES) {
    test(`draws the resume band above the prompt on ${surface}, the pane open`, async ($, on) => {
      await start($, on, RESUMABLE)
      const band = await $.ui.mount({ ...BAND, surface })
      expect(await band.find({ key: 'band-resume' })).toBeDefined()
      expect(await band.find({ key: 'band-resume-dismiss' })).toBeDefined()
      expect(await band.find({ type: 'Text', text: /Resumable work · handed off 1m ago/ })).toBeDefined()
      expect(await band.find({ key: 'band-expand' })).toBeUndefined()
    })

    test(`stacks the resume band on the minimized band on ${surface}`, async ($, on) => {
      await start($, on, RESUMABLE, COMPACT)
      const band = await $.ui.mount({ ...BAND, surface })
      expect(await band.find({ key: 'band-resume' })).toBeDefined()
      const site = await $.ui.mount(minimized(surface))
      expect(await site.find({ key: 'band-expand' })).toBeDefined()
    })
  }

  for (const [name, text] of [['finished', FINISHED], ['blocked', BLOCKED]] as const) {
    test(`offers nothing for a ${name} plan`, async ($, on) => {
      await start($, on, text)
      const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
      const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
      expect(await ui.find({ key: 'pane-resume' })).toBeUndefined()
      expect(await band.find({ key: 'band-resume' })).toBeUndefined()
    })
  }

  test('offers nothing for a handoff older than three days', async ($, on) => {
    await start($, on, RESUMABLE, {}, 1_000_000 - 3 * 86_400_000 - 1)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await ui.find({ key: 'pane-resume' })).toBeUndefined()
    expect(await band.find({ key: 'band-resume' })).toBeUndefined()
  })

  test('offers nothing once the session runs a plan', async ($, on) => {
    await start($, on, RESUMABLE)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await band.find({ key: 'band-resume' })).toBeUndefined()
  })

  test('leaves the slot above the prompt to a survey', async ($, on) => {
    await start($, on, RESUMABLE)
    const band = await $.ui.mount({ ...BAND, props: { ...BAND.props, hasSurvey: true }, surface: 'terminal' })
    expect(await band.find({ key: 'band-resume' })).toBeUndefined()
  })

  test("the band's Resume submits the resume prompt and removes the offer", async ($, on) => {
    const prompts = await start($, on, RESUMABLE)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    await band.press({ key: 'band-resume' })
    expect(prompts).toEqual([expect.stringContaining('resume-execution')])
    expect(await band.find({ key: 'band-resume' })).toBeUndefined()
    expect(await ui.find({ key: 'resume-card' })).toBeUndefined()
  })

  test("the pane's Resume removes the band too", async ($, on) => {
    const prompts = await start($, on, RESUMABLE)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    await ui.press({ key: 'pane-resume' })
    expect(prompts).toHaveLength(1)
    expect(await band.find({ key: 'band-resume' })).toBeUndefined()
    expect(await ui.find({ key: 'pane-resume' })).toBeUndefined()
  })

  test('Dismiss removes the offer without a prompt', async ($, on) => {
    const prompts = await start($, on, RESUMABLE)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    await band.press({ key: 'band-resume-dismiss' })
    expect(prompts).toEqual([])
    expect(await band.find({ key: 'band-resume' })).toBeUndefined()
    expect(await ui.find({ key: 'resume-card' })).toBeUndefined()
  })
})

describe('cockpit roots', () => {
  const MIRROR = '/home/me/.dforge/mirror/shop'
  const MODE = [
    `documents\tdarkmem\t${MIRROR}/superpowers`,
    `progress\tdarkmem\t${MIRROR}/work/sdd\t${MIRROR}/work/handoff/latest.md`,
    'project\tshop',
    '',
  ].join('\n')
  const LEDGER = '# SDD ledger — plan: docs/superpowers/plans/p.md\nTask 1: implementer dforge:impl-sonnet-low (assigned; base abc1234)\n'
  const PLAN = '# Plan\n\n### Task 1: Add the helpers\n\n### Task 2: Draw the card\n'
  // darkmem-config runs only once one of the ~/.dforge files exists.
  const storesFile = (): NonNullable<World['files']> => ({ '/home/me/.dforge/stores.json': { text: '{}', mtimeMs: 1 } })
  const checkoutFiles = (): NonNullable<World['files']> => ({
    ...storesFile(),
    '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
    '/home/me/code/shop/docs/dforge/plans/p.md': { text: PLAN },
  })

  test('reads the roots --mode prints', () => {
    expect(parseModeLines(MODE)).toEqual({
      docs: { store: 'darkmem', root: `${MIRROR}/superpowers` },
      progress: { store: 'darkmem', ledgerRoot: `${MIRROR}/work/sdd`, latestFile: `${MIRROR}/work/handoff/latest.md` },
      project: 'shop',
    })
    expect(parseModeLines('documents\tlocal\t/r/docs/dforge\nprogress\tlocal\t/r/.dforge/sdd\t/r/.dforge/handoff/latest.md\n')?.project).toBeNull()
    expect(parseModeLines(PORCELAIN)).toBeNull()
    expect(parseModeLines('documents\tlocal\t/r/docs/dforge\n')).toBeNull()
    expect(parseModeLines('documents\telsewhere\t/r\nprogress\tlocal\t/a\t/b\n')).toBeNull()
  })

  test('a failing --mode keeps the checkout paths and says why', async ($, on) => {
    const files = checkoutFiles()
    const stderr = 'darkmem-config: /home/me/.dforge/stores.json is not valid JSON: Unexpected token\nat line 2\n'
    world(on, { ...SIGNED_IN, files, modeOut: { exitCode: 2, stdout: '', stderr } })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^darkmem-config: \/home\/me\/\.dforge\/stores\.json is not valid JSON: Unexpected token$/ })).toBeDefined()
    await ui.unmount()
    const desk = await $.ui.mount({ ...PANE, surface: 'desktop' })
    expect(JSON.stringify(await desk.drawn())).toContain('stores.json is not valid JSON')
  })

  test('without node the checkout paths stay silently', async ($, on) => {
    const files = checkoutFiles()
    world(on, { ...SIGNED_IN, files, modeOut: 'missing' })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
    expect(await ui.find({ key: 'plan-roots' })).toBeUndefined()
  })

  for (const [name, modeOut] of [
    ['a run that fails at once without naming node', 'rejects'],
    ['an exit 127', { exitCode: 127, stdout: '', stderr: 'sh: 1: node: not found\n' }],
  ] as const) {
    test(`${name} keeps the checkout paths silently`, async ($, on) => {
      const files = checkoutFiles()
      world(on, { ...SIGNED_IN, files, modeOut })
      signedIn(on, files)
      await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
      await $.session.start(START)
      const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
      expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
      expect(JSON.stringify(await ui.drawn())).not.toMatch(/gave no answer|exited 127|not found/)
    })
  }

  test('a run the engine stops at its timeout says it gave no answer', async ($, on) => {
    const files = checkoutFiles()
    world(on, { ...SIGNED_IN, files, modeOut: 'timeout' })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /darkmem-config\.mjs --mode gave no answer within 5 seconds/ })).toBeDefined()
  })

  test('a run that prints no mode lines keeps the checkout paths silently', async ($, on) => {
    const files = checkoutFiles()
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, modeRuns })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(modeRuns).toEqual(['/home/me/code/shop'])
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
    expect(await ui.find({ key: 'plan-roots' })).toBeUndefined()
  })

  test('reads the roots once per stores.json change, re-read from a mirror path', async ($, on) => {
    const files: NonNullable<World['files']> = { ...checkoutFiles(), '/home/me/.dforge/stores.json': { text: '{}', mtimeMs: 1 } }
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, modeRuns })
    signedIn(on, files)
    await $.session.start(START)
    expect(modeRuns).toEqual(['/home/me/code/shop'])
    await $.tool.call({ tool: 'Bash', command: 'cat ~/.dforge/mirror/shop/work/sdd/p/progress.md' })
    expect(modeRuns).toHaveLength(1)
    files['/home/me/.dforge/stores.json']!.mtimeMs = 2
    await $.tool.call({ tool: 'Bash', command: 'cat ~/.dforge/mirror/shop/work/sdd/p/progress.md' })
    expect(modeRuns).toEqual(['/home/me/code/shop', '/home/me/code/shop'])
  })

  test('reads the roots again when ~/.dforge/config.json changes', async ($, on) => {
    const files: NonNullable<World['files']> = { ...checkoutFiles(), [CONFIG]: { text: '{}', mtimeMs: 1 } }
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, modeRuns })
    signedIn(on, files)
    await $.session.start(START)
    expect(modeRuns).toEqual(['/home/me/code/shop'])
    await $.tool.call({ tool: 'Bash', command: 'cat ~/.dforge/config.json' })
    expect(modeRuns).toHaveLength(1)
    files[CONFIG]!.mtimeMs = 2
    await $.tool.call({ tool: 'Bash', command: 'cat ~/.dforge/config.json' })
    expect(modeRuns).toHaveLength(2)
  })

  test('a --mode failure that names a missing file is shown, not taken for a missing node', async ($, on) => {
    const files = checkoutFiles()
    const stderr = "darkmem-config: ENOENT: no such file or directory, open '/home/me/.dforge/mirror/shop/.sync-state.json'\n"
    world(on, { ...SIGNED_IN, files, modeOut: { exitCode: 1, stdout: '', stderr } })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^darkmem-config: ENOENT: no such file or directory/ })).toBeDefined()
  })

  test('a run that timed out is tried again at the next read', async ($, on) => {
    const files = checkoutFiles()
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, modeRuns, modeOut: 'timeout' })
    signedIn(on, files)
    await $.session.start(START)
    expect(modeRuns).toHaveLength(1)
    await $.tool.call({ tool: 'Bash', command: 'cat .dforge/sdd/p/progress.md' })
    expect(modeRuns).toHaveLength(2)
  })

  test('runs no node while neither ~/.dforge/config.json nor stores.json exists', async ($, on) => {
    const files: NonNullable<World['files']> = {
      '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
      '/home/me/code/shop/docs/dforge/plans/p.md': { text: PLAN },
    }
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, modeRuns })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    expect(modeRuns).toEqual([])
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
  })

  test('resolves a plan under the docs root in darkmem, under the docs directory of each checkout otherwise', () => {
    const darkmem = { store: 'darkmem' as const, root: `${MIRROR}/superpowers` }
    const w = { root: '/w', docsDir: '/w/docs/dforge' }
    const p = { root: '/p', docsDir: '/p/docs/dforge' }
    for (const name of ['docs/superpowers/plans/p.md', 'docs/forge/plans/p.md', 'docs/dforge/plans/p.md', './docs/dforge/plans/p.md']) {
      expect(planCandidates(name, darkmem, [w, p])).toEqual([`${MIRROR}/superpowers/plans/p.md`])
      // Every prefix names the same document: an older citation reads under each checkout's docs/dforge.
      expect(planCandidates(name, { store: 'local', root: '/p/docs/dforge' }, [w, p])).toEqual(['/w/docs/dforge/plans/p.md', '/p/docs/dforge/plans/p.md'])
      expect(planCandidates(name, null, [p, p])).toEqual(['/p/docs/dforge/plans/p.md'])
    }
    expect(planCandidates('docs/plans/p.md', null, [w, p])).toEqual(['/w/docs/plans/p.md', '/p/docs/plans/p.md'])
    expect(planCandidates('/abs/plans/p.md', darkmem, [w])).toEqual(['/abs/plans/p.md'])
    expect(planCandidates('docs/superpowersx/p.md', darkmem, [w])).toEqual(['/w/docs/superpowersx/p.md'])
    expect(planCandidates('docs/forgex/p.md', darkmem, [w])).toEqual(['/w/docs/forgex/p.md'])
  })

  test('reads a plan named under docs/superpowers from a checkout that has only docs/dforge', async ($, on) => {
    const files: World['files'] = {
      '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
      '/home/me/code/shop/docs/dforge/plans/p.md': { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 2: Draw the card/ })).toBeDefined()
  })

  test('reads no plan from a pre-3.0 docs/superpowers directory', async ($, on) => {
    const files: World['files'] = {
      '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: LEDGER.replace('docs/superpowers', 'docs/dforge'), mtimeMs: 2_000_000 },
      '/home/me/code/shop/docs/superpowers/plans/p.md': { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 2: Draw the card/ })).toBeUndefined()
  })

  test('reads the ledger and the plan from the mirror when both families are in darkmem', async ($, on) => {
    const files: World['files'] = {
      ...storesFile(),
      [`${MIRROR}/work/sdd/p/progress.md`]: { text: LEDGER, mtimeMs: 2_000_000 },
      [`${MIRROR}/superpowers/plans/p.md`]: { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files, modeOut: { exitCode: 0, stdout: MODE, stderr: '' } })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Run' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Task 2: Draw the card/ })).toBeDefined()
    expect(await ui.find({ key: 'plan-roots' })).toBeUndefined()
  })

  test('offers Resume for latest.md in the mirror, naming it', async ($, on) => {
    const files: World['files'] = { ...storesFile(), [`${MIRROR}/work/handoff/latest.md`]: { text: RESUMABLE, mtimeMs: 900_000 } }
    const prompts: string[] = []
    world(on, { ...SIGNED_IN, files, prompts, modeOut: { exitCode: 0, stdout: MODE, stderr: '' } })
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-resume' })
    expect(prompts).toEqual([expect.stringContaining(`${MIRROR}/work/handoff/latest.md`)])
  })

  test("reads finish.json and a local plan from the session's worktree before the primary", async ($, on) => {
    const files: World['files'] = {
      '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
      '/home/me/code/main/.dforge/sdd/p/finish.json': { text: '{"action":"merge","base":"main","chosenAt":900}' },
      '/home/me/code/main/docs/dforge/plans/p.md': { text: '# Plan\n\n### Task 1: Old title\n' },
      '/home/me/code/shop/.dforge/sdd/p/finish.json': { text: '{"action":"pr","base":"main","chosenAt":900}' },
      '/home/me/code/shop/docs/dforge/plans/p.md': { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files, primary: '/home/me/code/main' })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Finish push and open a PR/ })).toBeDefined()
  })

  test('takes the primary checkout from the common directory, as the scripts do', async ($, on) => {
    // stores.json makes the cockpit ask darkmem-config for the primary's roots.
    const files: NonNullable<World['files']> = { '/home/me/.dforge/stores.json': { text: '{}', mtimeMs: 1 } }
    const gitRuns: string[] = []
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, primary: '/home/me/code/main', gitRuns, modeRuns })
    signedIn(on, files)
    await $.session.start(START)
    expect(gitRuns).toContain('git -C /home/me/code/main rev-parse --show-toplevel')
    // The roots are the linked worktree's, as sdd-workspace resolves them there.
    expect(modeRuns).toEqual(['/home/me/code/shop'])
  })

  test("reads a linked worktree's own ledger, not the primary checkout's", async ($, on) => {
    const files: World['files'] = {
      '/home/me/code/main/.dforge/sdd/q/progress.md': { text: LEDGER.replace('p.md', 'q.md'), mtimeMs: 2_500_000 },
      '/home/me/code/main/docs/dforge/plans/q.md': { text: '# Plan\n\n### Task 1: Primary task\n' },
      '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
      '/home/me/code/shop/docs/dforge/plans/p.md': { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files, primary: '/home/me/code/main' })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Primary task/ })).toBeUndefined()
  })

  test('a submodule has no primary checkout, as in the scripts', async ($, on) => {
    const files: NonNullable<World['files']> = { '/home/me/.dforge/stores.json': { text: '{}', mtimeMs: 1 } }
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, commonDir: '/home/me/code/shop/.git/modules/web', modeRuns })
    signedIn(on, files)
    await $.session.start(START)
    // With no primary, the session's own repository stands in.
    expect(modeRuns).toEqual(['/home/me/code/shop'])
  })

  test('a changed stores.json moves the card to the new roots', async ($, on) => {
    const files: NonNullable<World['files']> = {
      '/home/me/.dforge/stores.json': { text: '{}', mtimeMs: 1 },
      [`${MIRROR}/work/sdd/p/progress.md`]: { text: LEDGER, mtimeMs: 2_000_000 },
      [`${MIRROR}/superpowers/plans/p.md`]: { text: PLAN },
    }
    const w: World = { ...SIGNED_IN, files }
    world(on, w)
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Run' })).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▸ Run' })).toBeUndefined()
    await ui.unmount()
    w.modeOut = { exitCode: 0, stdout: MODE, stderr: '' }
    files['/home/me/.dforge/stores.json']!.mtimeMs = 2
    await $.tool.call({ tool: 'Bash', command: 'cat ~/.dforge/stores.json' })
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Run' })).toBeDefined()
  })
})

describe('flight deck', () => {
  test('draws every panel the way the approved preview does', async ($, on) => {
    const ledger = [
      '# SDD ledger — plan: docs/plans/cockpit.md',
      'Task 3: implementer dforge:impl-sonnet-low (assigned; base abc1234)',
      'Task 3: complete (commits a..b, review clean) — done: x; verified: y; remaining: none; discovered: none; assumptions: none',
      'Task 4: implementer dforge:impl-sonnet-low (assigned; base def5678)',
      'Task 4: fix round 2/5 (1 addressed, 1 open — meter width; commits c..d; fresh)',
      'Task 5: BLOCKED — needs the ledger format',
    ].join('\n')
    const now = 1_000_000
    const files: World['files'] = {
      '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: ledger, mtimeMs: now },
      '/home/me/code/shop/docs/plans/cockpit.md': { text: '# Plan\n\n### Task 1: Read the budget\n\n### Task 2: Draw the strip\n\n### Task 3: Draw the context section\n\n### Task 4: Draw usage and agents\n\n### Task 5: Track the plan and repo\n\n### Task 6: Write the README\n' },
    }
    const w: World = { ...SIGNED_IN, files, remoteControl: 'true' }
    world(on, w)
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    for (const [i, t] of [180_000, 205_000, 228_000, 251_000, 270_000, 284_000].entries()) { w.tokens = t; await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: `turn-${i}`, reason: 'answer' }) }
    await $.session.measure({ context: { tokens: 284_000, window: 650_000 }, rateLimits: [{ kind: 'five_hour', percentUsed: 23, resetsAt: new Date(1_000_000 + 220 * 60_000).toISOString() }, { kind: 'seven_day', percentUsed: 61, resetsAt: new Date(1_000_000 + 86 * 3600_000).toISOString() }], cost: { usd: 4.85 }, changed: ['context', 'rateLimits'], breakdown: true } as never)
    w.tools = { Bash: () => ({ result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: `b${Math.random()}` }, text: 'Running in the background' }) }
    await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true } as never)
    await $.tool.call({ tool: 'Bash', command: 'pytest -x --watch', run_in_background: true } as never)
    w.tools = {}
    await $.tool.call({ tool: 'Bash', command: 'git commit -m "fix" -m "Co-Authored-By: Claude <noreply@anthropic.com>"' })
    await $.agent.spawn({ tool_use_id: 'toolu_1', prompt: 'Implement task 3', description: 'Review task 3', subagentType: 'dforge:judge-opus', provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: false, fork: false })
    await $.turn.complete({ answer: 'done', durationMs: 1000, isAborted: false, turnId: 'turn-9', agentId: 'agent-1', reason: 'answer', usage: { model: 'claude-opus-5-5', input_tokens: 4_000, cache_read_input_tokens: 46_000, cache_creation_input_tokens: 14_000, output_tokens: 3_000 } })
    await $.agent.spawn({ tool_use_id: 'toolu_2', prompt: 'Implement task 4', description: 'Task 4', subagentType: 'dforge:impl-sonnet-low', provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: false, fork: false })
    const ui = await $.ui.mount({ ...PANE, props: { ...PANE.props, bodyColumns: 46, scroll: { offset: 0, bodyRows: 300 } }, surface: 'desktop' })
    const drawn = JSON.stringify(await ui.drawn())
    // The gauge tiles split each row by share and wrap when the dials won't
    // fit, so they always span the same width as the panels.
    const tileRows = async (bodyColumns: number) => {
      const mounted = await $.ui.mount({ ...PANE, props: { ...PANE.props, bodyColumns, scroll: { offset: 0, bodyRows: 300 } }, surface: 'desktop' })
      type Node = { props?: { key?: string; width?: number; flexGrow?: number }; children?: Node[] }
      const all: Node[] = []
      const walk = (node: Node) => (all.push(node), node.children?.forEach(walk))
      walk((await mounted.drawn()) as Node)
      await mounted.unmount()
      return all
        .filter(node => /^gauges-\d+$/.test(node.props?.key ?? ''))
        .map(row => (row.children ?? []).map(tile => `${tile.props?.key?.slice(6)}:${tile.props?.width}/${tile.props?.flexGrow}`))
    }
    // The gauges are one drawing per tile: context against the handoff, then
    // each window with its reset and forecast; figures take the page's tone.
    expect(drawn).toContain('of handoff · ≈')
    expect(drawn).toContain('5h limit 23% used, resets 3h40m, on pace')
    expect(drawn).toMatch(/7d limit 61% used, resets 3d14h, out in /)
    expect(drawn).toContain('class=\\"fg\\">23%</text>')
    // Panels sit on a soft fill, a row apart; their rows, chips and bars are
    // one drawing each that takes the page's light or dark tones.
    expect(drawn).toStartWith('{"type":"Box","props":{"flexDirection":"column","gap":"md"}')
    expect(drawn).toContain('"key":"usage","flexDirection":"column","borderStyle":"round","borderColor":"subtle","backgroundColor":"#8080800f","paddingX":"md","paddingY":"sm","gap":"xs"')
    expect(drawn).toContain('@media (prefers-color-scheme: dark)')
    // Titles, rows and pills are the desktop's own text in theme colors.
    expect((await ui.find({ key: 'usage-title' }))?.children[0]).toMatchObject({ type: 'Text', props: { size: 'heading', weight: 'semibold', color: 'suggestion' }, children: ['▾ Usage'] })
    expect(drawn).toContain('{"type":"Text","props":{"color":"suggestion","size":"caption","backgroundColor":"subtle"},"children":["Opus 5.5"]}')
    for (const chip of ['xhigh effort', 'Remote ○ on · no device yet', 'config ~/.claude']) expect(drawn).toContain(`"children":["${chip}"]`)
    // No picture stands in for a panel's rows; the gauges stay pictures.
    const alts = (await ui.findAll({ type: 'Svg' })).map(one => String(one.props.alt))
    for (const alt of alts) expect(alt).not.toMatch(/Opus 5\.5|npm run dev|judge-opus|Task 4|feat\/pane|running/)
    expect(alts).toContain('5h limit 23% used, resets 3h40m, on pace')
    // A badge row holds its picture beside its lines; a small row is a
    // footnote, a wrapped one wraps, and an indent is counted in cells.
    expect((await ui.find({ key: 'account-line-0' }))?.children[0]).toMatchObject({ type: 'Svg' })
    expect(drawn).toContain('"size":"footnote","wrap":"wrap"')
    expect(drawn).toContain('"columnGap":"sm","paddingLeft":2}')
    // Usage leaves the windows to their gauges and says what the ticks mean.
    expect(drawn).toContain("The gauges' ticks mark how far each window has run: 27% of 5h, 49% of 7d.")
    expect(drawn).not.toContain('of the window gone')
    expect((await ui.find({ key: 'shells-headline' }))?.text).toBe('2 running')
    expect((await ui.find({ key: 'shells-line-0-left' }))?.text).toBe('$ npm run dev')
    expect((await ui.find({ key: 'shells-line-0-right' }))?.text).toBe('0s')
    // Each seat's counts sit on a row above its bar, with no title or caption.
    expect(await boxTexts(ui)).toContain('judge-opus ×1')
    expect(await boxTexts(ui)).toContain('64k in · 72% cached · 3k out')
    expect(drawn).not.toContain('Seats by input')
    expect(drawn).not.toContain('prompt cache.')
    // The window's labels slide clear of each other rather than drop out.
    expect(drawn).toContain('>compacts 604k</text>')
    expect(drawn).toContain('>handoff 465k</text>')
    expect(drawn).toContain('+14k · 7 turns</text>')
    expect((await ui.find({ key: 'plan-headline' }))?.text).toBe('1 blocked · round 2/5 · 1/6')
    expect(drawn).toContain('round 2/5 · impl-sonnet-low')
    // The buttons stay the desktop's own.
    expect(await ui.find({ key: 'pane-handoff' })).toBeDefined()
    await ui.unmount()
    expect(await tileRows(80)).toEqual([['Context:0/1.35', '5h:0/1', '7d:0/1']])
    expect(await tileRows(46)).toEqual([['Context:0/1.35'], ['5h:0/1', '7d:0/1']])
    expect(await tileRows(30)).toEqual([['Context:0/1.35'], ['5h:0/1'], ['7d:0/1']])
  })
})

describe('settings file', () => {
  const FAKE: Schema = {
    layout: { type: 'enum', values: ['auto', 'full', 'compact'], default: 'auto', group: 'Cockpit', label: 'Layout', title: 'Layout', description: 'd', target: 'dforge' },
    warnAt: { type: 'number', default: 80, min: 1, max: 99, group: 'Context', label: 'Warn at', title: 'Warn', description: 'd', target: 'dforge' },
    handoffTokens: { type: 'number', default: 0, min: 0, max: 2_000_000, env: 'DFORGE_BUDGET', group: 'Context', label: 'Handoff budget', title: 'Budget', description: 'd', target: 'dforge' },
    nudgeModel: { type: 'boolean', default: true, group: 'Context', label: 'Handoff note', title: 'Nudge', description: 'd', target: 'dforge' },
  }

  test('resolves the environment, then the file, then the default', () => {
    expect(resolveSettings(FAKE, { layout: 'full', warnAt: 500, handoffTokens: 300_000 }, { DFORGE_BUDGET: '400000' })).toEqual({
      layout: 'full',
      warnAt: 80,
      handoffTokens: 400_000,
      nudgeModel: true,
    })
  })

  test('ignores an environment value that does not fit', () => {
    expect(resolveSettings(FAKE, { handoffTokens: 300_000 }, { DFORGE_BUDGET: 'junk' }).handoffTokens).toBe(300_000)
  })

  test('says which values it ignored', () => {
    expect(settingProblems(FAKE, { warnAt: 500, layout: 'full' }, { DFORGE_BUDGET: 'junk' })).toEqual([
      'warnAt in ~/.dforge/config.json is not valid; ignored',
      'DFORGE_BUDGET=junk is not a valid handoffTokens; ignored',
    ])
    expect(settingProblems(FAKE, { layout: 'full' }, {})).toEqual([])
  })

  test('an invalid notifyOn sends nothing rather than the default set', () => {
    expect(resolveSettings(SCHEMA, { notifyOn: 'off' }, {}).notifyOn).toBe('none')
    expect(resolveSettings(SCHEMA, { notifyOn: 3 }, {}).notifyOn).toBe('none')
    expect(resolveSettings(SCHEMA, {}, {}).notifyOn).toBe('')
    expect(resolveSettings(SCHEMA, { notifyOn: 'ask,done' }, {}).notifyOn).toBe('ask,done')
    expect(settingProblems(SCHEMA, { notifyOn: 'off' }, {})).toEqual(['notifyOn in ~/.dforge/config.json is not valid; read as none'])
  })

  test('a list naming an unknown name keeps the names it knows', () => {
    expect(resolveSettings(SCHEMA, { sections: 'plan, typo,Context' }, {}).sections).toBe('plan,context')
    expect(resolveSettings(SCHEMA, { collapsed: 'repo usage bogus' }, {}).collapsed).toBe('repo,usage')
    expect(resolveSettings(SCHEMA, { sections: 'typo' }, {}).sections).toBe('')
    expect(resolveSettings(SCHEMA, { notifyOn: 'ask,typo' }, {}).notifyOn).toBe('ask')
    expect(settingProblems(SCHEMA, { sections: 'plan,typo', collapsed: 'nope bad repo' }, {})).toEqual([
      'sections in ~/.dforge/config.json: unknown typo ignored',
      'collapsed in ~/.dforge/config.json: unknown nope, bad ignored',
    ])
    expect(settingProblems(SCHEMA, { sections: 'typo' }, {})).toEqual(['sections in ~/.dforge/config.json is not valid; ignored'])
  })

  test('a saved value drops its default and keeps darkmem', () => {
    const darkmem = { url: 'http://d.test', repos: {} }
    expect(settingWritten(FAKE, { darkmem, warnAt: 70 }, 'warnAt', 80)).toEqual({ darkmem })
    expect(settingWritten(FAKE, { darkmem }, 'layout', 'compact')).toEqual({ darkmem, layout: 'compact' })
  })

  test('a keepDefault key is saved even at its default', () => {
    const KEEP: Schema = { on: { type: 'boolean', default: false, keepDefault: true, group: 'darkmem', label: 'On', title: 'On', description: 'd', target: 'dforge' } }
    expect(settingWritten(KEEP, { on: true }, 'on', false)).toEqual({ on: false })
  })

  test('refuses an unknown key and a value that does not fit', () => {
    expect(() => settingWritten(FAKE, {}, 'nope', true)).toThrow('unknown setting nope')
    expect(() => settingWritten(FAKE, {}, 'layout', 'tiles')).toThrow('tiles is not a valid layout')
  })

  test('imports dr-cockpit options that differ from their defaults', () => {
    const claude = { pluginConfigs: { 'dr-cockpit@darkraise': { options: { layout: 'compact', warnAt: 80, nudgeModel: 'yes' } } } }
    expect(importedSettings(FAKE, claude)).toEqual({ layout: 'compact' })
    expect(importedSettings(FAKE, {})).toEqual({})
  })

  test('every default in the real schema fits its own type', () => {
    for (const spec of Object.values(SCHEMA)) expect(isValidSetting(spec, spec.default)).toBe(true)
  })
})

describe('polling', () => {
  test('puts an edited settings file in force within one tick', async ($, on) => {
    const files: NonNullable<World['files']> = { [CONFIG]: { text: JSON.stringify({ sections: 'context,usage' }), mtimeMs: 1 } }
    const clock = world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    files[CONFIG] = { text: JSON.stringify({ sections: 'usage' }), mtimeMs: 2 }
    await clock.advance(2_000)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Context' })).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▾ Usage' })).toBeDefined()
  })

  test('keeps the settings in force when the file stops being a JSON object', async ($, on) => {
    const files: NonNullable<World['files']> = { [CONFIG]: { text: JSON.stringify({ sections: 'usage' }), mtimeMs: 1 } }
    const clock = world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    files[CONFIG] = { text: '{ "sections": ', mtimeMs: 2 }
    await clock.advance(2_000)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Context' })).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▾ Usage' })).toBeDefined()
    await ui.press({ key: 'pane-settings' })
    expect(await ui.find({ type: 'Text', text: /config\.json is not a JSON object; the settings in force are kept/ })).toBeDefined()
  })

  test("puts a Claude key changed outside the pane in force", async ($, on) => {
    const w: World = { tokens: 284_000, config: {}, settings: { autoCompactWindow: 650_000 } }
    const clock = world(on, w)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: /^650k/ })).toBeDefined()
    w.settings = { autoCompactWindow: 700_000 }
    await clock.advance(2_000)
    expect(await ui.find({ type: 'Text', text: /^700k/ })).toBeDefined()
  })

  test('puts in force a settings file saved again just after the cockpit read it', async ($, on) => {
    const files: NonNullable<World['files']> = { [CONFIG]: { text: JSON.stringify({ sections: 'context,usage' }), mtimeMs: 1 } }
    const clock = world(on, { ...SIGNED_IN, files })
    let isSavingAgain = false
    on('fs.read', (_$, e) => {
      const file = files[e.path]
      if (file === undefined) throw new Error('ENOENT')
      if (e.path === CONFIG && isSavingAgain) {
        isSavingAgain = false
        files[CONFIG] = { text: JSON.stringify({ sections: 'context' }), mtimeMs: 3 }
      }
      return { value: file.text }
    })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    files[CONFIG] = { text: JSON.stringify({ sections: 'usage' }), mtimeMs: 2 }
    isSavingAgain = true
    await clock.advance(4_000)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Usage' })).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▾ Context' })).toBeDefined()
  })

  test("puts in force a Claude key changed again while the cockpit applied the last change", async ($, on) => {
    const w: World = { tokens: 284_000, config: {}, settings: { autoCompactWindow: 650_000 } }
    const clock = world(on, w)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    w.settings = { autoCompactWindow: 700_000 }
    // The poll's first merged read finds the change; the second is the one it applies.
    let mergedReads = 0
    w.afterSettingsRead = source => {
      if (source === undefined && ++mergedReads === 2) w.settings = { autoCompactWindow: 750_000 }
    }
    await clock.advance(4_000)
    expect(await ui.find({ type: 'Text', text: /^750k/ })).toBeDefined()
  })

  test('reads nothing while the cockpit is hidden', async ($, on) => {
    const gitRuns: string[] = []
    const clock = world(on, { ...SIGNED_IN, gitRuns, isPaneShut: true })
    signedIn(on)
    await $.session.start(START)
    await clock.advance(20_000)
    expect(gitRuns.filter(run => run.includes('status --porcelain=v2'))).toEqual([])
  })

  test('refreshes the git state every ten seconds while the pane is up', async ($, on) => {
    const gitRuns: string[] = []
    const clock = world(on, { ...SIGNED_IN, gitRuns })
    signedIn(on)
    await $.session.start(START)
    await clock.advance(8_000)
    expect(gitRuns.filter(run => run.includes('status --porcelain=v2'))).toEqual([])
    await clock.advance(2_000)
    expect(gitRuns.filter(run => run.includes('status --porcelain=v2'))).toHaveLength(1)
  })
})

describe('settings rows', () => {
  const ROWS: Schema = {
    layout: { type: 'enum', values: ['auto', 'full', 'compact'], default: 'auto', group: 'Cockpit', label: 'Layout', title: 'Layout', description: 'd', target: 'dforge' },
    warnAt: { type: 'number', default: 80, min: 1, max: 99, step: 5, unit: '%', group: 'Context', label: 'Warn at', title: 'Warn', description: 'd', target: 'dforge' },
    budget: { type: 'number', default: 0, min: 0, max: 2_000_000, step: 50_000, unit: 'k', zero: 'auto', env: 'DFORGE_BUDGET', group: 'Context', label: 'Handoff budget', title: 'Budget', description: 'd', target: 'dforge' },
    note: { type: 'boolean', default: true, group: 'Context', label: 'Handoff note', title: 'Note', description: 'd', target: 'dforge' },
    compactAt: { type: 'number', default: 0, min: 0, floor: 100_000, max: 1_000_000, step: 50_000, unit: 'k', zero: 'unset', group: 'Context', label: 'Auto-compact at', title: 'Compact', description: 'd', target: 'claude' },
    wait: { type: 'number', default: 30, min: 5, max: 240, step: 5, unit: 'min', group: 'Finish', label: 'Menu waits', title: 'Wait', description: 'd', target: 'dforge' },
  }
  const spec = (key: string) => ROWS[key] as SettingSpec

  test('the tabs are the groups in schema order', () => {
    expect(tabsOf(ROWS)).toEqual(['Cockpit', 'Context', 'Finish'])
    expect(tabsOf(SCHEMA)).toEqual(['Cockpit', 'Context', 'Workflow', 'Process', 'Finish', 'Notifications', 'darkmem'])
  })

  test('a value reads through its unit and zero word', () => {
    expect(shownValue(spec('warnAt'), 70)).toBe('70%')
    expect(shownValue(spec('budget'), 0)).toBe('auto')
    expect(shownValue(spec('budget'), 465_000)).toBe('465k')
    expect(shownValue(spec('wait'), 45)).toBe('45 min')
    expect(shownValue(spec('note'), false)).toBe('off')
    expect(shownValue(spec('layout'), 'full')).toBe('full')
  })

  test('a typed number is whole, in range, and may end in k', () => {
    expect(typedNumber(spec('warnAt'), ' 65 ')).toBe(65)
    expect(typedNumber(spec('warnAt'), '500')).toBeUndefined()
    expect(typedNumber(spec('warnAt'), '6.5')).toBeUndefined()
    expect(typedNumber(spec('warnAt'), 'many')).toBeUndefined()
    expect(typedNumber(spec('budget'), '465k')).toBe(465_000)
    expect(typedNumber(spec('budget'), '0.5K')).toBe(500)
    expect(typedNumber(spec('budget'), '1.001k')).toBe(1_001)
    expect(typedNumber(spec('budget'), '1.0005k')).toBeUndefined()
    expect(typedNumber(spec('compactAt'), '0')).toBe(0)
    expect(typedNumber(spec('compactAt'), '50000')).toBeUndefined()
    expect(typedNumber(spec('compactAt'), '100k')).toBe(100_000)
    expect(rangeText(spec('warnAt'))).toBe('Enter a whole number from 1 to 99')
    expect(rangeText(spec('compactAt'))).toBe('Enter 0 or a whole number from 100,000 to 1,000,000')
  })

  test('a step moves to the next multiple, stays in range, and jumps a floor', () => {
    expect(steppedSetting(spec('warnAt'), 80, 1)).toBe(85)
    expect(steppedSetting(spec('warnAt'), 97, 1)).toBe(99)
    expect(steppedSetting(spec('warnAt'), 99, -1)).toBe(95)
    expect(steppedSetting(spec('warnAt'), 1, -1)).toBe(1)
    expect(steppedSetting(spec('warnAt'), 1, 1)).toBe(5)
    expect(steppedSetting(spec('compactAt'), 0, 1)).toBe(100_000)
    expect(steppedSetting(spec('compactAt'), 0, -1)).toBe(0)
    expect(steppedSetting(spec('compactAt'), 100_000, -1)).toBe(0)
    expect(steppedSetting(spec('compactAt'), 100_000, 1)).toBe(150_000)
    expect(steppedSetting(spec('compactAt'), 1_000_000, 1)).toBe(1_000_000)
  })

  test('a row carries what the view draws', () => {
    expect(rowOf('warnAt', spec('warnAt'), 70)).toEqual({
      key: 'warnAt',
      group: 'Context',
      label: 'Warn at',
      description: 'd',
      kind: 'stepper',
      value: 70,
      shown: '70%',
      shownDefault: '80%',
      values: [],
      isChanged: true,
      lockedBy: null,
    })
    expect(rowOf('layout', spec('layout'), 'auto')).toMatchObject({ kind: 'choices', values: ['auto', 'full', 'compact'], isChanged: false })
    expect(rowOf('budget', spec('budget'), 465_000, 'set by DFORGE_BUDGET')).toMatchObject({ shown: '465k', isChanged: false, lockedBy: 'set by DFORGE_BUDGET' })
    expect(rowsOf(ROWS, { warnAt: 70 }, 'Context', { budget: 'set by DFORGE_BUDGET' }).map(row => [row.key, row.isChanged, row.lockedBy])).toEqual([
      ['warnAt', true, null],
      ['budget', false, 'set by DFORGE_BUDGET'],
      ['note', false, null],
      ['compactAt', false, null],
    ])
  })

  test('says which keys something outside the file forces', () => {
    expect(envLocks(ROWS, { DFORGE_BUDGET: '400000' })).toEqual({ budget: 'set by DFORGE_BUDGET' })
    expect(envLocks(ROWS, { DFORGE_BUDGET: 'junk' })).toEqual({})
    expect(envLocks(ROWS, {})).toEqual({})
    expect(claudeLocks(ROWS, { compactAt: 500_000 }, { compactAt: 650_000 })).toEqual({ compactAt: 'set by a project or managed settings file' })
    expect(claudeLocks(ROWS, { compactAt: 650_000 }, { compactAt: 650_000 })).toEqual({})
    expect(claudeLocks(ROWS, {}, {})).toEqual({})
    expect(claudeLocks(ROWS, { compactAt: 50_000 }, { compactAt: 650_000 })).toEqual({ compactAt: '50000 from a project or managed file, not valid' })
  })

  test('a Claude key resolves from the Claude settings and never enters the dforge file', () => {
    expect(resolveSettings(ROWS, { compactAt: 300_000 }, {}, { compactAt: 650_000 }).compactAt).toBe(650_000)
    expect(resolveSettings(ROWS, { compactAt: 300_000 }, {}, { compactAt: 50_000 }).compactAt).toBe(0)
    expect(resolveSettings(ROWS, { compactAt: 300_000 }, {}).compactAt).toBe(0)
    expect(settingProblems(ROWS, { compactAt: 'x' }, {})).toEqual([])
    expect(() => settingWritten(ROWS, {}, 'compactAt', 650_000)).toThrow("compactAt is stored in Claude's settings file")
    expect(importedSettings(ROWS, { pluginConfigs: { 'dr-cockpit@darkraise': { options: { compactAt: 650_000, warnAt: 70 } } } })).toEqual({ warnAt: 70 })
    expect(isValidSetting(spec('compactAt'), 0)).toBe(true)
    expect(isValidSetting(spec('compactAt'), 99_999)).toBe(false)
    expect(isValidSetting(spec('wait'), 5.5)).toBe(false)
  })
})

describe('settings held outside the file', () => {
  const NOTE = 'dforge settings changed'

  test('a value the environment forces shows locked, and a group reset leaves it alone', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: { warnAt: 70, handoffTokens: 300_000 }, written, env: { DFORGE_BUDGET: '465000' } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: 'set by DFORGE_BUDGET' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^465k/ })).toBeDefined()
    expect(await ui.find({ key: 'set-handoffTokens-more' })).toBeUndefined()
    expect(await ui.find({ key: 'set-warnAt-more' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: '1 changed' })).toBeDefined()
    await ui.press({ key: 'settings-reset' })
    await ui.press({ key: 'settings-reset-confirm' })
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ handoffTokens: 300_000 })
  })

  test('the pre-2.0 variable locks nothing', async ($, on) => {
    world(on, { tokens: 284_000, config: {}, env: { DR_SUPERPOWERS_BUDGET: '465000' } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: /set by DR_/ })).toBeUndefined()
  })

  test('a Claude key is saved through dforge-config, never into the dforge file', async ($, on) => {
    const written: Record<string, string> = {}
    const runs: string[] = []
    world(on, { tokens: 284_000, config: {}, written, runs, settings: { autoCompactWindow: 650_000 } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: /^650k/ })).toBeDefined()
    await ui.press({ key: 'set-autoCompactWindow-more' })
    expect(runs).toHaveLength(1)
    expect(runs[0]).toMatch(/^node .*\/scripts\/lib\/dforge-config\.mjs set autoCompactWindow 700000$/)
    // The row shows what was saved, and the next step starts from it.
    expect(await ui.find({ type: 'Text', text: /^700k/ })).toBeDefined()
    await ui.press({ key: 'set-autoCompactWindow-more' })
    expect(runs[1]).toMatch(/ set autoCompactWindow 750000$/)
    await ui.press({ key: 'set-autoCompactWindow-reset' })
    expect(runs[2]).toMatch(/ set autoCompactWindow 0$/)
    expect(await ui.find({ type: 'Text', text: /^unset/ })).toBeDefined()
    await ui.press({ key: 'set-autoCompactEnabled-toggle' })
    expect(runs[3]).toMatch(/ set autoCompactEnabled false$/)
    expect(written[CONFIG]).toBeUndefined()
  })

  test('says why a Claude key was not saved', async ($, on) => {
    const toasts: string[] = []
    world(on, { tokens: 284_000, config: {}, toasts, isDforgeConfigRefusing: true })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    await ui.press({ key: 'set-autoCompactWindow-more' })
    expect(toasts).toContain('dforge: autoCompactWindow not saved: /home/me/.claude/settings.json is not valid JSON; fix or remove it')
  })

  test('a Claude key a project or managed file overrides shows locked', async ($, on) => {
    world(on, { tokens: 284_000, config: {}, settings: { autoCompactWindow: 500_000 }, userSettings: { autoCompactWindow: 650_000 } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: 'set by a project or managed settings file' })).toBeDefined()
    expect(await ui.find({ key: 'set-autoCompactWindow-more' })).toBeUndefined()
  })

  test('a Claude key a project or managed file sets to an invalid value names that value', async ($, on) => {
    world(on, { tokens: 284_000, config: {}, settings: { autoCompactWindow: 50_000 }, userSettings: { autoCompactWindow: 650_000 } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: '50000 from a project or managed file, not valid' })).toBeDefined()
    expect(await ui.find({ key: 'set-autoCompactWindow-more' })).toBeUndefined()
  })

  test('a Claude key stays locked after a save while a project file forces another value', async ($, on) => {
    const w: World = { tokens: 284_000, config: {}, settings: { autoCompactWindow: 650_000 }, userSettings: { autoCompactWindow: 650_000 } }
    world(on, w)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ key: 'set-autoCompactWindow-more' })).toBeDefined()
    await ui.press({ key: 'set-autoCompactWindow-more' })
    expect(await ui.find({ type: 'Text', text: /^700k/ })).toBeDefined()
    // The engine now reports the user file as saved; the project file still wins the merged read.
    w.userSettings = { autoCompactWindow: 700_000 }
    await ui.press({ key: 'set-autoCompactEnabled-toggle' })
    expect(await ui.find({ type: 'Text', text: 'set by a project or managed settings file' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^650k/ })).toBeDefined()
    expect(await ui.find({ key: 'set-autoCompactWindow-more' })).toBeUndefined()
  })

  test('a hand edit after a save of a Claude key shows once the engine has the save', async ($, on) => {
    const w: World = { tokens: 284_000, config: {}, settings: { autoCompactWindow: 650_000 }, userSettings: { autoCompactWindow: 650_000 } }
    const clock = world(on, w)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    await ui.press({ key: 'set-autoCompactWindow-more' })
    w.userSettings = w.settings = { autoCompactWindow: 700_000 }
    await clock.advance(2_000)
    w.userSettings = w.settings = { autoCompactWindow: 800_000 }
    await clock.advance(2_000)
    expect(await ui.find({ type: 'Text', text: /^800k/ })).toBeDefined()
  })

  test('a reset Claude key shows a project file that sets the same key once the engine sees the removal', async ($, on) => {
    const w: World = { tokens: 284_000, config: {}, settings: { autoCompactWindow: 650_000 }, userSettings: { autoCompactWindow: 650_000 } }
    world(on, w)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    await ui.press({ key: 'set-autoCompactWindow-reset' })
    // dforge-config removed the key from the user file; the project file still sets it.
    w.userSettings = {}
    await ui.press({ key: 'set-autoCompactEnabled-toggle' })
    expect(await ui.find({ type: 'Text', text: 'set by a project or managed settings file' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^650k/ })).toBeDefined()
  })

  test('a changed skill setting is told to the model once, when the settings close', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 50_000, config: {}, notes, written: {} })
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Workflow' })
    await ui.press({ key: 'set-worktree-always' })
    await ui.press({ key: 'set-worktree-never' })
    await ui.press({ key: 'set-codexLane-toggle' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dforge settings changed: worktree=never. Each replaces the matching question or default in the skills.',
    ])
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toHaveLength(1)
  })

  test('leaving the settings through /cockpit tells the model too', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 50_000, config: {}, notes, written: {} })
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Workflow' })
    await ui.press({ key: 'set-worktree-always' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    await $.command.run({ ...COCKPIT, args: '' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dforge settings changed: worktree=always. Each replaces the matching question or default in the skills.',
    ])
  })

  test('a note the session refuses is sent at the next close', async ($, on) => {
    const notes: string[] = []
    const w: World = { tokens: 50_000, config: {}, notes, written: {}, isAppendFailing: true }
    world(on, w)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Workflow' })
    await ui.press({ key: 'set-worktree-always' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    w.isAppendFailing = false
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dforge settings changed: worktree=always. Each replaces the matching question or default in the skills.',
    ])
  })

  test('outside a dforge session the note waits for one', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 50_000, config: {}, notes, written: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Process' })
    await ui.press({ key: 'set-designApproval-whole' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    await $.tool.call({ tool: 'Skill', skill: 'dforge:brainstorming' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dforge settings changed: designApproval=whole. Each replaces the matching question or default in the skills.',
    ])
  })

  test('a dforge subagent spawn sends the waiting note once', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 50_000, config: {}, notes, written: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Process' })
    await ui.press({ key: 'set-designApproval-whole' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    const spawn = (n: number) =>
      $.agent.spawn({ tool_use_id: `toolu_${n}`, prompt: 'Implement', description: `Task ${n}`, subagentType: 'dforge:impl-sonnet-low', provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: false, fork: false })
    await spawn(1)
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dforge settings changed: designApproval=whole. Each replaces the matching question or default in the skills.',
    ])
    await spawn(2)
    expect(notes.filter(note => note.startsWith(NOTE))).toHaveLength(1)
  })

  test('closing the pane sends the note once', async ($, on) => {
    const notes: string[] = []
    const closed: string[] = []
    // The kit cannot raise the person's close, so the mod's own Minimize closes
    // the pane. Settings-back sends the note too, so the append is refused there
    // to keep the note waiting for the close.
    const w: World = { tokens: 50_000, config: {}, notes, closed, written: {}, isAppendFailing: true }
    world(on, w)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Workflow' })
    await ui.press({ key: 'set-worktree-always' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    w.isAppendFailing = false
    await ui.press({ key: 'pane-minimize' })
    expect(closed).toEqual(['dforge'])
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dforge settings changed: worktree=always. Each replaces the matching question or default in the skills.',
    ])
    await ui.unmount()
    // Nothing is left waiting: the next point that sends the note sends none.
    await $.agent.spawn({ tool_use_id: 'toolu_1', prompt: 'Implement', description: 'Task 1', subagentType: 'dforge:impl-sonnet-low', provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: false, fork: false })
    expect(notes.filter(note => note.startsWith(NOTE))).toHaveLength(1)
  })

  test('a dforge skill started as a slash command marks the session and sends the waiting note', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 50_000, config: {}, notes, written: {} })
    on('skill.prompt', ($, e) => ({ text: e.text }))
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Process' })
    await ui.press({ key: 'set-designApproval-whole' })
    await ui.press({ key: 'settings-back' })
    expect(await $.skill.prompt({ skill: 'commit', text: 'Commit.' })).toEqual({ text: 'Commit.' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    expect(await $.skill.prompt({ skill: 'dforge:brainstorming', text: 'Brainstorm.' })).toEqual({ text: 'Brainstorm.' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dforge settings changed: designApproval=whole. Each replaces the matching question or default in the skills.',
    ])
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Workflow' })
    await ui.press({ key: 'set-worktree-never' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toHaveLength(2)
  })
})

// An auto run's state file in the primary checkout the world names.
const AUTO = '/home/me/code/shop/.dforge/sdd/auto-run.json'
const SENTINEL = 'Task 3: complete.\n\nAuto run: compacting'
function autoFiles(fields: Record<string, unknown> = {}): NonNullable<World['files']> {
  return {
    [AUTO]: {
      text: JSON.stringify({
        active: true,
        session: 'sess-1',
        phase: 'execute',
        regime: 'normal',
        pending: 'compact',
        plan: 'docs/plan.md',
        compactions: 0,
        resumes: 0,
        stopped: null,
        resumePrompt: null,
        launch: null,
        ...fields,
      }),
    },
  }
}
/** Lets timers at the current instant fire and their work finish. */
async function settle(clock: ReturnType<typeof world>) {
  for (let i = 0; i < 10; i++) await clock.advance(1)
}
const pendingOf = (files: NonNullable<World['files']>) => (JSON.parse(files[AUTO]!.text) as { pending: unknown }).pending

describe('auto run', () => {
  test('compacts on the sentinel, books it and submits the continue prompt', async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.compacts?.[0]).toMatch(/Ruling: line/)
    expect(w.autoRuns).toContain('--session sess-1 compacted')
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts?.[0]).toMatch(/`bash "[^"]*\/scripts\/auto-run" after-compact`/)
    expect(w.prompts?.[0]).toMatch(/`bash "[^"]*\/scripts\/auto-run" status` names/)
    expect(w.prompts?.[0]).toMatch(/docs\/plan\.md/)
    expect(pendingOf(files)).toBe('after-compact')
  })

  test('stays still without the sentinel, on an interrupted turn, or for another session', async ($, on) => {
    const w: World = { ...SIGNED_IN, compacts: [], prompts: [] }
    const clock = world(on, w)
    const files = autoFiles()
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: true, turnId: 't2', reason: 'aborted' })
    files[AUTO] = autoFiles({ session: 'another' })[AUTO]!
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't3', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toEqual([])
    expect(w.prompts).toEqual([])
  })

  test('waits while a subagent runs', async ($, on) => {
    const w: World = { ...SIGNED_IN, compacts: [] }
    const clock = world(on, w)
    signedIn(on, autoFiles())
    await $.session.start(START)
    await $.agent.spawn({
      tool_use_id: 'toolu_1',
      prompt: 'Implement task 4',
      description: 'Task 4',
      subagentType: 'dforge:impl-sonnet-low',
      provider: { plugin: 'dforge', tier: 'user' },
      parentModel: 'claude-opus-5-5',
      background: true,
      fork: false,
    })
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    await clock.advance(5_000)
    await settle(clock)
    expect(w.compacts).toEqual([])
  })

  test('waits for a turn that started first, then compacts', async ($, on) => {
    const w: World = { ...SIGNED_IN, compacts: [] }
    const clock = world(on, w)
    signedIn(on, autoFiles())
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await $.turn.start({ text: 'How is it going?', turnId: 't2' })
    await settle(clock)
    expect(w.compacts).toEqual([])
    await $.turn.complete({ answer: 'Going well.', durationMs: 1, isAborted: false, turnId: 't2', reason: 'answer' })
    await clock.advance(5_000)
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
  })

  test('clears, binds the cleared session, sets its model and submits its first prompt', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: { model: 'sonnet', effort: 'high' } })
    const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.commands).toEqual(['/clear', '/model sonnet', '/effort high'])
    expect(w.autoRuns).toContain('--session sess-2 rebind --to sess-2')
    expect(w.autoRuns).toContain('--session sess-2 resumed')
    expect(w.prompts).toEqual(['Execute docs/plan.md.'])
    expect(pendingOf(files)).toBeNull()
  })

  test('puts back the default model and effort that /model and /effort save', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: { model: 'sonnet', effort: 'high' } })
    const userSettings = { model: 'opus[1m]', modelSettings: { 'claude-opus-5-5': { effortLevel: 'max' } }, theme: 'dark' }
    const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], runs: [], userSettings, autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.commands).toEqual(['/clear', '/model sonnet', '/effort high'])
    expect(w.runs?.filter(run => run.includes(' claude-restore '))).toEqual([
      expect.stringContaining(`claude-restore ${JSON.stringify({ model: 'opus[1m]', modelSettings: { 'claude-opus-5-5': { effortLevel: 'max' } } })}`),
    ])
    expect(w.prompts).toEqual(['Execute docs/plan.md.'])
  })

  test('removes the defaults /model and /effort added where none were set', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: { model: 'sonnet', effort: 'high' } })
    const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], runs: [], userSettings: {}, autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.runs?.filter(run => run.includes(' claude-restore '))).toEqual([expect.stringContaining('claude-restore {"model":null,"modelSettings":null}')])
  })

  test('restores nothing when the clear sets no model', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: null })
    const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], runs: [], userSettings: { model: 'opus[1m]' }, autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.runs?.filter(run => run.includes(' claude-restore '))).toEqual([])
  })

  test('tells the cleared session when its default model could not be put back', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: { model: 'sonnet', effort: 'high' } })
    const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], runs: [], userSettings: { model: 'opus[1m]' }, isDforgeConfigRefusing: true, autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts?.[0]).toMatch(/^Execute docs\/plan\.md\./)
    expect(w.prompts?.[0]).toMatch(/could not put back the default model and effort/)
    expect(w.prompts?.[0]).toMatch(/scripts\/auto-run ruling add/)
  })

  test('writes the defaults again when the engine misses the first write', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: { model: 'sonnet', effort: 'high' } })
    const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], runs: [], userSettings: { model: 'opus[1m]' }, missedRestores: 1, autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.prompts).toEqual([])
    for (let i = 0; i < 8; i++) await clock.advance(500)
    expect(w.runs?.filter(run => run.includes(' claude-restore '))).toHaveLength(2)
    expect(w.userSettings).toEqual({ model: 'opus[1m]' })
    expect(w.prompts).toEqual(['Execute docs/plan.md.'])
  })

  test('tells the cleared session when the engine never takes the restored defaults', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: { model: 'sonnet', effort: 'high' } })
    const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], runs: [], userSettings: { model: 'opus[1m]' }, missedRestores: 3, autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    for (let i = 0; i < 30; i++) await clock.advance(500)
    expect(w.runs?.filter(run => run.includes(' claude-restore '))).toHaveLength(3)
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts?.[0]).toMatch(/could not put back the default model and effort/)
  })

  test('shows the cleared session\'s run at once', async ($, on) => {
    const files = autoFiles({ pending: 'clear', regime: 'high', resumePrompt: 'Execute docs/plan.md.' })
    const w: World = { ...SIGNED_IN, commands: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Auto run · execute · high/ })).toBeDefined()
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(await ui.find({ type: 'Text', text: /Auto run · execute · normal/ })).toBeDefined()
  })

  test('shows the compaction at once', async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(await ui.find({ type: 'Text', text: /Auto run · execute · normal · 1 compaction · 0 resumes/ })).toBeDefined()
  })

  test('tells the cleared session when its model was refused', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: { model: 'sonnet', effort: 'high' } })
    const w: World = { ...SIGNED_IN, commands: [], prompts: [], autoFile: files[AUTO], refusedCommands: ['model'] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts?.[0]).toMatch(/could not run \/model sonnet/)
    expect(w.commands).toContain('/effort high')
    expect(w.prompts?.[0]).toMatch(/auto-run ruling add/)
  })

  test('stops the run when the cleared session cannot be bound', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.' })
    const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { rebind: 1 } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.autoRuns).toContain('--session sess-1 stop --reason the cleared session could not be bound')
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts?.[0]).toMatch(/could not be bound/)
  })

  test('retries the stage that failed', async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO], submitFailures: 1 }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.prompts).toEqual([])
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toHaveLength(1)
    await clock.advance(5_000)
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts?.[0]).toMatch(/after-compact/)
    // The submitted retry clears the booked failure, so a later one does not stop the run.
    expect(w.autoRuns?.at(-1)).toBe('--session sess-1 resumed')
    expect(pendingOf(files)).toBe('after-compact')
  })

  test('retries the first prompt after /clear without clearing again', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: null })
    const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO], submitFailures: 1 }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.prompts).toEqual([])
    expect(w.autoRuns?.filter(call => call.startsWith('--session sess-2 failure '))).toHaveLength(1)
    expect(pendingOf(files)).toBe('resume')
    await clock.advance(5_000)
    await settle(clock)
    expect(w.commands).toEqual(['/clear'])
    expect(w.prompts).toEqual(['Execute docs/plan.md.'])
    expect(w.autoRuns?.at(-1)).toBe('--session sess-2 resumed')
    expect(pendingOf(files)).toBeNull()
  })

  test('books a refused compaction and retries it once', async ($, on) => {
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], isCompactVetoed: true }
    const clock = world(on, w)
    signedIn(on, autoFiles())
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toHaveLength(1)
    await clock.advance(5_000)
    await settle(clock)
    expect(w.compacts).toHaveLength(2)
    expect(w.prompts).toEqual([])
  })

  test('at the second failure, says so once and asks for the ending', async ($, on) => {
    const fetches: World['fetches'] = []
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, fetches, compacts: [], prompts: [], isCompactVetoed: true, autoRunExits: { failure: 5 }, autoFile: files[AUTO] }
    const clock = world(on, w)
    mock.store(on, { notifyUrl: WEBHOOK })
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    await clock.advance(5_000)
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts?.[0]).toMatch(/auto run stopped/i)
    const titles = fetches.map(one => (one.body.embeds as Record<string, unknown>[] | undefined)?.[0]?.title)
    expect(titles.filter(title => title === '⛔ Auto run stopped')).toHaveLength(1)
  })

  test('stops the run when a failure cannot be booked', async ($, on) => {
    const fetches: World['fetches'] = []
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, fetches, autoRuns: [], prompts: [], isCompactVetoed: true, autoRunExits: { failure: 1 }, autoFile: files[AUTO] }
    const clock = world(on, w)
    mock.store(on, { notifyUrl: WEBHOOK })
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    await clock.advance(5_000)
    await settle(clock)
    expect(w.prompts?.filter(text => /could not book/.test(text))).toHaveLength(1)
    const titles = fetches.map(one => (one.body.embeds as Record<string, unknown>[] | undefined)?.[0]?.title)
    expect(titles.filter(title => title === '⛔ Auto run stopped')).toHaveLength(1)
    expect(w.autoRuns?.some(call => call.includes(' stop --reason '))).toBe(true)
  })

  test('books a compaction the engine made', async ($, on) => {
    const w: World = { ...SIGNED_IN, autoRuns: [] }
    world(on, w)
    signedIn(on, autoFiles({ pending: null }))
    await $.session.start(START)
    await $.session.compact({ trigger: 'auto', messages: [SUMMARY] })
    expect(w.autoRuns).toContain('--session sess-1 compacted')
  })

  test("books the pane's Compact", async ($, on) => {
    const w: World = { ...SIGNED_IN, autoRuns: [], compacts: [] }
    world(on, w)
    signedIn(on, autoFiles({ pending: null }))
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-compact' })
    expect(w.compacts).toHaveLength(1)
    expect(w.autoRuns).toEqual(['--session sess-1 compacted'])
  })

  test("satisfies a pending compact stage with the pane's Compact, once", async ($, on) => {
    const files = autoFiles({ pending: 'compact' })
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-compact' })
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.autoRuns?.filter(call => call.endsWith(' compacted'))).toHaveLength(1)
    expect(pendingOf(files)).toBe('after-compact')
    expect(w.prompts).toHaveLength(1)
  })

  test('books no engine compaction over a pending clear', async ($, on) => {
    const w: World = { ...SIGNED_IN, autoRuns: [] }
    world(on, w)
    signedIn(on, autoFiles({ pending: 'clear' }))
    await $.session.start(START)
    await $.session.compact({ trigger: 'auto', messages: [SUMMARY] })
    expect(w.autoRuns).toEqual([])
  })

  test('switches in place: compacts, books it, sets the model and submits the first prompt', async ($, on) => {
    const files = autoFiles({ phase: 'execute', pending: 'switch', resumePrompt: 'Continue `docs/plan.md` with dforge:subagent-driven-development.', launch: { model: 'sonnet', effort: 'high' } })
    const w: World = { ...SIGNED_IN, compacts: [], commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Plan saved.\n\nAuto run: switching', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.compacts?.[0]).toMatch(/Drop the design conversation/)
    expect(w.commands).toEqual(['/model sonnet', '/effort high'])
    expect(w.autoRuns).toContain('--session sess-1 compacted --switch')
    expect(w.autoRuns).toContain('--session sess-1 resumed')
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts?.[0]).toMatch(/^Run `bash "[^"]*\/scripts\/auto-run" after-compact` first\. Continue `docs\/plan\.md`/)
    expect(pendingOf(files)).toBe('after-compact')
  })

  test('retries the first prompt after the switch compaction without compacting again', async ($, on) => {
    const files = autoFiles({ phase: 'execute', pending: 'switch', resumePrompt: 'Continue `docs/plan.md`.', launch: null })
    const w: World = { ...SIGNED_IN, compacts: [], commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO], submitFailures: 1 }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Plan saved.\n\nAuto run: switching', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.prompts).toEqual([])
    expect(w.autoRuns?.filter(call => call.includes(' failure --reason the cockpit could not switch: '))).toHaveLength(1)
    expect(pendingOf(files)).toBe('switch-resume')
    await clock.advance(5_000)
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.commands).toEqual([])
    expect(w.prompts).toHaveLength(1)
    expect(w.autoRuns?.at(-1)).toBe('--session sess-1 resumed')
    expect(pendingOf(files)).toBe('after-compact')
  })

  test('switches over a refused compaction: books it and submits the first prompt', async ($, on) => {
    const files = autoFiles({ phase: 'execute', pending: 'switch', resumePrompt: 'Continue `docs/plan.md`.', launch: null })
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO], isCompactVetoed: true }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Plan saved.\n\nAuto run: switching', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toEqual([])
    expect(w.autoRuns).toContain('--session sess-1 compacted --switch')
    expect(w.prompts).toEqual([expect.stringMatching(/after-compact` first\. Continue `docs\/plan\.md`\.$/)])
    expect(pendingOf(files)).toBe('after-compact')
  })

  test('stops the run when the switch cannot book its resume', async ($, on) => {
    const files = autoFiles({ phase: 'execute', pending: 'switch', resumePrompt: 'Continue `docs/plan.md`.', launch: null })
    const w: World = { ...SIGNED_IN, compacts: [], commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { resumed: 1 } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Plan saved.\n\nAuto run: switching', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.prompts?.filter(text => text.includes('Continue `docs/plan.md`.'))).toHaveLength(1)
    expect(w.autoRuns).toContain('--session sess-1 stop --reason the cockpit switched but could not book it')
  })

  test("stops the run when the switch's compaction cannot be booked", async ($, on) => {
    const files = autoFiles({ phase: 'execute', pending: 'switch', resumePrompt: 'Continue `docs/plan.md`.', launch: null })
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { compacted: 1 } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Plan saved.\n\nAuto run: switching', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.autoRuns).toContain("--session sess-1 stop --reason the cockpit could not book the switch's compaction")
  })

  test('books no engine compaction over a pending switch', async ($, on) => {
    const w: World = { ...SIGNED_IN, autoRuns: [] }
    world(on, w)
    signedIn(on, autoFiles({ pending: 'switch' }))
    await $.session.start(START)
    await $.session.compact({ trigger: 'auto', messages: [SUMMARY] })
    expect(w.autoRuns).toEqual([])
  })

  test('books no engine compaction over a pending switch-resume', async ($, on) => {
    const w: World = { ...SIGNED_IN, autoRuns: [] }
    world(on, w)
    signedIn(on, autoFiles({ pending: 'switch-resume' }))
    await $.session.start(START)
    await $.session.compact({ trigger: 'auto', messages: [SUMMARY] })
    expect(w.autoRuns).toEqual([])
  })

  test('books nothing without a run', async ($, on) => {
    const w: World = { ...SIGNED_IN, autoRuns: [] }
    world(on, w)
    signedIn(on, {})
    await $.session.start(START)
    await $.session.compact({ trigger: 'auto', messages: [SUMMARY] })
    expect(w.autoRuns).toEqual([])
  })

  test('says at the switch that execution begins at Setup', async ($, on) => {
    const files = autoFiles({ phase: 'execute', pending: 'switch', resumePrompt: 'Continue `docs/plan.md`.', launch: null })
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Plan saved.\n\nAuto run: switching', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts?.[0]).toMatch(/No task has started and no execution worktree exists yet; execution begins at the execution skill's Setup\./)
  })

  test('ends the run when its compaction reaches the cap', async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { compacted: 5 } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.prompts).toEqual(['The auto run stopped: 3 compactions without a completed task. End as reference/auto-run.md §Stopping says.'])
    expect(w.autoRuns?.some(call => call.includes(' stop '))).toBe(false)
  })

  test('ends the run when an engine compaction reaches the cap', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { compacted: 5 } }
    world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.session.compact({ trigger: 'auto', messages: [SUMMARY] })
    expect(w.autoRuns).toContain('--session sess-1 compacted')
    expect(w.prompts).toEqual(['The auto run stopped: 3 compactions without a completed task. End as reference/auto-run.md §Stopping says.'])
  })

  for (const pending of ['handoff', 'compact']) {
    test(`books no engine compaction over a pending ${pending}`, async ($, on) => {
      const w: World = { ...SIGNED_IN, autoRuns: [] }
      world(on, w)
      signedIn(on, autoFiles({ pending }))
      await $.session.start(START)
      await $.session.compact({ trigger: 'auto', messages: [SUMMARY] })
      expect(w.autoRuns).toEqual([])
    })
  }

  for (const [why, flag] of [['node cannot run the restore', { isNodeMissing: true }], ['the user settings cannot be read', { isUserSettingsUnreadable: true }]] as const) {
    test(`runs neither /model nor /effort when ${why}`, async ($, on) => {
      const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: { model: 'sonnet', effort: 'high' } })
      const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], runs: [], userSettings: { model: 'opus[1m]' }, ...flag, autoFile: files[AUTO] }
      const clock = world(on, w)
      signedIn(on, files)
      await $.session.start(START)
      await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
      await settle(clock)
      expect(w.commands).toEqual(['/clear'])
      expect(w.userSettings).toEqual({ model: 'opus[1m]' })
      expect(w.runs?.filter(run => run.includes(' claude-restore '))).toEqual([])
      expect(w.prompts).toHaveLength(1)
      expect(w.prompts?.[0]).toMatch(/^Execute docs\/plan\.md\./)
      expect(w.prompts?.[0]).toMatch(/kept this session on .+ because it could not put back your default model afterwards\. Record that with scripts\/auto-run ruling add\./)
    })
  }

  test('sends a blocked notice naming the settings file when the defaults cannot be put back', async ($, on) => {
    const fetches: World['fetches'] = []
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: { model: 'sonnet', effort: 'high' } })
    const w: World = { ...SIGNED_IN, fetches, commands: [], autoRuns: [], prompts: [], runs: [], userSettings: { model: 'opus[1m]' }, isDforgeConfigRefusing: true, autoFile: files[AUTO] }
    const clock = world(on, w)
    mock.store(on, { notifyUrl: WEBHOOK })
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    const notice = fetches.map(one => (one.body.embeds as Record<string, unknown>[] | undefined)?.[0]).find(embed => embed?.title === '⛔ Default model not restored')
    expect(notice).toBeDefined()
    expect(JSON.stringify(notice)).toMatch(/\/home\/me\/\.claude\/settings\.json/)
  })

  test('writes the heartbeat at the start and on every watchdog tick', async ($, on) => {
    const written: Record<string, string> = {}
    const clock = world(on, { ...SIGNED_IN, written })
    signedIn(on, {})
    await $.session.start(START)
    expect(written['/home/me/.claude/dforge/sessions/cockpit/sess-1']).toBe('1000\n')
    await clock.advance(60_000)
    expect(written['/home/me/.claude/dforge/sessions/cockpit/sess-1']).toBe('1060\n')
  })

  test('books a failure once background work has deferred a stage for 30 minutes', async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.agent.spawn({
      tool_use_id: 'toolu_1',
      prompt: 'Implement task 4',
      description: 'Task 4',
      subagentType: 'dforge:impl-sonnet-low',
      provider: { plugin: 'dforge', tier: 'user' },
      parentModel: 'claude-opus-5-5',
      background: true,
      fork: false,
    })
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    await clock.advance(1_795_000)
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toEqual([])
    await clock.advance(10_000)
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toEqual(['--session sess-1 failure --reason a background launch kept the compact waiting 30 minutes'])
    expect(w.compacts).toEqual([])
  })

  test('a dev server left running in the background defers no stage', async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], autoFile: files[AUTO], tools: { Bash: () => ({ result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b7k2' }, text: 'Running in the background' }) } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true })
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
  })

  test('a live turn restarts the deferral, so the cap counts background work alone', async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.agent.spawn({
      tool_use_id: 'toolu_1',
      prompt: 'Implement task 4',
      description: 'Task 4',
      subagentType: 'dforge:impl-sonnet-low',
      provider: { plugin: 'dforge', tier: 'user' },
      parentModel: 'claude-opus-5-5',
      background: true,
      fork: false,
    })
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    await $.turn.start({ text: 'How is Task 4 going?', turnId: 't2' })
    await clock.advance(1_795_000)
    await $.turn.complete({ answer: 'Still running.', durationMs: 1, isAborted: false, turnId: 't2', reason: 'answer' })
    await clock.advance(10_000)
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toEqual([])
    expect(w.compacts).toEqual([])
  })

  for (const [code, prompt] of [
    [5, 'The auto run stopped: the cockpit could not compact twice. End as reference/auto-run.md §Stopping says.'],
    [1, 'The auto run stopped: a background launch kept the compact waiting 30 minutes, and the failure could not be booked (exit 1). End as reference/auto-run.md §Stopping says.'],
  ] as const) {
    test(`ends the run when the deferral cap's failure exits ${code}`, async ($, on) => {
      const files = autoFiles()
      const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { failure: code } }
      const clock = world(on, w)
      signedIn(on, files)
      await $.session.start(START)
      await $.agent.spawn({
        tool_use_id: 'toolu_1',
        prompt: 'Implement task 4',
        description: 'Task 4',
        subagentType: 'dforge:impl-sonnet-low',
        provider: { plugin: 'dforge', tier: 'user' },
        parentModel: 'claude-opus-5-5',
        background: true,
        fork: false,
      })
      await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
      await settle(clock)
      await clock.advance(1_805_000)
      expect(w.prompts).toEqual([prompt])
      expect(w.compacts).toEqual([])
      if (code === 1) {
        expect(w.autoRuns).toContain('--session sess-1 stop --reason a background launch kept the compact waiting 30 minutes, and the failure could not be booked (exit 1)')
      }
    })
  }

  test("starts a new run's deferral afresh after the last one stopped", async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.agent.spawn({
      tool_use_id: 'toolu_1',
      prompt: 'Implement task 4',
      description: 'Task 4',
      subagentType: 'dforge:impl-sonnet-low',
      provider: { plugin: 'dforge', tier: 'user' },
      parentModel: 'claude-opus-5-5',
      background: true,
      fork: false,
    })
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    await clock.advance(1_740_000)
    files[AUTO]!.text = autoFiles({ active: false, pending: null })[AUTO]!.text
    await clock.advance(10_000)
    files[AUTO]!.text = autoFiles()[AUTO]!.text
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't2', reason: 'answer' })
    await settle(clock)
    await clock.advance(120_000)
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toEqual([])
  })

  test('nudges a stalled run, and again only once its last nudge is as old', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(180_000)
    expect(w.prompts).toEqual([])
    await clock.advance(60_000)
    expect(w.autoRuns?.filter(call => call === '--session sess-1 stalled')).toHaveLength(1)
    expect(w.prompts).toEqual([
      expect.stringMatching(/^The auto run stalled: the last turn ended without its sentinel line\. Run `bash "[^"]*\/scripts\/auto-run" status`, continue the phase it names, and end the turn as reference\/auto-run\.md §Ending a turn says\.$/),
    ])
    await clock.advance(180_000)
    expect(w.prompts).toHaveLength(1)
    await clock.advance(60_000)
    expect(w.prompts).toHaveLength(2)
  })

  test('books no stall once the session has ended', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    on('session.end', (_$, e) => e as never)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await $.session.end({ reason: 'other', sessionId: 'sess-1', resume: { id: 'sess-1' } })
    await clock.advance(300_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    expect(w.prompts).toEqual([])
  })

  test('nudges a run whose turn failed', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'error' })
    await clock.advance(240_000)
    expect(w.autoRuns).toContain('--session sess-1 stalled')
    expect(w.prompts).toHaveLength(1)
  })

  test("a subagent's approval after a failed turn leaves the turn ended", async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    on('tool.check', () => ({ decision: 'ask' }))
    await $.session.start(START)
    await $.agent.spawn({ tool_use_id: 'toolu_1', prompt: 'Implement task 4', description: 'Task 4', subagentType: 'dforge:impl-sonnet-low', provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: true, fork: false })
    await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'error' })
    await $.tool.check({ tool: 'Bash', input: { command: 'ls' }, tool_use_id: 'toolu_9', agentId: 'agent-1' })
    await $.tool.call({ tool: 'Bash', command: 'ls', tool_use_id: 'toolu_9', agentId: 'agent-1' } as never)
    await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 'a1', reason: 'answer', agentId: 'agent-1' })
    await clock.advance(240_000)
    expect(w.autoRuns).toContain('--session sess-1 stalled')
  })

  test('leaves the run to the owner after an Esc', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3', durationMs: 1, isAborted: true, turnId: 't1', reason: 'aborted' })
    await clock.advance(600_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    expect(w.prompts).toEqual([])
  })

  test('leaves the run alone while a subagent runs', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.agent.spawn({
      tool_use_id: 'toolu_1',
      prompt: 'Implement task 4',
      description: 'Task 4',
      subagentType: 'dforge:impl-sonnet-low',
      provider: { plugin: 'dforge', tier: 'user' },
      parentModel: 'claude-opus-5-5',
      background: true,
      fork: false,
    })
    await $.turn.complete({ answer: 'Waiting for Task 4.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(600_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    expect(w.prompts).toEqual([])
  })

  test('ends the run at the stall that stops it', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { stalled: 5 } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(240_000)
    expect(w.prompts).toEqual(['The auto run stopped: 3 stalls without a completed task. End as reference/auto-run.md §Stopping says.'])
  })

  test('arms a pending stage that no timer holds', async ($, on) => {
    const files = autoFiles({ pending: 'compact' })
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(240_000)
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    expect(pendingOf(files)).toBe('after-compact')
  })

  test('resubmits the first prompt of a pending resume that no timer holds', async ($, on) => {
    const files = autoFiles({ pending: 'resume', resumePrompt: 'Execute docs/plan.md.', launch: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(240_000)
    await settle(clock)
    expect(w.prompts).toEqual(['Execute docs/plan.md.'])
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    expect(w.autoRuns).toContain('--session sess-1 resumed')
    expect(pendingOf(files)).toBeNull()
  })

  test('nudges a bound run in a session that has had no turn yet', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await clock.advance(180_000)
    expect(w.prompts).toEqual([])
    await clock.advance(60_000)
    expect(w.autoRuns).toContain('--session sess-1 stalled')
    expect(w.prompts).toHaveLength(1)
  })

  test('recovers a cleared session whose first prompt started no turn', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: null })
    const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.prompts).toEqual(['Execute docs/plan.md.'])
    await clock.advance(240_000)
    expect(w.autoRuns).toContain('--session sess-2 stalled')
    expect(w.prompts).toHaveLength(2)
  })

  test('waits STALL_MS after a stage before it nudges', async ($, on) => {
    const files = autoFiles({ pending: 'compact' })
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(240_000)
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.prompts).toHaveLength(1)
    await clock.advance(60_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    await clock.advance(120_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    await clock.advance(60_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toHaveLength(1)
  })

  test('leaves the run alone while a background shell runs', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO], tools: { Bash: () => ({ result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b9w1' }, text: 'Running in the background' }) } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'npm test', run_in_background: true } as never)
    await $.turn.complete({ answer: 'Waiting for the tests.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(600_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    expect(w.prompts).toEqual([])
  })

  test('a dev server in the background does not hide a stall', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO], tools: { Bash: () => ({ result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b9w1' }, text: 'Running in the background' }) } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true } as never)
    await $.turn.complete({ answer: 'The server is up.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(600_000)
    expect(w.autoRuns).toContain('--session sess-1 stalled')
  })

  test('leaves the run alone while a turn runs', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await $.turn.start({ text: 'Continue.', turnId: 't2' })
    await clock.advance(600_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    expect(w.prompts).toEqual([])
  })

  test('arms nothing while a stage runs, a long compaction included', async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO], compactMs: 240_000 }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    await clock.advance(250_000)
    expect(w.compacts).toHaveLength(1)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
  })

  test('after a stalled call that fails, waits STALL_MS before the next', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { stalled: 1 } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    const stalls = () => w.autoRuns?.filter(call => call === '--session sess-1 stalled').length
    await clock.advance(240_000)
    expect(stalls()).toBe(1)
    await clock.advance(180_000)
    expect(stalls()).toBe(1)
    await clock.advance(60_000)
    expect(stalls()).toBe(2)
    expect(w.prompts).toEqual([])
  })

  test('a heartbeat that fails leaves the rest of the tick to run', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(180_000)
    // The tick at 240 s: its heartbeat's session id read fails once.
    w.sessionIdFailures = 1
    await clock.advance(60_000)
    expect(w.autoRuns).toContain('--session sess-1 stalled')
  })

  test('submits no stall prompt once a turn has started during the stalled call', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    // The activity read before the call was idle; the person's prompt starts a
    // turn while scripts/auto-run books the stall, so only the turn guard
    // holds the stall prompt back.
    w.onAutoRun = word => (word === 'stalled' ? $.turn.start({ text: 'Continue.', turnId: 't2' }) : undefined)
    await clock.advance(240_000)
    expect(w.autoRuns).toContain('--session sess-1 stalled')
    expect(w.prompts).toEqual([])
  })

  test('reads a run only for its session, and its sentinel only as the last line', () => {
    const text = autoFiles({ session: 'b', launch: { model: 'sonnet', effort: 'high' } })[AUTO]!.text
    expect(autoRunFor(text, 'b')?.launch).toEqual({ model: 'sonnet', effort: 'high' })
    expect(autoRunFor(text, 'b')?.plan).toBe('docs/plan.md')
    expect(autoRunFor(text, 'b')?.stalledAt).toBeNull()
    expect(autoRunFor(autoFiles({ session: 'b', stalledAt: 1240 })[AUTO]!.text, 'b')?.stalledAt).toBe(1240)
    expect(autoRunFor(text, 'a')).toBeNull()
    expect(autoRunFor('not json', 'b')).toBeNull()
    expect(endsOnSentinel('x\n\nAuto run: compacting  \n\n', 'compact')).toBe(true)
    expect(endsOnSentinel('Auto run: compacting\nmore', 'compact')).toBe(false)
    expect(endsOnSentinel('Auto run: clearing', 'compact')).toBe(false)
    expect(endsOnSentinel('Auto run: clearing', 'clear')).toBe(true)
    expect(endsOnSentinel('Auto run: compacting', null)).toBe(false)
  })
})

describe('auto run in the pane', () => {
  test('the limit follows the regime', () => {
    expect(autoLimitFor('normal', 465_000, 1_000_000, 800_000)).toBe(465_000)
    expect(autoLimitFor('normal', 0, 1_000_000, 800_000)).toBe(604_000)
    expect(autoLimitFor('high', 465_000, 1_000_000, 800_000)).toBe(720_000)
    expect(autoLimitFor('high', 0, 650_000)).toBe(585_000)
  })

  test('shows the run and stops it from the pane', async ($, on) => {
    const files = autoFiles({ pending: null, compactions: 2 })
    const w: World = { ...SIGNED_IN, autoRuns: [], autoFile: files[AUTO] }
    world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Auto run · execute · normal · 2 compactions · 0 resumes/ })).toBeDefined()
    await ui.press({ key: 'pane-stop-auto' })
    expect(w.autoRuns).toContain('--session sess-1 stop --reason owner pressed Stop auto')
  })

  test('hides Hand off while a run is active and brings it back when the run stops', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, tokens: 470_000, autoRuns: [], autoFile: files[AUTO] }
    world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ key: 'pane-stop-auto' })).toBeDefined()
    expect(await ui.find({ key: 'pane-handoff' })).toBeUndefined()
    await ui.press({ key: 'pane-stop-auto' })
    expect(await ui.find({ key: 'pane-stop-auto' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /Auto run ·/ })).toBeUndefined()
    expect(await ui.find({ key: 'pane-handoff' })).toBeDefined()
  })

  test('hides Resume while a run is active and brings it back when the run stops', async ($, on) => {
    const files: NonNullable<World['files']> = { ...autoFiles({ pending: null }), '/home/me/code/shop/.dforge/handoff/latest.md': { text: RESUMABLE, mtimeMs: 900_000 } }
    const w: World = { ...SIGNED_IN, files, autoRuns: [], autoFile: files[AUTO] }
    world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ key: 'pane-stop-auto' })).toBeDefined()
    expect(await ui.find({ key: 'pane-resume' })).toBeUndefined()
    await ui.press({ key: 'pane-stop-auto' })
    expect(await ui.find({ key: 'pane-stop-auto' })).toBeUndefined()
    expect(await ui.find({ key: 'pane-resume' })).toBeDefined()
  })

  test('says the handoff budget again after a run that stopped', async ($, on) => {
    const fetches: World['fetches'] = []
    const w: World = { tokens: 100_000, env: { HOME: '/home/me' }, fetches }
    world(on, w)
    mock.store(on, { notifyUrl: WEBHOOK })
    const files: NonNullable<World['files']> = {}
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    w.tokens = 470_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const sent = () => fetches.filter(one => (one.body.embeds as Record<string, unknown>[] | undefined)?.[0]?.title === '🔶 Handoff budget reached').length
    expect(sent()).toBe(1)
    files[AUTO] = autoFiles({ pending: null })[AUTO]!
    w.tokens = 100_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    files[AUTO] = autoFiles({ pending: null, active: false })[AUTO]!
    w.tokens = 470_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(sent()).toBe(2)
  })

  test('picks up a run started during the turn, and mutes the handoff note', async ($, on) => {
    const notes: string[] = []
    world(on, { ...SIGNED_IN, tokens: 470_000, notes })
    const files: NonNullable<World['files']> = {}
    signedIn(on, files)
    await $.session.start(START)
    files[AUTO] = autoFiles({ pending: null })[AUTO]!
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes).toEqual([])
  })

  test('measures against the high regime', async ($, on) => {
    world(on, { ...SIGNED_IN, tokens: 470_000 })
    signedIn(on, autoFiles({ pending: null, regime: 'high' }))
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /80% of handoff/ })).toBeDefined()
  })
})
