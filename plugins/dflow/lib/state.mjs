import fs from 'node:fs';
import path from 'node:path';
import { nowIso, readJson, readText, withLock, writeJson } from './util.mjs';

export function loadState(paths) {
  const state = readJson(paths.state, null) ?? {};
  state.plans ??= {};
  return state;
}

function saveState(paths, state) {
  writeJson(paths.state, state);
}

// Commands overlap: a background `dflow done` holds its copy for as long as
// verify runs. Every write therefore re-reads state.json under a lock and
// applies only its own change, or it would put back what others removed.
export function updateState(paths, mutate) {
  return withLock(`${paths.state}.lock`, () => {
    const state = loadState(paths);
    const result = mutate(state);
    saveState(paths, state);
    return result;
  });
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
