// The keyed REST surface darkmem serves a mirror (work-log lane spec §2): the
// work-log routes, POST /documents, GET /documents/by-uri and the manifest.
// Every call carries the API key, names this client, and gives up after a
// bounded timeout.
export class TransportError extends Error {}

export class HttpError extends Error {
  constructor(method, route, status, detail) {
    super(`${method} ${route} answered ${status}: ${detail}`);
    this.status = status;
    this.detail = detail;
  }
}

const CLIENT = "dr-superpowers";

export function createClient({ url, apiKey, runKey, timeoutMs = 10000, fetchImpl = globalThis.fetch }) {
  async function call(method, route, { query = {}, body } = {}) {
    const target = new URL(`${url}${route}`);
    for (const [name, value] of Object.entries(query)) {
      if (value !== undefined && value !== null) target.searchParams.set(name, String(value));
    }
    const headers = { Authorization: `Bearer ${apiKey}`, "X-Darkmem-Client": CLIENT, Accept: "application/json" };
    if (body !== undefined) headers["Content-Type"] = "application/json";
    let response;
    let text;
    try {
      response = await fetchImpl(target, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      });
      text = await response.text();
    } catch (error) {
      const reason = error?.name === "TimeoutError"
        ? `no answer within ${timeoutMs} ms`
        : (error?.cause?.message ?? error?.message ?? String(error));
      throw new TransportError(`${method} ${route}: ${reason}`);
    }
    let data = null;
    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        data = null;
      }
    }
    if (!response.ok) {
      const detail = typeof data?.detail === "string"
        ? data.detail
        : data?.detail !== undefined ? JSON.stringify(data.detail) : text.slice(0, 300);
      throw new HttpError(method, route, response.status, detail);
    }
    return data;
  }

  return {
    async manifest(project, uriPrefix) {
      const items = [];
      let after;
      do {
        const page = await call("GET", "/api/v1/documents/manifest", { query: { project, uri_prefix: uriPrefix, after, limit: 1000 } });
        items.push(...page.items);
        after = page.next_after;
      } while (after);
      return items;
    },
    getDocument(project, uri) {
      return call("GET", "/api/v1/documents/by-uri", { query: { project, uri, include_content: "true" } });
    },
    putDocument({ project, uri, content, expectedHash }) {
      const body = { project, uri, content };
      if (expectedHash) body.expected_hash = expectedHash;
      return call("POST", "/api/v1/documents", { body });
    },
    append({ project, workstream, entries, properties }) {
      const body = { project, workstream, run_key: runKey, client: CLIENT, entries };
      if (properties) body.properties = properties;
      return call("POST", "/api/v1/worklog/entries", { body });
    },
    async resume(project, workstream) {
      try {
        return await call("GET", "/api/v1/worklog/resume", { query: { project, workstream } });
      } catch (error) {
        if (error instanceof HttpError && error.status === 404) return null;
        throw error;
      }
    },
    async workstreams(project, state) {
      const items = [];
      let before;
      do {
        const page = await call("GET", "/api/v1/worklog/workstreams", { query: { project, state, before, limit: 200 } });
        items.push(...page.items);
        before = page.next_before;
      } while (before);
      return items;
    },
    async entries(workstreamId, kind) {
      const items = [];
      let after;
      do {
        const page = await call("GET", `/api/v1/worklog/workstreams/${encodeURIComponent(workstreamId)}/entries`, { query: { kind, after, limit: 500 } });
        items.push(...page.items);
        after = page.next_after;
      } while (after !== null && after !== undefined);
      return items;
    },
    updateWorkstream(id, patch) {
      return call("PATCH", `/api/v1/worklog/workstreams/${encodeURIComponent(id)}`, { body: patch });
    },
    purgeWorkstream(id) {
      return call("DELETE", `/api/v1/worklog/workstreams/${encodeURIComponent(id)}`);
    },
  };
}
