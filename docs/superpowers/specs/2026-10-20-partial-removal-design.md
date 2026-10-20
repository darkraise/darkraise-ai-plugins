# Partial-file removal in writeExclusive

**Execution strategy:** sequential — one function, one test and a release;
nothing splits into independent parts

**Registers:** `docs/superpowers/registers/2026-09-24-darkmem-mirror.md`
(DM 73, DM 74); this spec is added to its `**Covers:**` line

**Approach:** inline - skip 1: the row names the fix, and the owner approved
the rulings as presented on 2026-10-20

## Decisions

The owner's answers on 2026-10-20.

1. DM 74 is fixed: `writeExclusive` removes its partial file only when the
   path still names the file its descriptor created.
2. DM 73 is deferred as "can stand". Node's `fs` has no `openat` and cannot
   refuse a link in the middle of a path, so a parent directory swapped for
   a link after the link check can only be narrowed, not closed. Only a
   process running as the same user can make the swap. The exclusive create
   never overwrites anything, so the worst outcome is a new file, and any
   directories `mkdirSync` makes, outside the checkout. The read-back after
   the copy loop follows parent links too, so it does not detect the stray
   file.
3. `progressToLocal` gains the comment `documentsToLocal` already carries,
   naming the unguarded parent swap.
4. Sequential execution.

## Problem

`writeExclusive` (`scripts/lib/darkmem-progress-move.mjs`, about line 60)
creates `file` with `openSync(file, "wx")` and writes through the
descriptor. When the write throws, it closes the descriptor and calls
`rmSync(file, { force: true })`. If another process unlinked or renamed
the new file and put its own at the same path between the create and the
failure, `rmSync` deletes that process's file.

Code paths are relative to `plugins/dforge/`.

## Design

### W1. `writeExclusive`

In the `catch` after a failed write, in this order:

1. `own = fs.fstatSync(fd, { bigint: true })`.
2. `now = fs.lstatSync(file, { bigint: true, throwIfNoEntry: false })`.
3. Close the descriptor, ignoring a close error as today.
4. Remove `file` only when `own` and `now` are both present and
   `own.dev === now.dev && own.ino === now.ino`.
5. Rethrow the write error.

A failure in step 1 or 2 means the file is left in place. The stats are
taken while the descriptor is open, because once our file has been
unlinked and its descriptor closed, the system can reuse its inode number
for a newcomer's file. `bigint` keeps Windows' 64-bit file IDs exact.

A gap remains between step 2 and the removal. The function's comment says
so, in place of its claim that a failed write "removes only the partial
file it made".

The success path and the callers' refusals ("a copy into ... failed
(`<code>`)") do not change. A file left in place because step 1 or 2
failed may be our partial file; a rerun's comparison then refuses it as a
different copy, as it did before the removal existed.

### W2. `progressToLocal` comment

Above the copy loop in `progressToLocal` (about line 655), the existing
comment adds that a parent directory swapped for a link after
`linksBelow`'s check is not guarded, matching `documentsToLocal`.

## Testing

`tests/darkmem-sync/reconcile-progress.test.mjs`, next to the test "a copy
into the primary checkout that fails part-way is a refusal, not a crash,
and a rerun finishes it" (about line 1042), which already shows our own
partial file being removed: its rerun succeeds only because the empty
partial file is gone. That test is the regression guard.

New test, modelled on it with `exclusiveOpens(t)` and a `writeFileSync`
mock keyed on the second target's descriptor:

- Before throwing `EIO`, the mock renames the target aside and plants a
  newcomer file with other content at the target path through the
  captured original `writeFileSync`.
- `progressToLocal` refuses with "a copy into the primary checkout failed
  (EIO); ...", and the newcomer file is still at the target with its
  content.
- It fails on main: the newcomer is deleted.

After the change: `node scripts/test-all.mjs`, `node
scripts/validate-repository.mjs`, `claude plugin validate` on the
marketplace and every Claude plugin, and `claude plugin test
plugins/dforge`, each with a timeout and nothing left running.

## Release

Version 4.2.4 in `plugins/dforge/.claude-plugin/plugin.json` and
`plugins/dforge/.codex-plugin/plugin.json`. Register bookkeeping through
dr-superpowers:finishing-a-development-branch closes DM 74; DM 73 is
deferred when this spec is committed.

## Acceptance

A1. [test, high] W1 behaves as written; the new test passes and fails on
main; the regression guard passes.
A2. [test, high] The validation commands under Testing pass on the merged
branch.
A3. [read, high] DM 74 is `done`, DM 73 is `deferred` with the ruling in
its note; `register check` reports no errors.
A4. [test, high] Both dforge manifests read 4.2.4.

## Riskiest assumption

That `fstatSync` on the open descriptor and `lstatSync` on the path report
the same `dev` and `ino` for the same file on Linux, macOS and Windows.
POSIX guarantees it for the first two. On Windows libuv fills `ino` from
the file index for both calls and `dev` from the volume serial number
(inference from libuv's source, unverified here). The new test also renames
a file whose descriptor is open, which Windows allows only when the file
was opened with `FILE_SHARE_DELETE`, as libuv does (inference, unverified).
The test runs on the Windows shards and is the check for both.
