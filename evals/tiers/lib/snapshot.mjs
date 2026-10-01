import { mkdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { sh, git } from './sh.mjs';

const IDENT = ['-c', 'user.name=tier-eval', '-c', 'user.email=tier-eval@example.invalid'];

// snapshot COMMIT DIR [DROP] — the tree of COMMIT as a fresh one-commit
// repository in DIR, without the paths in DROP, so nothing later than COMMIT
// is reachable from it. Returns that one commit.
export function snapshot(commit, dir, drop = []) {
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  const r = sh('bash', ['-c', 'set -o pipefail; git archive "$0" | tar -x -C "$1"', commit, dir]);
  if (r.code !== 0) throw new Error(`snapshot ${commit}: ${r.err.trim()}`);
  for (const path of drop) rmSync(join(dir, path), { recursive: true, force: true });
  git(['init', '-q', '-b', 'main'], { cwd: dir });
  git(['add', '-A'], { cwd: dir });
  git([...IDENT, 'commit', '-q', '-m', 'snapshot'], { cwd: dir });
  return git(['rev-parse', 'HEAD'], { cwd: dir }).trim();
}
