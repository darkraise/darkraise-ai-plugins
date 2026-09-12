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

1. **Claude review.** Dispatch a general-purpose agent on the most capable
   available model, using dr-superpowers:requesting-code-review's
   [code-reviewer.md](../skills/requesting-code-review/references/code-reviewer.md).
2. **Codex round.** When Codex is usable, run the round in
   [external-executor.md](external-executor.md) §Final-review Codex round. If it
   is not usable, or it times out, skip it and say so.
3. **Dedupe and verify** in one dispatch of `dr-superpowers:judge-fable`
   (`dr-superpowers:judge-opus` when Fable is unavailable or your human partner
   declined it — say the substitution aloud) given both reviewers' lists. It
   merges findings that name the same defect in the same place (not merely the
   same file), tags each `claude`, `codex`, or `both`, and returns `CONFIRMED` or
   `REJECTED` with evidence for each. The verifier is a third seat, so neither
   reviewer grades its own work.
4. **Report** confirmed findings ranked most severe first, then the rejected ones
   with the reason each was rejected. A finding both reviewers raised and the
   judge confirmed is the strongest signal available in this loop; say so.

## Fixing what it finds

A confirmed finding gates the handoff whichever reviewer raised it; a rejected
one never does.

If confirmed findings remain, fix them in ONE wave with the complete list — in
subagent mode one fix subagent, in inline mode one pass of your own. Never one
fixer per finding: per-finding fixers each rebuild context and re-run suites, and
a real session's final-review fix wave cost more than all its tasks combined.

Then run exactly one scoped re-review of the fix wave
(`scripts/review-package PLAN_FILE FIX_BASE HEAD` over the fix range, with
[re-review-prompt.md](../skills/subagent-driven-development/references/re-review-prompt.md)).
Send any residual findings to the ruling seat as `final-residual` items and carry
out its verdicts.

There is no second fix wave. Residual load-bearing findings surface to your human
partner when dr-superpowers:finishing-a-development-branch presents the options.
Only the four stop classes stop you here.
