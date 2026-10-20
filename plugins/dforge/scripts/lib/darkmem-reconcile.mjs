// darkmem-sync reconcile (darkmem store options spec §4, §7.2): move each
// family whose configured store differs from its applied store, under §4's
// refusals, and record each completed move in ~/.dforge/stores.json.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { HttpError, TransportError } from "./darkmem-client.mjs";
import { dforgeDir, resolveStores, writeApplied } from "./darkmem-config.mjs";
import {
  DOC_PREFIX, caseGroups, decodeUtf8, isArchiveUri, ledgerPlanPath, listDocumentFiles, sha256, uriFamily, uriProblem, utcStamp,
} from "./darkmem-mirror.mjs";
import { progressToDarkmem, progressToLocal, readNoFollow, readRegular } from "./darkmem-progress-move.mjs";
import { pullDocuments } from "./darkmem-pull.mjs";

const FAMILIES = ["documents", "progress"];
// dr-forge wrote docs/forge, dr-superpowers docs/superpowers.
const LEGACY = ["docs/forge", "docs/superpowers"];
const DOCS = "docs/dforge";

// Each move, under "<family>:<target store>". A move answers
// { moved: true, details } or { moved: false, reason, details }.
const MOVES = {
  "documents:darkmem": documentsToDarkmem,
  "documents:local": documentsToLocal,
  "progress:darkmem": progressToDarkmem,
  "progress:local": progressToLocal,
};

// A git that could not be started or was timed out sets result.error and
// prints nothing, so its message stands in for the empty stderr.
export function runGit(cwd, args, input) {
  const result = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf8", timeout: 60000, input, maxBuffer: 64 * 1024 * 1024 });
  return { status: result.status, signal: result.signal, stdout: result.stdout ?? "", stderr: result.stderr || result.error?.message || "" };
}

const slash = file => file.split(path.sep).join("/");

// stat follows a link to its target's type, and reads nothing through it. A link whose target cannot be stat'd (dangling, EACCES) counts as a plan directory: nothing can show its plan finished.
const isDirectoryLink = file => {
  try {
    return fs.statSync(file).isDirectory();
  } catch {
    return true;
  }
};

// The directories under `dir`, a symbolic link to one included, as
// { name, linked }.
function dirEntries(dir) {
  try {
    return fs.readdirSync(dir, { withFileTypes: true })
      .filter(entry => entry.isDirectory() || (entry.isSymbolicLink() && isDirectoryLink(path.join(dir, entry.name))))
      .map(entry => ({ name: entry.name, linked: entry.isSymbolicLink() }))
      .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
}

// One document name under any docs prefix (spec §7.1), as dforge_name_key
// and dforge_name_spellings spell it in roots.sh. The older docs/forge and
// docs/superpowers spellings stay readable because historical plans and
// ledgers cite them.
export function nameSpellings(name) {
  const text = String(name).replace(/^\.\//, "").replace(/(.)\/+$/, "$1");
  const old = LEGACY.find(prefix => text === prefix || text.startsWith(`${prefix}/`));
  const key = old ? `${DOCS}${text.slice(old.length)}` : text;
  return key === DOCS || key.startsWith(`${DOCS}/`) ? [key, ...LEGACY.map(prefix => `${prefix}${key.slice(DOCS.length)}`)] : [key];
}

export function pendingFamilies(cfg) {
  return FAMILIES.filter(family => cfg[family].configured !== cfg[family].applied);
}

export function stayLine(cfg, family, reason) {
  return `darkmem-sync reconcile: ${family} stay ${cfg[family].applied} (configured ${cfg[family].configured}): ${reason}`;
}

// The mirror subtree one move reads or fills, with only that family synced.
export function mirrorRoots(cfg, family) {
  return {
    docsRoot: path.join(cfg.mirror, DOC_PREFIX),
    workRoot: path.join(cfg.mirror, "work"),
    worktreeRoot: cfg.repoRoot,
    families: { documents: family === "documents", progress: family === "progress" },
  };
}

// Re-reads the stores after a move, so the next move sees the roots the
// last one produced; cfg and roots are rebuilt as main builds them. Once a
// disabled or unmapped repository has moved every family back, the stores
// name no mirror, so the run keeps the one it started with.
export function refreshContext(context) {
  const stores = resolveStores({ cwd: context.cfg.worktreeRoot, env: context.env });
  const sync = stores.sync ?? { ...context.cfg, documents: undefined, progress: undefined };
  const cfg = { ...sync, repoRoot: stores.repoRoot, worktreeRoot: stores.worktreeRoot, documents: stores.documents, progress: stores.progress };
  context.cfg = cfg;
  context.roots = {
    docsRoot: cfg.documents.root,
    workRoot: path.join(cfg.mirror, "work"),
    worktreeRoot: cfg.worktreeRoot,
    families: { documents: cfg.documents.applied === "darkmem", progress: cfg.progress.applied === "darkmem" },
  };
}

export function leftoverLines(cfg) {
  if (cfg.documents.applied !== "darkmem" || !cfg.worktreeRoot) return [];
  return [path.join(cfg.worktreeRoot, "docs", "dforge")]
    .filter(dir => fs.existsSync(dir))
    .map(dir => `darkmem-sync reconcile: ${dir} is not read while documents are applied darkmem`);
}

function worktreeTops(cfg) {
  const listing = runGit(cfg.repoRoot, ["worktree", "list", "--porcelain"]);
  return listing.status === 0
    ? listing.stdout.split(/\r?\n/).filter(line => line.startsWith("worktree ")).map(line => line.slice("worktree ".length))
    : [cfg.repoRoot];
}

// Where the ledgers live: every worktree's state directory while progress is
// local, the mirror's work tree while it is darkmem.
function ledgerSources(cfg) {
  if (cfg.progress.applied === "darkmem") return [{ sdd: path.join(cfg.mirror, "work", "sdd"), checkout: cfg.repoRoot }];
  return worktreeTops(cfg).map(tree => ({ sdd: path.join(dforgeDir("state", tree), "sdd"), checkout: tree }));
}

function planFile(cfg, checkout, name) {
  if (path.isAbsolute(name)) return name;
  const [key] = nameSpellings(name);
  if (key === DOCS || key.startsWith(`${DOCS}/`)) {
    const docsRoot = cfg.documents.applied === "darkmem" ? path.join(cfg.mirror, DOC_PREFIX) : dforgeDir("docs", checkout);
    return path.join(docsRoot, ...key.slice(DOCS.length).split("/").filter(Boolean));
  }
  return path.join(checkout, key);
}

const realOr = file => {
  try {
    return fs.realpathSync(file);
  } catch {
    return path.resolve(file);
  }
};

// The name an absolute ledger identity stands for, computed from the roots and
// never by searching for a docs segment (as pathToUri does): the docs root in
// use, this checkout's docs directory and top level, and the primary checkout's
// and every other worktree's (a ledger the mirror holds is checked from the
// primary, whichever worktree wrote it), tried as written and then with
// symbolic links resolved. The deepest of these roots that holds the name wins,
// so a worktree nested inside the primary checkout is not taken for the
// primary's own files. A relative name, or an absolute one under no root, is
// unchanged.
function rootedName(cfg, checkout, name) {
  if (!path.isAbsolute(name)) return name;
  const bases = [
    [dforgeDir("docs", checkout), DOCS],
    [checkout, null],
    [dforgeDir("docs", cfg.repoRoot), DOCS],
    [cfg.repoRoot, null],
    ...worktreeTops(cfg).flatMap(tree => [[dforgeDir("docs", tree), DOCS], [tree, null]]),
  ];
  if (cfg.documents.applied === "darkmem") bases.unshift([path.join(cfg.mirror, DOC_PREFIX), DOCS]);
  for (const resolve of [file => path.resolve(file), realOr]) {
    let best = null;
    for (const [base, prefix] of bases) {
      const root = resolve(base);
      const rel = path.relative(root, resolve(name));
      if (rel && rel !== ".." && !rel.startsWith(`..${path.sep}`) && !path.isAbsolute(rel)
        && (!best || root.length > best.root.length)) best = { root, rel, prefix };
    }
    if (best) {
      const posix = best.rel.split(path.sep).join("/");
      return best.prefix ? `${best.prefix}/${posix}` : posix;
    }
  }
  return name;
}

// Matched on the backticked name, as plan_finished does, so one plan's name
// that is a substring of another's cannot claim its outcome. An absolute
// identity is mapped first and completed.md is found from the mapped name: the
// directory the absolute path names is gone once the documents have moved. An
// identity no root maps is never finished, whatever lies beside it.
export function planFinished(cfg, checkout, identity) {
  const name = rootedName(cfg, checkout, identity);
  if (path.isAbsolute(name)) return false;
  let text;
  try {
    text = readRegular(path.join(path.dirname(planFile(cfg, checkout, name)), "completed.md"), { follow: true }).toString("utf8");
  } catch {
    return false;
  }
  return nameSpellings(name).some(spelling => text.includes(`\`${spelling}\``));
}

// Why no move may run now (spec §4, C8): an active auto run, then each ledger
// whose plan completed.md does not record, by its plan name, or by its path
// when it has no identity line.
export function inProgress(cfg) {
  const found = [];
  try {
    const run = JSON.parse(readRegular(path.join(dforgeDir("state", cfg.repoRoot), "sdd", "auto-run.json"), { follow: true }).toString("utf8"));
    if (run?.active === true) found.push("an auto run is active");
  } catch {
    // No auto run, or an unreadable record, which auto-run.sh reads as inactive
    // too. The record is read through a link, as auto-run.sh reads it; one that
    // is not a regular file holds no run, since auto-run.sh writes the record
    // with tmp+mv, which replaces a link or a pipe at the path.
  }
  for (const { sdd, checkout } of ledgerSources(cfg)) {
    for (const { name: slug, linked } of dirEntries(sdd)) {
      // A linked plan directory is not read through, so nothing can show its
      // plan finished.
      if (linked) {
        found.push(path.join(sdd, slug));
        continue;
      }
      const ledger = path.join(sdd, slug, "progress.md");
      // A linked ledger is never read through, and an unread one is in progress.
      let text;
      try {
        text = readNoFollow(ledger).toString("utf8");
      } catch (error) {
        if (error.code === "ENOENT") continue;
        found.push(ledger);
        continue;
      }
      const name = ledgerPlanPath(text);
      if (!name) found.push(ledger);
      else if (!planFinished(cfg, checkout, name)) found.push(name);
    }
  }
  return found;
}

// C8's refusal: null, or the first in-progress item as the reason and the
// rest as details. A move calls it again after its own pull.
export function inProgressReason(context) {
  const found = inProgress(context.cfg);
  return found.length ? { reason: `a plan is in progress: ${found[0]}`, details: found.slice(1) } : null;
}

const pullReport = () => ({ conflicts: [], failures: [], notes: [], counts: { documents: 0, ledgers: 0, checkpoints: 0 }, partial: false, refused: 0 });
// A directory or other non-file where a document belongs reads as a hash no
// file has, so it is reported as differing instead of throwing EISDIR.
export const NOT_A_FILE = "not a regular file";

export function fileHash(file) {
  try {
    return sha256(readRegular(file, { follow: true }));
  } catch (error) {
    if (error.code === "ENOENT" || error.code === "ENOTDIR") return null;
    if (error.code === "EISDIR" || error.code === "EFTYPE") return NOT_A_FILE;
    throw error;
  }
}

// A rename or copy in either column: an intent-to-add file (git add -N) is
// detected as a rename in the worktree column, Y.
const renamed = item => "RC".includes(item[0]) || "RC".includes(item[1]);

// git status --porcelain -z as "XY path" lines with raw paths, which plain
// --porcelain would C-quote; a rename or copy reads "XY from -> to".
function statusLines(stdout) {
  const entries = stdout.split("\0");
  const lines = [];
  for (let i = 0; i < entries.length; i += 1) {
    const item = entries[i];
    if (item.length < 4) continue;
    if (renamed(item)) {
      lines.push(`${item.slice(0, 3)}${entries[i + 1]} -> ${item.slice(3)}`);
      i += 1;
    } else {
      lines.push(item);
    }
  }
  return lines;
}

// Why the mirror would never sync a tracked file (spec §7.2), or null.
function uncarried(docsDir, parts) {
  if (parts.some(part => part.startsWith("."))) return "a dot name, which the mirror never syncs";
  if (parts[0] === "handoff") return "under handoff/, which is reserved for plan handoff notes";
  if (parts[0] === "archive") return "under archive/, which is reserved for deletion archives";
  let at = docsDir;
  let stat;
  for (const part of parts) {
    at = path.join(at, part);
    stat = fs.lstatSync(at, { throwIfNoEntry: false });
    // Tracked but deleted without a commit, as during a move's pull.
    if (!stat) return "missing from the working tree";
    if (stat.isSymbolicLink()) return "a symbolic link, or reached through one, which the mirror never syncs";
  }
  return stat.isFile() ? null : "not a regular file";
}

// The tracked documents the move carries, and every file it cannot (§7.2),
// with the uris of the tracked files that are not carried (`uncarriable`).
// Tracked is the test because git rm -r deletes only tracked paths.
export function carriedDocuments(repoRoot, docsDir, rel) {
  const problems = [];
  const documents = [];
  const uncarriable = new Set();
  const listed = runGit(repoRoot, ["ls-files", "-z", "--", rel]);
  if (listed.status !== 0) return { failed: `git ls-files failed: ${listed.stderr.trim()}`, problems: [], documents: [], uncarriable };
  for (const file of listed.stdout.split("\0").filter(Boolean)) {
    const parts = file.slice(rel.length + 1).split("/");
    const uri = `${DOC_PREFIX}/${parts.join("/")}`;
    const refuse = why => {
      problems.push(`${file}: ${why}`);
      uncarriable.add(uri);
    };
    const why = uncarried(docsDir, parts);
    if (why) {
      refuse(why);
      continue;
    }
    let buffer;
    try {
      buffer = readNoFollow(path.join(docsDir, ...parts));
    } catch (error) {
      refuse(`could not be read (${error.code})`);
      continue;
    }
    const content = decodeUtf8(buffer);
    if (!content) {
      refuse("empty or not UTF-8 text, which darkmem cannot store");
      continue;
    }
    const problem = uriProblem(uri);
    if (problem) {
      refuse(problem);
      continue;
    }
    documents.push({ file, parts, uri, content, hash: sha256(buffer) });
  }
  const fileOf = new Map(documents.map(doc => [doc.uri, doc.file]));
  for (const group of caseGroups(documents.map(doc => doc.uri))) {
    problems.push(`${group.map(uri => fileOf.get(uri)).join(", ")}: differ only in case, which a case-insensitive file system holds as one file`);
  }
  // The mirror walks the filesystem, so it would carry an ignored file, and
  // git rm -r would leave it behind.
  const ignored = runGit(repoRoot, ["status", "--porcelain", "-z", "--ignored=matching", "--untracked-files=all", "--", rel]);
  if (ignored.status !== 0) return { failed: `git status failed: ${ignored.stderr.trim()}`, problems: [], documents: [], uncarriable };
  for (const item of ignored.stdout.split("\0")) {
    if (item.startsWith("!! ")) problems.push(`${item.slice(3)}: ignored by git, so the mirror would carry it and git rm would leave it behind`);
  }
  return { problems, documents, uncarriable };
}

// The documents a linked worktree holds that the primary checkout does not:
// its branch's changes since the merge base with the primary's HEAD, and its
// uncommitted ones. The move carries only the primary's docs directory, so
// these would be left in a checkout reconcile then names as not read.
function worktreeOnlyDocuments(cfg) {
  const head = runGit(cfg.repoRoot, ["rev-parse", "HEAD"]);
  if (head.status !== 0) return { failed: `git rev-parse failed: ${head.stderr.trim()}` };
  const found = [];
  for (const tree of worktreeTops(cfg)) {
    if (realOr(tree) === realOr(cfg.repoRoot)) continue;
    const rel = slash(path.relative(tree, dforgeDir("docs", tree)));
    const committed = runGit(tree, ["diff", "--name-only", "-z", "--diff-filter=ACMR", `${head.stdout.trim()}...HEAD`, "--", rel]);
    if (committed.status !== 0) return { failed: `git diff failed in ${tree}: ${committed.stderr.trim()}` };
    const pending = runGit(tree, ["status", "--porcelain", "-z", "--untracked-files=all", "--", rel]);
    if (pending.status !== 0) return { failed: `git status failed in ${tree}: ${pending.stderr.trim()}` };
    const files = new Set(committed.stdout.split("\0").filter(Boolean));
    const entries = pending.stdout.split("\0");
    for (let i = 0; i < entries.length; i += 1) {
      const item = entries[i];
      if (item.length < 4) continue;
      // A rename or copy is followed by its source path, which is no entry.
      if (renamed(item)) i += 1;
      if (!"D ".includes(item[0]) || !"D ".includes(item[1])) files.add(item.slice(3));
    }
    found.push(...[...files].sort().map(file => `${tree}: ${file}`));
  }
  return { found };
}

// Documents, repository -> darkmem (spec §4): nothing is sent until every
// check passes, darkmem's copies are never overwritten, and the repository
// copy is removed only after a pull into the mirror reads back every file.
// A missing or empty docs directory has nothing tracked and moves as is.
async function documentsToDarkmem(context) {
  const { cfg, client } = context;
  const docsDir = dforgeDir("docs", cfg.repoRoot);
  const rel = slash(path.relative(cfg.repoRoot, docsDir));
  const dirty = runGit(cfg.repoRoot, ["status", "--porcelain", "-z", "--untracked-files=all", "--", rel]);
  if (dirty.status !== 0) return { moved: false, reason: `git status failed: ${dirty.stderr.trim()}`, details: [] };
  const changes = statusLines(dirty.stdout);
  if (changes.length) return { moved: false, reason: `${rel} has uncommitted changes`, details: changes };
  const { failed, problems, documents } = carriedDocuments(cfg.repoRoot, docsDir, rel);
  if (failed) return { moved: false, reason: failed, details: [] };
  if (problems.length) return { moved: false, reason: `${rel} holds files the move cannot carry`, details: problems };
  const stranded = worktreeOnlyDocuments(cfg);
  if (stranded.failed) return { moved: false, reason: stranded.failed, details: [] };
  if (stranded.found.length) {
    return { moved: false, reason: "a linked worktree holds documents the primary checkout does not; merge or remove them first", details: stranded.found };
  }
  // Import puts without a hash precondition, so this check is what keeps
  // darkmem's copies; the window between it and the puts is accepted.
  const remote = new Map((await client.manifest(cfg.project, DOC_PREFIX)).map(item => [item.uri, item.content_hash]));
  const differing = [];
  for (const doc of documents) {
    const held = remote.get(doc.uri);
    if (held !== undefined && held !== doc.hash) differing.push(`${doc.uri}: darkmem holds a different version`);
    const twins = [...remote.keys()].filter(uri => uri !== doc.uri && uri.toLowerCase() === doc.uri.toLowerCase()).sort();
    if (twins.length) differing.push(`${doc.uri}: darkmem holds ${twins.join(", ")}, which differ only in case`);
  }
  if (differing.length) return { moved: false, reason: "darkmem holds a different version of some documents; nothing was sent", details: differing };
  for (const doc of documents) {
    if (!remote.has(doc.uri)) await client.putDocument({ project: cfg.project, uri: doc.uri, content: doc.content });
  }
  const mirror = mirrorRoots(cfg, "documents");
  const pulled = pullReport();
  await pullDocuments({ ...context, roots: mirror, report: pulled });
  if (pulled.conflicts.length || pulled.failures.length) {
    return { moved: false, reason: "the pull into the mirror did not complete; the repository copy stays", details: [...pulled.conflicts, ...pulled.failures] };
  }
  const busy = inProgressReason(context);
  if (busy) return { moved: false, ...busy };
  const mismatched = documents
    .filter(doc => fileHash(path.join(mirror.docsRoot, ...doc.parts)) !== doc.hash)
    .map(doc => `${doc.uri}: the mirror's copy differs from the repository's`);
  if (mismatched.length) return { moved: false, reason: "a pull of darkmem's copy differs from the repository", details: mismatched };
  // A commit from another session during the upload and pull leaves the index
  // clean, so git rm would delete a version that was never carried.
  const again = carriedDocuments(cfg.repoRoot, docsDir, rel);
  const sent = new Map(documents.map(doc => [doc.uri, doc.hash]));
  const now = new Map(again.documents.map(doc => [doc.uri, doc.hash]));
  // A failed listing holds no documents, which would read as every one removed.
  // A sent document still tracked but no longer carriable changed; its problem line says how.
  const drifted = again.failed ? [] : [...new Set([...sent.keys(), ...now.keys()])].sort().flatMap(uri => {
    if (!now.has(uri)) return [`${uri}: ${again.uncarriable.has(uri) ? "changed" : "removed"} during the move`];
    if (!sent.has(uri)) return [`${uri}: added during the move`];
    return sent.get(uri) === now.get(uri) ? [] : [`${uri}: changed during the move`];
  });
  if (again.failed || again.problems.length || drifted.length) {
    return { moved: false, reason: `${rel} changed during the move; the repository copy stays`, details: [...(again.failed ? [again.failed] : []), ...again.problems, ...drifted] };
  }
  if (!documents.length) return { moved: true, details: [`${rel} holds no tracked files; nothing to stage`] };
  const removed = runGit(cfg.repoRoot, ["rm", "-r", "-q", "--", rel]);
  if (removed.status !== 0) return { moved: false, reason: `git rm failed: ${removed.stderr.trim()}`, details: [] };
  const details = [`the deletion of ${rel} is staged in ${cfg.repoRoot}; commit it`];
  const cites = runGit(cfg.repoRoot, ["grep", "-I", "-l", "-F", "-e", "docs/superpowers/", "-e", "docs/forge/", "-e", "docs/dforge/", "--", ".", `:(exclude)${rel}`]);
  const citing = cites.status === 0 ? cites.stdout.split("\n").filter(Boolean) : [];
  // 1 is "no match"; anything else, a killed or timed-out run's null included, is a failure.
  if (cites.status !== 0 && cites.status !== 1) {
    const why = cites.stderr.trim() || `it did not finish (${cites.signal ?? "no exit status"})`;
    details.push(`git grep failed: ${why}; check for docs/superpowers/, docs/forge/ and docs/dforge/ citations before you commit`);
  }
  if (citing.length) {
    details.push("these tracked files cite docs/superpowers/, docs/forge/ or docs/dforge/ names; rewrite them before you commit the deletion:");
    details.push(...citing.slice(0, 20).map(file => `  ${file}`));
    if (citing.length > 20) details.push(`and ${citing.length - 20} more`);
  }
  return { moved: true, details };
}

// Documents, darkmem -> repository (spec §4): the mirror, brought up to
// darkmem and matching darkmem's hashes, is copied into docs/dforge untracked;
// darkmem keeps its copy, and the mirror tree is set aside so a later move
// back cannot meet stale files. Offline (darkmem disabled, unmapped or not
// answering) the mirror is copied as it stands, and every file darkmem does
// not hold as the mirror does is named.
async function documentsToLocal(context, { offline = null } = {}) {
  const { cfg, client, state, persist } = context;
  const mirror = mirrorRoots(cfg, "documents");
  // A linked docs root would be read through, copied from and set aside as a link.
  if (fs.lstatSync(mirror.docsRoot, { throwIfNoEntry: false })?.isSymbolicLink()) {
    return { moved: false, reason: `the mirror's docs root ${mirror.docsRoot} is a symbolic link; nothing was copied`, details: [] };
  }
  if (!offline) {
    const pulled = pullReport();
    await pullDocuments({ ...context, roots: mirror, report: pulled });
    if (pulled.conflicts.length || pulled.failures.length) {
      return { moved: false, reason: "the mirror could not be brought up to darkmem", details: [...pulled.conflicts, ...pulled.failures] };
    }
    const busy = inProgressReason(context);
    if (busy) return { moved: false, ...busy };
  }
  // A deletion push has not archived yet: copied out now it would never be
  // archived, and a later move back would pull darkmem's copy in again.
  const unpushed = Object.keys(state.documents).sort().filter(uri => uriFamily(uri) === "documents" && !isArchiveUri(uri)
    && !fs.existsSync(path.join(mirror.docsRoot, ...uri.slice(DOC_PREFIX.length + 1).split("/"))));
  if (unpushed.length && !offline) return { moved: false, reason: "the mirror holds deletions not yet pushed; push first", details: unpushed };
  const target = path.join(cfg.repoRoot, "docs", "dforge");
  // A file under the docs root's handoff/ or archive/ has uri null: never synced, not carried.
  const files = listDocumentFiles(mirror).filter(item => item.uri).map(({ file, uri }) => {
    const dest = path.join(target, path.relative(mirror.docsRoot, file));
    return { file, uri, dest, name: slash(path.relative(cfg.repoRoot, dest)), hash: fileHash(file) };
  });
  // Offline, what darkmem lacks is named by what a later move into darkmem
  // does with it: an edit is refused, a new file is sent, and a deletion is
  // undone by the pull that move runs.
  const notes = [];
  if (offline) {
    for (const item of files) {
      const synced = state.documents[item.uri];
      if (synced === undefined) notes.push(`${item.name}: new since the last sync; a later move to darkmem sends it`);
      else if (synced !== item.hash) notes.push(`${item.name}: edited since the last sync; a later move to darkmem refuses it until darkmem's copy matches`);
    }
    for (const uri of unpushed) notes.push(`${uri}: deleted since the last sync; darkmem still holds it, and a later move to darkmem brings it back`);
  } else {
    const remote = new Map((await client.manifest(cfg.project, DOC_PREFIX))
      .filter(item => uriFamily(item.uri) === "documents" && !isArchiveUri(item.uri))
      .map(item => [item.uri, item.content_hash]));
    // Only what darkmem holds is carried, so an unpushed or damaged mirror
    // copy never lands in the repository as if it were darkmem's.
    const unverified = files.filter(item => remote.get(item.uri) !== item.hash).map(item => (remote.has(item.uri)
      ? `${item.uri}: the mirror's copy differs from darkmem's; push or discard it first`
      : `${item.uri}: not on darkmem; push or discard it first`));
    // listDocumentFiles lists regular files only, so a link or directory where
    // darkmem holds a document would otherwise be left behind unnoticed.
    const covered = new Set(files.map(item => item.uri));
    for (const uri of remote.keys()) {
      if (covered.has(uri)) continue;
      const held = path.join(mirror.docsRoot, ...uri.slice(DOC_PREFIX.length + 1).split("/"));
      if (fs.lstatSync(held, { throwIfNoEntry: false })) {
        unverified.push(`${uri}: the mirror holds a symbolic link or other non-file here, which the move cannot copy; make it a regular file`);
      }
    }
    if (unverified.length) return { moved: false, reason: "the mirror does not match darkmem; nothing was copied", details: unverified };
  }
  // mkdirSync cannot make docs/dforge where a file stands. A link is left to
  // the walk below, which names it.
  for (const rel of ["docs", DOCS]) {
    const stat = fs.lstatSync(path.join(cfg.repoRoot, ...rel.split("/")), { throwIfNoEntry: false });
    if (!stat || stat.isSymbolicLink()) break;
    if (!stat.isDirectory()) return { moved: false, reason: `${rel} is not a directory; nothing was copied`, details: [] };
  }
  // Copies and equality reads must not follow a link out of the repository.
  const checked = new Set(["docs", DOCS]);
  for (const { dest } of files) {
    const parts = slash(path.relative(cfg.repoRoot, dest)).split("/");
    for (let end = 1; end <= parts.length; end += 1) checked.add(parts.slice(0, end).join("/"));
  }
  const links = [];
  for (const rel of [...checked].sort()) {
    if (links.some(link => rel.startsWith(`${link}/`))) continue;
    if (fs.lstatSync(path.join(cfg.repoRoot, ...rel.split("/")), { throwIfNoEntry: false })?.isSymbolicLink()) links.push(rel);
  }
  if (links.length) {
    return {
      moved: false,
      reason: "docs/dforge is reached through symbolic links; nothing was copied",
      details: links.map(rel => `${rel}: a symbolic link, which the move will not write through`),
    };
  }
  // A killed earlier run may have copied some files: equal ones are fine and
  // are not written again. One that cannot be read, a named pipe included,
  // differs.
  const present = new Set();
  const differing = files
    .filter(({ file, dest }) => {
      if (!fs.existsSync(dest)) return false;
      try {
        if (!readNoFollow(dest).equals(readNoFollow(file))) return true;
      } catch {
        return true;
      }
      present.add(dest);
      return false;
    })
    .map(({ name }) => `${name}: already exists with different content`);
  if (differing.length) return { moved: false, reason: "docs/dforge already holds different copies; nothing was copied", details: differing };
  // A repository moved under the parent spec's §6 ignored its docs directory.
  // Asked before anything is copied so a git failure (exit above 1) can still refuse.
  const ignored = runGit(cfg.repoRoot, ["check-ignore", "--stdin"], files.map(({ name }) => name).join("\n"));
  if (ignored.status !== 0 && ignored.status !== 1) return { moved: false, reason: `git check-ignore failed: ${ignored.stderr.trim()}`, details: [] };
  fs.mkdirSync(target, { recursive: true });
  // Each mirror file is read once without following a link or blocking on a
  // named pipe, checked against the hash darkmem confirmed, and that buffer is
  // written exclusively, so nothing that lands at either end meanwhile is
  // read through or overwritten. A refusal keeps what was written, which a
  // rerun's comparison above takes as equal.
  const landed = [];
  const copied = [];
  const copiedLines = () => copied.map(name => `${name}: copied`);
  try {
    for (const { file, dest, name, hash } of files) {
      if (present.has(dest)) continue;
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      const buffer = readNoFollow(file);
      if (sha256(buffer) !== hash) {
        return {
          moved: false,
          reason: "the mirror changed during the move; nothing more was copied",
          details: [`${name}: the mirror's copy changed after darkmem confirmed it`, ...landed, ...copiedLines()],
        };
      }
      try {
        fs.writeFileSync(dest, buffer, { flag: "wx" });
      } catch (error) {
        if (error.code !== "EEXIST") throw error;
        landed.push(`${name}: changed during the move; not overwritten`);
        continue;
      }
      copied.push(name);
    }
    if (landed.length) return { moved: false, reason: "docs/dforge changed during the move; nothing was overwritten", details: [...landed, ...copiedLines()] };
    const mismatched = files.filter(({ dest, hash }) => sha256(readNoFollow(dest)) !== hash).map(({ name }) => `${name}: differs from the mirror's copy`);
    if (mismatched.length) return { moved: false, reason: "a copied file differs from the mirror's", details: [...mismatched, ...copiedLines()] };
  } catch (error) {
    return { moved: false, reason: `a copy into docs/dforge failed (${error.code}); the files copied so far stay, and a rerun copies the rest`, details: copiedLines() };
  }
  // Set aside before the sync state forgets the documents, so a failed rename
  // leaves a state that still describes the mirror.
  const aside = path.join(cfg.mirror, `${DOC_PREFIX}-moved-${utcStamp()}`);
  if (fs.existsSync(mirror.docsRoot)) {
    try {
      fs.renameSync(mirror.docsRoot, aside);
    } catch (error) {
      return { moved: false, reason: `the mirror's copy could not be set aside (${error.code}); docs/dforge holds the copied files, and the next reconcile finishes the move`, details: [] };
    }
  }
  for (const uri of Object.keys(state.documents)) {
    if (uriFamily(uri) === "documents") delete state.documents[uri];
  }
  persist();
  const details = [`copied ${files.length} files into docs/dforge, untracked; commit them`];
  if (notes.length) {
    details.push(`darkmem was not consulted; the mirror is kept at ${aside}. These differ from darkmem's last known copy:`);
    details.push(...notes.map(line => `  ${line}`));
  }
  for (const name of ignored.stdout.split("\n").filter(Boolean)) details.push(`${name}: ignored by git, so a commit would leave it out`);
  return { moved: true, details };
}

export async function reconcile(context) {
  const { client, env, out, report } = context;
  const pending = pendingFamilies(context.cfg);
  const refuseAll = (reason, details = []) => {
    for (const family of pending) {
      out(stayLine(context.cfg, family, reason));
      for (const line of details) out(`  ${line}`);
      report.refused += 1;
    }
  };
  const busy = inProgressReason(context);
  if (busy) return refuseAll(busy.reason, busy.details);
  // A move back to the checkout never waits for darkmem: without it the
  // mirror's own files are carried (offline). A move into darkmem needs it.
  // Turned off, darkmem is never asked: push is off too, so a mirror edit
  // darkmem lacks could never be resolved before an online move.
  let offline = context.cfg.enabled ? null : context.cfg.url ? "darkmem is turned off" : "the repository is not mapped to darkmem";
  try {
    offline ??= await context.migrate?.() ?? null;
  } catch (error) {
    if (!(error instanceof TransportError || error instanceof HttpError)) throw error;
    // The probe below names the same failure.
  }
  if (!offline && !context.cfg.url) offline = "the repository is not mapped to darkmem";
  else if (!offline && !context.cfg.apiKey) offline = `${context.cfg.keyEnv} is not set`;
  else if (!offline) {
    try {
      await client.manifest(context.cfg.project, DOC_PREFIX);
    } catch (error) {
      if (error instanceof TransportError) offline = `darkmem is unreachable: ${error.message}`;
      else if (error instanceof HttpError) offline = `darkmem refused the manifest read: ${error.message}`;
      else throw error;
    }
  }
  if (offline && pending.every(family => context.cfg[family].configured === "darkmem")) return refuseAll(offline);
  writeApplied(env, context.cfg.repoRoot, { documents: context.cfg.documents.applied, progress: context.cfg.progress.applied }, { project: context.cfg.project, mirror: context.cfg.mirror });
  for (const family of pending) {
    const { cfg } = context;
    const target = cfg[family].configured;
    const move = MOVES[`${family}:${target}`];
    let result;
    if (offline && target === "darkmem") {
      result = { moved: false, reason: offline, details: [] };
    } else if (!move) {
      result = { moved: false, reason: `no move from ${cfg[family].applied} to ${target}`, details: [] };
    } else {
      try {
        result = await move(context, { offline });
      } catch (error) {
        if (!(error instanceof TransportError || error instanceof HttpError)) throw error;
        result = { moved: false, reason: `darkmem failed during the move: ${error.message}`, details: [] };
      }
    }
    if (result.moved) {
      writeApplied(env, cfg.repoRoot, { [family]: target }, { project: cfg.project, mirror: cfg.mirror });
      refreshContext(context);
      out(`darkmem-sync reconcile: ${family} moved to ${target}${offline ? ` from the mirror, without darkmem (${offline})` : ""}`);
    } else {
      out(stayLine(context.cfg, family, result.reason));
      report.refused += 1;
    }
    for (const line of result.details) out(`  ${line}`);
  }
  for (const line of leftoverLines(context.cfg)) out(line);
}
