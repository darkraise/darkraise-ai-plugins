## Execution Handoff

A saved, reviewed plan is a hard stop (except at depth light, below): execution
starts in a fresh session (in
an auto run the session switches in place instead; see Auto run).
Invoke dforge:handoff. It commits (or pushes) the plan and the spec, writes
`<latest.md>`, runs `scripts/next-step PLAN_FILE`, and ends
your message with the resume guide — the launch command from the Execution
line and the first prompt for the skill that line names. Offer no execution
choice: the Execution line already made it.

The exception is a plan at depth light, which is no hard stop outside an auto
run (an auto run switches at every depth). A light plan of 4 or more tasks
still ends with dforge:handoff as above. A light plan of 1-3 tasks runs
dforge:handoff steps 0-4 only (reconcile background work, commit the plan and
the spec, write the handoff notes, `scripts/next-step PLAN_FILE`), so that
`latest.md` names this plan, then plain `scripts/context-size`: the task
budget, not `--plan`, which measures room to write a plan. On `ok`, say in one
line that the Execution line's model and effort are not applied in this
session, and invoke the skill that line names; print no resume guide. On any
other result, run handoff step 5 and end the session as above. The task count
decides only this, never the depth.
