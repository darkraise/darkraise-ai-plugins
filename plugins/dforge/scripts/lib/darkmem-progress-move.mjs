// The progress family's moves (darkmem store options spec §4): every
// checkout's plan ledgers and handoff notes, and the primary checkout's
// latest.md, into darkmem; and the mirror's back into the primary checkout.
// Nothing is deleted: a source is moved to a dated backup only after its
// copy reads back identical.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { HttpError, TransportError } from "./darkmem-client.mjs";
import { dforgeDir } from "./darkmem-config.mjs";
import { importLedger } from "./darkmem-import.mjs";
import {
  DOC_PREFIX, checkpointTarget, decodeUtf8, isoMicros, ledgerPieces, listDocumentFiles, newestCheckpointAt, propertiesFor,
  recordCheckpointAt, sha256, unsupportedPlanDirs, uriFamily, utcStamp, validKey, writeFileAtomic,
} from "./darkmem-mirror.mjs";
import { pullDocuments, pullLedgers, remoteLedger } from "./darkmem-pull.mjs";
import { inProgressReason, planFinished } from "./darkmem-reconcile.mjs";

const local = (base, rel) => path.join(base, ...rel.split("/"));

// `file`'s bytes, read without blocking on a FIFO or device: it throws an
// error whose code is EISDIR for a directory, EFTYPE for any other file that
// is not regular, or the open's or read's own (ENOENT, EACCES, ENOTDIR).
// Without `follow`, a symbolic link at the last component (a dangling one
// too) throws ELOOP; links earlier in the path are always followed. Function
// declarations, since darkmem-reconcile.mjs imports them across the import
// cycle between the two modules. Without O_NOFOLLOW or O_NONBLOCK (Windows,
// which has no FIFOs) a link is refused by lstat before the read, which
// leaves a window between the two. fs.constants cannot be stubbed, so a test
// passes a copy without them as `constants`.
export function readRegular(file, { follow = false } = {}, constants = fs.constants) {
  if (constants.O_NOFOLLOW === undefined || constants.O_NONBLOCK === undefined) {
    if (!follow && fs.lstatSync(file, { throwIfNoEntry: false })?.isSymbolicLink()) throw Object.assign(new Error(`${file} is a symbolic link`), { code: "ELOOP" });
    return fs.readFileSync(file);
  }
  const fd = fs.openSync(file, constants.O_RDONLY | constants.O_NONBLOCK | (follow ? 0 : constants.O_NOFOLLOW));
  try {
    const stat = fs.fstatSync(fd);
    if (!stat.isFile()) throw Object.assign(new Error(`${file} is not a regular file`), { code: stat.isDirectory() ? "EISDIR" : "EFTYPE" });
    return fs.readFileSync(fd);
  } finally {
    fs.closeSync(fd);
  }
}

export function readNoFollow(file, constants = fs.constants) {
  return readRegular(file, { follow: false }, constants);
}

// Each plan directory's progress.md that lstat finds, a dangling link
// included, so the read's link check names it. ledgerFiles' existsSync skips
// a dangling link, which its other callers rely on. An lstat that fails other
// than by ENOENT (EACCES, or ENOTDIR once the directory changed) keeps the
// file, so the callers' guarded read reports it instead of the listing throwing.
function ledgersIn(workRoot) {
  const sdd = path.join(workRoot, "sdd");
  let entries;
  try {
    entries = fs.readdirSync(sdd, { withFileTypes: true });
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
  return entries
    .filter(entry => entry.isDirectory() && validKey(entry.name))
    .map(entry => ({ slug: entry.name, file: path.join(sdd, entry.name, "progress.md") }))
    .filter(({ file }) => {
      try {
        return fs.lstatSync(file, { throwIfNoEntry: false }) !== undefined;
      } catch {
        return true;
      }
    })
    .sort((a, b) => (a.slug < b.slug ? -1 : a.slug > b.slug ? 1 : 0));
}

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
    const stateDir = dforgeDir("state", checkout);
    const sdd = path.join(stateDir, "sdd");
    // A linked plan directory is not listed as one, so its progress would be
    // left behind without a word. An sdd that cannot be listed is this
    // checkout's problem, and nothing under it is read.
    let entries;
    try {
      entries = fs.readdirSync(sdd, { withFileTypes: true });
    } catch (error) {
      if (error.code !== "ENOENT") {
        problems.push(`${sdd}: could not be read (${error.code})`);
        continue;
      }
      entries = [];
    }
    for (const entry of entries) {
      const dir = path.join(sdd, entry.name);
      if (entry.isSymbolicLink() && fs.statSync(dir, { throwIfNoEntry: false })?.isDirectory()) {
        problems.push(`${dir}: a symbolic link, which the move will not move files through`);
      }
    }
    for (const dir of unsupportedPlanDirs(stateDir)) problems.push(`${dir}: not a usable workstream key`);
    for (const { slug, file } of ledgersIn(stateDir)) files.push({ kind: "ledger", slug, file, stateDir, rel: `sdd/${slug}/progress.md` });
    for (const { file, uri } of listDocumentFiles({ workRoot: stateDir, families: { documents: false, progress: true } })) {
      const slug = path.basename(path.dirname(file));
      files.push({ kind: "handoff", slug, uri, file, stateDir, rel: `sdd/${slug}/handoff.md` });
    }
  }
  const primaryState = dforgeDir("state", cfg.repoRoot);
  const latest = path.join(primaryState, "handoff", "latest.md");
  if (fs.existsSync(latest)) files.push({ kind: "latest", file: latest, stateDir: primaryState, rel: "handoff/latest.md" });
  const sources = [];
  const byRel = new Map();
  for (const item of files) {
    // A linked file is never read through: it could lead anywhere, a FIFO included.
    try {
      item.buffer = readNoFollow(item.file);
    } catch (error) {
      problems.push(error.code === "ELOOP" ? `${item.file}: a symbolic link, which the move will not read through` : `${item.file}: could not be read (${error.code})`);
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

// How many of the ledger's import pieces darkmem's bytes are, when they are a
// proper prefix ending on a piece boundary; -1 otherwise.
function stoppedImport(held, buffer) {
  if (held.length >= buffer.length || !buffer.subarray(0, held.length).equals(held)) return -1;
  let at = 0;
  for (const [k, piece] of ledgerPieces(decodeUtf8(buffer)).entries()) {
    if (at === held.length) return k;
    if (at > held.length) return -1;
    at += Buffer.byteLength(piece, "utf8");
  }
  return -1;
}

// What darkmem and the mirror already hold at each source's place. A ledger
// darkmem holds byte for byte is already filed, and one an open workstream
// holds the first pieces of is a stopped import to resume, so a move stopped
// part-way runs again; any other existing copy that differs is a problem, so
// nothing is overwritten.
export async function checkProgressTargets({ cfg, client }, sources) {
  const problems = [];
  const filed = new Map();
  const partial = new Map();
  for (const item of sources) {
    const target = local(path.join(cfg.mirror, "work"), item.rel);
    if (!fs.existsSync(target)) continue;
    let held;
    try {
      held = readNoFollow(target);
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
      const { text, lastSeq } = await remoteLedger(client, existing.workstream.id);
      const held = Buffer.from(text, "utf8");
      const from = existing.workstream.state === "closed" ? -1 : stoppedImport(held, item.buffer);
      if (held.equals(item.buffer)) filed.set(item.slug, existing.workstream.id);
      else if (from >= 0) partial.set(item.slug, { id: existing.workstream.id, lastSeq, from });
      else problems.push(`${item.rel}: darkmem already holds a different ledger for workstream ${item.slug}`);
    }
  }
  return { problems, filed, partial };
}

const refuse = (reason, details = []) => ({ moved: false, reason, details });

// An answer from darkmem, or none, ends a move as a refusal; anything else is
// a bug and propagates.
function darkmemRefusal(error, details = []) {
  if (error instanceof TransportError || error instanceof HttpError) return refuse(`darkmem failed during the move: ${error.message}`, details);
  throw error;
}

// The report a move hands the sync code it reuses, so that code's lines
// become the move's details rather than the command's.
const scratchReport = () => ({ conflicts: [], failures: [], notes: [], counts: { workstreams: 0, documents: 0, ledgers: 0, checkpoints: 0 }, partial: false });

// The roots a checkout's progress reads its plans through: that checkout's
// own docs directory while documents are local, since a plan may exist only
// on its branch; the mirror's while they are darkmem.
const checkoutRoots = (cfg, stateDir) => ({
  docsRoot: cfg.documents.applied === "darkmem" ? cfg.documents.root : dforgeDir("docs", path.dirname(stateDir)),
  workRoot: stateDir,
  worktreeRoot: path.dirname(stateDir),
});

// The newest checkpoint darkmem holds across `workstreams`, with the key of
// the workstream that holds it as `workstream`, or null.
async function newestCheckpoint({ cfg, client }, workstreams) {
  let newest = null;
  for (const ws of workstreams) {
    const checkpoint = (await client.resume(cfg.project, ws.key))?.checkpoint;
    if (checkpoint && (!newest || isoMicros(checkpoint.created_at) > isoMicros(newest.created_at))) newest = { ...checkpoint, workstream: ws.key };
  }
  return newest;
}

// latest.md becomes a checkpoint of the plan or draft it names, so other
// machines receive it. The workstream follows that plan: an append reopens a
// closed one, so it stays open while the plan is active, and it is closed once
// completed.md records the plan, whether this append opened it or found it.
// One that names neither is copied unsent, dated at darkmem's newest
// checkpoint so a pull only replaces it with a newer one. Answers
// { hash, at, workstream, detail }, `workstream` naming the key `at` was read
// from (null with a null `at`), or { problem } when darkmem reads it back
// different.
async function fileLatest(context, item) {
  const { cfg, client } = context;
  const body = decodeUtf8(item.buffer);
  const hash = sha256(item.buffer);
  const target = checkpointTarget(body);
  if (!target) {
    const newest = await newestCheckpoint(context, await client.workstreams(cfg.project));
    return {
      hash, at: newest?.created_at ?? null, workstream: newest?.workstream ?? null,
      detail: "latest.md names no plan or draft; copied to the mirror, not sent",
    };
  }
  const before = await client.resume(cfg.project, target.slug);
  let at = before?.checkpoint && sha256(Buffer.from(before.checkpoint.body, "utf8")) === hash ? before.checkpoint.created_at : null;
  if (!at) {
    const properties = propertiesFor(checkoutRoots(cfg, item.stateDir), target.slug, target.path);
    const answer = await client.append({ project: cfg.project, workstream: target.slug, properties, entries: [{ kind: "checkpoint", body }] });
    at = answer.workstream.last_entry_at;
  }
  if (planFinished(cfg, path.dirname(item.stateDir), target.path)) {
    const after = await client.resume(cfg.project, target.slug);
    if (after.workstream.state !== "closed") await client.updateWorkstream(after.workstream.id, { state: "closed", retain: true });
  }
  const filed = (await client.resume(cfg.project, target.slug))?.checkpoint;
  if (!filed || sha256(Buffer.from(filed.body, "utf8")) !== hash) return { problem: "handoff/latest.md: darkmem's checkpoint reads back different" };
  return { hash, at, workstream: target.slug, detail: `latest.md filed as a checkpoint of ${target.slug}` };
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
  // The mirror's copies are read and written under its work directory, so a
  // link at the mirror, at work or below it would carry them elsewhere.
  const workRoot = path.join(cfg.mirror, "work");
  const linked = mirrorRefusal([...mirrorTop(cfg.mirror), ...mirrorLinks(workRoot)], "nothing was sent or moved");
  if (linked) return linked;
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
        await importLedger({ ...context, report }, checkoutRoots(cfg, item.stateDir), ledger, checked.partial.get(item.slug));
        if (ledger.id) ids.set(item.slug, ledger.id);
      } else if (item.kind === "handoff") {
        await client.putDocument({ project: cfg.project, uri: item.uri, content: decodeUtf8(item.buffer) });
      }
    }
    if (report.failures.length) {
      // Every handoff note was put (a put darkmem refuses throws), and ids
      // holds each ledger darkmem has in full.
      const held = [
        ...sources.filter(item => item.kind === "ledger" && ids.has(item.slug)).map(item => item.rel),
        ...sources.filter(item => item.kind === "handoff").map(item => item.uri),
      ];
      return refuse("darkmem refused part of the progress; nothing was moved locally, and darkmem keeps what it accepted", [
        ...report.failures,
        held.length ? `darkmem now holds in full: ${held.join(", ")}` : "darkmem now holds none of the progress in full",
        "a refused ledger keeps any entries darkmem accepted before the refusal, in its open workstream",
      ]);
    }
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
  // A plan may have started, or a ledger grown, while darkmem was written;
  // darkmem keeps what it was sent, and nothing local changes.
  const busy = inProgressReason(context);
  if (busy) return { moved: false, ...busy };
  const changed = [];
  for (const item of files) {
    let now;
    try {
      now = readNoFollow(item.file);
    } catch {
      now = null;
    }
    if (!now?.equals(item.buffer)) changed.push(`${item.file}: changed or removed during the move`);
  }
  if (changed.length) return refuse("progress changed in the checkouts during the move; nothing was moved locally", changed);
  // A link can be swapped into the mirror while darkmem is written, and the
  // atomic write follows one in any directory above the file it replaces.
  const relinked = mirrorRefusal([...mirrorTop(cfg.mirror), ...mirrorLinks(workRoot)], "nothing was sent or moved");
  if (relinked) return relinked;
  for (const item of sources) writeFileAtomic(local(workRoot, item.rel), item.buffer);
  const unread = sources.filter(item => {
    try {
      return !readNoFollow(local(workRoot, item.rel)).equals(item.buffer);
    } catch {
      return true;
    }
  });
  if (unread.length) return refuse("a copy into the mirror reads back different", unread.map(item => local(workRoot, item.rel)));
  for (const item of sources) {
    if (item.kind === "ledger") {
      state.ledgers[item.slug] = { offset: item.buffer.length, prefix: sha256(item.buffer), lastSeq: lastSeqs.get(item.slug) };
    } else if (item.kind === "handoff") {
      state.documents[item.uri] = sha256(item.buffer);
    } else {
      state.checkpoint = latest.hash;
      if (latest.at === null) state.checkpointAt = null;
      else recordCheckpointAt(state, latest.workstream, latest.at);
    }
  }
  persist();
  const aside = `moved-${utcStamp()}`;
  const backups = new Set();
  const left = [];
  for (const item of files) {
    const target = local(path.join(item.stateDir, aside), item.rel);
    try {
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.renameSync(item.file, target);
      backups.add(path.join(item.stateDir, aside));
    } catch (error) {
      left.push(`${item.file} (${error.code})`);
    }
  }
  // The checkout's state directory ignores itself, as .dforge/sdd/ does, so a
  // backup never shows as untracked in a repository that does not list it.
  // "wx" never writes through a link or over a file already there.
  const unignored = [];
  for (const stateDir of new Set(files.map(item => item.stateDir))) {
    if (fs.lstatSync(stateDir).isSymbolicLink()) continue;
    const file = path.join(stateDir, ".gitignore");
    try {
      fs.writeFileSync(file, "*\n", { flag: "wx" });
    } catch (error) {
      if (error.code === "EEXIST") continue;
      if (!error?.syscall) throw error;
      unignored.push({ file, code: error.code });
    }
  }
  // darkmem and the mirror already hold every source, so a rerun finds them
  // filed and moves aside only what is left.
  if (left.length) {
    const sourceCount = left.length === 1 ? "1 source" : `${left.length} sources`;
    const unwritten = unignored.map(({ file, code }) => `${file} (${code})`);
    return refuse(`darkmem and the mirror hold the progress, but ${sourceCount} could not be moved aside: ${left.join(", ")}${unwritten.length ? `, and ${unwritten.join(", ")} could not be written` : ""}; reconcile again to finish`);
  }
  const count = kind => sources.filter(item => item.kind === kind).length;
  return {
    moved: true,
    details: [
      `${count("ledger")} ledgers and ${count("handoff")} handoff notes in darkmem`,
      ...(latest ? [latest.detail] : []),
      ...[...backups].map(dir => `sources moved to ${dir}`),
      ...unignored.map(({ file, code }) => `${file} could not be written (${code})`),
    ],
  };
}

// The latest.md file for `newest`, unless the mirror's copy is newer or holds
// a local edit; pull's rule, applied across every workstream. A mirror that
// lost latest.md takes darkmem's newest again, however old.
function renderCheckpoint({ state, persist, report }, workRoot, newest) {
  if (!newest) return;
  const file = path.join(workRoot, "handoff", "latest.md");
  const synced = newestCheckpointAt(state);
  if (fs.existsSync(file) && synced && isoMicros(newest.created_at) <= isoMicros(synced)) return;
  const remote = Buffer.from(newest.body, "utf8");
  const hash = sha256(remote);
  let current = null;
  try {
    current = sha256(readNoFollow(file));
  } catch (error) {
    if (error.code !== "ENOENT") {
      report.failures.push(`handoff/latest.md: could not be read (${error.code})`);
      return;
    }
  }
  if (current !== null && current !== hash && current !== state.checkpoint) {
    report.conflicts.push("handoff/latest.md: changed locally, and darkmem holds a newer checkpoint");
    return;
  }
  try {
    if (current !== hash) writeFileAtomic(file, remote);
    state.checkpoint = hash;
    recordCheckpointAt(state, newest.workstream, newest.created_at);
    persist();
  } catch (error) {
    // persist's StateError, or a bug, propagates.
    if (!error?.syscall) throw error;
    report.failures.push(`handoff/latest.md: could not be written (${error.code})`);
    report.partial = true;
  }
}

// A file's bytes, or null when it does not exist; never read through a link.
function readOrNull(file) {
  try {
    return readNoFollow(file);
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

// The symbolic links at or below `stateRel` on the way to each rel, as
// checkout-relative paths; only the outermost link on a path is named.
function linksBelow(checkout, stateRel, rels) {
  const checked = new Set([stateRel]);
  for (const rel of rels) {
    const parts = `${stateRel}/${rel}`.split("/");
    for (let end = 1; end <= parts.length; end += 1) checked.add(parts.slice(0, end).join("/"));
  }
  const links = [];
  for (const rel of [...checked].sort()) {
    if (links.some(link => rel.startsWith(`${link}/`))) continue;
    let stat;
    try {
      stat = fs.lstatSync(path.join(checkout, ...rel.split("/")), { throwIfNoEntry: false });
    } catch {
      // A file where a directory belongs; the target read names it.
      continue;
    }
    if (stat?.isSymbolicLink()) links.push(rel);
  }
  return links;
}

const MIRROR_LINK = "a symbolic link in the mirror, which the move will not read through";

function mirrorTop(mirror) {
  return fs.lstatSync(mirror, { throwIfNoEntry: false })?.isSymbolicLink() ? [`${mirror}: ${MIRROR_LINK}`] : [];
}

// One line per symbolic link, or directory that cannot be listed, at or under the
// mirror's work directory. Dirent types come from lstat, so no link is followed.
function mirrorLinks(workRoot) {
  const lines = [];
  const walk = dir => {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (error) {
      if (error.code !== "ENOENT") lines.push(`${dir}: could not be listed (${error.code})`);
      return;
    }
    for (const entry of entries) {
      const file = path.join(dir, entry.name);
      if (entry.isSymbolicLink()) lines.push(`${file}: ${MIRROR_LINK}`);
      else if (entry.isDirectory()) walk(file);
    }
  };
  let top;
  try {
    top = fs.lstatSync(workRoot, { throwIfNoEntry: false });
  } catch (error) {
    return [`${workRoot}: could not be listed (${error.code})`];
  }
  if (top?.isSymbolicLink()) return [`${workRoot}: ${MIRROR_LINK}`];
  walk(workRoot);
  return lines;
}

// The refusal for mirrorLinks' lines, or null when there are none, saying
// whether the mirror could not be listed, is reached through links, or both.
function mirrorRefusal(lines, outcome) {
  if (!lines.length) return null;
  const found = [
    lines.some(line => !line.endsWith(MIRROR_LINK)) && "could not be listed",
    lines.some(line => line.endsWith(MIRROR_LINK)) && "is reached through symbolic links",
  ].filter(Boolean).join(", and ");
  return refuse(`the mirror's progress ${found}; ${outcome}`, lines);
}

// The mirror is brought up to darkmem first. A pull renders only open
// workstreams, and every imported ledger is closed, so this renders every
// workstream's ledger and the newest checkpoint across all of them; darkmem
// keeps its copy. Offline (darkmem disabled, unmapped or not answering) the
// mirror is copied as it stands.
export async function progressToLocal(context, { offline = null } = {}) {
  const { cfg, client, state, persist } = context;
  const workRoot = path.join(cfg.mirror, "work");
  const roots = { docsRoot: path.join(cfg.mirror, DOC_PREFIX), workRoot, worktreeRoot: cfg.repoRoot, families: { documents: false, progress: true } };
  // The pull below reads and rewrites the mirror's progress files, so a linked
  // one is refused before it, not only before the copies.
  const linked = mirrorRefusal(mirrorLinks(workRoot), "nothing was pulled or copied");
  if (linked) return linked;
  if (!offline) {
    const report = scratchReport();
    try {
      const pulling = { ...context, roots, report };
      await pullDocuments(pulling);
      const every = await client.workstreams(cfg.project);
      await pullLedgers(pulling, every);
      renderCheckpoint(pulling, workRoot, await newestCheckpoint(context, every));
    } catch (error) {
      return darkmemRefusal(error);
    }
    const unclean = [...report.conflicts.map(line => `conflict: ${line}`), ...report.failures.map(line => `failed: ${line}`)];
    if (unclean.length) return refuse("the pull into the mirror did not finish cleanly", unclean);
    // The pull can bring a workstream another machine opened since this
    // mirror's last pull, which reconcile's own check never saw.
    const busy = inProgressReason(context);
    if (busy) return refuse(busy.reason, busy.details);
  }
  const stateDir = dforgeDir("state", cfg.repoRoot);
  const problems = unsupportedPlanDirs(workRoot).map(dir => `${dir}: not a usable workstream key`);
  const sources = [
    ...ledgersIn(workRoot).map(({ slug, file }) => ({ file, rel: `sdd/${slug}/progress.md` })),
    ...listDocumentFiles(roots).map(({ file }) => ({ file, rel: `sdd/${path.basename(path.dirname(file))}/handoff.md` })),
  ];
  const latest = path.join(workRoot, "handoff", "latest.md");
  if (fs.existsSync(latest)) sources.push({ file: latest, rel: "handoff/latest.md" });
  // Copies and equality reads must not follow a link out of the checkout.
  const stateRel = path.relative(cfg.repoRoot, stateDir).split(path.sep).join("/");
  const links = linksBelow(cfg.repoRoot, stateRel, sources.map(item => item.rel));
  if (links.length) {
    return refuse(
      `${stateRel} is reached through symbolic links; nothing was copied`,
      links.map(rel => `${rel}: a symbolic link, which the move will not write through`),
    );
  }
  for (const item of sources) {
    item.target = local(stateDir, item.rel);
    try {
      item.buffer = readNoFollow(item.file);
    } catch (error) {
      problems.push(error.code === "ELOOP" ? `${item.file}: a symbolic link in the mirror, which the move will not read through` : `${item.file}: could not be read (${error.code})`);
      continue;
    }
    let held;
    try {
      held = readNoFollow(item.target);
    } catch (error) {
      if (error.code !== "ENOENT") problems.push(`${item.target}: could not be read (${error.code})`);
      continue;
    }
    if (!held.equals(item.buffer)) problems.push(`${item.target}: differs from the mirror's ${item.rel}`);
  }
  if (problems.length) return refuse("the primary checkout cannot take the mirror's progress", problems);
  // An edit can land in the checkout between the reads above and a copy: each
  // target is read again just before it is written, a new one is created
  // exclusively, and a failure part-way refuses, keeping what was copied.
  const landed = [];
  const copied = [];
  try {
    for (const item of sources) {
      fs.mkdirSync(path.dirname(item.target), { recursive: true });
      const now = readOrNull(item.target);
      if (now && !now.equals(item.buffer)) {
        landed.push(`${item.target}: changed during the move; not overwritten`);
        continue;
      }
      if (!now) {
        // A file the exclusive copy finds there landed after the read above.
        try {
          fs.copyFileSync(item.file, item.target, fs.constants.COPYFILE_EXCL);
        } catch (error) {
          if (error.code !== "EEXIST") throw error;
          landed.push(`${item.target}: changed during the move; not overwritten`);
          continue;
        }
        copied.push(item);
      }
    }
    if (landed.length) {
      return refuse("the primary checkout changed during the move; nothing was overwritten", [...landed, ...copied.map(item => `${item.target}: copied`)]);
    }
    const differing = sources.filter(item => !readOrNull(item.target)?.equals(item.buffer)).map(item => `${item.target}: the copy reads back different`);
    if (differing.length) return refuse("a copy into the primary checkout reads back different", differing);
  } catch (error) {
    return refuse(
      `a copy into the primary checkout failed (${error.code}); the files copied so far stay, and a rerun copies the rest`,
      copied.map(item => `${item.target}: copied`),
    );
  }
  const details = [`${sources.length} files copied into ${stateDir}`];
  if (offline) details.push("darkmem was not consulted: ledger lines and handoffs not yet pushed stay off darkmem, and another machine's newer progress was not fetched");
  // Moved, not deleted: left in place, these copies would meet a later move
  // back to darkmem as differing files.
  if (fs.existsSync(workRoot)) {
    const aside = path.join(cfg.mirror, `work-moved-${utcStamp()}`);
    fs.renameSync(workRoot, aside);
    details.push(`the mirror's copies moved to ${aside}`);
  }
  state.ledgers = Object.create(null);
  state.checkpoint = null;
  state.checkpointAt = null;
  state.pendingLinks = [];
  for (const uri of Object.keys(state.documents)) {
    if (uriFamily(uri) === "progress") delete state.documents[uri];
  }
  persist();
  return { moved: true, details };
}
