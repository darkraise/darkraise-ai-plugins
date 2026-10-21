import type { CockpitAutoRun, CockpitFinish, CockpitRoots } from '../../types'

// Pure helpers, kept apart from the hooks so tests can reach them directly.

/** The strip's handoff reading shows from this share of the budget. */
export const WARN_AT = 0.8

/**
 * The handoff budget: `configured`, else `env`, else dforge's own rule
 * (reference/session-budget.md): the compaction point minus one task's worst
 * growth, min(autoCompactWindow, window) × 93% − 140,000. Small windows, where
 * that comes out near zero, hold a fifth of the window. `configured` is
 * handoffTokens as the settings resolve it, where DFORGE_BUDGET already
 * overrides the file; `env` is a raw DFORGE_BUDGET for a caller without them.
 */
export function budgetFor(configured: number, env: string | undefined, window: number, compactWindow?: number): number {
  if (configured > 0) return Math.round(configured)
  const pinned = Number(env)
  if (Number.isFinite(pinned) && pinned > 0) return Math.round(pinned)
  const room = compactWindow !== undefined && compactWindow > 0 ? Math.min(window, compactWindow) : window
  return Math.max(Math.floor(room * 0.93) - 140_000, Math.floor(room / 5))
}

/**
 * The final-phase limit (reference/session-budget.md): 85% of min(autoCompactWindow, window).
 * Relaxed handoff measures every task against it.
 */
export function finalLimitFor(window: number, compactWindow?: number): number {
  const room = compactWindow !== undefined && compactWindow > 0 ? Math.min(window, compactWindow) : window
  return Math.floor(room * 0.85)
}

/** A positive whole number from a settings value, else undefined. */
export function positive(value: unknown): number | undefined {
  const n = Number(value)
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : undefined
}

export type Level = 'quiet' | 'warn' | 'handoff'

export function levelOf(tokens: number, limit: number, warnAt: number = WARN_AT): Level {
  if (tokens >= limit) return 'handoff'
  return tokens >= limit * warnAt ? 'warn' : 'quiet'
}

/** The warnAt setting, a percentage, as a share: 80 → 0.8, held to 1-99. */
export function warnShare(percent: number): number {
  return Number.isFinite(percent) && percent > 0 ? Math.min(Math.max(Math.round(percent), 1), 99) / 100 : WARN_AT
}

export const SECTIONS = ['account', 'context', 'usage', 'shells', 'agents', 'plan', 'repo', 'guard'] as const
export type Section = (typeof SECTIONS)[number]

/** The sections setting, "plan, context" → ['plan', 'context']: known names in the order given, each once. */
export function sectionsFrom(text: string): Section[] {
  const names = text
    .split(/[\s,]+/)
    .map(name => name.trim().toLowerCase())
    .filter((name): name is Section => (SECTIONS as readonly string[]).includes(name))
  const once = [...new Set(names)]
  return once.length === 0 ? [...SECTIONS] : once
}

/**
 * The sections setting after turning one section on or off: the shown order
 * kept, a section turned on added last, and the last one left never turned
 * off. All of them in their own order is the empty setting.
 */
export function sectionsToggled(shown: readonly Section[], name: Section): string {
  const next = shown.includes(name)
    ? shown.length === 1
      ? [...shown]
      : shown.filter(one => one !== name)
    : [...shown, name]
  const isDefault = next.length === SECTIONS.length && next.every((one, index) => one === SECTIONS[index])
  return isDefault ? '' : next.join(',')
}

/** The collapsed setting, "repo, usage" → ['usage', 'repo']: known names, each once, in SECTIONS order. */
export function collapsedFrom(text: string): Section[] {
  const names = text.split(/[\s,]+/).map(name => name.trim().toLowerCase())
  return SECTIONS.filter(name => names.includes(name))
}

/** The collapsed setting after collapsing or expanding one section, in SECTIONS order; empty when none is collapsed. */
export function collapsedToggled(collapsed: readonly Section[], name: Section): string {
  const next = collapsed.includes(name) ? collapsed.filter(one => one !== name) : [...collapsed, name]
  return SECTIONS.filter(one => next.includes(one)).join(',')
}

export type AgentGroupKey = 'waiting' | 'working' | 'failed' | 'done'
const AGENT_GROUPS: readonly { key: AgentGroupKey; name: string }[] = [
  { key: 'waiting', name: 'Waiting on you' },
  { key: 'working', name: 'Working' },
  { key: 'failed', name: 'Failed' },
  { key: 'done', name: 'Done' },
]

/**
 * The Agents section's groups in order, each left out while empty: the
 * running agents an open approval names, the other running ones, then the
 * recent ended ones (up to `shown` rows with the running) as failed or done.
 * A record without an outcome that ended reads as done. `spawns` must run
 * oldest first: the ended ones kept are the last ones.
 */
export function agentGroups<T extends { agentId: string; isDone: boolean; outcome?: 'done' | 'failed' | null }>(
  spawns: readonly T[],
  waiting: readonly string[],
  shown = 6,
): { key: AgentGroupKey; name: string; spawns: T[] }[] {
  const running = spawns.filter(one => !one.isDone)
  const room = Math.max(0, shown - running.length)
  // slice(-0) would keep every ended agent.
  const ended = room === 0 ? [] : spawns.filter(one => one.isDone).slice(-room)
  const members: Record<AgentGroupKey, T[]> = {
    waiting: running.filter(one => waiting.includes(one.agentId)),
    working: running.filter(one => !waiting.includes(one.agentId)),
    failed: ended.filter(one => one.outcome === 'failed'),
    done: ended.filter(one => one.outcome !== 'failed'),
  }
  return AGENT_GROUPS.map(group => ({ ...group, spawns: members[group.key] })).filter(group => group.spawns.length > 0)
}

/** 465000 → "465k"; 1234567 → "1.2M"; 999500, which rounds to 1000k, → "1.0M". */
export function kTokens(n: number): string {
  if (n >= 999_500) return `${(n / 1_000_000).toFixed(1)}M`
  return `${Math.round(n / 1000)}k`
}

const ATTRIBUTION = [
  /co-authored-by:[^\n]*(claude|anthropic|codex|openai|copilot)/i,
  /claude-session:/i,
  /generated with \[?claude code/i,
  /claude\.ai\/code\/session_/i,
]

/**
 * The first AI attribution line in a text, if any, without the quoting around
 * it: a shell command's closing quote, or a JSON string's escapes.
 */
export function attributionIn(text: string): string | undefined {
  for (const pattern of ATTRIBUTION) {
    const match = pattern.exec(text)
    if (match) {
      const line = text.slice(match.index).split(/\n|\\n/)[0] ?? ''
      return line.replace(/[\\"'`}\],\s]+$/, '').trim()
    }
  }
  return undefined
}

/** Whether a shell command writes a commit or a pull request. */
export function writesGitText(command: string): boolean {
  return /\bgit\b[^\n|;&]*\bcommit\b/.test(command) || /\bgh\s+pr\s+(create|edit)\b/.test(command)
}

/** The files a commit or pull request command takes its text from (`git commit -F`, `gh pr create --body-file`); stdin's `-` is the command's own text. */
export function gitTextFiles(command: string): string[] {
  const files: string[] = []
  for (const part of command.split(/[;&|\n]+/)) {
    if (!writesGitText(part)) continue
    for (const match of part.matchAll(/(?:^|\s)(?:-F[ \t]*|--(?:body-)?file(?:=|[ \t]+))("[^"]*"|'[^']*'|[^\s"';&|]+)/g)) {
      const file = (match[1] ?? '').replace(/^(["'])(.*)\1$/, '$2')
      if (file !== '' && file !== '-') files.push(file)
    }
  }
  return files
}

/** Whether a tool by this name writes a pull request or commits files. */
export function isGitWriteTool(tool: string): boolean {
  return /pull_request|create_or_update_file|push_files/.test(tool) && !/read|list|search|get_/.test(tool)
}

/** Whether a subagent type or skill name belongs to dforge. */
export function isDforge(name: string): boolean {
  return name.startsWith('dforge:')
}

/** 0.8 → "▰▰▰▰▰▰▰▰▱▱" at width 10; never full below 100%. */
export function bar(share: number, width: number): string {
  const clamped = Math.min(Math.max(share, 0), 1)
  let on = Math.round(clamped * width)
  if (on === width && clamped < 1) on = width - 1
  return '▰'.repeat(on) + '▱'.repeat(width - on)
}

/** The usage ramp: green, yellow, orange, then red. */
export function rampColor(percent: number): string {
  if (percent >= 90) return 'error'
  if (percent >= 75) return '#ff8700'
  return percent >= 50 ? 'warning' : 'success'
}

/** Milliseconds → "3h40m", "2d4h", "12m"; nothing under a minute, so a caller says "now" or "<1m" itself. */
export function duration(ms: number): string {
  if (!(ms >= 60_000)) return ''
  const minutes = Math.floor(ms / 60_000)
  const days = Math.floor(minutes / 1440)
  const hours = Math.floor((minutes % 1440) / 60)
  if (days > 0) return `${days}d${hours}h`
  return hours > 0 ? `${hours}h${minutes % 60}m` : `${minutes}m`
}

/** A handoff's age as the resume offer says it: "handed off 2h5m ago", "handed off just now". */
export function handedOff(ms: number): string {
  return ms < 60_000 ? 'handed off just now' : `handed off ${duration(ms)} ago`
}

/** five_hour → "5h", seven_day → "7d", spend_limit → "spend". */
export function limitLabel(kind: string): string {
  if (kind === 'five_hour') return '5h'
  if (kind === 'seven_day') return '7d'
  return kind.replace(/_limit$/, '').replace(/_/g, ' ')
}

export type PlanStatus = 'pending' | 'in_progress' | 'completed'
export type PlanItem = { id: string; text: string; status: PlanStatus }

/** A TodoWrite call replaces the whole list. */
export function planFromTodos(todos: readonly { content: string; status: PlanStatus }[]): PlanItem[] {
  return todos.map((todo, index) => ({ id: `todo-${index}`, text: todo.content, status: todo.status }))
}

/** A TaskUpdate call moves or retitles one task; `deleted` drops it. */
export function planWithUpdate(
  items: readonly PlanItem[],
  id: string,
  change: { subject?: string; status?: PlanStatus | 'deleted' },
): PlanItem[] {
  const { subject, status } = change
  if (status === 'deleted') return items.filter(item => item.id !== id)
  return items.map(item =>
    item.id === id ? { ...item, text: subject ?? item.text, status: status ?? item.status } : item,
  )
}

export type RepoState = { branch: string; ahead: number; behind: number; changed: number; untracked: number }

/** Reads `git status --porcelain=v2 --branch`. */
export function repoFromPorcelain(text: string): RepoState | null {
  const state: RepoState = { branch: '', ahead: 0, behind: 0, changed: 0, untracked: 0 }
  let oid = ''
  for (const line of text.split('\n')) {
    if (line.startsWith('# branch.oid ')) oid = line.slice(13).trim()
    else if (line.startsWith('# branch.head ')) state.branch = line.slice(14).trim()
    else if (line.startsWith('# branch.ab ')) {
      const match = /\+(\d+) -(\d+)/.exec(line)
      if (match) {
        state.ahead = Number(match[1])
        state.behind = Number(match[2])
      }
    } else if (line.startsWith('? ')) state.untracked += 1
    else if (/^[12u] /.test(line)) state.changed += 1
  }
  if (state.branch === '') return null
  if (state.branch === '(detached)') state.branch = oid === '' ? 'detached' : `@${oid.slice(0, 7)}`
  return state
}

const SPARKS = '▁▂▃▄▅▆▇█'

/** Readings → "▁▃▅█" scaled between their least and most; flat readings sit mid-height. */
export function sparkline(values: readonly number[]): string {
  if (values.length === 0) return ''
  const low = Math.min(...values)
  const span = Math.max(...values) - low
  return values
    .map(value => SPARKS[span === 0 ? 3 : Math.round(((value - low) / span) * (SPARKS.length - 1))])
    .join('')
}

/** One run of a meter: filled, empty, or a mark standing at a share of the width. */
export type TrackPart = { text: string; kind: 'fill' | 'empty' | 'mark'; mark?: string }

/**
 * A meter `width` cells wide filled to `share`, with each mark's glyph in the
 * cell its share lands on (a later mark wins a shared cell). Never full below 100%.
 */
export function track(share: number, width: number, marks: readonly { at: number; glyph: string; name: string }[]): TrackPart[] {
  const filled = bar(share, width)
  const cells: TrackPart[] = [...filled].map(cell => ({ text: cell, kind: cell === '▰' ? 'fill' : 'empty' }))
  for (const mark of marks) {
    if (!(mark.at >= 0 && mark.at <= 1)) continue
    const index = Math.min(width - 1, Math.floor(mark.at * width))
    cells[index] = { text: mark.glyph, kind: 'mark', mark: mark.name }
  }
  // Neighbouring cells of one kind join into one run.
  return cells.reduce<TrackPart[]>((runs, cell) => {
    const last = runs[runs.length - 1]
    if (last !== undefined && last.kind === cell.kind && cell.kind !== 'mark') last.text += cell.text
    else runs.push({ ...cell })
    return runs
  }, [])
}

/**
 * Splits `width` cells among values in proportion, largest remainders first,
 * every nonzero value at least one cell while the width lasts.
 */
export function stackedRuns(values: readonly number[], width: number): number[] {
  const total = values.reduce((sum, value) => sum + Math.max(0, value), 0)
  if (total === 0) return values.map(() => 0)
  const exact = values.map(value => (Math.max(0, value) / total) * width)
  const runs = exact.map(Math.floor)
  let left = width - runs.reduce((sum, run) => sum + run, 0)
  const order = exact.map((value, index) => ({ index, rest: value - Math.floor(value) })).sort((a, b) => b.rest - a.rest)
  for (const { index } of order) {
    if (left === 0) break
    runs[index] = (runs[index] ?? 0) + 1
    left--
  }
  for (const [index, run] of runs.entries()) {
    if (run > 0 || (values[index] ?? 0) <= 0) continue
    const donor = runs.indexOf(Math.max(...runs))
    if ((runs[donor] ?? 0) > 1) {
      runs[donor] = (runs[donor] ?? 0) - 1
      runs[index] = 1
    }
  }
  return runs
}

const WINDOW_MS: Record<string, number> = { five_hour: 5 * 3_600_000, seven_day: 7 * 86_400_000 }

/** How far through its window a rate limit is, 0 to 1, or null for a window of unknown length. */
export function windowElapsed(kind: string, resetsAt: number | null, now: number): number | null {
  const length = WINDOW_MS[kind]
  if (length === undefined || resetsAt === null) return null
  return Math.min(1, Math.max(0, 1 - (resetsAt - now) / length))
}

/** One stretch of text in the status strip, with how it is painted. */
export type Run = { text: string; color?: string; bold?: boolean; dim?: boolean }

/** What the minimized cockpit's band draws. */
export type BandInput = {
  cwd: string | null
  /** The repository's root, when the working directory is in one. */
  root: string | null
  home: string | null
  repo: RepoState | null
  /** The context against the handoff budget, over the model's window. */
  context: { tokens: number; limit: number; window: number } | null
  turnsLeft: number | null
  limits: readonly { kind: string; percent: number; resetsAt: number | null }[]
  agents: number
  /** Background shells running, and how long the oldest has run. */
  shells: { count: number; longest: number }
  now: number
  /** True while the main conversation's background work runs: line 2 leads with ◐. */
  isBackground?: boolean
}

const DIR = 'blue'
const GIT = 'magenta'
const AMBER_RUN = '#ff8700'
// Bar widths per tier; 0 draws no bar.
const BAND_WIDTHS = [
  { ctx: 10, limit: 8 },
  { ctx: 6, limit: 5 },
  { ctx: 0, limit: 0 },
  { ctx: 0, limit: 0 },
] as const
export const BAND_TIERS = BAND_WIDTHS.length

/** A shell's age: seconds under a minute, then minutes, hours and days. */
export function shellAge(ms: number): string {
  return ms < 60_000 ? elapsed(ms) : duration(ms)
}

/** The band's two lines at one tier: 0 is the fullest, 3 the most compact. */
export function bandLines(input: BandInput, tier: number): [Run[], Run[]] {
  const sep: Run = { text: tier < 2 ? '  ·  ' : ' · ', dim: true }
  const join = (segments: (Run[] | null)[]) =>
    segments.filter((one): one is Run[] => one !== null && one.length > 0).flatMap((one, index) => (index === 0 ? one : [sep, ...one]))
  const widths = BAND_WIDTHS[Math.min(tier, BAND_TIERS - 1)] ?? BAND_WIDTHS[0]
  const meter = (parts: TrackPart[], color: string, marks: Record<string, string>): Run[] =>
    parts.map(part => ({ text: part.text, color: part.kind === 'fill' ? color : part.kind === 'mark' ? (marks[part.mark ?? ''] ?? color) : undefined, dim: part.kind === 'empty', bold: part.kind === 'mark' }))

  let ctx: Run[] | null = null
  if (input.context !== null) {
    const { tokens, limit, window } = input.context
    const percent = (tokens / limit) * 100
    const color = rampColor(percent)
    const turns = input.turnsLeft
    ctx = [
      { text: 'ctx ', dim: true },
      ...(widths.ctx > 0 ? [...meter(track(tokens / window, widths.ctx, [{ at: limit / window, glyph: '┃', name: 'handoff' }]), color, { handoff: color }), { text: ' ' }] : []),
      { text: `${Math.round(percent)}%`, color, bold: true },
      ...(turns === null || tier >= 3 ? [] : [{ text: tier < 2 ? ` · ≈${turns} ${turns === 1 ? 'turn' : 'turns'}` : ` ≈${turns}t`, color: turns <= 3 ? AMBER_RUN : undefined, dim: turns > 3 }]),
    ]
  }

  const limits = input.limits.map((limit): Run[] => {
    const color = rampColor(limit.percent)
    const gone = windowElapsed(limit.kind, limit.resetsAt, input.now)
    const forecast = limitForecast(limit.kind, limit.percent, limit.resetsAt, input.now)
    const pace: Run[] =
      tier >= 3
        ? []
        : forecast === 'pace'
          ? [{ text: tier < 2 ? ' on pace' : ' ✓', color: 'success' }]
          : typeof forecast === 'number'
            ? [{ text: tier < 2 ? ` out in ${duration(forecast) || '<1m'}` : ` ${duration(forecast) || '<1m'}`, color: AMBER_RUN }]
            : []
    const reset = tier === 0 && limit.resetsAt !== null && forecast !== null && typeof forecast !== 'number' ? [{ text: ` · ${duration(limit.resetsAt - input.now) || 'now'}`, dim: true }] : []
    return [
      { text: `${limitLabel(limit.kind)} `, dim: true },
      ...(widths.limit > 0 ? [...meter(track(limit.percent / 100, widths.limit, gone === null ? [] : [{ at: gone, glyph: '┊', name: 'pace' }]), color, { pace: 'white' }), { text: ' ' }] : []),
      { text: `${Math.round(limit.percent)}%`, color, bold: true },
      ...pace,
      ...reset,
    ]
  })

  const agents: Run[] | null =
    input.agents === 0 ? null : [{ text: '● ', color: 'cyan' }, { text: tier < 2 ? `${input.agents} ${input.agents === 1 ? 'agent' : 'agents'}` : `${input.agents}`, color: 'cyan' }]
  const { count, longest } = input.shells
  const shells: Run[] | null =
    count === 0
      ? null
      : [
          { text: '$ ', color: 'yellow', bold: true },
          { text: tier < 2 ? `${count} ${count === 1 ? 'shell' : 'shells'}` : `${count}`, color: 'yellow' },
          ...(tier >= 3 ? [] : [{ text: tier < 1 ? ' · longest ' : ' · ', dim: true }, { text: shellAge(longest), color: 'yellow' }]),
        ]

  let dir: Run[] | null = null
  if (input.cwd !== null) {
    const { lead, anchor, inner } = pathParts(input.cwd, input.root, input.home)
    const parts = inner.split('/').filter(Boolean)
    const leaf = parts[parts.length - 1] ?? anchor
    dir = (
      tier === 0
        ? [{ text: lead, color: DIR, dim: true }, { text: anchor, color: DIR, bold: true }, { text: inner, color: DIR }]
        : tier === 1
          ? [{ text: anchor, color: DIR, bold: true }, { text: parts.length > 1 ? `/…/${leaf}` : inner, color: DIR }]
          : [{ text: input.root === null ? leaf : anchor, color: DIR, bold: true }]
    ).filter(run => run.text !== '')
  }
  let git: Run[] = []
  if (input.repo !== null) {
    const r = input.repo
    const branch = tier >= 2 && r.branch.length > 16 ? `${r.branch.slice(0, 15)}…` : r.branch
    const counters = [
      r.ahead > 0 ? `↑${r.ahead}` : '',
      tier < 3 && r.behind > 0 ? `↓${r.behind}` : '',
      tier < 2 && r.changed > 0 ? `~${r.changed}` : '',
      tier < 2 && r.untracked > 0 ? `?${r.untracked}` : '',
    ].filter((text, index) => text !== '' && (tier < 3 || index === 0))
    git = [
      { text: ' ⎇ ', color: GIT },
      { text: branch, color: GIT, bold: true },
      ...(r.changed > 0 || r.untracked > 0 ? [{ text: '*', color: GIT }] : []),
      ...(counters.length > 0 && tier < 3 ? [{ text: ` ${counters.join(' ')}`, color: GIT }] : []),
    ]
  }
  const where = dir === null && git.length === 0 ? null : [...(dir ?? []), ...(dir === null ? git.map((run, index) => (index === 0 ? { ...run, text: '⎇ ' } : run)) : git)]

  const two = join([agents, shells, where])
  return [join([ctx, ...limits]), input.isBackground === true ? [{ text: '◐ ', color: AMBER_RUN, bold: true }, ...two] : two]
}

/**
 * Each band line at the fullest tier that fits `width`, stepping down on its
 * own; a line too wide even at the last tier is cut.
 */
export function fitBand(input: BandInput, width: number): [Run[], Run[]] {
  const fit = (which: 0 | 1): Run[] => {
    for (let tier = 0; tier < BAND_TIERS; tier++) {
      const line = bandLines(input, tier)[which]
      if (runsWidth(line) <= width) return line
    }
    return runsCut(bandLines(input, BAND_TIERS - 1)[which], width)
  }
  return [fit(0), fit(1)]
}

/**
 * Cells the box below the prompt leaves for Claude Code's permission-mode
 * label on its row: the widest, `⏵⏵ bypass permissions on · ` after a 2-cell
 * margin, measured on Claude Code 2.1.304. The live mode cannot be read at
 * draw time, so every mode gets the widest.
 */
export const MODE_LABEL_RESERVE = 29

/** The band's bottom rule, `width` cells wide, with `label` set into it after `╰─ ` and cut to fit; no label draws a plain rule. */
export function bottomRule(label: string | null, width: number): { lead: string; label: string; tail: string } {
  const text = (label ?? '').trim()
  const room = width - 6
  if (text === '' || room < 4) return { lead: `╰${'─'.repeat(Math.max(0, width - 2))}╯`, label: '', tail: '' }
  const shown = commandExcerpt(text, room)
  return { lead: '╰─ ', label: shown, tail: ` ${'─'.repeat(Math.max(1, width - 5 - [...shown].length))}╯` }
}

// A terminal draws a combining mark, a joiner or a variation selector in no
// cell of its own, and an emoji or an East Asian wide or fullwidth character in two.
const ZERO_CELLS = /[\p{Mn}\p{Me}\u200b-\u200f\ufe00-\ufe0f]/u
const TWO_CELLS = /[\p{Emoji_Presentation}\u1100-\u115f\u2e80-\u303e\u3041-\u33ff\u3400-\u4dbf\u4e00-\u9fff\ua000-\ua4cf\uac00-\ud7a3\uf900-\ufaff\ufe30-\ufe4f\uff00-\uff60\uffe0-\uffe6\u{20000}-\u{3fffd}]/u

/** The terminal cells a text takes. */
export function cellWidth(text: string): number {
  let cells = 0
  for (const char of text) cells += ZERO_CELLS.test(char) ? 0 : TWO_CELLS.test(char) ? 2 : 1
  return cells
}

/** The cells a row of runs takes. */
export function runsWidth(runs: readonly Run[]): number {
  return runs.reduce((sum, run) => sum + cellWidth(run.text), 0)
}

/** A row cut to `width` cells, ending in an ellipsis when anything was cut. */
export function runsCut(runs: readonly Run[], width: number): Run[] {
  if (runsWidth(runs) <= width) return [...runs]
  const out: Run[] = []
  let left = Math.max(0, width - 1)
  for (const run of runs) {
    const cells = cellWidth(run.text)
    if (cells <= left) {
      out.push(run)
      left -= cells
      continue
    }
    let text = ''
    for (const char of run.text) {
      if (cellWidth(char) > left) break
      text += char
      left -= cellWidth(char)
    }
    if (text !== '') out.push({ ...run, text })
    break
  }
  if (width > 0) out.push({ text: '…', dim: true })
  return out
}

// The named colors the rows use, as the theme keys that mean the same.
const THEME_KEYS: Record<string, string> = { green: 'success', red: 'error', yellow: 'warning', cyan: 'suggestion', blue: 'suggestion', magenta: 'planMode', gray: 'subtle', white: 'text' }

/** A named color as the theme key that means the same, so the desktop's theme draws it; a theme key, a hex or any other name passes through. */
export function themeColor(name: string | undefined): string | undefined {
  return name === undefined ? undefined : (THEME_KEYS[name] ?? name)
}

/** A terminal color: a 256-color number becomes hex, orange its own hex, a name stays. */
export function termColor(name: string | null | undefined): string | undefined {
  if (name === null || name === undefined || name === '' || name === 'default') return undefined
  if (name === 'orange') return '#ff8700'
  if (!/^\d{1,3}$/.test(name)) return name
  const n = Number(name)
  if (n > 255) return undefined
  const base = ['#000000', '#800000', '#008000', '#808000', '#000080', '#800080', '#008080', '#c0c0c0',
    '#808080', '#ff0000', '#00ff00', '#ffff00', '#0000ff', '#ff00ff', '#00ffff', '#ffffff']
  if (n < 16) return base[n]
  const hex = (v: number) => v.toString(16).padStart(2, '0')
  if (n >= 232) {
    const v = 8 + (n - 232) * 10
    return `#${hex(v)}${hex(v)}${hex(v)}`
  }
  const steps = [0, 95, 135, 175, 215, 255]
  const i = n - 16
  return `#${hex(steps[Math.floor(i / 36)] ?? 0)}${hex(steps[Math.floor(i / 6) % 6] ?? 0)}${hex(steps[i % 6] ?? 0)}`
}

/** "claude-opus-5-5[1m]" → "Opus 5.5", or "Opus" when short. */
export function modelName(id: string, isShort = false): string {
  const bare = id.replace(/\[.*?\]$/, '').replace(/^claude-/, '').replace(/-\d{8}$/, '')
  const [family = bare, ...rest] = bare.split('-')
  const name = family.charAt(0).toUpperCase() + family.slice(1)
  const version = rest.filter(part => /^\d+$/.test(part)).join('.')
  return isShort || version === '' ? name : `${name} ${version}`
}

/** The account's key: its config directory, "~"-relative under home. */
export function accountKey(configDir: string, home: string): string {
  const dir = slashes(configDir)
  const base = slashes(home)
  if (dir === base) return '~'
  return base !== '' && dir.startsWith(`${base}/`) ? `~${dir.slice(base.length)}` : dir
}

// Frame colors that read on light and dark terminals alike.
const ACCOUNT_COLORS = ['#af87ff', '#5fafff', '#5fd7af', '#ffaf5f', '#ff87af', '#87d75f', '#d787ff', '#5fd7ff'] as const

/** The account's frame color: one of eight, picked from its key, so each account keeps its own. */
export function accountColor(key: string): string {
  let hash = 0
  for (const ch of key) hash = (hash * 31 + (ch.codePointAt(0) ?? 0)) >>> 0
  return ACCOUNT_COLORS[hash % ACCOUNT_COLORS.length] ?? ACCOUNT_COLORS[0]
}

/** Claude's billing type, "stripe_subscription" → "subscription". */
export function billingLabel(billing: string | null): string | null {
  if (billing === null || billing === '') return null
  return billing.replace(/^(stripe|apple|google)_/, '').replace(/_/g, ' ')
}

/** Whether a path is absolute on any platform: rooted at a slash or a drive letter. */
export function isAbsolutePath(path: string): boolean {
  return /^([\\/]|[a-z]:[\\/])/i.test(path)
}

/**
 * Where a ledger's plan name may be read, in order (darkmem store options spec
 * §7.1 and §7.3): an absolute name as written; a document name under the docs
 * root while documents are in darkmem, else under each checkout's own docs
 * directory; any other name under each checkout. The session's checkout comes
 * first. A ledger written before 4.0.0 cites its plan as docs/forge/<rest>,
 * or before 3.0.0 as docs/superpowers/<rest>; both still name
 * docs/dforge/<rest>: ledgers are never rewritten.
 */
export function planCandidates(plan: string, docs: CockpitRoots['docs'] | null, checkouts: readonly { root: string; docsDir: string }[]): string[] {
  if (isAbsolutePath(plan)) return [plan]
  const name = plan.replace(/^\.\//, '')
  const doc = /^docs\/(?:dforge|forge|superpowers)(?:\/(.*))?$/.exec(name)
  const under = (dir: string) => (doc?.[1] ? `${dir}/${doc[1]}` : dir)
  if (doc && docs?.store === 'darkmem') return [under(docs.root)]
  const seen = new Set<string>()
  return checkouts.filter(one => !seen.has(one.root) && Boolean(seen.add(one.root))).map(one => (doc ? under(one.docsDir) : `${one.root}/${name}`))
}

function slashes(path: string): string {
  return path.replace(/\\/g, '/').replace(/\/+$/, '')
}

/**
 * The working directory in three tones: what leads to the
 * repository, the repository's name, and the path inside it.
 */
export function pathParts(cwd: string, root: string | null, home: string | null): { lead: string; anchor: string; inner: string } {
  const tilde = (path: string) => {
    const h = home === null ? '' : slashes(home)
    return h !== '' && (path === h || path.startsWith(`${h}/`)) ? `~${path.slice(h.length)}` : path
  }
  const at = slashes(cwd)
  const top = root === null ? null : slashes(root)
  const anchorPath = top !== null && (at === top || at.startsWith(`${top}/`)) ? top : at
  const cut = anchorPath.lastIndexOf('/')
  const lead = cut <= 0 ? '' : tilde(anchorPath.slice(0, cut + 1))
  return { lead, anchor: anchorPath.slice(cut + 1) || anchorPath, inner: at.slice(anchorPath.length) }
}

/**
 * The repository's name: `owner/name` from its origin remote (scp-style or
 * URL, `.git` dropped), else the root folder's name.
 */
export function repoName(remote: string | null, root: string): string {
  const path = (remote ?? '')
    .trim()
    .replace(/\.git\/?$/, '')
    .replace(/\/+$/, '')
    .replace(/^[a-z][a-z0-9+.-]*:\/\/[^/]*\//i, '')
    .replace(/^[^@/]+@[^:/]+:/, '')
  const parts = path.split('/').filter(Boolean)
  if (parts.length >= 2) return parts.slice(-2).join('/')
  if (parts.length === 1) return parts[0] ?? ''
  const top = slashes(root).replace(/\/+$/, '')
  return top.slice(top.lastIndexOf('/') + 1) || top
}

/** The working folder: the way there dim, the repository bold, the rest plain. */
export function folderRuns(cwd: string, root: string | null, home: string | null): Run[] {
  const { lead, anchor, inner } = pathParts(cwd, root, home)
  return [
    ...(lead === '' ? [] : [{ text: lead, color: DIR, dim: true }]),
    { text: anchor, color: DIR, bold: true },
    ...(inner === '' ? [] : [{ text: inner, color: DIR }]),
  ]
}

/**
 * How many main turns until the context reaches the budget, at the average
 * growth of the last few turns; null with too little to go on, no growth, or
 * already past it.
 */
export function turnsToBudget(perTurn: readonly number[], limit: number): number | null {
  const recent = perTurn.slice(-6)
  const last = recent[recent.length - 1]
  if (recent.length < 3 || last === undefined || last >= limit) return null
  const steps = recent.slice(1).map((value, index) => value - (recent[index] ?? value)).filter(step => step > 0)
  if (steps.length === 0) return null
  const growth = steps.reduce((sum, step) => sum + step, 0) / steps.length
  return Math.max(1, Math.ceil((limit - last) / growth))
}

/**
 * Where a rate limit is headed at the pace spent so far in its window: the
 * milliseconds until it runs out when that comes before the reset, 'pace' when
 * it lasts, null when the window is too young or its length unknown.
 */
export function limitForecast(kind: string, percent: number, resetsAt: number | null, now: number): number | 'pace' | null {
  const length = WINDOW_MS[kind]
  if (length === undefined || resetsAt === null || percent <= 0 || percent >= 100) return null
  const spent = length - (resetsAt - now)
  if (spent < 10 * 60_000) return null
  const left = ((100 - percent) / percent) * spent
  return now + left < resetsAt ? left : 'pace'
}

/** One task's state in a dforge SDD ledger. */
export type LedgerTask = {
  n: number
  state: 'assigned' | 'complete' | 'blocked'
  /** The fix or review round in flight, "2/5". */
  round: string | null
  /** The seat the task was assigned to. */
  seat: string | null
  isClean: boolean
  reason: string | null
}

/** What a run's ledger says: its plan, each task it names, and whether the final review came back clean. */
export type Ledger = { plan: string | null; tasks: LedgerTask[]; isFinished: boolean }

/** Reads the subagent-driven-development ledger (progress.md) as its grammar writes it. */
export function parseLedger(text: string): Ledger {
  const tasks = new Map<number, LedgerTask>()
  const task = (n: number) => {
    const found = tasks.get(n) ?? { n, state: 'assigned' as const, round: null, seat: null, isClean: false, reason: null }
    tasks.set(n, found)
    return found
  }
  let plan: string | null = null
  let isFinished = false
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim()
    const header = /^#\s*SDD ledger\s*[—-]+\s*plan:\s*(.+)$/.exec(line)
    if (header) {
      plan = header[1]?.trim() ?? null
      continue
    }
    if (/^Final review: clean/.test(line)) {
      isFinished = true
      continue
    }
    const group = /^Group (\d+)-(\d+): review round (\d+\/\d+)/.exec(line)
    if (group) {
      for (let n = Number(group[1]); n <= Number(group[2]); n++) {
        const one = task(n)
        if (one.state === 'assigned') one.round = group[3] ?? null
      }
      continue
    }
    const match = /^Task (\d+): (.*)$/.exec(line)
    if (!match) continue
    // A Ruling, parked or deferred line names a task without starting it.
    const n = Number(match[1])
    const rest = match[2] ?? ''
    const assigned = /^implementer (\S+) \(assigned/.exec(rest)
    if (assigned) {
      const one = task(n)
      one.seat = assigned[1] ?? null
      if (one.state !== 'complete') one.state = 'assigned'
      one.reason = null
      continue
    }
    const round = /^fix round (\d+\/\d+)/.exec(rest)
    if (round) {
      task(n).round = round[1] ?? null
      continue
    }
    if (/^complete\b/.test(rest)) {
      const one = task(n)
      one.state = 'complete'
      one.round = null
      one.isClean = /review clean/.test(rest)
      continue
    }
    const blocked = /^BLOCKED\s*[—-]+\s*(.*)$/.exec(rest)
    if (blocked) {
      const one = task(n)
      one.state = 'blocked'
      one.reason = blocked[1]?.trim() || null
    }
  }
  return { plan, tasks: [...tasks.values()].sort((a, b) => a.n - b.n), isFinished }
}

/** A plan file's tasks, from its "### Task N: title" headings outside fenced blocks, as plan_tasks in scripts/lib/plan.sh reads them. */
export function planTasks(text: string): { n: number; title: string }[] {
  const out: { n: number; title: string }[] = []
  // CommonMark's rule, as plan.sh has it: a fence closes only at a bare marker of its character at least as long.
  let fence = ''
  for (const line of text.split(/\r?\n/)) {
    if (fence !== '') {
      const marker = line.replace(/^ {0,3}/, '').trimEnd()
      if (/^(`+|~+)$/.test(marker) && marker[0] === fence[0] && marker.length >= fence.length) fence = ''
      continue
    }
    const open = /^ {0,3}(`{3,}|~{3,})/.exec(line)
    if (open) {
      fence = open[1] ?? ''
      continue
    }
    const match = /^#+[ \t]+Task[ \t]+(\d+)(?=[ \t:.-]|$)[ \t]*[:.\-—]?[ \t]*(.*)$/.exec(line)
    if (match && !out.some(one => one.n === Number(match[1]))) out.push({ n: Number(match[1]), title: (match[2] ?? '').trim() })
  }
  return out
}

// A plan's last tasks join its final phase once this many or fewer remain
// (CTX_TAIL_TASKS in scripts/lib/context.sh).
const TAIL_TASKS = 2

/**
 * Whether a run is at its plan's tail or in its final phase: at most
 * TAIL_TASKS tasks left by its ledger, or its final review clean. The budget
 * line measures both against the final-phase limit.
 */
export function isPlanTail(run: { done: number; total: number; isFinished: boolean }): boolean {
  return run.isFinished || (run.total > 0 && run.total - run.done <= TAIL_TASKS)
}

const RUN_ORDER: Readonly<Record<string, number>> = { assigned: 0, blocked: 1, pending: 2, complete: 3 }

/** The first `size` of a run's tasks as the Run card lists them: in flight, blocked, not started, then done, each in plan order. */
export function runList<T extends { n: number; state: string }>(tasks: readonly T[], size: number): T[] {
  return [...tasks].sort((a, b) => (RUN_ORDER[a.state] ?? 2) - (RUN_ORDER[b.state] ?? 2) || a.n - b.n).slice(0, size)
}

/** Milliseconds → "42s", "2m14s", "1h05m": a turn's clock, to the second under an hour. */
export function elapsed(ms: number): string {
  const seconds = Math.max(0, Math.floor(ms / 1000))
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m${String(seconds % 60).padStart(2, '0')}s`
  return `${Math.floor(minutes / 60)}h${String(minutes % 60).padStart(2, '0')}m`
}

/** What the session is doing, as the Now row reads it. */
export type ActivityInput = {
  kind: 'idle' | 'running' | 'waiting' | 'asking' | 'failed' | 'interrupted' | 'background'
  since: number
  turnStartedAt: number | null
  step: number
  tool: string | null
  agent: string | null
  detail: string | null
  lastTurnMs: number | null
  endedAt: number | null
  isSent: boolean
}

const AMBER = '#ffaf5f'

/** The main conversation's background work, as the Now row names it. */
export type ActivityWork = { shells: readonly { command: string; startedAt: number }[]; agents: number }

/** A command's first line, cut to `width` characters with an ellipsis. */
function commandExcerpt(command: string, width: number): string {
  const chars = [...(command.split('\n')[0] ?? '')]
  return chars.length <= width ? chars.join('') : `${chars.slice(0, width - 1).join('')}…`
}

/** The Now row: one line, whatever the state, so the pane never jumps. */
export function nowLine(now: ActivityInput, at: number, work: ActivityWork = { shells: [], agents: 0 }): Run[] {
  const sep: Run = { text: ' · ', dim: true }
  const sent: Run[] = now.isSent ? [sep, { text: 'Discord ✓', dim: true }] : []
  switch (now.kind) {
    case 'running':
      return [
        { text: '● ', color: 'cyan', bold: true },
        { text: 'running ' },
        { text: elapsed(at - (now.turnStartedAt ?? now.since)), color: 'cyan', bold: true },
        ...(now.step > 0 ? [sep, { text: `step ${now.step}`, dim: true }] : []),
        ...(now.tool === null ? [] : [sep, { text: now.tool }]),
        ...(now.tool !== null && now.agent !== null ? [{ text: ' in ', dim: true }, { text: now.agent, color: 'magenta' }] : []),
      ]
    case 'waiting':
      return [
        { text: '⏳ approve? ', color: AMBER, bold: true },
        ...(now.detail === null ? [] : [{ text: now.detail }, sep]),
        { text: elapsed(at - now.since), color: AMBER, bold: true },
        ...sent,
      ]
    case 'asking':
      return [
        { text: '❓ Claude is asking ', color: AMBER, bold: true },
        { text: elapsed(at - now.since), color: AMBER, bold: true },
        ...(now.detail === null ? [] : [sep, { text: now.detail }]),
        ...sent,
      ]
    case 'failed':
      return [
        { text: '✗ last turn failed', color: 'error', bold: true },
        ...(now.detail === null ? [] : [{ text: ` ${now.detail}` }]),
        ...(now.lastTurnMs === null ? [] : [sep, { text: elapsed(now.lastTurnMs), dim: true }]),
        ...sent,
      ]
    case 'interrupted':
      return [
        { text: '■ interrupted', color: AMBER, bold: true },
        ...(now.detail === null ? [] : [sep, { text: now.detail }]),
        ...(now.endedAt === null ? [] : [sep, { text: at - now.endedAt < 60_000 ? 'just now' : `${duration(at - now.endedAt)} ago`, dim: true }]),
      ]
    case 'background': {
      const count = work.shells.length
      const newest = work.shells.reduce<{ command: string; startedAt: number } | null>((last, shell) => (last === null || shell.startedAt > last.startedAt ? shell : last), null)
      const oldest = Math.min(...work.shells.map(shell => shell.startedAt))
      return [
        { text: '◐ background', color: AMBER, bold: true },
        ...(count === 0 ? [] : [sep, { text: `${count} ${count === 1 ? 'shell' : 'shells'}` }]),
        ...(newest === null ? [] : [sep, { text: commandExcerpt(newest.command, 40), dim: true }]),
        ...(count === 0 ? [] : [sep, { text: shellAge(at - oldest), color: AMBER, bold: true }]),
        ...(work.agents === 0 ? [] : [sep, { text: `${work.agents} ${work.agents === 1 ? 'agent' : 'agents'}`, color: 'cyan' }]),
        ...sent,
      ]
    }
    default:
      return [
        { text: '○ idle', dim: true },
        ...(now.lastTurnMs === null ? [] : [sep, { text: 'last turn ', dim: true }, { text: elapsed(now.lastTurnMs) }]),
        ...(now.endedAt === null ? [] : [sep, { text: `ended ${duration(at - now.endedAt) || '<1m'} ago`, dim: true }]),
      ]
  }
}

/** What the dense pane's rows draw from. */
export type DenseInput = {
  email: string | null
  billing: string | null
  remote: Run[]
  /** The context against the handoff budget. */
  context: { tokens: number; limit: number } | null
  turnsLeft: number | null
  limits: readonly { kind: string; percent: number }[]
  shells: readonly { command: string; startedAt: number }[]
  /** The running subagents' seats, short names. */
  agents: readonly string[]
  run: { done: number; total: number; current: string | null } | null
  todos: { done: number; total: number; current: string | null } | null
  repo: RepoState | null
  refused: number
  now: number
}

/** A dense row's label, padded to five cells so the rows line up. */
function denseLabel(label: string, color?: string): Run {
  return { text: label.padEnd(5), color, dim: color === undefined }
}

/** One dense pane row for a section, or null when the section has nothing to show. */
export function denseLine(section: Section, input: DenseInput): Run[] | null {
  const sep: Run = { text: ' · ', dim: true }
  const join = (parts: Run[][]): Run[] => parts.filter(part => part.length > 0).flatMap((part, index) => (index === 0 ? part : [sep, ...part]))
  switch (section) {
    case 'account':
      if (input.email === null) return null
      return [denseLabel('acct'), ...join([[{ text: input.email, bold: true }], input.billing === null ? [] : [{ text: input.billing, dim: true }], [{ text: 'Remote ', dim: true }, ...input.remote]])]
    case 'context': {
      if (input.context === null) return [denseLabel('ctx'), { text: 'no reading yet', dim: true }]
      const { tokens, limit } = input.context
      const percent = (tokens / limit) * 100
      const color = rampColor(percent)
      const turns = input.turnsLeft
      return [
        denseLabel('ctx'),
        { text: bar(tokens / limit, 10), color },
        { text: ` ${Math.round(percent)}%`, color, bold: true },
        { text: ` ${kTokens(tokens)}/${kTokens(limit)}`, dim: true },
        ...(turns === null ? [] : [sep, { text: `≈${turns} ${turns === 1 ? 'turn' : 'turns'}`, color: turns <= 3 ? AMBER : undefined, dim: turns > 3 }]),
      ]
    }
    case 'usage': {
      const shown = input.limits.filter(limit => limit.kind === 'five_hour' || limit.kind === 'seven_day')
      if (shown.length === 0) return [denseLabel('lim'), { text: 'no reading yet', dim: true }]
      return [
        denseLabel('lim'),
        ...join(
          shown.map(limit => {
            const color = rampColor(limit.percent)
            return [{ text: `${limitLabel(limit.kind)} `, dim: true }, { text: bar(limit.percent / 100, 6), color }, { text: ` ${Math.round(limit.percent)}%`, color, bold: true }]
          }),
        ),
      ]
    }
    case 'shells': {
      if (input.shells.length === 0) return null
      const newest = input.shells.reduce((last, shell) => (shell.startedAt > last.startedAt ? shell : last))
      const count = input.shells.length
      return [
        denseLabel('$', 'yellow'),
        ...join([[{ text: `${count} ${count === 1 ? 'shell' : 'shells'}`, color: 'yellow' }], [{ text: commandExcerpt(newest.command, 40) }], [{ text: shellAge(input.now - newest.startedAt), dim: true }]]),
      ]
    }
    case 'agents':
      if (input.agents.length === 0) return null
      return [denseLabel('agt', 'cyan'), ...join([[{ text: `${input.agents.length} running`, color: 'cyan' }], [{ text: input.agents.join(', ') }]])]
    case 'plan': {
      const plan = input.run ?? input.todos
      if (plan === null || plan.total === 0) return null
      return [
        denseLabel('plan', 'magenta'),
        ...join([[{ text: bar(plan.done / plan.total, Math.min(plan.total, 10)), color: 'magenta' }, { text: ` ${plan.done}/${plan.total}`, bold: true }], plan.current === null ? [] : [{ text: plan.current }]]),
      ]
    }
    case 'repo': {
      if (input.repo === null) return null
      const r = input.repo
      const branch: Run[] = [{ text: r.branch, color: 'magenta', bold: true }, ...(r.ahead > 0 ? [{ text: ` ↑${r.ahead}`, color: 'magenta' }] : []), ...(r.behind > 0 ? [{ text: ` ↓${r.behind}`, color: 'magenta' }] : [])]
      return [denseLabel('⎇', 'magenta'), ...join([branch, r.changed > 0 ? [{ text: `~${r.changed} changed`, color: 'yellow' }] : [], r.untracked > 0 ? [{ text: `?${r.untracked}`, dim: true }] : []])]
    }
    case 'guard':
      return input.refused === 0 ? null : [denseLabel('grd'), { text: `✗ ${input.refused} refused`, color: 'red' }]
  }
}

// Commands that start something meant to run until stopped: a dev server, a
// watcher, a followed log.
const SERVICES = [
  /^(npm|pnpm|yarn|bun)( run)? (dev|start|serve|preview|watch)(:(?!build\b)|\s|$)/,
  /^((npx|bunx|pnpm exec) )?(vite(?! build)(\s|$)|next (dev|start)|nuxt dev|astro dev|webpack serve|ng serve|nodemon)/,
  /^python3? -m http\.server/,
  /^(uvicorn|flask run|rails (s|server))(\s|$)/,
  /^docker(-| )compose up(?!.*\s(-d|--detach)(\s|$))/,
  /^tail -[fF](\s|$)/,
  /^cargo watch(\s|$)/,
  /\s--watch(All)?(=|\s|$)/,
]

/** Whether a background command, by its first line, starts a service that never ends on its own. */
export function isServiceCommand(command: string): boolean {
  return command
    .split('\n')[0]!
    .split(/&&|\|\||;/)
    .map(part => part.trim().replace(/^(\w+=\S*\s+)+/, ''))
    .some(part => SERVICES.some(pattern => pattern.test(part)))
}

/** Whether a release (`2.1.295`) is at least `least`, compared part by part; an unreadable one is not. */
export function isAtLeast(base: string | undefined, least: string): boolean {
  const parts = (text: string) => text.split('-')[0]!.split('.').map(Number)
  if (base === undefined || !/^\d+\.\d+\.\d+/.test(base)) return false
  const have = parts(base)
  const want = parts(least)
  for (let i = 0; i < want.length; i++) {
    if ((have[i] ?? 0) !== want[i]) return (have[i] ?? 0) > want[i]!
  }
  return true
}

/**
 * What a handoff note offers to resume: the `**Next:**` line of its
 * `## Next session` block. scripts/next-step writes a first prompt into that
 * block only when a next session has work to start, so without one (a finished
 * plan, or a blocked task its human partner must rule on) there is no offer.
 */
export function resumeOfferOf(text: string): { next: string } | null {
  const lines = text.split(/\r?\n/)
  const start = lines.findIndex(line => /^## Next session\s*$/.test(line))
  if (start < 0) return null
  const end = lines.findIndex((line, index) => index > start && line.startsWith('## '))
  const block = lines.slice(start + 1, end < 0 ? undefined : end)
  if (!block.some(line => line.trim() === 'Paste as the first prompt:')) return null
  const next = block.find(line => line.startsWith('**Next:**'))?.slice('**Next:**'.length).trim() ?? ''
  return next === '' ? null : { next }
}

/** finish.json as dforge's finish-choice writes it; null when unreadable. */
export function parseFinish(text: string): CockpitFinish | null {
  try {
    const raw = JSON.parse(text) as Record<string, unknown>
    const action = raw.action
    if (action !== 'merge' && action !== 'pr' && action !== 'keep' && action !== 'wait') return null
    return {
      action,
      base: typeof raw.base === 'string' ? raw.base : null,
      answer: typeof raw.answer === 'string' ? raw.answer : null,
    }
  } catch {
    return null
  }
}

/**
 * The roots `darkmem-config.mjs --mode` prints (darkmem store options spec
 * §7.3): a documents and a progress line, then a project line when the
 * repository is mapped. Null when either family's line is missing.
 */
export function parseModeLines(text: string): CockpitRoots | null {
  let docs: CockpitRoots['docs'] | null = null
  let progress: CockpitRoots['progress'] | null = null
  let project: string | null = null
  for (const line of text.split(/\r?\n/)) {
    const [kind, store, root, extra] = line.split('\t')
    if (kind === 'project' && store) project = store
    if (store !== 'local' && store !== 'darkmem') continue
    if (kind === 'documents' && root) docs = { store, root }
    if (kind === 'progress' && root && extra) progress = { store, ledgerRoot: root, latestFile: extra }
  }
  return docs === null || progress === null ? null : { docs, progress, project }
}

/**
 * The Run card's finish row: the option chosen before the run, until
 * finishing carries it out or you answer the menu yourself.
 */
export function finishLine(finish: CockpitFinish): Run[] {
  if (finish.answer !== null) return []
  const label =
    finish.action === 'merge'
      ? `merge into ${finish.base ?? 'the base branch'}`
      : finish.action === 'pr'
        ? 'push and open a PR'
        : finish.action === 'keep'
          ? 'keep the branch'
          : 'ask me'
  return [{ text: 'Finish ', dim: true }, { text: label, bold: finish.action !== 'wait' }, { text: ' when done', dim: true }]
}

/** A background task's end as its notification reads: `<task-id>` and `<status>`. */
export function tasksEnded(text: string): { id: string; status: string }[] {
  const ended: { id: string; status: string }[] = []
  for (const block of text.split('<task-notification>').slice(1)) {
    const id = /<task-id>\s*([^<\s]+)\s*<\/task-id>/.exec(block)?.[1]
    if (id === undefined) continue
    ended.push({ id, status: /<status>\s*([^<\s]+)\s*<\/status>/.exec(block)?.[1] ?? 'completed' })
  }
  return ended
}

/** A remote client's surface as a person names the device. */
export function deviceName(surface: string): string {
  return surface === 'mobile' ? 'phone' : surface === 'desktop' ? 'desktop app' : surface === 'vscode' ? 'VS Code' : surface
}

/** Remote Control as the cockpit can see it: the devices attached, or the startup setting. */
export function remoteRuns(clients: readonly { surface: string }[], setting: string | null): Run[] {
  if (clients.length > 0) {
    const names = [...new Set(clients.map(one => deviceName(one.surface)))]
    const what = clients.length === 1 ? names[0]! : names.length === 1 ? `${clients.length} ${names[0]}s` : `${clients.length} devices`
    return [{ text: '● ', color: 'green', bold: true }, { text: 'connected' }, { text: ' · ', dim: true }, { text: what, color: 'green' }]
  }
  if (setting === 'true') return [{ text: '○ ', color: 'green' }, { text: 'on', color: 'green' }, { text: ' · no device yet', dim: true }]
  return [{ text: '○ not connected', dim: true }]
}

/** The run in an auto-run state file when it is bound to `sessionId`, active or not; else null. */
export function autoRunFor(text: string, sessionId: string): CockpitAutoRun | null {
  let parsed: unknown
  try {
    parsed = JSON.parse(text)
  } catch {
    return null
  }
  if (typeof parsed !== 'object' || parsed === null) return null
  const s = parsed as Record<string, unknown>
  if (s.session !== sessionId) return null
  const word = (value: unknown) => (typeof value === 'string' ? value : null)
  const count = (value: unknown) => (typeof value === 'number' && Number.isFinite(value) ? value : 0)
  const launch = (typeof s.launch === 'object' && s.launch !== null ? s.launch : {}) as Record<string, unknown>
  return {
    active: s.active === true,
    phase: word(s.phase) ?? 'spec',
    regime: word(s.regime) ?? 'normal',
    pending: word(s.pending),
    plan: word(s.plan),
    compactions: count(s.compactions),
    resumes: count(s.resumes),
    stopped: word(s.stopped),
    resumePrompt: word(s.resumePrompt),
    stalledAt: typeof s.stalledAt === 'number' && Number.isFinite(s.stalledAt) ? s.stalledAt : null,
    launch: typeof launch.model === 'string' && typeof launch.effort === 'string' ? { model: launch.model, effort: launch.effort } : null,
  }
}

/** The line an auto run's turn ends on, by the pending action it answers. */
export const AUTO_SENTINELS: Readonly<Record<string, string>> = { compact: 'Auto run: compacting', clear: 'Auto run: clearing', switch: 'Auto run: switching' }

/** Whether `answer`'s last non-blank line is the sentinel for `pending`. */
export function endsOnSentinel(answer: string, pending: string | null): boolean {
  const sentinel = pending === null ? undefined : AUTO_SENTINELS[pending]
  if (sentinel === undefined) return false
  const lines = answer.split('\n').map(line => line.trimEnd()).filter(line => line !== '')
  return lines[lines.length - 1] === sentinel
}

/**
 * An auto run's compaction point (reference/auto-run.md): the task budget, or
 * 90% of min(autoCompactWindow, window) in the high regime.
 */
export function autoLimitFor(regime: string, configured: number, window: number, compactWindow?: number): number {
  if (regime !== 'high') return budgetFor(configured, undefined, window, compactWindow)
  const room = compactWindow !== undefined && compactWindow > 0 ? Math.min(window, compactWindow) : window
  return Math.floor(room * 0.9)
}
