#!/usr/bin/env bash
# Sourced by the tests that pin text of the subagent-driven-development skill.
# SDD is its SKILL.md; each SDD_* below is a reference that holds text moved
# out of it to keep SKILL.md under 20 KB. sdd_text prints all of them, for a
# pin that asserts a phrase appears nowhere in the skill.
SDD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills/subagent-driven-development" && pwd)"
SDD="$SDD_DIR/SKILL.md"
SDD_BATCHING="$SDD_DIR/references/batching.md"
SDD_BUDGET="$SDD_DIR/references/budget.md"
SDD_EXAMPLE="$SDD_DIR/references/example-workflow.md"
SDD_FINISH_RULINGS="$SDD_DIR/references/finish-rulings.md"
SDD_GRAPH="$SDD_DIR/references/process-graph.md"
SDD_LEDGER="$SDD_DIR/references/ledger.md"
SDD_RATIONALE="$SDD_DIR/references/rationale.md"
SDD_RATIONALIZATIONS="$SDD_DIR/references/rationalizations.md"
SDD_RULING_SEAT="$SDD_DIR/references/ruling-seat.md"
SDD_SETUP="$SDD_DIR/references/setup.md"

sdd_text() {
  cat "$SDD" "$SDD_BATCHING" "$SDD_BUDGET" "$SDD_EXAMPLE" "$SDD_FINISH_RULINGS" "$SDD_GRAPH" \
    "$SDD_LEDGER" "$SDD_RATIONALE" "$SDD_RATIONALIZATIONS" "$SDD_RULING_SEAT" "$SDD_SETUP"
}
