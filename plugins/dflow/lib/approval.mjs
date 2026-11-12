import { parsePlan } from './plan.mjs';
import { git, gitOut } from './util.mjs';

// The plan as the owner approved it: its text at the commit that first
// carried the Approved line.
export function approvedPlan(ctx, active) {
  const commits = gitOut(ctx.root, ['log', '--format=%H', '-S**Approved:**', '--', active.rel]);
  const first = commits?.split('\n').filter(Boolean).at(-1);
  if (!first) return null;
  const shown = git(ctx.root, ['show', `${first}:${active.rel}`]);
  return shown.ok ? { commit: first, plan: parsePlan(shown.stdout) } : null;
}

// Tasks whose verify commands differ from the approved plan, with whether a
// logged `V:` line explains the change.
export function amendedVerify(ctx, active) {
  const approved = approvedPlan(ctx, active);
  if (!approved) return [];
  const before = new Map(approved.plan.tasks.map(task => [task.number, task.verify]));
  return active.plan.tasks.flatMap(task => {
    const was = before.get(task.number);
    const notes = active.plan.log.filter(entry => entry.task === task.number);
    // A task the approved plan did not have is explained by a logged
    // amendment; a changed command only by a V line that names that command,
    // so one `dflow amend` does not excuse a later hand edit.
    if (!was) return [{ task: task.number, was: [], now: task.verify, added: true, logged: notes.some(entry => entry.kind === 'A' || entry.kind === 'V') }];
    if (JSON.stringify(was) === JSON.stringify(task.verify)) return [];
    const logged = notes.some(entry => entry.kind === 'V' && task.verify.every(command => entry.text.includes(`\`${command}\``)));
    return [{ task: task.number, was, now: task.verify, logged }];
  });
}
