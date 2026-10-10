# Parallel waves

How dr-superpowers:subagent-driven-development runs a plan whose header says
`**Parallelism:** waves — …`. A plan without that line, or with
`**Parallelism:** sequential`, never reads this file. The design is
`docs/superpowers/specs/2026-10-10-parallel-waves-design.md` in the plugin's
repository.

## The invariant

**Running a wave one task after another is always correct.** plan-lint holds
every waves plan to contiguous, ascending ranges, and to `**Depends on:**`
lines that point only into earlier waves, so a wave's tasks in index order are
exactly the sequential run. Every doubt therefore serializes, and nothing here
ever widens a wave. A wave of one task is an ordinary task: the task loop runs
it in the checkout, with no Wave lines, no worktree and no merge.

Serialize the rest of a wave, logging `Wave <k>: serialized — <reason>` and a
`Ruling:` line, when:

- the pre-flight seat returned a CONFIRMED-GAP `serialize Task <a> and Task <b>`
  for a pair in it;
- an Agent call with `isolation: "worktree"` is refused, or this host has no
  such option (a Codex host never reaches this file: plan-lint refuses waves
  there);
- the integration check fails on the wave's base (§1);
- `scripts/context-size --wave 2` says `handoff` (§1);
- your human partner says so.

Tasks already running in worktrees finish and merge as below; the tasks not
yet dispatched then run through the ordinary task loop in index order, and the
integration check still runs once they are all complete.

## The ledger lines

The shared grammar ([subagent-driven-development](../skills/subagent-driven-development/SKILL.md)
§The Ledger) gains these lines for a wave of more than one task:

```
Wave <k>: started (base <sha7>; Tasks <a>-<b>; at most <c> at once)
Wave <k>: serialized — <reason>
Wave <k>: check failed — <command> → <one-line summary>
Wave <k>: fix round R/5 (<the fields of a task's fix round>)
Wave <k>: integrated (head <sha7>; <command> → pass)
```

A wave task's assigned line ends `; wave <k>`, and its complete line carries
`; merged <sha7>` after the commit range. `complete` keeps its meaning: the
task is reviewed and on the branch. `scripts/next-step` and every other reader
of `Task <N>:` lines read a waves ledger unchanged.

## 1. Open the wave

At a wave boundary — every earlier task complete, every earlier wave
`integrated` or `serialized`:

1. **Name the wave.** `scripts/wave list PLAN_FILE` prints the waves. Take
   the next one.
2. **Prove the base.** Unless the last `Wave <j>: integrated` line names the
   current `HEAD`, run the plan's `**Worktree setup:**` (when it is not `none`)
   and `**Integration check:**` in the checkout, bounded like any long command.
   A failure here is not this wave's: serialize the wave and record the
   output's summary in the Ruling, so the next wave's check is not blamed on
   it.
3. **Size it.** `c` starts at the smaller of the wave's width and 3. Run
   `scripts/context-size --wave <c>` and lower `c` while it exits 5; it
   reserves one task's worst growth for every task beside the first. `c = 1`
   serializes the wave, and `scripts/context-size` alone then decides between
   the next task and a handoff, exactly as in sequential mode.
4. **Check the checkout.** `git status --porcelain --untracked-files=no` is
   empty; commit your own bookkeeping first if it is not.
5. **Log** `Wave <k>: started (base <sha7>; Tasks <a>-<b>; at most <c> at once)`.

## 2. Dispatch in parallel

Dispatch up to `c` tasks of the wave in one message. Each is
[delegated-task.md](delegated-task.md) §1 with three differences:

- **The Agent call passes `isolation: "worktree"`** and, as always, no `model`
  or `effort`. The worktree Claude Code creates is the task's: its Bash runs
  there, and its edits cannot reach your checkout.
- **The base is this checkout's `HEAD` at dispatch** (the wave's base for the
  first `c` tasks, the merged head for a task that starts when a slot frees).
  The worktree is not created from it, so the dispatch tells the implementer
  to detach there first.
- **The dispatch carries the parallel section below**, filled in, after the
  brief line. Everything else in [implementer-prompt.md](../skills/subagent-driven-development/references/implementer-prompt.md)
  is unchanged.

```
## Parallel workspace

You run beside other implementers, each in a worktree of its own. Before
anything else, in your worktree:

1. `git switch --detach [START]`
2. `bash [PLUGIN_ROOT]/scripts/sdd-workspace [PLAN_FILE]` — write your
   report as `task-[N]-report.md` in the directory it prints, which is inside
   your worktree and ignored by git. [PRIOR_REPORT]
3. Run the worktree setup once before your first test: [WORKTREE_SETUP]

After every commit, run `git branch -f [TASK_REF] HEAD`; if git reports a
lock, wait a second and run it again. Never switch to or change another
branch, never run `git worktree`, `git stash` or `git push`, and never
touch a file outside your task's **Files:** list: another implementer may
own it. A test that fails because a shared resource is busy (a port in use,
a database lock) is run once more; if it fails again, report
DONE_WITH_CONCERNS and name the resource.

Add two lines to your short report: `**Worktree:**` with the output of
`git rev-parse --show-toplevel`, and `**Head:**` with the short SHA of HEAD.
```

- `[START]` — the base SHA for a first dispatch; `[TASK_REF]` for a fresh
  dispatch on a task that already has commits.
- `[TASK_REF]` — `scripts/wave ref PLAN_FILE <N>`.
- `[PRIOR_REPORT]` — empty on a first dispatch; on a fresh dispatch,
  `First copy <workspace>/task-<N>-report.md there and append to it.`
- `[WORKTREE_SETUP]` — the plan's `**Worktree setup:**` command, or `none`.

Write each assigned line, ending `; wave <k>`, in the message that dispatches
it. While tasks run, keep working as subagent-driven-development's Waiting on
dispatched subagents says; every report that arrives is handled at once.

## 3. Review each task on its own

As each implementer reports, copy its report file from the `**Worktree:**` it
named into the plan workspace as `task-<N>-report.md`; that copy is what
reviewers and any later dispatch read, because the worktree is removed in §5.
Then run delegated-task.md §2-§4 for that task, unchanged, with two
substitutions:

- **HEAD is the task ref.** The review package is
  `scripts/review-package PLAN_FILE <base> <TASK_REF>`; a scoped re-review's
  FIX_BASE is the task ref's commit the previous review saw. Both run from
  your checkout: the worktrees share its objects.
- **A resumed implementer is still in its worktree.** A fresh dispatch — the
  cache rule, an escalation, a split part — is a new parallel dispatch (§2)
  with `[START]` set to the task ref, and its report is copied back the same
  way.

Every finding, ruling and verdict is the task's own, exactly as in sequential
mode. Rulings for several tasks that arise together share one ruling-seat
dispatch, as they always do at one decision point.

## 4. Merge each task as it passes

When a task's review is clean, or every open finding is parked at the breaker,
merge it before writing its complete line:

```bash
bash scripts/wave merge PLAN_FILE <N> <task base>
```

- **Exit 0, `merged Task <N>: <sha7>`.** Write the complete line with
  `; merged <sha7>`. A `note:` line names a file outside the task's
  **Files:** list: the review already judged scope, so copy each note into
  the ledger as `Task <N>: minor (deferred): changed <file> outside its Files`.
  Start the next task of the wave if one is waiting and
  `scripts/context-size --wave <running + 1>` allows it.
- **Exit 1, `overlap` or `did not merge cleanly`.** The task changed a file a
  merged sibling also changed. Nothing was merged. This is the task's next fix
  round: a fresh parallel dispatch with `[START]` set to this checkout's
  `HEAD`, the merge output, and the instruction to re-apply the task on top of
  what is merged; log
  `Task <N>: fix round R/5 (rebased on <sha7>: overlap <files>; …; fresh (overlap))`,
  then a scoped re-review and the merge again. It counts toward the five
  rounds. The rebased task's base is now that `HEAD`: the re-review's
  FIX_BASE, the `wave merge` argument and the complete line's range all start
  there, because the task ref no longer descends from what the last review
  saw.
- **Exit 3, the checkout is not clean.** Something wrote into your checkout.
  Run `git status`, keep the change recoverable with
  `git stash push -m "wave <k> stray changes"`, log a Ruling naming it, and
  merge again.

Never merge a task by hand, never resolve a conflict yourself, and never
rebase or rewrite a task ref: the review saw those commits.

## 5. Integrate

When every task of the wave has a complete line:

1. `bash scripts/wave clean PLAN_FILE <k> <wave base>` removes the worktrees
   the wave's tasks committed in and deletes their merged refs. It never
   forces: a `kept` line is a worktree with uncommitted changes or a lock,
   left for your human partner; log each as a `Ruling:` line.
2. Run the plan's `**Worktree setup:**` (when it is not `none`) and its
   `**Integration check:**` in the checkout, bounded like any long command,
   with the output written to `<workspace>/wave-<k>-check.txt`.
3. **Pass:** log `Wave <k>: integrated (head <sha7>; <command> → pass)` and
   go to the next wave.
4. **Fail:** log `Wave <k>: check failed — <command> → <summary>` and run the
   wave's fix loop: delegated-task.md §4 with the check output as its one
   finding, the wave's highest-ranked `**Implementer:**` agent as the
   implementer, dispatched in your checkout without isolation (nothing else
   runs now), every task brief and report of the wave as its context, and
   this framing: "Each of these tasks passed its own review; merged together,
   the integration check fails. Find the interaction and make the smallest
   fix." Each round's scoped re-review covers the fix diff; you re-run the
   check after it, and the round passes only when the check does. Log rounds
   as `Wave <k>: fix round R/5 (…)`. At the cap, the open failure goes to the
   ruling seat as a `breaker` item against the wave's last task.

## Session budget

A wave is the unit a budget `handoff` waits for: on a `handoff` verdict from
any brief or review package, start no new task, finish every task already
dispatched through its complete line, integrate the wave, then invoke
dr-superpowers:handoff. §1's `--wave` check is what makes that room.

## Recovery

A `Wave <k>: started` line with no later `Wave <k>: integrated` or
`Wave <k>: serialized` line is a wave in flight. After compaction:

1. Run `bash scripts/wave status PLAN_FILE <k> <wave base>`: each task's ref,
   its commits since the base, whether it is merged, and the worktrees holding
   it.
2. For each task of the wave, apply the Recovery table of
   subagent-driven-development as usual, reading `git log <base>..<TASK_REF>`
   where it reads `git log <base>..HEAD`, and the workspace copy of the
   report. The agent ids are gone, so every dispatch is a fresh parallel
   dispatch (§2) from the task ref, or from the wave base when it has no ref.
   A task reviewed clean but not yet merged has no complete line: review it
   again, then merge.
3. A task with a complete line and `merged no` was logged before its merge
   finished: run `scripts/wave merge` for it again.
4. When every task is complete, continue at §5.

Live children are reconciled first, exactly as dr-superpowers:handoff step 0
says.

## Common rationalizations

| Excuse | Reality |
|--------|---------|
| "These two tasks touch different files, so the seat's coupling row is noise" | The seat found an interaction the file lists cannot show. Serialize the pair. |
| "The merge conflict is two lines, I'll resolve it" | You never edit code. The task gets a fresh round on the merged head and a review of the result. |
| "The integration check is slow; the task reviews were clean" | Clean reviews of tasks alone say nothing about the tasks together. The check is the wave's gate. |
| "Four tasks are ready, I'll start all four" | At most three run at once, and only as many as `context-size --wave` allows. |
| "The budget says handoff, but the other tasks are nearly done" | Finish what is dispatched, integrate, then hand off. Start nothing new. |
| "Serializing wastes the plan's waves" | Serializing is always correct; a wrong parallel run is a bug that every later wave builds on. |
