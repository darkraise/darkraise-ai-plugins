import { mkdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PLUGIN, sh } from './sh.mjs';

const LIB = resolve(PLUGIN, 'scripts/lib/plan.sh');
const TEST_FILE = /\.test\.(sh|mjs)$/;

// The plugin's own plan reader does the parsing, so the harness and
// scripts/task-brief agree on what a task is.
function planLib(fn, args, input) {
  return sh('bash', ['-c', '. "$0"; "$@"', LIB, fn, ...args], { input });
}

export function tasks(planFile) {
  return planLib('plan_tasks', [planFile]).out.split('\n').filter(Boolean).map(line => {
    const [n, title] = line.split('\t');
    return { n: Number(n), title };
  });
}

export function taskText(planFile, n) {
  const r = planLib('plan_task_text', [planFile, String(n)]);
  return r.code === 0 ? r.out : null;
}

// evaluation TEXT — the four axes and the total, or null unless the task has
// exactly one Evaluation line and it parses.
export function evaluation(text) {
  const lines = planLib('plan_eval_lines', [], text).out.split('\n').filter(Boolean);
  if (lines.length !== 1) return null;
  const m = lines[0].match(/files (\d+)\D+spec (\d+)\D+coupling (\d+)\D+risk (\d+) = (\d+)/);
  if (!m) return null;
  const [files, spec, coupling, risk, total] = m.slice(1).map(Number);
  return { files, spec, coupling, risk, total };
}

export function commitMessages(text) {
  const found = new Set();
  for (const m of text.matchAll(/git commit\b[^\n]*?-m\s+(["'])(.+?)\1/g)) found.add(m[2]);
  return [...found];
}

// filesBlock TEXT — the paths the task's **Files:** block names. A path is a
// test when its line is labelled Test or its name is a runnable test file:
// plans list an existing test file under Modify.
export function filesBlock(text) {
  const allowed = new Set(), tests = new Set();
  let on = false;
  for (const line of text.split('\n')) {
    if (line.startsWith('**Files:**')) { on = true; continue; }
    const m = on && line.match(/^- (Create|Modify|Test):\s*(.+)$/);
    if (!m) { if (on && line.trim() !== '') on = false; continue; }
    const quoted = [...m[2].matchAll(/`([^`]+)`/g)].map(q => q[1]);
    const names = quoted.length > 0 ? quoted : [m[2].split(/\s/)[0]];
    for (const name of names) {
      const path = name.replace(/:[0-9][0-9,-]*$/, '').replace(/,$/, '');
      if (!/[\/.]/.test(path) || /\s/.test(path)) continue;
      allowed.add(path);
      if (m[1] === 'Test' || TEST_FILE.test(path)) tests.add(path);
    }
  }
  return { allowed: [...allowed], tests: [...tests] };
}

// taskBrief PLAN_FILE N DIR — the brief scripts/task-brief writes for task N:
// the task text plus the header's Global Constraints and Contracts.
export function taskBrief(planFile, n, dir) {
  mkdirSync(dir, { recursive: true });
  const out = join(dir, 'brief.md');
  const r = sh('bash', [resolve(PLUGIN, 'scripts/task-brief'), planFile, String(n), out], { cwd: dir });
  if (r.code !== 0) throw new Error(`task-brief ${planFile} ${n}: exit ${r.code} ${r.err.trim()}`);
  return readFileSync(out, 'utf8');
}
