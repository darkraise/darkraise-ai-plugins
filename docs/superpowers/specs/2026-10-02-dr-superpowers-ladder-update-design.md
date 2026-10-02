# dr-superpowers ladder update from the tier evaluation

Date: 2026-10-02
Status: design, owner-approved in chat on 2026-10-02.
Register: `docs/superpowers/registers/2026-10-01-tier-reevaluation.md` row 2.
Evidence: `docs/superpowers/notes/2026-10-02-tier-eval-results.md`, section
Owner rulings, and the report below it.
Precedent: `docs/superpowers/specs/2026-09-29-dr-superpowers-sonnet-5-5-design.md`
§2, which moved total 4 and set the pattern for legacy plans.

## Rulings (owner, 2026-10-02)

1. **Moves taken:** total 2 to `impl-sonnet-low`, totals 3 and 4 to
   `impl-sonnet-medium`, total 5 to `impl-sonnet-high`, and `judge-opus` from
   `high` to `medium` effort.
2. **Declined or unchanged:** total 6 stays `impl-opus-high`; totals 0 and 1
   stay; `judge-sonnet-high` keeps totals 0 to 3; the escalation table is
   unchanged.
3. **No second repetition.** The harness defects in register rows 4 to 11 are
   deferred until one is scheduled.
4. **The heavy rule is unchanged.** A task is still heavy at total 5 or more,
   or risk 3: a total-5 task stays delegated with its own per-task review and,
   in an inline plan, a preflight ruling. Chosen over raising heavy to total 6,
   because the eval measured implementers at total 5, not whether those tasks
   can go without a per-task review.

All paths below are under `plugins/dr-superpowers/` unless they say otherwise.

## 1. The ladder

### The table

The `assignment` block in `reference/ladder.md` becomes:

```assignment
0 impl-haiku
1 impl-sonnet-low
2 impl-sonnet-low
3 impl-sonnet-medium
4 impl-sonnet-medium
5 impl-sonnet-high
6 impl-opus-high
```

The `escalation` and `reserve` blocks are unchanged. `impl-opus-medium` leaves
the assignment table but stays the escalation successor of
`impl-sonnet-medium` and `impl-opus-low`, as `impl-opus-low` already sits on
the ladder with no score assigning it. The seven execution implementers that
`tests/ladder.test.sh` and `tests/fleet.test.sh` check are therefore unchanged,
and so is the reserve table's count of implementers that neither table
reaches.

Escalation consequences, by the existing model-before-effort rule: a total-2
task that exhausts `impl-sonnet-low` goes to `impl-opus-low`; totals 3 and 4
on `impl-sonnet-medium` go to `impl-opus-medium`; total 5 on
`impl-sonnet-high` goes to `impl-opus-high`. Each successor runs Opus, as the
escalation of the old assignment did.

### Prose that states the old rows

- `agents/impl-sonnet-low.md` description: dispatched for scores 1 and 2.
- `agents/impl-sonnet-medium.md` description: dispatched for scores 3 and 4.
- `agents/impl-sonnet-high.md` description: dispatched for score 5, coupled
  work carrying a shared-path or data-shape risk.
- `agents/impl-opus-medium.md` description: escalation rung for
  `impl-sonnet-medium` and `impl-opus-low`; no score assigns it.
- `reference/ladder.md` §What the range actually reaches: Haiku takes total 0,
  Sonnet totals 1 to 5, and Opus is assigned only at 6 and otherwise reached by
  escalation. It names the tier evaluation as the measurement behind totals 2
  to 5, and its limits: one repetition, mostly as-written cases.
- `skills/writing-plans/SKILL.md` §Choosing the Execution line: "the
  assignment table sends every total below 5 to Haiku or Sonnet" becomes a
  statement that every self-implemented task (total 4 or less, risk below 3)
  is on Haiku or Sonnet. The inline effort rule is unchanged in wording, but it
  reads the table: an inline plan whose highest self-implemented total is 3 or
  4 and that delegates nothing now runs at `--effort medium`, not `high`.
- Worked examples that pair an `**Implementer:**` line with a total follow the
  table: the total-5 examples in `skills/writing-plans/SKILL.md` (the
  Implementer/Evaluation/Approach block) and `README.md` (its total-5
  Implementer/Evaluation block) name `impl-sonnet-high`; the total-2 example in
  `reference/executor-lane.md` names `impl-sonnet-low`, with the ledger and
  `HANDBACK` example lines in that file that follow from it. Examples that show
  no total, such as the walkthrough in
  `skills/subagent-driven-development/SKILL.md`, are left as they are.

### Plans written before 1.24.0

No compatibility code. `plan-lint` already reports an Implementer line that
disagrees with the table as an ERROR, and as a WARN when the task carries a
human `**Override:**` line.

`reference/ladder.md` §Plans written before 1.23.0 becomes §Plans written
before 1.24.0 and lists both changes: until 1.23.0 total 4 went to
`impl-opus-low`; until 1.24.0 totals 2 to 5 went to `impl-sonnet-medium`,
`impl-sonnet-high`, `impl-sonnet-high` and `impl-opus-medium`. The fix for
either is the same: change the line to the agent the current table names, or
keep the old agent with an `**Override:**` line. The existing sentence that an
inline `opus low` Execution line must rise to `--effort high` for a total-4
task becomes `--effort medium`, the effort the current table gives total 4.

## 2. The judge seat

`agents/judge-opus.md` changes `effort: high` to `effort: medium`, and its
description says "at medium effort". `tests/fleet.test.sh` ties an agent's
effort to its name suffix, and `judge-opus` has none, so no test blocks the
change.

`judge-opus` is one agent serving every Opus judge seat. The eval measured
code reviews and plan reviews (18 of 40 rubric defects found at both
efforts, no Critical defect missed). Rulings, Header-amendment confirmations,
approach ranking and distillation checks were not measured; they move with
the agent under the owner's ruling, and the ladder prose does not claim
otherwise.

Unchanged: `judge-fable` (high), `judge-sonnet-high`, and `scripts/review-route`'s
bands (Sonnet reviews totals 0 to 3 and Opus totals 4 to 6, risk 3 to Opus).
A total-5 task is now implemented by Sonnet and reviewed by Opus at medium.

## 3. Tests

Every fixture that pairs a total with the old row's agent is retargeted, in
`tests/ladder.test.sh`, `tests/plan-lint.test.sh`, `tests/plan-lib.test.sh`,
`tests/plan-revise.test.sh`, `tests/inline-mode.test.sh`,
`tests/next-step.test.sh`, `tests/review-route.test.sh` and
`tests/plan-amend.test.sh`. A fixture that deliberately pins a legacy agent,
as `review-route.test.sh` does for `impl-opus-low`, keeps it. New or rewritten
assertions:

- `plan-lint`: a total-5 task naming `impl-opus-medium` is an ERROR naming
  `impl-sonnet-high`, and a WARN with an `**Override:**` line; a total-4 task
  naming `impl-sonnet-high` is an ERROR naming `impl-sonnet-medium`.
- `plan-lint`: an inline plan whose highest self-implemented total is 4 and
  that delegates nothing passes at `--effort medium`.
- `plan-revise`: recommends `effort=medium` for that plan.
- `ladder.test.sh`: the assignment block parses to the table above, and every
  agent it names is an execution implementer.

## 4. Release and verification

- Commits, one concern each: `feat(superpowers): lower the ladder per tier
  eval` (§1 with its tests); `feat(superpowers): run judge-opus at medium
  effort` (§2); `chore(superpowers): release 1.24.0` (`.claude-plugin` and
  `.codex-plugin` manifests, and the version pin in
  `tests/review-route.test.sh`).
- Verification: `node scripts/validate-repository.mjs`, every
  `plugins/dr-superpowers/tests/*.test.sh`, and `claude plugin validate` on the
  marketplace and each Claude plugin, all under timeouts, with no process left
  running. `tests/ui-discovery.test.mjs` fails on this host without an `rg`
  binary (register row 14) and is reported, not fixed.

## Out of scope

- Register rows 4 to 11 (eval harness defects), and the eval harness itself.
  After this change `run-grid.mjs` refuses to run against the repetition 1
  manifest because the plugin differs from its start commit; a repetition 2
  needs a rebuilt manifest anyway (row 4).
- Total 6, the `judge-sonnet-high` band, the heavy rule, Fable tiers, the
  Codex external lane (its `HANDBACK` resolves through the assignment table,
  so it follows the new rows unaided) and native Codex routing.
- Completed plans under `docs/superpowers/plans/`.

## Acceptance

Register row 2 is done when:

- the assignment block reads as §1, and the escalation and reserve blocks are
  unchanged;
- the four implementer descriptions and `judge-opus`'s effort and description
  read as §1 and §2;
- `plan-lint` reports a 1.23.0-style total-5 `impl-opus-medium` line as an
  ERROR, and as a WARN with an Override;
- both manifests read 1.24.0;
- every check in §4 passes, apart from the reported `rg` failure.
