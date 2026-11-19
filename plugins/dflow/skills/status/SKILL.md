---
name: status
description: Use when asked where the work stands, what to do next, whether a plan is done, or for a checkpoint - reports the active plan, the board, gates, review and exactly one next step. Writes nothing.
---

# Status

State now (run `dflow status` if nothing follows):

!`node "${CLAUDE_PLUGIN_ROOT}/bin/dflow" status`

Report it to the owner: the outcome first, then the one step on the `Next` line. Add a `Check` or `Blocked` line only if one is printed. Do not start the next step unless asked.

For more, on request:

- `dflow plans --conflicts`: open plans in every worktree, and whether two of them touch the same files.
- `dflow ship --check`: each condition of the definition of done that is unmet.
- `dflow doctor`: doc budgets, dead path references, the board and open plans.
- `dflow cost`: the plan's token use by phase and model.
