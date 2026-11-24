#!/usr/bin/env node
// Per-task usage from task markers: slices Claude transcripts at the byte
// offsets the open and close markers recorded, prices each slice, and reports
// one row per task (or per group of tasks whose slices overlap).
// Arguments, exit codes and the JSON shape: the plugin's usage-report wrapper.
import fs from 'node:fs';
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

export function loadPrices(file = PRICES) {
  try {
    const models = JSON.parse(fs.readFileSync(file, 'utf8')).models || {};
    return Object.fromEntries(Object.entries(models).filter(([, r]) => r.provider === 'anthropic'));
  } catch { return {}; }
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
function messages(entries, sidechain) {
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

// Totals of a message list, priced; unpriced models are collected.
function total(msgs, prices, unpriced, byModel) {
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
    if (!file) continue;
    const same = session === close.session;
    segs.push({
      file,
      start: o ? num(o.bytes) || 0 : 0,
      end: same ? num(close.bytes) ?? Infinity : Infinity,
      from: o ? ms(o.time) : -Infinity,
      to: same ? ms(close.time) : Infinity,
    });
  }
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

export function reportPlan(plan, rows, opts, prices) {
  const dirs = opts.transcripts;
  const tasks = new Map();
  for (const r of rows) {
    if (!/^\d+$/.test(r.task)) continue;
    const t = tasks.get(r.task) || { n: Number(r.task), opens: [], close: null };
    if (r.event === 'close') { if (!t.close) t.close = r; } else if (!t.close) t.opens.push(r);
    tasks.set(r.task, t);
  }
  const excluded = [];
  let unclosed = 0;
  const closed = [];
  for (const t of [...tasks.values()].sort((a, b) => a.n - b.n)) {
    if (!t.close) { unclosed++; continue; }
    if (t.close.deferred === '1') { excluded.push(`Task ${t.n}: deferred by the auto run`); continue; }
    t.segs = segments(t.opens, t.close, dirs);
    closed.push(t);
  }
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
    for (const f of files) {
      const all = readEntries(f) || [];
      const spans = mergeIntervals(segs.filter((s) => s.file === f));
      const kept = inTasks.get(f) || [];
      kept.push(...spans);
      inTasks.set(f, kept);
      entries.push(...all.filter((x) => spans.some((s) => x.offset >= s.start && x.offset < s.end)));
    }
    const msgs = messages(entries, false);
    const main = total(msgs, prices, unpriced, byModel);
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
      label: 'marked',
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
      subagents,
      cost: round6(main.cost + subCost),
      unpriced: [...unpriced].sort(),
    });
  }
  outRows.sort((a, b) => a.tasks[0] - b.tasks[0]);
  // Usage in the same transcripts outside every task's slice.
  const outsideMsgs = [];
  const outsideUnpriced = new Set();
  for (const [f, spans] of inTasks) {
    const all = readEntries(f) || [];
    outsideMsgs.push(...messages(all.filter((x) => !spans.some((s) => x.offset >= s.start && x.offset < s.end)), false));
  }
  const outside = total(outsideMsgs, prices, outsideUnpriced, null);
  for (const list of subs.values()) {
    for (const sa of list) {
      if (sa.taken) continue;
      const u = total(messages(sa.entries, true), prices, outsideUnpriced, null);
      for (const k of Object.keys(outside)) outside[k] += u[k];
    }
  }
  outside.cost = round6(outside.cost);
  for (const u of Object.values(byModel)) u.cost = round6(u.cost);
  const completed = outRows.reduce((s, r) => s + r.tasks.length, 0);
  const file = rows[0] && rows[0].file;
  const repo = file && /[\\/]sdd[\\/]usage-markers\.tsv$/.test(file) ? path.resolve(file, '..', '..', '..') : null;
  return {
    plan,
    repo,
    tasks: outRows,
    outside,
    costPerTask: completed ? round6(outRows.reduce((s, r) => s + r.cost, 0) / completed) : null,
    completed,
    unclosed,
    excluded,
    byModel,
    asOf: null,
  };
}

export function report(opts) {
  const prices = loadPrices();
  const rows = readMarkers(opts.markers);
  const byPlan = new Map();
  for (const r of rows) {
    if (opts.plan && r.plan !== opts.plan && path.basename(r.plan) !== path.basename(opts.plan)) continue;
    const list = byPlan.get(r.plan) || [];
    list.push(r);
    byPlan.set(r.plan, list);
  }
  return { plans: [...byPlan].map(([plan, list]) => reportPlan(plan, list, opts, prices)) };
}

const usd = (n) => (n === null ? '-' : `$${n.toFixed(2)}`);

export function markdown(rep) {
  const out = [];
  for (const p of rep.plans) {
    out.push(`## ${p.plan}`, '');
    out.push('| Task | Label | Turns | Input | Cache read | Write 5m | Write 1h | Output | Cost |');
    out.push('|---|---|---|---|---|---|---|---|---|');
    for (const r of p.tasks) {
      out.push(`| ${r.tasks.join(', ')} | ${r.label}${r.group ? ' (group)' : ''} | ${r.turns} | ${r.input} | ${r.cacheRead} | ${r.cacheWrite5m} | ${r.cacheWrite1h} | ${r.output} | ${usd(r.cost)}${r.unpriced.length ? ` (unpriced: ${r.unpriced.join(', ')})` : ''} |`);
    }
    out.push('', `Completed: ${p.completed}; unclosed: ${p.unclosed}; cost per task: ${p.costPerTask === null ? '-' : usd(p.costPerTask)}; outside tasks: ${usd(p.outside.cost)}`);
    for (const e of p.excluded) out.push(`Excluded: ${e}`);
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
