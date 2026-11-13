import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Hud, HudContext, Mode } from '../../types'
import {
  RESET_INSTRUCTIONS,
  bandText,
  boardCard,
  checksCard,
  collapsedFrom,
  contextFile,
  isResetFor,
  nextMode,
  nextRow,
  nowRow,
  planCard,
  workersCard,
} from './view.mjs'
import { isAtLeast, runsCut } from './meter.mjs'

type Run = { text: string; color?: string; bold?: boolean; dim?: boolean; underline?: boolean }
type Card = { key: string; title: string; color: string; headline: Run[]; rows: Run[][] }

const PANE = 'dflow-hud'
const COMMAND = 'dflow:hud'
const POLL_MS = 2000
const REWRITE_MS = 5 * 60 * 1000
const PANE_COLUMNS = 56
const BUTTON_MAIN = 'permission'
const BUTTON_REST = 'inactive'
const UNDERLINE_SINCE = '2.1.295'

// Bump the tag when Hud's fields change: it declines what an earlier version
// stored, which outlives a reload.
const hudAtom = atom({ plugin: 'dflow', key: 'hud' } as const, null as Hud | null, {
  shape: 'hud-2',
})
const modeAtom = atom({ plugin: 'dflow', key: 'mode' } as const, 'band' as Mode)
const contextAtom = atom(
  { plugin: 'dflow', key: 'context' } as const,
  null as HudContext | null,
)
const collapsedAtom = atom({ plugin: 'dflow', key: 'collapsed' } as any, [] as string[])

// `root` is '' until looked up and null once known not to be a repository,
// so a session started outside one does not run git on every poll.
let root: string | null = ''
let lastText = ''
let lastTokens = -1
let lastWrite = 0
let sessionId = ''
let timer: { cancel: () => void } | null = null
// Read on a session switch, since a render hook makes no engine call.
let canUnderline = false

type ButtonLook = { hotkey?: string; isMain?: boolean; isOff?: boolean; isCompact?: boolean }

// A button in a rounded box: gray at rest, the accent on the main one, dim
// when it reads as off. The hotkey's letter is underlined in the label; a
// hidden twin holds the hotkey, since a Button with one draws "m: " before
// its label. Claude Code before 2.1.295 draws that prefix instead.
function drawButton(table: any, key: string, label: string, onPress: () => unknown, look: ButtonLook = {}) {
  const { Box, Button, Text } = table
  const at = canUnderline && look.hotkey !== undefined ? label.toLowerCase().indexOf(look.hotkey) : -1
  const button =
    at < 0 ? (
      <Button key={key} label={label} hotkey={canUnderline ? undefined : look.hotkey} plain dimColor={look.isOff} hover={{ bold: true }} onPress={onPress} />
    ) : (
      <Button key={key} label={label} plain dimColor={look.isOff} hover={{ bold: true }} onPress={onPress}>
        {label.slice(0, at)}
        <Text underline>{label.slice(at, at + 1)}</Text>
        {label.slice(at + 1)}
      </Button>
    )
  const twin = at >= 0 && (
    <Box key={`${key}-hotkey-box`} display="none">
      <Button key={`${key}-hotkey`} label={label} hotkey={look.hotkey} plain onPress={onPress} />
    </Box>
  )

  if (look.isCompact) {
    return (
      <Box key={`${key}-box`} flexDirection="row">
        {button}
        {twin}
      </Box>
    )
  }

  return (
    <Box key={`${key}-box`} borderStyle="round" borderColor={look.isMain ? BUTTON_MAIN : BUTTON_REST} paddingX={1}>
      {button}
      {twin}
    </Box>
  )
}

function drawRuns(table: any, key: string, runs: Run[]) {
  const { Text } = table

  return runs.map((run, index) => (
    <Text key={`${key}-${index}`} color={run.color} bold={run.bold} dimColor={run.dim} underline={run.underline}>
      {run.text}
    </Text>
  ))
}

// A rounded frame in the card's color: its title button and headline on the
// first line, its rows below, each cut to the frame. Keys sit on wrapper
// Boxes: the engine keeps no key on a Text. The title collapses it
// to that line; `extra` (its buttons) shows either way.
function drawCard(table: any, card: Card, isCollapsed: boolean, onToggle: () => unknown, extra: unknown[] = []) {
  const { Box, Button, Text } = table
  const inner = Math.max(10, table.columns - 4)
  const label = `${isCollapsed ? '▸' : '▾'} ${card.title}`

  return (
    <Box key={card.key} flexDirection="column" borderStyle="round" borderColor={card.color} paddingX={1}>
      <Box key={`${card.key}-head`} flexDirection="row" justifyContent="space-between">
        {canUnderline ? (
          <Button key={`${card.key}-title`} label={label} plain hover={{ bold: true }} onPress={onToggle}>
            <Text color={card.color} bold>
              {label}
            </Text>
          </Button>
        ) : (
          <Button key={`${card.key}-title`} label={label} plain hover={{ bold: true }} onPress={onToggle} />
        )}
        <Box key={`${card.key}-headline`}>
          <Text wrap="truncate-end">{drawRuns(table, `${card.key}-headline`, card.headline)}</Text>
        </Box>
      </Box>
      {!isCollapsed &&
        card.rows.map((row, index) => (
          <Box key={`${card.key}-row-${index}`}>
            <Text wrap="truncate-end">{drawRuns(table, `${card.key}-row-${index}`, runsCut(row, inner))}</Text>
          </Box>
        ))}
      {extra}
    </Box>
  )
}

async function toggleCollapsed($: any, key: string): Promise<void> {
  const now = await read($, collapsedAtom)
  const next = now.includes(key) ? now.filter(one => one !== key) : [...now, key]
  await update($, collapsedAtom, () => next)
  await $.store.set('collapsed', next)
  $.ui.invalidate('ui.render')
}

async function readVersion($: any): Promise<void> {
  try {
    const { base } = await $.session.version()
    canUnderline = isAtLeast(base, UNDERLINE_SINCE)
  } catch {
    canUnderline = false
  }
}

async function isPaneUp($: any): Promise<boolean> {
  return (await $.ui.panes()).some((pane: any) => pane.id === PANE && pane.isPlaced)
}

async function openPane($: any): Promise<void> {
  await $.ui.open({ id: PANE, title: 'dflow', columns: PANE_COLUMNS })
}

async function locate($: any): Promise<string | null> {
  const found = await $.process.run(['git', 'rev-parse', '--show-toplevel'], {
    timeoutMs: 5000,
  })

  return found.exitCode === 0 ? found.stdout.trim() : null
}

async function loadMode($: any): Promise<void> {
  const stored = await $.store.get('mode')

  if (stored === 'band' || stored === 'pane' || stored === 'off') {
    await update($, modeAtom, () => stored)
  }

  const collapsed = collapsedFrom(await $.store.get('collapsed'))
  await update($, collapsedAtom, () => collapsed)
}

// The HUD is a view: a failure to read or draw it must never surface.
async function refresh($: any): Promise<void> {
  try {
    await readState($)
  } catch {
    lastText = ''
  }
}

// Reads what the CLI wrote and tells the CLI the live context size. A session
// switch (/clear, /resume) empties the mod's state without a session.start,
// so everything is re-read when the session id changes.
async function readState($: any): Promise<void> {
  const id = await $.session.id()

  if (id !== sessionId) {
    sessionId = id
    lastText = ''
    lastTokens = -1
    root = ''
    await loadMode($)
    await readVersion($)

    if ((await read($, modeAtom)) === 'pane' && !(await isPaneUp($))) {
      await openPane($)
    }
  }

  if (root === '') {
    root = await locate($)
  }

  // A Hud stored earlier outlives a reload: outside a dflow checkout it must
  // not draw.
  if (!root || !(await $.fs.exists(`${root}/.dflow`))) {
    if ((await read($, hudAtom)) !== null) {
      await update($, hudAtom, () => null)
      lastText = ''
      $.ui.invalidate('ui.render')
    }

    return
  }

  const { context } = await $.session.usage()
  await update($, contextAtom, () => context)
  const now = await $.clock.now()

  // Written when the figure changes, and every few minutes so that the CLI
  // still finds it fresh; a write every poll would wake file watchers.
  if (
    typeof context.tokens === 'number' &&
    (context.tokens !== lastTokens || now - lastWrite > REWRITE_MS)
  ) {
    lastTokens = context.tokens
    lastWrite = now
    await $.fs.write(
      `${root}/.dflow/${contextFile(sessionId)}`,
      JSON.stringify({
        session: sessionId,
        tokens: context.tokens,
        window: context.window,
        at: new Date(now).toISOString(),
      }),
    )
  }

  if (!(await $.fs.exists(`${root}/.dflow/hud.json`))) {
    return
  }

  const text = await $.fs.read(`${root}/.dflow/hud.json`)

  if (text === lastText) {
    return
  }

  lastText = text

  try {
    const hud = JSON.parse(text) as Hud
    await update($, hudAtom, () => hud)
    $.ui.invalidate('ui.render')
  } catch {
    // A file caught mid-write is read again on the next poll.
    lastText = ''
  }
}

// `dflow done` leaves a flag when the context has passed the threshold and
// the session has ended its turn at a task boundary. Compacting there loses
// nothing, since all task state is on disk.
async function resetIfAsked($: any): Promise<void> {
  const flagPath = `${root}/.dflow/reset.json`

  if (!root || !(await $.fs.exists(flagPath))) {
    return
  }

  let flag: { at?: string } | null = null

  try {
    flag = JSON.parse(await $.fs.read(flagPath))
  } catch {
    flag = null
  }

  if (!isResetFor(flag, await $.clock.now(), await $.session.id())) {
    return
  }

  await $.fs.write(flagPath, '{}')
  $.clock.after(300, () => {
    void compactAndResume($)
  })
}

async function compactAndResume($: any): Promise<void> {
  try {
    await $.session.compact({ instructions: RESET_INSTRUCTIONS })
  } catch {
    // The turn had not fully ended; one more try once it has.
    await $.clock.sleep(2000)

    try {
      await $.session.compact({ instructions: RESET_INSTRUCTIONS })
    } catch {
      $.ui.toast('dflow: could not compact; run /compact, then /dflow:build')

      return
    }
  }

  await $.command.run({ command: 'dflow:build' })
}

async function setMode($: any, mode: Mode): Promise<void> {
  await update($, modeAtom, () => mode)
  await $.store.set('mode', mode)

  if (mode === 'pane') {
    await openPane($)
  } else {
    await $.ui.close({ id: PANE })
  }

  $.ui.invalidate('ui.render')
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    sessionId = ''
    await refresh($)

    timer?.cancel()
    timer = $.clock.every(POLL_MS, () => {
      void refresh($)
    })

    return started
  })

  on('turn.complete', async ($, e, next) => {
    const completed = await next(e)

    // A subagent's turn ends here too; only the main loop's end is a boundary.
    if (e.agentId === undefined) {
      await refresh($)
      await resetIfAsked($).catch(() => undefined)
    }

    return completed
  })

  // `/dflow:hud` is the plugin's `hud` skill, since a mod's own command name
  // cannot hold a colon. Answering it here spends no model turn; if this hook
  // fails, the skill runs and prints the status as text.
  on('command.run', { command: COMMAND }, async ($, e) => {
    const args = (e.args ?? '').trim()
    const current = await read($, modeAtom)

    // A pane the person closed is still the chosen mode: bring it back.
    if (args === '' && current === 'pane' && !(await isPaneUp($))) {
      await setMode($, 'pane')

      return { text: 'dflow HUD: pane' }
    }

    const mode = nextMode(current, args)

    if (mode === null) {
      return { text: 'Usage: /dflow:hud [band|pane|off]' }
    }

    await setMode($, mode as Mode)

    return { text: `dflow HUD: ${mode}` }
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const hud = await read($, hudAtom)

    if (e.props.hasSurvey || !hud?.plan || (await read($, modeAtom)) !== 'band') {
      return next(e)
    }

    const { Box, Text } = $.ui.resolve(e)

    return (
      <Box>
        <Text dimColor>
          {bandText(hud, await read($, contextAtom), e.props.bodyColumns)}
        </Text>
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const columns = e.props.bodyColumns
    const table = { ...$.ui.resolve(e), columns }
    const { Box, Text } = table
    const hud = await read($, hudAtom)

    if (hud === null) {
      return (
        <Box flexDirection="column">
          <Text dimColor>dflow has no state in this repository yet.</Text>
          <Text dimColor>Run /dflow:init, then /dflow:plan.</Text>
        </Box>
      )
    }

    const collapsed = await read($, collapsedAtom)
    const cards = [planCard(hud, Math.max(10, columns - 4)), checksCard(hud), boardCard(hud), workersCard(hud)].filter(
      (card): card is Card => card !== null,
    )

    return (
      <Box flexDirection="column">
        <Box key="now">
          <Text wrap="truncate-end">{drawRuns(table, 'now', runsCut(nowRow(hud), columns))}</Text>
        </Box>
        <Box key="controls" flexDirection="row" columnGap={1}>
          {drawButton(table, 'pane-minimize', '▁ Minimize', () => setMode($, 'band'), { hotkey: 'm' })}
        </Box>
        {cards.map(card => drawCard(table, card, collapsed.includes(card.key), () => toggleCollapsed($, card.key)))}
        <Box key="next">
          <Text wrap="truncate-end">{drawRuns(table, 'next', runsCut(nextRow(hud), columns))}</Text>
        </Box>
      </Box>
    )
  })
}
