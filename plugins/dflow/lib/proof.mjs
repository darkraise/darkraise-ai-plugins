import path from 'node:path';
import { isTestFile } from './tests-check.mjs';
import { gitOut, matchesAny, readJson } from './util.mjs';

export function proofDir(ctx, slug) {
  return path.join(ctx.paths.stateDir, 'proof', slug);
}

export function loadProofs(ctx, slug) {
  return readJson(path.join(proofDir(ctx, slug), 'proof.json'), {});
}

function uiPatterns(ctx, plan) {
  if (ctx.config.ui.paths.length) return ctx.config.ui.paths;
  return plan.tasks.flatMap(task => task.files);
}

// A proof goes stale when a commit after it touches a UI file: the configured
// UI paths, or without them any non-test file the plan's tasks name.
export function proofStatus(ctx, active, sha) {
  const proofs = loadProofs(ctx, active.slug);
  const patterns = uiPatterns(ctx, active.plan);
  return active.plan.acceptance.filter(line => line.ui).map(line => {
    const proof = proofs[line.id];
    if (!proof) return { id: line.id, state: 'missing' };
    if (proof.sha === sha) return { id: line.id, state: 'proven', proof };
    const changed = (gitOut(ctx.root, ['diff', '--name-only', '--no-renames', `${proof.sha}..${sha}`]) ?? '').split('\n').filter(Boolean);
    const touched = changed.filter(file => matchesAny(patterns, file) && !isTestFile(ctx.config, file));
    return touched.length ? { id: line.id, state: 'stale', proof, touched } : { id: line.id, state: 'proven', proof };
  });
}
