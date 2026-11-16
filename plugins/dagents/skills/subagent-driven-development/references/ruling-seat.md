# The Ruling Seat

Judgment belongs to the ruling seat, never to you, whatever model you run on.
It reads the whole plan, the spec, `amendments.md` and the ledger; you read
the header and one brief at a time.

**When.** Send the seat an item at each of these points, batching every item
that arises at one point into one dispatch:

| Kind | Decision point |
|---|---|
| `preflight` | Once, before Task 1 (Setup) |
| `plan-conflict` | A review finding labelled plan-mandated, or one that conflicts with what the plan's text requires |
| `cannot-verify` | Every `cannot-verify:` line of a `task-step verdict` digest, before the task completes |
| `breaker` | Every finding still open after round 2/2 |
| `blocked-plan` | An implementer BLOCKED because the plan is wrong |
| `executor-empty-diff` | An external executor's fix round that returned DONE with an empty diff and an argument ([executor-lane.md](../../../reference/executor-lane.md)) |
| `final-residual` | Findings still open after the final review's one fix wave |

**How.** Write `<workspace>/rulings-<point>-<task>.md` — `<task>` is the task
number the items concern, or `plan` for a plan-level point, so a recurring
point never overwrites an earlier file — listing each item: an id, its
kind, its task (or `plan`), and the paths it needs — brief, report, review
packages — with the findings copied verbatim. Run
`scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]` for the point's
kinds and the tasks its items concern, and dispatch the `primary` it prints
with [ruling-prompt.md](ruling-prompt.md), expanding its
placeholders. Its `[REPORT_FILE]` is `<workspace>/rulings-<point>-<task>-report.md`. The
seat writes its report there and replies in at most 10 lines;
read only its `## Verdict` section
(`awk '/^## / { on = ($0 == "## Verdict") } on' <report>`), never the rest.
Items of different kinds at one point share one dispatch, and
`<kind>` is then one comma-separated list, such as
`cannot-verify,executor-empty-diff`. The route prints
`dforge:judge-sonnet-high` (`reason=simple-kind`) when every kind in the list
is `cannot-verify` or `executor-empty-diff` and no task it names is risk 3,
and `dforge:judge-opus` otherwise; `preflight`, `plan-conflict`, `breaker`,
`blocked-plan`, `final-residual` and `acceptance-ambiguous` always go to
`dforge:judge-opus`. On any exit 2, dispatch `dforge:judge-opus` and say why,
quoting its message. Codex hosts, where `review-route` exits 2, use a native
judge at Astra high or above ([native-codex.md](../../../reference/native-codex.md)).

**Settled by a mechanical check.** `scripts/task-step review` prints
`check identity:` and `check attribution:` lines for the task's commits. A
reviewer's cannot-verify item that one of those lines answers `clean` (commit
author and committer, or an attribution trailer) goes to no seat; log it as
`Task <N>: Ruling: cannot-verify — settled by task-step check <name> — none`,
with `<name>` `identity` or `attribution`. A check that found something is a
finding for the fix loop, not a cannot-verify item.

**Carry out each verdict**, and copy its `Ruling:` line into the ledger
verbatim:

- **CONFIRMED-GAP** — the finding is real. Mid-task it enters the fix loop
  with the ruling's smallest fix in the fix message. At the breaker it is
  logged `Task <N>: Ruling: <finding> — <ruling>` and carried into the next
  dependent task's dispatch; with no later task depending on it, into the
  next task in plan order; after the last task, into the final review.
- **PARK** — log `Task <N>: parked — <finding> — Ruling: <why>`; the code
  stands.
- **AMEND** — run
  `scripts/plan-amend PLAN_FILE --report <workspace>/rulings-<point>-<task>-report.md --id A<k>`,
  `A<k>` being the item's `Amendment:` line; never copy the entry by hand. On `amended: A<k> …`, write the amendment ledger line; the next
  dispatch uses a fresh `task-brief`, which carries the amendment. On
  `rejected: …`, make one fresh seat dispatch carrying the report path, the
  entry's id and the rejection output; a second rejection is BLOCKED.

  **A Header amendment is confirmed first.** Before `plan-amend`, write
  `<workspace>/rulings-<point>-<task>-confirm.md`: the original item entry
  unchanged, then the path of the first seat's report and the item's id. Confirm it with
  a second, independent `dforge:judge-opus` dispatch, made directly
  rather than through `review-route`, with the same template and
  `[CONFIRM_NOTE]` filled; its `[REPORT_FILE]` is
  `<workspace>/rulings-<point>-<task>-confirm-report.md`, and its AMEND is
  applied with `--report` on that file. The second verdict replaces the first and is carried
  out like any verdict; the one fresh dispatch after a `rejected:` is a
  confirming seat too. Log
  `Ruling: header amendment A<k> confirmed by a second judge-opus — <its
  verdict> — if wrong, the plan's Global Constraints or Contracts carry a bad
  rule into every later task`.
- **BLOCKED** — log `Task <N>: BLOCKED — ruling seat — <decision>`, name it
  in your final message, and stop.

Never soften, merge or second-guess a verdict. If you think the seat is
wrong, carry the verdict out anyway: the ledger line is where your human
partner sees it.
