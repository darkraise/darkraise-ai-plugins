// Types for view.mjs, so the HUD mod's imports type-check.
import type { Hud, HudAccount, HudBreakdown, HudContext, HudEngine, HudRemote, HudRepo, HudUsage, HudWhere, Mode } from '../../types'
import type { Run } from './meter.mjs'

export type Card = { key: string; title: string; color: string; headline: Run[]; rows: Run[][] }
export type ResetFlag = { at?: string; session?: string }
type PlanTask = NonNullable<Hud['plan']>['tasks'][number]

export const MODES: Mode[]
export const RESET_FRESH_MS: number
export const RESET_INSTRUCTIONS: string
export const SECTIONS: string[]

export function nextMode(current: Mode, argument?: string): Mode | null
export function withoutControls<T>(value: T): T
export function isFreshReset(flag: ResetFlag | null | undefined, now: number): boolean
export function isResetFor(flag: ResetFlag | null | undefined, now: number, session: string): boolean
export function contextFile(session: string): string
export function nowRow(hud: Hud): Run[]
export function taskWindow(
  tasks: PlanTask[],
  currentNumber: number | undefined,
  size: number,
): { above: number; aboveDone: boolean; rows: PlanTask[]; below: number; belowDone: boolean }
export function planCard(hud: Hud, width?: number): Card
export function checksCard(hud: Hud): Card | null
export function boardCard(hud: Hud): Card | null
export function workersCard(hud: Hud): Card | null
export function nextRow(hud: Hud): Run[]
export function collapsedFrom(value: unknown): string[]
export function sectionsFrom(value: unknown): string[]
export function sectionsArg(text: string): string[] | null
export function sectionsToggled(list: string[], key: string): string[]
export function resumeOffer(hud: Hud): { title: string; next: string } | null
export function isOfferOver(start: Hud, hud: Hud): boolean
export function sectionsMoved(list: string[], key: string, delta: number): string[]
export function contextCard(input: { hud: Hud; context: HudContext | null; breakdown: HudBreakdown | null; readings: number[]; width: number }): Card | null
export function accountCard(input: { account: HudAccount; engine: HudEngine | null; remote: HudRemote | null }): Card
export function usageCard(input: { usage: HudUsage | null; now: number; width: number }): Card | null
export function repoCard(input: { repo: HudRepo | null; where: HudWhere }): Card
export function denseLines(
  input: {
    hud: Hud
    account: HudAccount | null
    remote: HudRemote | null
    context: HudContext | null
    usage: HudUsage | null
    now: number
    repo: HudRepo | null
    where: HudWhere | null
    shown: string[]
  },
  width: number,
): (Run[] & { key: string })[]
