import { spawn, spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

// ROOT is the repository whose history holds the cases, DATA holds the
// manifest and the results, WORK holds snapshots and transcripts. The tests
// point all three at a fixture; PLUGIN is always the plugin beside the harness.
export const ROOT = process.env.TIER_EVAL_ROOT ?? REPO;
export const DATA = process.env.TIER_EVAL_DATA ?? resolve(REPO, 'evals/tiers');
export const WORK = process.env.TIER_EVAL_WORK ?? resolve(homedir(), '.cache/dr-tier-eval');
export const PLUGIN = resolve(REPO, 'plugins/dr-superpowers');

export function sh(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, ...opts });
  return { code: r.status ?? 1, out: r.stdout ?? '', err: r.stderr ?? '' };
}

export function git(args, opts = {}) {
  const r = sh('git', args, opts);
  if (r.code !== 0) throw new Error(`git ${args.join(' ')}: ${r.err.trim()}`);
  return r.out;
}

// Every process group run() has started and not yet reaped. Whatever ends the
// harness - a signal or an uncaught error - kills them all, so a stopped grid
// leaves no agent behind.
const live = new Set();
process.on('exit', () => {
  for (const pid of live) { try { process.kill(-pid, 'SIGKILL'); } catch {} }
});
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => process.exit(130));

// run CMD ARGS { cwd, seconds, input, env } — resolves { code, out, err,
// timedOut }. The child leads its own process group, so a timeout kills the
// whole tree and nothing it started outlives the call.
export function run(cmd, args, { cwd, seconds, input, env } = {}) {
  return new Promise(resolveRun => {
    const child = spawn(cmd, args, { cwd, env: env ?? process.env, detached: true, stdio: ['pipe', 'pipe', 'pipe'] });
    live.add(child.pid);
    let out = '', err = '', timedOut = false;
    const kill = signal => { try { process.kill(-child.pid, signal); } catch {} };
    const timer = seconds ? setTimeout(() => { timedOut = true; kill('SIGTERM'); setTimeout(() => kill('SIGKILL'), 5000).unref(); }, seconds * 1000) : null;
    child.stdout.on('data', d => { out += d; });
    child.stderr.on('data', d => { err += d; });
    child.on('error', error => { clearTimeout(timer); live.delete(child.pid); resolveRun({ code: 127, out, err: String(error), timedOut }); });
    child.on('close', code => { clearTimeout(timer); kill('SIGKILL'); live.delete(child.pid); resolveRun({ code: code ?? 1, out, err, timedOut }); });
    child.stdin.on('error', () => {});
    child.stdin.end(input ?? '');
  });
}
