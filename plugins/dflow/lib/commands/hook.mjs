import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { nextTask, taskStates } from '../plan.mjs';
import { loadState, planState, updateState } from '../state.mjs';
import { activePlan, briefLines, buildModel, refreshHud } from '../status.mjs';

function input() {
  if (process.stdin.isTTY) return {};
  try {
    return JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch {
    return {};
  }
}

// The transcript the context size is read from without the mod, kept per
// session so that `dflow done` in one session never reads another's. The
// last 20 sessions are kept.
function remember(ctx, state, event) {
  if (typeof event.transcript_path !== 'string') return;
  const session = typeof event.session_id === 'string' ? event.session_id : null;
  if (state.transcript === event.transcript_path && (!session || state.transcripts?.[session] === event.transcript_path)) return;
  const apply = target => {
    target.transcript = event.transcript_path;
    if (session) {
      const others = Object.entries(target.transcripts ?? {}).filter(([key]) => key !== session);
      target.transcripts = Object.fromEntries([...others, [session, event.transcript_path]].slice(-20));
    }
  };
  apply(state);
  updateState(ctx.paths, apply);
}

function currentTask(ctx, state, active) {
  return nextTask(taskStates(active.plan, planState(state, active.slug)));
}

function sessionStart(ctx, event, out) {
  const state = loadState(ctx.paths);
  remember(ctx, state, event);
  const active = activePlan(ctx, state);
  if (!active) return;
  // After a compaction too: `Next:` names /dflow:build, whose `dflow next`
  // prints the task's brief once.
  for (const line of briefLines(buildModel(ctx))) out(line);
}

function preCompact(ctx, event, out) {
  const state = loadState(ctx.paths);
  remember(ctx, state, event);
  const active = activePlan(ctx, state);
  if (!active) return;
  const task = currentTask(ctx, state, active);
  out(`A dflow build is in progress. The plan file ${active.rel} and the git history hold all task state, so the summary keeps only:`);
  out(`- the plan path and that ${task ? `Task ${task.number} is in progress` : 'every task is done'};`);
  out('- inside the task in progress: what is finished, what is left, and why any uncommitted change was made;');
  out('- decisions and gotchas not yet recorded with `dflow log`;');
  out('- instructions the owner gave in this session.');
  out('Leave out tool output, file contents, finished tasks and the plan text itself.');
}

function stop(ctx, event) {
  const state = loadState(ctx.paths);
  remember(ctx, state, event);
  refreshHud(ctx);
}

// Resolved from this module, never from CLAUDE_PLUGIN_ROOT, so the guard that
// runs is the one shipped beside this file.
const GUARD = fileURLToPath(new URL('../../scripts/workflow-guard.mjs', import.meta.url));

// On a conflict the guard's JSON is the session start's whole output.
function guardConflict(ctx, event, out) {
  const ran = spawnSync(process.execPath, [GUARD, '--host', 'claude', '--self', 'dflow', '--hook', 'session-start'], {
    input: JSON.stringify(event),
    env: ctx.env,
    encoding: 'utf8',
    timeout: 5000,
  });
  if (ran.stderr) process.stderr.write(ran.stderr);
  if (ran.error || ran.status === null) process.stderr.write(`workflow-guard: the check did not finish (${ran.error?.message ?? ran.signal}); dflow runs as usual\n`);
  if (ran.status !== 3) return false;
  out(ran.stdout.trimEnd());
  return true;
}

function standsDown(ctx, event) {
  const data = ctx.env.CLAUDE_PLUGIN_DATA;
  const session = typeof event.session_id === 'string' ? event.session_id : '';
  return Boolean(data && session) && fs.existsSync(path.join(data, 'workflow-guard', session.replace(/[^A-Za-z0-9]/g, '-')));
}

// A hook must never break the session: every failure ends in exit 0.
export async function run(ctx, argv, { out }) {
  try {
    const event = input();
    if (argv[0] === 'session-start' && guardConflict(ctx, event, out)) return 0;
    if (argv[0] !== 'session-start' && standsDown(ctx, event)) return 0;
    if (!fs.existsSync(ctx.paths.docs)) return 0;
    if (argv[0] === 'session-start') sessionStart(ctx, event, out);
    else if (argv[0] === 'pre-compact') preCompact(ctx, event, out);
    else if (argv[0] === 'stop') stop(ctx, event);
  } catch {
    // Deliberately silent.
  }
  return 0;
}
