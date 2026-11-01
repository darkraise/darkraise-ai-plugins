import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { lintText, lintTree } from '../scripts/lint-portability.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const MSYS = 'export MSYS_NO_PATHCONV=1';
const found = (file, lines) => lintText(file, lines.join('\n')).map(({ line, rule }) => ({ line, rule }));
const marked = (file, lines, at) => lines.map((line, index) => index === at ? `${line}  ${file.endsWith('.mjs') ? '//' : '#'} portability: ok — the fixture runs on Linux` : line);

// [rule, file, the file's lines, the 0-based index of the line that hits]
const hitRows = [
  ['git-c-pwd', 'a.sh', ['git -C "$PWD" status'], 0],
  ['git-c-pwd', 'a.sh', ['echo start', '  top=$(git -C "$(pwd)" rev-parse --show-toplevel)'], 1],
  ['git-c-pwd', 'a.sh', ['git -C $PWD log'], 0],
  ['awk-v-backslash', 'a.sh', [String.raw`awk -v re='a\.b' '$0 ~ re' file`], 0],
  ['awk-v-backslash', 'a.sh', [String.raw`awk -F'\t' -v pat="^\\[x\\]" '$0 ~ pat' file`], 0],
  ['import-path', 'a.mjs', ['const mod = await import(modulePath);'], 0],
  ['import-path', 'a.mjs', ["const mod = await import(resolve(root, 'lib/x.mjs'));"], 0],
  ['import-path', 'a.mjs', ['const mod = await import(`${dir}/x.mjs`);'], 0],
  ['import-path', 'a.mjs', ['const a = 1;', 'const mod = await import(', "  path.join(root, 'x.mjs')", ');'], 1],
  ['jq-pwd-file', 'a.sh', [MSYS, 'jq -r .name "$PWD/package.json"'], 1],
  ['jq-pwd-file', 'a.sh', [MSYS, 'jq -r .name "$(pwd)/package.json"'], 1],
  ['jq-pwd-file', 'a.sh', [MSYS, 'name=$(jq -r .name "$TMPDIR/package.json")'], 1],
  ['jq-pwd-file', 'a.sh', [MSYS, "cat x | jq '.a | .b' \"$PWD/p.json\""], 1],
];

test('each rule flags its fixture line, and a reasoned exemption on that line clears it', () => {
  for (const [rule, file, lines, at] of hitRows) {
    assert.deepEqual(found(file, lines), [{ line: at + 1, rule }], `${rule}: ${lines.join(' / ')}`);
    assert.deepEqual(found(file, marked(file, lines, at)), [], `${rule} exempt: ${lines.join(' / ')}`);
  }
});

test('a line that follows the safe form is not flagged', () => {
  const safe = [
    ['a.sh', ['git -C "$(dr_native_path "$PWD")" status']],
    ['a.sh', ['git -C "$REPO" status']],
    ['a.sh', ['awk -v n="$N" \'{ print n }\' file']],
    ['a.sh', ['RE=\'a\\.b\' awk \'$0 ~ ENVIRON["RE"]\' file']],
    ['a.sh', [String.raw`awk -F'\t' '{ print $1 }' file`]],
    ['a.sh', [String.raw`awk -v h="$(printf 'x' | tr -d '\r')" '{ print h }' file`]],
    ['a.sh', [String.raw`awk '/\./ { print }' file`]],
    ['a.mjs', ['const mod = await import(pathToFileURL(file).href);']],
    ['a.mjs', ["const fs = await import('node:fs');"]],
    ['a.mjs', ['const mod = await import("./local.mjs");']],
    ['a.mjs', ['const mod = await import(`./${name}.mjs`);']],
    ['a.mjs', ['const mod = await import(', '  pathToFileURL(path.join(root, "x.mjs")).href', ');']],
    ['a.sh', ['jq -r .name "$PWD/package.json"']],
    ['a.sh', [MSYS, 'jq -r .name < "$PWD/package.json"']],
    ['a.sh', [MSYS, 'jq -n --arg d "$PWD" \'$d\'']],
    ['a.sh', [MSYS, 'cat "$PWD/a.json" | jq -r .name']],
    ['a.sh', [MSYS, 'jq -r .name "$REPO/package.json"']],
  ];
  for (const [file, lines] of safe) assert.deepEqual(found(file, lines), [], lines.join(' / '));
});

test('an exemption needs its reason and covers only its own line', () => {
  assert.deepEqual(found('a.sh', ['git -C "$PWD" status  # portability: ok']), [{ line: 1, rule: 'git-c-pwd' }]);
  assert.deepEqual(found('a.sh', ['git -C "$PWD" status  # portability: ok —']), [{ line: 1, rule: 'git-c-pwd' }]);
  assert.deepEqual(found('a.sh', ['# portability: ok — reason', 'git -C "$PWD" status']), [{ line: 2, rule: 'git-c-pwd' }]);
  assert.deepEqual(lintText('a.sh', 'echo ok\r\ngit -C "$PWD" status\r\n').map(({ line }) => line), [2]);
  assert.deepEqual(lintText('a.sh', 'git -C "$PWD" status  # portability: ok — reason\r\n'), []);
});

function fixtureTree(files) {
  const dir = mkdtempSync(join(tmpdir(), 'lint-portability-'));
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  return dir;
}

test('the tree scan reads plugin scripts and tests and the repository scripts only', () => {
  const dir = fixtureTree({
    'plugins/p/scripts/x.sh': 'git -C "$PWD" status\n',
    'plugins/p/tests/y.test.sh': 'git -C "$PWD" status  # portability: ok — fixture\nawk -v a=\'\\.\' x\n',
    'scripts/z.mjs': 'await import(file);\n',
    'tests/v.test.mjs': 'await import(file);\n',
    'plugins/p/skills/s.sh': 'git -C "$PWD" status\n',
  });
  try {
    assert.deepEqual(lintTree(dir).map(line => line.split(' ').slice(0, 2).join(' ')).sort(), [
      'plugins/p/scripts/x.sh:1 git-c-pwd',
      'plugins/p/tests/y.test.sh:2 awk-v-backslash',
      'scripts/z.mjs:1 import-path',
    ]);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('the repository has no portability hit', () => {
  assert.deepEqual(lintTree(root), []);
});

test('the command prints a hit as file:line rule message and exits 1, and validate-repository fails on it', () => {
  const dir = fixtureTree({ 'plugins/p/scripts/x.sh': 'git -C "$PWD" status\n' });
  try {
    const lint = spawnSync(process.execPath, ['scripts/lint-portability.mjs', dir], { cwd: root, encoding: 'utf8', timeout: 20000 });
    assert.ifError(lint.error);
    assert.equal(lint.status, 1);
    assert.match(lint.stdout, /^plugins\/p\/scripts\/x\.sh:1 git-c-pwd \S/m);
    const validate = spawnSync(process.execPath, ['scripts/validate-repository.mjs', dir], { cwd: root, encoding: 'utf8', timeout: 20000 });
    assert.ifError(validate.error);
    assert.equal(validate.status, 1);
    assert.match(validate.stderr, /^plugins\/p\/scripts\/x\.sh:1 git-c-pwd \S/m);
  } finally { rmSync(dir, { recursive: true, force: true }); }
  const clean = fixtureTree({ 'plugins/p/scripts/x.sh': 'git -C "$PWD" status  # portability: ok — fixture\n' });
  try {
    const lint = spawnSync(process.execPath, ['scripts/lint-portability.mjs', clean], { cwd: root, encoding: 'utf8', timeout: 20000 });
    assert.ifError(lint.error);
    assert.equal(lint.status, 0);
    assert.equal(lint.stdout, '');
  } finally { rmSync(clean, { recursive: true, force: true }); }
});
