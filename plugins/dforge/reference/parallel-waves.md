# Parallel waves

How dforge:subagent-driven-development runs a plan whose header says
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
it in the checkout, with no `started` line, no worktree and no merge, and it
closes by §5 like any wave.
Every wave closes with an `integrated` or a `merged` line, one-task and serialized waves included.

Serialize the rest of a wave, logging `Wave <k>: serialized — <reason>` and a
`Ruling:` line, when:

- the pre-flight seat returned a CONFIRMED-GAP `serialize Task <a> and Task <b>`
  for a pair in it;
- an Agent call with `isolation: "worktree"` is refused, or this host has no
  such option (a Codex host never reaches this file: plan-lint refuses waves
  there);
- the base proof fails on a failure the baseline does not hold (§1);
- `scripts/context-size --wave 2` says `handoff`, or `compact` in an auto run
  (§1);
- your human partner says so.

Tasks already running in worktrees finish and merge as below; the tasks not
yet dispatched then run through the ordinary task loop in index order, and the
wave still closes by §5 once they are all complete.

## The ledger lines

The shared grammar ([subagent-driven-development](../skills/subagent-driven-development/SKILL.md)
§The Ledger) gains these lines (`started` only for a wave of more than one task):

```
Wave <k>: started (base <sha7>; Tasks <a>-<b>; at most <c> at once)
Wave <k>: serialized — <reason>
Wave <k>: check failed — <command> → <one-line summary>
Wave <k>: fix round R/2 (<the fields of a task's fix round>)
Wave <k>: merged (head <sha7>; check at wave <m>)
Wave <k>: integrated (head <sha7>; <command> → pass[; baseline failures only])
Group <list>: review round R/2 (Task <N>: <k> open — <one-liners> | clean; …; commits <a7>..<b7> (Task <N>)[, <a7>..<b7> (Task <M>)])
```

`<m>` is the next wave `scripts/wave check-due` prints `full` for. `merged`
closes a wave as `integrated` does.

A wave task's assigned line ends `; wave <k>`, and its complete line carries
`; merged <sha7>` after the commit range. `complete` keeps its meaning: the
task is reviewed and on the branch. `scripts/next-step` and every other reader
of `Task <N>:` lines read a waves ledger unchanged.

## 1. Open the wave

At a wave boundary — every earlier task complete and
every earlier wave closed by its `integrated` or `merged` line:

1. **Name the wave.** `scripts/wave list PLAN_FILE` prints the waves. Take
   the next one.
2. **Prove the base.** The last `Wave <j>: integrated` or `Wave <j>: merged`
   line proves the base when its head is `HEAD`,
   or an ancestor of `HEAD` with no task commits between:
   `git merge-base --is-ancestor <sha7> HEAD` holds and every commit
   `git log --format='%h %s' --name-only <sha7>..HEAD` lists is your own
   bookkeeping (the ledger, amendments, a register or the roadmap; no path any
   task's `**Files:**` names). Then nothing reruns.
   Only a task commit outside any wave forces the fallback proof: the header's
   Wave check (amendments applied) when it has one, else the full Integration
   check, after the plan's `**Worktree setup:**` (when it is not `none`) in the
   checkout, through
   `bash <plugin-root>/scripts/suite-run -- bash -c '<the check>'`, in the
   background when it can outrun Bash's ten-minute cap. With no closing line
   yet (the first wave), the proof is the full check.
   A failing proof whose failures all appear in the file the previous proof
   wrote (compared as §5 step 5 says) is the known red baseline: log a
   `Ruling:` naming the count and open the wave. Any other failure, including
   a digest that shows `last 30 lines of <log>:` (it names no test), is not
   this wave's: serialize the wave and record the digest's summary in the
   Ruling, so the next wave's check is not blamed on it.
   A proof that ran the full check then writes
   `<workspace>/base-proof-failures.txt` (`<workspace>` is what
   `scripts/sdd-workspace PLAN_FILE` prints): the digest's failing-test lines,
   one per line, exactly as `suite-run` prints them; when its `counts:` line
   names more than 20 failures, every matching line of the log it names,
   `grep -E '^[[:space:]]*(not ok|\(fail\)|FAIL)' <log> | cut -c1-200`; empty
   on a pass.
3. **Size it.** `c` starts at the smaller of the wave's width and 3. Run
   `scripts/context-size --wave <c>` and lower `c` while it exits 5 (or 6, an
   auto run's `compact`); it reserves one task's worst growth for every task
   beside the first. `c = 1` serializes the wave, and `scripts/context-size`
   alone then decides between the next task and a handoff, exactly as in
   sequential mode: within the plan's last two tasks that is
   `scripts/context-size --tail <R>`, the line their briefs print.
4. **Check the checkout.** `git status --porcelain --untracked-files=no` is
   empty; commit your own bookkeeping first if it is not.
5. **Log** `Wave <k>: started (base <sha7>; Tasks <a>-<b>; at most <c> at once)`.

For a wave of one task, run step 2 only, then the task loop in the checkout.

A ledger written before this boundary rule may hold earlier waves with no
closing line: a wave whose tasks are all complete counts as closed, and the
base proof (step 2) then finds task commits after the last closing line.

## 2. Dispatch in parallel

Dispatch up to `c` tasks of the wave in one message. Each is
[delegated-task.md](delegated-task.md) §1, opened with
`bash <plugin-root>/scripts/task-step start PLAN_FILE N --wave <k>`, with three
differences:

- **The Agent call passes `isolation: "worktree"`** and, as always, no `model`
  or `effort`. The worktree Claude Code creates is the task's: its Bash runs
  there, and its edits cannot reach your checkout.
- **The base is this checkout's `HEAD` at dispatch** (the wave's base for the
  first `c` tasks, the merged head for a task that starts when a slot frees).
  The worktree is not created from it, so the dispatch tells the implementer
  to detach there first.
- **The dispatch carries the parallel section below**, filled in, after the
  line naming the dispatch file. Everything else in [implementer-prompt.md](../skills/subagent-driven-development/references/implementer-prompt.md)
  is unchanged.

```
## Parallel workspace

You run beside other implementers, each in a worktree of its own. Before
anything else, in your worktree:

1. `bash [PLUGIN_ROOT]/scripts/wave enter [PLAN_FILE] [N] [START]` — it
   detaches at `[START]` and marks the worktree as this task's, which is what
   lets the wave's clean-up remove it later
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

`task-step start --wave <k>` writes each assigned line, ending `; wave <k>`, and
its dispatch file; call it for every task in the message that dispatches them.
The dispatch file does not hold the section above: add the filled Parallel
workspace section to each Agent prompt, after the line naming the dispatch
file. While tasks run, keep working as subagent-driven-development's Waiting on
dispatched subagents says; every report that arrives is handled at once.

## 3. Review each task on its own

As each implementer reports, copy its report file from the `**Worktree:**` it
named into the plan workspace as `task-<N>-report.md`; that copy is what
reviewers and any later dispatch read, because the worktree is removed in §5.
Then run delegated-task.md §2-§4 for that task, unchanged, with two
substitutions:

- **HEAD is the task ref.** Pass `--head <TASK_REF>` to
  `task-step review PLAN_FILE N` and to `task-step rereview PLAN_FILE N`: the
  review package then runs from the recorded base to the task ref, and a
  scoped re-review's FIX_BASE is the task ref's commit the previous review saw,
  which `task-step` recorded. Both run from your checkout: the worktrees share
  its objects. Give `review` also `--cwd <worktree>`, so that a Codex seat's
  printed runner command runs in the task's worktree and not in your
  checkout.
- **A resumed implementer is still in its worktree.** A fresh dispatch — the
  cache rule, an escalation, a split part — is a new parallel dispatch (§2)
  with `[START]` set to the task ref, and its report is copied back the same
  way.

**Grouped tasks.** A wave task graded `review=group` is not reviewed on its
own. When it reports DONE, run
`task-step hold PLAN_FILE N --head <TASK_REF> --cwd <worktree>`: the group
review then checks the task's worktree for edits, not your checkout, whose
HEAD a sibling reviewed alone may move by merging meanwhile.
Then, once every grouped task in the wave is held, before any of them merges, run
one `task-step review --group PLAN_FILE <their numbers>` and dispatch its seat
([delegated-task.md](delegated-task.md) §3a). Each member keeps its held head
as its review head, so
a member's fix round goes to that task's implementer in its worktree,
re-reviewed with `task-step rereview PLAN_FILE N --head <TASK_REF>`.

Every finding, ruling and verdict is the task's own, exactly as in sequential
mode. Rulings for several tasks that arise together share one ruling-seat
dispatch, as they always do at one decision point. The `cannot-verify` items
of every task whose review is in hand when one task reaches its cannot-verify
point go to one dispatch, written with `<kind>` `cannot-verify` and every
such task number. A task not yet reviewed, or not yet dispatched, never holds
that dispatch back: its items wait for its own decision point.

## 4. Merge each task as it passes

When a task's review is clean (or, for a grouped task, its group is clean), or
every open finding is parked at the breaker, merge it before writing its
complete line:

```bash
bash scripts/wave merge PLAN_FILE <N> <task base>
```

- **Exit 0, `merged Task <N>: <sha7>`.** Write the complete line with
  `; merged <sha7>`. In an auto run, run `scripts/auto-run task-complete`
  right after it, before any budget check or dispatch; the Fable batch runs
  after the wave. A `note:` line names a file outside the task's
  **Files:** list: the review already judged scope, so copy each note into
  the ledger as `Task <N>: minor (deferred): changed <file> outside its Files`.
  Start the next task of the wave if one is waiting and
  `scripts/context-size --wave <running + 1>` allows it.
- **Exit 1, `overlap` or `did not merge cleanly`.** The task changed a file a
  merged sibling also changed. Nothing was merged. This is the task's next fix
  round: a fresh parallel dispatch with `[START]` set to this checkout's
  `HEAD`, the merge output, and the instruction to re-apply the task on top of
  what is merged; log
  `Task <N>: fix round R/2 (rebased on <sha7>: overlap <files>; …; fresh (overlap))`,
  then a scoped re-review and the merge again.
  It counts toward the two rounds. Past round 2 the overlap goes to the
  breaker like any open finding (`task-step rereview` exits 7 there). The
  rebased task's base is now that `HEAD`: the re-review's FIX_BASE, the
  `wave merge` argument and the complete line's range all start there, because the task ref no longer descends from what the last review
  saw. Pass that `HEAD` to the scoped re-review as
  `task-step rereview PLAN_FILE N --head <TASK_REF> --base <that HEAD>`; the
  state line it prints then shows it as the task's base, which is the
  `wave merge` argument.
- **Exit 3, the checkout is not clean.** Something wrote into your checkout.
  Run `git status`, keep the change recoverable with
  `git stash push -m "wave <k> stray changes"`, log a Ruling naming it, and
  merge again.

Never merge a task by hand, never resolve a conflict yourself, and never
rebase or rewrite a task ref: the review saw those commits.

## 5. Close the wave

When every task of the wave has a complete line:

1. For a wave of more than one task,
   `bash scripts/wave clean PLAN_FILE <k> <wave base>` removes the worktrees
   the wave's tasks entered and committed in, and deletes their merged refs.
   It never forces: a `kept` line is a worktree with uncommitted changes or a
   lock, left for your human partner; log each as a `Ruling:` line.
2. Run `bash <plugin-root>/scripts/wave check-due PLAN_FILE <k>`. It prints
   which check closes the wave: `full`, `wave-check` or `none`.
3. `full`: run the plan's `**Worktree setup:**` (when it is not `none`) in the
   checkout, then its `**Integration check:**` through
   `bash <plugin-root>/scripts/suite-run -- bash -c '<the check>'`, in the
   background when it can outrun Bash's ten-minute cap. The digest and the log
   path it prints replace a hand-made output file. `wave-check`: run the
   header's Wave check (amendments applied) through `suite-run` the same way.
   `none`: run nothing.
4. **Pass:** after a full check, log
   `Wave <k>: integrated (head <sha7>; <command> → pass)`; after a Wave check
   or none, log `Wave <k>: merged (head <sha7>; check at wave <m>)`. Then go
   to the next wave.
5. **Red baseline.** A failing check whose failing lines, taken as in §1, all
   appear in `<workspace>/base-proof-failures.txt` counts as passing: a full
   check logs
   `Wave <k>: integrated (head <sha7>; <command> → pass; baseline failures only)`,
   and a Wave check logs an ordinary merged line. Compare with TAP numbers
   removed on both sides (`sed -E 's/^([[:space:]]*not ok) [0-9]+/\1/'`); the failures
   are a subset when the baseline file exists, `<current>` holds at least
   one line, and `grep -vxFf <baseline> <current>` exits 1 (it printed
   nothing); only then. A missing baseline file, an empty `<current>`, or a grep exit
   of 2 is not a subset: go to step 6. A
   digest that names no test (`last 30 lines of <log>:`) is never the
   baseline.
6. **Fail:** any other failure logs
   `Wave <k>: check failed — <command> → <summary>` and runs the wave's fix
   loop: delegated-task.md §4 with the digest and its log as its one finding,
   dispatched in your checkout without isolation (nothing else runs now), and
   this framing: "Each of these tasks passed its own review; merged together,
   the check fails. Find the interaction and make the smallest fix." The fix
   dispatch gets every task diff since the last passing check, the last
   `Wave <j>: integrated` line: the diff
   `bash <plugin-root>/scripts/review-package PLAN_FILE <its head> HEAD`
   writes (from the first wave's base when there is none), and the brief and
   report of every task merged since. The implementer is the highest-ranked
   `**Implementer:**` agent among those tasks. Each round's scoped re-review
   is the by-hand one (*The steps by hand* in delegated-task.md): no task's
   `task-step` state fits a fix to the merged wave, so `task-step rereview` is
   not used here. It covers the fix diff; you re-run the check through
   `suite-run` after it, and the round passes only when the check does. Log
   rounds as `Wave <k>: fix round R/2 (…)`. At the cap, the open failure goes
   to the ruling seat as a `breaker` item against the wave's last task.

## Session budget

A wave is the unit a budget `handoff` waits for: on a `handoff` verdict from
any brief or review package, start no new task, finish every task already
dispatched through its complete line, integrate the wave, then invoke
dforge:handoff. §1's `--wave` check is what makes that room.

## In-flight runs

None is exempt. A run whose ledger holds an earlier cadence ruling (a full
check only every tenth wave because the baseline was red, say) follows this
cadence from its next wave boundary once the installed plugin carries it.
The earlier ruling is superseded by this cadence and the red-baseline rule,
and you log one `Ruling:` line saying so. A plan without a Wave check line
runs the full check on this cadence and nothing between; a Header AMEND in
`amendments.md` can add one without editing the plan file.

## Recovery

A `Wave <k>: started` line with no later `Wave <k>: integrated` or `Wave <k>: merged` line
is a wave in flight (a serialized wave included); a wave whose tasks are all
complete and has no closing line continues at §5. After compaction:

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

An older run's `Wave <k>: fix round R/5` line: R = 1 resumes at round 2,
R >= 2 goes to the breaker.

Live children are reconciled first, exactly as dforge:handoff step 0
says.

## Common rationalizations

| Excuse | Reality |
|--------|---------|
| "These two tasks touch different files, so the seat's coupling row is noise" | The seat found an interaction the file lists cannot show. Serialize the pair. |
| "The merge conflict is two lines, I'll resolve it" | You never edit code. The task gets a fresh round on the merged head and a review of the result. |
| "The integration check is slow; the task reviews were clean" | Clean reviews of tasks alone say nothing about the tasks together. `wave check-due` decides when the full check runs, never you; the check it names is the wave's gate. |
| "Four tasks are ready, I'll start all four" | At most three run at once, and only as many as `context-size --wave` allows. |
| "The budget says handoff, but the other tasks are nearly done" | Finish what is dispatched, integrate, then hand off. Start nothing new. |
| "Serializing wastes the plan's waves" | Serializing is always correct; a wrong parallel run is a bug that every later wave builds on. |

## Auto run

In an auto run ([auto-run.md](auto-run.md)) `--wave` prints the run's verdict.
Lower the width while it says `compact`, as on `handoff`; a narrower width that
fits cancels the compaction. At width 1 a `compact` verdict means finishing
the task in flight and ending the turn with `Auto run: compacting`. A task the
run defers is not merged, and `scripts/wave clean` keeps its ref: its deferred
ledger line and register row name that unmerged task ref
(`scripts/wave ref PLAN_FILE <N>`), since its commits lie outside the final
review's range ([auto-run.md](auto-run.md) §Rulings).
