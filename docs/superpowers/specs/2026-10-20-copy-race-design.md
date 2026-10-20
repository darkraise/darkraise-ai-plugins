# Copy race in the mirror moves

**Execution strategy:** sequential — two small edits that share their
refusal wording; a merge would cost more than parallel saves

**Registers:** `docs/superpowers/registers/2026-09-24-darkmem-mirror.md`
(DM 68); this spec is added to its `**Covers:**` line

**Approach:** inline - skip 1: the row names the fix, and the owner approved
the design as presented on 2026-10-20

## Decisions

The owner's answers on 2026-10-20.

1. DM 68 is fixed at both sites by writing a buffer read without following
   links, with an exclusive create.
2. DF 21 (`docs/superpowers/registers/2026-10-11-dr-forge.md`) closed `done`
   without a Windows run, in 1301340; it is not part of this work.
3. Sequential execution.
4. The design, its refusal wording and the skip of an identical destination
   approved as presented.

## Problem

Both mirror-to-checkout moves open a file a second time after checking it,
with `fs.copyFileSync`, which follows links and blocks on a named pipe:

- `progressToLocal` (`scripts/lib/darkmem-progress-move.mjs`, about line
  654) has already read the mirror's `item.file` into `item.buffer` through
  `readNoFollow`, then copies from `item.file` again. A link swapped in
  between is read through; the read-back after the loop catches it only after
  the write. A named pipe hangs reconcile. The target side is safe today:
  `COPYFILE_EXCL` creates exclusively.
- `documentsToLocal` (`scripts/lib/darkmem-reconcile.mjs`, about line 572)
  copies with no flag after the killed-run comparison. At `dest` it follows a
  link out of the repository, truncates what stands there, and blocks on a
  named pipe. The source is reopened the same way, and no buffer was kept:
  the listing stored only `fileHash(file)`.

Adjacent, same loop: `documentsToLocal` has no `try` around its copies, and
`reconcile` (about line 647) rethrows anything but a darkmem transport or
HTTP error, so `EIO`, `ENOSPC` or `EACCES` part-way crashes reconcile instead
of refusing as `progressToLocal` does.

Code paths are relative to `plugins/dforge/`.

## Design

### C1. `progressToLocal`

1. The copy becomes `fs.writeFileSync(item.target, item.buffer, { flag:
   "wx" })`. The source is not reopened.
2. Unchanged: the `EEXIST` branch ("`<target>`: changed during the move; not
   overwritten"), the catch-all refusal "a copy into the primary checkout
   failed (`<code>`); the files copied so far stay, and a rerun copies the
   rest", and the read-back check after the loop.

### C2. `documentsToLocal`

1. The killed-run comparison also collects the destinations that exist and
   are equal to their source into a set; the copy loop skips them. A skipped
   file is not listed as copied.
2. For every other file, inside one `try` around the loop:
   1. `buffer = readNoFollow(file)`.
   2. `sha256(buffer) !== hash` stops the loop and refuses with reason "the
      mirror changed during the move; nothing more was copied"; its details
      are "`<name>`: the mirror's copy changed after darkmem confirmed it",
      then any "changed during the move" lines recorded before it.
   3. `fs.writeFileSync(dest, buffer, { flag: "wx" })`. `EEXIST` records
      "`<name>`: changed during the move; not overwritten" and continues;
      after the loop any such line refuses with reason "docs/dforge changed
      during the move; nothing was overwritten".
3. Any other error in the loop refuses with reason "a copy into docs/dforge
   failed (`<code>`); the files copied so far stay, and a rerun copies the
   rest". A source swapped for a link fails `readNoFollow` with `ELOOP`, one
   swapped for a named pipe or directory with `EFTYPE` or `EISDIR`; all reach
   this refusal.
4. Every refusal in C2 ends its details with "`<name>`: copied" for each
   file written in this run, leaves the mirror in place and keeps the sync
   state, so a rerun's killed-run comparison takes the copies as equal and
   finishes the move.
5. Unchanged: the `fileHash(dest)` read-back after the loop.

## Testing

Suites in `tests/darkmem-sync/`. Each race is forced with `t.mock.method(fs,
…)`, as the suites already do; `mkdirSync` just before the write is the
injection point used in `reconcile-progress.test.mjs` (about line 999). A
failing-first test must fail, not hang: a test that would block on a named
pipe before the fix uses a symbolic link instead.

`reconcile-progress.test.mjs`:

- The three tests that intercept `copyFileSync` (about lines 1014, 1030 and
  1147) intercept `writeFileSync` for the target path instead; their
  assertions do not change.
- New, skipped on Windows: the mirror's `item.file` is replaced by a link to
  an outside file with other content after the read. The move succeeds and
  the target holds the mirror's original content. Fails before the fix (the
  read-back refuses).

`reconcile.test.mjs`:

- A file that lands at `dest` before the write: the "docs/dforge changed
  during the move" refusal, the landed content kept, earlier files listed as
  copied.
- A link at `dest`, created after the comparison, to an outside file, skipped
  on Windows: the outside file is unchanged and the move refuses with the
  "docs/dforge changed during the move" refusal. Fails before the fix (the
  copy writes through the link).
- A mirror source edited after it was hashed: the "mirror changed" refusal.
- A mirror source replaced by a link after it was hashed, skipped on
  Windows: the "failed (ELOOP)" refusal.
- A write that fails with `EIO` part-way: the "failed (EIO)" refusal with
  the copied list, then a rerun with the mock removed moves.
- A `dest` equal to its source from a killed earlier run: not written again
  (no `writeFileSync` call for it), and the move succeeds.

After the change: `node scripts/test-all.mjs`, `node
scripts/validate-repository.mjs`, `claude plugin validate` on the marketplace
and every Claude plugin, and `claude plugin test plugins/dforge`, each with a
timeout and nothing left running.

## Release

Version 4.2.3 in `plugins/dforge/.claude-plugin/plugin.json` and
`plugins/dforge/.codex-plugin/plugin.json`. Register bookkeeping through
dr-superpowers:finishing-a-development-branch closes DM 68.

## Acceptance

A1. [test, high] C1 and C2 behave as written and every new test passes; the
two failing-first tests fail on main.
A2. [test, high] The validation commands under Testing pass on the merged
branch.
A3. [read, high] DM 68 is `done`; `register check` reports no errors.
A4. [test, high] Both dforge manifests read 4.2.3.

## Riskiest assumption

That `open` with `O_CREAT | O_EXCL`, which `{ flag: "wx" }` uses, fails with
`EEXIST` on an existing symbolic link (dangling or not) or named pipe without
following or opening it. POSIX specifies this; the `dest` link test is the
check on this host. A written file takes the default mode rather than the
mirror file's mode, which `copyFileSync` copied; documents are never
executable, and git records nothing else.
