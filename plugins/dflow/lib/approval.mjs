import { parsePlan } from './plan.mjs';
import { git, gitOut, squash } from './util.mjs';

// The plan as the owner approved it: its text at the commit that first
// carried the Approved line.
export function approvedPlan(ctx, active) {
  const commits = gitOut(ctx.root, ['log', '--format=%H', '-S**Approved:**', '--', active.rel]);
  const first = commits?.split('\n').filter(Boolean).at(-1);
  if (!first) return null;
  const shown = git(ctx.root, ['show', `${first}:${active.rel}`]);
  return shown.ok ? { commit: first, plan: parsePlan(shown.stdout) } : null;
}

// The log stores its text with runs of whitespace collapsed, so commands are
// compared the same way, or a command holding two spaces could never match
// the line that explains it.
function sameCommands(a, b) {
  return a.length === b.length && a.every((command, index) => squash(command) === squash(b[index]));
}

function names(text, command) {
  return squash(text).includes(`\`${squash(command)}\``);
}

// Tasks whose verify commands differ from the approved plan, with whether a
// logged `V:` line explains the change.
export function amendedVerify(ctx, active, approved = approvedPlan(ctx, active)) {
  if (!approved) return [];
  const before = new Map(approved.plan.tasks.map(task => [task.number, task.verify]));
  return active.plan.tasks.flatMap(task => {
    const was = before.get(task.number);
    const notes = active.plan.log.filter(entry => entry.task === task.number);
    // A task the approved plan did not have is explained by a logged
    // amendment; a changed command only by a V line that names that command,
    // so one `dflow amend` does not excuse a later hand edit.
    if (!was) return [{ task: task.number, was: [], now: task.verify, added: true, logged: notes.some(entry => entry.kind === 'A' || entry.kind === 'V') }];
    if (sameCommands(was, task.verify)) return [];
    const logged = notes.some(entry => entry.kind === 'V' && task.verify.every(command => names(entry.text, command)));
    return [{ task: task.number, was, now: task.verify, logged }];
  });
}

// A task's Files set what `dflow done` accepts, so a list changed after
// approval needs a logged amendment of that task.
export function amendedFiles(ctx, active, approved = approvedPlan(ctx, active)) {
  if (!approved) return [];
  const key = files => [...files].sort().join('\n');
  const before = new Map(approved.plan.tasks.map(task => [task.number, task.files]));
  return active.plan.tasks.flatMap(task => {
    const was = before.get(task.number);
    if (!was || key(was) === key(task.files)) return [];
    const logged = active.plan.log.some(entry => entry.task === task.number && entry.kind === 'A');
    return [{ task: task.number, was, now: task.files, logged }];
  });
}

function describe(line) {
  if (!line) return null;
  return `${line.ui ? `UI ${line.visual ? 'visual ' : ''}` : ''}${squash(line.text)}`;
}

// Acceptance is the owner's. A line changed, added or dropped after approval
// is explained only by a plan-level A line that names its id and every
// command the line now runs, written once the owner has agreed.
export function amendedAcceptance(ctx, active, approved = approvedPlan(ctx, active)) {
  if (!approved) return [];
  const before = new Map(approved.plan.acceptance.map(line => [line.id, line]));
  const now = new Map(active.plan.acceptance.map(line => [line.id, line]));
  const notes = active.plan.log.filter(entry => entry.task === null && entry.kind === 'A');
  return [...new Set([...before.keys(), ...now.keys()])].flatMap(id => {
    const was = describe(before.get(id));
    const is = describe(now.get(id));
    if (was === is) return [];
    const named = new RegExp(`(^|[^A-Za-z0-9])${id}([^0-9]|$)`);
    const commands = now.get(id)?.commands ?? [];
    const logged = notes.some(entry => named.test(entry.text) && commands.every(command => names(entry.text, command)));
    return [{ id, was, now: is, logged }];
  });
}
