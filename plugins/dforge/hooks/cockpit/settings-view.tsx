import type { EngineInterface, RenderChildren } from 'claude-code'

import type { SettingValue, ViewRow } from './config'

// The engine refuses to pass `$` across an import, so this module draws from
// the surface's element table and reports every press through a callback.
type Elements = ReturnType<EngineInterface['ui']['resolve']>

const LABEL_WIDTH = 16
const INDENT = 2
const CARD = '#8080800f'
const ACCENT = 'permission'

/** What the settings view shows. */
export type SettingsModel = {
  tabs: readonly string[]
  tab: string
  /** Drawn dim beside the open group's name. */
  hint: string | null
  rows: readonly ViewRow[]
  isHelpShown: boolean
  /** The key whose value is being typed, and why the last entry was refused. */
  editing: string | null
  error: string | null
  isConfirmingReset: boolean
  /** Whether the surface has a text field. */
  canType: boolean
  /** Saved or environment values the settings in force ignored. */
  problems: readonly string[]
  /** Rows the caller draws itself, by key, in place of the schema's control. */
  custom: Readonly<Record<string, RenderChildren>>
  /** Drawn above the open group's rows. */
  top: RenderChildren
}

/** What each press does. */
export type SettingsActions = {
  openTab: (tab: string) => unknown
  set: (key: string, value: SettingValue) => unknown
  step: (key: string, direction: 1 | -1) => unknown
  edit: (key: string | null) => unknown
  submit: (key: string, text: string) => unknown
  reset: (key: string) => unknown
  toggleHelp: () => unknown
  askResetGroup: () => unknown
  resetGroup: () => unknown
  cancelReset: () => unknown
  back: () => unknown
}

/** The cockpit's settings: a tab for each group, the open group's rows, and the footer. */
export function drawSettings(table: Elements, model: SettingsModel, act: SettingsActions): RenderChildren {
  const { Box, Button, Text } = table
  const Input = 'Input' in table ? table.Input : undefined
  const press = (key: string, label: string, onPress: () => unknown, look: { hotkey?: string; isMain?: boolean; isOff?: boolean } = {}) => (
    <Button key={key} label={label} hotkey={look.hotkey} variant={look.isMain ? 'primary' : undefined} dimColor={look.isOff} onPress={onPress} />
  )

  const control = (row: ViewRow): RenderChildren => {
    if (row.lockedBy !== null) {
      return [
        <Text key={`set-${row.key}-value`} bold>{`${row.shown} `}</Text>,
        <Text key={`set-${row.key}-lock`} dimColor>
          {row.lockedBy}
        </Text>,
      ]
    }
    if (row.kind === 'toggle') {
      const isOn = row.value === true
      return press(`set-${row.key}-toggle`, isOn ? '● On' : '○ Off', () => act.set(row.key, !isOn), { isMain: isOn, isOff: !isOn })
    }
    if (row.kind === 'choices') {
      return row.values.map(choice =>
        press(`set-${row.key}-${choice}`, choice, () => act.set(row.key, choice), { isMain: row.value === choice, isOff: row.value !== choice }),
      )
    }
    if (model.editing === row.key && Input !== undefined) {
      return [
        <Input key={`set-${row.key}-input`} placeholder={String(row.value)} submitLabel="save" autoFocus onSubmit={(text: string) => act.submit(row.key, text)} />,
        press(`set-${row.key}-cancel`, 'Cancel', () => act.edit(null)),
      ]
    }
    const edit = model.canType && press(`set-${row.key}-edit`, 'Edit', () => act.edit(row.key), { isOff: true })
    if (row.kind === 'stepper') {
      return [
        <Text key={`set-${row.key}-value`} bold>
          {row.shown.padEnd(7)}
        </Text>,
        press(`set-${row.key}-less`, '−', () => act.step(row.key, -1)),
        press(`set-${row.key}-more`, '+', () => act.step(row.key, 1)),
        edit,
      ]
    }
    return [
      <Text key={`set-${row.key}-value`} dimColor={row.shown === ''}>{`${row.shown || '(empty)'} `}</Text>,
      edit || (
        <Text key={`set-${row.key}-cli`} dimColor>
          {`forge-config set ${row.key}`}
        </Text>
      ),
    ]
  }

  // Under a row: its description while help is shown, and its default with a Reset once it differs.
  const below = (row: ViewRow): RenderChildren => [
    model.isHelpShown && (
      <Box key={`set-${row.key}-help`} paddingLeft={INDENT}>
        <Text dimColor wrap="wrap">
          {row.description}
        </Text>
      </Box>
    ),
    row.isChanged && (
      <Box key={`set-${row.key}-default`} flexDirection="row" columnGap={1} paddingLeft={INDENT}>
        <Text key={`set-${row.key}-default-text`} dimColor>{row.shownDefault === '' ? 'changed from the default' : `default ${row.shownDefault}`}</Text>
        {press(`set-${row.key}-reset`, 'Reset', () => act.reset(row.key))}
      </Box>
    ),
  ]

  const mark = (row: ViewRow): RenderChildren =>
    row.isChanged && (
      <Box key={`set-${row.key}-mark`}>
        <Text color="yellow" bold>*</Text>
      </Box>
    )

  // A row the caller draws itself still gets the mark, the help and the default line.
  const drawRow = (row: ViewRow): RenderChildren => (
    <Box key={`set-${row.key}-block`} flexDirection="column">
      {model.custom[row.key] !== undefined ? (
        <Box key={`set-${row.key}`} flexDirection="row" columnGap={1}>
          {model.custom[row.key]}
          {mark(row)}
        </Box>
      ) : (
        // Controls that overflow wrap in the value column, not under the label.
        <Box key={`set-${row.key}`} flexDirection="row" columnGap={1}>
          <Box key={`set-${row.key}-label`} width={LABEL_WIDTH} flexShrink={0}>
            <Text>{row.label}</Text>
          </Box>
          <Box key={`set-${row.key}-controls`} flexDirection="row" flexWrap="wrap" alignItems="center" columnGap={1} flexShrink={1}>
            {control(row)}
            {mark(row)}
          </Box>
        </Box>
      )}
      {model.editing === row.key && model.error !== null && (
        <Text key={`set-${row.key}-error`} color="red">{`${' '.repeat(INDENT)}✗ ${model.error}`}</Text>
      )}
      {below(row)}
    </Box>
  )

  const changed = model.rows.filter(row => row.isChanged).length
  return (
    <Box flexDirection="column">
      <Text bold>Settings</Text>
      <Box key="settings-tabs" flexDirection="row" flexWrap="wrap" columnGap={1}>
        {model.tabs.map((tab, index) =>
          press(`settings-tab-${tab}`, tab, () => act.openTab(tab), { hotkey: index < 9 ? String(index + 1) : undefined, isMain: tab === model.tab, isOff: tab !== model.tab }),
        )}
      </Box>
      <Box key={`set-group-${model.tab}`} flexDirection="column" borderStyle="round" borderColor="subtle" backgroundColor={CARD} paddingX={1}>
        <Box key="set-group-head" flexDirection="row" columnGap={1}>
          <Text bold color={ACCENT}>
            {model.tab}
          </Text>
          {model.hint !== null && (
            <Text key="set-group-hint" dimColor>
              {model.hint}
            </Text>
          )}
          <Text key="set-group-changed" dimColor>
            {changed === 0 ? 'all defaults' : `${changed} changed`}
          </Text>
        </Box>
        {model.top}
        {model.rows.map(drawRow)}
      </Box>
      {model.problems.map((problem, index) => (
        <Text key={`set-problem-${index}`} color="yellow">
          ⚠ {problem}
        </Text>
      ))}
      <Box key="settings-actions" flexDirection="row" flexWrap="wrap" columnGap={1}>
        {press('settings-back', 'Back', act.back, { hotkey: 'b' })}
        {press('settings-help', model.isHelpShown ? 'Hide help' : 'Show help', act.toggleHelp, { hotkey: 'i' })}
        {model.isConfirmingReset
          ? [press('settings-reset-confirm', 'Confirm reset', act.resetGroup, { hotkey: 'r', isMain: true }), press('settings-reset-cancel', 'Cancel', act.cancelReset)]
          : changed > 0 && press('settings-reset', 'Reset group', act.askResetGroup, { hotkey: 'r' })}
      </Box>
      <Text dimColor>Saved to ~/.dforge/config.json{model.tab === 'Context' ? "; the auto-compact rows save to Claude's settings file" : ''}.</Text>
    </Box>
  )
}
