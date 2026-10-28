## Auto run

When `scripts/auto-run status` exits 0, this plan is written unattended
([auto-run.md](../../../reference/auto-run.md)). Run `scripts/auto-run phase plan`
first. Then nothing in this skill waits on your human partner:

- **The execution strategy:** take the spec's `**Execution strategy:**` line;
  with none, take the `executionStrategy` setting (`parallel` by default) as
  Parallel waves says, and write `sequential` when it is `ask`.
- **An approach or planning choice** you would ask about goes to
  `dforge:judge-opus` first, then the ladder in auto-run.md §Rulings.
  dforge:selecting-approaches runs as usual otherwise.
- **The executor offer:** tick only what a constraint ticks without asking;
  start no timed question.
- **At the review cap,** a Critical finding or a score of 8 or below goes on
  the pending list, and the Fable batch rules on it with the rest.
- **Once the plan is reviewed** (at depth light, once it is linted):
  `scripts/auto-run attach --plan PLAN_FILE`,
  the Fable batch when `scripts/auto-run decision list` prints anything, then
  the switch instead of Execution Handoff: when the spec's `## Decisions`
  holds a `Finish: <action>` line, `scripts/finish-choice set <action> --plan
  PLAN_FILE`; dforge:handoff steps 0-3 only; `scripts/next-step PLAN_FILE`
  (on exit 5, wait for or stop what `scripts/in-flight` lists and run it
  again, as auto-run.md §The switch step 3 says);
  then `scripts/auto-run switch` and end the turn with `Auto run: switching`
  as its last line, as auto-run.md §The switch says.
- **One plan.** An auto run writes one plan for the whole spec and amends it
  in place through the ruling seat's AMEND path (`scripts/plan-amend`); it
  never writes a follow-up plan or a second plan version.
