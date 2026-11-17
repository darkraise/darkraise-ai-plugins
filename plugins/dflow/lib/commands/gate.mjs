import fs from 'node:fs';
import path from 'node:path';
import { currentBranch, head, relative } from '../repo.mjs';
import { runCommand } from '../run.mjs';
import { loadState, planState, updateState } from '../state.mjs';
import { activePlan, refreshHud } from '../status.mjs';
import { fail, mustGit, nowIso, tail } from '../util.mjs';

// Runs the configured gates in order. A run of every gate is recorded against
// the head commit; a run of a named subset is not, since it proves less.
export async function runGates(ctx, { names = [], out }) {
  const all = ctx.config.gates;
  const unknown = names.filter(name => !all.some(gate => gate.name === name));
  if (unknown.length) fail(`no gate named ${unknown.join(', ')}; configured: ${all.map(gate => gate.name).join(', ') || 'none'}`);
  const selected = names.length ? all.filter(gate => names.includes(gate.name)) : all;
  const state = loadState(ctx.paths);
  const active = activePlan(ctx, state);
  const results = [];
  const changes = () => mustGit(ctx.root, ['status', '--porcelain', '--untracked-files=normal']).split('\n')
    .filter(entry => entry && !(entry.startsWith('??') && entry.slice(3).startsWith('docs/dflow/')));
  const shaBefore = head(ctx.root);
  const changesBefore = changes();
  // A pass on uncommitted changes says nothing about the commit.
  const dirty = changesBefore.length > 0;
  for (const gate of selected) {
    const logFile = path.join(ctx.paths.logs, active?.slug ?? '_', `gate-${gate.name}.log`);
    fs.rmSync(logFile, { force: true });
    const result = await runCommand(gate.cmd, { cwd: ctx.root, timeoutSeconds: gate.timeout ?? 900, logFile, env: ctx.env });
    results.push({ name: gate.name, ok: result.ok, seconds: Number(result.seconds.toFixed(1)) });
    if (result.ok) {
      out(`ok    ${gate.name} (${result.seconds.toFixed(1)}s)`);
      continue;
    }
    out(`FAIL  ${gate.name}: \`${gate.cmd}\` ${result.timedOut ? `timed out after ${gate.timeout ?? 900}s` : `exited ${result.status}`} (${result.seconds.toFixed(1)}s)`);
    for (const line of tail(result.output, 30)) out(`      ${line}`);
    out(`      full log: ${relative(ctx.root, logFile)}`);
  }
  const sha = head(ctx.root);
  const changesAfter = changes();
  const edited = [...new Set([...changesBefore, ...changesAfter].filter(entry => !changesBefore.includes(entry) || !changesAfter.includes(entry)).map(entry => entry.slice(3)))];
  const moved = sha !== shaBefore ? 'the head commit moved' : edited.length ? `the working tree changed (${edited.join(', ')})` : null;
  if (moved) {
    out(`${moved} while the gates ran; nothing was recorded, since the gates did not run on one tree. Run \`dflow gate\` again once nothing else is changing the checkout.`);
    refreshHud(ctx);
    return false;
  }
  const ok = results.every(result => result.ok);
  if (!names.length) {
    if (active) {
      updateState(ctx.paths, fresh => {
        planState(fresh, active.slug).gates = { sha, at: nowIso(ctx.env), ok, dirty, results };
      });
    }
    fs.mkdirSync(ctx.paths.stateDir, { recursive: true });
    for (const result of results) fs.appendFileSync(path.join(ctx.paths.stateDir, 'gate-history.jsonl'), `${JSON.stringify({ sha, branch: currentBranch(ctx.root), ...result })}\n`);
  }
  if (!all.length) out('No gates are configured; add them with `dflow init --gate "<name>=<command>"`.');
  refreshHud(ctx);
  return ok;
}

export async function run(ctx, argv, { out }) {
  return (await runGates(ctx, { names: argv, out })) ? 0 : 1;
}
