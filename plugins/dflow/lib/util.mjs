import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

export class CliError extends Error {
  constructor(message, code = 1) {
    super(message);
    this.code = code;
  }
}

export function fail(message, code = 1) {
  throw new CliError(message, code);
}

export function today(env = process.env) {
  return env.DFLOW_TODAY || new Date().toISOString().slice(0, 10);
}

export function nowIso(env = process.env) {
  return env.DFLOW_NOW || new Date().toISOString();
}

export function sh(command, args, { cwd, timeoutMs = 30000, input, env } = {}) {
  const result = spawnSync(command, args, {
    cwd, input, env, encoding: 'utf8', timeout: timeoutMs, windowsHide: true, maxBuffer: 64 * 1024 * 1024,
  });
  return {
    ok: result.status === 0,
    status: result.status,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
    timedOut: result.error?.code === 'ETIMEDOUT',
  };
}

export function git(root, args, options = {}) {
  return sh('git', ['-C', root, ...args], options);
}

export function gitOut(root, args) {
  const result = git(root, args);
  return result.ok ? result.stdout.trim() : null;
}

export function mustGit(root, args) {
  const result = git(root, args);
  if (!result.ok) fail(`git ${args.join(' ')} failed: ${(result.stderr || result.stdout).trim()}`);
  return result.stdout;
}

export function readText(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}

export function readJson(file, fallback = null) {
  const text = readText(file);
  if (text === null) return fallback;
  try {
    return JSON.parse(text);
  } catch {
    fail(`${file} is not valid JSON`);
  }
}

// A reader such as the HUD must never see a half-written file.
export function writeAtomic(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, text);
  fs.renameSync(temporary, file);
}

export function writeJson(file, value) {
  writeAtomic(file, `${JSON.stringify(value, null, 2)}\n`);
}

export function posix(file) {
  return file.split(path.sep).join('/');
}

export function tail(text, count) {
  const lines = text.replace(/\s+$/, '').split('\n');
  return lines.length <= count ? lines : [`… ${lines.length - count} earlier lines omitted`, ...lines.slice(-count)];
}

export function capLines(lines, count, more) {
  return lines.length <= count ? lines : [...lines.slice(0, count), more(lines.length - count)];
}

export function backticked(text) {
  return [...text.matchAll(/`([^`]+)`/g)].map(match => match[1].trim()).filter(Boolean);
}

// `dir/` matches everything below it; `*` stays inside one path segment and
// `**` crosses segments.
export function matchesPath(pattern, file) {
  let wanted = pattern.replace(/^\.\//, '');
  if (wanted.endsWith('/')) wanted += '**';
  if (!wanted.includes('*')) return file === wanted || file.startsWith(`${wanted}/`);
  const source = wanted.split(/(\*\*\/|\*\*|\*)/).map(part => {
    if (part === '**/') return '(?:.*/)?';
    if (part === '**') return '.*';
    if (part === '*') return '[^/]*';
    return part.replace(/[.+?^${}()|[\]\\]/g, '\\$&');
  }).join('');
  return new RegExp(`^${source}$`).test(file);
}

export function matchesAny(patterns, file) {
  return patterns.some(pattern => matchesPath(pattern, file));
}

export function shortSha(sha) {
  return sha ? sha.slice(0, 7) : '';
}
