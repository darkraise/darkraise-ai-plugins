import { nextTask, taskStates } from '../plan.mjs';
import { appendEvent, loadState, planState, updateState, taskRecord } from '../state.mjs';
import { activePlan, refreshHud, taskBrief } from '../status.mjs';
import { fail } from '../util.mjs';

export function requireActive(ctx, state) {
  const active = activePlan(ctx, state);
  if (!active) fail('no plan is active on this branch; write one with /dflow:plan or select one with `dflow plan use <file>`');
  return active;
}

export async function run(ctx, argv, { out }) {
  const state = loadState(ctx.paths);
  const active = requireActive(ctx, state);
  if (!active.plan.fields.approved) fail(`${active.rel} is not approved; run \`dflow plan approve\` once the owner has approved it`);
  const tasks = taskStates(active.plan, planState(state, active.slug));
  const task = nextTask(tasks);
  if (!task) {
    const left = tasks.filter(candidate => !candidate.done);
    if (!left.length) out(`Every task of ${active.rel} is done. Next: /dflow:review`);
    else out(`No task is ready: ${left.map(candidate => `Task ${candidate.number} ${candidate.state === 'blocked' ? `blocked (${candidate.blockedReason})` : `waits on ${candidate.after.join(', ')}`}`).join('; ')}`);
    return left.length ? 1 : 0;
  }
  updateState(ctx.paths, fresh => {
    const record = taskRecord(fresh, active.slug, task.number);
    if (record.state !== 'wip') {
      record.state = 'wip';
      record.startedAt = new Date().toISOString();
      appendEvent(ctx, { plan: active.slug, event: 'wip', task: task.number });
    }
    fresh.plan = active.rel;
  });
  for (const line of taskBrief(ctx, active, task)) out(line);
  out('');
  out(`When the task's files are staged: dflow done ${task.number} -m "<type>(<scope>): <subject>"`);
  refreshHud(ctx);
  return 0;
}
