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

const MONO = 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace'
const SANS = "system-ui, -apple-system, 'Segoe UI', sans-serif"

const n = (value: number) => String(Math.round(value * 10) / 10)
const esc = (text: string) => text.replace(/[&<>"']/g, ch => `&#${ch.charCodeAt(0)};`)
// A label in the drawings' small monospace type, about 6.3 pixels a character.
const LABEL_EM = 6.3
const label = (x: number, y: number, text: string, anchor: 'start' | 'middle' | 'end', color = MARK) =>
  `<text x="${n(x)}" y="${y}" text-anchor="${anchor}" font-family="${MONO}" font-size="10.5" fill="${color}">${esc(text)}</text>`
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

/** A headline figure, large in its color, with its words beside it. */
export function statSvg(value: string, words: string, width: number, color: string): string {
  // Figures at 24px run about 14px wide, a percent sign 21px.
  const after = 8 + [...value].reduce((sum, ch) => sum + (ch === '%' ? 21 : ch === '.' || ch === ',' ? 7 : 14.5), 0)
  return svg(
    width,
    30,
    `<text x="0" y="23" font-family="${SANS}" font-size="24" font-weight="600" fill="${paint(color)}">${esc(value)}</text>` +
      `<text x="${n(after)}" y="23" font-family="${SANS}" font-size="13" fill="${MARK}">${esc(words)}</text>`,
  )
}

export type SvgLabel = { at: number; text: string; color?: string }

/**
 * A meter with its marks named beneath it: each label sits under its point,
 * the first and last against the ends, and one that would run into a label
 * already placed is left out.
 */
export function labelledMeterSvg(share: number, width: number, color: string, marks: readonly SvgMark[], labels: readonly SvgLabel[]): string {
  const bar = meterSvg(share, width, color, marks, 16)
  const inner = bar.slice(bar.indexOf('>') + 1, bar.lastIndexOf('</svg>'))
  const taken: [number, number][] = []
  const texts = labels
    .map(one => {
      const size = one.text.length * LABEL_EM
      const x = clamp(one.at) * width
      const anchor = x - size / 2 <= 0 ? 'start' : x + size / 2 >= width ? 'end' : 'middle'
      const from = anchor === 'start' ? 0 : anchor === 'end' ? width - size : x - size / 2
      if (taken.some(([a, b]) => from < b + 8 && from + size > a - 8)) return ''
      taken.push([from, from + size])
      return label(anchor === 'start' ? 0 : anchor === 'end' ? width : x, 32, one.text, anchor, one.color === undefined ? MARK : paint(one.color))
    })
    .join('')
  return svg(width, 38, inner + texts)
}

/** The readings as a line over a soft fill, the latest one marked, with the change and the span at its right. */
export function trendSvg(values: readonly number[], width: number, color: string, height = 40, labels: { top?: string; bottom?: string } = {}): string {
  const shown = values.filter(Number.isFinite)
  if (shown.length < 2) return svg(width, height, '')
  const low = Math.min(...shown)
  const high = Math.max(...shown)
  const span = high - low || 1
  const pad = 4
  // The change sits above the line, clear of its latest point.
  const top = labels.top === undefined ? pad : 16
  const step = (width - 2 * pad) / (shown.length - 1)
  const points = shown.map((value, index) => [pad + index * step, height - pad - ((value - low) / span) * (height - pad - top)] as const)
  const line = points.map(([x, y], index) => `${index === 0 ? 'M' : 'L'}${n(x)} ${n(y)}`).join(' ')
  const [lastX, lastY] = points[points.length - 1] ?? [0, 0]
  const hue = paint(color)
  return svg(
    width,
    height,
    `<line x1="0" y1="${height - pad}" x2="${width}" y2="${height - pad}" stroke="${TRACK}"/>` +
      `<path d="${line} L${n(lastX)} ${height - pad} L${pad} ${height - pad} Z" fill="${hue}" fill-opacity="0.18"/>` +
      `<path d="${line}" fill="none" stroke="${hue}" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/>` +
      `<circle cx="${n(lastX)}" cy="${n(lastY)}" r="3" fill="${hue}"/>` +
      (labels.top === undefined ? '' : label(width, 11, labels.top, 'end', hue)) +
      (labels.bottom === undefined ? '' : label(width, height - pad - 4, labels.bottom, 'end')),
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

/**
 * A seat's line: its name and token counts above a bar of its input against
 * the busiest seat's, the share served from the prompt cache shaded.
 */
export function seatSvg(name: string, counts: string, share: number, cached: number, width: number, color: string): string {
  const hue = paint(color)
  const filled = clamp(share) * width
  const warm = filled * clamp(cached)
  return svg(
    width,
    28,
    label(0, 10, name, 'start') +
      label(width, 10, counts, 'end') +
      `<rect x="0" y="16" width="${width}" height="8" rx="4" fill="${TRACK}"/>` +
      (filled <= 0
        ? ''
        : `<defs><clipPath id="s"><rect x="0" y="16" width="${n(Math.max(filled, 8))}" height="8" rx="4"/></clipPath></defs>` +
          `<g clip-path="url(#s)"><rect x="0" y="16" width="${n(warm)}" height="8" fill="${hue}" fill-opacity="0.45"/>` +
          `<rect x="${n(warm)}" y="16" width="${n(Math.max(filled, 8) - warm)}" height="8" fill="${hue}"/></g>`),
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
  const text = esc(([...name.trim()][0] ?? '?').toUpperCase())
  const r = size / 2
  return svg(
    size,
    size,
    `<circle cx="${r}" cy="${r}" r="${r}" fill="${paint(color, PALETTE.blue)}"/>` +
      `<text x="${r}" y="${r}" dy="0.35em" text-anchor="middle" font-family="system-ui, sans-serif" font-size="${n(size * 0.45)}" font-weight="600" fill="#ffffff">${text}</text>`,
  )
}
