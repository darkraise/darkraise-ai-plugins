import RAW from '../../config/schema.mjs'

/** A setting's value as the settings file holds it. */
export type SettingValue = boolean | number | string

/** One setting as config/schema.mjs declares it. */
export type SettingSpec = {
  type: 'boolean' | 'number' | 'enum' | 'string'
  default: SettingValue
  group: string
  title: string
  description: string
  target: 'forge' | 'claude'
  env?: string
  min?: number
  max?: number
  step?: number
  values?: readonly string[]
}

export type Schema = Readonly<Record<string, SettingSpec>>

/** ~/.dr-forge/config.json as parsed: schema keys and the reserved darkmem object. */
export type SettingsFile = Record<string, unknown>

export const SCHEMA: Schema = RAW as unknown as Schema

/** Whether a value fits a setting exactly as the file must hold it. */
export function isValidSetting(spec: SettingSpec, value: unknown): value is SettingValue {
  switch (spec.type) {
    case 'boolean':
      return typeof value === 'boolean'
    case 'number':
      return (
        typeof value === 'number' &&
        Number.isFinite(value) &&
        (spec.min === undefined || value >= spec.min) &&
        (spec.max === undefined || value <= spec.max)
      )
    case 'enum':
      return typeof value === 'string' && (spec.values ?? []).includes(value)
    case 'string':
      return typeof value === 'string'
  }
}

/** A value as an environment variable spells it; undefined when it does not fit. */
export function settingFromText(spec: SettingSpec, text: string): SettingValue | undefined {
  const value =
    spec.type === 'boolean'
      ? text === 'true'
        ? true
        : text === 'false'
          ? false
          : undefined
      : spec.type === 'number'
        ? text.trim() === ''
          ? undefined
          : Number(text)
        : text
  return value !== undefined && isValidSetting(spec, value) ? value : undefined
}

/** Every setting in force: the environment variable a key names, then the file, then the default. */
export function resolveSettings(
  schema: Schema,
  file: SettingsFile,
  env: Readonly<Record<string, string | undefined>>,
): Record<string, SettingValue> {
  const values: Record<string, SettingValue> = {}
  for (const [key, spec] of Object.entries(schema)) {
    const raw = spec.env === undefined ? undefined : env[spec.env]
    const fromEnv = raw === undefined || raw === '' ? undefined : settingFromText(spec, raw)
    const stored = file[key]
    values[key] = fromEnv ?? (isValidSetting(spec, stored) ? stored : spec.default)
  }
  return values
}

/** One line for each environment or file value that does not fit its setting and is therefore ignored. */
export function settingProblems(
  schema: Schema,
  file: SettingsFile,
  env: Readonly<Record<string, string | undefined>>,
): string[] {
  const problems: string[] = []
  for (const [key, spec] of Object.entries(schema)) {
    const raw = spec.env === undefined ? undefined : env[spec.env]
    if (raw !== undefined && raw !== '' && settingFromText(spec, raw) === undefined) {
      problems.push(`${spec.env}=${raw} is not a valid ${key}; ignored`)
    }
    if (Object.prototype.hasOwnProperty.call(file, key) && !isValidSetting(spec, file[key])) {
      problems.push(`${key} in ~/.dr-forge/config.json is not valid; ignored`)
    }
  }
  return problems
}

/** The file after one setting is saved: a value equal to its default is dropped, everything else kept. */
export function settingWritten(schema: Schema, file: SettingsFile, key: string, value: SettingValue): SettingsFile {
  const spec = schema[key]
  if (spec === undefined) throw new Error(`unknown setting ${key}`)
  if (!isValidSetting(spec, value)) throw new Error(`${String(value)} is not a valid ${key}`)
  const next: SettingsFile = { ...file }
  if (value === spec.default) delete next[key]
  else next[key] = value
  return next
}

/** The first run's file: dr-cockpit's options that differ from their defaults, and dr-superpowers' darkmem mapping. */
export function importedSettings(schema: Schema, claudeSettings: unknown, oldForge: unknown): SettingsFile {
  const file: SettingsFile = {}
  const options = objectAt(objectAt(objectAt(claudeSettings, 'pluginConfigs'), 'dr-cockpit@darkraise'), 'options')
  for (const [key, spec] of Object.entries(schema)) {
    const value = options?.[key]
    if (isValidSetting(spec, value) && value !== spec.default) file[key] = value
  }
  const darkmem = objectAt(oldForge, 'darkmem')
  if (darkmem !== undefined) file.darkmem = darkmem
  return file
}

function objectAt(value: unknown, key: string): Record<string, unknown> | undefined {
  if (value === null || typeof value !== 'object') return undefined
  const inner = (value as Record<string, unknown>)[key]
  return inner !== null && typeof inner === 'object' && !Array.isArray(inner) ? (inner as Record<string, unknown>) : undefined
}
