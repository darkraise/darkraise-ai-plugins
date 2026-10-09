// Discord notifications: what each event sends, kept pure so tests reach it.
// register.tsx holds the sender, since only it may reach the host.
export const NOTIFY_KINDS = ['ask', 'question', 'done', 'error', 'blocked', 'budget', 'limit', 'task', 'session', 'agent'] as const
export type NotifyKind = (typeof NOTIFY_KINDS)[number]

/** The kinds that send unless the settings say otherwise. */
export const DEFAULT_NOTIFY_ON: readonly NotifyKind[] = ['ask', 'question', 'done', 'error', 'blocked', 'budget', 'limit']

// The kinds that need the person: they mention them, the rest post silently.
const PINGS: readonly NotifyKind[] = ['ask', 'question', 'error', 'blocked']
const COLORS: Record<NotifyKind, number> = {
  ask: 0xffaf00,
  question: 0xffaf00,
  done: 0x57d787,
  task: 0x57d787,
  error: 0xff5f5f,
  blocked: 0xff5f5f,
  budget: 0x5f87ff,
  limit: 0x5f87ff,
  session: 0x5f87ff,
  agent: 0x5f87ff,
}
// Discord's flag for a message that notifies nobody (`@silent`).
const SUPPRESS_NOTIFICATIONS = 4096
const WEBHOOK = /^https:\/\/(?:(?:ptb|canary)\.)?discord(?:app)?\.com\/api\/webhooks\/(\d+)\/([\w-]+)\/?$/

/** The notifyOn setting, "ask, done" → ['ask', 'done']: known kinds, each once; empty is the default set. */
export function notifyKindsFrom(text: string): NotifyKind[] {
  const names = text
    .split(/[\s,]+/)
    .map(name => name.trim().toLowerCase())
    .filter((name): name is NotifyKind => (NOTIFY_KINDS as readonly string[]).includes(name))
  return names.length === 0 ? [...DEFAULT_NOTIFY_ON] : [...new Set(names)]
}

/** The notifyOn setting after turning one kind on or off; the default set is the empty setting. */
export function notifyKindsToggled(on: readonly NotifyKind[], kind: NotifyKind): string {
  const next = on.includes(kind) ? on.filter(one => one !== kind) : [...on, kind]
  const ordered = NOTIFY_KINDS.filter(one => next.includes(one))
  const isDefault = ordered.length === DEFAULT_NOTIFY_ON.length && ordered.every(one => DEFAULT_NOTIFY_ON.includes(one))
  // Every kind turned off is spelt out, so it does not read back as the default.
  return isDefault ? '' : ordered.length === 0 ? 'none' : ordered.join(',')
}

/** Whether a URL is a Discord webhook, the only kind the cockpit posts to. */
export function isDiscordWebhook(url: string): boolean {
  return WEBHOOK.test(url.trim())
}

/** A webhook as the settings show it: the host, the id's start, the token hidden. */
export function maskWebhook(url: string): string {
  const match = WEBHOOK.exec(url.trim())
  if (!match) return '••••'
  return `discord.com/…/${(match[1] ?? '').slice(0, 4)}…/••••`
}

/** A Discord user id, digits only, as the mention setting takes it; else null. */
export function mentionId(text: string): string | null {
  const id = text.trim().replace(/^<@!?/, '').replace(/>$/, '')
  return /^\d{5,25}$/.test(id) ? id : null
}

const SECRETS: [RegExp, string][] = [
  [/\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})/g, '[token]'],
  [/\b(sk-[A-Za-z0-9_-]{16,}|xox[abposr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})/g, '[token]'],
  [/\bBearer\s+[A-Za-z0-9._~+/=-]{8,}/gi, 'Bearer [token]'],
  [/\b((?:api[_-]?key|token|secret|password|passwd|pwd)\s*[=:]\s*)("[^"]*"|'[^']*'|\S+)/gi, '$1[hidden]'],
  [/https:\/\/(?:(?:ptb|canary)\.)?discord(?:app)?\.com\/api\/webhooks\/\S+/g, '[webhook]'],
]

/** Masks the secrets text may carry before it leaves the machine. */
export function redact(text: string): string {
  return SECRETS.reduce((out, [pattern, mask]) => out.replace(pattern, mask), text)
}

/** Text cut to `max` characters on one line or a few, redacted. */
export function excerpt(text: string, max: number): string {
  const clean = redact(text.replace(/\r/g, '').trim())
  const chars = [...clean]
  return chars.length <= max ? clean : `${chars.slice(0, Math.max(0, max - 1)).join('').trimEnd()}…`
}

/** One event to send: its kind, a title, and what to say under it. */
export type NotifyEvent = {
  kind: NotifyKind
  title: string
  /** The one thing to read; full detail only, unless `isPlain`. */
  detail?: string
  /** Shown whatever the detail setting: carries no session text. */
  isPlain?: boolean
  fields?: { name: string; value: string }[]
}

/** Where a message came from, for its header and footer. */
export type NotifyPlace = {
  host: string | null
  repo: string | null
  branch: string | null
  tmux: string | null
  account: string | null
}

export type NotifyStyle = { mention: string | null; isBrief: boolean; now: number }

/** The webhook body for one event. */
export function discordBody(event: NotifyEvent, place: NotifyPlace, style: NotifyStyle): Record<string, unknown> {
  const isPing = PINGS.includes(event.kind) && style.mention !== null
  const fields = [
    ...(place.branch === null ? [] : [{ name: 'Branch', value: place.branch }]),
    ...(event.fields ?? []),
  ]
    .slice(0, 6)
    .map(field => ({ name: field.name.slice(0, 256), value: (field.value || '—').slice(0, 1024), inline: true }))
  const description = event.detail === undefined || (style.isBrief && event.isPlain !== true) ? undefined : event.detail.slice(0, 1500)
  const footer = ['dr-cockpit', place.account, place.tmux === null ? null : `tmux ${place.tmux}`].filter(Boolean).join(' · ')
  const author = [place.host, place.repo].filter(Boolean).join(' · ')
  const embed: Record<string, unknown> = {
    title: event.title.slice(0, 256),
    color: COLORS[event.kind],
    ...(author === '' ? {} : { author: { name: author.slice(0, 256) } }),
    ...(description === undefined || description === '' ? {} : { description }),
    ...(fields.length === 0 ? {} : { fields }),
    footer: { text: footer.slice(0, 2048) },
    timestamp: new Date(style.now).toISOString(),
  }
  return {
    username: 'Cockpit',
    ...(isPing ? { content: `<@${style.mention}>` } : { flags: SUPPRESS_NOTIFICATIONS }),
    allowed_mentions: { parse: [], users: isPing ? [style.mention] : [] },
    embeds: [embed],
  }
}

/** Whether a kind mentions the person. */
export function isPing(kind: NotifyKind): boolean {
  return PINGS.includes(kind)
}

/** What a send came to: the message id when Discord gave one, else why not. */
export type SendResult = { isSent: true; id: string | null } | { isSent: false; reason: string }
