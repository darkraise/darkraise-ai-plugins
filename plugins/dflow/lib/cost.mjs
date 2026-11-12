import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

// Relative prices of the four token kinds against uncached input, so one
// number compares runs on the same model: cache reads cost a tenth, cache
// writes more than input, output five times input.
const WEIGHT = { input: 1, write5m: 1.25, write1h: 2, read: 0.1, output: 5 };

export function transcriptRoots(ctx) {
  if (ctx.env.DFLOW_TRANSCRIPTS) return [ctx.env.DFLOW_TRANSCRIPTS];
  const projects = path.join(ctx.env.CLAUDE_CONFIG_DIR || path.join(ctx.env.HOME || os.homedir(), '.claude'), 'projects');
  const encoded = ctx.root.replace(/[^A-Za-z0-9]/g, '-');
  if (!fs.existsSync(projects)) return [];
  // Sessions started in a subdirectory or in a worktree of this repository
  // are stored under a name that extends the repository's own.
  return fs.readdirSync(projects).filter(name => name === encoded || name.startsWith(`${encoded}-`)).map(name => path.join(projects, name));
}

function transcriptFiles(directory) {
  const files = [];
  if (!fs.existsSync(directory)) return files;
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const full = path.join(directory, entry.name);
    if (entry.isFile() && entry.name.endsWith('.jsonl')) files.push({ file: full, agent: null });
    const subagents = path.join(full, 'subagents');
    if (!entry.isDirectory() || !fs.existsSync(subagents)) continue;
    for (const name of fs.readdirSync(subagents).filter(candidate => candidate.endsWith('.jsonl'))) {
      let agent = 'subagent';
      try {
        agent = JSON.parse(fs.readFileSync(path.join(subagents, name.replace(/\.jsonl$/, '.meta.json')), 'utf8')).agentType ?? agent;
      } catch {
        // No meta file: the run still counts, under the generic name.
      }
      files.push({ file: path.join(subagents, name), agent });
    }
  }
  return files;
}

// One record per API response. A streamed response is written several times
// under one message id, so the largest output count per id is kept.
export function readUsage(ctx, { from, to, branch }) {
  const byId = new Map();
  for (const directory of transcriptRoots(ctx)) {
    for (const { file, agent } of transcriptFiles(directory)) {
      for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
        if (!line.includes('"usage"')) continue;
        let entry;
        try {
          entry = JSON.parse(line);
        } catch {
          continue;
        }
        const usage = entry.message?.usage;
        const at = Date.parse(entry.timestamp);
        if (entry.type !== 'assistant' || !usage || !(at >= from && at <= to)) continue;
        if (branch && entry.gitBranch && entry.gitBranch !== branch) continue;
        const id = entry.message.id ?? entry.uuid;
        const known = byId.get(id);
        if (known && known.output >= (usage.output_tokens ?? 0)) continue;
        const write1h = usage.cache_creation?.ephemeral_1h_input_tokens ?? 0;
        byId.set(id, {
          at, agent, model: entry.message.model ?? 'unknown',
          input: usage.input_tokens ?? 0,
          write1h,
          write5m: (usage.cache_creation_input_tokens ?? 0) - write1h,
          read: usage.cache_read_input_tokens ?? 0,
          output: usage.output_tokens ?? 0,
        });
      }
    }
  }
  return [...byId.values()].sort((left, right) => left.at - right.at);
}

export function emptyTotals() {
  return { requests: 0, input: 0, write: 0, read: 0, output: 0, equivalent: 0 };
}

export function addTo(totals, record) {
  totals.requests += 1;
  totals.input += record.input;
  totals.write += record.write1h + record.write5m;
  totals.read += record.read;
  totals.output += record.output;
  totals.equivalent += Object.keys(WEIGHT).reduce((sum, key) => sum + WEIGHT[key] * record[key], 0);
  return totals;
}

// plan: up to approval; build: up to the last finished task; review and
// ship: after it.
export function phaseBounds(events) {
  const time = name => events.filter(event => event.event === name).map(event => Date.parse(event.at));
  const first = Math.min(...events.map(event => Date.parse(event.at)));
  const approved = time('approved')[0] ?? first;
  const built = Math.max(approved, ...time('done'));
  const shipped = time('shipped').at(-1) ?? null;
  return { first, approved, built, shipped };
}

export function summarise(records, bounds) {
  const phases = { plan: emptyTotals(), build: emptyTotals(), 'review and ship': emptyTotals() };
  const models = {};
  const agents = {};
  const total = emptyTotals();
  let mainContext = 0;
  let mainRequests = 0;
  for (const record of records) {
    const phase = record.at < bounds.approved ? 'plan' : record.at <= bounds.built ? 'build' : 'review and ship';
    addTo(phases[phase], record);
    addTo(models[record.model] ??= emptyTotals(), record);
    addTo(total, record);
    if (record.agent) addTo(agents[record.agent] ??= emptyTotals(), record);
    else {
      mainRequests += 1;
      mainContext += record.input + record.read + record.write1h + record.write5m;
    }
  }
  return { phases, models, agents, total, averageContext: mainRequests ? Math.round(mainContext / mainRequests) : 0 };
}
