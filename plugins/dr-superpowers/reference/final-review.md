# The final whole-branch review

Both execution skills end here. It is the broad review the per-task loop cannot
be: one reading of the whole branch against the spec, by reviewers that saw none
of the work being done.

## Who runs it, and when

- **Subagent mode** (dr-superpowers:subagent-driven-development): a fresh
  session. The last task's complete line is a hard stop, so that session handed
  off and dr-superpowers:resume-execution brought this one here.
- **Inline mode** (dr-superpowers:executing-plans): this session, unless the last
  budget line said `handoff`.
- **Either mode:** point the reviewer at the ledger's deferred-minor and parked
  lines, the complete lines' `discovered:` fields, every borderline (9-13) score,
  and every `(unseated)` ruling, so it can triage what must be fixed before
  merge.

## The review

Run `scripts/review-package PLAN_FILE MERGE_BASE HEAD` (MERGE_BASE is the commit
the branch started from, for example `git merge-base main HEAD`) and include the
printed path in each dispatch, so a reviewer reads one file instead of
re-deriving the branch diff with git commands.

0. **Gates.** When the project declares `docs/superpowers/gates.md`, run
   dr-superpowers:running-gates before dispatching any reviewer. A red gate stops
   the review, and so does a manifest defect: reviewing a branch that does not
   build, or whose suites fail, spends both reviewer seats on findings the gate
   already made. When the
   project has no manifest, say so in one line and go to step 1.
1. **Claude review.** Run `scripts/review-route PLAN_FILE --final` and dispatch
   the `primary` it prints: `dr-superpowers:judge-fable` for an intricate plan
   (a task at risk 3 or totalling 6), `dr-superpowers:judge-opus` otherwise.
   When Fable is unavailable or your human partner declined it, dispatch the
   `fallback` instead and say so aloud. Use dr-superpowers:requesting-code-review's
   [code-reviewer.md](../skills/requesting-code-review/references/code-reviewer.md)
   with `[DIFF_FILE]` set to the package path, `[PLAN_OR_REQUIREMENTS]` to the
   spec and plan paths, and the SHAs to `MERGE_BASE` and `HEAD`. Dispatch the
   `primary` (or `fallback`) as `subagent_type`; the template's own
   "Subagent (general-purpose)" line is not the seat here. The judge
   agents are read-only and carry no shell: the package file means the
   template's git fallback never applies, and neither do its Read-Only
   Review section's `git show`/`git diff`/`git worktree` instructions. A
   Codex-host plan takes its final-review seat from
   [native-codex.md](native-codex.md) instead.
2. **Codex round.** Run the round in
   [external-executor.md](external-executor.md) §Final-review Codex round. Its
   runner reports one of four outcomes: `OK` and `FALLBACK` produce findings
   for step 3, and `FALLBACK` also means the preferred judge rung refused the
   run — say so. `TIMEOUT` and `FAILED` produce nothing: skip the round, say
   which, and go to step 3 with the Claude review alone. An absent or empty
   report is never a clean round.
3. **Dedupe and verify, only with two lists.** When the Claude review and the
   Codex round each produced at least one finding, dispatch
   `dr-superpowers:judge-fable` once (`dr-superpowers:judge-opus` when Fable is
   unavailable or your human partner declined it — say the substitution aloud)
   given both lists. It merges findings that name the same defect in the same
   place (not merely the same file), tags each `claude`, `codex`, or `both`, and
   returns `CONFIRMED` or `REJECTED` with evidence for each. The verifier is a
   third seat, so neither reviewer grades its own work.

   **With one list** — Codex off, `TIMEOUT`, `FAILED`, or either reviewer
   returning no findings — there is no step-3 seat. Every finding in the list
   enters the fix wave unverified, and the fixer triages it (Fixing what it
   finds).
4. **Report.** With two lists: confirmed findings ranked most severe first, then
   the rejected ones with the reason each was rejected; a finding both reviewers
   raised and the judge confirmed is the strongest signal available in this
   loop, so say so. With one list: the findings ranked most severe first, then,
   after the fix wave, which were fixed and which the fixer rejected, with the
   re-review's verdict on each rejection.

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
dispatch the printed `primary` as `subagent_type`, with no `model` argument.

Whoever fixes writes `<workspace>/final-fix-report.md`: what changed per
finding, the covering tests, the command and its output. With one list the
fixer first checks each finding against the code under
dr-superpowers:receiving-code-review, fixes the real ones, and records each one
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

There is no second fix wave. Residual load-bearing findings surface to your human
partner when dr-superpowers:finishing-a-development-branch presents the options.
Only the four stop classes stop you here.
