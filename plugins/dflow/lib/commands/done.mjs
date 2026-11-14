import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { amendedFiles, amendedVerify } from '../approval.mjs';
import { parseBoard, rewriteRow } from '../board.mjs';
import { contextSize, formatTokens } from '../context.mjs';
import { appendLog, nextTask, parsePlan, taskStates, tickTask } from '../plan.mjs';
import { head, relative } from '../repo.mjs';
import { runCommand } from '../run.mjs';
import { appendEvent, loadState, planState, updateState, taskRecord } from '../state.mjs';
import { refreshHud, taskBrief } from '../status.mjs';
import { weakenedTests } from '../tests-check.mjs';
import { fail, git, gitList, matchesAny, mustGit, readText, shortSha, tail, today, writeJson } from '../util.mjs';
import { requireActive } from './next.mjs';
import { flush } from './sync.mjs';

const CHOICE = [
  'Three verify failures on this task. Stop patching and decide which is wrong:',
  '  the implementation — say what the cause is, fix that cause, run done again',
  '  the test — dflow amend <N> --verify "<command>" --reason "<why the old one was wrong>"',
  '  the plan — edit the task and log it (dflow log <N> A "<what changed and why>"); a change to Goal, Acceptance or a Design decision needs the owner',
  '  none of these can proceed — dflow block <N> "<reason>"',
];

function staged(ctx) {
  return gitList(ctx.root, ['diff', '--cached', '--name-only', '--no-renames', '-z']);
}

// Every path whose working copy differs from the index: an unstaged edit or
// an untracked file that is not ignored.
function unstaged(ctx) {
  return gitList(ctx.root, ['status', '--porcelain', '--untracked-files=all', '--no-renames', '-z']).filter(entry => entry[1] !== ' ').map(entry => entry.slice(3));
}

export async function run(ctx, argv, { out }) {
  const { values, positionals } = parseArgs({
    args: argv, allowPositionals: true,
    options: { message: { type: 'string', short: 'm' }, extra: { type: 'string' }, weaken: { type: 'string' }, 'allow-empty': { type: 'boolean' } },
  });
  const number = Number(positionals[0]);
  if (!Number.isInteger(number) || !values.message) fail('usage: dflow done <N> -m "<type>(<scope>): <subject>"');
  const state = loadState(ctx.paths);
  const active = requireActive(ctx, state);
  if (!active.plan.fields.approved) fail(`${active.rel} is not approved`);
  const record = planState(state, active.slug);
  const tasks = taskStates(active.plan, record);
  const task = tasks.find(candidate => candidate.number === number);
  if (!task) fail(`${active.rel} has no Task ${number}`);
  if (task.done) fail(`Task ${number} is already done`);
  if (task.state === 'blocked') fail(`Task ${number} is blocked (${task.blockedReason}); clear it with \`dflow unblock ${number} "<what changed>"\``);
  if (!task.ready) fail(`Task ${number} waits on Task ${task.after.filter(dependency => !tasks.find(candidate => candidate.number === dependency)?.done).join(', ')}`);

  if (!task.verify.length) fail(`Task ${number} has no \`Verify:\` step, and a task is done only when a command proves it; add one with \`dflow amend ${number} --verify "<command>" --reason "<why>"\``);
  const amended = amendedVerify(ctx, active).find(entry => entry.task === number && !entry.logged);
  if (amended?.added) fail(`Task ${number} is not in the approved plan and no log line explains it; record the amendment with \`dflow log ${number} A "<what was added and why>"\``);
  if (amended) fail(`Task ${number}'s verify command differs from the approved plan and no log line names the current command; use \`dflow amend ${number} --verify "<command>" --reason "<why>"\``);
  const widened = amendedFiles(ctx, active).find(entry => entry.task === number && !entry.logged);
  if (widened) fail(`Task ${number}'s Files differ from the approved plan (was ${widened.was.join(', ')}; now ${widened.now.join(', ')}) and no log line explains it; record the amendment with \`dflow log ${number} A "<what changed and why>"\``);

  const boardRel = relative(ctx.root, ctx.paths.board);
  const own = file => file === active.rel || file === boardRel;
  const stagedFiles = staged(ctx).filter(file => !own(file));
  if (!stagedFiles.length && !values['allow-empty']) fail(`nothing is staged; \`git add\` Task ${number}'s files first (or pass --allow-empty for a task that changes no file)`);
  // Verify runs on the working tree, so the working tree has to be what gets
  // committed: anything not staged would be verified and then left out.
  const forgotten = unstaged(ctx).filter(file => !own(file));
  if (forgotten.length) {
    fail(`the working tree holds changes that are not staged, so the verified tree would not be the committed one: ${forgotten.slice(0, 12).join(', ')}${forgotten.length > 12 ? `, and ${forgotten.length - 12} more` : ''}\nstage what belongs to Task ${number}; stash, revert or ignore the rest`);
  }
  // The living docs may change in any task. The configuration may not ride
  // along unseen: it sets the gates and what counts as a test.
  const living = file => file.startsWith('docs/dflow/') && file.endsWith('.md');
  const outside = stagedFiles.filter(file => !matchesAny(task.files, file) && !living(file));
  if (outside.length && !values.extra) fail(`staged files outside Task ${number}'s Files: ${outside.join(', ')}; unstage them, or pass --extra "<why they belong to this task>"`);
  const weakened = weakenedTests(ctx, ['--cached']);
  if (weakened.length && !values.weaken) fail(`this commit makes the tests prove less:\n${weakened.map(line => `  ${line}`).join('\n')}\nrestore them, or pass --weaken "<why this is right>"`);

  const logFile = path.join(ctx.paths.logs, active.slug, `task-${number}.log`);
  fs.rmSync(logFile, { force: true });
  for (const command of task.verify) {
    const result = await runCommand(command, { cwd: ctx.root, timeoutSeconds: ctx.config.verifyTimeout, logFile, env: ctx.env });
    if (result.ok) continue;
    const attempts = updateState(ctx.paths, fresh => {
      const entry = taskRecord(fresh, active.slug, number);
      entry.state = 'wip';
      entry.attempts = (entry.attempts ?? 0) + 1;
      return entry.attempts;
    });
    appendEvent(ctx, { plan: active.slug, event: 'verify-failed', task: number });
    out(`Task ${number} verify failed (attempt ${attempts}): \`${command}\` ${result.timedOut ? `timed out after ${ctx.config.verifyTimeout}s` : `exited ${result.status}`} in ${result.seconds.toFixed(1)}s. Nothing was ticked or committed.`);
    for (const line of tail(result.output, 40)) out(line);
    out(`Full log: ${relative(ctx.root, logFile)}`);
    if (attempts >= 3) for (const line of CHOICE) out(line.replaceAll('<N>', String(number)));
    refreshHud(ctx);
    return 1;
  }

  const planBefore = active.text;
  const boardBefore = readText(ctx.paths.board);
  let planText = tickTask(planBefore, number);
  if (outside.length) planText = appendLog(planText, { date: today(ctx.env), task: number, kind: 'X', message: `${outside.join(', ')} — ${values.extra}` });
  if (weakened.length) planText = appendLog(planText, { date: today(ctx.env), task: number, kind: 'W', message: `${weakened.join('; ')} — ${values.weaken}` });
  fs.writeFileSync(active.file, planText);
  const after = parsePlan(planText);
  const finished = after.tasks.every(candidate => candidate.done);
  const toAdd = [active.rel];
  if (boardBefore !== null) {
    const row = parseBoard(boardBefore).rows.find(candidate => String(candidate.number) === String(active.plan.fields.board));
    const change = !row ? null
      : finished && row.state !== 'done' ? { state: 'verify', note: `all ${after.tasks.length} tasks done ${today(ctx.env)}` }
        : ['open', 'planned'].includes(row.state) ? { state: 'doing' } : null;
    if (change) {
      fs.writeFileSync(ctx.paths.board, rewriteRow(boardBefore, row.number, change));
      toAdd.push(boardRel);
    }
  }
  mustGit(ctx.root, ['add', '--', ...toAdd]);
  const commit = git(ctx.root, ['commit', '-q', '-m', values.message]);
  if (!commit.ok) {
    fs.writeFileSync(active.file, planBefore);
    if (boardBefore !== null) fs.writeFileSync(ctx.paths.board, boardBefore);
    git(ctx.root, ['reset', '-q', '--', ...toAdd]);
    fail(`verify passed, but the commit failed and nothing was ticked:\n${(commit.stderr || commit.stdout).trim()}`);
  }

  const sha = head(ctx.root);
  updateState(ctx.paths, fresh => {
    const entry = taskRecord(fresh, active.slug, number);
    entry.state = 'done';
    entry.commit = sha;
    if (task.risk !== 'none') entry.reviewPending = true;
  });
  appendEvent(ctx, { plan: active.slug, event: 'done', task: number, commit: sha, ...(task.risk !== 'none' ? { review: true } : {}) });

  const doneCount = after.tasks.filter(candidate => candidate.done).length;
  out(`Task ${number} done · ${shortSha(sha)} · ${doneCount}/${after.tasks.length}`);
  if (task.risk !== 'none') out(`Task ${number} carries risk "${task.risk}": review its commit now (dflow review pack --task ${number}) before building on it.`);
  const size = contextSize(ctx, state);
  // Only the mod compacts on the flag; a figure read from the transcript would end the turn with nothing to follow.
  if (size && size.source === 'mod' && size.tokens >= ctx.config.context.resetAt) {
    // The session id names the conversation to compact: another session open
    // in this checkout must leave the flag alone.
    writeJson(path.join(ctx.paths.stateDir, 'reset.json'), { plan: active.slug, session: ctx.env.CLAUDE_CODE_SESSION_ID || null, at: new Date().toISOString() });
    out(`RESET: the context is ${formatTokens(size.tokens)}, past the ${formatTokens(ctx.config.context.resetAt)} threshold. End this turn now with one line; the build resumes from the plan in a compacted context.`);
  }
  const reloaded = { ...active, text: planText, plan: after };
  const upcoming = nextTask(taskStates(after, planState(loadState(ctx.paths), active.slug)));
  out('');
  if (finished) out('Every task is done. Next: /dflow:review');
  else if (!upcoming) out('No remaining task is ready (blocked or waiting on a blocked task). Run `dflow status`.');
  else {
    const started = updateState(ctx.paths, fresh => {
      const following = taskRecord(fresh, active.slug, upcoming.number);
      if (following.state === 'wip') return false;
      following.state = 'wip';
      return true;
    });
    if (started) appendEvent(ctx, { plan: active.slug, event: 'wip', task: upcoming.number });
    for (const line of taskBrief(ctx, reloaded, upcoming, { designLimit: 0 })) out(line);
  }
  await flush(ctx, { quiet: true });
  refreshHud(ctx);
  return 0;
}
