import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { COMMANDS } from '../lib/cli.mjs';
import { PLUGIN } from './helpers.mjs';

const SKILLS = ['plan', 'build', 'review', 'ship', 'status', 'init', 'hud'];
const LIMIT = 6000;

function frontmatter(text) {
  const block = /^---\n([\s\S]*?)\n---\n/.exec(text);
  assert.ok(block, 'starts with a frontmatter block');
  return Object.fromEntries(block[1].split('\n').map(line => [line.slice(0, line.indexOf(':')), line.slice(line.indexOf(':') + 1).trim()]));
}

function markdownFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const full = path.join(directory, entry.name);
    return entry.isDirectory() ? markdownFiles(full) : entry.name.endsWith('.md') ? [full] : [];
  });
}

test('the plugin ships exactly the seven skills, each small enough to survive compaction whole', () => {
  assert.deepEqual(fs.readdirSync(path.join(PLUGIN, 'skills')).sort(), [...SKILLS].sort());
  for (const name of SKILLS) {
    const text = fs.readFileSync(path.join(PLUGIN, 'skills', name, 'SKILL.md'), 'utf8');
    assert.ok(Buffer.byteLength(text) <= LIMIT, `${name}: ${Buffer.byteLength(text)} bytes, over ${LIMIT}`);
    const fields = frontmatter(text);
    assert.equal(fields.name, name);
    assert.ok(fields.description.length >= 40 && fields.description.length <= 1024, `${name}: description length`);
  }
});

test('the skills invoked by name only are marked so', () => {
  for (const name of SKILLS) {
    const fields = frontmatter(fs.readFileSync(path.join(PLUGIN, 'skills', name, 'SKILL.md'), 'utf8'));
    assert.equal(fields['disable-model-invocation'] === 'true', ['init', 'hud'].includes(name), name);
  }
});

test('every dflow command named in a skill, an agent or the workflow exists', () => {
  const files = [...markdownFiles(path.join(PLUGIN, 'skills')), ...markdownFiles(path.join(PLUGIN, 'agents')), path.join(PLUGIN, 'workflows/deep-review.js')];
  const named = new Set();
  for (const file of files) {
    for (const match of fs.readFileSync(file, 'utf8').matchAll(/(?:`|^\s*|bin\/dflow" )dflow ([a-z-]+)/gm)) named.add(match[1]);
  }
  assert.ok(named.size >= 15, `only ${named.size} commands found; the pattern no longer matches`);
  assert.deepEqual([...named].filter(name => !COMMANDS[name]), []);
});

test('the agents name a model and an effort, and the reviewer cannot edit', () => {
  const reviewer = frontmatter(fs.readFileSync(path.join(PLUGIN, 'agents/reviewer.md'), 'utf8'));
  const worker = frontmatter(fs.readFileSync(path.join(PLUGIN, 'agents/worker.md'), 'utf8'));
  assert.deepEqual([reviewer.model, reviewer.effort, worker.model, worker.effort], ['opus', 'medium', 'sonnet', 'medium']);
  for (const tool of ['Edit', 'Write', 'NotebookEdit']) assert.ok(reviewer.disallowedTools.split(', ').includes(tool), tool);
});

test('the workflow script starts with a literal meta and runs to a result', async () => {
  const source = fs.readFileSync(path.join(PLUGIN, 'workflows/deep-review.js'), 'utf8');
  assert.match(source, /^export const meta = \{\n {2}name: 'deep-review',/);
  const AsyncFunction = (async () => {}).constructor;
  const body = source.replace(/^export const meta/, 'const meta');
  const calls = [];
  const agent = async (prompt, options) => {
    calls.push(options);
    return options.schema.properties.recorded ? { recorded: [`F${calls.length}`], notChecked: '' } : { confirmed: ['F1'], refuted: ['F2'] };
  };
  const run = stubArgs => new AsyncFunction('args', 'agent', 'parallel', 'phase', 'log', body)(stubArgs, agent, thunks => Promise.all(thunks.map(thunk => thunk())), () => {}, () => {});
  assert.deepEqual(await run({ pack: '.dflow/review/x/pack.md' }), { complete: true, missingLenses: [], recorded: ['F1', 'F2'], confirmed: ['F1'], refuted: ['F2'], notChecked: [] });
  assert.deepEqual(calls.map(options => [options.agentType, options.model]), [['dflow:reviewer', 'opus'], ['dflow:reviewer', 'opus'], ['dflow:reviewer', 'sonnet']]);
  await assert.rejects(run(undefined), /deep-review needs args/);

  // A reviewer that fails is named, and the review is not complete.
  const failing = async (prompt, options) => (options.label === 'review:risk' ? null : agent(prompt, options));
  const partial = await new AsyncFunction('args', 'agent', 'parallel', 'phase', 'log', body)({ pack: 'p' }, failing, thunks => Promise.all(thunks.map(thunk => thunk())), () => {}, () => {});
  assert.deepEqual([partial.complete, partial.missingLenses], [false, ['risk']]);
});
