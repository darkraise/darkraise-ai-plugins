import fs from 'node:fs';
import path from 'node:path';
import { nowIso, readJson, readText, writeJson } from './util.mjs';

export function loadState(paths) {
  const state = readJson(paths.state, null) ?? {};
  state.version = 1;
  state.plans ??= {};
  return state;
}

export function saveState(paths, state) {
  writeJson(paths.state, state);
}

export function planState(state, slug) {
  state.plans[slug] ??= {};
  state.plans[slug].tasks ??= {};
  return state.plans[slug];
}

export function taskRecord(state, slug, number) {
  const plan = planState(state, slug);
  plan.tasks[number] ??= {};
  return plan.tasks[number];
}

// One line per transition: the source for the darkmem work log, the cost
// phases and the tick-without-commit check.
export function appendEvent(ctx, event) {
  fs.mkdirSync(path.dirname(ctx.paths.events), { recursive: true });
  fs.appendFileSync(ctx.paths.events, `${JSON.stringify({ at: nowIso(ctx.env), ...event })}\n`);
}

export function readEvents(paths) {
  const text = readText(paths.events);
  if (!text) return [];
  return text.split('\n').filter(Boolean).flatMap(line => {
    try {
      return [JSON.parse(line)];
    } catch {
      return [];
    }
  });
}
