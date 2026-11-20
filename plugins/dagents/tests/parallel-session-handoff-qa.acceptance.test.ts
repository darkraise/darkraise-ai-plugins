import { describe, expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'
import type { On, RenderElement, SessionMessage } from 'claude-code'

import type { SettingsFile } from '../hooks/cockpit/config'
import { SCHEMA, settingWritten } from '../hooks/cockpit/config'

// Acceptance tests for docs/dforge/specs/2026-11-20-parallel-session-handoff-design.md,
// the cockpit parts of A9 and A20, written from the spec's Acceptance section:
// the resume offer is the newest handoff of the session's checkout that is
// unclaimed or claimed by a gone session and does not recompute to exit 6; a
// handoff a live other session claims, or this session claims, raises no
// offer, including when the claim is taken after the offer appeared. The
// engine below answers the plugin's events: `scripts/handoff list` as the
// script judges claims, `scripts/next-step --print --handoff` in turn, and the
// files of a session's checkout and its cockpit heartbeats.

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
  /** The primary checkout `git rev-parse --git-common-dir` points into; the session's repository unless said. */
  primary?: string
  /** What each `next-step --print --handoff` run answers, in turn: an exit and its stdout, `timeout`, `hang` (never settles) or a function that settles it later; with none left, exit 6. */
  nextSteps?: ({ exitCode: number; stdout: string } | 'timeout' | 'hang' | { later: Promise<{ exitCode: number; stdout: string }> })[]
  /** What `scripts/handoff list --checkout` prints, one tab-separated line per handoff, computed when it runs. */
  handoffList?: () => string
  /** Each `scripts/handoff list` call, as one line. */
  handoffRuns?: string[]
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
    if (argv.includes('/scripts/handoff ') && argv.includes(' list')) {
      w.handoffRuns?.push(argv)
      return { value: { exitCode: 0, stdout: w.handoffList?.() ?? '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
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

const TOP = '/home/me/code/shop'
const HDIR = `${TOP}/.dagents/handoff`
const CLAIMS = `${HDIR}/claims`
const OWN = 'sess-1'
const OTHER = 'aaaaaaaa-1111-2222-3333-444444444444'
const heartbeat = (sid: string) => `/home/me/.claude/dagents/sessions/cockpit/${sid.replace(/[^A-Za-z0-9]/g, '-')}`
// The clock stands at 1,000 seconds: a beat of 1,000 is live, one of 1 is long gone.
const LIVE = '1000\n'
const GONE = '1\n'

const subjectOf = (key: string) => `docs/dagents/plans/${key}.md`
const marker = (key: string, at: number) => `<!-- next-step: kind=plan key=${key} session=- done=0 closed=0 subject=${subjectOf(key)} at=${at} -->`
/** A block as next-step writes it; with `prompt` empty, the cockpit's own resume prompt is used. */
const block = (key: string, next: string, prompt: string, at: number) =>
  ['## Next session', '', `**Status:** Plan \`${subjectOf(key)}\`: 1 of 6 tasks complete.`, `**Next:** ${next}`, '', `Launch in \`${TOP}\`:`, '', '```', 'claude --model opus', '```', '',
   'Paste as the first prompt:', '', '```', prompt, '```', marker(key, at), ''].join('\n')
const stored = (key: string, next: string, at: number) => `# Handoff\n\n## Notes\n\nNotes for ${key}.\n\n${block(key, next, 'Stored prompt.', at)}`
const exit0 = (key: string, next: string, prompt: string) => ({ exitCode: 0, stdout: block(key, next, prompt, 950) })
const exit6 = { exitCode: 6, stdout: '' }

type Claim = { session: string; mtimeMs?: number }
type Scene = {
  /** The session's handoffs: key, text and modification time. */
  handoffs: { key: string; text: string; mtimeMs: number }[]
  claims?: Record<string, Claim>
  beats?: Record<string, string>
}
/** The files of a scene, as the session's checkout holds them. */
function filesOf(scene: Scene): NonNullable<World['files']> {
  const files: NonNullable<World['files']> = {}
  for (const one of scene.handoffs) files[`${HDIR}/${one.key}.md`] = { text: one.text, mtimeMs: one.mtimeMs }
  for (const [key, claim] of Object.entries(scene.claims ?? {})) files[`${CLAIMS}/${key}`] = { text: `session=${claim.session}\nat=1000\n`, mtimeMs: claim.mtimeMs ?? 990_000 }
  for (const [sid, text] of Object.entries(scene.beats ?? {})) files[heartbeat(sid)] = { text, mtimeMs: 1 }
  return files
}
/** What `scripts/handoff list --checkout` prints for the files as they stand now: the claim column is unclaimed, `claimed <id8> live` or `claimed <id8> gone`. */
function listingOf(files: NonNullable<World['files']>): () => string {
  return () =>
    Object.keys(files)
      .filter(path => path.startsWith(`${HDIR}/`) && path.endsWith('.md') && !path.slice(HDIR.length + 1).includes('/'))
      .map(path => {
        const key = path.slice(HDIR.length + 1, -3)
        const claim = files[`${CLAIMS}/${key}`]
        const session = claim === undefined ? null : (/^session=(\S+)/m.exec(claim.text)?.[1] ?? null)
        const beat = session === null ? undefined : files[heartbeat(session)]?.text
        const isLive = beat !== undefined && Math.abs(1000 - Number(beat.trim())) <= 180
        const state = session === null ? 'unclaimed' : `claimed ${session.slice(0, 8)} ${isLive ? 'live' : 'gone'}`
        return [path, key, 'plan', '50', state].join('\t')
      })
      .join('\n')
}

async function begin($: Parameters<TestBody>[0], on: On, scene: Scene, w: Partial<World> = {}) {
  const files = filesOf(scene)
  const world_ = {
    ...SIGNED_IN,
    files,
    prompts: [] as string[],
    nextStepRuns: [] as NonNullable<World['nextStepRuns']>,
    handoffRuns: [] as string[],
    handoffList: listingOf(files),
    inFlight: { now: 0, max: 0 },
    ...w,
  }
  const clock = world(on, world_)
  signedIn(on, files)
  await $.session.start(START)
  await settle(clock)
  const turn = async () => {
    await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 'turn-1', reason: 'answer' })
    await settle(clock)
  }
  const run = (index: number) => /--handoff (\S+)/.exec(world_.nextStepRuns[index]?.argv ?? '')?.[1]
  return { ...world_, files, clock, turn, run }
}
const offered = async ($: Parameters<TestBody>[0]) => {
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  return { band, hasOffer: (await band.find({ key: 'band-resume' })) !== undefined }
}

describe('parallel-session-handoff: the cockpit resume offer (A9)', () => {
  test('A9: the newest unclaimed handoff of the checkout is offered, recomputed from that file', async ($, on) => {
    const w = await begin($, on, {
      handoffs: [
        { key: 'older', text: stored('older', 'Older: Task 1.', 800), mtimeMs: 800_000 },
        { key: 'newer', text: stored('newer', 'Newer: Task 2.', 900), mtimeMs: 900_000 },
      ],
    }, { nextSteps: [exit0('newer', 'Recomputed newer: Task 3.', 'Recomputed prompt.')] })
    const { band, hasOffer } = await offered($)
    expect(hasOffer).toBe(true)
    expect(await band.find({ type: 'Text', text: /Next: Recomputed newer: Task 3\.$/ })).toBeDefined()
    expect(w.nextStepRuns).toHaveLength(1)
    expect(w.run(0)).toBe(`${HDIR}/newer.md`)
    expect(w.handoffRuns.length).toBeGreaterThan(0)
    expect(w.handoffRuns[0]).toContain('--checkout')
  })

  test("A9: the resume prompt names the offered file when next-step gives none", async ($, on) => {
    const w = await begin($, on, {
      handoffs: [{ key: 'only', text: stored('only', 'Only: Task 2.', 900), mtimeMs: 900_000 }],
    }, { nextSteps: [exit0('only', 'Recomputed: Task 3.', '')] })
    const { band } = await offered($)
    await band.press({ key: 'band-resume' })
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts[0]).toContain(`${HDIR}/only.md`)
    expect(w.prompts[0]).toMatch(/claim/)
  })

  test('A9: a handoff claimed by a gone session is offered', async ($, on) => {
    const w = await begin($, on, {
      handoffs: [{ key: 'held', text: stored('held', 'Held: Task 2.', 900), mtimeMs: 900_000 }],
      claims: { held: { session: OTHER } },
      beats: { [OTHER]: GONE },
    }, { nextSteps: [exit0('held', 'Recomputed: Task 3.', 'Prompt.')] })
    expect((await offered($)).hasOffer).toBe(true)
    expect(w.run(0)).toBe(`${HDIR}/held.md`)
  })

  test('A9: a handoff claimed by a live other session raises no offer, and next-step is not run for it', async ($, on) => {
    const w = await begin($, on, {
      handoffs: [{ key: 'held', text: stored('held', 'Held: Task 2.', 900), mtimeMs: 900_000 }],
      claims: { held: { session: OTHER } },
      beats: { [OTHER]: LIVE },
    }, { nextSteps: [exit0('held', 'Recomputed: Task 3.', 'Prompt.')] })
    expect((await offered($)).hasOffer).toBe(false)
    expect(w.nextStepRuns).toHaveLength(0)
  })

  test('A9: a handoff this session claims raises no offer', async ($, on) => {
    const w = await begin($, on, {
      handoffs: [{ key: 'mine', text: stored('mine', 'Mine: Task 2.', 900), mtimeMs: 900_000 }],
      claims: { mine: { session: OWN } },
      beats: { [OWN]: LIVE },
    }, { nextSteps: [exit0('mine', 'Recomputed: Task 3.', 'Prompt.')] })
    expect((await offered($)).hasOffer).toBe(false)
    expect(w.nextStepRuns).toHaveLength(0)
  })

  test('A9: the newest handoff a live other session holds is passed over for the next newest unclaimed one', async ($, on) => {
    const w = await begin($, on, {
      handoffs: [
        { key: 'older', text: stored('older', 'Older: Task 1.', 800), mtimeMs: 800_000 },
        { key: 'newer', text: stored('newer', 'Newer: Task 2.', 900), mtimeMs: 900_000 },
      ],
      claims: { newer: { session: OTHER } },
      beats: { [OTHER]: LIVE },
    }, { nextSteps: [exit0('older', 'Recomputed older.', 'Prompt.')] })
    const { band, hasOffer } = await offered($)
    expect(hasOffer).toBe(true)
    expect(w.nextStepRuns).toHaveLength(1)
    expect(w.run(0)).toBe(`${HDIR}/older.md`)
    expect(await band.find({ type: 'Text', text: /Next: Recomputed older\.$/ })).toBeDefined()
  })

  test('A9: when the newest candidate recomputes to exit 6 the next newest is tried', async ($, on) => {
    const w = await begin($, on, {
      handoffs: [
        { key: 'older', text: stored('older', 'Older: Task 1.', 800), mtimeMs: 800_000 },
        { key: 'newer', text: stored('newer', 'Newer: Task 2.', 900), mtimeMs: 900_000 },
      ],
    }, { nextSteps: [exit6, exit0('older', 'Recomputed older.', 'Prompt.')] })
    const { band, hasOffer } = await offered($)
    expect(hasOffer).toBe(true)
    expect(w.nextStepRuns).toHaveLength(2)
    expect([w.run(0), w.run(1)]).toEqual([`${HDIR}/newer.md`, `${HDIR}/older.md`])
    expect(await band.find({ type: 'Text', text: /Next: Recomputed older\.$/ })).toBeDefined()
  })

  test('A9: when every candidate recomputes to exit 6 there is no offer', async ($, on) => {
    const w = await begin($, on, {
      handoffs: [
        { key: 'older', text: stored('older', 'Older: Task 1.', 800), mtimeMs: 800_000 },
        { key: 'newer', text: stored('newer', 'Newer: Task 2.', 900), mtimeMs: 900_000 },
      ],
    }, { nextSteps: [exit6, exit6] })
    expect((await offered($)).hasOffer).toBe(false)
    expect(w.nextStepRuns).toHaveLength(2)
  })

  test('A9: a claim taken by a live other session after the offer appeared withdraws it', async ($, on) => {
    const w = await begin($, on, {
      handoffs: [{ key: 'solo', text: stored('solo', 'Solo: Task 2.', 900), mtimeMs: 900_000 }],
    }, { nextSteps: [exit0('solo', 'Recomputed: Task 3.', 'Prompt.'), exit0('solo', 'Recomputed again.', 'Prompt.')] })
    const first = await offered($)
    expect(first.hasOffer).toBe(true)
    w.files[heartbeat(OTHER)] = { text: LIVE, mtimeMs: 2 }
    w.files[`${CLAIMS}/solo`] = { text: `session=${OTHER}\nat=1000\n`, mtimeMs: 999_000 }
    await w.turn()
    expect(await first.band.find({ key: 'band-resume' })).toBeUndefined()
    expect((await offered($)).hasOffer).toBe(false)
  })

  test('A9: a claim this session takes after the offer appeared withdraws it', async ($, on) => {
    const w = await begin($, on, {
      handoffs: [{ key: 'solo', text: stored('solo', 'Solo: Task 2.', 900), mtimeMs: 900_000 }],
    }, { nextSteps: [exit0('solo', 'Recomputed: Task 3.', 'Prompt.'), exit0('solo', 'Recomputed again.', 'Prompt.')] })
    const first = await offered($)
    expect(first.hasOffer).toBe(true)
    w.files[heartbeat(OWN)] = { text: LIVE, mtimeMs: 2 }
    w.files[`${CLAIMS}/solo`] = { text: `session=${OWN}\nat=1000\n`, mtimeMs: 999_000 }
    await w.turn()
    expect(await first.band.find({ key: 'band-resume' })).toBeUndefined()
  })

  test('A9: a claim that goes gone after the offer was withdrawn brings it back', async ($, on) => {
    const w = await begin($, on, {
      handoffs: [{ key: 'solo', text: stored('solo', 'Solo: Task 2.', 900), mtimeMs: 900_000 }],
      claims: { solo: { session: OTHER } },
      beats: { [OTHER]: LIVE },
    }, { nextSteps: [exit0('solo', 'Recomputed: Task 3.', 'Prompt.')] })
    expect((await offered($)).hasOffer).toBe(false)
    w.files[heartbeat(OTHER)] = { text: GONE, mtimeMs: 3 }
    await w.turn()
    expect((await offered($)).hasOffer).toBe(true)
  })
})

describe('parallel-session-handoff: handoffs of other work stay offered (A20)', () => {
  test('A20: a draft handoff and an adhoc handoff in the checkout are both offered, the newest first', async ($, on) => {
    const adhoc = `# Handoff\n\n## Notes\n\nUnplanned.\n\n## Next session\n\n**Status:** Unplanned work.\n**Next:** Carry on unplanned.\n\nLaunch in \`${TOP}\`:\n\n\`\`\`\nclaude --model sonnet --effort high\n\`\`\`\n\nPaste as the first prompt:\n\n\`\`\`\nContinue the unplanned work.\n\`\`\`\n<!-- next-step: kind=adhoc key=adhoc-bbbbbbbb session=bbbbbbbb-1 done=0 closed=0 subject=- at=900 -->\n`
    const w = await begin($, on, {
      handoffs: [
        { key: 'D', text: stored('D', 'Draft: write the spec.', 800).replace('kind=plan', 'kind=draft'), mtimeMs: 800_000 },
        { key: 'adhoc-bbbbbbbb', text: adhoc, mtimeMs: 900_000 },
      ],
    }, { nextSteps: [{ exitCode: 0, stdout: adhoc.slice(adhoc.indexOf('## Next session')) }] })
    const { band, hasOffer } = await offered($)
    expect(hasOffer).toBe(true)
    expect(w.run(0)).toBe(`${HDIR}/adhoc-bbbbbbbb.md`)
    expect(await band.find({ type: 'Text', text: /Next: Carry on unplanned\.$/ })).toBeDefined()
  })

  test('A20: the draft handoff is still offered when the adhoc one is held by a live session', async ($, on) => {
    const w = await begin($, on, {
      handoffs: [
        { key: 'D', text: stored('D', 'Draft: write the spec.', 800).replace('kind=plan', 'kind=draft'), mtimeMs: 800_000 },
        { key: 'adhoc-bbbbbbbb', text: stored('adhoc-bbbbbbbb', 'Unplanned.', 900).replace('kind=plan', 'kind=adhoc'), mtimeMs: 900_000 },
      ],
      claims: { 'adhoc-bbbbbbbb': { session: OTHER } },
      beats: { [OTHER]: LIVE },
    }, { nextSteps: [exit0('D', 'Recomputed draft step.', 'Draft prompt.')] })
    const { band, hasOffer } = await offered($)
    expect(hasOffer).toBe(true)
    expect(w.run(0)).toBe(`${HDIR}/D.md`)
    expect(await band.find({ type: 'Text', text: /Next: Recomputed draft step\.$/ })).toBeDefined()
  })
})
