import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

// Acceptance tests for docs/dforge/specs/2026-11-27-review-3c81c7d6-fixes-design.md,
// statement A10: scripts/lint-portability.mjs, run by scripts/validate-repository.mjs,
// fails on the bash 4 constructs in a shipped shell file. Each test runs the
// command line tools against a throwaway tree.

const repo = fileURLToPath(new URL('../', import.meta.url));
const LINT = join(repo, 'scripts', 'lint-portability.mjs');
const VALIDATE = join(repo, 'scripts', 'validate-repository.mjs');
const made = [];
process.on('exit', () => { for (const dir of made) rmSync(dir, { recursive: true, force: true }); });

function tree(files) {
  const root = mkdtempSync(join(tmpdir(), 'a10-'));
  made.push(root);
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  }
  return root;
}
const node = (...args) => spawnSync(process.execPath, args, { encoding: 'utf8', timeout: 60000, env: { ...process.env, NODE_TEST_CONTEXT: '' } });
const lint = root => node(LINT, root);

const CONSTRUCTS = [
  ['mapfile', 'mapfile -t lines < input.txt'],
  ['readarray', 'readarray -t lines < input.txt'],
  ['$BASHPID', 'echo "pid $BASHPID"'],
  ['${var,,}', 'lower=${name,,}'],
  ['${var^^}', 'upper=${name^^}'],
  ['declare -A', 'declare -A table'],
];
const SHIPPED = [
  ['a script named .sh', 'plugins/demo/scripts/run.sh', '#!/usr/bin/env bash\nset -u\n'],
  ['a script in a scripts subdirectory', 'plugins/demo/scripts/lib/util.sh', '# helpers\n'],
  ['a script with a bash shebang and no extension', 'plugins/demo/scripts/tool', '#!/usr/bin/env bash\nset -u\n'],
  ['a script with a sh shebang and no extension', 'plugins/demo/scripts/tool2', '#!/bin/sh\n'],
  ['a skill helper .sh', 'plugins/demo/skills/thing/helper.sh', '#!/usr/bin/env bash\n'],
  ['a skill helper .sh in a subdirectory', 'plugins/demo/skills/thing/sub/deep.sh', '#!/usr/bin/env bash\n'],
];

for (const [construct, line] of CONSTRUCTS) {
  for (const [kind, path, head] of SHIPPED) {
    test(`A10: ${construct} on a code line of ${kind} fails the lint`, () => {
      const root = tree({ [path]: `${head}${line}\n` });
      const result = lint(root);
      assert.equal(result.status, 1, `exit ${result.status}: ${result.stdout}${result.stderr}`);
      assert.ok(result.stdout.includes(path), `the output does not name ${path}: ${result.stdout}`);
    });
  }

  test(`A10: ${construct} after other code on a line ending in a comment still fails the lint`, () => {
    const path = 'plugins/demo/scripts/run.sh';
    const root = tree({ [path]: `#!/usr/bin/env bash\n  ${line} # trailing note\n` });
    assert.equal(lint(root).status, 1);
  });

  test(`A10: ${construct} on a line whose first non-blank character is # does not fail the lint`, () => {
    const root = tree({
      'plugins/demo/scripts/run.sh': `#!/usr/bin/env bash\n# ${line}\n    # ${line}\n\t#${line}\n`,
      'plugins/demo/skills/thing/helper.sh': `#!/usr/bin/env bash\n# ${line}\n`,
    });
    const result = lint(root);
    assert.equal(result.status, 0, `exit ${result.status}: ${result.stdout}${result.stderr}`);
  });

  test(`A10: ${construct} in a file that is not a shipped shell file does not fail the lint`, () => {
    const root = tree({
      'plugins/demo/scripts/tool.mjs': `// ${line}\nconst s = ${JSON.stringify(line)};\n`,
      'plugins/demo/scripts/node-tool': `#!/usr/bin/env node\nconst s = ${JSON.stringify(line)};\n`,
      'plugins/demo/scripts/py-tool': `#!/usr/bin/env python3\ns = ${JSON.stringify(line)}\n`,
      'plugins/demo/skills/thing/SKILL.md': `Use \`${line}\` carefully.\n`,
      'plugins/demo/skills/thing/notes.txt': `${line}\n`,
    });
    const result = lint(root);
    assert.equal(result.status, 0, `exit ${result.status}: ${result.stdout}${result.stderr}`);
  });
}

test('A10: a shipped shell file with none of the constructs passes the lint', () => {
  const root = tree({
    'plugins/demo/scripts/run.sh': '#!/usr/bin/env bash\nset -euo pipefail\nwhile IFS= read -r l; do echo "$l"; done < in.txt\nlower=$(printf %s "$n" | tr A-Z a-z)\n',
    'plugins/demo/skills/thing/helper.sh': '#!/usr/bin/env bash\necho ok\n',
  });
  const result = lint(root);
  assert.equal(result.status, 0, `exit ${result.status}: ${result.stdout}${result.stderr}`);
});

test('A10: the lint passes on the branch head', () => {
  const result = lint(repo);
  assert.equal(result.status, 0, `exit ${result.status}: ${result.stdout}${result.stderr}`);
});

// validate-repository.mjs reads the whole repository, so the tests below run it
// against a copy of the committed tree.
function repositoryCopy() {
  const root = mkdtempSync(join(tmpdir(), 'a10-repo-'));
  made.push(root);
  const archive = spawnSync('git', ['-C', repo, 'archive', 'HEAD'], { maxBuffer: 256 * 1024 * 1024, timeout: 60000 });
  assert.equal(archive.status, 0, String(archive.stderr));
  const extract = spawnSync('tar', ['-x', '-C', root], { input: archive.stdout, timeout: 60000 });
  assert.equal(extract.status, 0, String(extract.stderr));
  return root;
}

test('A10: validate-repository passes on a copy of the branch head', () => {
  const root = repositoryCopy();
  const result = node(join(root, 'scripts', 'validate-repository.mjs'), root);
  assert.equal(result.status, 0, `exit ${result.status}: ${result.stdout}${result.stderr}`);
});

for (const [construct, line] of CONSTRUCTS) {
  test(`A10: validate-repository fails on ${construct} added to a shipped script of the branch head`, () => {
    const root = repositoryCopy();
    const path = 'plugins/dforge/scripts/with-timeout';
    writeFileSync(join(root, path), `${spawnSync('cat', [join(root, path)], { encoding: 'utf8' }).stdout}\n${line}\n`);
    const result = node(join(root, 'scripts', 'validate-repository.mjs'), root);
    assert.equal(result.status, 1, `exit ${result.status}: ${result.stdout}${result.stderr}`);
    assert.ok(`${result.stdout}${result.stderr}`.includes(path), `the output does not name ${path}: ${result.stdout}${result.stderr}`);
  });
}
