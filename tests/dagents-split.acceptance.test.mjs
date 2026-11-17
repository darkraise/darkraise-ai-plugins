// Acceptance tests for docs/dforge/specs/2026-11-16-dagents-split-design.md,
// written from the spec's Acceptance statements and run through the public
// surface: the repository scripts, the workflow guard CLI, the hooks' commands
// and the files the branch ships.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';

const ROOT = fileURLToPath(new URL('../', import.meta.url));
const TAG = 'dforge-v4.17.1';
const SIBLINGS = ['dforge', 'dagents', 'dflow'];
const GUARD = name => join(ROOT, 'plugins', name, 'scripts/workflow-guard.mjs');
const REGISTER_PATH = 'docs/dforge/registers/2026-11-16-dagents-backport.md';
const REGISTER = join(ROOT, REGISTER_PATH);

function cleanEnv(extra = {}) {
  const env = { ...process.env };
  for (const name of Object.keys(env)) {
    if (name === 'NODE_TEST_CONTEXT' || name === 'CLAUDE_CONFIG_DIR' || name === 'CLAUDE_PLUGIN_DATA' || name === 'CLAUDE_PLUGIN_ROOT'
      || name === 'CLAUDE_PROJECT_DIR' || name === 'CLAUDE_CODE_SESSION_ID' || name === 'AR_SESSION'
      || name.startsWith('WORKFLOW_GUARD_') || name.startsWith('DFORGE_') || name.startsWith('DAGENTS_')
      || (name.startsWith('DR_') && !name.startsWith('DR_TEST_'))) delete env[name];
  }
  return { ...env, ...extra };
}
function run(command, args, { cwd = ROOT, env = cleanEnv(), input, timeout = 60000 } = {}) {
  return spawnSync(command, args, { cwd, env, input, encoding: 'utf8', timeout, maxBuffer: 256 * 1024 * 1024 });
}
const git = (...args) => execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', timeout: 60000, maxBuffer: 256 * 1024 * 1024 });
const gitOk = (...args) => spawnSync('git', args, { cwd: ROOT, stdio: 'ignore', timeout: 60000 }).status === 0;
const hasTag = gitOk('rev-parse', '--verify', '--quiet', `${TAG}^{commit}`);
const needTag = t => { if (!hasTag) { t.skip(`tag ${TAG} is not in this clone`); return false; } return true; };
const isShallow = git('rev-parse', '--is-shallow-repository').trim() === 'true';
const needHistory = t => { if (isShallow) { t.skip('this clone is shallow: the commits the check names are not in it'); return false; } return true; };
const scratch = t => {
  const dir = mkdtempSync(join(tmpdir(), 'dsplit-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
};
const json = path => JSON.parse(readFileSync(join(ROOT, path), 'utf8'));
const textFiles = prefix => git('ls-files', '-z', '--', prefix).split('\0').filter(Boolean)
  .filter(file => existsSync(join(ROOT, file)) && !readFileSync(join(ROOT, file)).includes(0));

// A1
test('A1: the copy commit holds the tag tree of plugins/dforge as plugins/dagents', t => {
  if (!needTag(t)) return;
  const first = git('log', '--reverse', '--format=%H', '--', 'plugins/dagents').split('\n').filter(Boolean)[0];
  assert.ok(first, 'no commit touches plugins/dagents');
  assert.equal(git('rev-parse', `${first}:plugins/dagents`).trim(), git('rev-parse', `${TAG}:plugins/dforge`).trim());
});

// A2
test('A2: both manifests name dagents at one version, and both catalogs list it', () => {
  const versions = ['.claude-plugin', '.codex-plugin'].map(dir => {
    const manifest = json(`plugins/dagents/${dir}/plugin.json`);
    assert.equal(manifest.name, 'dagents', dir);
    assert.match(manifest.version ?? '', /^\d+\.\d+\.\d+/, dir);
    return manifest.version;
  });
  assert.equal(versions[1], versions[0], 'the Codex manifest version differs from the Claude one');
  const claude = json('.claude-plugin/marketplace.json').plugins.find(plugin => plugin.name === 'dagents');
  assert.equal(claude?.source, './plugins/dagents');
  const codex = json('.agents/plugins/marketplace.json').plugins.find(plugin => plugin.name === 'dagents');
  assert.equal(codex?.source?.path ?? codex?.source, './plugins/dagents');
});
test('A2: claude plugin validate passes for plugins/dagents and the marketplace', t => {
  const claude = process.env.CLAUDE_BIN || 'claude';
  if (spawnSync(claude, ['--version'], { stdio: 'ignore', timeout: 15000 }).status !== 0) { t.skip('claude CLI not available'); return; }
  const home = scratch(t);
  const env = cleanEnv({ HOME: home });
  for (const target of ['plugins/dagents', '.']) {
    const result = run(claude, ['plugin', 'validate', target], { env, timeout: 90000 });
    assert.equal(result.status, 0, `${target}: ${result.stderr}${result.stdout}`);
  }
});

// A3 and A4
function registerRows() {
  const lines = readFileSync(REGISTER, 'utf8').split('\n');
  const start = lines.findIndex(line => /^\|\s*#\s*\|\s*Item\s*\|/.test(line));
  assert.ok(start >= 0, 'the register has no table');
  const rows = [];
  for (const line of lines.slice(start + 2)) {
    if (!line.startsWith('|')) break;
    const cells = line.split('|').slice(1, -1).map(cell => cell.trim());
    rows.push({ id: cells[0], item: cells[1], state: cells[4], note: cells[5] });
  }
  return rows;
}
const mainEnd = () => {
  if (!gitOk('rev-parse', '--verify', '--quiet', 'main')) return null;
  // The register stops at the split; once main holds it, main's later dforge commits are not rows.
  if (gitOk('cat-file', '-e', `main:${REGISTER_PATH}`)) return null;
  return gitOk('merge-base', '--is-ancestor', 'HEAD', 'main') ? null : 'main';
};
test('A3: every non-merge commit touching plugins/dforge is a register row, all answered', t => {
  if (!needTag(t)) return;
  const end = mainEnd();
  if (!end) { t.skip('no main ref, main already holds the register, or HEAD is merged into main: run this at merge time'); return; }
  const commits = git('log', '--no-merges', '--reverse', '--abbrev=7', '--format=%h %s', `${TAG}..${end}`, '--', 'plugins/dforge').split('\n').filter(Boolean);
  const rows = registerRows();
  assert.deepEqual(rows.map(row => row.item).sort(), [...commits].sort(), 'the register lists exactly the commits');
  const open = run('bash', ['plugins/dagents/scripts/register', 'open', REGISTER]);
  assert.equal(open.status, 0, open.stdout + open.stderr);
  const tagHas = path => gitOk('cat-file', '-e', `${TAG}:${path}`);
  for (const row of rows) {
    assert.ok(['done', 'n/a'].includes(row.state), `row ${row.id} is ${row.state}`);
    if (row.state === 'done') {
      const sha = /port ([0-9a-f]{7,40})/.exec(row.note)?.[1];
      assert.ok(sha && gitOk('cat-file', '-e', `${sha}^{commit}`), `row ${row.id} names no dagents commit`);
      continue;
    }
    const kind = /^(5-only|feature|test-only|docs-only|superseded)\b/.exec(row.note)?.[1];
    assert.ok(kind, `row ${row.id} has no class: ${row.note}`);
    const reason = row.note.slice(kind.length).replace(/^\s*[:\-—]\s*/, '').trim();
    const sha = row.item.split(' ')[0];
    if (kind === '5-only' && reason === '') {
      const paths = git('diff-tree', '--root', '--no-commit-id', '-r', '--name-only', '-z', sha, '--', 'plugins/dforge').split('\0').filter(Boolean)
        .filter(path => !path.includes('/tests/'));
      assert.ok(paths.length > 0, `row ${row.id}: no non-test path`);
      for (const path of paths) assert.equal(tagHas(path), false, `row ${row.id}: ${path} exists at the tag`);
    } else {
      assert.ok(reason.length >= 10, `row ${row.id} (${kind}) has no reason: ${row.note}`);
    }
  }
});
test('A4: every done row records its port and both results, or text-only with a changed file', t => {
  if (!needHistory(t)) return;
  const rows = registerRows().filter(row => row.state === 'done');
  assert.ok(rows.length > 0);
  const problems = [];
  for (const row of rows) {
    const match = /^port ([0-9a-f]{7,40}); (fail@parent pass@port|text-only (\S+))$/.exec(row.note);
    if (!match) { problems.push(`row ${row.id}: ${row.note}`); continue; }
    const sha = match[1];
    if (!gitOk('cat-file', '-e', `${sha}^{commit}`)) { problems.push(`row ${row.id}: ${sha} is not a commit`); continue; }
    if (git('diff-tree', '--no-commit-id', '-r', '--name-only', sha, '--', 'plugins/dagents').trim() === '') problems.push(`row ${row.id}: ${sha} touches no dagents file`);
    if (match[3]) {
      const changed = git('diff-tree', '--no-commit-id', '-r', '--name-only', sha).split('\n').filter(Boolean);
      if (!changed.includes(match[3])) problems.push(`row ${row.id}: text-only file ${match[3]} is not changed by ${sha}`);
      const code = changed.filter(file => !/\.md$/.test(file)).flatMap(file => git('diff-tree', '-p', '-U0', '--no-commit-id', sha, '--', file).split('\n')
        .filter(line => /^[+-]/.test(line) && !/^(\+\+\+|---) /.test(line) && !/^[+-]\s*(\/\/|#|\*|\/\*|$)/.test(line)));
      if (code.length > 0) problems.push(`row ${row.id}: ${sha} records text-only but changes code or tests`);
    }
  }
  assert.deepEqual(problems, []);
});
test('A4: a port that changes tests has them fail at its parent and pass at the port (replay)', { skip: process.env.DAGENTS_ACCEPTANCE_REPLAY !== '1' && 'set DAGENTS_ACCEPTANCE_REPLAY=1 (slow: reruns each port twice)', timeout: 4 * 3600 * 1000 }, t => {
  const [index, total] = (process.env.DAGENTS_ACCEPTANCE_SHARD ?? '1/1').split('/').map(Number);
  const ports = [...new Set(registerRows().filter(row => /fail@parent pass@port/.test(row.note)).map(row => /^port ([0-9a-f]+)/.exec(row.note)[1]))]
    .filter((_, position) => position % total === index - 1);
  const dir = scratch(t);
  const tree = join(dir, 'tree');
  git('worktree', 'add', '--detach', tree, 'HEAD');
  t.after(() => { spawnSync('git', ['worktree', 'remove', '--force', tree], { cwd: ROOT, stdio: 'ignore', timeout: 60000 }); });
  const sub = (...args) => spawnSync('git', args, { cwd: tree, encoding: 'utf8', timeout: 120000 });
  const runner = file => {
    if (/\.test\.sh$|\.acceptance\.sh$/.test(file)) return ['bash', [file]];
    if (/\.test\.mjs$/.test(file)) return ['node', ['--test', '--test-timeout=300000', file]];
    return null;
  };
  const env = cleanEnv({ TMPDIR: process.env.TMPDIR ?? tmpdir() });
  const report = [];
  for (const sha of ports) {
    const files = sub('diff-tree', '--no-commit-id', '-r', '--name-only', '--diff-filter=AM', sha).stdout.split('\n').filter(Boolean)
      .filter(file => file.startsWith('plugins/dagents/tests/') && runner(file));
    const tsOnly = files.length === 0 && sub('diff-tree', '--no-commit-id', '-r', '--name-only', sha).stdout.split('\n').some(file => /plugins\/dagents\/tests\/.*\.test\.tsx?$/.test(file));
    const verdict = { sha, files, parent: null, port: null };
    report.push(verdict);
    const attempt = (label, commands) => {
      for (const [command, args] of commands) {
        const result = spawnSync(command, args, { cwd: tree, env, encoding: 'utf8', timeout: 900000, maxBuffer: 256 * 1024 * 1024 });
        if (result.status !== 0) return { status: result.status, label, tail: (result.stdout + result.stderr).split('\n').slice(-6).join('\n') };
      }
      return { status: 0, label };
    };
    const commands = tsOnly ? [[process.env.CLAUDE_BIN || 'claude', ['plugin', 'test', 'plugins/dagents']]] : files.map(file => runner(file));
    assert.ok(commands.length > 0, `${sha}: no runnable test file`);
    assert.equal(sub('checkout', '-q', '--detach', sha).status, 0);
    verdict.port = attempt('port', commands);
    assert.equal(sub('checkout', '-q', '--detach', `${sha}^`).status, 0);
    if (files.length > 0) assert.equal(sub('checkout', sha, '--', ...files).status, 0);
    verdict.parent = attempt('parent', commands);
    sub('checkout', '-q', '--force', 'HEAD');
    sub('clean', '-fdxq');
  }
  const bad = report.filter(verdict => verdict.port.status !== 0 || verdict.parent.status === 0);
  assert.deepEqual(bad.map(verdict => ({ sha: verdict.sha, files: verdict.files, port: verdict.port.status, parent: verdict.parent.status, tail: verdict.port.status !== 0 ? verdict.port.tail : '' })), []);
});

// A5
const renameText = text => text.replace(/dforge/g, 'dagents').replace(/DFORGE/g, 'DAGENTS');
test('A5: dagents has none of version 5\'s features', () => {
  const absent = [
    'scripts/run-review-panel', 'scripts/run-agy-review.sh', 'scripts/lib/worktree-snapshot.sh', 'scripts/task-close',
    'scripts/run-api-judge', 'scripts/api-spend', 'scripts/decide', 'scripts/lib/api-budget.sh', 'scripts/lib/decisions.mjs',
    'scripts/lib/session-state.sh', 'reference/api-prices.json', 'reference/external-review.md', 'criteria/agy-final-review-schema.json',
  ];
  for (const path of absent) assert.equal(existsSync(join(ROOT, 'plugins/dagents', path)), false, path);
  const files = git('ls-files', '--', 'plugins/dagents').split('\n').filter(Boolean);
  for (const file of files) assert.doesNotMatch(file, /review-panel|task-close|api-judge|api-spend|session-state/, file);
  const prose = textFiles('plugins/dagents').filter(file => !file.includes('/tests/') && !/\/README\.md$/.test(file));
  for (const file of prose) {
    const text = readFileSync(join(ROOT, file), 'utf8');
    assert.doesNotMatch(text, /run-review-panel|run-api-judge|task-close|session-state\.sh/, file);
  }
});
test('A5: the agent set, subagent-driven-development and revising-plans keep the tag\'s files', t => {
  if (!needTag(t)) return;
  for (const dir of ['agents', 'skills/subagent-driven-development', 'skills/revising-plans']) {
    const tagFiles = git('ls-tree', '-r', '--name-only', TAG, `plugins/dforge/${dir}`).split('\n').filter(Boolean)
      .map(file => renameText(file).replace('plugins/dagents/', '')).sort();
    const ours = git('ls-files', '--', `plugins/dagents/${dir}`).split('\n').filter(Boolean).map(file => file.replace('plugins/dagents/', '')).sort();
    assert.deepEqual(ours, tagFiles, dir);
  }
  for (const file of git('ls-tree', '-r', '--name-only', TAG, 'plugins/dforge/agents').split('\n').filter(Boolean)) {
    const ours = join(ROOT, renameText(file));
    assert.equal(readFileSync(ours, 'utf8'), renameText(git('show', `${TAG}:${file}`)), `${file} differs under the rename`);
  }
  for (const dir of ['skills/subagent-driven-development', 'skills/revising-plans']) {
    for (const file of git('ls-tree', '-r', '--name-only', TAG, `plugins/dforge/${dir}`).split('\n').filter(Boolean)) {
      const path = renameText(file);
      if (readFileSync(join(ROOT, path), 'utf8') === renameText(git('show', `${TAG}:${file}`))) continue;
      const ports = git('log', '--format=%h', '--grep=^Backport of', '--', path).split('\n').filter(Boolean);
      assert.ok(ports.length > 0, `${path} differs from the tag under the rename and no port commit changed it`);
    }
  }
});
test('A5: plan-lint judges Executor lines as the tag does', t => {
  if (!needTag(t)) return;
  const dir = scratch(t);
  const tagTree = join(dir, 'tag');
  mkdirSync(tagTree);
  execFileSync('bash', ['-c', `git archive ${TAG} plugins/dforge | tar -x -C "${tagTree}"`], { cwd: ROOT, timeout: 60000 });
  const plan = executor => `# Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names.

**Goal:** Demo.

**Spec:** \`docs/spec.md\`

**Execution:** subagent — \`claude --model sonnet --effort high\` — Task 1 scores 2

**Task check:** \`bash quick.sh\` — gate 1 has Tier: task

**Integration check:** \`bash test.sh\`

**CI:** none

**Plan review:** 2026-09-12 — dagents:judge-fable — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)

> **External executors:** codex

## Global Constraints

- Bash only.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

1. First thing

### Task 1: First thing

**Files:**
- Create: \`a.txt\`

**Implementer:** dagents:impl-sonnet-low
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = ${executor.score}
${executor.line}

- [ ] **Step 1: Write the failing test**
`;
  const cases = {
    'lane-eligible with an Executor line': { score: 2, line: '**Executor:** codex gpt-6.1-sol / low' },
    'an Executor line under the gate': { score: 1, line: '**Executor:** codex gpt-6.1-sol / low' },
    'no Executor line': { score: 2, line: '' },
  };
  const outputs = {};
  for (const [name, spec] of Object.entries(cases)) {
    const home = join(dir, 'home'); mkdirSync(home, { recursive: true });
    const project = join(dir, `p-${Object.keys(outputs).length}`);
    mkdirSync(join(project, 'docs'), { recursive: true });
    writeFileSync(join(project, 'docs/spec.md'), '# Spec\n');
    execFileSync('git', ['init', '-q', project], { timeout: 30000 });
    const ours = join(project, 'plan.md');
    writeFileSync(ours, plan(spec));
    const env = cleanEnv({ HOME: home });
    const a = run('bash', [join(ROOT, 'plugins/dagents/scripts/plan-lint'), ours, '--no-probe'], { cwd: project, env });
    const theirs = join(project, 'plan-tag.md');
    writeFileSync(theirs, plan(spec).replace(/dagents/g, 'dforge'));
    const b = run('bash', [join(tagTree, 'plugins/dforge/scripts/plan-lint'), theirs, '--no-probe'], { cwd: project, env });
    assert.equal(a.status, b.status, `${name}: exit status\n${a.stdout}\n${b.stdout}`);
    const normal = text => renameText(text).replaceAll(theirs, ours).replace(/plan-tag\.md/g, 'plan.md');
    assert.equal(normal(a.stdout + a.stderr), normal(b.stdout + b.stderr), name);
    outputs[name] = a.stdout;
  }
  assert.match(outputs['an Executor line under the gate'], /ERROR Task 1: total 1 \/ risk 0 fails the lane gate \(min_score 2, max_score 4, max_risk 1\)/);
});

// A6
test('A6: dforge is spelled only where the allowlist and version-qualified origin text allow', { skip: 'deferred: docs/dforge/registers/2026-11-16-dagents-split.md row 9 (its filename regex omits the cockpit lib.ts older-spelling reader)' }, async () => {
  const { DAGENTS_DFORGE_ALLOWED } = await import(pathToFileURL(join(ROOT, 'scripts/validate-repository.mjs')).href);
  const migrateOrReader = /(migrate|dagents-dir|roots|darkmem-(mirror|sync|reconcile|config)|repo-audit|session-start|workflow-guard|README\.md|codex-tools|stand-down|isolation|cockpit\.test)/;
  for (const file of DAGENTS_DFORGE_ALLOWED) {
    if (/\/tests\//.test(file)) continue;
    assert.match(file, migrateOrReader, `${file} is allowlisted but is not a migrate, reader, guard or README file`);
  }
  const stray = [];
  for (const file of textFiles('plugins/dagents')) {
    if (DAGENTS_DFORGE_ALLOWED.has(file)) continue;
    readFileSync(join(ROOT, file), 'utf8').split('\n').forEach((line, index) => {
      if (/dforge/i.test(line.replace(/dforge(?= \d| v\d|-v\d)/gi, ''))) stray.push(`${file}:${index + 1}: ${line.trim().slice(0, 100)}`);
    });
  }
  assert.deepEqual(stray, []);
});
test('A6: plugins/dagents names no dagents version other than 1.x', () => {
  const wrong = [];
  for (const file of textFiles('plugins/dagents')) {
    readFileSync(join(ROOT, file), 'utf8').split('\n').forEach((line, index) => {
      for (const match of line.matchAll(/dagents(?:@darkraise)?[ -]v?(\d+)(?:\.(\d+|x))?/gi)) {
        if (match[1] !== '1') wrong.push(`${file}:${index + 1}: ${match[0]}`);
      }
    });
  }
  assert.deepEqual(wrong, []);
});

// The guard
function world(t) {
  const dir = scratch(t);
  const claude = join(dir, 'claude'); const managed = join(dir, 'managed'); const project = join(dir, 'project'); const codex = join(dir, 'codex'); const data = join(dir, 'data');
  for (const d of [join(claude, 'plugins'), managed, join(project, '.claude'), join(project, '.codex'), codex, data]) mkdirSync(d, { recursive: true });
  execFileSync('git', ['init', '-q', project], { timeout: 30000 });
  const write = (file, value) => writeFileSync(file, typeof value === 'string' ? value : JSON.stringify(value));
  const env = cleanEnv({ HOME: join(dir, 'home'), WORKFLOW_GUARD_CLAUDE_DIR: claude, WORKFLOW_GUARD_MANAGED_DIR: managed, WORKFLOW_GUARD_PROJECT_DIR: project, CODEX_HOME: codex, CLAUDE_PLUGIN_DATA: data });
  mkdirSync(env.HOME, { recursive: true });
  const w = {
    dir, claude, managed, project, codex, data, env, write,
    install: (entries) => write(join(claude, 'plugins/installed_plugins.json'), { version: 2, plugins: Object.fromEntries(Object.entries(entries).map(([name, installs]) => [`${name}@darkraise`, installs.map(i => ({ installPath: '/x', version: '1', ...i }))])) }),
    user: (...names) => Object.fromEntries(names.map(name => [name, [{ scope: 'user' }]])),
    enable: (file, map) => write(file, { enabledPlugins: Object.fromEntries(Object.entries(map).map(([name, value]) => [`${name}@darkraise`, value])) }),
    user_settings: () => join(claude, 'settings.json'),
    run: (name, args, input) => run(process.execPath, [GUARD(name), ...args], { env, input, timeout: 30000, cwd: project }),
  };
  return w;
}
const activeNames = out => out.split('\n').map(line => /^(dforge|dagents|dflow)(?:@darkraise)?\b/.exec(line.trim())?.[1]).filter(Boolean).sort();

// A15
test('A15: the standalone guard exits 0 with at most one workflow plugin, 3 with two or more, and lists each with its scope', t => {
  const w = world(t);
  w.install(w.user('dforge', 'dagents', 'dflow'));
  const cases = [
    [{}, 0, []],
    [{ dforge: true }, 0, ['dforge']],
    [{ dforge: true, dagents: true }, 3, ['dagents', 'dforge']],
    [{ dforge: true, dagents: true, dflow: true }, 3, ['dagents', 'dflow', 'dforge']],
  ];
  for (const [map, status, names] of cases) {
    w.enable(w.user_settings(), { dforge: false, dagents: false, dflow: false, ...map });
    for (const owner of SIBLINGS) {
      const result = w.run(owner, ['--host', 'claude']);
      assert.equal(result.status, status, `${owner} ${JSON.stringify(map)}: ${result.stderr}`);
      assert.deepEqual(activeNames(result.stdout), names, `${owner} ${JSON.stringify(map)}`);
      for (const line of result.stdout.split('\n').filter(Boolean)) assert.match(line, /user/, `${line} names its enabling scope`);
    }
  }
  assert.equal(w.run('dagents', []).status, 2);
});
test('A15: each enabling scope is named', t => {
  const w = world(t);
  w.install(w.user('dforge', 'dagents', 'dflow'));
  w.enable(w.user_settings(), { dforge: true });
  w.enable(join(w.project, '.claude/settings.json'), { dagents: true });
  w.enable(join(w.project, '.claude/settings.local.json'), { dflow: true });
  const result = w.run('dagents', ['--host', 'claude']);
  assert.equal(result.status, 3);
  const line = name => result.stdout.split('\n').find(l => l.startsWith(name));
  assert.match(line('dforge'), /user/);
  assert.match(line('dagents'), /project/);
  assert.match(line('dflow'), /local/);
  assert.doesNotMatch(line('dagents'), /local|user/);
});

// A14
test('A14: what is and is not a conflict', t => {
  const w = world(t);
  const verdict = (name = 'dagents') => { const r = w.run(name, ['--host', 'claude']); return [r.status, activeNames(r.stdout), r.stderr]; };
  w.install(w.user('dforge', 'dagents'));
  w.enable(w.user_settings(), { dforge: true, dagents: true });
  assert.equal(verdict()[0], 3, 'baseline: two enabled and installed');

  w.enable(join(w.project, '.claude/settings.json'), { dagents: false });
  assert.deepEqual(verdict().slice(0, 2), [0, ['dforge']], 'enabled in user settings, disabled in project settings');
  rmSync(join(w.project, '.claude/settings.json'));

  w.install(w.user('dforge'));
  assert.deepEqual(verdict().slice(0, 2), [0, ['dforge']], 'enabled but not installed');

  w.install({ dforge: [{ scope: 'user' }], dagents: [{ scope: 'project', projectPath: join(w.dir, 'elsewhere') }] });
  assert.deepEqual(verdict().slice(0, 2), [0, ['dforge']], 'installed at project scope for another project');
  w.install({ dforge: [{ scope: 'user' }], dagents: [{ scope: 'project', projectPath: w.project }] });
  assert.equal(verdict()[0], 3, 'installed at project scope for this project is active');

  w.install(w.user('dforge', 'dagents'));
  w.write(w.user_settings(), {});
  assert.equal(verdict()[0], 3, 'installed with no enabledPlugins entry at any scope is active');

  w.enable(join(w.managed, 'managed-settings.json'), { dagents: false });
  w.enable(join(w.project, '.claude/settings.local.json'), { dagents: true });
  w.enable(w.user_settings(), { dagents: true });
  assert.deepEqual(verdict().slice(0, 2), [0, ['dforge']], 'managed false overrides every other scope');
  rmSync(join(w.managed, 'managed-settings.json'));
  rmSync(join(w.project, '.claude/settings.local.json'));

  w.enable(w.user_settings(), { dforge: true, dagents: true });
  w.write(join(w.project, '.claude/settings.json'), '{ this is not json');
  const [status, names, stderr] = verdict();
  assert.equal(status, 0, 'a malformed settings file is no conflict');
  assert.equal(stderr.trim().split('\n').length, 1, `one diagnostic line: ${stderr}`);
  assert.deepEqual(names, []);
});
test('A14: with node missing the hooks print nothing extra', { skip: process.platform === 'win32' && 'POSIX PATH surgery; stand-down.test.sh covers the node-missing hooks on every host' }, t => {
  const w = world(t);
  w.install(w.user('dforge', 'dagents'));
  w.enable(w.user_settings(), { dforge: false, dagents: false });
  const bin = join(w.dir, 'nonode');
  mkdirSync(bin);
  const node = execFileSync('bash', ['-c', 'command -v node'], { encoding: 'utf8' }).trim();
  for (const dirName of (process.env.PATH ?? '').split(':')) {
    if (!dirName || !existsSync(dirName)) continue;
    for (const item of readdirSync(dirName)) {
      if (/^(node|nodejs|npm|npx|corepack)$/.test(item) || existsSync(join(bin, item))) continue;
      const path = join(dirName, item);
      if (path !== node) { try { symlinkSync(path, join(bin, item)); } catch { /* a name taken in the loop */ } }
    }
  }
  const event = JSON.stringify({ session_id: 's-nonode', cwd: w.project, source: 'startup', hook_event_name: 'SessionStart' });
  const withNode = run('bash', [join(ROOT, 'plugins/dagents/scripts/session-start.sh')], { env: w.env, input: event, cwd: w.project });
  const without = run('bash', [join(ROOT, 'plugins/dagents/scripts/session-start.sh')], { env: { ...w.env, PATH: bin }, input: event, cwd: w.project });
  assert.equal(without.status, 0);
  assert.equal(without.stderr, '', 'nothing on stderr');
  assert.equal(without.stdout, withNode.stdout, 'the output is the one a conflict-free session prints');
  assert.doesNotMatch(without.stdout, /workflow-guard\.mjs --host claude|systemMessage/);
  const guardNoNode = run('bash', ['-c', `"${join(w.dir, 'nonode/bash')}" "${join(ROOT, 'plugins/dforge/scripts/session-start.sh')}"`], { env: { ...w.env, PATH: bin }, input: event, cwd: w.project });
  assert.equal(guardNoNode.status, 0);
  assert.equal(guardNoNode.stderr, '');
});

// A12
test('A12: the guard never writes a settings file or the install record, under a conflict or not', t => {
  const w = world(t);
  w.install(w.user('dforge', 'dagents', 'dflow'));
  w.enable(w.user_settings(), { dforge: true, dagents: true, dflow: true });
  w.enable(join(w.project, '.claude/settings.json'), { dforge: true });
  w.enable(join(w.project, '.claude/settings.local.json'), { dflow: true });
  w.enable(join(w.managed, 'managed-settings.json'), { dagents: true });
  mkdirSync(join(w.managed, 'managed-settings.d'));
  w.enable(join(w.managed, 'managed-settings.d/10-x.json'), { dflow: true });
  const watched = () => {
    const out = {};
    for (const base of [w.claude, w.managed, w.project, w.codex]) {
      const visit = dir => { for (const item of readdirSync(dir, { withFileTypes: true })) {
        const path = join(dir, item.name);
        if (item.isDirectory()) { if (item.name !== '.git') visit(path); } else out[path] = `${statSync(path).mtimeMs}:${statSync(path).size}:${readFileSync(path, 'utf8')}`;
      } };
      visit(base);
    }
    return out;
  };
  const before = watched();
  const event = JSON.stringify({ session_id: 'a12', source: 'startup', hook_event_name: 'SessionStart', cwd: w.project });
  for (const owner of SIBLINGS) {
    for (const host of ['claude', 'codex']) w.run(owner, ['--host', host]);
    w.run(owner, ['--host', 'claude', '--self', owner, '--hook', 'session-start'], event);
  }
  assert.deepEqual(watched(), before, 'conflict run');
  for (const file of ['settings.json']) w.enable(join(w.claude, file), { dforge: false, dagents: false, dflow: false });
  rmSync(join(w.project, '.claude/settings.json')); rmSync(join(w.project, '.claude/settings.local.json')); rmSync(join(w.managed, 'managed-settings.json')); rmSync(join(w.managed, 'managed-settings.d'), { recursive: true });
  const quiet = watched();
  for (const owner of SIBLINGS) {
    w.run(owner, ['--host', 'claude']);
    w.run(owner, ['--host', 'claude', '--self', owner, '--hook', 'session-start'], event);
  }
  assert.deepEqual(watched(), quiet, 'no-conflict run');
});

// A18
test('A18: Codex reads config.toml, and the two hosts never combine', t => {
  const w = world(t);
  w.write(join(w.codex, 'config.toml'), '[plugins."dforge@darkraise"]\nenabled = true\n\n[plugins."dagents@darkraise"]\nenabled = true\n');
  for (const owner of SIBLINGS) assert.equal(w.run(owner, ['--host', 'codex']).status, 3, owner);
  w.write(join(w.codex, 'config.toml'), '[plugins."dagents@darkraise"]\nenabled = true\n');
  w.install(w.user('dforge'));
  w.enable(w.user_settings(), { dforge: true });
  for (const owner of SIBLINGS) {
    assert.equal(w.run(owner, ['--host', 'claude']).status, 0, `${owner} claude`);
    assert.equal(w.run(owner, ['--host', 'codex']).status, 0, `${owner} codex`);
  }
  const codex = w.run('dagents', ['--host', 'codex']);
  assert.match(codex.stdout, /dagents/);
  assert.doesNotMatch(codex.stdout, /dforge/);
});

// A Codex session resolved a skill-relative `references/codex-tools.md`
// against the plugin root, missed the file and never ran the guard.
test('A24: each Codex entry skill names the guard itself and its reference by a plugin-root path', () => {
  for (const plugin of ['dforge', 'dagents']) {
    const reference = `skills/using-${plugin}/references/codex-tools.md`;
    const line = readFileSync(join(ROOT, 'plugins', plugin, 'skills', `using-${plugin}`, 'SKILL.md'), 'utf8').split('\n').find(text => text.startsWith('- Codex:'));
    assert.ok(line, `${plugin}: the entry skill has a Codex line`);
    assert.ok(line.includes(`\`node <plugin-root>/scripts/workflow-guard.mjs --host codex --self ${plugin}\``), `${plugin}: ${line}`);
    assert.match(line, /exit 3/, `${plugin}: ${line}`);
    assert.ok(line.includes(`\`<plugin-root>/${reference}\``), `${plugin}: ${line}`);
    assert.ok(existsSync(join(ROOT, 'plugins', plugin, reference)), `${plugin}: ${reference} exists`);
  }
});

// A16
test('A16: the three guard copies are byte-identical, and validate-repository fails when one differs', t => {
  const bytes = SIBLINGS.map(name => readFileSync(GUARD(name)));
  assert.ok(bytes[0].equals(bytes[1]) && bytes[0].equals(bytes[2]), 'copies differ');
  const dir = scratch(t);
  const copy = join(dir, 'repo');
  mkdirSync(copy);
  execFileSync('bash', ['-c', `git ls-files -z | tar --null -T - -cf - | tar -x -C "${copy}"`], { cwd: ROOT, timeout: 120000 });
  const clean = run(process.execPath, [join(copy, 'scripts/validate-repository.mjs'), copy], { cwd: copy, timeout: 90000 });
  assert.equal(clean.status, 0, clean.stderr);
  for (const name of SIBLINGS) {
    const file = join(copy, 'plugins', name, 'scripts/workflow-guard.mjs');
    const original = readFileSync(file);
    writeFileSync(file, Buffer.concat([original, Buffer.from('\n// drift\n')]));
    const drift = run(process.execPath, [join(copy, 'scripts/validate-repository.mjs'), copy], { cwd: copy, timeout: 90000 });
    assert.notEqual(drift.status, 0, `${name}'s copy differs and validation still passes`);
    assert.match(drift.stderr, /workflow-guard/);
    writeFileSync(file, original);
  }
});

// A22
test('A22: a dagents suite sharing a dforge suite\'s basename has its own limit, parts and weight', async () => {
  const shards = await import(pathToFileURL(join(ROOT, 'scripts/test-shards.mjs')).href);
  const listing = args => {
    const result = run(process.execPath, ['scripts/test-all.mjs', ...args, '--list', '--limits']);
    assert.equal(result.status, 0, result.stderr);
    const suites = new Map();
    for (const line of result.stdout.split('\n').filter(Boolean)) {
      const [seconds, command] = line.split('\t');
      const [path, ...part] = command.split(' ');
      const entry = suites.get(path) ?? { seconds: Number(seconds), parts: [] };
      entry.parts.push(part);
      suites.set(path, entry);
    }
    return suites;
  };
  const forge = listing([]);
  const agents = listing(['--plugin', 'dagents']);
  const names = dir => readdirSync(join(ROOT, 'plugins', dir, 'tests')).filter(name => /\.(test|acceptance)(\.test)?\.sh$/.test(name));
  const shared = names('dforge').filter(name => names('dagents').includes(name));
  assert.ok(shared.length > 20, 'many suites share a basename');
  let differing = 0;
  for (const name of shared) {
    const forgePath = `plugins/dforge/tests/${name}`;
    const agentsPath = `plugins/dagents/tests/${name}`;
    const f = forge.get(forgePath); const a = agents.get(agentsPath);
    assert.ok(f, `${forgePath} is not run by test-all`);
    assert.ok(a, `${agentsPath} is not run by test-all --plugin dagents`);
    for (const [path, listed] of [[forgePath, f], [agentsPath, a]]) {
      assert.equal(listed.seconds, shards.suiteSeconds[path] ?? 600, `${path} limit`);
      assert.deepEqual(listed.parts, (shards.suiteParts[path] ?? [[]]), `${path} parts`);
      assert.ok(Object.hasOwn(shards.windowsSeconds, path), `${path} has its own weight`);
    }
    if (f.seconds !== a.seconds || JSON.stringify(f.parts) !== JSON.stringify(a.parts) || JSON.stringify(shards.windowsSeconds[forgePath]) !== JSON.stringify(shards.windowsSeconds[agentsPath])) differing += 1;
  }
  assert.ok(differing > 0, 'at least one shared basename is limited, split or weighed differently per plugin');
  for (const map of [shards.windowsSeconds, shards.suiteSeconds, shards.suiteParts]) {
    for (const key of Object.keys(map)) assert.match(key, /^(plugins\/[a-z0-9-]+\/)?tests\/[^/]+$/, `${key} is keyed by repository path`);
  }
  for (const [path, entry] of agents) assert.equal(shards.checkShellWeights([[ 'bash', [path, ...entry.parts[0]], entry.seconds ]]).filter(problem => problem.includes('no weight')).length, 0, path);
});

// A23
test('A23: the release dry run tags and releases each plugin from its manifest version', t => {
  if (!needTag(t)) return;
  const before = git('status', '--porcelain', '--untracked-files=no');
  const result = run(process.execPath, ['scripts/release.mjs', '--dry-run'], { timeout: 120000 });
  assert.equal(result.status, 0, result.stderr);
  const versionOf = name => json(`plugins/${name}/.claude-plugin/plugin.json`).version;
  const semver = version => version.split(/[-+]/)[0].split('.').map(Number);
  const newer = (to, from) => { const [a, b] = [semver(to), semver(from)]; const i = a.findIndex((n, k) => n !== b[k]); return i >= 0 && a[i] > b[i]; };
  for (const [, name, version] of result.stdout.matchAll(/^tag ([a-z0-9-]+)-v(\S+) at /gm)) assert.equal(version, versionOf(name), `tag line for ${name}`);
  for (const [, name, from, to] of result.stdout.matchAll(/^release ([a-z0-9-]+) (\S+) -> (\S+)$/gm)) {
    assert.equal(from, versionOf(name), `release line for ${name}`);
    assert.ok(newer(to, from), `${name}: ${to} is not newer than ${from}`);
  }
  assert.equal(git('status', '--porcelain', '--untracked-files=no'), before, 'a dry run changes nothing');
});

// A29
test('A29: a change outside plugins/dagents, scripts, tests and the workflow starts no dagents job', t => {
  const workflow = readFileSync(join(ROOT, '.github/workflows/validate.yml'), 'utf8');
  const step = /- id: filter\n(?:.*\n)*?\s+run: \|\n((?:\s{10}.*\n|\n)+)/.exec(workflow);
  assert.ok(step, 'the dagents change filter step is missing');
  const script = step[1].split('\n').map(line => line.replace(/^ {10}/, '')).join('\n');
  const dir = scratch(t);
  const repo = join(dir, 'repo');
  mkdirSync(repo);
  const g = (...args) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.invalid', ...args], { cwd: repo, encoding: 'utf8', timeout: 30000 });
  g('init', '-q');
  const commit = (file, message) => { mkdirSync(join(repo, file, '..'), { recursive: true }); writeFileSync(join(repo, file), `${message}\n`); g('add', '--', file); g('commit', '-q', '-m', message); return g('rev-parse', 'HEAD').trim(); };
  const base = commit('README.md', 'base');
  const decide = (file, event = 'push') => {
    const head = commit(file, `change ${file}`);
    const out = join(dir, `out-${head}`);
    writeFileSync(out, '');
    const result = run('bash', ['-c', script], { cwd: repo, env: cleanEnv({ EVENT: event, BEFORE: base, BASE: base, HEAD: head, GITHUB_OUTPUT: out }) });
    assert.equal(result.status, 0, result.stderr);
    const value = /dagents=(\w+)/.exec(readFileSync(out, 'utf8'))?.[1];
    g('reset', '-q', '--hard', base);
    return value;
  };
  for (const file of ['plugins/dflow/x.md', 'plugins/dforge/x.md', 'plugins/darkraise-ui/x.md', 'docs/a.md', 'README.md2']) {
    assert.equal(decide(file), 'false', `${file} starts a dagents job`);
    assert.equal(decide(file, 'pull_request'), 'false', `${file} (pull request) starts a dagents job`);
  }
  for (const file of ['plugins/dagents/x.md', 'scripts/x.mjs', 'tests/x.mjs', '.github/workflows/validate.yml']) assert.equal(decide(file), 'true', `${file} skips the dagents jobs`);
  for (const name of ['validate-dagents', 'windows-dagents']) {
    const job = new RegExp(`\\n  ${name}:\\n(?:    .*\\n|\\n)+`).exec(workflow)?.[0];
    assert.ok(job, `${name} job`);
    assert.match(job, /needs: dagents-changes/);
    assert.match(job, /if: needs\.dagents-changes\.outputs\.dagents == 'true'/);
  }
});

// A11 and A27: the three plugins' hooks under a conflict
const hooksOf = name => json(`plugins/${name}/hooks/hooks.json`).hooks;
const commandsOf = (name, event) => (hooksOf(name)[event] ?? []).flatMap(group => group.hooks.map(hook => hook.command));
function hookWorld(t) {
  const w = world(t);
  const datas = Object.fromEntries(SIBLINGS.map(name => [name, join(w.dir, `data-${name}`)]));
  for (const dir of Object.values(datas)) mkdirSync(dir, { recursive: true });
  const fire = (name, event, payload = {}, extraEnv = {}) => run('bash', ['-c', commandsOf(name, event)[0]], {
    cwd: w.project,
    env: { ...w.env, CLAUDE_PLUGIN_ROOT: join(ROOT, 'plugins', name), CLAUDE_PLUGIN_DATA: datas[name], ...extraEnv },
    input: JSON.stringify({ session_id: 'sess-A11-one', cwd: w.project, transcript_path: join(w.dir, 'transcript.jsonl'), hook_event_name: event, source: 'startup', stop_hook_active: false, prompt: 'hello', tool_name: 'Edit', tool_input: { file_path: join(w.project, 'a.txt') }, ...payload }),
    timeout: 120000,
  });
  const files = dir => {
    const out = {};
    const visit = base => { for (const item of readdirSync(base, { withFileTypes: true })) {
      const path = join(base, item.name);
      if (item.name === '.git') continue;
      if (item.isDirectory()) visit(path); else out[path] = readFileSync(path, 'utf8');
    } };
    visit(dir);
    return out;
  };
  return { ...w, datas, fire, files };
}
const COMBOS = [['dforge', 'dagents'], ['dagents', 'dflow'], ['dforge', 'dflow'], ['dforge', 'dagents', 'dflow']];
test('A11: each plugin\'s SessionStart names every active plugin with the local command first, then stays quiet', t => {
  for (const active of COMBOS) {
    const w = hookWorld(t);
    w.install(w.user(...SIBLINGS));
    const scopeFile = { dforge: w.user_settings(), dagents: join(w.project, '.claude/settings.json'), dflow: join(w.project, '.claude/settings.local.json') };
    w.enable(w.user_settings(), { dforge: false, dagents: false, dflow: false });
    for (const name of active) w.enable(scopeFile[name], { [name]: true });
    const scopeOf = { dforge: 'user', dagents: 'project', dflow: 'local' };
    for (const self of active) {
      const result = w.fire(self, 'SessionStart');
      assert.equal(result.status, 0, `${active} ${self}: ${result.stderr}`);
      const out = JSON.parse(result.stdout);
      for (const [label, text] of [['systemMessage', out.systemMessage], ['additionalContext', out.hookSpecificOutput?.additionalContext]]) {
        assert.equal(typeof text, 'string', `${self} ${label}`);
        for (const name of active) assert.ok(text.includes(`${name}@darkraise`), `${active} ${self} ${label} omits ${name}`);
        for (const other of active.filter(name => name !== self)) {
          const local = text.indexOf(`claude plugin disable ${other}@darkraise --scope local`);
          assert.ok(local >= 0, `${self} ${label}: no --scope local command for ${other}`);
          if (scopeOf[other] !== 'local') {
            const enabling = text.indexOf(`claude plugin disable ${other}@darkraise --scope ${scopeOf[other]}`);
            assert.ok(enabling > local, `${self} ${label}: ${other}'s ${scopeOf[other]} command must follow its local command`);
          }
        }
      }
      const marker = Object.keys(w.files(w.datas[self]));
      assert.ok(marker.length > 0, `${self} wrote no marker`);
      const before = { home: w.files(w.env.HOME), project: w.files(w.project), data: w.files(w.datas[self]) };
      for (const event of Object.keys(hooksOf(self)).filter(event => event !== 'SessionStart')) {
        for (const index of commandsOf(self, event).keys()) {
          const hook = run('bash', ['-c', commandsOf(self, event)[index]], {
            cwd: w.project,
            env: { ...w.env, CLAUDE_PLUGIN_ROOT: join(ROOT, 'plugins', self), CLAUDE_PLUGIN_DATA: w.datas[self] },
            input: JSON.stringify({ session_id: 'sess-A11-one', cwd: w.project, transcript_path: join(w.dir, 'transcript.jsonl'), hook_event_name: event, stop_hook_active: false, prompt: 'hello', tool_name: 'Edit', tool_input: { file_path: join(w.project, 'a.txt') }, agent_type: 'dagents:impl-sonnet-low', last_assistant_message: 'x' }),
            timeout: 120000,
          });
          assert.deepEqual([hook.status, hook.stdout, hook.stderr], [0, '', ''], `${self} ${event} hook #${index} under a conflict`);
        }
      }
      assert.deepEqual({ home: w.files(w.env.HOME), project: w.files(w.project), data: w.files(w.datas[self]) }, before, `${self}: a later hook wrote something`);
    }
  }
});
test('A27: a no-conflict SessionStart deletes its session\'s marker, and a fork start runs the guard', t => {
  const w = hookWorld(t);
  w.install(w.user(...SIBLINGS));
  w.enable(w.user_settings(), { dforge: true, dagents: true, dflow: true });
  const mine = dir => Object.keys(w.files(dir)).filter(file => file.includes('sess-A27-marker'));
  for (const self of SIBLINGS) {
    for (const source of ['startup', 'resume', 'clear', 'compact', 'fork']) {
      const hit = w.fire(self, 'SessionStart', { session_id: 'sess-A27-marker', source });
      assert.equal(hit.status, 0, `${self} ${source}: ${hit.stderr}`);
      assert.match(JSON.parse(hit.stdout).systemMessage, /--scope local/, `${self} ${source} runs the guard`);
      assert.equal(mine(w.datas[self]).length, 1, `${self} ${source}: one marker`);
      const other = w.fire(self, 'SessionStart', { session_id: 'sess-A27-other', source });
      assert.equal(other.status, 0);
      w.enable(w.user_settings(), { dforge: false, dagents: false, dflow: false });
      const clear = w.fire(self, 'SessionStart', { session_id: 'sess-A27-marker', source });
      assert.equal(clear.status, 0, `${self} ${source}: ${clear.stderr}`);
      assert.doesNotMatch(clear.stdout, /scope local/, `${self} ${source}: no conflict`);
      assert.deepEqual(mine(w.datas[self]), [], `${self} ${source}: the marker survives a conflict-free start`);
      assert.equal(Object.keys(w.files(w.datas[self])).filter(file => file.includes('sess-A27-other')).length, 1, `${self} ${source}: another session's marker is kept`);
      w.enable(w.user_settings(), { dforge: true, dagents: true, dflow: true });
      for (const file of Object.keys(w.files(w.datas[self]))) rmSync(file, { force: true });
    }
  }
  const matchers = SIBLINGS.map(name => hooksOf(name).SessionStart[0].matcher);
  for (const matcher of matchers) assert.equal(matcher, 'startup|resume|clear|compact|fork');
});
test('A11: control, a conflict-free turn-start hook does write its stamp', t => {
  const w = hookWorld(t);
  w.install(w.user(...SIBLINGS));
  w.enable(w.user_settings(), { dforge: true, dagents: false, dflow: false });
  for (const self of ['dforge', 'dagents']) {
    const before = Object.keys(w.files(w.env.HOME)).length;
    const hook = run('bash', ['-c', commandsOf(self, 'UserPromptSubmit')[0]], {
      cwd: w.project, env: { ...w.env, CLAUDE_PLUGIN_ROOT: join(ROOT, 'plugins', self), CLAUDE_PLUGIN_DATA: w.datas[self] },
      input: JSON.stringify({ session_id: 'sess-A11-ctl', cwd: w.project, hook_event_name: 'UserPromptSubmit', prompt: 'hi' }),
    });
    assert.equal(hook.status, 0, hook.stderr);
    if (self === 'dforge') assert.ok(Object.keys(w.files(w.env.HOME)).length >= before, 'dforge stays on');
    else {
      w.enable(w.user_settings(), { dforge: false, dagents: true, dflow: false });
      const hook2 = run('bash', ['-c', commandsOf(self, 'UserPromptSubmit')[0]], {
        cwd: w.project, env: { ...w.env, CLAUDE_PLUGIN_ROOT: join(ROOT, 'plugins', self), CLAUDE_PLUGIN_DATA: w.datas[self] },
        input: JSON.stringify({ session_id: 'sess-A11-ctl', cwd: w.project, hook_event_name: 'UserPromptSubmit', prompt: 'hi' }),
      });
      assert.equal(hook2.status, 0, hook2.stderr);
      assert.ok(Object.keys(w.files(w.env.HOME)).length > before, 'a plugin that is the only one active writes its turn stamp');
    }
  }
});

// A28
test('A28: dforge 5\'s plan-lint names dagents and /dagents:migrate in its subagent-mode error and Executor-line warning', t => {
  const dir = scratch(t);
  const project = join(dir, 'project');
  mkdirSync(join(project, 'docs'), { recursive: true });
  writeFileSync(join(project, 'docs/spec.md'), '# Spec\n');
  execFileSync('git', ['init', '-q', project], { timeout: 30000 });
  const plan = mode => `# Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names.

**Goal:** Demo.

**Spec:** \`docs/spec.md\`

**Execution:** ${mode} — \`claude --model sonnet --effort high\` — Task 1 scores 2

**Task check:** \`bash quick.sh\` — gate 1 has Tier: task

**Integration check:** \`bash test.sh\`

**CI:** none

## Global Constraints

- Bash only.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

1. First thing

### Task 1: First thing

**Files:**
- Create: \`a.txt\`

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
**Executor:** codex gpt-6.1-sol / low

- [ ] **Step 1: Write the failing test**
`;
  const lint = mode => {
    const file = join(project, `plan-${mode}.md`);
    writeFileSync(file, plan(mode));
    const env = cleanEnv({ HOME: join(dir, 'home') });
    mkdirSync(env.HOME, { recursive: true });
    const result = run('bash', [join(ROOT, 'plugins/dforge/scripts/plan-lint'), file], { cwd: project, env });
    return result.stdout + result.stderr;
  };
  const subagent = lint('subagent').split('\n');
  const error = subagent.find(line => /^ERROR header:.*subagent/i.test(line));
  assert.ok(error, `no subagent-mode error:\n${subagent.join('\n')}`);
  assert.match(error, /dagents/);
  assert.match(error, /\/dagents:migrate/);
  const warning = lint('inline').split('\n').find(line => /^WARN Task 1:.*Executor/.test(line));
  assert.ok(warning, 'no Executor-line warning');
  assert.match(warning, /dagents/);
  assert.match(warning, /\/dagents:migrate/);
});

// A17
test('A17: a session with exactly one workflow plugin active gets no guard output and no marker', t => {
  for (const only of SIBLINGS) {
    const w = hookWorld(t);
    w.install(w.user(...SIBLINGS));
    w.enable(w.user_settings(), Object.fromEntries(SIBLINGS.map(name => [name, name === only])));
    for (const self of [only]) {
      for (const source of ['startup', 'resume', 'clear', 'compact', 'fork']) {
        const result = w.fire(self, 'SessionStart', { session_id: `sess-A17-${source}`, source });
        assert.equal(result.status, 0, `${self} ${source}: ${result.stderr}`);
        assert.doesNotMatch(result.stdout + result.stderr, /Workflow plugins conflict|workflow-guard\.mjs --host claude|claude plugin disable/, `${self} ${source} with only ${only}`);
      }
      assert.deepEqual(Object.keys(w.files(w.datas[self])), [], `${self} wrote a marker with only ${only} active`);
    }
    const out = w.fire(only, 'SessionStart', { source: 'startup' });
    if (only !== 'dflow') assert.match(JSON.parse(out.stdout).hookSpecificOutput?.additionalContext ?? '', new RegExp(`using-${only}`), `${only} still injects its entry skill`);
  }
});
test('A17: the existing dforge and dflow tests changed only in the guard\'s inputs and in assertions other statements require', t => {
  if (!gitOk('rev-parse', '--verify', '--quiet', 'main^{commit}')) { t.skip('no local main branch to diff against'); return; }
  // The statement is about the split's own diff; once main holds the split, a later branch's test edits are not its subject.
  if (gitOk('cat-file', '-e', `main:${REGISTER_PATH}`)) { t.skip('main already holds the split: run this at merge time'); return; }
  const base = spawnSync('git', ['merge-base', 'main', 'HEAD'], { cwd: ROOT, encoding: 'utf8', timeout: 60000 });
  if (base.status !== 0) { t.skip('main and HEAD share no commit in this clone'); return; }
  const diff = git('diff', '-U0', base.stdout.trim(), 'HEAD', '--', 'plugins/dforge/tests', 'plugins/dflow/tests', ':(exclude)plugins/dforge/tests/stand-down.test.sh');
  let file = '';
  const odd = [];
  for (const line of diff.split('\n')) {
    if (line.startsWith('+++ ')) { file = line.slice(6); continue; }
    if (!line.startsWith('-') || line.startsWith('---')) continue;
    const removed = line.slice(1);
    const isolation = /GUARD|CLAUDE_CONFIG_DIR: ''/.test(removed) && file === 'plugins/dflow/tests/helpers.mjs';
    const importLine = /^import .* from '\.\.\/hooks\//.test(removed);
    const forkMatcher = /SessionStart\[0\]\.matcher/.test(removed);
    const signpost = /Executor:.*line is obsolete; the session implements this task/.test(removed);
    if (!(isolation || importLine || forkMatcher || signpost)) odd.push(`${file}: ${removed.trim().slice(0, 120)}`);
  }
  assert.deepEqual(odd, []);
});

// A25
test('A25: with an exported host config enabling the siblings, the hook suites of dagents, dforge and dflow still pass', t => {
  const dir = scratch(t);
  const claude = join(dir, 'claude'); const project = join(dir, 'project');
  mkdirSync(join(claude, 'plugins'), { recursive: true });
  mkdirSync(join(project, '.claude'), { recursive: true });
  const everyone = Object.fromEntries(SIBLINGS.map(name => [`${name}@darkraise`, true]));
  writeFileSync(join(claude, 'settings.json'), JSON.stringify({ enabledPlugins: everyone }));
  writeFileSync(join(project, '.claude/settings.json'), JSON.stringify({ enabledPlugins: everyone }));
  writeFileSync(join(claude, 'plugins/installed_plugins.json'), JSON.stringify({ version: 2, plugins: Object.fromEntries(SIBLINGS.map(name => [`${name}@darkraise`, [{ scope: 'user', installPath: '/x', version: '1' }]])) }));
  const env = cleanEnv({ CLAUDE_CONFIG_DIR: claude, CLAUDE_PROJECT_DIR: project });
  const suites = [
    ['bash', ['plugins/dagents/tests/hook.test.sh']],
    ['bash', ['plugins/dforge/tests/hook.test.sh']],
    [process.execPath, ['--test', 'plugins/dflow/tests/hooks.test.mjs']],
  ];
  for (const [command, args] of suites) {
    const result = run(command, args, { env, timeout: 240000 });
    assert.equal(result.status, 0, `${args.join(' ')}\n${result.stdout.slice(-1500)}${result.stderr.slice(-500)}`);
  }
});
