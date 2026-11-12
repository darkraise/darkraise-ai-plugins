import fs from 'node:fs';
import path from 'node:path';
import { amendedVerify, approvedPlan } from './approval.mjs';
import { sectionText } from './plan.mjs';
import { baseCommit, currentBranch, defaultBranch, relative } from './repo.mjs';
import { planState, loadState } from './state.mjs';
import { findingsFile, loadFindings } from './status.mjs';
import { isTestFile, weakenedTests } from './tests-check.mjs';
import { fail, git, gitOut, matchesAny, readText, shortSha, writeJson } from './util.mjs';

export const SEVERITIES = ['blocking', 'should', 'nit'];
const OWN = ':(exclude)docs/dflow';

// The commits a review covers: one task's commit, or the plan's branch since
// it left the default branch (since approval, when built on the default branch).
export function reviewRange(ctx, active, taskNumber) {
  if (taskNumber !== undefined) {
    const commit = planState(loadState(ctx.paths), active.slug).tasks[taskNumber]?.commit;
    if (!commit) fail(`Task ${taskNumber} has no recorded commit`);
    return { base: `${commit}^`, head: commit };
  }
  const base = baseCommit(ctx.root, ctx.config) ?? approvedPlan(ctx, active)?.commit;
  if (!base) fail('no base commit: the plan is neither on a branch off the default branch nor approved');
  return { base, head: 'HEAD' };
}

function numstat(ctx, range) {
  const output = gitOut(ctx.root, ['diff', '--numstat', '--no-renames', `${range.base}..${range.head}`, '--', '.', OWN]) ?? '';
  return output.split('\n').filter(Boolean).map(line => {
    const [added, deleted, file] = line.split('\t');
    return { file, added: Number(added) || 0, deleted: Number(deleted) || 0 };
  });
}

function suiteGrowth(ctx) {
  const text = readText(path.join(ctx.paths.stateDir, 'gate-history.jsonl'));
  if (!text) return null;
  const runs = text.split('\n').filter(Boolean).map(line => JSON.parse(line)).filter(run => run.ok);
  const total = branch => {
    const latest = new Map();
    for (const run of runs) if (run.branch === branch) latest.set(run.name, run.seconds);
    return latest.size ? [...latest.values()].reduce((sum, seconds) => sum + seconds, 0) : null;
  };
  const before = total(defaultBranch(ctx.root, ctx.config));
  const after = total(currentBranch(ctx.root));
  if (!before || after === null) return null;
  return { before, after, growth: (after - before) / before };
}

export function requiredTier(ctx, active, files) {
  const lines = files.reduce((sum, entry) => sum + entry.added + entry.deleted, 0);
  const limits = ctx.config.review;
  if (active.plan.risk !== 'none' || active.plan.tasks.some(task => task.risk !== 'none') || lines > limits.tier2Lines || files.length > limits.tier2Files) return 2;
  return lines <= limits.tier0Lines ? 0 : 1;
}

export function buildPack(ctx, active, taskNumber) {
  const range = reviewRange(ctx, active, taskNumber);
  const files = numstat(ctx, range);
  const tasks = taskNumber === undefined ? active.plan.tasks : active.plan.tasks.filter(task => task.number === taskNumber);
  const planned = tasks.flatMap(task => task.files);
  const testFiles = files.filter(entry => isTestFile(ctx.config, entry.file));
  const sourceFiles = files.filter(entry => !isTestFile(ctx.config, entry.file));
  const testLines = testFiles.reduce((sum, entry) => sum + entry.added, 0);
  const sourceLines = sourceFiles.reduce((sum, entry) => sum + entry.added, 0);
  const diffRange = `${range.base}..${range.head}`;
  const added = (gitOut(ctx.root, ['diff', '-U0', '--no-renames', diffRange, '--', '.', OWN]) ?? '').split('\n').filter(line => line.startsWith('+') && !line.startsWith('+++'));
  const newFiles = new Set((gitOut(ctx.root, ['diff', '--name-only', '--diff-filter=A', '--no-renames', diffRange, '--', '.', OWN]) ?? '').split('\n').filter(Boolean));
  const growth = suiteGrowth(ctx);
  const ratio = sourceLines ? testLines / sourceLines : (testLines ? Infinity : 0);
  const pack = {
    plan: active.rel,
    task: taskNumber ?? null,
    range,
    tier: taskNumber === undefined ? requiredTier(ctx, active, files) : 1,
    files,
    lines: files.reduce((sum, entry) => sum + entry.added + entry.deleted, 0),
    facts: {
      outsidePlan: files.map(entry => entry.file).filter(file => !matchesAny(planned, file)),
      amendedVerify: amendedVerify(ctx, active).filter(entry => taskNumber === undefined || entry.task === taskNumber),
      weakenedTests: weakenedTests(ctx, [diffRange]),
      tests: { testLines, sourceLines, ratio, newTestFiles: testFiles.filter(entry => newFiles.has(entry.file)).length, overBudget: ratio > ctx.config.tests.maxRatio },
      suite: growth && { ...growth, overBudget: growth.growth > ctx.config.tests.maxSuiteGrowth },
      todos: added.filter(line => /\b(TODO|FIXME|XXX)\b/.test(line)).length,
      deviations: active.plan.log.filter(entry => 'XWVA'.includes(entry.kind) && (taskNumber === undefined || entry.task === taskNumber)),
    },
  };
  return pack;
}

export function factLines(pack) {
  const { facts } = pack;
  const lines = [];
  if (facts.outsidePlan.length) lines.push(`Changed outside every task's Files: ${facts.outsidePlan.join(', ')}`);
  for (const entry of facts.amendedVerify) lines.push(`Task ${entry.task} verify changed after approval${entry.logged ? '' : ' WITHOUT a logged reason'}: was ${entry.was.join(' && ')}; now ${entry.now.join(' && ')}`);
  for (const line of facts.weakenedTests) lines.push(`Weakened test: ${line}`);
  const tests = facts.tests;
  const ratio = Number.isFinite(tests.ratio) ? `${tests.ratio.toFixed(1)}×` : 'tests only';
  lines.push(`Tests: ${tests.testLines} test lines against ${tests.sourceLines} source lines added (${ratio}), ${tests.newTestFiles} new test file(s)${tests.overBudget ? ' — OVER the test budget: trim or justify' : ''}`);
  if (facts.suite) lines.push(`Suite time: ${facts.suite.before.toFixed(1)}s on the default branch, ${facts.suite.after.toFixed(1)}s here (${(facts.suite.growth * 100).toFixed(0)}%)${facts.suite.overBudget ? ' — OVER the growth budget' : ''}`);
  else lines.push('Suite time: unknown (no recorded gate run on both branches)');
  if (facts.todos) lines.push(`${facts.todos} added line(s) carry TODO, FIXME or XXX`);
  for (const entry of facts.deviations) lines.push(`Logged deviation, ${entry.task ? `Task ${entry.task}` : 'plan'} ${entry.kind}: ${entry.text}`);
  return lines;
}

export function writePack(ctx, active, pack) {
  const { plan } = active;
  const file = path.join(ctx.paths.stateDir, 'review', active.slug, pack.task ? `pack-task-${pack.task}.md` : 'pack.md');
  const scope = pack.task ? `Task ${pack.task} of ${plan.title}` : plan.title;
  const text = [
    `# Review pack: ${scope}`,
    '',
    `Plan: ${active.rel} · tier ${pack.tier} · ${pack.files.length} files, ${pack.lines} changed lines`,
    `Diff: \`git diff ${shortSha(pack.range.base)}..${pack.range.head} -- . '${OWN}'\``,
    '',
    `Goal: ${plan.fields.goal ?? ''}`,
    '',
    'Acceptance:',
    ...plan.acceptance.map(line => `- ${line.id}${line.ui ? ' UI' : ''}: ${line.text}`),
    '',
    '## Design',
    ...sectionText(plan, 'design'),
    '',
    '## Mechanical facts (computed; do not re-derive)',
    ...factLines(pack).map(line => `- ${line}`),
    '',
    '## Files',
    ...pack.files.map(entry => `- ${entry.file} (+${entry.added} −${entry.deleted})`),
    '',
  ].join('\n');
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text);
  return relative(ctx.root, file);
}

function normalise(text) {
  return text.replace(/\s+/g, ' ').trim();
}

// A quote counts as present when it appears within five lines of the cited one.
export function quotePresent(ctx, finding) {
  const text = readText(path.join(ctx.root, finding.file));
  if (text === null) return false;
  const lines = text.split('\n');
  const from = Math.max(0, finding.line - 6);
  return normalise(lines.slice(from, finding.line + 5).join(' ')).includes(normalise(finding.evidence.value));
}

export function addFinding(ctx, slug, fields) {
  const findings = loadFindings(ctx, slug);
  const { file, line, severity, claim, breaks, command, quote } = fields;
  if (!file || !fs.existsSync(path.join(ctx.root, file))) fail(`--file ${JSON.stringify(file ?? '')} does not exist in the repository`);
  if (!Number.isInteger(line) || line < 1) fail('--line takes a line number');
  if (!SEVERITIES.includes(severity)) fail(`--severity is one of ${SEVERITIES.join(', ')}`);
  if (!claim?.trim()) fail('--claim is required: one sentence stating the defect');
  if (!breaks?.trim()) fail('--breaks is required: what goes wrong for whom');
  if (Boolean(command) === Boolean(quote)) fail('give exactly one piece of evidence: --cmd "<command that exits non-zero while the defect exists>" or --quote "<the exact text at file:line>"');
  const finding = {
    id: `F${Math.max(0, ...findings.map(entry => Number(entry.id.slice(1)))) + 1}`,
    file, line, severity, claim: claim.trim(), breaks: breaks.trim(),
    evidence: command ? { kind: 'command', value: command } : { kind: 'quote', value: quote },
    task: fields.task ?? null, lens: fields.lens ?? null,
    status: 'open', reproduced: null, note: null,
  };
  if (finding.evidence.kind === 'quote' && !quotePresent(ctx, finding)) fail(`the quoted text is not within five lines of ${file}:${line}; quote the file exactly`);
  findings.push(finding);
  writeJson(findingsFile(ctx, slug), findings);
  return finding;
}

export function saveFindings(ctx, slug, findings) {
  writeJson(findingsFile(ctx, slug), findings);
}

export function findingLine(finding) {
  const proof = finding.status !== 'open' ? finding.status : finding.reproduced === true ? 'reproduced' : 'unchecked';
  return `${finding.id} ${finding.severity.padEnd(8)} ${proof.padEnd(10)} ${finding.file}:${finding.line} ${finding.claim}`;
}
