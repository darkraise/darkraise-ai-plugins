# Switch, finish-question and ledger-path fixes

**Execution strategy:** sequential — three small fixes that all touch the
dforge version files and the auto-run skill pins.

**Register:** docs/superpowers/registers/2026-10-18-auto-execution-default.md
(rows 13-15)

**Approach:** inline - skip 1: each root cause was located by the 2026-10-19
end-to-end probe of row 11

## Decisions

The owner's answers on 2026-10-19.

1. Row 13 gets both the skill-text fix and a script guard on
   `scripts/auto-run phase execute`.
2. The plan executes sequentially.

## Problem

The row 11 probe ran a real auto run and an attended run of a one-task plan in
a scratch repository and found three defects.

1. **The switch skips execution Setup (row 13).** After the in-place switch, a
   compaction summary sits above the plan's first prompt, so the execution
   skill follows its After compaction steps. Those steps read the workspace and
   the ledger and continue from it; with no ledger yet they go straight to
   Task 1 and never reach Setup, where the worktree is created. The probe's
   auto run committed its task and its final-review fixes to `main`, the run's
   base, and its `Finish: keep` had no effect. Before the switch existed,
   plan saved cleared the session, and the fresh session started at Setup.
2. **The attended finish question is asked twice (row 14).** On the
   "Approve, keep the normal stops" path, the spec review records
   `Finish: <action>` in the spec's `## Decisions`. Execution Setup is told to
   use that line instead of asking, but `scripts/finish-choice get` does not
   read the spec and finish-preference.md's When to ask does not mention it, so
   the skip depends on the controller opening the spec. A Sonnet low controller
   did not, and asked again.
3. **The ledger can land where no script looks (row 15).** using-dforge
   documents `dforge-path ledger <plan>`, but the command treats its argument
   as a slug. Given `docs/dforge/plans/2026-10-19-greet.md`, it printed
   `.dforge/sdd/docs/dforge/plans/2026-10-19-greet.md`, and the attended run
   wrote its ledger there. `next-step`, `task-brief` and a resumed run read
   `.dforge/sdd/2026-10-19-greet/progress.md` and would not find it.

## Design

### Setup after the switch (row 13)

**Skill text.** dforge:executing-plans and dforge:subagent-driven-development
each get a new first step in `## After compaction`, before reading the
workspace:

> When this plan's ledger (`<ledger dir>/progress.md`) does not exist, no task
> has started: this is the first prompt after an auto run's switch, or a
> compaction before Task 1. Skip the rest of this section and follow Setup
> from its first step; the worktree comes first.

The remaining steps keep their order and numbering after it. auto-run.md
§The switch, in the paragraph that ends "follow the first prompt in this same
session", adds that the execution skill starts at Setup, worktree first, since
no ledger exists yet.

**Script guard.** `scripts/auto-run start` records `checkout`, the absolute
physical path (`pwd -P` form) of the top level it ran in. `scripts/auto-run
phase execute` compares the caller's top level, in the same form, with
`checkout`; when they are equal it changes nothing, prints

    auto-run: this is the checkout the run started in; create the execution worktree first (dforge:using-git-worktrees), then run auto-run phase execute from it

to stderr and exits 4. After a switch `phase` is already `execute`
(`ar_switch` sets it), so the exit code and the message are what the
controller sees. A state without `checkout`, written before this
change, uses the primary checkout (`ar_primary_root`) in its place. Every
other phase, and the phase `ar_switch` sets internally, is unaffected. The
two execution skills' Auto run Setup bullet says to run `phase execute` from
the execution worktree, and that exit 4 means the worktree step was skipped:
create it, then run the command again. An auto run always creates the
worktree (dforge:using-git-worktrees), so the refusal never blocks a correct
run.

### The spec's finish line (row 14)

`scripts/finish-choice get --plan PLAN_FILE`, with no `finish.json` yet,
reads the plan's `**Spec:**` header line with `plan_header_line` from
`scripts/lib/plan.sh`, strips backticks as `next-step` does, resolves it against the repository top level, and looks in that
spec's `## Decisions` section (up to the next `## ` heading) for a line that
is exactly `Finish: merge`, `Finish: pr` or `Finish: keep`, optionally with
trailing spaces. When one is found it records
`{action, base: null, chosenAt, source: "spec"}` and prints it, as the
setting fallback does. Order, first match wins:

1. a recorded `finish.json`;
2. the spec's `Finish:` line;
3. the `finishAction` setting, when it is not `ask`;
4. exit 3.

A missing plan header line, a missing spec file or no matching line falls
through to step 3. Without `--plan` nothing changes. finish-preference.md's
When to ask states that `get` reads the spec's `Finish:` line, so the
existing rule "skip the question when `get` prints a choice" covers a spec
review's answer. The execution skills' sentence "When the spec's
`## Decisions` holds a `Finish: <action>` line, run `scripts/finish-choice
set …` instead of asking" stays as a backstop. finishing-a-development-branch's
Auto run rule already accepts a choice recorded any way but the setting, so
it needs no change.

### Ledger path (row 15)

`dforge-path ledger ARG` accepts a slug or a plan path: when ARG contains
`/` or ends in `.md`, it uses `basename ARG .md`, the same reduction
`sdd-workspace` and `task-brief` apply. The usage line reads
`ledger SLUG|PLAN_FILE`. `dforge_ledger_dir` in `scripts/lib/roots.sh` stays
as it is: every script caller already passes a slug.

### Version

dforge goes from 4.0.0 to 4.0.1 in `.claude-plugin/plugin.json` and
`.codex-plugin/plugin.json`.

## Testing

`tests/auto-run.test.sh` covers the recorded checkout and the refusal, and
its two existing `phase execute` calls run from a linked worktree of the test
repository. `tests/finish-choice.test.sh` covers the four-step order and
the lines that must not be read. `tests/roots.test.sh`, which already
exercises `dforge-path`, covers the plan-path form. `tests/auto-run-skills.test.sh`
pins the new After compaction step in both execution skills, the auto-run.md
sentence, the Setup bullet's worktree wording and the finish-preference.md
line.

## Acceptance

A1. [test, high] dforge:executing-plans and dforge:subagent-driven-development each open `## After compaction` with a step that sends a session whose plan has no ledger to Setup's first step.
A2. [test, high] auto-run.md §The switch states that the execution skill starts at Setup, worktree first, after the switch.
A3. [test, high] `scripts/auto-run start` records `checkout` as the physical top level it ran in.
A4. [test, neg, high] `scripts/auto-run phase execute` run from the recorded checkout exits 4 with the message naming dforge:using-git-worktrees and leaves `phase` unchanged; run from a linked worktree of the same repository it sets `phase` to `execute` and exits 0.
A5. [test, high] With no `checkout` in the state, the primary checkout stands in for it in A4.
A6. [test, high] `scripts/finish-choice get --plan` with nothing recorded and a spec `Finish: keep` line in `## Decisions` records and prints `keep` with `"source": "spec"`, even when `finishAction` is `merge`.
A7. [test, high] A recorded `finish.json` outranks the spec's line, and a spec without the line falls through to the `finishAction` setting and then to exit 3.
A8. [test, neg, high] A `Finish:` line outside `## Decisions`, or one whose value is not exactly `merge`, `pr` or `keep` (such as `3. Finish: "Ask at spec review"`), is not read.
A9. [test, high] finish-preference.md's When to ask states that `get` reads the spec's `Finish:` line.
A10. [test, high] `dforge-path ledger docs/dforge/plans/2026-10-19-greet.md` prints the same directory as `dforge-path ledger 2026-10-19-greet`.
A11. [demo, high] Rerunning the row 11 probe's auto run leg, the switched session creates the execution worktree before Task 1, and the run's base branch gains no task commit.

## Riskiest assumption

That the skill text and the guard together are enough for a low-effort
controller. The guard is hit only when the controller runs `phase execute`,
which the probe's controller did as its first command; a controller that
skips that command too would still commit on the base branch. A11 checks the
observed case on a real engine.
