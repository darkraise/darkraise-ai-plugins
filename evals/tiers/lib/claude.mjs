import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PLUGIN, run } from './sh.mjs';

const LIMIT = /usage limit|rate limit|rate_limit|\b429\b|overloaded/i;
const BUDGET_USD = '5';

// agent ARM — an arm is an agent name, or `name@effort` to run that agent's
// body at another effort. The model and the default effort come from the
// agent's frontmatter; the body is everything after it.
export function agent(arm) {
  const [name, override] = arm.split('@');
  const text = readFileSync(resolve(PLUGIN, 'agents', `${name}.md`), 'utf8');
  const m = text.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!m) throw new Error(`${name}: no frontmatter`);
  const field = key => m[1].match(new RegExp(`^${key}:\\s*(\\S+)\\s*$`, 'm'))?.[1] ?? null;
  return { model: field('model'), effort: override ?? field('effort'), body: m[2].trim() + '\n' };
}

// invoke { model, effort, body, prompt, cwd, tools, seconds, dir } — one
// headless run. Resolves { kind, text, cost, seconds, turns, model } where
// kind is ok, timeout, budget, cut, limit or error. Raw output is kept in DIR.
export async function invoke({ model, effort, body, prompt, cwd, tools, seconds, dir }) {
  mkdirSync(dir, { recursive: true });
  const args = ['-p', '--model', model];
  if (effort) args.push('--effort', effort);
  if (body) {
    writeFileSync(join(dir, 'agent.md'), body);
    args.push('--append-system-prompt-file', join(dir, 'agent.md'));
  }
  args.push('--setting-sources', 'project', '--tools', tools.join(','));
  if (tools.length > 0) args.push('--allowedTools', tools.join(','), '--permission-mode', 'acceptEdits');
  args.push('--output-format', 'json', '--no-session-persistence', '--max-budget-usd', BUDGET_USD);
  writeFileSync(join(dir, 'prompt.txt'), prompt);
  const started = Date.now();
  // --setting-sources does not stop the user's global CLAUDE.md from loading.
  const env = { ...process.env, CLAUDE_CODE_DISABLE_CLAUDE_MDS: '1' };
  const r = await run(process.env.TIER_EVAL_CLAUDE ?? 'claude', args, { cwd, seconds, input: prompt, env });
  writeFileSync(join(dir, 'output.json'), r.out);
  writeFileSync(join(dir, 'stderr.txt'), r.err);
  return classify(r, (Date.now() - started) / 1000);
}

export function classify(r, elapsed) {
  const base = { text: '', cost: 0, seconds: Math.round(elapsed), turns: 0, model: '' };
  if (r.timedOut) return { ...base, kind: 'timeout' };
  let json = null;
  try {
    const parsed = JSON.parse(r.out);
    json = Array.isArray(parsed) ? parsed.findLast(e => e.type === 'result') : parsed;
  } catch {}
  if (!json) return { ...base, kind: LIMIT.test(r.out + r.err) ? 'limit' : 'error', text: (r.out + r.err).slice(-500) };
  const found = {
    text: json.result ?? '',
    cost: Number(json.total_cost_usd ?? 0),
    seconds: Math.round(elapsed),
    turns: Number(json.num_turns ?? 0),
    model: Object.keys(json.modelUsage ?? {}).sort().join('+'),
  };
  if (!json.is_error && r.code === 0) return { ...found, kind: 'ok' };
  // The budget stop is read first: its message may speak of a limit, and read
  // as a usage limit it would be retried at full price on every invocation.
  if (/budget/.test(json.subtype ?? '')) return { ...found, kind: 'budget' };
  if (LIMIT.test(`${json.result ?? ''} ${json.api_error_status ?? ''} ${r.err}`)) return { ...found, kind: 'limit' };
  // An error that arrives after the run spent something would be retried at
  // full price on every invocation, so it settles the cell as cut short.
  return { ...found, kind: found.cost > 0 ? 'cut' : 'error' };
}
