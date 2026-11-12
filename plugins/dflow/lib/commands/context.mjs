import { contextSize, formatTokens } from '../context.mjs';
import { loadState } from '../state.mjs';

export async function run(ctx, argv, { out }) {
  const size = contextSize(ctx, loadState(ctx.paths));
  const threshold = formatTokens(ctx.config.context.resetAt);
  if (!size) out(`context size unknown (no session transcript recorded); resets at ${threshold}`);
  else out(`context ${formatTokens(size.tokens)}${size.window ? ` of ${formatTokens(size.window)}` : ''} · resets at ${threshold} · read from the ${size.source}`);
  return 0;
}
