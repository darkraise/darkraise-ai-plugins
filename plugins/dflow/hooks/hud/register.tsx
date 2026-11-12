import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Hud, HudContext, Mode } from '../../types'
import {
  RESET_INSTRUCTIONS,
  bandText,
  isFreshReset,
  nextMode,
  paneRows,
} from './view.mjs'

const PANE = 'dflow-hud'
const COMMAND = 'dflow:hud'
const POLL_MS = 2000
const REWRITE_MS = 5 * 60 * 1000

// Bump the tag when Hud's fields change: it declines what an earlier version
// stored, which outlives a reload.
const hudAtom = atom({ plugin: 'dflow', key: 'hud' } as const, null as Hud | null, {
  shape: 'hud-1',
})
const modeAtom = atom({ plugin: 'dflow', key: 'mode' } as const, 'band' as Mode)
const contextAtom = atom(
  { plugin: 'dflow', key: 'context' } as const,
  null as HudContext | null,
)

// `root` is '' until looked up and null once known not to be a repository,
// so a session started outside one does not run git on every poll.
let root: string | null = ''
let lastText = ''
let lastTokens = -1
let lastWrite = 0
let sessionId = ''
let timer: { cancel: () => void } | null = null

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
  }

  if (root === '') {
    root = await locate($)
  }

  if (!root || !(await $.fs.exists(`${root}/.dflow`))) {
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
      `${root}/.dflow/context.json`,
      JSON.stringify({
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

  if (!isFreshReset(flag, await $.clock.now())) {
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
    await $.ui.open({ id: PANE, title: 'dflow' })
  } else {
    await $.ui.close({ id: PANE })
  }

  $.ui.invalidate('ui.render')
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await refresh($)

    if (timer === null) {
      timer = $.clock.every(POLL_MS, () => {
        void refresh($)
      })
    }

    if ((await read($, modeAtom)) === 'pane') {
      void $.ui.open({ id: PANE, title: 'dflow' })
    }

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
    const mode = nextMode(await read($, modeAtom), (e.args ?? '').trim())

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
    const { Box, Text } = $.ui.resolve(e)
    const hud = await read($, hudAtom)

    if (hud === null) {
      return (
        <Box flexDirection="column">
          <Text dimColor>dflow has no state in this repository yet.</Text>
          <Text dimColor>Run /dflow:init, then /dflow:plan.</Text>
        </Box>
      )
    }

    const rows = paneRows(hud, await read($, contextAtom), e.props.bodyColumns)

    return (
      <Box flexDirection="column">
        {rows.map(([label, text, isDim]: [string, string, boolean]) => (
          <Text dimColor={isDim}>
            {label ? `${label.padEnd(8)} ` : ''}
            {text}
          </Text>
        ))}
      </Box>
    )
  })
}
