/** The main session's context against its handoff budget, as last read. */
export type CockpitBudget = {
  /** Input tokens the last main-loop response was answered over. */
  tokens: number
  /** The handoff budget in tokens. */
  limit: number
  /** What the session has cost so far, in US dollars, when the host says. */
  usd: number | null
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
}

declare module 'claude-code' {
  interface PluginState {
    'dr-cockpit': {
      budget: CockpitBudget | null
      seats: CockpitSeat[]
      spawns: CockpitSpawn[]
      isBandHidden: boolean
      isNudged: boolean
      isPlanSession: boolean
    }
  }
}
