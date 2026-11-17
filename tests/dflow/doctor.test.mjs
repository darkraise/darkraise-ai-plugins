import assert from 'node:assert/strict';
import test from 'node:test';
import { PLAN_FILE, dflow, makeProject, read, write } from './helpers.mjs';

test('doctor passes on a clean project', t => {
  const root = makeProject(t);
  const result = dflow(root, ['doctor']);
  assert.equal(result.status, 0, result.stdout);
  assert.match(result.stdout, /dflow doctor: ok/);
});

test('doctor names an over-budget doc, a dead path, a bad board row and a plan that does not lint', t => {
  const root = makeProject(t, { config: { budgets: { 'project.md': 5 } } });
  write(root, 'src/real.mjs', '1\n');
  write(root, 'docs/dflow/project.md', ['# p', 'The parser is `src/real.mjs`, the meter `src/gone.mjs:12`.', 'States are `open/closed` and `n/a`; run `npm test`.', '```', '`src/in-a-fence.mjs`', '```', 'x'].join('\n'));
  write(root, 'docs/dflow/decisions.md', '# d\nThe old meter was `src/deleted-long-ago.mjs`.\n');
  write(root, 'docs/dflow/board.md', `${read(root, 'docs/dflow/board.md')}| 2 | Other | - | Passes | waiting | - |\n`);
  write(root, PLAN_FILE, read(root, PLAN_FILE).replace('**Goal:** Show the remaining rate limit.', '**Goal:** …'));
  const result = dflow(root, ['doctor']);
  assert.equal(result.status, 1);
  assert.deepEqual(result.stdout.trim().split('\n'), [
    'dflow doctor: 4 problem(s)',
    '- project.md: 7 lines, over its budget of 5; prune it',
    '- project.md:2: `src/gone.mjs:12` does not exist',
    '- board row 2: state "waiting" is not one of open, planned, doing, verify, done, deferred, n/a',
    `- ${PLAN_FILE}: Goal is empty`,
  ]);
});
