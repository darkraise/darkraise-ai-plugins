import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { PLAN, fixture } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { git, run, sh } = await import('../lib/sh.mjs');
const { commitMessages, evaluation, filesBlock, taskBrief, taskText, tasks } = await import('../lib/plan.mjs');
const plan = join(fx.top, 'plan.md');
writeFileSync(plan, git(['show', `${fx.planned}:${PLAN}`]));

test('git reads the fixture repository and throws on a failing command', () => {
  assert.equal(git(['rev-parse', 'HEAD~3']).trim(), fx.greet);
  assert.throws(() => git(['rev-parse', 'no-such-ref']), /git rev-parse no-such-ref/);
  assert.equal(sh('bash', ['-c', 'exit 3']).code, 3);
});

test('run returns the output and kills the whole tree at the timeout', async () => {
  assert.deepEqual(await run('bash', ['-c', 'cat; echo err >&2'], { input: 'in' }), { code: 0, out: 'in', err: 'err\n', timedOut: false });
  const started = Date.now();
  const slow = await run('bash', ['-c', 'sleep 30 & wait'], { seconds: 1 });
  assert.equal(slow.timedOut, true);
  assert.ok(Date.now() - started < 10000);
  assert.equal((await run('no-such-binary-xyz', [])).code, 127);
});

test('a signal that stops the harness kills what run started', async () => {
  const pidFile = join(fx.top, 'child.pid');
  const code = `import(${JSON.stringify(new URL('../lib/sh.mjs', import.meta.url).href)}).then(m => m.run('bash', ['-c', 'echo $$ > "$0"; sleep 30', ${JSON.stringify(pidFile)}]))`;
  const harness = spawn(process.execPath, ['-e', code], { stdio: 'ignore' });
  while (!existsSync(pidFile) || readFileSync(pidFile, 'utf8').trim() === '') await new Promise(r => setTimeout(r, 50));
  const pid = Number(readFileSync(pidFile, 'utf8'));
  harness.kill('SIGTERM');
  const exit = await new Promise(r => harness.on('exit', r));
  await new Promise(r => setTimeout(r, 200));
  assert.equal(exit, 130);
  assert.throws(() => process.kill(pid, 0), /ESRCH/);
});

test('the plan reader lists tasks, their text and their scores', () => {
  assert.deepEqual(tasks(plan), [{ n: 1, title: 'Greet' }, { n: 2, title: 'Shout' }, { n: 3, title: 'Notes' }, { n: 4, title: 'Already green' }]);
  assert.match(taskText(plan, 2), /^### Task 2: Shout\n[\s\S]*feat: add shout/);
  assert.doesNotMatch(taskText(plan, 2), /Task 3/);
  assert.equal(taskText(plan, 9), null);
  assert.deepEqual(evaluation(taskText(plan, 2)), { files: 1, spec: 0, coupling: 0, risk: 2, total: 3 });
  assert.equal(evaluation('no score here'), null);
  assert.equal(evaluation('**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1\n**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1'), null);
});

test('filesBlock reads labels, line suffixes and test files listed under Modify', () => {
  const text = ['**Files:**', '- Create: `src/a.sh` (new)', '- Modify: `tests/a.test.sh:10-20`', '- Modify: `lib/b.mjs`, `lib/c.mjs` (add `--flag`)', '- Test: tests/d.test.mjs,', '', '**Interfaces:**', '- Create: `not/in/block.sh`'].join('\n');
  assert.deepEqual(filesBlock(text), {
    allowed: ['src/a.sh', 'tests/a.test.sh', 'lib/b.mjs', 'lib/c.mjs', 'tests/d.test.mjs'],
    tests: ['tests/a.test.sh', 'tests/d.test.mjs'],
  });
});

test('commitMessages takes the first -m of each commit command', () => {
  assert.deepEqual(commitMessages('git add a\ngit commit -m "feat: one" -m "body"\ngit commit -q -m \'fix: two\'\ngit commit -m "feat: one"'), ['feat: one', 'fix: two']);
});

test('taskBrief is the task text followed by the header excerpt', () => {
  const brief = taskBrief(plan, 1, join(fx.top, 'brief'));
  assert.match(brief, /^### Task 1: Greet\n/);
  assert.match(brief, /## Plan header excerpt\n\n## Global Constraints\n\nNone\.\n\n## Contracts/);
  assert.doesNotMatch(brief, /Task 2/);
  assert.throws(() => taskBrief(plan, 9, join(fx.top, 'brief')), /task-brief .* 9: exit 3/);
});
