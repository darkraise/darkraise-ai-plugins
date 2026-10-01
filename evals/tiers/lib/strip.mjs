import { git } from './sh.mjs';

export const MARKER = '[implementation removed: write this code yourself so that the tests in this brief pass]';

export const isTestPath = path => /(^|\/)tests\//.test(path);

// addedLines BASE RESULT — the trimmed, non-blank lines RESULT adds to files
// outside every tests/ directory.
export function addedLines(base, result) {
  const files = git(['diff', '--name-only', base, result]).split('\n').filter(p => p && !isTestPath(p));
  if (files.length === 0) return new Set();
  const diff = git(['diff', '-U0', base, result, '--', ...files]);
  return new Set(diff.split('\n').filter(l => l.startsWith('+') && !l.startsWith('+++')).map(l => l.slice(1).trim()).filter(Boolean));
}

// strip BRIEF ADDED — BRIEF with every fenced block replaced by MARKER when more
// than half of its non-blank lines are in ADDED. An outer fence owns the
// fences nested inside it, as in the plan reader. Returns { text, removed }.
export function strip(brief, added) {
  const out = [];
  let open = null, block = [], removed = 0;
  for (const line of brief.split('\n')) {
    if (open === null) {
      const m = line.match(/^ {0,3}(`{3,}|~{3,})/);
      if (m) { open = m[1]; block = [line]; } else out.push(line);
      continue;
    }
    block.push(line);
    const t = line.trim();
    if (!(t.length >= open.length && t === open[0].repeat(t.length))) continue;
    const body = block.slice(1, -1).map(l => l.trim()).filter(Boolean);
    const hits = body.filter(l => added.has(l)).length;
    if (body.length > 0 && hits * 2 > body.length) { out.push(MARKER); removed += 1; } else out.push(...block);
    open = null;
  }
  if (open !== null) out.push(...block);
  return { text: out.join('\n'), removed };
}
