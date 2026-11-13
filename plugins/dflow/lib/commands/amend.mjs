import fs from 'node:fs';
import { parseArgs } from 'node:util';
import { appendLog, setVerify } from '../plan.mjs';
import { loadState, saveState, taskRecord } from '../state.mjs';
import { fail, today } from '../util.mjs';
import { requireActive } from './next.mjs';

export async function run(ctx, argv, { out }) {
  const { values, positionals } = parseArgs({ args: argv, allowPositionals: true, options: { verify: { type: 'string', multiple: true }, reason: { type: 'string' } } });
  const number = Number(positionals[0]);
  if (!Number.isInteger(number) || !values.verify?.length || !values.reason) fail('usage: dflow amend <N> --verify "<command>" [--verify "<command>"] --reason "<why the approved one was wrong>"');
  if (values.verify.some(command => command.includes('`'))) fail('a verify command cannot contain a backtick');
  // The plan holds one command per line.
  if (values.verify.some(command => /[\r\n]/.test(command))) fail('a verify command is one line; join the steps with && or put them in a script');
  const state = loadState(ctx.paths);
  const active = requireActive(ctx, state);
  const task = active.plan.tasks.find(candidate => candidate.number === number);
  if (!task) fail(`${active.rel} has no Task ${number}`);
  if (task.done) fail(`Task ${number} is already done`);
  const amended = setVerify(active.text, number, values.verify);
  fs.writeFileSync(active.file, appendLog(amended, {
    date: today(ctx.env), task: number, kind: 'V',
    message: `verify is now ${values.verify.map(command => `\`${command}\``).join(', ')}, was ${task.verify.map(command => `\`${command}\``).join(', ') || 'missing'} — ${values.reason}`,
  }));
  taskRecord(state, active.slug, number).attempts = 0;
  saveState(ctx.paths, state);
  out(`Task ${number} now verifies with: ${values.verify.join(' && ')}. The change is logged and will be listed in the review pack.`);
  return 0;
}
