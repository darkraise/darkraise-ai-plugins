#!/usr/bin/env node
// Choose the 12 cases of the pipeline stage from the finished plans listed in
// docs/dforge/plans/completed.md and write cases/pipeline.tsv. Every case is
// golden-checked first: its hidden tests fail at the base commit and pass at
// the result commit. Tasks that needed fix rounds come first.
// Usage: node evals/tiers/build-pipeline-manifest.mjs
// Exit: 0 written; 1 fewer than 12 usable cases.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { DATA, ROOT, git } from './lib/sh.mjs';
import { golden } from './lib/cases.mjs';
import { PIPELINE_CASES, finishedPlans, manifestText, pickCases, pipelineCandidates } from './lib/pipeline-manifest.mjs';

const JOBS = 6;
const MANIFEST = resolve(DATA, 'cases/pipeline.tsv');
const start = git(['rev-parse', 'HEAD']).trim();
const done = finishedPlans(readFileSync(resolve(ROOT, 'docs/dforge/plans/completed.md'), 'utf8'));
const queue = pipelineCandidates(start, done);
const total = queue.length;
const usable = [];
await Promise.all(Array.from({ length: JOBS }, async () => {
  for (let c = queue.shift(); c; c = queue.shift()) {
    if (await golden(c) === null) usable.push(c);
  }
}));
const picked = pickCases(usable);
if (picked.length < PIPELINE_CASES) {
  console.error(`build-pipeline-manifest: ${picked.length} usable cases of ${total}, need ${PIPELINE_CASES}`);
  process.exit(1);
}
mkdirSync(dirname(MANIFEST), { recursive: true });
writeFileSync(MANIFEST, manifestText(picked));
console.log(`build-pipeline-manifest: ${picked.length} cases (${picked.filter(c => c.fixRounds > 0).length} with a fix round) from ${usable.length} usable of ${total}`);
