# darkmem mirror: resumable ledger import, absolute identities, Stop push, cockpit run errors

Date: 2026-10-14
Status: design, owner-approved row by row on 2026-10-14; revised the same day
after an independent review.
Register: `docs/superpowers/registers/2026-09-24-darkmem-mirror.md` rows 23,
24, 25 and 26. Row 6 stays `verify` and is not designed here.

**Execution strategy:** sequential — four small, file-disjoint changes plus one
release bump that touches every manifest; inline execution in one session.

## Rulings (owner, 2026-10-14)

1. **Row 23: resume, never purge.** A move stopped after an append batch
   resumes the import from where darkmem stops. Deleting darkmem's copy and
   re-importing was rejected: a move never overwrites darkmem (store-options
   spec §4). The `import` command keeps `--replace` as its recovery.
2. **Row 24: names from the roots only.** An absolute ledger identity is mapped
   to its name from known roots, as `pathToUri` does, never by searching for a
   `docs/forge` segment. An identity no root maps stays unfinished, so the move
   refuses and names it.
3. **Row 25: the Stop push runs in the background now.** No Windows measurement
   gates the decision; row 6 records the timing as an observation.
4. **Row 26: settle the engine's wording with a probe.** The engine's types
   already say `$.process.run` rejects both when the command cannot start and
   when it outlives `timeoutMs`; a probe records the two messages.

## 1. Resuming a partial ledger import (row 23)

`importLedger` (`scripts/lib/darkmem-import.mjs`) splits a ledger with
`splitAtBlankLines` then `splitAtLimit`, appends the pieces in batches of
`MAX_ENTRIES_PER_APPEND`, and closes the workstream only after the last batch.
A move killed between batches leaves an open workstream holding the first
batches. Today `checkProgressTargets` (`scripts/lib/darkmem-progress-move.mjs`)
files a ledger darkmem holds byte for byte and refuses every other existing
copy, so the next reconcile refuses this one forever.

**One splitter.** `darkmem-mirror.mjs` exports `ledgerPieces(text)` (the
`splitAtBlankLines` then `splitAtLimit` chain); `importLedger` and the
classifier below both use it, and piece lengths are measured with
`Buffer.byteLength(piece, "utf8")`. The split is deterministic, so the pieces
an earlier run sent are the first pieces of this run's split of the same bytes.

**Recognising a stopped import.** For a ledger source whose workstream exists,
`checkProgressTargets` reads darkmem's ledger text and last ledger sequence
number (`remoteLedger`) and classifies it:

- equal bytes: filed, as today;
- darkmem's bytes are a proper prefix of the local ledger, the workstream's
  `state` is not `closed`, and the prefix length equals the summed byte length
  of the first *k* pieces of `ledgerPieces(local text)` for some *k* ≥ 0:
  **partial**;
- anything else, including a closed workstream holding a prefix or a prefix
  ending inside a piece: a problem, as today
  (`darkmem already holds a different ledger for workstream <slug>`).

`checkProgressTargets` answers
`{ problems, filed, partial: Map<slug, { id, lastSeq, from: k }> }`.

The stub server holds `state` as `open` or `closed`; the real server's full
value set is not verified in this repository, so the test is "not `closed`",
matching the existing check in the move. *k* = 0 is an open workstream with no
ledger entries; its `lastSeq` is 0 because `remoteLedger` counts ledger entries
only and darkmem checks `expected_last_seq` per entry kind, an assumption
`pushLedger` already relies on.

A same-slug ledger another mirror pushed line by line can also end on a piece
boundary and classify as partial. That is accepted: its bytes are this ledger's
first bytes, so the move continues the same ledger rather than a different one.

**Resuming.** `importLedger(context, roots, ledger, resume)` takes an optional
`{ id, lastSeq, from }`. With it, the function skips the first `from` pieces and
sends each remaining batch with `expectedLastSeq` set to the last ledger
sequence number darkmem holds, starting from `lastSeq` and then taken from each
append's `last_seq` answer. A 409 (another writer appended) or a 422 (an entry
refused) records a failure in the report and stops that ledger, as a 422 does
today; the move then refuses with "darkmem refused part of the progress;
nothing was moved locally". After the last batch the workstream is closed as
before. The move calls `importLedger(…, ledger, partial.get(slug))` for every
ledger it does not hold as filed.

Everything after the import is unchanged: the read-back compares darkmem's full
text with the local bytes before anything local moves, so a resume that went
wrong refuses there. The `import` command (`importRepository`) is not changed.

## 2. Absolute ledger identities (row 24)

A ledger's identity line (`# SDD ledger — plan: <name>`) written before the
store-roots work can hold an absolute path such as
`/repo/docs/forge/plans/p.md`. `planFinished` (`scripts/lib/darkmem-reconcile.mjs`)
and `plan_finished` (`scripts/next-step`) look for a backticked spelling of the
name in the `completed.md` beside the plan. Two things fail for an absolute
name:

- its only spelling is the absolute path, while `completed.md` records the
  relative `docs/forge/…` or `docs/superpowers/…` name, so it never matches;
- `completed.md` is read beside the absolute path (`planFile` and
  `forge_resolve` pass an absolute name through), and that directory is gone
  once the documents family has moved: reconcile moves documents before
  progress and stages `git rm -r` of the docs directory, so the progress move's
  `inProgressReason` cannot read it.

**The rule, in both languages: map first, then locate.** An absolute name is
mapped to a relative name, and both the spelling and the `completed.md`
location then come from the mapped name, through `planFile` /
`forge_resolve`, which read the docs root in use. Only an unmappable name keeps
reading beside its absolute path. The bases, in order:

1. the docs root in use (the mirror's `superpowers/` while documents are in
   darkmem), and the checkout's `docs/forge` and `docs/superpowers`: the docs
   name plus the path below;
2. the checkout's top level: the path below it;
3. the same two for the primary checkout (`cfg.repoRoot` in JS, the
   `git-common-dir` top in bash), because a worktree cut while a ledger
   existed holds a copy whose identity points into the primary.

A name under none keeps its absolute spelling, never matches, and the move
refuses naming it. No segment search is ever done.

- **JS.** A helper beside `planFile` applies the bases with `path.relative` on
  resolved paths, retrying once with `fs.realpathSync` of the name (as
  `forge_name` retries the physical path). On Windows `path.win32.relative`
  compares case-insensitively.
- **Bash.** `plan_finished ROOT NAME` passes NAME through `forge_name NAME ROOT`
  only when NAME is absolute (`/*`, `[A-Za-z]:/*`, `[A-Za-z]:\\*`); a relative
  name is untouched, since `forge_name` makes an existing relative name absolute
  (row 22). `_forge_name_of` gains the primary checkout's bases. Bash compares
  the `cygpath -m` forms verbatim, so a drive-letter case difference does not
  map; row 6's Windows run shows whether that occurs.
- **next-step.** `plan_finished` is called on a register row's Assigned cell.
  The same absolute-to-name mapping is applied before the `forge_name_key`
  comparison with the plan being completed (`next-step` near line 282), so an
  absolute Assigned cell naming that plan is stale, not routed back to it.

## 3. The Stop push in the background (row 25)

`turn-end.sh` runs `darkmem_push_quietly` first, synchronously, with a 100 s
bound, inside a hook whose `timeout` in `hooks/hooks.json` is 120 s. The rest of
the hook (an unbounded `auto-run … pending` call, the transcript scan, the
decision) runs after it. A slow darkmem delays every turn's end, and a push near
its bound can run the hook past 120 s, which kills it and loses its block
decision.

**Change.**

- A new script, `scripts/darkmem-stop-push.sh`, reads the Stop payload
  (`session_id`, `cwd`; no `jq` or no session id means no push, as in
  `turn-end.sh` today), sources `scripts/lib/darkmem-hook.sh` and calls
  `darkmem_push_quietly`. It prints nothing and exits 0 whatever happens.
- It bounds the whole push itself: where GNU `timeout` exists `_darkmem_run`
  already does; elsewhere (macOS) the script runs the push in the background
  and kills it after 100 s. The comment in `darkmem-hook.sh` that says "the
  hook's own timeout bounds it" is reworded, and `darkmem_push_quietly`'s
  comment no longer says its stdout is a decision.
- `hooks/hooks.json` lists it as a second command hook in the Stop group with
  `"async": true` and no `timeout`; `turn-end.sh` stays first, synchronous,
  `timeout` 120.
- `turn-end.sh` no longer sources the library or pushes; the comment above the
  push call goes, and its header is unchanged.

What the hooks reference (https://code.claude.com/docs/en/hooks.md, read
2026-10-14) says about async command hooks, and what follows:

- Claude Code starts the process and continues without waiting, and all
  matching hooks run in parallel, so `turn-end.sh`'s decision no longer waits
  on darkmem.
- An async hook's `decision` has no effect; the push decides nothing.
- Claude Code does not enforce `timeout` on an async command hook, hence the
  script's own bound.
- In a `-p` run, Claude Code cancels an async hook still running at teardown;
  for an interactive exit the docs do not say. A push cut short is the case
  darkmem-sync already handles for a killed or timed-out push: ledger appends
  carry `expected_last_seq`, `darkmem-push.mjs` reconciles a 409 against
  darkmem's copy, and the next push sends the rest.

**The mirror lock.** `darkmem-sync` refuses, with exit 1, when another run holds
the mirror lock (`darkmem-sync.mjs`, `acquireLock` returning null); nothing
waits. Once the Stop push runs in the background, a skill's explicit push at a
stop point can start while it still holds the lock. *Pending owner ruling;
recommended:* `push` (only `push`) waits for the lock, retrying once a second
for up to 100 s, the Stop push's own bound, before refusing as today.
`reconcile`, `pull` and the other commands keep refusing at once.

Prose naming the Stop hook as a pusher (`README.md` darkmem section,
`reference/project-state.md` sync points, the `hooks.json` description) stays
true; `README.md`'s test list adds the push script's test. The Codex manifest
declares no hooks and is unaffected.

## 4. How the cockpit reads a failed run (row 26)

`readRoots` (`hooks/cockpit/register.tsx`) runs
`node scripts/lib/darkmem-config.mjs --mode <primary>` with a 5 s timeout. The
engine's types (`claude-code.d.ts`, Claude Code 2.1.296, `process.run`) state
that `run` resolves `{ exitCode, stdout, stderr }` for any exit code and rejects
when the command cannot start or is still running at the timeout. So:

- the resolved branch's `exitCode !== 127` guard can never see 127 from a
  missing `node` (there is no shell); it is removed. The `NO_NODE` stderr test
  on a resolved run stays;
- a rejection is a missing `node`, a timeout, or another engine refusal, and
  today the elapsed time decides whether it was a timeout.

**Probe.** A throwaway mod, run in a nested session with no model turn (a fresh
`CLAUDE_CONFIG_DIR` in the scratchpad, `--plugin-dir <probe>`), handles
`session.start`, calls `$.process.run(['dr-forge-no-such-command'])` and
`$.process.run(['sleep', '10'], { timeoutMs: 500 })`, and writes each
rejection's name, `code` and message to a file with `$.fs.write`. The probe is
not committed; its two messages and the Claude Code version are quoted in row
26's note.

- If the timeout rejection carries a timeout wording the missing-command one
  does not, `readRoots` sets the "gave no answer within 5 seconds" note only
  for a rejection matching that wording, loosely (a word, not the full
  message); every other rejection, `ENOENT` included, sets no note. The
  `$.clock.now()` elapsed-time check and its comment are removed. A later
  engine wording that no longer matches falls back to silence.
- If not, the elapsed-time check stays, its comment cites the probe, and the
  row closes as "the engine does not distinguish".

## 5. Testing

- **Row 23** (`tests/darkmem-sync/reconcile-progress.test.mjs`, stub server):
  a ledger longer than one batch whose first batch alone sits on an open
  workstream moves, ends closed, and reads back byte-identical; the *k* = 0
  case moves; a closed workstream holding a prefix, a prefix ending inside a
  piece, and a non-prefix each refuse with nothing moved; a 409 during the
  resumed append refuses with nothing moved locally. `ledgerPieces` is covered
  in `mirror.test.mjs`.
- **Row 24** (`tests/darkmem-sync/reconcile.test.mjs`, `tests/next-step.test.sh`,
  `tests/roots.test.sh`): documents applied darkmem, the checkout's `docs/forge`
  absent, identity `<checkout>/docs/forge/plans/p.md`, the mirror's
  `completed.md` recording it: the move runs; an identity into the primary read
  from a worktree's copy: the move runs; an absolute identity under a path no
  root maps: the move refuses and names it; `next-step` reports an absolute
  Assigned cell naming a finished plan, or the plan being completed, as stale;
  a relative name is unchanged by `plan_finished`.
- **Row 25** (`tests/darkmem-sync/hooks.test.mjs`, `tests/turn-end.test.sh`):
  the test that asserts `turn-end.sh` appends to darkmem is rewritten to run
  `darkmem-stop-push.sh`; `turn-end.sh` with darkmem configured makes no
  darkmem request; the push script prints nothing; the hooks.json check
  asserts `Stop[0].hooks[0]` is `turn-end.sh`, synchronous with `timeout` 120,
  and `Stop[0].hooks[1]` is the push script, `async` true with no `timeout`;
  an explicit push started while another holds the lock waits and then
  succeeds, and one that outwaits the bound refuses as today.
- **Row 26** (`tests/cockpit.test.ts`): the existing "fails at once without
  naming node" rejection stays silent; a rejection shaped like the probe's
  timeout message shows the note and one shaped like its missing-command
  message does not, whatever the elapsed time; a resolved non-zero exit still
  shows its first stderr line.
- Repository validation as `CLAUDE.md` lists it.

## Delivery

One plan, sequential, inline: rows 24, 23, 25, then 26 (the probe first), then
the release bump, which moves both dr-forge manifests and the version pinned in
`tests/review-route.test.sh` (row 32). Row 6's Windows check runs on the pull
request that carries this work and the local commits before it; opening that
pull request waits for the owner's go-ahead.

## Not in scope

- Row 20's other half (sync roots pointing into the working tree) and row 22's
  other hazards.
- Resuming a stopped `import` command run.
- Measuring the push on Windows (row 6).
