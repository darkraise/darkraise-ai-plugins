import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { amendedAcceptance, approvedPlan } from '../approval.mjs';
import { parseBoard, rewriteRow } from '../board.mjs';
import { blockedTasks, setField } from '../plan.mjs';
import { proofStatus } from '../proof.mjs';
import { baseCommit, defaultBranch, head, relative } from '../repo.mjs';
import { buildPack } from '../review.mjs';
import { runCommand } from '../run.mjs';
import { appendEvent, loadState, planState, updateState } from '../state.mjs';
import { loadFindings, refreshHud, unrecordedTicks } from '../status.mjs';
import { git, gitList, gitOut, mustGit, readText, shortSha, tail, today } from '../util.mjs';
import { diagnose } from './doctor.mjs';
import { runGates } from './gate.mjs';
import { requireActive } from './next.mjs';
import { closeWorkstream, flush } from './sync.mjs';

const PROMOTED = { D: 'decisions.md', G: 'gotchas.md' };

// Runs the acceptance commands that have not passed on this commit. Under
// --check nothing is run: those lines are returned as pending, since only
// running them can show whether they hold.
async function acceptance(ctx, active, record, sha, checkOnly, out) {
  const problems = [];
  const pending = [];
  record.acceptance ??= {};
  for (const line of active.plan.acceptance.filter(candidate => !candidate.ui)) {
    const known = record.acceptance[line.id];
    if (known?.ok && known.sha === sha) continue;
    if (checkOnly) {
      pending.push(`${line.id}: ${line.commands.map(command => `\`${command}\``).join(', ')}`);
      continue;
    }
    for (const command of line.commands) {
      const logFile = path.join(ctx.paths.logs, active.slug, `acceptance-${line.id}.log`);
      fs.rmSync(logFile, { force: true });
      const result = await runCommand(command, { cwd: ctx.root, timeoutSeconds: 900, logFile, env: ctx.env });
      record.acceptance[line.id] = { ok: result.ok, sha };
      if (result.ok) continue;
      problems.push(`${line.id} fails: \`${command}\` ${result.timedOut ? 'timed out' : `exited ${result.status}`}`);
      for (const text of tail(result.output, 15)) out(`      ${text}`);
      break;
    }
  }
  for (const line of proofStatus(ctx, active, sha)) {
    if (line.state === 'missing') problems.push(`${line.id} (UI) has no proof; drive it in the running app and record it with \`dflow proof ${line.id}\``);
    if (line.state === 'stale') problems.push(`${line.id} (UI) was proven at ${shortSha(line.proof.sha)}, before ${line.touched.join(', ')} changed; prove it again`);
  }
  return { problems, pending };
}

function docsDelta(ctx, active, base) {
  const problems = [];
  for (const name of active.plan.docs) {
    const file = path.join(ctx.paths.docs, name);
    if (!fs.existsSync(file)) {
      problems.push(`Docs names ${name}, which does not exist in docs/dflow`);
      continue;
    }
    const kind = Object.keys(PROMOTED).find(key => PROMOTED[key] === name);
    if (kind && active.plan.log.some(entry => entry.kind === kind)) continue;
    const changed = gitOut(ctx.root, ['diff', '--name-only', `${base}..HEAD`, '--', relative(ctx.root, file)]);
    if (!changed) problems.push(kind ? `Docs names ${name}, but the plan log has no \`${kind}:\` line to promote and the file is unchanged` : `Docs names ${name}, but this branch does not change it`);
  }
  return problems;
}

function promote(ctx, active) {
  const date = today(ctx.env);
  const source = `plans/${path.basename(active.file)}`;
  const written = [];
  const decisions = active.plan.log.filter(entry => entry.kind === 'D');
  if (decisions.length) {
    const file = path.join(ctx.paths.docs, 'decisions.md');
    let text = readText(file) ?? '# Decisions\n';
    // Numbered within the plan: plans built side by side on separate branches
    // both append here, and a counter over the file would give two entries
    // the same number.
    decisions.forEach((entry, index) => {
      text = `${text.replace(/\s*$/, '')}\n\n## D-${active.slug}/${index + 1} · ${date}\n\n${entry.text}\n\nSource: ${source}${entry.task ? `, Task ${entry.task}` : ''}\n`;
    });
    fs.writeFileSync(file, text);
    written.push(`${decisions.length} decision(s) to decisions.md`);
  }
  const gotchas = active.plan.log.filter(entry => entry.kind === 'G');
  if (gotchas.length) {
    const file = path.join(ctx.paths.docs, 'gotchas.md');
    const text = readText(file) ?? '# Gotchas\n';
    fs.writeFileSync(file, `${text.replace(/\s*$/, '')}\n${gotchas.map(entry => `\n- ${entry.text} (${source}, ${date})`).join('')}\n`);
    written.push(`${gotchas.length} gotcha(s) to gotchas.md`);
  }
  return { written, decisions };
}

export async function run(ctx, argv, { out }) {
  const { values } = parseArgs({ args: argv, options: { check: { type: 'boolean' } } });
  const state = loadState(ctx.paths);
  const active = requireActive(ctx, state);
  const record = planState(state, active.slug);
  const sha = head(ctx.root);
  const problems = [];
  const pending = [];

  const open = active.plan.tasks.filter(task => !task.done);
  const blocked = blockedTasks(active.plan);
  if (open.length) problems.push(`not every task is done: ${open.map(task => `Task ${task.number}${blocked.has(task.number) ? ' (blocked)' : ''}`).join(', ')}`);
  for (const number of unrecordedTicks(ctx, active)) problems.push(`Task ${number} is ticked without a recorded \`dflow done\`, so its verify never passed here; untick its steps and run \`dflow done ${number}\``);
  // Ship runs the acceptance commands the plan holds now, so a line changed
  // after approval counts only once the owner's agreement is on record.
  for (const change of amendedAcceptance(ctx, active).filter(entry => !entry.logged)) {
    problems.push(`Acceptance ${change.id} changed after approval with no record of the owner agreeing (was: ${change.was ?? 'absent'}; now: ${change.now ?? 'removed'}); ask the owner, then \`dflow log - A "${change.id}: <what changed> — agreed by the owner"\`, naming each command it runs in backticks`);
  }

  // An untracked file outside docs/dflow/ may be one the gates used, and the
  // commit would ship without it; drafts of other work there stay untracked.
  const dirty = gitList(ctx.root, ['status', '--porcelain', '--untracked-files=normal', '--no-renames', '-z'])
    .filter(entry => !(entry.startsWith('??') && entry.slice(3).startsWith('docs/dflow/')));
  if (dirty.length) problems.push(`uncommitted changes: ${dirty.map(entry => entry.slice(3)).join(', ')}`);

  if (!problems.length) {
    // A recorded pass counts only for this commit and a clean tree.
    const gatesHold = record.gates?.ok && record.gates.sha === sha && !record.gates.dirty;
    if (ctx.config.gates.length && !gatesHold) {
      if (values.check) pending.push(`the gates: ${ctx.config.gates.map(gate => gate.name).join(', ')}`);
      else if (!await runGates(ctx, { out })) problems.push('a gate fails');
    }
    const accepted = await acceptance(ctx, active, record, sha, values.check, out);
    problems.push(...accepted.problems);
    pending.push(...accepted.pending);
    // runGates saved its own result meanwhile, so merge into the file's state.
    updateState(ctx.paths, latest => {
      planState(latest, active.slug).acceptance = record.acceptance;
    });
  }

  const required = buildPack(ctx, active).tier;
  const review = planState(loadState(ctx.paths), active.slug).review;
  if (!review) problems.push(`no review is recorded; this diff needs tier ${required} (/dflow:review)`);
  else {
    if (review.tier < required) problems.push(`the recorded review is tier ${review.tier}; this diff needs tier ${required}`);
    // Fixes made after the review are expected, so the review is recorded
    // once they are in. Code committed after that has been seen by nobody.
    const since = gitList(ctx.root, ['diff', '--name-only', '--no-renames', '-z', `${review.sha}..HEAD`]).filter(file => !(file.startsWith('docs/dflow/') && file.endsWith('.md')));
    if (since.length) problems.push(`${since.length} file(s) changed after the recorded review (${since.slice(0, 5).join(', ')}${since.length > 5 ? ', …' : ''}); review them and run \`dflow review record\` again`);
  }
  const findings = loadFindings(ctx, active.slug);
  const blocking = findings.filter(finding => finding.status === 'open' && finding.severity === 'blocking');
  if (blocking.length) problems.push(`${blocking.length} blocking finding(s) are open: ${blocking.map(finding => finding.id).join(', ')}`);

  const base = baseCommit(ctx.root, ctx.config) ?? approvedPlan(ctx, active)?.commit;
  if (base) problems.push(...docsDelta(ctx, active, base));
  problems.push(...diagnose(ctx, { plans: [active] }).map(problem => `doctor: ${problem}`));

  if (problems.length) {
    out(`Not done: ${problems.length} condition(s) of the definition of done are unmet.`);
    for (const problem of problems) out(`- ${problem}`);
    if (pending.length) out(`Not yet run, \`dflow ship\` runs them: ${pending.join('; ')}`);
    return 1;
  }
  const declined = findings.filter(finding => finding.status === 'declined');
  if (values.check) {
    if (pending.length) out(`Nothing is unmet at ${shortSha(sha)}. \`dflow ship\` still has to run: ${pending.join('; ')}`);
    else out(`Ready to ship: every condition of the definition of done holds at ${shortSha(sha)}.`);
    return 0;
  }

  // Everything ship writes, so that a refused closing commit can be undone
  // and so that nothing else under docs/dflow rides along.
  const boardText = readText(ctx.paths.board);
  const row = boardText && parseBoard(boardText).rows.find(candidate => String(candidate.number) === String(active.plan.fields.board));
  const touched = [active.file, path.join(ctx.paths.docs, 'decisions.md'), path.join(ctx.paths.docs, 'gotchas.md'), ...(row ? [ctx.paths.board] : [])];
  const before = new Map(touched.map(file => [file, readText(file)]));
  const restore = () => {
    git(ctx.root, ['reset', '-q', '--', ...touched.map(file => relative(ctx.root, file))]);
    for (const [file, text] of before) {
      if (text === null) fs.rmSync(file, { force: true });
      else fs.writeFileSync(file, text);
    }
  };

  const { written, decisions } = promote(ctx, active);
  const date = today(ctx.env);
  fs.writeFileSync(active.file, setField(readText(active.file), 'Shipped', date));
  if (row) fs.writeFileSync(ctx.paths.board, rewriteRow(boardText, row.number, { state: 'done', note: `shipped ${date}` }));
  const changed = touched.filter(file => readText(file) !== before.get(file)).map(file => relative(ctx.root, file));
  mustGit(ctx.root, ['add', '--', ...changed]);
  const commit = git(ctx.root, ['commit', '-q', '-m', `docs(dflow): ship ${active.slug}`.slice(0, 72), '--', ...changed]);
  if (!commit.ok) {
    restore();
    out(`The closing commit failed, so the plan is not shipped and nothing was changed:\n${(commit.stderr || commit.stdout).trim()}`);
    return 1;
  }
  appendEvent(ctx, { plan: active.slug, event: 'shipped', commit: head(ctx.root) });
  await closeWorkstream(ctx, active.slug);
  await flush(ctx, { quiet: true });
  refreshHud(ctx);

  out(`Shipped ${active.rel} at ${shortSha(head(ctx.root))}${written.length ? `; promoted ${written.join(' and ')}` : ''}. Board row ${row ? row.number : '-'} is done.`);
  for (const finding of declined) out(`Declined finding for the owner to see: ${finding.id} ${finding.severity} ${finding.file}:${finding.line} ${finding.claim} — ${finding.note}`);
  if (decisions.length) {
    out('Durable facts to file in darkmem memory (one per entry), if its tools are available:');
    for (const entry of decisions) out(`- ${entry.text}`);
  }
  out(`Now offer the owner: open a pull request, or merge into ${defaultBranch(ctx.root, ctx.config)}. Push only after they say so.`);
  return 0;
}
