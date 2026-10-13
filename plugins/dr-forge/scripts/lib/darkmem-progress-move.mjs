// The progress family's moves (darkmem store options spec §4): every
// checkout's plan ledgers and handoff notes, and the primary checkout's
// latest.md, into darkmem; and the mirror's back into the primary checkout.
// Nothing is deleted: a source is moved to a dated backup only after its
// copy reads back identical.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { forgeDir } from "./darkmem-config.mjs";
import { DOC_PREFIX, decodeUtf8, ledgerFiles, listDocumentFiles, sha256, unsupportedPlanDirs } from "./darkmem-mirror.mjs";
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
    item.buffer = fs.readFileSync(item.file);
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
    if (fs.existsSync(target) && !fs.readFileSync(target).equals(item.buffer)) {
      problems.push(`${target}: the mirror already holds a different copy of ${item.rel}`);
    }
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
