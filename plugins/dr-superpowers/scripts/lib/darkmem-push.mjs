// darkmem-sync push (darkmem mirror spec §3): send the mirror's local changes
// to darkmem. Documents go up under the recorded hash, so a document that moved
// on darkmem is a conflict rather than an overwrite; a ledger goes up as the
// bytes appended since the last push, never as a rewrite. Every write whose
// answer may have been lost is reconciled against darkmem before it is retried,
// so a retry never sends the same bytes twice.
import fs from "node:fs";
import path from "node:path";
import { HttpError } from "./darkmem-client.mjs";
import {
  DOC_PREFIX, EMPTY_SHA, MAX_ENTRIES_PER_APPEND, MAX_ENTRY_CHARS, UsageError, checkpointTarget, decodeUtf8,
  ledgerFiles, ledgerPlanPath, listDocumentFiles, propertiesFor, sha256, splitAtLimit, unsupportedPlanDirs, validKey,
} from "./darkmem-mirror.mjs";
import { ledgerText } from "./darkmem-pull.mjs";

const RESOLVE = "pull, reconcile, then push";
const HANDOFF_URI = new RegExp(`^${DOC_PREFIX}/handoff/([^/]+)\\.md$`);

// A handoff note filed after its workstream began: point the workstream at it.
async function linkHandoff({ cfg, client }, uri) {
  const slug = HANDOFF_URI.exec(uri)?.[1];
  if (!slug) return;
  const existing = await client.resume(cfg.project, slug);
  if (existing && existing.workstream.properties?.handoff_uri !== uri) {
    await client.updateWorkstream(existing.workstream.id, { properties: { handoff_uri: uri } });
  }
}

async function pushDocuments(context) {
  const { cfg, client, roots, state, persist, report } = context;
  let remote = null;
  const remoteHash = async uri => {
    remote ??= new Map((await client.manifest(cfg.project, DOC_PREFIX)).map(item => [item.uri, item.content_hash]));
    return remote.get(uri) ?? null;
  };
  for (const { file, uri } of listDocumentFiles(roots)) {
    if (!uri) {
      report.notes.push(`${path.relative(roots.docsRoot, file).split(path.sep).join("/")}: the docs root's handoff/ directory is reserved, not pushed`);
      continue;
    }
    const buffer = fs.readFileSync(file);
    const local = sha256(buffer);
    const recorded = state.documents[uri];
    if (local === recorded) continue;
    const content = decodeUtf8(buffer);
    if (!content) {
      report.failures.push(`${uri}: empty or not UTF-8 text, which darkmem cannot store; not pushed`);
      continue;
    }
    if (recorded === undefined) {
      const current = await remoteHash(uri);
      if (current === local) {
        state.documents[uri] = local;
        persist();
        await linkHandoff(context, uri);
        continue;
      }
      if (current !== null) {
        report.conflicts.push(`${uri}: darkmem already holds different content; ${RESOLVE}`);
        continue;
      }
    }
    let answer;
    try {
      answer = await client.putDocument({ project: cfg.project, uri, content, expectedHash: recorded });
    } catch (error) {
      if (error instanceof HttpError && error.status === 422) {
        report.failures.push(`${uri}: darkmem refused it: ${error.detail}`);
        continue;
      }
      if (!(error instanceof HttpError && error.status === 409)) throw error;
      // A 409 may be this mirror's own earlier put whose answer was lost.
      let current = null;
      try {
        current = (await client.getDocument(cfg.project, uri)).content_hash;
      } catch (readError) {
        if (!(readError instanceof HttpError && readError.status === 404)) throw readError;
        report.conflicts.push(`${uri}: deleted on darkmem since the last sync; ${RESOLVE}`);
        continue;
      }
      if (current !== local) {
        report.conflicts.push(`${uri}: changed on darkmem since the last sync (darkmem said: ${error.detail}); ${RESOLVE}`);
        continue;
      }
      answer = { content_hash: current, outcome: "unchanged" };
    }
    state.documents[uri] = answer.content_hash;
    persist();
    report.counts.documents += 1;
    if (recorded === undefined && answer.outcome === "updated") {
      // darkmem has no create-only put: another client filed this uri between
      // the manifest read and this put, and its content was replaced.
      report.failures.push(`${uri}: another client filed it during this push, and this push replaced its content`);
    }
    await linkHandoff(context, uri);
  }
}

// What darkmem already holds of a ledger, adopted when it is a prefix of the
// file: used for a ledger this mirror never synced (a lost state file) and for
// one whose last append may have landed without an answer.
async function adoptRemoteLedger({ cfg, client }, slug, buffer) {
  const existing = await client.resume(cfg.project, slug);
  if (!existing) return { offset: 0, prefix: EMPTY_SHA };
  const remote = Buffer.from(await ledgerText(client, existing.workstream.id), "utf8");
  if (buffer.length >= remote.length && buffer.subarray(0, remote.length).equals(remote)) {
    return { offset: remote.length, prefix: sha256(remote) };
  }
  return null;
}

async function pushLedgers(context) {
  const { cfg, client, roots, state, persist, report } = context;
  for (const dir of unsupportedPlanDirs(roots.workRoot)) {
    report.failures.push(`${dir}: not a usable workstream key; rename the directory to letters, digits, '.', '_' or '-'`);
  }
  for (const { slug, file } of ledgerFiles(roots.workRoot)) {
    const buffer = fs.readFileSync(file);
    let record = state.ledgers[slug];
    let adopted = false;
    if (!record || record.pending) {
      adopted = true;
      record = await adoptRemoteLedger(context, slug, buffer);
      if (!record) {
        report.conflicts.push(`sdd/${slug}/progress.md: darkmem's ledger for ${slug} is not a prefix of this file; move the local file aside, pull, and re-apply your lines`);
        continue;
      }
      state.ledgers[slug] = record;
      persist();
    }
    if (buffer.length < record.offset || sha256(buffer.subarray(0, record.offset)) !== record.prefix) {
      report.conflicts.push(`sdd/${slug}/progress.md: rewritten rather than appended to; refusing to push it`);
      continue;
    }
    if (buffer.length === record.offset) continue;
    // Another mirror may have appended since the last sync: send only what
    // darkmem does not already hold, and never lines that would interleave.
    if (!adopted) {
      const current = await adoptRemoteLedger(context, slug, buffer);
      if (!current || current.offset < record.offset) {
        report.conflicts.push(`sdd/${slug}/progress.md: darkmem's ledger for ${slug} changed since the last sync and no longer matches this file; move the local file aside, pull, and re-apply your lines`);
        continue;
      }
      if (current.offset !== record.offset) {
        record = current;
        state.ledgers[slug] = record;
        persist();
        if (buffer.length === record.offset) continue;
      }
    }
    const appended = decodeUtf8(buffer.subarray(record.offset));
    if (appended === null) {
      report.notes.push(`sdd/${slug}/progress.md: the appended bytes end inside a character; push again once the write finishes`);
      continue;
    }
    const properties = propertiesFor(roots, slug, ledgerPlanPath(buffer.toString("utf8")));
    const pieces = splitAtLimit(appended);
    for (let i = 0; i < pieces.length; i += MAX_ENTRIES_PER_APPEND) {
      const group = pieces.slice(i, i + MAX_ENTRIES_PER_APPEND);
      // Marked before the call: if the answer is lost, or this process dies
      // before the offset is saved, the next push reconciles instead of
      // re-sending.
      state.ledgers[slug] = { ...record, pending: true };
      persist();
      try {
        await client.append({ project: cfg.project, workstream: slug, properties, entries: group.map(body => ({ kind: "ledger", body })) });
      } catch (error) {
        if (!(error instanceof HttpError && error.status === 422)) throw error;
        state.ledgers[slug] = record;
        persist();
        report.failures.push(`sdd/${slug}/progress.md: darkmem refused an entry: ${error.detail}`);
        break;
      }
      const offset = record.offset + Buffer.byteLength(group.join(""), "utf8");
      record = { offset, prefix: sha256(buffer.subarray(0, offset)) };
      state.ledgers[slug] = record;
      persist();
      report.counts["ledger entries"] += group.length;
    }
  }
}

async function pushCheckpoint({ cfg, client, roots, state, persist, report }, named) {
  const file = path.join(roots.workRoot, "handoff", "latest.md");
  if (!fs.existsSync(file)) return;
  const buffer = fs.readFileSync(file);
  const hash = sha256(buffer);
  if (hash === state.checkpoint) return;
  const body = decodeUtf8(buffer);
  if (!body) {
    report.failures.push("handoff/latest.md: empty or not UTF-8 text, not pushed");
    return;
  }
  const target = checkpointTarget(body);
  const workstream = named ?? target?.slug;
  if (!workstream) {
    report.failures.push("handoff/latest.md: its State section names no plan or draft; push again with --workstream KEY");
    return;
  }
  const chars = [...body].length;
  if (chars > MAX_ENTRY_CHARS) {
    report.failures.push(`handoff/latest.md: ${chars} characters, over the ${MAX_ENTRY_CHARS} one checkpoint holds`);
    return;
  }
  // The same note already filed since the last synced checkpoint (an earlier
  // push whose answer was lost, even behind another client's checkpoint) is
  // recorded, not filed twice.
  const existing = await client.resume(cfg.project, workstream);
  const since = state.checkpointAt ? Date.parse(state.checkpointAt) : -Infinity;
  const filed = existing && (await client.entries(existing.workstream.id, "checkpoint"))
    .find(entry => Date.parse(entry.created_at) >= since && sha256(Buffer.from(entry.body, "utf8")) === hash);
  if (filed) {
    state.checkpoint = hash;
    state.checkpointAt = filed.created_at;
    persist();
    return;
  }
  const properties = propertiesFor(roots, workstream, target && target.slug === workstream ? target.path : null);
  let answer;
  try {
    answer = await client.append({ project: cfg.project, workstream, properties, entries: [{ kind: "checkpoint", body }] });
  } catch (error) {
    if (!(error instanceof HttpError && error.status === 422)) throw error;
    report.failures.push(`handoff/latest.md: darkmem refused it: ${error.detail}`);
    return;
  }
  state.checkpoint = hash;
  state.checkpointAt = answer.workstream.last_entry_at;
  persist();
  report.counts.checkpoints += 1;
}

export async function push(context) {
  const named = context.options["--workstream"];
  if (named !== undefined && !validKey(named)) throw new UsageError(`--workstream ${JSON.stringify(named)} is not a workstream key`);
  Object.assign(context.report.counts, { documents: 0, "ledger entries": 0, checkpoints: 0 });
  await pushDocuments(context);
  await pushLedgers(context);
  await pushCheckpoint(context, named);
}
