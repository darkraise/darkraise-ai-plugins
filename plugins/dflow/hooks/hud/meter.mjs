// Meters, durations and terminal widths for the HUD, ported from the dforge
// cockpit's lib.ts: plugins never import each other.

/** 465000 → "465k"; 1234567 → "1.2M"; 999500, which rounds to 1000k, → "1.0M". */
export function kTokens(n) {
  if (n >= 999_500) return `${(n / 1_000_000).toFixed(1)}M`;
  return `${Math.round(n / 1000)}k`;
}

/** 0.8 → "▰▰▰▰▰▰▰▰▱▱" at width 10; never full below 100%. */
export function bar(share, width) {
  const clamped = Math.min(Math.max(share, 0), 1);
  let on = Math.round(clamped * width);
  if (on === width && clamped < 1) on = width - 1;
  return '▰'.repeat(on) + '▱'.repeat(width - on);
}

/** The usage ramp: green, yellow, orange, then red. */
export function rampColor(percent) {
  if (percent >= 90) return 'error';
  if (percent >= 75) return '#ff8700';
  return percent >= 50 ? 'warning' : 'success';
}

/** Milliseconds → "3h40m", "2d4h", "12m"; nothing under a minute, so a caller says "now" or "<1m" itself. */
export function duration(ms) {
  if (!(ms >= 60_000)) return '';
  const minutes = Math.floor(ms / 60_000);
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  if (days > 0) return `${days}d${hours}h`;
  return hours > 0 ? `${hours}h${minutes % 60}m` : `${minutes}m`;
}

/** five_hour → "5h", seven_day → "7d", spend_limit → "spend". */
export function limitLabel(kind) {
  if (kind === 'five_hour') return '5h';
  if (kind === 'seven_day') return '7d';
  return kind.replace(/_limit$/, '').replace(/_/g, ' ');
}

const SPARKS = '▁▂▃▄▅▆▇█';

/** Readings → "▁▃▅█" scaled between their least and most; flat readings sit mid-height. */
export function sparkline(values) {
  if (values.length === 0) return '';
  const low = Math.min(...values);
  const span = Math.max(...values) - low;
  return values
    .map(value => SPARKS[span === 0 ? 3 : Math.round(((value - low) / span) * (SPARKS.length - 1))])
    .join('');
}

/**
 * A meter `width` cells wide filled to `share`, with each mark's glyph in the
 * cell its share lands on (a later mark wins a shared cell). Never full below 100%.
 */
export function track(share, width, marks) {
  const cells = [...bar(share, width)].map(cell => ({ text: cell, kind: cell === '▰' ? 'fill' : 'empty' }));
  for (const mark of marks) {
    if (!(mark.at >= 0 && mark.at <= 1)) continue;
    const index = Math.min(width - 1, Math.floor(mark.at * width));
    cells[index] = { text: mark.glyph, kind: 'mark', mark: mark.name };
  }
  // Neighbouring cells of one kind join into one run.
  return cells.reduce((runs, cell) => {
    const last = runs[runs.length - 1];
    if (last !== undefined && last.kind === cell.kind && cell.kind !== 'mark') last.text += cell.text;
    else runs.push({ ...cell });
    return runs;
  }, []);
}

/** A track's parts as runs: the fill in `color`, the empty part dim, each mark bold in its own color. */
export function trackRuns(parts, color, markColors) {
  return parts.map(part => {
    if (part.kind === 'fill') return { text: part.text, color };
    if (part.kind === 'empty') return { text: part.text, dim: true };
    return { text: part.text, color: markColors[part.mark] ?? color, bold: true };
  });
}

/**
 * Splits `width` cells among values in proportion, largest remainders first,
 * every nonzero value at least one cell while the width lasts.
 */
export function stackedRuns(values, width) {
  const total = values.reduce((sum, value) => sum + Math.max(0, value), 0);
  if (total === 0) return values.map(() => 0);
  const exact = values.map(value => (Math.max(0, value) / total) * width);
  const runs = exact.map(Math.floor);
  let left = width - runs.reduce((sum, run) => sum + run, 0);
  const order = exact.map((value, index) => ({ index, rest: value - Math.floor(value) })).sort((a, b) => b.rest - a.rest);
  for (const { index } of order) {
    if (left === 0) break;
    runs[index] += 1;
    left--;
  }
  for (const [index, run] of runs.entries()) {
    if (run > 0 || values[index] <= 0) continue;
    const donor = runs.indexOf(Math.max(...runs));
    if (runs[donor] > 1) {
      runs[donor] -= 1;
      runs[index] = 1;
    }
  }
  return runs;
}

const WINDOW_MS = { five_hour: 5 * 3_600_000, seven_day: 7 * 86_400_000 };

/** How far through its window a rate limit is, 0 to 1, or null for a window of unknown length. */
export function windowElapsed(kind, resetsAt, now) {
  const length = WINDOW_MS[kind];
  if (length === undefined || resetsAt === null) return null;
  return Math.min(1, Math.max(0, 1 - (resetsAt - now) / length));
}

/**
 * Where a rate limit is headed at the pace spent so far in its window: the
 * milliseconds until it runs out when that comes before the reset, 'pace' when
 * it lasts, null when the window is too young or its length unknown.
 */
export function limitForecast(kind, percent, resetsAt, now) {
  const length = WINDOW_MS[kind];
  if (length === undefined || resetsAt === null || percent <= 0 || percent >= 100) return null;
  const spent = length - (resetsAt - now);
  if (spent < 10 * 60_000) return null;
  const left = ((100 - percent) / percent) * spent;
  return now + left < resetsAt ? left : 'pace';
}

// A terminal draws a combining mark, a joiner or a variation selector in no
// cell of its own, and an emoji or an East Asian wide or fullwidth character in
// two. An emoji drawn as text by default (⚠) takes two once U+FE0F asks for its
// emoji presentation (⚠️).
const ZERO_CELLS = /[\p{Mn}\p{Me}​-‏︀-️]/u;
const TWO_CELLS = /[\p{Emoji_Presentation}ᄀ-ᅟ⺀-〾ぁ-㏿㐀-䶿一-鿿ꀀ-꓏가-힣豈-﫿︰-﹏＀-｠￠-￦\u{20000}-\u{3fffd}]/u;
const EMOJI = /\p{Emoji}/u;

/** The terminal cells a text takes. */
export function cellWidth(text) {
  let cells = 0;
  let previous = '';
  for (const char of text) {
    const isWidened = char === '️' && EMOJI.test(previous) && !TWO_CELLS.test(previous);
    cells += isWidened ? 1 : ZERO_CELLS.test(char) ? 0 : TWO_CELLS.test(char) ? 2 : 1;
    previous = char;
  }
  return cells;
}

/** The cells a row of runs takes. */
export function runsWidth(runs) {
  return runs.reduce((sum, run) => sum + cellWidth(run.text), 0);
}

/** A row cut to `width` cells, ending in an ellipsis when anything was cut. */
export function runsCut(runs, width) {
  if (runsWidth(runs) <= width) return [...runs];
  const out = [];
  let left = Math.max(0, width - 1);
  for (const run of runs) {
    const cells = cellWidth(run.text);
    if (cells <= left) {
      out.push(run);
      left -= cells;
      continue;
    }
    let text = '';
    for (const char of run.text) {
      if (cellWidth(text + char) > left) break;
      text += char;
    }
    if (text !== '') out.push({ ...run, text });
    break;
  }
  if (width > 0) out.push({ text: '…', dim: true });
  return out;
}

/** Whether a release (`2.1.295`) is at least `least`, compared part by part; an unreadable one is not. */
export function isAtLeast(base, least) {
  const parts = text => text.split('-')[0].split('.').map(Number);
  if (base === undefined || !/^\d+\.\d+\.\d+/.test(base)) return false;
  const have = parts(base);
  const want = parts(least);
  for (let i = 0; i < want.length; i++) {
    if ((have[i] ?? 0) !== want[i]) return (have[i] ?? 0) > want[i];
  }
  return true;
}
