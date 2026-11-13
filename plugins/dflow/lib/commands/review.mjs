import { parseArgs } from 'node:util';
import { head, relative } from '../repo.mjs';
import { addFinding, buildPack, factLines, findingLine, quotePresent, updateFindings, writePack } from '../review.mjs';
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

// A command finding is proven while its command fails, and fixed once it
// passes after having failed; one that never failed proves nothing. 126 and
// 127 are the shell's own: the command could not run, which shows nothing
// about the code.
export function evidenceResult(finding, status) {
  if (status === 126 || status === 127) return { lastExit: status, note: `the evidence command could not run (exit ${status}); correct it with the reviewer, or resolve the finding` };
  if (status !== 0) return { lastExit: status, reproduced: true, note: null };
  if (finding.reproduced) return { lastExit: status, status: 'fixed' };
  return { lastExit: status, status: 'unproven', note: 'the evidence command passes, so it does not show the defect' };
}

function summary(findings, out) {
  const open = findings.filter(finding => finding.status === 'open');
  const proven = open.filter(finding => finding.reproduced);
  out(`${open.length} open (${open.filter(finding => finding.severity === 'blocking').length} blocking); fix the ${proven.length} with reproduced evidence, then run verify again.`);
}

// A reviewer wrote the evidence commands, so dflow never runs them: the
// session runs each with its own shell tool, where the permission checks see
// the command, and records the exit status with `check`. A quote is only
// read, so it is checked here.
function verify(ctx, active, argv, out) {
  const selected = loadFindings(ctx, active.slug).filter(finding => finding.status === 'open' && (!argv[0] || finding.id === argv[0]));
  if (argv[0] && !selected.length) fail(`no open finding ${argv[0]}`);
  const quotes = selected.filter(finding => finding.evidence.kind === 'quote');
  const commands = selected.filter(finding => finding.evidence.kind === 'command');
  const results = new Map(quotes.map(finding => [finding.id, quotePresent(ctx, finding)
    ? { reproduced: true }
    : { note: 'the quoted text is no longer at that place; confirm the fix with `dflow review resolve`' }]));
  const findings = updateFindings(ctx, active.slug, current => {
    for (const finding of current) Object.assign(finding, results.get(finding.id) ?? {});
    return current;
  });
  for (const finding of findings.filter(entry => results.has(entry.id))) out(findingLine(finding));
  if (commands.length) {
    out(`${commands.length} finding(s) carry an evidence command a reviewer wrote. Read each one, run it from ${ctx.root} with your shell tool, then record its exit status:`);
    for (const finding of commands) {
      out(`  ${finding.id}: ${finding.evidence.value}`);
      out(`      dflow review check ${finding.id} --exit <status>`);
    }
  }
  summary(findings, out);
  refreshHud(ctx);
  return 0;
}

function check(ctx, active, argv, out) {
  const { values, positionals } = parseArgs({ args: argv, allowPositionals: true, options: { exit: { type: 'string' } } });
  const id = positionals[0];
  if (!id || !/^[0-9]+$/.test(values.exit ?? '')) fail('usage: dflow review check <id> --exit <status>');
  let finding;
  const findings = updateFindings(ctx, active.slug, current => {
    finding = current.find(entry => entry.id === id);
    if (!finding) fail(`no finding ${id}`);
    if (finding.evidence.kind !== 'command') fail(`${id} carries quote evidence, which \`dflow review verify\` checks`);
    if (finding.status !== 'open') fail(`${id} is already ${finding.status}`);
    Object.assign(finding, evidenceResult(finding, Number(values.exit)));
    return current;
  });
  out(findingLine(finding));
  if (finding.note) out(`   ${finding.note}`);
  summary(findings, out);
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
  // Shipping closes the plan and promotes its decisions, so by default the
  // owner sees the review before it happens.
  if (task === undefined) out(ctx.config.autoShip ? 'Next: continue with the dflow:ship skill.' : 'Next: report the review to the owner and end your turn; shipping is their call (/dflow:ship).');
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
  if (action === 'check') return check(ctx, active, rest, out);
  if (action === 'resolve') return settle(ctx, active, rest, out, { statuses: ['fixed', 'declined'], verb: 'resolve' });
  if (action === 'judge') return settle(ctx, active, rest, out, { statuses: ['confirmed', 'refuted'], verb: 'judge' });
  if (action === 'record') return record(ctx, active, rest, out);
  fail('usage: dflow review pack|add|list|verify|check|resolve|judge|record');
}
