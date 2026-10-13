// The progress family's moves (darkmem store options spec §4): every
// checkout's plan ledgers and handoff notes, and the primary checkout's
// latest.md, into darkmem; and the mirror's back into the primary checkout.
// Nothing is deleted: a source is moved to a dated backup only after its
// copy reads back identical.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { HttpError, TransportError } from "./darkmem-client.mjs";
import { forgeDir } from "./darkmem-config.mjs";
import { importLedger } from "./darkmem-import.mjs";
import {
  DOC_PREFIX, checkpointTarget, decodeUtf8, isoMicros, ledgerFiles, listDocumentFiles, propertiesFor, sha256, unsupportedPlanDirs,
  utcStamp, writeFileAtomic,
} from "./darkmem-mirror.mjs";
import { remoteLedger } from "./darkmem-pull.mjs";

const local = (base, rel) => path.join(base, ...rel.split("/"));

// The primary checkout first, then every linked worktree git lists.
function checkouts(repoRoot) {
  const result = spawnSync("git", ["-C", repoRoot, "worktree", "list", "--porcelain"], { encoding: "utf8", timeout: 10000 });
  if (result.status !== 0) return { problem: `git worktree list failed in ${repoRoot}: ${(result.stderr || result.error?.message || "").trim()}` };
  const listed = result.stdout.split(/\r?\n/).filter(line => line.startsWith("worktree ")).map(line => line.slice("worktree ".length));
  return { dirs: [repoRoot, ...listed.filter(dir => path.resolve(dir) !== path.resolve(repoRoot))] };
}

// Every progress file the checkouts hold, and the sources a move carries: one
// per mirror path, since a worktree cut while a ledger existed holds a copy of
// it. Copies that differ, a plan directory that is not a workstream key, and
// empty or non-UTF-8 text are problems; every one is collected.
export function gatherLocalProgress(cfg) {
  const listed = checkouts(cfg.repoRoot);
  if (listed.problem) return { problems: [listed.problem], files: [], sources: [] };
  const problems = [];
  const files = [];
  for (const checkout of listed.dirs) {
    const stateDir = forgeDir("state", checkout);
    for (const dir of unsupportedPlanDirs(stateDir)) problems.push(`${dir}: not a usable workstream key`);
    for (const { slug, file } of ledgerFiles(stateDir)) files.push({ kind: "ledger", slug, file, stateDir, rel: `sdd/${slug}/progress.md` });
    for (const { file, uri } of listDocumentFiles({ workRoot: stateDir, families: { documents: false, progress: true } })) {
      const slug = path.basename(path.dirname(file));
      files.push({ kind: "handoff", slug, uri, file, stateDir, rel: `sdd/${slug}/handoff.md` });
    }
  }
  const primaryState = forgeDir("state", cfg.repoRoot);
  const latest = path.join(primaryState, "handoff", "latest.md");
  if (fs.existsSync(latest)) files.push({ kind: "latest", file: latest, stateDir: primaryState, rel: "handoff/latest.md" });
  const sources = [];
  const byRel = new Map();
  for (const item of files) {
    try {
      item.buffer = fs.readFileSync(item.file);
    } catch (error) {
      problems.push(`${item.file}: could not be read (${error.code})`);
      continue;
    }
    if (!decodeUtf8(item.buffer)) {
      problems.push(`${item.file}: empty or not UTF-8 text`);
      continue;
    }
    const seen = byRel.get(item.rel);
    if (!seen) {
      byRel.set(item.rel, item);
      sources.push(item);
    } else if (!seen.buffer.equals(item.buffer)) {
      problems.push(`${item.rel}: ${seen.file} and ${item.file} differ`);
    }
  }
  return { problems, files, sources };
}

// What darkmem and the mirror already hold at each source's place. A ledger
// darkmem holds byte for byte is already filed, so a move stopped part-way
// runs again; any other existing copy that differs is a problem, so nothing
// is overwritten.
export async function checkProgressTargets({ cfg, client }, sources) {
  const problems = [];
  const filed = new Map();
  for (const item of sources) {
    const target = local(path.join(cfg.mirror, "work"), item.rel);
    if (!fs.existsSync(target)) continue;
    let held;
    try {
      held = fs.readFileSync(target);
    } catch (error) {
      problems.push(`${target}: could not be read (${error.code})`);
      continue;
    }
    if (!held.equals(item.buffer)) problems.push(`${target}: the mirror already holds a different copy of ${item.rel}`);
  }
  const notes = new Map((await client.manifest(cfg.project, `${DOC_PREFIX}/handoff`)).map(doc => [doc.uri, doc.content_hash]));
  for (const item of sources) {
    if (item.kind === "handoff") {
      const hash = notes.get(item.uri);
      if (hash !== undefined && hash !== sha256(item.buffer)) problems.push(`${item.uri}: darkmem already holds a different handoff note`);
    } else if (item.kind === "ledger") {
      const existing = await client.resume(cfg.project, item.slug);
      if (!existing) continue;
      const { text } = await remoteLedger(client, existing.workstream.id);
      if (Buffer.from(text, "utf8").equals(item.buffer)) filed.set(item.slug, existing.workstream.id);
      else problems.push(`${item.rel}: darkmem already holds a different ledger for workstream ${item.slug}`);
    }
  }
  return { problems, filed };
}

const refuse = (reason, details = []) => ({ moved: false, reason, details });

// An answer from darkmem, or none, ends a move as a refusal; anything else is
// a bug and propagates.
function darkmemRefusal(error, details = []) {
  if (error instanceof TransportError) return refuse(`darkmem is unreachable: ${error.message}`, details);
  if (error instanceof HttpError) return refuse(`darkmem answered ${error.status}: ${error.detail}; nothing was moved locally`, details);
  throw error;
}

// The report a move hands the sync code it reuses, so that code's lines
// become the move's details rather than the command's.
const scratchReport = () => ({ conflicts: [], failures: [], notes: [], counts: { workstreams: 0, documents: 0, ledgers: 0, checkpoints: 0 }, partial: false });

// The roots a checkout's progress reads its plans through: that checkout's
// own docs directory while documents are local, since a plan may exist only
// on its branch; the mirror's while they are darkmem.
const checkoutRoots = (cfg, stateDir) => ({
  docsRoot: cfg.documents.applied === "darkmem" ? cfg.documents.root : forgeDir("docs", path.dirname(stateDir)),
  workRoot: stateDir,
  worktreeRoot: path.dirname(stateDir),
});

// The newest checkpoint darkmem holds across `workstreams`, or null.
async function newestCheckpoint({ cfg, client }, workstreams) {
  let newest = null;
  for (const ws of workstreams) {
    const checkpoint = (await client.resume(cfg.project, ws.key))?.checkpoint;
    if (checkpoint && (!newest || isoMicros(checkpoint.created_at) > isoMicros(newest.created_at))) newest = checkpoint;
  }
  return newest;
}

// latest.md becomes a checkpoint of the plan or draft it names, so other
// machines receive it; a workstream that was closed is closed again. One that
// names neither is copied unsent, dated at darkmem's newest checkpoint so a
// pull only replaces it with a newer one. Answers { hash, at, detail }, or
// { problem } when darkmem reads it back different.
async function fileLatest(context, item) {
  const { cfg, client } = context;
  const body = decodeUtf8(item.buffer);
  const hash = sha256(item.buffer);
  const target = checkpointTarget(body);
  if (!target) {
    const newest = await newestCheckpoint(context, await client.workstreams(cfg.project));
    return { hash, at: newest?.created_at ?? null, detail: "latest.md names no plan or draft; copied to the mirror, not sent" };
  }
  const before = await client.resume(cfg.project, target.slug);
  let at = before?.checkpoint && sha256(Buffer.from(before.checkpoint.body, "utf8")) === hash ? before.checkpoint.created_at : null;
  if (!at) {
    const properties = propertiesFor(checkoutRoots(cfg, item.stateDir), target.slug, target.path);
    const answer = await client.append({ project: cfg.project, workstream: target.slug, properties, entries: [{ kind: "checkpoint", body }] });
    at = answer.workstream.last_entry_at;
  }
  if (before?.workstream.state === "closed") {
    const after = await client.resume(cfg.project, target.slug);
    if (after.workstream.state !== "closed") await client.updateWorkstream(after.workstream.id, { state: "closed", retain: true });
  }
  const filed = (await client.resume(cfg.project, target.slug))?.checkpoint;
  if (!filed || sha256(Buffer.from(filed.body, "utf8")) !== hash) return { problem: "handoff/latest.md: darkmem's checkpoint reads back different" };
  return { hash, at, detail: `latest.md filed as a checkpoint of ${target.slug}` };
}

// The symbolic links between a checkout and its progress files. A source is
// moved aside by renaming it, and through a link two checkouts can list one
// file, so the second rename would fail after darkmem and the sync state were
// written.
function linksOnTheWay(files) {
  const links = new Set();
  for (const item of files) {
    let at = path.dirname(item.stateDir);
    for (const part of path.relative(at, item.file).split(path.sep)) {
      at = path.join(at, part);
      if (fs.lstatSync(at, { throwIfNoEntry: false })?.isSymbolicLink()) {
        links.add(at);
        break;
      }
    }
  }
  return [...links].sort();
}

export async function progressToDarkmem(context) {
  const { cfg, client, state, persist } = context;
  const { problems, files, sources } = gatherLocalProgress(cfg);
  if (problems.length) return refuse("the checkouts hold progress the move cannot carry", problems);
  const links = linksOnTheWay(files);
  if (links.length) {
    return refuse(
      "the checkouts' progress is reached through symbolic links; nothing was sent or moved",
      links.map(link => `${link}: a symbolic link, which the move will not move files through`),
    );
  }
  const report = scratchReport();
  const ids = new Map();
  const lastSeqs = new Map();
  let latest = null;
  try {
    const checked = await checkProgressTargets(context, sources);
    if (checked.problems.length) return refuse("darkmem or the mirror already holds different progress", checked.problems);
    // Every ledger here belongs to a finished plan (reconcile refuses while
    // one is in progress), so one a stopped move filed is closed like the rest.
    for (const [slug, id] of checked.filed) {
      ids.set(slug, id);
      await client.updateWorkstream(id, { state: "closed", retain: true });
    }
    for (const item of sources) {
      if (item.kind === "ledger" && !ids.has(item.slug)) {
        const ledger = { slug: item.slug, text: decodeUtf8(item.buffer), mtime: fs.statSync(item.file).mtime.toISOString(), id: null };
        await importLedger({ ...context, report }, checkoutRoots(cfg, item.stateDir), ledger);
        if (ledger.id) ids.set(item.slug, ledger.id);
      } else if (item.kind === "handoff") {
        await client.putDocument({ project: cfg.project, uri: item.uri, content: decodeUtf8(item.buffer) });
      }
    }
    if (report.failures.length) return refuse("darkmem refused part of the progress; nothing was moved locally", report.failures);
    const differing = [];
    for (const item of sources) {
      if (item.kind === "ledger") {
        const { text, lastSeq } = await remoteLedger(client, ids.get(item.slug));
        lastSeqs.set(item.slug, lastSeq);
        if (!Buffer.from(text, "utf8").equals(item.buffer)) differing.push(`${item.rel}: darkmem's copy reads back different`);
      } else if (item.kind === "handoff" && (await client.getDocument(cfg.project, item.uri)).content_hash !== sha256(item.buffer)) {
        differing.push(`${item.uri}: darkmem's copy reads back different`);
      }
    }
    if (differing.length) return refuse("a read-back of darkmem's copies differs; nothing was moved locally", differing);
    const latestItem = sources.find(item => item.kind === "latest");
    if (latestItem) {
      latest = await fileLatest(context, latestItem);
      if (latest.problem) return refuse("a read-back of darkmem's copies differs; nothing was moved locally", [latest.problem]);
    }
  } catch (error) {
    return darkmemRefusal(error, report.failures);
  }
  const workRoot = path.join(cfg.mirror, "work");
  for (const item of sources) writeFileAtomic(local(workRoot, item.rel), item.buffer);
  const unread = sources.filter(item => !fs.readFileSync(local(workRoot, item.rel)).equals(item.buffer));
  if (unread.length) return refuse("a copy into the mirror reads back different", unread.map(item => local(workRoot, item.rel)));
  for (const item of sources) {
    if (item.kind === "ledger") {
      state.ledgers[item.slug] = { offset: item.buffer.length, prefix: sha256(item.buffer), lastSeq: lastSeqs.get(item.slug) };
    } else if (item.kind === "handoff") {
      state.documents[item.uri] = sha256(item.buffer);
    } else {
      state.checkpoint = latest.hash;
      state.checkpointAt = latest.at;
    }
  }
  persist();
  const aside = `moved-${utcStamp()}`;
  const backups = new Set();
  for (const item of files) {
    const target = local(path.join(item.stateDir, aside), item.rel);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.renameSync(item.file, target);
    backups.add(path.join(item.stateDir, aside));
  }
  const count = kind => sources.filter(item => item.kind === kind).length;
  return {
    moved: true,
    details: [
      `${count("ledger")} ledgers and ${count("handoff")} handoff notes in darkmem`,
      ...(latest ? [latest.detail] : []),
      ...[...backups].map(dir => `sources moved to ${dir}`),
    ],
  };
}
