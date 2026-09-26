# darkmem-sync Hardening (Client) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the gaps the final review of darkmem-sync's increment 1 left (register row 7) — one bad item no longer stops a push or pull, ledgers push under darkmem's `expected_last_seq`, a failed handoff link is retried, an invalid ledger byte fails with its offset, checkpoints compare to the microsecond, unportable and case-twin uris are refused, and the lock never deletes a lock it did not judge abandoned.

**Architecture:** No new file. `darkmem-mirror.mjs` gains two state fields (`lastSeq` on a ledger record, `pendingLinks`), four pure helpers (`utf8Fault`, `isoMicros`, `uriProblem`, `caseGroups`) and a lock that leaves a mistakenly moved lock aside. `darkmem-client.mjs` gains `failItem`, the one rule for which darkmem answers become an item's failure line and which stop the run, and sends `expected_last_seq`. `darkmem-push.mjs` and `darkmem-pull.mjs` use them item by item; the stub server implements the precondition as darkmem's server does.

**Tech Stack:** Node.js 22 built-ins only (`fetch`, `node:http`, `node:test`), bash, git.

**Spec:** `docs/superpowers/specs/2026-09-25-darkmem-sync-hardening-design.md`

**Execution:** inline — `claude --model opus --effort high` — 3 of 6 tasks are heavy (Tasks 1, 2 and 4, delegated to their implementers), 3 are four-band (Tasks 3, 5 and 6; 3 × 3 > 6, so none is delegated for its band), and Task 3 carries a Codex `**Executor:**` line and is delegated through it; the session implements Tasks 5 and 6 itself at total 4, so the model is opus, and effort is high because tasks are delegated.

**Plan review:** 2026-09-26 — dr-superpowers:judge-opus — executability 18 / coherence 18 / coverage 18 / assumptions 15 (round 2)

> **External executors:** codex

## Global Constraints

- Node.js 22 built-ins only: no npm dependency, no `package.json`. CI runs Node 22 on Linux and Windows (`.github/workflows/validate.yml`).
- Work on branch `docs/darkmem-mirror-spec` in place, as darkmem-sync's first plan did (its ledger's ruling): the spec, the sync client and this plan exist only on this branch. It merges into `main` only through a pull request whose six Windows CI shards pass (register row 6); never merge it locally.
- Every command in a task, `git add` and `git commit` included, runs from `plugins/dr-superpowers` unless the step says otherwise; the paths in each commit step are relative to that directory. Run every `node` command, test suite and `claude plugin validate` under `timeout`; plain `git`, `grep`, `ls` and `cat` need none.
- Every `node --test` command passes `--test-reporter=spec`: Node 22 prints TAP, not the `ℹ pass` summary the steps check, when stdout is not a terminal.
- Tests call no model and no real darkmem. Never point the sync at a real darkmem while working this plan: darkmem's append schema forbids unknown fields (`backend/app/schemas/worklog.py:54`), so a server without the precondition deployed answers every ledger push 422.
- Only the edits a task lists: no other change to `scripts/lib/darkmem-import.mjs`, `darkmem-config.mjs`, `darkmem-sync.mjs`, `scripts/darkmem-sync`, the README or any skill. `import` keeps appending without the precondition (spec, Not in scope).
- The state file stays version 1 and no migration is written (spec §2): a record without `lastSeq` is reconciled against darkmem before its first append, and a state without `pendingLinks` loads it as `[]`.
- The dr-superpowers manifests stay at `1.22.0`: that release is unmerged on this branch, and this plan joins it.
- A test that creates a file name Windows cannot hold skips on `win32`; a test that needs two files differing only in case skips off Linux. Every other test runs on every platform. The pass counts the steps give are Linux runs: from Task 5 on, Windows reports two fewer passes and `ℹ skipped 2` (`push refuses a uri Windows cannot hold`, `push refuses local files that differ only in case`), and macOS one fewer and `ℹ skipped 1` (the second).
- Commit messages follow `<type>(superpowers): <subject>`, the whole subject line 50 characters or fewer, and end with the `Co-Authored-By:` line naming the model that did the work. Each task's commit step spells the line for its assigned implementer; an implementer running on a different model writes its own model's name.
- English only in code, comments, docs and tests. Do not edit historical plans or specs.

## Contracts

- **Files** (all under `plugins/dr-superpowers/`): `scripts/lib/darkmem-mirror.mjs` (Tasks 1, 2), `scripts/lib/darkmem-client.mjs` (Task 3), `tests/darkmem-sync/stub-server.mjs` (Task 3), `scripts/lib/darkmem-pull.mjs` (Tasks 4, 6), `scripts/lib/darkmem-push.mjs` (Tasks 4, 5), and the suites `tests/darkmem-sync/{mirror,client,pull,push}.test.mjs`.
- **State file** (Task 1): `<mirror>/.sync-state.json` = `{version: 1, documents, ledgers: {<slug>: {offset, prefix, lastSeq?, pending?}}, checkpoint, checkpointAt, conflicts, pendingLinks: [<handoff uri>]}`. `lastSeq`, when present, is a safe integer ≥ 0: the seq of the newest ledger entry darkmem holds for the bytes up to `offset` (0 for none). `pendingLinks` is an array of strings, `[]` when absent, and holds `superpowers/handoff/<slug>.md` uris whose workstream link has not been confirmed. Any other value is a `StateError`.
- **darkmem-mirror.mjs** (Tasks 1, 2): `utf8Fault(buffer)` → `null` when `buffer` is strict UTF-8, else `{offset, partial}` — `offset` the index of the first byte that does not decode, `partial` true only when the fault is a character cut short by the end of the buffer; `isoMicros(text)` → microseconds since the epoch as a safe integer (offset applied, fraction padded or cut to six digits, a missing fraction reading as zero), or `null` when `text` is not `YYYY-MM-DDTHH:MM:SS[.fraction]` with `Z` or `±HH:MM`, names an impossible date, time or offset (February 30, minute 60, `+24:00`), or falls outside the years 1970–2200; `uriProblem(uri)` → `null`, or one of `the name "<segment>" holds a character Windows refuses` (`< > : " | ? *` or any Unicode control character, category Cc: U+0000–U+001F and U+007F–U+009F), `the name "<segment>" ends in a dot or a space`, `the name "<segment>" is a Windows device name`; `caseGroups(uris)` → every group of two or more distinct uris equal under `toLowerCase()`, each group sorted; `acquireLock(dir, {staleMs = 600000, beforeTakeover, beforeRestore})` → release function or `null`. Off Windows a lock is built as `.sync.lock.new-<token>` with its `owner.json` inside and renamed to `.sync.lock`, so it is never an empty directory; on `win32`, where a rename never replaces a directory, it is `mkdir` then the owner write, as at the base commit. The release moves the lock to `.sync.lock.stale-<token>` and deletes it there only while it still carries this holder's token. A lock moved aside by mistake is renamed back and, when that fails, left as `.sync.lock.stale-<token>`; each acquire first removes `.sync.lock.stale-*` and `.sync.lock.new-*` directories older than `staleMs`. `beforeRestore` runs just before the rename back.
- **darkmem-client.mjs** (Task 3): `failItem(report, label, error, suffix = "")` pushes `<label>: darkmem answered <status>: <detail><suffix>` onto `report.failures` when `error` is an `HttpError` other than 401, and rethrows anything else; `append({project, workstream, entries, properties, expectedLastSeq})` adds `expected_last_seq` to the body only when `expectedLastSeq` is not `undefined`, and resolves to `{workstream, entry_ids, last_seq}`.
- **Stub append** (Task 3; darkmem's route, `backend/app/api/routes/worklog.py:60-84`): with `expected_last_seq` set, a value that is not a safe integer ≥ 0 is 422; entries of more than one kind are 422 (`expected_last_seq needs every entry of the append to share one kind`); otherwise the newest seq of that kind in the workstream (0 when the workstream or the kind is absent) must equal it, or the answer is 409 `expected the newest <kind> entry to be seq <expected>, but it is <current>` and nothing is written — no entry, no workstream. Every 201 answer carries `last_seq`, the seq of the last entry written.
- **Stub by-uri 404** (Task 3; consumed by Task 5): `GET /api/v1/documents/by-uri` for a uri nothing is filed at answers 404 `no document is filed at uri '<uri>' in project '<project>'`, darkmem's own text (`backend/app/services/document_door.py:181-185`, raised through `backend/app/api/routes/documents.py:137-141`).
- **darkmem-pull.mjs** (Task 4): `remoteLedger(client, workstreamId)` → `{text, lastSeq}`, the ledger entries' bodies joined in order and the seq of the newest (0 for none). It replaces `ledgerText`, whose only callers were `pullLedgers` and push's `adoptRemoteLedger`.
- **Output lines** (Tasks 4–6; each is printed after `failed: `, `conflict: ` or `note: ` as today):
  - failed `<label>: darkmem answered <status>: <detail>` — label `<uri>`, `sdd/<slug>/progress.md` or `handoff/latest.md`; for a handoff link `<uri>: linking it from workstream <slug>: darkmem answered …`; for a phase `document manifest: darkmem answered …; no document pushed`, `document manifest: darkmem answered …; no document pulled`, `workstream list: darkmem answered …; no ledger or checkpoint pulled`, and `handoff/latest.md: darkmem answered … (reading workstream <key>); not pulled`.
  - failed `sdd/<slug>/progress.md: byte <file offset> is not UTF-8 text; not pushed`.
  - failed `<uri>: <uriProblem>, so not every mirror can hold it as a file; not pushed` (push) and `…; not pulled — rename it on darkmem by hand` (pull).
  - conflict `<uri>, <uri>…: differ only in case, which a case-insensitive file system holds as one file; none of them pushed — rename all but one` (push, local files) and `…; none of them pulled — rename or delete all but one on darkmem by hand (the sync has no rename or delete route)` (pull).
  - conflict `<uri>: darkmem holds <twins, comma-separated>, which differ only in case from it; not pushed — rename the local file, or rename or delete the others on darkmem by hand (the sync has no rename or delete route)` — every spelling darkmem holds under the uri's lower-case form other than the uri itself.
  - A push's 409 is followed by a read of the document; only darkmem's own 404 text (Contracts → **Stub by-uri 404**) makes that a `deleted on darkmem since the last sync` conflict, and any other 404 is a failure line.
  - Pull reads every open workstream's checkpoint even after one read fails, and writes no `latest.md` in a run where any failed.
  - A `TransportError` and a 401 still stop the command with exit 3; any failure or conflict is exit 1, as today.

## Assumptions (evidence)

- darkmem's side (spec §1) is merged into darkmem `master` and not deployed (darkmem register row 26, read 2026-09-26 at `a2b003fc`): the schema field (`backend/app/schemas/worklog.py:86-97`), the service's comparison under the row lock and its message (`backend/app/services/worklog.py:91-96,217-237`), the route's 409 and `last_seq` (`backend/app/api/routes/worklog.py:72-81`). The stub copies that behaviour; the first run against a real darkmem is the owner's, after that deploy.
- The spec says every existing suite passes unchanged, but its own rules change five existing assertions, and this plan follows the rules: under §2's per-item rule an injected 502 on a document put, a ledger append or a checkpoint append is a failure line and exit 1, not exit 3 (Tasks 4 and 5 edit those three assertions and add the failure line); under §3 a 503 on the workstream list fails its phase instead of stopping the pull, so "conflicts found before a failure are kept for status" injects a 401 to keep testing a run that stops part-way (Task 6); and pull now records `lastSeq`, so the ledger record that test compares gains it (Task 4). No other existing test changes.
- The three-process lock race needs a point between moving the lock aside and giving it back, which `beforeTakeover` (before the move) cannot reach; Task 2 adds a second seam, `beforeRestore`, rather than stubbing `fs`.
- A lock window the spec does not name (register row 15): on POSIX, `rename` onto an existing *empty* directory replaces it, and the base commit's lock is empty between its `mkdir` and its `owner.json` write, so a restore landing there would replace a fresh lock. Task 2 builds each lock under a temporary name with its owner record inside and renames it into place, and releases it by moving it aside before deleting it, so a live lock directory is never empty and neither a restore nor a new lock's rename can land on one. An empty `.sync.lock` left by an older version is still judged by its age before any rename, as today. Node has no create-only rename for directories (`renameat2`'s `RENAME_NOREPLACE` is not exposed), which is why the lock is kept non-empty instead. On `win32` the lock keeps `mkdir` plus the owner write: a Windows rename never replaces an existing directory, so the hazard is POSIX-only, and renaming a just-written directory there is a known intermittent failure under antivirus and indexer handles (inferred, the reason graceful-fs retries renames on Windows; not observed here). The Linux suite runs only the rename branch; CI's Windows shards run the other (register row 6).
- Push now reads the manifest whenever it has a changed document to send (at the base commit it read it only for a document no sync had recorded), because the case check compares each outgoing uri with darkmem's uris. That is one extra `GET` per push that sends a document.
- When one open workstream's checkpoint read fails, pull writes no `latest.md` that run: the newest checkpoint cannot be known without every workstream's, and the next pull takes it.
- Every edit in Tasks 1–6 was run on a scratch worktree of `7538f90` on 2026-09-26, applied task by task from this plan's own text: after each task the darkmem-sync suite passes 73, 75, 77, 82, 91 and 95 tests, the final tree equals the prototype byte for byte, and three consecutive full runs pass 95 of 95 leaving no fixture directory. Before each task's implementation its new tests fail as the Step 2 lines list, except two guards that pass before and after: a 401 on a document stops the push (Task 5), and the edited conflicts test (Task 6). `node scripts/validate-repository.mjs` is valid; `node scripts/test-all.mjs` fails only `tests/ui-discovery.test.mjs`, which calls `rg` from a non-interactive `bash` where it is not on `PATH` here, and fails identically on `main`.
- `utf8Fault` uses the WHATWG decoder's byte ranges; on 2026-09-26, 300,000 random buffers of one to six bytes drawn from the boundary bytes gave no disagreement with `decodeUtf8`, and Task 1's test keeps a seeded 20,000-buffer version of that check.
- Codex executor: `codex-gate` printed `lane=true` (`source=probe`) on 2026-09-26, and `docs/superpowers/distilled/constraints.md` ticks the lane without asking. Only Task 3 passes the lane gate (total ≥ 2, risk ≤ 1). Its client suite binds `127.0.0.1` through the stub server, which the Codex sandbox refused on three runs of an earlier darkmem plan (darkmem-sync's first plan, Assumptions); if it refuses again, the lane's two-failure rule hands the task back to its `**Implementer:**`.
- Review: round 1 (codex gpt-6-astra / xhigh; 15 / 16 / 15 / 17) raised 2 Critical and 8 Important findings, all fixed; round 2 (judge-opus; 18 / 18 / 18 / 15) confirmed every one addressed and raised 1 Important and 4 Minor findings, all fixed after the round (`.superpowers/sdd/2026-09-26-darkmem-sync-hardening/plan-review-round-2.md`). No round returned a score of 8 or below after round 1's Criticals were fixed, so no third round ran.
- Windows is unverified locally: the new tests that create `a:b.md` or `CON.md` skip on `win32`, the local case-twin test skips off Linux, and CI's Windows shards are the first run there (register row 6).

## Task index

1. Sync state fields and text checks
2. The lock never deletes a lock it moved aside by mistake
3. The append precondition in the stub and the client
4. Ledger pushes guarded by the last seq
5. Push goes on past a failed document, link or checkpoint
6. Pull goes on past a failed item and refuses unportable uris

---

### Task 1: Sync state fields and text checks

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/darkmem-mirror.mjs` (`emptyState`, `isLedgerRecord`, `loadState`; four helpers before `decodeUtf8`)
- Test: `plugins/dr-superpowers/tests/darkmem-sync/mirror.test.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces: Contracts → **State file**, and `utf8Fault`, `isoMicros`, `uriProblem`, `caseGroups` in Contracts → **darkmem-mirror.mjs**.

**Items:** 7

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

The state keeps two new fields and four pure helpers arrive for Tasks 4–6. `utf8Fault` must agree with `decodeUtf8` on every input; the test checks 20,000 seeded random buffers against it.

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/darkmem-sync/mirror.test.mjs`, replace:

```js
import {
  EMPTY_SHA, StateError, acquireLock, checkpointTarget, lockOwner, decodeUtf8, emptyState, ledgerFiles, ledgerPlanPath,
  listDocumentFiles, loadState, localChanges, pathToUri, propertiesFor, saveState, sha256, splitAtBlankLines,
  splitAtLimit, unsupportedPlanDirs, uriToLocal,
} from "../../scripts/lib/darkmem-mirror.mjs";
```

with:

```js
import {
  EMPTY_SHA, StateError, acquireLock, caseGroups, checkpointTarget, lockOwner, decodeUtf8, emptyState, isoMicros,
  ledgerFiles, ledgerPlanPath, listDocumentFiles, loadState, localChanges, pathToUri, propertiesFor, saveState, sha256,
  splitAtBlankLines, splitAtLimit, unsupportedPlanDirs, uriProblem, uriToLocal, utf8Fault,
} from "../../scripts/lib/darkmem-mirror.mjs";
```

In `plugins/dr-superpowers/tests/darkmem-sync/mirror.test.mjs`, replace:

```js
    JSON.stringify({ ...good, conflicts: [1] }),
  ]) {
```

with:

```js
    JSON.stringify({ ...good, conflicts: [1] }),
    JSON.stringify({ ...good, ledgers: { p1: { offset: 0, prefix: EMPTY_SHA, lastSeq: -1 } } }),
    JSON.stringify({ ...good, ledgers: { p1: { offset: 0, prefix: EMPTY_SHA, lastSeq: "3" } } }),
    JSON.stringify({ ...good, ledgers: { p1: { offset: 0, prefix: EMPTY_SHA, lastSeq: 1.5 } } }),
    JSON.stringify({ ...good, pendingLinks: "superpowers/handoff/p1.md" }),
    JSON.stringify({ ...good, pendingLinks: [1] }),
  ]) {
```

Append to the end of `plugins/dr-superpowers/tests/darkmem-sync/mirror.test.mjs`:

```js
test("a ledger's lastSeq and the pending handoff links survive a save, and an older state loads with no links", () => {
  const { root } = mirror();
  const file = path.join(root, ".sync-state.json");
  const state = emptyState();
  assert.deepEqual(state.pendingLinks, []);
  state.ledgers.p1 = { offset: 3, prefix: sha256("abc"), lastSeq: 7 };
  state.pendingLinks.push("superpowers/handoff/p1.md");
  saveState(file, state);
  const loaded = loadState(file);
  assert.deepEqual(loaded.ledgers.p1, { offset: 3, prefix: sha256("abc"), lastSeq: 7 });
  assert.deepEqual(loaded.pendingLinks, ["superpowers/handoff/p1.md"]);
  fs.writeFileSync(file, JSON.stringify({ version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [] }));
  assert.deepEqual(loadState(file).pendingLinks, []);
});

test("utf8Fault finds the first undecodable byte and tells a character cut short at the end apart", () => {
  assert.equal(utf8Fault(Buffer.from("héllo ✓ 😀\n")), null);
  assert.deepEqual(utf8Fault(Buffer.from([0x61, 0xe2, 0x82])), { offset: 1, partial: true });
  assert.deepEqual(utf8Fault(Buffer.from([0x61, 0xf0, 0x9f, 0x98])), { offset: 1, partial: true });
  assert.deepEqual(utf8Fault(Buffer.from([0x61, 0xff])), { offset: 1, partial: false }, "a lone 0xFF is never a partial character");
  assert.deepEqual(utf8Fault(Buffer.from([0x61, 0xc3, 0x28, 0x62])), { offset: 1, partial: false });
  assert.deepEqual(utf8Fault(Buffer.from([0x61, 0x62, 0x80])), { offset: 2, partial: false });
  assert.deepEqual(utf8Fault(Buffer.from([0xe0, 0x80])), { offset: 0, partial: false }, "an overlong lead is refused at once");
  const pool = [0x00, 0x41, 0x7f, 0x80, 0x9f, 0xa0, 0xbf, 0xc1, 0xc2, 0xdf, 0xe0, 0xed, 0xef, 0xf0, 0xf4, 0xf5, 0xff];
  let seed = 7;
  const next = () => (seed = (seed * 1103515245 + 12345) % 2147483648);
  for (let n = 0; n < 20000; n += 1) {
    const buffer = Buffer.from(Array.from({ length: 1 + (next() % 6) }, () => pool[next() % pool.length]));
    assert.equal(utf8Fault(buffer) === null, decodeUtf8(buffer) !== null, buffer.toString("hex"));
  }
});

test("isoMicros orders darkmem's timestamps to the microsecond, offsets applied", () => {
  assert.equal(isoMicros("2026-09-25T10:00:00.000002+00:00") - isoMicros("2026-09-25T10:00:00.000001+00:00"), 1);
  assert.equal(isoMicros("2026-09-25T10:00:00+00:00"), isoMicros("2026-09-25T10:00:00.000000Z"), "a dropped zero fraction");
  assert.equal(isoMicros("2026-09-25T12:00:00.5+02:00"), isoMicros("2026-09-25T10:00:00.500000Z"));
  assert.equal(isoMicros("2026-09-25T10:00:00.1234567Z"), isoMicros("2026-09-25T10:00:00.123456Z"), "digits past six are dropped");
  assert.equal(isoMicros("2026-09-24T10:00:00.123Z"), Date.parse("2026-09-24T10:00:00.123Z") * 1000);
  assert.equal(isoMicros("2200-12-31T23:59:59.999999Z"), Date.UTC(2200, 11, 31, 23, 59, 59) * 1000 + 999999);
  assert.ok(Number.isSafeInteger(isoMicros("2200-12-31T23:59:59.999999Z")));
  for (const bad of [
    "yesterday", "2026-02-30T10:00:00Z", "0099-01-01T00:00:00Z", "1969-12-31T23:59:59Z", "2201-01-01T00:00:00Z",
    "2026-09-25T24:00:00Z", "2026-09-25T10:60:00Z", "2026-09-25T10:00:60Z", "2026-09-25T10:00:00+24:00",
    "2026-09-25T10:00:00+05:60", "2026-09-25T10:00:00",
  ]) {
    assert.equal(isoMicros(bad), null, bad);
  }
});

test("uriProblem refuses names Windows cannot hold, and caseGroups finds uris that differ only in case", () => {
  for (const bad of [
    "superpowers/notes/a:b.md", "superpowers/notes/a?.md", "superpowers/notes/a\u0001.md", "superpowers/notes/a.",
    "superpowers/notes/a\u007f.md", "superpowers/notes/a\u0085.md", "superpowers/notes/a ", "superpowers/notes/CON.md", "superpowers/con/a.md", "superpowers/notes/lpt9", "superpowers/Aux.tar.gz",
  ]) {
    assert.notEqual(uriProblem(bad), null, bad);
  }
  for (const good of ["superpowers/notes/a.md", "superpowers/notes/console.md", "superpowers/notes/com10.md", "superpowers/handoff/p1.md"]) {
    assert.equal(uriProblem(good), null, good);
  }
  assert.match(uriProblem("superpowers/notes/CON.md"), /"CON\.md" is a Windows device name/);
  assert.deepEqual(caseGroups(["superpowers/A.md", "superpowers/b.md", "superpowers/a.md", "superpowers/A.md"]), [["superpowers/A.md", "superpowers/a.md"]]);
  assert.deepEqual(caseGroups(["superpowers/a.md", "superpowers/b.md"]), []);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `plugins/dr-superpowers`): `timeout 300 node --test --test-reporter=spec tests/darkmem-sync/mirror.test.mjs`

Expected: FAIL: the file does not load — `SyntaxError: The requested module '../../scripts/lib/darkmem-mirror.mjs' does not provide an export named 'caseGroups'` — so the run reports `ℹ pass 0` and `ℹ fail 1`.

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/lib/darkmem-mirror.mjs`, replace:

```js
  return { version: 1, documents: Object.create(null), ledgers: Object.create(null), checkpoint: null, checkpointAt: null, conflicts: [] };
```

with:

```js
  return {
    version: 1, documents: Object.create(null), ledgers: Object.create(null), checkpoint: null, checkpointAt: null,
    conflicts: [], pendingLinks: [],
  };
```

In `plugins/dr-superpowers/scripts/lib/darkmem-mirror.mjs`, replace:

```js
  && (record.pending === undefined || typeof record.pending === "boolean");
```

with:

```js
  && (record.pending === undefined || typeof record.pending === "boolean")
  && (record.lastSeq === undefined || (Number.isSafeInteger(record.lastSeq) && record.lastSeq >= 0));
```

In `plugins/dr-superpowers/scripts/lib/darkmem-mirror.mjs`, replace:

```js
    && Array.isArray(raw.conflicts) && raw.conflicts.every(line => typeof line === "string");
  if (!valid) throw new StateError(`${file} does not hold a valid sync state; ${REBUILD}`);
  return { version: 1, documents, ledgers, checkpoint: raw.checkpoint, checkpointAt: raw.checkpointAt, conflicts: raw.conflicts };
```

with:

```js
    && Array.isArray(raw.conflicts) && raw.conflicts.every(line => typeof line === "string")
    && (raw.pendingLinks === undefined || (Array.isArray(raw.pendingLinks) && raw.pendingLinks.every(uri => typeof uri === "string")));
  if (!valid) throw new StateError(`${file} does not hold a valid sync state; ${REBUILD}`);
  return {
    version: 1, documents, ledgers, checkpoint: raw.checkpoint, checkpointAt: raw.checkpointAt, conflicts: raw.conflicts,
    pendingLinks: raw.pendingLinks ?? [],
  };
```

In `plugins/dr-superpowers/scripts/lib/darkmem-mirror.mjs`, replace:

```js
// Strict UTF-8, BOM kept, or null
```

with:

```js
// Where strict UTF-8 decoding of `buffer` first fails, or null when it does
// not: {offset, partial}, where partial means the only fault is a character
// cut short by the end of the buffer, which is what a file still being written
// looks like. The byte ranges are the WHATWG decoder's, so this agrees with
// decodeUtf8 on every input.
export function utf8Fault(buffer) {
  let i = 0;
  while (i < buffer.length) {
    const lead = buffer[i];
    if (lead < 0x80) {
      i += 1;
      continue;
    }
    let need = 0;
    if (lead >= 0xc2 && lead <= 0xdf) need = 1;
    else if (lead >= 0xe0 && lead <= 0xef) need = 2;
    else if (lead >= 0xf0 && lead <= 0xf4) need = 3;
    else return { offset: i, partial: false };
    const low = lead === 0xe0 ? 0xa0 : lead === 0xf0 ? 0x90 : 0x80;
    const high = lead === 0xed ? 0x9f : lead === 0xf4 ? 0x8f : 0xbf;
    for (let k = 1; k <= need; k += 1) {
      if (i + k >= buffer.length) return { offset: i, partial: true };
      const byte = buffer[i + k];
      if (byte < (k === 1 ? low : 0x80) || byte > (k === 1 ? high : 0xbf)) return { offset: i, partial: false };
    }
    i += need + 1;
  }
  return null;
}

// darkmem's ISO timestamps as microseconds since the epoch, or null. Python's
// isoformat writes six fraction digits and drops a zero fraction; Date.parse
// keeps three, so two entries filed in one millisecond would compare equal.
// Years 1970-2200 keep the result a safe integer.
export function isoMicros(text) {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-](\d{2}):(\d{2}))$/.exec(String(text));
  if (!m) return null;
  const [year, month, day, hour, minute, second] = m.slice(1, 7).map(Number);
  const [fraction = "", zone, zoneHours, zoneMinutes] = m.slice(7);
  if (year < 1970 || year > 2200 || (zone !== "Z" && (Number(zoneHours) > 23 || Number(zoneMinutes) > 59))) return null;
  const ms = Date.UTC(year, month - 1, day, hour, minute, second);
  // Date.UTC rolls an impossible field over (February 30 becomes March 2,
  // minute 60 the next hour); a round trip refuses it.
  const date = new Date(ms);
  if (date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day || date.getUTCHours() !== hour
    || date.getUTCMinutes() !== minute || date.getUTCSeconds() !== second) return null;
  const offsetMinutes = zone === "Z" ? 0 : (zone[0] === "-" ? -1 : 1) * (Number(zoneHours) * 60 + Number(zoneMinutes));
  return (ms - offsetMinutes * 60000) * 1000 + Number(fraction.padEnd(6, "0").slice(0, 6));
}

// Why a uri cannot be a file name on every platform the mirror runs on, or
// null. Windows refuses these characters, a trailing dot or space, and its
// device names whatever their extension; checking everywhere keeps a Linux
// mirror from filing what a Windows mirror cannot hold.
export function uriProblem(uri) {
  for (const segment of String(uri).split("/")) {
    if (/[<>:"|?*\p{Cc}]/u.test(segment)) return `the name ${JSON.stringify(segment)} holds a character Windows refuses`;
    if (/[. ]$/.test(segment)) return `the name ${JSON.stringify(segment)} ends in a dot or a space`;
    if (/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$/i.test(segment)) return `the name ${JSON.stringify(segment)} is a Windows device name`;
  }
  return null;
}

// Groups of two or more uris that differ only in case, which a
// case-insensitive file system holds as one file.
export function caseGroups(uris) {
  const byFold = new Map();
  for (const uri of new Set(uris)) {
    const fold = uri.toLowerCase();
    byFold.set(fold, [...(byFold.get(fold) ?? []), uri]);
  }
  return [...byFold.values()].filter(group => group.length > 1).map(group => group.sort());
}

// Strict UTF-8, BOM kept, or null
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `plugins/dr-superpowers`): `timeout 300 node --test --test-reporter=spec tests/darkmem-sync/mirror.test.mjs`

Expected (Linux): `ℹ pass 17`, `ℹ fail 0`.

- [ ] **Step 5: Run the whole darkmem-sync suite**

Run (from `plugins/dr-superpowers`): `timeout 300 bash tests/darkmem-sync.test.sh`

Expected (Linux): `ℹ pass 73`, `ℹ fail 0`; `ls "${TMPDIR:-/tmp}" | grep -c '^dms-'` prints `0` (no fixture directory left behind).

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/darkmem-mirror.mjs tests/darkmem-sync/mirror.test.mjs
git commit -m "feat(superpowers): add sync seq, links and checks" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The lock never deletes a lock it moved aside by mistake

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/darkmem-mirror.mjs` (`acquireLock`, and new `removeOldLeftovers` and `placeLock` above it)
- Test: `plugins/dr-superpowers/tests/darkmem-sync/mirror.test.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces: Contracts → **darkmem-mirror.mjs** `acquireLock(dir, {staleMs, beforeTakeover, beforeRestore})`.

**Items:** 7, 15

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 3 = 4

Spec §3, the lock, and register row 15. A lock is now built under a temporary name and renamed into place, so it is never an empty directory a rename could replace. The three-process race is driven through the existing `beforeTakeover` seam plus a new `beforeRestore` seam (Assumptions explains both).

- [ ] **Step 1: Write the failing tests**

Append to the end of `plugins/dr-superpowers/tests/darkmem-sync/mirror.test.mjs`:

```js
test("a takeover that moved a live lock aside and cannot give it back leaves it there, and a later acquire clears it once stale", () => {
  const { root } = mirror();
  const lock = path.join(root, ".sync.lock");
  fs.mkdirSync(lock);
  const dead = spawnSync(process.execPath, ["-e", ""]).pid;
  fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify({ pid: dead, host: os.hostname(), token: "stale" }));
  let first = null;
  let third = null;
  const second = acquireLock(root, {
    beforeTakeover: () => { first ??= acquireLock(root); },
    beforeRestore: () => { third ??= acquireLock(root); },
  });
  assert.equal(typeof first, "function", "the first takeover holds a lock");
  assert.equal(typeof third, "function", "a third process took the lock the second one moved aside");
  assert.equal(second, null);
  const asides = fs.readdirSync(root).filter(name => name.startsWith(".sync.lock.stale-"));
  assert.equal(asides.length, 1, "the first holder's lock was moved aside, not deleted");
  const aside = path.join(root, asides[0]);
  const firstToken = JSON.parse(fs.readFileSync(path.join(aside, "owner.json"), "utf8")).token;
  assert.notEqual(firstToken, lockOwner(root).token);
  first();
  assert.equal(fs.existsSync(lock), true, "the displaced first holder leaves the third's lock alone");
  third();
  assert.equal(fs.existsSync(lock), false);
  const release = acquireLock(root);
  assert.equal(fs.existsSync(aside), true, "a fresh aside is kept");
  release();
  const old = new Date(Date.now() - 60 * 60 * 1000);
  fs.utimesSync(aside, old, old);
  acquireLock(root)();
  assert.deepEqual(fs.readdirSync(root), [], "a stale aside is removed by the next acquire");
});

test("a half-built lock a crash left is kept while fresh and cleared once stale", () => {
  const { root } = mirror();
  const half = path.join(root, ".sync.lock.new-crashed");
  fs.mkdirSync(half);
  const release = acquireLock(root);
  assert.equal(lockOwner(root).pid, process.pid);
  assert.deepEqual(fs.readdirSync(root).sort(), [".sync.lock", ".sync.lock.new-crashed"], "a fresh half-built lock is kept");
  release();
  const old = new Date(Date.now() - 60 * 60 * 1000);
  fs.utimesSync(half, old, old);
  acquireLock(root)();
  assert.deepEqual(fs.readdirSync(root), []);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `plugins/dr-superpowers`): `timeout 300 node --test --test-reporter=spec tests/darkmem-sync/mirror.test.mjs`

Expected: FAIL: `ℹ pass 17`, `ℹ fail 2`; the failing tests are exactly:

  - a half-built lock a crash left is kept while fresh and cleared once stale
  - a takeover that moved a live lock aside and cannot give it back leaves it there, and a later acquire clears it once stale

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/lib/darkmem-mirror.mjs`, replace:

```js
// One sync per mirror at a time. Returns a release function, or null when a
// live sync holds the lock. Taking over an abandoned lock moves it aside and
// deletes it only if it is still the lock judged abandoned, so two processes
// taking over at once cannot delete each other's fresh lock. The release
// removes the lock only while it still carries this holder's token.
// beforeTakeover is a test seam: it runs between judging a lock abandoned and
// moving it aside.
export function acquireLock(dir, { staleMs = 10 * 60 * 1000, beforeTakeover } = {}) {
  const lock = path.join(dir, ".sync.lock");
  const owner = { pid: process.pid, host: os.hostname(), token: crypto.randomUUID() };
  fs.mkdirSync(dir, { recursive: true });
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      fs.mkdirSync(lock);
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      const seen = lockSnapshot(lock);
      if (!lockAbandoned(seen, staleMs)) return null;
      const identity = lockIdentity(seen);
      beforeTakeover?.();
      const aside = `${lock}.stale-${owner.token}`;
      try {
        fs.renameSync(lock, aside);
      } catch {
        continue;
      }
      if (lockIdentity(lockSnapshot(aside)) !== identity) {
        // Another process took the lock over first; give its lock back.
        try {
          fs.renameSync(aside, lock);
        } catch {
          fs.rmSync(aside, { recursive: true, force: true });
        }
        return null;
      }
      fs.rmSync(aside, { recursive: true, force: true });
      continue;
    }
    fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify(owner));
    return () => {
      if (readOwner(lock)?.token === owner.token) fs.rmSync(lock, { recursive: true, force: true });
    };
  }
  return null;
}
```

with:

```js
// A lock moved aside and left there, because it could not be given back, or
// one a crash left half built, is removed by a later acquire once it is older
// than staleMs.
function removeOldLeftovers(dir, staleMs) {
  for (const entry of sortedEntries(dir)) {
    if (!entry.isDirectory() || !/^\.sync\.lock\.(stale|new)-/.test(entry.name)) continue;
    const aside = path.join(dir, entry.name);
    try {
      if (Date.now() - fs.statSync(aside).mtimeMs >= staleMs) fs.rmSync(aside, { recursive: true, force: true });
    } catch {
      // Another acquire removed it first.
    }
  }
}

// A lock appears with its owner record already inside: it is built under a
// temporary name and renamed into place. A rename replaces an empty directory
// on POSIX, so a lock that were ever empty could be replaced by a restore;
// one that never is cannot. False when another lock got there first.
function placeLock(dir, lock, owner) {
  if (process.platform === "win32") {
    // A Windows rename never replaces a directory, so an empty lock is safe
    // there, and mkdir avoids renaming a just-written directory, which
    // antivirus and indexer handles make fail intermittently.
    try {
      fs.mkdirSync(lock);
    } catch (error) {
      if (error.code === "EEXIST") return false;
      throw error;
    }
    fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify(owner));
    return true;
  }
  const building = path.join(dir, `.sync.lock.new-${owner.token}`);
  fs.mkdirSync(building);
  fs.writeFileSync(path.join(building, "owner.json"), JSON.stringify(owner));
  try {
    fs.renameSync(building, lock);
    return true;
  } catch (error) {
    fs.rmSync(building, { recursive: true, force: true });
    if (fs.existsSync(lock)) return false;
    throw error;
  }
}

// One sync per mirror at a time. Returns a release function, or null when a
// live sync holds the lock. Taking over an abandoned lock moves it aside and
// deletes it only if it is still the lock judged abandoned, so two processes
// taking over at once cannot delete each other's fresh lock; a lock moved
// aside by mistake is given back, or left aside when a third process has
// taken the lock meanwhile, and never deleted. The release removes the lock
// only while it still carries this holder's token. beforeTakeover and
// beforeRestore are test seams: the first runs between judging a lock
// abandoned and moving it aside, the second before giving back a lock that was
// moved aside by mistake.
export function acquireLock(dir, { staleMs = 10 * 60 * 1000, beforeTakeover, beforeRestore } = {}) {
  const lock = path.join(dir, ".sync.lock");
  const owner = { pid: process.pid, host: os.hostname(), token: crypto.randomUUID() };
  fs.mkdirSync(dir, { recursive: true });
  removeOldLeftovers(dir, staleMs);
  for (let attempt = 0; attempt < 3; attempt += 1) {
    // An existing lock, even an empty one an older version left, is judged
    // before placing a new one, so the rename never lands on it.
    if (fs.existsSync(lock) || !placeLock(dir, lock, owner)) {
      const seen = lockSnapshot(lock);
      if (!lockAbandoned(seen, staleMs)) return null;
      const identity = lockIdentity(seen);
      beforeTakeover?.();
      const aside = `${lock}.stale-${owner.token}`;
      try {
        fs.renameSync(lock, aside);
      } catch {
        continue;
      }
      if (lockIdentity(lockSnapshot(aside)) !== identity) {
        // Another process took the lock over first; give its lock back. When a
        // third has taken the lock since, the moved lock stays aside: it may
        // be a live holder's, and it is not this process's to delete.
        beforeRestore?.();
        try {
          fs.renameSync(aside, lock);
        } catch {
          // Left aside; removeOldLeftovers clears it once it is stale.
        }
        return null;
      }
      fs.rmSync(aside, { recursive: true, force: true });
      continue;
    }
    // Moved aside before it is deleted: a recursive delete in place would
    // leave an empty lock for a moment, which a restore could land on.
    return () => {
      if (readOwner(lock)?.token !== owner.token) return;
      const gone = `${lock}.stale-${owner.token}`;
      try {
        fs.renameSync(lock, gone);
      } catch {
        return;
      }
      if (readOwner(gone)?.token === owner.token) {
        fs.rmSync(gone, { recursive: true, force: true });
        return;
      }
      try {
        fs.renameSync(gone, lock);
      } catch {
        // Left aside; removeOldLeftovers clears it once it is stale.
      }
    };
  }
  return null;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `plugins/dr-superpowers`): `timeout 300 node --test --test-reporter=spec tests/darkmem-sync/mirror.test.mjs`

Expected (Linux): `ℹ pass 19`, `ℹ fail 0`.

- [ ] **Step 5: Run the whole darkmem-sync suite**

Run (from `plugins/dr-superpowers`): `timeout 300 bash tests/darkmem-sync.test.sh`

Expected (Linux): `ℹ pass 75`, `ℹ fail 0`; `ls "${TMPDIR:-/tmp}" | grep -c '^dms-'` prints `0` (no fixture directory left behind).

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/darkmem-mirror.mjs tests/darkmem-sync/mirror.test.mjs
git commit -m "fix(superpowers): never delete a lock moved aside" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The append precondition in the stub and the client

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/darkmem-client.mjs` (`failItem` after `CLIENT`; `append`)
- Modify: `plugins/dr-superpowers/tests/darkmem-sync/stub-server.mjs` (header comment; `GET /api/v1/documents/by-uri`'s 404 text; `POST /api/v1/worklog/entries`)
- Test: `plugins/dr-superpowers/tests/darkmem-sync/client.test.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces: Contracts → **darkmem-client.mjs** (`failItem`, `append`'s `expectedLastSeq`), Contracts → **Stub append** and Contracts → **Stub by-uri 404**.

**Items:** 7

**Implementer:** dr-superpowers:impl-opus-low
**Executor:** codex gpt-6-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

Spec §4's stub requirement and §2's per-item rule. The stub's 409 detail is darkmem's own message (`backend/app/services/worklog.py:94-96`).

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/darkmem-sync/client.test.mjs`, replace:

```js
import { HttpError, TransportError, createClient } from "../../scripts/lib/darkmem-client.mjs";
```

with:

```js
import { HttpError, TransportError, createClient, failItem } from "../../scripts/lib/darkmem-client.mjs";
```

Append to the end of `plugins/dr-superpowers/tests/darkmem-sync/client.test.mjs`:

```js
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
```

In `plugins/dr-superpowers/tests/darkmem-sync/stub-server.mjs`, replace:

```js
// content; a stale or absent expected_hash is a 409; an append needs a run key,
// holds 1-100 entries of 1-65,536 characters, and reopens a closed workstream;
// every list is keyset-paged.
```

with:

```js
// content; a stale or absent expected_hash is a 409; an append needs a run key,
// holds 1-100 entries of 1-65,536 characters, reopens a closed workstream, and
// with expected_last_seq writes nothing unless it names the seq of the
// workstream's newest entry of the call's one kind (0 for none), answering 409
// otherwise; a by-uri read of a uri nothing is filed at answers darkmem's own
// 404 text; every list is keyset-paged.
```

In `plugins/dr-superpowers/tests/darkmem-sync/stub-server.mjs`, replace:

```js
      const now = tick();
      let ws = db.workstreams.find(w => w.project === body.project && w.key === body.workstream);
```

with:

```js
      let ws = db.workstreams.find(w => w.project === body.project && w.key === body.workstream);
      if (body.expected_last_seq !== undefined && body.expected_last_seq !== null) {
        const expected = body.expected_last_seq;
        if (!Number.isSafeInteger(expected) || expected < 0) return send(422, { detail: "expected_last_seq must be an integer of at least 0" });
        const kinds = new Set(body.entries.map(e => e.kind));
        if (kinds.size !== 1) return send(422, { detail: "expected_last_seq needs every entry of the append to share one kind" });
        const [kind] = kinds;
        const current = Math.max(0, ...(ws?.entries ?? []).filter(e => e.kind === kind).map(e => e.seq));
        if (current !== expected) return send(409, { detail: `expected the newest ${kind} entry to be seq ${expected}, but it is ${current}` });
      }
      const now = tick();
```

In `plugins/dr-superpowers/tests/darkmem-sync/stub-server.mjs`, replace:

```js
      if (!doc) return send(404, { detail: "Document not found" });
```

with:

```js
      if (!doc) return send(404, { detail: `no document is filed at uri '${q.get("uri")}' in project '${q.get("project")}'` });
```

In `plugins/dr-superpowers/tests/darkmem-sync/stub-server.mjs`, replace:

```js
      const ids = body.entries.map(e => {
        const entry = { id: crypto.randomUUID(), seq: db.nextSeq++, run_key: body.run_key, kind: e.kind, body: e.body, properties: e.properties ?? {}, created_at: now };
        ws.entries.push(entry);
        return entry.id;
      });
      Object.assign(ws, { last_entry_at: now, updated_at: now });
      return send(201, { workstream: wsOut(ws), entry_ids: ids });
```

with:

```js
      const written = body.entries.map(e => {
        const entry = { id: crypto.randomUUID(), seq: db.nextSeq++, run_key: body.run_key, kind: e.kind, body: e.body, properties: e.properties ?? {}, created_at: now };
        ws.entries.push(entry);
        return entry;
      });
      Object.assign(ws, { last_entry_at: now, updated_at: now });
      return send(201, { workstream: wsOut(ws), entry_ids: written.map(e => e.id), last_seq: written.at(-1).seq });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `plugins/dr-superpowers`): `timeout 300 node --test --test-reporter=spec tests/darkmem-sync/client.test.mjs`

Expected: FAIL: the file does not load — `SyntaxError: The requested module '../../scripts/lib/darkmem-client.mjs' does not provide an export named 'failItem'` — so the run reports `ℹ pass 0` and `ℹ fail 1`.

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/lib/darkmem-client.mjs`, replace:

```js
const CLIENT = "dr-superpowers";
```

with:

```js
const CLIENT = "dr-superpowers";

// Records a darkmem answer that concerns one item as that item's failure line,
// so the command goes on with the next item; anything else (no answer at all,
// or a 401, which every later call would get too) is rethrown to stop it.
export function failItem(report, label, error, suffix = "") {
  if (!(error instanceof HttpError) || error.status === 401) throw error;
  report.failures.push(`${label}: darkmem answered ${error.status}: ${error.detail}${suffix}`);
}
```

In `plugins/dr-superpowers/scripts/lib/darkmem-client.mjs`, replace:

```js
    append({ project, workstream, entries, properties }) {
      const body = { project, workstream, run_key: runKey, client: CLIENT, entries };
      if (properties) body.properties = properties;
```

with:

```js
    append({ project, workstream, entries, properties, expectedLastSeq }) {
      const body = { project, workstream, run_key: runKey, client: CLIENT, entries };
      if (properties) body.properties = properties;
      if (expectedLastSeq !== undefined) body.expected_last_seq = expectedLastSeq;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `plugins/dr-superpowers`): `timeout 300 node --test --test-reporter=spec tests/darkmem-sync/client.test.mjs`

Expected (Linux): `ℹ pass 8`, `ℹ fail 0`.

- [ ] **Step 5: Run the whole darkmem-sync suite**

Run (from `plugins/dr-superpowers`): `timeout 300 bash tests/darkmem-sync.test.sh`

Expected (Linux): `ℹ pass 77`, `ℹ fail 0`; `ls "${TMPDIR:-/tmp}" | grep -c '^dms-'` prints `0` (no fixture directory left behind).

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/darkmem-client.mjs tests/darkmem-sync/client.test.mjs tests/darkmem-sync/stub-server.mjs
git commit -m "feat(superpowers): add the append precondition" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Ledger pushes guarded by the last seq

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/darkmem-pull.mjs` (`ledgerText` becomes `remoteLedger`; `pullLedgers` records `lastSeq`)
- Modify: `plugins/dr-superpowers/scripts/lib/darkmem-push.mjs` (imports; `adoptRemoteLedger`, new `pushLedger`, `pushLedgers`)
- Test: `plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs`, `plugins/dr-superpowers/tests/darkmem-sync/push.test.mjs`

**Interfaces:**
- Consumes: Task 1's `utf8Fault` and ledger record; Task 3's `failItem`, `append({expectedLastSeq})` and the stub's precondition.
- Produces: Contracts → **darkmem-pull.mjs** `remoteLedger`, and the ledger lines in Contracts → **Output lines**.

**Items:** 7

**Implementer:** dr-superpowers:impl-opus-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 3 = 6

Spec §2, ledger precondition and invalid UTF-8, plus pull recording `lastSeq` (§2). The re-read of darkmem's whole ledger before every append (`darkmem-push.mjs:136-150` at the base commit) is removed: another mirror's append now answers 409. Two existing assertions change here, as Assumptions records.

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs`, replace:

```js
  assert.deepEqual(s.state().ledgers.p1, { offset: fs.statSync(file).size, prefix: sha(read(file)) });
```

with:

```js
  const newest = s.stub.db.workstreams.find(w => w.key === "p1").entries.filter(e => e.kind === "ledger").at(-1);
  assert.deepEqual(s.state().ledgers.p1, { offset: fs.statSync(file).size, prefix: sha(read(file)), lastSeq: newest.seq });
```

Append to the end of `plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs`:

```js
test("a pulled ledger records its newest seq, so the next push appends without re-reading it", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  assert.equal((await s.pull()).code, 0);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  fs.appendFileSync(file, "two\n");
  const reads = () => s.stub.db.requests.filter(r => r.method === "GET" && r.path.endsWith("/entries")).length;
  const before = reads();
  const pushed = await run(["push"], { cwd: s.repo, env: s.env });
  assert.equal(pushed.code, 0, pushed.stdout + pushed.stderr);
  assert.equal(reads(), before, "push trusts the pulled seq instead of reading the ledger again");
  const [append] = s.stub.db.requests.filter(r => r.method === "POST" && r.path === "/api/v1/worklog/entries" && r.body.run_key !== "seed");
  assert.equal(append.body.expected_last_seq, s.stub.db.workstreams[0].entries[0].seq);
  assert.deepEqual(s.stub.db.workstreams[0].entries.map(e => e.body), ["one\n", "two\n"]);
});
```

In `plugins/dr-superpowers/tests/darkmem-sync/push.test.mjs`, replace:

```js
  const lost = await s.push();
  assert.equal(lost.code, 3);
  assert.equal(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).ledgers.p1.pending, true);
```

with:

```js
  const lost = await s.push();
  assert.equal(lost.code, 1);
  assert.match(lost.stdout, /^failed: sdd\/p1\/progress\.md: darkmem answered 502: injected failure$/m);
  assert.equal(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).ledgers.p1.pending, true);
```

Append to the end of `plugins/dr-superpowers/tests/darkmem-sync/push.test.mjs`:

```js
test("every ledger append names the seq it follows; another mirror's append is a 409 reconciled once", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "one\n");
  assert.equal((await s.push()).code, 0);
  const [first] = s.posts("/api/v1/worklog/entries");
  assert.equal(first.body.expected_last_seq, 0, "a new ledger expects an empty one");
  const oneSeq = (await s.ledger("p1"))[0].seq;
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "two\n" }] });
  fs.appendFileSync(file, "two\nthree\n");
  const result = await s.push();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n", "two\n", "three\n"]);
  const appends = s.posts("/api/v1/worklog/entries").filter(r => r.body.run_key !== "seed");
  assert.equal(appends[1].body.expected_last_seq, oneSeq, "the stale expectation, answered 409");
  assert.deepEqual(appends[2].body.entries, [{ kind: "ledger", body: "three\n" }], "only the bytes darkmem lacked");
  const state = JSON.parse(read(path.join(s.mirror, ".sync-state.json")));
  assert.equal(state.ledgers.p1.lastSeq, (await s.ledger("p1")).at(-1).seq);
});

test("a second 409 in one push is a conflict and nothing more is sent", async t => {
  const racing = [];
  const s = await setup(t, {
    onRequest: (request, db) => {
      if (racing.length && request.method === "POST" && request.path === "/api/v1/worklog/entries") {
        const ws = db.workstreams.find(w => w.key === "p1");
        ws.entries.push({ id: `race-${db.nextSeq}`, seq: db.nextSeq++, run_key: "other", kind: "ledger", body: racing.shift(), properties: {}, created_at: ws.last_entry_at });
      }
    },
  });
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "one\n");
  await s.push();
  fs.appendFileSync(file, "two\nthree\n");
  racing.push("two\n", "three\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^conflict: sdd\/p1\/progress\.md: darkmem's ledger for p1 changed since the last sync/m);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n", "two\n", "three\n"], "the other client's lines, none sent twice");
  assert.equal(s.posts("/api/v1/worklog/entries").length, 3, "the first push, the 409, and the retry's 409");
});

test("a ledger with a byte that is not UTF-8 fails with its offset; a character still being written is a note", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "one\n");
  await s.push();
  fs.appendFileSync(file, Buffer.from([0x61, 0xff, 0x62, 0x0a]));
  const middle = await s.push();
  assert.equal(middle.code, 1);
  assert.match(middle.stdout, /^failed: sdd\/p1\/progress\.md: byte 5 is not UTF-8 text; not pushed$/m);
  write(file, "one\n");
  fs.appendFileSync(file, Buffer.from([0xff]));
  const lone = await s.push();
  assert.equal(lone.code, 1);
  assert.match(lone.stdout, /^failed: sdd\/p1\/progress\.md: byte 4 is not UTF-8 text; not pushed$/m);
  write(file, "one\n");
  fs.appendFileSync(file, Buffer.from([0xe2, 0x82]));
  const partial = await s.push();
  assert.equal(partial.code, 0, partial.stdout);
  assert.match(partial.stdout, /^note: sdd\/p1\/progress\.md: the appended bytes end inside a character; push again once the write finishes$/m);
  fs.appendFileSync(file, Buffer.from([0xac, 0x0a]));
  assert.equal((await s.push()).code, 0);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n", "€\n"]);
});

test("a ledger longer than one append call chains each call's last_seq into the next", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "big", "progress.md");
  const line = `${"x".repeat(65535)}\n`;
  write(file, line.repeat(101));
  const result = await s.push();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /101 ledger entries/);
  const appends = s.posts("/api/v1/worklog/entries");
  assert.deepEqual(appends.map(r => r.body.entries.length), [100, 1]);
  const entries = await s.ledger("big");
  assert.equal(appends[0].body.expected_last_seq, 0);
  assert.equal(appends[1].body.expected_last_seq, entries[99].seq, "the second call expects the first call's last seq");
  assert.equal(entries.map(e => e.body).join(""), read(file));
  assert.equal(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).ledgers.big.lastSeq, entries[100].seq);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `plugins/dr-superpowers`): `timeout 300 node --test --test-reporter=spec tests/darkmem-sync/pull.test.mjs tests/darkmem-sync/push.test.mjs`

Expected: FAIL: `ℹ pass 27`, `ℹ fail 7`; the failing tests are exactly:

  - a ledger append whose answer was lost is reconciled, never sent twice
  - a ledger longer than one append call chains each call's last_seq into the next
  - a ledger with a byte that is not UTF-8 fails with its offset; a character still being written is a note
  - a pulled ledger records its newest seq, so the next push appends without re-reading it
  - a second 409 in one push is a conflict and nothing more is sent
  - every ledger append names the seq it follows; another mirror's append is a 409 reconciled once
  - open workstreams render their ledgers; closed ones do not

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/lib/darkmem-pull.mjs`, replace:

```js
// A workstream's ledger as a file: its ledger entries' bodies, in order.
export async function ledgerText(client, workstreamId) {
  return (await client.entries(workstreamId, "ledger")).map(entry => entry.body).join("");
}
```

with:

```js
// A workstream's ledger as a file: its ledger entries' bodies, in order, and
// the seq of the newest one (0 when it holds none), which the next append
// names as its expected_last_seq.
export async function remoteLedger(client, workstreamId) {
  const entries = await client.entries(workstreamId, "ledger");
  return { text: entries.map(entry => entry.body).join(""), lastSeq: entries.at(-1)?.seq ?? 0 };
}
```

In `plugins/dr-superpowers/scripts/lib/darkmem-pull.mjs`, replace:

```js
    const text = await ledgerText(client, ws.id);
    if (!text) continue;
    const remote = Buffer.from(text, "utf8");
    const synced = { offset: remote.length, prefix: sha256(remote) };
```

with:

```js
    const { text, lastSeq } = await remoteLedger(client, ws.id);
    if (!text) continue;
    const remote = Buffer.from(text, "utf8");
    const synced = { offset: remote.length, prefix: sha256(remote), lastSeq };
```

In `plugins/dr-superpowers/scripts/lib/darkmem-push.mjs`, replace:

```js
import { HttpError } from "./darkmem-client.mjs";
import {
  DOC_PREFIX, EMPTY_SHA, MAX_ENTRIES_PER_APPEND, MAX_ENTRY_CHARS, UsageError, checkpointTarget, decodeUtf8,
  ledgerFiles, ledgerPlanPath, listDocumentFiles, propertiesFor, sha256, splitAtLimit, unsupportedPlanDirs, validKey,
} from "./darkmem-mirror.mjs";
import { ledgerText } from "./darkmem-pull.mjs";
```

with:

```js
import { HttpError, failItem } from "./darkmem-client.mjs";
import {
  DOC_PREFIX, EMPTY_SHA, MAX_ENTRIES_PER_APPEND, MAX_ENTRY_CHARS, UsageError, checkpointTarget, decodeUtf8,
  ledgerFiles, ledgerPlanPath, listDocumentFiles, propertiesFor, sha256, splitAtLimit, unsupportedPlanDirs, utf8Fault,
  validKey,
} from "./darkmem-mirror.mjs";
import { remoteLedger } from "./darkmem-pull.mjs";
```

In `plugins/dr-superpowers/scripts/lib/darkmem-push.mjs`, replace:

```js
// What darkmem already holds of a ledger, adopted when it is a prefix of the
// file: used for a ledger this mirror never synced (a lost state file) and for
// one whose last append may have landed without an answer.
async function adoptRemoteLedger({ cfg, client }, slug, buffer) {
  const existing = await client.resume(cfg.project, slug);
  if (!existing) return { offset: 0, prefix: EMPTY_SHA };
  const remote = Buffer.from(await ledgerText(client, existing.workstream.id), "utf8");
  if (buffer.length >= remote.length && buffer.subarray(0, remote.length).equals(remote)) {
    return { offset: remote.length, prefix: sha256(remote) };
  }
  return null;
}

async function pushLedgers(context) {
  const { cfg, client, roots, state, persist, report } = context;
  for (const dir of unsupportedPlanDirs(roots.workRoot)) {
    report.failures.push(`${dir}: not a usable workstream key; rename the directory to letters, digits, '.', '_' or '-'`);
  }
  for (const { slug, file } of ledgerFiles(roots.workRoot)) {
    const buffer = fs.readFileSync(file);
    let record = state.ledgers[slug];
    let adopted = false;
    if (!record || record.pending) {
      adopted = true;
      record = await adoptRemoteLedger(context, slug, buffer);
      if (!record) {
        report.conflicts.push(`sdd/${slug}/progress.md: darkmem's ledger for ${slug} is not a prefix of this file; move the local file aside, pull, and re-apply your lines`);
        continue;
      }
      state.ledgers[slug] = record;
      persist();
    }
    if (buffer.length < record.offset || sha256(buffer.subarray(0, record.offset)) !== record.prefix) {
      report.conflicts.push(`sdd/${slug}/progress.md: rewritten rather than appended to; refusing to push it`);
      continue;
    }
    if (buffer.length === record.offset) continue;
    // Another mirror may have appended since the last sync: send only what
    // darkmem does not already hold, and never lines that would interleave.
    if (!adopted) {
      const current = await adoptRemoteLedger(context, slug, buffer);
      if (!current || current.offset < record.offset) {
        report.conflicts.push(`sdd/${slug}/progress.md: darkmem's ledger for ${slug} changed since the last sync and no longer matches this file; move the local file aside, pull, and re-apply your lines`);
        continue;
      }
      if (current.offset !== record.offset) {
        record = current;
        state.ledgers[slug] = record;
        persist();
        if (buffer.length === record.offset) continue;
      }
    }
    const appended = decodeUtf8(buffer.subarray(record.offset));
    if (appended === null) {
      report.notes.push(`sdd/${slug}/progress.md: the appended bytes end inside a character; push again once the write finishes`);
      continue;
    }
    const properties = propertiesFor(roots, slug, ledgerPlanPath(buffer.toString("utf8")));
    const pieces = splitAtLimit(appended);
    for (let i = 0; i < pieces.length; i += MAX_ENTRIES_PER_APPEND) {
      const group = pieces.slice(i, i + MAX_ENTRIES_PER_APPEND);
      // Marked before the call: if the answer is lost, or this process dies
      // before the offset is saved, the next push reconciles instead of
      // re-sending.
      state.ledgers[slug] = { ...record, pending: true };
      persist();
      try {
        await client.append({ project: cfg.project, workstream: slug, properties, entries: group.map(body => ({ kind: "ledger", body })) });
      } catch (error) {
        if (!(error instanceof HttpError && error.status === 422)) throw error;
        state.ledgers[slug] = record;
        persist();
        report.failures.push(`sdd/${slug}/progress.md: darkmem refused an entry: ${error.detail}`);
        break;
      }
      const offset = record.offset + Buffer.byteLength(group.join(""), "utf8");
      record = { offset, prefix: sha256(buffer.subarray(0, offset)) };
      state.ledgers[slug] = record;
      persist();
      report.counts["ledger entries"] += group.length;
    }
  }
}
```

with:

```js
// What darkmem already holds of a ledger, adopted when it is a prefix of the
// file: used for a ledger this mirror never synced (a lost state file), for
// one whose last append may have landed without an answer, for a record from
// before lastSeq was kept, and after an append's precondition failed.
async function adoptRemoteLedger({ cfg, client }, slug, buffer) {
  const existing = await client.resume(cfg.project, slug);
  if (!existing) return { offset: 0, prefix: EMPTY_SHA, lastSeq: 0 };
  const { text, lastSeq } = await remoteLedger(client, existing.workstream.id);
  const remote = Buffer.from(text, "utf8");
  if (buffer.length >= remote.length && buffer.subarray(0, remote.length).equals(remote)) {
    return { offset: remote.length, prefix: sha256(remote), lastSeq };
  }
  return null;
}

// One ledger's appended bytes. Every append names the seq it expects to
// follow, so another mirror's append since the last sync is a 409 rather than
// interleaved lines; the 409 is reconciled once, and the bytes darkmem does
// not yet hold are sent.
async function pushLedger(context, slug, file) {
  const { cfg, client, roots, state, persist, report } = context;
  const label = `sdd/${slug}/progress.md`;
  const buffer = fs.readFileSync(file);
  let record = state.ledgers[slug];
  if (!record || record.pending || record.lastSeq === undefined) {
    record = await adoptRemoteLedger(context, slug, buffer);
    if (!record) {
      report.conflicts.push(`${label}: darkmem's ledger for ${slug} is not a prefix of this file; move the local file aside, pull, and re-apply your lines`);
      return;
    }
    state.ledgers[slug] = record;
    persist();
  }
  if (buffer.length < record.offset || sha256(buffer.subarray(0, record.offset)) !== record.prefix) {
    report.conflicts.push(`${label}: rewritten rather than appended to; refusing to push it`);
    return;
  }
  let reconciled = false;
  sending: while (buffer.length > record.offset) {
    const rest = buffer.subarray(record.offset);
    const appended = decodeUtf8(rest);
    if (appended === null) {
      const fault = utf8Fault(rest);
      if (fault.partial) report.notes.push(`${label}: the appended bytes end inside a character; push again once the write finishes`);
      else report.failures.push(`${label}: byte ${record.offset + fault.offset} is not UTF-8 text; not pushed`);
      return;
    }
    const properties = propertiesFor(roots, slug, ledgerPlanPath(buffer.toString("utf8")));
    const pieces = splitAtLimit(appended);
    for (let i = 0; i < pieces.length; i += MAX_ENTRIES_PER_APPEND) {
      const group = pieces.slice(i, i + MAX_ENTRIES_PER_APPEND);
      // Marked before the call: if the answer is lost, or this process dies
      // before the offset is saved, the next push reconciles instead of
      // re-sending.
      state.ledgers[slug] = { ...record, pending: true };
      persist();
      let answer;
      try {
        answer = await client.append({
          project: cfg.project, workstream: slug, properties, expectedLastSeq: record.lastSeq,
          entries: group.map(body => ({ kind: "ledger", body })),
        });
      } catch (error) {
        if (!(error instanceof HttpError && (error.status === 409 || error.status === 422))) throw error;
        // Both answers wrote nothing, so the record stands as it was.
        state.ledgers[slug] = record;
        persist();
        if (error.status === 422) {
          report.failures.push(`${label}: darkmem refused an entry: ${error.detail}`);
          return;
        }
        const current = reconciled ? null : await adoptRemoteLedger(context, slug, buffer);
        if (!current || current.offset < record.offset) {
          report.conflicts.push(`${label}: darkmem's ledger for ${slug} changed since the last sync and no longer matches this file; move the local file aside, pull, and re-apply your lines`);
          return;
        }
        reconciled = true;
        record = current;
        state.ledgers[slug] = record;
        persist();
        continue sending;
      }
      const offset = record.offset + Buffer.byteLength(group.join(""), "utf8");
      record = { offset, prefix: sha256(buffer.subarray(0, offset)), lastSeq: answer.last_seq };
      state.ledgers[slug] = record;
      persist();
      report.counts["ledger entries"] += group.length;
    }
  }
}

async function pushLedgers(context) {
  const { roots, report } = context;
  for (const dir of unsupportedPlanDirs(roots.workRoot)) {
    report.failures.push(`${dir}: not a usable workstream key; rename the directory to letters, digits, '.', '_' or '-'`);
  }
  for (const { slug, file } of ledgerFiles(roots.workRoot)) {
    try {
      await pushLedger(context, slug, file);
    } catch (error) {
      // A pending mark set before a failed append stays: its answer may have
      // been lost, so the next push reconciles before sending.
      failItem(report, `sdd/${slug}/progress.md`, error);
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `plugins/dr-superpowers`): `timeout 300 node --test --test-reporter=spec tests/darkmem-sync/pull.test.mjs tests/darkmem-sync/push.test.mjs`

Expected (Linux): `ℹ pass 34`, `ℹ fail 0`.

- [ ] **Step 5: Run the whole darkmem-sync suite**

Run (from `plugins/dr-superpowers`): `timeout 300 bash tests/darkmem-sync.test.sh`

Expected (Linux): `ℹ pass 82`, `ℹ fail 0`; `ls "${TMPDIR:-/tmp}" | grep -c '^dms-'` prints `0` (no fixture directory left behind).

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/darkmem-pull.mjs scripts/lib/darkmem-push.mjs tests/darkmem-sync/pull.test.mjs tests/darkmem-sync/push.test.mjs
git commit -m "feat(superpowers): guard ledger pushes by seq" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Push goes on past a failed document, link or checkpoint

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/darkmem-push.mjs` (imports; `linkHandoff`, new `pushDocument`, `pushDocuments`; `pushCheckpoint` split into `pushCheckpoint` and `sendCheckpoint`; `push`)
- Test: `plugins/dr-superpowers/tests/darkmem-sync/push.test.mjs`

**Interfaces:**
- Consumes: Task 1's `isoMicros`, `uriProblem`, `caseGroups` and `pendingLinks`; Task 3's `failItem` and Contracts → **Stub by-uri 404**; Task 4's `push.mjs` imports as Task 4 leaves them.
- Produces: the push lines in Contracts → **Output lines**.

**Items:** 7

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

Spec §2 (per-item errors, handoff links, timestamps) and §3 (portable uris, push side). The push-side case check compares each outgoing uri with every spelling darkmem holds, and a 409's follow-up read treats only darkmem's own not-filed 404 as a deletion. Two existing assertions change here (exit 3 becomes exit 1 for an injected 502), as Assumptions records.

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/darkmem-sync/push.test.mjs`, replace:

```js
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/documents", status: 502, commit: true });
  assert.equal((await s.push()).code, 3);
  const retry = await s.push();
```

with:

```js
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/documents", status: 502, commit: true });
  const lost = await s.push();
  assert.equal(lost.code, 1);
  assert.match(lost.stdout, /^failed: superpowers\/a\.md: darkmem answered 502: injected failure$/m);
  const retry = await s.push();
```

In `plugins/dr-superpowers/tests/darkmem-sync/push.test.mjs`, replace:

```js
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/worklog/entries", status: 502, commit: true });
  assert.equal((await s.push()).code, 3);
  await s.seed.append({ project: "proj", workstream: "d-design", entries: [{ kind: "checkpoint", body: "# Handoff from another machine\n" }] });
```

with:

```js
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/worklog/entries", status: 502, commit: true });
  const lost = await s.push();
  assert.equal(lost.code, 1);
  assert.match(lost.stdout, /^failed: handoff\/latest\.md: darkmem answered 502: injected failure$/m);
  await s.seed.append({ project: "proj", workstream: "d-design", entries: [{ kind: "checkpoint", body: "# Handoff from another machine\n" }] });
```

Append to the end of `plugins/dr-superpowers/tests/darkmem-sync/push.test.mjs`:

```js
test("a 503 on one document names its uri, and the other documents, the ledger and the checkpoint still land", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  write(path.join(s.docsRoot, "b.md"), "b\n");
  write(path.join(s.workRoot, "sdd", "p1", "progress.md"), "one\n");
  write(path.join(s.workRoot, "handoff", "latest.md"), "# Handoff\n\n## State\n- Plan: `docs/superpowers/plans/p1.md`\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/documents", status: 503 });
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^failed: superpowers\/a\.md: darkmem answered 503: injected failure$/m);
  assert.equal(s.stub.db.documents.has("proj\u0000superpowers/a.md"), false);
  assert.equal(s.stub.db.documents.get("proj\u0000superpowers/b.md").content, "b\n");
  assert.deepEqual(s.stub.db.workstreams.find(w => w.key === "p1").entries.map(e => e.kind), ["ledger", "checkpoint"]);
  assert.equal((await s.push()).code, 0);
  assert.equal(s.stub.db.documents.get("proj\u0000superpowers/a.md").content, "a\n");
});

test("a 401 on a document stops the push before the ledgers", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  write(path.join(s.workRoot, "sdd", "p1", "progress.md"), "one\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/documents", status: 401, detail: "Not authenticated" });
  const result = await s.push();
  assert.equal(result.code, 3);
  assert.match(result.stderr, /^darkmem-sync: push failed: POST \/api\/v1\/documents answered 401: Not authenticated$/m);
  assert.equal(s.stub.db.workstreams.length, 0);
});

test("a failed document manifest fails the documents phase and the ledgers still push", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  write(path.join(s.workRoot, "sdd", "p1", "progress.md"), "one\n");
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/documents/manifest", status: 503 });
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^failed: document manifest: darkmem answered 503: injected failure; no document pushed$/m);
  assert.equal(s.posts("/api/v1/documents").length, 0);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n"]);
});

test("a failed handoff link stays pending and the next push links it; a pending link with no workstream is dropped", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  write(path.join(s.workRoot, "sdd", "p1", "handoff.md"), "# Handoff p1\n");
  s.stub.db.failures.push({ method: "PATCH", path: "/api/v1/worklog/workstreams/", status: 503 });
  const failed = await s.push();
  assert.equal(failed.code, 1);
  assert.match(failed.stdout, /^failed: superpowers\/handoff\/p1\.md: linking it from workstream p1: darkmem answered 503: injected failure$/m);
  const stateFile = path.join(s.mirror, ".sync-state.json");
  assert.deepEqual(JSON.parse(read(stateFile)).pendingLinks, ["superpowers/handoff/p1.md"]);
  const retried = await s.push();
  assert.equal(retried.code, 0, retried.stdout);
  assert.equal(s.stub.db.workstreams.find(w => w.key === "p1").properties.handoff_uri, "superpowers/handoff/p1.md");
  assert.deepEqual(JSON.parse(read(stateFile)).pendingLinks, []);
  const state = JSON.parse(read(stateFile));
  state.pendingLinks = ["superpowers/handoff/ghost.md"];
  fs.writeFileSync(stateFile, JSON.stringify(state));
  const dropped = await s.push();
  assert.equal(dropped.code, 0, dropped.stdout);
  assert.deepEqual(JSON.parse(read(stateFile)).pendingLinks, []);
  assert.equal(s.stub.db.workstreams.some(w => w.key === "ghost"), false);
});

test("a checkpoint filed a microsecond before the last synced one is not taken for this note", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# X\n" }] });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# Y\n" }] });
  const [x, y] = s.stub.db.workstreams[0].entries;
  x.created_at = "2026-09-25T10:00:00.000001+00:00";
  y.created_at = "2026-09-25T10:00:00.000002+00:00";
  assert.equal((await run(["pull"], { cwd: s.repo, env: s.env })).code, 0);
  assert.equal(read(path.join(s.workRoot, "handoff", "latest.md")), "# Y\n");
  write(path.join(s.workRoot, "handoff", "latest.md"), "# X\n");
  const result = await s.push("--workstream", "p1");
  assert.equal(result.code, 0, result.stdout);
  assert.match(result.stdout, /1 checkpoints/);
  assert.deepEqual(s.stub.db.workstreams[0].entries.map(e => e.body), ["# X\n", "# Y\n", "# X\n"]);
});

test("push refuses a uri Windows cannot hold", { skip: process.platform === "win32" && "Windows cannot create these files" }, async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "notes", "a:b.md"), "x\n");
  write(path.join(s.docsRoot, "notes", "CON.md"), "y\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^failed: superpowers\/notes\/a:b\.md: the name "a:b\.md" holds a character Windows refuses, so not every mirror can hold it as a file; not pushed$/m);
  assert.match(result.stdout, /^failed: superpowers\/notes\/CON\.md: the name "CON\.md" is a Windows device name/m);
  assert.equal(s.posts("/api/v1/documents").length, 0);
});

test("push refuses a uri that differs only in case from one darkmem holds", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/notes/A.md", content: "theirs\n" });
  write(path.join(s.docsRoot, "notes", "a.md"), "mine\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^conflict: superpowers\/notes\/a\.md: darkmem holds superpowers\/notes\/A\.md, which differ only in case from it; not pushed — rename the local file, or rename or delete the others on darkmem by hand \(the sync has no rename or delete route\)$/m);
  assert.equal(s.posts("/api/v1/documents").length, 1, "only the seeding put");
  await s.seed.putDocument({ project: "proj", uri: "superpowers/notes/a.md", content: "also theirs\n" });
  const pair = await s.push();
  assert.equal(pair.code, 1);
  assert.match(pair.stdout, /^conflict: superpowers\/notes\/a\.md: darkmem holds superpowers\/notes\/A\.md, which differ only in case/m, "a local file matching one of a remote pair still collides with the other");
  assert.equal(s.posts("/api/v1/documents").length, 2, "only the two seeding puts");
});

test("push refuses local files that differ only in case", { skip: process.platform !== "linux" && "needs a case-sensitive file system" }, async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "A.md"), "one\n");
  write(path.join(s.docsRoot, "a.md"), "two\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^conflict: superpowers\/A\.md, superpowers\/a\.md: differ only in case, which a case-insensitive file system holds as one file; none of them pushed — rename all but one$/m);
  assert.equal(s.posts("/api/v1/documents").length, 0);
});

test("a 409 whose read answers darkmem's own 404 is a deletion; any other 404 is a failure", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "one\n");
  await s.push();
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "theirs\n" });
  write(path.join(s.docsRoot, "a.md"), "two\n");
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/documents/by-uri", status: 404, detail: "Not Found" });
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^failed: superpowers\/a\.md: darkmem answered 404: Not Found$/m);
  assert.doesNotMatch(result.stdout, /deleted on darkmem/);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `plugins/dr-superpowers`): `timeout 300 node --test --test-reporter=spec tests/darkmem-sync/push.test.mjs`

Expected: FAIL: `ℹ pass 21`, `ℹ fail 10`; the failing tests are exactly:

  - a 409 whose read answers darkmem's own 404 is a deletion; any other 404 is a failure
  - a 503 on one document names its uri, and the other documents, the ledger and the checkpoint still land
  - a checkpoint filed a microsecond before the last synced one is not taken for this note
  - a document put whose answer was lost is recorded on the next push, not reported as a conflict
  - a failed document manifest fails the documents phase and the ledgers still push
  - a failed handoff link stays pending and the next push links it; a pending link with no workstream is dropped
  - latest.md goes up as a checkpoint on the plan its State names, or on --workstream
  - push refuses a uri Windows cannot hold
  - push refuses a uri that differs only in case from one darkmem holds
  - push refuses local files that differ only in case

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/lib/darkmem-push.mjs`, replace:

```js
const RESOLVE = "pull, reconcile, then push";
```

with:

```js
const RESOLVE = "pull, reconcile, then push";
// darkmem's own answer for a uri nothing is filed at; any other 404 (a wrong
// url, a missing route) is not evidence that the document was deleted.
const NOT_FILED = /^no document is filed at uri /;
```

In `plugins/dr-superpowers/scripts/lib/darkmem-push.mjs`, replace:

```js
import { HttpError, failItem } from "./darkmem-client.mjs";
import {
  DOC_PREFIX, EMPTY_SHA, MAX_ENTRIES_PER_APPEND, MAX_ENTRY_CHARS, UsageError, checkpointTarget, decodeUtf8,
  ledgerFiles, ledgerPlanPath, listDocumentFiles, propertiesFor, sha256, splitAtLimit, unsupportedPlanDirs, utf8Fault,
  validKey,
} from "./darkmem-mirror.mjs";
import { remoteLedger } from "./darkmem-pull.mjs";
```

with:

```js
import { HttpError, failItem } from "./darkmem-client.mjs";
import {
  DOC_PREFIX, EMPTY_SHA, MAX_ENTRIES_PER_APPEND, MAX_ENTRY_CHARS, UsageError, caseGroups, checkpointTarget, decodeUtf8,
  isoMicros, ledgerFiles, ledgerPlanPath, listDocumentFiles, propertiesFor, sha256, splitAtLimit, unsupportedPlanDirs,
  uriProblem, utf8Fault, validKey,
} from "./darkmem-mirror.mjs";
import { remoteLedger } from "./darkmem-pull.mjs";
```

In `plugins/dr-superpowers/scripts/lib/darkmem-push.mjs`, replace:

```js
// A handoff note filed after its workstream began: point the workstream at it.
async function linkHandoff({ cfg, client }, uri) {
  const slug = HANDOFF_URI.exec(uri)?.[1];
  if (!slug) return;
  const existing = await client.resume(cfg.project, slug);
  if (existing && existing.workstream.properties?.handoff_uri !== uri) {
    await client.updateWorkstream(existing.workstream.id, { properties: { handoff_uri: uri } });
  }
}

async function pushDocuments(context) {
  const { cfg, client, roots, state, persist, report } = context;
  let remote = null;
  const remoteHash = async uri => {
    remote ??= new Map((await client.manifest(cfg.project, DOC_PREFIX)).map(item => [item.uri, item.content_hash]));
    return remote.get(uri) ?? null;
  };
  for (const { file, uri } of listDocumentFiles(roots)) {
    if (!uri) {
      report.notes.push(`${path.relative(roots.docsRoot, file).split(path.sep).join("/")}: the docs root's handoff/ directory is reserved, not pushed`);
      continue;
    }
    const buffer = fs.readFileSync(file);
    const local = sha256(buffer);
    const recorded = state.documents[uri];
    if (local === recorded) continue;
    const content = decodeUtf8(buffer);
    if (!content) {
      report.failures.push(`${uri}: empty or not UTF-8 text, which darkmem cannot store; not pushed`);
      continue;
    }
    if (recorded === undefined) {
      const current = await remoteHash(uri);
      if (current === local) {
        state.documents[uri] = local;
        persist();
        await linkHandoff(context, uri);
        continue;
      }
      if (current !== null) {
        report.conflicts.push(`${uri}: darkmem already holds different content; ${RESOLVE}`);
        continue;
      }
    }
    let answer;
    try {
      answer = await client.putDocument({ project: cfg.project, uri, content, expectedHash: recorded });
    } catch (error) {
      if (error instanceof HttpError && error.status === 422) {
        report.failures.push(`${uri}: darkmem refused it: ${error.detail}`);
        continue;
      }
      if (!(error instanceof HttpError && error.status === 409)) throw error;
      // A 409 may be this mirror's own earlier put whose answer was lost.
      let current = null;
      try {
        current = (await client.getDocument(cfg.project, uri)).content_hash;
      } catch (readError) {
        if (!(readError instanceof HttpError && readError.status === 404)) throw readError;
        report.conflicts.push(`${uri}: deleted on darkmem since the last sync; ${RESOLVE}`);
        continue;
      }
      if (current !== local) {
        report.conflicts.push(`${uri}: changed on darkmem since the last sync (darkmem said: ${error.detail}); ${RESOLVE}`);
        continue;
      }
      answer = { content_hash: current, outcome: "unchanged" };
    }
    state.documents[uri] = answer.content_hash;
    persist();
    report.counts.documents += 1;
    if (recorded === undefined && answer.outcome === "updated") {
      // darkmem has no create-only put: another client filed this uri between
      // the manifest read and this put, and its content was replaced.
      report.failures.push(`${uri}: another client filed it during this push, and this push replaced its content`);
    }
    await linkHandoff(context, uri);
  }
}
```

with:

```js
// A handoff note filed after its workstream began: point the workstream at it.
// The uri stays in pendingLinks until the workstream carries it, or has none
// yet (its first append carries the uri), so a failed link is retried by the
// next push rather than only by a later append.
async function linkHandoff({ cfg, client, state, persist, report }, uri) {
  const slug = HANDOFF_URI.exec(uri)?.[1];
  if (!slug) return;
  if (!state.pendingLinks.includes(uri)) {
    state.pendingLinks.push(uri);
    persist();
  }
  try {
    const existing = await client.resume(cfg.project, slug);
    if (existing && existing.workstream.properties?.handoff_uri !== uri) {
      await client.updateWorkstream(existing.workstream.id, { properties: { handoff_uri: uri } });
    }
  } catch (error) {
    failItem(report, `${uri}: linking it from workstream ${slug}`, error);
    return;
  }
  state.pendingLinks = state.pendingLinks.filter(item => item !== uri);
  persist();
}

// One changed document, sent under its recorded hash. `remote` is the
// manifest's uri -> content_hash map.
async function pushDocument(context, { uri, buffer, local, recorded }, remote) {
  const { cfg, client, state, persist, report } = context;
  const content = decodeUtf8(buffer);
  if (!content) {
    report.failures.push(`${uri}: empty or not UTF-8 text, which darkmem cannot store; not pushed`);
    return;
  }
  if (recorded === undefined) {
    const current = remote.get(uri) ?? null;
    if (current === local) {
      state.documents[uri] = local;
      persist();
      await linkHandoff(context, uri);
      return;
    }
    if (current !== null) {
      report.conflicts.push(`${uri}: darkmem already holds different content; ${RESOLVE}`);
      return;
    }
  }
  let answer;
  try {
    answer = await client.putDocument({ project: cfg.project, uri, content, expectedHash: recorded });
  } catch (error) {
    if (error instanceof HttpError && error.status === 422) {
      report.failures.push(`${uri}: darkmem refused it: ${error.detail}`);
      return;
    }
    if (!(error instanceof HttpError && error.status === 409)) throw error;
    // A 409 may be this mirror's own earlier put whose answer was lost.
    let current = null;
    try {
      current = (await client.getDocument(cfg.project, uri)).content_hash;
    } catch (readError) {
      if (!(readError instanceof HttpError && readError.status === 404 && NOT_FILED.test(readError.detail))) throw readError;
      report.conflicts.push(`${uri}: deleted on darkmem since the last sync; ${RESOLVE}`);
      return;
    }
    if (current !== local) {
      report.conflicts.push(`${uri}: changed on darkmem since the last sync (darkmem said: ${error.detail}); ${RESOLVE}`);
      return;
    }
    answer = { content_hash: current, outcome: "unchanged" };
  }
  state.documents[uri] = answer.content_hash;
  persist();
  report.counts.documents += 1;
  if (recorded === undefined && answer.outcome === "updated") {
    // darkmem has no create-only put: another client filed this uri between
    // the manifest read and this put, and its content was replaced.
    report.failures.push(`${uri}: another client filed it during this push, and this push replaced its content`);
  }
  await linkHandoff(context, uri);
}

async function pushDocuments(context) {
  const { cfg, client, roots, state, report } = context;
  const files = listDocumentFiles(roots);
  const twins = caseGroups(files.map(({ uri }) => uri).filter(Boolean));
  for (const group of twins) {
    report.conflicts.push(`${group.join(", ")}: differ only in case, which a case-insensitive file system holds as one file; none of them pushed — rename all but one`);
  }
  const held = new Set(twins.flat());
  const changed = [];
  for (const { file, uri } of files) {
    if (!uri) {
      report.notes.push(`${path.relative(roots.docsRoot, file).split(path.sep).join("/")}: the docs root's handoff/ directory is reserved, not pushed`);
      continue;
    }
    if (held.has(uri)) continue;
    const buffer = fs.readFileSync(file);
    const local = sha256(buffer);
    const recorded = state.documents[uri];
    if (local === recorded) continue;
    const problem = uriProblem(uri);
    if (problem) {
      report.failures.push(`${uri}: ${problem}, so not every mirror can hold it as a file; not pushed`);
      continue;
    }
    changed.push({ uri, buffer, local, recorded });
  }
  if (!changed.length) return;
  let remote;
  try {
    remote = new Map((await client.manifest(cfg.project, DOC_PREFIX)).map(item => [item.uri, item.content_hash]));
  } catch (error) {
    failItem(report, "document manifest", error, "; no document pushed");
    return;
  }
  // Every spelling darkmem holds under each lower-case form: when it holds
  // A.md and a.md, a local a.md collides with A.md although a.md matches.
  const spellings = new Map();
  for (const uri of remote.keys()) spellings.set(uri.toLowerCase(), [...(spellings.get(uri.toLowerCase()) ?? []), uri]);
  for (const item of changed) {
    const twins = (spellings.get(item.uri.toLowerCase()) ?? []).filter(uri => uri !== item.uri).sort();
    if (twins.length) {
      report.conflicts.push(`${item.uri}: darkmem holds ${twins.join(", ")}, which differ only in case from it; not pushed — rename the local file, or rename or delete the others on darkmem by hand (the sync has no rename or delete route)`);
      continue;
    }
    try {
      await pushDocument(context, item, remote);
    } catch (error) {
      failItem(report, item.uri, error);
    }
  }
}
```

In `plugins/dr-superpowers/scripts/lib/darkmem-push.mjs`, replace:

```js
async function pushCheckpoint({ cfg, client, roots, state, persist, report }, named) {
```

with:

```js
async function pushCheckpoint(context, named) {
  try {
    await sendCheckpoint(context, named);
  } catch (error) {
    failItem(context.report, "handoff/latest.md", error);
  }
}

async function sendCheckpoint({ cfg, client, roots, state, persist, report }, named) {
```

In `plugins/dr-superpowers/scripts/lib/darkmem-push.mjs`, replace:

```js
  const since = state.checkpointAt ? Date.parse(state.checkpointAt) : -Infinity;
  const filed = existing && (await client.entries(existing.workstream.id, "checkpoint"))
    .find(entry => Date.parse(entry.created_at) >= since && sha256(Buffer.from(entry.body, "utf8")) === hash);
```

with:

```js
  const since = (state.checkpointAt && isoMicros(state.checkpointAt)) ?? -Infinity;
  const filed = existing && (await client.entries(existing.workstream.id, "checkpoint"))
    .find(entry => isoMicros(entry.created_at) >= since && sha256(Buffer.from(entry.body, "utf8")) === hash);
```

In `plugins/dr-superpowers/scripts/lib/darkmem-push.mjs`, replace:

```js
  Object.assign(context.report.counts, { documents: 0, "ledger entries": 0, checkpoints: 0 });
  await pushDocuments(context);
```

with:

```js
  Object.assign(context.report.counts, { documents: 0, "ledger entries": 0, checkpoints: 0 });
  for (const uri of [...context.state.pendingLinks]) await linkHandoff(context, uri);
  await pushDocuments(context);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `plugins/dr-superpowers`): `timeout 300 node --test --test-reporter=spec tests/darkmem-sync/push.test.mjs`

Expected (Linux): `ℹ pass 31`, `ℹ fail 0`.

- [ ] **Step 5: Run the whole darkmem-sync suite**

Run (from `plugins/dr-superpowers`): `timeout 300 bash tests/darkmem-sync.test.sh`

Expected (Linux): `ℹ pass 91`, `ℹ fail 0`; `ls "${TMPDIR:-/tmp}" | grep -c '^dms-'` prints `0` (no fixture directory left behind).

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/darkmem-push.mjs tests/darkmem-sync/push.test.mjs
git commit -m "fix(superpowers): keep pushing past a failed item" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Pull goes on past a failed item and refuses unportable uris

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/darkmem-pull.mjs` (import; `pullDocuments` split into `pullDocument` and `pullDocuments`; `pullLedgers`; `pullCheckpoint`; `pull`)
- Test: `plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs`

**Interfaces:**
- Consumes: Task 1's `isoMicros`, `uriProblem`, `caseGroups`; Task 3's `failItem`; Task 4's `pullLedgers` as Task 4 leaves it.
- Produces: the pull lines in Contracts → **Output lines**.

**Items:** 7

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

Spec §3 (pull errors and timestamps; portable uris, pull side). One existing test changes its injected answer from 503 to 401, so it still exercises a run that stops part-way; it passes before and after this task. The portability check runs before the uri is mapped, so a uri darkmem holds that no mirror can hold (`superpowers/handoff/a:b.md`, and a name like `superpowers/../x.md`, whose `..` segment ends in a dot) fails every pull until it is renamed on darkmem, instead of being skipped with a note; it is never written either way.

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs`, replace:

```js
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/worklog/workstreams", status: 503 });
  const result = await s.pull();
  assert.equal(result.code, 3);
```

with:

```js
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/worklog/workstreams", status: 401, detail: "Not authenticated" });
  const result = await s.pull();
  assert.equal(result.code, 3);
```

Append to the end of `plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs`:

```js
test("a failed document fetch names its uri and the pull goes on; a failed manifest or workstream list fails its phase", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "a\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/b.md", content: "b\n" });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/documents/by-uri", status: 503 });
  const one = await s.pull();
  assert.equal(one.code, 1);
  assert.match(one.stdout, /^failed: superpowers\/a\.md: darkmem answered 503: injected failure$/m);
  assert.equal(fs.existsSync(path.join(s.docsRoot, "a.md")), false);
  assert.equal(read(path.join(s.docsRoot, "b.md")), "b\n");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), "one\n");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "two\n" }] });
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/documents/manifest", status: 503 });
  const manifest = await s.pull();
  assert.equal(manifest.code, 1);
  assert.match(manifest.stdout, /^failed: document manifest: darkmem answered 503: injected failure; no document pulled$/m);
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), "one\ntwo\n", "the ledgers still pull");
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/worklog/workstreams", status: 503 });
  const list = await s.pull();
  assert.equal(list.code, 1);
  assert.match(list.stdout, /^failed: workstream list: darkmem answered 503: injected failure; no ledger or checkpoint pulled$/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "a\n", "the documents still pull");
});

test("a failed ledger or checkpoint read names its item and the rest still pull", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "ledger", body: "two\n" }, { kind: "checkpoint", body: "# p2\n" }] });
  s.stub.db.failures.push({ method: "GET", path: `/api/v1/worklog/workstreams/${s.stub.db.workstreams[1].id}/entries`, status: 503 });
  const ledger = await s.pull();
  assert.equal(ledger.code, 1);
  assert.match(ledger.stdout, /^failed: sdd\/p2\/progress\.md: darkmem answered 503: injected failure$/m);
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), "one\n");
  assert.equal(read(path.join(s.workRoot, "handoff", "latest.md")), "# p2\n");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# p1\n" }] });
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/worklog/resume", status: 503 });
  const resumes = () => s.stub.db.requests.filter(r => r.path === "/api/v1/worklog/resume").length;
  const before = resumes();
  const checkpoint = await s.pull();
  assert.equal(resumes() - before, 2, "the other workstream's checkpoint is still read");
  assert.equal(checkpoint.code, 1);
  assert.match(checkpoint.stdout, /^failed: handoff\/latest\.md: darkmem answered 503: injected failure \(reading workstream p2\); not pulled$/m);
  assert.equal(read(path.join(s.workRoot, "handoff", "latest.md")), "# p2\n", "without every checkpoint the newest is unknown");
  assert.equal(read(path.join(s.workRoot, "sdd", "p2", "progress.md")), "two\n");
});

test("checkpoints a microsecond apart are ordered by darkmem's clock, not rounded to the millisecond", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# A\n" }] });
  s.stub.db.workstreams[0].entries[0].created_at = "2026-09-25T10:00:00.000001+00:00";
  assert.equal((await s.pull()).code, 0);
  const latest = path.join(s.workRoot, "handoff", "latest.md");
  assert.equal(read(latest), "# A\n");
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "checkpoint", body: "# B\n" }] });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# C\n" }] });
  s.stub.db.workstreams[1].entries[0].created_at = "2026-09-25T10:00:00.000002+00:00";
  s.stub.db.workstreams[0].entries[1].created_at = "2026-09-25T10:00:00.000003+00:00";
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(latest), "# C\n", "p2 is listed first, and C is newer than B by one microsecond");
  assert.equal(s.state().checkpointAt, "2026-09-25T10:00:00.000003+00:00");
});

test("pull refuses uris Windows cannot hold, and writes none of a set that differ only in case", async t => {
  const s = await setup(t);
  for (const uri of ["superpowers/notes/a:b.md", "superpowers/notes/CON.md", "superpowers/handoff/a:b.md", "superpowers/A.md", "superpowers/a.md", "superpowers/ok.md"]) {
    await s.seed.putDocument({ project: "proj", uri, content: `${uri}\n` });
  }
  const result = await s.pull();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^failed: superpowers\/notes\/a:b\.md: the name "a:b\.md" holds a character Windows refuses, so not every mirror can hold it as a file; not pulled — rename it on darkmem by hand$/m);
  assert.match(result.stdout, /^failed: superpowers\/notes\/CON\.md: the name "CON\.md" is a Windows device name/m);
  assert.match(result.stdout, /^failed: superpowers\/handoff\/a:b\.md: the name "a:b\.md" holds a character Windows refuses/m, "a handoff uri is checked before it is mapped");
  assert.match(result.stdout, /^conflict: superpowers\/A\.md, superpowers\/a\.md: differ only in case, which a case-insensitive file system holds as one file; none of them pulled — rename or delete all but one on darkmem by hand \(the sync has no rename or delete route\)$/m);
  assert.deepEqual(fs.readdirSync(s.docsRoot), ["ok.md"]);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `plugins/dr-superpowers`): `timeout 300 node --test --test-reporter=spec tests/darkmem-sync/pull.test.mjs`

Expected: FAIL: `ℹ pass 12`, `ℹ fail 4`; the failing tests are exactly:

  - a failed document fetch names its uri and the pull goes on; a failed manifest or workstream list fails its phase
  - a failed ledger or checkpoint read names its item and the rest still pull
  - checkpoints a microsecond apart are ordered by darkmem's clock, not rounded to the millisecond
  - pull refuses uris Windows cannot hold, and writes none of a set that differ only in case

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/lib/darkmem-pull.mjs`, replace:

```js
import { DOC_PREFIX, sha256, uriToLocal, validKey, writeFileAtomic } from "./darkmem-mirror.mjs";
```

with:

```js
import { failItem } from "./darkmem-client.mjs";
import { DOC_PREFIX, caseGroups, isoMicros, sha256, uriProblem, uriToLocal, validKey, writeFileAtomic } from "./darkmem-mirror.mjs";
```

In `plugins/dr-superpowers/scripts/lib/darkmem-pull.mjs`, replace:

```js
// Every document under superpowers/ whose manifest hash differs from the
// mirror's copy. The local file is hashed again after the fetch, because an
// edit can land while the request is out.
export async function pullDocuments({ cfg, client, roots, state, persist, report }) {
  for (const item of await client.manifest(cfg.project, DOC_PREFIX)) {
    if (!item.content_hash) continue;
    const file = uriToLocal(roots, item.uri);
    if (!file) {
      report.notes.push(`${item.uri}: has no place in the mirror, skipped`);
      continue;
    }
    const local = localHash(file);
    if (local === item.content_hash) {
      state.documents[item.uri] = local;
      continue;
    }
    // darkmem has not moved since the last sync: a local edit is push's to
    // send, not a conflict.
    if (local !== null && item.content_hash === state.documents[item.uri]) continue;
    if (local !== null && local !== state.documents[item.uri]) {
      report.conflicts.push(`${item.uri}: changed locally and on darkmem; ${RESOLVE}`);
      continue;
    }
    const doc = await client.getDocument(cfg.project, item.uri);
    if (typeof doc.content !== "string") {
      report.notes.push(`${item.uri}: darkmem holds no text for it, skipped`);
      continue;
    }
    if (localHash(file) !== local) {
      report.conflicts.push(`${item.uri}: changed locally during the pull; ${RESOLVE}`);
      continue;
    }
    writeFileAtomic(file, doc.content);
    state.documents[item.uri] = doc.content_hash;
    persist();
    report.counts.documents += 1;
  }
}
```

with:

```js
// One manifest item whose hash differs from the mirror's copy. The local file
// is hashed again after the fetch, because an edit can land while the request
// is out.
async function pullDocument({ cfg, client, roots, state, persist, report }, item) {
  // Checked before the mapping, which refuses some of these names on its own
  // (a handoff uri needs a workstream key) and would only note them.
  const problem = uriProblem(item.uri);
  if (problem) {
    report.failures.push(`${item.uri}: ${problem}, so not every mirror can hold it as a file; not pulled — rename it on darkmem by hand`);
    return;
  }
  const file = uriToLocal(roots, item.uri);
  if (!file) {
    report.notes.push(`${item.uri}: has no place in the mirror, skipped`);
    return;
  }
  const local = localHash(file);
  if (local === item.content_hash) {
    state.documents[item.uri] = local;
    return;
  }
  // darkmem has not moved since the last sync: a local edit is push's to
  // send, not a conflict.
  if (local !== null && item.content_hash === state.documents[item.uri]) return;
  if (local !== null && local !== state.documents[item.uri]) {
    report.conflicts.push(`${item.uri}: changed locally and on darkmem; ${RESOLVE}`);
    return;
  }
  const doc = await client.getDocument(cfg.project, item.uri);
  if (typeof doc.content !== "string") {
    report.notes.push(`${item.uri}: darkmem holds no text for it, skipped`);
    return;
  }
  if (localHash(file) !== local) {
    report.conflicts.push(`${item.uri}: changed locally during the pull; ${RESOLVE}`);
    return;
  }
  writeFileAtomic(file, doc.content);
  state.documents[item.uri] = doc.content_hash;
  persist();
  report.counts.documents += 1;
}

// Every document under superpowers/. Uris that differ only in case are one
// file on a case-insensitive file system, so none of them is written.
export async function pullDocuments(context) {
  const { cfg, client, report } = context;
  let items;
  try {
    items = await client.manifest(cfg.project, DOC_PREFIX);
  } catch (error) {
    failItem(report, "document manifest", error, "; no document pulled");
    return;
  }
  const twins = caseGroups(items.map(item => item.uri));
  for (const group of twins) {
    report.conflicts.push(`${group.join(", ")}: differ only in case, which a case-insensitive file system holds as one file; none of them pulled — rename or delete all but one on darkmem by hand (the sync has no rename or delete route)`);
  }
  const held = new Set(twins.flat());
  for (const item of items) {
    if (!item.content_hash || held.has(item.uri)) continue;
    try {
      await pullDocument(context, item);
    } catch (error) {
      failItem(report, item.uri, error);
    }
  }
}
```

In `plugins/dr-superpowers/scripts/lib/darkmem-pull.mjs`, replace:

```js
    const { text, lastSeq } = await remoteLedger(client, ws.id);
    if (!text) continue;
```

with:

```js
    let ledger;
    try {
      ledger = await remoteLedger(client, ws.id);
    } catch (error) {
      failItem(report, `sdd/${ws.key}/progress.md`, error);
      continue;
    }
    const { text, lastSeq } = ledger;
    if (!text) continue;
```

In `plugins/dr-superpowers/scripts/lib/darkmem-pull.mjs`, replace:

```js
  let newest = null;
  for (const ws of open) {
    const checkpoint = (await client.resume(cfg.project, ws.key))?.checkpoint;
    if (checkpoint && (!newest || Date.parse(checkpoint.created_at) > Date.parse(newest.created_at))) newest = checkpoint;
  }
  if (!newest) return;
  if (state.checkpointAt && Date.parse(newest.created_at) <= Date.parse(state.checkpointAt)) return;
```

with:

```js
  let newest = null;
  let unread = false;
  for (const ws of open) {
    let checkpoint;
    try {
      checkpoint = (await client.resume(cfg.project, ws.key))?.checkpoint;
    } catch (error) {
      failItem(report, "handoff/latest.md", error, ` (reading workstream ${ws.key}); not pulled`);
      unread = true;
      continue;
    }
    if (checkpoint && (!newest || isoMicros(checkpoint.created_at) > isoMicros(newest.created_at))) newest = checkpoint;
  }
  // Without every workstream's checkpoint the newest is unknown.
  if (!newest || unread) return;
  if (state.checkpointAt && isoMicros(newest.created_at) <= isoMicros(state.checkpointAt)) return;
```

In `plugins/dr-superpowers/scripts/lib/darkmem-pull.mjs`, replace:

```js
  await pullDocuments(context);
  const open = await context.client.workstreams(context.cfg.project, "open");
```

with:

```js
  await pullDocuments(context);
  let open;
  try {
    open = await context.client.workstreams(context.cfg.project, "open");
  } catch (error) {
    failItem(context.report, "workstream list", error, "; no ledger or checkpoint pulled");
    return;
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `plugins/dr-superpowers`): `timeout 300 node --test --test-reporter=spec tests/darkmem-sync/pull.test.mjs`

Expected (Linux): `ℹ pass 16`, `ℹ fail 0`.

- [ ] **Step 5: Run the whole darkmem-sync suite**

Run (from `plugins/dr-superpowers`): `timeout 300 bash tests/darkmem-sync.test.sh`

Expected (Linux): `ℹ pass 95`, `ℹ fail 0`; `ls "${TMPDIR:-/tmp}" | grep -c '^dms-'` prints `0` (no fixture directory left behind).

- [ ] **Step 6: Run the repository checks**

Run from the repository root:

```bash
timeout 60 node scripts/validate-repository.mjs
timeout 590 node scripts/test-all.mjs
for target in . plugins/dr-status plugins/dr-superpowers plugins/dcc-darkraise-ui plugins/dcc-darkraise-win32ui; do timeout 60 claude plugin validate "$target"; done
```

Expected: `Repository catalogs, manifests, versions, and bundled links are valid.`; every suite `test-all.mjs` runs exits 0; `✔ Validation passed` five times. `tests/ui-discovery.test.mjs` calls `rg` from a non-interactive `bash`; where `rg` is not on that `PATH` it fails with `rg: command not found`. If it fails, check the same test on `main` in a throwaway worktree, from the repository root:

```bash
base=$(mktemp -d)
git worktree add --detach "$base/main" main
(cd "$base/main" && timeout 60 node --test --test-reporter=spec tests/ui-discovery.test.mjs)
git worktree remove --force "$base/main" && rm -rf "$base"
```

Expected: the same `rg: command not found` failure on `main`. Report it as pre-existing, and do not edit that test. Any other failing suite is this plan's to fix.

- [ ] **Step 7: Commit**

```bash
git add scripts/lib/darkmem-pull.mjs tests/darkmem-sync/pull.test.mjs
git commit -m "fix(superpowers): keep pulling past a failed item" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
