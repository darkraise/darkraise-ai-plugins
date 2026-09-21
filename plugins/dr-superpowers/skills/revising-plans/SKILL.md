---
name: revising-plans
description: Use when a plan written before the external executor lane needs bringing up to the current format - scores what is unscored, ticks the executors the live roster offers, and writes the Executor and Execution lines
---

# Revising Plans

A plan written before the external executor lane names no executor, so every
task runs on the Claude lane whether or not the lane would admit it. This skill
revises one named plan into an ordinary current-format plan.

**Announce at start:** "I'm using the revising-plans skill to revise `<plan>`."

`scripts/plan-revise` computes; this skill decides and edits. Call it as
`bash <plugin-root>/scripts/plan-revise <PLAN_FILE>`, with the working directory
inside the plan's repository.

## Survey first, when you do not know which plan

`bash <plugin-root>/scripts/plan-revise --survey docs/superpowers/plans` prints
one row per plan: its task count, how many units score, how many are eligible,
and its liveness evidence. It writes nothing. Report the rows and stop — which
plan is worth revising is your human partner's call, not yours.

`eligible=-` means the plan has no parseable score yet, so its eligibility is
unknown rather than zero. `eligible=<n>+?` means `n` units are known eligible
and the rest cannot be judged until they are scored. The survey counts what
*could* be delegated and ignores which executors are ticked; single-plan mode
applies the tick.

## The checklist

Create a todo per item and work them in order. The order matters: the gate reads
the scores, so scoring cannot follow the executor question.

1. **Refuse a plan that may be running.** Run `plan-revise --survey` on the
   plan's directory and read its `live=` field.
   - `live=yes`: stop, quoting the evidence, and name
     `bash <plugin-root>/scripts/plan-amend` as the route for a plan under
     execution — it is a script, not a skill, and it appends to the plan's
     workspace instead of editing the file.
     Never edit a plan whose ledger names it: during execution the file is
     immutable and the ledger is keyed to it.
   - `live=unknown` with the evidence `completed.md via PR, no ledger`: stop,
     quoting it. The plan may be awaiting a merge.
   - `live=unknown` with evidence that reads `steps <done> <open> (done open),
     no ledger`: nothing records the plan as run or merged, but a clone this
     survey cannot see may be running it. Quote the evidence and ask your human
     partner to confirm that the plan is not being executed in any clone.
     Continue only on that explicit confirmation; without it, stop.
2. **Repair the header.** `plan-revise`'s `header` row lists the sections the
   plan lacks. Add them from the plan's own content: Global Constraints from its
   stated rules, Contracts from the names tasks already exchange, Assumptions
   from claims the plan relies on, and a Task index matching its headings. Invent
   no requirement that is not already in the plan.
3. **Score every unit that needs one.** A `unit` row reporting `score=-` has no
   `**Evaluation:**` line; one reporting `score=?` has a line that does not
   parse, usually in an older prose form. Both are repaired here, as is a unit
   with a score but no `**Implementer:**` line. Score on the four axes in
   `reference/ladder.md`, then apply Rule S: a unit whose
   `files + spec + coupling` reaches 4, or whose spec scores 3, is split or
   redesigned rather than handed a larger model.
   Splitting a task Rule S rejects is part of this skill, and it is the one
   change to a task's body this skill makes: the task's steps are rewritten only
   as far as the split requires. A task needing more than that needs re-planning,
   not revision — say so and stop.
   Scoring precedes the executor question.
4. **Read the project's constraints.** `docs/superpowers/distilled/constraints.md`
   when the project has one. An absent file is not an error.
5. **Gate each executor, then run the roster.** Enumerate with
   `bash <plugin-root>/scripts/executors list`. For each id, run its gate:

   ```bash
   bash "$(bash <plugin-root>/scripts/executors path <id> gate)"
   ```

   That is a script to execute, not a path to print. Say its line aloud when it
   ends `source=probe`. If no gate printed `lane=true`, skip to step 7 and write
   no executor lines.
   Otherwise run `bash <plugin-root>/scripts/detect-executors.sh` once. It takes
   no id argument and probes every registered executor, so read its output and
   ignore every row whose gate did not print `lane=true`. An executor is
   offerable only when its gate printed `lane=true` and the roster reports it
   `usable`. A constraint that declares an executor's lane on ticks it without
   asking, on the same two conditions: a constraint cannot tick an executor that
   is not there.
6. **Offer the rest.** Render the remaining offerable executors as a
   multi-select question, and name every other detected executor with its reason
   in prose. If none is offerable, ask nothing and say so in one line. Record
   the tick as one appended blockquote line in the header:

   ```markdown
   > **External executors:** <id>
   ```

7. **Write the Executor lines.** Re-run `plan-revise`, which now sees the tick.
   Every unit row reading `gate=pass` takes an `**Executor:**` line naming one
   of the executors in its `rungs=` field, at that executor's rung, written
   below the unit's `**Implementer:**` line and above its `**Evaluation:**`
   line. Where `rungs=` lists several, you choose one; a unit carries at most
   one `**Executor:**` line.
   A unit that already reads `executor=<id>` is reconciled, not preserved: if
   its id is absent from `rungs=`, or its rung differs from the one printed for
   that id, replace it with the printed rung; if the unit no longer reads
   `gate=pass`, delete the line. A stale assignment survives otherwise and fails
   at verification with nothing to explain it.
   `gate=fail:not_enabled` means the scores pass but no ticked executor admits
   the unit — revisit step 6 rather than writing a line.
   Batching is decided at dispatch, not here, so no unit is exempted for it.
8. **Settle the Execution line.** Re-run plan-revise after writing the Executor
   lines, and copy the mode, model and effort from that run's `recommend` row.
   Do not reuse an earlier run's row and do not recompute it by hand: writing
   an Executor line changes what is delegated, which changes the recommended
   effort.
9. **Verify.** `bash <plugin-root>/scripts/plan-lint <PLAN_FILE>` reports
   `0 errors`, and a final `plan-revise` run shows every unit either `gate=fail`
   or `executor=<id>` matching its `rungs=`, with the header's `execution`
   matching the `recommend` row.

## When a task cannot be scored honestly

A task whose description is too thin to score gets no invented number. Leave it
unscored, say which task it is and what is missing, and let `plan-lint` report
the plan as incomplete. A guessed score is worse than a visible gap: it routes a
task to a seat nobody chose.

## What this skill never does

- It never edits a plan under execution. Corrections there go through
  `bash <plugin-root>/scripts/plan-amend`, which appends to the workspace rather
  than editing the file.
- It never decides which plans to revise. The survey reports; your human partner
  picks.
- It never rewrites a task's steps beyond the split Rule S requires. A plan
  whose content is wrong needs re-planning, not revision.
