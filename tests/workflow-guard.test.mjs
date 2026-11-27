import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, symlinkSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const guard = fileURLToPath(new URL('../plugins/dagents/scripts/workflow-guard.mjs', import.meta.url));

function world(t) {
  const dir = mkdtempSync(join(tmpdir(), 'guard-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const claude = join(dir, 'claude'); const managed = join(dir, 'managed'); const project = join(dir, 'project'); const codex = join(dir, 'codex'); const data = join(dir, 'data');
  for (const d of [claude, managed, join(project, '.claude'), join(project, '.codex'), codex, data, join(claude, 'plugins')]) mkdirSync(d, { recursive: true });
  const json = (file, value) => writeFileSync(file, JSON.stringify(value));
  const installs = (entries) => json(join(claude, 'plugins/installed_plugins.json'), { version: 2, plugins: entries });
  const userInstall = name => ({ [`${name}@darkraise`]: [{ scope: 'user', installPath: '/x', version: '1' }] });
  const env = { ...process.env, WORKFLOW_GUARD_CLAUDE_DIR: claude, WORKFLOW_GUARD_MANAGED_DIR: managed, WORKFLOW_GUARD_PROJECT_DIR: project, CODEX_HOME: codex, CLAUDE_PLUGIN_DATA: data };
  const run = (args, input) => spawnSync(process.execPath, [guard, ...args], { encoding: 'utf8', env, input, timeout: 30000 });
  return { dir, claude, managed, project, codex, data, json, installs, userInstall, run };
}

test('one or no workflow plugin is no conflict; two are', t => {
  const w = world(t);
  w.installs({ ...w.userInstall('dforge'), ...w.userInstall('dagents') });
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true, 'dagents@darkraise': false } });
  const one = w.run(['--host', 'claude']);
  assert.equal(one.status, 0, one.stderr);
  assert.equal(one.stdout, 'dforge@darkraise user\n');
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true, 'dagents@darkraise': true } });
  const two = w.run(['--host', 'claude']);
  assert.equal(two.status, 3);
  assert.equal(two.stdout, 'dagents@darkraise user\ndforge@darkraise user\n');
});

test('scope precedence, defaults and installs decide what is active', t => {
  const w = world(t);
  w.installs({ ...w.userInstall('dforge'), ...w.userInstall('dagents'), 'dflow@darkraise': [{ scope: 'project', projectPath: '/elsewhere', installPath: '/x', version: '1' }] });
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true, 'dagents@darkraise': true, 'dflow@darkraise': true } });
  w.json(join(w.project, '.claude/settings.json'), { enabledPlugins: { 'dagents@darkraise': false } });
  assert.equal(w.run(['--host', 'claude']).stdout, 'dforge@darkraise user\n', 'project false wins; dflow is installed for another project');
  w.json(join(w.claude, 'settings.json'), {});
  assert.equal(w.run(['--host', 'claude']).stdout, 'dforge@darkraise default\n', 'installed with no entry anywhere is enabled');
  w.json(join(w.managed, 'managed-settings.json'), { enabledPlugins: { 'dforge@darkraise': false } });
  w.json(join(w.project, '.claude/settings.local.json'), { enabledPlugins: { 'dforge@darkraise': true } });
  assert.equal(w.run(['--host', 'claude']).stdout, '', 'managed false overrides every scope');
});

test('a project or local install for this project, under any spelling of its path, is active', t => {
  const w = world(t);
  const link = join(w.dir, 'link');
  symlinkSync(w.project, link, 'dir');
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true, 'dagents@darkraise': true } });
  for (const [scope, projectPath] of [['project', w.project], ['local', w.project], ['project', link], ['local', `${w.project}/`]]) {
    w.installs({ ...w.userInstall('dforge'), 'dagents@darkraise': [{ scope, projectPath, installPath: '/x', version: '1' }] });
    const out = w.run(['--host', 'claude']);
    assert.deepEqual([out.status, out.stdout], [3, 'dagents@darkraise user\ndforge@darkraise user\n'], `${scope} install at ${projectPath}`);
  }
});

test('a managed drop-in overrides the managed file, and local settings override project settings', t => {
  const w = world(t);
  w.installs({ ...w.userInstall('dforge'), ...w.userInstall('dagents') });
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true, 'dagents@darkraise': true } });
  w.json(join(w.project, '.claude/settings.json'), { enabledPlugins: { 'dagents@darkraise': true } });
  w.json(join(w.project, '.claude/settings.local.json'), { enabledPlugins: { 'dagents@darkraise': false } });
  assert.equal(w.run(['--host', 'claude']).stdout, 'dforge@darkraise user\n', 'local false wins over project true');
  rmSync(join(w.project, '.claude/settings.local.json'));
  w.json(join(w.managed, 'managed-settings.json'), { enabledPlugins: { 'dforge@darkraise': true } });
  mkdirSync(join(w.managed, 'managed-settings.d'));
  w.json(join(w.managed, 'managed-settings.d/10-off.json'), { enabledPlugins: { 'dforge@darkraise': false } });
  assert.equal(w.run(['--host', 'claude']).stdout, 'dagents@darkraise project\n', 'a drop-in false wins over the managed file');
});

test('a hook run that cannot read its inputs clears the session marker and stays silent on stdout', t => {
  const w = world(t);
  w.installs({ ...w.userInstall('dforge'), ...w.userInstall('dagents') });
  const marker = join(w.data, 'workflow-guard', 's-1');
  mkdirSync(join(w.data, 'workflow-guard'), { recursive: true });
  writeFileSync(marker, 'earlier conflict\n');
  writeFileSync(join(w.claude, 'settings.json'), '{ not json');
  const out = w.run(['--host', 'claude', '--self', 'dagents', '--hook', 'session-start'], JSON.stringify({ session_id: 's-1' }));
  assert.deepEqual([out.status, out.stdout], [0, '']);
  assert.equal(out.stderr.trim().split('\n').length, 1);
  assert.match(out.stderr, /^workflow-guard: /);
  assert.equal(existsSync(marker), false, 'the failed check leaves no stand-down behind');
});

test('the conflict block tells a managed self how to disable it', t => {
  const w = world(t);
  w.installs({ ...w.userInstall('dforge'), ...w.userInstall('dagents') });
  w.json(join(w.managed, 'managed-settings.json'), { enabledPlugins: { 'dagents@darkraise': true } });
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true } });
  const out = w.run(['--host', 'claude', '--self', 'dagents', '--hook', 'session-start'], JSON.stringify({ session_id: 's-4' }));
  assert.equal(out.status, 3, out.stderr);
  const message = JSON.parse(out.stdout).systemMessage;
  assert.ok(message.includes('- dagents@darkraise: dagents@darkraise is enabled by managed settings; ask your administrator to disable it'), message);
  assert.ok(message.includes('dagents@darkraise (this session)'), message);
  assert.ok(!message.includes('claude plugin disable dagents@darkraise --scope local'), message);
});

test('a marker that cannot be written still announces the conflict', t => {
  const w = world(t);
  w.installs({ ...w.userInstall('dforge'), ...w.userInstall('dagents') });
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true, 'dagents@darkraise': true } });
  writeFileSync(join(w.data, 'workflow-guard'), 'a file where the marker directory belongs\n');
  const out = w.run(['--host', 'claude', '--self', 'dagents', '--hook', 'session-start'], JSON.stringify({ session_id: 's-2' }));
  assert.equal(out.status, 3);
  assert.match(JSON.parse(out.stdout).systemMessage, /dforge@darkraise/);
  assert.match(out.stderr, /^workflow-guard: the stand-down marker could not be written/);
});

test('a malformed file gives one diagnostic and no conflict', t => {
  const w = world(t);
  w.installs({ ...w.userInstall('dforge'), ...w.userInstall('dagents') });
  writeFileSync(join(w.claude, 'settings.json'), '{ not json');
  const out = w.run(['--host', 'claude']);
  assert.equal(out.status, 0);
  assert.equal(out.stderr.trim().split('\n').length, 1);
  assert.match(out.stderr, /^workflow-guard: /);
});

test('the session-start hook returns the block for the user and the model, and keeps its marker in step', t => {
  const w = world(t);
  w.installs({ ...w.userInstall('dforge'), ...w.userInstall('dflow') });
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true } });
  w.json(join(w.project, '.claude/settings.json'), { enabledPlugins: { 'dflow@darkraise': true } });
  const event = JSON.stringify({ session_id: 'ab/c 1', hook_event_name: 'SessionStart', source: 'startup' });
  const marker = join(w.data, 'workflow-guard', 'ab-c-1');
  const hit = w.run(['--host', 'claude', '--self', 'dagents', '--hook', 'session-start'], event);
  assert.equal(hit.status, 3);
  const out = JSON.parse(hit.stdout);
  for (const text of [out.systemMessage, out.hookSpecificOutput.additionalContext]) {
    for (const name of ['dagents', 'dforge', 'dflow']) assert.match(text, new RegExp(`${name}@darkraise`));
    assert.ok(text.indexOf('claude plugin disable dforge@darkraise --scope local') < text.indexOf('claude plugin disable dforge@darkraise --scope user'));
    assert.match(text, /claude plugin disable dflow@darkraise --scope project/);
  }
  assert.equal(out.hookSpecificOutput.hookEventName, 'SessionStart');
  assert.ok(existsSync(marker));
  const old = join(w.data, 'workflow-guard', 'stale');
  writeFileSync(old, '');
  const past = (Date.now() - 8 * 86400 * 1000) / 1000;
  utimesSync(old, past, past);
  w.json(join(w.project, '.claude/settings.json'), { enabledPlugins: { 'dflow@darkraise': false } });
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': false } });
  const clear = w.run(['--host', 'claude', '--self', 'dagents', '--hook', 'session-start'], event);
  assert.deepEqual([clear.status, clear.stdout], [0, '']);
  assert.equal(existsSync(marker), false, 'no conflict deletes the marker');
  assert.equal(existsSync(old), false, 'markers older than seven days are pruned');
});

test('the guard writes no settings file and no install record', t => {
  const w = world(t);
  w.installs({ ...w.userInstall('dforge'), ...w.userInstall('dagents') });
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true, 'dagents@darkraise': true } });
  const snapshot = () => [join(w.claude, 'settings.json'), join(w.claude, 'plugins/installed_plugins.json'), join(w.project, '.claude/settings.json')]
    .map(f => existsSync(f) ? `${statSync(f).mtimeMs}:${readFileSync(f, 'utf8')}` : 'absent');
  const before = snapshot();
  w.run(['--host', 'claude', '--self', 'dagents', '--hook', 'session-start'], JSON.stringify({ session_id: 's' }));
  w.run(['--host', 'claude']);
  assert.deepEqual(snapshot(), before);
});

test('Codex reads config.toml and never combines hosts', t => {
  const w = world(t);
  writeFileSync(join(w.codex, 'config.toml'), '[plugins."dforge@darkraise"]\nenabled = true\n\n[plugins."dagents@darkraise"]\nenabled = true\n');
  assert.equal(w.run(['--host', 'codex']).status, 3);
  writeFileSync(join(w.project, '.codex/config.toml'), '[plugins."dagents@darkraise"]\nenabled = false\n');
  assert.equal(w.run(['--host', 'codex']).status, 0, 'the project file wins');
  writeFileSync(join(w.codex, 'config.toml'), '[plugins."dagents@darkraise"]\nenabled = true\n');
  rmSync(join(w.project, '.codex/config.toml'));
  w.installs(w.userInstall('dforge'));
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true } });
  assert.equal(w.run(['--host', 'claude']).status, 0);
  assert.equal(w.run(['--host', 'codex']).status, 0);
  assert.equal(w.run([]).status, 2);
});
