import { parseArgs } from 'node:util';
import { briefLines, buildModel, refreshHud, statusLines } from '../status.mjs';

export async function run(ctx, argv, { out }) {
  const { values } = parseArgs({ args: argv, options: { json: { type: 'boolean' }, brief: { type: 'boolean' } } });
  const model = buildModel(ctx);
  if (values.json) out(JSON.stringify(model, null, 2));
  else for (const line of values.brief ? briefLines(model) : statusLines(model)) out(line);
  refreshHud(ctx);
  return 0;
}
