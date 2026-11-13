import fs from 'node:fs';
import { nextTask, taskStates } from '../plan.mjs';
import { loadState, planState, saveState } from '../state.mjs';
import { activePlan, briefLines, buildModel, refreshHud, taskBrief } from '../status.mjs';
import { checkpoint, flush, pull } from './sync.mjs';

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
  state.transcript = event.transcript_path;
  if (session) {
    const others = Object.entries(state.transcripts ?? {}).filter(([key]) => key !== session);
    state.transcripts = Object.fromEntries([...others, [session, event.transcript_path]].slice(-20));
  }
  saveState(ctx.paths, state);
}

function currentTask(ctx, state, active) {
  return nextTask(taskStates(active.plan, planState(state, active.slug)));
}

async function sessionStart(ctx, event, out) {
  const state = loadState(ctx.paths);
  remember(ctx, state, event);
  await pull(ctx, { quiet: true });
  const active = activePlan(ctx, state);
  if (!active) return;
  for (const line of briefLines(buildModel(ctx))) out(line);
  if (event.source !== 'compact') return;
  const task = currentTask(ctx, state, active);
  if (!task) return;
  out('');
  out('The conversation was compacted. The task in progress, from the plan:');
  for (const line of taskBrief(ctx, active, task)) out(line);
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

async function stop(ctx, event) {
  const state = loadState(ctx.paths);
  remember(ctx, state, event);
  await checkpoint(ctx);
  await flush(ctx, { quiet: true });
  refreshHud(ctx);
}

// A hook must never break the session: every failure ends in exit 0.
export async function run(ctx, argv, { out }) {
  try {
    if (!fs.existsSync(ctx.paths.docs)) return 0;
    const event = input();
    if (argv[0] === 'session-start') await sessionStart(ctx, event, out);
    else if (argv[0] === 'pre-compact') preCompact(ctx, event, out);
    else if (argv[0] === 'stop') await stop(ctx, event);
  } catch {
    // Deliberately silent.
  }
  return 0;
}
