// USD per million tokens, from https://platform.claude.com/docs/en/about-claude/pricing
// as fetched on 2026-10-17. A model not listed is named in `unpriced`, and its
// tokens are counted but not priced.
export const PRICES = {
  'claude-opus-5-5': { input: 4, write5m: 5, write1h: 8, read: 0.2, output: 20 },
  'claude-sonnet-5-5': { input: 2, write5m: 2.5, write1h: 4, read: 0.1, output: 10 },
};

const METERS = ['input', 'write5m', 'write1h', 'read', 'output'];
const COUNTS = ['calls', ...METERS, 'cost', 'dispatches', 'sleeps', 'listAgents', 'monitors', 'nudges', 'seatMisses'];
const NAMES = ['models', 'efforts', 'unpriced', 'completed'];
// What an owner types when the controller has lost track of its background work.
const NUDGE = /check (the )?status|still running|anything (still )?running/i;
const SLEEP = /^\s*sleep\s+[\d.]+\s*;?\s*$/;
const SEAT = /^review-seat (\S+) .*primary=(\S+) fallback=(\S+)/gm;
// A ledger line the controller wrote; a task the auto run deferred is not done.
const COMPLETE = /(?:^|[\s'"])Task (\d+): complete \((?!deferred by the auto run\))/g;
const isAgent = use => use.name === 'Agent' || use.name === 'Task';
const byNumber = list => [...new Set(list)].sort((a, b) => Number(a) - Number(b));

export function priceOf(model) {
  const key = Object.keys(PRICES).find(k => model === k || model.startsWith(`${k}-`));
  return key === undefined ? null : PRICES[key];
}

function textOf(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) return content.map(c => (typeof c?.text === 'string' ? c.text : '')).join('\n');
  return '';
}

// The text a tool call writes into a ledger (progress.md), or ''.
function ledgerText(use) {
  const input = use.input ?? {};
  // A Bash command that only reads the ledger (grep, cat) writes nothing into it.
  if (use.name === 'Bash') return /progress\.md/.test(String(input.command ?? '')) && /(>|\btee\b|<<)/.test(String(input.command)) ? String(input.command) : '';
  if (!/progress\.md$/.test(String(input.file_path ?? ''))) return '';
  if (use.name === 'Write') return String(input.content ?? '');
  if (use.name === 'Edit') return String(input.new_string ?? '');
  if (use.name === 'MultiEdit') return (input.edits ?? []).map(e => String(e?.new_string ?? '')).join('\n');
  return '';
}

// measureTranscript SOURCE — one session's metrics from its JSONL transcript.
// Claude Code writes one record per content block, so a message's usage
// repeats under one id: each id is counted once, from its last record.
export function measureTranscript(source) {
  const usage = new Map();
  const uses = new Map();
  const results = new Map();
  const models = new Set();
  const efforts = new Set();
  let nudges = 0;
  let last = '';
  for (const line of source.split('\n')) {
    let r;
    try { r = JSON.parse(line); } catch { continue; }
    if (typeof r?.timestamp === 'string' && r.timestamp > last) last = r.timestamp;
    const m = r?.message;
    // A <synthetic> message is written by Claude Code itself and was never billed.
    if (r?.type === 'assistant' && m?.id && m.usage && !String(m.model ?? '').startsWith('<')) {
      usage.set(m.id, { model: m.model ?? '', usage: m.usage });
      if (m.model) models.add(m.model);
      if (r.effort) efforts.add(r.effort);
    }
    if (r?.type === 'assistant' && Array.isArray(m?.content)) {
      for (const c of m.content) if (c?.type === 'tool_use') uses.set(c.id, c);
    }
    if (r?.type === 'user' && Array.isArray(m?.content)) {
      for (const c of m.content) if (c?.type === 'tool_result') results.set(c.tool_use_id, textOf(c.content));
    }
    // Skill bodies and command wrappers arrive as user records too; only what
    // a person typed counts.
    if (r?.type === 'user' && typeof m?.content === 'string' && !r.isMeta && !m.content.startsWith('<') && NUDGE.test(m.content)) nudges++;
  }

  const out = { models: [...models].sort(), efforts: [...efforts].sort(), unpriced: [], completed: [], last, calls: usage.size };
  for (const k of [...METERS, 'cost']) out[k] = 0;
  const unpriced = new Set();
  for (const { model, usage: u } of usage.values()) {
    const split = u.cache_creation;
    const n = {
      input: u.input_tokens ?? 0,
      write5m: split ? split.ephemeral_5m_input_tokens ?? 0 : u.cache_creation_input_tokens ?? 0,
      write1h: split ? split.ephemeral_1h_input_tokens ?? 0 : 0,
      read: u.cache_read_input_tokens ?? 0,
      output: u.output_tokens ?? 0,
    };
    for (const k of METERS) out[k] += n[k];
    const price = priceOf(model);
    if (price !== null) out.cost += METERS.reduce((sum, k) => sum + n[k] * price[k], 0) / 1e6;
    else if (METERS.some(k => n[k] > 0)) unpriced.add(model);
  }
  out.unpriced = [...unpriced].sort();

  let dispatches = 0, sleeps = 0, listAgents = 0, monitors = 0, seatMisses = 0;
  const completed = [];
  // Routes wait in print order, a review route for the next review dispatch
  // and a final-fix route for the next implementer dispatch; each dispatch
  // answers the oldest route of its kind. A dispatch with no route waiting (a
  // header amendment's confirmation, a task's implementer) is unrouted and
  // never a miss.
  const waiting = { review: [], fix: [] };
  for (const use of uses.values()) {
    const cmd = use.name === 'Bash' ? String(use.input?.command ?? '') : '';
    const type = isAgent(use) ? String(use.input?.subagent_type ?? '') : '';
    if (isAgent(use) || /run-codex-(task|review)\.sh/.test(cmd)) dispatches++;
    if (SLEEP.test(cmd)) sleeps++;
    if (use.name === 'ListAgents') listAgents++;
    if (use.name === 'Monitor') monitors++;
    for (const hit of ledgerText(use).matchAll(COMPLETE)) completed.push(hit[1]);
    let seat = null;
    if (/run-codex-review\.sh/.test(cmd) || /judge-/.test(type)) seat = { kind: 'review', name: type || 'codex' };
    else if (/run-codex-task\.sh/.test(cmd) || /impl-/.test(type)) seat = { kind: 'fix', name: type || 'codex' };
    if (seat !== null && waiting[seat.kind].length > 0) {
      const route = waiting[seat.kind].shift();
      const fits = route.primary.startsWith('codex:') ? seat.name === 'codex' || seat.name === route.fallback : seat.name === route.primary;
      if (!fits) seatMisses++;
    }
    if (/review-route/.test(cmd)) {
      for (const hit of (results.get(use.id) ?? '').matchAll(SEAT)) {
        const queue = waiting[hit[1] === 'final-fix' || /impl-/.test(hit[2]) ? 'fix' : 'review'];
        // A route printed again for a scope still waiting is a re-query, not a second review.
        const again = queue.findIndex(route => route.scope === hit[1]);
        const route = { scope: hit[1], primary: hit[2], fallback: hit[3] };
        if (again === -1) queue.push(route);
        else queue[again] = route;
      }
    }
  }
  seatMisses += waiting.review.length + waiting.fix.length;
  out.completed = byNumber(completed);
  return { ...out, dispatches, sleeps, listAgents, monitors, nudges, seatMisses };
}

// sumMetrics LIST — the metrics of several transcripts added together.
export function sumMetrics(list) {
  const total = measureTranscript('');
  for (const m of list) {
    for (const k of COUNTS) total[k] += m[k];
    for (const k of NAMES) total[k] = k === 'completed' ? byNumber([...total[k], ...m[k]]) : [...new Set([...total[k], ...m[k]])].sort();
    if (m.last > total.last) total.last = m.last;
  }
  return total;
}
