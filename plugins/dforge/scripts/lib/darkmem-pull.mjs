// darkmem-sync pull (darkmem mirror spec §3): bring the mirror up to darkmem.
// A local file with changes of its own is never overwritten: it is reported
// as a conflict and left for the agent to resolve.
import fs from "node:fs";
import path from "node:path";
import { failItem } from "./darkmem-client.mjs";
import {
  DOC_PREFIX, caseGroups, checkpointAtOf, checkpointTarget, decodeUtf8, familiesOf, handoffMarker, isArchiveUri, isoMicros, newestCheckpointAt, recordCheckpointAt, refuseLinkedDirs, sha256, uriFamily, uriProblem,
  uriToLocal, usableHandoffKey, validKey, writeFileAtomic,
} from "./darkmem-mirror.mjs";
import { readRegular } from "./darkmem-progress-move.mjs";

const RESOLVE = "move the local file aside, pull, and re-apply your change";

// The mirror, which holds both roots: nothing a pull writes or removes may be
// reached through a symbolic link below it.
const mirrorOf = roots => path.dirname(roots.workRoot);

// A mirror file's bytes, or null when there is none; a named pipe or other
// non-file throws rather than blocking the pull.
function localBytes(file) {
  try {
    return readRegular(file, { follow: true });
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

const localHash = file => {
  const bytes = localBytes(file);
  return bytes && sha256(bytes);
};

const sameFile = (a, b) => {
  try {
    const x = fs.statSync(a), y = fs.statSync(b);
    return x.dev === y.dev && x.ino === y.ino;
  } catch {
    return false;
  }
};

// A workstream's ledger as a file: its ledger entries' bodies, in order, and
// the seq of the newest one (0 when it holds none), which the next append
// names as its expected_last_seq.
export async function remoteLedger(client, workstreamId) {
  const entries = await client.entries(workstreamId, "ledger");
  return { text: entries.map(entry => entry.body).join(""), lastSeq: entries.at(-1)?.seq ?? 0 };
}

// One manifest item whose hash differs from the mirror's copy. The local file
// is hashed again after the fetch, because an edit can land while the request
// is out. keepDeletions leaves a synced document deleted from the mirror to
// push, which archives it, while darkmem still holds the copy that was deleted.
async function pullDocument({ cfg, client, roots, state, persist, report }, item, keepDeletions) {
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
  refuseLinkedDirs(mirrorOf(roots), path.dirname(file));
  const local = localHash(file);
  if (local === item.content_hash) {
    state.documents[item.uri] = local;
    return;
  }
  const deleted = keepDeletions && local === null && state.documents[item.uri] !== undefined && uriFamily(item.uri) === "documents";
  if (deleted && item.content_hash === state.documents[item.uri]) return;
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
  writeFileAtomic(file, doc.content, mirrorOf(roots));
  state.documents[item.uri] = doc.content_hash;
  persist();
  report.counts.documents += 1;
  if (deleted) report.notes.push(`${item.uri}: deleted locally but changed on darkmem; darkmem's copy pulled back`);
}

// A synced document darkmem no longer holds was archived or deleted
// elsewhere: an unchanged local copy goes with it, an edited one stays. A
// name that case-folds to a uri darkmem still files, and reaches the same
// file, is that document on a case-insensitive file system, so it is never
// removed. A copy that cannot be read or removed is one item's failure.
function removeVanished({ roots, state, persist, report }, filed) {
  // Built once: darkmem can hold two twins of one fold.
  const byFold = new Map();
  for (const uri of filed) {
    if (isArchiveUri(uri)) continue;
    const fold = uri.toLowerCase();
    if (!byFold.has(fold)) byFold.set(fold, []);
    byFold.get(fold).push(uri);
  }
  for (const uri of Object.keys(state.documents).sort()) {
    if (filed.has(uri) || uriFamily(uri) !== "documents" || isArchiveUri(uri)) continue;
    const file = uriToLocal(roots, uri);
    if (!file) continue;
    const twins = (byFold.get(uri.toLowerCase()) ?? []).filter(other => other !== uri);
    if (twins.some(twin => sameFile(file, uriToLocal(roots, twin)))) {
      delete state.documents[uri];
      persist();
      continue;
    }
    try {
      refuseLinkedDirs(mirrorOf(roots), path.dirname(file));
      // Hashed directly before the removal, with nothing in between.
      const local = localHash(file);
      if (local !== null && local !== state.documents[uri]) {
        report.conflicts.push(`${uri}: archived or deleted on darkmem, and changed locally; the local file stays — push it under a new name, or delete it`);
        continue;
      }
      if (local !== null) {
        fs.rmSync(file);
        report.counts.removed = (report.counts.removed ?? 0) + 1;
      }
    } catch (error) {
      report.failures.push(`${uri}: archived or deleted on darkmem, and the local copy could not be checked or removed (${error.code}); it stays`);
      continue;
    }
    delete state.documents[uri];
    persist();
  }
}

// Every document under dforge/ but the archives. Uris that differ only
// in case are one file on a case-insensitive file system, so none of them is
// written. A docs root that is gone entirely is a lost mirror, not a set of
// deletions, so every document is pulled back into it.
export async function pullDocuments(context) {
  const { cfg, client, roots, report } = context;
  let items;
  try {
    items = await client.manifest(cfg.project, DOC_PREFIX);
  } catch (error) {
    failItem(report, "document manifest", error, "; no document pulled");
    return;
  }
  const families = familiesOf(roots);
  const keepDeletions = families.documents && fs.existsSync(roots.docsRoot);
  const filed = new Set(items.map(item => item.uri));
  items = items.filter(item => !isArchiveUri(item.uri) && families[uriFamily(item.uri)]);
  const twins = caseGroups(items.map(item => item.uri));
  for (const group of twins) {
    report.conflicts.push(`${group.join(", ")}: differ only in case, which a case-insensitive file system holds as one file; none of them pulled — rename or delete all but one on darkmem by hand (the sync has no rename or delete route)`);
  }
  const held = new Set(twins.flat());
  for (const item of items) {
    if (!item.content_hash || held.has(item.uri)) continue;
    try {
      await pullDocument(context, item, keepDeletions);
    } catch (error) {
      if (!error?.syscall) {
        failItem(report, item.uri, error);
        continue;
      }
      report.failures.push(`${item.uri}: the local copy could not be read or written (${error.code}); not pulled`);
      report.partial = true;
    }
  }
  if (families.documents) removeVanished(context, filed);
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
    try {
      const local = localBytes(file);
      const record = state.ledgers[ws.key];
      if (local && local.length >= remote.length && local.subarray(0, remote.length).equals(remote)) {
        // Equal, or ahead by lines push has not sent yet.
        state.ledgers[ws.key] = synced;
      } else if (!local || (record && !record.pending && local.length === record.offset && sha256(local) === record.prefix)) {
        writeFileAtomic(file, remote, mirrorOf(roots));
        state.ledgers[ws.key] = synced;
        report.counts.ledgers += 1;
      } else {
        report.conflicts.push(`sdd/${ws.key}/progress.md: the local ledger and darkmem's have diverged; ${RESOLVE}`);
        continue;
      }
      persist();
    } catch (error) {
      // persist's StateError, or a bug, is not this ledger's failure.
      if (!error?.syscall) throw error;
      report.failures.push(`sdd/${ws.key}/progress.md: the local ledger could not be read or written (${error.code}); not pulled`);
      report.partial = true;
    }
  }
}

// The handoff key a pulled checkpoint is written under: its marker's key=, or
// for a checkpoint without one the key the migration gives an older layout's
// handoff (the plan or draft its marker names, else adhoc-legacy-<marker at,
// else the checkpoint's time>). Null when that key fails the handoff key rule, which
// adds "latest" to the state's own key rule, or when no time can be read.
export function pulledKey(body, createdAt) {
  const last = (body.match(/^<!-- next-step: .* -->\r?$/gm) ?? []).at(-1);
  // key= runs to the next named word, so a key holding a space is read whole and refused.
  const named = last && / key=(.*?)(?= [a-z]+=| -->|$)/.exec(last.replace(/ subject=.*$/, ""))?.[1];
  const micros = isoMicros(createdAt);
  const at = (last && / at=(-?\d+) -->/.exec(last)?.[1]) ?? (micros === null ? null : String(Math.floor(micros / 1e6)));
  const subject = handoffMarker(body)?.subject;
  const key = named ?? (subject ? path.posix.basename(subject.replace(/\\/g, "/"), ".md") : at === null ? null : `adhoc-legacy-${at}`);
  return usableHandoffKey(key) ? key : null;
}

// Each open workstream's newest checkpoint is its handoff, written to
// work/handoff/<key>.md when it is newer than the checkpoint this mirror last
// synced for that workstream (by darkmem's own timestamps, never the file's
// mtime): its own checkpointAt, else the record's "*", else the record's
// newest, which the first pull after the upgrade stores under "*". A handoff
// superseded or consumed here is therefore not pulled back. Only a mirror
// that never synced a checkpoint takes the single newest. A pull never writes
// another key's file, nor over local edits that have not been pushed; of two
// workstreams naming one key the newer checkpoint is written.
export async function pullCheckpoints({ cfg, client, roots, state, persist, report, out }, open) {
  const isFirst = state.checkpointAt === null;
  if (!isFirst && typeof state.checkpointAt === "object" && state.checkpointAt["*"] === undefined) {
    state.checkpointAt["*"] = newestCheckpointAt(state);
    persist();
  }
  const found = [];
  let unread = false;
  for (const ws of open) {
    let checkpoint;
    try {
      checkpoint = (await client.resume(cfg.project, ws.key))?.checkpoint;
    } catch (error) {
      failItem(report, `handoff checkpoint of workstream ${ws.key}`, error, "; no handoff pulled");
      unread = true;
      continue;
    }
    if (!checkpoint) continue;
    const since = isFirst ? null : checkpointAtOf(state, ws.key);
    if (since && isoMicros(checkpoint.created_at) <= isoMicros(since)) continue;
    found.push({ checkpoint, workstream: ws.key });
  }
  // Without every workstream's checkpoint a newer one naming the same key may be missed.
  if (unread || found.length === 0) return;
  const newer = (a, b) => isoMicros(a.checkpoint.created_at) > isoMicros(b.checkpoint.created_at);
  const candidates = isFirst ? [found.reduce((best, one) => (newer(one, best) ? one : best))] : found;
  // A checkpoint that is not written (a refused key, or the older of two
  // naming one key) is recorded as seen, so a later pull neither repeats its
  // note nor writes it over the newer handoff.
  const seen = one => {
    recordCheckpointAt(state, one.workstream, one.checkpoint.created_at);
    persist();
  };
  const byKey = new Map();
  for (const one of candidates) {
    const key = pulledKey(one.checkpoint.body, one.checkpoint.created_at);
    if (key === null) {
      out(`skipped: workstream ${one.workstream}'s checkpoint names no usable handoff key; not pulled`);
      seen(one);
      continue;
    }
    const held = byKey.get(key);
    if (held && !newer(one, held)) seen(one);
    else {
      if (held) seen(held);
      byKey.set(key, one);
    }
  }
  for (const [key, { checkpoint, workstream }] of byKey) {
    const rel = `handoff/${key}.md`;
    const file = path.join(roots.workRoot, "handoff", `${key}.md`);
    const remote = Buffer.from(checkpoint.body, "utf8");
    const remoteHash = sha256(remote);
    let bytes;
    try {
      bytes = localBytes(file);
    } catch (error) {
      report.failures.push(`${rel}: could not be read (${error.code}); not pulled`);
      report.partial = true;
      continue;
    }
    const local = bytes && sha256(bytes);
    if (local !== null && local !== remoteHash && local !== state.checkpoints[key]) {
      report.conflicts.push(`${rel}: changed locally, and darkmem holds a newer checkpoint; ${RESOLVE}`);
      continue;
    }
    // The synced handoff may be another workstream's newer checkpoint for this
    // key, as when a closed workstream is reopened without a new checkpoint.
    if (local !== null && local !== remoteHash) {
      const owner = checkpointTarget(decodeUtf8(bytes) ?? "", { marker: true })?.slug;
      const ownerAt = owner ? checkpointAtOf(state, owner) : null;
      if (ownerAt && isoMicros(checkpoint.created_at) <= isoMicros(ownerAt)) {
        seen({ checkpoint, workstream });
        continue;
      }
    }
    try {
      if (local !== remoteHash) {
        writeFileAtomic(file, remote, mirrorOf(roots));
        report.counts.checkpoints += 1;
      }
      state.checkpoints[key] = remoteHash;
      recordCheckpointAt(state, workstream, checkpoint.created_at);
      if (isFirst) recordCheckpointAt(state, "*", checkpoint.created_at);
      persist();
    } catch (error) {
      if (!error?.syscall) throw error;
      report.failures.push(`${rel}: could not be written (${error.code}); not pulled`);
      report.partial = true;
    }
  }
}

export async function pull(context) {
  Object.assign(context.report.counts, { documents: 0, ledgers: 0, checkpoints: 0 });
  const families = familiesOf(context.roots);
  if (families.documents || families.progress) await pullDocuments(context);
  if (!families.progress) return;
  let open;
  try {
    open = await context.client.workstreams(context.cfg.project, "open");
  } catch (error) {
    failItem(context.report, "workstream list", error, "; no ledger or checkpoint pulled");
    return;
  }
  await pullLedgers(context, open);
  await pullCheckpoints(context, open);
}
