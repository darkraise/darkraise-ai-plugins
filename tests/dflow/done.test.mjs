import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { parseBoard } from '../../plugins/dflow/lib/board.mjs';
import { parsePlan } from '../../plugins/dflow/lib/plan.mjs';
import { PLAN, PLAN_FILE, dflow, git, makeProject, read, write } from './helpers.mjs';

const PASS = 'process.exit(0)\n';
const FAIL = 'console.log("line one"); console.error("expected 5, got 4"); process.exit(3)\n';

function stageTask1(root, verify = PASS) {
  write(root, 'verify1.mjs', verify);
  write(root, 'src/limit.mjs', 'export const parseLimit = () => null;\n');
  write(root, 'tests/limit.test.mjs', 'assert(parseLimit() === null);\n');
  // A new test file is not a weakened one, whatever its text holds.
  write(root, 'tests/fixture.test.mjs', 'const sample = \'it.skip("x", () => {})\';\n');
  git(root, 'add', 'src', 'tests');
}

test('a failing verify changes nothing and counts the attempt; the third prints the choice', t => {
  const root = makeProject(t);
  stageTask1(root, FAIL);
  const before = git(root, 'rev-parse', 'HEAD');
  const first = dflow(root, ['done', '1', '-m', 'feat: parse']);
  assert.equal(first.status, 1);
  assert.match(first.stdout, /Task 1 verify failed \(attempt 1\): `node verify1\.mjs` exited 3/);
  assert.match(first.stdout, /expected 5, got 4/);
  assert.match(first.stdout, /Full log: \.dflow\/logs\/2026-11-12-meter\/task-1\.log/);
  assert.doesNotMatch(first.stdout, /Three verify failures/);
  assert.equal(git(root, 'rev-parse', 'HEAD'), before);
  assert.equal(parsePlan(read(root, PLAN_FILE)).tasks[0].done, false);
  assert.match(read(root, '.dflow/logs/2026-11-12-meter/task-1.log'), /line one/);

  dflow(root, ['done', '1', '-m', 'feat: parse']);
  const third = dflow(root, ['done', '1', '-m', 'feat: parse']);
  assert.match(third.stdout, /attempt 3/);
  assert.match(third.stdout, /Three verify failures on this task/);
  assert.match(third.stdout, /dflow block 1 "<reason>"/);
  assert.equal(JSON.parse(dflow(root, ['status', '--json']).stdout).plan.current.attempts, 3);
});

test('a passing verify ticks the task, commits code with plan and board, and prints the next brief', t => {
  const root = makeProject(t);
  stageTask1(root);
  const done = dflow(root, ['done', '1', '-m', 'feat(meter): parse limit header']);
  assert.equal(done.status, 0, done.stderr + done.stdout);
  assert.match(done.stdout, /^Task 1 done · [0-9a-f]{7} · 1\/2/);
  assert.match(done.stdout, /### Task 2: Draw the meter/);
  assert.doesNotMatch(done.stdout, /## Design/);
  assert.equal(git(root, 'log', '-1', '--format=%s'), 'feat(meter): parse limit header');
  assert.deepEqual(git(root, 'show', '--name-only', '--format=', 'HEAD').split('\n').sort(), ['docs/dflow/board.md', PLAN_FILE, 'src/limit.mjs', 'tests/fixture.test.mjs', 'tests/limit.test.mjs']);
  const plan = parsePlan(read(root, PLAN_FILE));
  assert.deepEqual(plan.tasks.map(task => task.done), [true, false]);
  assert.equal(parseBoard(read(root, 'docs/dflow/board.md')).rows[0].state, 'doing');
  assert.equal(dflow(root, ['done', '1', '-m', 'x']).status, 1);

  write(root, 'verify2.mjs', PASS);
  write(root, 'src/meter.mjs', 'export const drawMeter = () => "";\n');
  git(root, 'add', 'src');
  const last = dflow(root, ['done', '2', '-m', 'feat(meter): draw']);
  assert.match(last.stdout, /Every task is done\. Next: \/dflow:review/);
  const row = parseBoard(read(root, 'docs/dflow/board.md')).rows[0];
  assert.deepEqual([row.state, row.note], ['verify', 'all 2 tasks done 2026-11-12']);
  assert.equal(git(root, 'status', '--porcelain', '--untracked-files=no'), '');
});

test('done refuses out of order, with nothing staged, and with unstaged task files', t => {
  const root = makeProject(t);
  assert.match(dflow(root, ['done', '2', '-m', 'x']).stderr, /Task 2 waits on Task 1/);
  write(root, 'verify1.mjs', PASS);
  assert.match(dflow(root, ['done', '1', '-m', 'x']).stderr, /nothing is staged/);
  stageTask1(root);
  write(root, 'src/limit.mjs', 'export const parseLimit = () => 1;\n');
  write(root, 'notes with space.txt', 'scratch\n');
  const refused = dflow(root, ['done', '1', '-m', 'x']).stderr;
  assert.match(refused, /the verified tree would not be the committed one: src\/limit\.mjs, notes with space\.txt/);
});

test('files outside the task stop done until explained, and the reason is logged', t => {
  const root = makeProject(t);
  stageTask1(root);
  write(root, 'other.mjs', '1\n');
  git(root, 'add', 'other.mjs');
  const refused = dflow(root, ['done', '1', '-m', 'feat: parse']);
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /outside Task 1's Files: other\.mjs/);
  const accepted = dflow(root, ['done', '1', '-m', 'feat: parse', '--extra', 'shared constant the parser needs']);
  assert.equal(accepted.status, 0, accepted.stderr);
  assert.deepEqual(parsePlan(read(root, PLAN_FILE)).log.map(entry => [entry.task, entry.kind, entry.text]), [[1, 'X', 'other.mjs — shared constant the parser needs']]);
});

test('a deleted or weakened test stops done until explained', t => {
  const root = makeProject(t);
  stageTask1(root);
  dflow(root, ['done', '1', '-m', 'feat: parse']);
  write(root, 'verify2.mjs', PASS);
  write(root, 'src/meter.mjs', '1\n');
  write(root, 'tests/limit.test.mjs', 'it.skip("parses", () => {});\n');
  git(root, 'add', 'src', 'tests');
  const refused = dflow(root, ['done', '2', '-m', 'feat: draw', '--extra', 'test touched']);
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /tests\/limit\.test\.mjs: a skip marker was added/);
  assert.match(refused.stderr, /1 more assertion line\(s\) removed than added/);
  git(root, 'rm', '-q', '--cached', 'tests/limit.test.mjs');
  fs.rmSync(path.join(root, 'tests/limit.test.mjs'));
  git(root, 'add', '-A', 'tests');
  assert.match(dflow(root, ['done', '2', '-m', 'feat: draw', '--extra', 'x']).stderr, /test file deleted/);
  const accepted = dflow(root, ['done', '2', '-m', 'feat: draw', '--extra', 'x', '--weaken', 'the parser moved into the meter']);
  assert.equal(accepted.status, 0, accepted.stderr);
  assert.ok(parsePlan(read(root, PLAN_FILE)).log.some(entry => entry.kind === 'W' && /parser moved/.test(entry.text)));
});

test('a verify line edited by hand stops done; amend changes it with a logged reason', t => {
  const root = makeProject(t);
  stageTask1(root);
  write(root, PLAN_FILE, read(root, PLAN_FILE).replace('`node verify1.mjs`', '`true`'));
  assert.match(dflow(root, ['done', '1', '-m', 'x']).stderr, /differs from the approved plan/);
  write(root, PLAN_FILE, read(root, PLAN_FILE).replace('`true`', '`node verify1.mjs`'));
  const amended = dflow(root, ['amend', '1', '--verify', 'node verify1.mjs --strict', '--reason', 'the flag is required']);
  assert.equal(amended.status, 0, amended.stderr);
  const plan = parsePlan(read(root, PLAN_FILE));
  assert.deepEqual(plan.tasks[0].verify, ['node verify1.mjs --strict']);
  assert.equal(plan.log[0].text, 'verify is now `node verify1.mjs --strict`, was `node verify1.mjs` — the flag is required');
  // One logged amendment does not excuse a later edit by hand.
  write(root, PLAN_FILE, read(root, PLAN_FILE).replace('- [ ] Verify: `node verify1.mjs --strict`', '- [ ] Verify: `true`'));
  assert.match(dflow(root, ['done', '1', '-m', 'x']).stderr, /no log line names the current command/);
  write(root, PLAN_FILE, read(root, PLAN_FILE).replace('- [ ] Verify: `true`', '- [ ] Verify: `node verify1.mjs --strict`'));
  assert.equal(dflow(root, ['done', '1', '-m', 'feat: parse']).status, 0);
});

test('a verify command amended with a run of spaces passes the gate; one with a newline is refused', t => {
  const root = makeProject(t);
  stageTask1(root);
  assert.match(dflow(root, ['amend', '1', '--verify', 'node verify1.mjs\nnode verify2.mjs', '--reason', 'two steps']).stderr, /a verify command is one line/);
  assert.equal(dflow(root, ['amend', '1', '--verify', 'node  verify1.mjs', '--reason', 'two spaces']).status, 0);
  const done = dflow(root, ['done', '1', '-m', 'feat: parse']);
  assert.equal(done.status, 0, done.stderr);
});

test('Files changed after approval stop done until an amendment is logged', t => {
  const root = makeProject(t);
  stageTask1(root);
  write(root, PLAN_FILE, read(root, PLAN_FILE).replace('**Files:** src/limit.mjs, tests/ ·', '**Files:** src/, tests/ ·'));
  assert.match(dflow(root, ['done', '1', '-m', 'x']).stderr, /Task 1's Files differ from the approved plan \(was src\/limit\.mjs, tests\/; now src\/, tests\/\) and no log line explains it/);
  assert.equal(dflow(root, ['log', '1', 'A', 'the parser needs a helper module beside it']).status, 0);
  const done = dflow(root, ['done', '1', '-m', 'feat: parse']);
  assert.equal(done.status, 0, done.stderr);
  assert.match(dflow(root, ['review', 'pack']).stdout, /Task 1 Files changed after approval: was src\/limit\.mjs, tests\/; now src\/, tests\//);
});

test('block is derived from the log, skips the task and unblock restores it', t => {
  const root = makeProject(t, { plan: PLAN.replace('**After:** 1', '**After:** —') });
  const blocked = dflow(root, ['block', '1', 'the API key is missing']);
  assert.equal(blocked.status, 0, blocked.stderr);
  assert.match(blocked.stdout, /Continue with Task 2/);
  fs.rmSync(path.join(root, '.dflow'), { recursive: true });
  const status = JSON.parse(dflow(root, ['status', '--json']).stdout);
  assert.deepEqual(status.plan.blocked, [{ number: 1, reason: 'the API key is missing' }]);
  assert.match(dflow(root, ['next']).stdout, /### Task 2/);
  assert.match(dflow(root, ['done', '1', '-m', 'x']).stderr, /Task 1 is blocked/);
  assert.equal(dflow(root, ['unblock', '1', 'key issued']).status, 0);
  assert.deepEqual(JSON.parse(dflow(root, ['status', '--json']).stdout).plan.blocked, []);
});

test('a verify command that hangs is killed at the timeout', t => {
  const root = makeProject(t, { config: { verifyTimeout: 1 } });
  stageTask1(root, 'setInterval(() => {}, 1000)\n');
  const started = Date.now();
  const result = dflow(root, ['done', '1', '-m', 'x']);
  assert.equal(result.status, 1);
  assert.match(result.stdout, /timed out after 1s/);
  assert.ok(Date.now() - started < 15000);
});

test('the reset line appears once the context passes the threshold', t => {
  const root = makeProject(t);
  stageTask1(root);
  write(root, '.dflow/context/sess-a.json', JSON.stringify({ session: 'sess-a', tokens: 162000, window: 1000000, at: new Date().toISOString() }));
  const env = { CLAUDE_CODE_SESSION_ID: 'sess-a' };
  const done = dflow(root, ['done', '1', '-m', 'feat: parse'], { env });
  assert.match(done.stdout, /RESET: the context is 162k, past the 150k threshold/);
  assert.match(dflow(root, ['context'], { env }).stdout, /context 162k of 1M · resets at 150k · read from the mod/);
  // Another session open in this checkout has a figure of its own.
  assert.match(dflow(root, ['context'], { env: { CLAUDE_CODE_SESSION_ID: 'sess-b' } }).stdout, /^context size unknown/);
  // Run by hand, the CLI reads the freshest figure.
  assert.match(dflow(root, ['context']).stdout, /context 162k of 1M/);
});

test('a context read only from the transcript prints no reset line, since only the mod compacts', t => {
  const root = makeProject(t);
  stageTask1(root);
  write(root, '.transcripts/big.jsonl', `${JSON.stringify({ type: 'assistant', message: { usage: { input_tokens: 162000 } } })}\n`);
  dflow(root, ['status']);
  const file = path.join(root, '.dflow/state.json');
  const state = JSON.parse(fs.readFileSync(file, 'utf8'));
  fs.writeFileSync(file, JSON.stringify({ ...state, transcript: path.join(root, '.transcripts/big.jsonl') }));
  assert.match(dflow(root, ['context']).stdout, /context 162k/);
  const done = dflow(root, ['done', '1', '-m', 'feat: parse']);
  assert.equal(done.status, 0, done.stderr + done.stdout);
  assert.doesNotMatch(done.stdout, /RESET:/);
  assert.equal(fs.existsSync(path.join(root, '.dflow/reset.json')), false);
});

test('state written by another command while verify runs survives done', t => {
  const root = makeProject(t);
  // The verify stands in for a gate or merge saved during a long verify.
  stageTask1(root, `import fs from 'node:fs';
const file = '.dflow/state.json';
const state = JSON.parse(fs.readFileSync(file, 'utf8'));
state.concurrent = 'kept';
fs.writeFileSync(file, JSON.stringify(state));
`);
  const done = dflow(root, ['done', '1', '-m', 'feat: parse']);
  assert.equal(done.status, 0, done.stderr + done.stdout);
  const state = JSON.parse(read(root, '.dflow/state.json'));
  assert.equal(state.concurrent, 'kept');
  assert.equal(state.plans['2026-11-12-meter'].tasks[1].state, 'done');
});

test('a torn context file reads as no figure and breaks no command', t => {
  const root = makeProject(t);
  stageTask1(root);
  write(root, '.dflow/context/sess-a.json', '{"session":"sess-a","tok');
  const env = { CLAUDE_CODE_SESSION_ID: 'sess-a' };
  assert.equal(dflow(root, ['status'], { env }).status, 0);
  assert.equal(dflow(root, ['status']).status, 0);
  const done = dflow(root, ['done', '1', '-m', 'feat: parse'], { env });
  assert.equal(done.status, 0, done.stderr + done.stdout);
  assert.match(done.stdout, /### Task 2: Draw the meter/);
  assert.equal(fs.existsSync(path.join(root, '.dflow/context/sess-a.json')), false);
});

test('log appends a decision line and rejects kinds the CLI writes itself', t => {
  const root = makeProject(t);
  assert.equal(dflow(root, ['log', '1', 'D', 'a function, not a class']).status, 0);
  assert.equal(dflow(root, ['log', '-', 'G', 'the suite needs TZ=UTC']).status, 0);
  assert.equal(dflow(root, ['log', '1', 'B', 'x']).status, 1);
  assert.deepEqual(parsePlan(read(root, PLAN_FILE)).log.map(entry => [entry.task, entry.kind]), [[1, 'D'], [null, 'G']]);
});

test('a task without a verify command cannot be done, and a task added after approval needs a logged amendment', t => {
  const root = makeProject(t);
  stageTask1(root);
  write(root, PLAN_FILE, read(root, PLAN_FILE).replace('- [ ] Verify: `node verify1.mjs`\n', ''));
  const refused = dflow(root, ['done', '1', '-m', 'x']);
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /Task 1 has no `Verify:` step/);
  assert.equal(parsePlan(read(root, PLAN_FILE)).tasks[0].done, false);
  assert.equal(dflow(root, ['amend', '1', '--verify', 'node verify1.mjs', '--reason', 'restored']).status, 0);
  assert.deepEqual(parsePlan(read(root, PLAN_FILE)).tasks[0].verify, ['node verify1.mjs']);
  assert.equal(dflow(root, ['done', '1', '-m', 'feat: parse']).status, 0);

  write(root, 'verify2.mjs', PASS);
  write(root, 'src/meter.mjs', '1\n');
  git(root, 'add', 'src');
  dflow(root, ['done', '2', '-m', 'feat: draw']);
  write(root, PLAN_FILE, read(root, PLAN_FILE).replace('## Log', '### Task 3: Added later\n**Files:** src/late.mjs · **After:** 2 · **Run:** inline · **Size:** S\n- [ ] Implement it\n- [ ] Verify: `true`\n\n## Log'));
  write(root, 'src/late.mjs', '1\n');
  git(root, 'add', 'src');
  assert.match(dflow(root, ['done', '3', '-m', 'feat: late']).stderr, /Task 3 is not in the approved plan/);
  dflow(root, ['log', '3', 'A', 'added a task for the late module the owner asked for']);
  assert.equal(dflow(root, ['done', '3', '-m', 'feat: late']).status, 0);
});

test('the dflow configuration cannot ride along in a task commit unseen', t => {
  const root = makeProject(t);
  stageTask1(root);
  write(root, 'docs/dflow/config.json', JSON.stringify({ gates: [] }));
  write(root, 'docs/dflow/project.md', '# updated\n');
  git(root, 'add', 'docs');
  const refused = dflow(root, ['done', '1', '-m', 'feat: parse']);
  assert.match(refused.stderr, /outside Task 1's Files: docs\/dflow\/config\.json;/);
  assert.equal(dflow(root, ['done', '1', '-m', 'feat: parse', '--extra', 'the gate list moved']).status, 0);
});

test('moving a test file is not weakening it, and a file name with a space is matched', t => {
  const root = makeProject(t, { plan: PLAN.replace('**Files:** src/meter.mjs', '**Files:** src/meter.mjs, src/my meter.mjs, tests/') });
  stageTask1(root);
  dflow(root, ['done', '1', '-m', 'feat: parse']);
  write(root, 'verify2.mjs', PASS);
  write(root, 'src/my meter.mjs', '1\n');
  git(root, 'mv', 'tests/limit.test.mjs', 'tests/parse.test.mjs');
  git(root, 'add', '-A', 'src', 'tests');
  const done = dflow(root, ['done', '2', '-m', 'feat: draw']);
  assert.equal(done.status, 0, done.stderr);
  assert.equal(parsePlan(read(root, PLAN_FILE)).log.length, 0);
});

test('a test file renamed out of the test patterns counts as removed', t => {
  const root = makeProject(t, { plan: PLAN.replace('**Files:** src/meter.mjs', '**Files:** src/meter.mjs, tests/, notes/') });
  stageTask1(root);
  dflow(root, ['done', '1', '-m', 'feat: parse']);
  write(root, 'verify2.mjs', PASS);
  write(root, 'src/meter.mjs', '1\n');
  fs.mkdirSync(path.join(root, 'notes'));
  git(root, 'mv', 'tests/limit.test.mjs', 'notes/limit.txt');
  git(root, 'add', '-A', 'src', 'tests', 'notes');
  const refused = dflow(root, ['done', '2', '-m', 'feat: draw']);
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /tests\/limit\.test\.mjs: test file moved to notes\/limit\.txt, which no test pattern matches/);
});

test('a verify command that exits 0 but leaves a background process is a pass, not a hang', t => {
  const root = makeProject(t, { plan: PLAN.replace('`node verify1.mjs`', '`sleep 30 & echo started`') });
  write(root, 'src/limit.mjs', '1\n');
  git(root, 'add', 'src');
  const started = Date.now();
  const done = dflow(root, ['done', '1', '-m', 'feat: parse']);
  assert.equal(done.status, 0, done.stdout + done.stderr);
  assert.ok(Date.now() - started < 10000);
});
