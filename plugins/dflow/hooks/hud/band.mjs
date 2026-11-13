// The minimized band's lines, modelled on the dforge cockpit's bandLines and
// fitBand in lib.ts: plugins never import each other.

import { billingLabel, modelName } from './account.mjs';
import { repoName, shortDir } from './repo.mjs';
import { duration, kTokens, limitForecast, limitLabel, rampColor, runsCut, runsWidth, track, trackRuns, windowElapsed } from './meter.mjs';

const DIR = 'blue';
const GIT = 'magenta';
const COST = '#af87ff';
const AMBER = '#ff8700';
// The effort's hue rises with it, away from the meters' green-to-red ramp, so
// a color never means both near a limit and set to max.
const EFFORT_COLORS = { low: 'gray', medium: 'blue', high: 'cyan', xhigh: '#af87ff', max: 'magenta' };
// Meter cells per tier; 0 draws the percent alone.
const METERS = [8, 4, 0, 0, 0, 0];
export const BAND_TIERS = METERS.length;

const FIRST_TIER = { meters: 2, readings: 3, repoName: 4, engine: 5 };

function joined(segments, tier) {
  const sep = { text: tier === 0 ? '  ·  ' : ' · ', dim: true };
  return segments.filter(Boolean).flatMap((runs, index) => (index ? [sep, ...runs] : runs));
}

function folderRuns({ where, repo }, tier) {
  const runs = [];
  if (where) {
    const name = tier >= FIRST_TIER.repoName ? repoName(null, where.root ?? where.cwd) : shortDir(where.cwd, where.home);
    runs.push({ text: name, color: DIR, bold: true });
  }
  if (repo) {
    const counts = [repo.ahead ? `↑${repo.ahead}` : '', repo.behind ? `↓${repo.behind}` : '', repo.changed ? `~${repo.changed}` : '', repo.untracked ? `?${repo.untracked}` : ''].filter(Boolean);
    if (runs.length) runs.push({ text: ' ' });
    runs.push({ text: '⎇ ', color: GIT }, { text: repo.branch, color: GIT, bold: true });
    if (repo.changed + repo.untracked > 0) runs.push({ text: '*', color: GIT });
    if (counts.length) runs.push({ text: ` ${counts.join(' ')}`, color: GIT });
  }
  return runs.length ? runs : null;
}

function planRuns({ plan }) {
  if (!plan) return null;
  return [
    { text: 'dflow ', color: 'yellow', bold: true },
    { text: `${plan.done}/${plan.total}`, color: 'yellow' },
    ...(plan.current ? [{ text: ` · Task ${plan.current.number}`, color: 'yellow' }] : []),
  ];
}

function workerRuns({ workers }) {
  if (!workers?.length) return null;
  return [{ text: `● ${workers.length} ${workers.length === 1 ? 'worker' : 'workers'}`, color: 'magenta' }];
}

// The context against the reset point (`┃`), or against the window when no
// reset point is set.
function contextRuns({ hud, context }, tier) {
  if (typeof context?.tokens !== 'number') return null;
  const { tokens, window } = context;
  const resetAt = hud.context?.resetAt ?? null;
  const color = rampColor(resetAt ? (tokens / resetAt) * 100 : (tokens / window) * 100);
  const cells = METERS[tier];
  const marks = resetAt ? [{ at: resetAt / window, glyph: '┃', name: 'reset' }] : [];
  const meter = cells ? [...trackRuns(track(tokens / window, cells, marks), color, { reset: color }), { text: ' ' }] : [];
  let reading = [{ text: kTokens(tokens), color, bold: true }];
  if (resetAt) reading = [{ text: `${Math.round((tokens / resetAt) * 100)}%`, color, bold: true }];
  else if (tier < FIRST_TIER.meters) reading.push({ text: ` of ${kTokens(window)}`, dim: true });
  return [{ text: 'ctx ', dim: true }, ...meter, ...reading];
}

// A rate-limit window with how far through it the session is (`┊`), its pace
// and its reset.
function limitRuns({ usage, now }, kind, tier) {
  const limit = usage?.limits.find(one => one.kind === kind);
  if (!limit) return null;
  const color = rampColor(limit.percent);
  const cells = METERS[tier];
  const elapsed = windowElapsed(kind, limit.resetsAt, now);
  const marks = elapsed === null ? [] : [{ at: elapsed, glyph: '┊', name: 'elapsed' }];
  const runs = [{ text: `${limitLabel(kind)} `, dim: true }];
  if (cells) runs.push(...trackRuns(track(limit.percent / 100, cells, marks), color, { elapsed: 'gray' }), { text: ' ' });
  runs.push({ text: `${Math.round(limit.percent)}%`, color, bold: true });
  if (tier >= FIRST_TIER.readings) return runs;
  const forecast = limitForecast(kind, limit.percent, limit.resetsAt, now);
  if (forecast === 'pace') runs.push({ text: ' on pace', color: 'green' });
  else if (typeof forecast === 'number') runs.push({ text: ` out in ${duration(forecast) || '<1m'}`, color: AMBER });
  if (limit.resetsAt !== null) runs.push({ text: ` · ${duration(limit.resetsAt - now) || 'now'}`, dim: true });
  return runs;
}

/** The band's two lines at one tier: 0 is the fullest, BAND_TIERS - 1 the most compact. */
export function bandLines(input, tier) {
  const { engine, hud, usage } = input;
  const hasEngine = tier < FIRST_TIER.engine;
  const model = hasEngine && engine?.model ? [{ text: modelName(engine.model), color: 'cyan', bold: true }] : null;
  const effort = hasEngine && engine?.effort ? [{ text: engine.effort, color: EFFORT_COLORS[engine.effort] ?? 'gray' }] : null;
  const cost = typeof usage?.usd === 'number' ? [{ text: `$${usage.usd.toFixed(2)}`, color: COST, bold: true }] : null;
  return [
    joined([folderRuns(input, tier), model, effort, planRuns(hud), workerRuns(hud)], tier),
    joined([contextRuns(input, tier), limitRuns(input, 'five_hour', tier), limitRuns(input, 'seven_day', tier), cost], tier),
  ];
}

/** Each band line at the fullest tier that fits `width`, stepping down on its own; a line too wide even at the last tier is cut. */
export function fitBand(input, width) {
  const fit = which => {
    for (let tier = 0; tier < BAND_TIERS; tier++) {
      const line = bandLines(input, tier)[which];
      if (runsWidth(line) <= width) return line;
    }
    return runsCut(bandLines(input, BAND_TIERS - 1)[which], width);
  };
  return [fit(0), fit(1)];
}

/** The top rule's text: who the session runs as and Remote Control. */
export function bandTop({ account, remote }) {
  const parts = [];
  if (account?.email) parts.push([{ text: account.email }]);
  else if (account) parts.push([{ text: `config ${account.key}`, dim: true }]);
  const billing = billingLabel(account?.billing);
  if (billing) parts.push([{ text: billing, dim: true }]);
  if (remote?.clients?.length) parts.push([{ text: 'Remote ' }, { text: '● ', color: 'green', bold: true }, { text: 'connected', color: 'green' }]);
  else if (String(remote?.setting) === 'true') parts.push([{ text: 'Remote ' }, { text: '○ on', color: 'green' }]);
  else parts.push([{ text: 'Remote ○ not connected', dim: true }]);
  return parts.flatMap((runs, index) => (index ? [{ text: ' · ', dim: true }, ...runs] : runs));
}

// A darkmem server that cannot be reached is not a warning: the Board card
// shows it as offline.
export function bandWarning(hud) {
  const parts = [];
  const blocked = hud.plan?.blocked ?? [];
  if (blocked.length === 1) parts.push(`✗ Task ${blocked[0].number} blocked`);
  else if (blocked.length > 1) parts.push(`✗ ${blocked.length} tasks blocked`);
  if (hud.gates && !hud.gates.ok) parts.push('✗ gates failed');
  const { sync } = hud;
  if (sync?.enabled && sync.conflict) parts.push('✗ darkmem conflict');
  else if (sync?.enabled && (sync.refused || (sync.error && !sync.offline))) parts.push('✗ darkmem refused');
  return parts.flatMap((part, index) => [...(index ? [{ text: ' · ', dim: true }] : []), { text: part, color: 'red' }]);
}
