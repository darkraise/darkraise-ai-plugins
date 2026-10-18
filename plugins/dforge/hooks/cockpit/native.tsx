import type { EngineInterface, RenderChildren } from 'claude-code'

import { themeColor } from './lib'
import { CELL_PX } from './svg'
import type { PanelLine, PanelRun } from './svg'

// The engine refuses to pass `$` across an import, so this module draws from
// the surface's element table, as settings-view.tsx does.
type Elements = ReturnType<EngineInterface['ui']['resolve']>

/** One run as the desktop's own text: a theme color, dim or faint dimmed, bold semibold, a chip on a soft pill. */
export function nativeRun(table: Elements, key: string, run: PanelRun): RenderChildren {
  const { Text } = table
  return (
    <Text
      key={key}
      color={themeColor(run.color)}
      dimColor={run.dim || run.faint ? true : undefined}
      weight={run.bold ? 'semibold' : undefined}
      mono={run.mono ? true : undefined}
      size={run.chip ? 'caption' : undefined}
      backgroundColor={run.chip ? 'subtle' : undefined}
    >
      {run.text}
    </Text>
  )
}

/** One panel row as the desktop's own elements, keyed `key`; a row's pixel indent becomes cells. */
export function nativeLine(table: Elements, key: string, line: PanelLine): RenderChildren {
  const { Box, Text } = table
  const Svg = 'Svg' in table ? table.Svg : undefined
  const runs = (part: string, list: readonly PanelRun[]) => list.map((run, index) => nativeRun(table, `${key}-${part}-${index}`, run))
  if (line.kind === 'picture') return Svg !== undefined && <Svg key={key} source={line.svg} alt={line.alt ?? ''} />
  if (line.kind === 'chips') {
    return (
      <Box key={key} flexDirection="row" flexWrap="wrap" gap="xs">
        {line.chips.map((chip, index) => nativeRun(table, `${key}-${index}`, { ...chip, chip: true }))}
      </Box>
    )
  }
  if (line.kind === 'badge') {
    return (
      <Box key={key} flexDirection="row" alignItems="center" columnGap="sm">
        {Svg !== undefined && <Svg key={`${key}-svg`} source={line.svg} alt="" />}
        <Box key={`${key}-lines`} flexDirection="column" flexShrink={1}>
          {line.lines.map((one, row) => (
            <Text key={`${key}-${row}`} size={row === 0 ? undefined : 'footnote'} wrap="truncate-end">
              {runs(String(row), one)}
            </Text>
          ))}
        </Box>
      </Box>
    )
  }
  const size = line.small ? 'footnote' : undefined
  const right = line.right ?? []
  return (
    <Box key={key} flexDirection="row" justifyContent="space-between" columnGap="sm" paddingLeft={line.indent === undefined ? undefined : Math.round(line.indent / CELL_PX)}>
      <Box key={`${key}-left`} flexGrow={1} flexShrink={1}>
        <Text size={size} wrap={line.wrap ? 'wrap' : 'truncate-end'}>
          {runs('left', line.left)}
        </Text>
      </Box>
      {right.length > 0 && (
        <Box key={`${key}-right`} flexShrink={0}>
          <Text size={size}>{runs('right', right)}</Text>
        </Box>
      )}
    </Box>
  )
}
