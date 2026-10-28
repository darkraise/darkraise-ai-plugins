# The Ledger

This skill owns every line in `<ledger dir>/progress.md`. The grammar:

```
# SDD ledger — plan: <path>
Task <N>: implementer <agent> (assigned; base <sha7>[; part A][; reserve tier][; scored at dispatch][; wave <k>][; executor <id> <model>/<effort>, thread <id>][; escalated from <old>: BLOCKED][; <substitution>])
Task <N>: fix round R/2 (X addressed, Y open — <one-liners>; commits a..b[; re-review skipped (<n> lines)]; resumed | fresh (<why>) | escalated <old> -> <new> | HANDBACK to <agent>)
Group <a>-<b>: review round R/2 (<same fields as a fix round>)
Task <N>: awaiting group review (commits <a7>..<b7>)
Group <list>: review round R/2 (Task <N>: <k> open — <one-liners> | clean; …; commits <a7>..<b7> (Task <N>)[, <a7>..<b7> (Task <M>)])
Wave <k>: started (base <sha7>; Tasks <a>-<b>; at most <c> at once)
Wave <k>: serialized — <reason>
Wave <k>: check failed — <command> → <one-line summary>
Wave <k>: fix round R/2 (<same fields as a fix round>)
Wave <k>: integrated (head <sha7>; <command> → pass[; baseline failures only])
Wave <k>: merged (head <sha7>; check at wave <m>)
Task <N>: escalated inline -> subagent — <trigger>          (written by inline mode only)
Task <N>: minor (deferred): <one-liner>
Task <N>: parked — <finding> — Ruling: <why the code stands>
Task <N>: Ruling: <finding> — <what was decided and why>
Task <N>: BLOCKED — <agent> exhausted — <what a human must decide>
Task <N>: BLOCKED — ruling seat — <what a human must decide>
Task <N>: Ruling: amendment A<k> — <reason> — <cost if wrong>
Ruling: amendment A<k> (Header) — <reason> — <cost if wrong>
Task <N>: complete (commits a..b[; merged <sha7>], review clean | K parked[, C carried to Task M | C carried to final review][; parts A, B][; scores spec s / scope c / verification v / quality q, seat <seat>]) — done: …; verified: <command → result>; remaining: none | <parked>; discovered: none | …; assumptions: none | …
Ruling: <what> — <why> — <cost if wrong>
Review depth: <light|standard|full> (<reason>)
Acceptance QA: dispatched (base <sha7>)
Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo
Acceptance QA: skipped (depth light)
Final fix: implementer <agent> (assigned; base <sha7>)
Final review: clean (commits <merge-base7>..<head7>[, K parked])
```

- `Acceptance QA:` lines are written by
  [final-review.md](../../../reference/final-review.md) step 0.5. On recovery:
  a `complete` line skips step 0.5; a `dispatched` line with no `complete`
  line and `<workspace>/acceptance-report.md` present means read the report
  and write `complete`; with no report, re-dispatch QA once with `[MODE]`
  `rerun`. Step 0.5 holds the rest of the procedure.
- `Acceptance QA: skipped (depth light)` counts as `complete` on recovery.
  `Review depth: <light|standard|full> (<reason>)` is written once, before
  step 0 of the final review, and is read on recovery, never recomputed; it is
  not a `Final review:` line, which recovery keys on.
- After each `complete` and `fix round` line, run `scripts/darkmem-sync push`;
  at `complete`, also promote the task's durable facts
  ([project-state.md](../../../reference/project-state.md) §darkmem sync points).
- Every task gets its own assigned line and its own complete line, including
  tasks reviewed as a batch or in a group review. Batches are contiguous task
  ranges named `Group <a>-<b>`; only a batch's review rounds log on its Group
  line. A group review's `<list>` is
  the task numbers in ascending order joined by commas (`Group 4,6,7`), or a contiguous range (`Group <a>-<b>`).
  Its clause attributes every finding to its member, and its commits clause
  holds one `<a7>..<b7> (Task <N>)` range per member fixed in the round, in
  sequential and wave mode alike.
- `Wave` lines and the `wave` and `merged` fields belong to parallel waves
  ([parallel-waves.md](../../../reference/parallel-waves.md)); a sequential plan
  never writes them. `Wave <k>: merged` closes the wave as `integrated` does:
  the next wave starts on it, and its head proves that wave's base
  (parallel-waves.md §1).
- The scores clause is present whenever a review seat, Codex or judge, scored the task.
- The checkpoint after the `—` comes from the report's
  `## Discovered issues (not fixed)` and `## Assumptions made` sections — the
  implementer's or the Codex wrapper's. `done` is a one-line summary of the
  task's deliverable, `verified` the covering command and its result, and
  `remaining` the parked findings. A batch report's sections are copied onto
  each task's complete line, attributed per task where the report names one.
- Write each line in the same message as your other bookkeeping, never later.
- A ruling-seat `BLOCKED` that belongs to no task (a `preflight` row, a
  Header amendment) is logged against the lowest-numbered task without a
  complete line, so recovery reads it as that task's terminal line.

**Recovery.** For task N, take the last line in file order among its
`Task <N>:` lines and any `Group` line covering N
(a range covers the tasks inside it; a comma list covers the tasks it names),
stepping over `minor (deferred)`, `parked`, `Task <N>: Ruling:`, and bare
`Ruling:` lines. A group review's `Group` line is the one whose clause starts
`Task <N>:`. Then:

| Last line | Action |
|---|---|
| `complete` | Done; never re-dispatch |
| `BLOCKED` | Terminal; never re-dispatch. It is a stop of the fourth class for any task that depends on it; name it in your final message |
| `awaiting group review` | Reviewed by the next group dispatch ([delegated-task.md](../../../reference/delegated-task.md) §3a); never re-dispatch its implementer |
| `review round 1/2` on a `Group` line, or `review round 1/5` from an older run | Resume the group's loop at round 2 — a fresh dispatch on the successor rung. On a group review's line (its clause starts `Task <N>:`), run round 2 for each member whose clause is open, one member at a time; on a batch's line, run it once for the batch |
| `review round 2/2` on a `Group` line, or `review round R/5` with R >= 2 from an older run | Go to the breaker: a group review's line (its clause starts `Task <N>:`) sends each member's open findings, a batch's line the batch's |
| `escalated inline -> subagent` | Inline mode escalated this task here. Dispatch the first rung on the escalation table ranked strictly above both the task's `**Implementer:**` agent and the inline session's rung, the successor of whichever ranks higher ([escalation.md](escalation.md) §Escalating out of inline mode) fresh at round 1 of 2, with the brief and the task's preceding fix-round lines; the inline session already spent three rounds at or above the assigned tier, and the task's earlier commits are in `git log` |
| `implementer <agent> (assigned …; wave <k>)`, or a `fix round R/2` after one | A parallel task: apply [parallel-waves.md](../../../reference/parallel-waves.md) §Recovery |
| `implementer <agent> (assigned …)` or `fix round R/2` | Apply [delegated-task.md](../../../reference/delegated-task.md) §Recovery |
| none | Not started |

A `Task`, `Group` or `Wave` round line written before the two-round cap reads `R/5`: R = 1 resumes at round 2, and R >= 2 goes to the breaker.
On a `Host: codex` plan a `Task` or `Wave` round line reading `R/5` is live, not older: apply the Codex row of [delegated-task.md](../../../reference/delegated-task.md) §Recovery.
A `Wave` fix-round line resumes the wave's fix loop
([parallel-waves.md](../../../reference/parallel-waves.md) §5) by the same rule.

A ledger written by an older version of this skill may carry an assigned line
without `base`: take the previous task's complete-line head, or the branch's
merge base for Task 1. An old `(scored at dispatch)` line reads as assigned.

**Plan state.** Every task complete and no `Final review:` line: go to Final
Review; an `Acceptance QA: dispatched` line with no `complete` line resumes at
its step 0.5. A `Final fix:` line and no `Final review:` line: the fix wave was
dispatched; after compaction the agent id is gone, so re-dispatch that agent
fresh, then continue Final Review at the scoped re-review. A
`Final review: clean` line: the review is done — go to
dforge:finishing-a-development-branch.
