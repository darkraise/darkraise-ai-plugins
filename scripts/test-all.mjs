import { spawn, spawnSync } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
import { availableParallelism } from 'node:os';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const { values: options } = parseArgs({ options: { jobs: { type: 'string' } } });
if (options.jobs !== undefined && !/^[1-9]\d*$/.test(options.jobs)) {
  console.error('test-all: --jobs takes a whole number of at least 1');
  process.exit(2);
}
// Windows stays sequential: its limits were measured that way.
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
  const job = {};
  running.add(job);
  const ok = await new Promise((resolveRun, reject) => {
    job.child = spawn(executable, args, { cwd: root, stdio: buffered ? ['inherit', 'pipe', 'pipe'] : 'inherit', windowsHide: true, detached: process.platform !== 'win32', env: { ...process.env, DR_TEST_BASH: bash } });
    const closed = buffered ? Promise.all([job.child.stdout, job.child.stderr].map(stream => new Promise(done => { stream.on('data', chunk => chunks.push(chunk)); stream.on('close', done); }))) : Promise.resolve();
    job.timer = setTimeout(() => { say(`Timeout after ${seconds}s`, console.error); stop(job); }, seconds * 1000);
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
      running.delete(job);
      resolveRun(code === 0 && !signal);
    });
  });
  if (buffered) process.stdout.write(Buffer.concat(chunks));
  return ok;
}
// The cockpit's tests need the claude CLI; CI runs them in their own pinned-CLI step.
const hasClaude = process.platform !== 'win32' && spawnSync('claude', ['--version'], { stdio: 'ignore', timeout: 5000 }).status === 0;
// The mod's type check needs tsc on PATH and the declarations Claude Code lays
// beside a mod it loads from a folder, which are gitignored: a fresh clone has none.
const typesGenerated = ['plugins/dforge/tsconfig.json', 'plugins/dforge/.claude-plugin/types/tsconfig.json'].every(path => existsSync(resolve(root, path)));
// npm installs tsc on Windows as tsc.cmd, which Node spawns only through a
// shell (EINVAL without one since the April 2024 security releases), so there
// both the probe and the job run it through cmd.exe.
const [tscExecutable, tscPrefix] = process.platform === 'win32' ? [process.env.ComSpec ?? 'cmd.exe', ['/d', '/s', '/c', 'tsc']] : ['tsc', []];
const hasTsc = typesGenerated && spawnSync(tscExecutable, [...tscPrefix, '--version'], { stdio: 'ignore', timeout: 10000, windowsHide: true }).status === 0;
const jobs = [
  [process.execPath, ['scripts/validate-repository.mjs'], 60],
  [process.execPath, ['--test', ...readdirSync(resolve(root, 'tests')).filter(name => name.endsWith('.test.mjs')).map(name => `tests/${name}`)], 120],
  [bash, ['plugins/dr-status/tests/run-all.sh'], 420],
  ...readdirSync(resolve(root, 'plugins/dforge/tests')).filter(name => name.endsWith('.test.sh')).sort().map(name => [bash, [`plugins/dforge/tests/${name}`], 600]),
  ...(hasClaude ? [['claude', ['plugin', 'test', 'plugins/dforge'], 300]] : []),
  ...(hasTsc ? [[tscExecutable, [...tscPrefix, '--noEmit', '-p', 'plugins/dforge'], 300]] : []),
];
if (!hasTsc) {
  console.log(`Skipped tsc --noEmit -p plugins/dforge: ${typesGenerated ? 'tsc not found' : 'the generated types are missing (Claude Code writes them when it loads plugins/dforge from the folder)'}`);
}
const workers = Math.min(parallelJobs, jobs.length);
if (workers > 1) console.log(`Running ${jobs.length} jobs, ${workers} at a time (--jobs 1 runs them in order)`);
let next = 0;
let success = true;
await Promise.all(Array.from({ length: workers }, async () => {
  while (next < jobs.length && !interrupted) {
    const [executable, args, seconds] = jobs[next++];
    if (!await run(executable, args, seconds, workers > 1)) success = false;
  }
}));
process.exitCode = success && !interrupted ? 0 : 1;
