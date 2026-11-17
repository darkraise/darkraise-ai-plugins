import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { renamePath, renameText } from '../scripts/dagents-rename.mjs';

const script = fileURLToPath(new URL('../scripts/dagents-rename.mjs', import.meta.url));
const run = (args, input) => spawnSync(process.execPath, [script, ...args], { encoding: 'utf8', input, timeout: 30000 });

test('identifiers take their dagents form', () => {
  for (const [from, to] of [
    ['use dforge:brainstorming', 'use dagents:brainstorming'],
    ['docs/dforge/plans and .dforge/sdd', 'docs/dagents/plans and .dagents/sdd'],
    ['~/.dforge/config.json and ~/.claude/dforge/sessions', '~/.dagents/config.json and ~/.claude/dagents/sessions'],
    ['${DFORGE_BUDGET:-}', '${DAGENTS_BUDGET:-}'],
    ['DR_CODEX_SESSION_DIR=x', 'DAGENTS_CODEX_SESSION_DIR=x'],
    ['DR_TEST_BASH DR_TEST_ALL', 'DR_TEST_BASH DR_TEST_ALL'],
    ['DR_FORGE_DOCUMENT_STORE DR_SUPERPOWERS_JQ', 'DR_FORGE_DOCUMENT_STORE DR_SUPERPOWERS_JQ'],
    ['ADDR_X', 'ADDR_X'],
    ['DARKMEM_API_KEY DARKMEM_URL', 'DARKMEM_API_KEY DARKMEM_URL'],
    ['DARKMEM_SYNC_LOCK_WAIT_MS', 'DAGENTS_DARKMEM_SYNC_LOCK_WAIT_MS'],
    ['Dforge and DFORGE', 'Dagents and DAGENTS'],
    ['off by default since dforge 3.0', 'off by default since dforge 3.0'],
    ['tag dforge-v4.17.1, dforge v4', 'tag dforge-v4.17.1, dforge v4'],
    ['plugins/dforge/scripts', 'plugins/dagents/scripts'],
  ]) assert.equal(renameText(from), to, from);
});

test('path components take their dagents form', () => {
  assert.equal(renamePath('skills/using-dforge/SKILL.md'), 'skills/using-dagents/SKILL.md');
  assert.equal(renamePath('scripts/lib/dforge-dir.sh'), 'scripts/lib/dagents-dir.sh');
  assert.equal(renamePath('tests/plan-lint.test.sh'), 'tests/plan-lint.test.sh');
});

test('tree renames contents and paths in place and refuses a collision', t => {
  const dir = mkdtempSync(join(tmpdir(), 'rename-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'skills/using-dforge'), { recursive: true });
  mkdirSync(join(dir, 'scripts/lib'), { recursive: true });
  writeFileSync(join(dir, 'skills/using-dforge/SKILL.md'), 'name: using-dforge\n');
  writeFileSync(join(dir, 'scripts/dforge-path'), '. "$HERE/lib/dforge-dir.sh"\n');
  writeFileSync(join(dir, 'scripts/lib/dforge-dir.sh'), 'echo "${DFORGE_DOCS_ROOT:-docs/dforge}"\n');
  writeFileSync(join(dir, 'blob.bin'), Buffer.from('dforge\0dforge:x', 'binary'));
  const ok = run(['tree', dir]);
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(readFileSync(join(dir, 'skills/using-dagents/SKILL.md'), 'utf8'), 'name: using-dagents\n');
  assert.equal(readFileSync(join(dir, 'scripts/dagents-path'), 'utf8'), '. "$HERE/lib/dagents-dir.sh"\n');
  assert.equal(readFileSync(join(dir, 'scripts/lib/dagents-dir.sh'), 'utf8'), 'echo "${DAGENTS_DOCS_ROOT:-docs/dagents}"\n');
  assert.equal(existsSync(join(dir, 'skills/using-dforge')), false);
  assert.equal(readFileSync(join(dir, 'blob.bin'), 'binary'), 'dforge\0dforge:x', 'a file holding a NUL keeps its bytes');

  writeFileSync(join(dir, 'clash.sh'), 'echo "$DFORGE_LOCK_TENTHS $DR_LOCK_TENTHS"\n');
  const clash = run(['tree', dir]);
  assert.equal(clash.status, 1);
  assert.match(clash.stderr, /DFORGE_LOCK_TENTHS/);
  assert.match(clash.stderr, /DR_LOCK_TENTHS/);
});

test('patch translates paths and lines of a diff', () => {
  const diff = [
    'diff --git a/plugins/dforge/scripts/lib/roots.sh b/plugins/dforge/scripts/lib/roots.sh',
    '--- a/plugins/dforge/scripts/lib/roots.sh',
    '+++ b/plugins/dforge/scripts/lib/roots.sh',
    '@@ -1,2 +1,2 @@',
    ' . "$HERE/dforge-dir.sh"',
    '-echo "$DFORGE_DOCS_ROOT"',
    '+echo "${DFORGE_DOCS_ROOT:-docs/dforge}"',
    '',
  ].join('\n');
  const out = run(['patch'], diff);
  assert.equal(out.status, 0, out.stderr);
  assert.equal(out.stdout, [
    'diff --git a/plugins/dagents/scripts/lib/roots.sh b/plugins/dagents/scripts/lib/roots.sh',
    '--- a/plugins/dagents/scripts/lib/roots.sh',
    '+++ b/plugins/dagents/scripts/lib/roots.sh',
    '@@ -1,2 +1,2 @@',
    ' . "$HERE/dagents-dir.sh"',
    '-echo "$DAGENTS_DOCS_ROOT"',
    '+echo "${DAGENTS_DOCS_ROOT:-docs/dagents}"',
    '',
  ].join('\n'));
});
