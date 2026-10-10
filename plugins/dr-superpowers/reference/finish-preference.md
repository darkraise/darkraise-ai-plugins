# Finish Preference

A run ends while its human is away more often than not. Without this, the
finishing menu waits forever and the finished branch sits unintegrated. So the
finish action is asked once, before the first task, and
dr-superpowers:finishing-a-development-branch carries it out when its menu goes
unanswered for 30 minutes. An answer to the menu inside those 30 minutes always
wins over the choice made here.

`scripts/finish-choice` keeps the choice (see using-superpowers §Session
Budget). Pass `--plan PLAN_FILE` in a plan run; leave it out for work done
without a plan.

## When to ask

- **A plan run** (dr-superpowers:subagent-driven-development or
  dr-superpowers:executing-plans): at Setup, before the pre-flight and Task 1.
  Skip the question when `scripts/finish-choice get --plan PLAN_FILE` already
  prints a choice, or when the plan's ledger already exists: a resumed run
  never stops to ask, and its finishing menu simply waits.
- **Work without a plan** that you will finish with
  finishing-a-development-branch (implementation on its own branch or
  worktree, straight from the chat): before the first change, once
  dr-superpowers:using-git-worktrees has the workspace ready.
- Never in the middle of a run, and never again once answered.

## The question

Determine the base branch first, as finishing Step 3 would (the plan, the
conversation, the branch's upstream), so the merge option names it. Then ask
exactly this, as the last thing in the message:

```
Before I start: when the implementation is done, the finish menu waits for
your answer. If it gets none within 30 minutes, what should I do?

1. Merge back to <base-branch> locally
2. Push and create a Pull Request
3. Keep the branch as-is
4. Nothing: wait for my answer

Which option?
```

From a detached HEAD the merge option does not exist: offer "Push as new
branch and create a Pull Request", "Keep as-is" and "Nothing: wait for my
answer".

Ask before this run writes anything to its ledger: the stop hook holds a turn
that wrote a ledger and ends on anything but the next step. Record the answer,
with the base branch the merge option named, and start work in the same turn:

```bash
bash <plugin-root>/scripts/finish-choice set <merge|pr|keep|wait> --base <base-branch> [--plan PLAN_FILE]
```

An answer that is not one of the options (a question, a change of plan) is
handled first; ask again only if it left the choice open. Asking is the only
pause this adds: a run never stops again for it.

## At the finishing menu

finishing-a-development-branch Step 4 arms the choice as it shows the menu:

```bash
bash <plugin-root>/scripts/finish-choice arm [--plan PLAN_FILE]
```

Exit 3 means nothing to arm (no choice, `wait`, or already answered): show the
menu as usual. Otherwise it prints three lines:

- `cron: …` — on Claude Code, schedule the wake with the CronCreate tool, that
  cron expression and `recurring: false`, then record the job id it returns
  with `scripts/finish-choice job <id> [--plan PLAN_FILE]`.
- `due: HH:MM` — the menu's last line before `Which option?` becomes
  `No answer by HH:MM: I'll <the chosen option, as worded in the menu>
  (chosen before the run).`
- `prompt: …` — the wake prompt; pass it to CronCreate verbatim.

Without a scheduler (Codex, or a host with no CronCreate tool), nothing can
wake the session: say `Chosen before the run: <option>. Reply to confirm or pick
another.` on that line instead, and wait.

## When your human partner answers

Any answer to the menu inside the 30 minutes, whichever option it names, is
theirs: run `scripts/finish-choice answer <merge|pr|keep|discard> [--plan
PLAN_FILE]` before acting on it. It prints the wake's job id when there is one;
cancel it with the CronDelete tool. Then carry out their choice.

## When the wake fires

The wake prompt runs `scripts/finish-choice due [--plan PLAN_FILE]`:

| Exit | Meaning | Do |
|---|---|---|
| 0, prints the action | Unanswered and due | Carry it out from finishing Step 5, with the recorded base branch (`scripts/finish-choice get`), exactly as if your human partner had chosen it |
| 3 | Answered, already handled, or never armed | Nothing; end the turn in one line |
| 4 | Woke early | Nothing; the menu still stands |

An unattended finish stops where an attended one would ask: a merged result
that fails its tests, a rejected push, a worktree whose removal is refused.
Leave everything in place, report what stopped it, and end with the menu
again without arming it; never pick a destructive answer for your human
partner. Open the final
message with `No answer within 30 minutes, so I went with <option>, as chosen
before the run.`
