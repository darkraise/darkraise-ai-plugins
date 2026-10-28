# Switching to subagent mode

Inline mode has one exit, and it runs in one direction. Take it when:

- your human partner says to;
- a task is still failing its own verifications after `fix round 3/3`;
- a ruling-seat CONFIRMED-GAP names a fix you have attempted and failed.

The trigger is mechanical, so the switch is your ruling, not a seat verdict:
the seat's four verdicts say nothing about execution mode. It happens only at a
task boundary where every earlier task is complete.

1. Append `Task <N>: escalated inline -> subagent — <trigger>`, where `<N>` is
   the task that will run first under subagent mode - the failing task, or,
   on your human partner's instruction, the next task not yet started. This
   line is the switch: every trigger writes it, with or without a preceding
   fix-round line.
2. Log, and say aloud, `Ruling: switch to subagent mode at Task <N> —
   <trigger> — if wrong, the remaining tasks each cost one dispatch that inline
   would not have spent`.
3. Do not edit the plan. `**Execution:**` is one of the lines
   `scripts/plan-amend` refuses to touch, and the ledger is where the switch is
   recorded.
4. Invoke dforge:handoff. The switch is always a handoff: subagent
   mode's value is a fresh controller that reads the header and one brief at a
   time, and this session's context is full of implementation detail it does
   not need. In an auto run, run dforge:handoff steps 0-4, then
   `scripts/auto-run clear --phase`, and end the turn with
   `Auto run: clearing` as its last line; a `next-step` exit 4 or 5 there is
   handled as auto-run.md §Clears says; a phase clear never counts as a
   self-resume.

Your human partner may also move a plan the other way, from subagent mode to
this one. Only their explicit instruction does that, and only at the same kind
of boundary. The return takes effect at the first remaining task that is not delegated:
only its `implementer inline (assigned` line records the return, so delegated
tasks before it still run under subagent mode.
