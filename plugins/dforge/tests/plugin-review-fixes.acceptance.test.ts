import { describe, expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'
import type { On, RenderElement, SessionMessage } from 'claude-code'

import { parseLedger } from '../hooks/cockpit/lib'
import type { SettingsFile } from '../hooks/cockpit/config'
import { SCHEMA, settingWritten } from '../hooks/cockpit/config'

// Acceptance tests for docs/dforge/specs/2026-11-15-plugin-review-fixes-design.md,
// the cockpit statements. The engine below is the same set of event answers the
// other cockpit suites use: it records what the plugin writes, runs, toasts and
// submits, and the tests reach the plugin only through the engine's events.

const BAND = {
  plugin: 'dforge',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isCollapsed: false, isWorking: false, maxRows: 3, bodyColumns: 100, scroll: { offset: 0, bodyRows: 3 }, view: {} },
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
const CONFIG = '/home/me/.dforge/config.json'

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
    if (argv.includes('/scripts/lib/dforge-config.mjs ')) {
      w.runs?.push(argv)
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
  if (w.config !== undefined) {
    on('fs.exists', (_$, e) => ({ value: e.path === CONFIG || e.path in (w.written ?? {}) || e.path in (w.files ?? {}) }))
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

// The host keeps the cockpit's values per session: after the returned call,
// as in the session a /clear or /resume carries the process into, each reads
// as never written until the cockpit writes it again.
function wipesState(on: On) {
  let kept: Set<string> | null = null
  on('state.get', { plugin: 'dforge' } as never, (async (_$: unknown, e: { key: string }, next: (e: unknown) => Promise<{ value: { version: number } }>) => {
    const held = await next(e)
    return kept !== null && !kept.has(e.key) ? { value: { value: undefined, version: held.value.version } } : held
  }) as never)
  on('state.set', { plugin: 'dforge' } as never, ((_$: unknown, e: { key: string }, next: (e: unknown) => unknown) => {
    kept?.add(e.key)
    return next(e)
  }) as never)
  return () => {
    kept = new Set()
  }
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

function configured(values: Record<string, unknown>): NonNullable<World['files']> {
  return { [CONFIG]: { text: JSON.stringify(values) } }
}
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
const bg = (id: string) => ({ Bash: () => ({ result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: id }, text: 'Running in the background' }) })

const STATE_FILE = '/home/me/.claude/dforge/sessions/state/sess-1.json'

describe('plugin-review-fixes: the session state file and fast mode', () => {
  const stateOf = (written: Record<string, string>) => JSON.parse(written[STATE_FILE] ?? 'null') as Record<string, unknown> & { updated: number }
  const said = ($: Parameters<TestBody>[0], text: string, n: number) =>
    $.session.append({ message: { type: 'assistant', role: 'assistant', content: [{ type: 'text', text }] }, door: 'response', origin: { kind: 'model' }, uuid: `acc-${n}` } as never)

  test('A14: the cockpit writes the session state file at session start, prompt submit and turn end', async ($, on) => {
    const written: Record<string, string> = {}
    const clock = world(on, { ...SIGNED_IN, written, window: 650_000 })
    signedIn(on, {})
    expect(written[STATE_FILE]).toBeUndefined()
    await $.session.start(START)
    const atStart = stateOf(written)
    expect(atStart.session).toBe('sess-1')
    expect(atStart.window).toBe(650_000)
    expect(Array.isArray(atStart.launches)).toBe(true)
    expect(typeof atStart.updated).toBe('number')
    await clock.advance(5_000)
    await $.prompt.submit({ text: 'go on', wait: false } as never)
    const atSubmit = stateOf(written)
    expect(atSubmit.updated).toBeGreaterThan(atStart.updated)
    await clock.advance(5_000)
    await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    expect(stateOf(written).updated).toBeGreaterThan(atSubmit.updated)
  })

  test('A14: a launch that starts is in the file, and one that ends is out of it', async ($, on) => {
    const written: Record<string, string> = {}
    const w: World = { ...SIGNED_IN, written, tools: bg('b1') }
    world(on, w)
    signedIn(on, {})
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'npm test', description: 'Suite', run_in_background: true } as never)
    expect((stateOf(written).launches as { id: string }[]).map(l => l.id)).toEqual(['b1'])
    await $.session.append({ message: { type: 'user', role: 'user', content: [{ type: 'text', text: '<task-notification>\n<task-id>b1</task-id>\n<status>completed</status>\n</task-notification>' }] }, door: 'queue', origin: { kind: 'task-notification' }, uuid: 'n1' } as never)
    expect(stateOf(written).launches).toEqual([])
  })

  const nudge = async ($: Parameters<TestBody>[0], on: On, fast: boolean) => {
    const notes: string[] = []
    const w: World = { tokens: 440_000, notes }
    world(on, w)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:brainstorming' })
    if (fast) await said($, 'Process: fast — a one-line fix', 1)
    w.tokens = 470_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.turn.complete({ answer: 'Done.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    return notes.filter(text => /handoff/i.test(text))
  }
  test('A19: without fast mode a session far over its budget is nudged to hand off (control)', async ($, on) => {
    expect((await nudge($, on, false)).length).toBeGreaterThan(0)
  })
  test('A19: the budget nudge never fires while fast mode is on', async ($, on) => {
    expect(await nudge($, on, true)).toEqual([])
  })
})

describe('plugin-review-fixes: auto-run reconcile and relaxed handoff', () => {
  test('A20: a bare sleep launch alone is never named idle work, however long it runs', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO], tools: bg('qa1') }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'sleep 3600', run_in_background: true } as never)
    await $.turn.complete({ answer: 'Waiting for QA.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(3_000_000)
    expect(w.prompts?.filter(text => /Background work has run|TaskStop|idle/.test(text))).toEqual([])
  })

  test('A20: a finite background command alone does draw the reconcile prompt (control)', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO], tools: bg('b9') }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'npm test', run_in_background: true } as never)
    await $.turn.complete({ answer: 'Waiting.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(1_300_000)
    expect(w.prompts?.filter(text => /Background work has run/.test(text)).length).toBe(1)
  })

  const ledger = (extra: string) => ({
    '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: `# SDD ledger — plan: docs/plans/p.md\nTask 1: complete (commits a..b, review clean) — done: x${extra}`, mtimeMs: 2_000_000 },
    '/home/me/code/shop/docs/plans/p.md': { text: '# Plan\n\n### Task 1: Only\n\n### Task 2: Second\n' },
  })
  const handoffNotes = async ($: Parameters<TestBody>[0], on: On, files: World['files'], tokens: number) => {
    const notes: string[] = []
    world(on, { ...SIGNED_IN, tokens, notes, files })
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:executing-plans' })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    return notes.filter(text => /— handoff\./.test(text))
  }
  test('A24: in relaxed handoff mode the cockpit adds no handoff note during the final phase', async ($, on) => {
    const files = {
      ...configured({ handoffMode: 'relaxed' }),
      ...ledger('\nTask 2: complete (commits b..c, review clean) — done: y'),
    }
    expect(await handoffNotes($, on, files, 600_000)).toEqual([])
  })
})

describe('plugin-review-fixes: the judge write guard', () => {
  const STATE = '/home/me/code/shop/.dforge'
  const WS = `${STATE}/sdd/2026-11-15-plan`
  const REFUSED = /^dforge: a review seat writes only the report file/
  const spawn = (prompt: string, subagentType: string, n: number) =>
    ({ tool_use_id: `toolu_acc_${n}`, prompt, description: 'Re-review', subagentType, provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: true, fork: false }) as never
  const write = ($: Parameters<TestBody>[0], agentId: string, path: string) => $.tool.call({ tool: 'Write', file_path: path, content: 'x', agentId } as never)

  test('A31: a write to a prior round report named in a direct re-review prompt is refused; the prompt\'s report line is accepted', async ($, on) => {
    const PRIOR = `${WS}/final-review-round-1-report.md`
    const NEXT = `${WS}/final-review-round-2-report.md`
    world(on, { tokens: 10_000, agentIds: ['judge-1'] })
    on('agent.list', () => ({ value: [] }) as never)
    await $.session.start(START)
    await $.agent.spawn(spawn(`Round 1 found issues, see ${PRIOR}.\nWrite your full report to ${NEXT}, then reply in 10 lines.`, 'dforge:judge-opus', 1))
    expect((await write($, 'judge-1', PRIOR)).deny).toMatch(REFUSED)
    expect((await write($, 'judge-1', NEXT)).deny).toBeUndefined()
  })
})
