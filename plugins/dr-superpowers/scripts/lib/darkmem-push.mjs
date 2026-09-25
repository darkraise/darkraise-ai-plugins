// darkmem-sync push (darkmem mirror spec §3): send the mirror's local changes
// to darkmem. Documents go up under the recorded hash, so a document that moved
// on darkmem is a conflict rather than an overwrite; a ledger goes up as the
// bytes appended since the last push, never as a rewrite. Every write whose
// answer may have been lost is reconciled against darkmem before it is retried,
// so a retry never sends the same bytes twice.
import fs from "node:fs";
import path from "node:path";
import { HttpError, failItem } from "./darkmem-client.mjs";
import {
  DOC_PREFIX, EMPTY_SHA, MAX_ENTRIES_PER_APPEND, MAX_ENTRY_CHARS, UsageError, caseGroups, checkpointTarget, decodeUtf8,
  isoMicros, ledgerFiles, ledgerPlanPath, listDocumentFiles, propertiesFor, sha256, splitAtLimit, unsupportedPlanDirs,
  uriProblem, utf8Fault, validKey,
} from "./darkmem-mirror.mjs";
import { remoteLedger } from "./darkmem-pull.mjs";

const RESOLVE = "pull, reconcile, then push";
// darkmem's own answer for a uri nothing is filed at; any other 404 (a wrong
// url, a missing route) is not evidence that the document was deleted.
const NOT_FILED = /^no document is filed at uri /;
const HANDOFF_URI = new RegExp(`^${DOC_PREFIX}/handoff/([^/]+)\\.md$`);

// A handoff note filed after its workstream began: point the workstream at it.
// The uri stays in pendingLinks until the workstream carries it, or has none
// yet (its first append carries the uri), so a failed link is retried by the
// next push rather than only by a later append.
async function linkHandoff({ cfg, client, state, persist, report }, uri) {
  const slug = HANDOFF_URI.exec(uri)?.[1];
  if (!slug) return;
  if (!state.pendingLinks.includes(uri)) {
    state.pendingLinks.push(uri);
    persist();
  }
  try {
    const existing = await client.resume(cfg.project, slug);
    if (existing && existing.workstream.properties?.handoff_uri !== uri) {
      await client.updateWorkstream(existing.workstream.id, { properties: { handoff_uri: uri } });
    }
  } catch (error) {
    failItem(report, `${uri}: linking it from workstream ${slug}`, error);
    return;
  }
  state.pendingLinks = state.pendingLinks.filter(item => item !== uri);
  persist();
}

// One changed document, sent under its recorded hash. `remote` is the
// manifest's uri -> content_hash map.
async function pushDocument(context, { uri, buffer, local, recorded }, remote) {
  const { cfg, client, state, persist, report } = context;
  const content = decodeUtf8(buffer);
  if (!content) {
    report.failures.push(`${uri}: empty or not UTF-8 text, which darkmem cannot store; not pushed`);
    return;
  }
  if (recorded === undefined) {
    const current = remote.get(uri) ?? null;
    if (current === local) {
      state.documents[uri] = local;
      persist();
      await linkHandoff(context, uri);
      return;
    }
    if (current !== null) {
      report.conflicts.push(`${uri}: darkmem already holds different content; ${RESOLVE}`);
      return;
    }
  }
  let answer;
  try {
    answer = await client.putDocument({ project: cfg.project, uri, content, expectedHash: recorded });
  } catch (error) {
    if (error instanceof HttpError && error.status === 422) {
      report.failures.push(`${uri}: darkmem refused it: ${error.detail}`);
      return;
    }
    if (!(error instanceof HttpError && error.status === 409)) throw error;
    // A 409 may be this mirror's own earlier put whose answer was lost.
    let current = null;
    try {
      current = (await client.getDocument(cfg.project, uri)).content_hash;
    } catch (readError) {
      if (!(readError instanceof HttpError && readError.status === 404 && NOT_FILED.test(readError.detail))) throw readError;
      report.conflicts.push(`${uri}: deleted on darkmem since the last sync; ${RESOLVE}`);
      return;
    }
    if (current !== local) {
      report.conflicts.push(`${uri}: changed on darkmem since the last sync (darkmem said: ${error.detail}); ${RESOLVE}`);
      return;
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

async function pushDocuments(context) {
  const { cfg, client, roots, state, report } = context;
  const files = listDocumentFiles(roots);
  const twins = caseGroups(files.map(({ uri }) => uri).filter(Boolean));
  for (const group of twins) {
    report.conflicts.push(`${group.join(", ")}: differ only in case, which a case-insensitive file system holds as one file; none of them pushed — rename all but one`);
  }
  const held = new Set(twins.flat());
  const changed = [];
  for (const { file, uri } of files) {
    if (!uri) {
      report.notes.push(`${path.relative(roots.docsRoot, file).split(path.sep).join("/")}: the docs root's handoff/ directory is reserved, not pushed`);
      continue;
    }
    if (held.has(uri)) continue;
    const buffer = fs.readFileSync(file);
    const local = sha256(buffer);
    const recorded = state.documents[uri];
    if (local === recorded) continue;
    const problem = uriProblem(uri);
    if (problem) {
      report.failures.push(`${uri}: ${problem}, so not every mirror can hold it as a file; not pushed`);
      continue;
    }
    changed.push({ uri, buffer, local, recorded });
  }
  if (!changed.length) return;
  let remote;
  try {
    remote = new Map((await client.manifest(cfg.project, DOC_PREFIX)).map(item => [item.uri, item.content_hash]));
  } catch (error) {
    failItem(report, "document manifest", error, "; no document pushed");
    return;
  }
  // Every spelling darkmem holds under each lower-case form: when it holds
  // A.md and a.md, a local a.md collides with A.md although a.md matches.
  const spellings = new Map();
  for (const uri of remote.keys()) spellings.set(uri.toLowerCase(), [...(spellings.get(uri.toLowerCase()) ?? []), uri]);
  for (const item of changed) {
    const twins = (spellings.get(item.uri.toLowerCase()) ?? []).filter(uri => uri !== item.uri).sort();
    if (twins.length) {
      report.conflicts.push(`${item.uri}: darkmem holds ${twins.join(", ")}, which differ only in case from it; not pushed — rename the local file, or rename or delete the others on darkmem by hand (the sync has no rename or delete route)`);
      continue;
    }
    try {
      await pushDocument(context, item, remote);
    } catch (error) {
      failItem(report, item.uri, error);
    }
  }
}

// What darkmem already holds of a ledger, adopted when it is a prefix of the
// file: used for a ledger this mirror never synced (a lost state file), for
// one whose last append may have landed without an answer, for a record from
// before lastSeq was kept, and after an append's precondition failed.
async function adoptRemoteLedger({ cfg, client }, slug, buffer) {
  const existing = await client.resume(cfg.project, slug);
  if (!existing) return { offset: 0, prefix: EMPTY_SHA, lastSeq: 0 };
  const { text, lastSeq } = await remoteLedger(client, existing.workstream.id);
  const remote = Buffer.from(text, "utf8");
  if (buffer.length >= remote.length && buffer.subarray(0, remote.length).equals(remote)) {
    return { offset: remote.length, prefix: sha256(remote), lastSeq };
  }
  return null;
}

// One ledger's appended bytes. Every append names the seq it expects to
// follow, so another mirror's append since the last sync is a 409 rather than
// interleaved lines; the 409 is reconciled once, and the bytes darkmem does
// not yet hold are sent.
async function pushLedger(context, slug, file) {
  const { cfg, client, roots, state, persist, report } = context;
  const label = `sdd/${slug}/progress.md`;
  const buffer = fs.readFileSync(file);
  let record = state.ledgers[slug];
  if (!record || record.pending || record.lastSeq === undefined) {
    record = await adoptRemoteLedger(context, slug, buffer);
    if (!record) {
      report.conflicts.push(`${label}: darkmem's ledger for ${slug} is not a prefix of this file; move the local file aside, pull, and re-apply your lines`);
      return;
    }
    state.ledgers[slug] = record;
    persist();
  }
  if (buffer.length < record.offset || sha256(buffer.subarray(0, record.offset)) !== record.prefix) {
    report.conflicts.push(`${label}: rewritten rather than appended to; refusing to push it`);
    return;
  }
  let reconciled = false;
  sending: while (buffer.length > record.offset) {
    const rest = buffer.subarray(record.offset);
    const appended = decodeUtf8(rest);
    if (appended === null) {
      const fault = utf8Fault(rest);
      if (fault.partial) report.notes.push(`${label}: the appended bytes end inside a character; push again once the write finishes`);
      else report.failures.push(`${label}: byte ${record.offset + fault.offset} is not UTF-8 text; not pushed`);
      return;
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
      let answer;
      try {
        answer = await client.append({
          project: cfg.project, workstream: slug, properties, expectedLastSeq: record.lastSeq,
          entries: group.map(body => ({ kind: "ledger", body })),
        });
      } catch (error) {
        if (!(error instanceof HttpError && (error.status === 409 || error.status === 422))) throw error;
        // Both answers wrote nothing, so the record stands as it was.
        state.ledgers[slug] = record;
        persist();
        if (error.status === 422) {
          report.failures.push(`${label}: darkmem refused an entry: ${error.detail}`);
          return;
        }
        const current = reconciled ? null : await adoptRemoteLedger(context, slug, buffer);
        if (!current || current.offset < record.offset) {
          report.conflicts.push(`${label}: darkmem's ledger for ${slug} changed since the last sync and no longer matches this file; move the local file aside, pull, and re-apply your lines`);
          return;
        }
        reconciled = true;
        record = current;
        state.ledgers[slug] = record;
        persist();
        continue sending;
      }
      const offset = record.offset + Buffer.byteLength(group.join(""), "utf8");
      record = { offset, prefix: sha256(buffer.subarray(0, offset)), lastSeq: answer.last_seq };
      state.ledgers[slug] = record;
      persist();
      report.counts["ledger entries"] += group.length;
    }
  }
}

async function pushLedgers(context) {
  const { roots, report } = context;
  for (const dir of unsupportedPlanDirs(roots.workRoot)) {
    report.failures.push(`${dir}: not a usable workstream key; rename the directory to letters, digits, '.', '_' or '-'`);
  }
  for (const { slug, file } of ledgerFiles(roots.workRoot)) {
    try {
      await pushLedger(context, slug, file);
    } catch (error) {
      // A pending mark set before a failed append stays: its answer may have
      // been lost, so the next push reconciles before sending.
      failItem(report, `sdd/${slug}/progress.md`, error);
    }
  }
}

async function pushCheckpoint(context, named) {
  try {
    await sendCheckpoint(context, named);
  } catch (error) {
    failItem(context.report, "handoff/latest.md", error);
  }
}

async function sendCheckpoint({ cfg, client, roots, state, persist, report }, named) {
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
  const since = (state.checkpointAt && isoMicros(state.checkpointAt)) ?? -Infinity;
  const filed = existing && (await client.entries(existing.workstream.id, "checkpoint"))
    .find(entry => isoMicros(entry.created_at) >= since && sha256(Buffer.from(entry.body, "utf8")) === hash);
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
  for (const uri of [...context.state.pendingLinks]) await linkHandoff(context, uri);
  await pushDocuments(context);
  await pushLedgers(context);
  await pushCheckpoint(context, named);
}
