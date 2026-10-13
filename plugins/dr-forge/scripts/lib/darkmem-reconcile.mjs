// darkmem-sync reconcile (darkmem store options spec §4, §7.2): move each
// family whose configured store differs from its applied store, under §4's
// refusals, and record each completed move in ~/.dr-forge/stores.json.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { HttpError, TransportError } from "./darkmem-client.mjs";
import { forgeDir, resolveStores, writeApplied } from "./darkmem-config.mjs";
import { DOC_PREFIX, ledgerPlanPath } from "./darkmem-mirror.mjs";

const FAMILIES = ["documents", "progress"];
const LEGACY = "docs/superpowers";
const DOCS = "docs/forge";

// Each move, under "<family>:<target store>". A move answers
// { moved: true, details } or { moved: false, reason, details }.
const MOVES = {};

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
