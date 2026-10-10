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

/** One background shell the session started and has not heard the end of. */
export type CockpitShell = {
  /** The background task's id, as its notification names it. */
  id: string
  command: string
  /** When it went to the background, in milliseconds since the epoch. */
  startedAt: number
}

/** Remote Control as the cockpit sees it. */
export type CockpitRemote = {
  /** The remote clients attached now (a phone, the desktop app). */
  clients: { id: string; surface: string }[]
  /** The `/config` row "Enable Remote Control for all sessions": `true`, `false` or `default`. */
  setting: string | null
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

/** The account the session runs as, from its .claude.json and dr-status' config. */
export type CockpitAccount = {
  email: string | null
  name: string | null
  organization: string | null
  role: string | null
  /** Claude's billing type, such as `stripe_subscription`. */
  billing: string | null
  /** The config directory as dr-status keys it: `~/.claude`, `~/.claude-work`. */
  key: string
  /** The frame color dr-status assigns this account, as configured. */
  color: string | null
}

/** Where the session runs, for the status strip's path. */
export type CockpitPlace = {
  cwd: string
  /** The repository's root, when the working directory is in one. */
  root: string | null
  /** The repository's `origin` remote URL, when it has one. */
  remote?: string | null
  home: string | null
}

/** The main loop's model, effort and cache hit rate, as its last request had them. */
export type CockpitEngine = {
  model: string | null
  effort: string | null
  /** The share of the last main turn's input served from the cache, 0 to 1. */
  cache: number | null
}

/** What the session is doing now, for the Now row and the state file. */
export type CockpitActivity = {
  /** `waiting` on an approval, `asking` a question, `failed` once a turn ended in an error, `interrupted` once Esc stopped it. */
  kind: 'idle' | 'running' | 'waiting' | 'asking' | 'failed' | 'interrupted'
  /** When this state began, in milliseconds since the epoch. */
  since: number
  /** When the running turn began. */
  turnStartedAt: number | null
  /** The main loop's request count this turn. */
  step: number
  /** The tool in flight, and the subagent seat running it. */
  tool: string | null
  agent: string | null
  /** What waits on the person, or why the turn failed. */
  detail: string | null
  lastTurnMs: number | null
  endedAt: number | null
  /** Whether a Discord message went out for this state. */
  isSent: boolean
}

/** One task of a dr-superpowers run, from its plan and its ledger. */
export type CockpitRunTask = {
  n: number
  title: string
  state: 'pending' | 'assigned' | 'complete' | 'blocked'
  /** The fix or review round in flight, "2/5". */
  round: string | null
  seat: string | null
  isClean: boolean
  reason: string | null
}

/** A dr-superpowers run as its SDD ledger tells it. */
export type CockpitRun = {
  plan: string | null
  tasks: CockpitRunTask[]
  done: number
  total: number
  isFinished: boolean
}

/** The Discord webhook's state, as the settings view shows it. */
export type CockpitNotifier = {
  /** The webhook URL; never drawn, only masked. */
  url: string | null
  isFromEnv: boolean
  /** The Discord user id that ping messages mention. */
  mention: string | null
  /** The field being edited in the settings view. */
  editing: 'url' | 'mention' | null
  /** Why the last edit was refused. */
  error: string | null
  /** The last send's outcome. */
  last: { at: number; text: string; isError: boolean } | null
}

declare module 'claude-code' {
  interface PluginState {
    'dr-cockpit': {
      budget: CockpitBudget | null
      usage: CockpitUsage | null
      breakdown: CockpitBreakdown | null
      seats: CockpitSeat[]
      spawns: CockpitSpawn[]
      shells: CockpitShell[]
      remote: CockpitRemote
      plan: CockpitPlanItem[]
      repo: CockpitRepo | null
      refusals: CockpitRefusal[]
      account: CockpitAccount | null
      place: CockpitPlace | null
      engine: CockpitEngine
      /** Rate-limit windows already alerted, as `<kind>@<resetsAt>`. */
      alerted: string[]
      /** The main session's context readings, oldest first, for the trend line. */
      trend: number[]
      /** Whether the pane shows the cockpit or its settings. */
      view: 'cockpit' | 'settings'
      activity: CockpitActivity
      /** The main session's context at the end of each turn, oldest first, for the forecast. */
      turnTokens: number[]
      run: CockpitRun | null
      /** When the newest handoff note was written, in milliseconds since the epoch. */
      handoffAt: number | null
      notifier: CockpitNotifier
      isNudged: boolean
      isPlanSession: boolean
    }
  }
}
