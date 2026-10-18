# Finish Preference

A run ends while its human is away more often than not, and a finishing menu
nobody answers leaves the finished branch unintegrated. So the finish action
is asked once, before the first task, and
dforge:finishing-a-development-branch carries it out as soon as the final
review is clean, with no menu and no wait. Choosing "Ask me then" keeps the
menu.

`scripts/finish-choice` keeps the choice (see using-dforge §Session
Budget). Pass `--plan PLAN_FILE` in a plan run; leave it out for work done
without a plan.

## Auto run

An auto run ([auto-run.md](auto-run.md)) never asks the question below:
finishing carries out `finishAction` at once into the run's recorded base
(`merge` or `pr`), and keeps the branch under `keep`, `ask` or `wait`, or when
there is no base, with no menu.

## The setting

`finishAction` (`scripts/dforge-config`, or the cockpit's Finish tab): `ask`,
the default, keeps the question below. With `merge`, `pr`, `keep` or `wait`,
`scripts/finish-choice get` records and prints that action whenever nothing is
chosen yet, so the question is never asked: the "skip the question when `get`
prints a choice" rule already covers it. A choice recorded this way has no base
branch (`base` is null): finishing finds it as its Step 4 says.

## When to ask

- **A plan run** (dforge:subagent-driven-development or
  dforge:executing-plans): at Setup, before the pre-flight and Task 1.
  Skip the question when `scripts/finish-choice get --plan PLAN_FILE` already
  prints a choice, or when the plan's ledger already exists: a resumed run
  never stops to ask: finishing carries out the choice recorded at its
  start, or shows its menu when there is none.
- **Work without a plan** that you will finish with
  finishing-a-development-branch (implementation on its own branch or
  worktree, straight from the chat): before the first change, once
  dforge:using-git-worktrees has the workspace ready.
- Never in the middle of a run, and never again once answered.

## The question

Determine the base branch first, as finishing Step 3 would (the plan, the
conversation, the branch's upstream), so the merge option names it. Then ask
exactly this, as the last thing in the message:

```
Before I start: when the implementation is done and its final review is
clean, what should I do?

1. Merge back to <base-branch> locally
2. Push and create a Pull Request
3. Keep the branch as-is
4. Ask me then: show the finish menu and wait for my answer

Which option?
```

From a detached HEAD the merge option does not exist: offer "Push as new
branch and create a Pull Request", "Keep as-is" and "Ask me then: show the
finish menu and wait for my answer".

Ask before this run writes anything to its ledger: the stop hook holds a turn
that wrote a ledger and ends on anything but the next step. Record the answer,
with the base branch the merge option named, and start work in the same turn
("Ask me then" records `wait`):

```bash
bash <plugin-root>/scripts/finish-choice set <merge|pr|keep|wait> --base <base-branch> [--plan PLAN_FILE]
```

An answer that is not one of the options (a question, a change of plan) is
handled first; ask again only if it left the choice open. Asking is the only
pause this adds: a run never stops again for it.

## At finishing

finishing-a-development-branch Step 4 reads the choice after its in-flight
check. A `merge`, `pr` or `keep` with no `answer` field is carried out at once,
with no menu: the step records it with `scripts/finish-choice answer`, finds
the base without asking, and stops wherever an attended finish would ask.
`wait`, nothing recorded, or a record already answered shows the menu. Step 4
holds the full rule.

## When your human partner answers the menu

Run `scripts/finish-choice answer <merge|pr|keep|discard> [--plan PLAN_FILE]`
before acting on the answer, then carry it out.
