import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";
import { HttpError, TransportError, createClient, failItem } from "../../scripts/lib/darkmem-client.mjs";
import { STUB_KEY, startStub } from "./stub-server.mjs";

async function withStub(options, body) {
  const stub = await startStub(options);
  try {
    await body(stub, createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "run-1", timeoutMs: 3000 }));
  } finally {
    await stub.close();
  }
}

test("every call carries the key and names the client; an append declares the run", () => withStub({}, async (stub, client) => {
  await client.append({ project: "p", workstream: "w", entries: [{ kind: "ledger", body: "line\n" }], properties: { plan_uri: "superpowers/plans/w.md" } });
  const [request] = stub.db.requests;
  assert.equal(request.headers.authorization, `Bearer ${STUB_KEY}`);
  assert.equal(request.headers["x-darkmem-client"], "dr-superpowers");
  assert.equal(request.body.run_key, "run-1");
  assert.equal(request.body.client, "dr-superpowers");
  assert.deepEqual(request.body.properties, { plan_uri: "superpowers/plans/w.md" });
}));

test("a filed document reads back with its content and hash", () => withStub({}, async (stub, client) => {
  const put = await client.putDocument({ project: "p", uri: "superpowers/specs/a.md", content: "# A\n" });
  assert.equal(put.outcome, "created");
  const doc = await client.getDocument("p", "superpowers/specs/a.md");
  assert.equal(doc.content, "# A\n");
  assert.equal(doc.content_hash, put.content_hash);
  assert.equal("expected_hash" in stub.db.requests[0].body, false);
}));

test("a stale expected hash is an HttpError 409", () => withStub({}, async (stub, client) => {
  await client.putDocument({ project: "p", uri: "superpowers/a.md", content: "one" });
  await assert.rejects(
    client.putDocument({ project: "p", uri: "superpowers/a.md", content: "two", expectedHash: "0".repeat(64) }),
    error => error instanceof HttpError && error.status === 409,
  );
}));

test("manifest, workstreams and entries follow every page", () => withStub({ pageSize: 2 }, async (stub, client) => {
  for (const name of ["a", "b", "c", "d", "e"]) {
    await client.putDocument({ project: "p", uri: `superpowers/${name}.md`, content: name });
    await client.append({ project: "p", workstream: `w${name}`, entries: [{ kind: "ledger", body: name }] });
  }
  await client.putDocument({ project: "p", uri: "other/x.md", content: "x" });
  assert.deepEqual((await client.manifest("p", "superpowers")).map(i => i.uri), ["a", "b", "c", "d", "e"].map(n => `superpowers/${n}.md`));
  assert.equal((await client.workstreams("p", "open")).length, 5);
  const ws = (await client.resume("p", "wa")).workstream;
  await client.append({ project: "p", workstream: "wa", entries: ["2", "3", "4", "5"].map(body => ({ kind: "ledger", body })) });
  assert.equal((await client.entries(ws.id, "ledger")).map(e => e.body).join(""), "a2345");
}));

test("resume on an absent workstream is null; purge removes one", () => withStub({}, async (stub, client) => {
  assert.equal(await client.resume("p", "absent"), null);
  const { workstream } = await client.append({ project: "p", workstream: "w", entries: [{ kind: "note", body: "n" }] });
  assert.equal((await client.updateWorkstream(workstream.id, { state: "closed", retain: true })).state, "closed");
  assert.equal(await client.purgeWorkstream(workstream.id), null);
  assert.equal(await client.resume("p", "w"), null);
  const answering = fetchImpl => createClient({ url: "http://x.invalid", apiKey: "k", runKey: "r", timeoutMs: 1000, fetchImpl });
  await assert.rejects(
    answering(async () => new Response("<html>not darkmem</html>", { status: 200 })).manifest("p", "superpowers"),
    error => error instanceof TransportError && /not JSON/.test(error.message),
  );
  await assert.rejects(
    answering(async () => new Response(JSON.stringify({ detail: "Not Found" }), { status: 404 })).resume("p", "w"),
    error => error instanceof HttpError && error.status === 404,
  );
}));

test("a refused connection and a silent server are TransportErrors within the timeout", async () => {
  const refused = createClient({ url: "http://127.0.0.1:9", apiKey: "k", runKey: "r", timeoutMs: 2000 });
  await assert.rejects(refused.manifest("p", "superpowers"), TransportError);
  const silent = http.createServer(() => {});
  await new Promise(resolve => silent.listen(0, "127.0.0.1", resolve));
  try {
    const client = createClient({ url: `http://127.0.0.1:${silent.address().port}`, apiKey: "k", runKey: "r", timeoutMs: 300 });
    const started = Date.now();
    await assert.rejects(client.manifest("p", "superpowers"), /no answer within 300 ms/);
    assert.ok(Date.now() - started < 3000);
  } finally {
    silent.closeAllConnections();
    await new Promise(resolve => silent.close(resolve));
  }
});

test("an append with expected_last_seq writes only when it names the newest seq of its kind, and answers last_seq", () => withStub({}, async (stub, client) => {
  const first = await client.append({ project: "p", workstream: "w", entries: [{ kind: "ledger", body: "a" }, { kind: "ledger", body: "b" }], expectedLastSeq: 0 });
  assert.equal(stub.db.requests[0].body.expected_last_seq, 0);
  assert.equal(first.last_seq, stub.db.workstreams[0].entries.at(-1).seq);
  await client.append({ project: "p", workstream: "w", entries: [{ kind: "checkpoint", body: "c" }] });
  const second = await client.append({ project: "p", workstream: "w", entries: [{ kind: "ledger", body: "d" }], expectedLastSeq: first.last_seq });
  assert.equal(second.last_seq, first.last_seq + 2, "a checkpoint between them does not move the ledger's expectation");
  await assert.rejects(
    client.append({ project: "p", workstream: "w", entries: [{ kind: "ledger", body: "e" }], expectedLastSeq: first.last_seq }),
    error => error instanceof HttpError && error.status === 409
      && error.detail === `expected the newest ledger entry to be seq ${first.last_seq}, but it is ${second.last_seq}`,
  );
  await assert.rejects(
    client.append({ project: "p", workstream: "fresh", entries: [{ kind: "ledger", body: "x" }], expectedLastSeq: 5 }),
    error => error instanceof HttpError && error.status === 409,
  );
  assert.equal(stub.db.workstreams.some(w => w.key === "fresh"), false, "a refused append creates no workstream");
  await assert.rejects(
    client.append({ project: "p", workstream: "w", entries: [{ kind: "ledger", body: "x" }, { kind: "note", body: "y" }], expectedLastSeq: second.last_seq }),
    error => error instanceof HttpError && error.status === 422,
  );
  await client.append({ project: "p", workstream: "w", entries: [{ kind: "note", body: "n" }] });
  assert.equal("expected_last_seq" in stub.db.requests.at(-1).body, false, "left out unless given");
  assert.equal(stub.db.workstreams[0].entries.length, 5);
}));

test("failItem records any darkmem answer but a 401 as one item's failure and rethrows everything else", () => {
  const report = { failures: [] };
  failItem(report, "superpowers/a.md", new HttpError("GET", "/x", 503, "busy"));
  failItem(report, "document manifest", new HttpError("GET", "/x", 403, "forbidden"), "; no document pushed");
  assert.deepEqual(report.failures, ["superpowers/a.md: darkmem answered 503: busy", "document manifest: darkmem answered 403: forbidden; no document pushed"]);
  for (const error of [new HttpError("GET", "/x", 401, "Not authenticated"), new TransportError("GET /x: no answer within 10 ms"), new Error("bug")]) {
    assert.throws(() => failItem(report, "x", error), error);
  }
  assert.equal(report.failures.length, 2);
});
