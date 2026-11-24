// run-totals CORE TRANSCRIPTS — one run's whole usage and dispatch counts as
// JSON: every session transcript collect copied and each one's subagents,
// inside a task's slice or not. The report's per-task rows leave out the work
// before the first task opens and after the last one closes, where one arm
// may spend what the other spends inside its tasks.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [core, dir] = process.argv.slice(2);
const { loadPrices, readEntries, messages, total, lookupMetrics } = await import(pathToFileURL(path.resolve(core)).href);
const prices = loadPrices();
const unpriced = new Set();
const main = total([], prices, unpriced);
const subagents = total([], prices, unpriced);
const dispatches = {};
const add = (into, u) => { for (const k of Object.keys(into)) into[k] += u[k]; };
const count = (entries) => {
  for (const [k, n] of Object.entries(lookupMetrics(entries, []).dispatches)) dispatches[k] = (dispatches[k] || 0) + n;
};
const jsonl = (d) => (fs.existsSync(d) ? fs.readdirSync(d).filter((f) => f.endsWith('.jsonl')).sort() : []);
for (const name of jsonl(dir)) {
  const entries = readEntries(path.join(dir, name)) || [];
  add(main, total(messages(entries, false), prices, unpriced));
  count(entries);
  const subDir = path.join(dir, name.slice(0, -'.jsonl'.length), 'subagents');
  for (const sub of jsonl(subDir)) {
    const subEntries = readEntries(path.join(subDir, sub)) || [];
    add(subagents, total(messages(subEntries, true), prices, unpriced));
    count(subEntries);
  }
}
const round6 = (x) => Math.round(x * 1e6) / 1e6;
const all = { ...main };
add(all, subagents);
for (const u of [main, subagents, all]) u.cost = round6(u.cost);
process.stdout.write(`${JSON.stringify({ total: all, main, subagents, dispatches, unpriced: [...unpriced].sort() }, null, 2)}\n`);
