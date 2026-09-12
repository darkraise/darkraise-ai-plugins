# dr-superpowers Inline Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship dr-superpowers 1.5.0: `executing-plans` becomes the mode the plan's Execution line selects, writing the same ledger as subagent mode, sending its three judgment kinds to the same ruling seat, exiting to subagent mode when a task will not converge, and ending at a whole-branch final review both modes now share.

**Architecture:** The shared `reference/final-review.md` lands first, since both execution skills point at it. Then `executing-plans` is rewritten against it. Then the three documents that route by mode (resume-execution, handoff, session-budget) are brought into agreement, then `scripts/next-step` stops failing silently and stops handing an escalated plan the wrong launch command, then the structural test that pins all of it, then README and version, then full verification.

**Tech Stack:** Markdown skills and references; Bash (Git Bash on Windows) with coreutils, GNU awk, git and jq; Node 22 for the repository validator.

**Spec:** `docs/superpowers/specs/2026-09-12-dr-superpowers-inline-mode-design.md`

**Execution:** subagent — `claude --model sonnet --effort high` — Tasks 1 and 2 score 4, so R5 inline eligibility fails; every task carries its full replacement text for literal execution.

**Program:** docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md — sub-project 5 of 5 — last

**Plan review:** 2026-09-12 — dcc-superpower-companions:judge-fable — executability 17 / coherence 18 / coverage 14 / assumptions 16 (round 3)

Execute in a worktree (using-git-worktrees) branched from `docs/dr-superpowers-fork-design`, which carries the spec and this plan.

## Global Constraints

- Never touch `plugins/darkmem-resume/` (owner's live work) or historical docs under `docs/superpowers/`. Never push. Never merge to main.
- Claude and Codex dr-superpowers manifest versions stay equal: both become `1.5.0` (Task 6). Catalogs are unchanged.
- Literal prefix rule (enforced by `scripts/validate-repository.mjs`): outside `plugins/dr-superpowers/reference/legacy-names.md`, no file under `plugins/` may contain `superpowers:` unless preceded by `dr-`, or `dcc-superpower-companions:`. Test fixtures that need an old prefix build it by string concatenation.
- Reference rule (same validator): every `dr-superpowers:<name>` under `plugins/` must name `plugins/dr-superpowers/skills/<name>/` or `plugins/dr-superpowers/agents/<name>.md`. Every relative Markdown link in a skill must resolve.
- Scripts are Bash with `#!/usr/bin/env bash`, run under Git Bash on Windows, and use only bash, coreutils, GNU awk, git and jq. New executables are added with `git add --chmod=+x`.
- Skill bodies are Markdown with YAML frontmatter carrying exactly `name:` and `description:`.
- Do not modify `reference/ladder.md`, `reference/codex-routing.json`, `reference/native-codex.md`, `criteria/`, any agent file, or any script other than `scripts/next-step`.
- Commits: `<type>(superpowers): <subject>`, the subject (the text after `): `) ≤50 chars, imperative, English. No attribution or co-author lines.
- Every test/CLI run is bounded with `timeout`; kill any process you start.
- **Before running a git-backed test suite**, in the same Bash call: `export TMPDIR="C:/Users/quang/AppData/Local/Temp"`. Claude Code sets `TMPDIR=/tmp`, and suites that export `MSYS_NO_PATHCONV=1` then create their git repositories where native `git.exe` cannot find them. Use that literal path: the worktree sandbox refuses `export TMPDIR="$(cygpath -m "$TMP")"`, and refuses `for` loops that invoke `bash`, so run one suite per Bash call.
- `P` below means `plugins/dr-superpowers`. Paths are relative to the repository root.

## Contracts

- **`P/reference/final-review.md`** (new, Task 1): the whole-branch review procedure both execution skills follow. Linked as `../../reference/final-review.md` from a skill body. Sections: `# The final whole-branch review`, `## Who runs it, and when`, `## The review`, `## Fixing what it finds`.
- **Ledger grammar, inline lines** (Tasks 1, 2, 5), written to `<workspace>/progress.md`:
  - `Task <N>: implementer inline (assigned; base <sha7>)`
  - `Task <N>: fix round R/3 (X addressed, Y open — <one-liners>; commits a..b; inline | escalated inline -> subagent)`
  - `Task <N>: Ruling: (unseated) <item> — <decision> — <cost if wrong>`
  - `Task <N>: complete (commits a..b, unreviewed | K parked) — done: …; verified: <command → result>; remaining: …; discovered: …; assumptions: …`
  - The shared lines are unchanged: `minor (deferred)`, `parked`, `Task <N>: Ruling:`, `BLOCKED`, bare `Ruling:`, `Final review: clean`.
- **The escalation clause** (Tasks 1, 2, 4): the literal string `escalated inline -> subagent`, written as the last field of a task's `fix round 3/3` line. It is the only marker that a plan has left inline mode. ASCII hyphen-greater-than, not an arrow character.
- **Ruling-seat item kinds inline** (Task 2): exactly `blocked-plan`, `plan-conflict`, `final-residual`. The items file is `<workspace>/rulings-<point>-<task>.md` and the prompt is `../subagent-driven-development/references/ruling-prompt.md`, both unchanged from subagent mode.
- **`P/scripts/next-step`** (Task 4): unchanged usage, `next-step [--complete] PLAN_FILE` and `next-step --draft DRAFT_FILE --next ACTION`; unchanged exit codes 0/2/3/4. New: every non-zero exit prints `next-step: <reason>` on stdout as well as stderr, where `<reason>` carries a remedy clause when there is one to give (the missing-plan and unwritable-handoff messages do; usage and no-tasks are self-explanatory). New: when a ledger's last `escalated inline -> subagent` line is not followed by a later `implementer inline` line, `launch_cmd` is `claude --model sonnet --effort high` and the prompt gains the sentence `This plan escalated to subagent mode at Task <N>.`
- **Version string** (Task 6): `1.5.0` in `P/.claude-plugin/plugin.json` and `P/.codex-plugin/plugin.json`.

## Assumptions (evidence)

- Implementer lines use `dcc-superpower-companions:` names because dr-superpowers is not enabled on this machine; dr-superpowers' subagent-driven-development translates them through `reference/legacy-names.md`. Same choice as sub-project 4's plan.
- No `**Executor:**` lines: the Codex executor lane fails on this Windows box (`jq: Argument list too long`, parked since sub-project 2) and the Codex quota is exhausted until 2026-09-16.
- `scripts/next-step --complete` works from the repository root: run against `docs/superpowers/plans/2026-09-12-dr-superpowers-small-model-planning.md` on 2026-09-12 it printed the sub-project 5 block and exited 0. The reported "returned nothing" is the silent exit-2 path, not a logic error — `[ -f "$plan" ]` fails to stderr only (`scripts/next-step:37`). Task 4 fixes the silence, not the logic.
- `$skill` in `scripts/next-step` reaches the prompt only when there is no ledger (`scripts/next-step:136-140`); with a ledger the prompt names resume-execution. That is why Task 4 changes `launch_cmd` and the prompt sentence rather than the skill name — spec §8 records the same finding.
- `scripts/next-step` runs under `set -euo pipefail` (line 20), so any `grep` that may find nothing kills the script unless its pipeline ends `|| true`. The script's own `launch_cmd` line (`scripts/next-step:64`) is the pattern Task 4 follows.
- `tests/next-step.test.sh` invokes the script only through its `run <dir> <args...>` helper (lines 60-63), which runs `cd "$1" && bash "$SCRIPT" ...` in a subshell and sets `out` and `status`. Calling `"$SCRIPT"` directly would resolve the real checkout through `git rev-parse --show-toplevel` and overwrite the developer's own `.superpowers/handoff/latest.md`.
- No test asserts that `next-step` prints nothing on stdout when it fails: `tests/next-step.test.sh` checks only `no tasks: exits 3` (line 212) among the error paths, 2026-09-12.
- `ledger_done` matches only `^Task ([0-9]+): complete` (`P/scripts/lib/plan.sh:52`), and `snapshot.sh` greps only for `Ruling:` (`P/scripts/lib/snapshot.sh:31`), so inline's new line kinds need no parser change.
- `plan-lint` enforces R5 at plan time (`P/scripts/plan-lint:219-224`), which is why the rewritten skill never re-scores tasks.
- `tests/criteria.test.sh` is the house pattern for structural assertions about documents: a `check <name> <got> <want>` helper and `grep -c` counts. Task 5 follows it.
- Baselines for expected counts, 2026-09-12: `grep -c 'works much better with access to subagents' P/skills/executing-plans/SKILL.md` is `1` (Task 2 expects `0`); `grep -c 'review-package PLAN_FILE MERGE_BASE HEAD' P/skills/subagent-driven-development/SKILL.md` is `2`, at lines 714 (the Final Review section) and 845 (the Example Workflow fence), so Task 1 replaces both to reach `0`; `P/skills/executing-plans/SKILL.md` is 4,053 bytes.
- `scripts/test-all.mjs` has no `--list` flag; it discovers and runs every suite.
- **Measured baseline, 2026-09-12, before any task in this plan ran.** `export TMPDIR="C:/Users/quang/AppData/Local/Temp"; node scripts/test-all.mjs` fails four suites: `tests/ui-discovery.test.mjs` (`rg` not installed), `budget-line` (14 passed, 16 failed), `context-size` (0 passed, 19 failed) and `snapshot` (19 passed, 8 failed). Exporting `TMPDIR` in the calling shell does **not** rescue the three git-backed suites under the runner. Run directly under Bash with the same export they pass: `budget-line` 30/0, `snapshot` 27/0, `context-size` 18/1 (the one failure asserts a Windows-form path). Task 6 Steps 9 and 10 encode exactly these numbers, and Step 10's are the ones that decide.
- `tests/ui-discovery.test.mjs` fails with `bash: rg: command not found` and `tests/context-size.test.sh` fails 18/19 on a Windows-form path assertion. Both are environmental and pre-existing.
- `claude plugin validate` accepts both a marketplace manifest path and a plugin directory: run against `.claude-plugin/marketplace.json` and `plugins/dr-superpowers` on 2026-09-12, both printed `Validation passed` and exited 0. The `claude` CLI is on PATH on this box.
- `scripts/validate-repository.mjs` checks relative Markdown links inside `skills/` only, so the links in the new `reference/final-review.md` are covered by Task 1 Step 2's explicit `test -f` checks rather than by the validator.
- The README's `## Tests` section runs `for t in plugins/dr-superpowers/tests/*.test.sh`, so a new suite needs no edit there. Spec §2 lists that section as changed; this plan rules it needs no change, and Task 6 Step 4 records the ruling.
- Borderline plan-review scores (9-13), if any, are recorded here rather than adjudicated; the final review triages them.
- Plan review round 3 raised one Important that was a spec conflict, not a plan defect: spec §8 said `next-step`'s stderr text would not change, while Task 4 prefixes both streams. The spec was corrected to describe the prefixed form on both streams; no plan step changed.

## Task index

1. The shared final review reference
2. executing-plans rewritten for inline mode
3. Routing by mode in resume-execution, handoff and session-budget
4. next-step — visible failures and escalated launch commands
5. The inline-mode structural test
6. README, version 1.5.0, full verification

---

### Task 1: The shared final review reference

**Files:**
- Create: `plugins/dr-superpowers/reference/final-review.md`
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` (the `## Final Review` section; the `**vs. Executing Plans**` mode paragraph; the Recovery table)

**Interfaces:**
- Produces: `P/reference/final-review.md` and the escalation clause's consumer in subagent mode — both cited in Contracts.
- Consumes: nothing.

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Create the shared reference**

Create `plugins/dr-superpowers/reference/final-review.md` with exactly this content:

````markdown
# The final whole-branch review

Both execution skills end here. It is the broad review the per-task loop cannot
be: one reading of the whole branch against the spec, by reviewers that saw none
of the work being done.

## Who runs it, and when

- **Subagent mode** (dr-superpowers:subagent-driven-development): a fresh
  session. The last task's complete line is a hard stop, so that session handed
  off and dr-superpowers:resume-execution brought this one here.
- **Inline mode** (dr-superpowers:executing-plans): this session, unless the last
  budget line said `handoff`.
- **Either mode:** point the reviewer at the ledger's deferred-minor and parked
  lines, the complete lines' `discovered:` fields, every borderline (9-13) score,
  and every `(unseated)` ruling, so it can triage what must be fixed before
  merge.

## The review

Run `scripts/review-package PLAN_FILE MERGE_BASE HEAD` (MERGE_BASE is the commit
the branch started from, for example `git merge-base main HEAD`) and include the
printed path in each dispatch, so a reviewer reads one file instead of
re-deriving the branch diff with git commands.

1. **Claude review.** Dispatch a general-purpose agent on the most capable
   available model, using dr-superpowers:requesting-code-review's
   [code-reviewer.md](../skills/requesting-code-review/references/code-reviewer.md).
2. **Codex round.** When Codex is usable, run the round in
   [external-executor.md](external-executor.md) §Final-review Codex round. If it
   is not usable, or it times out, skip it and say so.
3. **Dedupe and verify** in one dispatch of `dr-superpowers:judge-fable`
   (`dr-superpowers:judge-opus` when Fable is unavailable or your human partner
   declined it — say the substitution aloud) given both reviewers' lists. It
   merges findings that name the same defect in the same place (not merely the
   same file), tags each `claude`, `codex`, or `both`, and returns `CONFIRMED` or
   `REJECTED` with evidence for each. The verifier is a third seat, so neither
   reviewer grades its own work.
4. **Report** confirmed findings ranked most severe first, then the rejected ones
   with the reason each was rejected. A finding both reviewers raised and the
   judge confirmed is the strongest signal available in this loop; say so.

## Fixing what it finds

A confirmed finding gates the handoff whichever reviewer raised it; a rejected
one never does.

If confirmed findings remain, fix them in ONE wave with the complete list — in
subagent mode one fix subagent, in inline mode one pass of your own. Never one
fixer per finding: per-finding fixers each rebuild context and re-run suites, and
a real session's final-review fix wave cost more than all its tasks combined.

Then run exactly one scoped re-review of the fix wave
(`scripts/review-package PLAN_FILE FIX_BASE HEAD` over the fix range, with
[re-review-prompt.md](../skills/subagent-driven-development/references/re-review-prompt.md)).
Send any residual findings to the ruling seat as `final-residual` items and carry
out its verdicts.

There is no second fix wave. Residual load-bearing findings surface to your human
partner when dr-superpowers:finishing-a-development-branch presents the options.
Only the four stop classes stop you here.
````

- [ ] **Step 2: Verify the links resolve**

Run:

```bash
cd plugins/dr-superpowers && for l in skills/requesting-code-review/references/code-reviewer.md reference/external-executor.md skills/subagent-driven-development/references/re-review-prompt.md; do test -f "$l" && echo "ok $l" || echo "MISSING $l"; done
```

Expected: three `ok` lines, no `MISSING`.

- [ ] **Step 3: Replace subagent-driven-development's Final Review section**

In `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, replace the whole `## Final Review` section — from the line `## Final Review` through the line before `## Finish` — with exactly:

````markdown
## Final Review

This runs in a fresh session: after the last task's complete line you handed
off, and dr-superpowers:resume-execution brought the next session here.

Follow [final-review.md](../../reference/final-review.md), the procedure both
execution skills share. Point the reviewer at the ledger's deferred-minor and
parked lines, the complete lines' `discovered:` fields, and every borderline
(9-13) score, so it can triage which findings must be fixed before merge.

````

- [ ] **Step 4: Remove the second copy of the package call**

The same string also appears in the `## Example Workflow` fence at the end of the file. Replace this line:

```
[review-package PLAN_FILE MERGE_BASE HEAD; general-purpose final reviewer on the most capable model; Codex round in the background]
```

with:

```
[final-review.md: package the branch; general-purpose final reviewer on the most capable model; Codex round in the background]
```

- [ ] **Step 5: Verify the extraction removed the duplicate procedure**

Run:

```bash
grep -c 'review-package PLAN_FILE MERGE_BASE HEAD' plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md
```

Expected: `0`. (It was `2` before this task: the Final Review section replaced in Step 3, and the Example Workflow line replaced in Step 4.)

Run:

```bash
grep -c 'final-review.md' plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md
```

Expected: `2` — Step 3's link and Step 4's Example Workflow line. The file has `0` before this task.

- [ ] **Step 6: Add the inline-return direction to the mode paragraph**

In the same file, in the `**vs. Executing Plans (parallel session):**` block, replace the paragraph that currently reads:

```markdown
The plan's `**Execution:**` line decides the mode. Only your human partner's
explicit instruction switches it, and only at a task boundary where every
earlier task is complete, recorded as a `Ruling:` line.
```

with:

```markdown
The plan's `**Execution:**` line decides the mode. Your human partner's explicit
instruction switches it in either direction, and only at a task boundary where
every earlier task is complete, recorded as a `Ruling:` line. Inline mode also
escalates here on its own when a task will not converge; it arrives with an
`escalated inline -> subagent` clause on that task's fix-round line, and the
Recovery table below says what to do with it.
```

- [ ] **Step 7: Add the escalation row to the Recovery table**

In the same file's `## The Ledger` section, in the Recovery table, insert this row immediately after the `| `fix round 5/5` or `review round 5/5` | Go to the breaker |` row:

```markdown
| a fix-round line ending `escalated inline -> subagent` | Inline mode escalated this task here. Dispatch the task's `**Implementer:**` agent fresh at round 1 of 5, with the brief, the open findings that line names, and the commits it names |
```

- [ ] **Step 8: Verify the whole file still parses as a skill**

Run:

```bash
head -4 plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md && grep -c '^## ' plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md
```

Expected: frontmatter with `name: subagent-driven-development` and `description:`, then a count of `15`.

- [ ] **Step 9: Run the repository validator**

Run:

```bash
timeout 120 node scripts/validate-repository.mjs
```

Expected: exit 0, no errors reported.

- [ ] **Step 10: Commit**

```bash
git add plugins/dr-superpowers/reference/final-review.md plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md
git commit -m "refactor(superpowers): share the final review reference"
```

---

### Task 2: executing-plans rewritten for inline mode

**Files:**
- Modify: `plugins/dr-superpowers/skills/executing-plans/SKILL.md` (replaced end to end)

**Interfaces:**
- Consumes: `P/reference/final-review.md` (Task 1), the ledger grammar and the escalation clause from Contracts, and the existing `../subagent-driven-development/references/ruling-prompt.md`.
- Produces: the inline ledger lines and the three seat kinds that Tasks 4 and 5 assert on, both cited in Contracts.

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 0 - spec 0 - coupling 2 - risk 2 = 4

- [ ] **Step 1: Replace the skill file end to end**

Replace the entire contents of `plugins/dr-superpowers/skills/executing-plans/SKILL.md` with exactly this:

````markdown
---
name: executing-plans
description: Use when a plan's Execution line names inline mode - the session implements every task itself, with the whole-branch final review as its gate
---

# Executing Plans

## After compaction

If this session was compacted - a compaction snapshot or summary sits above -
your memory of the run is gone, and only the start of this file may have come
back. Before anything else:

1. Run `scripts/sdd-workspace PLAN_FILE`, from the plugin root (two levels
   above this skill's directory), and read `progress.md` and `handoff.md` in
   the directory it prints.
2. Trust the ledger and `git log` over the summary. For each task the last
   ledger line decides; see the Recovery table under The Ledger.
3. Run `scripts/context-size`. On exit 5, invoke dr-superpowers:handoff.
4. Re-read this skill in full before the next task.

## Select the host first

On Codex, the ruling seat is a native judge at Astra high or above
([native-codex.md](../../reference/native-codex.md)), and there is no budget
line: hand off after every 3 completed tasks, or after any task that needed 3
or more fix rounds. Everything else here is host-neutral - inline mode
dispatches nothing but the ruling seat and the final review.

## Overview

Execute a plan yourself, task by task, with the whole-branch final review as
the gate.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Why this mode.** The plan's `**Execution:**` line chose it because every task
scores 3 or less with none at risk 3: each is a small change whose text carries
the code, and a subagent per task would cost more in context rebuild than the
task itself. Subagent availability has nothing to do with it - the line
decides, and only your human partner overrides it.

**Why no per-task review.** The eligibility bar is the gate, applied before
execution starts. A task too large, too vague or too risky for this mode never
reaches it: the plan would have said `subagent`. What catches the rest is the
plan's own verification steps, your self-review of each diff, and one broad
review of the whole branch at the end.

**Continuous execution.** Do not pause between tasks to check in. "Should I
continue?" prompts and progress summaries waste your human partner's time -
they asked you to execute the plan, so execute it.

**Rulings, not stalls.** Decide the mechanical problems yourself - a legacy
name, a missing directory, a tool failure, a plan that is silent where you need
an answer - and record each in the ledger as `Ruling: <what you decided> —
<why> — <what it costs if wrong>`, said aloud. Everything that needs judgment
about the plan, the spec or a finding goes to the ruling seat, which reads the
whole plan and the spec you never read. A wrong ruling costs rework your human
partner can see and undo; a session parked on a question costs their whole day
and buys nothing.

**Surgical execution.** Change only what the task names. Note adjacent problems
in the ledger as `Task <N>: minor (deferred): <one-liner>` instead of fixing
them.

Four things stop you, and only these: an irreversible or destructive operation;
a security-sensitive action; a side effect outside this worktree that norms say
you ask about first (a merge, a push to a shared branch, a publish); and a
ruling-seat `BLOCKED` verdict. For those, stop and ask.

**Every session ends with the next step.** Whenever this session ends before
the plan is finished - one of those four stops, a context-budget handoff, a
switch to subagent mode, or your human partner asking you to stop - run
`scripts/next-step PLAN_FILE`, from the plugin root, as your last action. The
last thing in your final message is the block it prints, verbatim. It also
rewrites the `## Next session` section of the primary checkout's
`.superpowers/handoff/latest.md`; if it exits 4, say the handoff file could not
be written. When the plan finishes,
dr-superpowers:finishing-a-development-branch runs it instead.

## Setup

Ensure the work happens in an isolated workspace: use
dr-superpowers:using-git-worktrees to create one or verify the existing one.
Never start implementation on a main/master branch without your human partner's
explicit consent.

Conversation memory does not survive compaction. Track progress in a ledger
file, not only in todos.

- Each plan owns a workspace: run `scripts/sdd-workspace PLAN_FILE`, from the
  plugin root, and it prints the plan's git-ignored directory
  (`<repo-root>/.superpowers/sdd/<plan-basename>/`), home to every artifact for
  THIS plan. Another plan's directory is never yours to read or write.
- This plan's ledger is `<workspace>/progress.md`. If its first line names your
  plan file, recover each task's state with the Recovery table under The
  Ledger. A ledger whose first line names a different plan - or a stray ledger
  at the old flat path `.superpowers/sdd/progress.md` - is another plan's
  progress: leave it in place and start your own, fresh.
- Create the ledger with its identity as the first line:
  `# SDD ledger — plan: <plan file path>`.
- Create `<workspace>/handoff.md` from the template in dr-superpowers:handoff
  if it does not exist. Update it in the same message as a ledger write
  whenever an owner constraint, gotcha, prohibition or open question changes.
- `git clean -fdx` will destroy the workspace (it is git-ignored scratch); if
  that happens, recover from `git log`.

Read the plan's header, never the whole plan: run
`scripts/task-brief --header PLAN_FILE`, from the plugin root, and read the
file it prints (`<workspace>/plan-header.md`). Note the Execution line, the
Global Constraints and the Contracts, and create a todo per Task index entry. A
plan written before 1.4.0 may have no Task index: then run
`scripts/task-brief PLAN_FILE N` for N = 1, 2, … until it exits 3, and take
each task's title from its brief's first line. You never read the spec: the
ruling seat and the final review do. If the plan's `**Spec:**` path is
unreachable, note it in the ledger and say so in every ruling-seat dispatch;
the seat marks its rulings provisional.

**Check the Execution line.** It must name `inline`.

- It names `subagent`: log `Ruling: routed to subagent mode — the plan's
  Execution line names it — none` and use
  dr-superpowers:subagent-driven-development instead.
- The plan has no Execution line, because it was written before 1.4.0: log
  `Ruling: inline by invocation — plan predates the Execution line — if wrong,
  the run escalates at the first task that will not converge` and continue.

Never re-score the tasks. `scripts/plan-lint` enforced the eligibility rule
when the plan was saved, and a plan whose Execution line says `inline` has
passed it.

**Resolve legacy names.** Plans written before this plugin's 1.2.0 may name
skills and agents under older plugin prefixes. Translate each with
[legacy-names.md](../../reference/legacy-names.md) at read time, never edit the
plan, and log one `Ruling: translated <old> -> <new> — legacy plugin name —
none` per distinct name. `**Implementer:**` and `**Executor:**` lines are inert
in this mode: no task is dispatched, so their names need no translation.

There is no pre-flight scan. It is one whole-plan judge dispatch, and a plan
eligible for this mode is low-coupling by construction. A plan defect that
surfaces while you work goes to the seat as a `blocked-plan` item.

## The Ledger

This skill and dr-superpowers:subagent-driven-development share one grammar, so
a plan that changes mode mid-run leaves one readable record. The lines this
mode writes:

```
# SDD ledger — plan: <path>
Task <N>: implementer inline (assigned; base <sha7>)
Task <N>: fix round R/3 (X addressed, Y open — <one-liners>; commits a..b; inline | escalated inline -> subagent)
Task <N>: minor (deferred): <one-liner>
Task <N>: parked — <finding> — Ruling: <why the code stands>
Task <N>: Ruling: <finding> — <what was decided and why>
Task <N>: Ruling: (unseated) <item> — <decision> — <cost if wrong>
Task <N>: Ruling: amendment A<k> — <reason> — <cost if wrong>
Task <N>: BLOCKED — ruling seat — <what a human must decide>
Task <N>: complete (commits a..b, unreviewed | K parked) — done: …; verified: <command → result>; remaining: none | <parked>; discovered: none | …; assumptions: none | …
Ruling: <what> — <why> — <cost if wrong>
Final review: clean (commits <merge-base7>..<head7>[, K parked])
```

- `implementer inline` is this mode's assigned line. You are the implementer,
  so the agent slot says so, and `base` is `git rev-parse --short HEAD` taken
  before you change anything.
- `unreviewed` is where subagent mode writes `review clean`. No judge scored
  this task, and saying so is what keeps the two modes' complete lines honest.
  The branch's review is the `Final review:` line.
- There is no scores clause. A scores clause appears only when a judge scored
  the task.
- The fix cap is 3, not subagent mode's 5. You are fixing your own work, so a
  fourth round is not a better round - it is the trigger in Switching to
  subagent mode.
- The checkpoint after the `—` is yours to write, and the final review reads it
  as a claim to check rather than a finding. `done` is a one-line summary of
  the deliverable, `verified` the covering command and its result, `remaining`
  the parked findings, `discovered` the problems you found and did not fix, and
  `assumptions` what you assumed where the plan was silent.
- Write each line in the same message as your other bookkeeping, never later.

**Recovery.** For task N, take the last line in file order among its
`Task <N>:` lines, stepping over `minor (deferred)`, `parked`,
`Task <N>: Ruling:` and bare `Ruling:` lines. Then:

| Last line | Action |
|---|---|
| `complete` | Done; never redo |
| `BLOCKED` | Terminal. It is a stop of the fourth class for any task that depends on it; name it in your final message |
| `fix round R/3`, R < 3 | Resume the loop at round R+1 |
| a fix-round line ending `escalated inline -> subagent` | This plan has left inline mode: use dr-superpowers:subagent-driven-development |
| `fix round 3/3` | Go to Switching to subagent mode |
| `implementer inline (assigned; base <sha7>)` | If `git log <base>..HEAD` is non-empty, re-run the task's verifications and finish it from where those commits leave it; otherwise start the task |
| none | Not started |

**Plan state.** Every task complete and no `Final review:` line: go to Final
Review. A `Final review: clean` line: go to
dr-superpowers:finishing-a-development-branch.

## Session Budget

`scripts/task-brief` ends its output with the budget line
([session-budget.md](../../reference/session-budget.md)), so you check the
budget before every task at no extra request:

    budget: 312k of 475k (65%) — ok — source: record

- `ok` or `unknown`: carry on.
- `handoff`: finish the task in flight, write its ledger line, then invoke
  dr-superpowers:handoff. Never hand off mid-task.

Run `scripts/context-size` after each `Task <N>: complete` line and act on its
exit 5 the same way.

The last task completing is a soft stop: the final review runs in this session
unless the budget line says `handoff`. A switch to subagent mode is always a
handoff.

## The Task Loop

For each task, in order:

1. **Read the brief.** Run `scripts/task-brief PLAN_FILE N`, from the plugin
   root, and read the file it prints. It carries the task text with every
   amendment applied, the header's Global Constraints and Contracts, and the
   budget line. You never read task text any other way: reading the plan file
   directly skips the amendments.
2. **Open the task.** Take the base commit (`git rev-parse --short HEAD`) and
   append `Task <N>: implementer inline (assigned; base <sha7>)`.
3. **Implement exactly what the task names.** Follow its steps in order. Where
   the task says to write a test first, use
   dr-superpowers:test-driven-development. Touch only the files and lines the
   task names; a change the task did not ask for is a deferred minor, not a
   bonus.
4. **Run the verifications as written.** A step that says `Expected: PASS` is
   not done until you have seen it pass. Run the focused test while you work
   and the full suite once before committing.
5. **Self-review your own diff** against the brief before you commit. This is
   the only per-task gate this mode has, so it is not a formality: read
   `git diff`, and check that every step is done, that nothing outside the
   named files changed, and that no test you wrote would pass against an
   unimplemented function. A test that passes with `return <constant>` is not
   a test.
6. **Commit** as the task's commit step specifies.
7. **Close the task.** Append the complete line with its checkpoint, in the
   same message as your other bookkeeping, and mark the todo complete.
8. **Check the budget.** Run `scripts/context-size`.

**When a verification will not pass.** Append `Task <N>: fix round R/3 (…)`,
fix, and re-run. Rounds 1 through 3 are yours. A task still failing after `3/3`
goes to Switching to subagent mode - not to a fourth round, and not to a
complete line.

**When the plan is silent** - it does not say which of two reasonable things to
do - rule, log it, and carry on.

**When the plan is wrong** - its steps contradict each other, the output it
expects cannot be produced, a name it mandates does not exist - send a
`blocked-plan` item to the ruling seat. Improvising here is the one failure
this mode cannot review its way out of, because the final review reads the
branch against the spec, not against what you meant.

## The Ruling Seat

Judgment about the plan, the spec or a finding belongs to the ruling seat, not
to you, whatever model you run on. It reads the whole plan, the spec,
`amendments.md` and the ledger; you read the header and one brief at a time. It
is the only thing this mode dispatches before the final review.

**When.** Three points arise in this mode:

| Kind | Decision point |
|---|---|
| `blocked-plan` | The plan is wrong and no path forward is a mechanical choice |
| `plan-conflict` | A final-review finding that conflicts with what the plan's text requires, or is labelled plan-mandated |
| `final-residual` | Findings still open after the final review's one fix wave |

The other five kinds belong to seats this mode does not run: `preflight` (there
is no pre-flight scan), `cannot-verify` and `risk3-spread` (no task reviewer),
`breaker` (no five-round review loop), and `codex-empty-diff` (no external
executor).

**How.** Write `<workspace>/rulings-<point>-<task>.md` - `<task>` is the task
number the items concern, or `plan` for a plan-level point, so a recurring
point never overwrites an earlier file - listing each item: an id, its kind,
its task, and the paths it needs, with the findings copied verbatim. Dispatch
`dr-superpowers:judge-fable` (`dr-superpowers:judge-opus` when Fable is
unavailable or your human partner declined it - say the substitution aloud)
with
[ruling-prompt.md](../subagent-driven-development/references/ruling-prompt.md),
expanding its placeholders.

**Carry out each verdict**, and copy its `Ruling:` line into the ledger
verbatim:

- **CONFIRMED-GAP** - the finding is real. Make the smallest fix the ruling
  names. A CONFIRMED-GAP whose fix you attempt and fail is a trigger in
  Switching to subagent mode.
- **PARK** - log `Task <N>: parked — <finding> — Ruling: <why>`; the code
  stands.
- **AMEND** - copy the entry, from its `## A?` line through the New fence's
  closing line, to `<workspace>/amend-<id>.md` and run
  `scripts/plan-amend PLAN_FILE <workspace>/amend-<id>.md`, from the plugin
  root. On `amended: A<k> …`, write the amendment ledger line; your next
  `task-brief` carries the amendment. On `rejected: …`, make one fresh seat
  dispatch carrying the entry and the rejection output; a second rejection is
  BLOCKED.
- **BLOCKED** - log `Task <N>: BLOCKED — ruling seat — <decision>`, name it in
  your final message, and stop.

Never soften, merge or second-guess a verdict. If you think the seat is wrong,
carry the verdict out anyway: the ledger line is where your human partner sees
it.

**When no subagent facility exists at all**, the seat is unreachable. Rule
yourself, write `Task <N>: Ruling: (unseated) <item> — <decision> — <cost if
wrong>`, and say it aloud; list every unseated ruling for the final reviewer. A
visible ruling your human partner can rework beats a session parked on a
question. On Claude Code and on Codex this never fires - if it does, check
whether you are in the mode and on the host you think you are.

## Switching to subagent mode

Inline mode has one exit, and it runs in one direction. Take it when:

- your human partner says to;
- a task is still failing its own verifications after `fix round 3/3`;
- a ruling-seat CONFIRMED-GAP names a fix you have attempted and failed.

The trigger is mechanical, so the switch is your ruling, not a seat verdict:
the seat's four verdicts say nothing about execution mode. It happens only at a
task boundary where every earlier task is complete.

1. Append the escalation clause to the task's fix-round line:
   `Task <N>: fix round 3/3 (…; commits a..b; escalated inline -> subagent)`.
2. Log, and say aloud, `Ruling: switch to subagent mode at Task <N> —
   <trigger> — if wrong, the remaining tasks each cost one dispatch that inline
   would not have spent`.
3. Do not edit the plan. `**Execution:**` is one of the lines
   `scripts/plan-amend` refuses to touch, and the ledger is where the switch is
   recorded.
4. Invoke dr-superpowers:handoff. The switch is always a handoff: subagent
   mode's value is a fresh controller that reads the header and one brief at a
   time, and this session's context is full of implementation detail it does
   not need.

Your human partner may also move a plan the other way, from subagent mode to
this one. Only their explicit instruction does that, and only at the same kind
of boundary.

## Final Review

Every task is complete, so the branch gets one broad review: follow
[final-review.md](../../reference/final-review.md), the procedure both
execution skills share. In this mode it runs in this session, unless the last
budget line said `handoff` - then invoke dr-superpowers:handoff, and
dr-superpowers:resume-execution brings the next session here. List any
`(unseated)` rulings for the reviewer alongside the ledger's parked and
deferred-minor lines.

## Finish

Before you leave this skill, collect every ledger line containing `Ruling:` -
translations, parked findings, unseated rulings, ruling-seat verdicts, the
mode-switch ruling if you made one - into your final message under "Rulings I
made", in the order you made them, each with what it costs if wrong. The list
is exhaustive: if the ledger holds a ruling, the list holds it. That list is
the only place the decisions you took on your human partner's behalf reach
them - they read it and rework whatever you got wrong. Name every `BLOCKED`
task there too.

Then, under "Amendments made", print every entry of `<workspace>/amendments.md`
in full, if the file exists. The workspace is deleted after a merge, so this
printed list is the only lasting record of how the plan changed during
execution.

When the final review is clean and its fixes are committed, append
`Final review: clean (commits <merge-base7>..<head7>[, K parked])` to the
ledger in the same message as printing the rulings. Do not delete the
workspace: dr-superpowers:finishing-a-development-branch removes it with the
worktree once the work is merged or discarded, and until then it is what a
later session resumes from.

Use dr-superpowers:finishing-a-development-branch.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Subagents are available, so I should switch to the other skill" | The Execution line chose this mode, not the absence of subagents. Only your human partner overrides it. |
| "I'll read the whole plan, it's faster than one brief at a time" | The plan on disk has no amendments applied. `task-brief` is how corrections reach you. |
| "This task is harder than it scored - I'll just take more rounds" | Three rounds, then the switch. A fourth round on your own work is what not converging looks like. |
| "The plan is wrong here, I'll fix it as I go" | You read one brief; the seat reads the plan and the spec. Send a blocked-plan item. |
| "No reviewer is watching, so the self-review is optional" | It is the only per-task gate this mode has. Skipping it makes the final review the first time anyone reads the diff. |
| "I'll mention the ruling in my final message instead of the ledger" | Your message dies with the session; the ledger survives compaction. |
| "I'll batch the commits at the end" | The ledger names commit ranges per task. A task without its own commits cannot be recovered or reviewed. |
| "The adjacent bug is a two-line fix" | It is a deferred minor. The final review triages it with the rest. |
| "I should check in before the next task" | Continuous execution. The stops are the four; "are you still happy?" is not one. |
| "Nothing dispatches here, so there is no ledger to keep" | The ledger is what survives compaction, in this mode exactly as in the other. |
````

- [ ] **Step 2: Verify the deleted upstream note is gone**

Run:

```bash
grep -c 'works much better with access to subagents' plugins/dr-superpowers/skills/executing-plans/SKILL.md
```

Expected: `0`. (It was `1` before this task.)

- [ ] **Step 3: Verify the scripts and references the skill must name**

Run:

```bash
cd plugins/dr-superpowers/skills/executing-plans && for s in 'task-brief --header' 'task-brief PLAN_FILE N' sdd-workspace context-size next-step plan-amend; do printf '%s: %s\n' "$s" "$(grep -c -- "$s" SKILL.md)"; done
```

Expected: every count is 1 or more.

- [ ] **Step 4: Verify both relative links resolve**

Run:

```bash
cd plugins/dr-superpowers/skills/executing-plans && test -f ../../reference/final-review.md && test -f ../subagent-driven-development/references/ruling-prompt.md && echo both-resolve
```

Expected: `both-resolve`.

- [ ] **Step 5: Run the repository validator**

Run:

```bash
timeout 120 node scripts/validate-repository.mjs
```

Expected: exit 0, no errors reported. This checks the literal-prefix rule and that every `dr-superpowers:<name>` in the new text resolves.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/skills/executing-plans/SKILL.md
git commit -m "feat(superpowers): rewrite executing-plans as inline mode"
```

---

### Task 3: Routing by mode in resume-execution, handoff and session-budget

**Files:**
- Modify: `plugins/dr-superpowers/skills/resume-execution/SKILL.md:45-47` (step 5's final-review branch)
- Modify: `plugins/dr-superpowers/skills/handoff/SKILL.md` (the `description:` frontmatter line; the hard-stop bullet at lines 22-24)
- Modify: `plugins/dr-superpowers/reference/session-budget.md` (`## Checkpoints` and `## Stops`)

**Interfaces:**
- Consumes: the mode rule and the soft/hard stop distinction from Task 2's skill body.
- Produces: nothing other tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Route resume-execution's final-review branch by mode**

In `plugins/dr-superpowers/skills/resume-execution/SKILL.md`, in step 5, replace this bullet:

```markdown
   - Run the final whole-branch review: invoke
     dr-superpowers:subagent-driven-development; with every task complete it
     goes straight to its Final Review section.
```

with:

```markdown
   - Run the final whole-branch review: invoke the skill the plan's
     `**Execution:**` line names, as the previous bullet does. With every task
     complete, each goes straight to its Final Review section, and both follow
     the same [final-review.md](../../reference/final-review.md).
```

- [ ] **Step 2: Verify the link resolves from that skill**

Run:

```bash
cd plugins/dr-superpowers/skills/resume-execution && test -f ../../reference/final-review.md && echo resolves
```

Expected: `resolves`.

- [ ] **Step 3: Give handoff the inline stop rules**

In `plugins/dr-superpowers/skills/handoff/SKILL.md`, in the `## When` list, replace this bullet:

```markdown
- A hard stop: the plan is saved, or every plan task is complete under
  subagent-driven-development (the final whole-branch review runs in a fresh
  session).
```

with:

```markdown
- A hard stop: the plan is saved; every plan task is complete under
  dr-superpowers:subagent-driven-development (the final whole-branch review
  runs in a fresh session); or a plan has just switched from inline to subagent
  mode. Under dr-superpowers:executing-plans the last task is a soft stop
  instead: the final review runs in the same session unless the budget line
  says `handoff`.
```

- [ ] **Step 4: Update the checkpoints table in session-budget.md**

In `plugins/dr-superpowers/reference/session-budget.md`, under `## Checkpoints`, replace this bullet:

```markdown
- **executing-plans:** `context-size` after each `Task N: complete` line.
```

with:

```markdown
- **executing-plans:** the budget line on every `task-brief`, and
  `context-size` after each `Task N: complete` line.
```

- [ ] **Step 5: Update the stops list in session-budget.md**

In the same file, under `## Stops`, replace this bullet:

```markdown
- **Hard:** the plan is saved; every plan task is complete under
  subagent-driven-development (the final review runs in a fresh session).
  writing-plans runs dr-superpowers:handoff once the plan is reviewed.
```

with:

```markdown
- **Hard:** the plan is saved; every plan task is complete under
  subagent-driven-development (the final review runs in a fresh session); a
  plan switches from inline to subagent mode. writing-plans runs
  dr-superpowers:handoff once the plan is reviewed.
```

- [ ] **Step 6: Update the handoff skill's description**

The `description:` in that file's frontmatter is what the router matches on, and it still names only subagent mode's hard stop. Replace:

```yaml
description: Use when a budget line says handoff, at a hard phase stop (plan saved, every plan task complete under subagent-driven-development), after 3 Codex tasks or a task that needed 3+ fix rounds, or when your human partner steps away or asks to stop - ends the session with durable handoff files and a resume guide
```

with:

```yaml
description: Use when a budget line says handoff, at a hard phase stop (plan saved, every plan task complete under subagent-driven-development, or a switch from inline to subagent mode), after 3 Codex tasks or a task that needed 3+ fix rounds, or when your human partner steps away or asks to stop - ends the session with durable handoff files and a resume guide
```

- [ ] **Step 7: Verify the three documents agree on the soft stop**

Run:

```bash
cd plugins/dr-superpowers && grep -c 'soft stop' skills/executing-plans/SKILL.md skills/handoff/SKILL.md && grep -c 'inline to subagent' skills/handoff/SKILL.md reference/session-budget.md
```

Expected: each of the four counts is 1 or more.

- [ ] **Step 8: Run the repository validator**

Run:

```bash
timeout 120 node scripts/validate-repository.mjs
```

Expected: exit 0, no errors reported.

- [ ] **Step 9: Commit**

```bash
git add plugins/dr-superpowers/skills/resume-execution/SKILL.md plugins/dr-superpowers/skills/handoff/SKILL.md plugins/dr-superpowers/reference/session-budget.md
git commit -m "docs(superpowers): route stops and review by mode"
```

---

### Task 4: next-step — visible failures and escalated launch commands

**Files:**
- Modify: `plugins/dr-superpowers/scripts/next-step`
- Test: `plugins/dr-superpowers/tests/next-step.test.sh`

**Interfaces:**
- Consumes: the escalation clause `escalated inline -> subagent` and the assigned line `implementer inline`, both from Contracts.
- Produces: nothing other tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests for visible failures**

Append to `plugins/dr-superpowers/tests/next-step.test.sh`, immediately before its final summary block (the lines that print the pass/fail totals):

```bash
# --- failures are visible on stdout ---
# Every non-zero exit prints on stdout too: a session that surfaces only stdout
# would otherwise see nothing at all from the script whose job is saying what
# happens next. Always go through run(): it cds into the fixture repo, so the
# script cannot resolve the real checkout and overwrite its handoff file.
run "$REPO" docs/plans/no-such-plan.md
check "missing plan: exits 2" "$status" "2"
has "missing plan: says so on stdout" "$out" "next-step: no such file"

printf '# Empty plan\n\n**Goal:** nothing\n' > "$REPO/docs/plans/2026-01-01-empty.md"
run "$REPO" docs/plans/2026-01-01-empty.md
check "no tasks: exits 3 (stdout form)" "$status" "3"
has "no tasks: says so on stdout" "$out" "next-step: no tasks in"

run "$REPO"
check "no arguments: exits 2" "$status" "2"
has "no arguments: prints usage on stdout" "$out" "next-step: usage:"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
export TMPDIR="C:/Users/quang/AppData/Local/Temp"; timeout 180 bash plugins/dr-superpowers/tests/next-step.test.sh 2>&1 | tail -20
```

Expected: FAIL lines for the three `says so on stdout` / `prints usage on stdout` checks; the `exits 2` and `exits 3` checks pass.

- [ ] **Step 3: Make every failure print on stdout**

In `plugins/dr-superpowers/scripts/next-step`, immediately after the `set -euo pipefail` line, insert:

```bash
# Failures print on stdout as well as stderr. A session that surfaces only
# stdout would otherwise get an empty result from the one script whose whole
# job is saying what happens next.
fail() { # fail EXIT MESSAGE
  printf 'next-step: %s\n' "$2"
  printf 'next-step: %s\n' "$2" >&2
  exit "$1"
}
```

Then replace the `usage()` definition:

```bash
usage() { echo "usage: next-step [--complete] PLAN_FILE | next-step --draft DRAFT_FILE --next ACTION" >&2; exit 2; }
```

with:

```bash
usage() { fail 2 "usage: next-step [--complete] PLAN_FILE | next-step --draft DRAFT_FILE --next ACTION"; }
```

`usage()` already sits above the `. "$(cd ...)/lib/plan.sh"` line, so inserting `fail` directly after `set -euo pipefail` puts both definitions ahead of every call site. Nothing else moves.

- [ ] **Step 4: Convert the two remaining failure paths**

In the same file, replace:

```bash
[ -f "$plan" ] || { echo "no such file: $plan" >&2; exit 2; }
```

with:

```bash
[ -f "$plan" ] || fail 2 "no such file: $plan — run it from the repository root, or check the plan path"
```

Replace:

```bash
  [ -n "$tasks" ] || { echo "no tasks in ${plan} (no heading matching 'Task N')" >&2; exit 3; }
```

with:

```bash
  [ -n "$tasks" ] || fail 3 "no tasks in ${plan} (no heading matching 'Task N')"
```

Replace the final block:

```bash
if ! write_handoff 2>/dev/null; then
  rm -f "$handoff.tmp" 2>/dev/null || true
  echo "next-step: could not write $handoff — copy the block above into it by hand" >&2
  exit 4
fi
```

with:

```bash
if ! write_handoff 2>/dev/null; then
  rm -f "$handoff.tmp" 2>/dev/null || true
  fail 4 "could not write $handoff — copy the block above into it by hand"
fi
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:

```bash
export TMPDIR="C:/Users/quang/AppData/Local/Temp"; timeout 180 bash plugins/dr-superpowers/tests/next-step.test.sh 2>&1 | tail -8
```

Expected: `0 failed`.

- [ ] **Step 6: Cover the exit-4 path in the existing handoff test**

The spec requires an unwritable `latest.md` to print on stdout too, and the suite's existing block checks only stderr. In the same file, in the `# --- handoff write failure still prints the block ---` block, immediately after this line:

```bash
has "unwritable handoff: says so on stderr" "$(cat "$TMP/stderr")" "could not write"
```

add:

```bash
has "unwritable handoff: says so on stdout" "$out" "next-step: could not write"
```

Re-run the suite with the command from Step 5. Expected: `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/scripts/next-step plugins/dr-superpowers/tests/next-step.test.sh
git commit -m "fix(superpowers): make next-step failures visible"
```

- [ ] **Step 8: Write the failing tests for escalated launch commands**

Append to `plugins/dr-superpowers/tests/next-step.test.sh`, again immediately before the final summary block:

```bash
# --- a plan that escalated out of inline mode ---
# The ledger, not the Execution line, says which mode a run is in after a
# switch. The launch command has to follow it, or the resumed session starts at
# inline mode's model and effort.
INL="$REPO/docs/plans/2026-01-01-inline.md"
cat > "$INL" <<'PLAN'
# Inline plan

**Goal:** demo

**Spec:** docs/spec.md

**Execution:** inline — `claude --model sonnet --effort low` — every task scores 2

## Task index

1. First
2. Second

### Task 1: First

### Task 2: Second
PLAN
INL_LEDGER="$REPO/.superpowers/sdd/2026-01-01-inline"
mkdir -p "$INL_LEDGER"
{
  echo "# SDD ledger — plan: docs/plans/2026-01-01-inline.md"
  echo "Task 1: implementer inline (assigned; base aaaaaaa)"
  echo "Task 1: complete (commits aaaaaaa..bbbbbbb, unreviewed) — done: x; verified: y → ok; remaining: none; discovered: none; assumptions: none"
  echo "Task 2: implementer inline (assigned; base bbbbbbb)"
  echo "Task 2: fix round 3/3 (0 addressed, 1 open — still red; commits bbbbbbb..ccccccc; escalated inline -> subagent)"
} > "$INL_LEDGER/progress.md"

run "$REPO" docs/plans/2026-01-01-inline.md
has "escalated: launches the subagent pair" "$out" "claude --model sonnet --effort high"
lacks "escalated: drops the inline pair" "$out" "--effort low"
has "escalated: says the plan escalated" "$out" "This plan escalated to subagent mode at Task 2."

# A later inline assignment means the plan came back; the Execution line rules
# again.
echo "Task 2: implementer inline (assigned; base ccccccc)" >> "$INL_LEDGER/progress.md"
run "$REPO" docs/plans/2026-01-01-inline.md
has "returned to inline: launches the inline pair" "$out" "claude --model sonnet --effort low"
lacks "returned to inline: drops the escalation sentence" "$out" "This plan escalated to subagent mode"
```

- [ ] **Step 9: Run the tests to verify they fail**

Run:

```bash
export TMPDIR="C:/Users/quang/AppData/Local/Temp"; timeout 180 bash plugins/dr-superpowers/tests/next-step.test.sh 2>&1 | tail -20
```

Expected: FAIL lines for `escalated: launches the subagent pair`, `escalated: drops the inline pair` and `escalated: says the plan escalated`; the two `returned to inline` checks already pass.

- [ ] **Step 10: Detect the escalation and override the launch command**

In `plugins/dr-superpowers/scripts/next-step`, find the block that ends the ledger resolution:

```bash
    if head -n 1 <<<"$ledger_text" | grep -qF "plan: $rel"; then
      has_ledger=1
      ledger_note="ledger \`$ledger_shown\`"
      done_tasks=$(ledger_done "$ledger_file")
    else
```

Immediately after the `done_tasks=$(ledger_done "$ledger_file")` line, insert:

```bash
      # A ledger outranks the Execution line on which mode the run is in: a
      # switch is recorded there and the plan is never edited. The escalation
      # holds until a later inline assignment shows the plan came back.
      esc=$(grep -n 'escalated inline -> subagent' <<<"$ledger_text" | tail -n 1 | cut -d: -f1 || true)
      if [ -n "$esc" ]; then
        back=$(grep -n 'implementer inline' <<<"$ledger_text" | tail -n 1 | cut -d: -f1 || true)
        if [ -z "$back" ] || [ "$back" -lt "$esc" ]; then
          escalated_at=$(sed -n "${esc}p" <<<"$ledger_text" | sed -E 's/^Task ([0-9]+):.*/\1/')
        fi
      fi
```

- [ ] **Step 11: Declare the variable and apply the override**

In the same file, add `escalated_at=""` to the initialisation line that currently reads:

```bash
status_line="" next_line="" prompt="" launch=1 dir="$primary" launch_cmd=""
```

so it reads:

```bash
status_line="" next_line="" prompt="" launch=1 dir="$primary" launch_cmd="" escalated_at=""
```

Then, in the `else` branch that builds the resume prompt, find:

```bash
    if [ "$has_ledger" -eq 1 ]; then
      prompt="Resume \`$rel\` with dr-superpowers:resume-execution. $next_line"
    else
```

and insert, immediately before that `if`:

```bash
    if [ -n "$escalated_at" ]; then
      launch_cmd="claude --model sonnet --effort high"
      next_line="$next_line This plan escalated to subagent mode at Task $escalated_at."
    fi
```

Spec §8 says "the prompt gains one sentence". Appending to `next_line` puts it in the block's `**Next:**` line *and* the prompt, because the prompt is built from `next_line`. That is the intended reading: a reader of the handoff block sees the escalation without having to parse the prompt. Do not split it into two strings.

- [ ] **Step 12: Run the tests to verify they pass**

Run:

```bash
export TMPDIR="C:/Users/quang/AppData/Local/Temp"; timeout 180 bash plugins/dr-superpowers/tests/next-step.test.sh 2>&1 | tail -8
```

Expected: `0 failed`.

- [ ] **Step 13: Run the two suites that share the plan library**

Run:

```bash
export TMPDIR="C:/Users/quang/AppData/Local/Temp"; timeout 180 bash plugins/dr-superpowers/tests/plan-lib.test.sh 2>&1 | tail -4
```

Expected: `0 failed`.

Run:

```bash
export TMPDIR="C:/Users/quang/AppData/Local/Temp"; timeout 180 bash plugins/dr-superpowers/tests/repo-audit.test.sh 2>&1 | tail -4
```

Expected: `0 failed`.

- [ ] **Step 14: Commit**

```bash
git add plugins/dr-superpowers/scripts/next-step plugins/dr-superpowers/tests/next-step.test.sh
git commit -m "feat(superpowers): resume an escalated plan correctly"
```

---

### Task 5: The inline-mode structural test

**Files:**
- Create: `plugins/dr-superpowers/tests/inline-mode.test.sh`

**Interfaces:**
- Consumes: the rewritten `executing-plans/SKILL.md` (Task 2), `reference/final-review.md` and the edited `subagent-driven-development/SKILL.md` (Task 1).
- Produces: nothing other tasks consume.

**Implementer:** dcc-superpower-companions:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

- [ ] **Step 1: Write the test**

Create `plugins/dr-superpowers/tests/inline-mode.test.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# Inline mode is a document, and the claims that make it work are structural:
# which scripts it calls, which references it links, which ledger lines it
# shares with subagent mode, and which ruling-seat kinds it claims. A model is
# not needed to check any of them, so they are checked here instead of in a
# review.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
INLINE="$P/skills/executing-plans/SKILL.md"
SDD="$P/skills/subagent-driven-development/SKILL.md"
FINAL="$P/reference/final-review.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

for f in "$INLINE" "$SDD" "$FINAL"; do
  check "exists: $(basename "$(dirname "$f")")/$(basename "$f")" \
    "$([ -f "$f" ] && echo yes || echo no)" "yes"
done

# The scripts inline mode must call. Reading the plan directly would skip
# amendments; skipping next-step would end a session without a next action.
for s in 'task-brief --header' 'task-brief PLAN_FILE N' 'sdd-workspace' 'context-size' 'next-step' 'plan-amend'; do
  present "calls $s" "$INLINE" "$s"
done

# The two skills a finished or interrupted run hands control to. Dropping
# either would strand a session with nowhere to go.
present "names handoff" "$INLINE" "dr-superpowers:handoff"
present "names finishing" "$INLINE" "dr-superpowers:finishing-a-development-branch"

# Only the first 5,000 tokens of a skill body come back after compaction, so
# the recovery instructions have to be at the top.
check "opens with After compaction" \
  "$(grep -m 1 '^## ' "$INLINE")" "## After compaction"

# Links, and the files they point at.
present "links the shared final review" "$INLINE" "../../reference/final-review.md"
present "links the ruling prompt" "$INLINE" "../subagent-driven-development/references/ruling-prompt.md"
check "the shared final review exists" \
  "$([ -f "$P/reference/final-review.md" ] && echo yes || echo no)" "yes"
check "the ruling prompt exists" \
  "$([ -f "$P/skills/subagent-driven-development/references/ruling-prompt.md" ] && echo yes || echo no)" "yes"

# The mode is chosen by the plan, not by whether subagents exist.
absent "drops the upstream subagent-availability note" "$INLINE" \
  "works much better with access to subagents"

# The three ruling-seat kinds this mode can reach, and the five it cannot.
for k in blocked-plan plan-conflict final-residual; do
  present "claims the $k kind" "$INLINE" "\`$k\`"
done
# The skill names all eight kinds - three it runs and five it explains away -
# so "states the three and no others" is not greppable. Assert the three plus
# the sentence that excludes the rest.
present "names the kinds it does not run" "$INLINE" "no task reviewer"

# The fix cap, and the escalation clause both skills key on.
present "states the fix cap" "$INLINE" "fix round R/3"
present "inline writes the escalation clause" "$INLINE" "escalated inline -> subagent"
present "subagent mode reads the escalation clause" "$SDD" "escalated inline -> subagent"

# One ledger grammar for both modes.
for line in 'minor (deferred)' 'parked' 'BLOCKED' 'Ruling:' 'Final review: clean'; do
  present "inline ledger has: $line" "$INLINE" "$line"
  present "subagent ledger has: $line" "$SDD" "$line"
done
present "inline marks an unreviewed completion" "$INLINE" "unreviewed"
present "inline assigns itself" "$INLINE" "implementer inline"

# The final review lives in one place now.
present "subagent mode links the shared final review" "$SDD" "final-review.md"
absent "subagent mode no longer spells out the package call" "$SDD" \
  "review-package PLAN_FILE MERGE_BASE HEAD"
absent "inline mode does not spell out the package call" "$INLINE" \
  "review-package PLAN_FILE MERGE_BASE HEAD"
present "the shared reference spells out the package call" "$FINAL" \
  "review-package PLAN_FILE MERGE_BASE HEAD"
present "the shared reference names both modes" "$FINAL" "Inline mode"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Make it executable and run it**

Run:

```bash
git add --chmod=+x plugins/dr-superpowers/tests/inline-mode.test.sh && timeout 120 bash plugins/dr-superpowers/tests/inline-mode.test.sh 2>&1 | tail -6
```

Expected: `0 failed`.

- [ ] **Step 3: Verify the runner will discover it**

`test-all.mjs` globs the tests directory, so discovery is a filename-and-mode question, not a reason to run the whole suite (Task 6 does that once, at the end).

Run:

```bash
ls plugins/dr-superpowers/tests/inline-mode.test.sh && git ls-files -s plugins/dr-superpowers/tests/inline-mode.test.sh
```

Expected: the path exists, and git reports mode `100755` — matching the other `.test.sh` files.

- [ ] **Step 4: Commit**

```bash
git add plugins/dr-superpowers/tests/inline-mode.test.sh
git commit -m "test(superpowers): pin inline mode's structure"
```

---

### Task 6: README, version 1.5.0, full verification

**Files:**
- Modify: `plugins/dr-superpowers/README.md`
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json`
- Modify: `plugins/dr-superpowers/.codex-plugin/plugin.json`

**Interfaces:**
- Consumes: every earlier task's deliverable — this task documents and verifies them.
- Produces: nothing.

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Describe inline mode in the README**

In `plugins/dr-superpowers/README.md`, in the `## What you get` section, add this paragraph immediately before the `**An external executor lane.**` paragraph:

```markdown
**Two execution modes, chosen by the plan.** The `**Execution:**` line decides
whether a plan runs under subagent-driven-development, a dispatch and a scored
review per task, or under executing-plans, where one session implements every
task itself. Inline mode is available only when every task scores 3 or less
with none at risk 3 - `plan-lint` refuses the line otherwise - and it trades
per-task review for one whole-branch review at the end, which both modes now
share. A task that will not converge after three fix rounds escalates to
subagent mode at the next task boundary, recorded in the ledger both modes
write.
```

- [ ] **Step 2: Correct the Stops bullet in the session-budget section**

In the same file, in `## Session budget`, replace this whole bullet:

```markdown
- **Stops.** A saved plan and a finished task list are hard stops under
  subagent-driven-development; executing-plans' finished task list is a soft
  stop, continuing in-session unless the budget says otherwise. The final
  review always runs in a fresh session; see
  [session-budget.md](reference/session-budget.md) for the full Stops table.
```

with:

```markdown
- **Stops.** A saved plan, a finished task list under
  subagent-driven-development, and a switch from inline to subagent mode are
  hard stops; executing-plans' finished task list is a soft stop, continuing
  in-session unless the budget says otherwise. So the final whole-branch review
  runs in a fresh session under subagent mode and in the same session under
  inline mode; see [session-budget.md](reference/session-budget.md) for the
  full Stops table.
```

The sentence being removed — "The final review always runs in a fresh session" — is what inline mode makes untrue.

- [ ] **Step 3: Say that the Execution line is binding**

In the same file, in `## What a plan looks like`, the first paragraph already names the `**Execution:**` line as the one that "decides inline or subagent execution". That paragraph ends with the lead-in `Each task then reads:`; the new sentence goes before that lead-in, not after it. Replace:

```markdown
index. `scripts/plan-lint` checks it, and a judge reviews it against
`criteria/plan-review.md` before it is saved. Each task then reads:
```

with:

```markdown
index. `scripts/plan-lint` checks it, and a judge reviews it against
`criteria/plan-review.md` before it is saved. That Execution line is binding: a
session does not change mode because subagents happen to be available, and only
your explicit instruction overrides it. Each task then reads:
```

- [ ] **Step 4: Add the new reference to the Reference section**

In `## Reference`, replace this paragraph:

```markdown
`reference/external-executor.md` holds the Claude-hosted Codex CLI lane,
`reference/legacy-names.md` translates names written under older plugin
prefixes, and `reference/session-budget.md` holds the budget numbers,
checkpoints, stops and the Compact Instructions block.
```

with:

```markdown
`reference/external-executor.md` holds the Claude-hosted Codex CLI lane,
`reference/legacy-names.md` translates names written under older plugin
prefixes, `reference/session-budget.md` holds the budget numbers, checkpoints,
stops and the Compact Instructions block, and `reference/final-review.md` holds
the whole-branch review both execution skills end at.
```

`## Tests` needs no edit: it runs every `tests/*.test.sh` through a loop rather than listing suites.

- [ ] **Step 5: Record the mode behaviour among the differences from upstream**

In `## Differences from upstream 6.3.0`, the numbered list ends at item 9 ("Small-model planning"). Add a tenth item immediately after it, before the closing "Names written under older plugin prefixes resolve through" paragraph:

```markdown
10. **Two modes, chosen by the plan.** Upstream picks `executing-plans` when
    subagents are unavailable and recommends subagent execution otherwise. Here
    the `**Execution:**` line decides and is binding: `executing-plans` is a
    full inline mode that writes the same ledger, sends its judgment to the
    same ruling seat, and ends at the same shared
    [final-review.md](reference/final-review.md), with no per-task review. A
    task it cannot land in three fix rounds escalates to subagent mode at the
    next task boundary.
```

- [ ] **Step 6: Correct the claim that inline mode never dispatches**

In `## What you get`, the external-executor discussion still says `executing-plans` "never dispatches subagents". After Task 2 it dispatches the ruling seat and the final review. Replace:

```markdown
`**Implementer:**` still names the Claude agent for the score. `**Executor:**` is
an override on a second line, which is what makes a machine without Codex, a cold
session, and an executor whose auth has lapsed all degrade by reading a line that
is already there rather than re-deriving the assignment at dispatch. Under
`dr-superpowers:executing-plans`, which never dispatches subagents, both lines are
simply inert instead - nothing dispatches, so nothing falls back.
```

with:

```markdown
`**Implementer:**` still names the Claude agent for the score. `**Executor:**` is
an override on a second line, which is what makes a machine without Codex, a cold
session, and an executor whose auth has lapsed all degrade by reading a line that
is already there rather than re-deriving the assignment at dispatch. Under
`dr-superpowers:executing-plans`, which dispatches only the ruling seat and the
final review, both lines are simply inert instead - no task is dispatched, so
nothing falls back.
```

- [ ] **Step 7: Bump both manifests**

In `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json`, change `"version": "1.4.0",` to `"version": "1.5.0",`.

Run:

```bash
grep -h '"version"' plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json
```

Expected: two identical `"version": "1.5.0",` lines.

- [ ] **Step 8: Run the repository validator**

Run:

```bash
timeout 120 node scripts/validate-repository.mjs
```

Expected: exit 0, no errors reported.

- [ ] **Step 9: Run the full test runner**

Run:

```bash
export TMPDIR="C:/Users/quang/AppData/Local/Temp"; timeout 900 node scripts/test-all.mjs 2>&1 | tail -30
```

Expected: exactly four failing suites, all environmental and pre-existing, all measured on 2026-09-12 (see Assumptions):

| Suite | Under the runner | Directly under Bash |
|---|---|---|
| `tests/ui-discovery.test.mjs` | fails (`bash: rg: command not found`) | same |
| `plugins/dr-superpowers/tests/budget-line.test.sh` | 14 passed, 16 failed | 30 passed, 0 failed |
| `plugins/dr-superpowers/tests/context-size.test.sh` | 0 passed, 19 failed | 18 passed, 1 failed |
| `plugins/dr-superpowers/tests/snapshot.test.sh` | 19 passed, 8 failed | 27 passed, 0 failed |

Exporting `TMPDIR` in your own shell does not rescue the three git-backed suites under the runner — that is why Step 10 re-runs them directly, and Step 10's numbers are the ones that decide. A fifth failing suite, or a worse direct result in Step 10, is a real regression from this plan: fix it before continuing. Record the four in the ledger's `discovered:` field rather than fixing them.

- [ ] **Step 10: Run the git-backed suites directly**

Run each in its own Bash call, because the worktree sandbox refuses loops that invoke `bash`:

```bash
export TMPDIR="C:/Users/quang/AppData/Local/Temp"; timeout 180 bash plugins/dr-superpowers/tests/budget-line.test.sh 2>&1 | tail -4
```

Expected: `30 passed, 0 failed`.

```bash
export TMPDIR="C:/Users/quang/AppData/Local/Temp"; timeout 180 bash plugins/dr-superpowers/tests/snapshot.test.sh 2>&1 | tail -4
```

Expected: `27 passed, 0 failed`.

```bash
export TMPDIR="C:/Users/quang/AppData/Local/Temp"; timeout 180 bash plugins/dr-superpowers/tests/context-size.test.sh 2>&1 | tail -6
```

Expected: `18 passed, 1 failed`. That single failure asserts a Windows-form path and is environmental and pre-existing.

- [ ] **Step 11: Validate the marketplace and every Claude plugin**

Run:

```bash
timeout 180 claude plugin validate .claude-plugin/marketplace.json 2>&1 | tail -5
```

Expected: valid.

```bash
timeout 180 claude plugin validate plugins/dr-superpowers 2>&1 | tail -5
```

Expected: valid.

Run the same command for `plugins/dr-status`, `plugins/dcc-darkraise-ui` and `plugins/dcc-darkraise-win32ui`, one call each.

Expected: valid for each.

- [ ] **Step 12: Confirm no process was left running**

Every command in this plan runs in the foreground under `timeout`, so nothing should survive it. Confirm that rather than counting processes by name: the owner runs their own `node` and `bash`, and a name-based count says nothing about what this session started.

If you backgrounded anything at all during execution, you recorded its PID at the time. For each such PID, run:

```bash
taskkill /F /T /PID <pid> 2>/dev/null || echo "already gone: <pid>"
```

Then write one ledger line stating either `no background processes were started` or the PIDs and that each is confirmed gone. Never blanket-kill by process name.

- [ ] **Step 13: Commit**

```bash
git add plugins/dr-superpowers/README.md plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json
git commit -m "docs(superpowers): document inline mode, 1.5.0"
```
