// Acceptance tests for the parallel-session handoff spec, A15 (dforge only),
// written from the spec's Acceptance section: darkmem push and pull of keyed
// handoffs and the sync state they keep. Each test name starts with A15.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../../plugins/dforge/scripts/lib/darkmem-client.mjs";
import { STUB_KEY, startStub } from "./stub-server.mjs";
import { makeHome, makeRepo, read, run, write } from "./helpers.mjs";

const sha = text => crypto.createHash("sha256").update(text, "utf8").digest("hex");
const mark = (kind, key, subject, extra = "") => `<!-- next-step: kind=${kind} key=${key} session=s-1 done=0 closed=0 subject=${subject} at=1795000000${extra} -->`;
const note = (text, marker) => `# Handoff\n\n## Next session\n\n${text}\n${marker}\n`;

async function setup(t) {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const dir = path.join(home.workRoot, "handoff");
  const stateFile = path.join(home.mirror, ".sync-state.json");
  return {
    stub, repo, seed, dir, stateFile, ...home,
    state: () => JSON.parse(read(stateFile)),
    push: (...args) => run(["push", ...args], { cwd: repo, env: home.env }),
    pull: () => run(["pull"], { cwd: repo, env: home.env }),
    checkpoint: (workstream, body) => seed.append({ project: "proj", workstream, entries: [{ kind: "checkpoint", body }] }),
    bodies: key => (stub.db.workstreams.find(w => w.key === key)?.entries ?? []).filter(e => e.kind === "checkpoint").map(e => e.body),
    at: key => stub.db.workstreams.find(w => w.key === key).entries.at(-1).created_at,
  };
}
// A state file as the plugin before this change wrote it: one checkpoint hash, one checkpointAt time.
const oldState = (s, { checkpoint = null, checkpointAt = "2000-01-01T00:00:00Z", ...rest } = {}) =>
  write(s.stateFile, JSON.stringify({ version: 1, documents: {}, ledgers: {}, checkpoint, checkpointAt, conflicts: [], pendingLinks: [], prefix: "dforge", ...rest }));

test("A15: push files plan, draft, complete and project handoffs under the workstream checkpointTarget picks", async t => {
  const s = await setup(t);
  const files = {
    "PA.md": note("PLAN-NOTE", mark("plan", "PA", "docs/dforge/plans/PA.md")),
    "DD.md": note("DRAFT-NOTE", mark("draft", "DD", "docs/dforge/specs/DD.md")),
    "QC.md": note("COMPLETE-NOTE", mark("complete", "QC", "docs/dforge/plans/QC.md")),
    "adhoc-0a1b2c3d.md": note("PROJECT-NOTE", mark("project", "adhoc-0a1b2c3d", "-")),
  };
  for (const [name, text] of Object.entries(files)) write(path.join(s.dir, name), text);
  const result = await s.push();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.doesNotMatch(result.stdout, /failed/);
  assert.deepEqual(s.bodies("PA"), [files["PA.md"]], "a plan's handoff is filed under the plan");
  assert.deepEqual(s.bodies("DD"), [files["DD.md"]], "a draft's handoff is filed under the draft");
  assert.deepEqual(s.bodies("project").sort(), [files["QC.md"], files["adhoc-0a1b2c3d.md"]].sort(), "complete and project blocks are filed under project");
});

test("A15: push skips a plain adhoc handoff with exit 0 and no failure line", async t => {
  const s = await setup(t);
  write(path.join(s.dir, "adhoc-deadbeef.md"), note("ADHOC-ONLY-NOTE", mark("adhoc", "adhoc-deadbeef", "-")));
  const result = await s.push();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.doesNotMatch(result.stdout + result.stderr, /^failed:/m, "no failure line");
  assert.match(result.stdout, /\b0 failures\b/);
  assert.equal(s.stub.db.workstreams.flatMap(w => w.entries).filter(e => e.kind === "checkpoint").length, 0, "no checkpoint is filed anywhere");
  assert.doesNotMatch(JSON.stringify(s.stub.db.requests.map(r => r.body ?? null)), /ADHOC-ONLY-NOTE/);
});

test("A15: push refuses --workstream without --handoff and sends nothing", async t => {
  const s = await setup(t);
  write(path.join(s.dir, "PB.md"), note("PB-NOTE", mark("plan", "PB", "docs/dforge/plans/PB.md")));
  const result = await s.push("--workstream", "somewhere");
  assert.notEqual(result.code, 0, "a usage error");
  assert.match(result.stdout + result.stderr, /--workstream/);
  assert.equal(s.stub.db.workstreams.length, 0);
  assert.equal(s.stub.db.requests.filter(r => r.method === "POST").length, 0);
});

test("A15: pull writes each workstream's newest checkpoint to the key file its marker names and touches no other file", async t => {
  const s = await setup(t);
  oldState(s);
  const other = path.join(s.dir, "ZZ.md");
  write(other, "# another key's file, edited by hand\n");
  const otherBefore = fs.statSync(other);
  const first = note("FIRST", mark("plan", "KA", "docs/dforge/plans/KA.md"));
  const second = note("SECOND", mark("plan", "KA", "docs/dforge/plans/KA.md"));
  const draft = note("DRAFTBODY", mark("draft", "KB", "docs/dforge/specs/KB.md"));
  await s.checkpoint("ws-one", first);
  await s.checkpoint("ws-one", second);
  await s.checkpoint("ws-two", draft);
  const result = await s.pull();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.equal(read(path.join(s.dir, "KA.md")), second, "the workstream's newest checkpoint, at the key its marker names");
  assert.equal(read(path.join(s.dir, "KB.md")), draft);
  assert.deepEqual(fs.readdirSync(s.dir).sort(), ["KA.md", "KB.md", "ZZ.md"]);
  assert.equal(read(other), "# another key's file, edited by hand\n");
  assert.equal(fs.statSync(other).mtimeMs, otherBefore.mtimeMs, "another key's file is not modified");
});

test("A15: pull writes a checkpoint only when newer than that workstream's checkpointAt", async t => {
  const s = await setup(t);
  await s.checkpoint("ws-old", note("OLD", mark("plan", "KOLD", "docs/dforge/plans/KOLD.md")));
  const oldAt = s.at("ws-old");
  oldState(s, { checkpointAt: oldAt, checkpointAtByWorkstream: { "ws-old": oldAt } });
  const same = await s.pull();
  assert.equal(same.code, 0, same.stdout + same.stderr);
  assert.equal(fs.existsSync(path.join(s.dir, "KOLD.md")), false, "a checkpoint no newer than its checkpointAt is not written");
  const newer = note("NEWER", mark("plan", "KOLD", "docs/dforge/plans/KOLD.md"));
  await s.checkpoint("ws-old", newer);
  const result = await s.pull();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.equal(read(path.join(s.dir, "KOLD.md")), newer);
});

test("A15: the first pull after the upgrade writes no file for a workstream whose newest checkpoint was already synced", async t => {
  const s = await setup(t);
  await s.checkpoint("ws-synced", note("SYNCED", mark("plan", "KS", "docs/dforge/plans/KS.md")));
  const syncedAt = s.at("ws-synced");
  oldState(s, { checkpoint: sha("whatever the older plugin had hashed"), checkpointAt: syncedAt });
  const result = await s.pull();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.equal(fs.existsSync(path.join(s.dir, "KS.md")), false);
  assert.equal(fs.existsSync(s.dir) ? fs.readdirSync(s.dir).length : 0, 0, "no handoff file is written at all");
});

test("A15: with a record holding only workstream P and no star, an older checkpoint of workstream D writes no file and a newer one is written", async t => {
  const s = await setup(t);
  await s.checkpoint("D", note("D-OLD", mark("draft", "KD", "docs/dforge/specs/KD.md")));
  await s.checkpoint("P", note("P-NOW", mark("plan", "KP", "docs/dforge/plans/KP.md")));
  const pAt = s.at("P");
  assert.ok(Date.parse(s.at("D")) < Date.parse(pAt), "D's checkpoint is older than P's recorded time");
  oldState(s, { checkpointAt: pAt, checkpointAtByWorkstream: { P: pAt } });
  const first = await s.pull();
  assert.equal(first.code, 0, first.stdout + first.stderr);
  assert.equal(fs.existsSync(path.join(s.dir, "KD.md")), false, "older than P's recorded time: no file");
  assert.equal(fs.existsSync(path.join(s.dir, "KP.md")), false, "P's own checkpoint was already synced");
  assert.equal(s.state().checkpointAtByWorkstream["*"], pAt, "the first pull stores that time under *");
  const fresh = note("D-NEW", mark("draft", "KD", "docs/dforge/specs/KD.md"));
  await s.checkpoint("D", fresh);
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(path.join(s.dir, "KD.md")), fresh, "a newer checkpoint is written");
});

test("A15: a marker key failing the key rule is skipped with a note, and of two checkpoints naming one key the newer is written", async t => {
  const s = await setup(t);
  oldState(s);
  await s.checkpoint("w-bad", `# Bad\n<!-- next-step: kind=adhoc key=bad/key session=- done=0 closed=0 subject=- at=1795000000 -->\n`);
  await s.checkpoint("w-latest", `# Latest\n<!-- next-step: kind=adhoc key=latest session=- done=0 closed=0 subject=- at=1795000000 -->\n`);
  await s.checkpoint("w-zeta", note("FROM-ZETA", mark("plan", "KX", "docs/dforge/plans/KX.md")));
  const newer = note("FROM-ALPHA-NEWER", mark("plan", "KX", "docs/dforge/plans/KX.md"));
  await s.checkpoint("w-alpha", newer);
  const result = await s.pull();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout + result.stderr, /skipped/i, "a note says the checkpoint was skipped");
  assert.match(result.stdout + result.stderr, /w-bad/);
  assert.deepEqual(fs.readdirSync(s.dir), ["KX.md"], "only the usable key is written");
  assert.equal(read(path.join(s.dir, "KX.md")), newer, "the newer created_at wins");
});

test("A15: a handoff deleted after it was pulled (superseded or consumed) is not pulled back", async t => {
  const s = await setup(t);
  oldState(s);
  const body = note("PULLED-ONCE", mark("plan", "KG", "docs/dforge/plans/KG.md"));
  await s.checkpoint("ws-g", body);
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(path.join(s.dir, "KG.md")), body);
  fs.rmSync(path.join(s.dir, "KG.md"));
  const again = await s.pull();
  assert.equal(again.code, 0, again.stdout + again.stderr);
  assert.equal(fs.existsSync(path.join(s.dir, "KG.md")), false, "the deleted handoff stays gone");
});

test("A15: a locally changed handoff conflicts alone", async t => {
  const s = await setup(t);
  oldState(s);
  await s.checkpoint("ws-a", note("A-V1", mark("plan", "KCA", "docs/dforge/plans/KCA.md")));
  await s.checkpoint("ws-b", note("B-V1", mark("plan", "KCB", "docs/dforge/plans/KCB.md")));
  assert.equal((await s.pull()).code, 0);
  write(path.join(s.dir, "KCA.md"), "# edited locally\n");
  const bNew = note("B-V2", mark("plan", "KCB", "docs/dforge/plans/KCB.md"));
  await s.checkpoint("ws-a", note("A-V2", mark("plan", "KCA", "docs/dforge/plans/KCA.md")));
  await s.checkpoint("ws-b", bNew);
  const result = await s.pull();
  assert.match(result.stdout + result.stderr, /conflict/i);
  assert.match(result.stdout + result.stderr, /KCA/);
  assert.equal(read(path.join(s.dir, "KCA.md")), "# edited locally\n", "the locally changed file is left");
  assert.equal(read(path.join(s.dir, "KCB.md")), bNew, "the other key's file is still updated");
});

test("A15: loadState converts the old single checkpoint field, and the saved state keeps it for the older plugin", async t => {
  const s = await setup(t);
  const text = note("ALREADY-SYNCED", mark("plan", "KL", "docs/dforge/plans/KL.md"));
  write(path.join(s.dir, "KL.md"), text);
  oldState(s, { checkpoint: sha(text) });
  assert.equal((await s.pull()).code, 0);
  let saved = s.state();
  assert.deepEqual(saved.checkpoints, { KL: sha(text) }, "the old hash maps to the handoff file it hashes to");
  assert.ok("checkpoint" in saved, "the older plugin's field stays");
  assert.ok(saved.checkpoint === null || typeof saved.checkpoint === "string");
  assert.equal(typeof saved.checkpointAt, "string", "the older plugin reads a string checkpointAt");
  oldState(s, { checkpoint: sha("matches no handoff file") });
  assert.equal((await s.pull()).code, 0);
  saved = s.state();
  assert.ok(!Object.values(saved.checkpoints ?? {}).includes(sha("matches no handoff file")), "an old hash that hashes to no file is dropped");
  assert.ok(saved.checkpoint === null || typeof saved.checkpoint === "string");
});
