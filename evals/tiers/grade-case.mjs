#!/usr/bin/env node
// Grade one implementation run with no model call.
// Usage: node evals/tiers/grade-case.mjs RUN_DIR   (re-grades a finished run)
// Exit: 0 graded; 2 usage.
import { existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { classify } from './lib/claude.mjs';
import { changedFiles, outcome, overlayTests, runTests, statusWord } from './lib/grade.mjs';

// gradeImpl INFO INVOCATION — the outcome of §3 of the spec: the scope check
// reads the tree before the historical tests are laid over it.
export async function gradeImpl(info, inv) {
  const outside = changedFiles(info.work, info.initial).filter(p => !info.allowed.includes(p));
  if (!overlayTests(info.work, info.result, info.tests)) throw new Error(`${info.id}: a test file is missing at ${info.result}`);
  const tested = await runTests(info.work, info.tests);
  const status = statusWord(inv.text);
  const cutShort = inv.kind !== 'ok';
  const detail = [
    `status=${status ?? 'none'}`,
    cutShort ? `cut=${inv.kind}` : '',
    tested.pass ? '' : `failed=${tested.failed}`,
    outside.length > 0 ? `outside=${outside.join(',')}` : '',
  ].filter(Boolean).join(' ');
  return { outcome: outcome({ testsPass: tested.pass, outside, status, cutShort }), detail };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const dir = process.argv[2] ? resolve(process.argv[2]) : null;
  if (!dir || !existsSync(join(dir, 'case.json'))) { console.error('usage: grade-case.mjs RUN_DIR'); process.exit(2); }
  const info = JSON.parse(readFileSync(join(dir, 'case.json'), 'utf8'));
  const inv = classify({ out: readFileSync(join(dir, 'output.json'), 'utf8'), err: '', code: 0, timedOut: false }, 0);
  const graded = await gradeImpl(info, inv);
  console.log(`${info.id}\t${graded.outcome}\t${graded.detail}`);
}
