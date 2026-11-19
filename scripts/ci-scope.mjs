#!/usr/bin/env node
import { appendFileSync } from 'node:fs';
import { execFileSync, spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const RUN_TITLES = { full: 'Validate marketplace (full)', slice: 'Validate marketplace (slice)' };

const WINDOWS_SHARDS = Array.from({ length: 16 }, (_, i) => i + 1);
const RELEASE_SUBJECT = /^chore\(([^)\s]+)\): release \S+$/;
const USAGE = 'usage: ci-scope.mjs plan';

const oneLine = text => String(text).replace(/\s+/g, ' ').trim();

function git(...args) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

function lastFullRun(repository) {
  const args = ['run', 'list', '--repo', repository, '--workflow', 'validate.yml', '--branch', 'main', '--status', 'success', '--limit', '50', '--json', 'databaseId,displayTitle,headSha'];
  const [command, argv] = process.env.CI_SCOPE_GH ? [process.execPath, [process.env.CI_SCOPE_GH, ...args]] : ['gh', args];
  const result = spawnSync(command, argv, { encoding: 'utf8', timeout: 30_000 });
  if (result.error) return { error: oneLine(result.error.message) };
  if (result.status !== 0) return { error: oneLine(result.stderr || `gh exited ${result.status}`) };
  let runs;
  try {
    runs = JSON.parse(result.stdout);
  } catch (error) {
    return { error: `unreadable gh output: ${oneLine(error.message)}` };
  }
  return { run: Array.isArray(runs) ? runs.find(run => String(run.displayTitle ?? '').endsWith(' (full)')) : undefined };
}

function onlyReleaseCommits(base, sha) {
  try {
    const subjects = git('log', '--format=%s', `${base}..${sha}`).split('\n').filter(Boolean);
    if (subjects.length === 0) return false;
    const names = new Set();
    for (const subject of subjects) {
      const match = RELEASE_SUBJECT.exec(subject);
      if (!match) return false;
      names.add(match[1]);
    }
    const allowed = new Set([...names].flatMap(name => [`plugins/${name}/.claude-plugin/plugin.json`, `plugins/${name}/.codex-plugin/plugin.json`, `plugins/${name}/scripts/VERSION`]));
    return git('diff', '--name-only', base, sha).split('\n').filter(Boolean).every(file => allowed.has(file));
  } catch {
    return false;
  }
}

function decide({ EVENT: event, SCOPE_INPUT: scopeInput = '', SHA: sha = '', REPOSITORY: repository = '' }) {
  const full = event === 'schedule' || (event === 'workflow_dispatch' && scopeInput !== 'slice');
  if (!full) return { scope: 'slice', run: true, why: `${event} runs the Windows portability slice` };
  if (event !== 'schedule') return { scope: 'full', run: true, why: `${event} asked for the full run` };
  const { run, error } = lastFullRun(repository);
  if (error) return { scope: 'full', run: true, why: `the last full run could not be looked up (${error}), so this run proceeds` };
  if (!run) return { scope: 'full', run: true, why: 'no earlier successful full run, so this run proceeds' };
  if (run.headSha === sha) return { scope: 'full', run: false, why: `full run ${run.databaseId} already validated ${sha}, so this run is skipped` };
  if (onlyReleaseCommits(run.headSha, sha)) return { scope: 'full', run: false, why: `only release commits follow ${run.headSha}, validated by full run ${run.databaseId}, so this run is skipped` };
  return { scope: 'full', run: true, why: `${sha} has changes since ${run.headSha}, validated by full run ${run.databaseId}, so this run proceeds` };
}

function plan(env) {
  if (!env.EVENT || !env.GITHUB_OUTPUT) {
    console.error('ci-scope plan: EVENT and GITHUB_OUTPUT must be set');
    return 2;
  }
  const decision = decide(env);
  const windows = decision.scope === 'full' ? WINDOWS_SHARDS : ['slice'];
  appendFileSync(env.GITHUB_OUTPUT, `scope=${decision.scope}\nrun=${decision.run}\nwindows=${JSON.stringify(windows)}\n`);
  console.log(`::notice::scope ${decision.scope}, run ${decision.run}: ${decision.why}`);
  return 0;
}

function main(argv, env) {
  if (argv[0] === 'plan') return plan(env);
  console.error(USAGE);
  return 2;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2), process.env);
}
