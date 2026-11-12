---
name: ship
description: Use when a dflow plan is built and reviewed, or to check whether it is done - proves UI acceptance lines in the running app, checks the whole definition of done, promotes logged decisions into the living docs and closes the board row.
---

# Ship

## 1. See what is unmet

```
dflow ship --check
```

It lists every condition of the definition of done that does not hold. Fix each:

- **A task is not done or is blocked**: go back to the dflow:build skill.
- **A UI line has no proof, or a stale one**: follow the Proof section of `${CLAUDE_PLUGIN_ROOT}/skills/plan/ui.md`.
- **No review, or a blocking finding is open**: the dflow:review skill.
- **A doc named in `Docs:` is unchanged**: update it now so that it describes the system after this change, within its line budget, and commit it (`docs: …`). `decisions.md` and `gotchas.md` are written for you from the plan's `D:` and `G:` log lines; add those lines with `dflow log` if a decision worth keeping was never logged.
- **doctor**: fix what it names. A dead path in `project.md` means the doc still describes a file that is gone.

## 2. Ship

```
dflow ship
```

It runs the gates and the acceptance commands on the current commit, then promotes the log, marks the plan shipped, moves the board row to done and commits. Run it in the background when the gates are slow, and wait for the notification. If a gate or an acceptance command fails, fix the cause and run it again; do not report the plan as done.

## 3. After it succeeds

1. When the darkmem memory tools are connected, file the facts it printed with one `memory_batch_add`: one fact per entry, one to three sentences, tagged `project/<name>`.
2. Offer the owner the choice it names: open a pull request, or merge. Push only after they say so. Commit messages and pull request text carry no attribution line.
3. Report: the outcome first, then what was verified and by which command, any declined finding, and anything not verified.

`dflow cost` shows the plan's token use by phase when the owner asks.
