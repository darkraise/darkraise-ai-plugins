import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const BIN = fileURLToPath(new URL('../../plugins/dflow/bin/dflow', import.meta.url));
export const PLUGIN = fileURLToPath(new URL('../../plugins/dflow/', import.meta.url));

// The session-start hook runs the workflow guard, which must not read the
// host's plugin settings: a caller that wants it to sets these itself.
const GUARD_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'dflow-guard-'));
process.on('exit', () => fs.rmSync(GUARD_DIR, { recursive: true, force: true }));
const GUARD_ENV = { WORKFLOW_GUARD_CLAUDE_DIR: GUARD_DIR, WORKFLOW_GUARD_MANAGED_DIR: GUARD_DIR, WORKFLOW_GUARD_PROJECT_DIR: GUARD_DIR };

export function sh(cwd, command, args, options = {}) {
  const result = spawnSync(command, args, { cwd, encoding: 'utf8', timeout: 60000, ...options });
  return { status: result.status, stdout: result.stdout ?? '', stderr: result.stderr ?? '' };
}

export function git(cwd, ...args) {
  const result = sh(cwd, 'git', args);
  if (result.status !== 0) throw new Error(`git ${args.join(' ')}: ${result.stderr}`);
  return result.stdout.trim();
}

export function write(root, relative, text) {
  const file = path.join(root, relative);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text);
  return file;
}

export function read(root, relative) {
  return fs.readFileSync(path.join(root, relative), 'utf8');
}

export function makeRepo(t, { branch = 'feat/x' } = {}) {
  // The native form expands a Windows short name, as git does.
  const root = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'dflow-test-')));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  git(root, 'init', '-q', '-b', 'main');
  git(root, 'config', 'user.name', 'Test');
  git(root, 'config', 'user.email', 'test@example.com');
  git(root, 'config', 'commit.gpgsign', 'false');
  write(root, 'README.md', '# fixture\n');
  git(root, 'add', '-A');
  git(root, 'commit', '-q', '-m', 'chore: start');
  if (branch) git(root, 'switch', '-q', '-c', branch);
  return root;
}

export function dflow(root, args, { env = {}, input, cwd = '.' } = {}) {
  const home = path.join(root, '.test-home');
  return sh(path.join(root, cwd), process.execPath, [BIN, ...args], {
    input,
    env: { ...process.env, HOME: home, DFLOW_HOME: path.join(home, '.dflow'), DFLOW_TODAY: '2026-11-12', CLAUDE_CONFIG_DIR: '', CLAUDE_CODE_SESSION_ID: '', ...GUARD_ENV, ...env },
  });
}

export const PLAN = `# Rate-limit meter

**Board:** 1 · **Branch:** feat/x
**Goal:** Show the remaining rate limit.
**Acceptance:**
- A1: \`node check.mjs\` passes
**Docs:** none — the fixture has no living docs
**Risk:** none

## Design

- D1: a parser function — one call site

## Tasks

### Task 1: Parse the header
**Files:** src/limit.mjs, tests/ · **After:** — · **Run:** inline · **Size:** S
- [ ] Test: a header parses
- [ ] Implement \`parseLimit\`
- [ ] Verify: \`node verify1.mjs\`

### Task 2: Draw the meter
**Files:** src/meter.mjs · **After:** 1 · **Run:** inline · **Size:** S
- [ ] Implement \`drawMeter\`
- [ ] Verify: \`node verify2.mjs\`

## Log
`;

// A repository with dflow set up on main, and PLAN approved and committed on
// the branch feat/x.
export function makeProject(t, { plan = PLAN, config } = {}) {
  const root = makeRepo(t, { branch: null });
  const init = dflow(root, ['init']);
  if (init.status !== 0) throw new Error(init.stderr);
  if (config) write(root, 'docs/dflow/config.json', JSON.stringify(config));
  // The scripts a test stands in for a project's test commands with are
  // ignored, as build output would be: `dflow done` refuses a tree that holds
  // changes it would not commit.
  fs.appendFileSync(path.join(root, '.gitignore'), 'verify*.mjs\ncheck.mjs\nsuite.mjs\nlint.mjs\nprobe.mjs\nshot.png\n.transcripts/\n');
  write(root, 'docs/dflow/board.md', '# board\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | Meter | - | It works | open | - |\n');
  git(root, 'add', '-A');
  git(root, 'commit', '-q', '-m', 'docs: set up dflow');
  git(root, 'switch', '-q', '-c', 'feat/x');
  write(root, 'docs/dflow/plans/2026-11-12-meter.md', plan);
  git(root, 'add', '-A');
  git(root, 'commit', '-q', '-m', 'docs: draft the plan');
  const approved = dflow(root, ['plan', 'approve']);
  if (approved.status !== 0) throw new Error(approved.stderr + approved.stdout);
  return root;
}

export const PLAN_FILE = 'docs/dflow/plans/2026-11-12-meter.md';

// spawnSync would block the event loop that serves a stub server in the same
// process, so tests that talk to one run the CLI asynchronously.
export function dflowAsync(root, args, { env = {} } = {}) {
  const home = path.join(root, '.test-home');
  return new Promise(resolve => {
    const child = spawn(process.execPath, [BIN, ...args], {
      cwd: root,
      env: { ...process.env, HOME: home, DFLOW_HOME: path.join(home, '.dflow'), DFLOW_TODAY: '2026-11-12', CLAUDE_CONFIG_DIR: '', CLAUDE_CODE_SESSION_ID: '', ...GUARD_ENV, ...env },
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    const timer = setTimeout(() => child.kill('SIGKILL'), 60000);
    child.on('close', status => {
      clearTimeout(timer);
      resolve({ status, stdout, stderr });
    });
  });
}
