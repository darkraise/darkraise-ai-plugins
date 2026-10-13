// darkmem-sync reconcile (darkmem store options spec §4, §7.2): move each
// family whose configured store differs from its applied store, under §4's
// refusals, and record each completed move in ~/.dr-forge/stores.json.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { HttpError, TransportError } from "./darkmem-client.mjs";
import { forgeDir, resolveStores, writeApplied } from "./darkmem-config.mjs";
import { DOC_PREFIX, caseGroups, decodeUtf8, ledgerPlanPath, sha256, uriProblem } from "./darkmem-mirror.mjs";
import { pullDocuments } from "./darkmem-pull.mjs";

const FAMILIES = ["documents", "progress"];
const LEGACY = "docs/superpowers";
const DOCS = "docs/forge";

// Each move, under "<family>:<target store>". A move answers
// { moved: true, details } or { moved: false, reason, details }.
const MOVES = {
  "documents:darkmem": documentsToDarkmem,
};

function runGit(cwd, args, input) {
  const result = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf8", timeout: 60000, input, maxBuffer: 64 * 1024 * 1024 });
  return { status: result.status, stdout: result.stdout ?? "", stderr: result.stderr ?? "" };
}

const slash = file => file.split(path.sep).join("/");

function dirEntries(dir) {
  try {
    return fs.readdirSync(dir, { withFileTypes: true }).filter(entry => entry.isDirectory()).map(entry => entry.name).sort();
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
}

// One document name under either docs prefix (spec §7.1), as forge_name_key
// and forge_name_spellings spell it in roots.sh.
export function nameSpellings(name) {
  const text = String(name).replace(/^\.\//, "");
  const key = text === LEGACY || text.startsWith(`${LEGACY}/`) ? `${DOCS}${text.slice(LEGACY.length)}` : text;
  return key === DOCS || key.startsWith(`${DOCS}/`) ? [key, `${LEGACY}${key.slice(DOCS.length)}`] : [key];
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
    docsRoot: path.join(cfg.mirror, "superpowers"),
    workRoot: path.join(cfg.mirror, "work"),
    worktreeRoot: cfg.repoRoot,
    families: { documents: family === "documents", progress: family === "progress" },
  };
}

// Re-reads the stores after a move, so the next move sees the roots the
// last one produced; cfg and roots are rebuilt as main builds them.
export function refreshContext(context) {
  const stores = resolveStores({ cwd: context.cfg.worktreeRoot, env: context.env });
  const cfg = { ...stores.sync, repoRoot: stores.repoRoot, worktreeRoot: stores.worktreeRoot, documents: stores.documents, progress: stores.progress };
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
  return [path.join(cfg.worktreeRoot, "docs", "forge"), path.join(cfg.worktreeRoot, "docs", "superpowers")]
    .filter(dir => fs.existsSync(dir))
    .map(dir => `darkmem-sync reconcile: ${dir} is not read while documents are applied darkmem`);
}

// Where the ledgers live: every worktree's state directory while progress is
// local, the mirror's work tree while it is darkmem.
function ledgerSources(cfg) {
  if (cfg.progress.applied === "darkmem") return [{ sdd: path.join(cfg.mirror, "work", "sdd"), checkout: cfg.repoRoot }];
  const listing = runGit(cfg.repoRoot, ["worktree", "list", "--porcelain"]);
  const trees = listing.status === 0
    ? listing.stdout.split(/\r?\n/).filter(line => line.startsWith("worktree ")).map(line => line.slice("worktree ".length))
    : [cfg.repoRoot];
  return trees.map(tree => ({ sdd: path.join(forgeDir("state", tree), "sdd"), checkout: tree }));
}

function planFile(cfg, checkout, name) {
  if (path.isAbsolute(name)) return name;
  const [key] = nameSpellings(name);
  if (key === DOCS || key.startsWith(`${DOCS}/`)) {
    const docsRoot = cfg.documents.applied === "darkmem" ? path.join(cfg.mirror, "superpowers") : forgeDir("docs", checkout);
    return path.join(docsRoot, ...key.slice(DOCS.length).split("/").filter(Boolean));
  }
  return path.join(checkout, key);
}

// Matched on the backticked name, as plan_finished does, so one plan's name
// that is a substring of another's cannot claim its outcome.
function planFinished(cfg, checkout, name) {
  let text;
  try {
    text = fs.readFileSync(path.join(path.dirname(planFile(cfg, checkout, name)), "completed.md"), "utf8");
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
    const run = JSON.parse(fs.readFileSync(path.join(forgeDir("state", cfg.repoRoot), "sdd", "auto-run.json"), "utf8"));
    if (run?.active === true) found.push("an auto run is active");
  } catch {
    // No auto run, or an unreadable record, which auto-run.sh reads as inactive too.
  }
  for (const { sdd, checkout } of ledgerSources(cfg)) {
    for (const slug of dirEntries(sdd)) {
      const ledger = path.join(sdd, slug, "progress.md");
      let text;
      try {
        text = fs.readFileSync(ledger, "utf8");
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
const fileHash = file => (fs.existsSync(file) ? sha256(fs.readFileSync(file)) : null);

// Why the mirror would never sync a tracked file (spec §7.2), or null.
function uncarried(docsDir, parts) {
  if (parts.some(part => part.startsWith("."))) return "a dot name, which the mirror never syncs";
  if (parts[0] === "handoff") return "under handoff/, which is reserved for plan handoff notes";
  if (parts[0] === "archive") return "under archive/, which is reserved for deletion archives";
  let at = docsDir;
  for (const part of parts) {
    at = path.join(at, part);
    if (fs.lstatSync(at).isSymbolicLink()) return "a symbolic link, or reached through one, which the mirror never syncs";
  }
  return fs.lstatSync(at).isFile() ? null : "not a regular file";
}

// The tracked documents the move carries, and every file it cannot (§7.2).
// Tracked is the test because git rm -r deletes only tracked paths.
function carriedDocuments(repoRoot, docsDir, rel) {
  const problems = [];
  const documents = [];
  const listed = runGit(repoRoot, ["ls-files", "-z", "--", rel]);
  if (listed.status !== 0) return { failed: `git ls-files failed: ${listed.stderr.trim()}`, problems: [], documents: [] };
  for (const file of listed.stdout.split("\0").filter(Boolean)) {
    const parts = file.slice(rel.length + 1).split("/");
    const why = uncarried(docsDir, parts);
    if (why) {
      problems.push(`${file}: ${why}`);
      continue;
    }
    const buffer = fs.readFileSync(path.join(docsDir, ...parts));
    const content = decodeUtf8(buffer);
    if (!content) {
      problems.push(`${file}: empty or not UTF-8 text, which darkmem cannot store`);
      continue;
    }
    const uri = `${DOC_PREFIX}/${parts.join("/")}`;
    const problem = uriProblem(uri);
    if (problem) {
      problems.push(`${file}: ${problem}`);
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
  if (ignored.status !== 0) return { failed: `git status failed: ${ignored.stderr.trim()}`, problems: [], documents: [] };
  for (const item of ignored.stdout.split("\0")) {
    if (item.startsWith("!! ")) problems.push(`${item.slice(3)}: ignored by git, so the mirror would carry it and git rm would leave it behind`);
  }
  return { problems, documents };
}

// Documents, repository -> darkmem (spec §4): nothing is sent until every
// check passes, darkmem's copies are never overwritten, and the repository
// copy is removed only after a pull into the mirror reads back every file.
// A missing or empty docs directory has nothing tracked and moves as is.
async function documentsToDarkmem(context) {
  const { cfg, client } = context;
  const docsDir = forgeDir("docs", cfg.repoRoot);
  const rel = slash(path.relative(cfg.repoRoot, docsDir));
  const dirty = runGit(cfg.repoRoot, ["status", "--porcelain", "--untracked-files=all", "--", rel]);
  if (dirty.status !== 0) return { moved: false, reason: `git status failed: ${dirty.stderr.trim()}`, details: [] };
  if (dirty.stdout.trim()) return { moved: false, reason: `${rel} has uncommitted changes`, details: dirty.stdout.split("\n").filter(Boolean) };
  const { failed, problems, documents } = carriedDocuments(cfg.repoRoot, docsDir, rel);
  if (failed) return { moved: false, reason: failed, details: [] };
  if (problems.length) return { moved: false, reason: `${rel} holds files the move cannot carry`, details: problems };
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
  if (!documents.length) return { moved: true, details: [`${rel} holds no tracked files; nothing to stage`] };
  const removed = runGit(cfg.repoRoot, ["rm", "-r", "-q", "--", rel]);
  if (removed.status !== 0) return { moved: false, reason: `git rm failed: ${removed.stderr.trim()}`, details: [] };
  const details = [`the deletion of ${rel} is staged in ${cfg.repoRoot}; commit it`];
  const cites = runGit(cfg.repoRoot, ["grep", "-I", "-l", "-F", "-e", "docs/superpowers/", "-e", "docs/forge/", "--", ".", `:(exclude)${rel}`]);
  const citing = cites.status === 0 ? cites.stdout.split("\n").filter(Boolean) : [];
  if (citing.length) {
    details.push("these tracked files cite docs/superpowers/ or docs/forge/ names; rewrite them before you commit the deletion:");
    details.push(...citing.slice(0, 20).map(file => `  ${file}`));
    if (citing.length > 20) details.push(`and ${citing.length - 20} more`);
  }
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
  if (!context.cfg.apiKey) return refuseAll(`${context.cfg.keyEnv} is not set`);
  try {
    await client.manifest(context.cfg.project, DOC_PREFIX);
  } catch (error) {
    if (error instanceof TransportError) return refuseAll(`darkmem is unreachable: ${error.message}`);
    if (error instanceof HttpError) return refuseAll(`darkmem refused the manifest read: ${error.message}`);
    throw error;
  }
  // Without a record the applied store follows the sync state (first-run
  // rule), which a refused move's partial pull could tip to darkmem; the
  // record pins it first. A recorded family is rewritten with its own value.
  writeApplied(env, context.cfg.repoRoot, { documents: context.cfg.documents.applied, progress: context.cfg.progress.applied });
  for (const family of pending) {
    const { cfg } = context;
    const target = cfg[family].configured;
    const move = MOVES[`${family}:${target}`];
    let result;
    if (!move) {
      result = { moved: false, reason: `no move from ${cfg[family].applied} to ${target}`, details: [] };
    } else {
      try {
        result = await move(context);
      } catch (error) {
        if (!(error instanceof TransportError || error instanceof HttpError)) throw error;
        result = { moved: false, reason: `darkmem failed during the move: ${error.message}`, details: [] };
      }
    }
    if (result.moved) {
      writeApplied(env, cfg.repoRoot, { [family]: target });
      refreshContext(context);
      out(`darkmem-sync reconcile: ${family} moved to ${target}`);
    } else {
      out(stayLine(context.cfg, family, result.reason));
      report.refused += 1;
    }
    for (const line of result.details) out(`  ${line}`);
  }
  for (const line of leftoverLines(context.cfg)) out(line);
}
