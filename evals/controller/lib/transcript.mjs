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
// A shell redirect or tee into the ledger, by path or by a variable set in the same command; `2>/dev/null` on a grep is not one.
const WRITES_LEDGER = /(?:>>?|\btee\b(?:\s+-a)?)\s*['"]?(?:[^\s'";&|]*progress\.md|\$\{?\w+)/;
// The wrapper's operations that launch nothing.
const CODEX_CONTROL = /--(?:dry-run|recover-commit|handback|release|amend-write-set|accept-baseline)\b/;
// Only a command that launches a run counts: naming a runner in cat, grep or ps does not.
const isCodexTask = cmd => /run-codex-task\.sh|scripts\/executors['"]?\s+path\s+\S+\s+wrapper/.test(cmd) && /--brief\b/.test(cmd) && !CODEX_CONTROL.test(cmd);
const codexReviewTier = cmd => (/run-codex-review\.sh/.test(cmd) && /--kind\b/.test(cmd) ? cmd.match(/--tier\s+(\w+)/)?.[1] ?? 'heavy' : null);
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

// shellLists CMD — CMD cut at its list separators outside quotes: `;`, a
// newline, and an `&` that is not part of `&&` or a redirect (`2>&1`, `&>`).
// A newline after a trailing `&&`, `||` or `|` continues the list. A `{ … }`
// or `( … )` group is part of the list that opened it, and each list inside
// it is also given on its own, led by the text before and including the
// group's opener, so an `&&` ahead of the group still gates what it holds.
// A heredoc's body, on the lines after its opener, is appended to the list
// that opened it, even when more lists follow the opener on its line. The
// delimiter is the whole word after << or <<-, quoted ('END-OF-DOC') or not.
function shellLists(cmd) {
  const lists = [];
  const groups = [];
  const pending = [];
  let list = { lead: '', start: 0, body: '', close: '' };
  let quote = '';
  const cut = (at, next) => {
    list.text = list.lead + cmd.slice(list.start, at);
    lists.push(list);
    list = next ?? { lead: list.lead, start: at + 1, body: '', close: list.close };
  };
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i];
    if (quote) {
      if (c === quote) quote = '';
      else if (c === '\\' && quote === '"') i++;
    } else if (c === "'" || c === '"') quote = c;
    else if (c === '\\') i++;
    else if (cmd.startsWith('<<', i)) {
      const opener = /^<<(-)?[ \t]*(?:'([^'\n]*)'|"([^"\n]*)"|([^\s;&|<>()'"]+))/.exec(cmd.slice(i));
      if (opener) pending.push({ owner: list, word: opener[2] ?? opener[3] ?? opener[4], tabs: opener[1] === '-' });
      i += opener ? opener[0].length - 1 : 1;
    } else if (c === '(' || (c === '{' && /^[\s;&|(]?$/.test(cmd[i - 1] ?? '') && /\s/.test(cmd[i + 1] ?? ''))) {
      groups.push(list);
      list = { lead: list.lead + cmd.slice(list.start, i + 1), start: i + 1, body: '', close: c === '(' ? ')' : '}' };
    } else if (list.close === ')' && c === ')') cut(i, groups.pop());
    else if (list.close === '}' && c === '}' && cmd.slice(list.start, i).trim() === '' && /^[\s;&|)]?$/.test(cmd[i + 1] ?? '')) cut(i, groups.pop());
    else if (c === '\n' || c === ';' || (c === '&' && !/[&<>|]/.test(cmd[i - 1] ?? '') && !/[&>]/.test(cmd[i + 1] ?? ''))) {
      const at = i;
      if (c === '\n') {
        for (const { owner, word, tabs } of pending.splice(0)) {
          const quoted = word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
          const end = new RegExp(`\\n${tabs ? '\\t*' : ''}${quoted}(?=\\n|$)`).exec(cmd.slice(i));
          const stop = end ? i + end.index + end[0].length : cmd.length;
          owner.body += cmd.slice(i, stop);
          i = stop;
        }
        if (/(?:&&|\|)[ \t]*$/.test(cmd.slice(list.start, at))) continue;
      }
      cut(at);
      list.start = i + 1;
    }
  }
  // A group left open at the end closes there, its own lists first.
  for (;;) {
    list.text = list.lead + cmd.slice(list.start);
    lists.push(list);
    if (groups.length === 0) break;
    list = groups.pop();
  }
  return lists.map(l => l.text + l.body);
}

// ledgerWrites CMD — the lists of a failed Bash command that still wrote the
// ledger: the call's error is only its last command's exit status, so a list
// wrote unless an `&&` ahead of its redirect let an earlier failure skip it.
function ledgerWrites(cmd) {
  return shellLists(cmd).filter(list => {
    const at = list.search(WRITES_LEDGER);
    return at !== -1 && !/&&/.test(list.slice(0, at));
  }).join('\n');
}

// The text a tool call writes into a ledger (progress.md), or ''.
function ledgerText(use) {
  const input = use.input ?? {};
  // A Bash command that only reads the ledger (grep, cat) writes nothing into it.
  if (use.name === 'Bash') {
    const cmd = String(input.command ?? '');
    return /progress\.md/.test(cmd) && WRITES_LEDGER.test(cmd) ? cmd : '';
  }
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
  const failed = new Set();
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
      for (const c of m.content) {
        if (c?.type !== 'tool_result') continue;
        results.set(c.tool_use_id, textOf(c.content));
        if (c.is_error) failed.add(c.tool_use_id);
      }
    }
    // Skill bodies and command wrappers arrive as user records too; only what
    // a person typed counts, as a string or as text blocks beside an attachment.
    if (r?.type === 'user' && !r.isMeta) {
      const typed = typeof m?.content === 'string' ? [m.content] : Array.isArray(m?.content) ? m.content.filter(c => c?.type === 'text' && typeof c.text === 'string').map(c => c.text) : [];
      if (typed.some(text => !text.startsWith('<') && NUDGE.test(text))) nudges++;
    }
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
    const tier = codexReviewTier(cmd);
    if (isAgent(use) || isCodexTask(cmd) || tier !== null) dispatches++;
    if (SLEEP.test(cmd)) sleeps++;
    if (use.name === 'ListAgents') listAgents++;
    if (use.name === 'Monitor') monitors++;
    // A write that failed (an Edit whose old string was not found) recorded
    // nothing; a failed Bash call recorded what its lists wrote (ledgerWrites).
    const written = !failed.has(use.id) ? ledgerText(use) : use.name === 'Bash' && ledgerText(use) !== '' ? ledgerWrites(cmd) : '';
    for (const hit of written.matchAll(COMPLETE)) completed.push(hit[1]);
    let seat = null;
    if (tier !== null || /judge-/.test(type)) seat = { kind: 'review', name: type || `codex:${tier}` };
    else if (isCodexTask(cmd) || /impl-/.test(type)) seat = { kind: 'fix', name: type || 'codex' };
    if (seat !== null && waiting[seat.kind].length > 0) {
      const route = waiting[seat.kind].shift();
      const fits = route.primary.startsWith('codex:') ? route.primary.startsWith(seat.name) || seat.name === route.fallback : seat.name === route.primary;
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
