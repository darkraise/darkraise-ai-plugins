import { describe, expect, mock, test } from 'claude-code/testing'
import type { CommandRunInput, On, RenderElement, SessionMeasureInput, SessionMessage } from 'claude-code'

import {
  accountColor,
  accountKey,
  autoLimitFor,
  autoRunFor,
  isAbsolutePath,
  isForge,
  attributionIn,
  bar,
  billingLabel,
  budgetFor,
  duration,
  elapsed,
  endsOnSentinel,
  finalLimitFor,
  finishLine,
  bandLines,
  fitBand,
  folderRuns,
  isAtLeast,
  levelOf,
  limitForecast,
  modelName,
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
  runsWidth,
  sectionsToggled,
  sparkline,
  stackedRuns,
  shellAge,
  tasksEnded,
  termColor,
  track,
  turnsToBudget,
  windowElapsed,
  writesGitText,
} from '../hooks/cockpit/lib'
import type { ActivityInput, Run } from '../hooks/cockpit/lib'
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
import type { Schema, SettingSpec } from '../hooks/cockpit/config'
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
import { avatarSvg, bandMetersSvg, gaugeTileSvg, gaugeSvg, labelledMeterSvg, meterSvg, paint, panelSvg, panelText, seatSvg, segmentsSvg, stackSvg, statSvg, svgWidth, trendSvg } from '../hooks/cockpit/svg'

const SURFACES = ['terminal', 'desktop'] as const
const runsText = (runs: Run[]) => runs.map(one => one.text).join('')
const BAND = {
  plugin: 'dr-forge',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 3, bodyColumns: 100, scroll: { offset: 0, bodyRows: 3 }, view: {} },
} as const
const HINT = {
  plugin: 'dr-forge',
  component: 'PromptHint',
  props: { isDraft: false, isWorking: false, hint: '? for shortcuts' },
} as const
const PANE = {
  plugin: 'dr-forge',
  component: 'Pane',
  requestId: 'dr-forge',
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

// A terminal session starting in the repository.
const START = { cwd: '/home/me/code/shop/web', surface: 'terminal', isInteractive: true } as never

// What a compaction leaves: one row standing for the conversation.
const SUMMARY: SessionMessage = { role: 'user', text: 'Summary.', toolUses: [] }

const CONFIG = '/home/me/.dr-forge/config.json'

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
  /** Each forge-config command the plugin runs, as one line. */
  runs?: string[]
  /** forge-config refuses, as on a Claude settings file it cannot parse. */
  isForgeConfigRefusing?: boolean
  /** How many claude-restore writes the engine misses, as one landing right after its own save. */
  missedRestores?: number
  /** The session refuses every row the plugin appends. */
  isAppendFailing?: boolean
  toasts?: string[]
  notes?: string[]
  env?: Record<string, string>
  /** Files the plugin reads, by path, with their modification time. */
  files?: Record<string, { text: string; mtimeMs?: number }>
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
  /** ~/.dr-forge/config.json's values; set, HOME is /home/me and world answers reads of the file. */
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
  on('settings.read', (_$, e) => ({ value: e?.source === 'user' && w.userSettings !== undefined ? w.userSettings : (w.settings ?? {}) }))
  on('tool.call', (_$, e) => w.tools?.[String(e.tool)]?.() ?? { result: 'ok', text: 'ok' })
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'agent-1' }))
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
    return w.isCompactVetoed ? ({ skip: 'vetoed' } as never) : { messages: e.messages ?? [SUMMARY] }
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
        if (exitCode === 0 && word === 'compacted') Object.assign(state, { pending: 'after-compact', compactions: Number(state.compactions) + 1 })
        if (exitCode === 0 && word === 'rebind') Object.assign(state, { session: words[4], pending: 'resume', regime: 'normal' })
        if (exitCode === 0 && word === 'resumed' && state.pending === 'resume') state.pending = null
        if (exitCode === 0 && word === 'stop') Object.assign(state, { active: false, stopped: call.split(' --reason ')[1] ?? null, pending: null })
        if (exitCode === 5 && word === 'failure') Object.assign(state, { active: false, stopped: 'the cockpit could not compact twice', pending: null })
        w.autoFile.text = JSON.stringify(state)
      }
      return { value: { exitCode, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    }
    if (argv.includes('/scripts/lib/forge-config.mjs ')) {
      w.runs?.push(argv)
      const restore = e.argv[e.argv.indexOf('claude-restore') + 1]
      if (e.argv.includes('claude-restore') && !w.isForgeConfigRefusing && w.userSettings !== undefined) {
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
      const stderr = w.isForgeConfigRefusing ? 'forge-config: /home/me/.claude/settings.json is not valid JSON; fix or remove it\n' : ''
      return { value: { exitCode: w.isForgeConfigRefusing ? 1 : 0, stdout: '', stderr, isStdoutTruncated: false, isStderrTruncated: false } }
    }
    if (argv.includes('/scripts/lib/darkmem-config.mjs ')) {
      w.modeRuns?.push(e.argv[e.argv.length - 1] ?? '')
      if (w.modeOut === 'missing') {
        return clock.advance(5_000).then(() => ({ deny: 'dr-forge: $.process.run(node) failed to start: ENOENT: Executable not found in $PATH: "node"' }))
      }
      if (w.modeOut === 'rejects') return { deny: 'the engine refused to start the process' }
      if (w.modeOut === 'timeout') return { deny: 'dr-forge: $.process.run(node) aborted: still running after 5000ms' }
      const out = w.modeOut ?? { exitCode: 0, stdout: PORCELAIN, stderr: '' }
      return { value: { ...out, isStdoutTruncated: false, isStderrTruncated: false } }
    }
    const stdout = argv === 'hostname' ? 'devbox\n' : argv.startsWith('git rev-parse') ? `${w.primary ?? '/home/me/code/shop'}/.git\n` : PORCELAIN
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('session.id', () => ({ value: w.sessionId ?? 'sess-1' }))
  on('fs.stat', (_$, e) => {
    const file = w.files?.[e.path]
    if (file === undefined) throw new Error('ENOENT')
    return { value: { kind: 'file', size: file.text.length, mtimeMs: file.mtimeMs ?? 0, isLink: false } }
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
  on('ui.panes', () => ({ value: w.isPaneShut ? [] : [{ id: 'dr-forge', title: 'Cockpit', isShown: true, isFocused: false, isPlaced: true }] }))
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
function signedIn(on: On, files: World['files'] = {}) {
  on('fs.read', (_$, e) => {
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

test('only a dr-forge name marks a workflow session', () => {
  expect(isForge('dr-forge:brainstorming')).toBe(true)
  expect(isForge('dr-superpowers:brainstorming')).toBe(false)
  expect(isForge('feature-dev:code-reviewer')).toBe(false)
})

describe('budget rule', () => {
  test('follows the setting, then the env, then dr-forge', () => {
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
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
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
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
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
      subagentType: 'dr-forge:impl-sonnet-low',
      provider: { plugin: 'dr-forge', tier: 'user' },
      parentModel: 'claude-opus-5-5',
      background: false,
      fork: false,
    })
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...PANE, surface })
      // The desktop draws its panels as pictures, their words in each one's alt.
      if (surface === 'desktop') expect(JSON.stringify(await ui.drawn())).toMatch(/●  impl-sonnet-low  Task 3/)
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
        const drawn = JSON.stringify(await ui.drawn())
        expect(drawn).toContain('impl-sonnet-low ×1 40k in · 75% cached · 3k out')
        expect(drawn).toContain('✓  impl-sonnet-low  Task 3')
      } else {
        expect(await ui.find({ type: 'Text', text: /40k in · 75% cached · 3k out/ })).toBeDefined()
        expect(await ui.find({ type: 'Text', text: /✓ impl-sonnet-low Task 3/ })).toBeDefined()
      }
      await ui.unmount()
    }
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
        // The desktop draws its panels as pictures, naming their figures and
        // the repo's chips in each one's alt.
        expect(drawn).toContain('Usage: $1.50')
        expect(drawn).toContain('61% of the handoff budget')
        expect(drawn).toContain('5h limit 23% used')
        expect(drawn).toContain('284k of 650k tokens, handoff at 465k')
        expect(drawn).toContain('⎇ feat/pane, ↑2, ↓1, ~1 changed, ?1 untracked')
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

  test('sections picks and orders the pane', async ($, on) => {
    world(on, { tokens: 50_000, config: { sections: 'plan, repo' } })
    await $.session.start(START)
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
    world(on, { tokens: 340_000, config: {}, env: { DR_FORGE_BUDGET: '3000000' } })
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

  test('DR_FORGE_BUDGET sets the budget', async ($, on) => {
    world(on, { tokens: 340_000, config: {}, env: { DR_FORGE_BUDGET: '500000' } })
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
    expect(await ui.find({ type: 'Text', text: /warnAt in ~\/\.dr-forge\/config\.json is not valid; ignored/ })).toBeDefined()
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
  const OLD_FORGE = '/home/me/.dr-superpowers/config.json'
  const DARKMEM = { url: 'http://d.test', repos: {} }
  const OLD_FILES = {
    [STORE_FILE]: JSON.stringify({ notifyUrl: 'https://discord.com/api/webhooks/1/abc', notifyMention: '42' }),
    [OLD_FORGE]: JSON.stringify({ darkmem: DARKMEM }),
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

  test('a settings file forge-config wrote first is kept, and the webhook still comes over', async ($, on) => {
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
    expect(await ui.find({ type: 'Text', text: 'Context' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /^╭─ me@example\.com · subscription · Remote ○ off ─+ $/ })).toBeDefined()
    expect(await ui.find({ key: 'band-expand' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /ctx ▰+▱*┃?▱* 61%.*5h ▰+▱*┊?▱* 23%.*7d .* 61%/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /\$ 1 shell · longest 0s.*~\/code\/shop\/web ⎇ feat\/pane\* ↑2 ↓1 ~1 \?1/ })).toBeDefined()
    // No buttons beside Expand, and no commands.
    expect(await ui.find({ key: 'pane-compact' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /npm run dev/ })).toBeUndefined()
    await ui.unmount()
    const desk = await $.ui.mount({ ...INLINE, surface: 'desktop' })
    const drawn = JSON.stringify(await desk.drawn())
    expect(drawn).toContain('me@example.com · subscription')
    expect(drawn).toContain('5h 23%')
    expect(drawn).toContain('1 shell · longest 0s')
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

  test('is used docked too when minimized', async ($, on) => {
    world(on, { tokens: 284_000, config: { layout: 'compact' } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Context' })).toBeUndefined()
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
      expect(closed).toEqual(['dr-forge'])
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

    test(`draws the band above the prompt when minimized on ${surface}`, async ($, on) => {
      world(on, SIGNED_IN)
      signedIn(on, configured({ layout: 'compact' }))
      await $.session.start(START)
      await $.tool.call({ tool: 'Bash', command: 'ls' })
      await $.session.measure(MEASURE)
      const band = await $.ui.mount({ ...BAND, surface })
      expect(await band.find({ key: 'band-expand' })).toBeDefined()
      const drawn = JSON.stringify(await band.drawn())
      expect(drawn).toContain('me@example.com')
      expect(drawn).toContain('5h')
    })

    test(`Expand on the band above the prompt opens the pane on ${surface}`, async ($, on) => {
      const written: Record<string, string> = {}
      const opened: string[] = []
      world(on, { tokens: 284_000, opened, written, config: { layout: 'compact' } })
      await $.session.start(START)
      await $.tool.call({ tool: 'Bash', command: 'ls' })
      // Left on the settings view, as closing the settings pane by hand leaves it.
      await $.command.run({ ...COCKPIT, args: 'settings' })
      opened.length = 0
      const docking = await $.ui.mount({ ...BAND, surface, viewport: { columns: 160, rows: 50, isFullscreen: true } })
      await docking.press({ key: 'band-expand' })
      expect(opened).toEqual(['dr-forge'])
      // auto is the default, so saving it drops the key.
      expect(JSON.parse(written[CONFIG] ?? '{"layout":"unwritten"}').layout).toBeUndefined()
      await docking.unmount()
      const pane = await $.ui.mount({ ...PANE, surface })
      expect(await pane.find({ type: 'Text', text: 'Settings' })).toBeUndefined()
      await pane.unmount()
      // Minimized again for the next session, which reads the file afresh.
      written[CONFIG] = JSON.stringify({ layout: 'compact' })
      await $.session.start(START)
      const main = await $.ui.mount({ ...BAND, surface, viewport: { columns: 100, rows: 50, isFullscreen: false } })
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
    const band = await $.ui.mount({ ...BAND, props: { ...BAND.props, hasSurvey: true }, surface: 'terminal' })
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
    expect(closed).toEqual(['dr-forge'])
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
    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await band.find({ type: 'Text', text: /⎇ feat\/pane\*/ })).toBeDefined()
  })

  test('/cockpit expands a minimized cockpit', async ($, on) => {
    const written: Record<string, string> = {}
    const opened: string[] = []
    world(on, { tokens: 284_000, opened, written, config: { layout: 'compact' } })
    await $.session.start(START)
    opened.length = 0
    await $.command.run(COCKPIT)
    expect(opened).toEqual(['dr-forge'])
    // auto is the default, so saving it leaves an object without the key.
    expect(JSON.parse(written[CONFIG] ?? '{"layout":"unwritten"}')).toEqual({})
  })

  for (const [layout, want] of [
    ['compact', ['dr-forge']],
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
    expect(await ui.find({ type: 'Text', text: 'Context' })).toBeDefined()
  })

  test('an unknown layout reads as auto', async ($, on) => {
    world(on, { tokens: 284_000, config: { layout: 'tiles' } })
    await $.session.start(START)
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
    const answer = await $.command.run(COCKPIT)
    expect(answer.text).toBe('Cockpit pane opened.')
  })

  test('says why when Claude Code holds the pane back', async ($, on) => {
    world(on, { tokens: 284_000, open: { isPlaced: false, reason: 'this desktop app places no panes' } })
    const answer = await $.command.run(COCKPIT)
    expect(answer.text).toBe('Cockpit pane is waiting: this desktop app places no panes')
  })
})

describe('buttons', () => {
  test('wear a rounded box, the accent on the one that matters', async ($, on) => {
    const w: World = { ...SIGNED_IN, tokens: 200_000 }
    world(on, w)
    signedIn(on, configured({ handoffTokens: 400_000 }))
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
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
      await ui.press({ key: 'set-openAtStart-toggle' })
      await ui.press({ key: 'set-layout-compact' })
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
    expect(toasts.some(text => text.startsWith('dr-forge: guardAttribution not saved:'))).toBe(true)
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
    expect(toasts.some(text => text.startsWith('dr-forge: guardAttribution not saved:'))).toBe(true)
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
    expect(statSvg('68%', 'of handoff budget', 200, 'success')).toContain('fill="#3fb36b">68%</text>')
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
    // A panel lays its lines out in pixels: the header, text cut to fit
    // beside its right side, pills, wrapped notes and drawings placed whole.
    const lines = [
      { kind: 'head', lamp: 'cyan', title: 'Context', right: [{ text: '284k of 650k' }] },
      { kind: 'text', left: [{ text: 'a very long command line that will not fit in the room it has' }], right: [{ text: '12:04', mono: true }] },
      { kind: 'chips', chips: [{ text: 'Opus 5.5', color: 'cyan' }, { text: 'xhigh effort' }] },
      { kind: 'text', wrap: true, small: true, left: [{ text: 'one two three four five six seven eight nine ten eleven twelve', dim: true }] },
      { kind: 'picture', svg: seatSvg(1, 0.5, 120, 'magenta'), alt: 'a seat' },
      { kind: 'picture', svg: seatSvg(0.5, 0.5, 120, 'magenta') },
    ] as const
    const drawnPanel = panelSvg(lines as never, 120)
    expect(drawnPanel).toContain('>CONTEXT</text>')
    expect(drawnPanel).toContain('text-anchor="end"')
    expect(drawnPanel).toContain('…</tspan>')
    expect(drawnPanel).toContain('class="pill"')
    expect(drawnPanel).toContain('@media (prefers-color-scheme: dark)')
    expect(drawnPanel.match(/<text /g)?.length).toBeGreaterThan(6)
    // Two placed drawings keep their clip paths apart.
    const clips = [...drawnPanel.matchAll(/<clipPath id="([^"]+)"/g)].map(match => match[1])
    expect(new Set(clips).size).toBe(2)
    expect(panelText(lines as never)).toBe(
      'Context: 284k of 650k\na very long command line that will not fit in the room it has 12:04\nOpus 5.5, xhigh effort\none two three four five six seven eight nine ten eleven twelve\na seat',
    )
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

  test('opens the pane when the desktop joins', async ($, on) => {
    const opened: string[] = []
    world(on, { tokens: 100_000, opened, isPaneShut: true })
    await $.session.attach({ surface: 'mobile', clientId: 'mobile:default' } as never)
    expect(opened).toEqual([])
    await $.session.attach({ surface: 'desktop', clientId: 'desktop:default' } as never)
    expect(opened).toEqual(['dr-forge'])
  })

  test('leaves the pane shut on a desktop joining when Show at start is off', async ($, on) => {
    const opened: string[] = []
    world(on, { tokens: 100_000, opened, isPaneShut: true, config: { openAtStart: false } })
    await $.session.start(START)
    await $.session.attach({ surface: 'desktop', clientId: 'desktop:default' } as never)
    expect(opened).toEqual([])
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
    expect(await ui.find({ type: 'Text', text: 'Account' })).toBeDefined()
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
    expect(await ui.find({ type: 'Text', text: 'Account' })).toBeUndefined()
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
    expect(await ui.find({ type: 'Text', text: /^Agents$/ })).toBeDefined()
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
    expect(redact(`post ${WEBHOOK}`)).toBe('post [webhook]')
    expect(excerpt('a'.repeat(20), 10)).toBe(`${'a'.repeat(9)}…`)
  })

  test('picks kinds and keeps the default set as the empty setting', () => {
    expect(notifyKindsFrom('')).toEqual(['ask', 'question', 'done', 'error', 'blocked', 'budget', 'limit'])
    expect(notifyKindsFrom('done, nope, done')).toEqual(['done'])
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
    expect(embed?.footer).toEqual({ text: 'dr-forge · ~/.claude · tmux work' })
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

  test('sends to the webhook named by DR_FORGE_NOTIFY_URL alone', async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches, config: { notifyAfter: 0 }, env: { DR_FORGE_NOTIFY_URL: WEBHOOK } })
    mock.store(on, {})
    await $.session.start(START)
    await $.turn.complete({ answer: 'ok', durationMs: 5_000, isAborted: false, turnId: 't1', reason: 'answer' })
    expect(fetches).toHaveLength(1)
    expect(fetches[0]?.url).toBe(`${WEBHOOK}?wait=true`)
  })

  test('sends to the webhook named by DR_COCKPIT_NOTIFY_URL when DR_FORGE_NOTIFY_URL is unset', async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches, config: { notifyAfter: 0 }, env: { DR_COCKPIT_NOTIFY_URL: WEBHOOK } })
    mock.store(on, {})
    await $.session.start(START)
    await $.turn.complete({ answer: 'ok', durationMs: 5_000, isAborted: false, turnId: 't1', reason: 'answer' })
    expect(fetches).toHaveLength(1)
    expect(fetches[0]?.url).toBe(`${WEBHOOK}?wait=true`)
  })

  test('prefers DR_FORGE_NOTIFY_URL over DR_COCKPIT_NOTIFY_URL', async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { tokens: 50_000, fetches, config: { notifyAfter: 0 }, env: { DR_FORGE_NOTIFY_URL: WEBHOOK, DR_COCKPIT_NOTIFY_URL: 'https://discord.com/api/webhooks/2/old' } })
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
    'Task 1: implementer dr-forge:impl-sonnet-low (assigned; base abc1234)',
    'Task 1: complete (commits a..b, review clean) — done: x; verified: y; remaining: none; discovered: none; assumptions: none',
    'Task 2: implementer dr-forge:impl-sonnet-low (assigned; base def5678)',
    'Task 2: fix round 2/5 (1 addressed, 1 open — meter width; commits c..d; fresh)',
  ].join('\n')
  const PLAN = '# Plan\n\n### Task 1: Add the helpers\n\n### Task 2: Draw the card\n\n### Task 3: Ship it\n'
  const runFiles = (ledger: string): World['files'] => ({
    '/home/me/code/shop/.forge/sdd/p/progress.md': { text: ledger, mtimeMs: 2_000_000 },
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

  test('replaces the plan card in a dr-forge run', async ($, on) => {
    const files = runFiles(LEDGER)
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Run' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^round 2\/5$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^1\/3$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers · clean/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /round 2\/5 · impl-sonnet-low/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Task 3: Ship it/ })).toBeDefined()
  })

  test('reads no ledger left under the pre-3.0 .superpowers', async ($, on) => {
    const files: World['files'] = {
      '/home/me/code/shop/.superpowers/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
      '/home/me/code/shop/docs/plans/p.md': { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
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
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    expect(fetches).toHaveLength(0)
    const ledger = files?.['/home/me/code/shop/.forge/sdd/p/progress.md']
    if (ledger !== undefined) ledger.text += '\nTask 2: BLOCKED — impl exhausted — pick a meter width rule'
    await $.tool.call({ tool: 'Bash', command: 'echo x >> .forge/sdd/p/progress.md' })
    await $.tool.call({ tool: 'Bash', command: 'cat .forge/sdd/p/progress.md' })
    expect(fetches).toHaveLength(1)
    expect((fetches[0]?.body.embeds as Record<string, unknown>[])[0]?.title).toBe('🛑 Task 2 blocked')
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^1 blocked$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /BLOCKED · impl exhausted/ })).toBeDefined()
  })

  test('clears a run finished before the session started', async ($, on) => {
    const done = [
      '# SDD ledger — plan: docs/plans/p.md',
      ...[1, 2, 3].map(n => `Task ${n}: complete (commits a..b, review clean) — done: x; verified: y; remaining: none; discovered: none; assumptions: none`),
    ].join('\n')
    const files = runFiles(done)
    world(on, { ...SIGNED_IN, files, startedAt: 3_000_000 })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:brainstorming' })
    await $.session.start(START)
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Run' })).toBeUndefined()
    await ui.unmount()
    // A run still open from before keeps its card.
    const ledger = files?.['/home/me/code/shop/.forge/sdd/p/progress.md']
    if (ledger !== undefined) ledger.text = LEDGER
    await $.tool.call({ tool: 'Bash', command: 'cat .forge/sdd/p/progress.md' })
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Run' })).toBeDefined()
  })

  test('reads the finish choice and counts it down', () => {
    const chosen = parseFinish('{"action":"pr","base":"main","chosenAt":900}')
    expect(chosen).toEqual({ action: 'pr', base: 'main', dueAt: null, answer: null, firedAt: null })
    expect(parseFinish('{"action":"later"}')).toBeNull()
    expect(parseFinish('{broken')).toBeNull()
    if (chosen === null) return
    expect(runsText(finishLine(chosen, 0))).toBe('Finish push and open a PR if the menu goes unanswered')
    const armed = { ...chosen, action: 'merge' as const, dueAt: 1_800_000 }
    expect(runsText(finishLine(armed, 420_000))).toBe('⏱ Finish merge into main · in 23m')
    expect(runsText(finishLine(armed, 1_800_000))).toBe('⏱ Finish merge into main · due now')
    expect(runsText(finishLine({ ...armed, firedAt: 1_800_000 }, 1_900_000))).toBe('✓ Finish merge into main · no answer, so done')
    expect(finishLine({ ...armed, answer: 'keep' }, 420_000)).toEqual([])
    expect(runsText(finishLine({ ...chosen, action: 'wait' }, 0))).toBe('Finish wait for your answer')
  })

  test('shows the finish choice on the Run card', async ($, on) => {
    const files = {
      ...runFiles(LEDGER),
      '/home/me/code/shop/.forge/sdd/p/finish.json': { text: '{"action":"pr","base":"main","chosenAt":900,"armedAt":1000,"dueAt":2800}' },
    }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    // The world's clock reads 1,000,000 ms; the menu's 30 minutes end at 2,800 s.
    expect(await ui.find({ type: 'Text', text: /⏱ Finish push and open a PR · in 30m/ })).toBeDefined()
  })

  test('offers no Resume for a handoff left under the pre-3.0 .superpowers', async ($, on) => {
    const files: World['files'] = { '/home/me/code/shop/.superpowers/handoff/latest.md': { text: '# Handoff', mtimeMs: 900_000 } }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ key: 'pane-resume' })).toBeUndefined()
  })

  test('offers Resume for a handoff under .forge', async ($, on) => {
    const files: World['files'] = { '/home/me/code/shop/.forge/handoff/latest.md': { text: '# Handoff', mtimeMs: 900_000 } }
    const prompts: string[] = []
    world(on, { ...SIGNED_IN, files, prompts })
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ key: 'pane-resume' })).toBeDefined()
    await ui.press({ key: 'pane-resume' })
    expect(prompts).toEqual([expect.stringContaining('.forge/handoff/latest.md')])
  })
})

describe('cockpit roots', () => {
  const MIRROR = '/home/me/.dr-forge/mirror/shop'
  const MODE = [
    `documents\tdarkmem\t${MIRROR}/superpowers`,
    `progress\tdarkmem\t${MIRROR}/work/sdd\t${MIRROR}/work/handoff/latest.md`,
    'project\tshop',
    '',
  ].join('\n')
  const LEDGER = '# SDD ledger — plan: docs/superpowers/plans/p.md\nTask 1: implementer dr-forge:impl-sonnet-low (assigned; base abc1234)\n'
  const PLAN = '# Plan\n\n### Task 1: Add the helpers\n\n### Task 2: Draw the card\n'
  const checkoutFiles = (): NonNullable<World['files']> => ({
    '/home/me/code/shop/.forge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
    '/home/me/code/shop/docs/forge/plans/p.md': { text: PLAN },
  })

  test('reads the roots --mode prints', () => {
    expect(parseModeLines(MODE)).toEqual({
      docs: { store: 'darkmem', root: `${MIRROR}/superpowers` },
      progress: { store: 'darkmem', ledgerRoot: `${MIRROR}/work/sdd`, latestFile: `${MIRROR}/work/handoff/latest.md` },
      project: 'shop',
    })
    expect(parseModeLines('documents\tlocal\t/r/docs/forge\nprogress\tlocal\t/r/.forge/sdd\t/r/.forge/handoff/latest.md\n')?.project).toBeNull()
    expect(parseModeLines(PORCELAIN)).toBeNull()
    expect(parseModeLines('documents\tlocal\t/r/docs/forge\n')).toBeNull()
    expect(parseModeLines('documents\telsewhere\t/r\nprogress\tlocal\t/a\t/b\n')).toBeNull()
  })

  test('a failing --mode keeps the checkout paths and says why', async ($, on) => {
    const files = checkoutFiles()
    const stderr = 'darkmem-config: /home/me/.dr-forge/stores.json is not valid JSON: Unexpected token\nat line 2\n'
    world(on, { ...SIGNED_IN, files, modeOut: { exitCode: 2, stdout: '', stderr } })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^darkmem-config: \/home\/me\/\.dr-forge\/stores\.json is not valid JSON: Unexpected token$/ })).toBeDefined()
    await ui.unmount()
    const desk = await $.ui.mount({ ...PANE, surface: 'desktop' })
    expect(JSON.stringify(await desk.drawn())).toContain('stores.json is not valid JSON')
  })

  test('without node the checkout paths stay silently', async ($, on) => {
    const files = checkoutFiles()
    world(on, { ...SIGNED_IN, files, modeOut: 'missing' })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
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
      await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
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
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /darkmem-config\.mjs --mode gave no answer within 5 seconds/ })).toBeDefined()
  })

  test('a run that prints no mode lines keeps the checkout paths silently', async ($, on) => {
    const files = checkoutFiles()
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, modeRuns })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(modeRuns).toEqual(['/home/me/code/shop'])
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
    expect(await ui.find({ key: 'plan-roots' })).toBeUndefined()
  })

  test('reads the roots once per stores.json change, re-read from a mirror path', async ($, on) => {
    const files: NonNullable<World['files']> = { ...checkoutFiles(), '/home/me/.dr-forge/stores.json': { text: '{}', mtimeMs: 1 } }
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, modeRuns })
    signedIn(on, files)
    await $.session.start(START)
    expect(modeRuns).toEqual(['/home/me/code/shop'])
    await $.tool.call({ tool: 'Bash', command: 'cat ~/.dr-forge/mirror/shop/work/sdd/p/progress.md' })
    expect(modeRuns).toHaveLength(1)
    files['/home/me/.dr-forge/stores.json']!.mtimeMs = 2
    await $.tool.call({ tool: 'Bash', command: 'cat ~/.dr-forge/mirror/shop/work/sdd/p/progress.md' })
    expect(modeRuns).toEqual(['/home/me/code/shop', '/home/me/code/shop'])
  })

  test('resolves a plan under the docs root in darkmem, under the docs directory of each checkout otherwise', () => {
    const darkmem = { store: 'darkmem' as const, root: `${MIRROR}/superpowers` }
    const w = { root: '/w', docsDir: '/w/docs/forge' }
    const p = { root: '/p', docsDir: '/p/docs/forge' }
    for (const name of ['docs/superpowers/plans/p.md', 'docs/forge/plans/p.md', './docs/forge/plans/p.md']) {
      expect(planCandidates(name, darkmem, [w, p])).toEqual([`${MIRROR}/superpowers/plans/p.md`])
      // Either prefix names the same document: a pre-3.0 citation reads under each checkout's docs/forge.
      expect(planCandidates(name, { store: 'local', root: '/p/docs/forge' }, [w, p])).toEqual(['/w/docs/forge/plans/p.md', '/p/docs/forge/plans/p.md'])
      expect(planCandidates(name, null, [p, p])).toEqual(['/p/docs/forge/plans/p.md'])
    }
    expect(planCandidates('docs/plans/p.md', null, [w, p])).toEqual(['/w/docs/plans/p.md', '/p/docs/plans/p.md'])
    expect(planCandidates('/abs/plans/p.md', darkmem, [w])).toEqual(['/abs/plans/p.md'])
    expect(planCandidates('docs/superpowersx/p.md', darkmem, [w])).toEqual(['/w/docs/superpowersx/p.md'])
  })

  test('reads a plan named under docs/superpowers from a checkout that has only docs/forge', async ($, on) => {
    const files: World['files'] = {
      '/home/me/code/shop/.forge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
      '/home/me/code/shop/docs/forge/plans/p.md': { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 2: Draw the card/ })).toBeDefined()
  })

  test('reads no plan from a pre-3.0 docs/superpowers directory', async ($, on) => {
    const files: World['files'] = {
      '/home/me/code/shop/.forge/sdd/p/progress.md': { text: LEDGER.replace('docs/superpowers', 'docs/forge'), mtimeMs: 2_000_000 },
      '/home/me/code/shop/docs/superpowers/plans/p.md': { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 2: Draw the card/ })).toBeUndefined()
  })

  test('reads the ledger and the plan from the mirror when both families are in darkmem', async ($, on) => {
    const files: World['files'] = {
      [`${MIRROR}/work/sdd/p/progress.md`]: { text: LEDGER, mtimeMs: 2_000_000 },
      [`${MIRROR}/superpowers/plans/p.md`]: { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files, modeOut: { exitCode: 0, stdout: MODE, stderr: '' } })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Run' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Task 2: Draw the card/ })).toBeDefined()
    expect(await ui.find({ key: 'plan-roots' })).toBeUndefined()
  })

  test('offers Resume for latest.md in the mirror, naming it', async ($, on) => {
    const files: World['files'] = { [`${MIRROR}/work/handoff/latest.md`]: { text: '# Handoff', mtimeMs: 900_000 } }
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
      '/home/me/code/main/.forge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
      '/home/me/code/main/.forge/sdd/p/finish.json': { text: '{"action":"merge","base":"main","chosenAt":900}' },
      '/home/me/code/main/docs/forge/plans/p.md': { text: '# Plan\n\n### Task 1: Old title\n' },
      '/home/me/code/shop/.forge/sdd/p/finish.json': { text: '{"action":"pr","base":"main","chosenAt":900}' },
      '/home/me/code/shop/docs/forge/plans/p.md': { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files, primary: '/home/me/code/main' })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Finish push and open a PR/ })).toBeDefined()
  })

  test('a changed stores.json moves the card to the new roots', async ($, on) => {
    const files: NonNullable<World['files']> = {
      '/home/me/.dr-forge/stores.json': { text: '{}', mtimeMs: 1 },
      [`${MIRROR}/work/sdd/p/progress.md`]: { text: LEDGER, mtimeMs: 2_000_000 },
      [`${MIRROR}/superpowers/plans/p.md`]: { text: PLAN },
    }
    const w: World = { ...SIGNED_IN, files }
    world(on, w)
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Run' })).toBeUndefined()
    await ui.unmount()
    w.modeOut = { exitCode: 0, stdout: MODE, stderr: '' }
    files['/home/me/.dr-forge/stores.json']!.mtimeMs = 2
    await $.tool.call({ tool: 'Bash', command: 'cat ~/.dr-forge/stores.json' })
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Run' })).toBeDefined()
  })
})

describe('flight deck', () => {
  test('draws every panel the way the approved preview does', async ($, on) => {
    const ledger = [
      '# SDD ledger — plan: docs/plans/cockpit.md',
      'Task 3: implementer dr-forge:impl-sonnet-low (assigned; base abc1234)',
      'Task 3: complete (commits a..b, review clean) — done: x; verified: y; remaining: none; discovered: none; assumptions: none',
      'Task 4: implementer dr-forge:impl-sonnet-low (assigned; base def5678)',
      'Task 4: fix round 2/5 (1 addressed, 1 open — meter width; commits c..d; fresh)',
      'Task 5: BLOCKED — needs the ledger format',
    ].join('\n')
    const now = 1_000_000
    const files: World['files'] = {
      '/home/me/code/shop/.forge/sdd/p/progress.md': { text: ledger, mtimeMs: now },
      '/home/me/code/shop/docs/plans/cockpit.md': { text: '# Plan\n\n### Task 1: Read the budget\n\n### Task 2: Draw the strip\n\n### Task 3: Draw the context section\n\n### Task 4: Draw usage and agents\n\n### Task 5: Track the plan and repo\n\n### Task 6: Write the README\n' },
    }
    const w: World = { ...SIGNED_IN, files, remoteControl: 'true' }
    world(on, w)
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    for (const [i, t] of [180_000, 205_000, 228_000, 251_000, 270_000, 284_000].entries()) { w.tokens = t; await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: `turn-${i}`, reason: 'answer' }) }
    await $.session.measure({ context: { tokens: 284_000, window: 650_000 }, rateLimits: [{ kind: 'five_hour', percentUsed: 23, resetsAt: new Date(1_000_000 + 220 * 60_000).toISOString() }, { kind: 'seven_day', percentUsed: 61, resetsAt: new Date(1_000_000 + 86 * 3600_000).toISOString() }], cost: { usd: 4.85 }, changed: ['context', 'rateLimits'], breakdown: true } as never)
    w.tools = { Bash: () => ({ result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: `b${Math.random()}` }, text: 'Running in the background' }) }
    await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true } as never)
    await $.tool.call({ tool: 'Bash', command: 'pytest -x --watch', run_in_background: true } as never)
    w.tools = {}
    await $.tool.call({ tool: 'Bash', command: 'git commit -m "fix" -m "Co-Authored-By: Claude <noreply@anthropic.com>"' })
    await $.agent.spawn({ tool_use_id: 'toolu_1', prompt: 'Implement task 3', description: 'Review task 3', subagentType: 'dr-forge:judge-opus', provider: { plugin: 'dr-forge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: false, fork: false })
    await $.turn.complete({ answer: 'done', durationMs: 1000, isAborted: false, turnId: 'turn-9', agentId: 'agent-1', reason: 'answer', usage: { model: 'claude-opus-5-5', input_tokens: 4_000, cache_read_input_tokens: 46_000, cache_creation_input_tokens: 14_000, output_tokens: 3_000 } })
    await $.agent.spawn({ tool_use_id: 'toolu_2', prompt: 'Implement task 4', description: 'Task 4', subagentType: 'dr-forge:impl-sonnet-low', provider: { plugin: 'dr-forge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: false, fork: false })
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
    expect(drawn).toStartWith('{"type":"Box","props":{"flexDirection":"column","rowGap":1}')
    expect(drawn).toContain('"key":"usage","flexDirection":"column","borderStyle":"round","borderColor":"subtle","backgroundColor":"#8080800f"')
    expect(drawn).toContain('@media (prefers-color-scheme: dark)')
    expect(drawn).toContain('Opus 5.5, xhigh effort, Remote ○ on · no device yet, config ~/.claude')
    // Usage leaves the windows to their gauges and says what the ticks mean.
    expect(drawn).toContain("The gauges' ticks mark how far each window has run: 27% of 5h, 49% of 7d.")
    expect(drawn).not.toContain('of the window gone')
    expect(drawn).toContain('Shells: 2 running')
    expect(drawn).toContain('$ npm run dev 0s')
    // Each seat's counts sit on a row above its bar, with no title or caption.
    expect(drawn).toContain('judge-opus ×1 64k in · 72% cached · 3k out')
    expect(drawn).not.toContain('Seats by input')
    expect(drawn).not.toContain('prompt cache.')
    // The window's labels slide clear of each other rather than drop out.
    expect(drawn).toContain('>compacts 604k</text>')
    expect(drawn).toContain('>handoff 465k</text>')
    expect(drawn).toContain('+14k · 7 turns</text>')
    expect(drawn).toContain('Run: 1 blocked · round 2/5 · 1/6')
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
    layout: { type: 'enum', values: ['auto', 'full', 'compact'], default: 'auto', group: 'Cockpit', label: 'Layout', title: 'Layout', description: 'd', target: 'forge' },
    warnAt: { type: 'number', default: 80, min: 1, max: 99, group: 'Context', label: 'Warn at', title: 'Warn', description: 'd', target: 'forge' },
    handoffTokens: { type: 'number', default: 0, min: 0, max: 2_000_000, env: 'DR_FORGE_BUDGET', group: 'Context', label: 'Handoff budget', title: 'Budget', description: 'd', target: 'forge' },
    nudgeModel: { type: 'boolean', default: true, group: 'Context', label: 'Handoff note', title: 'Nudge', description: 'd', target: 'forge' },
  }

  test('resolves the environment, then the file, then the default', () => {
    expect(resolveSettings(FAKE, { layout: 'full', warnAt: 500, handoffTokens: 300_000 }, { DR_FORGE_BUDGET: '400000' })).toEqual({
      layout: 'full',
      warnAt: 80,
      handoffTokens: 400_000,
      nudgeModel: true,
    })
  })

  test('ignores an environment value that does not fit', () => {
    expect(resolveSettings(FAKE, { handoffTokens: 300_000 }, { DR_FORGE_BUDGET: 'junk' }).handoffTokens).toBe(300_000)
  })

  test('says which values it ignored', () => {
    expect(settingProblems(FAKE, { warnAt: 500, layout: 'full' }, { DR_FORGE_BUDGET: 'junk' })).toEqual([
      'warnAt in ~/.dr-forge/config.json is not valid; ignored',
      'DR_FORGE_BUDGET=junk is not a valid handoffTokens; ignored',
    ])
    expect(settingProblems(FAKE, { layout: 'full' }, {})).toEqual([])
  })

  test('a saved value drops its default and keeps darkmem', () => {
    const darkmem = { url: 'http://d.test', repos: {} }
    expect(settingWritten(FAKE, { darkmem, warnAt: 70 }, 'warnAt', 80)).toEqual({ darkmem })
    expect(settingWritten(FAKE, { darkmem }, 'layout', 'compact')).toEqual({ darkmem, layout: 'compact' })
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

describe('settings rows', () => {
  const ROWS: Schema = {
    layout: { type: 'enum', values: ['auto', 'full', 'compact'], default: 'auto', group: 'Cockpit', label: 'Layout', title: 'Layout', description: 'd', target: 'forge' },
    warnAt: { type: 'number', default: 80, min: 1, max: 99, step: 5, unit: '%', group: 'Context', label: 'Warn at', title: 'Warn', description: 'd', target: 'forge' },
    budget: { type: 'number', default: 0, min: 0, max: 2_000_000, step: 50_000, unit: 'k', zero: 'auto', env: 'DR_FORGE_BUDGET', group: 'Context', label: 'Handoff budget', title: 'Budget', description: 'd', target: 'forge' },
    note: { type: 'boolean', default: true, group: 'Context', label: 'Handoff note', title: 'Note', description: 'd', target: 'forge' },
    compactAt: { type: 'number', default: 0, min: 0, floor: 100_000, max: 1_000_000, step: 50_000, unit: 'k', zero: 'unset', group: 'Context', label: 'Auto-compact at', title: 'Compact', description: 'd', target: 'claude' },
    wait: { type: 'number', default: 30, min: 5, max: 240, step: 5, unit: 'min', group: 'Finish', label: 'Menu waits', title: 'Wait', description: 'd', target: 'forge' },
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
    expect(rowOf('budget', spec('budget'), 465_000, 'set by DR_FORGE_BUDGET')).toMatchObject({ shown: '465k', isChanged: false, lockedBy: 'set by DR_FORGE_BUDGET' })
    expect(rowsOf(ROWS, { warnAt: 70 }, 'Context', { budget: 'set by DR_FORGE_BUDGET' }).map(row => [row.key, row.isChanged, row.lockedBy])).toEqual([
      ['warnAt', true, null],
      ['budget', false, 'set by DR_FORGE_BUDGET'],
      ['note', false, null],
      ['compactAt', false, null],
    ])
  })

  test('says which keys something outside the file forces', () => {
    expect(envLocks(ROWS, { DR_FORGE_BUDGET: '400000' })).toEqual({ budget: 'set by DR_FORGE_BUDGET' })
    expect(envLocks(ROWS, { DR_FORGE_BUDGET: 'junk' })).toEqual({})
    expect(envLocks(ROWS, {})).toEqual({})
    expect(claudeLocks(ROWS, { compactAt: 500_000 }, { compactAt: 650_000 })).toEqual({ compactAt: 'set by a project or managed settings file' })
    expect(claudeLocks(ROWS, { compactAt: 650_000 }, { compactAt: 650_000 })).toEqual({})
    expect(claudeLocks(ROWS, {}, {})).toEqual({})
  })

  test('a Claude key resolves from the Claude settings and never enters the forge file', () => {
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
  const NOTE = 'dr-forge settings changed'

  test('a value the environment forces shows locked, and a group reset leaves it alone', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: { warnAt: 70, handoffTokens: 300_000 }, written, env: { DR_FORGE_BUDGET: '465000' } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: 'set by DR_FORGE_BUDGET' })).toBeDefined()
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

  test('a Claude key is saved through forge-config, never into the forge file', async ($, on) => {
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
    expect(runs[0]).toMatch(/^node .*\/scripts\/lib\/forge-config\.mjs set autoCompactWindow 700000$/)
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
    world(on, { tokens: 284_000, config: {}, toasts, isForgeConfigRefusing: true })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    await ui.press({ key: 'set-autoCompactWindow-more' })
    expect(toasts).toContain('dr-forge: autoCompactWindow not saved: /home/me/.claude/settings.json is not valid JSON; fix or remove it')
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

  test('a reset Claude key shows a project file that sets the same key once the engine sees the removal', async ($, on) => {
    const w: World = { tokens: 284_000, config: {}, settings: { autoCompactWindow: 650_000 }, userSettings: { autoCompactWindow: 650_000 } }
    world(on, w)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    await ui.press({ key: 'set-autoCompactWindow-reset' })
    // forge-config removed the key from the user file; the project file still sets it.
    w.userSettings = {}
    await ui.press({ key: 'set-autoCompactEnabled-toggle' })
    expect(await ui.find({ type: 'Text', text: 'set by a project or managed settings file' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^650k/ })).toBeDefined()
  })

  test('a changed skill setting is told to the model once, when the settings close', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 50_000, config: {}, notes, written: {} })
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Workflow' })
    await ui.press({ key: 'set-worktree-always' })
    await ui.press({ key: 'set-worktree-never' })
    await ui.press({ key: 'set-codexLane-toggle' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dr-forge settings changed: worktree=never. Each replaces the matching question or default in the skills.',
    ])
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toHaveLength(1)
  })

  test('leaving the settings through /cockpit tells the model too', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 50_000, config: {}, notes, written: {} })
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Workflow' })
    await ui.press({ key: 'set-worktree-always' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    await $.command.run({ ...COCKPIT, args: '' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dr-forge settings changed: worktree=always. Each replaces the matching question or default in the skills.',
    ])
  })

  test('a note the session refuses is sent at the next close', async ($, on) => {
    const notes: string[] = []
    const w: World = { tokens: 50_000, config: {}, notes, written: {}, isAppendFailing: true }
    world(on, w)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
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
      'dr-forge settings changed: worktree=always. Each replaces the matching question or default in the skills.',
    ])
  })

  test('outside a dr-forge session the note waits for one', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 50_000, config: {}, notes, written: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Process' })
    await ui.press({ key: 'set-designApproval-whole' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:brainstorming' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dr-forge settings changed: designApproval=whole. Each replaces the matching question or default in the skills.',
    ])
  })

  test('a dr-forge skill started as a slash command marks the session and sends the waiting note', async ($, on) => {
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
    expect(await $.skill.prompt({ skill: 'dr-forge:brainstorming', text: 'Brainstorm.' })).toEqual({ text: 'Brainstorm.' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dr-forge settings changed: designApproval=whole. Each replaces the matching question or default in the skills.',
    ])
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Workflow' })
    await ui.press({ key: 'set-worktree-never' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toHaveLength(2)
  })
})

// An auto run's state file in the primary checkout the world names.
const AUTO = '/home/me/code/shop/.forge/sdd/auto-run.json'
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
    expect(w.prompts?.[0]).toMatch(/scripts\/auto-run after-compact/)
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
      subagentType: 'dr-forge:impl-sonnet-low',
      provider: { plugin: 'dr-forge', tier: 'user' },
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
    const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], runs: [], userSettings: { model: 'opus[1m]' }, isForgeConfigRefusing: true, autoFile: files[AUTO] }
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
    expect(await ui.find({ type: 'Text', text: /Auto run · execute · normal · 1 compactions/ })).toBeDefined()
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

  test('books no engine compaction over a pending clear', async ($, on) => {
    const w: World = { ...SIGNED_IN, autoRuns: [] }
    world(on, w)
    signedIn(on, autoFiles({ pending: 'clear' }))
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

  test('reads a run only for its session, and its sentinel only as the last line', () => {
    const text = autoFiles({ session: 'b', launch: { model: 'sonnet', effort: 'high' } })[AUTO]!.text
    expect(autoRunFor(text, 'b')?.launch).toEqual({ model: 'sonnet', effort: 'high' })
    expect(autoRunFor(text, 'b')?.plan).toBe('docs/plan.md')
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
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
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
    const files = { ...autoFiles({ pending: null }), '/home/me/code/shop/.forge/handoff/latest.md': { text: '# Handoff', mtimeMs: 900_000 } }
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
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
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
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
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
