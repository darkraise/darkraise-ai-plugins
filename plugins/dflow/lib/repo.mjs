import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fail, git, gitOut, readJson, writeJson } from './util.mjs';

export const DEFAULTS = {
  defaultBranch: null,
  gates: [],
  run: null,
  verifyTimeout: 600,
  budgets: { 'project.md': 150, 'gotchas.md': 100 },
  context: { resetAt: 150000 },
  review: { tier0Lines: 40, tier2Lines: 800, tier2Files: 25 },
  tests: {
    patterns: ['**/*.test.*', '**/*.spec.*', '**/*_test.*', '**/test_*.py', 'tests/', 'test/', '**/tests/', '**/__tests__/'],
    maxRatio: 2,
    maxSuiteGrowth: 0.2,
  },
  ui: { paths: [] },
  darkmem: { project: '' },
  // Off: the review ends the turn and shipping waits for the owner.
  autoShip: false,
};

function merge(base, extra) {
  const merged = { ...base };
  for (const [key, value] of Object.entries(extra ?? {})) {
    const isPlain = value && typeof value === 'object' && !Array.isArray(value);
    merged[key] = isPlain && base[key] && typeof base[key] === 'object' && !Array.isArray(base[key]) ? merge(base[key], value) : value;
  }
  return merged;
}

export function findRoot(cwd) {
  const root = gitOut(cwd, ['rev-parse', '--show-toplevel']);
  if (!root) fail('dflow runs inside a git repository; none found here');
  return path.resolve(root);
}

// The primary checkout of the repository, the same from each of its
// worktrees: the key under which the user enables darkmem for it.
export function primaryRoot(root) {
  const common = gitOut(root, ['rev-parse', '--path-format=absolute', '--git-common-dir']);
  if (!common || !path.isAbsolute(common)) return root;
  const top = gitOut(path.dirname(common), ['rev-parse', '--show-toplevel']);
  return top ? path.resolve(top) : root;
}

export function layout(root) {
  const docs = path.join(root, 'docs', 'dflow');
  const stateDir = path.join(root, '.dflow');
  return {
    root,
    docs,
    plans: path.join(docs, 'plans'),
    board: path.join(docs, 'board.md'),
    config: path.join(docs, 'config.json'),
    stateDir,
    state: path.join(stateDir, 'state.json'),
    events: path.join(stateDir, 'events.jsonl'),
    hud: path.join(stateDir, 'hud.json'),
    logs: path.join(stateDir, 'logs'),
  };
}

export function loadConfig(root) {
  return merge(DEFAULTS, readJson(layout(root).config, {}));
}

export function dflowHome(env = process.env) {
  return env.DFLOW_HOME || path.join(env.HOME || os.homedir(), '.dflow');
}

export function userConfig(env = process.env) {
  return readJson(path.join(dflowHome(env), 'config.json'), {});
}

// Records, in the user's own config, that this repository may send its docs to
// a darkmem project; null as the project withdraws it.
export function setDarkmemConsent(env, root, project) {
  const file = path.join(dflowHome(env), 'config.json');
  const config = readJson(file, {}) ?? {};
  const repositories = { ...(config.darkmem?.repositories ?? {}) };
  if (project) repositories[root] = project;
  else delete repositories[root];
  config.darkmem = { ...(config.darkmem ?? {}), repositories };
  writeJson(file, config);
}

export function currentBranch(root) {
  return gitOut(root, ['symbolic-ref', '--quiet', '--short', 'HEAD']);
}

export function head(root) {
  return gitOut(root, ['rev-parse', '--verify', '--quiet', 'HEAD']);
}

export function defaultBranch(root, config) {
  if (config.defaultBranch) return config.defaultBranch;
  const remote = gitOut(root, ['symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD']);
  if (remote) return remote.replace(/^origin\//, '');
  for (const name of ['main', 'master']) {
    if (git(root, ['rev-parse', '--verify', '--quiet', `refs/heads/${name}`]).ok) return name;
  }
  return currentBranch(root);
}

// The commit a plan's branch left the default branch at; null on the default
// branch itself or in a repository with a single commit line.
export function baseCommit(root, config) {
  const branch = defaultBranch(root, config);
  if (!branch || branch === currentBranch(root)) return null;
  return gitOut(root, ['merge-base', 'HEAD', branch]);
}

export function isAncestor(root, ancestor, descendant = 'HEAD') {
  return git(root, ['merge-base', '--is-ancestor', ancestor, descendant]).ok;
}

export function context(cwd = process.cwd(), env = process.env) {
  const root = findRoot(cwd);
  return { root, cwd, env, paths: layout(root), config: loadConfig(root) };
}

export function relative(root, file) {
  return path.relative(root, file).split(path.sep).join('/');
}

export function listPlans(paths) {
  if (!fs.existsSync(paths.plans)) return [];
  return fs.readdirSync(paths.plans).filter(name => name.endsWith('.md')).sort().map(name => path.join(paths.plans, name));
}
