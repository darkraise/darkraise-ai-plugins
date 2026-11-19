// Acceptance tests for the phase-0-verification spec's repository-level
// statements: release (A10), ci-scope (A11, A12, A14-A16), the workflow's wiring
// (A17, A27, A29), the Windows slice (A18, A28), the dagents path filter (A19,
// A20) and test-all's JUnit output (A25, A26).
import assert from 'node:assert/strict';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const ROOT = fileURLToPath(new URL('../', import.meta.url));
const BASH = process.env.DR_TEST_BASH ?? 'bash';
const yml = readFileSync(join(ROOT, '.github/workflows/validate.yml'), 'utf8').replace(/\r\n/g, '\n');
const releaseYml = readFileSync(join(ROOT, '.github/workflows/release.yml'), 'utf8').replace(/\r\n/g, '\n');

const cleanEnv = (extra = {}) => {
  const env = { ...process.env };
  for (const name of Object.keys(env)) if (name === 'NODE_TEST_CONTEXT' || name === 'CLAUDE_CONFIG_DIR' || name === 'CLAUDE_CODE_SESSION_ID' || name.startsWith('GITHUB_')) delete env[name];
  return { ...env, ...extra };
};
const scratchDir = (t, prefix = 'p0qa-') => {
  const dir = mkdtempSync(join(tmpdir(), prefix));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
};
const gitIn = (cwd, ...args) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.invalid', ...args], { cwd, encoding: 'utf8', timeout: 60000 }).trim();
const jobBlock = name => new RegExp(`\\n  ${name}:\\n((?:    .*\\n|\\n)+)`).exec(yml)?.[1] ?? '';
const needsOf = name => {
  const m = /^ {4}needs: (?:\[([^\]]*)\]|([\w-]+))$/m.exec(jobBlock(name));
  return m ? (m[1] ?? m[2]).split(',').map(need => need.trim()).filter(Boolean) : [];
};
const stepsOf = name => jobBlock(name).split(/\n {6}- /).slice(1).map(step => `- ${step}`);

// --- ci-scope ---
const SHARDS_16 = JSON.stringify(Array.from({ length: 16 }, (_, i) => i + 1));
const SHARDS_17 = JSON.stringify(Array.from({ length: 17 }, (_, i) => i + 1));
const FULL_RUN = (id, sha) => ({ databaseId: id, displayTitle: 'Validate marketplace (full)', headSha: sha, status: 'completed', conclusion: 'success' });
const SLICE_RUN = (id, sha) => ({ databaseId: id, displayTitle: 'Validate marketplace (slice)', headSha: sha, status: 'completed', conclusion: 'success' });

function scope(t) {
  const dir = scratchDir(t, 'p0qa-scope-');
  const repo = join(dir, 'repo');
  mkdirSync(repo);
  gitIn(repo, 'init', '-q', '-b', 'main');
  const commit = (files, subject) => {
    for (const file of [files].flat()) {
      mkdirSync(dirname(join(repo, file)), { recursive: true });
      writeFileSync(join(repo, file), `${subject}\n`);
      gitIn(repo, 'add', '--', file);
    }
    gitIn(repo, 'commit', '-q', '-m', subject);
    return gitIn(repo, 'rev-parse', 'HEAD');
  };
  let n = 0;
  const gh = (runs, failure) => {
    const file = join(dir, `gh-${++n}.cjs`);
    writeFileSync(file, failure === undefined ? `process.stdout.write(${JSON.stringify(JSON.stringify(runs))});` : `process.stderr.write(${JSON.stringify(failure)}); process.exit(1);`);
    return file;
  };
  const plan = env => {
    const out = join(dir, `out-${++n}`);
    writeFileSync(out, '');
    const result = spawnSync(process.execPath, [join(ROOT, 'scripts/ci-scope.mjs'), 'plan'], {
      cwd: repo, encoding: 'utf8', timeout: 60000,
      env: { PATH: process.env.PATH, SYSTEMROOT: process.env.SYSTEMROOT ?? '', GITHUB_OUTPUT: out, REPOSITORY: 'o/r', REF: 'refs/heads/main', ...env },
    });
    const outputs = Object.fromEntries(readFileSync(out, 'utf8').split('\n').filter(Boolean).map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));
    return { status: result.status, stdout: result.stdout, notices: result.stdout.split('\n').filter(line => line.startsWith('::notice::')), outputs };
  };
  return { commit, gh, plan };
}
const dagentsMatrix = outputs => {
  const key = Object.keys(outputs).find(name => /dagents/i.test(name));
  return key === undefined ? undefined : outputs[key];
};

const RELEASE_JOBS = ['scope', 'validate', 'dagents-changes', 'validate-dagents', 'windows', 'windows-dagents'];
const needsJson = (overrides = {}) => JSON.stringify(Object.fromEntries(['homelab', ...RELEASE_JOBS].map(name => [name, { result: overrides[name] ?? 'success', outputs: {} }])));
const releaseGate = (env, needs) => spawnSync(process.execPath, [join(ROOT, 'scripts/ci-scope.mjs'), 'release'], {
  encoding: 'utf8', timeout: 60000,
  env: { PATH: process.env.PATH, SYSTEMROOT: process.env.SYSTEMROOT ?? '', SCOPE: 'full', REF: 'refs/heads/main', NEEDS: needs, ...env },
}).status;

test('A11: ci-scope release exits 0 for a full run of main where homelab succeeded and every other job succeeded', () => {
  assert.equal(releaseGate({}, needsJson()), 0);
});

test('A11: ci-scope release exits 0 when homelab was skipped, as in the hosted fallback run', () => {
  assert.equal(releaseGate({}, needsJson({ homelab: 'skipped' })), 0);
});

test('A12: ci-scope release exits non-zero for a slice run, whatever else passed', () => {
  assert.notEqual(releaseGate({ SCOPE: 'slice' }, needsJson()), 0);
  assert.notEqual(releaseGate({ SCOPE: '' }, needsJson()), 0);
});

test('A12: ci-scope release exits non-zero for a ref other than main', () => {
  for (const REF of ['refs/heads/feature', 'refs/heads/main-2', 'refs/pull/7/merge', 'refs/tags/v1', '']) assert.notEqual(releaseGate({ REF }, needsJson()), 0, REF);
});

test('A12: ci-scope release exits non-zero when any needed job failed, was cancelled or was skipped', () => {
  for (const job of RELEASE_JOBS) {
    for (const result of ['failure', 'cancelled', 'skipped']) assert.notEqual(releaseGate({}, needsJson({ [job]: result })), 0, `${job} ${result}`);
  }
});

test('A12: ci-scope release exits non-zero when homelab failed or was cancelled', () => {
  for (const result of ['failure', 'cancelled']) assert.notEqual(releaseGate({}, needsJson({ homelab: result })), 0, `homelab ${result}`);
});

test('A14: ci-scope plan gives slice for a push or a pull request, with the one-job Windows slice matrix', t => {
  const { commit, plan } = scope(t);
  const sha = commit('a.txt', 'feat: a');
  for (const EVENT of ['push', 'pull_request']) {
    const result = plan({ EVENT, SHA: sha });
    assert.equal(result.status, 0, EVENT);
    assert.equal(result.outputs.scope, 'slice', EVENT);
    assert.equal(result.outputs.run, 'true', EVENT);
    assert.deepEqual(JSON.parse(result.outputs.windows), ['slice'], EVENT);
    assert.equal(result.notices.length, 1, `${EVENT}: one ::notice:: saying why`);
  }
});

test('A14: ci-scope plan gives an empty dagents Windows matrix for a push or a pull request', { skip: 'deferred: register row 10 (docs/dforge/registers/2026-11-19-phase-0-verification.md)' }, t => {
  const { commit, plan } = scope(t);
  const sha = commit('a.txt', 'feat: a');
  for (const EVENT of ['push', 'pull_request']) {
    const matrix = dagentsMatrix(plan({ EVENT, SHA: sha }).outputs);
    assert.notEqual(matrix, undefined, `${EVENT}: ci-scope plan prints no dagents Windows matrix`);
    assert.deepEqual(JSON.parse(matrix), [], EVENT);
  }
});

test('A14: the windows-dagents job runs only in a full-scope run', () => {
  assert.match(jobBlock('windows-dagents'), /needs\.scope\.outputs\.scope == 'full'/);
});

test('A15: ci-scope plan gives full for a schedule and for a scope=full dispatch, with all 16 Windows shards, whatever changed', t => {
  const { commit, gh, plan } = scope(t);
  commit('plugins/dagents/x.md', 'docs(dagents): x');
  const sha = commit('docs/only.md', 'docs: only docs');
  for (const [name, env] of [
    ['schedule', { EVENT: 'schedule', SHA: sha, CI_SCOPE_GH: gh([]) }],
    ['dispatch', { EVENT: 'workflow_dispatch', SCOPE_INPUT: 'full', SHA: sha, CI_SCOPE_GH: gh([FULL_RUN(11, '0'.repeat(40))]) }],
  ]) {
    const result = plan(env);
    assert.equal(result.status, 0, name);
    assert.equal(result.outputs.scope, 'full', name);
    assert.equal(result.outputs.run, 'true', name);
    assert.equal(result.outputs.windows, SHARDS_16, name);
    assert.equal(result.notices.length, 1, `${name}: one ::notice:: saying why`);
  }
});

test('A15: ci-scope plan gives all 17 dagents Windows shards for a schedule and for a scope=full dispatch', { skip: 'deferred: register row 11 (docs/dforge/registers/2026-11-19-phase-0-verification.md)' }, t => {
  const { commit, gh, plan } = scope(t);
  const sha = commit('docs/only.md', 'docs: only docs');
  for (const env of [{ EVENT: 'schedule', SHA: sha, CI_SCOPE_GH: gh([]) }, { EVENT: 'workflow_dispatch', SCOPE_INPUT: 'full', SHA: sha, CI_SCOPE_GH: gh([]) }]) {
    const matrix = dagentsMatrix(plan(env).outputs);
    assert.notEqual(matrix, undefined, `${env.EVENT}: ci-scope plan prints no dagents Windows matrix`);
    assert.equal(matrix, SHARDS_17, env.EVENT);
  }
});

test('A15: the windows-dagents job has all 17 shards', () => {
  const shards = /shard: \[([^\]]*)\]/.exec(jobBlock('windows-dagents'))?.[1].split(',').map(Number);
  assert.deepEqual(shards, Array.from({ length: 17 }, (_, i) => i + 1));
});

test('A16: a scheduled run skips when the last successful full run on main has its commit', t => {
  const { commit, gh, plan } = scope(t);
  const sha = commit('a.txt', 'feat: a');
  const result = plan({ EVENT: 'schedule', SHA: sha, CI_SCOPE_GH: gh([SLICE_RUN(12, '1'.repeat(40)), FULL_RUN(11, sha)]) });
  assert.equal(result.status, 0);
  assert.equal(result.outputs.run, 'false');
  assert.equal(result.notices.length, 1);
  assert.match(result.notices[0], /\b11\b/, 'the skip names the earlier run');
});

test('A16: a successful slice run of the same commit is no full run, so the schedule proceeds', t => {
  const { commit, gh, plan } = scope(t);
  const sha = commit('a.txt', 'feat: a');
  const result = plan({ EVENT: 'schedule', SHA: sha, CI_SCOPE_GH: gh([SLICE_RUN(12, sha)]) });
  assert.equal(result.outputs.run, 'true');
  assert.equal(result.notices.length, 1);
});

test('A16: a scheduled run skips when only release commits lie between the last full run and its commit', t => {
  const { commit, gh, plan } = scope(t);
  const validated = commit('plugins/foo/lib.mjs', 'feat(foo): x');
  commit(['plugins/foo/.claude-plugin/plugin.json', 'plugins/foo/.codex-plugin/plugin.json', 'plugins/foo/scripts/VERSION'], 'chore(foo): release 1.2.0');
  const head = commit(['plugins/bar/.claude-plugin/plugin.json'], 'chore(bar): release 0.3.1');
  const result = plan({ EVENT: 'schedule', SHA: head, CI_SCOPE_GH: gh([FULL_RUN(11, validated)]) });
  assert.equal(result.status, 0);
  assert.equal(result.outputs.run, 'false');
  assert.match(result.notices[0], /\b11\b/);
});

test('A16: a scheduled run proceeds when a change that is no release commit follows the last full run', t => {
  const { commit, gh, plan } = scope(t);
  const validated = commit('plugins/foo/lib.mjs', 'feat(foo): x');
  commit('plugins/foo/.claude-plugin/plugin.json', 'chore(foo): release 1.2.0');
  const head = commit('plugins/foo/lib.mjs', 'fix(foo): y');
  const result = plan({ EVENT: 'schedule', SHA: head, CI_SCOPE_GH: gh([FULL_RUN(11, validated)]) });
  assert.equal(result.outputs.run, 'true');
  assert.equal(result.notices.length, 1);
});

test('A16: a release-titled commit that touches other files is no release commit', t => {
  const { commit, gh, plan } = scope(t);
  const validated = commit('plugins/foo/lib.mjs', 'feat(foo): x');
  const head = commit('plugins/foo/lib.mjs', 'chore(foo): release 9.9.9');
  assert.equal(plan({ EVENT: 'schedule', SHA: head, CI_SCOPE_GH: gh([FULL_RUN(11, validated)]) }).outputs.run, 'true');
});

test('A16: a scheduled run proceeds with no earlier full run, an unreachable commit or a failed lookup, saying why', t => {
  const { commit, gh, plan } = scope(t);
  const sha = commit('a.txt', 'feat: a');
  const none = plan({ EVENT: 'schedule', SHA: sha, CI_SCOPE_GH: gh([]) });
  assert.equal(none.outputs.run, 'true');
  assert.equal(none.notices.length, 1);
  const unreachable = plan({ EVENT: 'schedule', SHA: sha, CI_SCOPE_GH: gh([FULL_RUN(11, 'f'.repeat(40))]) });
  assert.equal(unreachable.status, 0);
  assert.equal(unreachable.outputs.run, 'true');
  assert.equal(unreachable.notices.length, 1);
  const failed = plan({ EVENT: 'schedule', SHA: sha, CI_SCOPE_GH: gh(null, 'HTTP 403: Resource not accessible by integration') });
  assert.equal(failed.status, 0);
  assert.equal(failed.outputs.run, 'true');
  assert.equal(failed.outputs.scope, 'full');
  assert.equal(failed.notices.length, 1);
  assert.match(failed.notices[0], /Resource not accessible by integration/, 'the notice carries the lookup error');
});

test('A16: a scope=full dispatch on a commit a full run validated still runs', t => {
  const { commit, gh, plan } = scope(t);
  const sha = commit('a.txt', 'feat: a');
  const result = plan({ EVENT: 'workflow_dispatch', SCOPE_INPUT: 'full', SHA: sha, CI_SCOPE_GH: gh([FULL_RUN(11, sha)]) });
  assert.equal(result.outputs.run, 'true');
  assert.equal(result.outputs.scope, 'full');
});

// --- release.mjs --validated (A10) ---
test('A10: release.mjs --validated exits 0 and releases nothing when HEAD differs, and releases when they match', { skip: process.platform === 'win32' && 'the gh stub is a shell script' }, t => {
  const dir = scratchDir(t, 'p0qa-release-');
  const origin = join(dir, 'origin.git');
  const repo = join(dir, 'repo');
  const bin = join(dir, 'bin');
  mkdirSync(bin);
  const log = join(dir, 'gh.log');
  writeFileSync(join(bin, 'gh'), `#!/bin/sh\necho "$@" >> "${log}"\nif [ "$1 $2" = "release list" ]; then echo '[]'; fi\n`);
  chmodSync(join(bin, 'gh'), 0o755);
  gitIn(dir, 'init', '-q', '--bare', '-b', 'main', origin);
  mkdirSync(repo);
  gitIn(repo, 'init', '-q', '-b', 'main');
  gitIn(repo, 'remote', 'add', 'origin', origin);
  mkdirSync(join(repo, 'scripts'));
  mkdirSync(join(repo, '.claude-plugin'));
  mkdirSync(join(repo, 'plugins/foo/.claude-plugin'), { recursive: true });
  cpSync(join(ROOT, 'scripts/release.mjs'), join(repo, 'scripts/release.mjs'));
  writeFileSync(join(repo, 'scripts/validate-repository.mjs'), 'process.exit(0);\n');
  writeFileSync(join(repo, '.claude-plugin/marketplace.json'), JSON.stringify({ plugins: [{ name: 'foo' }] }));
  writeFileSync(join(repo, 'plugins/foo/.claude-plugin/plugin.json'), JSON.stringify({ name: 'foo', version: '1.0.0' }, null, 2));
  gitIn(repo, 'add', '-A');
  gitIn(repo, 'commit', '-q', '-m', 'feat(foo): start');
  const validated = gitIn(repo, 'rev-parse', 'HEAD');
  gitIn(repo, 'tag', '-a', 'foo-v1.0.0', '-m', 'first');
  writeFileSync(join(repo, 'plugins/foo/lib.mjs'), 'export {};\n');
  gitIn(repo, 'add', '-A');
  gitIn(repo, 'commit', '-q', '-m', 'fix(foo): a later fix');
  const head = gitIn(repo, 'rev-parse', 'HEAD');
  gitIn(repo, 'push', '-q', 'origin', 'main', '--tags');
  const run = sha => spawnSync(process.execPath, ['scripts/release.mjs', '--validated', sha], { cwd: repo, encoding: 'utf8', timeout: 120000, env: cleanEnv({ PATH: `${bin}${delimiter}${process.env.PATH}` }) });

  const moved = run(validated);
  assert.equal(moved.status, 0, moved.stderr);
  assert.equal(gitIn(repo, 'rev-parse', 'HEAD'), head, 'no commit');
  assert.equal(gitIn(repo, 'tag', '--list'), 'foo-v1.0.0', 'no tag');
  assert.equal(gitIn(origin, 'rev-parse', 'refs/heads/main'), head, 'no push');
  assert.equal(gitIn(origin, 'tag', '--list'), 'foo-v1.0.0', 'no tag pushed');
  assert.equal(existsSync(log), false, 'no gh call');

  const matched = run(head);
  assert.equal(matched.status, 0, matched.stderr);
  const released = gitIn(repo, 'rev-parse', 'HEAD');
  assert.notEqual(released, head, 'a release commit');
  assert.equal(gitIn(repo, 'log', '-1', '--format=%s'), 'chore(foo): release 1.0.1');
  assert.equal(gitIn(repo, 'tag', '--list', 'foo-v*').split('\n').sort().join(' '), 'foo-v1.0.0 foo-v1.0.1');
  assert.equal(gitIn(origin, 'rev-parse', 'refs/heads/main'), released, 'pushed');
  assert.ok(gitIn(origin, 'tag', '--list').includes('foo-v1.0.1'), 'the tag is pushed');
  assert.match(readFileSync(log, 'utf8'), /release create foo-v1\.0\.1/);
});

test('A10: release.yml has no workflow_run trigger and is dispatched', () => {
  assert.doesNotMatch(releaseYml, /workflow_run/);
  assert.match(releaseYml, /^ {2}workflow_dispatch:/m);
});

// --- the workflow's wiring (A17, A27, A29) ---
test('A17: the homelab fallback re-dispatches with -f scope= and -f from=, taken from the scope job and the push base', () => {
  const homelab = jobBlock('homelab');
  const dispatch = /^.*gh workflow run validate\.yml.*$/m.exec(homelab)?.[0] ?? '';
  assert.ok(dispatch, 'the fallback dispatches validate.yml');
  assert.match(dispatch, /-f scope=\S*SCOPE/);
  assert.match(dispatch, /-f from=\S*FROM/);
  assert.match(homelab, /^ +SCOPE: \$\{\{ needs\.scope\.outputs\.scope \}\}$/m);
  assert.match(homelab, /^ +FROM: \$\{\{ github\.event\.before \|\| github\.event\.pull_request\.base\.sha \}\}$/m);
});

test('A17: the dagents filter compares a dispatch against its from input', () => {
  const filter = jobBlock('dagents-changes');
  assert.match(filter, /FROM: \$\{\{ inputs\.from \}\}/);
  assert.match(filter, /workflow_dispatch\) from=\$FROM/);
});

test('A27: full-scope Windows jobs pass --junit and upload that directory as an artifact named with the shard, unless cancelled', () => {
  for (const [name, artifact] of [['windows', /junit-windows-\$\{\{ matrix\.shard \}\}/], ['windows-dagents', /junit-windows-dagents-\$\{\{ matrix\.shard \}\}/]]) {
    const steps = stepsOf(name);
    const dir = steps.map(step => /--junit (\S+)/.exec(step)?.[1]).find(Boolean);
    assert.ok(dir, `${name} passes --junit`);
    const upload = steps.find(step => /actions\/upload-artifact/.test(step));
    assert.ok(upload, `${name} uploads an artifact`);
    assert.match(upload, artifact, `${name}: the artifact is named with the shard`);
    assert.match(upload, new RegExp(`^ +path: ${dir}$`, 'm'), `${name}: uploads the --junit directory`);
    const condition = /^ +if: (.*)$/m.exec(upload)?.[1] ?? '';
    assert.match(condition, /!cancelled\(\)/, `${name}: runs unless the run was cancelled`);
    assert.doesNotMatch(condition, /always\(\)|failure\(\)|success\(\)/, name);
  }
});

test('A29: every Windows job needs homelab and runs when its result is success or skipped', () => {
  for (const name of ['windows', 'windows-dagents']) {
    assert.ok(needsOf(name).includes('homelab'), `${name} needs homelab`);
    const condition = /^ {4}if: (.*)$/m.exec(jobBlock(name))?.[1] ?? '';
    assert.match(condition, /needs\.homelab\.result/, name);
    assert.match(condition, /'success'|"success"/, name);
    assert.match(condition, /'skipped'|"skipped"/, name);
    assert.match(condition, /!cancelled\(\)/, `${name}: a skipped homelab must not skip the job`);
  }
});

// --- the dagents path filter (A19, A20) ---
function filterScript() {
  const lines = yml.split('\n');
  const id = lines.findIndex(line => /^ +- id: filter$/.test(line));
  const run = lines.findIndex((line, i) => i > id && /^ +run: \|$/.test(line));
  assert.ok(id >= 0 && run > id, 'the dagents change filter step is missing');
  const body = [];
  for (const line of lines.slice(run + 1)) {
    if (line.trim() !== '' && !line.startsWith(' '.repeat(10))) break;
    body.push(line.slice(10));
  }
  return body.join('\n');
}

test('A19: the dagents filter is true for dagents, its suites, the five root scripts and the workflow, false for everything else', t => {
  const dir = scratchDir(t, 'p0qa-filter-');
  const repo = join(dir, 'repo');
  mkdirSync(repo);
  gitIn(repo, 'init', '-q', '-b', 'main');
  writeFileSync(join(repo, 'README.md'), 'base\n');
  gitIn(repo, 'add', '-A');
  gitIn(repo, 'commit', '-q', '-m', 'base');
  const base = gitIn(repo, 'rev-parse', 'HEAD');
  const script = filterScript();
  const decide = (file, event = 'push') => {
    mkdirSync(dirname(join(repo, file)), { recursive: true });
    writeFileSync(join(repo, file), 'change\n');
    gitIn(repo, 'add', '-A');
    gitIn(repo, 'commit', '-q', '-m', `change ${file}`);
    const head = gitIn(repo, 'rev-parse', 'HEAD');
    const out = join(dir, `out-${head}`);
    writeFileSync(out, '');
    const result = spawnSync(BASH, ['-c', script], { cwd: repo, encoding: 'utf8', timeout: 60000, env: cleanEnv({ EVENT: event, BEFORE: base, BASE: base, FROM: base, HEAD: head, GITHUB_OUTPUT: out }) });
    assert.equal(result.status, 0, result.stderr);
    gitIn(repo, 'reset', '-q', '--hard', base);
    return /dagents=(\w+)/.exec(readFileSync(out, 'utf8'))?.[1];
  };
  for (const file of ['plugins/dagents/skills/x/SKILL.md', 'tests/dagents/x.test.sh', 'scripts/test-all.mjs', 'scripts/test-shards.mjs', 'scripts/validate-repository.mjs', 'scripts/lint-portability.mjs', 'scripts/dagents-rename.mjs', '.github/workflows/validate.yml']) {
    assert.equal(decide(file), 'true', `${file} (push)`);
    assert.equal(decide(file, 'pull_request'), 'true', `${file} (pull request)`);
  }
  for (const file of ['tests/dforge/x.test.sh', 'tests/dflow/x.test.mjs', 'tests/ci-scope.test.mjs', 'scripts/release.mjs', 'plugins/dforge/x.md', 'plugins/dflow/x.md', 'docs/a.md']) {
    assert.equal(decide(file), 'false', `${file} (push)`);
    assert.equal(decide(file, 'pull_request'), 'false', `${file} (pull request)`);
  }
});

test('A20: A29 of dagents-split fails when a tests/dagents suite runs a root script, or one it imports, that the filter does not match', async t => {
  const dir = scratchDir(t, 'p0qa-drift-');
  const tree = join(dir, 'tree');
  for (const sub of ['scripts', 'tests/dagents', '.github/workflows']) mkdirSync(join(tree, sub), { recursive: true });
  for (const file of readdirSync(join(ROOT, 'scripts')).filter(name => name.endsWith('.mjs'))) cpSync(join(ROOT, 'scripts', file), join(tree, 'scripts', file));
  cpSync(join(ROOT, 'tests/dagents'), join(tree, 'tests/dagents'), { recursive: true });
  cpSync(join(ROOT, '.github/workflows/validate.yml'), join(tree, '.github/workflows/validate.yml'));
  cpSync(join(ROOT, 'tests/dagents-split.acceptance.test.mjs'), join(tree, 'tests/dagents-split.acceptance.test.mjs'));
  const run = cwd => new Promise(resolve => {
    const child = spawn(process.execPath, ['--test', '--test-name-pattern=A29', 'tests/dagents-split.acceptance.test.mjs'], { cwd, env: cleanEnv() });
    let output = '';
    child.stdout.on('data', chunk => { output += chunk; });
    child.stderr.on('data', chunk => { output += chunk; });
    const timer = setTimeout(() => child.kill(), 120000);
    child.on('close', status => { clearTimeout(timer); resolve({ status, output }); });
  });
  // Three copies of the tree: as it is, with a suite that runs scripts/release.mjs, and with a script a suite runs importing it.
  const copies = ['baseline', 'named', 'imported'].map(name => {
    const copy = join(dir, name);
    cpSync(tree, copy, { recursive: true });
    return copy;
  });
  writeFileSync(join(copies[1], 'tests/dagents/zz-qa.test.sh'), '#!/usr/bin/env bash\nnode scripts/release.mjs --dry-run\n');
  writeFileSync(join(copies[2], 'scripts/test-all.mjs'), `import { x } from './release.mjs';\n${readFileSync(join(copies[2], 'scripts/test-all.mjs'), 'utf8')}`);
  const [baseline, named, imported] = await Promise.all(copies.map(run));
  assert.equal(baseline.status, 0, `baseline (scratch tree) must pass:\n${baseline.output}`);
  assert.notEqual(named.status, 0, 'a dagents suite that runs scripts/release.mjs');
  assert.match(named.output, /scripts\/release\.mjs/);
  assert.notEqual(imported.status, 0, 'a script a dagents suite runs imports scripts/release.mjs');
  assert.match(imported.output, /scripts\/release\.mjs/);
});

// --- the Windows slice (A18, A28) ---
const SLICE = ['darkmem-sync', 'register', 'dforge-migrate', 'dforge-state', 'working-directory', 'roadmap', 'plan-amend'].map(name => `tests/dforge/${name}.test.sh`);
const listed = (cwd, ...args) => {
  const result = spawnSync(process.execPath, ['scripts/test-all.mjs', '--list', ...args], { cwd, encoding: 'utf8', timeout: 60000, env: cleanEnv() });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.split('\n').filter(Boolean);
};
// A PATH without claude, so test-all adds no `claude plugin test` job to a scratch tree.
const PATH_NO_CLAUDE = process.env.PATH.split(delimiter).filter(dir => !['claude', 'claude.exe', 'claude.cmd'].some(name => existsSync(join(dir, name)))).join(delimiter);

test('A28: windowsSlice names exactly the seven suites and the Windows slice is one job', async () => {
  const { windowsSlice } = await import(new URL('../scripts/test-shards.mjs', import.meta.url).href);
  assert.deepEqual([...windowsSlice].sort(), [...SLICE].sort());
  const steps = stepsOf('windows').filter(step => /node scripts\/test-all\.mjs/.test(step));
  assert.ok(steps.some(step => /--slice/.test(step)), 'the windows job runs test-all --slice for the slice shard');
});

test('A28: the slice is a single entry in the Windows matrix of a push', t => {
  const { commit, plan } = scope(t);
  const sha = commit('a.txt', 'feat: a');
  assert.equal(plan({ EVENT: 'push', SHA: sha }).outputs.windows, '["slice"]');
});

test('A18: test-all --slice lists exactly the suites windowsSlice names', async () => {
  const { windowsSlice } = await import(new URL('../scripts/test-shards.mjs', import.meta.url).href);
  assert.deepEqual([...new Set(listed(ROOT, '--slice').map(line => line.split(' ')[0]))].sort(), [...windowsSlice].sort());
});

test('A18: test-all --slice runs exactly the suites windowsSlice names', t => {
  const dir = scratchDir(t, 'p0qa-slice-');
  for (const sub of ['scripts', 'tests/dforge', 'tests/dflow']) mkdirSync(join(dir, sub), { recursive: true });
  cpSync(join(ROOT, 'scripts/test-all.mjs'), join(dir, 'scripts/test-all.mjs'));
  const shards = readFileSync(join(ROOT, 'scripts/test-shards.mjs'), 'utf8');
  const replaced = shards.replace(/export const windowsSlice = \[[^\]]*\];/, "export const windowsSlice = ['tests/dforge/a.test.sh', 'tests/dforge/c.test.sh'];");
  assert.notEqual(replaced, shards, 'windowsSlice was found');
  writeFileSync(join(dir, 'scripts/test-shards.mjs'), replaced);
  for (const name of ['a', 'b', 'c', 'd']) writeFileSync(join(dir, `tests/dforge/${name}.test.sh`), `echo ${name} >> "$RAN_LOG"\necho "ok   - ${name}"\n`);
  const log = join(dir, 'ran.log');
  const result = spawnSync(process.execPath, ['scripts/test-all.mjs', '--slice'], { cwd: dir, encoding: 'utf8', timeout: 120000, env: cleanEnv({ PATH: PATH_NO_CLAUDE, RAN_LOG: log }) });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.deepEqual(readFileSync(log, 'utf8').split('\n').filter(Boolean).sort(), ['a', 'c']);
});

test('A18: tests/test-shards.test.mjs fails when a suite windowsSlice lists does not exist', t => {
  const dir = scratchDir(t, 'p0qa-shards-');
  mkdirSync(join(dir, 'tests'));
  cpSync(join(ROOT, 'scripts'), join(dir, 'scripts'), { recursive: true });
  cpSync(join(ROOT, '.github'), join(dir, '.github'), { recursive: true });
  for (const entry of readdirSync(join(ROOT, 'tests'))) {
    if (entry === 'test-shards.test.mjs') cpSync(join(ROOT, 'tests', entry), join(dir, 'tests', entry));
    else symlinkSync(join(ROOT, 'tests', entry), join(dir, 'tests', entry), 'junction');
  }
  const run = () => spawnSync(process.execPath, ['--test', 'tests/test-shards.test.mjs'], { cwd: dir, encoding: 'utf8', timeout: 120000, env: cleanEnv({ PATH: PATH_NO_CLAUDE }) });
  const bogus = 'tests/dforge/no-such-suite-qa.test.sh';
  const baseline = run();
  assert.ok(!(baseline.stdout + baseline.stderr).includes(bogus), 'the scratch tree names no missing suite before the edit');
  const shards = readFileSync(join(dir, 'scripts/test-shards.mjs'), 'utf8');
  const edited = shards.replace(/(export const windowsSlice = \[)/, `$1\n  '${bogus}',`);
  assert.notEqual(edited, shards);
  writeFileSync(join(dir, 'scripts/test-shards.mjs'), edited);
  const broken = run();
  assert.notEqual(broken.status, 0, 'a listed suite that does not exist');
  assert.ok((broken.stdout + broken.stderr).includes(bogus), 'the failure names the missing suite');
});

// --- test-all --junit (A25, A26) ---
function junitTree(t, { paced = true } = {}) {
  const dir = scratchDir(t, 'p0qa-junit-');
  mkdirSync(join(dir, 'scripts'));
  mkdirSync(join(dir, 'tests/dagents'), { recursive: true });
  for (const file of ['test-all.mjs', 'test-shards.mjs']) cpSync(join(ROOT, 'scripts', file), join(dir, 'scripts', file));
  writeFileSync(join(dir, 'tests/dagents/alpha.test.sh'), [
    paced ? 'sleep 1' : ':', "echo 'ok   - first check'", paced ? 'sleep 1.2' : ':', "echo 'note: not a case'",
    `echo 'FAIL - second <check> & "quoted"'`, paced ? 'sleep 0.5' : ':', "echo 'ok   - third check'", 'echo "to stderr" >&2', 'exit 1', '',
  ].join('\n'));
  writeFileSync(join(dir, 'tests/dagents/beta.test.sh'), 'echo plain output\n');
  return dir;
}
const testAll = (dir, ...args) => spawnSync(process.execPath, ['scripts/test-all.mjs', '--plugin', 'dagents', ...args], { cwd: dir, encoding: 'utf8', timeout: 120000, env: cleanEnv({ PATH: PATH_NO_CLAUDE }) });
const attrs = tag => Object.fromEntries([...tag.matchAll(/([\w-]+)="([^"]*)"/g)].map(match => [match[1], match[2]]));
const cases = xml => [...xml.matchAll(/<testcase\b([^>]*?)(\/?)>/g)].map(match => attrs(match[1]));

for (const jobs of ['1', '2']) {
  test(`A25: --junit writes one JUnit file per job with one timed case per ok/FAIL line (--jobs ${jobs})`, t => {
    const dir = junitTree(t);
    const result = testAll(dir, '--jobs', jobs, '--junit', 'junit');
    assert.equal(result.status, 1, 'alpha fails, so the run fails');
    const files = readdirSync(join(dir, 'junit')).filter(name => name.endsWith('.xml')).sort();
    assert.equal(files.length, 2, `one file per job: ${files}`);
    const read = suite => readFileSync(join(dir, 'junit', files.find(name => name.includes(suite))), 'utf8');
    const alpha = read('alpha');
    const rows = cases(alpha);
    assert.equal(rows.length, 3, 'one case per ok/FAIL line, none for other output');
    assert.deepEqual(rows.map(row => row.name), ['first check', 'second &lt;check&gt; &amp; &quot;quoted&quot;', 'third check']);
    assert.ok(rows.every(row => row.file === 'tests/dagents/alpha.test.sh'), 'file carries the suite path');
    assert.equal((alpha.match(/<failure\b/g) ?? []).length, 1, 'the FAIL line is a failure');
    assert.match(alpha, /<testcase\b[^>]*name="second[^>]*>\s*<failure\b/);
    assert.ok(Number(rows[1].time) >= 1.0 && Number(rows[1].time) < 4, `second case is timed from the previous line: ${rows[1].time}`);
    assert.ok(Number(rows[2].time) >= 0.4 && Number(rows[2].time) < 3, `third case is timed from the previous line: ${rows[2].time}`);
    assert.ok(Number(rows[0].time) < 0.6, `the time before the first line is no case: ${rows[0].time}`);
    for (const value of alpha.matchAll(/="([^"]*)"/g)) assert.doesNotMatch(value[1].replace(/&(?:amp|lt|gt|quot|apos);/g, ''), /[<&"]/, `unescaped text in ${value[0]}`);
    assert.equal(cases(read('beta')).length, 1, 'a job with no ok/FAIL line gets one case');
    const profile = spawnSync(BASH, [join(ROOT, 'plugins/dforge/scripts/test-profile'), join(dir, 'junit')], { encoding: 'utf8', timeout: 60000 });
    assert.equal(profile.status, 0, profile.stderr);
    assert.match(profile.stdout, /tests\/dagents\/alpha\.test\.sh/);
    const brief = spawnSync(BASH, [join(ROOT, 'plugins/dforge/scripts/test-profile'), '--brief', join(dir, 'junit')], { encoding: 'utf8', timeout: 60000 });
    assert.equal(brief.status, 0, brief.stderr);
    const overhead = Number(/\boverhead=([\d.]+)s/.exec(brief.stdout)?.[1]);
    assert.ok(overhead >= 0.9, `the time before the first line is reported as overhead: ${brief.stdout}`);
  });
}

// What base's test-all printed for these suites, as literal text, with the job
// times masked; parallel output is compared as a sorted set of lines.
const SKIP_CLAUDE = 'Skipped claude plugin test: claude not found';
const SKIP_TSC = 'Skipped tsc --noEmit -p plugins/dagents: the generated types are missing (Claude Code writes them when it loads plugins/dagents from the folder)';
const masked = text => text.replace(/ in \d+\.\d+s \(/g, ' in Ns (');
test('A26: without --junit a sequential run prints and exits as it did', t => {
  const dir = junitTree(t, { paced: false });
  const result = testAll(dir, '--jobs', '1');
  assert.equal(result.status, 1);
  assert.equal(masked(result.stdout), [
    SKIP_CLAUDE, SKIP_TSC, '', 'Running tests/dagents/alpha.test.sh', 'ok   - first check', 'note: not a case', 'FAIL - second <check> & "quoted"', 'ok   - third check',
    'Finished tests/dagents/alpha.test.sh in Ns (exit 1)', '', 'Running tests/dagents/beta.test.sh', 'plain output', 'Finished tests/dagents/beta.test.sh in Ns (exit 0)', '',
  ].join('\n'));
  assert.equal(result.stderr, 'to stderr\n');
  assert.equal(existsSync(join(dir, 'junit')), false, 'no JUnit directory');
});

test('A26: without --junit a parallel run prints and exits as it did', t => {
  const dir = junitTree(t, { paced: false });
  const result = testAll(dir, '--jobs', '2');
  assert.equal(result.status, 1);
  assert.deepEqual(masked(result.stdout).split('\n').filter(Boolean).sort(), [
    SKIP_CLAUDE, SKIP_TSC, 'Running 2 jobs, 2 at a time (--jobs 1 runs them in order)', 'Running tests/dagents/alpha.test.sh', 'ok   - first check', 'note: not a case',
    'FAIL - second <check> & "quoted"', 'ok   - third check', 'Finished tests/dagents/alpha.test.sh in Ns (exit 1)', 'Running tests/dagents/beta.test.sh', 'plain output',
    'Finished tests/dagents/beta.test.sh in Ns (exit 0)', 'to stderr',
  ].sort());
  assert.equal(result.stderr, '', 'a parallel job\'s stderr is held in its block and printed on stdout');
  assert.equal(existsSync(join(dir, 'junit')), false, 'no JUnit directory');
});

test('A26: --junit leaves the exit status and the printed lines as they are, sequential and parallel', t => {
  const dir = junitTree(t, { paced: false });
  for (const jobs of ['1', '2']) {
    const plain = testAll(dir, '--jobs', jobs);
    const timed = testAll(dir, '--jobs', jobs, '--junit', join(dir, `junit-${jobs}`));
    assert.equal(timed.status, plain.status, `--jobs ${jobs}: exit status`);
    assert.deepEqual(masked(timed.stdout).split('\n').filter(Boolean).sort(), masked(plain.stdout).split('\n').filter(Boolean).sort(), `--jobs ${jobs}: stdout`);
    assert.equal(timed.stderr, plain.stderr, `--jobs ${jobs}: stderr`);
  }
});
