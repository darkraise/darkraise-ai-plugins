// The desktop's drawings: meters, the context trend, the category stack, the
// run's tasks and the account's badge, as SVG documents for its Svg element.
// The desktop draws them as images, so they carry their own colors: mid tones
// and a translucent track that read on its light and dark themes alike.

const PALETTE: Record<string, string> = {
  cyan: '#1fa8c9',
  blue: '#4f7cff',
  yellow: '#d4a017',
  magenta: '#c056d6',
  green: '#3fb36b',
  red: '#e5534b',
  gray: '#8a8a99',
  white: '#8a8a99',
  success: '#3fb36b',
  warning: '#d4a017',
  error: '#e5534b',
}
const TRACK = 'rgba(128,128,140,0.24)'
const MARK = '#8a8a99'

/** A tree's color (a name, a theme key or hex) as one an SVG can paint. */
export function paint(color: string | undefined, fallback = MARK): string {
  if (color !== undefined && /^#[0-9a-f]{3,8}$/i.test(color)) return color
  return (color === undefined ? undefined : PALETTE[color]) ?? fallback
}

/** The drawing's width in CSS pixels for a pane `columns` cells wide. */
export function svgWidth(columns: number): number {
  return Math.max(120, Math.min(640, Math.round(columns * 7.5)))
}

const n = (value: number) => String(Math.round(value * 10) / 10)
const clamp = (share: number) => Math.min(Math.max(Number.isFinite(share) ? share : 0, 0), 1)
const svg = (width: number, height: number, body: string) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${body}</svg>`

export type SvgMark = { at: number; color?: string; isDashed?: boolean }

/** A rounded meter filled to `share`, with upright marks across it. */
export function meterSvg(share: number, width: number, color: string, marks: readonly SvgMark[] = [], height = 12): string {
  const bar = Math.max(4, height - 4)
  const y = (height - bar) / 2
  const r = bar / 2
  const filled = clamp(share) * width
  const fill = filled <= 0 ? '' : `<rect x="0" y="${n(y)}" width="${n(Math.max(filled, bar))}" height="${n(bar)}" rx="${n(r)}" fill="${paint(color)}"/>`
  const lines = marks
    .filter(mark => Number.isFinite(mark.at))
    .map(mark => {
      const x = Math.min(Math.max(clamp(mark.at) * width, 1), width - 1)
      const dash = mark.isDashed ? ' stroke-dasharray="2 2"' : ''
      return `<line x1="${n(x)}" y1="0" x2="${n(x)}" y2="${height}" stroke="${paint(mark.color)}" stroke-width="2"${dash}/>`
    })
    .join('')
  return svg(width, height, `<rect x="0" y="${n(y)}" width="${width}" height="${n(bar)}" rx="${n(r)}" fill="${TRACK}"/>${fill}${lines}`)
}

/** The readings as a line over a soft fill, the latest one marked. */
export function trendSvg(values: readonly number[], width: number, color: string, height = 40): string {
  const shown = values.filter(Number.isFinite)
  if (shown.length < 2) return svg(width, height, '')
  const low = Math.min(...shown)
  const high = Math.max(...shown)
  const span = high - low || 1
  const pad = 4
  const step = (width - 2 * pad) / (shown.length - 1)
  const points = shown.map((value, index) => [pad + index * step, height - pad - ((value - low) / span) * (height - 2 * pad)] as const)
  const line = points.map(([x, y], index) => `${index === 0 ? 'M' : 'L'}${n(x)} ${n(y)}`).join(' ')
  const [lastX, lastY] = points[points.length - 1] ?? [0, 0]
  const hue = paint(color)
  return svg(
    width,
    height,
    `<line x1="0" y1="${height - pad}" x2="${width}" y2="${height - pad}" stroke="${TRACK}"/>` +
      `<path d="${line} L${n(lastX)} ${height - pad} L${pad} ${height - pad} Z" fill="${hue}" fill-opacity="0.18"/>` +
      `<path d="${line}" fill="none" stroke="${hue}" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/>` +
      `<circle cx="${n(lastX)}" cy="${n(lastY)}" r="3" fill="${hue}"/>`,
  )
}

/** One bar split by the values' shares, each part in its color. */
export function stackSvg(values: readonly number[], colors: readonly string[], width: number, height = 10): string {
  const total = values.reduce((sum, value) => sum + Math.max(0, value), 0)
  let x = 0
  const parts = values
    .map((value, index) => {
      const part = total <= 0 ? 0 : (Math.max(0, value) / total) * width
      const rect = part <= 0 ? '' : `<rect x="${n(x)}" y="0" width="${n(part)}" height="${height}" fill="${paint(colors[index % colors.length])}"/>`
      x += part
      return rect
    })
    .join('')
  const r = height / 2
  return svg(
    width,
    height,
    `<defs><clipPath id="c"><rect x="0" y="0" width="${width}" height="${height}" rx="${n(r)}"/></clipPath></defs>` +
      `<rect x="0" y="0" width="${width}" height="${height}" rx="${n(r)}" fill="${TRACK}"/><g clip-path="url(#c)">${parts}</g>`,
  )
}

export type Segment = 'done' | 'active' | 'blocked' | 'todo'
const SEGMENT_COLORS: Record<Segment, string> = { done: PALETTE.green, active: PALETTE.blue, blocked: PALETTE.red, todo: TRACK }

/** One segment per task, colored by where it stands. */
export function segmentsSvg(states: readonly Segment[], width: number, height = 8): string {
  if (states.length === 0) return svg(width, height, '')
  const gap = states.length > 24 ? 1 : 4
  const each = Math.max(1, (width - gap * (states.length - 1)) / states.length)
  const body = states
    .map((state, index) => `<rect x="${n(index * (each + gap))}" y="0" width="${n(each)}" height="${height}" rx="${n(Math.min(3, each / 2))}" fill="${SEGMENT_COLORS[state]}"/>`)
    .join('')
  return svg(width, height, body)
}

/** A round badge in the account's color with its first letter. */
export function avatarSvg(name: string, color: string | undefined, size = 30): string {
  const letter = ([...name.trim()][0] ?? '?').toUpperCase()
  const text = letter.replace(/[&<>"']/g, ch => `&#${ch.charCodeAt(0)};`)
  const r = size / 2
  return svg(
    size,
    size,
    `<circle cx="${r}" cy="${r}" r="${r}" fill="${paint(color, PALETTE.blue)}"/>` +
      `<text x="${r}" y="${r}" dy="0.35em" text-anchor="middle" font-family="system-ui, sans-serif" font-size="${n(size * 0.45)}" font-weight="600" fill="#ffffff">${text}</text>`,
  )
}
