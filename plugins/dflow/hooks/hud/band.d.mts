// Types for band.mjs, so the HUD mod's imports type-check.
import type { Hud, HudAccount, HudContext, HudEngine, HudRemote, HudRepo, HudUsage, HudWhere } from '../../types'
import type { Run } from './meter.mjs'

export type BandInput = {
  hud: Hud
  where: HudWhere | null
  repo: HudRepo | null
  engine: HudEngine | null
  context: HudContext | null
  usage: HudUsage | null
  now: number
}

export const BAND_TIERS: number
export function bandLines(input: BandInput, tier: number): [Run[], Run[]]
export function fitBand(input: BandInput, width: number): [Run[], Run[]]
export function bandTop(input: { account: HudAccount | null; remote: HudRemote | null }): Run[]
export function bandWarning(hud: Hud): Run[]
