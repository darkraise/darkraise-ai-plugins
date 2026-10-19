# The final whole-branch review

Both execution skills end here. It is the broad review the per-task loop cannot
be: one reading of the whole branch against the spec, by reviewers that saw none
of the work being done.

## Who runs it, and when

- **Either execution mode:** the session that completed the last task: the
  final phase never hands off. The final
  phase - this review, its one fix wave and finishing - is measured against
  that final-phase limit, not the task budget, so a `review-package` budget
  line saying `handoff` here does not stop it. Once the review is clean,
  finishing follows with no budget check.
- **Either mode:** point the reviewer at the ledger's deferred-minor and parked
  lines, the complete lines' `discovered:` fields, every borderline (9-13) score,
  and every `(unseated)` ruling, so it can triage what must be fixed before
  merge.

## The review

MERGE_BASE is the commit the branch started from, for example
`git merge-base main HEAD`. Steps 0 and 0.5 run first; step 1 builds the
review package, so the package includes the acceptance tests step 0.5 commits.

0. **Gates.** When the project declares `<docs>/gates.md`, run
   dforge:running-gates before dispatching any reviewer. A red gate stops
   the review, and so does a manifest defect: reviewing a branch that does not
   build, or whose suites fail, spends both reviewer seats on findings the gate
   already made. When the
   project has no manifest, say so in one line and go to step 0.5. In an auto
   run ([auto-run.md](auto-run.md)), a red gate does not stop the review: the
   review runs, the red gate is the first finding on the one fix wave's
   list, and the gates run again after that wave; a gate still red then runs
   `scripts/auto-run stop --reason "gate <name> red"` and ends as auto-run.md
   §Stopping says; a manifest defect does the same with the reason
   `"gates manifest defect"`.

0.5 **Acceptance QA.** Skip this step, saying so in one line, when the plan's
   spec has no `A<n>` statement tagged `test`, or when the ledger already holds `Acceptance QA: complete`. When the ledger holds
   `Acceptance QA: dispatched` with no `complete` line, QA was cut off: when
   `<workspace>/acceptance-report.md` exists, read it and go to (c) below;
   otherwise re-dispatch once with `[MODE]` `rerun`, under (b)'s timer, then
   continue at (c); it counts as this review's one re-dispatch. When the
   ledger already holds the re-dispatch `Ruling:` line below, that re-dispatch
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
      too, for its mutation worktree. Before dispatching, run
      `git status --porcelain` and keep its output.
      Dispatch it in the background and, in the same message, start a
      background timer, `sleep 2700` (45 minutes), as
      [executor-lane.md](executor-lane.md) arms its timers. When the timer
      finishes first, stop the QA agent (TaskStop on Claude Code; on Codex,
      close the child). Run `git status --porcelain` again: each path it
      lists that the earlier output did not is QA's unfinished work. Restore
      a tracked one with `git restore --staged --worktree -- <path>`, delete
      an untracked one, and log
      `Ruling: QA timed out — its uncommitted files were removed — none`.
      Then write or complete `<workspace>/acceptance-report.md` yourself,
      with `cannot-test: timeout` for every statement it does not cover.
      When QA finishes first, stop the timer.

   (c) When it returns, or on recovery, run `git worktree list`. A QA worktree still listed is
      removed with `git worktree remove --force <workspace>/qa-mutation` and
      `git worktree prune`, and logged as
      `Ruling: QA worktree removed — it held only the throwaway break — none`.
   (d) Read the report and act on each row:
      - `fail`, `flaky`, mutation `green`, or `cannot-test: no-surface`: a
        finding added to the Claude list (step 1), written
        `[qa] A<n>: <result> — <test>`.
      - `cannot-test: ambiguous`: an item for
        `scripts/review-route PLAN_FILE --ruling acceptance-ambiguous`, sent
        with [ruling-prompt.md](../skills/subagent-driven-development/references/ruling-prompt.md).
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
   (e) Append `Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo`,
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
   and the dedupe judge and the fixer receive the lens file paths. `lens-skipped` lines and `lenses off` dispatch
   nothing; step 4 names them. Lens seats are read-only, so a recovery may
   dispatch them again.

   ```
   You are a specialist reviewer. Read the lens at <criteria path>: its
   criteria are defect patterns, not a rubric, so do not score them. Review
   the branch diff in <package path> against the spec <spec path> and the
   plan <plan path>, and report each hit, most severe first, as
   `### <Critical|Important|Minor>: [lens:<id>] <one-line claim>` followed by
   at most three lines: file:line, what fails, and the fix. Report at most ten
   findings. With none, write `No findings.` and stop.
   ```

   Then run `scripts/review-route PLAN_FILE --final` and dispatch
   the `primary` it prints: `dforge:judge-opus`, with `reason=intricate`
   for a plan with a task at risk 3 or totalling 6. Use
   dforge:requesting-code-review's
   [code-reviewer.md](../skills/requesting-code-review/references/code-reviewer.md)
   with `[DIFF_FILE]` set to the package path, `[PLAN_OR_REQUIREMENTS]` to the
   spec and plan paths, and the SHAs to `MERGE_BASE` and `HEAD`. Dispatch the
   `primary` as `subagent_type`; the template's own
   "Subagent (general-purpose)" line is not the seat here. The judge
   agents are read-only and carry no shell: the package file means the
   template's git fallback never applies, and neither do its Read-Only
   Review section's `git show`/`git diff`/`git worktree` instructions. A
   Codex-host plan takes its final-review seat from
   [native-codex.md](native-codex.md) instead.
2. **Codex round.** Run the round in
   [executor-lane.md](executor-lane.md) §Final-review Codex round. Its
   runner reports one of four outcomes: `OK` and `FALLBACK` produce findings
   for step 3, and `FALLBACK` also means the preferred judge rung refused the
   run — say so. `TIMEOUT` and `FAILED` produce nothing: skip the round, say
   which, and go to step 3 with the Claude review alone. An absent or empty
   report is never a clean round.
3. **Wait for the round's status line first.** Until the runner has printed
   `OK`, `FALLBACK`, `TIMEOUT` or `FAILED`, there is no step 3: end the turn
   and resume on its notification. An absent report is a round still running,
   never a one-list case.

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

   **With one list** — Codex off, `TIMEOUT`, `FAILED`, or either reviewer
   returning no findings — there is no step-3 seat. Every finding in the list
   enters the fix wave unverified, and the fixer triages it (Fixing what it
   finds).
4. **Report.** Name the lenses that ran, each `lens-skipped` lens (or
   `lenses off`), and the `Acceptance QA: complete` counts. With two lists:
   confirmed findings ranked most severe first, then
   the rejected ones with the reason each was rejected; a finding both reviewers
   raised and the judge confirmed is the strongest signal available in this
   loop, so say so. With one list: the findings ranked most severe first, then,
   after the fix wave, which were fixed and which the fixer rejected, with the
   re-review's verdict on each rejection. The report is not where the turn
   ends: after the fix wave, the execution skill's Finish section goes
   straight on to dforge:finishing-a-development-branch, and the report
   sits above its menu.

## Fixing what it finds

A confirmed finding gates the handoff whichever reviewer raised it; a rejected
one never does. With one list, every finding gates the handoff until the fixer
fixes it or rejects it with evidence the re-review upholds.

If confirmed findings remain, fix them in ONE wave with the complete list — in
subagent mode one fix subagent, in inline mode one pass of your own. Never one
fixer per finding: per-finding fixers each rebuild context and re-run suites, and
a real session's final-review fix wave cost more than all its tasks combined.

**The fix subagent** (subagent mode). Run
`scripts/review-route PLAN_FILE --final-fix <file> [<file> ...]` with every
repository-relative path the findings name. It prints the highest implementer
tier among the tasks whose `**Files:**` blocks name those paths, as the ledger
last recorded each (an escalation counts, and an `inline` implementer counts as
the Execution line's rung), raised to `impl-sonnet-high` and capped at
`impl-opus-high`; no matched task gives `reason=floor`. Append
`Final fix: implementer <agent> (assigned; base <sha7>)` to the ledger, then
dispatch the printed `primary` as `subagent_type`, with no `model` or `effort` argument.

Whoever fixes writes `<workspace>/final-fix-report.md`: what changed per
finding, the covering tests, the command and its output. With one list the
fixer first checks each finding against the code under
dforge:receiving-code-review, fixes the real ones, and records each one
it rejects under `REJECTED: <finding>` with its evidence. In subagent mode the
fix subagent writes it as its report file; in inline mode you write it before
the re-review. Then run exactly one scoped re-review of the fix wave
(`scripts/review-package PLAN_FILE FIX_BASE HEAD` over the fix range, with
[re-review-prompt.md](../skills/subagent-driven-development/references/re-review-prompt.md),
its `[REPORT_FILE]` being that file).
Send any residual findings — `NOT ADDRESSED`, and `REJECTION DISPUTED` in the
one-list case — to the ruling seat as `final-residual` items and carry out its
verdicts. The scoped re-review is a Claude seat that wrote none of the code, so
a list from Codex alone, which may cover Codex's own executor-lane commits,
still gets an independent reader.

**Acceptance tests.** The fixer never weakens a test whose name starts with
`A<n>:`; to dispute one it records `REJECTED: A<n> — <evidence>`, and the
scoped re-review decides. The fix wave's verification runs the acceptance file
again. A `fail` or `flaky` acceptance test that survives the fix wave (the
rejection upheld, or the ruling seat parking it) is the one edit allowed on an acceptance test:
mark that test skipped with a reason naming its register row, commit it, and
run `scripts/register add <register> "A<n>: <statement>" --state deferred --note "<the upheld rejection>"`,
so finishing's test run is green and the statement is not lost.

There is no second fix wave. Residual load-bearing findings surface to your human
partner when dforge:finishing-a-development-branch presents the options.
Only the four stop classes stop you here.
