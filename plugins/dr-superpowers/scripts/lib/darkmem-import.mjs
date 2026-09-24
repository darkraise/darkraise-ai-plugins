// darkmem-sync import (darkmem mirror spec §3): the one-time move of a
// repository's docs/superpowers/ and its local ledgers and handoff notes into
// darkmem. It reads the repository, never the mirror, and finishes by pulling
// everything it filed into a scratch directory with pull's own code and
// comparing bytes. A pull afterwards fills the real mirror.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { HttpError } from "./darkmem-client.mjs";
import {
  MAX_ENTRIES_PER_APPEND, decodeUtf8, emptyState, ledgerFiles, ledgerPlanPath, listDocumentFiles, propertiesFor,
  splitAtBlankLines, splitAtLimit, unsupportedPlanDirs, uriToLocal,
} from "./darkmem-mirror.mjs";
import { pullDocuments, pullLedgers } from "./darkmem-pull.mjs";

// The import's source snapshot. Every problem is collected, so one run names
// all of them.
function readSources(roots) {
  const problems = [];
  const documents = [];
  const ledgers = [];
  for (const dir of unsupportedPlanDirs(roots.workRoot)) problems.push(`${dir}: not a usable workstream key`);
  for (const { file, uri } of listDocumentFiles(roots)) {
    if (!uri) {
      problems.push(`${file}: docs/superpowers/handoff/ is reserved for handoff notes`);
      continue;
    }
    const buffer = fs.readFileSync(file);
    const content = decodeUtf8(buffer);
    if (!content) {
      problems.push(`${file}: empty or not UTF-8 text`);
      continue;
    }
    documents.push({ uri, buffer, content });
  }
  for (const { slug, file } of ledgerFiles(roots.workRoot)) {
    const buffer = fs.readFileSync(file);
    const text = decodeUtf8(buffer);
    if (!text) {
      problems.push(`${file}: empty or not UTF-8 text`);
      continue;
    }
    ledgers.push({ slug, buffer, text, mtime: fs.statSync(file).mtime.toISOString(), id: null });
  }
  return { problems, documents, ledgers };
}

async function importLedger({ cfg, client, report }, roots, ledger) {
  const pieces = splitAtBlankLines(ledger.text).flatMap(piece => splitAtLimit(piece));
  const properties = { ...propertiesFor(roots, ledger.slug, ledgerPlanPath(ledger.text)), imported_mtime: ledger.mtime };
  for (let i = 0; i < pieces.length; i += MAX_ENTRIES_PER_APPEND) {
    const entries = pieces.slice(i, i + MAX_ENTRIES_PER_APPEND).map(body => ({ kind: "ledger", body }));
    try {
      ledger.id = (await client.append({ project: cfg.project, workstream: ledger.slug, properties, entries })).workstream.id;
    } catch (error) {
      if (!(error instanceof HttpError && error.status === 422)) throw error;
      report.failures.push(`sdd/${ledger.slug}/progress.md: darkmem refused an entry: ${error.detail}`);
      ledger.id = null;
      return;
    }
  }
  await client.updateWorkstream(ledger.id, { state: "closed", retain: true });
  report.counts.workstreams += 1;
}

const sameBytes = (file, buffer) => fs.existsSync(file) && fs.readFileSync(file).equals(buffer);

async function verify(context, roots, snapshot) {
  const { report } = context;
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "darkmem-import-"));
  // A byte difference keeps the scratch copy for the operator to compare.
  let keepScratch = false;
  try {
    const scratchRoots = { docsRoot: path.join(scratch, "superpowers"), workRoot: path.join(scratch, "work") };
    const scratchContext = {
      ...context,
      roots: scratchRoots,
      state: emptyState(),
      persist: () => {},
      report: { conflicts: [], failures: [], notes: [], counts: { documents: 0, ledgers: 0 } },
    };
    await pullDocuments(scratchContext);
    const imported = snapshot.ledgers.filter(l => l.id).map(l => ({ id: l.id, key: l.slug }));
    await pullLedgers(scratchContext, imported);
    // Re-read after the pull, so an edit made while it ran fails the import too.
    const again = readSources(roots);
    const inventory = source => [...source.documents.map(d => d.uri), ...source.ledgers.map(l => `sdd/${l.slug}`)].sort().join("\n");
    const changed = inventory(again) !== inventory(snapshot)
      || again.documents.some((d, i) => !d.buffer.equals(snapshot.documents[i].buffer))
      || again.ledgers.some((l, i) => !l.buffer.equals(snapshot.ledgers[i].buffer));
    if (changed || again.problems.length) {
      report.failures.push("the source files changed during the import; run it again with --replace");
      return;
    }
    const differing = [
      ...snapshot.documents.filter(d => !sameBytes(uriToLocal(scratchRoots, d.uri), d.buffer)).map(d => d.uri),
      ...snapshot.ledgers.filter(l => !sameBytes(path.join(scratchRoots.workRoot, "sdd", l.slug, "progress.md"), l.buffer)).map(l => `sdd/${l.slug}/progress.md`),
    ];
    if (differing.length) {
      keepScratch = true;
      for (const name of differing) report.failures.push(`${name}: a pull of darkmem's copy differs from the source; compare under ${scratch}`);
      return;
    }
    report.notes.push("verified: a pull of every imported file reads back byte-identical");
  } finally {
    if (!keepScratch) fs.rmSync(scratch, { recursive: true, force: true });
  }
}

export async function importRepository(context) {
  const { cfg, client, report, options } = context;
  Object.assign(report.counts, { documents: 0, workstreams: 0 });
  const roots = { docsRoot: path.join(cfg.repoRoot, "docs", "superpowers"), workRoot: path.join(cfg.repoRoot, ".superpowers") };
  const snapshot = readSources(roots);
  if (snapshot.problems.length) {
    report.failures.push(...snapshot.problems);
    report.notes.push("nothing was imported");
    return;
  }
  const existing = new Map();
  for (const ledger of snapshot.ledgers) {
    const answer = await client.resume(cfg.project, ledger.slug);
    if (answer) existing.set(ledger.slug, answer.workstream.id);
  }
  if (existing.size && !options["--replace"]) {
    report.failures.push(`already in darkmem: ${[...existing.keys()].join(", ")}; run import --replace to purge and re-import them (needs an admin key)`);
    report.notes.push("nothing was imported");
    return;
  }
  // Purges come first: a key that may not purge stops the import before any
  // document is written.
  for (const id of existing.values()) await client.purgeWorkstream(id);
  for (const doc of snapshot.documents) {
    try {
      await client.putDocument({ project: cfg.project, uri: doc.uri, content: doc.content });
      report.counts.documents += 1;
    } catch (error) {
      if (!(error instanceof HttpError && error.status === 422)) throw error;
      report.failures.push(`${doc.uri}: darkmem refused it: ${error.detail}`);
    }
  }
  for (const ledger of snapshot.ledgers) await importLedger(context, roots, ledger);
  await verify(context, roots, snapshot);
}
