import { describe, expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'
import type { On, RenderElement, SessionMessage } from 'claude-code'

import type { SettingsFile } from '../hooks/cockpit/config'
import { SCHEMA, settingWritten } from '../hooks/cockpit/config'

// Acceptance tests for docs/dagents/specs/2026-11-18-per-worktree-handoff-design.md,
// the cockpit statements A9 and A12. The engine below is the same set of event
// answers the other cockpit suites use: it records what the plugin writes, runs,
// toasts and submits, and the tests reach the plugin only through the engine's
// events. A run of `scripts/next-step --print --handoff` is answered by the
// test, in turn.

const BAND = {
  plugin: 'dagents',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isCollapsed: false, isWorking: false, maxRows: 3, bodyColumns: 100, scroll: { offset: 0, bodyRows: 3 }, view: {} },
} as const
const HINT = {
  plugin: 'dagents',
  component: 'PromptHint',
  props: { isDraft: false, isWorking: false, hint: '? for shortcuts' },
} as const
const PANE = {
  plugin: 'dagents',
  component: 'Pane',
  requestId: 'dagents',
  props: { title: 'Cockpit', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
} as const
const PORCELAIN = '# branch.oid abc1234def\n# branch.head feat/pane\n# branch.ab +2 -1\n1 .M N... 100644 100644 100644 a b src/a.ts\n? notes.md\n'
const BREAKDOWN = {
  categories: [
    { name: 'Messages', tokens: 180_000, kind: 'used', color: '', isDeferred: false },
    { name: 'System tools', tokens: 38_000, kind: 'used', color: '', isDeferred: false },
    { name: 'Free space', tokens: 300_000, kind: 'free', color: '', isDeferred: false },
  ],
  isAutoCompactEnabled: true,
  autoCompactThreshold: 604_000,
  totalTokens: 218_000,
} as never
const START = { cwd: '/home/me/code/shop/web', surface: 'terminal', isInteractive: true } as never
const SUMMARY: SessionMessage = { role: 'user', text: 'Summary.', toolUses: [] }
const CONFIG = '/home/me/.dagents/config.json'

type World = {
  tokens: number | undefined
  window?: number
  startedAt?: number
  settings?: Record<string, unknown>
  /** What the user's own Claude settings file holds, when it differs from the merged `settings`. */
  userSettings?: Record<string, unknown>
  /** Each dagents-config command the plugin runs, as one line. */
  runs?: string[]
  /** dagents-config refuses, as on a Claude settings file it cannot parse. */
  isDagentsConfigRefusing?: boolean
  /** How many claude-restore writes the engine misses, as one landing right after its own save. */
  missedRestores?: number
  /** The session refuses every row the plugin appends. */
  isAppendFailing?: boolean
  /** The engine cannot report the session's usage. */
  isUsageFailing?: boolean
  toasts?: string[]
  notes?: string[]
  env?: Record<string, string>
  /** Files the plugin reads, by path, with their modification time. */
  files?: Record<string, { text: string; mtimeMs?: number; kind?: 'file' | 'dir' | 'other'; isLink?: boolean }>
  /** Paths whose stat rejects; the kit drops the code, so the mod sees a rejection with none. */
  statErrors?: Record<string, string>
  /** What the plugin writes, by path. */
  written?: Record<string, string>
  /** Each request the plugin sends through $.http.fetch. */
  prompts?: string[]
  fetches?: { url: string; method: string; body: Record<string, unknown> }[]
  /** Every fetch rejects, its message naming the URL as a host's might. */
  isFetchFailing?: boolean
  /** Every fetch stays unanswered, as on a stalled connection. */
  isFetchHanging?: boolean
  /** The first fetch answers 429 with this body; the next ones succeed. */
  rateLimitBody?: string
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
  /** ~/.dagents/config.json's values; set, HOME is /home/me and world answers reads of the file. */
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
  /** What each `next-step --print --handoff` run answers, in turn: an exit and its stdout, `timeout`, `hang` (never settles) or a function that settles it later; with none left, exit 6. */
  nextSteps?: ({ exitCode: number; stdout: string } | 'timeout' | 'hang' | { later: Promise<{ exitCode: number; stdout: string }> })[]
  /** Each `next-step --print --handoff` run, as the engine saw it. */
  nextStepRuns?: { argv: string; cwd: string; timeoutMs: number | undefined }[]
  /** How many next-step runs are in flight now, and the most that ever were. */
  inFlight?: { now: number; max: number }
  /** The agent ids the spawns get, in turn; `agent-1` once they run out. */
  agentIds?: string[]
  /** `node --version` cannot start, as on a machine without node. */
  isNodeMissing?: boolean
  /** What the session has cost, in dollars; 1.5 unless said. */
  usd?: number
  /** Runs inside each `command.run`, given the command word and its arguments, before it answers. */
  onCommand?: (command: string, args: string) => void
  /** The rate-limit windows `$.session.usage()` answers; none unless said. */
  rateLimits?: { kind: string; percentUsed: number; resetsAt?: string }[]
  /** The name of each command the plugin registers. */
  registered?: string[]
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
  /** What `git worktree list --porcelain` names. */
  worktrees?: string[]
  /** What `git rev-parse --show-toplevel` answers in the session's directory: the work tree it is in; the session repository's unless said. */
  checkout?: string
  /** Runs inside each scripts/auto-run call, given its command word, before the call answers. */
  onAutoRun?: (word: string) => unknown
  /** How many `$.session.id()` calls fail before one answers. */
  sessionIdFailures?: number
  /** Runs after each settings read has taken its answer, given the source it named. */
  afterSettingsRead?: (source: string | undefined) => void
  /** The draft the person's prompt box holds; empty unless said. */
  draft?: string
}

// The engine beneath the plugin: a context of `w.tokens` (read on each call,
// so a test moves it) in a 650k window, every tool call answered, every toast
// and every row the plugin appends recorded in `w.notes`.
function world(on: On, w: World) {
  mock.env(on, { ...(w.config === undefined ? {} : { HOME: '/home/me' }), ...(w.env ?? {}) })
  const clock = mock.clock(on, { now: 1_000_000 })
  on('command.register', (_$, e) => {
    w.registered?.push(e.name)
    return { value: undefined } as never
  })
  on('session.start', (_$, e) => e as never)
  on('session.usage', (_$, e) => {
    if (w.isUsageFailing) throw new Error('usage unavailable')
    return {
      value: {
        startedAt: w.startedAt ?? 0,
        context: {
          tokens: w.tokens,
          window: w.window ?? 650_000,
          ...(e.breakdown === undefined ? {} : { breakdown: BREAKDOWN }),
        },
        rateLimits: w.rateLimits ?? [],
        cost: { usd: w.usd ?? 1.5 },
      },
    }
  })
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
  on('prompt.read', () => ({ value: { text: w.draft ?? '', cursor: (w.draft ?? '').length } }))
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
    w.onCommand?.(e.command, e.args)
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
    if (argv.includes('/scripts/next-step') && argv.includes('--print --handoff')) {
      const extra = { cwd: '', timeoutMs: (e as unknown as { init?: { timeoutMs?: number } }).init?.timeoutMs }
      w.nextStepRuns?.push({ argv, cwd: extra.cwd ?? '', timeoutMs: extra.timeoutMs })
      const out = w.nextSteps?.shift() ?? { exitCode: 6, stdout: '' }
      const flight = w.inFlight
      if (flight !== undefined) {
        flight.now += 1
        flight.max = Math.max(flight.max, flight.now)
      }
      const done = (value: { exitCode: number; stdout: string }) => {
        if (flight !== undefined) flight.now -= 1
        return { value: { ...value, stderr: value.exitCode === 0 ? '' : 'next-step: failed\n', isStdoutTruncated: false, isStderrTruncated: false } }
      }
      if (out === 'hang') return new Promise<never>(() => undefined)
      if (out === 'timeout') {
        if (flight !== undefined) flight.now -= 1
        return { deny: 'dagents: $.process.run(bash) aborted: still running after 20000ms' }
      }
      if ('later' in out) return out.later.then(done)
      return done(out)
    }
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
        if (exitCode === 0 && word === 'clear') Object.assign(state, { pending: 'clear', rebind: true })
        if (exitCode === 0 && word === 'rebind') Object.assign(state, { session: words[4], pending: 'resume', regime: 'normal' })
        if (exitCode === 0 && word === 'resumed' && state.pending === 'resume') state.pending = null
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
    if (argv.includes('/scripts/lib/dagents-config.mjs ')) {
      w.runs?.push(argv)
      const restore = e.argv[e.argv.indexOf('claude-restore') + 1]
      if (e.argv.includes('claude-restore') && !w.isDagentsConfigRefusing && w.userSettings !== undefined) {
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
      // A dagents-target set rewrites the settings file as the cockpit's own
      // fallback write would, and fails as that write does.
      const at = e.argv.indexOf('set')
      const setKey = at < 0 ? undefined : e.argv[at + 1]
      const setSpec = setKey === undefined ? undefined : SCHEMA[setKey]
      if (setKey !== undefined && setSpec !== undefined && setSpec.target !== 'claude') {
        if (w.isNodeMissing) return { deny: 'dagents: $.process.run(node) failed to start: ENOENT: Executable not found in $PATH: "node"' }
        if (w.isReadOnly) return { value: { exitCode: 1, stdout: '', stderr: 'dagents-config: EROFS: read-only file system\n', isStdoutTruncated: false, isStderrTruncated: false } }
        const text = e.argv[at + 2] ?? ''
        const value = setSpec.type === 'boolean' ? text === 'true' : setSpec.type === 'number' ? Number(text) : text
        const current = w.written?.[CONFIG] ?? w.files?.[CONFIG]?.text ?? (w.config === undefined ? '{}' : JSON.stringify(w.config))
        const next = settingWritten(SCHEMA, JSON.parse(current) as SettingsFile, setKey, value)
        if (w.written !== undefined) w.written[CONFIG] = `${JSON.stringify(next, null, 2)}\n`
        else w.config = next
        if (w.files?.[CONFIG] !== undefined) w.files[CONFIG].text = JSON.stringify(next)
      }
      const stderr = w.isDagentsConfigRefusing ? 'dagents-config: /home/me/.claude/settings.json is not valid JSON; fix or remove it\n' : ''
      return { value: { exitCode: w.isDagentsConfigRefusing ? 1 : 0, stdout: '', stderr, isStdoutTruncated: false, isStderrTruncated: false } }
    }
    if (argv.includes('/scripts/lib/darkmem-config.mjs ')) {
      w.modeRuns?.push(e.argv[e.argv.length - 1] ?? '')
      if (w.modeOut === 'missing') {
        return clock.advance(5_000).then(() => ({ deny: 'dagents: $.process.run(node) failed to start: ENOENT: Executable not found in $PATH: "node"' }))
      }
      if (w.modeOut === 'rejects') return { deny: 'the engine refused to start the process' }
      if (w.modeOut === 'timeout') return { deny: 'dagents: $.process.run(node) aborted: still running after 5000ms' }
      const out = w.modeOut ?? { exitCode: 0, stdout: PORCELAIN, stderr: '' }
      return { value: { ...out, isStdoutTruncated: false, isStderrTruncated: false } }
    }
    if (argv === 'node --version') {
      if (w.isNodeMissing) return { deny: 'dagents: $.process.run(node) failed to start: ENOENT: Executable not found in $PATH: "node"' }
      return { value: { exitCode: 0, stdout: 'v24.18.0\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    }
    if (argv.startsWith('git --no-optional-locks') && w.gitStatusOut === 'timeout') return { deny: 'dagents: $.process.run(git) aborted: still running after 3000ms' }
    if (argv.startsWith('git --no-optional-locks') && w.gitStatusOut === 'missing') return { deny: 'dagents: $.process.run(git) failed to start: ENOENT' }
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
    if (argv === 'git rev-parse --show-toplevel') {
      return { value: { exitCode: 0, stdout: `${w.checkout ?? '/home/me/code/shop'}\n`, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    }
    if (argv === 'git worktree list --porcelain') {
      const stdout = (w.worktrees ?? []).map(dir => `worktree ${dir}\nHEAD 1234567\nbranch refs/heads/work\n`).join('\n')
      return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
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
    const code = w.statErrors?.[e.path]
    if (code !== undefined) throw Object.assign(new Error(code), { code })
    const file = w.files?.[e.path]
    if (file === undefined) throw new Error('ENOENT')
    return { value: { kind: file.kind ?? 'file', size: file.text.length, mtimeMs: file.mtimeMs ?? 0, isLink: file.isLink ?? false } }
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
  on('fs.exists', (_$, e) => ({ value: (w.config !== undefined && e.path === CONFIG) || e.path in (w.written ?? {}) || e.path in (w.files ?? {}) }))
  if (w.config !== undefined) {
    on('fs.read', (_$, e) => {
      if (e.path === CONFIG) return { value: w.written?.[CONFIG] ?? JSON.stringify(w.config) }
      throw new Error('ENOENT')
    })
  }
  on('http.fetch', (_$, e) => {
    const body = e.init?.body ?? '{}'
    if (typeof body !== 'string') throw new Error(`expected a text body for ${e.url}`)
    w.fetches?.push({ url: e.url, method: e.init?.method ?? 'GET', body: JSON.parse(body) as Record<string, unknown> })
    if (w.isFetchFailing) return { deny: `fetch failed for ${e.url}` }
    if (w.isFetchHanging) return new Promise<never>(() => undefined)
    if (w.rateLimitBody !== undefined && w.fetches?.length === 1) return { value: { status: 429, ok: false, headers: {}, text: w.rateLimitBody } }
    return { value: { status: 200, ok: true, headers: {}, text: '{"id":"m1"}' } }
  })
  on('ui.panes', () => ({ value: w.isPaneShut ? [] : [{ id: 'dagents', title: 'Cockpit', isShown: true, isFocused: false, isPlaced: true }] }))
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


// A signed-in account working in a repository under home. In a linked
// worktree the engine names the main working tree as the repository's root.
const SIGNED_IN = { tokens: 284_000, env: { HOME: '/home/me' }, settings: { effortLevel: 'xhigh' } }
function signedIn(on: On, files: World['files'] = {}, reads?: string[], repoRoot = '/home/me/code/shop', cwd = () => '/home/me/code/shop/web', model: string | (() => string) = 'claude-opus-5-5[1m]') {
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
  on('session.cwd', () => ({ value: cwd() }))
  on('session.repo', () => ({ value: { root: repoRoot, remote: null, internal: false, name: null } }))
  on('session.model', () => ({ value: typeof model === 'string' ? model : model() }))
}

/** Lets timers at the current instant fire and their work finish. */
async function settle(clock: ReturnType<typeof world>) {
  for (let i = 0; i < 10; i++) await clock.advance(1)
}

const PRIMARY = '/home/me/code/shop'
const WORKTREE = '/home/me/code/shop-w1'
const PRIMARY_LATEST = `${PRIMARY}/.dagents/handoff/latest.md`
const WORKTREE_LATEST = `${WORKTREE}/.dagents/handoff/latest.md`
const PLAN = 'docs/dagents/plans/2026-10-14-band.md'

const marker = (at: number) => `<!-- next-step: kind=plan done=0 closed=0 subject=${PLAN} at=${at} -->`
/** A block as next-step writes it; a null `prompt` leaves the first-prompt fence empty, so the offer carries no prompt of its own. */
const block = (next: string, prompt: string | null, at: number) =>
  [
    '## Next session',
    '',
    `**Status:** Plan \`${PLAN}\`: 1 of 6 tasks complete.`,
    `**Next:** ${next}`,
    '',
    'Paste as the first prompt:',
    '',
    '```',
    ...(prompt === null ? [] : [prompt]),
    '```',
    marker(at),
    '',
  ].join('\n')
const stored = (next: string, prompt: string | null, at: number) => `# Handoff\n\n${block(next, prompt, at)}`
const exit0 = (next: string, prompt: string, at: number) => ({ exitCode: 0, stdout: block(next, prompt, at) })

type Begin = { files: NonNullable<World['files']>; cwd: string; checkout: string; nextSteps?: World['nextSteps'] }
async function begin($: Parameters<TestBody>[0], on: On, o: Begin) {
  const w = {
    ...SIGNED_IN,
    files: o.files,
    prompts: [] as string[],
    nextStepRuns: [] as NonNullable<World['nextStepRuns']>,
    nextSteps: o.nextSteps ?? [],
    primary: PRIMARY,
    checkout: o.checkout,
    worktrees: [PRIMARY, WORKTREE],
  }
  const clock = world(on, w)
  signedIn(on, o.files, undefined, PRIMARY, () => o.cwd)
  await $.session.start({ cwd: o.cwd, surface: 'terminal', isInteractive: true } as never)
  await settle(clock)
  return { ...w, clock }
}

describe('per-worktree-handoff: the cockpit reads its own checkout (A9, A12)', () => {
  test("A9: a worktree session's resume offer is built from the worktree's handoff, not the primary's", async ($, on) => {
    const files = {
      [WORKTREE_LATEST]: { text: stored('WORKTREE-STORED-NEXT', 'Worktree stored prompt.', 900), mtimeMs: 900_000 },
      [PRIMARY_LATEST]: { text: stored('PRIMARY-STORED-NEXT', 'Primary stored prompt.', 900), mtimeMs: 900_000 },
      [WORKTREE]: { text: '', kind: 'dir' as const, mtimeMs: 1 },
    }
    const w = await begin($, on, { files, cwd: WORKTREE, checkout: WORKTREE, nextSteps: [{ exitCode: 1, stdout: '' }] })
    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await band.find({ type: 'Text', text: /Next: WORKTREE-STORED-NEXT$/ })).toBeDefined()
    expect(JSON.stringify(await band.drawn())).not.toContain('PRIMARY-STORED-NEXT')
    expect(w.nextStepRuns).toHaveLength(1)
    expect(w.nextStepRuns[0]!.argv).toContain(WORKTREE)
    await band.press({ key: 'band-resume' })
    expect(w.prompts).toEqual(['Worktree stored prompt.'])
  })

  test("A9: the resume prompt of a worktree session names the worktree's handoff by absolute path", async ($, on) => {
    const files = {
      [WORKTREE_LATEST]: { text: stored('WORKTREE-STORED-NEXT', null, 900), mtimeMs: 900_000 },
      [PRIMARY_LATEST]: { text: stored('PRIMARY-STORED-NEXT', null, 900), mtimeMs: 900_000 },
      [WORKTREE]: { text: '', kind: 'dir' as const, mtimeMs: 1 },
    }
    const w = await begin($, on, { files, cwd: WORKTREE, checkout: WORKTREE, nextSteps: [{ exitCode: 1, stdout: '' }] })
    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    await band.press({ key: 'band-resume' })
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts[0]).toContain(WORKTREE_LATEST)
    expect(w.prompts[0]).not.toContain(PRIMARY_LATEST)
  })

  test("A9: a handoff in the primary raises no offer in a worktree session", async ($, on) => {
    const files = {
      [PRIMARY_LATEST]: { text: stored('PRIMARY-STORED-NEXT', 'Primary stored prompt.', 900), mtimeMs: 900_000 },
      [WORKTREE]: { text: '', kind: 'dir' as const, mtimeMs: 1 },
    }
    const w = await begin($, on, { files, cwd: WORKTREE, checkout: WORKTREE, nextSteps: [exit0('Recomputed.', 'p', 950)] })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await band.find({ key: 'band-resume' })).toBeUndefined()
    expect(await ui.find({ key: 'resume-card' })).toBeUndefined()
    expect(JSON.stringify(await band.drawn())).not.toContain('PRIMARY-STORED-NEXT')
    expect(w.nextStepRuns.filter(run => run.argv.includes('--print --handoff'))).toHaveLength(0)
  })

  test("A12: a primary session reads the primary's handoff as before", async ($, on) => {
    const files = {
      [PRIMARY_LATEST]: { text: stored('PRIMARY-STORED-NEXT', 'Primary stored prompt.', 900), mtimeMs: 900_000 },
    }
    const w = await begin($, on, { files, cwd: PRIMARY, checkout: PRIMARY, nextSteps: [{ exitCode: 1, stdout: '' }] })
    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await band.find({ type: 'Text', text: /Next: PRIMARY-STORED-NEXT$/ })).toBeDefined()
    await band.press({ key: 'band-resume' })
    expect(w.prompts).toEqual(['Primary stored prompt.'])
  })

  test("A12: the primary session's resume prompt names the primary's handoff path", async ($, on) => {
    const files = {
      [PRIMARY_LATEST]: { text: stored('PRIMARY-STORED-NEXT', null, 900), mtimeMs: 900_000 },
    }
    const w = await begin($, on, { files, cwd: PRIMARY, checkout: PRIMARY, nextSteps: [{ exitCode: 1, stdout: '' }] })
    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    await band.press({ key: 'band-resume' })
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts[0]).toContain(PRIMARY_LATEST)
  })
})

// A8, the cockpit's part: the phase clear runs in a session whose checkout is a
// linked worktree, and `$.process.run` takes no directory, so the call has to
// carry the checkout the auto run's plan executes in.

const SWITCH_ANSWER = 'Plan saved.\n\nAuto run: switching'
const FIRST_PROMPT = 'Execute docs/plan.md with dagents:executing-plans.'
const FAILURE_CAP = 2
const AUTO = '/home/me/code/shop/.dagents/sdd/auto-run.json'

type PhaseWorld = {
  prompts: string[]
  autoRuns: string[]
  /** The whole argv of each scripts/auto-run call. */
  autoArgv: string[][]
  commands: string[]
  sessionId: string
  autoFile: { text: string }
}

function phaseWorld(on: On, w: PhaseWorld) {
  mock.env(on, { HOME: '/home/me' })
  const clock = mock.clock(on, { now: 1_000_000 })
  on('command.register', () => ({ value: undefined }) as never)
  on('session.start', (_$, e) => e as never)
  on('session.usage', () => ({ value: { startedAt: 0, context: { tokens: 284_000, window: 650_000 }, rateLimits: [], cost: { usd: 1.5 } } }))
  on('settings.read', () => ({ value: { effortLevel: 'xhigh' } }))
  on('tool.call', () => ({ result: 'ok', text: 'ok' }) as never)
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'agent-1' }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('prompt.submit', (_$, e) => {
    w.prompts.push(e.text)
    return { text: e.text }
  })
  on('session.attach', (_$, e) => ({ clientId: e.clientId }))
  on('session.detach', (_$, e) => ({ clientId: e.clientId }))
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('config.list', () => ({ value: [] }) as never)
  on('ui.open', () => ({ value: { isPlaced: true } }) as never)
  on('ui.close', () => ({ value: undefined }) as never)
  on('ui.panes', () => ({ value: [] }))
  on('session.compact', (_$, e) => {
    w.compacts.push(`${e.trigger}:${(e as { instructions?: string }).instructions ?? ''}`)
    return { messages: e.messages ?? [SUMMARY] }
  })
  on('command.run', (_$, e) => {
    w.commands.push(e.args === '' ? `/${e.command}` : `/${e.command} ${e.args}`)
    if (e.command === 'clear') w.sessionId = 'sess-2'
    return { text: '' } as never
  })
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('session.id', () => ({ value: w.sessionId }))
  on('session.cwd', () => ({ value: WORKTREE }))
  on('session.repo', () => ({ value: { root: '/home/me/code/shop', remote: null, internal: false, name: null } }))
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
  on('fs.read', (_$, e) => {
    if (e.path === AUTO) return { value: w.autoFile.text }
    if (e.path === '/home/me/.claude.json') {
      return { value: JSON.stringify({ oauthAccount: { emailAddress: 'me@example.com', displayName: 'Me', organizationName: 'Acme', organizationRole: 'admin', billingType: 'stripe_subscription' } }) }
    }
    throw new Error('ENOENT')
  })
  on('fs.stat', (_$, e) => {
    if (e.path === AUTO) return { value: { kind: 'file', size: w.autoFile.text.length, mtimeMs: 0, isLink: false } }
    if (e.path === WORKTREE) return { value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false } }
    throw new Error('ENOENT')
  })
  on('fs.list', () => {
    throw new Error('ENOENT')
  })
  on('fs.write', () => ({ value: undefined }))
  on('http.fetch', () => ({ value: { status: 200, ok: true, headers: {}, text: '{"id":"m1"}' } }))
  on('session.append', (_$, e, next) => next(e))
  on('ui.toast', () => ({ value: undefined }))
  on('process.run', (_$, e) => {
    const argv = e.argv.join(' ')
    const script = '/scripts/auto-run '
    const result = (exitCode: number, stdout = '') => ({ value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } })
    if (argv.includes(script)) {
      w.autoArgv.push(e.argv)
      const call = argv.slice(argv.indexOf(script) + script.length)
      w.autoRuns.push(call)
      const words = call.split(' ')
      const verb = words[2] ?? ''
      const exitCode = verb === 'failure' ? 0 : (w.exits[verb] ?? 0)
      const state = JSON.parse(w.autoFile.text) as Record<string, unknown>
      if (verb === 'clear' && exitCode === 0) Object.assign(state, { pending: 'clear', rebind: true })
      if (verb === 'rebind') Object.assign(state, { session: words[4], pending: 'resume' })
      if (verb === 'resumed' && state.pending === 'resume') state.pending = null
      if (verb === 'compacted') Object.assign(state, { pending: 'after-compact', compactions: Number(state.compactions) + 1 })
      if (verb === 'failure') {
        state.failures = Number(state.failures ?? 0) + 1
        if (Number(state.failures) >= FAILURE_CAP) {
          Object.assign(state, { active: false, pending: null, stopped: call.split(' --reason ')[1] ?? null })
          w.autoFile.text = JSON.stringify(state)
          return result(5)
        }
      }
      w.autoFile.text = JSON.stringify(state)
      return result(exitCode)
    }
    if (argv === 'node --version') return result(0, 'v24.18.0\n')
    const toplevel = /^git -C (.+) rev-parse --show-toplevel$/.exec(argv)
    if (toplevel !== null) return result(0, `${toplevel[1]}\n`)
    if (argv === 'git rev-parse --show-toplevel') return result(0, `${WORKTREE}\n`)
    if (argv.startsWith('git rev-parse')) return result(0, '/home/me/code/shop/.git\n')
    return result(0, '# branch.oid abc1234def\n# branch.head main\n')
  })
  on('ui.render', ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    if (e.component === 'PromptHint') return h(Text, {}, e.props.tail ?? '') as RenderElement
    return h(Box, { key: 'engine' }) as RenderElement
  })
  return clock
}


describe('per-worktree-handoff: the cockpit phase clear (A8)', () => {
  test("A8: the switch's clear --phase passes the session's worktree checkout in its argv", async ($, on) => {
    const w: PhaseWorld = {
      prompts: [],
      autoRuns: [],
      autoArgv: [],
      commands: [],
      sessionId: 'sess-1',
      autoFile: {
        text: JSON.stringify({
          active: true, session: 'sess-1', phase: 'execute', regime: 'normal', pending: 'switch', plan: 'docs/plan.md', compactions: 0,
          resumes: 0, failures: 0, rebind: false, setupDue: true, stopped: null, resumePrompt: FIRST_PROMPT, launch: { model: 'sonnet', effort: 'high' },
        }),
      },
    }
    const clock = phaseWorld(on, w)
    await $.session.start({ cwd: WORKTREE, surface: 'terminal', isInteractive: true } as never)
    await $.turn.complete({ answer: SWITCH_ANSWER, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' } as never)
    await settle(clock)
    const clearIndex = w.autoRuns.findIndex(call => call.endsWith(' clear --phase'))
    expect(clearIndex, 'the cockpit ran clear --phase').toBeGreaterThanOrEqual(0)
    expect(w.autoArgv[clearIndex]!.some(part => part.includes(WORKTREE)), `argv ${JSON.stringify(w.autoArgv[clearIndex])} names the worktree`).toBe(true)
  })
})
