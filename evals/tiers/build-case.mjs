#!/usr/bin/env node
// Build the snapshot, the brief and the prompt for one case.
// Usage: node evals/tiers/build-case.mjs CASE_ID DIR
// Exit: 0 built; 2 usage or no such case.
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DATA, PLUGIN, git } from './lib/sh.mjs';
import { MANIFEST, brief, readManifest } from './lib/cases.mjs';
import { filesBlock, tasks, taskText } from './lib/plan.mjs';
import { fill, template } from './lib/prompt.mjs';
import { snapshot } from './lib/snapshot.mjs';
import { MARKER, addedLines, strip } from './lib/strip.mjs';

const IMPLEMENTER = resolve(PLUGIN, 'skills/subagent-driven-development/references/implementer-prompt.md');
const CODE_REVIEWER = resolve(PLUGIN, 'skills/requesting-code-review/references/code-reviewer.md');
const PLAN_REVIEWER = resolve(PLUGIN, 'skills/writing-plans/references/plan-reviewer-prompt.md');
const SCRATCH = '.superpowers/sdd/eval';

export function reviewCases() {
  const file = resolve(DATA, 'cases/reviews/cases.json');
  return existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : [];
}

// buildCase CASE DIR — an implementation case: DIR/work is the base commit's
// snapshot, holding the brief where production puts it. A stripped case loses
// docs/superpowers, so the plan's code cannot be read from disk.
export function buildCase(c, dir) {
  const stripped = c.pool === 'stripped';
  const work = join(dir, 'work');
  const initial = snapshot(c.base, work, stripped ? ['docs/superpowers'] : []);
  const planDir = join(dir, 'plan');
  let text = brief(c, planDir);
  if (stripped) text = strip(text, addedLines(c.base, c.result)).text;
  const planFile = join(planDir, 'plan.md');
  const { allowed, tests } = filesBlock(taskText(planFile, c.task));
  const title = tasks(planFile).find(t => t.n === c.task).title;
  mkdirSync(join(work, SCRATCH), { recursive: true });
  const briefFile = join(work, SCRATCH, `task-${c.task}-brief.md`);
  writeFileSync(briefFile, text);
  let context = `This is Task ${c.task} of the plan ${basename(c.plan)}. The tasks before it are already in this repository; the tasks after it are not your concern.`;
  if (stripped) context += ` This brief gives the prose, the signatures and the tests, but not the implementation code: wherever it shows "${MARKER}", write that code yourself. The plan file is not available.`;
  const prompt = fill(template(IMPLEMENTER), {
    'Task N: [task name]': `Task ${c.task}: ${title}`,
    '[BRIEF_FILE]': briefFile,
    '[Scene-setting: where this fits, dependencies, architectural context]': context,
    '[directory]': work,
    '[REPORT_FILE]': join(work, SCRATCH, `task-${c.task}-report.md`),
  });
  const info = { id: c.id, kind: 'impl', work, initial, result: c.result, allowed, tests };
  writeFileSync(join(dir, 'case.json'), JSON.stringify(info, null, 2) + '\n');
  return { info, prompt };
}

// buildReview CASE DIR — a review case. A code case snapshots the head commit
// and hands the reviewer one diff file for base..head. A plan case snapshots
// the plan's commit and strips the plan's first Plan review line, so the
// reviewer does not see an earlier verdict.
export function buildReview(c, dir) {
  const work = join(dir, 'work');
  const scratch = join(work, SCRATCH);
  let prompt;
  if (c.kind === 'code') {
    snapshot(c.head, work);
    mkdirSync(scratch, { recursive: true });
    const diffFile = join(scratch, 'review.diff');
    writeFileSync(diffFile, [
      git(['log', '--oneline', `${c.base}..${c.head}`]),
      git(['diff', '--stat', c.base, c.head]),
      git(['diff', c.base, c.head]),
    ].join('\n'));
    prompt = fill(template(CODE_REVIEWER), {
      '[DESCRIPTION]': c.description,
      '[PLAN_OR_REQUIREMENTS]': `The plan this branch implements: ${join(work, c.plan)}`,
      '[DIFF_FILE]': diffFile,
      '[BASE_SHA]': c.base.slice(0, 7),
      '[HEAD_SHA]': c.head.slice(0, 7),
    });
  } else {
    snapshot(c.commit, work);
    mkdirSync(join(scratch, 'plugin/criteria'), { recursive: true });
    const planFile = join(work, c.plan);
    const lines = readFileSync(planFile, 'utf8').split('\n');
    const reviewed = lines.findIndex(l => l.startsWith('**Plan review:**'));
    if (reviewed >= 0) lines.splice(reviewed, 1);
    writeFileSync(planFile, lines.join('\n'));
    if (!existsSync(join(work, c.spec))) throw new Error(`${c.id}: ${c.spec} is missing at ${c.commit}`);
    copyFileSync(resolve(PLUGIN, 'criteria/plan-review.md'), join(scratch, 'plugin/criteria/plan-review.md'));
    const lintFile = join(scratch, 'plan-lint.txt');
    writeFileSync(lintFile, 'plan-lint was not run for this replay.\n');
    prompt = fill(template(PLAN_REVIEWER), {
      '[PLAN_FILE]': planFile,
      '[SPEC_FILE]': join(work, c.spec),
      '[LINT_FILE]': lintFile,
      '[PLUGIN_ROOT]': join(scratch, 'plugin'),
    });
  }
  const info = { id: c.id, kind: 'review', work };
  writeFileSync(join(dir, 'case.json'), JSON.stringify(info, null, 2) + '\n');
  return { info, prompt };
}

// findCase ID — the manifest row or the review case with that id.
export function findCase(id) {
  const cases = existsSync(MANIFEST) ? readManifest().cases : [];
  return cases.find(c => c.id === id) ?? reviewCases().find(c => c.id === id) ?? null;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [id, dir] = process.argv.slice(2);
  const c = id && dir ? findCase(id) : null;
  if (!c) { console.error('usage: build-case.mjs CASE_ID DIR (CASE_ID from the manifest or cases/reviews/cases.json)'); process.exit(2); }
  const built = c.pool ? buildCase(c, resolve(dir)) : buildReview(c, resolve(dir));
  writeFileSync(join(resolve(dir), 'prompt.txt'), built.prompt);
  console.log(`build-case: ${id} in ${dirname(built.info.work)}`);
}
