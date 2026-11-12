import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { parseBoard } from './board.mjs';
import { nextTask, taskStates } from './plan.mjs';
import { currentBranch, defaultBranch, head, relative, userConfig } from './repo.mjs';
import { loadState, planState, readEvents, saveState } from './state.mjs';
import { activePlan } from './status.mjs';
import { nowIso, readJson, readText, shortSha, writeJson } from './util.mjs';

export const PREFIX = 'dflow';
const CLIENT = 'dflow';

export class HttpError extends Error {
  constructor(method, route, status, detail) {
    super(`${method} ${route} answered ${status}: ${detail}`);
    this.status = status;
  }
}
export class TransportError extends Error {}

// darkmem is on only when all three are present: the server URL and key
// variable in the user's config, and the project name in the repository's.
export function settings(ctx) {
  const user = userConfig(ctx.env).darkmem ?? {};
  const url = (ctx.env.DFLOW_DARKMEM_URL || user.url || '').replace(/\/+$/, '');
  const keyEnv = user.api_key_env || 'DARKMEM_API_KEY';
  const project = ctx.config.darkmem?.project || '';
  if (!project) return { off: 'the repository names no darkmem project (dflow init --darkmem <project>)' };
  if (!url) return { off: 'no darkmem URL is configured (~/.dflow/config.json: {"darkmem": {"url": "..."}})' };
  if (!ctx.env[keyEnv]) return { off: `the API key variable ${keyEnv} is not set` };
  return { url, apiKey: ctx.env[keyEnv], project };
}

export function createClient({ url, apiKey, timeoutMs }) {
  return async function call(method, route, { query = {}, body } = {}) {
    const target = new URL(`${url}${route}`);
    for (const [name, value] of Object.entries(query)) if (value !== undefined && value !== null) target.searchParams.set(name, String(value));
    const headers = { Authorization: `Bearer ${apiKey}`, 'X-Darkmem-Client': CLIENT, Accept: 'application/json' };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    let response;
    let text;
    try {
      response = await fetch(target, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(timeoutMs) });
      text = await response.text();
    } catch (error) {
      throw new TransportError(`${method} ${route}: ${error?.name === 'TimeoutError' ? `no answer within ${timeoutMs} ms` : (error?.cause?.message ?? error?.message ?? String(error))}`);
    }
    let data = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      if (response.ok) throw new TransportError(`${method} ${route}: the answer is not JSON; is the URL a darkmem instance?`);
    }
    if (!response.ok) throw new HttpError(method, route, response.status, typeof data?.detail === 'string' ? data.detail : text.slice(0, 200));
    return data;
  };
}

function sha256(text) {
  return createHash('sha256').update(text).digest('hex');
}

function syncFile(ctx) {
  return path.join(ctx.paths.stateDir, 'sync.json');
}

export function loadSync(ctx) {
  const sync = readJson(syncFile(ctx), null) ?? {};
  sync.documents ??= {};
  sync.cursor ??= 0;
  return sync;
}

function uriOf(ctx, file) {
  return `${PREFIX}/${relative(ctx.paths.docs, file)}`;
}

function markdownUnder(directory) {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) return markdownUnder(full);
    return entry.name.endsWith('.md') ? [full] : [];
  });
}

function onDefaultBranch(ctx) {
  return currentBranch(ctx.root) === defaultBranch(ctx.root, ctx.config);
}

async function getDocument(call, project, uri) {
  try {
    return await call('GET', '/api/v1/documents/by-uri', { query: { project, uri, include_content: 'true' } });
  } catch (error) {
    if (error instanceof HttpError && error.status === 404) return null;
    throw error;
  }
}

// The repository wins for every document except the board, whose rows the
// darkmem UI may edit: there a remote change is a conflict to report.
async function pushDocument(run, file, { boardRules }) {
  const { ctx, call, cfg, sync, report } = run;
  const uri = uriOf(ctx, file);
  const content = readText(file);
  if (content === null || !content.trim()) return;
  const local = sha256(content);
  const known = sync.documents[uri];
  if (known?.local === local) return;
  const put = expected => call('POST', '/api/v1/documents', { body: { project: cfg.project, uri, content, ...(expected ? { expected_hash: expected } : {}) } });
  let answer;
  try {
    answer = await put(known?.remote);
  } catch (error) {
    if (!(error instanceof HttpError) || error.status !== 409) throw error;
    if (boardRules) {
      report.conflict = `${uri} changed on darkmem and in the repository; run \`dflow sync pull\` on a clean board, or re-apply the darkmem edit by hand`;
      return;
    }
    answer = await put(null);
  }
  sync.documents[uri] = { local, remote: answer.content_hash, id: answer.id ?? answer.document_id ?? known?.id };
  report.documents.push(uri);
}

async function pushBoardRow(run, active) {
  const { ctx, call, cfg, report } = run;
  const number = Number(active.plan.fields.board);
  const text = readText(ctx.paths.board);
  if (!Number.isInteger(number) || text === null) return;
  const mine = parseBoard(text).rows.find(row => row.number === number);
  if (!mine) return;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const remote = await getDocument(call, cfg.project, `${PREFIX}/board.md`);
    if (!remote) return;
    const theirs = parseBoard(remote.content).rows.find(row => row.number === number);
    if (!theirs) return;
    const changes = {};
    for (const column of ['state', 'note', 'assigned']) if (mine[column] !== theirs[column]) changes[column] = mine[column];
    if (!Object.keys(changes).length) return;
    try {
      await call('PATCH', `/api/v1/board/registers/${encodeURIComponent(remote.id)}/rows/${number}`, { body: { expected_hash: remote.content_hash, ...changes } });
      report.rows.push(number);
      return;
    } catch (error) {
      if (!(error instanceof HttpError) || error.status !== 409 || attempt) throw error;
    }
  }
}

const STATE_OF = { wip: 'wip', blocked: 'blocked', unblocked: 'todo' };

function ledgerEntry(event) {
  const properties = {};
  if (event.task) properties.task = event.task;
  let body;
  switch (event.event) {
    case 'done':
      properties.state = event.review ? 'review' : 'done';
      properties.commit = event.commit;
      body = `Task ${event.task}: complete (commit ${shortSha(event.commit)})`;
      break;
    case 'blocked':
      body = event.reason;
      break;
    case 'unblocked':
      body = `Task ${event.task}: unblocked — ${event.reason}`;
      break;
    case 'wip':
      body = `Task ${event.task}: started`;
      break;
    case 'verify-failed':
      body = `Task ${event.task}: verify failed`;
      break;
    case 'review':
      if (event.task) properties.state = 'done';
      body = event.task ? `Task ${event.task}: reviewed at tier ${event.tier}` : `Plan reviewed at tier ${event.tier}`;
      break;
    case 'shipped':
      body = `Plan shipped (commit ${shortSha(event.commit)})`;
      break;
    default:
      body = `Plan ${event.event}`;
  }
  if (STATE_OF[event.event]) properties.state = STATE_OF[event.event];
  return { kind: 'ledger', body, properties };
}

function runKey(ctx) {
  return `dflow:${sha256(ctx.root).slice(0, 12)}`;
}

async function append(run, slug, entries) {
  const { ctx, call, cfg } = run;
  for (let index = 0; index < entries.length; index += 100) {
    await call('POST', '/api/v1/worklog/entries', {
      body: { project: cfg.project, workstream: slug, run_key: runKey(ctx), client: CLIENT, entries: entries.slice(index, index + 100), properties: { plan_uri: `${PREFIX}/plans/${slug}.md` } },
    });
  }
}

async function pushWorklog(run) {
  const { ctx, sync, report } = run;
  const events = readEvents(ctx.paths);
  const pending = events.slice(sync.cursor);
  const bySlug = new Map();
  for (const event of pending) {
    if (!event.plan) continue;
    if (!bySlug.has(event.plan)) bySlug.set(event.plan, []);
    bySlug.get(event.plan).push(ledgerEntry(event));
  }
  for (const [slug, entries] of bySlug) await append(run, slug, entries);
  sync.cursor = events.length;
  report.entries += pending.length;
}

function open(ctx, { timeoutMs }) {
  const cfg = settings(ctx);
  if (cfg.off) return null;
  return { ctx, cfg, call: createClient({ ...cfg, timeoutMs }), sync: loadSync(ctx), report: { documents: [], rows: [], entries: 0, conflict: null, error: null } };
}

function close(run) {
  const { ctx, sync, report } = run;
  writeJson(syncFile(ctx), sync);
  const state = loadState(ctx.paths);
  const queued = readEvents(ctx.paths).length - sync.cursor;
  state.sync = { enabled: true, queued, lastAt: report.error ? state.sync?.lastAt ?? null : nowIso(ctx.env), conflict: report.conflict, error: report.error };
  saveState(ctx.paths, state);
  return report;
}

// On the default branch every document under docs/dflow is pushed; on a plan
// branch only that plan and its own board row, so branches never overwrite
// each other's view of the shared documents.
export async function push(ctx, { timeoutMs = 10000 } = {}) {
  const run = open(ctx, { timeoutMs });
  if (!run) return null;
  try {
    const active = activePlan(ctx);
    if (onDefaultBranch(ctx)) {
      for (const file of markdownUnder(ctx.paths.docs)) await pushDocument(run, file, { boardRules: file === ctx.paths.board });
    } else if (active) {
      await pushDocument(run, active.file, { boardRules: false });
      await pushBoardRow(run, active);
    }
    await pushWorklog(run);
  } catch (error) {
    if (!(error instanceof HttpError) && !(error instanceof TransportError)) throw error;
    run.report.error = error.message;
  }
  return close(run);
}

// The one inbound path: a board row edited in darkmem's UI.
export async function pull(ctx, { timeoutMs = 5000 } = {}) {
  if (!onDefaultBranch(ctx)) return null;
  const run = open(ctx, { timeoutMs });
  if (!run) return null;
  const { sync, report, cfg, call } = run;
  const uri = `${PREFIX}/board.md`;
  try {
    const remote = await getDocument(call, cfg.project, uri);
    const known = sync.documents[uri];
    const text = readText(ctx.paths.board);
    if (remote && known && remote.content_hash !== known.remote) {
      if (text !== null && sha256(text) !== known.local) report.conflict = `${uri} changed on darkmem and in the repository; nothing was overwritten`;
      else {
        fs.writeFileSync(ctx.paths.board, remote.content);
        sync.documents[uri] = { ...known, local: sha256(remote.content), remote: remote.content_hash };
        report.documents.push(uri);
      }
    }
  } catch (error) {
    if (!(error instanceof HttpError) && !(error instanceof TransportError)) throw error;
    report.error = error.message;
  }
  return close(run);
}

export async function writeCheckpoint(ctx, { timeoutMs = 5000 } = {}) {
  const run = open(ctx, { timeoutMs });
  const state = loadState(ctx.paths);
  const active = activePlan(ctx, state);
  if (!run || !active) return null;
  const tasks = taskStates(active.plan, planState(state, active.slug));
  const upcoming = nextTask(tasks);
  const body = `${tasks.filter(task => task.done).length}/${tasks.length} tasks done · ${upcoming ? `next: Task ${upcoming.number} ${upcoming.title}` : 'no task ready'} · ${currentBranch(ctx.root)} @ ${shortSha(head(ctx.root))}`;
  if (run.sync.checkpoint === body) return null;
  try {
    await append(run, active.slug, [{ kind: 'checkpoint', body, properties: {} }]);
    run.sync.checkpoint = body;
  } catch (error) {
    if (!(error instanceof HttpError) && !(error instanceof TransportError)) throw error;
    run.report.error = error.message;
  }
  return close(run);
}

export async function closeStream(ctx, slug, { timeoutMs = 5000 } = {}) {
  const run = open(ctx, { timeoutMs });
  if (!run) return null;
  try {
    const resumed = await run.call('GET', '/api/v1/worklog/resume', { query: { project: run.cfg.project, workstream: slug } });
    const id = resumed?.workstream?.id;
    if (id) await run.call('PATCH', `/api/v1/worklog/workstreams/${encodeURIComponent(id)}`, { body: { state: 'closed' } });
  } catch (error) {
    if (!(error instanceof HttpError) && !(error instanceof TransportError)) throw error;
    run.report.error = error.message;
  }
  return close(run);
}
