import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const KEEP_BYTES = 256 * 1024;

const GRACE_MS = 2000;

// Stops the command and what it left behind: SIGTERM to its process group, a
// grace for the group to clean up, then SIGKILL for what is still running.
async function killTree(child) {
  if (!child.pid) return;
  if (process.platform === 'win32') {
    spawnSync('taskkill', ['/F', '/T', '/PID', String(child.pid)], { stdio: 'ignore', timeout: 10000, windowsHide: true });
    return;
  }
  // The command runs in its own process group so that its children die with it.
  try {
    process.kill(-child.pid, 'SIGTERM');
  } catch {
    return;
  }
  const deadline = Date.now() + GRACE_MS;
  while (Date.now() < deadline) {
    await new Promise(resolve => setTimeout(resolve, 50));
    try {
      process.kill(-child.pid, 0);
    } catch {
      return;
    }
  }
  try {
    process.kill(-child.pid, 'SIGKILL');
  } catch {
    // The group ended in the last moment.
  }
}

let bashFound;
function findBash(env) {
  if (bashFound === undefined) {
    bashFound = (env.PATH || '').split(path.delimiter).some(dir => dir && fs.existsSync(path.join(dir, 'bash')));
  }
  return bashFound;
}

// Runs one shell command with a timeout, writing everything it prints to
// logFile and keeping the end of it in memory for the failure report.
export function runCommand(command, { cwd, timeoutSeconds, logFile, env = process.env }) {
  fs.mkdirSync(path.dirname(logFile), { recursive: true });
  const log = fs.createWriteStream(logFile, { flags: 'a' });
  log.write(`$ ${command}\n`);
  const started = Date.now();
  let kept = Buffer.alloc(0);
  let timedOut = false;
  return new Promise(resolve => {
    const shell = env.DFLOW_SHELL || (process.platform === 'win32' || findBash(env) ? 'bash' : '/bin/sh');
    // Without pipefail `npm test | tail -20` reports tail's status, so a failing
    // suite would open the task gate.
    // A POSIX shell that lacks the option exits on `set -o pipefail`, so it is
    // tried in a subshell first.
    const args = /(^|[\\/])bash(\.exe)?$/i.test(shell) ? ['-o', 'pipefail', '-c', command]
      : /(^|[\\/])(sh|dash|ash|ksh|mksh|zsh)(\.exe)?$/i.test(shell) ? ['-c', `(set -o pipefail) 2>/dev/null && set -o pipefail\n${command}`]
        : ['-c', command];
    const child = spawn(shell, args, { cwd, env, stdio: ['ignore', 'pipe', 'pipe'], detached: process.platform !== 'win32', windowsHide: true });
    const collect = chunk => {
      log.write(chunk);
      kept = Buffer.concat([kept, chunk]);
      if (kept.length > KEEP_BYTES) kept = kept.subarray(kept.length - KEEP_BYTES);
    };
    child.stdout.on('data', collect);
    child.stderr.on('data', collect);
    const timer = setTimeout(() => {
      timedOut = true;
      killTree(child);
    }, timeoutSeconds * 1000);
    let settled = false;
    const finish = async status => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (process.platform !== 'win32') await killTree(child);
      const seconds = (Date.now() - started) / 1000;
      child.stdout.destroy();
      child.stderr.destroy();
      log.end(`[exit ${timedOut ? `timeout after ${timeoutSeconds}s` : status}]\n`, () => {
        resolve({ ok: status === 0 && !timedOut, status, timedOut, seconds, output: kept.toString('utf8') });
      });
    };
    child.on('error', error => {
      collect(Buffer.from(`${error.message}\n`));
      finish(127);
    });
    // `close` waits for every process that inherited the pipes, so a command
    // that exits 0 but leaves a background child would look hung. Its exit is
    // the result; the grace only lets the last output arrive, and finish then
    // kills what the command left behind.
    child.on('exit', status => setTimeout(() => finish(status ?? 1), 300));
    child.on('close', status => finish(status ?? 1));
  });
}
