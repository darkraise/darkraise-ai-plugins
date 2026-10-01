import assert from 'node:assert/strict';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { PLAN, fixture, modes } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const git = (...args) => spawnSync('git', args, { cwd: fx.repo, encoding: 'utf8' }).stdout.trim();

test('the fixture holds one plan and the commits that carried it out', () => {
  assert.deepEqual(git('log', '--reverse', '--format=%s').split('\n'), ['docs: plan the fixture', 'feat: add greet', 'feat: add shout', 'docs: add notes', 'feat: add idle']);
  assert.deepEqual([git('rev-parse', 'HEAD~4'), git('rev-parse', 'HEAD~3'), git('rev-parse', 'HEAD~2')], [fx.planned, fx.greet, fx.shout]);
  assert.equal(git('show', `${fx.planned}:${PLAN}`).match(/^### Task \d+:/gm).length, 4);
  assert.equal(process.env.TIER_EVAL_ROOT, fx.repo);
});

test('the stub acts as its mode says, records the call and moves down the mode list', () => {
  const clone = join(fx.top, 'clone');
  spawnSync('git', ['clone', '-q', fx.repo, clone]);
  spawnSync('git', ['checkout', '-q', fx.planned], { cwd: clone });
  modes(fx.stub, 'pass', 'blocked');
  const call = () => spawnSync(process.env.TIER_EVAL_CLAUDE, ['-p', '--model', 'sonnet'], { cwd: clone, input: 'the prompt', encoding: 'utf8' });
  const first = JSON.parse(call().stdout);
  assert.deepEqual([first.result, first.is_error, first.total_cost_usd, first.num_turns], ['**Status:** DONE', false, 0.5, 3]);
  assert.equal(existsSync(join(clone, 'src/greet.sh')), true);
  assert.match(JSON.parse(call().stdout).result, /BLOCKED/);
  assert.match(JSON.parse(call().stdout).result, /BLOCKED/);
  const calls = readFileSync(join(fx.stub, 'calls.log'), 'utf8').trim().split('\n').map(l => JSON.parse(l));
  assert.deepEqual(calls.map(c => c.mode), ['pass', 'blocked', 'blocked']);
  assert.deepEqual([calls[0].prompt, calls[0].args, calls[0].cwd], ['the prompt', ['-p', '--model', 'sonnet'], clone]);
  modes(fx.stub, 'limit');
  const limited = call();
  assert.deepEqual([limited.status, JSON.parse(limited.stdout).is_error], [1, true]);
});
