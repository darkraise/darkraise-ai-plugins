// Types for schema.mjs, so the cockpit's imports type-check.
export type SettingSpecShape = {
  type: string
  min?: number
  max?: number
  floor?: number
  values?: readonly string[]
}
export function isValidValue(spec: SettingSpecShape, value: unknown): boolean
export function listNames(spec: SettingSpecShape, value: unknown): { known: string[]; unknown: string[] } | undefined
export function resolveStored(key: string, spec: SettingSpecShape & { default: unknown }, file: Readonly<Record<string, unknown>>): unknown
declare const schema: Record<string, Record<string, unknown>>
export default schema
