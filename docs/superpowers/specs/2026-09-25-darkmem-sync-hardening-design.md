# darkmem-sync hardening

Date: 2026-09-25
Status: design, owner-approved section by section on 2026-09-25.
Parent: `docs/superpowers/specs/2026-09-23-darkmem-mirror-design.md` (§3).
Register: `docs/superpowers/registers/2026-09-24-darkmem-mirror.md` rows 7 and 14.

Sub-project (a) of the mirror's remaining work, which the owner split into
three on 2026-09-25: (a) this hardening, (b) the two roots and plan identity
(row 2), (c) sync triggers and memory promotion (rows 3 and 4). (a) comes
first because row 3's Stop hook will push unattended.

The final review of increment 1 left these gaps. Its finding labels (C5, C11)
did not survive; this design covers every item row 7 lists, so the labels no
longer matter.

## 1. Server: an append precondition (darkmem repository)

`POST /api/v1/worklog/entries` gains an optional `expected_last_seq`
(integer, ≥ 0).

- When present, every entry in the call must share one kind; a mixed-kind call
  with the field set is a 422.
- Under the workstream row lock `_lock_or_create` already takes, the service
  compares the field with the seq of the workstream's newest entry of that
  kind; `0` means the workstream holds none (seq starts at 1). A mismatch
  answers 409 with the actual last seq in the detail and writes nothing,
  including no workstream creation or reopen.
- Absent, the append behaves exactly as today.
- The response gains `last_seq`: the seq of the last entry the call wrote.
- The check is per kind, so a checkpoint filed into a workstream never
  invalidates a ledger push's expectation.
- Only the REST door changes; the MCP `worklog_append` tool keeps its current
  signature (agents do not append ledgers).

Seq is a database-wide identity, not a per-workstream counter, so the
precondition names the last seq seen rather than the next one expected.

Tests (`test_worklog_service.py`, `test_worklog_rest.py`): a match writes; a
mismatch is a 409 and writes nothing; `0` on a new workstream writes and on a
workstream holding that kind is a 409; a mixed-kind call with the field is a
422; two concurrent appends expecting the same seq yield exactly one success;
`last_seq` equals the seq of the last written entry.

## 2. Client push (`scripts/lib/darkmem-push.mjs`)

**Per-item errors.** A document put, a ledger append, a checkpoint append or a
handoff link that darkmem answers with any status other than the handled
409 and 422 (a 5xx, 403, or an unexpected 404) becomes a failure line naming
the item — `<uri>: darkmem answered <status>: <detail>` — and push continues
with the next item and the next phase. A `TransportError` (no answer within
the timeout, refused connection) and a 401 still abort the run, since every
later call would fail alike. Exit codes are unchanged: any failure or conflict
is exit 1.

**Ledger precondition.** A ledger's state record becomes
`{ offset, prefix, lastSeq }`. Every append sends `expected_last_seq:
record.lastSeq` and records the answer's `last_seq`. On a 409, push
reconciles with the existing `adoptRemoteLedger` path — re-read darkmem's
ledger; when it is still a prefix of the file, adopt its offset, prefix and
the seq of its newest ledger entry, and retry the remaining bytes once;
otherwise, or on a second 409, report the conflict as today. A record without `lastSeq`, or marked
`pending`, is reconciled the same way before its first append. No mirror
exists in the field yet, so the state version stays 1 and no migration is
written. Checkpoint appends do not send the field; their de-duplication stays
as it is.

**Handoff links.** Sync state gains `pendingLinks`, a list of handoff uris.
Push adds a uri before calling the workstream update, removes it on success,
and retries every listed uri at the start of each push. A failed link is a
failure line naming the uri.

**Invalid UTF-8 in a ledger.** When the appended bytes do not decode, push
decodes them again without their last 1 to 3 bytes. If that succeeds, the
file ends inside a character still being written: a note, as today. Otherwise
the failure names the file and the offset of the first undecodable byte, and
the run exits 1.

**Timestamps.** A helper in `darkmem-mirror.mjs` turns darkmem's ISO
timestamps into comparable microsecond integers (offset applied, fraction
padded or truncated to six digits). The checkpoint "filed since the last
synced checkpoint" test uses it instead of `Date.parse`.

## 3. Client pull, uris and the lock

**Portable uris.** One check, used by pull before writing a document and by
push before sending one: a uri path segment is refused when it contains
`< > : " | ? *` or a control character, ends in a dot or a space, or is a
reserved Windows device name (`CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`,
`LPT1`–`LPT9`, with or without an extension, any case). A refused uri is a
failure naming it. Pull also groups the manifest's uris by their lower-case
form; a group of two or more is a conflict naming every member, and none of
them is written. Push treats a local file whose uri differs only in case from
another local file or a manifest uri the same way. The checks run on every
platform, so a Linux mirror never files what a Windows mirror cannot hold.

**Pull errors and timestamps.** A document fetch answered with a 5xx, 403 or
unexpected 404 is a failure naming the uri; pull continues. Choosing the
newest checkpoint and comparing it with `checkpointAt` use the timestamp
helper.

**The lock.** In `acquireLock`, a takeover that moved the lock aside, found it
is not the lock it judged abandoned, and cannot rename it back (another
process created a lock meanwhile) now leaves the moved lock in place instead
of deleting it, and returns busy. Each acquire first removes any
`.sync.lock.stale-*` directory older than `staleMs`. Two syncs can still end
up running at once in that three-process race; that is safe because
documents carry `expected_hash`, ledgers carry `expected_last_seq`,
checkpoints are de-duplicated, and the state file is written atomically.

## 4. Testing (plugin)

The stub server (`tests/darkmem-sync/stub-server.mjs`) implements
`expected_last_seq`, its 409 and `last_seq`. New cases:

- a 503 on one document: the failure names its uri, the ledger and the
  checkpoint still land, exit 1;
- a 401 on a document aborts the run;
- a ledger 409 that reconciles and appends the remainder, and one that becomes
  a conflict;
- a failed handoff link listed in `pendingLinks` and linked by the next push;
- a mid-file invalid byte: failure with its offset, exit 1; a trailing partial
  character: a note, exit 0;
- two checkpoints 1 µs apart ordered correctly by pull and push;
- `superpowers/notes/a:b.md` and `superpowers/notes/CON.md` refused by pull
  and push; `A.md` and `a.md` reported as a case conflict, neither written;
- the three-process lock race through `acquireLock`'s `beforeTakeover` seam:
  no process deletes a lock it did not judge abandoned; an old
  `.sync.lock.stale-*` is removed.

Every existing suite passes unchanged, plus `node scripts/validate-repository.mjs`
and `claude plugin validate` on the marketplace and every Claude plugin.

## Delivery

1. **Server plan** in the darkmem repository, citing this spec's §1; merged and
   deployed before the client is used against a real server. It closes this
   repository's register row 14 and adds a matching row to darkmem's
   `docs/superpowers/registers/2026-09-23-work-log-lane.md`.
2. **Client plan** in this repository for §2–§4, assigned to register row 7.
   It builds and tests against the stub server at any time; the request
   schema refuses unknown fields, so a real server needs plan 1 deployed.

Row 6 (CI's Windows shards) remains the gate for merging the darkmem-sync
branch into `main`.

## Not in scope

- Path resolution, deletions and `pathToUri` (row 2, sub-project b).
- Hooks, stop-point pushes and memory promotion (rows 3–4, sub-project c).
- An MCP-door precondition.
