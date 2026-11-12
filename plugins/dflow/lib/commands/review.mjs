import path from 'node:path';
import { parseArgs } from 'node:util';
import { head, relative } from '../repo.mjs';
import { addFinding, buildPack, factLines, findingLine, quotePresent, updateFindings, writePack } from '../review.mjs';
import { runCommand } from '../run.mjs';
import { appendEvent, loadState, planState, saveState } from '../state.mjs';
import { loadFindings, refreshHud } from '../status.mjs';
import { fail, nowIso } from '../util.mjs';
import { requireActive } from './next.mjs';

function taskOption(value) {
  if (value === undefined) return undefined;
  if (!/^[0-9]+$/.test(value)) fail('--task takes a task number');
  return Number(value);
}

function pack(ctx, active, argv, out) {
  const { values } = parseArgs({ args: argv, options: { task: { type: 'string' }, json: { type: 'boolean' } } });
  const built = buildPack(ctx, active, taskOption(values.task));
  if (values.json) {
    out(JSON.stringify(built, null, 2));
    return 0;
  }
  const file = writePack(ctx, active, built);
  out(`Review tier ${built.tier}: ${built.files.length} files, ${built.lines} changed lines${built.task ? ` (Task ${built.task})` : ''}.`);
  for (const line of factLines(built)) out(`- ${line}`);
  out(`Pack: ${file}`);
  out(['Tier 0: check the diff against Acceptance yourself, then `dflow review record --tier 0`.',
    'Tier 1: dispatch one dflow:reviewer with the pack path, then `dflow review verify`.',
    'Tier 2: run the deep-review workflow with the pack path, then `dflow review verify`.'][built.tier]);
  return 0;
}

function add(ctx, active, argv, out) {
  const { values } = parseArgs({
    args: argv,
    options: {
      file: { type: 'string' }, line: { type: 'string' }, severity: { type: 'string' }, claim: { type: 'string' }, breaks: { type: 'string' },
      cmd: { type: 'string' }, quote: { type: 'string' }, task: { type: 'string' }, lens: { type: 'string' },
    },
  });
  const finding = addFinding(ctx, active.slug, {
    file: values.file, line: Number(values.line), severity: values.severity, claim: values.claim, breaks: values.breaks,
    command: values.cmd, quote: values.quote, task: taskOption(values.task), lens: values.lens,
  });
  out(`${finding.id} recorded (${finding.severity}, ${finding.evidence.kind} evidence)`);
  refreshHud(ctx);
  return 0;
}

function list(ctx, active, argv, out) {
  const { values } = parseArgs({ args: argv, options: { all: { type: 'boolean' }, json: { type: 'boolean' } } });
  const findings = loadFindings(ctx, active.slug).filter(finding => values.all || finding.status === 'open');
  if (values.json) out(JSON.stringify(findings, null, 2));
  else if (!findings.length) out(values.all ? 'No findings.' : 'No open findings.');
  else {
    for (const finding of findings) {
      out(findingLine(finding));
      out(`   breaks: ${finding.breaks}`);
      out(`   ${finding.evidence.kind}: ${finding.evidence.value}${finding.note ? ` · note: ${finding.note}` : ''}`);
    }
  }
  return 0;
}

// A command finding is proven while its command fails and fixed once the
// command passes after having failed; one that never failed proves nothing.
async function verify(ctx, active, argv, out) {
  const selected = loadFindings(ctx, active.slug).filter(finding => finding.status === 'open' && (!argv[0] || finding.id === argv[0]));
  if (argv[0] && !selected.length) fail(`no open finding ${argv[0]}`);
  const results = new Map();
  for (const finding of selected) {
    const change = {};
    if (finding.evidence.kind === 'command') {
      const logFile = path.join(ctx.paths.logs, active.slug, `finding-${finding.id}.log`);
      const result = await runCommand(finding.evidence.value, { cwd: ctx.root, timeoutSeconds: ctx.config.verifyTimeout, logFile, env: ctx.env });
      if (!result.ok) change.reproduced = true;
      else if (finding.reproduced) change.status = 'fixed';
      else {
        change.status = 'unproven';
        change.note = 'the evidence command passes, so it does not show the defect';
      }
    } else if (quotePresent(ctx, finding)) change.reproduced = true;
    else change.note = 'the quoted text is no longer at that place; confirm the fix with `dflow review resolve`';
    results.set(finding.id, change);
  }
  // The commands ran without the lock; their results are merged into whatever
  // the file holds now, so a finding added meanwhile is kept.
  const findings = updateFindings(ctx, active.slug, current => {
    for (const finding of current) Object.assign(finding, results.get(finding.id) ?? {});
    return current;
  });
  for (const finding of findings.filter(entry => results.has(entry.id))) out(findingLine(finding));
  const open = findings.filter(finding => finding.status === 'open');
  const proven = open.filter(finding => finding.reproduced);
  out(`${open.length} open (${open.filter(finding => finding.severity === 'blocking').length} blocking); fix the ${proven.length} with reproduced evidence, then run verify again.`);
  refreshHud(ctx);
  return 0;
}

function settle(ctx, active, argv, out, { statuses, verb }) {
  const [id, status, ...words] = argv;
  const note = words.join(' ').trim();
  if (!id || !statuses.includes(status)) fail(`usage: dflow review ${verb} <id> ${statuses.join('|')} "<note>"`);
  if (status !== 'fixed' && status !== 'confirmed' && !note) fail(`${status} needs a note saying why`);
  const finding = updateFindings(ctx, active.slug, findings => {
    const found = findings.find(entry => entry.id === id);
    if (!found) fail(`no finding ${id}`);
    if (status === 'confirmed') found.confirmed = true;
    else found.status = status;
    if (note) found.note = note;
    return found;
  });
  out(findingLine(finding));
  refreshHud(ctx);
  return 0;
}

function record(ctx, active, argv, out) {
  const { values } = parseArgs({ args: argv, options: { tier: { type: 'string' }, task: { type: 'string' } } });
  if (!/^[012]$/.test(values.tier ?? '')) fail('usage: dflow review record --tier 0|1|2 [--task N]');
  const tier = Number(values.tier);
  const task = taskOption(values.task);
  const required = buildPack(ctx, active, task).tier;
  if (tier < required) fail(`this diff needs a tier ${required} review; tier ${tier} is not enough`);
  const state = loadState(ctx.paths);
  const plan = planState(state, active.slug);
  const entry = { tier, sha: head(ctx.root), at: nowIso(ctx.env) };
  if (task === undefined) plan.review = entry;
  else {
    if (!plan.tasks[task]) fail(`Task ${task} has no record`);
    delete plan.tasks[task].reviewPending;
  }
  saveState(ctx.paths, state);
  appendEvent(ctx, { plan: active.slug, event: 'review', tier, task: task ?? null });
  out(`Recorded a tier ${tier} review of ${task === undefined ? relative(ctx.root, active.file) : `Task ${task}`} at ${entry.sha.slice(0, 7)}.`);
  refreshHud(ctx);
  return 0;
}

export async function run(ctx, argv, { out }) {
  const [action, ...rest] = argv;
  const active = requireActive(ctx, loadState(ctx.paths));
  if (action === 'pack') return pack(ctx, active, rest, out);
  if (action === 'add') return add(ctx, active, rest, out);
  if (action === 'list') return list(ctx, active, rest, out);
  if (action === 'verify') return verify(ctx, active, rest, out);
  if (action === 'resolve') return settle(ctx, active, rest, out, { statuses: ['fixed', 'declined'], verb: 'resolve' });
  if (action === 'judge') return settle(ctx, active, rest, out, { statuses: ['confirmed', 'refuted'], verb: 'judge' });
  if (action === 'record') return record(ctx, active, rest, out);
  fail('usage: dflow review pack|add|list|verify|resolve|judge|record');
}
