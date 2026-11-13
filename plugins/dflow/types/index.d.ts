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
    }
  }
}
