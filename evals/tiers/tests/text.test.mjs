import assert from 'node:assert/strict';
import { rmSync } from 'node:fs';
import { resolve } from 'node:path';
import { after, test } from 'node:test';
import { fixture } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { PLUGIN } = await import('../lib/sh.mjs');
const { fill, template } = await import('../lib/prompt.mjs');
const { MARKER, addedLines, isTestPath, strip } = await import('../lib/strip.mjs');

test('the three production templates yield a prompt body', () => {
  const body = template(resolve(PLUGIN, 'skills/subagent-driven-development/references/implementer-prompt.md'));
  assert.match(body, /^You are implementing Task N: \[task name\]/);
  assert.doesNotMatch(body, /^Subagent|prompt: \|/m);
  assert.match(template(resolve(PLUGIN, 'skills/requesting-code-review/references/code-reviewer.md')), /\[DIFF_FILE\][\s\S]*```bash[\s\S]*## Critical Rules/);
  assert.match(template(resolve(PLUGIN, 'skills/writing-plans/references/plan-reviewer-prompt.md')), /\[PLAN_FILE\][\s\S]*\[PLUGIN_ROOT\]/);
  assert.throws(() => template(resolve(PLUGIN, 'README.md')), /no "prompt: \|" block/);
});

test('fill replaces every occurrence and refuses a key the template lacks', () => {
  assert.equal(fill('a [X] b [X]', { '[X]': 'y' }), 'a y b y');
  assert.throws(() => fill('a', { '[X]': 'y' }), /no \[X\]/);
});

test('addedLines holds what a commit added outside tests/', () => {
  assert.deepEqual([...addedLines(fx.planned, fx.greet)].sort(), ['# greets', 'echo hello']);
  assert.deepEqual([isTestPath('tests/a.sh'), isTestPath('x/tests/fixtures/a'), isTestPath('src/tests.sh')], [true, true, false]);
});

test('strip removes a block only when more than half of it was added', () => {
  const added = new Set(['echo hello', '# greets']);
  const brief = ['Test:', '```bash', 'set -e', '[ "$out" = "hello" ]', '```', 'Code:', '````bash', '# greets', '```', 'echo hello', '````', 'Half:', '```', 'echo hello', 'other', '```'].join('\n');
  const { text, removed } = strip(brief, added);
  assert.equal(removed, 1);
  assert.equal(text, ['Test:', '```bash', 'set -e', '[ "$out" = "hello" ]', '```', 'Code:', MARKER, 'Half:', '```', 'echo hello', 'other', '```'].join('\n'));
  assert.deepEqual(strip('no fence', added), { text: 'no fence', removed: 0 });
});
