import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { after, test } from 'node:test';
import { projectFolder } from '../lib/sessions.mjs';

const top = mkdtempSync(join(tmpdir(), 'controller-pilot-'));
after(() => rmSync(top, { recursive: true, force: true }));
const projects = join(top, 'projects');
const data = join(top, 'data');
const repo = join(top, 'repos/app');
const folder = join(projects, projectFolder(repo));

const usage = { input_tokens: 0, cache_read_input_tokens: 1000000, output_tokens: 0 };
const said = (id, model, effort, content) => ({ type: 'assistant', effort, message: { id, model, usage, content } });
const use = (id, name, input) => ({ type: 'tool_use', id, name, input });
const session = (slugs, model, effort, done = []) => [
  said('s', model, effort, [use('u0', 'Skill', { skill: 'dforge:subagent-driven-development' })]),
  ...slugs.map((slug, i) => said(`b${i}`, model, effort, [use(`u${i + 1}`, 'Bash', { command: `bash /p/scripts/task-brief docs/plans/${slug}.md 1` })])),
  ...done.map(n => said(`l${n}`, model, effort, [use(`w${n}`, 'Write', { file_path: '/w/.dforge/sdd/x/progress.md', content: `Task ${n}: complete (commits a..b, review clean)\n` })])),
  { type: 'user', message: { content: 'check status please' } },
].map(r => JSON.stringify(r)).join('\n') + '\n';
const write = (path, text) => { mkdirSync(join(path, '..'), { recursive: true }); writeFileSync(path, text); };

const SONNET = 'claude-sonnet-5-5';
const OPUS = 'claude-opus-5-5';
write(join(folder, 'one.jsonl'), session(['2026-10-18-one'], SONNET, 'high', [1, 2]));
write(join(folder, 'two.jsonl'), session(['2026-10-18-two'], SONNET, 'low', [1, 2]));
write(join(folder, 'four.jsonl'), session(['2026-10-18-four'], OPUS, 'low', [1]));
// Five ran one session on the arm and one on Opus medium: the arms mixed.
write(join(folder, 'five-a.jsonl'), session(['2026-10-18-five'], OPUS, 'low', [1]));
write(join(folder, 'five-b.jsonl'), session(['2026-10-18-five'], OPUS, 'medium', [2]));
write(join(folder, 'mixed.jsonl'), session(['2026-10-18-six', '2026-10-18-seven'], OPUS, 'low', [1, 2]));
write(join(folder, 'eight.jsonl'), session(['2026-10-18-eight'], SONNET, 'high', [1, 2]));
// Task 9 is quoted inside a fence and is not one of the plan's tasks.
const PLAN_TEXT = '# P\n\n### Task 1: A\n\n````markdown\n```js\n### Task 9: quoted\n```\n````\n\n### Task 2: B\n';
for (const slug of ['one', 'two', 'three', 'four', 'five', 'six']) write(join(repo, `docs/plans/2026-10-18-${slug}.md`), PLAN_TEXT);
spawnSync('git', ['init', '-q', repo]);
spawnSync('git', ['-C', repo, 'add', '-A']);
spawnSync('git', ['-C', repo, '-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-q', '-m', 'init']);

const report = rows => {
  write(join(data, 'pilot.tsv'), ['plan\trepo\tarm\tnote', ...rows].join('\n') + '\n');
  return spawnSync(process.execPath, ['evals/controller/pilot-report.mjs'], { encoding: 'utf8', env: { ...process.env, CONTROLLER_EVAL_PROJECTS: projects, CONTROLLER_EVAL_DATA: data, CONTROLLER_EVAL_REPOS: join(top, 'repos') } });
};

test('pilot-report prints a row per plan with its status, and decides on the usable ones', () => {
  const r = report([
    'docs/plans/2026-10-18-one.md\tapp\tsonnet@high\t-',
    `docs/plans/2026-10-18-two.md\t${repo}\topus@low\tlaunched on the wrong line`,
    'docs/plans/2026-10-18-three.md\tapp\topus@low\tnot run yet',
    'docs/plans/2026-10-18-four.md\tapp\topus@low\t-',
    'docs/plans/2026-10-18-five.md\tapp\topus@low\tresumed on medium',
    'docs/plans/2026-10-18-six.md\tapp\topus@low\tran with seven',
    'docs/plans/2026-10-18-eight.md\tapp\tsonnet@high\tplan not committed',
  ]);
  assert.equal(r.status, 0, r.stderr);
  const lines = r.stdout.trim().split('\n');
  assert.equal(lines.length, 9);
  const rows = lines.slice(1, 8).map(l => l.split('\t'));
  assert.deepEqual(rows.map(row => row.slice(0, 4)), [
    ['2026-10-18-one', 'sonnet@high', 'ok', 'yes'],
    ['2026-10-18-two', 'opus@low', 'mismatch', 'yes'],
    ['2026-10-18-three', 'opus@low', 'no-sessions', 'no'],
    ['2026-10-18-four', 'opus@low', 'ok', 'no'],
    ['2026-10-18-five', 'opus@low', 'mismatch', 'yes'],
    ['2026-10-18-six', 'opus@low', 'shared', 'yes'],
    ['2026-10-18-eight', 'sonnet@high', 'no-plan', 'unknown'],
  ]);
  assert.deepEqual(rows[0].slice(4, 8), ['1', '0', SONNET, 'high']);
  assert.deepEqual([rows[0][11], rows[0][13]], ['4', '1']);
  assert.equal(lines[8], 'stage1: incomplete — 2 of 7 plans usable; opus@low costs 1.50x sonnet@high per dispatch; failures sonnet@high 1, opus@low 1');
});

test('pilot-report refuses an arm the pilot does not run', () => {
  const r = report(['docs/plans/2026-10-18-one.md\tapp\tsonnet@medium\t-']);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /arm must be sonnet@high or opus@low/);
});
