import assert from 'node:assert/strict';
import { test } from 'node:test';
import { measureTranscript, priceOf, sumMetrics } from '../lib/transcript.mjs';

const usage = (read, output, extra = {}) => ({ input_tokens: 10, cache_read_input_tokens: read, output_tokens: output, cache_creation_input_tokens: 1000, cache_creation: { ephemeral_5m_input_tokens: 0, ephemeral_1h_input_tokens: 1000 }, ...extra });
const said = (id, model, u, content = [], effort = 'high') => ({ type: 'assistant', effort, timestamp: `2026-10-18T00:00:0${id.length % 10}Z`, message: { id, model, usage: u, content } });
const use = (id, name, input) => ({ type: 'tool_use', id, name, input });
const result = (id, text) => ({ type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: id, content: text }] } });
const typed = (text, extra = {}) => ({ type: 'user', message: { content: text }, ...extra });
const jsonl = records => records.map(r => JSON.stringify(r)).join('\n') + '\nnot json\n';

test('each message id is counted once, from its last record, and priced by meter', () => {
  const m = measureTranscript(jsonl([
    said('msg_a', 'claude-sonnet-5-5', usage(200000, 100)),
    said('msg_a', 'claude-sonnet-5-5', usage(200000, 700)),
    said('msg_b', 'claude-opus-5-5', usage(100000, 300), [], 'low'),
  ]));
  assert.equal(m.calls, 2);
  assert.deepEqual([m.input, m.write5m, m.write1h, m.read, m.output], [20, 0, 2000, 300000, 1000]);
  const sonnet = (10 * 2 + 1000 * 4 + 200000 * 0.1 + 700 * 10) / 1e6;
  const opus = (10 * 4 + 1000 * 8 + 100000 * 0.2 + 300 * 20) / 1e6;
  assert.ok(Math.abs(m.cost - (sonnet + opus)) < 1e-9);
  assert.deepEqual(m.models, ['claude-opus-5-5', 'claude-sonnet-5-5']);
  assert.deepEqual(m.efforts, ['high', 'low']);
  assert.deepEqual(m.unpriced, []);
});

test('a usage without the cache split counts its writes as 5-minute writes', () => {
  const m = measureTranscript(jsonl([said('msg_a', 'claude-sonnet-5-5', { input_tokens: 0, cache_creation_input_tokens: 400, cache_read_input_tokens: 0, output_tokens: 0 })]));
  assert.deepEqual([m.write5m, m.write1h], [400, 0]);
  assert.ok(Math.abs(m.cost - 400 * 2.5 / 1e6) < 1e-12);
});

test('an unlisted model is named and left unpriced; a synthetic one is not a call', () => {
  const m = measureTranscript(jsonl([
    said('msg_a', 'claude-haiku-5-5', usage(10, 10)),
    said('msg_b', '<synthetic>', { input_tokens: 0, output_tokens: 0 }),
  ]));
  assert.deepEqual(m.unpriced, ['claude-haiku-5-5']);
  assert.equal(m.cost, 0);
  assert.equal(m.calls, 1);
  assert.deepEqual(m.models, ['claude-haiku-5-5']);
  assert.equal(measureTranscript(jsonl([said('msg_s', '<synthetic>', { input_tokens: 0, output_tokens: 0 })])).calls, 0);
  assert.equal(priceOf('claude-sonnet-5-5-20261001').output, 10);
  assert.equal(priceOf('claude-sonnet-5'), null);
});

test('dispatches, busy waits, monitors and nudges are counted', () => {
  const m = measureTranscript(jsonl([
    said('msg_a', 'claude-sonnet-5-5', usage(1, 1), [
      use('t1', 'Agent', { subagent_type: 'dforge:impl-sonnet-low' }),
      use('t2', 'Bash', { command: 'bash /p/scripts/run-codex-task.sh --brief b.md --task 3' }),
      use('t3', 'Bash', { command: 'sleep 1' }),
      use('t4', 'Bash', { command: 'sleep 30; echo done' }),
      use('t5', 'ListAgents', {}),
      use('t6', 'Monitor', { command: 'tail -f x' }),
      use('t7', 'Bash', { command: 'bash "$(bash /p/scripts/executors path codex wrapper)" --brief b.md --task-id t' }),
    ]),
    said('msg_a', 'claude-sonnet-5-5', usage(1, 1), [use('t1', 'Agent', { subagent_type: 'dforge:impl-sonnet-low' })]),
    typed('check status, I see that there are still agent and shell running'),
    typed('<command-name>/status</command-name> still running'),
    typed('the skill says check status', { isMeta: true }),
    { type: 'user', message: { content: [{ type: 'text', text: 'anything running?' }, { type: 'image', source: {} }] } },
  ]));
  assert.deepEqual([m.dispatches, m.sleeps, m.listAgents, m.monitors, m.nudges], [3, 1, 1, 1, 2]);
});

test('the Task tool is a dispatch, and the latest timestamp is kept', () => {
  const a = measureTranscript(jsonl([said('msg_a', 'claude-sonnet-5-5', usage(1, 1), [use('k1', 'Task', { subagent_type: 'dforge:impl-sonnet-low' })])]));
  const b = measureTranscript(jsonl([said('msg_bb', 'claude-sonnet-5-5', usage(1, 1))]));
  assert.equal(a.dispatches, 1);
  assert.equal(a.last, '2026-10-18T00:00:05Z');
  assert.equal(sumMetrics([a, b]).last, '2026-10-18T00:00:06Z');
});

test('each routed review is the next review dispatched, and must reach the printed seat', () => {
  const route = (id, primary, fallback) => [said(`m${id}`, 'claude-sonnet-5-5', usage(1, 1), [use(id, 'Bash', { command: `bash /p/scripts/review-route plan.md --task ${id}` })]), result(id, `review-seat task=${id} primary=${primary} fallback=${fallback} reason=band`)];
  const call = (id, input, name = 'Agent') => said(`c${id}`, 'claude-sonnet-5-5', usage(1, 1), [use(id, name, input)]);
  const m = measureTranscript(jsonl([
    call('early', { subagent_type: 'dforge:judge-opus' }),
    ...route('r1', 'dforge:judge-sonnet-high', '-'),
    call('a1', { subagent_type: 'dforge:impl-sonnet-low' }),
    call('a2', { subagent_type: 'dforge:judge-sonnet-high' }),
    ...route('r2', 'codex:light', 'dforge:judge-opus'),
    ...route('r3', 'codex:light', 'dforge:judge-opus'),
    call('b1', { command: 'bash /p/scripts/run-codex-review.sh --kind task --tier light' }, 'Bash'),
    call('b2', { subagent_type: 'dforge:judge-opus' }),
    call('b3', { subagent_type: 'dforge:judge-opus' }),
    ...route('r4', 'dforge:judge-opus', '-'),
    call('c1', { subagent_type: 'dforge:judge-sonnet-high' }),
    call('c2', { subagent_type: 'dforge:judge-opus' }),
    said('mf1', 'claude-sonnet-5-5', usage(1, 1), [use('f1', 'Bash', { command: 'bash /p/scripts/review-route plan.md --final-fix' })]),
    result('f1', 'review-seat final-fix primary=dforge:impl-sonnet-high fallback=- reason=floor'),
    said('mf3', 'claude-sonnet-5-5', usage(1, 1), [use('f3', 'Bash', { command: 'bash /p/scripts/review-route plan.md --final-fix' })]),
    result('f3', 'review-seat final-fix primary=dforge:impl-sonnet-high fallback=- reason=tasks:1,2'),
    call('c3', { subagent_type: 'dforge:judge-opus' }),
    call('f2', { subagent_type: 'dforge:impl-sonnet-high' }),
  ]));
  // r1 reached its seat; r2 and r3, printed together, were answered in order
  // (r3 through its fallback); b3 and c2 are unrouted; r4 went to the wrong
  // judge, and the right judge dispatched after it does not repair that; the
  // final-fix route, printed twice, waits for one implementer, so c3 does not
  // answer it.
  assert.equal(m.seatMisses, 1);
  const open = measureTranscript(jsonl([...route('r5', 'dforge:judge-opus', '-'), call('i1', { subagent_type: 'dforge:impl-sonnet-low' })]));
  assert.equal(open.seatMisses, 1);
});

test('a Codex review must run at the routed tier, and a command that launches no run answers no route', () => {
  const routed = (id, primary, fallback) => [said(`m${id}`, 'claude-sonnet-5-5', usage(1, 1), [use(id, 'Bash', { command: 'bash /p/scripts/review-route plan.md --task 1' })]), result(id, `review-seat task=1 primary=${primary} fallback=${fallback} reason=band`)];
  const run = (id, command) => said(`c${id}`, 'claude-sonnet-5-5', usage(1, 1), [use(id, 'Bash', { command })]);
  const at = (tier, extra = []) => measureTranscript(jsonl([...routed('r1', 'codex:heavy+judge-opus', 'dforge:judge-opus'), ...extra, run('b1', `bash /p/scripts/run-codex-review.sh --kind task --tier ${tier}`)]));
  assert.equal(at('heavy').seatMisses, 0);
  assert.equal(at('light').seatMisses, 1);
  const reading = at('heavy', [run('x1', 'cat /p/scripts/run-codex-review.sh'), run('x2', 'ps aux | grep run-codex-review.sh')]);
  assert.deepEqual([reading.seatMisses, reading.dispatches], [0, 1]);
  const fix = measureTranscript(jsonl([
    ...routed('f1', 'dforge:impl-sonnet-high', '-'),
    run('x3', 'bash /p/scripts/run-codex-task.sh --cwd w --task-id t --release'),
    run('x4', 'bash /p/scripts/run-codex-task.sh --brief b.md --dry-run'),
    said('d', 'claude-sonnet-5-5', usage(1, 1), [use('d1', 'Agent', { subagent_type: 'dforge:impl-sonnet-high' })]),
  ]));
  assert.deepEqual([fix.seatMisses, fix.dispatches], [0, 1]);
});

test('a ledger check that only redirects stderr, and a write that failed, are not completions', () => {
  const ledger = '/w/.dforge/sdd/p/progress.md';
  const m = measureTranscript(jsonl([
    said('msg_a', 'claude-sonnet-5-5', usage(1, 1), [
      use('g1', 'Bash', { command: "grep -q 'Task 7: complete (' .dforge/sdd/p/progress.md 2>/dev/null && echo yes" }),
      use('g2', 'Bash', { command: "grep -c 'Task 8: complete (' .dforge/sdd/p/progress.md > /dev/null || true" }),
      use('e1', 'Edit', { file_path: ledger, old_string: 'x', new_string: 'Task 1: complete (commits a..b)' }),
      use('e2', 'Edit', { file_path: ledger, old_string: 'y', new_string: 'Task 2: complete (commits c..d)' }),
      use('t1', 'Bash', { command: "echo 'Task 3: complete (x)' | tee -a .dforge/sdd/p/progress.md" }),
      use('m1', 'MultiEdit', { file_path: ledger, edits: [{ old_string: 'a', new_string: 'Task 5: complete (x)' }] }),
      use('v1', 'Bash', { command: "L=/w/.dforge/sdd/p/progress.md && cat >> $L <<'EOF'\nTask 4: complete (x)\nEOF" }),
      use('v2', 'Bash', { command: "L=/w/.dforge/sdd/p/progress.md; grep -q 'Task 9: complete (' \"$L\" 2>/dev/null" }),
    ]),
    { type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'e1', is_error: true, content: 'String to replace not found' }] } },
  ]));
  assert.deepEqual(m.completed, ['2', '3', '4', '5']);
});

test('ledger complete lines the controller wrote are collected, deferred ones left out', () => {
  const ledger = '/w/.dforge/sdd/p/progress.md';
  const m = measureTranscript(jsonl([
    said('msg_a', 'claude-sonnet-5-5', usage(1, 1), [
      use('w1', 'Write', { file_path: ledger, content: 'Task 1: complete (commits a..b, review clean) — done: x\nTask 2: complete (deferred by the auto run) — done: nothing\n' }),
      use('e1', 'Edit', { file_path: ledger, old_string: 'x', new_string: 'Task 10: complete (commits c..d, review clean)' }),
      use('b1', 'Bash', { command: "printf '%s\\n' 'Task 4: complete (commits e..f, review clean)' >> .dforge/sdd/p/progress.md" }),
      use('n1', 'Write', { file_path: '/w/notes.md', content: 'Task 5: complete (commits g..h)' }),
      use('n2', 'Write', { file_path: ledger, content: 'Task 6: BLOCKED (tests fail)' }),
      use('r1', 'Bash', { command: "grep -c 'Task 7: complete (' .dforge/sdd/p/progress.md" }),
    ]),
  ]));
  assert.deepEqual(m.completed, ['1', '4', '10']);
});

test('sumMetrics adds counts and merges names', () => {
  const a = measureTranscript(jsonl([said('msg_a', 'claude-sonnet-5-5', usage(100, 10), [use('w', 'Write', { file_path: 'progress.md', content: 'Task 2: complete (x)' })])]));
  const b = measureTranscript(jsonl([said('msg_b', 'claude-opus-5-5', usage(100, 10), [use('v', 'Write', { file_path: 'progress.md', content: 'Task 10: complete (x)\nTask 2: complete (x)' })], 'low'), typed('anything still running?')]));
  const s = sumMetrics([a, b]);
  assert.equal(s.calls, 2);
  assert.equal(s.nudges, 1);
  assert.ok(Math.abs(s.cost - (a.cost + b.cost)) < 1e-12);
  assert.deepEqual(s.efforts, ['high', 'low']);
  assert.deepEqual(s.completed, ['2', '10']);
  assert.equal(sumMetrics([]).calls, 0);
});
