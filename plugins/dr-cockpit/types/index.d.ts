/** The main session's context against its handoff budget, as last read. */
export type CockpitBudget = {
  /** Input tokens the last main-loop response was answered over. */
  tokens: number
  /** The handoff budget in tokens. */
  limit: number
  /** The model's context window in tokens. */
  window: number
  /** The auto-compaction window from the settings, when one is set. */
  compactWindow: number | null
  /** What the session has cost so far, in US dollars, when the host says. */
  usd: number | null
}

/** One rate-limit window as the last response reported it. */
export type CockpitLimit = {
  /** `five_hour`, `seven_day`, or a gateway's `spend_limit`. */
  kind: string
  percent: number
  /** When the window resets, in milliseconds since the epoch. */
  resetsAt: number | null
}

/** The account's limits and the session's spend, from the last measurement. */
export type CockpitUsage = {
  limits: CockpitLimit[]
  /** When the session began, in milliseconds since the epoch. */
  startedAt: number
  /** When these figures were read, in milliseconds since the epoch. */
  readAt: number
}

/** One row of the /context breakdown. */
export type CockpitContextRow = {
  name: string
  tokens: number
}

/** The /context breakdown, estimated locally. */
export type CockpitBreakdown = {
  rows: CockpitContextRow[]
  /** The token count at which auto-compaction runs, when it is on. */
  compactAt: number | null
}

/** One subagent type's runs and tokens this session. */
export type CockpitSeat = {
  seat: string
  runs: number
  input: number
  cacheRead: number
  cacheWrite: number
  output: number
}

/** One subagent the session started. */
export type CockpitSpawn = {
  agentId: string
  seat: string
  model: string
  description: string
  isDone: boolean
  /** When it started, in milliseconds since the epoch. */
  startedAt: number
}

/** One item of the session's todo or task list. */
export type CockpitPlanItem = {
  id: string
  text: string
  status: 'pending' | 'in_progress' | 'completed'
}

/** The working directory's git state. */
export type CockpitRepo = {
  branch: string
  ahead: number
  behind: number
  changed: number
  untracked: number
}

/** A git write the attribution guard refused. */
export type CockpitRefusal = {
  at: number
  tool: string
  line: string
}

declare module 'claude-code' {
  interface PluginState {
    'dr-cockpit': {
      budget: CockpitBudget | null
      usage: CockpitUsage | null
      breakdown: CockpitBreakdown | null
      seats: CockpitSeat[]
      spawns: CockpitSpawn[]
      plan: CockpitPlanItem[]
      repo: CockpitRepo | null
      refusals: CockpitRefusal[]
      /** Rate-limit windows already alerted, as `<kind>@<resetsAt>`. */
      alerted: string[]
      isBandHidden: boolean
      isNudged: boolean
      isPlanSession: boolean
    }
  }
}
