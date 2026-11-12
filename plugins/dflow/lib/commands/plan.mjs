import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { addRow, emptyBoard, parseBoard, rewriteRow } from '../board.mjs';
import { lintPlan, setField, template } from '../plan.mjs';
import { currentBranch, relative } from '../repo.mjs';
import { appendEvent, loadState, saveState } from '../state.mjs';
import { activePlan, loadPlan, refreshHud } from '../status.mjs';
import { fail, git, mustGit, readText, today } from '../util.mjs';

function resolvePlan(ctx, name) {
  if (!name) {
    const active = activePlan(ctx);
    if (!active) fail('no plan is active on this branch; name the plan file');
    return active;
  }
  const candidates = [path.resolve(ctx.cwd, name), path.join(ctx.paths.plans, name), path.join(ctx.paths.plans, `${name}.md`)];
  const file = candidates.find(candidate => fs.existsSync(candidate) && fs.statSync(candidate).isFile());
  if (!file) fail(`no plan at ${name}`);
  return loadPlan(ctx, file);
}

export function linkBoardRow(ctx, { number, item, planRel, acceptance }) {
  let text = readText(ctx.paths.board) ?? emptyBoard(`${path.basename(ctx.root)} board`);
  if (number !== undefined) {
    const row = parseBoard(text).rows.find(candidate => candidate.number === number);
    if (!row) fail(`board row ${number} does not exist in ${relative(ctx.root, ctx.paths.board)}`);
    const changes = { assigned: planRel };
    if (row.state === 'open') changes.state = 'planned';
    text = rewriteRow(text, number, changes);
  } else {
    ({ text, number } = addRow(text, { item, assigned: planRel, acceptance: acceptance ?? 'Every acceptance line of the plan passes', state: 'planned', note: '-' }));
  }
  fs.mkdirSync(path.dirname(ctx.paths.board), { recursive: true });
  fs.writeFileSync(ctx.paths.board, text);
  return number;
}

function create(ctx, argv, out) {
  const { values, positionals } = parseArgs({
    args: argv, allowPositionals: true,
    options: { title: { type: 'string' }, board: { type: 'string' }, branch: { type: 'string' }, acceptance: { type: 'string' } },
  });
  const slug = positionals[0];
  if (!slug || !/^[a-z0-9][a-z0-9-]*$/.test(slug)) fail('usage: dflow plan new <slug> --title "<title>" [--board <row>]; the slug is lowercase letters, digits and dashes');
  if (!values.title) fail('--title is required');
  if (values.board !== undefined && !/^[0-9]+$/.test(values.board)) fail('--board takes a row number');
  const file = path.join(ctx.paths.plans, `${today(ctx.env)}-${slug}.md`);
  if (fs.existsSync(file)) fail(`${relative(ctx.root, file)} already exists`);
  const planRel = relative(ctx.root, file);
  const number = linkBoardRow(ctx, { number: values.board === undefined ? undefined : Number(values.board), item: values.title, planRel, acceptance: values.acceptance });
  fs.mkdirSync(ctx.paths.plans, { recursive: true });
  fs.writeFileSync(file, template({ title: values.title, branch: values.branch ?? currentBranch(ctx.root) ?? '…', board: number }));
  const state = loadState(ctx.paths);
  state.plan = planRel;
  saveState(ctx.paths, state);
  appendEvent(ctx, { plan: path.basename(file, '.md'), event: 'planned' });
  out(`Created ${planRel}, linked to board row ${number}. Fill it in, then run \`dflow plan check\`.`);
  refreshHud(ctx);
  return 0;
}

function check(ctx, argv, out) {
  const entry = resolvePlan(ctx, argv[0]);
  const { errors, warnings } = lintPlan(entry.plan);
  for (const warning of warnings) out(`warning: ${warning}`);
  if (!errors.length) {
    out(`${entry.rel}: ${entry.plan.tasks.length} tasks, ${entry.plan.acceptance.length} acceptance lines; no problems`);
    return 0;
  }
  out(`${entry.rel}: ${errors.length} problem(s)`);
  for (const error of errors) out(`- ${error}`);
  return 1;
}

function approve(ctx, argv, out) {
  const entry = resolvePlan(ctx, argv[0]);
  const { errors } = lintPlan(entry.plan);
  if (errors.length) fail(`${entry.rel} does not lint (${errors.length} problem(s)); run \`dflow plan check\``);
  if (entry.plan.fields.approved) fail(`${entry.rel} was approved on ${entry.plan.fields.approved}`);
  fs.writeFileSync(entry.file, setField(entry.text, 'Approved', today(ctx.env)));
  const committed = [entry.rel];
  const row = Number(entry.plan.fields.board);
  if (Number.isInteger(row) && fs.existsSync(ctx.paths.board)) {
    linkBoardRow(ctx, { number: row, planRel: entry.rel });
    committed.push(relative(ctx.root, ctx.paths.board));
  }
  mustGit(ctx.root, ['add', '--', ...committed]);
  const commit = git(ctx.root, ['commit', '-q', '-m', `docs(dflow): approve plan ${entry.slug}`.slice(0, 72), '--', ...committed]);
  if (!commit.ok) fail(`the approval commit failed: ${(commit.stderr || commit.stdout).trim()}`);
  const state = loadState(ctx.paths);
  state.plan = entry.rel;
  saveState(ctx.paths, state);
  appendEvent(ctx, { plan: entry.slug, event: 'approved' });
  out(`Approved ${entry.rel} and committed it. Next: /dflow:build`);
  refreshHud(ctx);
  return 0;
}

function use(ctx, argv, out) {
  const entry = resolvePlan(ctx, argv[0] ?? fail('usage: dflow plan use <file>'));
  const state = loadState(ctx.paths);
  state.plan = entry.rel;
  saveState(ctx.paths, state);
  out(`Active plan: ${entry.rel}`);
  refreshHud(ctx);
  return 0;
}

export async function run(ctx, argv, { out }) {
  const [action, ...rest] = argv;
  if (action === 'new') return create(ctx, rest, out);
  if (action === 'check') return check(ctx, rest, out);
  if (action === 'approve') return approve(ctx, rest, out);
  if (action === 'use') return use(ctx, rest, out);
  fail('usage: dflow plan new|check|approve|use');
}
