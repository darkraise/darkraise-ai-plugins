// Pure helpers, kept apart from the hooks so tests can reach them directly.

/** The band shows from this share of the budget. */
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

export const SECTIONS = ['context', 'usage', 'agents', 'plan', 'repo', 'guard'] as const
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
 * off. All six in their own order is the empty setting.
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
