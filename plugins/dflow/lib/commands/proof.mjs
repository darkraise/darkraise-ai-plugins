import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { loadProofs, proofDir, proofStatus } from '../proof.mjs';
import { head, relative } from '../repo.mjs';
import { loadState } from '../state.mjs';
import { fail, mustGit, nowIso, shortSha, writeJson } from '../util.mjs';
import { requireActive } from './next.mjs';

export async function run(ctx, argv, { out }) {
  const { values, positionals } = parseArgs({
    args: argv, allowPositionals: true,
    options: { shot: { type: 'string' }, steps: { type: 'string' }, text: { type: 'string' }, list: { type: 'boolean' } },
  });
  const active = requireActive(ctx, loadState(ctx.paths));
  const sha = head(ctx.root);
  if (values.list || !positionals.length) {
    const lines = proofStatus(ctx, active, sha);
    if (!lines.length) out('This plan has no UI acceptance lines.');
    for (const line of lines) out(`${line.id} ${line.state}${line.state === 'stale' ? ` (changed since: ${line.touched.join(', ')})` : line.proof ? ` at ${shortSha(line.proof.sha)}` : ''}`);
    return lines.every(line => line.state === 'proven') ? 0 : 1;
  }
  const id = positionals[0];
  const line = active.plan.acceptance.find(candidate => candidate.id === id);
  if (!line) fail(`${active.rel} has no acceptance line ${id}`);
  if (!line.ui) fail(`${id} is not a UI line; it is proven by its command at ship`);
  if (!values.shot) fail('usage: dflow proof <A-id> --shot <screenshot file> --text "<what the page showed>" [--steps "<how you got there>"]');
  if (!line.visual && !values.text) fail(`${id} is proven on text: pass --text "<the text or state the page showed>"`);
  const source = path.resolve(ctx.cwd, values.shot);
  if (!fs.existsSync(source)) fail(`no screenshot at ${values.shot}`);
  const dirty = mustGit(ctx.root, ['status', '--porcelain', '--untracked-files=no']).split('\n').filter(entry => entry && !entry.slice(3).startsWith('docs/dflow/'));
  if (dirty.length) fail('the working tree has uncommitted changes; a proof is of a commit, so commit first');
  const directory = proofDir(ctx, active.slug);
  const target = path.join(directory, `${id}${path.extname(source) || '.png'}`);
  fs.mkdirSync(directory, { recursive: true });
  if (path.resolve(target) !== source) fs.copyFileSync(source, target);
  const proofs = loadProofs(ctx, active.slug);
  proofs[id] = { shot: relative(ctx.root, target), text: values.text ?? null, steps: values.steps ?? null, sha, at: nowIso(ctx.env) };
  writeJson(path.join(directory, 'proof.json'), proofs);
  out(`${id} proven at ${shortSha(sha)}: ${relative(ctx.root, target)}`);
  return 0;
}
