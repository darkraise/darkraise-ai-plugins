import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { delimiter, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const PROFILE = join(ROOT, 'plugins/dforge/scripts/test-profile');
// Without claude on PATH test-all adds no `claude plugin test` job to the scratch tree.
const PATH = process.env.PATH.split(delimiter).filter(dir => !['claude', 'claude.exe', 'claude.cmd'].some(name => existsSync(join(dir, name)))).join(delimiter);

function tree(t) {
  const dir = mkdtempSync(join(tmpdir(), 'test-all-junit-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'scripts'));
  mkdirSync(join(dir, 'tests/dagents'), { recursive: true });
  for (const file of ['test-all.mjs', 'test-shards.mjs']) cpSync(join(ROOT, 'scripts', file), join(dir, 'scripts', file));
  writeFileSync(join(dir, 'tests/dagents/alpha.test.sh'), [
    'sleep 1', "echo 'ok   - first check'", 'sleep 1', "echo 'FAIL - second check: got [a], want [b]'",
    `echo 'ok - third <check> & "quoted"'`, 'exit 1', '',
  ].join('\n'));
  writeFileSync(join(dir, 'tests/dagents/beta.test.sh'), 'echo plain output\n');
  return dir;
}
const run = (dir, ...args) => spawnSync(process.execPath, ['scripts/test-all.mjs', '--plugin', 'dagents', ...args], { cwd: dir, encoding: 'utf8', env: { ...process.env, PATH }, timeout: 120000 });
const cases = xml => [...xml.matchAll(/<testcase\b([^>]*)>/g)].map(match => Object.fromEntries([...match[1].matchAll(/(\w+)="([^"]*)"/g)].map(m => [m[1], m[2]])));

for (const jobs of ['1', '2']) {
  test(`--junit writes one timed file per job (--jobs ${jobs})`, t => {
    const dir = tree(t);
    const r = run(dir, '--jobs', jobs, '--junit', 'junit');
    assert.equal(r.status, 1, 'alpha fails');
    assert.deepEqual(readdirSync(join(dir, 'junit')).sort(), ['tests-dagents-alpha.test.sh.xml', 'tests-dagents-beta.test.sh.xml']);
    const alpha = readFileSync(join(dir, 'junit/tests-dagents-alpha.test.sh.xml'), 'utf8');
    const rows = cases(alpha);
    assert.deepEqual(rows.map(row => row.name), ['first check', 'second check: got [a], want [b]', 'third &lt;check&gt; &amp; &quot;quoted&quot;']);
    assert.ok(rows.every(row => row.file === 'tests/dagents/alpha.test.sh' && row.classname === 'tests/dagents/alpha.test.sh'));
    assert.equal((alpha.match(/<failure\b/g) ?? []).length, 1);
    const suite = Number(/<testsuite\b[^>]*\btime="([\d.]+)"/.exec(alpha)[1]);
    const sum = rows.reduce((total, row) => total + Number(row.time), 0);
    assert.ok(Number(rows[1].time) >= 0.9, 'a case is timed from the previous line');
    assert.ok(suite - sum >= 0.9, 'the time before the first line is no case');
    assert.equal(cases(readFileSync(join(dir, 'junit/tests-dagents-beta.test.sh.xml'), 'utf8')).length, 1);
    const profile = spawnSync('bash', [PROFILE, join(dir, 'junit')], { encoding: 'utf8' });
    assert.equal(profile.status, 0, profile.stderr);
    assert.match(profile.stdout, /tests\/dagents\/alpha\.test\.sh/);
    const brief = spawnSync('bash', [PROFILE, '--brief', join(dir, 'junit')], { encoding: 'utf8' });
    assert.equal(brief.status, 0, brief.stderr);
    assert.match(brief.stdout, /\boverhead=(?:0\.9|[1-9]\d*\.\d)s /, 'the time before alpha\'s first line is reported as overhead');
  });
}

test('without --junit the output and exit status are unchanged', t => {
  const dir = tree(t);
  for (const jobs of ['1', '2']) {
    const r = run(dir, '--jobs', jobs);
    assert.equal(r.status, 1);
    assert.match(r.stdout, /^Running tests\/dagents\/alpha\.test\.sh$/m);
    assert.match(r.stdout, /^ok {3}- first check$/m);
    assert.match(r.stdout, /^Finished tests\/dagents\/alpha\.test\.sh in [\d.]+s \(exit 1\)$/m);
    assert.equal(existsSync(join(dir, 'junit')), false);
  }
});
