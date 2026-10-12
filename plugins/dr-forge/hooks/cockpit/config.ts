import RAW from '../../config/schema.mjs'

/** A setting's value as the settings file holds it. */
export type SettingValue = boolean | number | string

/** One setting as config/schema.mjs declares it. */
export type SettingSpec = {
  type: 'boolean' | 'number' | 'enum' | 'string'
  default: SettingValue
  group: string
  /** The row's label in the settings view. */
  label: string
  title: string
  description: string
  target: 'forge' | 'claude'
  env?: string
  min?: number
  max?: number
  step?: number
  values?: readonly string[]
  /** How a number reads: thousands of tokens, a percentage, seconds or minutes. */
  unit?: 'k' | '%' | 's' | 'min'
  /** The word shown at 0. */
  zero?: string
  /** The smallest value allowed other than 0, on a number where 0 means unset. */
  floor?: number
  enforcedBy?: 'script' | 'skill'
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
      // A number setting is whole, as scripts/lib/forge-config.mjs holds it too.
      if (typeof value !== 'number' || !Number.isInteger(value)) return false
      // A floor leaves 0 as the one value below it: "unset".
      if (spec.floor !== undefined) return value === 0 || (value >= spec.floor && (spec.max === undefined || value <= spec.max))
      return (spec.min === undefined || value >= spec.min) && (spec.max === undefined || value <= spec.max)
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

/**
 * Every setting in force. A forge key: the environment variable it names, then the file, then the default.
 * A Claude key: Claude's own settings as the engine merged them, then the default.
 */
export function resolveSettings(
  schema: Schema,
  file: SettingsFile,
  env: Readonly<Record<string, string | undefined>>,
  claude: Readonly<Record<string, unknown>> = {},
): Record<string, SettingValue> {
  const values: Record<string, SettingValue> = {}
  for (const [key, spec] of Object.entries(schema)) {
    if (spec.target === 'claude') {
      const held = claude[key]
      values[key] = isValidSetting(spec, held) ? held : spec.default
      continue
    }
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
    if (spec.target === 'forge' && Object.prototype.hasOwnProperty.call(file, key) && !isValidSetting(spec, file[key])) {
      problems.push(`${key} in ~/.dr-forge/config.json is not valid; ignored`)
    }
  }
  return problems
}

/** The file after one setting is saved: a value equal to its default is dropped, everything else kept. */
export function settingWritten(schema: Schema, file: SettingsFile, key: string, value: SettingValue): SettingsFile {
  const spec = schema[key]
  if (spec === undefined) throw new Error(`unknown setting ${key}`)
  if (spec.target === 'claude') throw new Error(`${key} is stored in Claude's settings file`)
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
    if (spec.target === 'forge' && isValidSetting(spec, value) && value !== spec.default) file[key] = value
  }
  const darkmem = objectAt(oldForge, 'darkmem')
  if (darkmem !== undefined) file.darkmem = darkmem
  return file
}

/** One settings-view row drawn from the schema. */
export type SettingRow = {
  key: string
  group: string
  title: string
  kind: 'toggle' | 'choices' | 'stepper' | 'text'
  value: SettingValue
  values: readonly string[]
  min: number
  max: number
  step: number
}

/** A row for each setting the view has no control of its own for, in schema order. */
export function schemaRows(
  schema: Schema,
  values: Readonly<Record<string, SettingValue>>,
  custom: ReadonlySet<string>,
): SettingRow[] {
  return Object.entries(schema)
    .filter(([key]) => !custom.has(key))
    .map(([key, spec]) => ({
      key,
      group: spec.group,
      title: spec.title,
      kind: spec.type === 'boolean' ? 'toggle' : spec.type === 'enum' ? 'choices' : spec.type === 'number' ? 'stepper' : 'text',
      value: values[key] ?? spec.default,
      values: spec.values ?? [],
      min: spec.min ?? 0,
      max: spec.max ?? Number.MAX_SAFE_INTEGER,
      step: spec.step ?? 1,
    }))
}

/** One settings-view row, drawn from the schema and the value in force. */
export type ViewRow = {
  key: string
  group: string
  label: string
  description: string
  kind: 'toggle' | 'choices' | 'stepper' | 'text'
  value: SettingValue
  /** The value as its row reads, through the unit and the zero word. */
  shown: string
  /** The default the same way, for the line under a changed row. */
  shownDefault: string
  values: readonly string[]
  isChanged: boolean
  /** What forces the value from outside the file; such a row draws no controls. */
  lockedBy: string | null
}

/** The view's tabs: the schema's groups in the order they first appear. */
export function tabsOf(schema: Schema): string[] {
  return [...new Set(Object.values(schema).map(spec => spec.group))]
}

/** A value as its row reads: on or off, a number through its unit and zero word, anything else as text. */
export function shownValue(spec: SettingSpec, value: SettingValue): string {
  if (spec.type === 'boolean') return value === true ? 'on' : 'off'
  if (spec.type !== 'number' || typeof value !== 'number') return String(value)
  if (value === 0 && spec.zero !== undefined) return spec.zero
  if (spec.unit === 'k') return `${value / 1000}k`
  if (spec.unit === 'min') return `${value} min`
  return `${value}${spec.unit ?? ''}`
}

/** A number typed into a row: whole, with a trailing k for thousands; undefined when it does not fit the setting. */
export function typedNumber(spec: SettingSpec, text: string): number | undefined {
  const typed = text.trim().toLowerCase()
  // At most three significant decimals before k, so rounding only removes floating-point error (1.001 * 1000 is 1000.9999999999999).
  const value = /^\d+(\.\d{1,3}0*)?k$/.test(typed) ? Math.round(Number(typed.slice(0, -1)) * 1000) : /^\d+$/.test(typed) ? Number(typed) : Number.NaN
  return Number.isInteger(value) && isValidSetting(spec, value) ? value : undefined
}

// The mod's runtime is not promised a locale, so the digits are grouped by hand.
function grouped(n: number): string {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
}

/** What a typed number must be, for the row's refusal. */
export function rangeText(spec: SettingSpec): string {
  const to = grouped(spec.max ?? Number.MAX_SAFE_INTEGER)
  return spec.floor === undefined
    ? `Enter a whole number from ${grouped(spec.min ?? 0)} to ${to}`
    : `Enter 0 or a whole number from ${grouped(spec.floor)} to ${to}`
}

/** One press of − (-1) or + (1): the next multiple of the step, kept in range; a floor is entered from 0 and left to 0. */
export function steppedSetting(spec: SettingSpec, value: number, direction: 1 | -1): number {
  const step = spec.step ?? 1
  const next = direction > 0 ? Math.floor(value / step) * step + step : Math.ceil(value / step) * step - step
  if (spec.floor !== undefined) {
    if (direction > 0 && value < spec.floor) return spec.floor
    if (direction < 0 && next < spec.floor) return 0
  }
  return Math.min(spec.max ?? Number.MAX_SAFE_INTEGER, Math.max(spec.min ?? 0, next))
}

/** A setting's row. A locked row is never "changed": the file is not what holds its value. */
export function rowOf(key: string, spec: SettingSpec, value: SettingValue, lockedBy: string | null = null): ViewRow {
  return {
    key,
    group: spec.group,
    label: spec.label,
    description: spec.description,
    kind: spec.type === 'boolean' ? 'toggle' : spec.type === 'enum' ? 'choices' : spec.type === 'number' ? 'stepper' : 'text',
    value,
    shown: shownValue(spec, value),
    shownDefault: shownValue(spec, spec.default),
    values: spec.values ?? [],
    isChanged: lockedBy === null && value !== spec.default,
    lockedBy,
  }
}

/** A group's rows in schema order. */
export function rowsOf(
  schema: Schema,
  values: Readonly<Record<string, SettingValue>>,
  group: string,
  locks: Readonly<Record<string, string>> = {},
): ViewRow[] {
  return Object.entries(schema)
    .filter(([, spec]) => spec.group === group)
    .map(([key, spec]) => rowOf(key, spec, values[key] ?? spec.default, locks[key] ?? null))
}

/** The keys an environment variable forces, each with the words its row shows. */
export function envLocks(schema: Schema, env: Readonly<Record<string, string | undefined>>): Record<string, string> {
  const locks: Record<string, string> = {}
  for (const [key, spec] of Object.entries(schema)) {
    const raw = spec.env === undefined ? undefined : env[spec.env]
    if (spec.env !== undefined && raw !== undefined && raw !== '' && settingFromText(spec, raw) !== undefined) locks[key] = `set by ${spec.env}`
  }
  return locks
}

/** The Claude keys a project or managed settings file overrides: the merged value is not the user file's. */
export function claudeLocks(schema: Schema, merged: Readonly<Record<string, unknown>>, user: Readonly<Record<string, unknown>>): Record<string, string> {
  const locks: Record<string, string> = {}
  for (const [key, spec] of Object.entries(schema)) {
    if (spec.target === 'claude' && merged[key] !== undefined && merged[key] !== user[key]) locks[key] = 'set by a project or managed settings file'
  }
  return locks
}

function objectAt(value: unknown, key: string): Record<string, unknown> | undefined {
  if (value === null || typeof value !== 'object') return undefined
  const inner = (value as Record<string, unknown>)[key]
  return inner !== null && typeof inner === 'object' && !Array.isArray(inner) ? (inner as Record<string, unknown>) : undefined
}
