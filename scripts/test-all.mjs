import { spawn, spawnSync } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { driftWarning, selectShard } from './test-shards.mjs';

const { values: options } = parseArgs({ options: { shard: { type: 'string' }, list: { type: 'boolean' }, limits: { type: 'boolean' } } });
if (options.limits && !options.list) {
  console.error('test-all: --limits only changes what --list prints');
  process.exit(2);
}

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
  let timedOut = false;
  return new Promise((resolveRun, reject) => {
    child = spawn(executable, args, { cwd: root, stdio: 'inherit', windowsHide: true, detached: process.platform !== 'win32', env: { ...process.env, DR_TEST_BASH: bash, DR_TEST_ALL: '1' } });
    timer = setTimeout(() => { timedOut = true; console.error(`Timeout after ${seconds}s`); stop(); }, seconds * 1000);
    child.on('error', error => { clearTimeout(timer); clearTimeout(forceTimer); forceTimer = undefined; child = undefined; reject(error); });
    child.on('exit', (code, signal) => {
      const elapsed = (Date.now() - started) / 1000;
      console.log(`Finished ${args.join(' ')} in ${elapsed.toFixed(1)}s (exit ${code ?? signal})`);
      // A timed-out or killed job has already failed; a warning would repeat it.
      const warning = timedOut || signal || interrupted ? undefined : driftWarning(args, elapsed, seconds);
      if (warning !== undefined) console.log(warning);
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
// minutes on a Windows runner and under a minute on Linux. next-step and
// auto-run take about 500 s on a Windows runner; 700 s keeps that under 80% of
// their limit. task-step's limit applies to each of its parts.
const suiteSeconds = { 'plan-lint.test.sh': 1200, 'speed-and-cost-followups.acceptance.test.sh': 1200, 'task-loop-steps.acceptance.test.sh': 1200, 'task-step-base.test.sh': 900, 'task-step.test.sh': 900, 'next-step.test.sh': 700, 'auto-run.test.sh': 700 };
// faster-plans takes about 20 minutes on a Windows runner, more than a shard
// can hold beside anything else, so it runs as three parts of its tests.
// task-step runs as four parts, one per section of the suite.
const suiteParts = {
  'faster-plans.acceptance.test.sh': [Array.from({ length: 8 }, (_, i) => `a${i + 1}`), Array.from({ length: 8 }, (_, i) => `a${i + 9}`), Array.from({ length: 7 }, (_, i) => `a${i + 17}`)],
  'task-step.test.sh': [['start'], ['rereview'], ['group'], ['verdict']],
  // speed-and-cost-followups ran past 600 s on a Windows runner while its A12
  // re-ran two whole suites, which it skips under test-all.
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
  // DR_TEST_ALL tells a suite that every other suite runs as its own job, so
  // the acceptance checks that re-run whole suites skip those re-runs.
  ...readdirSync(resolve(root, 'plugins/dforge/tests')).filter(name => name.endsWith('.test.sh') || name.endsWith('.acceptance.sh')).sort().flatMap(name => (suiteParts[name] ?? [[]]).map(part => [bash, [`plugins/dforge/tests/${name}`, ...part], suiteSeconds[name] ?? 600])),
  ...(hasClaude ? [['claude', ['plugin', 'test', 'plugins/dforge'], 300]] : []),
  ...(hasTsc ? [[tscExecutable, [...tscPrefix, '--noEmit', '-p', 'plugins/dforge'], 300]] : []),
];
if (!options.list && !hasTsc) {
  console.log(`Skipped tsc --noEmit -p plugins/dforge: ${typesGenerated ? 'tsc not found' : 'the generated types are missing (Claude Code writes them when it loads plugins/dforge from the folder)'}`);
}
let success = true;
for (const [executable, args, seconds] of selectShard(jobs, options.shard)) {
  if (options.list) { console.log(options.limits ? `${seconds}\t${args.join(' ')}` : args.join(' ')); continue; }
  if (interrupted) break;
  if (!await run(executable, args, seconds)) success = false;
}
process.exitCode = success && !interrupted ? 0 : 1;
