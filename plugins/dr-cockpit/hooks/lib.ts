// Pure helpers, kept apart from the hooks so tests can reach them directly.

/** The strip's handoff reading shows from this share of the budget. */
export const WARN_AT = 0.8

/**
 * The handoff budget: the configured tokens, else DR_SUPERPOWERS_BUDGET, else
 * dr-superpowers' own rule (reference/session-budget.md): the compaction point
 * minus one task's worst growth, min(autoCompactWindow, window) × 93% − 140,000.
 * Small windows, where that comes out near zero, hold a fifth of the window.
 */
export function budgetFor(configured: number, env: string | undefined, window: number, compactWindow?: number): number {
  if (configured > 0) return Math.round(configured)
  const pinned = Number(env)
  if (Number.isFinite(pinned) && pinned > 0) return Math.round(pinned)
  const room = compactWindow !== undefined && compactWindow > 0 ? Math.min(window, compactWindow) : window
  return Math.max(Math.floor(room * 0.93) - 140_000, Math.floor(room / 5))
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

export const SECTIONS = ['account', 'context', 'usage', 'agents', 'plan', 'repo', 'guard'] as const
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

/** A number setting one step up or down, kept within its range. */
export function stepped(value: number, step: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value + step))
}

/** 465000 → "465k"; 1234567 → "1.2M". */
export function kTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
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

/** Whether a tool by this name writes a pull request or commits files. */
export function isGitWriteTool(tool: string): boolean {
  return /pull_request|create_or_update_file|push_files/.test(tool) && !/read|list|search|get_/.test(tool)
}

/** Whether a subagent type or skill name belongs to dr-superpowers. */
export function isSuperpowers(name: string): boolean {
  return name.startsWith('dr-superpowers:')
}

/** 0.8 → "▰▰▰▰▰▰▰▰▱▱" at width 10; never full below 100%. */
export function bar(share: number, width: number): string {
  const clamped = Math.min(Math.max(share, 0), 1)
  let on = Math.round(clamped * width)
  if (on === width && clamped < 1) on = width - 1
  return '▰'.repeat(on) + '▱'.repeat(width - on)
}

/** The usage ramp dr-status uses: green, yellow, orange, then red. */
export function rampColor(percent: number): string {
  if (percent >= 90) return 'error'
  if (percent >= 75) return '#ff8700'
  return percent >= 50 ? 'warning' : 'success'
}

/** Milliseconds → "3h40m", "2d4h", "12m"; nothing at or below zero. */
export function duration(ms: number): string {
  if (!(ms > 0)) return ''
  const minutes = Math.floor(ms / 60_000)
  const days = Math.floor(minutes / 1440)
  const hours = Math.floor((minutes % 1440) / 60)
  if (days > 0) return `${days}d${hours}h`
  return hours > 0 ? `${hours}h${minutes % 60}m` : `${minutes}m`
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

/** What the status strip draws, read from the session as dr-status reads its payload. */
export type StatusInput = {
  cwd: string | null
  /** The repository's root, when the working directory is in one. */
  root: string | null
  home: string | null
  repo: RepoState | null
  model: string | null
  effort: string | null
  context: { tokens: number; window: number } | null
  /** The share of the last main request served from the prompt cache, 0 to 1. */
  cache: number | null
  usd: number | null
  limits: readonly { kind: string; percent: number; resetsAt: number | null }[]
  now: number
  /** The context against the handoff budget, shown once it nears it; null keeps it off the strip. */
  handoff?: { tokens: number; limit: number; warnAt: number } | null
  /** A dr-superpowers run's progress: tasks done of all, and the round in flight. */
  run?: { done: number; total: number; round: number | null } | null
}

// dr-status' default palette.
const DIR = 'blue'
const GIT = 'magenta'
const MODEL = 'cyan'
const COST = '#af87ff'
const EFFORT: Record<string, string> = { low: 'gray', medium: 'blue', high: 'cyan', xhigh: '#af87ff', max: 'magenta' }
// Bar widths per tier, as dr-status narrows them; under 2 draws no bar.
const METER_WIDTHS = [
  { ctx: 10, cache: 10, limit: 8 },
  { ctx: 6, cache: 6, limit: 5 },
  { ctx: 4, cache: 4, limit: 3 },
  { ctx: 0, cache: 0, limit: 0 },
] as const
export const STATUS_TIERS = METER_WIDTHS.length

/** The cells a row of runs takes. */
export function runsWidth(runs: readonly Run[]): number {
  return runs.reduce((sum, run) => sum + [...run.text].length, 0)
}

/** A row cut to `width` cells, ending in an ellipsis when anything was cut. */
export function runsCut(runs: readonly Run[], width: number): Run[] {
  if (runsWidth(runs) <= width) return [...runs]
  const out: Run[] = []
  let left = Math.max(0, width - 1)
  for (const run of runs) {
    const chars = [...run.text]
    if (chars.length <= left) {
      out.push(run)
      left -= chars.length
      continue
    }
    if (left > 0) out.push({ ...run, text: chars.slice(0, left).join('') })
    break
  }
  if (width > 0) out.push({ text: '…', dim: true })
  return out
}

/** A color from dr-status' config: a 256-color number becomes hex, orange its own hex, a name stays. */
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

/** The accounts key dr-status colors by: the config directory, "~"-relative under home. */
export function accountKey(configDir: string, home: string): string {
  const dir = slashes(configDir)
  const base = slashes(home)
  if (dir === base) return '~'
  return base !== '' && dir.startsWith(`${base}/`) ? `~${dir.slice(base.length)}` : dir
}

/** Claude's billing type, "stripe_subscription" → "subscription". */
export function billingLabel(billing: string | null): string | null {
  if (billing === null || billing === '') return null
  return billing.replace(/^(stripe|apple|google)_/, '').replace(/_/g, ' ')
}

function slashes(path: string): string {
  return path.replace(/\\/g, '/').replace(/\/+$/, '')
}

/**
 * The working directory in dr-status' three tones: what leads to the
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

/** dr-status' two lines at one tier: 0 is the fullest, 3 the most compact. */
export function statusLines(input: StatusInput, tier: number): [Run[], Run[]] {
  const sep: Run = { text: tier < 2 ? '  ·  ' : ' · ', dim: true }
  const join = (segments: (Run[] | null)[]) =>
    segments.filter((one): one is Run[] => one !== null && one.length > 0).flatMap((one, index) => (index === 0 ? one : [sep, ...one]))
  const widths = METER_WIDTHS[Math.min(tier, METER_WIDTHS.length - 1)] ?? METER_WIDTHS[0]
  const extras = tier < 2

  let dir: Run[] | null = null
  if (input.cwd !== null) {
    const { lead, anchor, inner } = pathParts(input.cwd, input.root, input.home)
    const parts = inner.split('/').filter(Boolean)
    const leaf = parts[parts.length - 1] ?? anchor
    dir =
      tier === 0
        ? [{ text: lead, color: DIR, dim: true }, { text: anchor, color: DIR, bold: true }, { text: inner, color: DIR }]
        : tier === 1
          ? [{ text: anchor, color: DIR, bold: true }, { text: inner, color: DIR }]
          : tier === 2
            ? [{ text: anchor, color: DIR, bold: true }, { text: parts.length > 1 ? `/…/${leaf}` : inner, color: DIR }]
            : [{ text: leaf, color: DIR, bold: true }]
    dir = dir.filter(run => run.text !== '')
  }

  let git: Run[] | null = null
  if (input.repo !== null) {
    const r = input.repo
    const branch = tier === 3 && r.branch.length > 16 ? `${r.branch.slice(0, 15)}…` : r.branch
    const counters = [r.ahead > 0 ? `↑${r.ahead}` : '', r.behind > 0 ? `↓${r.behind}` : '', r.untracked > 0 ? `?${r.untracked}` : '']
      .filter(Boolean)
      .join(' ')
    git = [
      { text: branch, color: GIT, bold: true },
      ...(r.changed > 0 ? [{ text: '*', color: GIT }] : []),
      ...(tier < 2 && counters !== '' ? [{ text: ` ${counters}`, color: GIT }] : []),
    ]
  }

  const model = input.model === null ? null : [{ text: modelName(input.model, tier >= 2), color: MODEL, bold: true }]
  const effort = input.effort === null ? null : [{ text: input.effort, color: EFFORT[input.effort] ?? 'gray' }]
  const run =
    input.run == null || input.run.total === 0
      ? null
      : [{ text: `run ${input.run.done}/${input.run.total}${tier < 2 && input.run.round !== null ? ` r${input.run.round}` : ''}`, color: 'yellow' }]

  const meter = (label: string, share: number, colorShare: number, width: number, extra: string): Run[] => {
    const percent = Math.round(share * 100)
    const color = rampColor(colorShare * 100)
    return [
      { text: `${label} ` },
      ...(width >= 2 ? [{ text: `${bar(share, width)} `, color }] : []),
      { text: `${percent}%`, color, bold: true },
      ...(extras && extra !== '' ? [{ text: ` · ${extra}`, dim: true }] : []),
    ]
  }
  const ctx =
    input.context === null
      ? null
      : meter('ctx', input.context.tokens / input.context.window, input.context.tokens / input.context.window, widths.ctx, kTokens(input.context.tokens))
  // A high hit rate is good news: the bar fills with the hits, the color reads the misses.
  // The handoff reading joins the strip only once the context nears its budget.
  const near = input.handoff == null ? null : levelOf(input.handoff.tokens, input.handoff.limit, input.handoff.warnAt)
  const handoff =
    input.handoff == null || near === null || near === 'quiet'
      ? null
      : [
          { text: tier < 3 ? 'handoff ' : 'ho ' },
          { text: `${Math.round((input.handoff.tokens / input.handoff.limit) * 100)}%`, color: near === 'handoff' ? 'error' : 'warning', bold: true },
        ]
  const cache = input.cache === null ? null : meter('cache', input.cache, 1 - input.cache, widths.cache, '')
  const cost = input.usd === null ? null : [{ text: `$${input.usd.toFixed(2)}`, color: COST, bold: true }]
  const limits = input.limits.map(limit =>
    meter(limitLabel(limit.kind), limit.percent / 100, limit.percent / 100, widths.limit, limit.resetsAt === null ? '' : duration(limit.resetsAt - input.now)),
  )

  return [join([dir, git, model, effort, run]), join([ctx, handoff, cache, cost, ...limits])]
}

/**
 * Each line at the fullest tier that fits `width`, stepping down on its own;
 * a line too wide even at the last tier is cut.
 */
export function fitStatus(input: StatusInput, width: number): { tiers: [number, number]; lines: [Run[], Run[]] } {
  const fit = (which: 0 | 1): [number, Run[]] => {
    for (let tier = 0; tier < STATUS_TIERS; tier++) {
      const line = statusLines(input, tier)[which]
      if (runsWidth(line) <= width) return [tier, line]
    }
    return [STATUS_TIERS - 1, runsCut(statusLines(input, STATUS_TIERS - 1)[which], width)]
  }
  const [oneTier, one] = fit(0)
  const [twoTier, two] = fit(1)
  return { tiers: [oneTier, twoTier], lines: [one, two] }
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

/** One task's state in a dr-superpowers SDD ledger. */
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
    const one = task(Number(match[1]))
    const rest = match[2] ?? ''
    const assigned = /^implementer (\S+) \(assigned/.exec(rest)
    if (assigned) {
      one.seat = assigned[1] ?? null
      if (one.state !== 'complete') one.state = 'assigned'
      one.reason = null
      continue
    }
    const round = /^fix round (\d+\/\d+)/.exec(rest)
    if (round) {
      one.round = round[1] ?? null
      continue
    }
    if (/^complete\b/.test(rest)) {
      one.state = 'complete'
      one.round = null
      one.isClean = /review clean/.test(rest)
      continue
    }
    const blocked = /^BLOCKED\s*[—-]+\s*(.*)$/.exec(rest)
    if (blocked) {
      one.state = 'blocked'
      one.reason = blocked[1]?.trim() || null
    }
  }
  return { plan, tasks: [...tasks.values()].sort((a, b) => a.n - b.n), isFinished }
}

/** A plan file's tasks, from its "### Task N: title" headings. */
export function planTasks(text: string): { n: number; title: string }[] {
  const out: { n: number; title: string }[] = []
  for (const line of text.split(/\r?\n/)) {
    const match = /^#{2,4}\s+Task\s+(\d+)\s*[:.\-—]?\s*(.*)$/.exec(line.trim())
    if (match && !out.some(one => one.n === Number(match[1]))) out.push({ n: Number(match[1]), title: (match[2] ?? '').trim() })
  }
  return out
}

/** "2/5" → 2. */
export function roundNumber(round: string | null): number | null {
  const n = Number((round ?? '').split('/')[0])
  return round !== null && Number.isFinite(n) && n > 0 ? n : null
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
  kind: 'idle' | 'running' | 'waiting' | 'asking' | 'failed' | 'interrupted'
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

/** The Now row: one line, whatever the state, so the pane never jumps. */
export function nowLine(now: ActivityInput, at: number): Run[] {
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
    default:
      return [
        { text: '○ idle', dim: true },
        ...(now.lastTurnMs === null ? [] : [sep, { text: 'last turn ', dim: true }, { text: elapsed(now.lastTurnMs) }]),
        ...(now.endedAt === null ? [] : [sep, { text: `ended ${duration(at - now.endedAt) || '<1m'} ago`, dim: true }]),
      ]
  }
}

/** The Now row cut down for the strip's top rule; nothing while idle. */
export function nowBadge(now: ActivityInput, at: number): Run[] {
  switch (now.kind) {
    case 'running':
      return [
        { text: '● ', color: 'cyan', bold: true },
        { text: elapsed(at - (now.turnStartedAt ?? now.since)), color: 'cyan' },
        ...(now.tool === null ? [] : [{ text: ` · ${now.tool}`, color: 'cyan' }]),
      ]
    case 'waiting':
      return [{ text: `⏳ waiting ${elapsed(at - now.since)}`, color: AMBER, bold: true }]
    case 'asking':
      return [{ text: `❓ asking ${elapsed(at - now.since)}`, color: AMBER, bold: true }]
    case 'failed':
      return [{ text: '✗ failed', color: 'error', bold: true }]
    case 'interrupted':
      return [{ text: '■ interrupted', color: AMBER, bold: true }]
    default:
      return []
  }
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
    const what = clients.length === 1 ? names[0] : names.length === 1 ? `${clients.length} ${names[0]}s` : `${clients.length} devices`
    return [{ text: '● ', color: 'green', bold: true }, { text: 'connected' }, { text: ' · ', dim: true }, { text: what, color: 'green' }]
  }
  if (setting === 'true') return [{ text: '○ ', color: 'green' }, { text: 'on', color: 'green' }, { text: ' · no device yet', dim: true }]
  return [{ text: '○ not connected', dim: true }]
}

/** What keeps running beside the turn, for the strip's bottom rule: shells and remote devices. */
export function backgroundBadge(shells: number, clients: readonly { surface: string }[]): Run[] {
  const runs: Run[] = []
  if (shells > 0) runs.push({ text: '$ ', color: 'yellow', bold: true }, { text: `${shells} ${shells === 1 ? 'shell' : 'shells'}`, color: 'yellow' })
  if (clients.length > 0) {
    if (runs.length > 0) runs.push({ text: ' · ', dim: true })
    const names = [...new Set(clients.map(one => deviceName(one.surface)))]
    runs.push({ text: '● ', color: 'green', bold: true }, { text: clients.length === 1 || names.length === 1 ? names[0] : `${clients.length} devices`, color: 'green' })
  }
  return runs
}
