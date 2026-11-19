import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { emptyBoard } from '../board.mjs';
import { relative } from '../repo.mjs';
import { fail, readJson, readText, writeJson } from '../util.mjs';

const PROJECT = name => `# ${name}

## What it is

…

## Module map

…

## Run and verify

…
`;
const DECISIONS = '# Decisions\n\nAppend-only. Each entry states the decision, the reason and what it supersedes.\n';
const GOTCHAS = '# Gotchas\n\nSymptom first. Delete an entry when its cause is fixed.\n';

export async function run(ctx, argv, { out }) {
  const { values } = parseArgs({ args: argv, options: { gate:{ type: 'string', multiple: true } } });
  if (Number(process.versions.node.split('.')[0]) < 20) fail(`Node ${process.versions.node} is too old; dflow needs Node 20 or later`);
  const { paths, root } = ctx;
  const created = [];
  const write = (file, text) => {
    if (fs.existsSync(file)) return;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
    created.push(relative(root, file));
  };
  const name = path.basename(root);
  write(path.join(paths.docs, 'project.md'), PROJECT(name));
  write(path.join(paths.docs, 'decisions.md'), DECISIONS);
  write(path.join(paths.docs, 'gotchas.md'), GOTCHAS);
  write(paths.board, emptyBoard(`${name} board`));
  fs.mkdirSync(paths.plans, { recursive: true });

  const config = readJson(paths.config, null) ?? { gates: [] };
  config.gates ??= [];
  for (const gate of values.gate ?? []) {
    const at = gate.indexOf('=');
    if (at < 1) fail(`--gate takes name=command, got ${JSON.stringify(gate)}`);
    const entry = { name: gate.slice(0, at), cmd: gate.slice(at + 1) };
    config.gates = [...(config.gates ?? []).filter(existing => existing.name !== entry.name), entry];
  }
  if (!fs.existsSync(paths.config)) created.push(relative(root, paths.config));
  writeJson(paths.config, config);

  const ignoreFile = path.join(root, '.gitignore');
  const ignore = readText(ignoreFile) ?? '';
  if (!ignore.split(/\r?\n/).some(line => line.trim() === '.dflow/' || line.trim() === '.dflow')) {
    fs.writeFileSync(ignoreFile, `${ignore}${ignore && !ignore.endsWith('\n') ? '\n' : ''}.dflow/\n`);
    created.push('.gitignore (.dflow/ ignored)');
  }

  // decisions.md and gotchas.md only grow at the end, so two branches that
  // each add entries would conflict there; the union driver keeps both.
  const attributesFile = path.join(root, '.gitattributes');
  const attributes = readText(attributesFile) ?? '';
  const union = ['docs/dflow/decisions.md merge=union', 'docs/dflow/gotchas.md merge=union'].filter(line => !attributes.split(/\r?\n/).some(existing => existing.trim() === line));
  if (union.length) {
    fs.writeFileSync(attributesFile, `${attributes}${attributes && !attributes.endsWith('\n') ? '\n' : ''}${union.join('\n')}\n`);
    created.push('.gitattributes (decisions.md and gotchas.md merge by union)');
  }

  out(created.length ? `dflow init: created ${created.join(', ')}` : 'dflow init: already set up; nothing created');
  if (!config.gates.length) out('No gates configured: add them with `dflow init --gate "test=<command>"` (lint, type check, full suite, build).');
  return 0;
}
