import { spawn, spawnSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
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
const jobs = [
  [process.execPath, ['scripts/validate-repository.mjs'], 60],
  [process.execPath, ['--test', ...readdirSync(resolve(root, 'tests')).filter(name => name.endsWith('.test.mjs')).map(name => `tests/${name}`)], 120],
  [bash, ['plugins/dr-status/tests/run-all.sh'], 420],
  ...readdirSync(resolve(root, 'plugins/dr-superpowers/tests')).filter(name => name.endsWith('.test.sh')).sort().map(name => [bash, [`plugins/dr-superpowers/tests/${name}`], 600]),
];
let success = true;
for (const [executable, args, seconds] of selectShard(jobs, options.shard)) {
  if (options.list) { console.log(args.join(' ')); continue; }
  if (interrupted) break;
  if (!await run(executable, args, seconds)) success = false;
}
process.exitCode = success && !interrupted ? 0 : 1;
