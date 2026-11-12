import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const KEEP_BYTES = 256 * 1024;

function killTree(child) {
  if (!child.pid) return;
  if (process.platform === 'win32') {
    spawnSync('taskkill', ['/F', '/T', '/PID', String(child.pid)], { stdio: 'ignore', timeout: 10000, windowsHide: true });
    return;
  }
  // The command runs in its own process group so that its children die with it.
  for (const signal of ['SIGTERM', 'SIGKILL']) {
    try {
      process.kill(-child.pid, signal);
    } catch {
      return;
    }
  }
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
    const shell = process.platform === 'win32' ? (env.DFLOW_SHELL || 'bash') : (env.DFLOW_SHELL || '/bin/sh');
    const child = spawn(shell, ['-c', command], { cwd, env, stdio: ['ignore', 'pipe', 'pipe'], detached: process.platform !== 'win32', windowsHide: true });
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
    const finish = status => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (process.platform !== 'win32') killTree(child);
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
