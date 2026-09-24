// darkmem-sync pull (darkmem mirror spec §3): bring the mirror up to darkmem.
// A local file with changes of its own is never overwritten: it is reported
// as a conflict and left for the agent to resolve.
import fs from "node:fs";
import path from "node:path";
import { DOC_PREFIX, sha256, uriToLocal, validKey, writeFileAtomic } from "./darkmem-mirror.mjs";

const RESOLVE = "move the local file aside, pull, and re-apply your change";

const localHash = file => (fs.existsSync(file) ? sha256(fs.readFileSync(file)) : null);

// A workstream's ledger as a file: its ledger entries' bodies, in order.
export async function ledgerText(client, workstreamId) {
  return (await client.entries(workstreamId, "ledger")).map(entry => entry.body).join("");
}

// Every document under superpowers/ whose manifest hash differs from the
// mirror's copy. The local file is hashed again after the fetch, because an
// edit can land while the request is out.
export async function pullDocuments({ cfg, client, roots, state, persist, report }) {
  for (const item of await client.manifest(cfg.project, DOC_PREFIX)) {
    if (!item.content_hash) continue;
    const file = uriToLocal(roots, item.uri);
    if (!file) {
      report.notes.push(`${item.uri}: has no place in the mirror, skipped`);
      continue;
    }
    const local = localHash(file);
    if (local === item.content_hash) {
      state.documents[item.uri] = local;
      continue;
    }
    // darkmem has not moved since the last sync: a local edit is push's to
    // send, not a conflict.
    if (local !== null && item.content_hash === state.documents[item.uri]) continue;
    if (local !== null && local !== state.documents[item.uri]) {
      report.conflicts.push(`${item.uri}: changed locally and on darkmem; ${RESOLVE}`);
      continue;
    }
    const doc = await client.getDocument(cfg.project, item.uri);
    if (typeof doc.content !== "string") {
      report.notes.push(`${item.uri}: darkmem holds no text for it, skipped`);
      continue;
    }
    if (localHash(file) !== local) {
      report.conflicts.push(`${item.uri}: changed locally during the pull; ${RESOLVE}`);
      continue;
    }
    writeFileAtomic(file, doc.content);
    state.documents[item.uri] = doc.content_hash;
    persist();
    report.counts.documents += 1;
  }
}

// Render each workstream's ledger entries into work/sdd/<key>/progress.md.
export async function pullLedgers({ client, roots, state, persist, report }, workstreams) {
  for (const ws of workstreams) {
    if (!validKey(ws.key)) {
      report.notes.push(`workstream ${JSON.stringify(ws.key)}: not usable as a directory name, skipped`);
      continue;
    }
    const text = await ledgerText(client, ws.id);
    if (!text) continue;
    const remote = Buffer.from(text, "utf8");
    const synced = { offset: remote.length, prefix: sha256(remote) };
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
  for (const ws of open) {
    const checkpoint = (await client.resume(cfg.project, ws.key))?.checkpoint;
    if (checkpoint && (!newest || Date.parse(checkpoint.created_at) > Date.parse(newest.created_at))) newest = checkpoint;
  }
  if (!newest) return;
  if (state.checkpointAt && Date.parse(newest.created_at) <= Date.parse(state.checkpointAt)) return;
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
  const open = await context.client.workstreams(context.cfg.project, "open");
  await pullLedgers(context, open);
  await pullCheckpoint(context, open);
}
