import { spawn, spawnSync } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { selectShard } from './test-shards.mjs';

const { values: options } = parseArgs({ options: { shard: { type: 'string' }, list: { type: 'boolean' } } });

const root = fileURLToPath(new URL('../', import.meta.url));
const bash = process.env.DR_TEST_BASH ?? 'bash';
let child;
let timer;
let forceTimer;
let interrupted = false;
function terminate(force = false) {
  if (!child?.pid) return;
  if (process.platform === 'win32') spawnSync('taskkill', ['/F', '/T', '/PID', String(child.pid)], { timeout: 10000, stdio: 'ignore', windowsHide: true });
  else { try { process.kill(-child.pid, force ? 'SIGKILL' : 'SIGTERM'); } catch {} }
}
function stop() {
  terminate();
  forceTimer ??= setTimeout(() => terminate(true), 5000);
}
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { interrupted = true; stop(); process.exitCode = 1; });
async function run(executable, args, seconds) {
  console.log(`\nRunning ${args.join(' ')}`);
  const started = Date.now();
  return new Promise((resolveRun, reject) => {
    child = spawn(executable, args, { cwd: root, stdio: 'inherit', windowsHide: true, detached: process.platform !== 'win32', env: { ...process.env, DR_TEST_BASH: bash } });
    timer = setTimeout(() => { console.error(`Timeout after ${seconds}s`); stop(); }, seconds * 1000);
    child.on('error', error => { clearTimeout(timer); clearTimeout(forceTimer); forceTimer = undefined; child = undefined; reject(error); });
    child.on('exit', (code, signal) => {
      console.log(`Finished ${args.join(' ')} in ${((Date.now() - started) / 1000).toFixed(1)}s (exit ${code ?? signal})`);
      clearTimeout(timer); clearTimeout(forceTimer); forceTimer = undefined;
      if (process.platform !== 'win32') terminate(true);
      child = undefined; resolveRun(code === 0 && !signal);
    });
  });
}
// The cockpit's tests need the claude CLI; CI runs them in their own pinned-CLI step.
const hasClaude = !options.list && process.platform !== 'win32' && spawnSync('claude', ['--version'], { stdio: 'ignore', timeout: 5000 }).status === 0;
// The mod's type check needs tsc on PATH and the declarations Claude Code lays
// beside a mod it loads from a folder, which are gitignored: a fresh clone has none.
const typesGenerated = ['plugins/dforge/tsconfig.json', 'plugins/dforge/.claude-plugin/types/tsconfig.json'].every(path => existsSync(resolve(root, path)));
// npm installs tsc on Windows as tsc.cmd, which Node spawns only through a
// shell (EINVAL without one since the April 2024 security releases), so there
// both the probe and the job run it through cmd.exe.
const [tscExecutable, tscPrefix] = process.platform === 'win32' ? [process.env.ComSpec ?? 'cmd.exe', ['/d', '/s', '/c', 'tsc']] : ['tsc', []];
// Detected under --list too, so a listing shows the job that a run would start.
const hasTsc = typesGenerated && spawnSync(tscExecutable, [...tscPrefix, '--version'], { stdio: 'ignore', timeout: 10000, windowsHide: true }).status === 0;
// plan-lint runs about 240 checks of a few processes each, which take over ten
// minutes on a Windows runner and under a minute on Linux.
const suiteSeconds = { 'plan-lint.test.sh': 900, 'speed-and-cost-followups.acceptance.test.sh': 1200, 'task-loop-steps.acceptance.test.sh': 1200, 'task-step-base.test.sh': 900, 'task-step.test.sh': 1450 };
// faster-plans takes about 20 minutes on a Windows runner, more than a shard
// can hold beside anything else, so it runs as two halves of its tests.
const suiteParts = {
  'faster-plans.acceptance.test.sh': [Array.from({ length: 12 }, (_, i) => `a${i + 1}`), Array.from({ length: 11 }, (_, i) => `a${i + 13}`)],
  // speed-and-cost-followups ran past 600 s on a Windows runner; A12 alone
  // re-runs two whole suites.
  'speed-and-cost-followups.acceptance.test.sh': [['A1', 'A2', 'A3', 'A4', 'A6', 'A7', 'A8', 'A9', 'A10', 'A11'], ['A12'], ['A13', 'A14', 'A15', 'A16', 'A19', 'A20', 'A21', 'A23']],
};
const jobs = [
  [process.execPath, ['scripts/validate-repository.mjs'], 60],
  [process.execPath, ['--test', ...readdirSync(resolve(root, 'tests')).filter(name => name.endsWith('.test.mjs')).map(name => `tests/${name}`)], 120],
  // The tier-eval harness kills process groups and shells out to tar, so its
  // tests run on POSIX only.
  ...(process.platform === 'win32' ? [] : [[process.execPath, ['--test', ...readdirSync(resolve(root, 'evals/tiers/tests')).filter(name => name.endsWith('.test.mjs')).map(name => `evals/tiers/tests/${name}`)], 300]]),
  // The controller-eval harness reads transcripts through dforge's bash
  // in-flight scanner, so it is POSIX only too.
  ...(process.platform === 'win32' ? [] : [[process.execPath, ['--test', ...readdirSync(resolve(root, 'evals/controller/tests')).filter(name => name.endsWith('.test.mjs')).map(name => `evals/controller/tests/${name}`)], 300]]),
  [bash, ['plugins/dr-status/tests/run-all.sh'], 420],
  ...readdirSync(resolve(root, 'plugins/dforge/tests')).filter(name => name.endsWith('.test.sh')).sort().flatMap(name => (suiteParts[name] ?? [[]]).map(part => [bash, [`plugins/dforge/tests/${name}`, ...part], suiteSeconds[name] ?? 600])),
  ...(hasClaude ? [['claude', ['plugin', 'test', 'plugins/dforge'], 300]] : []),
  ...(hasTsc ? [[tscExecutable, [...tscPrefix, '--noEmit', '-p', 'plugins/dforge'], 300]] : []),
];
if (!options.list && !hasTsc) {
  console.log(`Skipped tsc --noEmit -p plugins/dforge: ${typesGenerated ? 'tsc not found' : 'the generated types are missing (Claude Code writes them when it loads plugins/dforge from the folder)'}`);
}
let success = true;
for (const [executable, args, seconds] of selectShard(jobs, options.shard)) {
  if (options.list) { console.log(args.join(' ')); continue; }
  if (interrupted) break;
  if (!await run(executable, args, seconds)) success = false;
}
process.exitCode = success && !interrupted ? 0 : 1;
