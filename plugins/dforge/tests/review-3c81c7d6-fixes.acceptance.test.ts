import { describe, expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'


// Acceptance tests for docs/dforge/specs/2026-11-27-review-3c81c7d6-fixes-design.md,
// statement A6: the cockpit attribution guard. The tests reach the plugin only
// through the engine's events: a Bash tool call is made and the guard's answer
// (a deny text or none) is read. The engine below answers just what the guard
// needs: the session's directory, the files it may read, and the account.

const TRAILER = ['Co', 'authored-by:'].join('-')
const AI_TRAILER = `${TRAILER} Claude <noreply@anthropic.com>`
const AI_SESSION = ['Claude', 'Session:'].join('-') + ' https://claude.ai/code/session_01ABC'
const AI_GENERATED = `${['Generated', 'with'].join(' ')} Claude Code`
const REFUSAL = /keeps AI attribution out of git/

const CWD = '/home/me/code/shop/web'
const HOME_FILES = '/home/me'

type Files = Record<string, { text: string; kind?: 'file' | 'dir' | 'other' }>

function engine(on: On, files: Files) {
  mock.env(on, { HOME: HOME_FILES })
  mock.clock(on, { now: 1_000_000 })
  on('session.start', (_$, e) => e as never)
  on('session.usage', () => ({
    value: { startedAt: 0, context: { tokens: 284_000, window: 650_000 }, rateLimits: [], cost: { usd: 1.5 } },
  }))
  on('settings.read', () => ({ value: { effortLevel: 'xhigh' } }))
  on('tool.call', () => ({ result: 'ok', text: 'ok' }))
  on('fs.read', (_$, e) => {
    const file = files[e.path]
    if (file !== undefined) return { value: file.text }
    if (e.path === '/home/me/.claude.json') {
      return { value: JSON.stringify({ oauthAccount: { emailAddress: 'me@example.com', displayName: 'Me', organizationName: 'Acme', organizationRole: 'admin', billingType: 'stripe_subscription' } }) }
    }
    throw new Error('ENOENT')
  })
  on('fs.stat', (_$, e) => {
    const file = files[e.path]
    if (file === undefined) throw new Error('ENOENT')
    return { value: { kind: file.kind ?? 'file', size: file.text.length, mtimeMs: 0, isLink: false } }
  })
  on('fs.exists', (_$, e) => ({ value: e.path in files }))
  on('session.cwd', () => ({ value: CWD }))
  on('session.repo', () => ({ value: { root: '/home/me/code/shop', remote: null, internal: false, name: null } }))
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
}

type Form = { name: string; command: (message: string) => string; files?: (message: string) => Files }

const msgAt = (dir: string, message: string): Files => ({ [`${dir}/msg.txt`]: { text: `fix: tidy\n\n${message}\n` } })

// Each form carries the message text it is given, so one list drives both
// the refusing and the allowing run.
const FORMS: Form[] = [
  { name: 'relative -F file after cd (absolute dir)', command: () => `cd ${CWD}/.worktrees/x && git commit -F msg.txt`, files: m => msgAt(`${CWD}/.worktrees/x`, m) },
  { name: 'relative -F file after cd (relative dir)', command: () => 'cd .worktrees/x && git commit -F msg.txt', files: m => msgAt(`${CWD}/.worktrees/x`, m) },
  { name: 'relative -F file after git -C', command: () => 'git -C .worktrees/x commit -F msg.txt', files: m => msgAt(`${CWD}/.worktrees/x`, m) },
  { name: 'relative -F file in the session directory', command: () => 'git commit -F msg.txt', files: m => msgAt(CWD, m) },
  { name: '-m "$(cat file)" with a relative file', command: () => 'git commit -m "$(cat msg.txt)"', files: m => msgAt(CWD, m) },
  { name: '-m "$(cat file)" with an absolute file', command: () => 'git commit -m "$(cat /tmp/msg.txt)"', files: m => msgAt('/tmp', m) },
  { name: 'git merge -m', command: m => `git merge --no-ff topic -m "Merge topic\n\n${m}"` },
  { name: 'git merge -m with a plain message', command: m => `git merge topic -m "${m}"` },
  { name: 'gh pr merge --body', command: m => `gh pr merge 12 --squash --body "fix\n\n${m}"` },
  { name: 'gh with a short flag before pr', command: m => `gh -R o/r pr create --title x --body "fix\n\n${m}"` },
  { name: 'gh with a long flag before pr', command: m => `gh --repo o/r pr merge 12 --body "fix\n\n${m}"` },
  { name: 'backslash-newline between git and commit', command: m => `git \\\n  commit -m 'fix' -m '${m}'` },
  { name: 'attached -am"..."', command: m => `git commit -am"fix\n\n${m}"` },
  { name: '-F after a quoted ;', command: () => "git commit -m 'fix; tidy' -F msg.txt", files: m => msgAt(CWD, m) },
  { name: '-F after a double-quoted ; in an earlier command', command: () => 'echo "a;b" && git commit -F msg.txt', files: m => msgAt(CWD, m) },
]

const CLEAN = 'a plain message with no attribution'

async function run(on: On, $: Parameters<Parameters<typeof test>[1]>[0], form: Form, message: string) {
  engine(on, form.files?.(message) ?? {})
  await $.session.start({ cwd: CWD, surface: 'terminal', isInteractive: true } as never)
  return $.tool.call({ tool: 'Bash', command: form.command(message) })
}

describe('review-3c81c7d6-fixes: cockpit attribution guard', () => {
  for (const form of FORMS) {
    test(`A6: refuses ${form.name} when the message carries an attribution line`, async ($, on) => {
      const ran = await run(on, $, form, AI_TRAILER)
      expect(ran.deny).toMatch(REFUSAL)
    })

    test(`A6: allows ${form.name} when the message has no attribution line`, async ($, on) => {
      const ran = await run(on, $, form, CLEAN)
      expect(ran.deny).toBeUndefined()
    })
  }

  // The other attribution line shapes the guard names, through one file form
  // and one inline form.
  for (const line of [AI_SESSION, AI_GENERATED]) {
    for (const form of [FORMS[3]!, FORMS[6]!]) {
      test(`A6: refuses ${form.name} carrying "${line.slice(0, 18)}..."`, async ($, on) => {
        const ran = await run(on, $, form, line)
        expect(ran.deny).toMatch(REFUSAL)
      })
    }
  }
})
