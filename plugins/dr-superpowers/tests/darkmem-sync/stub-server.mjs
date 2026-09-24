// An in-memory stand-in for the darkmem routes darkmem-sync calls, faithful to
// the contract points the sync relies on: content_hash is SHA-256 of the UTF-8
// content; a stale or absent expected_hash is a 409; an append needs a run key,
// holds 1-100 entries of 1-65,536 characters, and reopens a closed workstream;
// every list is keyset-paged. db.failures injects answers: {method, path,
// status, detail, commit}, where commit: true applies the request first and
// then answers the failure, which is what a lost response looks like.
import crypto from "node:crypto";
import http from "node:http";

export const STUB_KEY = "dmk_test_secret";

export const sha = text => crypto.createHash("sha256").update(text, "utf8").digest("hex");

// A document as the stub stores it, for a test that plants one directly.
export function storedDocument(project, uri, content) {
  return { id: crypto.randomUUID(), project, uri, content, content_hash: sha(content), updated_at: new Date().toISOString() };
}

// pageSize caps every page, to exercise paging. transformContent rewrites a
// document's content as it is stored, to simulate a server that alters bytes.
// onRequest(request, db) runs before each authenticated request is answered,
// to simulate another client or a local edit landing mid-sync.
export async function startStub({ pageSize, transformContent, onRequest } = {}) {
  const db = { documents: new Map(), workstreams: [], requests: [], failures: [], nextSeq: 1, clock: Date.now() };
  const tick = () => new Date((db.clock += 1000)).toISOString();
  const docKey = (project, uri) => `${project}\u0000${uri}`;
  const limitOf = (url, fallback) => {
    const asked = Number(url.searchParams.get("limit") ?? fallback);
    return pageSize ? Math.min(asked, pageSize) : asked;
  };
  const wsOut = ws => ({
    id: ws.id, project: ws.project, key: ws.key, title: ws.title, client: ws.client, state: ws.state,
    closed_at: ws.closed_at, retain: ws.retain, properties: ws.properties, last_entry_at: ws.last_entry_at,
    created_at: ws.created_at, updated_at: ws.updated_at,
  });
  const entryOut = (ws, e) => ({
    id: e.id, workstream_id: ws.id, seq: e.seq, run_key: e.run_key, kind: e.kind, body: e.body,
    properties: e.properties, created_at: e.created_at,
  });

  function route(method, url, body, send) {
    const q = url.searchParams;
    const p = url.pathname;
    let m;
    if (method === "GET" && p === "/api/v1/documents/manifest") {
      const project = q.get("project");
      const prefix = (q.get("uri_prefix") ?? "").replace(/\/+$/, "");
      const after = q.get("after");
      const limit = limitOf(url, 500);
      const items = [...db.documents.values()]
        .filter(d => d.project === project && (prefix === "" || d.uri === prefix || d.uri.startsWith(`${prefix}/`)) && (after === null || d.uri > after))
        .sort((a, b) => (a.uri < b.uri ? -1 : a.uri > b.uri ? 1 : 0))
        .slice(0, limit)
        .map(d => ({ id: d.id, uri: d.uri, content_hash: d.content_hash, updated_at: d.updated_at }));
      return send(200, { items, next_after: items.length === limit ? items.at(-1).uri : null });
    }
    if (method === "GET" && p === "/api/v1/documents/by-uri") {
      const doc = db.documents.get(docKey(q.get("project"), q.get("uri")));
      if (!doc) return send(404, { detail: "Document not found" });
      const answer = { document_id: doc.id, blocks: [], content_hash: doc.content_hash, horizon: true };
      if (q.get("include_content") === "true") answer.content = doc.content;
      return send(200, answer);
    }
    if (method === "POST" && p === "/api/v1/documents") {
      if (typeof body?.content !== "string" || body.content.length === 0) return send(422, { detail: "content must not be empty" });
      const key = docKey(body.project, body.uri);
      const existing = db.documents.get(key);
      const content = transformContent ? transformContent(body.content) : body.content;
      const hash = sha(content);
      if (body.expected_hash !== undefined && body.expected_hash !== null && (!existing || existing.content_hash !== body.expected_hash)) {
        return send(409, { detail: `expected_hash ${body.expected_hash} does not match the document's current content_hash ${existing?.content_hash ?? null}` });
      }
      const outcome = !existing ? "created" : existing.content_hash === hash ? "unchanged" : "updated";
      const doc = existing ?? { id: crypto.randomUUID(), project: body.project, uri: body.uri };
      if (outcome !== "unchanged") Object.assign(doc, { content, content_hash: hash, updated_at: tick() });
      db.documents.set(key, doc);
      return send(201, {
        document_id: doc.id, outcome, blocks_filed: 0, blocks_embedded: 0, title_applied: outcome !== "unchanged",
        oversized_blocks: null, largest_block_chars: null, content_hash: doc.content_hash,
      });
    }
    if (method === "POST" && p === "/api/v1/worklog/entries") {
      if (!body?.run_key) return send(422, { detail: "a work-log entry needs a declared agent-run identity" });
      if (!Array.isArray(body.entries) || body.entries.length < 1 || body.entries.length > 100) {
        return send(422, { detail: "entries must hold 1 to 100 items" });
      }
      for (const e of body.entries) {
        if (!["checkpoint", "ledger", "note"].includes(e.kind)) return send(422, { detail: `unknown kind ${e.kind}` });
        const chars = [...(e.body ?? "")].length;
        if (chars < 1 || chars > 65536) return send(422, { detail: `body must hold 1 to 65536 characters, got ${chars}` });
      }
      const now = tick();
      let ws = db.workstreams.find(w => w.project === body.project && w.key === body.workstream);
      if (!ws) {
        ws = {
          id: crypto.randomUUID(), project: body.project, key: body.workstream, title: body.title ?? null,
          client: body.client ?? null, state: "open", closed_at: null, retain: false, properties: {}, entries: [],
          created_at: now, updated_at: now, last_entry_at: now,
        };
        db.workstreams.push(ws);
      }
      if (ws.state === "closed") Object.assign(ws, { state: "open", closed_at: null });
      Object.assign(ws.properties, body.properties ?? {});
      const ids = body.entries.map(e => {
        const entry = { id: crypto.randomUUID(), seq: db.nextSeq++, run_key: body.run_key, kind: e.kind, body: e.body, properties: e.properties ?? {}, created_at: now };
        ws.entries.push(entry);
        return entry.id;
      });
      Object.assign(ws, { last_entry_at: now, updated_at: now });
      return send(201, { workstream: wsOut(ws), entry_ids: ids });
    }
    if (method === "GET" && p === "/api/v1/worklog/resume") {
      const ws = db.workstreams.find(w => w.project === q.get("project") && w.key === q.get("workstream"));
      if (!ws) return send(404, { detail: "No workstream with that key in that project" });
      const of = kind => ws.entries.filter(e => e.kind === kind);
      const checkpoints = of("checkpoint");
      const notes = of("note");
      return send(200, {
        workstream: wsOut(ws),
        checkpoint: checkpoints.length ? entryOut(ws, checkpoints.at(-1)) : null,
        notes: notes.slice(-50).map(e => entryOut(ws, e)),
        notes_truncated: notes.length > 50,
        ledger: of("ledger").slice(-20).map(e => entryOut(ws, e)),
      });
    }
    if (method === "GET" && p === "/api/v1/worklog/workstreams") {
      const state = q.get("state");
      const before = q.get("before");
      const limit = limitOf(url, 50);
      const all = db.workstreams.filter(w => w.project === q.get("project") && (!state || w.state === state)).reverse();
      const start = before ? all.findIndex(w => w.id === before) + 1 : 0;
      const items = all.slice(start, start + limit);
      return send(200, { items: items.map(wsOut), next_before: items.length === limit ? items.at(-1).id : null });
    }
    if (method === "GET" && (m = p.match(/^\/api\/v1\/worklog\/workstreams\/([^/]+)\/entries$/))) {
      const ws = db.workstreams.find(w => w.id === m[1]);
      if (!ws) return send(404, { detail: "No such workstream" });
      const kind = q.get("kind");
      const after = q.get("after") === null ? 0 : Number(q.get("after"));
      const limit = limitOf(url, 100);
      const items = ws.entries.filter(e => (!kind || e.kind === kind) && e.seq > after).slice(0, limit);
      return send(200, { items: items.map(e => entryOut(ws, e)), next_after: items.length === limit ? items.at(-1).seq : null });
    }
    if ((m = p.match(/^\/api\/v1\/worklog\/workstreams\/([^/]+)$/))) {
      const index = db.workstreams.findIndex(w => w.id === m[1]);
      if (index < 0) return send(404, { detail: "No such workstream" });
      const ws = db.workstreams[index];
      if (method === "PATCH") {
        if (body?.state) Object.assign(ws, { state: body.state, closed_at: body.state === "closed" ? tick() : null });
        if (typeof body?.retain === "boolean") ws.retain = body.retain;
        if (typeof body?.title === "string") ws.title = body.title;
        if (body?.properties) Object.assign(ws.properties, body.properties);
        return send(200, wsOut(ws));
      }
      if (method === "DELETE") {
        db.workstreams.splice(index, 1);
        return send(204);
      }
    }
    return send(404, { detail: `stub has no route ${method} ${p}` });
  }

  const server = http.createServer((req, res) => {
    let raw = "";
    req.setEncoding("utf8");
    req.on("data", chunk => { raw += chunk; });
    req.on("end", () => {
      const url = new URL(req.url, "http://stub");
      const send = (status, payload) => {
        res.writeHead(status, { "Content-Type": "application/json" });
        res.end(payload === undefined ? "" : JSON.stringify(payload));
      };
      let body;
      try {
        body = raw ? JSON.parse(raw) : undefined;
      } catch {
        return send(400, { detail: "body is not JSON" });
      }
      const request = { method: req.method, path: url.pathname, query: Object.fromEntries(url.searchParams), headers: req.headers, body };
      db.requests.push(request);
      if (req.headers.authorization !== `Bearer ${STUB_KEY}`) return send(401, { detail: "Not authenticated" });
      if (onRequest) onRequest(request, db);
      const injected = db.failures.findIndex(f => f.method === req.method && url.pathname.startsWith(f.path));
      if (injected >= 0) {
        const [failure] = db.failures.splice(injected, 1);
        if (failure.commit) route(req.method, url, body, () => {});
        return send(failure.status, { detail: failure.detail ?? "injected failure" });
      }
      return route(req.method, url, body, send);
    });
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  return {
    url: `http://127.0.0.1:${server.address().port}`,
    db,
    close: () => new Promise(resolve => {
      server.closeAllConnections();
      server.close(() => resolve());
    }),
  };
}
