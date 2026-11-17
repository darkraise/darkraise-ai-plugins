#!/usr/bin/env node
// workflow-guard.mjs --host claude|codex [--self <name>] [--hook session-start]
//
// dforge, dagents and dflow each own a whole workflow: their hooks, skills and
// state collide when two run in one session. This check reads the host's own
// settings to find which of them are active and, as a SessionStart hook, tells
// the user and the model when more than one is. The same file ships,
// byte-identical, in each of the three plugins.
//
// Exit: 0 at most one active (or a file could not be read: fail open), 3 two
// or more, 2 bad usage. It never writes a settings file or the install record.
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';

const SIBLINGS = ['dforge', 'dagents', 'dflow'];
const MARKETPLACE = 'darkraise';
const MARKER_DAYS = 7;
const USAGE = 'usage: workflow-guard.mjs --host claude|codex [--self <name>] [--hook session-start]';

class Unreadable extends Error {}

// The hook's marker, once known, so a failure can clear it as no conflict does.
let hookMarker = null;

function parseArgs(argv) {
  const options = { host: null, self: null, hook: null };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!['--host', '--self', '--hook'].includes(flag) || value === undefined) return null;
    options[flag.slice(2)] = value;
    index += 1;
  }
  if (!['claude', 'codex'].includes(options.host)) return null;
  if (options.self !== null && !SIBLINGS.includes(options.self)) return null;
  if (options.hook !== null && options.hook !== 'session-start') return null;
  return options;
}

function readText(file) {
  try {
    return readFileSync(file, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT' || error.code === 'ENOTDIR') return null;
    throw new Unreadable(`${file}: ${error.message}`);
  }
}

function readJson(file) {
  const text = readText(file);
  if (text === null) return null;
  let data;
  try {
    data = JSON.parse(text);
  } catch (error) {
    throw new Unreadable(`${file}: ${error.message}`);
  }
  if (data === null || typeof data !== 'object' || Array.isArray(data)) throw new Unreadable(`${file}: not a JSON object`);
  return data;
}

function samePath(a, b) {
  const real = file => {
    try {
      return realpathSync.native(file);
    } catch {
      return resolve(file);
    }
  };
  const x = real(a);
  const y = real(b);
  return process.platform === 'win32' ? x.toLowerCase() === y.toLowerCase() : x === y;
}

function managedDefault() {
  if (process.platform === 'darwin') return '/Library/Application Support/ClaudeCode';
  if (process.platform === 'win32') return 'C:\\Program Files\\ClaudeCode';
  return '/etc/claude-code';
}

function projectDir(env) {
  if (env.WORKFLOW_GUARD_PROJECT_DIR) return env.WORKFLOW_GUARD_PROJECT_DIR;
  if (env.CLAUDE_PROJECT_DIR) return env.CLAUDE_PROJECT_DIR;
  const top = spawnSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8', timeout: 10000 });
  return top.status === 0 && top.stdout.trim() ? top.stdout.trim() : process.cwd();
}

const enabledIn = settings => (settings && settings.enabledPlugins && typeof settings.enabledPlugins === 'object' && !Array.isArray(settings.enabledPlugins) ? settings.enabledPlugins : {});

// The managed file first, then every visible *.json drop-in in name order,
// each later one replacing the keys it sets.
function managedPlugins(dir) {
  const merged = { ...enabledIn(readJson(join(dir, 'managed-settings.json'))) };
  const dropins = join(dir, 'managed-settings.d');
  let names = [];
  try {
    names = readdirSync(dropins).filter(name => name.endsWith('.json') && !name.startsWith('.')).sort();
  } catch (error) {
    if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') throw new Unreadable(`${dropins}: ${error.message}`);
  }
  for (const name of names) Object.assign(merged, enabledIn(readJson(join(dropins, name))));
  return merged;
}

function installedHere(record, id, project) {
  const installs = record?.plugins?.[id];
  if (!Array.isArray(installs)) return false;
  return installs.some(install => install && (install.scope === 'user' || install.scope === 'managed'
    || ((install.scope === 'project' || install.scope === 'local') && typeof install.projectPath === 'string' && samePath(install.projectPath, project))));
}

function claudeActive(env) {
  const claudeDir = env.WORKFLOW_GUARD_CLAUDE_DIR || env.CLAUDE_CONFIG_DIR || join(homedir(), '.claude');
  const managedDir = env.WORKFLOW_GUARD_MANAGED_DIR || managedDefault();
  const project = projectDir(env);
  const scopes = [
    ['managed', managedPlugins(managedDir)],
    ['local', enabledIn(readJson(join(project, '.claude', 'settings.local.json')))],
    ['project', enabledIn(readJson(join(project, '.claude', 'settings.json')))],
    ['user', enabledIn(readJson(join(claudeDir, 'settings.json')))],
  ];
  const installs = readJson(join(claudeDir, 'plugins', 'installed_plugins.json'));
  const active = [];
  for (const name of SIBLINGS) {
    const id = `${name}@${MARKETPLACE}`;
    if (!installedHere(installs, id, project)) continue;
    const decided = scopes.find(([, plugins]) => typeof plugins[id] === 'boolean');
    if (!decided) active.push({ name, scope: 'default' });
    else if (decided[1][id]) active.push({ name, scope: decided[0] });
  }
  return active;
}

// The subset of TOML Codex's config uses for plugins: [plugins."<id>"] tables
// holding an enabled boolean. Any other line is skipped.
function tomlPlugins(file) {
  const text = readText(file);
  const plugins = {};
  if (text === null) return plugins;
  let current = null;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.replace(/\s+#.*$/, '').trim();
    if (!line || line.startsWith('#')) continue;
    const table = line.match(/^\[\s*plugins\s*\.\s*(?:"([^"]+)"|'([^']+)'|([A-Za-z0-9_-]+))\s*\]$/);
    if (table) {
      current = table[1] ?? table[2] ?? table[3];
      continue;
    }
    if (line.startsWith('[')) {
      current = null;
      continue;
    }
    const enabled = line.match(/^enabled\s*=\s*(true|false)$/);
    if (current !== null && enabled) plugins[current] = enabled[1] === 'true';
  }
  return plugins;
}

function codexActive(env) {
  const scopes = [
    ['project', tomlPlugins(join(projectDir(env), '.codex', 'config.toml'))],
    ['user', tomlPlugins(join(env.CODEX_HOME || join(homedir(), '.codex'), 'config.toml'))],
  ];
  const active = [];
  for (const name of SIBLINGS) {
    const id = `${name}@${MARKETPLACE}`;
    const decided = scopes.find(([, plugins]) => typeof plugins[id] === 'boolean');
    if (decided && decided[1][id]) active.push({ name, scope: decided[0] });
  }
  return active;
}

function activePlugins(env, options) {
  const found = options.host === 'claude' ? claudeActive(env) : codexActive(env);
  const active = found.filter(plugin => plugin.name !== options.self);
  if (options.self) active.push({ name: options.self, scope: 'self' });
  return active.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
}

function disableSteps(plugin, host) {
  const id = `${plugin.name}@${MARKETPLACE}`;
  if (host === 'codex') return [`set enabled = false under [plugins."${id}"] in the Codex config.toml that enables it`];
  if (plugin.scope === 'managed') return [`${id} is enabled by managed settings; ask your administrator to disable it`];
  const steps = [`claude plugin disable ${id} --scope local`];
  if (plugin.scope === 'user' || plugin.scope === 'project') steps.push(`claude plugin disable ${id} --scope ${plugin.scope}`);
  return steps;
}

function conflictBlock(active, host) {
  const names = active.map(plugin => `${plugin.name}@${MARKETPLACE} (${plugin.scope === 'self' ? 'this session' : plugin.scope})`);
  const lines = [
    `Workflow plugins conflict: ${names.join(', ')} are enabled together. Each owns a whole workflow, so only one may be enabled. Keep one and disable the others:`,
  ];
  for (const plugin of active) lines.push(`- ${plugin.name}@${MARKETPLACE}: ${disableSteps(plugin, host).join(', then ')}`);
  lines.push('Then start a new session.');
  return lines.join('\n');
}

const markerName = session => session.replace(/[^A-Za-z0-9]/g, '-');

function pruneMarkers(dir) {
  let names = [];
  try {
    names = readdirSync(dir);
  } catch {
    return;
  }
  const cutoff = Date.now() - MARKER_DAYS * 86400 * 1000;
  for (const name of names) {
    const file = join(dir, name);
    try {
      if (statSync(file).mtimeMs < cutoff) rmSync(file, { force: true });
    } catch {
      // Gone already, or not ours to remove.
    }
  }
}

function readStdin() {
  try {
    return readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function hookRun(env, options) {
  const text = readStdin();
  let event = {};
  if (text.trim()) {
    try {
      event = JSON.parse(text);
    } catch (error) {
      throw new Unreadable(`the hook event on stdin is not JSON: ${error.message}`);
    }
  }
  const session = typeof event?.session_id === 'string' ? event.session_id : '';
  const markers = env.CLAUDE_PLUGIN_DATA ? join(env.CLAUDE_PLUGIN_DATA, 'workflow-guard') : null;
  if (markers) pruneMarkers(markers);
  const marker = markers && session ? join(markers, markerName(session)) : null;
  hookMarker = marker;
  const active = activePlugins(env, options);
  if (active.length < 2) {
    if (marker) rmSync(marker, { force: true });
    return 0;
  }
  const block = conflictBlock(active, options.host);
  const others = active.map(plugin => `${plugin.name}@${MARKETPLACE}`).join(', ');
  const relay = `Show the block above to the user as it is, before anything else. Until only one of ${others} is enabled, use no skill, command or agent of any of them.`;
  if (marker) {
    mkdirSync(markers, { recursive: true });
    writeFileSync(marker, `${new Date().toISOString()}\n`);
  }
  process.stdout.write(`${JSON.stringify({ systemMessage: block, hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: `${block}\n\n${relay}` } })}\n`);
  return 3;
}

function main(argv, env) {
  const options = parseArgs(argv);
  if (!options) {
    process.stderr.write(`${USAGE}\n`);
    return 2;
  }
  try {
    if (options.hook) return hookRun(env, options);
    const active = activePlugins(env, options);
    for (const plugin of active) process.stdout.write(`${plugin.name}@${MARKETPLACE} ${plugin.scope}\n`);
    return active.length >= 2 ? 3 : 0;
  } catch (error) {
    process.stderr.write(`workflow-guard: ${String(error?.message ?? error).split('\n')[0]}\n`);
    if (hookMarker) rmSync(hookMarker, { force: true });
    return 0;
  }
}

process.exitCode = main(process.argv.slice(2), process.env);
