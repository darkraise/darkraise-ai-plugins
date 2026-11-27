#!/usr/bin/env node
// Per-task usage from task markers: slices Claude transcripts at the byte
// offsets the open and close markers recorded, prices each slice, and reports
// one row per task (or per group of tasks whose slices overlap).
// Arguments, exit codes and the JSON shape: the plugin's usage-report wrapper.
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PRICES = path.join(HERE, '..', '..', 'reference', 'api-prices.json');
const FIELDS = ['input', 'cacheRead', 'cacheWrite5m', 'cacheWrite1h', 'output'];
const COLUMNS = ['time', 'event', 'plugin', 'version', 'root', 'plan', 'task', 'session',
  'transcript', 'bytes', 'context', 'caller', 'range', 'deferred'];
const MULTI = new Set(['--markers', '--transcripts', '--repo']);
const SINGLE = new Set(['--plan', '--ledger', '--register', '--review-record', '--workspace',
  '--saved', '--from-archive', '--format']);

class UsageError extends Error {}

export function parseArgs(argv) {
  const opts = { markers: [], transcripts: [], repo: [], format: 'md' };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    const key = flag.replace(/^--/, '').replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    if (MULTI.has(flag)) {
      let n = 0;
      while (i + 1 < argv.length && !argv[i + 1].startsWith('--')) { opts[key].push(argv[++i]); n++; }
      if (n === 0) throw new UsageError(`${flag} needs a value`);
    } else if (SINGLE.has(flag)) {
      if (i + 1 >= argv.length) throw new UsageError(`${flag} needs a value`);
      opts[key] = argv[++i];
    } else {
      throw new UsageError(`unknown argument: ${flag}`);
    }
  }
  if (!['md', 'json'].includes(opts.format)) throw new UsageError('--format is md or json');
  return opts;
}

const emptyUsage = () => ({ turns: 0, input: 0, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0, output: 0, cost: 0 });
const round6 = (x) => Math.round(x * 1e6) / 1e6;
const num = (s) => (s === undefined || s === '' || Number.isNaN(Number(s)) ? null : Number(s));

// Set when the prices file cannot be read: every model is then unpriced, and
// the report says why instead of showing a cost of $0.00 as measured.
let pricesError = null;

export function loadPrices(file = PRICES) {
  try {
    const models = JSON.parse(fs.readFileSync(file, 'utf8')).models || {};
    pricesError = null;
    return Object.fromEntries(Object.entries(models).filter(([, r]) => r.provider === 'anthropic'));
  } catch (e) {
    pricesError = `${file}: ${e.message}`;
    return {};
  }
}

// The usage of one assistant message, in report fields.
function usageOf(u) {
  const cc = u.cache_creation;
  return {
    input: u.input_tokens || 0,
    cacheRead: u.cache_read_input_tokens || 0,
    cacheWrite5m: cc ? cc.ephemeral_5m_input_tokens || 0 : u.cache_creation_input_tokens || 0,
    cacheWrite1h: cc ? cc.ephemeral_1h_input_tokens || 0 : 0,
    output: u.output_tokens || 0,
  };
}

export function costOf(model, u, prices) {
  const p = prices[model];
  if (!p) return null;
  return (u.input * p.input + u.cacheRead * p.cacheRead + u.cacheWrite5m * p.cacheWrite5m
    + u.cacheWrite1h * p.cacheWrite1h + u.output * p.output) / 1e6;
}

const transcriptCache = new Map();
// [{offset, entry}] for a JSONL file, read once; unparsable lines are skipped.
export function readEntries(file) {
  if (transcriptCache.has(file)) return transcriptCache.get(file);
  let buf;
  try { buf = fs.readFileSync(file); } catch { transcriptCache.set(file, null); return null; }
  const out = [];
  let start = 0;
  while (start < buf.length) {
    let end = buf.indexOf(10, start);
    if (end < 0) end = buf.length;
    const line = buf.subarray(start, end).toString('utf8').replace(/\r$/, '');
    if (line) { try { out.push({ offset: start, entry: JSON.parse(line) }); } catch { /* not JSON */ } }
    start = end + 1;
  }
  out.size = buf.length;
  transcriptCache.set(file, out);
  return out;
}

// Assistant messages, one per message id with the largest value of each field:
// a streamed message is written several times as its usage grows.
export function messages(entries, sidechain) {
  const byId = new Map();
  for (const { entry: e } of entries) {
    const m = e && e.type === 'assistant' && e.message;
    if (!m || !m.usage || m.model === '<synthetic>') continue;
    if (!sidechain && e.isSidechain) continue;
    const id = m.id || e.uuid;
    const u = usageOf(m.usage);
    const prev = byId.get(id);
    if (!prev) byId.set(id, { model: m.model, usage: u });
    else for (const f of FIELDS) prev.usage[f] = Math.max(prev.usage[f], u[f]);
  }
  return [...byId.values()];
}

// Main-chain messages of one transcript, each at the offset of its first
// record with the largest value of each field over all its records: a slice
// counts a streamed message once, in the slice its first record falls in.
const streamIndexes = new WeakMap();
function streamIndex(all) {
  if (streamIndexes.has(all)) return streamIndexes.get(all);
  const byId = new Map();
  for (const { offset, entry: e } of all) {
    const m = e && e.type === 'assistant' && e.message;
    if (!m || !m.usage || m.model === '<synthetic>' || e.isSidechain) continue;
    const id = m.id || e.uuid;
    const u = usageOf(m.usage);
    const prev = byId.get(id);
    if (!prev) byId.set(id, { id, offset, model: m.model, usage: u });
    else for (const f of FIELDS) prev.usage[f] = Math.max(prev.usage[f], u[f]);
  }
  const out = [...byId.values()];
  streamIndexes.set(all, out);
  return out;
}

// The messages of [transcript entries, offset test] slices, one per message id.
function sliceMessages(parts) {
  const byId = new Map();
  for (const [all, inSlice] of parts) {
    for (const x of streamIndex(all)) {
      if (!inSlice(x.offset)) continue;
      const prev = byId.get(x.id);
      if (!prev) byId.set(x.id, { model: x.model, usage: { ...x.usage } });
      else for (const f of FIELDS) prev.usage[f] = Math.max(prev.usage[f], x.usage[f]);
    }
  }
  return [...byId.values()];
}

// Totals of a message list, priced; unpriced models are collected.
export function total(msgs, prices, unpriced, byModel) {
  const t = emptyUsage();
  for (const { model, usage } of msgs) {
    t.turns++;
    for (const f of FIELDS) t[f] += usage[f];
    const c = costOf(model, usage, prices);
    if (c === null) unpriced.add(model); else t.cost += c;
    if (byModel) {
      const b = byModel[model] || (byModel[model] = emptyUsage());
      b.turns++;
      for (const f of FIELDS) b[f] += usage[f];
      b.cost += c || 0;
    }
  }
  return t;
}

export function readMarkers(files) {
  const rows = [];
  files.forEach((file, fi) => {
    let text;
    try { text = fs.readFileSync(file, 'utf8'); } catch { return; }
    text.split('\n').forEach((line, li) => {
      const cols = line.replace(/\r$/, '').split('\t');
      if (cols.length !== COLUMNS.length || !['open', 'close'].includes(cols[1])) return;
      const r = Object.fromEntries(COLUMNS.map((c, i) => [c, cols[i]]));
      r.order = fi * 1e9 + li;
      r.file = file;
      rows.push(r);
    });
  });
  return rows.sort((a, b) => (a.time < b.time ? -1 : a.time > b.time ? 1 : a.order - b.order));
}

function resolveTranscript(row, dirs) {
  if (row.transcript && fs.existsSync(row.transcript)) return row.transcript;
  if (!row.session) return null;
  for (const d of dirs) {
    const direct = path.join(d, `${row.session}.jsonl`);
    if (fs.existsSync(direct)) return direct;
    let subs = [];
    try { subs = fs.readdirSync(d, { withFileTypes: true }).filter((s) => s.isDirectory()); } catch { /* none */ }
    for (const s of subs) {
      const f = path.join(d, s.name, `${row.session}.jsonl`);
      if (fs.existsSync(f)) return f;
    }
  }
  return null;
}

const ms = (t) => (t ? Date.parse(t) : NaN);

// The segments of one closed task: per session, from its open (or the
// transcript's start) to the close in that session (or the transcript's end).
function segments(opens, close, dirs) {
  const bySession = new Map();
  for (const o of opens) if (!bySession.has(o.session)) bySession.set(o.session, o);
  if (!bySession.has(close.session)) bySession.set(close.session, null);
  const segs = [];
  for (const [session, o] of bySession) {
    const file = resolveTranscript(o || close, dirs);
    const same = session === close.session;
    const start = o ? num(o.bytes) : 0;
    const end = same ? num(close.bytes) : Infinity;
    // A mark written while no transcript was found carries no byte offset, so
    // the slice it bounds is unknown, not the whole transcript.
    if (!file || start === null || end === null) { segs.unresolved = true; continue; }
    segs.push({ file, start, end, from: o ? ms(o.time) : -Infinity, to: same ? ms(close.time) : Infinity });
  }
  if (!segs.length) segs.unresolved = true;
  return segs;
}

function mergeIntervals(list) {
  const sorted = [...list].sort((a, b) => a.start - b.start);
  const out = [];
  for (const s of sorted) {
    const last = out[out.length - 1];
    if (last && s.start <= last.end) last.end = Math.max(last.end, s.end);
    else out.push({ start: s.start, end: s.end });
  }
  return out;
}

function subagentFiles(transcript) {
  const dir = path.join(transcript.replace(/\.jsonl$/, ''), 'subagents');
  let names = [];
  try { names = fs.readdirSync(dir).filter((n) => /^agent-.*\.jsonl$/.test(n)).sort(); } catch { return []; }
  return names.map((n) => {
    const file = path.join(dir, n);
    let type = 'unknown';
    try { type = JSON.parse(fs.readFileSync(file.replace(/\.jsonl$/, '.meta.json'), 'utf8')).agentType || type; } catch { /* no meta */ }
    const entries = readEntries(file) || [];
    const first = entries.find((x) => x.entry && x.entry.timestamp);
    return { file, type, entries, first: first ? ms(first.entry.timestamp) : NaN };
  });
}

const FAMILIES = [[/run-codex-task\.sh/g, 'codex-task'], [/run-agy-task\.sh/g, 'agy-task'],
  [/run-codex-review\.sh/g, 'codex-review'], [/run-agy-review\.sh/g, 'agy-review'],
  [/run-review-panel/g, 'review-panel'], [/run-api-judge/g, 'api-judge']];

// C15: task bounds from the task-brief, task-step start and task-close calls
// in a transcript's Bash commands, with $VAR and ${VAR} resolved from
// assignments earlier in the same command.
export function inferBounds(entries) {
  const opens = [];
  const closes = [];
  for (const { offset, entry: e } of entries) {
    for (const b of toolUses(e)) {
      if (b.name !== 'Bash' || !b.input || typeof b.input.command !== 'string') continue;
      const vars = {};
      for (const part of b.input.command.split(/\n|;|&&|\|\|/)) {
        const cmd = part.trim().replace(/\$\{(\w+)\}|\$(\w+)/g, (m, a, c) => (vars[a || c] ?? m));
        const as = /^([A-Za-z_]\w*)=("[^"]*"|'[^']*'|\S*)\s*$/.exec(cmd);
        if (as) { vars[as[1]] = as[2].replace(/^["']|["']$/g, ''); continue; }
        const unq = (x) => x.replace(/^["']|["']$/g, '');
        let m = /task-brief["']?(\s+--open)?\s+("[^"]+"|'[^']+'|[^\s-]\S*)\s+(\d+)\b/.exec(cmd);
        if (m) opens.push({ plan: unq(m[2]), task: Number(m[3]), start: offset, explicit: Boolean(m[1]) });
        m = /task-step["']?\s+start\s+("[^"]+"|'[^']+'|\S+)((?:\s+\d+)+)/.exec(cmd);
        if (m) for (const n of m[2].trim().split(/\s+/)) opens.push({ plan: unq(m[1]), task: Number(n), start: offset });
        m = /task-close["']?\s+("[^"]+"|'[^']+'|\S+)\s+(\d+)\b/.exec(cmd);
        if (m) closes.push({ plan: unq(m[1]), task: Number(m[2]), at: offset });
      }
    }
  }
  const size = entries.size ?? (entries.length ? entries[entries.length - 1].offset + 1 : 0);
  // A plain task-brief only reads a brief once --open exists: it opens a task
  // only in sessions that never call --open for that task.
  const kept = opens.filter((o) => o.explicit !== false
    || !opens.some((x) => x.explicit && x.plan === o.plan && x.task === o.task));
  return kept.map((o) => {
    const close = closes.find((c) => c.plan === o.plan && c.task === o.task && c.at >= o.start);
    const next = kept.find((x) => x.start > o.start);
    return { plan: o.plan, task: o.task, start: o.start, end: close ? close.at + 1 : next ? next.start : size };
  });
}

// --from-archive DIR: an extracted transcript archive whose manifest.tsv names
// each session and its project. With no markers, a task's bounds come from the
// session's own task calls (C15), as open and close rows labelled inferred; a
// task no task-close call ends closes where its last bound ends.
export function archiveRows(dir) {
  if (!dir) return [];
  const manifest = path.join(dir, 'manifest.tsv');
  let text;
  try { text = fs.readFileSync(manifest, 'utf8'); } catch { return []; }
  const [head = '', ...lines] = text.split(/\r?\n/).filter(Boolean);
  const cols = head.split('\t');
  const rows = [];
  const last = new Map();
  for (const line of lines) {
    const cells = line.split('\t');
    const session = cells[cols.indexOf('session')];
    const file = session && resolveTranscript({ session }, [dir]);
    if (!file) continue;
    const entries = readEntries(file) || [];
    const starts = new Set(entries.map((x) => x.offset));
    for (const b of inferBounds(entries)) {
      if (!/\.md$/.test(b.plan) || b.plan.includes('$')) continue;
      const stamped = entries.filter((x) => x.offset >= b.start && x.offset < b.end && x.entry && x.entry.timestamp);
      if (!stamped.length) continue;
      const row = {
        plugin: '', version: '', root: '', plan: path.basename(b.plan), task: String(b.task), session,
        transcript: file, context: '', caller: 'inferred', range: '', deferred: '', file: manifest,
        repo: cells[cols.indexOf('project')] || null, inferred: true,
      };
      const end = stamped[stamped.length - 1].entry.timestamp;
      rows.push({ ...row, time: stamped[0].entry.timestamp, event: 'open', bytes: String(b.start) });
      // A bound a task-close call ends stops one byte past that call's line start.
      if (starts.has(b.end - 1)) rows.push({ ...row, time: end, event: 'close', bytes: String(b.end) });
      last.set(`${row.plan}\t${row.task}`, { ...row, time: end, event: 'close', bytes: String(b.end) });
    }
    transcriptCache.delete(file);
  }
  for (const [key, close] of last) {
    if (!rows.some((r) => r.event === 'close' && `${r.plan}\t${r.task}` === key)) rows.push(close);
  }
  return rows;
}

const LOOKUP_WORDS = new Set(['grep', 'rg', 'cat', 'head', 'tail']);
const toolUses = (e) => (e && e.type === 'assistant' && e.message && Array.isArray(e.message.content)
  ? e.message.content.filter((b) => b && b.type === 'tool_use') : []);
const userBlocks = (e) => (e && e.type === 'user' && e.message && Array.isArray(e.message.content) ? e.message.content : []);
const textOf = (c) => (typeof c === 'string' ? c : Array.isArray(c) ? c.map((b) => (b && typeof b.text === 'string' ? b.text : '')).join('') : '');
const contextOf = (u) => u.input + u.cacheRead + u.cacheWrite5m + u.cacheWrite1h;

// The command a Bash lookup runs, past `cd …&&` and environment assignments.
function lookupTarget(cmd) {
  const parts = cmd.split(/&&|;/).map((x) => x.trim()).filter(Boolean);
  const last = parts.filter((x) => !/^cd(\s|$)/.test(x)).shift();
  if (!last) return null;
  const words = last.split(/\s+/).filter((w) => !/^[A-Za-z_][A-Za-z0-9_]*=/.test(w));
  const [w0, w1] = words;
  if (!(LOOKUP_WORDS.has(w0) || (w0 === 'sed' && w1 === '-n'))) return null;
  const tail = words.slice(1).filter((w) => !w.startsWith('-') && !/[|<>]/.test(w));
  return { target: (tail[tail.length - 1] || '').replace(/^['"]|['"]$/g, '') };
}

// The paths a task names on its **Files:** and its - Create/Modify/Test/Delete
// lines anywhere in its section, each whole, without a :<line> range or ./
export function planFiles(planText, n) {
  const m = planText.split(/\r?\n/);
  const start = m.findIndex((l) => new RegExp(`^### Task ${n}:`).test(l));
  if (start < 0) return [];
  const out = [];
  let fence = '';
  for (let i = start + 1; i < m.length; i++) {
    const l = m[i];
    const f = /^\s*(`{3,}|~{3,})/.exec(l);
    if (f) {
      if (!fence) fence = f[1];
      else if (f[1][0] === fence[0] && f[1].length >= fence.length) fence = '';
      continue;
    }
    if (fence) continue;
    if (/^### /.test(l)) break;
    const head = /^\*\*Files:\*\*/.exec(l) || /^\s*- (?:Create|Modify|Test|Delete)(?:\s*\([^)]*\))?:/.exec(l);
    if (!head) continue;
    const ticks = [...l.matchAll(/`([^`]+)`/g)].map((x) => x[1].trim());
    for (const p of ticks.length ? ticks : (l.slice(head[0].length).match(/[\w./-]+\.\w+/g) || [])) {
      const file = p.replace(/:\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*$/, '').replace(/^\.\//, '');
      if (file) out.push(file);
    }
  }
  return out;
}

// Lookups, reads, repeat reads and background waits among a row's entries.
export function lookupMetrics(entries, files) {
  const seen = new Set();
  const readIds = new Set();
  const wholeRead = new Set();
  const bg = new Map();
  let lookups = 0; let repeatReads = 0; let inFiles = 0; let readTokens = 0; let waitSeconds = 0; let fixRounds = 0;
  const dispatches = {};
  const bump = (k) => { dispatches[k] = (dispatches[k] || 0) + 1; };
  const hit = (t) => t && files.some((f) => t === f || t.endsWith(`/${f}`));
  for (const { entry: e } of entries) {
    for (const b of toolUses(e)) {
      if (seen.has(b.id)) continue;
      seen.add(b.id);
      const inp = b.input || {};
      if (b.name === 'Read') {
        lookups++;
        readIds.add(b.id);
        if (hit(inp.file_path)) inFiles++;
        if (inp.offset === undefined && inp.limit === undefined) {
          if (wholeRead.has(inp.file_path)) repeatReads++;
          wholeRead.add(inp.file_path);
        }
      } else if ((b.name === 'Agent' || b.name === 'Task') && inp.subagent_type) {
        bump(inp.subagent_type);
      } else if (b.name === 'Bash' && typeof inp.command === 'string') {
        for (const [re, fam] of FAMILIES) for (let k = (inp.command.match(re) || []).length; k > 0; k--) bump(fam);
        fixRounds += (inp.command.match(/task-step\S*\s+rereview\b/g) || []).length;
        const l = lookupTarget(inp.command);
        if (l) { lookups++; if (hit(l.target)) inFiles++; }
        if (inp.run_in_background) bg.set(b.id, { at: ms(e.timestamp), task: null });
      }
    }
    for (const b of userBlocks(e)) {
      if (b.type !== 'tool_result') continue;
      if (readIds.has(b.tool_use_id)) readTokens += Math.ceil(textOf(b.content).length / 4);
      const w = bg.get(b.tool_use_id);
      const id = w && /ID: ([A-Za-z0-9_-]+)/.exec(textOf(b.content));
      if (id) w.task = id[1];
    }
    const text = e && e.type === 'user' && e.message ? textOf(e.message.content) : '';
    if (text.includes('<task-notification>')) {
      const ids = [...text.matchAll(/<task-id>([^<]+)<\/task-id>/g)].map((x) => x[1]);
      for (const [k, w] of bg) {
        if (ids.length ? ids.includes(w.task) : w.task === null) {
          const at = ms(e.timestamp);
          if (Number.isFinite(at) && Number.isFinite(w.at)) waitSeconds += Math.round((at - w.at) / 1000);
          bg.delete(k);
          break;
        }
      }
    }
  }
  return { lookups, readTokens, repeatReads, filesLookupShare: lookups && files.length ? round6(inFiles / lookups) : null, waitSeconds, dispatches, fixRounds };
}

// Context growth: the sum of rises between consecutive main-chain requests.
function growthOf(msgs) {
  let g = 0;
  for (let i = 1; i < msgs.length; i++) g += Math.max(0, contextOf(msgs[i].usage) - contextOf(msgs[i - 1].usage));
  return g;
}

// The byte spans of every closed task's slices, per transcript.
function taskSpans(rows, dirs) {
  const tasks = new Map();
  for (const r of rows) {
    const t = tasks.get(r.task) || { opens: [], close: null };
    if (r.event === 'close') { if (!t.close) t.close = r; } else if (!t.close) t.opens.push(r);
    tasks.set(r.task, t);
  }
  const spans = new Map();
  for (const t of tasks.values()) {
    if (!t.close) continue;
    for (const x of segments(t.opens, t.close, dirs)) spans.set(x.file, [...(spans.get(x.file) || []), { start: x.start, end: x.end, from: x.from, to: x.to }]);
  }
  return spans;
}

function transcriptFiles(dirs) {
  const out = [];
  for (const d of dirs) {
    let list = [];
    try { list = fs.readdirSync(d, { withFileTypes: true }); } catch { continue; }
    for (const x of list) {
      if (x.isFile() && x.name.endsWith('.jsonl')) out.push(path.join(d, x.name));
      else if (x.isDirectory()) {
        try { for (const y of fs.readdirSync(path.join(d, x.name))) if (y.endsWith('.jsonl')) out.push(path.join(d, x.name, y)); } catch { /* skip */ }
      }
    }
  }
  return out;
}

function ledgerUnmarked(ledger, marked, plan, dirs) {
  let text;
  if (!ledger) return [];
  try { text = fs.readFileSync(ledger, 'utf8'); } catch { return []; }
  const out = [];
  let bounds = null;
  for (const line of text.split(/\r?\n/)) {
    const m = /^Task (\d+): complete \((.*)/.exec(line);
    if (!m || marked.get(m[1])?.close || /^deferred by the auto run\)/.test(m[2])) continue;
    // Open rows with no close (an attended dagents run): measured by inference.
    const opened = marked.get(m[1]);
    if (!bounds) {
      bounds = [];
      for (const f of transcriptFiles(dirs)) for (const b of inferBounds(readEntries(f) || [])) bounds.push({ ...b, file: f });
    }
    const n = Number(m[1]);
    const segs = bounds.filter((b) => b.task === n && path.basename(b.plan) === path.basename(plan)).map((b) => {
      const inside = (readEntries(b.file) || []).filter((x) => x.offset >= b.start && x.offset < b.end && x.entry && x.entry.timestamp);
      return { file: b.file, start: b.start, end: b.end, from: inside.length ? ms(inside[0].entry.timestamp) : NaN, to: inside.length ? ms(inside[inside.length - 1].entry.timestamp) : NaN };
    });
    const range = /^commits ([^,)]+)/.exec(m[2]);
    if (!segs.length) segs.unresolved = true;
    out.push({ n, opens: opened ? opened.opens : [], close: { range: range ? range[1] : '', context: '', time: '', inferred: Boolean(opened) }, segs, unmarked: !opened });
  }
  return out;
}

// Quality pairing for a plan: final-review findings, fix rounds, breaker
// items, deferred register rows, follow-up plan size and later fix commits.
function quality(opts, rowsOut, closeRows, planText) {
  const q = { findings: {}, fixRounds: rowsOut.reduce((s, r) => s + r.fixRounds, 0), breakerItems: 0, deferredRows: 0, followUpTasks: 0, fixCommits: 0 };
  const read = (f) => { try { return fs.readFileSync(f, 'utf8'); } catch { return null; } };
  const record = opts.reviewRecord && read(opts.reviewRecord);
  if (opts.reviewRecord && record === null) q.findings = null;
  // A review record keeps the findings as its retained lens lines; bracketed
  // tags are read only from a record that has none.
  const lens = record ? [...record.matchAll(/^final review lens \S+ — (\d+) Critical, (\d+) Important, (\d+) Minor/gm)] : [];
  if (lens.length) {
    for (const m of lens) ['Critical', 'Important', 'Minor'].forEach((k, i) => { q.findings[k] = (q.findings[k] || 0) + Number(m[i + 1]); });
  } else if (record) for (const m of record.matchAll(/\[(Critical|Important|Minor)\]/g)) q.findings[m[1]] = (q.findings[m[1]] || 0) + 1;
  const ledger = opts.ledger || (opts.workspace && path.join(opts.workspace, 'progress.md'));
  const progress = ledger && read(ledger);
  if (progress) q.breakerItems = (progress.match(/^Task \d+: fix round 3\/3 \(.*still failing\)/gm) || []).length;
  const register = opts.register && read(opts.register);
  if (register) {
    q.deferredRows = register.split(/\r?\n/).filter((l) => /^\|/.test(l) && l.split('|').some((c) => c.trim() === 'deferred')).length;
    const reg = path.basename(opts.register, '.md');
    // The register's name as a whole token: milestone-1 is not inside milestone-10.
    const named = new RegExp(`(^|[^A-Za-z0-9_.-])${reg.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}($|[^A-Za-z0-9_.-])`);
    if (opts.plan) {
      let names = [];
      try { names = fs.readdirSync(path.dirname(opts.plan)).filter((n) => n.endsWith('.md')); } catch { /* none */ }
      for (const n of names) {
        const f = path.join(path.dirname(opts.plan), n);
        if (path.resolve(f) === path.resolve(opts.plan)) continue;
        const t = read(f) || '';
        if (t.split(/\r?\n/).some((l) => l.startsWith('**Items:**') && named.test(l))) {
          q.followUpTasks += (t.match(/^### Task \d+:/gm) || []).length;
        }
      }
    }
  }
  const finish = Math.max(...closeRows.map((r) => ms(r.time)).filter(Number.isFinite));
  const files = [...new Set([...planText.matchAll(/^### Task (\d+):/gm)].flatMap((m) => planFiles(planText, m[1])))];
  for (const repo of opts.repo) {
    if (!Number.isFinite(finish) || !files.length || q.fixCommits === null) break;
    const inRange = new Set();
    for (const r of closeRows) {
      if (!/^[0-9a-f]+\.\.[0-9a-f]+$/.test(r.range || '')) continue;
      try {
        for (const h of execFileSync('git', ['-C', repo, 'rev-list', r.range], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).split('\n')) if (h) inRange.add(h);
      } catch { /* a range whose commits are gone excludes nothing */ }
    }
    try {
      const log = execFileSync('git', ['-c', 'core.quotePath=false', '-C', repo, 'log', baseBranch(repo), '--format=%x00%H %s', '--name-only',
        `--since=@${Math.floor(finish / 1000)}`, `--until=@${Math.floor(finish / 1000) + 7 * 86400}`], { encoding: 'utf8' });
      for (const chunk of log.split('\0').slice(1)) {
        const [head, ...paths] = chunk.split('\n').filter(Boolean);
        const [hash, ...subject] = head.split(' ');
        if (inRange.has(hash) || !/^fix(\(|:|!)/.test(subject.join(' '))) continue;
        if (paths.some((p) => files.some((f) => p === f || p.endsWith(`/${f}`)))) q.fixCommits++;
      }
    } catch { q.fixCommits = null; }
  }
  return q;
}

// The branch fix commits land on: the remote's default branch when its local
// copy exists, else main or master, else HEAD.
function baseBranch(repo) {
  const git = (...a) => { try { return execFileSync('git', ['-C', repo, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return ''; } };
  const remote = git('symbolic-ref', '--short', 'refs/remotes/origin/HEAD').replace(/^origin\//, '');
  for (const b of [remote, 'main', 'master']) if (b && git('rev-parse', '--verify', '--quiet', `refs/heads/${b}`)) return b;
  return 'HEAD';
}

export function reportPlan(plan, rows, opts, prices, foreign = new Map()) {
  const dirs = opts.transcripts;
  let planText = '';
  if (opts.plan) { try { planText = fs.readFileSync(opts.plan, 'utf8'); } catch { /* no plan */ } }
  const tasks = new Map();
  for (const r of rows) {
    if (!/^\d+$/.test(r.task)) continue;
    const t = tasks.get(r.task) || { n: Number(r.task), opens: [], close: null };
    if (r.event === 'close') { if (!t.close) t.close = r; } else if (!t.close) t.opens.push(r);
    tasks.set(r.task, t);
  }
  const excluded = [];
  const deferredSegs = [];
  let unclosed = 0;
  const closed = [];
  for (const t of [...tasks.values()].sort((a, b) => a.n - b.n)) {
    if (!t.close) { unclosed++; continue; }
    if (t.close.deferred === '1') {
      excluded.push(`Task ${t.n}: deferred by the auto run`);
      deferredSegs.push(...segments(t.opens, t.close, dirs));
      continue;
    }
    t.segs = segments(t.opens, t.close, dirs);
    closed.push(t);
  }
  const unresolved = (t) => t.segs.unresolved;
  // A ledger complete line with no markers: bounded by the transcripts' own
  // task-brief / task-step start / task-close calls.
  let unmarked = 0;
  for (const u of ledgerUnmarked(opts.ledger, tasks, plan, dirs)) {
    closed.push(u);
    if (u.close.inferred) unclosed--; else unmarked++;
  }
  for (const t of closed) {
    if (!unresolved(t)) continue;
    excluded.push(`Task ${t.n}: no transcript bounds its slice`);
    t.segs = Object.assign([], { unresolved: true });
  }
  closed.sort((a, b) => a.n - b.n);
  // Tasks whose segments overlap in one transcript form one group.
  const parent = new Map(closed.map((t) => [t.n, t.n]));
  const find = (n) => (parent.get(n) === n ? n : find(parent.get(n)));
  for (let i = 0; i < closed.length; i++) {
    for (let j = i + 1; j < closed.length; j++) {
      const hit = closed[i].segs.some((a) => closed[j].segs.some((b) => a.file === b.file && a.start < b.end && b.start < a.end));
      if (hit) parent.set(find(closed[j].n), find(closed[i].n));
    }
  }
  const groups = new Map();
  for (const t of closed) {
    const g = groups.get(find(t.n)) || [];
    g.push(t);
    groups.set(find(t.n), g);
  }
  const byModel = {};
  const inTasks = new Map();
  const outRows = [];
  const subs = new Map();
  for (const members of groups.values()) {
    const segs = members.flatMap((t) => t.segs);
    const files = [...new Set(segs.map((s) => s.file))];
    const unpriced = new Set();
    const entries = [];
    const parts = [];
    for (const f of files) {
      const all = readEntries(f) || [];
      const spans = mergeIntervals(segs.filter((s) => s.file === f));
      const kept = inTasks.get(f) || [];
      kept.push(...spans);
      inTasks.set(f, kept);
      const inSlice = (o) => spans.some((s) => o >= s.start && o < s.end);
      entries.push(...all.filter((x) => inSlice(x.offset)));
      parts.push([all, inSlice]);
    }
    const msgs = sliceMessages(parts);
    const main = total(msgs, prices, unpriced, byModel);
    const named = [...new Set(members.flatMap((t) => planFiles(planText, t.n)))];
    const lm = lookupMetrics(entries, named);
    const compactions = [];
    for (const f of files) {
      const all = readEntries(f) || [];
      const spans = mergeIntervals(segs.filter((x) => x.file === f));
      all.forEach((x, i) => {
        const e = x.entry;
        if (!(e && e.type === 'system' && e.subtype === 'compact_boundary') || !spans.some((sp) => x.offset >= sp.start && x.offset < sp.end)) return;
        const md = e.compactMetadata || {};
        const next = messages(all.slice(i + 1).filter((y) => y.entry && y.entry.type === 'assistant'), false)[0];
        compactions.push({ durationMs: md.durationMs ?? null, postTokens: md.postTokens ?? null, nextContext: next ? contextOf(next.usage) : null, file: f, offset: x.offset });
      });
    }
    const subagents = {};
    for (const f of files) {
      if (!subs.has(f)) subs.set(f, subagentFiles(f));
      for (const sa of subs.get(f)) {
        if (sa.taken || !segs.some((s) => s.file === f && sa.first >= s.from && sa.first <= s.to)) continue;
        sa.taken = true;
        const u = total(messages(sa.entries, true), prices, unpriced, byModel);
        const acc = subagents[sa.type] || (subagents[sa.type] = emptyUsage());
        for (const k of Object.keys(acc)) acc[k] += u[k];
      }
    }
    for (const u of Object.values(subagents)) u.cost = round6(u.cost);
    const subCost = Object.values(subagents).reduce((s, u) => s + u.cost, 0);
    const opens = members.flatMap((t) => t.opens).sort((a, b) => (a.time < b.time ? -1 : 1));
    const lastClose = members.map((t) => t.close).sort((a, b) => (a.time < b.time ? 1 : -1))[0];
    outRows.push({
      tasks: members.map((t) => t.n).sort((a, b) => a - b),
      label: members.some(unresolved) ? 'unresolved' : members.some((t) => t.unmarked) ? 'unmarked' : members.some((t) => t.close.inferred) ? 'inferred' : 'marked',
      group: members.length > 1,
      range: members.map((t) => t.close.range).filter(Boolean).join(', '),
      turns: main.turns,
      input: main.input,
      cacheRead: main.cacheRead,
      cacheWrite5m: main.cacheWrite5m,
      cacheWrite1h: main.cacheWrite1h,
      output: main.output,
      models: [...new Set(msgs.map((m) => m.model))].sort(),
      contextOpen: opens.length ? num(opens[0].context) : null,
      contextClose: num(lastClose.context),
      growth: growthOf(msgs),
      lookups: lm.lookups,
      readTokens: lm.readTokens,
      repeatReads: lm.repeatReads,
      filesLookupShare: lm.filesLookupShare,
      compactions,
      lookupsAfterCompaction: null,
      waitSeconds: lm.waitSeconds,
      dispatches: lm.dispatches,
      fixRounds: lm.fixRounds,
      start: Math.min(...segs.map((x) => (Number.isFinite(x.from) ? x.from : Infinity))),
      firstSeg: segs.map((x) => ({ file: x.file, start: x.start })),
      subagents,
      cost: round6(main.cost + subCost),
      unpriced: [...unpriced].sort(),
    });
  }
  outRows.sort((a, b) => a.tasks[0] - b.tasks[0]);
  // The first task to start after a compaction carries its lookups.
  const comps = outRows.flatMap((r) => r.compactions);
  for (const c of comps) {
    const after = outRows.filter((r) => r.firstSeg.some((x) => x.file === c.file && x.start > c.offset))
      .sort((a, b) => a.start - b.start)[0];
    if (after) after.lookupsAfterCompaction = after.lookups;
  }
  for (const r of outRows) {
    for (const c of r.compactions) { delete c.file; delete c.offset; }
    delete r.start; delete r.firstSeg;
  }
  // Usage in the same transcripts outside every task's slice, from each
  // transcript's first open on; what comes before it is excluded.
  // Another plan's slices in a shared transcript are not this plan's outside.
  for (const [f, list] of foreign) if (inTasks.has(f)) inTasks.set(f, [...inTasks.get(f), ...list]);
  // A deferred task's slice is neither a task's nor outside.
  for (const x of deferredSegs) inTasks.set(x.file, [...(inTasks.get(x.file) || []), { start: x.start, end: x.end }]);
  const firstOpen = new Map();
  const firstOpenAt = new Map();
  for (const x of [...closed.flatMap((t) => t.segs), ...deferredSegs]) {
    firstOpen.set(x.file, Math.min(firstOpen.get(x.file) ?? Infinity, x.start));
    firstOpenAt.set(x.file, Math.min(firstOpenAt.get(x.file) ?? Infinity, x.from));
  }
  const outsideMsgs = [];
  const outsideUnpriced = new Set();
  let before = 0;
  for (const [f, spans] of inTasks) {
    const all = readEntries(f) || [];
    const from = firstOpen.get(f) ?? 0;
    before += sliceMessages([[all, (o) => o < from]]).length;
    outsideMsgs.push(...sliceMessages([[all, (o) => o >= from && !spans.some((s) => o >= s.start && o < s.end)]]));
  }
  const outside = total(outsideMsgs, prices, outsideUnpriced, byModel);
  // A subagent no slice took is outside only when it started after the
  // transcript's first open and inside none of another plan's slices.
  for (const [f, list] of subs) {
    const others = foreign.get(f) || [];
    for (const sa of list) {
      if (sa.taken) continue;
      if (!(sa.first >= (firstOpenAt.get(f) ?? Infinity)) || others.some((s) => sa.first >= s.from && sa.first <= s.to)) {
        if (!(sa.first >= (firstOpenAt.get(f) ?? Infinity))) before++;
        continue;
      }
      const u = total(messages(sa.entries, true), prices, outsideUnpriced, byModel);
      for (const k of Object.keys(outside)) outside[k] += u[k];
    }
  }
  if (before) excluded.push('before first open');
  excluded.push('finishing session');
  outside.cost = round6(outside.cost);
  for (const u of Object.values(byModel)) u.cost = round6(u.cost);
  const completed = outRows.filter((r) => r.label !== 'unresolved').reduce((s, r) => s + r.tasks.length, 0);
  const segCost = outRows.reduce((s, r) => s + r.cost, 0);
  const planTotal = emptyUsage();
  for (const u of Object.values(byModel)) for (const k of Object.keys(planTotal)) planTotal[k] += u[k];
  planTotal.cost = round6(planTotal.cost);
  const file = rows[0] && rows[0].file;
  const repo = rows.find((r) => r.repo)?.repo
    || (file && /[\\/]sdd[\\/]usage-markers\.tsv$/.test(file) ? path.resolve(file, '..', '..', '..') : null);
  return {
    plan,
    repo,
    tasks: outRows,
    outside,
    costPerTask: completed ? round6((segCost + outside.cost) / completed) : null,
    costPerTaskSegments: completed ? round6(segCost / completed) : null,
    completed,
    unclosed,
    unmarked,
    excluded,
    byModel,
    byRepo: repo ? { [repo]: planTotal } : {},
    quality: quality(opts, outRows, rows.filter((r) => r.event === 'close'), planText),
    asOf: null,
  };
}

export function report(opts) {
  const prices = loadPrices();
  const archived = archiveRows(opts.fromArchive);
  archived.forEach((r, i) => { r.order = 1e15 + i; });
  const rows = [...readMarkers(opts.markers), ...archived]
    .sort((a, b) => (a.time < b.time ? -1 : a.time > b.time ? 1 : a.order - b.order));
  const byPlan = new Map();
  for (const r of rows) {
    const list = byPlan.get(r.plan) || [];
    list.push(r);
    byPlan.set(r.plan, list);
  }
  const spans = new Map([...byPlan].map(([plan, list]) => [plan, taskSpans(list, opts.transcripts)]));
  const wanted = (plan) => !opts.plan || plan === opts.plan || path.basename(plan) === path.basename(opts.plan);
  const saved = savedPlans(opts);
  return {
    plans: [...byPlan].filter(([plan]) => wanted(plan)).map(([plan, list]) => {
      const foreign = new Map();
      for (const [other, m] of spans) {
        if (other === plan) continue;
        for (const [f, l] of m) foreign.set(f, [...(foreign.get(f) || []), ...l]);
      }
      const rep = reportPlan(plan, list, opts, prices, foreign);
      // An archive holds gigabytes of transcripts: keep one plan's in memory.
      transcriptCache.clear();
      const kept = saved.find((p) => p && (p.plan === plan || path.basename(String(p.plan)) === path.basename(plan)));
      if (kept && kept.quality) Object.assign(rep, { quality: kept.quality, asOf: 'finishing' });
      return rep;
    }),
    ...(pricesError ? { pricesError } : {}),
  };
}

// The plans of the report finishing saved, read only once the ledger and the
// workspace are gone: until then the live quality fields are the newer ones.
function savedPlans(opts) {
  const gone = (f) => !f || !fs.existsSync(f);
  if (!opts.saved || !gone(opts.ledger) || !gone(opts.workspace)) return [];
  try {
    const plans = JSON.parse(fs.readFileSync(opts.saved, 'utf8')).plans;
    return Array.isArray(plans) ? plans : [];
  } catch { return []; }
}

const usd = (n) => (n === null ? '-' : `$${n.toFixed(2)}`);

export function markdown(rep) {
  const out = [];
  if (rep.pricesError) out.push(`Prices unreadable, every cost is unpriced: ${rep.pricesError}`, '');
  for (const p of rep.plans) {
    out.push(`## ${p.plan}`, '');
    out.push('| Task | Label | Turns | Input | Cache read | Write 5m | Write 1h | Output | Cost |');
    out.push('|---|---|---|---|---|---|---|---|---|');
    for (const r of p.tasks) {
      out.push(`| ${r.tasks.join(', ')} | ${r.label}${r.group ? ' (group)' : ''} | ${r.turns} | ${r.input} | ${r.cacheRead} | ${r.cacheWrite5m} | ${r.cacheWrite1h} | ${r.output} | ${usd(r.cost)}${r.unpriced.length ? ` (unpriced: ${r.unpriced.join(', ')})` : ''} |`);
    }
    out.push('', `Completed: ${p.completed}; unclosed: ${p.unclosed}; cost per task: ${p.costPerTask === null ? '-' : usd(p.costPerTask)}; outside tasks: ${usd(p.outside.cost)}`);
    for (const e of p.excluded) out.push(`Excluded: ${e}`);
    if (p.asOf) out.push(`Quality fields: as of ${p.asOf}`);
    out.push('');
  }
  return out.join('\n');
}

function main() {
  let opts;
  try { opts = parseArgs(process.argv.slice(2)); } catch (e) {
    if (!(e instanceof UsageError)) throw e;
    process.stderr.write(`usage-report: ${e.message}\n`);
    process.exit(2);
  }
  const rep = report(opts);
  process.stdout.write(opts.format === 'json' ? `${JSON.stringify(rep, null, 2)}\n` : `${markdown(rep)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) main();
