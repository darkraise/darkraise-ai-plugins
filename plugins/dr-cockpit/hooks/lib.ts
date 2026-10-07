// Pure helpers, kept apart from the hooks so tests can reach them directly.

/** The band shows from this share of the budget. */
export const WARN_AT = 0.8

/**
 * The handoff budget: the configured tokens, else DR_SUPERPOWERS_BUDGET, else
 * dr-superpowers' own rule (reference/session-budget.md): 93% of the window
 * minus 140,000, floored at half the window for small windows.
 */
export function budgetFor(configured: number, env: string | undefined, window: number): number {
  if (configured > 0) return Math.round(configured)
  const pinned = Number(env)
  if (Number.isFinite(pinned) && pinned > 0) return Math.round(pinned)
  return Math.max(Math.floor(window * 0.93) - 140_000, Math.floor(window / 2))
}

export type Level = 'quiet' | 'warn' | 'handoff'

export function levelOf(tokens: number, limit: number): Level {
  if (tokens >= limit) return 'handoff'
  return tokens >= limit * WARN_AT ? 'warn' : 'quiet'
}

/** 465000 → "465k"; 1234567 → "1.2M". */
export function kTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  return `${Math.round(n / 1000)}k`
}

const ATTRIBUTION = [
  /co-authored-by:[^\n]*(claude|anthropic|codex|openai|copilot)/i,
  /claude-session:/i,
  /generated with \[?claude code/i,
  /claude\.ai\/code\/session_/i,
]

/** The first AI attribution line in a text, if any. */
export function attributionIn(text: string): string | undefined {
  for (const pattern of ATTRIBUTION) {
    const match = pattern.exec(text)
    if (match) return text.slice(match.index).split('\n')[0]?.trim()
  }
  return undefined
}

/** Whether a shell command writes a commit or a pull request. */
export function writesGitText(command: string): boolean {
  return /\bgit\b[^\n|;&]*\bcommit\b/.test(command) || /\bgh\s+pr\s+(create|edit)\b/.test(command)
}

/** Whether a tool by this name writes a pull request or commits files. */
export function isGitWriteTool(tool: string): boolean {
  return /pull_request|create_or_update_file|push_files/.test(tool) && !/read|list|search|get_/.test(tool)
}

/** Whether a subagent type or skill name belongs to dr-superpowers. */
export function isSuperpowers(name: string): boolean {
  return name.startsWith('dr-superpowers:')
}
