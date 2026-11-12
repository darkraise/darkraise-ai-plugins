import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { dflow, makeProject, write } from './helpers.mjs';

const usage = (id, timestamp, tokens, extra = {}) => JSON.stringify({
  type: 'assistant', timestamp, gitBranch: 'feat/x', ...extra,
  message: { id, model: extra.model ?? 'claude-opus-5-5', usage: { input_tokens: tokens.input ?? 0, cache_read_input_tokens: tokens.read ?? 0, cache_creation_input_tokens: tokens.write ?? 0, cache_creation: { ephemeral_1h_input_tokens: tokens.write1h ?? 0 }, output_tokens: tokens.output ?? 0 } },
});

test('cost sums usage once per message id, by phase and model, with subagents', t => {
  const root = makeProject(t);
  const event = (at, name, fields = {}) => JSON.stringify({ at, plan: '2026-11-12-meter', event: name, ...fields });
  write(root, '.dflow/events.jsonl', [
    event('2026-11-12T10:00:00.000Z', 'planned'),
    event('2026-11-12T11:00:00.000Z', 'approved'),
    event('2026-11-12T12:00:00.000Z', 'done', { task: 1 }),
    event('2026-11-12T13:00:00.000Z', 'done', { task: 2 }),
    event('2026-11-12T14:00:00.000Z', 'shipped'),
  ].join('\n'));
  const store = path.join(root, '.transcripts/project');
  write(root, '.transcripts/project/session.jsonl', [
    usage('m0', '2026-11-12T09:00:00.000Z', { input: 999 }),
    usage('m1', '2026-11-12T10:30:00.000Z', { input: 100, read: 1000, output: 10 }),
    usage('m2', '2026-11-12T11:30:00.000Z', { input: 10, read: 20000, write: 400, write1h: 400, output: 5 }),
    usage('m2', '2026-11-12T11:30:01.000Z', { input: 10, read: 20000, write: 400, write1h: 400, output: 50 }),
    usage('m3', '2026-11-12T13:30:00.000Z', { input: 5, read: 30000, output: 20 }),
    usage('m4', '2026-11-12T11:40:00.000Z', { input: 7 }, { gitBranch: 'other' }),
    usage('m5', '2026-11-12T15:00:00.000Z', { input: 999 }),
    'not json',
  ].join('\n'));
  // A sibling repository whose encoded name extends this one's is not this one.
  write(root, '.transcripts/project/sibling.jsonl', usage('x1', '2026-11-12T11:45:00.000Z', { input: 5000 }, { cwd: `${root}-web` }));
  write(root, '.transcripts/project/inside.jsonl', usage('x2', '2026-11-12T09:30:00.000Z', { input: 1 }, { cwd: `${root}/src` }));
  write(root, '.transcripts/project/session/subagents/agent-a1.jsonl', usage('s1', '2026-11-12T12:30:00.000Z', { input: 50, write: 2000, output: 100 }, { model: 'claude-sonnet-5-5' }));
  write(root, '.transcripts/project/session/subagents/agent-a1.meta.json', JSON.stringify({ agentType: 'dflow:worker' }));

  const env = { DFLOW_TRANSCRIPTS: store };
  const summary = JSON.parse(dflow(root, ['cost', '--json'], { env }).stdout);
  assert.deepEqual(summary.phases.plan, { requests: 1, input: 100, write: 0, read: 1000, output: 10, equivalent: 250 });
  assert.deepEqual(summary.phases.build, { requests: 2, input: 60, write: 2400, read: 20000, output: 150, equivalent: 60 + 800 + 2500 + 2000 + 750 });
  assert.equal(summary.phases['review and ship'].requests, 1);
  assert.equal(summary.total.requests, 4);
  assert.deepEqual(Object.keys(summary.models).sort(), ['claude-opus-5-5', 'claude-sonnet-5-5']);
  assert.equal(summary.agents['dflow:worker'].output, 100);
  assert.equal(summary.averageContext, Math.round((1100 + 20410 + 30005) / 3));

  const printed = dflow(root, ['cost'], { env });
  assert.match(printed.stdout, /^dflow cost · 2026-11-12-meter · 2026-11-12T10:00 to 2026-11-12T14:00/);
  assert.match(printed.stdout, /^build +2 +60 +2k +20k +150 +6k/m);
  assert.match(printed.stdout, /Subagents are \d+% of the total/);
  assert.match(printed.stdout, /Average context per main-session request: 17k/);
});

test('cost says so when there is no transcript usage, and refuses an unknown plan', t => {
  const root = makeProject(t);
  const missing = dflow(root, ['cost'], { env: { DFLOW_TRANSCRIPTS: path.join(root, 'none') } });
  assert.equal(missing.status, 0, missing.stderr);
  assert.match(missing.stdout, /^No transcript usage found for 2026-11-12-meter/);
  assert.match(dflow(root, ['cost', '--plan', 'nope']).stderr, /no plan named nope/);
});
