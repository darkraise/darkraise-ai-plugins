// darkmem-sync pull (darkmem mirror spec §3): bring the mirror up to darkmem.
// A local file with changes of its own is never overwritten: it is reported
// as a conflict and left for the agent to resolve.
import fs from "node:fs";
import path from "node:path";
import { failItem } from "./darkmem-client.mjs";
import { DOC_PREFIX, caseGroups, isoMicros, sha256, uriProblem, uriToLocal, validKey, writeFileAtomic } from "./darkmem-mirror.mjs";

const RESOLVE = "move the local file aside, pull, and re-apply your change";

const localHash = file => (fs.existsSync(file) ? sha256(fs.readFileSync(file)) : null);

// A workstream's ledger as a file: its ledger entries' bodies, in order, and
// the seq of the newest one (0 when it holds none), which the next append
// names as its expected_last_seq.
export async function remoteLedger(client, workstreamId) {
  const entries = await client.entries(workstreamId, "ledger");
  return { text: entries.map(entry => entry.body).join(""), lastSeq: entries.at(-1)?.seq ?? 0 };
}

// One manifest item whose hash differs from the mirror's copy. The local file
// is hashed again after the fetch, because an edit can land while the request
// is out.
async function pullDocument({ cfg, client, roots, state, persist, report }, item) {
  // Checked before the mapping, which refuses some of these names on its own
  // (a handoff uri needs a workstream key) and would only note them.
  const problem = uriProblem(item.uri);
  if (problem) {
    report.failures.push(`${item.uri}: ${problem}, so not every mirror can hold it as a file; not pulled — rename it on darkmem by hand`);
    return;
  }
  const file = uriToLocal(roots, item.uri);
  if (!file) {
    report.notes.push(`${item.uri}: has no place in the mirror, skipped`);
    return;
  }
  const local = localHash(file);
  if (local === item.content_hash) {
    state.documents[item.uri] = local;
    return;
  }
  // darkmem has not moved since the last sync: a local edit is push's to
  // send, not a conflict.
  if (local !== null && item.content_hash === state.documents[item.uri]) return;
  if (local !== null && local !== state.documents[item.uri]) {
    report.conflicts.push(`${item.uri}: changed locally and on darkmem; ${RESOLVE}`);
    return;
  }
  const doc = await client.getDocument(cfg.project, item.uri);
  if (typeof doc.content !== "string") {
    report.notes.push(`${item.uri}: darkmem holds no text for it, skipped`);
    return;
  }
  if (localHash(file) !== local) {
    report.conflicts.push(`${item.uri}: changed locally during the pull; ${RESOLVE}`);
    return;
  }
  writeFileAtomic(file, doc.content);
  state.documents[item.uri] = doc.content_hash;
  persist();
  report.counts.documents += 1;
}

// Every document under superpowers/. Uris that differ only in case are one
// file on a case-insensitive file system, so none of them is written.
export async function pullDocuments(context) {
  const { cfg, client, report } = context;
  let items;
  try {
    items = await client.manifest(cfg.project, DOC_PREFIX);
  } catch (error) {
    failItem(report, "document manifest", error, "; no document pulled");
    return;
  }
  const twins = caseGroups(items.map(item => item.uri));
  for (const group of twins) {
    report.conflicts.push(`${group.join(", ")}: differ only in case, which a case-insensitive file system holds as one file; none of them pulled — rename or delete all but one on darkmem by hand (the sync has no rename or delete route)`);
  }
  const held = new Set(twins.flat());
  for (const item of items) {
    if (!item.content_hash || held.has(item.uri)) continue;
    try {
      await pullDocument(context, item);
    } catch (error) {
      failItem(report, item.uri, error);
    }
  }
}

// Render each workstream's ledger entries into work/sdd/<key>/progress.md.
export async function pullLedgers({ client, roots, state, persist, report }, workstreams) {
  for (const ws of workstreams) {
    if (!validKey(ws.key)) {
      report.notes.push(`workstream ${JSON.stringify(ws.key)}: not usable as a directory name, skipped`);
      continue;
    }
    let ledger;
    try {
      ledger = await remoteLedger(client, ws.id);
    } catch (error) {
      failItem(report, `sdd/${ws.key}/progress.md`, error);
      continue;
    }
    const { text, lastSeq } = ledger;
    if (!text) continue;
    const remote = Buffer.from(text, "utf8");
    const synced = { offset: remote.length, prefix: sha256(remote), lastSeq };
    const file = path.join(roots.workRoot, "sdd", ws.key, "progress.md");
    const local = fs.existsSync(file) ? fs.readFileSync(file) : null;
    const record = state.ledgers[ws.key];
    if (local && local.length >= remote.length && local.subarray(0, remote.length).equals(remote)) {
      // Equal, or ahead by lines push has not sent yet.
      state.ledgers[ws.key] = synced;
    } else if (!local || (record && !record.pending && local.length === record.offset && sha256(local) === record.prefix)) {
      writeFileAtomic(file, remote);
      state.ledgers[ws.key] = synced;
      report.counts.ledgers += 1;
    } else {
      report.conflicts.push(`sdd/${ws.key}/progress.md: the local ledger and darkmem's have diverged; ${RESOLVE}`);
      continue;
    }
    persist();
  }
}

// latest.md is the most recent stop: the newest checkpoint across the open
// workstreams, taken when it is newer than the last checkpoint this mirror
// synced (by darkmem's own timestamps, never the file's mtime) and never over
// local edits that have not been pushed.
async function pullCheckpoint({ cfg, client, roots, state, persist, report }, open) {
  let newest = null;
  let unread = false;
  for (const ws of open) {
    let checkpoint;
    try {
      checkpoint = (await client.resume(cfg.project, ws.key))?.checkpoint;
    } catch (error) {
      failItem(report, "handoff/latest.md", error, ` (reading workstream ${ws.key}); not pulled`);
      unread = true;
      continue;
    }
    if (checkpoint && (!newest || isoMicros(checkpoint.created_at) > isoMicros(newest.created_at))) newest = checkpoint;
  }
  // Without every workstream's checkpoint the newest is unknown.
  if (!newest || unread) return;
  if (state.checkpointAt && isoMicros(newest.created_at) <= isoMicros(state.checkpointAt)) return;
  const file = path.join(roots.workRoot, "handoff", "latest.md");
  const remote = Buffer.from(newest.body, "utf8");
  const remoteHash = sha256(remote);
  const local = localHash(file);
  if (local !== null && local !== remoteHash && local !== state.checkpoint) {
    report.conflicts.push(`handoff/latest.md: changed locally, and darkmem holds a newer checkpoint; ${RESOLVE}`);
    return;
  }
  if (local !== remoteHash) {
    writeFileAtomic(file, remote);
    report.counts.checkpoints += 1;
  }
  state.checkpoint = remoteHash;
  state.checkpointAt = newest.created_at;
  persist();
}

export async function pull(context) {
  Object.assign(context.report.counts, { documents: 0, ledgers: 0, checkpoints: 0 });
  await pullDocuments(context);
  let open;
  try {
    open = await context.client.workstreams(context.cfg.project, "open");
  } catch (error) {
    failItem(context.report, "workstream list", error, "; no ledger or checkpoint pulled");
    return;
  }
  await pullLedgers(context, open);
  await pullCheckpoint(context, open);
}
