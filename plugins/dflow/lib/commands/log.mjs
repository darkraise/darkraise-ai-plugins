import fs from 'node:fs';
import { appendLog } from '../plan.mjs';
import { loadState } from '../state.mjs';
import { fail, today } from '../util.mjs';
import { requireActive } from './next.mjs';

const BY_HAND = { D: 'decision, promoted to decisions.md at ship', G: 'gotcha, promoted to gotchas.md at ship', A: 'plan amended', N: 'note' };

export async function run(ctx, argv, { out }) {
  const [target, kind, ...words] = argv;
  const message = words.join(' ').trim();
  const number = target === '-' ? null : Number(target);
  if (!target || (number !== null && !Number.isInteger(number)) || !BY_HAND[kind] || !message) {
    fail(`usage: dflow log <N|-> <${Object.keys(BY_HAND).join('|')}> "<text>" — ${Object.entries(BY_HAND).map(([key, meaning]) => `${key}: ${meaning}`).join('; ')}`);
  }
  const active = requireActive(ctx, loadState(ctx.paths));
  if (number !== null && !active.plan.tasks.some(task => task.number === number)) fail(`${active.rel} has no Task ${number}`);
  fs.writeFileSync(active.file, appendLog(active.text, { date: today(ctx.env), task: number, kind, message }));
  out(`Logged in ${active.rel}: ${number === null ? '-' : `T${number}`} ${kind}: ${message}`);
  return 0;
}
