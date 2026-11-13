export type Mode = 'band' | 'pane' | 'off'

export type HudTask = { number: number; title: string; state: string; attempts?: number }

export type Hud = {
  branch: string | null
  next: string
  plan: null | {
    title: string
    file: string
    done: number
    total: number
    current: HudTask | null
    blocked: { number: number; reason: string }[]
    approved: string | null
    tasks: { number: number; title: string; state: string; run?: string }[]
  }
  gates: null | { ok: boolean; stale: boolean; failed: string[] }
  review: null | { recorded: null | { tier: number }; open: number; blocking: number }
  board: null | { counts: Record<string, number>; row: null | { number: number; state: string } }
  sync: {
    enabled: boolean
    queued?: number
    conflict?: string | null
    error?: string | null
    offline?: boolean
    refused?: number
  }
  context: null | { resetAt: number }
  workers: { task: number; path?: string; branch?: string }[]
  checks: string[]
}

export type HudContext = { tokens?: number; window: number }

export type HudAccount = {
  email: string | null
  name: string | null
  organization: string | null
  role: string | null
  billing: string | null
  key: string
  color: string
}

export type HudEngine = { model: string | null; effort: string | null }

export type HudRemote = { clients: { id: string; surface: string }[]; setting: string | null }

export type HudUsage = {
  limits: { kind: string; percent: number; resetsAt: number | null }[]
  usd: number | null
  startedAt: number
}

export type HudRepo = { branch: string; ahead: number; behind: number; changed: number; untracked: number }

export type HudWhere = { cwd: string; root: string | null; home: string | null; remote: string | null }

export type HudBreakdown = {
  rows: { name: string; tokens: number }[]
  compactAt: number | null
  total: number | null
}

declare module 'claude-code' {
  interface PluginState {
    dflow: {
      hud: Shaped<Hud | null>
      mode: Mode
      context: HudContext | null
      collapsed: string[]
      readings: number[]
      breakdown: HudBreakdown | null
      account: HudAccount | null
      engine: HudEngine
      remote: HudRemote
      usage: HudUsage | null
      repo: HudRepo | null
      where: HudWhere | null
    }
  }
}
