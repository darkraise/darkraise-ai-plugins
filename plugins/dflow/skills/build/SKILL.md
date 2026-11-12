---
name: build
description: Use to execute an approved dflow plan, or to continue one after a break, a /clear or a compaction - builds each task test-first and closes it with `dflow done`, which runs the task's verify command and makes the commit.
argument-hint: "[plan file]"
---

# Build

State now (run `dflow status` if nothing follows):

!`node "${CLAUDE_PLUGIN_ROOT}/bin/dflow" status`

The plan file and the git history hold all task state. Do not rebuild it from memory, and do not edit checkboxes by hand: `dflow` is the only writer of task state.

## The loop

1. `dflow next` prints the task's brief. Work from the brief, not from the whole plan.
2. Write the tests the task lists. Run them and see them fail for the reason you expect.
3. Implement the general behaviour until they pass. Change only the task's `Files`. Never hard-code a value or branch on a test's input to pass it.
4. `git add` the task's files, then:

   ```
   dflow done <N> -m "<type>(<scope>): <subject>"
   ```

   It runs the verify command. On success it ticks the task, commits the staged code with the plan, and prints the next brief: go to step 2. The subject is imperative, at most 50 characters, with no attribution line.

Run a slow command in the background and wait for its notification; do not poll. Run only the task's tests while building: the full suite runs once, at ship.

## When `dflow done` refuses

- **Verify failed.** Nothing was ticked or committed. Read the output, state the cause in one sentence, and fix that cause. Do not run it again unchanged.
- **Third failure.** Make the choice it prints: the implementation is wrong, the test is wrong (`dflow amend`), the plan is wrong, or the task is blocked.
- **Files outside the task.** Unstage them, or pass `--extra "<why they belong>"` when they truly do.
- **A test proves less.** Restore it. Pass `--weaken "<reason>"` only when removing it is right, and say so in your report.

## Decisions, amendments, blockers

- A decision the plan left open is yours: decide, then `dflow log <N> D "<decision — reason>"`. A trap worth remembering: `dflow log <N> G "<symptom — cause>"`.
- A task's steps or files turn out wrong: fix the plan and `dflow log <N> A "<what changed and why>"`.
- A change to Goal, Acceptance or a Design decision is the owner's: stop and ask.
- A hard blocker: `dflow block <N> "<reason>"`, continue with the task it names, and report every blocked task at the end.

## A `RESET:` line

When `dflow done` prints `RESET:`, end your turn at once with one line saying which task comes next. The build resumes from the plan in a smaller context; nothing is lost.

## A task with a risk

When `dflow done` says the task carries a risk, review it before building on it: `dflow review pack --task <N>`, dispatch one `dflow:reviewer` with the pack's path, fix what `dflow review verify` shows reproduced, then `dflow review record --tier 1 --task <N>`.

## Waves

When two or more ready tasks are marked `Run: worker`, `dflow wave` lists the ones that can run together.

1. For each: `dflow worktree add <N>`. It prints a one-line prompt.
2. Dispatch one `dflow:worker` per task, all in a single message, each with its printed line as the whole prompt, model sonnet, effort low, medium or high for size S, M or L.
3. As each returns: `dflow worktree merge <N>`, then `dflow done <N> -m "…"` as for any task.
4. A worker that failed: send it the failing output once. A second failure: `dflow worktree drop <N>` and build the task yourself.

A single worker task is built inline: delegation buys time only when tasks run side by side.

## When every task is done

Continue with the dflow:review skill.
