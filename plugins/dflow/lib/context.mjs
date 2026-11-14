import fs from 'node:fs';
import path from 'node:path';
import { readText } from './util.mjs';

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

const KEEP_MS = 7 * 24 * 60 * 60 * 1000;

// The same name as contextFile in hooks/hud/view.mjs, which the mod writes.
function contextFile(ctx, session) {
  return path.join(ctx.paths.stateDir, 'context', `${session.replace(/[^A-Za-z0-9_-]/g, '_')}.json`);
}

// The mod rewrites these files as the figure moves, so a torn one is likely
// enough that it reads as no figure and is removed, never as an error.
function readEntry(file) {
  const text = readText(file);
  if (text === null) return null;
  try {
    return JSON.parse(text);
  } catch {
    fs.rmSync(file, { force: true });
    return null;
  }
}

// Inside a session the CLI reads that session's own figure (the harness sets
// CLAUDE_CODE_SESSION_ID for its shell); run by hand, the freshest one.
// Files of sessions gone for a week are removed on the way.
function liveContext(ctx, now) {
  const session = ctx.env.CLAUDE_CODE_SESSION_ID;
  if (session) return readEntry(contextFile(ctx, session));
  const dir = path.join(ctx.paths.stateDir, 'context');
  let names = [];
  try {
    names = fs.readdirSync(dir);
  } catch {
    return null;
  }
  const entries = names.flatMap(name => {
    const file = path.join(dir, name);
    const entry = readEntry(file);
    const at = Date.parse(entry?.at ?? '');
    if (!Number.isFinite(at) || now - at > KEEP_MS) {
      fs.rmSync(file, { force: true });
      return [];
    }
    return [entry];
  });
  return entries.sort((a, b) => Date.parse(b.at) - Date.parse(a.at))[0] ?? null;
}

// The mod writes the live figure; without the mod the transcript is read.
export function contextSize(ctx, state) {
  const now = Date.parse(ctx.env.DFLOW_NOW || '') || Date.now();
  const live = liveContext(ctx, now);
  if (live && typeof live.tokens === 'number' && now - Date.parse(live.at) < FRESH_MS) {
    return { tokens: live.tokens, window: live.window ?? null, source: 'mod' };
  }
  const session = ctx.env.CLAUDE_CODE_SESSION_ID;
  const transcript = session ? state.transcripts?.[session] : state.transcript;
  const tokens = transcript ? transcriptContext(transcript) : null;
  return tokens === null ? null : { tokens, window: null, source: 'transcript' };
}

export function formatTokens(tokens) {
  if (tokens >= 1000000) return `${(tokens / 1000000).toFixed(tokens % 1000000 ? 1 : 0)}M`;
  return tokens >= 1000 ? `${Math.round(tokens / 1000)}k` : String(tokens);
}
