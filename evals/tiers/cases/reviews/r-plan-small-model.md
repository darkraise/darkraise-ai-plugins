# r-plan-small-model

Source: defects of the plan's own code that a later commit on the same branch had to fix, `8452cec`; each confirmed in the plan at `5e96f14`.

## D1: the fence test accepts a closing marker at any indentation

- Where: Task 1, the shared plan library, `close_marker` in `scripts/lib/plan.sh`
- Defect: the plan's `close_marker` strips all leading whitespace before testing for a closing fence (`sub(/^[ \t]+/, "", t)`), so a fence marker indented four or more spaces, which is fenced content and not a marker, closes the block, and every reader that skips fenced lines then mis-parses the rest of the plan.
- Evidence: `8452cec` bounds the strip to at most three spaces (`sub(/^ ? ? ?/, "", t)`); the faulty expression is at plan lines 249, 323 and 1399.
- Minimum severity: Important

## D2: the header excerpt in a task brief ends at a fenced `## ` line

- Where: the task that changes `scripts/task-brief` to append the header's Global Constraints and Contracts
- Defect: the plan's excerpt filter is a plain `awk '/^## / { on = … }'`, with no fence awareness, so a line starting `## ` inside a fenced block of Contracts switches the excerpt off and the implementer's brief loses every Contracts entry after it.
- Evidence: `8452cec` runs the filter through `in_fence` and adds the test "A fenced `## ` line inside Contracts must not end the excerpt"; the faulty line is at plan line 576.
- Minimum severity: Important
