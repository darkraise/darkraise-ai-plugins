# Next-session routing that matches the repository

**Execution strategy:** sequential — inline execution
**Depth:** standard — interface

## Decisions

- Process: architectural, depth standard — triggers `interface` (next-step
  gains modes that the cockpit, the Stop hook and several skills consume),
  `approach` (how a programme spec's rows route), `intricate`.
- Fix order, from the Fable review of the first proposal
  (`.dforge/handoff-routing-fix-review-report.md`, 2026-11-16): router first,
  then a read-only next-step mode with the completed.md and cross-worktree
  ledger checks, then the plan-less mode in closing-a-milestone and handoff,
  then the readers, then the Stop hook. Owner: "yes" to brainstorming the spec
  in that order.
- Approach. Asked: "where should the correct next step come from?" Answer:
  **"Recompute on read (Recommended)"** — a read-only next-step mode, and the
  cockpit band, repo-audit, project-status and resume-execution recompute
  from the repository instead of trusting latest.md. Rejected: fixing writers
  and only withdrawing stale offers; dropping the stored Next line entirely.
- Register row 11 (darkmem checkpoint). Answer: **"Reproduce, then fix
  (Recommended)"** — a test reproduces it first; fix only on a failing test,
  else close the row as not reproduced.
- Carried from the review, not re-asked: the Stop hook keeps holding once per
  reason; an epic row assigned to a spec is never reassigned to a plan (the
  roadmap finds requirement registers through that cell,
  `scripts/lib/roadmap.sh:76-93`); the auto-run switch keeps its plain
  `next-step PLAN_FILE` call (`ar_switch` needs the plan in the prompt,
  `scripts/lib/auto-run.sh:488-490`).
- Spec review, built rows (the Blocker). Answer: **"Step 2 asks next-step
  (Recommended)"** — step 2 takes its go or stop from
  `next-step --print --project`; step 7 sets built rows to `done` with the
  `verify` rows (§4).
- Spec review, A10. Answer: **"Hide it (Recommended)"** — a superseded draft
  or unplanned block exits 6 (§2).
- Spec review, A16. Answer: **"This turn's change only (Recommended)"** — the
  transition hold fires only on this turn's own change (§5).
- Spec review approval: **"Approve and run unattended"**.

Early CI: none

Finish: merge

Worktree: in-place

## Problem

Register `docs/dforge/registers/2026-11-16-next-session-routing.md` rows 1-12.
In short: `latest.md`'s `## Next session` block is computed once, by whichever
session last ran `scripts/next-step`, and then trusted for days by the cockpit
band, repo-audit, the compaction snapshot and resume-execution. Several
transitions never rewrite it (milestone close, a finishing turn that skips
Step 7, a dead session), and the router itself answers wrongly for specs that
already have plans: on darkpanel, `next-step --complete` says
"`…v1-completion-design.md`: write its plan" for a spec with 25 plans. The Stop
hook only checks turns that wrote a ledger, and accepts any message containing
`## Next session`.

## Design

### 1. Router: a spec's plans decide its rows (rows 3, 10)

The register router at `scripts/next-step:294-401` moves into a function in a
new `scripts/lib/route.sh`, used by `--complete` and by the new `--project`
mode, unchanged except as below.

`spec_plans ROOT SPEC` (same file) prints every plan whose header `**Spec:**`
or `**Program:**` line names SPEC, compared by name key, over the plan
directories of every place `_plan_roots` lists. One awk pass reads all
headers; it strips `\r` itself and resets its fence state per file
(Windows Git Bash, `reference/ci-parity.md`).

Both a row assigned to a plan and rule 2 below find a plan's ledger with
§2's cross-worktree lookup, not only this checkout's (`scripts/next-step:357`
reads only this checkout today).

A row assigned to spec S (an existing file with no tasks) routes by S's plans:

1. **No plan names S:** writing-plans, as today.
2. **A plan naming S, other than the plan `--complete` is completing, is not
   in completed.md:** route to that plan, as a row assigned to a plan routes.
   This rule applies only when completed.md exists and that plan's filename
   date is not older than the index's first entry. Otherwise the row is listed
   as "plans exist, outcome unrecorded" and routes neither to execution nor to
   writing-plans. Among several live plans: the lowest `sub-project <k>` on its
   Program line, else the oldest filename date. The Next line adds: "if it was
   abandoned, record it in completed.md or delete it."
3. **Every plan naming S is finished, and the row's register covers S:**
   writing-plans for a follow-up plan:
   "`S`: write a follow-up plan for rows #a, #b with dforge:writing-plans."
4. **Every plan naming S is finished, and the row's register does not cover
   S** (an epic row): never writing-plans. The row is listed as built and
   joins the `verify` rows for the milestone branch (`scripts/next-step:373-377`):
   with nothing concrete open, the current milestone goes to its audit, which
   §4 lets these rows pass. With no roadmap, the router falls through to the
   Program-line branches (`:405-414`) as if no row were open.

Finishing Step 5b runs `scripts/roadmap settle --spec` for the plan's
`**Spec:**` and, when it has one, its `**Program:**` spec: an early settle
only, since rule 4 and §4 are what close row 10 (darkpanel's plans carry no
Program line). `roadmap settle` keeps an existing note and prefixes its own,
instead of replacing it (`scripts/roadmap:342`, `scripts/register:159`).

project-status rules 6 and 7 become one rule: run
`scripts/next-step --print --project` (with `--host codex` on Codex) and
recommend what its Next line names. `skills/project-status/SKILL.md:11-12`
changes from "never calls `scripts/next-step`" to "calls it only with
`--print`". Open items still list every register.

### 2. next-step modes (rows 5, 6)

- **`--print`** combines with a plan, `--complete`, `--kept`, `--project` and
  `--latest`. It prints the block and changes nothing: no latest.md write, no
  file or directory created (no lock, no handoff directory), no finish.json
  delete, no in-flight check (so never exit 5).
- **`--project`**: no plan. With a current milestone, it routes that
  milestone's registers only (`roadmap_unresolved`); Status
  `Project: milestone M<n> (<name>) is current.` With every milestone closed,
  or no roadmap, it routes every register under `<docs>/registers/` with an
  unresolved row; Status `Project: every milestone is closed.` or
  `Project: no roadmap.` Nothing open: the milestone audit when a milestone is
  current, else `**Next:** Nothing — no register holds an unresolved row.`
  with no launch. It replaces latest.md wholesale, as `--complete` does;
  `--keep-notes` (used by handoff step 4) replaces only the `## Next session`
  section. Takes `--host`.
- **Plain `PLAN_FILE`:**
  - a plan listed in completed.md (`plan_finished`) is answered as
    `--complete PLAN_FILE`, with its side effects in write mode and none under
    `--print`. An auto run's finish entry runs before Step 5b, so it is
    unaffected; after 5b, `auto-run clear` refuses (exit 4) and the run stops
    rather than restarting at Task 1.
  - with no ledger for it in this checkout, `dforge_ledger_files` is searched
    for a ledger whose plan line names it. The found ledger's checkout replaces
    the current one in `plan_final_review_state` and in the "First enter the
    existing worktree `<checkout>`" sentence. Under darkmem progress that
    checkout is the worktree holding `<state>/sdd/<slug>`.
- **Marker.** Every latest.md write adds one last line to the `## Next session`
  section, never to the printed block:
  `<!-- next-step: kind=<plan|complete|kept|project|draft|adhoc> [branch=<name>] done=<completed.md entries> closed=<closed milestones> subject=<name or -> at=<epoch seconds> -->`.
  `branch=` appears for `kept` only. `subject=` runs to the last ` at=`, so a
  name may hold spaces.
- **`--print --latest`** reads latest.md's block and marker and recomputes:
  - `plan`: `--print PLAN`; but when the stored Status line counts completed
    tasks and no ledger for the plan is found in any worktree, exit 6 with
    "the ledger is gone and the plan is unrecorded" on stderr, so a recompute
    never moves a plan backwards to Task 1;
  - `complete`: `--print --complete PLAN`;
  - `kept`: the stored block stands; `--print --complete PLAN` once the plan
    is in completed.md; exit 6 when the branch is gone or is an ancestor of the
    primary checkout's HEAD;
  - `project`: `--print --project`;
  - `draft`, `adhoc`: the stored block stands unless superseded, then exit 6.
    Superseded means completed.md now holds more entries than `done=`, or more
    milestones are closed than `closed=`, or, for a draft, a plan names the
    draft as its `**Spec:**`. Counts, not mtimes, so a pull, a clone or a new
    worktree does not supersede a valid block.
  - no marker (written before this change): the stored block stands, and the
    output ends with `kind=none at=<latest.md mtime>`.
  - It ends its output with the marker line it used, so readers take the age
    from `at`. Exit 6: nothing to resume. A missing latest.md or one without a
    `## Next session` section exits 6. A sub-mode's exit 2 or 3 passes through
    with its message. `--latest` without `--print` is a usage error.
- **Snapshot:** `snapshot_latest` (`scripts/lib/snapshot.sh:43`) strips the
  marker line and takes the age from `at`.

### 3. Readers recompute (rows 4, 9)

- **Cockpit** (`hooks/cockpit/register.tsx` `readResumeOffer`): runs
  `bash <root>/scripts/next-step --print --latest` with `$.process.run`, a
  20-second timeout, and the session's checkout as cwd, or the primary
  checkout when that directory no longer exists. `readRun` never awaits it: one
  run at a time, started detached, applied when it resolves. It is skipped
  while the offer cannot show (plan session, active auto run, dismissed, older
  than three days). It runs again only when the cache key changes: the mtimes
  of latest.md, completed.md, roadmap.md, each register file, the plans
  directory, and the subject plan's file. The subject plan's ledger is left
  out on purpose: during a plan session the offer is hidden anyway.
  - Exit 0: parse the block with `resumeOfferOf`, age from the marker's `at`.
  - Exit 6: clear the offer.
  - Failure or timeout: today's read of latest.md, `hasUnresolvedRows` check
    included, and the band marks the line "not rechecked".
  - The dismissal and the three-day window key on `at`, so editing the notes
    no longer restarts them.
- **repo-audit** `## Handoff`: runs `--print --latest` bounded by
  `scripts/with-timeout` (20 s). Exit 0 prints its `**Status:**` and `**Next:**`
  lines under "recomputed from the repository". Exit 6 prints
  `- nothing to resume (the stored block is superseded)`. Any other outcome
  prints the stored lines labelled "stored, not recomputed: <first error
  line>".
- **resume-execution** step 5 continues with the Next line of
  `scripts/next-step --print PLAN_FILE`, not latest.md's.

### 4. Skills that must end on a block (rows 2, 6, 10, 12)

- **closing-a-milestone:**
  - Step 2 takes its go or stop from `scripts/next-step --print --project`:
    when it names this milestone's audit, the unresolved rows are `verify` or
    built (§1 rule 4) and the audit continues with both; otherwise the skill
    reports the rows, runs `scripts/next-step --project`, and ends on its block.
  - Step 6's GAP stop runs `scripts/next-step --project` and ends on its block.
    Step 6's UNVERIFIABLE question and step 7's sign-off stay questions.
  - Step 7 sets the built rows to `done` together with the `verify` rows, so
    `roadmap close` accepts the milestone (`scripts/roadmap:307-311`).
  - Step 9 runs `scripts/next-step --project` and ends on its block.
- **handoff** step 4 gains the form "Between plans on a roadmap or register
  project: `scripts/next-step --project --keep-notes`", preferred over
  `--adhoc` there.
- **Codex:** `skills/using-dforge/SKILL.md` and `references/codex-tools.md`
  say to print the next-step block at every step a skill says to end on it,
  not only on early stops. Codex has no Stop hook, so this text is its only
  guard.

### 5. Stop hook (rows 2, 7, 8)

In `scripts/turn-end.sh`, with hold-once kept:

- **Removed checkout:** when `git -C <cwd>` fails, read line 1 of
  `$stamp.refs` (the common git directory turn-start recorded) and use its
  primary checkout, for the auto-run lookup (`scripts/turn-end.sh:53`) as well
  as the root. Exit silently only when that also fails. turn-start keeps the
  previous first line of `$stamp.refs` when `turn_refs` fails, so the fallback
  lasts past one turn.
- **Transition trigger:** runs before the `[ -d "$sdd" ]` exit
  (`scripts/turn-end.sh:60`) and joins the early exit at `:100-103`. When no
  ledger hold applies, it holds once if this turn itself changed completed.md
  or roadmap.md of the docs root:
  - the file is newer than the turn stamp (`[ -nt ]`), and latest.md is not
    newer than the file;
  - and the change is this turn's: the file is dirty, or its newest commit is
    at or after the turn stamp;
  - and for roadmap.md, more milestones are `closed` than at the turn-start
    head recorded in `$stamp.refs`.
  - With documents in darkmem, the mtime test alone applies.
  The reason names `next-step --complete <plan>`, where `<plan>` is the
  completed.md line added since the turn-start head (else its last line), or
  `next-step --project` for roadmap.md. The trigger stands down for running
  background work (`:126-138`), a queued notification (`:179`), a bound auto
  run, and the finishing endings at `:86-87`.
- **Release rule:** a held turn's ending counts only when latest.md was
  rewritten this turn and the message contains its `**Next:**` line. A message
  with a line reading exactly `## Next session` also counts when latest.md
  cannot be written: the file exists and is not writable, or it is absent and
  its nearest existing parent is not writable. The hook tests that itself.
  This replaces the substring test at `scripts/turn-end.sh:86` and `:90`, and
  the same helper serves `scripts/ui-turn-end.sh:52`. The finishing-menu
  endings stay as they are.
- **Another worktree's ledger:** not built here. The premise (a hook cwd that
  differs from the ledger's worktree) is unconfirmed, and sessions that enter
  a worktree natively already give the hook its cwd
  (`tests/turn-end.test.sh:363-366`). Register row 13 defers it until one
  logged stop shows the case. Another session's ledger never holds this turn
  (A19).

### 6. darkmem checkpoint (row 11)

First a test feeds `darkmem-push` a latest.md written by `next-step --complete`
(no `## State`). Reading says it will be refused
(`scripts/lib/darkmem-push.mjs:402-406`, `scripts/lib/darkmem-mirror.mjs:759-763`),
so the plan budgets the fix. Then:

- `kind=complete` and `kind=project` file the checkpoint under the `project`
  workstream, not the finished plan's: `closeFinished` closes that workstream
  in the same push (`scripts/lib/darkmem-push.mjs:353-363`), and a pull reads
  only open workstreams (`scripts/lib/darkmem-pull.mjs:226-247`).
- For those kinds the marker outranks a `## State` section, so stale notes do
  not decide the workstream.
- `checkpointTarget` is shared with `scripts/darkmem-progress-move.mjs:294`;
  that caller keeps its current behaviour.

If the test passes unchanged, row 11 closes as not reproduced. The band's
dependence on a pulled file's mtime goes away with the marker's `at` either
way.

## Acceptance

A1. [test, neg, high] When a register row is assigned to spec S and a plan whose `**Spec:**` names S is not in completed.md (and completed.md exists, its first entry no newer than the plan's date), `next-step --complete` and `--project` route to that plan and never print "write its plan".
A2. [test, high] When no plan names spec S, a row assigned to S still routes to dforge:writing-plans.
A3. [test, high] With every plan naming S in completed.md, an epic row assigned to S in a milestone register that does not cover S, and nothing else open, the block routes to closing that milestone.
A4. [test, high] With every plan naming S finished and an open row in a register that covers S, the block asks for a follow-up plan for that row's id.
A5. [test, high] A plan whose `**Program:**` line names S counts as a plan of S exactly as a `**Spec:**` line does.
A6. [test, neg, high] `next-step --print` in every mode leaves latest.md and finish.json byte-identical with unchanged mtimes, creates no file or directory, and never exits 5.
A7. [test, high] `next-step --project` prints the milestone-audit block when the current milestone has only `verify` or built rows, and prints "Nothing" with no launch when there is no roadmap and no unresolved register row.
A8. [test, high] Plain `next-step PLAN` for a plan listed in completed.md prints the same Next line as `next-step --complete PLAN`.
A9. [test, high] Plain `next-step PLAN` run in the primary checkout, with the plan's ledger only in a linked worktree, reports that ledger's progress, reads its final review against that worktree, and names that worktree.
A10. [test, confirmed] An `adhoc` or `draft` block followed by one more completed.md entry or closed milestone than its marker records makes `next-step --print --latest` exit 6.
A11. [test, high] latest.md written by next-step carries the marker with kind, counts, subject and `at`; the printed block does not contain it; the auto-run switch and clear still read the first prompt and launch from it.
A12. [test, high] The cockpit band shows the recomputed Next line and prompt, hides the offer on exit 6, falls back to the stored block with its register check and a "not rechecked" mark when the run fails or times out, and takes its age from the marker, so editing the notes does not reset a dismissal.
A13. [test, neg, high] The cockpit does not run next-step while the offer cannot show, never more than one run at a time, never awaited by the tool-call path, and not again while its cache key is unchanged.
A14. [test, high] repo-audit's Handoff section prints the recomputed Status and Next lines; on exit 6 it says nothing is to resume; on any other failure or timeout it prints the stored lines labelled as not recomputed.
A15. [test, high] A turn whose cwd worktree was removed, which committed a new completed.md line and ends on a summary, is held once, and the reason names `next-step --complete` with that plan.
A16. [test, neg, confirmed] A turn whose own commit closes a milestone in roadmap.md and ends without the block is held once naming `next-step --project`, and the retry passes; a turn where roadmap.md or completed.md moved only through a pull is not held.
A17. [test, neg, high] A first stop of a ledger or transition turn whose message contains `## Next session`, while latest.md is writable and not newer than the turn stamp, is held.
A18. [test, neg, high] A turn that changed no ledger, completed.md or roadmap.md is not held by the ledger or transition rules.
A19. [test, neg, high] Another session's ledger written during the turn never holds it (`tests/turn-end.test.sh:421-424` keeps passing).
A20. [demo, high] closing-a-milestone's step 2 stop, step 6 GAP stop and step 9, the handoff skill's between-plans form, resume-execution step 5, project-status's next-step rule and the Codex guidance say what §3 and §4 state.
A21. [demo, high] finishing Step 5b runs `roadmap settle` for the plan's Program spec as well as its Spec.
A22. [test, high] A latest.md written by `next-step --complete` or `--project` is pushed as a checkpoint under the `project` workstream, and a second mirror's pull receives it.
A23. [test, high] With two live plans naming S, rule 2 picks the one with the lower `sub-project <k>`, else the older filename date.
A24. [test, high] Without completed.md, or for a plan dated before its first entry, a row assigned to S with plans that are not indexed is listed as "plans exist, outcome unrecorded" and routes neither to execution nor to writing-plans.
A25. [test, high] `next-step --print --latest` on a latest.md with no marker prints the stored block and ends with `kind=none`.
A26. [test, high] A draft block whose draft a plan now names as its `**Spec:**` makes `--print --latest` exit 6.
A27. [test, high] A `kept` block stays as stored while its branch is unmerged, becomes the `--complete` block once the plan is in completed.md, and exits 6 once the branch is gone or merged into the primary checkout's HEAD.
A28. [test, neg, high] A `plan` block whose Status counts completed tasks, for a plan with no ledger anywhere and no completed.md entry, makes `--print --latest` exit 6 rather than print "Start at Task 1".
A29. [test, high] When latest.md cannot be written, a message with a line reading exactly `## Next session` releases a held turn.
A30. [test, high] On a fixture shaped like darkpanel M5 (epic rows `doing` and `open`, assigned to a spec whose plans are all indexed), after step 7 sets the built and `verify` rows to `done`, `scripts/roadmap close M<n>` succeeds.
A31. [test, neg, high] `roadmap settle` keeps a row's existing note and prefixes its own.

## Riskiest assumption

A milestone the router sends to its audit can pass closing-a-milestone step 2
and `roadmap close`. On darkpanel today it cannot: M5's epic rows are `doing`
and `open` (`/root/repositories/darkpanel/docs/dforge/registers/2026-10-17-m5-tailscale.md:8-11`),
step 2 stops on them and `roadmap close` refuses them
(`scripts/roadmap:307-311`). §4's step 2 and step 7 changes are the answer:
unverified — the plan's first task verifies it, by running the new
`--print --project` on a clone of darkpanel, then setting the rows step 7
would set, then `scripts/roadmap close M5` on the clone.

Second: recomputing on read is cheap enough. Evidence, 2026-11-16, Linux, a
clone of darkpanel (1,118 register lines, 25 programme plans):
`next-step --complete` 1,953 ms, plain `next-step PLAN` 563 ms. The cockpit
never waits on it and falls back on a 20-second timeout. The plan records one
Windows Git Bash figure from a CI shard log, for a generated fixture of 1,000
register rows and 25 plans, against a 10-second budget.

## Register

`docs/dforge/registers/2026-11-16-next-session-routing.md`: rows 1-2 are the
owner's report and close with the rest; row 3 → §1; rows 4, 9 → §3; row 5 →
§2; row 6 → §2, §4; rows 7, 8 → §5; row 10 → §1, §4; row 11 → §6; row 12 → §4;
row 13 (deferred) → §5.

## Review rulings

Fable, spec review round 1 (`.dforge/spec-review-2026-11-16-next-session-routing-design-1-report.md`):

- Decisions conformance and the earlier review's fixes: confirmed; four dropped items restored (worktree premise, narrow match, no design-turn holds, settle note overwrite).
- Riskiest assumption: the closing-a-milestone path first, cost second with a Windows figure.
- Row 11: the refusal will reproduce by reading; the plan budgets the fix.
- Rule 2: applies only with completed.md and a plan not older than its first entry; otherwise "outcome unrecorded".
- Rule 2 and plan-assigned rows use the cross-worktree ledger lookup.
- Cross-worktree ledger: its checkout replaces the root in the final-review state and the worktree sentence; darkmem case stated.
- Plain PLAN in completed.md: `--complete`'s side effects in write mode only; safe for auto runs.
- `kept`: never recomputed with `--kept`; `branch=` in the marker; `--complete` once indexed; exit 6 when the branch is gone or merged.
- `--project` scope: current milestone only; every register when all are closed.
- `--print --latest` edges: missing file or section exits 6; sub-mode exits pass through; `--latest` needs `--print`; no marker prints `kind=none`.
- Marker grammar: `subject=` runs to the last ` at=`.
- Cockpit: detached, one run at a time, skipped while hidden; `hasUnresolvedRows` kept for the fallback.
- Cockpit cwd: the primary checkout when the session's directory is gone.
- repo-audit: a labelled stored-lines fallback for other failures.
- Snapshot: strips the marker, ages from `at`.
- project-status: its "never calls next-step" line allows `--print`; `--host codex` on Codex.
- Transition trigger placement: before the `sdd` exit; stands down for background work, queued notification, auto run, finishing endings.
- Removed checkout: the fallback root serves the auto-run lookup too.
- Release rule: "cannot be written" defined.
- Another worktree's ledger: not built until a logged case (row 13); A19 stays the pure negative.
- A17 and A18 reworded to what hold-once allows.
- Acceptance gaps filled: A23-A29, A30 (the Blocker), A31 (settle note); A20 widened to rows 9's skill changes.
- Register coverage: rows 1-12 mapped; row 10 met through §4.
- Existing callers: no regression in `ar_fenced` or `resumeOfferOf`; expected test edits named.
- Windows Git Bash: `\r` and fence state in the header scan, two-form stat, `[ -nt ]` in the hook.

## Critic findings

Folded into Fable's round 1: 1 Blocker, 3 High (4 fixed, 0 answered), 8 Medium, 3 Nit.

- [Blocker] Rule 4 routed to an audit that stops on the same rows — fixed: §4 step 2 and step 7, A30, riskiest assumption.
- [High] Recomputing `kept` printed the reader's branch — fixed: §2 `kept`.
- [High] The cockpit recompute sat on the tool-call path, and its fallback lost the register check — fixed: §3.
- [High] Rule 2 treated every unindexed plan as live — fixed: §1 rule 2 guard.
- [Medium] The roadmap.md trigger fired on design turns and pulls — fixed: §5 narrowed to this turn's own change (pending A16).
- [Medium] The cross-worktree hold lost its precondition — fixed: deferred to row 13.
- [Medium] Mtime supersession misfired across hosts — fixed: counts in the marker.
- [Medium] A recompute could move a plan back to Task 1 — fixed: §2 `plan` guard, A28.
- [Medium] The row 11 fix filed the checkpoint under a closed workstream — fixed: §6 `project` workstream, A22.
- [Medium] Cost unmeasured on Windows; repo-audit unbounded; fallback unmarked — fixed: §3, riskiest assumption.
- [Medium] Settle erased notes — fixed: §1, A31.
- [Medium] `--project` kept notes it did not write — fixed: wholesale by default, `--keep-notes` for handoff.
- [Nit] The removed-checkout fallback lasted one turn — fixed: turn-start keeps the line.
- [Nit] The cache key omitted the subject plan — fixed: added; the ledger omission is deliberate.
- [Nit] "The last plan completed.md lists" — fixed: the line added since the turn-start head.
