# The final whole-branch review

Both execution skills end here. It is the broad review the per-task loop cannot
be: one reading of the whole branch against the spec, by reviewers that saw none
of the work being done.

## Who runs it, and when

- **Either execution mode:** the session that completed the last task: the
  final phase never hands off. The final phase - this review, its one fix wave
  and finishing - is measured against that final-phase limit, not the task
  budget, so a `review-package` budget line saying `handoff` here does not
  stop it. Once the review is clean, finishing follows with no budget check.
- **In an auto run** ([auto-run.md](auto-run.md)) the budget line prints the
  run's verdict, and a `compact` line does end the turn here: finish the step
  in flight, with no reviewer or fixer still running, and end the turn as
  auto-run.md §Ending a turn says. After the compaction,
  `scripts/auto-run after-compact` prints `continue` in this phase: resume the
  review from the ledger as the execution skill's After compaction section
  says. It never hands off, and once a compaction has run in this phase every
  budget line says `ok`.
- **Either mode:** point the reviewer at the ledger's deferred-minor and
  parked lines, the complete lines' `discovered:` fields, every borderline
  (9-13) score, and every `(unseated)` ruling, so it can triage what must be
  fixed before merge. Give it the ledger's path and name those line kinds;
  never paste the lines into the prompt, which on a long plan runs to hundreds
  of lines the reviewer reads before the diff. A gap a complete line carried
  to the final review is a confirmed finding already:
  it goes on the fix list without triage.

## The review

MERGE_BASE is the commit the branch started from, for example
`git merge-base main HEAD`. Step 0 runs first, then step 0.2. Step 0.5 dispatches QA in the
background and goes straight on to step 1: QA runs alongside the Claude review,
the lenses and the Codex round, and the fix wave waits for it (step 3).
Serializing them added QA's whole run, often a quarter of an hour, to every
final review. Because QA commits while the reviewers read, HEAD in steps 1 and
2 is the SHA recorded in the `Acceptance QA: dispatched (base <sha7>)` line,
passed as that SHA, never as the word `HEAD`; with no such line (QA skipped),
it is the branch head. QA's own tests reach an independent reader in the scoped
re-review instead (Fixing what it finds). While QA runs, make no commit of
your own: QA commits on this branch.

0. **Gates.** When the project declares `<docs>/gates.md`, run
   dforge:running-gates before dispatching any reviewer. A red gate stops
   the review, and so does a manifest defect: reviewing a branch that does not
   build, or whose suites fail, spends both reviewer seats on findings the gate
   already made. When the
   project has no manifest, say so in one line and go to step 0.2. In an auto
   run ([auto-run.md](auto-run.md)), a red gate does not stop the review: the
   review runs, the red gate is the first finding on the one fix wave's
   list, and the gates run again after that wave; a gate still red then runs
   `scripts/auto-run stop --reason "gate <name> red"` and ends as auto-run.md
   §Stopping says; a manifest defect does the same with the reason
   `"gates manifest defect"`.

- 0.2 **UI proof.** Run
  `bash <plugin-root>/scripts/ui-proof check --base MERGE_BASE --spec <the plan's Spec>`
  under `timeout 120`. Exit 0 goes on (it also prints `ok` when the project
  has no UI profile and the spec no UI/UX contract, or when no UI file
  changed). Any other status (2 for a bad base or spec, 124 for the timeout)
  means the check never ran: treat it as exit 1.
  Exit 1 stops the review like a red gate: the UI is unproven, and
  reviewing it spends the seats on what the proof would have found. Attended,
  report the failed steps and stop. In an auto run, run the dforge:ui-ux Prove
  phase, then check again, and go on when it passes; when the second exit 1
  comes only from `unverifiable` rows, which need the user's words, run
  `scripts/auto-run stop --reason "ui proof needs the user"` and end as
  auto-run.md §Stopping says; any other second exit 1 is the first finding on
  the fix wave's list.

- 0.5 **Acceptance QA.** Skip this step, saying so in one line, when the
  plan's spec has no `A<n>` statement tagged `test`, or when
  the ledger already holds `Acceptance QA: complete`. When the ledger holds
  `Acceptance QA: dispatched` with no `complete` line, QA was cut off. First,
  when `<workspace>/qa-status-before.txt` exists, remove QA's uncommitted work
  as (b) does when its timer finishes first, and log
  `Ruling: QA cut off — its uncommitted files were removed — none`; without
  that file, remove nothing. Then, when
  `<workspace>/acceptance-report.md` exists, read it, complete it yourself
  with `cannot-test: timeout` for every `test` statement it does not cover,
  and go to (c) below; otherwise re-dispatch once with `[MODE]` `rerun`, under
  (b)'s timer, then continue at (c); it counts as this review's one
  re-dispatch. When the re-dispatch `Ruling:` line below is already in the
  ledger, that re-dispatch
  is spent: write `<workspace>/acceptance-report.md` yourself, with
  `cannot-test: timeout` for every `test` statement, and continue at (c).
  Otherwise:

  (a) Append `Acceptance QA: dispatched (base <sha7>)` (the HEAD you hand QA).

  (b) Dispatch `dforge:impl-sonnet-high` (on a Codex host, the native
      implementer `gpt-6.1-sol / high`) with
      [acceptance-qa.md](acceptance-qa.md) and its placeholders: the spec,
      its `test` statements verbatim, MERGE_BASE, HEAD, the test command
      `gates.md` declares or `none`, the workspace, and `[MODE]` `first`.
      When the plan has a `**Worktree setup:**` line, give QA that command
      too, for its mutation worktree. Before dispatching, save the output of
      `git status --porcelain` to `<workspace>/qa-status-before.txt`.
      Dispatch it in the background and, in the same message, start a
      background timer, `sleep <s>` with `<s>` = 600 + 180 × the number of
      `test` statements, at least 1200 and at most 3600 (20 to 60 minutes),
      as [executor-lane.md](executor-lane.md) arms its timers, with the Bash
      call's `timeout` set to (`<s>` + 120) × 1000 ms: a background call's
      limit defaults to 30 minutes, and a timer killed there fires early.
      Then go on to step 1 without waiting; (c) to (e) run when QA returns
      or its timer finishes, before step 3's fix wave. When the
      timer finishes first, stop the QA agent: TaskStop on Claude Code; on
      Codex, `close_agent` where your tools offer it. V2 has none: send the
      child a `followup_task` telling it to stop and return now, then wait for
      it in bounded `wait_agent` stretches until `list_agents` shows it
      finished, for 10 minutes at most in all.
      Clean up only once it has stopped, since removing files a live writer
      still owns races it. If it cannot be stopped, leave its files in place
      and report the blocked cleanup.
      Once it has stopped, run `git status --porcelain` again: each path it
      lists that `<workspace>/qa-status-before.txt` does not is QA's
      unfinished work. Restore a tracked one with
      `git restore --staged --worktree -- <path>`, delete an untracked one,
      and log
      `Ruling: QA timed out — its uncommitted files were removed — none`.
      Then write or complete `<workspace>/acceptance-report.md` yourself,
      with `cannot-test: timeout` for every statement it does not cover.
      When QA finishes first, stop the timer.

  (c) When it returns, or on recovery, run `git worktree list`. A QA worktree
      still listed is removed with
      `git worktree remove --force <workspace>/qa-mutation` and
      `git worktree prune`, and logged as
      `Ruling: QA worktree removed — it held only the throwaway break — none`.

  (d) Read the report and act on each row:
    - In an auto run, a `fail` or `flaky` row whose statement needs work that
      a `Task <N>: complete (deferred by the auto run)` line lists under
      `remaining:` is no finding: the fix wave never does a deferred task's
      work, nor anything [auto-run.md](auto-run.md) §Rulings says is never
      performed. Handle its test as Fixing what it finds §Acceptance tests
      says, with the note `deferred task <N>`.
    - Any other `fail`, `flaky`, mutation `green`, or
      `cannot-test: no-surface`: a finding added to the Claude list (step 1),
      written `[qa] A<n>: <result> — <test>`.
    - `cannot-test: ambiguous`: an item for
      `scripts/review-route PLAN_FILE --ruling acceptance-ambiguous`, sent
      with
      [ruling-prompt.md](../skills/subagent-driven-development/references/ruling-prompt.md).
      `REWORD`: replace the statement's text in the spec with the
      `New statement:` line, commit the spec, and re-dispatch QA with
      `[MODE]` `reword A<n>[, A<m>]`; every ambiguous statement of one
      report shares that single re-dispatch. `PARK`: run
      `scripts/register add <register> "A<n>: <statement>" --state deferred --note "<the ruling>"`
      and change the spec line to `A<n>. deferred — register row <id>`.
      In an auto run a missing ruling follows
      [auto-run.md](auto-run.md) §Rulings.
    - `cannot-test: timeout`: no finding; it is reported, and it keeps the
      branch at an auto run's finish.

  (e) Append
      `Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo`,
      counted from the final report, except `<d>`: the number of the spec's
      statements tagged `demo`, which QA is not given and finishing lists.

  QA is re-dispatched at most once per final review, the recovery
  re-dispatch included. Before that re-dispatch, append
  `Ruling: Acceptance QA re-dispatched (<rerun | reword A<n>[, A<m>]>) — <why> — none`;
  on recovery, that line means the re-dispatch is spent. When it is spent,
  carry out a `REWORD` verdict as `PARK`.

1. **Claude review.** Run `scripts/review-package PLAN_FILE MERGE_BASE HEAD`
   and include the printed path in each dispatch below, so a reviewer reads
   one file instead of re-deriving the branch diff with git commands.

   **Lenses.** Run `scripts/lens-route PLAN_FILE --final MERGE_BASE HEAD`. In
   the same message as the Claude review, dispatch each printed `seat` with
   the prompt below, so they run in parallel; on a Codex host, a native judge
   at rank 8 or above. Then save each reply to `<workspace>/lens-<id>.md`:
   the Claude list for step 3 is the Claude review's findings plus every
   `[qa]` finding from step 0.5 and every lens finding, tagged `[lens:<id>]`,
   and the dedupe judge and the fixer receive the lens file paths.
   `lens-skipped` lines and `lenses off` dispatch nothing; step 4 names them
   and writes each `lens-skipped` line to the ledger. Lens seats are
   read-only, so a recovery may dispatch them again. A
   `lens-floor important` line means the plan is below the `lensMinorFrom`
   setting: add the bracketed sentence to every lens prompt. With one list,
   every lens finding enters the fix wave, and on a short plan the Minor tail
   costs the fixer more triage than it yields fixes.

   ```
   You are a specialist reviewer. Read the lens at <criteria path>: its
   criteria are defect patterns, not a rubric, so do not score them. Review
   the branch diff in <package path> against the spec <spec path> and the
   plan <plan path>, and report each hit, most severe first, as
   `### <Critical|Important|Minor>: [lens:<id>] <one-line claim>` followed by
   at most three lines: file:line, what fails, and the fix. Report at most ten
   findings. [Report Critical and Important findings only; leave Minor ones
   out.] With none, write `No findings.` and stop.
   ```

   Then run `scripts/review-route PLAN_FILE --final` and dispatch
   the `primary` it prints: `dforge:judge-opus`, with `reason=intricate`
   for a plan with a task at risk 3 or totalling 6. Use
   dforge:requesting-code-review's
   [code-reviewer.md](../skills/requesting-code-review/references/code-reviewer.md)
   with `[DIFF_FILE]` set to the package path, `[PLAN_OR_REQUIREMENTS]` to the
   spec and plan paths, and the SHAs to `MERGE_BASE` and `HEAD`. Dispatch the
   `primary` as `subagent_type`, in place of the template's seat line. A
   Codex-host plan takes its final-review seat from
   [native-codex.md](native-codex.md) instead.
2. **Codex round.** Run the round in
   [executor-lane.md](executor-lane.md) §Final-review Codex round. Its
   runner reports one of four outcomes: `OK` and `FALLBACK` produce findings
   for step 3, and `FALLBACK` also means the preferred judge rung refused the
   run — say so. `TIMEOUT` and `FAILED` produce nothing: skip the round, say
   which, and go to step 3 with the Claude review alone. An absent or empty
   report is never a clean round.
3. **Wait for QA.** When step 0.5 dispatched QA, nothing below runs until its
   (c) to (e) are done and its `[qa]` findings have joined the Claude list.

   **Wait for the round's status line first.** When step 2 launched the
   runner, there is no step 3 until it has printed `OK`, `FALLBACK`,
   `TIMEOUT` or `FAILED`: end the turn and resume on its notification. An
   absent report from a launched runner is a round still running, never a
   one-list case. When step 2 skipped the round without launching one
   (`codexReview` off, or the gate did not print `review=true`), there is
   nothing to wait for: go straight to the one-list case.

   **Dedupe and verify, only with two lists.** When the Claude review and the
   Codex round each produced at least one finding, dispatch a fresh
   `dforge:judge-opus` once, given both lists. It merges findings that
   name the same defect in the same place (not merely the same file), tags each
   `claude`, `codex`, or `both`, and
   returns `CONFIRMED` or `REJECTED` with evidence for each. The verifier is a
   third seat that wrote neither list, so neither reviewer grades its own work.
   A `[qa]` finding is not given to the verifier: it enters the fix wave as
   confirmed, because only the scoped re-review decides a `REJECTED: A<n>`
   dispute (Fixing what it finds).

   **With one list** — Codex off or the round skipped, `TIMEOUT`, `FAILED`, or either reviewer
   returning no findings — there is no step-3 seat. Every finding in the list
   enters the fix wave unverified, and the fixer triages it (Fixing what it
   finds).
4. **Report.** Name the lenses that ran, each `lens-skipped` lens (or
   `lenses off`), whether a `lens-floor` line held them to Critical and
   Important, and the `Acceptance QA: complete` counts. Append each
   `lens-skipped <id> reason=cap` line step 1 printed to the ledger as
   `final review lens-skipped <id> reason=cap`, one line per lens, unless the
   ledger already holds it: finishing lists them from there, because after a
   merge `scripts/lens-route` has no diff left to read. With two lists:
   confirmed findings ranked most severe first, then the rejected ones with
   the reason each was rejected; a finding both reviewers raised and the judge
   confirmed is the strongest signal available in this loop, so say so. With
   one list: the findings ranked most severe first, then, after the fix wave,
   which were fixed and which the fixer rejected, with the re-review's verdict
   on each rejection. The report is not where the turn ends: after the fix
   wave, the execution skill's Finish section goes straight on to
   dforge:finishing-a-development-branch, and the report sits above its menu.

## Fixing what it finds

A confirmed finding gates the handoff whichever reviewer raised it; a rejected
one never does. With one list, every finding gates the handoff until the fixer
fixes it or rejects it with evidence the re-review upholds.

If confirmed findings remain, fix them in ONE wave with the complete list — in
subagent mode one fix subagent, in inline mode one pass of your own. Never one
fixer per finding: per-finding fixers each rebuild context and re-run suites,
and a real session's final-review fix wave cost more than all its tasks
combined. In an auto run a deferred task's acceptance failures are not on that
list (step 0.5 (d)).

The fix wave edits UI files and so stales the UI proof: after the wave, run
step 0.2's `ui-proof check` again. Exit 1 then means, attended, a stop that
reports the failed steps. In an auto run it means going on to finishing,
whose Step 1b runs the dforge:ui-ux Prove phase once and keeps the branch
when the check still fails; do not run the Prove phase here.

**The fix subagent** (subagent mode). Run
`scripts/review-route PLAN_FILE --final-fix <file> [<file> ...]` with every
repository-relative path the findings name. It prints the highest implementer
tier among the tasks whose `**Files:**` blocks name those paths, as the ledger
last recorded each (an escalation counts, and an `inline` implementer counts as
the Execution line's rung), raised to `impl-sonnet-high` and capped at
`impl-opus-high`; no matched task gives `reason=floor`. Append
`Final fix: implementer <agent> (assigned; base <sha7>)` to the ledger, then
dispatch the printed `primary` as `subagent_type`, with no `model` or `effort`
argument. On a Codex-host plan it prints `primary=native:<model>/<effort>`,
which [native-codex.md](native-codex.md) says how to record and dispatch.

Whoever fixes writes `<workspace>/final-fix-report.md`: what changed per
finding, the covering tests, the command and its output. With one list the
fixer first checks each finding against the code under
dforge:receiving-code-review, fixes the real ones, and records each one
it rejects under `REJECTED: <finding>` with its evidence. In subagent mode the
fix subagent writes it as its report file; in inline mode you write it before
the re-review. Then run exactly one scoped re-review of the fix wave
(`scripts/review-package PLAN_FILE FIX_BASE HEAD` over the fix range, with
[re-review-prompt.md](../skills/subagent-driven-development/references/re-review-prompt.md),
its `[REPORT_FILE]` being that file). When QA committed tests, FIX_BASE is the
review's HEAD (the `Acceptance QA: dispatched` SHA), so the range holds QA's
commits too: the final reviewers never saw them. When no confirmed finding
needs a fix wave but QA committed tests, still run that one scoped re-review
over the same range, with `<workspace>/acceptance-report.md` as
`[REPORT_FILE]`.
Send any residual findings — `NOT ADDRESSED`, and `REJECTION DISPUTED` in the
one-list case — to the ruling seat as `final-residual` items and carry out its
verdicts. The scoped re-review is a Claude seat that wrote none of the code, so
a list from Codex alone, which may cover Codex's own executor-lane commits,
still gets an independent reader.

**Acceptance tests.** The fixer never weakens a test whose name starts with
`A<n>:`, or with `a<n>_` where the framework forbids a colon in a test name
([acceptance-qa.md](acceptance-qa.md)), or which the QA report identifies as an
acceptance test; to dispute one it records `REJECTED: A<n> — <evidence>`, and the
scoped re-review decides. The fix wave's verification runs the acceptance file
again. A `fail` or `flaky` acceptance test that survives the fix wave (the
rejection upheld, or the ruling seat parking it), or one step 0.5 left to a
deferred task, is the one edit allowed on an acceptance test: mark that test
skipped with a reason naming its register row, commit it, and run
`scripts/register add <register> "A<n>: <statement>" --state deferred --note "<the upheld rejection>"`,
so finishing's test run is green and the statement is not lost.

**Suites.** Any test or validation suite you run in the final review — the
check after the fix wave, or the project's full suite in inline mode — goes
through `bash <plugin-root>/scripts/suite-run -- <command>`, which records the
HEAD it ran at and prints a digest in place of the output. Tell the fix
subagent to run the project's full suite the same way after its last commit,
on a clean tree: finishing's verification then reuses that pass at the
unchanged HEAD instead of running the suite again. A fix wave whose commits
moved HEAD past that run is not reused.

There is no second fix wave. Residual load-bearing findings surface to your
human partner when dforge:finishing-a-development-branch presents the options.
Only the four stop classes stop you here.
