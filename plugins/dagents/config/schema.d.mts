// Types for schema.mjs, so the cockpit's imports type-check.
export type SettingSpecShape = {
  type: string
  min?: number
  max?: number
  floor?: number
  values?: readonly string[]
}
export function isValidValue(spec: SettingSpecShape, value: unknown): boolean
declare const schema: Record<string, Record<string, unknown>>
export default schema
