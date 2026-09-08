# Codex Terra Scoring Implementation Plan

Execute inline with superpowers:executing-plans; design approved on 2026-09-08.

**Goal:** Add Terra and a calculated 0–9 native routing score, preserving Claude
routing and preventing escalation history from moving backward.

**Spec:** [Approved design](../specs/2026-09-08-codex-terra-scoring-design.md).

**Architecture:** Keep the JSON policy and Bash/jq selector. Require raw axes for
rubric requests; calculate files + spec + coupling + twice risk in the selector.
Publish `codex-v2`; reject old policy requests with a conversion-required error.

## Constraints

- Native Codex only; Claude scoring and external executor routing remain distinct.
- Rule S retains its existing thresholds. Review decisions use raw risk.
- Human pins require approval before substitution. Capability filtering remains.
- Preserve the one-split budget and five-round cap. Reserve cannot return to execution.
- Use disposable local fixtures and bounded processes, without paid model calls.
- Preserve unrelated `plugins/darkmem-resume/` work. Do not commit or publish.

## Task 1: Verify the new routing contract

File: `plugins/dr-superpowers/tests/native-routing.test.sh`.

- [x] Add explicit raw-axis examples for each score 0–9 and the approved pairs.
- [x] Exercise omitted/incorrect score, invalid axes, both Rule S triggers,
  Terra capability gaps, reviewer floors, human pins, and old policy rejection.
- [x] Add history cases for reassigning attempted tasks, empty escalation,
  malformed history, reserve without a split, and renewed execution availability
  after max/ultra. Retain review/split termination coverage.
- [x] Run the bounded test before production edits and confirm intended failures.

Request fields: `policy`, `operation`, `role`, `assignment_source`,
`available_pairs`, `attempted_ranks`, `attempted_reserves`, `split_consumed`,
`review_rounds`, and either rubric `axes: {files,spec,coupling,risk}` with optional
`score`, or a human `pinned_pair`. The output retains action/reason/model/effort
and execution rank, and includes the calculated score for rubric decisions.

## Task 2: Implement scoring and escalation

Files: `plugins/dr-superpowers/reference/codex-routing.json` and
`plugins/dr-superpowers/scripts/select-native-tier.sh`.

- [x] Install the approved ten-row table, policy version, and role floors 6/8.
- [x] Validate one JSON request, policy version, axes, score, and attempt history.
- [x] Calculate the weighted score before selection and enforce Rule S for rubric
  assignments. Human pins bypass rubric selection, not capability/user policy.
- [x] Evaluate reserve continuation before execution choices. Block after ultra;
  reject attempts to restart or forge structurally inconsistent history.
- [x] Run native tests and inspect the actual decision JSON on boundary cases.

## Task 3: Integrate the policy and verify compatibility

Files under `plugins/dr-superpowers/`: `reference/native-codex.md`,
`reference/ladder.md`, `README.md`, the three `skills/*/SKILL.md` host branches,
`.claude-plugin/plugin.json`, and `.codex-plugin/plugin.json`.

- [x] Document the exact request, score calculation, table, and migration preview.
  Distinguish native weighted score from Claude's total in all shared host branches.
- [x] Preserve prior assignments/axes/history during explicit conversion. Refuse
  to reinterpret active old-policy ranks. Explain human override request fields.
- [x] Mark external CLI capability evidence as historical and bump both manifests
  from 0.5.0 to 0.6.0.
- [x] Run bounded native, Claude ladder/lane/fleet/criteria/hook regressions and
  repository tests; validate the Claude plugin manifest and whitespace.
- [x] Record measured results, remaining limits, and process cleanup in the spec.

## Execution record

Completed inline. The marketplace smoke assertion now compares the installed
version with the source manifest, and external-lane test wording identifies its
historical policy instead of claiming live account availability. No external
CLI routing values or Claude agent assignments changed.

Validation: 86 native routing assertions and 280 Claude compatibility assertions
passed, along with 13 Node tests, repository validation, Claude manifest
validation, and 20 isolated real-client marketplace checks. Version 0.6.0 was
installed successfully. All owned test runners exited. Paid model behavior and
live plan conversion were not evaluated; migration is documented and old-policy
requests fail closed.
