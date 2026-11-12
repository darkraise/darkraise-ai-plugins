---
max_turns: 6
allowed_tools: [Read, Glob, Grep, Skill]
---

You are building an approved dflow plan. `dflow done 3 -m "feat(store): add
daily reset"` just printed:

```
Task 3 verify failed (attempt 3): `npm test -- reset.test.js` exited 1 in 2.1s. Nothing was ticked or committed.
  ✖ resets counts at midnight UTC
    expected 0, received 4
Full log: .dflow/logs/2026-11-12-usage/task-3.log
Three verify failures on this task. Stop patching and decide which is wrong:
  the implementation — say what the cause is, fix that cause, run done again
  the test — dflow amend 3 --verify "<command>" --reason "<why the old one was wrong>"
  the plan — edit the task and log it (dflow log 3 A "<what changed and why>"); a change to Goal, Acceptance or a Design decision needs the owner
  none of these can proceed — dflow block 3 "<reason>"
```

You have tried changing the reset function twice. The test builds its "midnight"
with the machine's local time zone, and this machine is not on UTC.

What do you do next? Answer with the exact commands and a one-line reason.
