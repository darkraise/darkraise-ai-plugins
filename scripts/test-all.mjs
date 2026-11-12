import { spawn, spawnSync } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
import { availableParallelism } from 'node:os';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { driftWarning, selectShard } from './test-shards.mjs';

const { values: options } = parseArgs({ options: { shard: { type: 'string' }, list: { type: 'boolean' }, limits: { type: 'boolean' }, jobs: { type: 'string' } } });
if (options.limits && !options.list) {
  console.error('test-all: --limits only changes what --list prints');
  process.exit(2);
}
if (options.jobs !== undefined && !/^[1-9]\d*$/.test(options.jobs)) {
  console.error('test-all: --jobs takes a whole number of at least 1');
  process.exit(2);
}
// Windows shards stay sequential: their weights and limits were measured that way.
const parallelJobs = options.jobs !== undefined ? Number(options.jobs) : process.platform === 'win32' ? 1 : availableParallelism();

const root = fileURLToPath(new URL('../', import.meta.url));
const bash = process.env.DR_TEST_BASH ?? 'bash';
const running = new Set();
let interrupted = false;
function terminate(job, force = false) {
  if (!job.child?.pid) return;
  if (process.platform === 'win32') spawnSync('taskkill', ['/F', '/T', '/PID', String(job.child.pid)], { timeout: 10000, stdio: 'ignore', windowsHide: true });
  else { try { process.kill(-job.child.pid, force ? 'SIGKILL' : 'SIGTERM'); } catch {} }
}
function stop(job) {
  terminate(job);
  job.forceTimer ??= setTimeout(() => terminate(job, true), 5000);
}
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { interrupted = true; for (const job of running) stop(job); process.exitCode = 1; });
// A parallel job's output is held and printed as one block when it ends, so
// the log reads suite by suite.
async function run(executable, args, seconds, buffered) {
  const chunks = [];
  const say = (text, log = console.log) => { if (buffered) chunks.push(Buffer.from(`${text}\n`)); else log(text); };
  say(`\nRunning ${args.join(' ')}`);
  const started = Date.now();
  let timedOut = false;
  const job = {};
  running.add(job);
  const ok = await new Promise((resolveRun, reject) => {
    job.child = spawn(executable, args, { cwd: root, stdio: buffered ? ['inherit', 'pipe', 'pipe'] : 'inherit', windowsHide: true, detached: process.platform !== 'win32', env: { ...process.env, DR_TEST_BASH: bash, DR_TEST_ALL: '1' } });
    const closed = buffered ? Promise.all([job.child.stdout, job.child.stderr].map(stream => new Promise(done => { stream.on('data', chunk => chunks.push(chunk)); stream.on('close', done); }))) : Promise.resolve();
    job.timer = setTimeout(() => { timedOut = true; say(`Timeout after ${seconds}s`, console.error); stop(job); }, seconds * 1000);
    job.child.on('error', error => { clearTimeout(job.timer); clearTimeout(job.forceTimer); running.delete(job); reject(error); });
    job.child.on('exit', async (code, signal) => {
      const elapsed = (Date.now() - started) / 1000;
      clearTimeout(job.timer); clearTimeout(job.forceTimer);
      if (process.platform !== 'win32') terminate(job, true);
      // A process the suite left behind may hold the pipes open past the kill.
      let grace;
      await Promise.race([closed, new Promise(done => { grace = setTimeout(done, 5000); })]);
      clearTimeout(grace);
      say(`Finished ${args.join(' ')} in ${elapsed.toFixed(1)}s (exit ${code ?? signal})`);
      // A timed-out or killed job has already failed; a warning would repeat it.
      const warning = timedOut || signal || interrupted ? undefined : driftWarning(args, elapsed, seconds);
      if (warning !== undefined) say(warning);
      running.delete(job);
      resolveRun(code === 0 && !signal);
    });
  });
  if (buffered) process.stdout.write(Buffer.concat(chunks));
  return ok;
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
// plan-lint runs about 320 checks of a few processes each, which take over
// twenty minutes on a Windows runner and under a minute on Linux. next-step and
// auto-run take about 500 s on a Windows runner; 700 s keeps that under 80% of
// their limit. plan-revise grew to about 560 s there. task-step's limit
// applies to each of its parts.
const suiteSeconds = { 'plan-lint.test.sh': 1200, 'speed-and-cost-followups.acceptance.test.sh': 1200, 'task-loop-steps.acceptance.test.sh': 1200, 'task-step-base.test.sh': 1200, 'task-step.test.sh': 900, 'next-step.test.sh': 700, 'plan-revise.test.sh': 900, 'auto-run.test.sh': 700 };
// faster-plans takes about 20 minutes on a Windows runner, more than a shard
// can hold beside anything else, so it runs as three parts of its tests.
// task-step runs as four parts, one per section of the suite, and plan-lint as
// two, whose limit applies to each.
const suiteParts = {
  'faster-plans.acceptance.test.sh': [['a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8'], ['a9', 'a10', 'a11', 'a12', 'a13'], ['a17', 'a18', 'a19', 'a20', 'a21', 'a22', 'a23']],
  'task-step.test.sh': [['start'], ['rereview'], ['group'], ['verdict']],
  'plan-lint.test.sh': [['one'], ['two']],
  // speed-and-cost-followups ran past 600 s on a Windows runner while its A12
  // re-ran two whole suites, which it skips under test-all.
  'speed-and-cost-followups.acceptance.test.sh': [['A1', 'A2', 'A3', 'A4', 'A7', 'A8', 'A9', 'A10', 'A11'], ['A12'], ['A13', 'A14', 'A15', 'A16', 'A19', 'A20', 'A23']],
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
const selected = selectShard(jobs, options.shard);
if (options.list) {
  for (const [, args, seconds] of selected) console.log(options.limits ? `${seconds}\t${args.join(' ')}` : args.join(' '));
} else {
  const workers = Math.min(parallelJobs, selected.length);
  if (workers > 1) console.log(`Running ${selected.length} jobs, ${workers} at a time (--jobs 1 runs them in order)`);
  let next = 0;
  let success = true;
  await Promise.all(Array.from({ length: workers }, async () => {
    while (next < selected.length && !interrupted) {
      const [executable, args, seconds] = selected[next++];
      if (!await run(executable, args, seconds, workers > 1)) success = false;
    }
  }));
  process.exitCode = success && !interrupted ? 0 : 1;
}
