import fs from 'node:fs';
import { appendLog, blockedTasks, nextTask, taskStates } from '../plan.mjs';
import { appendEvent, loadState, planState, updateState, taskRecord } from '../state.mjs';
import { loadPlan, refreshHud } from '../status.mjs';
import { fail, today } from '../util.mjs';
import { requireActive } from './next.mjs';

export async function run(ctx, argv, { out, name }) {
  const number = Number(argv[0]);
  const reason = argv.slice(1).join(' ').trim();
  if (!Number.isInteger(number) || !reason) fail(`usage: dflow ${name} <N> "<${name === 'block' ? 'reason' : 'what changed'}>"`);
  const state = loadState(ctx.paths);
  const active = requireActive(ctx, state);
  const task = active.plan.tasks.find(candidate => candidate.number === number);
  if (!task) fail(`${active.rel} has no Task ${number}`);
  const blocked = blockedTasks(active.plan).has(number);
  if (name === 'block') {
    if (task.done) fail(`Task ${number} is already done`);
    if (blocked) fail(`Task ${number} is already blocked`);
  } else if (!blocked) fail(`Task ${number} is not blocked`);

  fs.writeFileSync(active.file, appendLog(active.text, { date: today(ctx.env), task: number, kind: name === 'block' ? 'B' : 'U', message: reason }));
  updateState(ctx.paths, fresh => {
    const record = taskRecord(fresh, active.slug, number);
    delete record.state;
    if (name === 'unblock') record.attempts = 0;
  });
  appendEvent(ctx, { plan: active.slug, event: name === 'block' ? 'blocked' : 'unblocked', task: number, reason });

  const reloaded = loadPlan(ctx, active.file);
  const upcoming = nextTask(taskStates(reloaded.plan, planState(state, active.slug)));
  if (name === 'block') {
    out(`Task ${number} is blocked: ${reason}. The plan cannot ship while it is.`);
    out(upcoming ? `Continue with Task ${upcoming.number}: ${upcoming.title} (dflow next).` : 'No other task is ready. Report the blocker to the owner.');
  } else out(`Task ${number} is unblocked. Run \`dflow next\`.`);
  refreshHud(ctx);
  return 0;
}
