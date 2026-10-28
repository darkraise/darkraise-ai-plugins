// Stands in for the `claude` CLI. Each call takes the next mode from
// $STUB_DIR/modes, records its arguments in $STUB_DIR/calls.log, acts in its
// working directory as that mode says, and prints the JSON a headless run
// prints.
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { PLAN } from './fixture.mjs';

const ISOLATION = ['HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'CLAUDE_CONFIG_DIR', 'TMPDIR'];
const dir = process.env.STUB_DIR;
const list = readFileSync(join(dir, 'modes'), 'utf8').split('\n').filter(Boolean);
const mode = list[0];
if (list.length > 1) writeFileSync(join(dir, 'modes'), list.slice(1).join('\n') + '\n');
appendFileSync(join(dir, 'calls.log'), JSON.stringify({ mode, cwd: process.cwd(), args: process.argv.slice(2), claudeMds: process.env.CLAUDE_CODE_DISABLE_CLAUDE_MDS, env: Object.fromEntries(ISOLATION.map(k => [k, process.env[k]])), config: process.env.CLAUDE_CONFIG_DIR && existsSync(process.env.CLAUDE_CONFIG_DIR) ? readdirSync(process.env.CLAUDE_CONFIG_DIR).sort() : [], prompt: readFileSync(0, 'utf8') }) + '\n');

const reply = (result, extra = {}) => console.log(JSON.stringify({ type: 'result', is_error: false, result, total_cost_usd: 0.5, num_turns: 3, modelUsage: { 'stub-model': {} }, ...extra }));
const apply = () => spawnSync('git', ['apply', join(dir, 'greet.patch')], { stdio: 'ignore' });
const file = name => existsSync(join(dir, name)) ? readFileSync(join(dir, name), 'utf8') : '';
// A controller session: the ledger where sdd-workspace puts it, and a
// transcript with two dispatches of its own and one inside a subagent's.
const session = ledger => {
  const script = fileURLToPath(new URL('../../../plugins/dforge/scripts/sdd-workspace', import.meta.url));
  const workspace = spawnSync('bash', [script, PLAN], { encoding: 'utf8' }).stdout.trim();
  writeFileSync(join(workspace, 'progress.md'), ledger.join('\n') + '\n');
  const projects = join(process.env.CLAUDE_CONFIG_DIR, 'projects/-work');
  mkdirSync(join(projects, 'session/subagents'), { recursive: true });
  const use = name => JSON.stringify({ message: { content: [{ type: 'tool_use', name }] } });
  writeFileSync(join(projects, 'session.jsonl'), [use('Agent'), use('Bash'), use('Agent')].join('\n') + '\n');
  writeFileSync(join(projects, 'session/subagents/agent-1.jsonl'), use('Agent') + '\n');
};

if (mode === 'pass') { apply(); reply('**Status:** DONE'); }
else if (mode === 'loop') { apply(); session(['Task 1: implementer impl-sonnet-low (assigned; base abc1234)', 'Task 1: fix round 1/2 (1 addressed, 0 open)', 'Task 1: complete (commits abc1234..def5678, review clean)']); reply('Task 1: complete'); }
else if (mode === 'loopstop') { apply(); session(['Task 1: implementer impl-sonnet-low (assigned; base abc1234)']); reply('stopped at the first wait'); }
else if (mode === 'slice') { spawnSync('git', ['apply', join(dir, 'slice.patch')], { stdio: 'ignore' }); reply('**Status:** DONE'); }
else if (mode === 'concerns') { apply(); reply('**Status:** DONE_WITH_CONCERNS'); }
else if (mode === 'failtest') { apply(); writeFileSync('src/greet.sh', 'echo nope\n'); reply('**Status:** DONE'); }
else if (mode === 'cheat') { apply(); writeFileSync('src/greet.sh', 'echo nope\n'); writeFileSync('tests/greet.test.sh', 'true\n'); reply('**Status:** DONE'); }
else if (mode === 'outside') { apply(); writeFileSync('extra.txt', 'x\n'); reply('**Status:** DONE'); }
else if (mode === 'blocked') { reply('**Status:** BLOCKED - the brief is unclear'); }
else if (mode === 'budget') { apply(); reply('', { is_error: true, subtype: 'error_max_budget_usd' }); process.exitCode = 1; }
else if (mode === 'limit') { reply("You've hit your usage limit", { is_error: true, total_cost_usd: 0 }); process.exitCode = 1; }
else if (mode === 'crash') { console.error('boom'); process.exitCode = 2; }
else if (mode === 'review') { mkdirSync('.superpowers/sdd/eval', { recursive: true }); writeFileSync('.superpowers/sdd/eval/review-report.md', file('review.md')); reply('Report: .superpowers/sdd/eval/review-report.md'); }
else if (mode === 'noreport') { reply('A review with no report file.'); }
else if (mode === 'grade') { reply(file('grade.json')); }
else { console.error(`stub-claude: unknown mode ${mode}`); process.exitCode = 2; }
