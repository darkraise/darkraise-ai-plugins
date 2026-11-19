import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { RUN_TITLES } from '../scripts/ci-scope.mjs';

const yml = readFileSync(new URL('../.github/workflows/validate.yml', import.meta.url), 'utf8');
const job = name => new RegExp(`\\n  ${name}:\\n((?:    .*\\n|\\n)+)`).exec(yml)?.[1] ?? '';
const needsOf = name => {
  const m = /^ {4}needs: (?:\[([^\]]*)\]|([\w-]+))$/m.exec(job(name));
  return m ? (m[1] ?? m[2]).split(',').map(need => need.trim()).filter(Boolean) : [];
};
const JOBS = ['scope', 'homelab', 'validate', 'dagents-changes', 'validate-dagents', 'windows', 'windows-dagents', 'release'];

test('every job exists and needs scope', () => {
  for (const name of JOBS) assert.ok(job(name), name);
  for (const name of JOBS.filter(name => name !== 'scope')) assert.ok(needsOf(name).includes('scope'), `${name} needs scope`);
  assert.deepEqual([...needsOf('release')].sort(), JOBS.filter(name => name !== 'release').sort(), 'release needs every other job');
});

test('the run title carries the scope literal ci-scope looks up', () => {
  const runName = /^run-name: (.*)$/m.exec(yml)?.[1] ?? '';
  for (const title of Object.values(RUN_TITLES)) {
    const [prefix, scope] = /^(.*) \((\w+)\)$/.exec(title).slice(1);
    assert.ok(runName.startsWith(`${prefix} (`), 'prefix');
    assert.ok(runName.includes(`'${scope}'`), scope);
  }
});

test('a nightly schedule and a scope input', () => {
  assert.match(yml, /schedule:\n\s+- cron: '17 19 \* \* \*'/);
  assert.match(yml, /\n {6}scope:\n(?: {8}.*\n)*? {8}options: \[slice, full\]\n(?: {8}.*\n)*? {8}default: full/);
});

test('the scope job decides with actions read', () => {
  assert.match(job('scope'), /actions: read/);
  assert.match(job('scope'), /node scripts\/ci-scope\.mjs plan/);
  for (const output of ['scope', 'run', 'windows']) assert.match(job('scope'), new RegExp(`${output}: \\$\\{\\{ steps\\.\\w+\\.outputs\\.${output} \\}\\}`));
});

test('the fallback re-dispatch keeps the scope and the base', () => {
  assert.match(job('homelab'), /gh workflow run validate\.yml[^\n]*-f scope=/);
  assert.match(job('homelab'), /gh workflow run validate\.yml[^\n]*-f from=/);
});

test('the Windows jobs wait for homelab and follow the scope', () => {
  for (const name of ['windows', 'windows-dagents']) {
    assert.match(job(name), /needs:[^\n]*homelab/, name);
    assert.match(job(name), /contains\(fromJSON\('\["success","skipped"\]'\), needs\.homelab\.result\)/, name);
  }
  assert.match(job('windows'), /matrix:\n\s+shard: \$\{\{ fromJSON\(needs\.scope\.outputs\.windows\) \}\}/);
  assert.match(job('windows'), /--slice/);
  assert.match(job('windows-dagents'), /needs\.scope\.outputs\.scope == 'full'/);
});

test('full-scope Windows jobs upload their timing per shard unless cancelled', () => {
  for (const name of ['windows', 'windows-dagents']) {
    const block = job(name);
    assert.match(block, /--junit/, name);
    assert.match(block, /actions\/upload-artifact@v4/, name);
    assert.match(block, /name: junit-[\w-]*\$\{\{ matrix\.shard \}\}/, name);
    assert.match(block, /if: \$\{\{ !cancelled\(\) && needs\.scope\.outputs\.scope == 'full' \}\}/, name);
    assert.match(block, /retention-days: 14/, name);
  }
});

test('the release job needs every job and dispatches through ci-scope', () => {
  const block = job('release');
  for (const name of JOBS.filter(name => name !== 'release')) assert.match(block, new RegExp(`needs:.*\\b${name}\\b`, 's'), name);
  assert.match(block, /if: \$\{\{ !cancelled\(\) \}\}/);
  assert.match(block, /actions: write/);
  assert.match(block, /node scripts\/ci-scope\.mjs release/);
  assert.match(block, /NEEDS: \$\{\{ toJSON\(needs\) \}\}/);
  assert.match(block, /gh workflow run release\.yml --repo "\$GITHUB_REPOSITORY" --ref main -f validated="?\$GITHUB_SHA"?/);
});
