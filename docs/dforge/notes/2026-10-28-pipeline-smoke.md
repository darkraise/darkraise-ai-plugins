# Pipeline smoke: can `claude -p` drive the whole task loop?

Run on 2026-10-28 with Claude Code 2.1.312 (Claude Code), plugin commit 2c3add12, in a temporary root with its own HOME, XDG and CLAUDE_CONFIG_DIR (only .credentials.json copied in from the session). Spec: docs/dforge/specs/2026-10-27-speed-and-cost-design.md, Riskiest assumption.

Every run used `claude -p --model sonnet --effort high --permission-mode bypassPermissions --setting-sources project,local --output-format stream-json --verbose --no-session-persistence` with `IS_SANDBOX=1`, a budget cap of $1 for P1 and $8 for P2, and a timeout of 420 s and 1500 s.

## P1: a background Bash command and a subagent, then continue after both notifications

A `claude -p` session started `sleep 25` in the background and a general-purpose Agent running `sleep 15` in one message, ended its turn, and was asked to print one line after both completion notifications.

Assistant messages (id, stop_reason, tools):

```
msg_011CgTjZywkQajFAAQEx3p25		Bash
msg_011CgTjZywkQajFAAQEx3p25		Agent
msg_011CgTjaC7jVgFGEE4nZ6fhJ		
msg_011CgTjaBrMq6hS9xLnq7cCe		Bash
msg_011CgTjbZAHwP7vzhEwR8w7X		
msg_011CgTjbdhuJLVByibe7YZg7		
msg_011CgTjbzHQNmaPRKY9pDWPm		
msg_011CgTjbzHQNmaPRKY9pDWPm		Read
msg_011CgTjcCaZx3UqnM6LUQs2y		
```

- Both calls in one message: msg_011CgTjZywkQajFAAQEx3p25
- Final result: `PROBE-COMPLETE suite=SUITE-DONE judge=JUDGE-DONE`
- Cost, turns, milliseconds: 0.0381567	2	4371
- Outcome: pass

## P2: one task through the current plugin's task loop

A one-task plan (docs/plan.md, Task 1 on `dforge:impl-sonnet-low`) in an isolated clone; `claude -p --plugin-dir plugins/dforge` was told to run dforge:subagent-driven-development through the `Task 1: complete` line. The finished test was overlaid after the run and executed.

Task 1 ledger lines:

```
Task 1: implementer impl-sonnet-low (assigned; base 4fd0198)
Task 1: minor (deferred): bin/greet:1 — file mode is 100644, not executable
Task 1: minor (deferred): tests/greet.test.sh:8 — empty-string argument edge case is untested
Task 1: minor (deferred): bin/greet committed as mode 100644 (not executable); no test for `greet ""`
Task 1: Ruling: cannot-verify (test pass claim unopened by reviewer) — controller re-ran `bash tests/greet.test.sh` at 263837a → 2/2 ok, exit 0 — none
Task 1: complete (commits 4fd0198..263837a, review clean; 2 minor deferred; scores spec 20 / scope 20 / verification 16 / quality 17, seat dforge:judge-sonnet-high) — done: bin/greet and tests/greet
```

Hidden test:

```
ok   - greets by name
ok   - defaults to world
```

- Cost, turns, milliseconds: 0.41851839999999996	6	17669
- Outcome: pass

## Caveats

The cost, turn and millisecond figures above come from the last `result` event of each run only, so they are not run totals: P1's 4371 ms cannot cover a run that includes `sleep 25`, and a session that resumes after a completion notification emits more than one `result` event. Do not size the pipeline stage's cost cap or timeouts from them.

The P1 timeline lists every assistant message, subagent messages included, because its jq has no `parent_tool_use_id` filter. The second `Bash` and the `Read` therefore cannot be attributed to the main session from that table, and the Conclusion's no-polling reading rests on the `parent_tool_use_id`-filtered check, whose output this note does not show.

The plan's `p1_overlap` check collected tool names per stream event, which finds no overlap when the two tool uses of one message arrive as separate events with the same message id. It was changed mid-run to group tool uses by message id, which is why the note reports `pass` for the message id above. The historical plan keeps the original check.

## Conclusion

Under `claude -p` a turn that ends on pending background work resumes on each completion notification, and the controller finished a task loop without a human. The pipeline stage can drive `claude -p`; design section 5 stands.

**Verdict:** HEADLESS
