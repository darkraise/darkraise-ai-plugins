// The desktop's drawings: meters, the context trend, the category stack, the
// run's tasks and the account's badge, as SVG documents for its Svg element.
// The desktop draws them as images, so they carry their own colors: mid tones
// and a translucent track that read on its light and dark themes alike.

const PALETTE = {
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
const PALETTE_BY_NAME: Record<string, string> = PALETTE
const TRACK = 'rgba(128,128,140,0.24)'
const MARK = '#8a8a99'

/** A tree's color (a name, a theme key or hex) as one an SVG can paint. */
export function paint(color: string | undefined, fallback = MARK): string {
  if (color !== undefined && /^#[0-9a-f]{3,8}$/i.test(color)) return color
  return (color === undefined ? undefined : PALETTE_BY_NAME[color]) ?? fallback
}

/** CSS pixels one terminal column spans in the desktop's text. */
export const CELL_PX = 7.5

/** The drawing's width in CSS pixels for a pane `columns` cells wide. */
export function svgWidth(columns: number): number {
  return Math.max(120, Math.min(640, Math.round(columns * CELL_PX)))
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
      const at = anchor === 'start' ? 0 : anchor === 'end' ? width - size : x - size / 2
      const clashes = (from: number) => from < 0 || from + size > width || taken.some(([a, b]) => from < b + 8 && from + size > a - 8)
      // A label that would run into one already placed slides clear of it,
      // to the left first; with no room either side it is left out.
      const from = [at, ...taken.flatMap(([a, b]) => [a - 8 - size, b + 8])].sort((p, q) => Math.abs(p - at) - Math.abs(q - at)).find(one => !clashes(one))
      if (from === undefined) return ''
      taken.push([from, from + size])
      return label(from, 32, one.text, 'start', one.color === undefined ? MARK : paint(one.color))
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
 * A seat's bar: its input against the busiest seat's, the share served from
 * the prompt cache shaded.
 */
export function seatSvg(share: number, cached: number, width: number, color: string): string {
  const hue = paint(color)
  const filled = clamp(share) * width
  const warm = filled * clamp(cached)
  return svg(
    width,
    8,
    `<rect x="0" y="0" width="${width}" height="8" rx="4" fill="${TRACK}"/>` +
      (filled <= 0
        ? ''
        : `<defs><clipPath id="s"><rect x="0" y="0" width="${n(Math.max(filled, 8))}" height="8" rx="4"/></clipPath></defs>` +
          `<g clip-path="url(#s)"><rect x="0" y="0" width="${n(warm)}" height="8" fill="${hue}" fill-opacity="0.45"/>` +
          `<rect x="${n(warm)}" y="0" width="${n(Math.max(filled, 8) - warm)}" height="8" fill="${hue}"/></g>`),
  )
}

/**
 * A half-round gauge filled to `share`, its figure inside in the gauge's
 * color (or, `isThemed`, the page's text tone where the drawing it sits in
 * carries the theme), with an optional tick where the limit's window has run to.
 */
export function gaugeSvg(share: number, color: string, size: number, value: string, tick: number | null = null, isThemed = false): string {
  const stroke = Math.max(6, Math.round(size * 0.085))
  const r = size / 2 - stroke * 0.9 - 2
  const cx = size / 2
  // Room above the arc for the tick, which reaches past the stroke.
  const cy = r + stroke * 0.9 + 2
  const height = Math.ceil(cy + stroke / 2 + 2)
  const at = (part: number) => {
    const angle = Math.PI * (1 - clamp(part))
    return [cx + r * Math.cos(angle), cy - r * Math.sin(angle)] as const
  }
  const hue = paint(color)
  const arc = (part: number, paintWith: string) => {
    const [x, y] = at(part)
    return `<path d="M${n(cx - r)} ${n(cy)} A${n(r)} ${n(r)} 0 0 1 ${n(x)} ${n(y)}" fill="none" stroke="${paintWith}" stroke-width="${stroke}" stroke-linecap="round"/>`
  }
  let mark = ''
  if (tick !== null && Number.isFinite(tick)) {
    const angle = Math.PI * (1 - clamp(tick))
    const inner = r - stroke * 0.9
    const outer = r + stroke * 0.9
    mark = `<line x1="${n(cx + inner * Math.cos(angle))}" y1="${n(cy - inner * Math.sin(angle))}" x2="${n(cx + outer * Math.cos(angle))}" y2="${n(cy - outer * Math.sin(angle))}" stroke="${MARK}" stroke-width="2" stroke-linecap="round"/>`
  }
  return svg(
    size,
    height,
    arc(1, TRACK) +
      (clamp(share) > 0 ? arc(share, hue) : '') +
      mark +
      `<text x="${n(cx)}" y="${n(cy - 2)}" text-anchor="middle" font-family="${SANS}" font-size="${n(size * 0.2)}" font-weight="700"${isThemed ? ' class="fg"' : ` fill="${hue}"`}>${esc(value)}</text>`,
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

// ---------------------------------------------------------------------------
// The rows a panel describes, which native.tsx draws as the desktop's own
// text, and the type the gauge tiles and the band's meters set in their
// drawings: the page's light or dark tones from the system setting, the
// accents the drawings' own mid tones.

/** One stretch of text in a panel line; `chip` sets it on a soft pill. */
export type PanelRun = { text: string; color?: string; bold?: boolean; dim?: boolean; faint?: boolean; mono?: boolean; chip?: boolean }

export type PanelLine =
  /** Text, its `left` cut to fit beside `right`; `wrap` breaks a long `left` onto more lines instead. */
  | { kind: 'text'; left: PanelRun[]; right?: PanelRun[]; indent?: number; small?: boolean; wrap?: boolean }
  /** One of the drawings above, placed whole; `alt` says what it shows. */
  | { kind: 'picture'; svg: string; alt?: string; indent?: number }
  /** Pills in a row that wraps. */
  | { kind: 'chips'; chips: PanelRun[] }
  /** A badge beside two lines, as the account's. */
  | { kind: 'badge'; svg: string; lines: PanelRun[][] }

const THEME =
  '<style>' +
  '.fg{fill:#1d1d22}.dim{fill:#6b6b76}.faint{fill:#9a9aa6}.pill{fill:rgba(128,128,140,0.16)}' +
  '@media (prefers-color-scheme: dark){.fg{fill:#ececf1}.dim{fill:#a3a3ae}.faint{fill:#7a7a85}}' +
  '</style>'
const BODY = 12.5
const SMALL = 11.5
const PILL_X = 7

// A glyph's advance in pixels, near enough to cut and place text: wide
// scripts take a full em, monospace 0.6, proportional text about 0.56.
function advance(ch: string, size: number, mono: boolean): number {
  const code = ch.codePointAt(0) ?? 0
  if (code >= 0x2e80) return size
  if (mono) return size * 0.6
  if (' .,:;\'|!il'.includes(ch)) return size * 0.3
  if ('MWmw@'.includes(ch)) return size * 0.82
  if (/[A-Z]/.test(ch)) return size * 0.64
  return size * 0.55
}
const measure = (text: string, size: number, mono = false) => [...text].reduce((sum, ch) => sum + advance(ch, size, mono), 0)
// A chip's text is set small, whatever the line's size.
const sizeOf = (run: PanelRun, size: number) => (run.chip ? Math.min(size, SMALL) : size) - (run.mono ? 1 : 0)
const runWidth = (run: PanelRun, size: number) => measure(run.text, sizeOf(run, size), run.mono) + (run.chip ? 2 * PILL_X : 0)

/** Runs cut to `room` pixels, the last kept one ending in an ellipsis. */
function cut(runs: readonly PanelRun[], size: number, room: number): PanelRun[] {
  const total = runs.reduce((sum, run) => sum + runWidth(run, size), 0)
  if (total <= room) return [...runs]
  const kept: PanelRun[] = []
  let left = room - measure('…', size)
  for (const run of runs) {
    const width = runWidth(run, size)
    if (width <= left) {
      kept.push(run)
      left -= width
      continue
    }
    let text = ''
    for (const ch of run.text) {
      const next = advance(ch, run.mono ? size - 1 : size, Boolean(run.mono))
      if (next > left - (run.chip ? 2 * PILL_X : 0)) break
      text += ch
      left -= next
    }
    kept.push({ ...run, text: text.trimEnd() + '…' })
    break
  }
  return kept
}

function toneOf(run: PanelRun): { cls: string; fill: string; opacity: string } {
  if (run.color !== undefined && PALETTE_BY_NAME[run.color] === undefined && !/^#/.test(run.color)) {
    // A theme key the drawings lack reads as body text.
    return { cls: run.dim ? 'dim' : run.faint ? 'faint' : 'fg', fill: '', opacity: '' }
  }
  if (run.color !== undefined) return { cls: '', fill: ` fill="${paint(run.color)}"`, opacity: run.dim ? ' fill-opacity="0.7"' : '' }
  return { cls: run.dim ? 'dim' : run.faint ? 'faint' : 'fg', fill: '', opacity: '' }
}

const tspan = (run: PanelRun, size: number) => {
  const runSize = run.mono ? size - 1 : size
  const tone = toneOf(run)
  return (
    `<tspan${tone.cls ? ` class="${tone.cls}"` : ''}${tone.fill}${tone.opacity} font-family="${run.mono ? MONO : SANS}" font-size="${n(runSize)}"` +
    `${run.bold ? ' font-weight="600"' : ''}>${esc(run.text)}</tspan>`
  )
}

let nested = 0
/** A whole drawing placed at `x`, `y` inside another, its ids made its own. */
function place(source: string, x: number, y: number): { svg: string; width: number; height: number } {
  const width = Number(/width="([\d.]+)"/.exec(source)?.[1] ?? 0)
  const height = Number(/height="([\d.]+)"/.exec(source)?.[1] ?? 0)
  const tag = `p${++nested}`
  const body = source
    .replace(/ id="([^"]+)"/g, ` id="${tag}$1"`)
    .replace(/url\(#([^)]+)\)/g, `url(#${tag}$1)`)
    .replace('<svg xmlns="http://www.w3.org/2000/svg" ', `<svg x="${n(x)}" y="${n(y)}" `)
  return { svg: body, width, height }
}

/**
 * A gauge tile's face: the dial over its key and notes, centered in `width`.
 * The tile's frame is the desktop's own, so it stretches with the pane as the
 * panels do.
 */
export function gaugeTileSvg(tile: { dial: string; key: string; notes: readonly PanelRun[][] }, width: number): string {
  nested = 0
  const cx = width / 2
  const dial = place(tile.dial, 0, 0)
  let out = place(tile.dial, cx - dial.width / 2, 6).svg
  let y = 6 + dial.height + 4
  out += `<text x="${n(cx)}" y="${n(y + 9)}" text-anchor="middle" class="faint" font-family="${MONO}" font-size="10" font-weight="600" letter-spacing="0.8">${esc(tile.key.toUpperCase())}</text>`
  y += 12
  for (const note of tile.notes) {
    const runs = cut(note, 11, width - 4)
    out += `<text x="${n(cx)}" y="${n(y + 11)}" text-anchor="middle" xml:space="preserve">${runs.map(run => tspan({ ...run, dim: run.color === undefined ? true : run.dim }, 11)).join('')}</text>`
    y += 15
  }
  return svg(width, Math.ceil(y + 6), THEME + out)
}

/** One meter in the minimized band: a key, its figure, a bar with an optional tick, and a note. */
export type BandMeter = { key: string; percent: number; share: number; color: string; tick: number | null; note: PanelRun[] }

/**
 * The minimized band's meters side by side, each column as wide as the
 * others with a gap between; a narrow drawing drops the notes' tails.
 */
export function bandMetersSvg(meters: readonly BandMeter[], width: number): string {
  nested = 0
  const gap = 12
  const column = (width - gap * Math.max(0, meters.length - 1)) / Math.max(1, meters.length)
  let out = ''
  for (const [index, meter] of meters.entries()) {
    const x = index * (column + gap)
    out += `<text x="${n(x)}" y="11" class="faint" font-family="${MONO}" font-size="10" font-weight="600" letter-spacing="0.8">${esc(meter.key.toUpperCase())}</text>`
    out += `<text x="${n(x + column)}" y="11" text-anchor="end" font-family="${SANS}" font-size="${BODY}" font-weight="600" fill="${paint(meter.color)}">${esc(`${Math.round(meter.percent)}%`)}</text>`
    out += place(meterSvg(meter.share, column, meter.color, meter.tick === null ? [] : [{ at: meter.tick }], 10), x, 16).svg
    if (meter.note.length > 0) {
      const runs = cut(meter.note, 11, column)
      out += `<text x="${n(x)}" y="41" xml:space="preserve">${runs.map(run => tspan({ ...run, dim: run.color === undefined ? true : run.dim }, 11)).join('')}</text>`
    }
  }
  return svg(width, meters.some(meter => meter.note.length > 0) ? 46 : 30, THEME + out)
}
