// Types for meter.mjs, so the HUD mod's imports type-check.
export type Run = { text: string; color?: string; bold?: boolean; dim?: boolean }
export type TrackMark = { at: number; glyph: string; name: string }
export type TrackPart = { text: string; kind: 'fill' | 'empty' | 'mark'; mark?: string }

export function kTokens(n: number): string
export function bar(share: number, width: number): string
export function rampColor(percent: number): string
export function duration(ms: number): string
export function limitLabel(kind: string): string
export function sparkline(values: number[]): string
export function track(share: number, width: number, marks: TrackMark[]): TrackPart[]
export function trackRuns(parts: TrackPart[], color: string, markColors: Record<string, string>): Run[]
export function stackedRuns(values: number[], width: number): number[]
export function windowElapsed(kind: string, resetsAt: number | null, now: number): number | null
export function limitForecast(kind: string, percent: number, resetsAt: number | null, now: number): number | 'pace' | null
export function cellWidth(text: string): number
export function runsWidth(runs: readonly { text: string }[]): number
export function runsCut<R extends Run>(runs: readonly R[], width: number): (R | Run)[]
export function isAtLeast(base: string | undefined, least: string): boolean
