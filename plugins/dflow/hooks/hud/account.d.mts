// Types for account.mjs, so the HUD mod's imports type-check.
import type { HudAccount, HudRemote } from '../../types'
import type { Run } from './meter.mjs'

export function accountKey(configDir: string, home: string): string
export function accountColor(key: string): string
export function billingLabel(billing: string | null | undefined): string | null
export function modelName(id: string, isShort?: boolean): string
export function deviceName(surface: string): string
export function remoteRuns(clients: HudRemote['clients'], setting: string | null): Run[]
export function accountFrom(claudeJson: unknown, configDir: string, home: string): HudAccount
