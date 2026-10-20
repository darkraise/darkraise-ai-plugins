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
   process with write access to the parent directory (normally the same
   user) can make the swap. The exclusive create never overwrites anything,
   so the worst outcome is a new file, and any directories `mkdirSync`
   makes, outside the checkout. The read-back after the copy loop follows
   parent links too, so it matches and the move reports success: the
   mirror's copy is set aside and the sync state cleared, with the files
   reachable only through the link. Nothing is lost; the set-aside copy and
   darkmem still hold them.
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
4. Remove `file` with `rmSync(file, { force: true })`, as today, only when
   `own` and `now` are both present and
   `own.dev === now.dev && own.ino === now.ino`.
5. Rethrow the write error.

Steps 1 to 4 each ignore their own error, as the close and the removal do
today; only the write error leaves the function. An error from a stat call
must not replace it: `documentsToLocal` rethrows an error without a string
`code` and reconcile crashes. A failure in step 1 or 2 means the file is
left in place.

The descriptor is closed before the removal, not after: removing first would
shorten the window on POSIX, but Windows keeps the name until the last
handle closes. The stats are
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

Regression guards, which pass before and after the change and fail if W1
never removes our own partial file:

- `tests/darkmem-sync/reconcile-progress.test.mjs`, "a copy into the primary
  checkout that fails after a partial write leaves no partial file, and a
  rerun finishes it" (about line 1062), asserts directly that the target is
  gone.
- The same file's "a copy into the primary checkout that fails part-way is
  a refusal, not a crash, and a rerun finishes it" (about line 1042) and
  `tests/darkmem-sync/reconcile.test.mjs`'s "a write into docs/dforge that
  fails part-way ..." (about line 902) show it indirectly: their reruns
  succeed only because the empty partial file is gone.

New test in `reconcile-progress.test.mjs`, modelled on the line-1042 test
with `exclusiveOpens(t)` and a `writeFileSync` mock keyed on the second
target's descriptor:

- Before throwing `EIO`, the mock renames the target to `<target>.aside` in
  the same directory (a rename into a scratch directory could fail with
  `EXDEV`) and plants a newcomer file with other content at the target path
  through the captured original `writeFileSync`.
- `progressToLocal` refuses with "a copy into the primary checkout failed
  (EIO); ...", its details equal `[<p1 target>: copied]`, the mirror is not
  set aside, and the newcomer file is still at the target with its content.
- It fails on main: the newcomer is deleted.

`reconcile.test.mjs` gets no new test: `documentsToLocal` calls the same
`writeExclusive`, and its line-902 test guards the removal there.

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
main; the three regression guards pass.
A2. [test, high] The validation commands under Testing pass on the merged
branch.
A3. [read, high] DM 74 is `done`, DM 73 is `deferred` with the ruling in
its note; `register check` reports no errors.
A4. [test, high] Both dforge manifests read 4.2.4.

## Riskiest assumption

That `fstatSync` on the open descriptor and `lstatSync` on the path report
the same `dev` and `ino` for the same file on Linux, macOS and Windows. If
they disagree, W1 never removes anything: the new test still passes, and
only the regression guards fail. The fallback is safe, since a file left in
place is refused by a rerun as a differing copy.

- POSIX guarantees the agreement on Linux and macOS. One known exception is
  overlayfs before kernel 4.19, where `fstat` reported the underlying
  file's numbers (inference from kernel history), with the same safe
  fallback.
- On Windows, libuv's `fstat` reads the handle's index number and volume
  serial number. Its `lstat` first tries `GetFileInformationByName`, whose
  `FileId` and `VolumeSerialNumber` come without opening a handle, and
  falls back to opening one where that API is absent or the path is a
  reparse point. Both feed the same conversion, and `FileId` is documented
  as the index number (inference from libuv's source and Microsoft's
  documentation, unverified on a Windows host).
- The new test renames a file whose descriptor is open, which Windows
  allows because libuv opens files with `FILE_SHARE_DELETE` (confirmed in
  libuv's source).

The regression guards on the Windows shards check the `dev` and `ino`
agreement there; the new test checks the rename and the branch that leaves
the newcomer in place.

## Review rulings

Fable review, 2026-10-20 (commit 86e23b2, verdict: revise), all applied:

- M1, the new test cannot detect a `dev` or `ino` disagreement: the
  regression guards are named as that check (Testing, Riskiest assumption,
  A1).
- M2, W1 now states that the stat, close and removal steps swallow their own
  errors and only the write error leaves the function.
- L1 and L2, the DM 73 ruling names who can make the swap and that the move
  reports success; L3 and L4, the riskiest assumption names both libuv
  paths and old overlayfs; L5, the test's rename stays in the target's
  directory and its assertions are listed; L6, no `reconcile.test.mjs` test;
  L7, the removal stays `rmSync` and the close-first order is explained.
- The success-path `closeSync` outside the `try` is DM 75, already
  deferred.
