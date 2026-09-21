# Revising plans — follow-ups

What the run of `docs/superpowers/plans/2026-09-21-dr-superpowers-revising-plans.md`
left open. The ledger is deleted with the workspace, so this is the record.
Every task number below is that plan's.

## Open, with a register row

- **`plan_executors` still honours an `**Executor:**` line above the first
  `#### Part` heading**, so `task-brief` delegates a split task on a line that
  `plan-lint` and `plan-revise` no longer read. Spec §5a scopes `plan_executors`
  out, so the branch conforms; register row 5 in
  `registers/2026-09-20-review-fixes-deferrals.md`. Task 4's parked Override
  ruling does not carry over to it, because there the two tools do disagree.
- **Plans headed `### Task A1` are invisible to `plan_tasks`**, so `plan-lint`,
  `review-route`, `task-brief` and `plan-revise` skip them silently (three
  darkcloud plans). Spec §4 defines a plan file by numeric tasks; register
  row 6.

## Worth doing before the skill is relied on

- Run `revising-plans` end to end on one real legacy plan. The prose tests pin
  sentences, not the checklist (Task 6).
- `SKILL.md` step 1 has no catch-all for a `live=unknown` whose evidence
  matches neither shape it names; `plan-revise` cannot print one today (Task 6).
- `SKILL.md` step 3 asks the model to repair a unit that has a score but no
  `**Implementer:**` line, but the `unit` row has no implementer field, so only
  `plan-lint` shows it (Task 6). Step 5 says to skip to step 7 when no gate
  printed `lane=true`, while step 7 also reconciles stale Executor lines (Task 6).
- The plan's Architecture sentence says the four helpers are the only way any
  script reads `**Executor:**` lines. The spec never granted that; it is a
  wording defect in the plan, not in the code.

## Deferred minors

- Task 1: `plan_part_text` passes fence markers through, so callers re-filter;
  the part-heading pattern is stricter than `is_task`, so a near-miss heading
  reverts to the stale parent score; `plan_lines` and `plan_part_text` are
  asserted only by count; three RED checks passed vacuously.
- Task 2: the new `review-route` tests capture stderr but never assert on it;
  no case pins the `die` path for a task whose only Evaluation line is fenced;
  `review_surface true` is never restored, so later appended tests inherit it.
- Task 3: the fenced-part fixture asserts only an absence, not a clean exit.
- Task 4: with several ticked executors the reported gate reason depends on
  tick order (a later `fail:risk` overwrites an earlier `fail:total`); comments
  cite line numbers in other files; `EXEC_TABLE` is built at every start though
  single-plan mode never reads it.
- Task 5: no test asserts the `exec=` or `executors=` survey fields, or the
  `steps N M (done open)` and `via PR` evidence strings; `ledger_for`'s
  `[ -n "$rel" ] || return 0` can never fire; `ledger_for` drops the `cygpath`
  normalisation `plan_ledger` performs.
- Task 6: the two prose needles for step 1 do not pin the word "stop"; the
  `using-superpowers` entry point has 66 bytes left of its 4,800-byte budget, so
  the next Routing row forces trimming one.
- Final review, not fixed: `for eid in $ticked` and `for _eid in $EXEC_IDS` are
  unquoted; `fail:not_enabled` covers both "no executor ticked" and "no rung for
  this total"; the survey's `unparsed` column merges "no Evaluation line" with
  "a line that does not parse"; `plan-lint` validates a unit from its first
  Evaluation line while `plan-revise` takes the highest total and highest risk.

## Parked, with the ruling

- **Task 4, an Override above `#### Part A` is not seen by the part units.**
  `plan-lint` reads each part's text the same way, so the tools agree by
  construction; carrying it into every part would report units `plan-lint`
  accepts as `fail:override`.
- **Task 5, the survey's `eligible` ignores `**Override:**` lines.** Spec §4
  defines survey eligibility as potential; neither legacy corpus holds an
  Override line.

## For your information

- Codex was off for the whole run (`codex-gate` printed `plugin-version:1.0.6`),
  so Tasks 3 to 7 ran on their Claude `**Implementer:**` agents and every review
  seat was a Claude judge.
- Commits for Tasks 3 to 7 and the final fix wave carry `Co-Authored-By: Claude
  Sonnet 5`, not the `Claude Opus 5` line the plan's Global Constraints name;
  the trailer follows the model that wrote the commit.
- `tests/ui-discovery.test.mjs` fails on a machine where `rg` is only a shell
  function; it passes with an `rg` executable on `PATH`.
