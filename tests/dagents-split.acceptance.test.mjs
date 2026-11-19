// Regression tests for running dforge, dagents and dflow side by side: the
// workflow guard CLI, the hooks' stand-down, the per-plugin suite limits and
// the CI path filter, run through the repository scripts and the shipped files.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';

const ROOT = fileURLToPath(new URL('../', import.meta.url));
const SIBLINGS = ['dforge', 'dagents', 'dflow'];
const GUARD = name => join(ROOT, 'plugins', name, 'scripts/workflow-guard.mjs');

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
const scratch = t => {
  const dir = mkdtempSync(join(tmpdir(), 'dsplit-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
};
const json = path => JSON.parse(readFileSync(join(ROOT, path), 'utf8'));

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
  for (const path of execFileSync('git', ['ls-files', '-z'], { cwd: ROOT, encoding: 'utf8', timeout: 120000 }).split('\0').filter(Boolean)) {
    mkdirSync(dirname(join(copy, path)), { recursive: true });
    copyFileSync(join(ROOT, path), join(copy, path));
  }
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
  const names = dir => readdirSync(join(ROOT, 'tests', dir)).filter(name => /\.(test|acceptance)(\.test)?\.sh$/.test(name));
  const shared = names('dforge').filter(name => names('dagents').includes(name));
  assert.ok(shared.length > 20, 'many suites share a basename');
  let differing = 0;
  for (const name of shared) {
    const forgePath = `tests/dforge/${name}`;
    const agentsPath = `tests/dagents/${name}`;
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
    for (const key of Object.keys(map)) assert.match(key, /^tests\/([a-z0-9-]+\/)?[^/]+$/, `${key} is keyed by repository path`);
  }
  for (const [path, entry] of agents) assert.equal(shards.checkShellWeights([[ 'bash', [path, ...entry.parts[0]], entry.seconds ]]).filter(problem => problem.includes('no weight')).length, 0, path);
});

// A29
test('A29: only dagents, its suites, the root scripts its jobs run and the workflow start a dagents job', t => {
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
    const result = run('bash', ['-c', script], { cwd: repo, env: cleanEnv({ EVENT: event, BEFORE: base, BASE: base, FROM: base, HEAD: head, GITHUB_OUTPUT: out }) });
    assert.equal(result.status, 0, result.stderr);
    const value = /dagents=(\w+)/.exec(readFileSync(out, 'utf8'))?.[1];
    g('reset', '-q', '--hard', base);
    return value;
  };
  const ROOT_SCRIPTS = ['test-all', 'test-shards', 'validate-repository', 'lint-portability', 'dagents-rename'].map(name => `scripts/${name}.mjs`);
  for (const file of ['plugins/dflow/x.md', 'plugins/dforge/x.md', 'plugins/darkraise-ui/x.md', 'docs/a.md', 'README.md2', 'tests/dforge/x.test.sh', 'tests/dflow/x.test.mjs', 'tests/x.test.mjs', 'scripts/release.mjs']) {
    assert.equal(decide(file), 'false', `${file} starts a dagents job`);
    assert.equal(decide(file, 'pull_request'), 'false', `${file} (pull request) starts a dagents job`);
  }
  for (const file of ['plugins/dagents/x.md', 'tests/dagents/x.test.sh', ...ROOT_SCRIPTS, '.github/workflows/validate.yml']) assert.equal(decide(file), 'true', `${file} skips the dagents jobs`);
  assert.equal(decide('tests/dforge/x.test.sh', 'workflow_dispatch'), 'false', 'a slice dispatch compares against from');
  // Drift: every root script a dagents suite runs, and what it imports, is in the filter.
  const named = new Set();
  for (const suite of readdirSync(join(ROOT, 'tests/dagents')).filter(name => name.endsWith('.sh'))) {
    for (const match of readFileSync(join(ROOT, 'tests/dagents', suite), 'utf8').matchAll(/(?<![\w/])scripts\/([\w-]+\.mjs)/g)) named.add(`scripts/${match[1]}`);
  }
  for (const script of [...named]) {
    for (const match of readFileSync(join(ROOT, script), 'utf8').matchAll(/from '\.\/([\w-]+\.mjs)'/g)) named.add(`scripts/${match[1]}`);
  }
  for (const script of named) assert.ok(ROOT_SCRIPTS.includes(script), `${script} runs in a dagents job but the filter misses it`);
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
    ['bash', ['tests/dagents/hook.test.sh']],
    ['bash', ['tests/dforge/hook.test.sh']],
    [process.execPath, ['--test', 'tests/dflow/hooks.test.mjs']],
  ];
  for (const [command, args] of suites) {
    const result = run(command, args, { env, timeout: 240000 });
    assert.equal(result.status, 0, `${args.join(' ')}\n${result.stdout.slice(-1500)}${result.stderr.slice(-500)}`);
  }
});
