# Clean-session phases

Auto runs carry the design conversation into execution and the whole execution
into finishing, and every final-review judge reads the branch's own design
documents as if they were code. The 2026-11-08 run cost 17.1M input-equivalent
tokens: finish and CI 2.2M at about 307k context per turn, the four lenses
0.94M. This spec removes those three costs. It covers all three rows of
`docs/dforge/registers/2026-11-09-clean-session-phases.md`.

**Execution strategy:** sequential — inline execution
**Depth:** standard — interface

## Decisions

- Process and scope. Handoff of 2026-11-09: "Owner chose the full dforge flow
  and all three register items as written."
- Row 2 approach. Asked with measurements from eight recent merges; the owner
  answered "Drop own docs (Recommended)".
  **Approach:** inline - skip 3: the owner chose among the measured options.
  Rejected: per-lens scopes (estimated 48-63% off lens cost, only about
  0.15-0.2M more than this option, for a new `lens-route` field and a
  `lang-bash` fix); `-U3` (at most 17%, removes context); on-demand reads
  (judges have no shell).
- Row 3 approach. Handoff: "make the switch always take the clear path, keeping
  phase execute and setupDue".
  **Approach:** inline - skip 3: the owner's notes chose it.
- Row 1 approach. Handoff: "after `Final review: clean` in an auto run, run
  next-step (it already prints finishing), then `auto-run clear --phase` and
  end `Auto run: clearing`. This overrides the owner's earlier same-session
  ruling, at the owner's request."
  **Approach:** inline - skip 3: the owner's notes chose it. The placement at
  finishing's entry is this spec's own and is open to the spec review
  (Row 1, below).
- Assumption for the spec review to overturn: attended runs stay as they are,
  since they already stop after the plan and an agent cannot clear its own
  session.

Early CI: none

Finish: merge

Worktree: in-place

## Row 3: a fresh session after the plan

The cockpit's `at === 'switch'` stage stops compacting. It runs
`auto-run clear --phase` and falls through to the existing `at === 'clear'`
stage, which clears, binds the new session, applies the plan's launch model and
effort, and submits the plan's first prompt. This is the path a refused
compaction already takes (`hooks/cockpit/register.tsx`, the `'skip' in done`
branch), so it becomes the only path.

`ar_switch` is unchanged in what it stores: phase `execute`, `setupDue` true,
the first prompt and the launch. `ar_clear` touches neither the phase nor
`setupDue`, and with `--phase` does not count a self-resume. A failed
`clear --phase` still books a failure and retries the `switch` stage, as a
failed refusal path does today.

With no caller left, these are removed:

- `AUTO_SWITCH_INSTRUCTIONS`, the `switch-resume` stage and pending value, and
  the `after-compact` lead on the submitted prompt, in the cockpit;
- `auto-run compacted --switch` and its handling in `ar_compacted` and
  `ar_resumed`;
- the same value in `scripts/turn-end.sh`, `types/index.d.ts`, the skip list of
  `bookAutoCompaction` in the cockpit, and the usage text of `scripts/auto-run`;
- the tests that pin them: the `cockpit.test.ts` state simulator and switch
  tests, and `tests/turn-end.test.sh`. In `tests/auto-run.test.sh`,
  `compacted --switch` is a fixture for the after-compact and setup-due checks,
  and those fixtures move to a plain `compacted` after `switch`, which keeps
  `setupDue` true.

No migration is written for a state file already holding `switch-resume`: the
run is bound to the session that wrote it, no new session can bind it, and it
ends at the hold cap as any stalled run does.

`scripts/turn-end.sh`'s hold message, `ar_switch`'s comment, `auto-run.md`
§The switch, §Ending a turn's pending list and §Clears (the "Plan saved is no
clear" sentence), `session-budget.md` §Stops and dforge:handoff's `When` say the
session is cleared rather than compacted. §Clears and the `clear --phase` usage
text name its three callers: the escalated plan, the switch and finishing. The
verb `auto-run switch` and the line `Auto run: switching` stay, so
dforge:writing-plans does not change.

## Row 1: finishing in a clean session

In an auto run, finishing runs in a session of its own. The rule sits at the
entry of dforge:finishing-a-development-branch, not in the execution skills:
`executing-plans` requires finishing "in this same turn" and has no room to
carve out an exception, and the entry is also where
`subagent-driven-development` and recovery arrive.

The skill's `## Auto run` section reads the phase from `scripts/auto-run status`:

- **Any phase other than `finish`** (normally `final`): run
  `scripts/auto-run phase finish`, with its existing exit 4 handling. Then run
  dforge:handoff steps 0-3, `scripts/next-step PLAN_FILE`, and
  `scripts/auto-run clear --phase`, and end the turn with
  `Auto run: clearing`. `next-step` already prints
  `Run dforge:finishing-a-development-branch.` for a ledger holding
  `Final review: clean`. Its exits 4 and 5 are handled as `auto-run.md` §Clears
  says, and a nonzero `clear --phase` stops the run as §Stopping says.
- **Phase `finish`:** this is the clean session. Continue with the skill as
  today.

`phase finish` runs before the clear so a second entry cannot clear again.
Handoff step 2 stays even though a commit there moves HEAD: that costs one suite
run at finishing's first step, not correctness. The clean session arrives
through dforge:resume-execution, because `next-step`'s first prompt names it, and
that skill needs no change.

Two inputs of finishing live in the conversation today: step 5b's "every
final-review finding you left for your human partner", and the final-review
report above its menu. `auto-run.md` §Finishing tells the clean session to read
them from their durable copies: the ledger's parked and `Ruling:` lines, the
`final review residual` register rows, and the workspace's `final-fix-report.md`
and `final-rereview-report.md`.

The
skill stays under the 20,000-byte test limit by moving existing wording into
`auto-run.md` §Finishing, which holds the full rule. `final-review.md`,
`auto-run.md` §After a compaction, `session-budget.md` (Finishing, Stops,
Auto run) and dforge:handoff's `When` state the auto-run exception. Pins in
`tests/final-phase`, `context-size` and `task-step` change only where the text
or behaviour they name changes.

Attended runs keep finishing in the session that ran the final review.

## Row 2: judges stop reading the branch's own documents

`scripts/review-package` leaves `<docs>/specs`, `<docs>/plans` and
`<docs>/registers` out of the `## Files changed` stat and the `## Diff`, for
every seat. The lens seats and the final judge already receive the spec and plan
by path, and task and group reviewers receive the brief. Those documents were
13-41% of the package across eight recent merges (about a third on a typical
branch). The directories resolve as `scripts/dforge-path docs` does, under each
spelling `dforge_name_spellings` returns, so a migrated project's older
`docs/superpowers/` documents count and a project with a `documentStore` gets
the right paths or none. Both git calls run from the repository top with
top-relative excludes, because an exclude makes the working directory matter and
a relative pathspec would narrow the range to the current subdirectory.

- `## Commits` is unchanged.
- When files were left out, a line under `## Files changed` names each path and
  says the seat has the spec and plan by path or the brief. The task-reviewer
  prompt gains one sentence allowing a Read of a named left-out file.
- A range that changes nothing else keeps those files, so a task that only
  edits a document never gets an empty package.

## Testing

Each change lands with its pins in the existing suites: `auto-run.test.sh`,
`cockpit.test.ts`, `turn-end.test.sh`, `final-phase.test.sh`, and
review-package checks beside `budget-line.test.sh` or in a test file sized like
its neighbours. The review-package test runs on the Windows shards, which is
what shows git receives the exclude pathspecs intact under Git Bash path
conversion. The repository's validation commands in `CLAUDE.md` apply.

## Acceptance

A1. [test, high] With `switch` pending, the cockpit clears the session, binds the new one and submits the plan's first prompt on the plan's launch model and effort.
A2. [test, neg, high] With `switch` pending, the cockpit makes no compaction call, and the submitted prompt carries no `after-compact` instruction.
A3. [test, high] After the switch's clear, `auto-run status` reports phase `execute`, "setup due", and an unchanged resume count.
A4. [test, neg, high] `auto-run compacted --switch` exits as a usage error, and neither the `auto-run` usage text nor `auto-run.md`'s pending list names `switch-resume`.
A5. [test, high] After `auto-run phase finish` then `auto-run clear --phase`, the phase is `finish`, `clear` is pending, the first prompt is `next-step`'s finishing prompt, and the resume count is unchanged.
A6. [test, high] dforge:finishing-a-development-branch states that on any phase other than `finish` an auto run sets phase `finish`, runs handoff steps 0-3, `next-step` and `auto-run clear --phase`, and ends with `Auto run: clearing`, and that on phase `finish` it continues.
A7. [test, neg, high] `session-budget.md` keeps "Once the final review is clean, finishing runs in the same session" with the auto-run exception appended, dforge:handoff's `When` keeps "nothing stops finishing once the final review is clean" for attended runs, and the `## Auto run` section is the only place in dforge:finishing-a-development-branch that names `auto-run clear`.
A8. [test, high] `review-package` over a range changing code and a file under each of `<docs>/specs`, `<docs>/plans` and `<docs>/registers` lists and diffs the code only, and names each file it left out.
A9. [test, neg, high] `review-package` leaves in a changed document outside those three directories, and its commit list still names every commit.
A10. [test, neg, high] `review-package` over a range changing only files under those directories still shows their diff.
A11. [test, high] Every skill file stays at or under the 20,000-byte limit its test enforces.
A12. [demo, high] A real auto run moves from a saved plan into execution through a cleared session, and from a clean final review into finishing through another, and reaches its finish action; its finishing session's per-turn context is recorded against the roughly 52k baseline of a new session and the 307k of the 2026-11-08 run.
A13. [test, neg, high] With `switch` pending and the first `clear --phase` failing, the cockpit books one failure and retries, and a second failure stops the run with a reason naming the switch.
A14. [test, high] `review-package` run from a subdirectory of the repository produces the same diff and stat as from the top.
A15. [test, high] `auto-run.md` §Finishing names the ledger's parked and `Ruling:` lines, the `final review residual` register rows, and the workspace's `final-fix-report.md` and `final-rereview-report.md` as where a clean session reads what the final review left open.

## Riskiest assumption

A cleared session can start execution and carry out finishing from what is on
disk, with no conversation behind it. Evidence for the switch: the refused
compaction path already clears and submits the same first prompt
(`hooks/cockpit/register.tsx:2778-2783`, `reference/auto-run.md:297-300`), and
Setup runs when no ledger exists. Evidence for finishing: its final message is
built from the ledger, `auto-run ruling list`, the register and the spec
(`reference/auto-run.md:375-379`), and its suite reuse keys on the commit
(`skills/finishing-a-development-branch/SKILL.md:89`). The two inputs that live
only in the conversation today have durable copies (Row 1). No real run has
exercised either path end to end; A12 is the check.

## Review rulings

- Row 1 placement at the entry of dforge:finishing-a-development-branch: approved; every arrival passes through it.
- Attended runs stay as they are: the assumption stands.
- Finishing's conversation-only inputs: nothing blocks; name their durable copies in `auto-run.md` §Finishing.
- `auto-run phase finish` before the clear: no adverse side effect; keep the order.
- Other consumers of `switch-resume`: add the `bookAutoCompaction` skip list and the named test fixtures; write no migration.
- `review-package` exclusion: keep it for every seat, correct the by-path claim, and name the left-out paths.
- Acceptance statements: A7's second clause becomes named pins; the rest are checkable as written.
- Row 3's document list: add §Clears, §Ending a turn's pending list and the `auto-run` usage text.
- "a clear that failed and was resumed": struck; the `finish` branch is the clean session.
- Handoff step 2 at the finishing entry: kept; a commit there costs one suite run.
- Legacy documents prefix: exclude every spelling `dforge_name_spellings` returns.
- Pathspec form: run both git calls from the repository top with top-relative excludes.

## Critic findings

- Medium, the by-path claim is false for task reviewers: fixed in Row 2.
- Medium, finishing's conversation-only inputs: fixed in Row 1 and A15.
- Medium, stale `auto-run.md` sentences and usage text: fixed in Row 3 and A4.
- Medium, the exclusion makes the working directory matter: fixed in Row 2 and A14.
- Medium, A7's second clause cannot be checked: fixed in A7.
- Nit, the clean session arrives through dforge:resume-execution: fixed in Row 1.
- Nit, the left-out line gives a count only: fixed in Row 2 and A8.
- Nit, only the current documents root is excluded: fixed in Row 2.
- Nit, the phrase naming no code path: struck in Row 1.
- Nit, the fixed cost of the added session: A12 records it against the 52k baseline.
- Nit, a state file already holding `switch-resume`: answered in Row 3, no migration.
- Nit, handoff step 2 can move HEAD: answered in Row 1.
- Nit, no statement covers Row 3's failure path: fixed in A13.
