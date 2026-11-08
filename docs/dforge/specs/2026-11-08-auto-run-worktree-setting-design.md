# Auto runs follow the worktree setting

**Execution strategy:** sequential — inline execution; the guard in
`scripts/lib/auto-run.sh` is read by every skill change that follows it.
**Depth:** full — risk

## Goal

An auto run stops creating its execution worktree unconditionally. It follows
the `worktree` setting (`ask`, `always`, `never`) the way an attended run
does: `always` creates the worktree without asking, `never` works in the
primary checkout on a branch of its own, and `ask` asks — at the one stop an
auto run has, the spec review, or at the auto-run offer when the run starts
from there.

Today `skills/using-git-worktrees/SKILL.md:41` creates the worktree in every
auto run and ignores `worktree=never`, and `scripts/lib/auto-run.sh`
(`ar_set_phase`, `ar_task_complete`) refuses execution in the primary checkout,
so working in place is impossible. The guard's purpose (its comment at
`scripts/lib/auto-run.sh:30-32`) is that an unattended run never commits a task
onto its base branch; the primary-checkout test is a stand-in for that rule.

## Decisions

- **Flow.** Asked fast mode or the full flow; answer: "Full dforge flow
  (Recommended)".
- **Where `never` commits.** Asked where an in-place run's commits go; answer:
  "New branch in place (Recommended)" — at execution setup the run switches the
  primary checkout to a new feature branch (`git switch -c`); tasks commit
  there, and finishing merges it or opens a pull request as usual.
- **Uncommitted changes.** Asked what an in-place run does when the primary
  checkout is dirty at setup; answer: "Carry them along" — the branch switch
  carries them, and they stay uncommitted.
  Spec review: staged changes cannot be carried, since `git commit` commits
  the whole index; when the index holds any, setup stops the run and names
  the paths (Fable ruling F1).
- **Guard.** Asked how `scripts/lib/auto-run.sh` guards a run that may work in
  the primary checkout; answer: "Refuse on the base branch (Recommended)" —
  the primary-checkout test is replaced by a branch test, one rule for a
  worktree and for in-place work.
  Spec review: the primary-checkout test stays for `worktree` runs; a
  detached linked worktree has no branch to record.
- **Decided while writing** (the spec review can overturn each):
  - The resolved choice is stored in the run's state as
    `isolation: "worktree" | "in-place"`, passed by
    `scripts/auto-run start --isolation <worktree|in-place>`. A state file
    without the field, or a start without the flag, reads as `worktree`, so a
    run started before this change behaves as today.
  - The in-place branch is named `auto/<plan slug>`, the slug derived exactly
    as `ar_start` derives the register slug (`scripts/lib/auto-run.sh:193-195`:
    the filename without `.md` and its date prefix), with `-2`, `-3`, …
    appended until the name is free. Setup records it in the state; a later
    Setup or a resume switches back to the recorded branch and never creates
    another.
  - Carried-along changes are protected mechanically, not by convention
    (critic Blocker): the dirty paths at setup are recorded, a commit that
    includes one is refused at `task-complete`, `phase final` and
    `phase finish`, and the recovery and QA-cleanup steps skip them.
  - A task with an `**Executor:**` line in an in-place run falls back to the
    session: the external lanes require an exclusive linked worktree
    (`scripts/lib/task-state.sh:200`). writing-plans' auto-run executor offer
    ticks nothing when the run's isolation is `in-place`; the run-time
    fallback covers attended sessions in the primary checkout.
- **Suite reuse.** Asked at the spec review how to handle suite-run never
  reusing a pass while carried paths dirty the tree; answer: "Accept the cost
  (Recommended)" — no code change, the cost is stated.
- **Early CI.** Asked at the spec review whether to run CI early on the pushed
  branch; answer: "No early run (Recommended)".

Early CI: none

- **Finish.** Asked at the spec review how the run finishes; answer: "Open a
  pull request (Recommended)".

Finish: pr

## Design

### Resolving the choice

The skill that starts the run resolves `isolation` once, before
`scripts/auto-run start`:

| `worktree` setting | Question | `isolation` |
|---|---|---|
| `always` | none | `worktree` |
| `never` | none | `in-place` |
| `ask` (default) | asked at the spec review or the offer | the answer |

- **Spec review (`autoRun=on`).** `skills/brainstorming/references/auto-by-default.md`
  step 5 gains one question when the setting is `ask`, asked in the last call,
  beside the approval question: **Isolated worktree (Recommended)** or
  **Work in place on a new branch — leave this checkout alone until the run
  finishes**. The answer is recorded in `## Decisions` as its own paragraph,
  one `Worktree: <worktree|in-place>` line, as the `Finish:` line is. Step 6
  passes `--isolation` from it, or from the setting under `always`/`never`.
- **Offer (`autoRun=ask`).** Under `worktree=ask`, the offer in
  `references/auto-run-offer.md` has three options: `1. Yes, in an isolated
  worktree`, `2. Yes, in place on a new branch (leave this checkout alone
  until the run finishes)`, `3. No, keep the normal stops`; 1 and 2 pass
  `--isolation worktree` and `--isolation in-place`. Under `always` or
  `never` it keeps its two options and passes the setting's value.
- A user instruction naming a worktree preference outranks the setting, as
  using-git-worktrees Step 0 already says.

### Run state and the guard (`scripts/lib/auto-run.sh`, `scripts/auto-run`)

New state fields: `isolation` (set by `start`), and `branch`, `branchBase`
(the commit the branch was created at) and `carried` (a list of paths), set by
a new `scripts/auto-run setup-branch <name>` that Setup calls after creating
the branch. `setup-branch`:

- refuses (exit 4, nothing recorded) when HEAD is not on `<name>`, when
  `<name>` equals the state's `base`, or when any status line has an index
  column other than space or `?` (staged changes), printing those paths;
- records as `carried` every path `git status --porcelain=v1 -z
  --untracked-files=all` lists, so an untracked directory yields each file
  and a rename yields both its old and new path.

`ar_status` prints `— isolation <value>` and, once recorded, `— branch <name>`;
`scripts/auto-run carried` prints the carried paths, one per line.

The guard (`ar_guard`) refuses when any of these holds:

1. HEAD's branch (`git symbolic-ref --short -q HEAD`) is the state's `base`,
   or HEAD is detached while `base` is null;
2. `isolation` is `in-place`, a `branch` is recorded, and HEAD is not on it;
3. `isolation` is `worktree` and the session is in the primary checkout (the
   current test, kept for worktree runs).

The carried check (`ar_carried_hit`) is true when a path of
`git diff --name-only <branchBase>..HEAD` is in `carried`.

- `phase execute` refuses (exit 4, phase unchanged) on the guard. The message
  names the remedy for the state's isolation: create the worktree, or switch
  to the run's branch (dforge:using-git-worktrees Step 0).
- `task-complete` stops the run (exit 5) on the guard during the execute or
  final phase, or on the carried check; the stop reason names the path.
- `phase final` and `phase finish` refuse (exit 4, phase unchanged) on the
  carried check, naming the path. The execution skills' final-review step and
  finishing's auto-run section treat that exit 4 as
  `scripts/auto-run stop --reason "<path> is a carried path and was committed"`.
- `start --isolation` rejects any value other than `worktree` or `in-place`
  (exit 2, no state written). The "setup due" hint in `scripts/auto-run`, and
  the switch prompt in `scripts/next-step:562`, read "workspace first"
  instead of "worktree first".

### Setup (`skills/using-git-worktrees/SKILL.md` Step 0)

In an auto run the skill reads the run's state (`scripts/auto-run status`)
instead of the `worktree` setting. Before the "already in a linked worktree"
skip, in any checkout:

- A recorded `branch` exists: switch to it when HEAD is elsewhere, and go on.
- No branch is recorded and HEAD is the run's base (or detached): under
  `in-place`, or in a linked worktree under either isolation, run
  `git switch -c auto/<plan slug>` (with the collision suffix), then
  `scripts/auto-run setup-branch <name>`. Unstaged and untracked changes are
  carried. On a staged-changes refusal, run
  `scripts/auto-run stop --reason "staged changes in the primary checkout: <paths>"`
  and end as auto-run.md §Stopping says.
- Under `worktree` in the primary checkout: create the worktree without
  asking, as today; the sandbox fallback still stops the run.

The execution skills' Setup lines (`skills/executing-plans/SKILL.md`,
`skills/subagent-driven-development/SKILL.md`, `reference/auto-run.md` §The
switch) say "from the execution workspace" — the worktree, or the checkout on
the run's branch — and their exit-4 remedy is "follow
dforge:using-git-worktrees Step 0 for the run, then run the command again".
`reference/auto-run.md` §Skipped questions names the worktree consent as
asked at the spec review under `worktree=ask`. "A side effect outside the
worktree" (`reference/auto-run.md:182-184`) and "outside this worktree"
(`skills/executing-plans/SKILL.md:136`) become "outside the execution
workspace".

### Resume (`skills/resume-execution/SKILL.md`)

Step 2 gains, for an auto run whose `scripts/auto-run status` prints
`branch <name>`: when `git branch --list <name>` prints nothing, run
`scripts/auto-run stop --reason "the run's branch <name> is gone"` and ask;
when HEAD is not on it, `git switch <name>`; a refused switch stops the run
the same way. Step 3's EnterWorktree is skipped when the recorded workspace is
the primary checkout. `reference/auto-run.md` §Stopping adds "the run's branch
is gone" beside "a worktree whose branch is gone".

### Carried paths

- A task, fix round or acceptance QA run that needs to change a carried path
  does not: the run stops with `scripts/auto-run stop --reason "<task> needs
  carried path <path>"`. The carried check at `task-complete`, `phase final`
  and `phase finish` is the backstop for every commit the run makes.
- Tasks stage the paths they changed by name, never `git add -A` or
  `git add .` (executing-plans Setup).
- `skills/executing-plans/references/recovery.md`: "commit anything
  uncommitted" excludes the carried paths.
- `reference/final-review.md` QA timeout cleanup: a carried path is never
  restored or deleted, whatever its status line shows.
- The merged-result suite at finishing runs over the carried changes; a red
  result is reported with the carried paths listed, so its cause can be told
  apart from the run's own changes.
- Suite reuse: `scripts/suite-run` records a reusable pass only on a clean
  tree (`scripts/suite-run:14-18`), so while carried paths exist every suite
  run of the run executes in full (ci-mirror, the integration check,
  finishing's Step 1 and the merged result). This is the cost of `in-place`
  with a dirty checkout; there is no code change (owner's answer at the spec
  review).

### Executor lanes

`reference/executor-lane.md` §Reserve an exclusive linked worktree gains: in
the primary checkout, run `task-step start` as the executor path does (it
needs no linked worktree: `scripts/task-step` makes only temporary detached
worktrees for its baseline checks), then neither the gate nor the wrapper;
fall back to the session review loop as `reference/executor-lane.md:137-139`
describes, recording
`Task <N>: implementer inline (assigned; base <sha7>; executor <id> unavailable - no linked worktree)`.
Its sentence "The user can continue in the primary checkout" is limited to
worktree runs. The auto-run executor offer in
`skills/writing-plans/references/auto-run-plan.md` ticks nothing when
`scripts/auto-run status` reports `isolation in-place`.

### Finishing

An in-place run reaches dforge:finishing-a-development-branch in the primary
checkout on its recorded branch: Step 2 reads a normal repository, Option 1
checks out the base there, pulls and merges, Step 6 deletes only the plan
workspace, and the branch is deleted with `git branch -d`. The finishing
skill's auto-run stop list gains "a refused checkout, pull or merge of the
base" and the `phase finish` carried-check refusal. After finishing, the
carried changes are still uncommitted in the checkout, unchanged. For `pr` and
`keep` the checkout stays on `auto/<plan slug>` with the carried changes in
it, and the final message says so in one line ("This checkout is on
`auto/<slug>`; your uncommitted changes are here").

### Unchanged

The attended path of using-git-worktrees, the scratch worktrees dforge makes
for its own checks (`scripts/task-step`, the final review's integration run,
acceptance QA's mutation check), parallel waves, the `worktree` setting's
values and default, and the cockpit's switch-compaction sentence
(`hooks/cockpit/register.tsx:145`, "no execution worktree exists yet"), which
stays true of the plan phase.

## Files

- `plugins/dforge/scripts/lib/auto-run.sh`, `plugins/dforge/scripts/auto-run`,
  `plugins/dforge/scripts/next-step` (one wording change)
- `plugins/dforge/skills/using-git-worktrees/SKILL.md`
- `plugins/dforge/skills/resume-execution/SKILL.md`
- `plugins/dforge/skills/brainstorming/references/auto-by-default.md`,
  `plugins/dforge/skills/brainstorming/references/auto-run-offer.md`
- `plugins/dforge/reference/auto-run.md`, `plugins/dforge/reference/executor-lane.md`,
  `plugins/dforge/reference/final-review.md`
- `plugins/dforge/skills/executing-plans/SKILL.md`,
  `plugins/dforge/skills/executing-plans/references/setup.md`,
  `plugins/dforge/skills/executing-plans/references/recovery.md`,
  `plugins/dforge/skills/subagent-driven-development/SKILL.md`
- `plugins/dforge/skills/writing-plans/references/auto-run-plan.md` (executor
  offer)
- `plugins/dforge/skills/finishing-a-development-branch/SKILL.md` (auto-run
  stop list and the in-place final-message line)
- `plugins/dforge/config/schema.mjs` (the `worktree` description names auto
  runs)
- `plugins/dforge/README.md` wherever it says an auto run always uses a
  worktree
- Tests: `plugins/dforge/tests/auto-run.test.sh`,
  `plugins/dforge/tests/auto-run-skills.test.sh`,
  `plugins/dforge/tests/settings-skills.test.sh`, and a new
  `plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`
- Plugin manifests: a minor version bump

## Acceptance

A1. [test, high] `scripts/auto-run start --spec S --isolation in-place` records `isolation: "in-place"` in the state file, and `scripts/auto-run status` prints `isolation in-place`.
A2. [test, high] A start without `--isolation`, and a state file written before this change (no `isolation` field), both read as `isolation worktree`.
A3. [test, neg, high] `scripts/auto-run start --isolation elsewhere` exits 2 and writes no state file.
A4. [test, neg, high] `scripts/auto-run phase execute` exits 4 and leaves the phase unchanged when HEAD is the run's base branch, in the primary checkout and in a linked worktree alike.
A5. [test, high] In an `in-place` run, `phase execute` exits 0 in the primary checkout on the branch `setup-branch` recorded.
A6. [test, neg, high] In an `in-place` run with a recorded branch, `phase execute` exits 4 and `task-complete` exits 5 (run stopped) when HEAD is on any other branch, base or not.
A7. [test, neg, high] In a `worktree` run, `phase execute` exits 4 in the primary checkout even on a branch other than the base.
A8. [test, high] With no recorded base, `phase execute` exits 4 while HEAD is detached in the primary checkout and exits 0 on the run's recorded branch.
A9. [test, high] `setup-branch <name>` records `branch`, `branchBase` and, as `carried`, every modified and untracked path — each file of an untracked directory, and both sides of an unstaged rename — and exits 4, recording nothing, when HEAD is not on `<name>` or `<name>` is the run's base.
A10. [test, neg, high] `task-complete` exits 5 with the path in the stop reason when a commit since `branchBase` includes a carried path, and exits 0 when the commits touch only other paths.
A11. [test, high] A scripted in-place flow in a temporary repository — a dirty primary checkout, `git switch -c`, `setup-branch`, a task commit of a non-carried path, `task-complete`, then a merge into the base and `git branch -d` — leaves every carried path uncommitted, byte for byte as before setup.
A12. [test, high] Starting in a linked worktree on its base, the run reaches `phase execute` with exit 0 once Setup has switched to `auto/<plan slug>` and called `setup-branch`.
A13. [test, high] using-git-worktrees' auto-run paragraph reads the run's state, not the `worktree` setting: it switches to a recorded branch, creates `auto/<plan slug>` and calls `setup-branch` when HEAD is the base or detached (under `in-place`, or in a linked worktree), stops the run on staged changes, and creates the worktree without asking under `worktree` in the primary checkout.
A14. [test, high] auto-by-default.md asks the worktree question only under `worktree=ask`, in the last call beside the approval, records a `Worktree: <worktree|in-place>` line in `## Decisions`, and step 6 passes `--isolation`; auto-run-offer.md shows the three-option offer under `worktree=ask` and passes `--isolation`.
A15. [test, neg, high] No skill text says an auto run creates the worktree when `worktree=never` is set.
A16. [test, high] executor-lane.md tells a session in the primary checkout to run `task-step start`, then the task itself, recording `executor <id> unavailable - no linked worktree`; auto-run-plan.md ticks no executor when the run's isolation is `in-place`.
A17. [test, neg, high] recovery.md's "commit anything uncommitted" and final-review.md's QA timeout cleanup both exclude carried paths; the executing-plans Setup states by-name staging, and no auto-run Setup or task-loop text stages with `git add -A` or `git add .`.
A18. [test, high] The finishing skill's auto-run section lists a refused checkout, pull or merge of the base among the stops, and its final message names the run's branch for `pr` and `keep` in an in-place run.
A19. [test, high] resume-execution's step 2, for an auto run with a recorded branch, switches a HEAD that is elsewhere back to that branch before any task, and stops the run with "the run's branch <name> is gone" when the branch no longer exists.
A20. [test, neg, high] `phase final` and `phase finish` exit 4, phase unchanged, naming the path, when a commit since `branchBase` includes a carried path, and exit 0 otherwise.
A21. [test, neg, high] `setup-branch` exits 4, recording nothing and printing the paths, when the index holds a staged change.

## Riskiest assumption

Switching the primary checkout to a new branch mid-session leaves the run's
state, ledger and handoff in place, and every dforge step that assumes the
execution workspace's dirty files belong to the run is one this spec names.

Evidence: `.dforge/` is git-ignored (`git check-ignore -v
.dforge/sdd/auto-run.json` → `.gitignore:15`, run 2026-11-08), so a branch
switch does not touch it; the auto-run state path is computed from the primary
checkout (`ar_path`, `scripts/lib/auto-run.sh`); the cockpit treats only
`EnterWorktree`/`ExitWorktree` or a shell `cd` as a workspace move
(`hooks/cockpit/register.tsx:775`), and a branch switch is neither. The
dirty-file assumers found are recovery.md's `fix round … passing` row,
final-review.md's QA timeout cleanup (both covered) and suite-run's clean-tree
reuse test (a cost, stated above); the carried check at `task-complete`,
`phase final` and `phase finish` catches any commit the search missed before
it reaches the base. Parallel waves run only on a deprecated subagent plan and
give each task a worktree of its own.

## Review rulings

- Fable, spec: `isolation` field and `start --isolation`, default `worktree` — kept.
- Fable, spec: `auto/<plan slug>` branch — kept; `setup-branch` refuses the base as `<name>`, and the slug follows `ar_start`'s register slug.
- Fable, spec: mechanical carried-path protection — kept, amended by F1, F2 and F4.
- Fable, spec: executor fallback — kept; the offer rule lives in `auto-run-plan.md`, and the fallback runs `task-step start` before joining the session review loop.
- Fable, spec: "Carry them along" is the owner's answer and is not re-asked.
- Fable, spec: guard rule 3 kept, recorded under Guard in Decisions.
- Fable, spec: F1 — staged changes at setup stop the run with the paths named.
- Fable, spec: F2 — `phase final` and `phase finish` run the carried check (A20).
- Fable, spec: F3 — resume-execution switches back to the recorded branch, or stops when it is gone (A19).
- Fable, spec: F4 — carried paths from `--porcelain=v1 -z --untracked-files=all`, both rename sides (A9).
- Fable, spec: F7 — after `pr` or `keep`, the final message names the checkout's branch.
- Fable, spec: F9/F10 — `next-step`, `auto-run.md` and `executing-plans` wording becomes "workspace"; the cockpit sentence stays.
- Fable, spec: F8 — A19-A21 added, A9 amended.

## Critic findings

- [Blocker] Carried changes committed or wiped by existing steps — fixed:
  carried paths are recorded at setup, a task that needs one stops the run,
  the carried check refuses such a commit at `task-complete`, `phase final`
  and `phase finish`, and recovery and QA cleanup skip them (A9-A11, A17,
  A20, A21).
- [High] The run's branch is unrecorded and any non-base branch passes —
  fixed: `branch` is recorded, the in-place guard requires it, a worktree run
  keeps the primary-checkout refusal, and Setup or resume switch back to it
  (A5-A7, A9, A19).
- [High] A run started in a linked worktree dead-ends at `phase execute` —
  fixed: Step 0 switches a base HEAD to the run's branch in any checkout
  before the linked-worktree skip, and the exit-4 remedy points at Step 0
  (A12, A13).
- [Medium] Pull and merge refusals and the suite over carried changes —
  fixed: the stop list names checkout, pull and merge; a red merged suite
  lists the carried paths (A18).
- [Medium] The primary checkout is assumed unused during the run — fixed: the
  in-place option text says to leave the checkout alone; executor-lane.md's
  "continue in the primary checkout" is limited to worktree runs.
- [Medium] Acceptance tested text, not behaviour — fixed: A5-A12 and A19-A21
  run the scripts and a scripted in-place flow.
- [Nit] Four-question limit at the spec review — fixed: the worktree question
  goes in the last call beside the approval.
- [Nit] The offer's combined form — fixed: the three-option offer is written
  out.
- [Nit] Executor fallback decidable at plan time — fixed: the auto-run
  executor offer ticks nothing under `isolation in-place`.
