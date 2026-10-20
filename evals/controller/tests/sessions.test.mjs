import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { after, test } from 'node:test';
import { flatten, inFlight, measureSessions, planSessions, planSlugs, projectFolder } from '../lib/sessions.mjs';

const top = mkdtempSync(join(tmpdir(), 'controller-sessions-'));
after(() => rmSync(top, { recursive: true, force: true }));
const usage = { input_tokens: 0, cache_read_input_tokens: 1000000, output_tokens: 0 };
const said = (id, content, model = 'claude-sonnet-5-5') => ({ type: 'assistant', effort: 'high', message: { id, model, usage, content } });
const bash = (id, command, extra = {}) => said(`m-${id}`, [{ type: 'tool_use', id, name: 'Bash', input: { command, ...extra } }]);
const skill = name => said(`s-${name}`, [{ type: 'tool_use', id: `u-${name}`, name: 'Skill', input: { skill: name } }]);
const brief = slug => bash(`u-${slug}`, `bash /p/scripts/task-brief docs/plans/${slug}.md 1`);
const launch = id => [bash(id, 'npm test', { run_in_background: true }), { type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: id, content: `Command running in background with ID: shell-${id}` }] } }];
const done = id => ({ type: 'user', message: { content: `<task-notification><tool-use-id>${id}</tool-use-id><status>completed</status></task-notification>` } });
const write = (path, records) => { mkdirSync(join(path, '..'), { recursive: true }); writeFileSync(path, records.map(r => JSON.stringify(r)).join('\n') + '\n'); };

const REPO = '/r/app';
const own = join(top, '-r-app');
const tree = join(top, '-r-app--worktrees-x');
const SDD = 'dforge:subagent-driven-development';
write(join(own, 's1.jsonl'), [skill(SDD), brief('2026-10-18-alpha'), ...launch('bg')]);
write(join(own, 's1/subagents/agent-x.jsonl'), [said('x1', [], 'claude-opus-5-5')]);
write(join(own, 's2.jsonl'), [brief('2026-10-18-alpha')]);
write(join(tree, 's3.jsonl'), [skill('dr-superpowers:subagent-driven-development'), brief('2026-10-18-beta')]);
write(join(tree, 's4.jsonl'), [skill(SDD), brief('2026-10-18-alpha')]);
write(join(own, 's5.jsonl'), [skill(SDD), brief('2026-10-18-beta'), bash('cat', 'cat docs/plans/2026-10-18-alpha.md')]);
write(join(top, '-r-app-two/s6.jsonl'), [skill(SDD), brief('2026-10-18-alpha')]);
write(join(own, 's7.jsonl'), [skill(SDD), brief('2026-10-18-alpha'), brief('2026-10-18-beta')]);
write(join(own, 's9.jsonl'), [skill(SDD), bash('ff', 'bash /p/scripts/review-route docs/plans/2026-10-18-alpha.md --final-fix README.md docs/guide.md && cat .dforge/handoff/latest.md'), bash('pk', "bash /p/scripts/review-package 'docs/plans/2026-10-18-alpha.md' a1 b2 out/package.md; cat notes.md"), bash('vr', 'PLAN=docs/plans/2026-10-18-alpha.md\nbash $P/scripts/task-brief "$PLAN" 2 > $W/task-2-brief.md\ncp x/task-3-report.md $W/task-3-report.md')]);
write(join(own, 's8.jsonl'), [...launch('early'), done('early'), ...launch('late'), bash('next', 'bash /p/scripts/next-step docs/plans/x.md'), done('late')]);
// A plain worktrees/ directory maps to <repo>-worktrees-…, not <repo>--….
const plain = join(top, '-r-app-worktrees-y');
write(join(plain, 's10.jsonl'), [skill(SDD), bash('q', 'bash "/p/scripts/task-brief" docs/plans/2026-10-18-delta.md 1')]);
write(join(plain, 's11.jsonl'), [skill(SDD), brief('2026-10-18-delta'), bash('rg', 'rg task-brief docs/plans/2026-10-18-epsilon.md')]);
const MEASURE = fileURLToPath(new URL('../measure.mjs', import.meta.url));

test('projectFolder spells a path as Claude Code names its project folder', () => {
  assert.equal(projectFolder('/root/repositories/darkraise-ai-plugins'), '-root-repositories-darkraise-ai-plugins');
});

test('planSessions finds the repository\'s sessions that ran a task script on the plan', () => {
  assert.deepEqual(planSessions('2026-10-18-alpha', REPO, top).map(f => f.slice(top.length)).sort(), ['/-r-app--worktrees-x/s4.jsonl', '/-r-app/s1.jsonl', '/-r-app/s7.jsonl', '/-r-app/s9.jsonl']);
  assert.deepEqual(planSessions('2026-10-18-gamma', REPO, top), []);
  assert.deepEqual(planSessions('x', REPO, join(top, 'missing')), []);
});

test('planSessions admits a plain worktrees/ directory and a quoted script path', () => {
  assert.deepEqual(planSessions('2026-10-18-delta', REPO, top).map(f => f.slice(top.length)).sort(), ['/-r-app-worktrees-y/s10.jsonl', '/-r-app-worktrees-y/s11.jsonl']);
  assert.deepEqual(planSlugs(join(plain, 's11.jsonl')), ['2026-10-18-delta']);
});

test('planSlugs names every plan a session executed', () => {
  assert.deepEqual(planSlugs(join(own, 's7.jsonl')), ['2026-10-18-alpha', '2026-10-18-beta']);
  assert.deepEqual(planSlugs(join(own, 's5.jsonl')), ['2026-10-18-beta']);
  assert.deepEqual(planSlugs(join(own, 's2.jsonl')), []);
  assert.deepEqual(planSlugs(join(own, 's9.jsonl')), ['2026-10-18-alpha']);
});

test('planSlugs counts a script run, not another command reading its path', () => {
  const dir = join(top, 'slugs');
  write(join(dir, 'cat.jsonl'), [skill(SDD), bash('c', 'cat $S/task-brief docs/plans/2026-10-18-zeta.md')]);
  write(join(dir, 'sed.jsonl'), [skill(SDD), bash('s', 'sed -n 1p /p/scripts/task-brief 2026-10-18-zeta.md')]);
  write(join(dir, 'echo.jsonl'), [skill(SDD), bash('e', "echo 'bash /p/scripts/task-brief docs/plans/2026-10-18-zeta.md'")]);
  write(join(dir, 'run.jsonl'), [skill(SDD), bash('v', 'S=/p/scripts; bash $S/task-brief docs/plans/2026-10-18-eta.md 1'), bash('t', 'timeout 60 bash /p/scripts/task-brief docs/plans/2026-10-18-theta.md 2'), bash('d', 'cd /w && /p/scripts/review-route docs/plans/2026-10-18-iota.md 3'), bash('a', 'FOO=1 /p/scripts/task-brief docs/plans/2026-10-18-kappa.md 4'), bash('w', 'env -u AR_SESSION timeout 60 bash /p/scripts/task-brief docs/plans/2026-10-18-lambda.md 5'), bash('u', 'bash -u /p/scripts/task-brief docs/plans/2026-10-18-mu.md 6'), bash('o', 'bash -o pipefail /p/scripts/task-brief docs/plans/2026-10-18-nu.md 7'), bash('eo', 'bash -eo pipefail /p/scripts/task-brief docs/plans/2026-10-18-xi.md 8'), bash('po', 'sh +o histexpand /p/scripts/review-package docs/plans/2026-10-18-omicron.md a b out.md'), bash('bb', '/bin/bash /p/scripts/task-brief docs/plans/2026-10-18-pi.md 9'), bash('ue', '/usr/bin/env timeout 60 bash /p/scripts/task-brief docs/plans/2026-10-18-rho.md 10'), bash('hd', "cat > notes.md <<-'EOF'\n\tbash /p/scripts/task-brief docs/plans/2026-10-18-zeta.md\n\tEOF\nbash /p/scripts/task-brief docs/plans/2026-10-18-sigma.md 11"), bash('nr', 'bash --norc /p/scripts/task-brief docs/plans/2026-10-18-tau.md 12')]);
  write(join(dir, 'heredoc.jsonl'), [skill(SDD), bash('h', 'cat <<EOF\nbash /p/scripts/task-brief docs/plans/2026-10-18-zeta.md\nEOF')]);
  assert.deepEqual(planSlugs(join(dir, 'heredoc.jsonl')), []);
  write(join(dir, 'herestring.jsonl'), [skill(SDD), bash('hs', 'jq . <<< "$x"\nbash /p/scripts/task-brief docs/plans/2026-10-18-a.md 1'), bash('hs2', 'jq . <<<"$y"\nbash /p/scripts/task-brief docs/plans/2026-10-18-b.md 1')]);
  assert.deepEqual(planSlugs(join(dir, 'herestring.jsonl')), ['2026-10-18-a', '2026-10-18-b']);
  write(join(dir, 'n.jsonl'), [skill(SDD), bash('n', 'bash -n /p/scripts/task-brief docs/plans/2026-10-18-zeta.md'), bash('bn', '/bin/bash -n /p/scripts/task-brief docs/plans/2026-10-18-zeta.md'), bash('nx', 'bash -nx /p/scripts/task-brief docs/plans/2026-10-18-zeta.md'), bash('en', 'sh -en /p/scripts/task-brief docs/plans/2026-10-18-zeta.md'), bash('on', 'bash -o noexec /p/scripts/task-brief docs/plans/2026-10-18-zeta.md'), bash('eon', 'bash -eo noexec /p/scripts/task-brief docs/plans/2026-10-18-zeta.md')]);
  write(join(dir, 'v.jsonl'), [skill(SDD), bash('v', 'command -v /p/scripts/task-brief docs/plans/2026-10-18-zeta.md')]);
  assert.deepEqual(planSlugs(join(dir, 'n.jsonl')), []);
  assert.deepEqual(planSlugs(join(dir, 'v.jsonl')), []);
  assert.deepEqual(planSlugs(join(dir, 'cat.jsonl')), []);
  assert.deepEqual(planSlugs(join(dir, 'sed.jsonl')), []);
  assert.deepEqual(planSlugs(join(dir, 'echo.jsonl')), []);
  assert.deepEqual(planSlugs(join(dir, 'run.jsonl')), ['2026-10-18-eta', '2026-10-18-iota', '2026-10-18-kappa', '2026-10-18-lambda', '2026-10-18-mu', '2026-10-18-nu', '2026-10-18-omicron', '2026-10-18-pi', '2026-10-18-rho', '2026-10-18-sigma', '2026-10-18-tau', '2026-10-18-theta', '2026-10-18-xi']);
});

test('inFlight counts launches running at a handoff or at the end', () => {
  assert.equal(inFlight(join(own, 's1.jsonl')), 1);
  assert.equal(inFlight(join(tree, 's3.jsonl')), 0);
  assert.equal(inFlight(join(own, 's8.jsonl')), 1);
});

test('inFlight fails when jq is missing instead of reporting nothing running', () => {
  const path = process.env.PATH;
  process.env.PATH = join(top, 'empty-bin');
  try {
    assert.throws(() => inFlight(join(own, 's1.jsonl')), /needs jq/);
  } finally {
    process.env.PATH = path;
  }
});

test('measureSessions sums controllers and subagents, and flatten rounds the costs', () => {
  const row = flatten(measureSessions([join(own, 's1.jsonl'), join(tree, 's4.jsonl')]));
  assert.equal(row.sessions, 2);
  assert.equal(row.calls, 5);
  assert.equal(row.controllerCost, 0.5);
  assert.equal(row.subagentCost, 0.2);
  assert.equal(row.inFlight, 1);
  assert.equal(row.dispatches, 0);
  assert.equal(row.costPerDispatch, 0);
  assert.equal(row.models, 'claude-sonnet-5-5');
});

test('measure.mjs prints a plan\'s row, and exits 1 when no session matches', () => {
  const run = (...args) => spawnSync(process.execPath, [MEASURE, ...args], { encoding: 'utf8', env: { ...process.env, CONTROLLER_EVAL_PROJECTS: top } });
  const ok = run('--plan', '2026-10-18-beta', '--repo', REPO);
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(JSON.parse(ok.stdout).sessions, 3);
  assert.equal(run('--plan', '2026-10-18-gamma', '--repo', REPO).status, 1);
  assert.equal(run('--plan', '2026-10-18-beta').status, 2);
  assert.equal(run('--session', join(top, 'no-such.jsonl')).status, 2);
  assert.equal(run().status, 2);
});
