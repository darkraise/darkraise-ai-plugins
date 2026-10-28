import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// A small repository the harness reads its history from; set before the
// harness modules load, as they read the variable once.
const top = mkdtempSync(join(tmpdir(), 'pipeline-manifest-test-'));
const repo = join(top, 'repo');
mkdirSync(repo);
process.env.TIER_EVAL_ROOT = repo;
after(() => rmSync(top, { recursive: true, force: true }));
const git = (...args) => spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.invalid', ...args], { cwd: repo, encoding: 'utf8' });
function commit(files, message) {
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(repo, path)), { recursive: true });
    writeFileSync(join(repo, path), text);
  }
  git('add', '-A');
  git('commit', '-q', '-m', message);
  return git('rev-parse', 'HEAD').stdout.trim();
}
git('init', '-q', '-b', 'main');
commit({ 'a.txt': '1' }, 'chore: start');
const one = commit({ 'src/one.sh': 'echo 1' }, 'feat: one');
commit({ 'src/one.sh': 'echo 1b' }, 'fix: one review');
commit({ 'other.sh': 'x' }, 'fix: unrelated');
const two = commit({ 'src/two.sh': 'echo 2' }, 'feat: two');
const end = commit({ 'src/two.sh': 'echo 2b' }, 'fix: final review');
const own = new Set(['feat: one', 'feat: two']);

const { PIPELINE_CASES, caseId, finishedPlans, fixRounds, manifestText, pickCases } = await import('../lib/pipeline-manifest.mjs');

test('finishedPlans reads the plan and merge commit of each completed line', () => {
  const text = [
    '- 2026-10-24 `docs/dforge/plans/2026-10-24-ui-ux-skill.md` — merged into `main` at c98d3488',
    '- 2026-10-27 `docs/dforge/plans/2026-10-26-faster-plans.md` — merged into `main` at 922e16c',
    'a note that names no plan',
  ].join('\n');
  assert.deepEqual(finishedPlans(text), [
    { plan: 'docs/dforge/plans/2026-10-24-ui-ux-skill.md', merge: 'c98d3488' },
    { plan: 'docs/dforge/plans/2026-10-26-faster-plans.md', merge: '922e16c' },
  ]);
});

test('fixRounds counts the commits on a task\'s files before the next task commit', () => {
  assert.equal(fixRounds({ result: one, merge: end, allowed: ['src/one.sh'], own }), 1);
  assert.equal(fixRounds({ result: one, merge: end, allowed: ['src/one.sh', 'other.sh'], own }), 2);
  assert.equal(fixRounds({ result: one, merge: end, allowed: ['src/two.sh'], own }), 0);
});

test('the last task of a plan has no fix rounds: what follows it is the final review', () => {
  assert.equal(fixRounds({ result: two, merge: end, allowed: ['src/two.sh'], own }), 0);
});

const c = (plan, task, fixRounds) => ({ plan, task, fixRounds, base: 'b'.repeat(40) });

test('pickCases takes fix-round tasks first, then fills round-robin across plans', () => {
  const list = [c('p1', 1, 0), c('p1', 2, 0), c('p1', 3, 1), c('p2', 1, 0), c('p2', 2, 2), c('p3', 1, 0)];
  assert.deepEqual(pickCases(list, 4).map(x => `${x.plan}:${x.task}`), ['p1:1', 'p1:3', 'p2:1', 'p2:2']);
  assert.deepEqual(pickCases(list, 2).map(x => `${x.plan}:${x.task}`), ['p1:3', 'p2:2']);
  assert.equal(pickCases(list).length, 6);
});

test('the manifest is a header and one tab-separated row per case', () => {
  const text = manifestText([{ plan: 'docs/dforge/plans/2026-10-24-ui-ux-skill.md', task: 2, base: 'a'.repeat(40), fixRounds: 1 }]);
  assert.equal(text, `case\tplan\ttask\tbase\tfixRounds\np-ui-ux-skill-t2\tdocs/dforge/plans/2026-10-24-ui-ux-skill.md\t2\t${'a'.repeat(40)}\t1\n`);
  assert.equal(caseId({ plan: 'docs/dforge/plans/2026-10-26-faster-plans.md', task: 11 }), 'p-faster-plans-t11');
});

test('the committed pipeline manifest has 12 well-formed cases', () => {
  const root = resolve(fileURLToPath(new URL('../../../', import.meta.url)));
  const lines = readFileSync(join(root, 'evals/tiers/cases/pipeline.tsv'), 'utf8').split('\n').filter(Boolean);
  assert.equal(lines[0], 'case\tplan\ttask\tbase\tfixRounds');
  assert.equal(lines.length - 1, PIPELINE_CASES);
  const rows = lines.slice(1).map(line => line.split('\t'));
  assert.equal(new Set(rows.map(r => r[0])).size, PIPELINE_CASES);
  for (const [id, plan, task, base, rounds] of rows) {
    assert.match(id, /^p-[a-z0-9-]+-t[0-9]+$/);
    assert.ok(existsSync(join(root, plan)), `${plan} exists`);
    assert.match(task, /^[0-9]+$/);
    assert.match(base, /^[0-9a-f]{40}$/);
    assert.match(rounds, /^[0-9]+$/);
  }
});
