import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { classify } from './claude.mjs';
import { planAt } from './cases.mjs';
import { changedFiles, overlayTests, runTests } from './grade.mjs';
import { commitMessages, filesBlock, taskText } from './plan.mjs';
import { PIPELINE_COLUMNS, PIPELINE_RESULTS, appendTsv, readTsv } from './results.mjs';
import { snapshot } from './snapshot.mjs';
import { DATA, PLUGIN, WORK, git, run as launch, sh } from './sh.mjs';

const CASE_SECONDS = 3600;
const BUDGET_USD = '10';
const DISPATCH_TOOLS = new Set(['Agent', 'Task']);
// The only host variables the child sees: the executable search path, locale,
// terminal, user and temp names, the Windows system variables a process needs
// to start, and the credentials for the API. The child runs with permissions
// bypassed, so anything else (cloud and registry tokens, SSH_AUTH_SOCK, GH_*)
// stays out. HOME, XDG_*, CLAUDE_CONFIG_DIR, TMPDIR, TMP and TEMP are set by isolatedEnv.
const HOST_ENV = /^(PATH|LANG|LANGUAGE|LC_[A-Z_]+|TERM|TZ|SHELL|USER|LOGNAME|TMP|TEMP|SYSTEMROOT|COMSPEC|PATHEXT|WINDIR)$/i;
const CREDENTIALS = /^(ANTHROPIC_|CLAUDE_CODE_OAUTH_TOKEN$)/;

// armPlugin REF ROOT — the dforge plugin directory of REF's tree under ROOT/arms,
// materialised once. No git worktree is created.
export function armPlugin(ref, root) {
  const sha = git(['rev-parse', ref]).trim();
  const tree = join(root, 'arms', sha.slice(0, 7));
  const plugin = join(tree, 'plugins/dforge');
  if (!existsSync(plugin)) snapshot(sha, tree);
  return plugin;
}

// isolatedEnv DIR — the child's environment: the allowlisted host variables,
// and its own HOME, XDG, Claude config and temp directories under DIR.
function isolatedEnv(dir) {
  const kept = Object.entries(process.env).filter(([key]) => CREDENTIALS.test(key) || HOST_ENV.test(key));
  const env = {
    ...Object.fromEntries(kept),
    HOME: join(dir, 'home'),
    XDG_CONFIG_HOME: join(dir, 'xdg/config'),
    XDG_CACHE_HOME: join(dir, 'xdg/cache'),
    XDG_DATA_HOME: join(dir, 'xdg/data'),
    XDG_STATE_HOME: join(dir, 'xdg/state'),
    CLAUDE_CONFIG_DIR: join(dir, 'claude'),
    TMPDIR: join(dir, 'tmp'),
    TMP: join(dir, 'tmp'),
    TEMP: join(dir, 'tmp'),
    CLAUDE_CODE_DISABLE_CLAUDE_MDS: '1',
    IS_SANDBOX: '1',
  };
  for (const key of ['HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'CLAUDE_CONFIG_DIR', 'TMPDIR']) mkdirSync(env[key], { recursive: true });
  return env;
}

// gradingFor C — what the hidden-test grader needs for a manifest row: the
// paths the task may touch, its test files, and the first commit after the
// base that carries the task's commit message.
function gradingFor(c) {
  const tmp = mkdtempSync(join(tmpdir(), 'tier-eval-pipeline-'));
  try {
    const plan = planAt(c.base, c.plan, tmp);
    if (plan === null) throw new Error(`${c.plan} is missing at ${c.base}`);
    const text = taskText(plan, c.task);
    if (text === null) throw new Error(`${c.plan} has no Task ${c.task} at ${c.base}`);
    const { allowed, tests } = filesBlock(text);
    if (tests.length === 0) throw new Error(`Task ${c.task} names no test file`);
    const messages = commitMessages(text);
    const result = git(['log', '--reverse', '--format=%H%x09%s', `${c.base}..HEAD`]).split('\n').filter(Boolean)
      .map(line => line.split('\t')).find(([, subject]) => messages.includes(subject))?.[0];
    if (!result) throw new Error(`no commit after ${c.base} carries the message of Task ${c.task}`);
    // Checked before the launch: found only after it, a missing test would
    // re-run the paid session on every invocation.
    for (const test of tests) if (sh('git', ['cat-file', '-e', `${result}:${test}`]).code !== 0) throw new Error(`${test} is missing at ${result}`);
    return { allowed, tests, result };
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

function controllerPrompt(c) {
  return [
    `Use the dforge:subagent-driven-development skill to carry out Task ${c.task} of ${c.plan}, and only that task.`,
    'Run it through the controller loop: the implementer, the suite beside the review, the task review and at most two fix rounds.',
    'Every earlier task of the plan is already in this repository. Nobody can answer a question: where the skill would ask, take the smallest reading and record it in the ledger.',
    'This directory is already the isolated workspace, a git checkout on its own branch: create no worktree, and work on this branch without asking. Log "Ruling: pre-flight — skipped (replay) — none" and go on without the pre-flight ruling. No final review, no finishing, no handoff.',
    `Wait as the skill says: when only waiting remains, end your turn; the completion notifications resume you. Stop when the ledger holds a "Task ${c.task}: complete" line or the task is parked.`,
    'Do not push, merge, open a pull request or change anything outside this repository.',
  ].join('\n');
}

function ledgerLines(work, plan, env) {
  const r = sh('bash', [resolve(PLUGIN, 'scripts/sdd-workspace'), plan], { cwd: work, env });
  const dir = r.out.trim();
  // A failed call is a fault of the harness: read as an empty ledger it would
  // record a product FAIL that settles the cell and is never rerun.
  if (r.code !== 0 || !dir) throw new Error(`sdd-workspace exited ${r.code}: ${(r.err || r.out).trim().slice(0, 120)}`);
  const file = join(dir, 'progress.md');
  return existsSync(file) ? readFileSync(file, 'utf8').replace(/\r/g, '').split('\n') : [];
}

// dispatches CONFIG — the subagent dispatches the controller made, counted in
// its own transcript; subagent transcripts live in a subagents/ directory and
// are left out.
function dispatches(config) {
  let count = 0;
  const walk = dir => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) { if (entry.name !== 'subagents') walk(path); continue; }
      if (!entry.name.endsWith('.jsonl')) continue;
      for (const line of readFileSync(path, 'utf8').split('\n').filter(Boolean)) {
        let message;
        try { message = JSON.parse(line).message; } catch { continue; }
        if (Array.isArray(message?.content)) count += message.content.filter(part => part.type === 'tool_use' && DISPATCH_TOOLS.has(part.name)).length;
      }
    }
  };
  if (existsSync(join(config, 'projects'))) walk(join(config, 'projects'));
  return count;
}

// runPipelineCase { c, arm, ref, run, root } — replays manifest row C once
// under the plugin of REF: an isolated clone at C's base commit, one headless
// controller session, then the hidden tests of the commit that finished the
// task. ARM labels the row, RUN is the run number, ROOT the eval's own
// directory: nothing the run touches lies outside it.
export async function runPipelineCase({ c, arm, ref, run, root }) {
  const failed = (detail, extra = {}) => ({ outcome: 'ERROR', costUsd: 0, seconds: 0, dispatches: 0, fixRounds: 0, detail, ...extra });
  let inv = null;
  try {
    const plugin = armPlugin(ref, root);
    const grading = gradingFor(c);
    const dir = join(root, 'runs', c.case, `${arm.replace('@', '-at-')}-run${run}`);
    rmSync(dir, { recursive: true, force: true });
    const work = join(dir, 'work');
    const initial = snapshot(c.base, work);
    const env = isolatedEnv(dir);
    const key = process.env.ANTHROPIC_API_KEY;
    writeFileSync(join(env.CLAUDE_CONFIG_DIR, '.claude.json'), JSON.stringify({
      hasCompletedOnboarding: true,
      customApiKeyResponses: { approved: key ? [key.slice(-20)] : [], rejected: [] },
      projects: { [work]: { hasTrustDialogAccepted: true } },
    }));
    // The login is the only thing taken from the session's config directory;
    // its settings, plugins and history stay out of the run.
    const credentials = join(process.env.CLAUDE_CONFIG_DIR ?? join(homedir(), '.claude'), '.credentials.json');
    if (existsSync(credentials)) copyFileSync(credentials, join(env.CLAUDE_CONFIG_DIR, '.credentials.json'));
    const prompt = controllerPrompt(c);
    writeFileSync(join(dir, 'prompt.txt'), prompt);
    const args = ['-p', '--model', 'sonnet', '--effort', 'high', '--plugin-dir', plugin, '--setting-sources', 'project',
      '--dangerously-skip-permissions', '--output-format', 'json', '--max-budget-usd', BUDGET_USD];
    const started = Date.now();
    const r = await launch(process.env.TIER_EVAL_CLAUDE ?? 'claude', args, { cwd: work, seconds: CASE_SECONDS, input: prompt, env });
    writeFileSync(join(dir, 'output.json'), r.out);
    writeFileSync(join(dir, 'stderr.txt'), r.err);
    inv = classify(r, (Date.now() - started) / 1000);
    if (inv.kind === 'limit' || inv.kind === 'error') return failed(`${inv.kind}: ${inv.text.slice(0, 200)}`, { costUsd: inv.cost, seconds: inv.seconds });

    const ledger = ledgerLines(work, c.plan, env);
    const complete = ledger.some(line => line.startsWith(`Task ${c.task}: complete`));
    const fixRounds = ledger.filter(line => line.startsWith(`Task ${c.task}: fix round `)).length;
    const outside = changedFiles(work, initial).filter(p => !p.startsWith('.dforge/') && !grading.allowed.includes(p));
    if (!overlayTests(work, grading.result, grading.tests)) throw new Error(`a test file is missing at ${grading.result}`);
    const tested = await runTests(work, grading.tests);
    const detail = [
      inv.kind === 'ok' ? '' : `cut=${inv.kind}`,
      complete ? '' : 'no-complete-line',
      tested.pass ? '' : `failed=${tested.failed}`,
      outside.length > 0 ? `outside=${outside.join(',')}` : '',
    ].filter(Boolean).join(' ');
    const passed = inv.kind === 'ok' && complete && tested.pass && outside.length === 0;
    return { outcome: passed ? 'PASS' : 'FAIL', costUsd: inv.cost, seconds: inv.seconds, dispatches: dispatches(env.CLAUDE_CONFIG_DIR), fixRounds, detail };
  } catch (error) {
    // A session that ran has spent money, so the spend cap must count it.
    return failed(`error: ${error.message.slice(0, 200)}`, inv ? { costUsd: inv.cost, seconds: inv.seconds } : {});
  }
}

// runPipelineStage { rep, jobs, capUsd, deadline } — every (case, arm, run)
// cell of cases/pipeline.tsv with no settled row in results/pipeline.tsv, run
// `jobs` at a time. An arm is keyed `<label>@<ref7>`, so a baseline measured
// once at a ref serves every later comparison against that ref. A row
// settles its cell unless it is an ERROR; a rate limit stops the stage.
export async function runPipelineStage({ rep, jobs, capUsd, deadline }) {
  const armsFile = resolve(DATA, 'arms.json');
  const refs = JSON.parse(readFileSync(armsFile, 'utf8')).pipeline;
  if (!refs?.baseline || !refs?.candidate) throw new Error(`${armsFile} has no "pipeline" entry with a baseline and a candidate ref`);
  const manifest = resolve(DATA, 'cases/pipeline.tsv');
  if (!existsSync(manifest)) throw new Error(`no pipeline manifest at ${manifest}`);
  const root = join(WORK, 'pipeline', `rep${rep}`);
  const arms = ['baseline', 'candidate'].map(label => {
    const sha = git(['rev-parse', refs[label]]).trim();
    return { ref: sha, key: `${label}@${sha.slice(0, 7)}` };
  });
  const cells = readTsv(manifest).flatMap(c => arms.flatMap(arm => [1, 2].map(run => ({ c, arm, run }))));
  const rows = () => readTsv(PIPELINE_RESULTS).filter(r => r.rep === String(rep));
  const pending = () => cells.filter(({ c, arm, run }) => !rows().some(r => r.case === c.case && r.arm === arm.key && r.run === String(run) && r.outcome !== 'ERROR'));
  const spent = () => rows().reduce((sum, r) => sum + Number(r.costUsd), 0);
  const queue = pending();
  for (const arm of arms) if (queue.some(cell => cell.arm === arm)) armPlugin(arm.ref, root);
  let stop = null, ran = 0;
  await Promise.all(Array.from({ length: jobs }, async () => {
    while (stop === null && queue.length > 0) {
      if (spent() >= capUsd) { stop = 'cap'; break; }
      if (Date.now() >= deadline) { stop = 'time'; break; }
      const { c, arm, run } = queue.shift();
      const result = await runPipelineCase({ c, arm: arm.key, ref: arm.ref, run, root });
      const row = { rep, case: c.case, arm: arm.key, run, ...result };
      appendTsv(PIPELINE_RESULTS, PIPELINE_COLUMNS, row);
      ran += 1;
      console.log(PIPELINE_COLUMNS.map(k => row[k] ?? '').join('\t'));
      if (row.outcome === 'ERROR' && row.detail.startsWith('limit')) stop = 'limit';
    }
  }));
  return { ran, remaining: pending().length, spent: spent(), stop };
}
