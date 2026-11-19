import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { parseBoard } from '../board.mjs';
import { parsePlan, taskStates } from '../plan.mjs';
import { head, relative } from '../repo.mjs';
import { appendEvent, loadState, planState, updateState, taskRecord } from '../state.mjs';
import { refreshHud, taskBrief } from '../status.mjs';
import { fail, git, gitOut, mustGit, readText, shortSha } from '../util.mjs';
import { requireActive } from './next.mjs';

// The fixed part of a Files entry, up to its first wildcard, and whether a
// wildcard follows it.
function stem(pattern) {
  const clean = pattern.replace(/^\.\//, '');
  return { text: clean.split('*')[0].replace(/\/+$/, ''), wild: clean.includes('*') };
}

// Errs toward overlap: `src/limit*.mjs` can match `src/limit.test.mjs`, so
// with a wildcard on either side a shared prefix is enough. Two plain paths
// overlap when they are equal or one is a directory holding the other.
export function filesOverlap(left, right) {
  return left.some(a => right.some(b => {
    const [x, y] = [stem(a), stem(b)];
    if (x.wild || y.wild) return x.text.startsWith(y.text) || y.text.startsWith(x.text);
    return x.text === y.text || x.text.startsWith(`${y.text}/`) || y.text.startsWith(`${x.text}/`);
  }));
}

export function readyWave(tasks, workers) {
  const wave = [];
  for (const task of tasks) {
    if (task.run !== 'worker' || !task.ready || workers[task.number]) continue;
    if (wave.every(chosen => !filesOverlap(chosen.files, task.files))) wave.push(task);
  }
  return wave;
}

function wave(ctx, argv, out) {
  const { values } = parseArgs({ args: argv, options: { json: { type: 'boolean' } } });
  const state = loadState(ctx.paths);
  const active = requireActive(ctx, state);
  const tasks = taskStates(active.plan, planState(state, active.slug));
  const ready = readyWave(tasks, state.workers ?? {});
  if (values.json) {
    out(JSON.stringify(ready.map(task => ({ number: task.number, title: task.title, size: task.size, files: task.files }))));
    return 0;
  }
  if (ready.length < 2) {
    out(`No wave: ${ready.length} worker task(s) are ready with disjoint files, and a wave needs two or more.${ready.length ? ` Build Task ${ready[0].number} inline.` : ''}`);
    return 0;
  }
  out(`A wave of ${ready.length} tasks can run at the same time:`);
  for (const task of ready) out(`  Task ${task.number} (${task.size}): ${task.title} — ${task.files.join(', ')}`);
  out('For each: `dflow worktree add <N>`, then dispatch one dflow:worker per task in a single message with the line it prints.');
  return 0;
}

function workerPath(ctx, number) {
  return path.join(ctx.paths.stateDir, 'worktrees', `t${number}`);
}

const RULES = [
  'Rules for this task:',
  '- Work only inside the worktree above; every command runs there.',
  '- Write the tests the task lists first, see them fail for the expected reason, then implement.',
  '- Change only the files the task names. Never edit the plan or anything under docs/dflow/.',
  '- Solve the general case: no value hard-coded to satisfy a test, no special case for the test input.',
  '- An existing test is not yours to weaken. If one is wrong, stop and report it.',
  '- Run the task\'s verify command and see it pass, then commit in the worktree with a `<type>(<scope>): <subject>` message.',
  '- If you cannot finish, commit nothing and say exactly what stopped you.',
  'Reply with: the commit hash, the verify command\'s last line, and anything you did that the task did not say.',
];

function add(ctx, argv, out) {
  const number = Number(argv[0]);
  if (!Number.isInteger(number)) fail('usage: dflow worktree add <N>');
  const state = loadState(ctx.paths);
  const active = requireActive(ctx, state);
  const task = taskStates(active.plan, planState(state, active.slug)).find(candidate => candidate.number === number);
  if (!task) fail(`${active.rel} has no Task ${number}`);
  if (!task.ready) fail(`Task ${number} is not ready (${task.state})`);
  state.workers ??= {};
  if (state.workers[number]) fail(`Task ${number} already has a worktree at ${state.workers[number].path}`);
  const directory = workerPath(ctx, number);
  const branch = `dflow/${active.slug}-t${number}`;
  fs.mkdirSync(path.dirname(directory), { recursive: true });
  // From the current head, not the remote default branch, so the worker has
  // the plan's earlier commits.
  mustGit(ctx.root, ['worktree', 'add', '-q', '-b', branch, directory, 'HEAD']);
  const brief = `${directory}.brief.md`;
  fs.writeFileSync(brief, [`Worktree: ${directory}`, '', ...taskBrief(ctx, active, task), '', ...RULES, ''].join('\n'));
  const worker = { task: number, path: relative(ctx.root, directory), branch, base: head(ctx.root) };
  updateState(ctx.paths, fresh => {
    fresh.workers ??= {};
    fresh.workers[number] = worker;
    const record = taskRecord(fresh, active.slug, number);
    if (record.state !== 'wip') {
      record.state = 'wip';
      appendEvent(ctx, { plan: active.slug, event: 'wip', task: number });
    }
  });
  out(`Read ${brief} and do the task it describes.`);
  refreshHud(ctx);
  return 0;
}

function release(ctx, state, number) {
  const worker = state.workers[number];
  git(ctx.root, ['worktree', 'remove', '--force', path.join(ctx.root, worker.path)]);
  git(ctx.root, ['branch', '-q', '-D', worker.branch]);
  fs.rmSync(`${path.join(ctx.root, worker.path)}.brief.md`, { force: true });
  delete state.workers[number];
  updateState(ctx.paths, fresh => {
    delete fresh.workers?.[number];
  });
}

function merge(ctx, argv, out, { keep }) {
  const number = Number(argv[0]);
  const state = loadState(ctx.paths);
  const worker = state.workers?.[number];
  if (!worker) fail(`Task ${number} has no worktree`);
  if (!keep) {
    release(ctx, state, number);
    out(`Dropped Task ${number}'s worktree and branch without merging.`);
    refreshHud(ctx);
    return 0;
  }
  const commits = (gitOut(ctx.root, ['rev-list', '--reverse', `${worker.base}..${worker.branch}`]) ?? '').split('\n').filter(Boolean);
  if (!commits.length) fail(`the worker made no commit on ${worker.branch}; give it the failing output once, or \`dflow worktree drop ${number}\` and build the task inline`);
  if (mustGit(ctx.root, ['diff', '--cached', '--name-only']).trim()) fail('the index already holds staged changes; commit or unstage them before merging a worker');
  const picked = git(ctx.root, ['cherry-pick', '-n', ...commits]);
  if (!picked.ok) {
    // Back to exactly where the plan branch was: the index and tree first,
    // then the sequencer state a multi-commit pick leaves behind.
    git(ctx.root, ['reset', '-q', '--merge']);
    git(ctx.root, ['cherry-pick', '--quit']);
    fail(`Task ${number}'s commits do not apply onto the plan branch:\n${(picked.stderr || picked.stdout).trim()}\nThe worktree is kept at ${worker.path}; resolve by hand or drop it and build inline.`);
  }
  release(ctx, state, number);
  out(`Task ${number}'s ${commits.length} commit(s) (${commits.map(shortSha).join(', ')}) are staged on the plan branch. Now: dflow done ${number} -m "<type>(<scope>): <subject>"`);
  refreshHud(ctx);
  return 0;
}

function worktrees(ctx) {
  const listed = gitOut(ctx.root, ['worktree', 'list', '--porcelain']) ?? '';
  return listed.split('\n\n').map(block => ({
    root: /^worktree (.*)$/m.exec(block)?.[1],
    branch: /^branch refs\/heads\/(.*)$/m.exec(block)?.[1] ?? null,
  })).filter(entry => entry.root && entry.branch);
}

function plans(ctx, argv, out) {
  const { values } = parseArgs({ args: argv, options: { conflicts: { type: 'boolean' } } });
  const open = [];
  for (const tree of worktrees(ctx)) {
    const directory = path.join(tree.root, 'docs', 'dflow', 'plans');
    if (!fs.existsSync(directory)) continue;
    for (const name of fs.readdirSync(directory).filter(file => file.endsWith('.md')).sort()) {
      const plan = parsePlan(readText(path.join(directory, name)));
      if (plan.fields.shipped || plan.fields.branch !== tree.branch) continue;
      const left = plan.tasks.filter(task => !task.done);
      open.push({ name, branch: tree.branch, root: tree.root, done: plan.tasks.length - left.length, total: plan.tasks.length, files: left.flatMap(task => task.files) });
    }
  }
  if (!open.length) out('No open plan in any worktree of this repository.');
  for (const plan of open) out(`${plan.name} · ${plan.branch} · ${plan.done}/${plan.total} · ${plan.root}`);
  if (!values.conflicts) return 0;
  let conflicts = 0;
  open.forEach((left, index) => open.slice(index + 1).forEach(right => {
    if (!filesOverlap(left.files, right.files)) return;
    conflicts += 1;
    out(`CONFLICT: ${left.name} and ${right.name} both have unfinished tasks in overlapping files; build them one after the other.`);
  }));
  if (!conflicts && open.length > 1) out('No two open plans touch the same files.');
  return conflicts ? 1 : 0;
}

function session(ctx, argv, out) {
  const number = Number(argv[0]);
  const text = readText(ctx.paths.board);
  const row = text && parseBoard(text).rows.find(candidate => candidate.number === number);
  if (!row) fail('usage: dflow session <board row>; the row must exist on the board');
  const plan = /^docs\/dflow\/plans\//.test(row.assigned) && fs.existsSync(path.join(ctx.root, row.assigned));
  out('Start this in your own terminal; a background session keeps running after the terminal closes:');
  // Single quotes: a board item may hold `$(...)` or backticks, and the row
  // text can come from another person through the shared board.
  const quoted = text => `'${text.replaceAll("'", "'\\''")}'`;
  out(`  claude --bg ${quoted(plan ? `/dflow:build ${row.assigned}` : `/dflow:plan board row ${row.number}: ${row.item}`)}`);
  out('It works in a worktree of its own. A permission prompt makes it wait: attach with `claude attach` to answer.');
  out('Before starting a second plan, check `dflow plans --conflicts`.');
  return 0;
}

export async function run(ctx, argv, { out, name }) {
  if (name === 'wave') return wave(ctx, argv, out);
  if (name === 'plans') return plans(ctx, argv, out);
  if (name === 'session') return session(ctx, argv, out);
  const [action, ...rest] = argv;
  if (action === 'add') return add(ctx, rest, out);
  if (action === 'merge') return merge(ctx, rest, out, { keep: true });
  if (action === 'drop') return merge(ctx, rest, out, { keep: false });
  fail('usage: dflow worktree add|merge|drop <N>');
}
