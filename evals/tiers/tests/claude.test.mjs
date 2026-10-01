import assert from 'node:assert/strict';
import { readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { fixture, modes } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { agent, classify, invoke } = await import('../lib/claude.mjs');
const lastCall = () => JSON.parse(readFileSync(join(fx.stub, 'calls.log'), 'utf8').trim().split('\n').at(-1));

test('agent reads the model, the effort and the body, and an arm can override the effort', () => {
  const high = agent('impl-sonnet-high');
  assert.deepEqual([high.model, high.effort], ['sonnet', 'high']);
  assert.match(high.body, /^You are a task implementer\./);
  assert.doesNotMatch(high.body, /^---|^model:/m);
  assert.deepEqual([agent('judge-opus@medium').model, agent('judge-opus@medium').effort], ['opus', 'medium']);
  assert.deepEqual([agent('impl-haiku').model, agent('impl-haiku').effort], ['haiku', null]);
});

test('classify tells a limit, a budget stop, an error and a timeout apart', () => {
  const run = (out, extra = {}) => classify({ out, err: '', code: 0, timedOut: false, ...extra }, 2);
  assert.equal(run(JSON.stringify({ result: 'hi', total_cost_usd: 0.25, num_turns: 2, modelUsage: { m: {} } })).kind, 'ok');
  assert.deepEqual(run(JSON.stringify([{ type: 'system' }, { type: 'result', result: 'hi', total_cost_usd: 0.25, num_turns: 2, modelUsage: { b: {}, a: {} } }])),
    { kind: 'ok', text: 'hi', cost: 0.25, seconds: 2, turns: 2, model: 'a+b' });
  assert.equal(run(JSON.stringify({ is_error: true, result: "You've hit your usage limit" }), { code: 1 }).kind, 'limit');
  assert.equal(run(JSON.stringify({ is_error: true, subtype: 'error_max_budget_usd' }), { code: 1 }).kind, 'budget');
  assert.equal(run(JSON.stringify({ is_error: true, subtype: 'error_max_budget_usd', result: 'Reached the budget: usage limit of $5', total_cost_usd: 5.1 }), { code: 1 }).kind, 'budget');
  assert.equal(run(JSON.stringify({ is_error: true, result: 'Budget limit reached', total_cost_usd: 5.1 }), { code: 1 }).kind, 'cut');
  assert.equal(run(JSON.stringify({ is_error: true, result: 'bad flag' }), { code: 1 }).kind, 'error');
  assert.equal(run(JSON.stringify({ is_error: true, subtype: 'error_during_execution', total_cost_usd: 1.5 }), { code: 1 }).kind, 'cut');
  assert.equal(run(JSON.stringify({ is_error: true, result: 'API Error: overloaded', total_cost_usd: 1.5 }), { code: 1 }).kind, 'limit');
  assert.equal(run('not json', { code: 1 }).kind, 'error');
  assert.equal(run('API Error: 429 rate limit', { code: 1 }).kind, 'limit');
  assert.equal(run('', { timedOut: true }).kind, 'timeout');
});

test('invoke passes the arm and the isolation flags, and keeps the raw output', async () => {
  modes(fx.stub, 'blocked');
  const dir = join(fx.work, 'call');
  const inv = await invoke({ ...agent('impl-sonnet-low'), prompt: 'do it', cwd: fx.repo, tools: ['Bash', 'Read'], seconds: 60, dir });
  assert.deepEqual([inv.kind, inv.cost, inv.turns, inv.model], ['ok', 0.5, 3, 'stub-model']);
  assert.match(inv.text, /BLOCKED/);
  const call = lastCall();
  assert.deepEqual(call.args, ['-p', '--model', 'sonnet', '--effort', 'low', '--append-system-prompt-file', join(dir, 'agent.md'),
    '--setting-sources', 'project', '--tools', 'Bash,Read', '--allowedTools', 'Bash,Read', '--permission-mode', 'acceptEdits',
    '--output-format', 'json', '--no-session-persistence', '--max-budget-usd', '5']);
  assert.deepEqual([call.prompt, call.cwd], ['do it', fx.repo]);
  assert.match(readFileSync(join(dir, 'agent.md'), 'utf8'), /^You are a task implementer\./);
  assert.match(readFileSync(join(dir, 'output.json'), 'utf8'), /"result"/);
});

test('invoke omits the effort, the body and the permission flags when there are none', async () => {
  modes(fx.stub, 'limit');
  const inv = await invoke({ model: 'opus', effort: null, body: null, prompt: 'grade', cwd: fx.repo, tools: [], seconds: 60, dir: join(fx.work, 'bare') });
  assert.equal(inv.kind, 'limit');
  assert.deepEqual(lastCall().args, ['-p', '--model', 'opus', '--setting-sources', 'project', '--tools', '', '--output-format', 'json', '--no-session-persistence', '--max-budget-usd', '5']);
});
