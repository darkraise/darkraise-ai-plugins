// Stands in for the `claude` CLI. Each call takes the next mode from
// $STUB_DIR/modes, records its arguments in $STUB_DIR/calls.log, acts in its
// working directory as that mode says, and prints the JSON a headless run
// prints.
import { appendFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const dir = process.env.STUB_DIR;
const list = readFileSync(join(dir, 'modes'), 'utf8').split('\n').filter(Boolean);
const mode = list[0];
if (list.length > 1) writeFileSync(join(dir, 'modes'), list.slice(1).join('\n') + '\n');
appendFileSync(join(dir, 'calls.log'), JSON.stringify({ mode, cwd: process.cwd(), args: process.argv.slice(2), prompt: readFileSync(0, 'utf8') }) + '\n');

const reply = (result, extra = {}) => console.log(JSON.stringify({ type: 'result', is_error: false, result, total_cost_usd: 0.5, num_turns: 3, modelUsage: { 'stub-model': {} }, ...extra }));
const apply = () => spawnSync('git', ['apply', join(dir, 'greet.patch')], { stdio: 'ignore' });
const file = name => existsSync(join(dir, name)) ? readFileSync(join(dir, name), 'utf8') : '';

if (mode === 'pass') { apply(); reply('**Status:** DONE'); }
else if (mode === 'concerns') { apply(); reply('**Status:** DONE_WITH_CONCERNS'); }
else if (mode === 'failtest') { apply(); writeFileSync('src/greet.sh', 'echo nope\n'); reply('**Status:** DONE'); }
else if (mode === 'cheat') { apply(); writeFileSync('src/greet.sh', 'echo nope\n'); writeFileSync('tests/greet.test.sh', 'true\n'); reply('**Status:** DONE'); }
else if (mode === 'outside') { apply(); writeFileSync('extra.txt', 'x\n'); reply('**Status:** DONE'); }
else if (mode === 'blocked') { reply('**Status:** BLOCKED - the brief is unclear'); }
else if (mode === 'budget') { apply(); reply('', { is_error: true, subtype: 'error_max_budget_usd' }); process.exitCode = 1; }
else if (mode === 'limit') { reply("You've hit your usage limit", { is_error: true, total_cost_usd: 0 }); process.exitCode = 1; }
else if (mode === 'crash') { console.error('boom'); process.exitCode = 2; }
else if (mode === 'review') { reply(file('review.md')); }
else if (mode === 'grade') { reply(file('grade.json')); }
else { console.error(`stub-claude: unknown mode ${mode}`); process.exitCode = 2; }
