import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { BIN, PLUGIN, dflow, makeProject, makeRepo, read, sh } from './helpers.mjs';

const event = fields => JSON.stringify({ session_id: 's1', transcript_path: '/tmp/none.jsonl', hook_event_name: 'x', ...fields });

test('session start says nothing without a plan and two lines with one', t => {
  const empty = makeRepo(t);
  const silent = dflow(empty, ['hook', 'session-start'], { input: event({ source: 'startup' }) });
  assert.deepEqual([silent.status, silent.stdout], [0, '']);

  const root = makeProject(t);
  const started = dflow(root, ['hook', 'session-start'], { input: event({ source: 'startup' }) });
  assert.deepEqual(started.stdout.trim().split('\n'), [
    'dflow: plan "Rate-limit meter" (docs/dflow/plans/2026-11-12-meter.md) is 0/2 done on feat/x.',
    'Next: /dflow:build — Task 1: Parse the header',
  ]);
  assert.equal(JSON.parse(read(root, '.dflow/state.json')).transcript, '/tmp/none.jsonl');
});

test('after a compaction the hook names the next step, and the brief is left to dflow next', t => {
  const root = makeProject(t);
  const compacted = dflow(root, ['hook', 'session-start'], { input: event({ source: 'compact' }) });
  assert.deepEqual(compacted.stdout.trim().split('\n'), [
    'dflow: plan "Rate-limit meter" (docs/dflow/plans/2026-11-12-meter.md) is 0/2 done on feat/x.',
    'Next: /dflow:build — Task 1: Parse the header',
  ]);
});

test('pre-compact prints summary instructions only while a plan is active', t => {
  const root = makeProject(t);
  const instructions = dflow(root, ['hook', 'pre-compact'], { input: event({ trigger: 'auto' }) });
  assert.match(instructions.stdout, /A dflow build is in progress\. The plan file docs\/dflow\/plans\/2026-11-12-meter\.md/);
  assert.match(instructions.stdout, /Task 1 is in progress/);
  assert.equal(dflow(makeRepo(t), ['hook', 'pre-compact'], { input: event({}) }).stdout, '');
});

test('a hook outside a repository, or with broken input, exits 0 silently', t => {
  const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'dflow-norepo-'));
  t.after(() => fs.rmSync(outside, { recursive: true, force: true }));
  for (const name of ['session-start', 'pre-compact', 'stop']) {
    const result = sh(outside, process.execPath, [BIN, 'hook', name], { input: 'not json' });
    assert.deepEqual([result.status, result.stdout, result.stderr], [0, '', ''], name);
  }
  assert.equal(dflow(makeProject(t), ['hook', 'stop'], { input: 'not json' }).status, 0);
});

test('hooks.json wires the three events to the CLI', () => {
  const { hooks } = JSON.parse(fs.readFileSync(path.join(PLUGIN, 'hooks/hooks.json'), 'utf8'));
  const commands = Object.fromEntries(Object.entries(hooks).map(([name, groups]) => [name, groups[0].hooks[0]]));
  assert.deepEqual(Object.keys(commands), ['SessionStart', 'PreCompact', 'Stop']);
  for (const [name, hook] of Object.entries(commands)) assert.match(hook.command, /^node "\$\{CLAUDE_PLUGIN_ROOT\}\/bin\/dflow" hook /, name);
  assert.equal(commands.Stop.async, true);
});

test('no hook writes into a repository that does not use dflow', t => {
  const root = makeRepo(t);
  for (const name of ['session-start', 'pre-compact', 'stop']) dflow(root, ['hook', name], { input: event({ source: 'startup' }) });
  dflow(root, ['status']);
  assert.ok(!fs.existsSync(path.join(root, '.dflow')));
});

test('a conflicted session start returns the guard block and the other hooks stay silent', t => {
  const root = makeProject(t);
  const claude = fs.mkdtempSync(path.join(os.tmpdir(), 'guard-'));
  const data = fs.mkdtempSync(path.join(os.tmpdir(), 'data-'));
  t.after(() => { fs.rmSync(claude, { recursive: true, force: true }); fs.rmSync(data, { recursive: true, force: true }); });
  fs.mkdirSync(path.join(claude, 'plugins'));
  fs.writeFileSync(path.join(claude, 'plugins/installed_plugins.json'), JSON.stringify({ version: 2, plugins: { 'dforge@darkraise': [{ scope: 'user', installPath: '/x', version: '5' }] } }));
  fs.writeFileSync(path.join(claude, 'settings.json'), JSON.stringify({ enabledPlugins: { 'dforge@darkraise': true } }));
  const env = { WORKFLOW_GUARD_CLAUDE_DIR: claude, WORKFLOW_GUARD_MANAGED_DIR: claude, WORKFLOW_GUARD_PROJECT_DIR: root, CLAUDE_PLUGIN_DATA: data };
  const started = dflow(root, ['hook', 'session-start'], { input: event({ source: 'startup' }), env });
  assert.equal(started.status, 0);
  const out = JSON.parse(started.stdout);
  assert.match(out.systemMessage, /dforge@darkraise/);
  assert.match(out.hookSpecificOutput.additionalContext, /claude plugin disable dforge@darkraise --scope local/);
  const tree = () => fs.readdirSync(path.join(root, '.dflow'), { recursive: true }).sort().map(file => {
    const full = path.join(root, '.dflow', file);
    return fs.statSync(full).isFile() ? `${file}:${fs.readFileSync(full, 'utf8')}` : file;
  });
  const held = tree();
  const stopped = dflow(root, ['hook', 'stop'], { input: event({ transcript_path: '/tmp/conflicted.jsonl' }), env });
  assert.deepEqual([stopped.status, stopped.stdout, stopped.stderr], [0, '', '']);
  assert.deepEqual(tree(), held, 'a stood-down stop records nothing');
  dflow(root, ['hook', 'stop'], { input: event({ session_id: 's2', transcript_path: '/tmp/conflicted.jsonl' }), env });
  assert.notDeepEqual(tree(), held, 'the same stop in a session with no marker records its transcript');
  const compact = dflow(root, ['hook', 'pre-compact'], { input: event({}), env });
  assert.deepEqual([compact.status, compact.stdout], [0, '']);
  assert.equal(JSON.parse(fs.readFileSync(path.join(PLUGIN, 'hooks/hooks.json'), 'utf8')).hooks.SessionStart[0].matcher, 'startup|resume|clear|compact|fork');
});
