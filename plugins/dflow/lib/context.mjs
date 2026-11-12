import fs from 'node:fs';
import path from 'node:path';
import { readJson } from './util.mjs';

const TAIL_BYTES = 1024 * 1024;
const FRESH_MS = 10 * 60 * 1000;

// The context the last main-conversation response was answered over.
export function transcriptContext(file) {
  let text;
  try {
    const size = fs.statSync(file).size;
    const handle = fs.openSync(file, 'r');
    const length = Math.min(size, TAIL_BYTES);
    const buffer = Buffer.alloc(length);
    fs.readSync(handle, buffer, 0, length, size - length);
    fs.closeSync(handle);
    text = buffer.toString('utf8');
  } catch {
    return null;
  }
  const lines = text.split('\n');
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    if (!lines[index].includes('"usage"')) continue;
    let entry;
    try {
      entry = JSON.parse(lines[index]);
    } catch {
      continue;
    }
    const usage = entry.message?.usage;
    if (entry.type !== 'assistant' || entry.isSidechain || !usage) continue;
    return (usage.input_tokens ?? 0) + (usage.cache_read_input_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0);
  }
  return null;
}

// The mod writes the live figure; without the mod the transcript is read.
export function contextSize(ctx, state) {
  const live = readJson(path.join(ctx.paths.stateDir, 'context.json'), null);
  const now = Date.parse(ctx.env.DFLOW_NOW || '') || Date.now();
  if (live && typeof live.tokens === 'number' && now - Date.parse(live.at) < FRESH_MS) {
    return { tokens: live.tokens, window: live.window ?? null, source: 'mod' };
  }
  const tokens = state.transcript ? transcriptContext(state.transcript) : null;
  return tokens === null ? null : { tokens, window: null, source: 'transcript' };
}

export function formatTokens(tokens) {
  if (tokens >= 1000000) return `${(tokens / 1000000).toFixed(tokens % 1000000 ? 1 : 0)}M`;
  return tokens >= 1000 ? `${Math.round(tokens / 1000)}k` : String(tokens);
}
