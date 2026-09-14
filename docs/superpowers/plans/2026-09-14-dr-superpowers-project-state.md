# dr-superpowers Project State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three skills — `project-status`, `running-gates`, `distilling-docs` — plus the committed project state they read, so a session can say where a project stands, run the gates that project declares, and collapse accumulated session notes into four durable files.

**Architecture:** Everything new is Markdown: one shared reference document, three skill bodies, two skill reference files, three structural test suites, and additive edits to thirteen existing files. No new script ships; `running-gates` reads its manifest and `project-status` reads the docs tree. Each task pairs its document with the assertions that pin it, in the house pattern where a prose skill's structural claims are checked by `grep` rather than by a reviewer.

**Tech Stack:** Markdown, POSIX shell test suites (`bash`, `grep`, `awk`), git.

**Spec:** `docs/superpowers/specs/2026-09-14-dr-superpowers-project-state-design.md`

**Execution:** inline — `claude --model opus --effort low` — every task totals 4 or less and none is at risk 3; Task 11 is the only 4, so the model follows it into the Opus-low band.

**Program:** `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` — sub-project 6 of 6 — last

## Global Constraints

- Plugin version is `1.7.0` on both `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json`. The two must stay equal.
- Every change is additive. No existing plan format, ledger format, script interface or manifest format changes.
- English only, in every file: code, comments, docs, commits, tests.
- Commits follow `<type>(<scope>): <subject>`, subject 50 characters or fewer, imperative, no trailing period. The scope for this sub-project is `superpowers`.
- `plugins/dr-superpowers/skills/using-superpowers/SKILL.md` must stay at 4,800 bytes or fewer — `plugins/dr-superpowers/tests/hook.test.sh:124` asserts it. It is 4,135 bytes before this plan.
- `plugins/dr-superpowers/skills/verification-before-completion/SKILL.md` is **not** modified by any task. All sixteen `plugins/dr-superpowers/agents/impl-*.md` preload it, so a gates pointer there would reach every task implementer.
- New test suites are executable (`chmod +x`) and follow the existing pattern in `plugins/dr-superpowers/tests/inline-mode.test.sh`: a `pass`/`fail` counter, whichever of the `check`/`present`/`absent` helpers that suite actually uses (a suite that never calls `absent` does not define it), and `[ "$fail" -eq 0 ]` as the last line.
- Never commit `.superpowers/`.

## Contracts

Paths below are repository-relative. Paths inside skill bodies are relative to the skill file, per the existing house convention (`../../reference/x.md` from `skills/<name>/SKILL.md`).

**Files this plan creates**

| Path | Produced by |
|---|---|
| `plugins/dr-superpowers/reference/project-state.md` | Task 1 |
| `plugins/dr-superpowers/tests/project-status.test.sh` | Task 1, extended by Tasks 2 and 8 |
| `plugins/dr-superpowers/skills/project-status/SKILL.md` | Task 2 |
| `plugins/dr-superpowers/skills/running-gates/SKILL.md` | Task 3 |
| `plugins/dr-superpowers/tests/gates-manifest.test.sh` | Task 3, extended by Tasks 4 and 11 |
| `plugins/dr-superpowers/skills/running-gates/references/gates-template.md` | Task 4 |
| `plugins/dr-superpowers/skills/distilling-docs/SKILL.md` | Task 5 |
| `plugins/dr-superpowers/tests/distilling-docs.test.sh` | Task 5, extended by Task 6 |
| `plugins/dr-superpowers/skills/distilling-docs/references/distil-judge.md` | Task 6 |

**Skill names** (used verbatim in routing rows, cross-references and assertions): `dr-superpowers:project-status`, `dr-superpowers:running-gates`, `dr-superpowers:distilling-docs`.

**Project-state paths** that skills name, relative to an adopting project's repository root:

- `docs/superpowers/gates.md`
- `docs/superpowers/plans/completed.md`
- `docs/superpowers/distilled/constraints.md`
- `docs/superpowers/distilled/gotchas.md`
- `docs/superpowers/distilled/reference.md`
- `docs/superpowers/distilled/rejected.md`

**`gates.md` field names** — exactly nine, this spelling and case: `Command`, `Green`, `Applies`, `Evidence`, `Repo`, `Setup`, `Teardown`, `Known-flaky`, `Why`. `Command` and `Green` are required; the other seven are optional.

**`Evidence` values** — exactly four, lower case: `output` (the default), `exit`, `image`, `judgment`.

**Gate heading form:** `## <n>. <title>`, `<n>` contiguous from 1.

**`completed.md` line forms:**

```markdown
- 2026-09-12 `docs/superpowers/plans/2026-09-12-example.md` — merged into `main` at 6a4619a
- 2026-09-12 `docs/superpowers/plans/2026-09-12-example.md` — via PR
```

**Distilled entry field names**, per file: `constraints.md` uses `Set by`, `Scope`, `Source`; `gotchas.md` uses `Cause`, `Workaround`, `Verified`, `Source`; `reference.md` uses `Measured`, `Authority`, `Verified`, `Source`; `rejected.md` uses `Tried`, `Why it looked right`, `Why it failed`, `Would change if`, `Source`. Every entry carries `Source`.

**Judge verdicts** — exactly three, upper case: `CARRIED`, `MISSING`, `DISTORTED`.

**Judge agents:** `dr-superpowers:judge-fable`, with `dr-superpowers:judge-opus` as the stated substitute.

**Routing rows** added to `skills/using-superpowers/SKILL.md`'s `## Routing` table, in this order and wording:

```markdown
| Where the work stands, what to do next | dr-superpowers:project-status |
| Before the final review or merge, when `gates.md` exists | dr-superpowers:running-gates |
| Session notes have accumulated | dr-superpowers:distilling-docs |
```

**Plan discriminator** used by `project-status`: a file under `docs/superpowers/plans/` is a plan when it contains at least one `Task N` heading outside a fenced block — what `plan_tasks` in `plugins/dr-superpowers/scripts/lib/plan.sh` extracts. Not the `**Execution:**` header.

## Assumptions (evidence)

- `plugins/dr-superpowers/tests/hook.test.sh:124` caps `using-superpowers/SKILL.md` at 4,800 bytes; the file is 4,135 bytes — `wc -c`, 2026-09-14. The three routing rows are about 230 bytes with newlines, projecting to roughly 4,368 — inside the cap.
- All sixteen `plugins/dr-superpowers/agents/impl-*.md` carry `skills: - dr-superpowers:verification-before-completion` in frontmatter — `grep -l`, 2026-09-14.
- `plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md:173` states Step 6 "Runs for Option 1 and confirmed discards"; Options 2 and 3 preserve the worktree — read 2026-09-14. Task 11 binds the completed-index write to the outcome for this reason.
- `plugins/dr-superpowers/scripts/lib/plan.sh` defines `plan_tasks` (task headings outside fences) and `scripts/next-step:65-66` fails with "no tasks" when it is empty — read 2026-09-14.
- Only 5 of 20 plans in this repository and 9 of 78 in `darkraise-modder` carry a `**Execution:**` header line — `grep -l`, 2026-09-14. This is why the plan discriminator is the task-heading test.
- `plugins/dr-superpowers/agents/judge-fable.md:6` grants `tools: Read, Grep, Glob, WebFetch` and no Bash — read 2026-09-14. Task 6's judge contract depends on it.
- `scripts/detect-executors.sh` reports Codex 0.153.4 authenticated and usable — run 2026-09-14. The external lane is not used: the Execution line is `inline`, under which `**Implementer:**` and `**Executor:**` lines are inert, so no task carries an Executor line.
- Repository files use LF line endings. Task 4's validator keys on `^$` and on
  trailing whitespace, and `scripts/lib/plan.sh:37` strips `\r` for the same
  reason; Task 4's test pipes the template through `tr -d '\r'` so a CRLF
  checkout cannot turn every blank line into a stray-line error.
- `scripts/test-all.mjs` exists at the repository root, and
  `tests/ui-discovery.test.mjs` has a pre-existing failure on this machine
  (`bash: rg: command not found`) that predates this plan — verified 2026-09-14.
  Task 12 Step 6 relies on both.
- No task depends on a network call, a game install, or a corpus path.

## Task index

1. The shared project-state reference
2. The project-status skill
3. The running-gates skill
4. The gates manifest template and format validator
5. The distilling-docs skill
6. The distillation judge contract
7. Routing rows in the entry point
8. Distilled constraints in resume-execution and brainstorming
9. Distilled constraints in both execution skills
10. Gates before the final whole-branch review
11. Gates and the completed index in finishing-a-development-branch
12. README, manifests, and the program design amendment

---

### Task 1: The shared project-state reference

**Files:**
- Create: `plugins/dr-superpowers/reference/project-state.md`
- Create: `plugins/dr-superpowers/tests/project-status.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `reference/project-state.md`, which Tasks 2, 3 and 5 link to; and `tests/project-status.test.sh`, which Tasks 2 and 8 extend. Both are named in Contracts.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/project-status.test.sh`:

```bash
#!/usr/bin/env bash
# project-status and the shared project-state reference are documents, and the
# claims that make them work are structural: which files they name, which order
# their recommendation rules appear in, and which scripts they must never call.
# A model is not needed to check any of them.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
STATE="$P/reference/project-state.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
check "exists: reference/project-state.md" \
  "$([ -f "$STATE" ] && echo yes || echo no)" "yes"

# The six project-state paths. A skill that names a different path than this
# reference document is naming a file no other skill writes.
for path in \
  'docs/superpowers/gates.md' \
  'docs/superpowers/plans/completed.md' \
  'docs/superpowers/distilled/constraints.md' \
  'docs/superpowers/distilled/gotchas.md' \
  'docs/superpowers/distilled/reference.md' \
  'docs/superpowers/distilled/rejected.md'; do
  present "project-state names $path" "$STATE" "$path"
done

# The precedence order is the whole point of the document: a skill that acts on
# the losing side of it has made an error, not a judgment call.
present "project-state states precedence" "$STATE" "## Precedence"
present "project-state ranks CLAUDE.md first" "$STATE" "CLAUDE.md"
present "project-state ranks handoff above distilled" "$STATE" "yields to"
present "project-state says every file is optional" "$STATE" "optional"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
chmod +x plugins/dr-superpowers/tests/project-status.test.sh && plugins/dr-superpowers/tests/project-status.test.sh
```

Expected: FAIL — `exists: reference/project-state.md` reports `no`, and every `present` check fails because `grep` cannot open a missing file.

- [ ] **Step 3: Write the reference document**

Create `plugins/dr-superpowers/reference/project-state.md`. The outer fence here
is four backticks because the file contains a three-backtick block; write the
file with an ordinary three-backtick fence around the directory tree and none
around the file as a whole.

````markdown
# Project-declared state

A project tells a session three kinds of thing through its repository. Specs and
plans under `docs/superpowers/` are authored and permanent — the record of what
was intended. `.superpowers/` is generated, gitignored and disposable — the state
of a run in flight. This document describes the third kind: small committed
documents that state facts about the project a session cannot derive from the
code.

```
docs/superpowers/
  specs/                 authored, permanent, never deleted by a skill
  plans/                 authored, permanent, never deleted by a skill
    completed.md         append-only index of merged plans
  gates.md               what proves a change works here, in order
  distilled/
    constraints.md       owner rulings, do-nots, fixed policy
    gotchas.md           tooling and environment traps, symptom first
    reference.md         measured facts, formats, corpus numbers
    rejected.md          approaches tried and abandoned, and why
```

Every one of these is optional, and none of them is an error when absent. A
project with none of them loses nothing: each skill that reads one states what
it does without it.

## The files, by full path

- `docs/superpowers/gates.md`
- `docs/superpowers/plans/completed.md`
- `docs/superpowers/distilled/constraints.md`
- `docs/superpowers/distilled/gotchas.md`
- `docs/superpowers/distilled/reference.md`
- `docs/superpowers/distilled/rejected.md`

## Who writes what

| File | Written by | Read by |
|---|---|---|
| `gates.md` | a human, or dr-superpowers:running-gates' bootstrap on approval | dr-superpowers:running-gates |
| `plans/completed.md` | dr-superpowers:finishing-a-development-branch | dr-superpowers:project-status |
| `distilled/*.md` | dr-superpowers:distilling-docs | dr-superpowers:project-status, dr-superpowers:brainstorming, dr-superpowers:resume-execution, both execution skills |

## Precedence

When two sources disagree, this order settles it:

1. `CLAUDE.md`, `AGENTS.md`, and anything your human partner says directly.
2. `handoff.md`'s owner constraints, for the run in flight.
3. `distilled/constraints.md` — which binds like those constraints and yields to
   them wherever both speak.
4. A spec.
5. A fact in `distilled/reference.md`.

A skill that acts on the losing side of that order has made an error, not a
judgment call.

## What never happens to these files

`distilled/*.md` are written only by dr-superpowers:distilling-docs, which
deletes sources under its own rules and never touches a spec, a plan,
`completed.md`, or anything outside `docs/superpowers/notes/` and
`docs/superpowers/findings/`. `gates.md` is edited by a human or by an approved
bootstrap, never silently. `completed.md` is append-only.
````

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/project-status.test.sh
```

Expected: the summary line ends `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/reference/project-state.md plugins/dr-superpowers/tests/project-status.test.sh
git commit -m "feat(superpowers): add project-state reference"
```

---

### Task 2: The project-status skill

**Files:**
- Create: `plugins/dr-superpowers/skills/project-status/SKILL.md`
- Modify: `plugins/dr-superpowers/tests/project-status.test.sh` (append checks before the final `printf`)

**Interfaces:**
- Consumes: `reference/project-state.md` and the suite from Task 1; the plan discriminator and the six project-state paths from Contracts.
- Produces: the skill name `dr-superpowers:project-status`, which Task 7 routes to.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/project-status.test.sh`, insert this block immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
SKILL="$P/skills/project-status/SKILL.md"
check "exists: skills/project-status/SKILL.md" \
  "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"

# The one script it may call, and the two it must not. Both forbidden names
# appear in the body explaining why, so assert the prohibition rather than the
# absence: sdd-workspace runs mkdir -p and rewrites a .gitignore, and next-step
# rewrites latest.md. This skill writes nothing.
present "status calls repo-audit" "$SKILL" 'scripts/repo-audit'
present "status forbids sdd-workspace" "$SKILL" 'never call `scripts/sdd-workspace`'
present "status forbids next-step" "$SKILL" 'never calls `scripts/next-step`'

# The plan discriminator. Most plans predate the Execution header, so keying on
# it would make the skill ignore them.
present "status uses the task-heading discriminator" "$SKILL" 'plan_tasks'
present "status rejects the Execution header" "$SKILL" 'Do **not** use the `**Execution:**` header as the discriminator'

# completed.md is the only completion signal, and it gates rules 4 and 5.
present "status names the completed index" "$SKILL" 'docs/superpowers/plans/completed.md'
present "status gates rules 4 and 5 on the index" "$SKILL" 'Rules 4 and 5 require'

# The recommendation table must stay ordered: two sessions on one repo reach
# the same step only if the rules are read in a fixed order.
rules=$(grep -oE '^\| [0-7] \|' "$SKILL" | grep -oE '[0-7]' | tr '\n' ' ')
check "status rules run 0 to 7 in order" "$rules" "0 1 2 3 4 5 6 7 "
present "status rule 0 reads the last line per task" "$SKILL" "A task's **last** ledger line is"
present "status routes to resume-execution" "$SKILL" 'dr-superpowers:resume-execution'

# The five output sections, in order.
sections=$(grep -oE '^- \*\*(Repos|In flight|Not started|Owner-only items|Next step)\*\*' "$SKILL" \
  | sed 's/^- \*\*//; s/\*\*$//' | tr '\n' '|')
check "status output sections in order" "$sections" "Repos|In flight|Not started|Owner-only items|Next step|"

present "status links project-state" "$SKILL" 'project-state.md'
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
plugins/dr-superpowers/tests/project-status.test.sh
```

Expected: FAIL — `exists: skills/project-status/SKILL.md` reports `no`.

- [ ] **Step 3: Write the skill**

Create `plugins/dr-superpowers/skills/project-status/SKILL.md`:

````markdown
---
name: project-status
description: Use when asked what to do next, where the project stands, whether the work is done, or for a checkpoint - reports state and exactly one recommended next step, and writes nothing
---

# Project Status

**Announce at start:** "I'm using the project-status skill to report where this project stands."

One screen: where the repository stands, what is open, and the single next step.
This skill writes nothing — not `latest.md`, not a workspace, not a ledger. It
never calls `scripts/next-step`, which rewrites `latest.md`. See
[project-state.md](../../reference/project-state.md) for the files it reads.

## Steps

1. **Orient in one call.** Run `scripts/repo-audit`, from the plugin root (the
   path the session's entry point names; two levels above this skill's
   directory). It gives branch and HEAD, worktrees, dirty files, plans with
   ledgers, the handoff file, and recent commits.
2. **Route out if execution is live.** If a ledger has incomplete tasks and no
   task's last line is `BLOCKED`, name the plan and the task reached and route
   to dr-superpowers:resume-execution. Stop there: this skill orients a session
   with no thread to pick up, and never duplicates the resume path.
3. **Classify each plan.** A file under `docs/superpowers/plans/` is a plan when
   it has at least one `Task N` heading outside a fenced block — what
   `plan_tasks` in `scripts/lib/plan.sh` extracts, and the test `scripts/next-step`
   applies when it fails with "no tasks".
   Do **not** use the `**Execution:**` header as the discriminator:
   `plan-lint` requires it, but only plans written since 1.4.0 have one, so it
   would hide most plans. Then, in order:
   - **In flight** — `<worktree>/.superpowers/sdd/<basename minus .md>/progress.md`
     exists with incomplete tasks, checked under every worktree the audit lists,
     because a ledger lives in the worktree executing it. Compute that path
     directly; never call `scripts/sdd-workspace`, which creates the directory.
     A plan whose tasks are all complete but which is not yet indexed as merged
     is also in flight — a review or an integration is still ahead of it.
   - **Complete** — listed in `docs/superpowers/plans/completed.md`. That index
     is the only completion signal. A ledger showing every task complete is not
     one: the work may be unmerged.
   - **Not started** — neither, and only when `completed.md` exists. "No ledger"
     never means "never ran": dr-superpowers:finishing-a-development-branch
     deletes the workspace on integration.
4. **Match specs to plans.** A spec's slug is its filename without the leading
   `YYYY-MM-DD-` and the trailing `-design`. A plan matches when its filename
   without its own date prefix equals that slug; dates need not agree. A prefix
   match counts only when no other spec claims that plan exactly. A spec whose
   body decomposes a programme into sub-projects is a program design and is
   never unplanned — its plans belong to the sub-projects.
5. **Find unmerged work with no plan.** `git branch --no-merged <base>` plus the
   audit's worktrees. `<base>` is the plan's recorded base when a ledger names
   one, else `git symbolic-ref refs/remotes/origin/HEAD`, else `main` — say
   which you used, since unlike finishing-a-development-branch you have no plan,
   conversation or upstream to derive it from.
6. **Read the open constraints.** When `docs/superpowers/distilled/constraints.md`
   exists, take the entries whose scope covers the current work.
7. **Report** the shape below, then stop. There is no memory-store step: every
   line comes from the audit or the tree.

## Output

Five sections, in this order, nothing else:

- **Repos** — the audit's branch, HEAD and worktree lines.
- **In flight** — one bullet per plan with an active ledger, tasks complete of
  total, and its last ledger line; plus each unmerged branch from step 5.
- **Not started** — one bullet per un-started plan and unplanned spec, with paths.
- **Owner-only items** — decisions and prohibitions waiting on your human
  partner, including every task whose last ledger line is `BLOCKED`.
- **Next step** — exactly one, naming the skill or command that starts it.

Unfinished work always appears. Finished work appears only when touched within
seven days: for an indexed plan that is the date on its `completed.md` line (a
merged plan's file date is when it was authored), for anything else
`git log -1 --format=%cs -- <path>`.

## The recommendation is ordered, not chosen

Two sessions on one repository must reach the same step. The first matching rule
wins, and the report names which one matched.

| # | Condition | Recommendation |
|---|---|---|
| 0 | A task's **last** ledger line is `Task N: BLOCKED` | No skill. The decision it names goes under Owner-only items |
| 1 | A ledger has incomplete tasks and no such line | dr-superpowers:resume-execution |
| 2 | Every task complete, no `Final review: clean` line | the final review, via the plan's `**Execution:**` skill |
| 3 | Final review clean, branch unmerged (`git merge-base --is-ancestor <branch> <base>` exits non-zero) | dr-superpowers:finishing-a-development-branch |
| 4 | `completed.md` exists and a spec has no plan | dr-superpowers:writing-plans |
| 5 | `completed.md` exists and a plan is absent from it with no ledger | dr-superpowers:using-git-worktrees, then the plan's execution skill |
| 6 | A dirty tree with no plan in flight | name the files and ask whether they are live work |
| 7 | None of the above | say the project is between programmes, offer dr-superpowers:brainstorming |

`BLOCKED` outranks everything: `scripts/next-step` already treats it as terminal
and hands the decision to your human partner. Rule 0 reads each task's **last**
line, as both execution skills' recovery tables do, so a task that was blocked
and later ruled and completed no longer matches.

Rules 4 and 5 require `completed.md` to exist. Without it nothing can be shown to
have finished, and firing rule 5 would recommend re-executing merged work — fall
to rule 7 and say the index is absent. When several plans match one rule, take
the newest filename date and say so. When a rule matches in more than one
worktree, report each and recommend the one whose branch has the newest commit.

## Red Flags

| Thought | Reality |
|---------|---------|
| "I'll list every plan so nothing is missed" | A list of forty is a list of none. Unfinished, plus seven days. |
| "Three things look important" | Pick one by the table and say which rule matched. |
| "I know roughly where this stands" | Every line comes from the audit or the tree. Nothing from memory. |
| "No ledger, so nobody ever ran it" | The workspace is deleted on merge. Check `completed.md` first. |
| "I should write the handoff while I'm here" | This skill writes nothing. `latest.md` belongs to dr-superpowers:handoff. |
````

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/project-status.test.sh
```

Expected: the summary line ends `0 failed`.

- [ ] **Step 5: Verify the reference link resolves**

Run:

```bash
cd plugins/dr-superpowers/skills/project-status && test -f ../../reference/project-state.md && echo resolves
```

Expected: `resolves`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/skills/project-status/SKILL.md plugins/dr-superpowers/tests/project-status.test.sh
git commit -m "feat(superpowers): add project-status skill"
```

---

### Task 3: The running-gates skill

**Files:**
- Create: `plugins/dr-superpowers/skills/running-gates/SKILL.md`
- Create: `plugins/dr-superpowers/tests/gates-manifest.test.sh`

**Interfaces:**
- Consumes: `reference/project-state.md` from Task 1; the nine field names, four `Evidence` values and gate heading form from Contracts.
- Produces: the skill name `dr-superpowers:running-gates` (Tasks 7, 10, 11) and `tests/gates-manifest.test.sh` (Tasks 4 and 11 extend it).

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/gates-manifest.test.sh`:

```bash
#!/usr/bin/env bash
# The gates manifest is a format that adopting projects depend on, and the
# skill is the only specification of it. These checks pin the parts two
# sessions could otherwise read differently: the field set, the evidence
# values, the default, and the retry rule.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
SKILL="$P/skills/running-gates/SKILL.md"

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

check "exists: skills/running-gates/SKILL.md" \
  "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"

present "gates names the manifest path" "$SKILL" 'docs/superpowers/gates.md'

# Two required fields and seven optional ones.
for f in Command Green; do
  present "required field $f" "$SKILL" "**\`$f\`**"
done
for f in Applies Evidence Repo Setup Teardown Known-flaky Why; do
  present "optional field $f" "$SKILL" "**\`$f\`**"
done
present "gates says seven optional fields" "$SKILL" 'seven'

# The four evidence values and the default. Defaulting to exit would make every
# Green line decorative in a manifest that omits the field.
for v in output exit image judgment; do
  present "evidence value $v" "$SKILL" "\`$v\`"
done
present "evidence default is output" "$SKILL" 'default is `output`'
present "every gate also requires exit 0" "$SKILL" 'exit 0'

# Branch-level only. A pointer from verification-before-completion would reach
# all sixteen implementer agents.
present "gates are branch level" "$SKILL" 'branch level'

# The rules that stop a rotted or flaky manifest passing silently.
present "stop at the first red" "$SKILL" 'first red'
present "known-flaky retries only its own failure" "$SKILL" 'matches the `Known-flaky`'
present "a non-launching gate is a manifest defect" "$SKILL" 'manifest defect'
present "gates computes its own base" "$SKILL" 'merge-base'
present "gates states a skip" "$SKILL" 'silent skip'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
chmod +x plugins/dr-superpowers/tests/gates-manifest.test.sh && plugins/dr-superpowers/tests/gates-manifest.test.sh
```

Expected: FAIL — `exists: skills/running-gates/SKILL.md` reports `no`.

- [ ] **Step 3: Write the skill**

Create `plugins/dr-superpowers/skills/running-gates/SKILL.md`:

````markdown
---
name: running-gates
description: Use before the final whole-branch review or before merging, when the project declares gates in docs/superpowers/gates.md - runs the applicable gates in order and stops at the first red
---

# Running Gates

**Announce at start:** "I'm using the running-gates skill to run this project's declared gates."

A project declares what proves a change works, in order, in
`docs/superpowers/gates.md`. This skill reads that manifest and runs it. Gates
are **branch level**: they are reached from dr-superpowers:finishing-a-development-branch
and from [final-review.md](../../reference/final-review.md), never from inside a
per-task loop, where a five-gate manifest would cost more than the plan. See
[project-state.md](../../reference/project-state.md).

## The manifest format

`gates.md` is a document a human maintains, read by a model. No shipped script
parses it, so it is a convention with required fields — tight enough that two
sessions read it the same way.

- An H1, optionally followed by prose.
- Each gate is `## <n>. <title>`, `<n>` the run order, contiguous from 1.
- Under the heading, one `Field: value` line per field, in any order.
- Required: **`Command`** and **`Green`** (what output or observation proves it).
- Optional, seven of them: **`Applies`** (default `always`), **`Evidence`**
  (default `output`), **`Repo`**, **`Setup`**, **`Teardown`**,
  **`Known-flaky`** — the specific failure that is known noise — and **`Why`**,
  the reason the gate exists, which is what stops a later session deleting it.
- **Value form:** when a value both begins and ends with a backtick, those two
  delimiters are stripped and the rest is the value. Otherwise the value is the
  remainder of the line verbatim, backticks included.
- **Continuation:** a value may continue on following lines indented two spaces,
  or — when it contains its own newlines — be given as an empty `Field:` line
  followed immediately by a fenced code block. Those two forms are the only ones.
- **`Repo`:** a path relative to the manifest's repository root. The gate's
  `Command`, `Setup` and `Teardown` run with that repository as the working
  directory. Each repository has its own base and its own change set. Omitted
  means the manifest's own repository. This is what lets a manifest order a
  framework's gates before its consumer's.

A complete example, and a blank skeleton, are in
[gates-template.md](references/gates-template.md).

## Evidence

The `Evidence` field is the load-bearing part of the format. It exists because of
a recorded failure: a payload mask carried the wrong bit layout, every value in
the corpus decoded to the same wrong answer, and the suites stayed green
throughout, because nothing had looked at the output.

| Evidence | What proves it | What is not enough |
|---|---|---|
| `output` (default) | The declared `Green` text appears in this run's output | A previous run, a partial match |
| `exit` | Exit code 0 | Output that looks fine |
| `image` | Opening the artifact and writing one sentence describing what it shows | Any metric, including one reporting zero defects |
| `judgment` | A stated verdict against `Green`, with the observation it rests on | "Looks right" |

The default is `output`, not `exit`: a gate that declares `Green` and omits
`Evidence` must be judged against that text, or every `Green` line in a minimal
manifest is decorative. Every gate additionally requires its command to exit 0,
`image` and `judgment` included — a crashed run that left a readable artifact is
red. An `image` gate is never passed off numbers; the numbers say where to look.

## Steps

1. **Locate the manifest** at `<repo root>/docs/superpowers/gates.md`. Absent:
   say so, offer the bootstrap below, and fall back to the project's full test
   suite for this run. A missing manifest is not an error.
2. **Compute the base and the change set.** Determine the base yourself — the
   plan's base when a plan is in force, else `git merge-base <default branch> HEAD`,
   else ask — and state it in the report. Never expect a caller to supply one:
   dr-superpowers:finishing-a-development-branch establishes its base in Step 3,
   after the Step 1 that invokes this skill. The change set is
   `git diff --name-only <base>...HEAD` plus `git status --short`, computed per
   `Repo`, each against its own repository's default branch.
3. **Select the gates.** `Applies: always` runs. A conditional gate runs when its
   own repository's change set touches what it names. Report every skipped
   conditional gate with the reason it did not apply: a silent skip is
   indistinguishable from a forgotten one.
4. **Run in order, stop at the first red.** Later gates usually depend on earlier
   ones — a manifest whose `Repo` fields put a framework before its consumer
   encodes a build dependency — so results after a red are not unknown, they are
   meaningless.
5. **Judge by `Evidence`.** For an `image` gate, open the artifact and write the
   sentence before recording a result.
6. **`Known-flaky` never auto-passes.** Re-run once **only** when the observed
   failure matches the `Known-flaky` text. Any other failure is red on the first
   occurrence. A retry that passes is recorded as passed-on-retry, naming the
   flake.
7. **Report** one row per gate: number, title, result, and the summary line the
   command printed — plus, for `image` gates, the sentence written after looking.
   Name the base from step 2.

A gate whose command cannot launch at all — missing script, bad path — is a
**manifest defect**, not a red gate. Report it as one and say the manifest needs
updating. A manifest that has rotted silently is worse than no manifest, because
it turns a real check into a green line.

## Bootstrap

When no manifest exists and your human partner wants one, propose it from
evidence rather than asking them to dictate it: read the build, test and lint
entry points under `scripts/` or the package manifest, any CI workflow, and the
verification commands `CLAUDE.md` already names. Present the draft — ordered,
with a `Green` for each — and write it only after approval. The first version
does not need every gate; it needs the ones that are run today.

## Red Flags

| Thought | Reality |
|---------|---------|
| "The metrics say zero overlaps, so the picture is fine" | Open the picture. That is what `Evidence: image` means. |
| "It failed, but it's just this machine" | Only a failure matching `Known-flaky` gets a retry. Everything else is red. |
| "The later gates will probably pass" | Stop at the first red. Results after a failed dependency mean nothing. |
| "This gate seems obsolete, I'll skip it" | Read its `Why`. If it is dead, propose deleting it from the manifest. |
| "I'll run the gates for each task" | Gates are branch level. Per-task verification is the task's own tests. |
````

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/gates-manifest.test.sh
```

Expected: the summary line ends `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/skills/running-gates/SKILL.md plugins/dr-superpowers/tests/gates-manifest.test.sh
git commit -m "feat(superpowers): add running-gates skill"
```

---

### Task 4: The gates manifest template and format validator

**Files:**
- Create: `plugins/dr-superpowers/skills/running-gates/references/gates-template.md`
- Modify: `plugins/dr-superpowers/tests/gates-manifest.test.sh` (append before the final `printf`)

**Interfaces:**
- Consumes: the format from Task 3's skill body; the nine field names, four `Evidence` values and heading form from Contracts.
- Produces: nothing later tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/gates-manifest.test.sh`, insert this block immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
TPL="$P/skills/running-gates/references/gates-template.md"
check "exists: references/gates-template.md" \
  "$([ -f "$TPL" ] && echo yes || echo no)" "yes"

# The template is the worked example the format documents, so it must satisfy
# the format. Line classes are enumerated rather than rejected by exclusion:
# an H1, prose before the first gate, a gate heading, a blank line, a Field:
# line with one of the nine names, a two-space continuation, or a fenced line.
awk_out=$(awk '
  BEGIN {
    split("Command Green Applies Evidence Repo Setup Teardown Known-flaky Why", f, " ")
    for (i in f) field[f[i]] = 1
    split("output exit image judgment", e, " ")
    for (i in e) ev[e[i]] = 1
    expect = 1; seen_gate = 0; fence = 0
  }
  /^(```|~~~)/ { fence = !fence; next }
  fence { next }
  /^# / { if (!seen_gate) next }
  /^## / {
    if ($0 !~ /^## [0-9]+\. .+/) { print "bad heading: " $0; next }
    n = $0; sub(/^## /, "", n); sub(/\..*$/, "", n)
    if (n + 0 != expect) print "non-contiguous: want " expect " got " n
    expect = n + 1
    if (seen_gate && !(cmd && grn)) print "gate " prev " missing Command or Green"
    prev = n; cmd = 0; grn = 0; seen_gate = 1
    next
  }
  /^$/ { next }
  /^  / { next }
  !seen_gate { next }
  /^[A-Za-z-]+:/ {
    name = $0; sub(/:.*$/, "", name)
    if (!(name in field)) { print "unknown field: " name; next }
    if (name == "Command") cmd = 1
    if (name == "Green") grn = 1
    if (name == "Evidence") {
      v = $0; sub(/^Evidence:[ \t]*/, "", v); gsub(/`/, "", v); sub(/[ \t]+$/, "", v)
      if (!(v in ev)) print "bad evidence: " v
    }
    next
  }
  { print "stray line: " $0 }
  END { if (seen_gate && !(cmd && grn)) print "gate " prev " missing Command or Green" }
' <(tr -d '\r' < "$TPL"))
check "template satisfies the documented format" "$awk_out" ""

present "template shows the fenced Setup form" "$TPL" 'Setup:'
present "template shows an image gate" "$TPL" 'Evidence: image'
present "template carries a blank skeleton" "$TPL" 'Copy the block below for a new gate'
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
plugins/dr-superpowers/tests/gates-manifest.test.sh
```

Expected: FAIL — `exists: references/gates-template.md` reports `no`.

- [ ] **Step 3: Write the template**

Create `plugins/dr-superpowers/skills/running-gates/references/gates-template.md`.
Write exactly the content below — it must satisfy the validator from Step 1, so
three things are deliberate: no prose line begins `word:` (a line starting
`dr-superpowers:` would be read as an unknown field), the gates are numbered 1
to 4 with no gaps, and the skeleton sits inside a fenced block with no heading
of its own so the checker skips it entirely. The `Setup:` field in gate 3 shows
the fenced-block form for a multi-line value.

````markdown
# Gates

What proves a change works in this project, in the order it must run. This file
is read by the running-gates skill. Every gate needs a `Command` field and a
`Green` field; the seven optional ones are `Applies`, `Evidence`, `Repo`,
`Setup`, `Teardown`, `Known-flaky` and `Why`.

## 1. Build
Command: `pwsh -NoProfile -File scripts/build.ps1 -Repo both`
Green: 0 errors in both repos
Evidence: output

## 2. Layout suite
Command: `pwsh -NoProfile -File scripts/test-framework.ps1 layout`
Green: `Passed!`
Known-flaky: the routing timing gate under load

## 3. Script-schema corpus sweep
Setup:
```powershell
$env:DARKRAISE_SCRIPT_CORPUS = "D:/Games Modding/SRHD;D:/Repositories/Personal/SRHD-Mods"
```
Command: `pwsh -NoProfile -File scripts/test-framework.ps1 ScriptSchemaCorpus`
Green: `Passed!`
Teardown: `Remove-Item Env:DARKRAISE_SCRIPT_CORPUS`
Applies: changes touching ScriptSchema, ScriptValueTables, or any payload-mask or choice read
Why: the regression runner never sets the corpus variable, so these suites otherwise
  sweep only the handful of in-repo fixtures and pass green over a real mapping error

## 4. Graph capture
Command: `pwsh -NoProfile -File scripts/capture-graph.ps1 begin.svr -Sheet`
Green: no card on card, no edge through a card, no edge crossing the whole graph
Evidence: image
Applies: changes touching the script canvas, NodeGraph, layout, routing or rendering
Why: metrics have reported zero overlaps over a sheet that was visibly wrong

```markdown
Copy the block below for a new gate. It lives inside this fence so the format
check skips it.

## 1. <title>
Command: `<what to run>`
Green: <what output or observation proves it passed>
Evidence: output
Applies: always
Why: <why this gate exists, so a later session does not delete it>
```
````

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/gates-manifest.test.sh
```

Expected: the summary line ends `0 failed`. If `template satisfies the documented
format` fails, the awk output names the offending line — fix the template, not
the validator.

- [ ] **Step 5: Prove the format check can fail**

A check that never fires is worse than no check. Run this negative control from
the repository root:

```bash
printf '# G\n\n## 2. X\nCommand: `x`\nGreen: ok\n' > /tmp/bad-gates.md
sed -n "/^awk_out=/,/^' <(tr/p" plugins/dr-superpowers/tests/gates-manifest.test.sh \
  | sed '1d;$d' > /tmp/v.awk
awk -f /tmp/v.awk /tmp/bad-gates.md
rm -f /tmp/bad-gates.md /tmp/v.awk
```

Expected: `non-contiguous: want 1 got 2`. Empty output means the validator is
inert — most likely the `tr -d` argument lost its escape — and Step 4's pass was
meaningless.

- [ ] **Step 6: Verify the skill's link resolves**

Run:

```bash
cd plugins/dr-superpowers/skills/running-gates && test -f references/gates-template.md && echo resolves
```

Expected: `resolves`.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/skills/running-gates/references/gates-template.md plugins/dr-superpowers/tests/gates-manifest.test.sh
git commit -m "feat(superpowers): add gates manifest template"
```

---

### Task 5: The distilling-docs skill

**Files:**
- Create: `plugins/dr-superpowers/skills/distilling-docs/SKILL.md`
- Create: `plugins/dr-superpowers/tests/distilling-docs.test.sh`

**Interfaces:**
- Consumes: `reference/project-state.md` from Task 1; the four distilled paths, entry field names and judge verdicts from Contracts.
- Produces: the skill name `dr-superpowers:distilling-docs` (Task 7) and `tests/distilling-docs.test.sh` (Task 6 extends it).

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/distilling-docs.test.sh`:

```bash
#!/usr/bin/env bash
# This skill deletes files. The checks below pin the three conditions that make
# a deletion recoverable, the judge gate that must clear first, and the commit
# shape the recovery story depends on.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
SKILL="$P/skills/distilling-docs/SKILL.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

check "exists: skills/distilling-docs/SKILL.md" \
  "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"

# The four output files.
for f in constraints gotchas reference rejected; do
  present "names distilled/$f.md" "$SKILL" "distilled/$f.md"
done
present "every entry carries Source" "$SKILL" 'Source:'

# The three eligibility conditions. Each one closes a path by which a fact
# could be destroyed with no way back.
present "eligible paths are notes and findings" "$SKILL" 'docs/superpowers/findings/'
present "eligible is markdown only" "$SKILL" 'Markdown'
present "condition: tracked" "$SKILL" 'git ls-files --error-unmatch'
present "condition: clean" "$SKILL" 'git status --porcelain'
present "condition: unreferenced" "$SKILL" 'git grep'
present "ancestor directories count as references" "$SKILL" 'ancestor'

# Never-eligible. A judge cannot enumerate facts in a PNG, so CARRIED is
# unreachable for one by construction.
present "specs and plans are never deleted" "$SKILL" 'Never deleted'
present "hand-written research is never deleted" "$SKILL" 'docs/reverse-engineering/'
present "non-markdown under notes is never eligible" "$SKILL" 'never eligible'

# The judge gate.
present "dispatches judge-fable" "$SKILL" 'dr-superpowers:judge-fable'
present "names judge-opus as the substitute" "$SKILL" 'dr-superpowers:judge-opus'
for v in CARRIED MISSING DISTORTED; do
  present "verdict $v" "$SKILL" "$v"
done
present "judge enumerates before mapping" "$SKILL" 'enumerated'
present "commit before judging" "$SKILL" 'before the judge runs'
present "judge reads the working tree, not the commit" "$SKILL" 'no Bash'

# The commit shape.
present "exactly one removal commit" "$SKILL" 'exactly one removal commit'
present "never squashed" "$SKILL" 'squash'
present "waves are bounded" "$SKILL" 'never the whole tree'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
chmod +x plugins/dr-superpowers/tests/distilling-docs.test.sh && plugins/dr-superpowers/tests/distilling-docs.test.sh
```

Expected: FAIL — `exists: skills/distilling-docs/SKILL.md` reports `no`.

- [ ] **Step 3: Write the skill**

Create `plugins/dr-superpowers/skills/distilling-docs/SKILL.md` with the content below. Note that the outer fence in this plan is four backticks because the file itself contains a three-backtick block; write the file with ordinary three-backtick fences.

````markdown
---
name: distilling-docs
description: Use when session notes, findings and gate reports have accumulated, or after a programme completes - distils them into four durable files and deletes the tracked sources it has absorbed, gated on an independent verification
---

# Distilling Docs

**Announce at start:** "I'm using the distilling-docs skill to distil <area> into the durable files."

Session notes accumulate until nothing reads them. This skill collapses them into
four durable files and deletes the sources it has absorbed — but only tracked,
clean, unreferenced Markdown, and only after an independent judge confirms every
fact survived. See [project-state.md](../../reference/project-state.md).

## The four files

Under `docs/superpowers/distilled/`, each an H1, a one-line statement of what
belongs in it, then `## <area>` sections holding `### <entry>` blocks.

**`distilled/constraints.md`** — rulings and policy that bind future work.
Fields: `Set by`, `Scope`, `Source`.

**`distilled/gotchas.md`** — the symptom leads, because that is how a session
recognises it is inside one. Fields: `Cause`, `Workaround`, `Verified`, `Source`.

**`distilled/reference.md`** — measured facts. Fields: `Measured`, `Authority`,
`Verified`, `Source`.

**`distilled/rejected.md`** — approaches a future session would re-propose.
Fields: `Tried`, `Why it looked right`, `Why it failed`, `Would change if`,
`Source`.

An example entry, from `gotchas.md`:

```markdown
### `bash: rg: command not found` in a test that greps
Cause: ripgrep is not on PATH in Git Bash on this machine; the suite assumes it
Workaround: use the Grep tool, or `fd`; this one discovery failure is environmental
Verified: 2026-09-11
Source: docs/superpowers/notes/2026-09-11-test-env.md@e4f5a6b
```

Every entry carries a `Source:` line: the file it came from and the short SHA of
the last commit that touched it, from `git log -1 --format=%h -- <path>`, captured
before deletion. Because only tracked, clean files are eligible, that SHA always
resolves and the original is one `git show` away, permanently.

**Size discipline.** A distilled file over 400 lines has become the wall it
replaced. The next wave begins by merging duplicate and obsolete entries; if it
is still over, split by area into `distilled/<area>-<kind>.md` with an index in
the original. Splitting happens during a wave's extraction, never after that
wave's judge has ruled.

## What may be deleted

Eligible by path and extension: Markdown files (`*.md`) under
`docs/superpowers/notes/` and `docs/superpowers/findings/`. Every non-Markdown
file under those paths is **never eligible** — captures and fixtures live there
too, and a judge whose tools are `Read, Grep, Glob, WebFetch` cannot enumerate
the facts in a binary, so `CARRIED` is unreachable for one by construction.

Three conditions, checked per file, all required:

1. **Tracked** — `git ls-files --error-unmatch <path>` succeeds. An untracked
   file has no SHA, cannot be `git rm`'d, and cannot be recovered by `git show`,
   so the recovery story below does not hold for it. This excludes gitignored
   conventions such as a `.reviews/` directory or archived handoffs; they are out
   of the eligible set entirely and this skill never proposes deleting them.
2. **Clean** — `git status --porcelain -- <path>` is empty. A file with
   uncommitted edits would get a `Source:` SHA pointing at older content while
   the content you actually distilled went unrecoverable. Commit it first, or
   leave it out of the wave.
3. **Unreferenced** — `git grep` over tracked files outside those two
   directories, plus the primary checkout's `.superpowers/handoff/latest.md`,
   finds neither the file's path, nor its basename, nor any **ancestor**
   directory path beneath those roots. The ancestor check matters: a plan naming
   a capture directory references every file in it without naming one.

**Never deleted**, whatever a judge says: specs, plans, `completed.md`, `README`,
`CLAUDE.md`, `AGENTS.md`, licence files, hand-written research anywhere else in
the repository (a `docs/reverse-engineering/` tree is research, not session
detritus), and anything failing one of the three conditions. Specs and plans
are read as sources and are never targets.

## Waves

Work on a branch (dr-superpowers:using-git-worktrees), in waves of **five to
fifteen** source files covering one area, never the whole tree. A wave fits one
session with room for the judge round, and is the unit at which work can stop:
git is the ledger, so a fresh session sees what remains from the distilled files
and the log.

Per wave: inventory the sources, apply the three conditions, classify each
survivor (durable-fact carrier, superseded by code or tests, or historical record
with nothing durable in it), extract into the four files, then verify.

## The verification gate

**Commit the extraction before the judge runs.** The first commit below lands
first, and the judge is given its SHA. A judge that reads uncommitted files can
be invalidated by any later edit — a merge, a split, or a fix made for another
file's verdict — and would then be attesting to text that no longer exists.

**The judge reads the working tree, not the commit.** `agents/judge-fable.md`
grants `Read, Grep, Glob, WebFetch` and **no Bash**, so it cannot run
`git show <sha>:<path>`. Committing first therefore binds the verdict only under
three conditions you must hold: the working tree is clean at that SHA when you
dispatch, nothing is edited until the verdict returns, and the verdict names the
SHA it was given. A verdict returned against an edited tree is void; re-judge.

Dispatch dr-superpowers:judge-fable (dr-superpowers:judge-opus when Fable is
unavailable or your human partner declined it — say the substitution aloud) with
[distil-judge.md](references/distil-judge.md). It must work in one order:
enumerate every fact in each source as a numbered list first, then map each
numbered fact to the entry that carries it, and only then return a verdict. A
judge that reads holistically grades the summary it was handed.

| Verdict | Meaning | Consequence |
|---|---|---|
| `CARRIED` | Every enumerated fact maps to a named distilled entry | Eligible for deletion |
| `MISSING` | An enumerated fact maps to nothing | Fix, re-commit, re-judge |
| `DISTORTED` | A fact was carried but its meaning changed | Fix, re-commit, re-judge |

Any edit after a verdict re-judges **every** file whose entries changed, not only
the one that prompted it.

## Deletion, in two kinds of commit

```
docs(<scope>): distil <area> notes            # adds the distilled entries - no deletions
docs(<scope>): remove absorbed <area> notes   # git rm only - no content changes
```

One or more distil commits — each `MISSING` or `DISTORTED` verdict produces
another — then **exactly one removal commit**, carrying only the files the judge
returned `CARRIED` against the committed content. Never combined, and never
squashed on integration: a squash collapses the two commits the recovery story
depends on, so merge with `--no-ff` or fast-forward. Reverting a bad deletion is
then one `git revert` that keeps the distillation.

## Re-runs

Entries merge rather than accumulate. A new fact that duplicates an existing entry
updates it and adds its `Source:` line. A new fact that **contradicts** one wins
only when it is both newer and carries evidence; otherwise report both to your
human partner and drop neither. A corpus holding two opposed facts is worse than
one holding neither. Every merge happens during extraction, before that wave's
commit and judge round.

A wave that edits entries carried by an **earlier** wave is editing facts whose
sources may already be deleted, and its own judge sees only its own sources. When
that happens, include the touched entry's diff and a `git show` extract of the
source named in its `Source:` line in the dispatch, so the judge rules on the
rewrite too. Without that, a fact can be rewritten out of the corpus with no seat
having checked it.

## An external memory store

These files are repo-scoped, committed, and readable with no MCP server present:
they survive a fresh clone, reach a Codex session, and travel with the branch. An
external store holds cross-repo facts for one human's agents. They are not
substitutes, and a fact can belong in both — when one is available, offer to push
newly distilled constraints and gotchas there as well, and never do it silently.

## Red Flags

| Thought | Reality |
|---------|---------|
| "I read the whole notes directory, I can summarise it all" | Waves of five to fifteen. A summary written from a full context loses the specifics that made the note worth keeping. |
| "The judge will probably say CARRIED" | Dispatch it, against a commit. Deletion is gated on the verdict, not the expectation. |
| "This note is obviously superseded, I'll just delete it" | Three conditions, two kinds of commit, one judge. Nothing else deletes. |
| "It's only in a gitignored directory, deleting it is free" | It is untracked. Deleting it destroys it. It is not in the eligible set. |
| "One commit is tidier" | Two are what make the deletion revertible on its own. |
| "The spec says it, so I'll distil and delete the spec" | Specs and plans are sources, never targets. |
````

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/distilling-docs.test.sh
```

Expected: the summary line ends `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/skills/distilling-docs/SKILL.md plugins/dr-superpowers/tests/distilling-docs.test.sh
git commit -m "feat(superpowers): add distilling-docs skill"
```

---

### Task 6: The distillation judge contract

**Files:**
- Create: `plugins/dr-superpowers/skills/distilling-docs/references/distil-judge.md`
- Modify: `plugins/dr-superpowers/tests/distilling-docs.test.sh` (append before the final `printf`)

**Interfaces:**
- Consumes: the three verdicts and the enumerate-then-map rule from Task 5's skill body and from Contracts.
- Produces: nothing later tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/distilling-docs.test.sh`, insert this block immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
JUDGE="$P/skills/distilling-docs/references/distil-judge.md"
check "exists: references/distil-judge.md" \
  "$([ -f "$JUDGE" ] && echo yes || echo no)" "yes"

# The contract must force enumeration first. A holistic judge grades the summary
# it was handed and cannot notice a fact absent from both the summary and its
# own attention.
present "judge enumerates facts first" "$JUDGE" 'numbered list'
present "judge maps each fact to an entry" "$JUDGE" 'maps to'
for v in CARRIED MISSING DISTORTED; do
  present "judge contract verdict $v" "$JUDGE" "$v"
done
present "judge returns one verdict per source file" "$JUDGE" 'one verdict per source file'
present "judge names the SHA it was given" "$JUDGE" 'COMMIT'
present "judge is read-only" "$JUDGE" 'read-only'
present "judge rules on rewritten entries too" "$JUDGE" 'rewrite'
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
plugins/dr-superpowers/tests/distilling-docs.test.sh
```

Expected: FAIL — `exists: references/distil-judge.md` reports `no`.

- [ ] **Step 3: Write the judge contract**

Create `plugins/dr-superpowers/skills/distilling-docs/references/distil-judge.md`. The outer fence here is four backticks; write the file with ordinary three-backtick fences.

````markdown
# Distillation judge contract

The dispatch prompt for the seat that gates deletion in
dr-superpowers:distilling-docs. Fill the placeholders and send it as the whole
instruction set: the judge has no other context.

## Placeholders

- `[SOURCES]` — the wave's source file paths, one per line.
- `[DISTILLED]` — the four `docs/superpowers/distilled/*.md` paths.
- `[COMMIT]` — the SHA of the commit that added this wave's distilled entries.
- `[REWRITES]` — for each pre-existing entry this wave edited, its diff and a
  `git show` extract of the source named in its `Source:` line. `none` when the
  wave added entries only.

## The prompt

```markdown
You are verifying that a set of source documents can be safely deleted, because
every fact in them now lives in a distilled corpus. You are read-only: do not
edit any file. Your verdict decides whether these files are deleted.

Sources under review:
[SOURCES]

Distilled files as they now stand, committed at [COMMIT]:
[DISTILLED]

Pre-existing distilled entries this wave rewrote:
[REWRITES]

The working tree is clean at [COMMIT]. Read the files from the working tree.
Name [COMMIT] in your report so a later reader can tell what you judged.

Work in this order. Do not skip to the verdict.

1. For EACH source file, enumerate every fact it states, as a numbered list.
   A fact is anything a future session could act on or get wrong: a measurement,
   a rule, a constraint, a workaround, a rejected approach, an authority for a
   claim, a date that scopes one. Do not summarise, do not group, do not judge
   importance yet. A file with thirty facts gets thirty numbered lines.
2. For EACH numbered fact, say which distilled entry carries it, by file and
   entry heading - "fact 7 maps to gotchas.md 'rg not found in a test that
   greps'" - or say it maps to nothing.
3. For each rewritten entry in [REWRITES], compare the new text against the
   source extract and say whether the rewrite preserves what the source stated.
4. Return one verdict per source file:
   - CARRIED - every enumerated fact maps to a named entry, and any rewrite of
     its entries preserves the source.
   - MISSING - at least one enumerated fact maps to nothing. List those facts by
     number.
   - DISTORTED - a fact is carried but its meaning changed. Quote the source and
     the entry side by side.

Enumerate before you map. A judge that reads holistically grades the summary it
was handed, and cannot notice the fact that is absent from both the summary and
its own attention. That failure is the entire reason this seat exists.

Output: the numbered enumeration per file, the mapping, the rewrite findings,
then the verdict list. Nothing else.
```
````

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/distilling-docs.test.sh
```

Expected: the summary line ends `0 failed`.

- [ ] **Step 5: Verify the skill's link resolves**

Run:

```bash
cd plugins/dr-superpowers/skills/distilling-docs && test -f references/distil-judge.md && echo resolves
```

Expected: `resolves`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/skills/distilling-docs/references/distil-judge.md plugins/dr-superpowers/tests/distilling-docs.test.sh
git commit -m "feat(superpowers): add distillation judge contract"
```

---

### Task 7: Routing rows in the entry point

**Files:**
- Modify: `plugins/dr-superpowers/skills/using-superpowers/SKILL.md` (the `## Routing` table)
- Modify: `plugins/dr-superpowers/tests/hook.test.sh` (append before the final `printf`)

**Interfaces:**
- Consumes: the three skill names from Tasks 2, 3 and 5, and the routing row wording from Contracts.
- Produces: nothing later tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Record the current size**

Run:

```bash
wc -c plugins/dr-superpowers/skills/using-superpowers/SKILL.md
```

Expected: 4135, or close to it. The cap is 4,800 bytes, asserted at `tests/hook.test.sh:124`. If this reading is already above 4,700, stop and report: the rows will not fit and the plan's assumption is stale.

- [ ] **Step 2: Write the failing test**

In `plugins/dr-superpowers/tests/hook.test.sh`, insert this block immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
# The three project-state skills must be reachable from the entry point, which
# is the only skill list a cold session sees.
ENTRY="$HERE/../skills/using-superpowers/SKILL.md"
for s in project-status running-gates distilling-docs; do
  if grep -qF -- "dr-superpowers:$s" "$ENTRY"; then
    printf 'ok   - routing names dr-superpowers:%s\n' "$s"; pass=$((pass + 1))
  else
    printf 'FAIL - routing names dr-superpowers:%s\n' "$s"; fail=$((fail + 1))
  fi
done
if grep -qF -- 'Before the final review or merge' "$ENTRY"; then
  printf 'ok   - gates row is worded by workflow position\n'; pass=$((pass + 1))
else
  printf 'FAIL - gates row is worded by workflow position\n'; fail=$((fail + 1))
fi
```

- [ ] **Step 3: Run it and verify it fails**

Run:

```bash
plugins/dr-superpowers/tests/hook.test.sh
```

Expected: FAIL — the three `routing names` checks and the wording check fail.

- [ ] **Step 4: Add the routing rows**

In `plugins/dr-superpowers/skills/using-superpowers/SKILL.md`, in the `## Routing` table, replace this row:

```markdown
| Writing a skill | dr-superpowers:writing-skills |
```

with:

```markdown
| Writing a skill | dr-superpowers:writing-skills |
| Where the work stands, what to do next | dr-superpowers:project-status |
| Before the final review or merge, when `gates.md` exists | dr-superpowers:running-gates |
| Session notes have accumulated | dr-superpowers:distilling-docs |
```

The gates row is worded by position in the workflow, not as "proving a change
works", which would overlap the existing "Before claiming done" row.

- [ ] **Step 5: Verify the byte cap still holds**

Run:

```bash
wc -c plugins/dr-superpowers/skills/using-superpowers/SKILL.md
```

Expected: at most 4800. If it is over, shorten the three new rows to their skill
names before touching any existing row or principle.

- [ ] **Step 6: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/hook.test.sh
```

Expected: all checks pass, including `entry point is at most 4,800 bytes`.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/skills/using-superpowers/SKILL.md plugins/dr-superpowers/tests/hook.test.sh
git commit -m "feat(superpowers): route to the project-state skills"
```

---

### Task 8: Distilled constraints in resume-execution and brainstorming

**Files:**
- Modify: `plugins/dr-superpowers/skills/resume-execution/SKILL.md` (step 4)
- Modify: `plugins/dr-superpowers/skills/brainstorming/SKILL.md` (the explore-project-context bullet under **Understanding the idea**)
- Modify: `plugins/dr-superpowers/tests/project-status.test.sh` (append before the final `printf`)

**Interfaces:**
- Consumes: the distilled paths and the precedence rule from Contracts and from Task 1's reference document.
- Produces: nothing later tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/project-status.test.sh`, insert this block immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
# A constraint that outranks a spec must load where it can still bind. These
# two skills are the pick-up seat and the design seat.
RESUME="$P/skills/resume-execution/SKILL.md"
BRAIN="$P/skills/brainstorming/SKILL.md"
present "resume loads distilled constraints" "$RESUME" 'distilled/constraints.md'
present "resume loads distilled gotchas" "$RESUME" 'distilled/gotchas.md'
present "resume says constraints yield to handoff" "$RESUME" 'yield to'
present "brainstorming loads distilled constraints" "$BRAIN" 'distilled/constraints.md'
present "brainstorming loads rejected approaches" "$BRAIN" 'distilled/rejected.md'
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
plugins/dr-superpowers/tests/project-status.test.sh
```

Expected: FAIL — all five new checks report missing needles.

- [ ] **Step 3: Load the constraints in resume-execution**

In `plugins/dr-superpowers/skills/resume-execution/SKILL.md`, in step 4, replace:

```markdown
4. **Reload** `<workspace>/handoff.md`, the plan's header (run
   `scripts/task-brief --header PLAN_FILE` and read the file it prints), and
   the ledger. The owner constraints and do-nots in
   `handoff.md` bind you as if your human partner had just said them.
```

with:

```markdown
4. **Reload** `<workspace>/handoff.md`, the plan's header (run
   `scripts/task-brief --header PLAN_FILE` and read the file it prints), and
   the ledger. The owner constraints and do-nots in
   `handoff.md` bind you as if your human partner had just said them. When the
   project has them, read `docs/superpowers/distilled/constraints.md` and
   `docs/superpowers/distilled/gotchas.md` in the same step: they bind the same
   way, and yield to `handoff.md` wherever both speak. Neither is an error when
   absent. See [project-state.md](../../reference/project-state.md).
```

- [ ] **Step 4: Load the constraints in brainstorming**

In `plugins/dr-superpowers/skills/brainstorming/SKILL.md`, under **Understanding the idea**, replace:

```markdown
- Check out the current project state first (files, docs, recent commits)
```

with:

```markdown
- Check out the current project state first (files, docs, recent commits)
- Read `docs/superpowers/distilled/constraints.md` and
  `docs/superpowers/distilled/rejected.md` when the project has them: a
  constraint outranks the spec you are about to write, and a rejected approach
  is the one a fresh design most reliably re-proposes. Neither is an error when
  absent.
```

- [ ] **Step 5: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/project-status.test.sh
```

Expected: the summary line ends `0 failed`.

- [ ] **Step 6: Verify the new link resolves**

Run:

```bash
cd plugins/dr-superpowers/skills/resume-execution && test -f ../../reference/project-state.md && echo resolves
```

Expected: `resolves`.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/skills/resume-execution/SKILL.md plugins/dr-superpowers/skills/brainstorming/SKILL.md plugins/dr-superpowers/tests/project-status.test.sh
git commit -m "feat(superpowers): load distilled constraints on pick-up"
```

---

### Task 9: Distilled constraints in both execution skills

**Files:**
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` (the Setup bullet that creates `handoff.md`, near line 184)
- Modify: `plugins/dr-superpowers/skills/executing-plans/SKILL.md` (the Setup bullet that creates `handoff.md`, near line 105)
- Modify: `plugins/dr-superpowers/tests/inline-mode.test.sh` (append before the final `printf`)

**Interfaces:**
- Consumes: the distilled constraints path from Contracts; the precedence rule from Task 1's reference document.
- Produces: nothing later tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/inline-mode.test.sh`, insert this block immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
# A standing project constraint outranks a spec, so both execution skills read
# it at Setup. Without this, a plan can be executed against a constraint and
# nothing notices until a handoff.
for f in "$INLINE" "$SDD"; do
  present "setup loads distilled constraints: $(basename "$(dirname "$f")")" \
    "$f" 'distilled/constraints.md'
done
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
plugins/dr-superpowers/tests/inline-mode.test.sh
```

Expected: FAIL — both `setup loads distilled constraints` checks report missing needles.

- [ ] **Step 3: Load the constraints in subagent-driven-development**

In `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, in the
Setup section, replace this **complete** bullet — all four lines, not just the
first, or the continuation will attach itself to the new bullet:

```markdown
- Create `<workspace>/handoff.md` from the template in dr-superpowers:handoff
  if it does not exist. Update it in the same message as a ledger write
  whenever an owner constraint, gotcha, prohibition or open question changes —
  not after every task.
```

with:

```markdown
- Create `<workspace>/handoff.md` from the template in dr-superpowers:handoff
  if it does not exist. Update it in the same message as a ledger write
  whenever an owner constraint, gotcha, prohibition or open question changes —
  not after every task.
- Read `docs/superpowers/distilled/constraints.md` when the project has one. Its
  entries bind like the owner constraints in `handoff.md` and yield to them
  wherever both speak; an absent file is not an error. See
  [project-state.md](../../reference/project-state.md).
```

- [ ] **Step 4: Load the constraints in executing-plans**

In `plugins/dr-superpowers/skills/executing-plans/SKILL.md`, in the Setup
section, replace this **complete** bullet — all three lines. Note that this
file's bullet ends with a full stop where subagent-driven-development's ends
with an em dash clause; copy the text below exactly:

```markdown
- Create `<workspace>/handoff.md` from the template in dr-superpowers:handoff
  if it does not exist. Update it in the same message as a ledger write
  whenever an owner constraint, gotcha, prohibition or open question changes.
```

with:

```markdown
- Create `<workspace>/handoff.md` from the template in dr-superpowers:handoff
  if it does not exist. Update it in the same message as a ledger write
  whenever an owner constraint, gotcha, prohibition or open question changes.
- Read `docs/superpowers/distilled/constraints.md` when the project has one. Its
  entries bind like the owner constraints in `handoff.md` and yield to them
  wherever both speak; an absent file is not an error. See
  [project-state.md](../../reference/project-state.md).
```

- [ ] **Step 5: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/inline-mode.test.sh
```

Expected: every check passes, including the two new ones.

- [ ] **Step 6: Verify both links resolve**

Run:

```bash
cd plugins/dr-superpowers/skills/executing-plans && test -f ../../reference/project-state.md && echo inline-resolves
cd ../subagent-driven-development && test -f ../../reference/project-state.md && echo sdd-resolves
```

Expected: `inline-resolves` then `sdd-resolves`.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md plugins/dr-superpowers/skills/executing-plans/SKILL.md plugins/dr-superpowers/tests/inline-mode.test.sh
git commit -m "feat(superpowers): load constraints at execution setup"
```

---

### Task 10: Gates before the final whole-branch review

**Files:**
- Modify: `plugins/dr-superpowers/reference/final-review.md` (the `## The review` section)
- Modify: `plugins/dr-superpowers/tests/inline-mode.test.sh` (append before the final `printf`)

**Interfaces:**
- Consumes: the skill name `dr-superpowers:running-gates` from Task 3.
- Produces: nothing later tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/inline-mode.test.sh`, insert this block immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
# Gates run before the reviewers are dispatched: reviewing a branch that does
# not build wastes both reviewer seats.
present "final review runs gates first" "$FINAL" 'dr-superpowers:running-gates'
present "a red gate stops the review" "$FINAL" 'A red gate stops'
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
plugins/dr-superpowers/tests/inline-mode.test.sh
```

Expected: FAIL — both new checks report missing needles.

- [ ] **Step 3: Add the gates step to the final review**

In `plugins/dr-superpowers/reference/final-review.md`, in the `## The review` section, replace:

```markdown
1. **Claude review.** Dispatch a general-purpose agent on the most capable
```

with:

```markdown
0. **Gates.** When the project declares `docs/superpowers/gates.md`, run
   dr-superpowers:running-gates before dispatching any reviewer. A red gate stops
   the review: reviewing a branch that does not build, or whose suites fail,
   spends both reviewer seats on findings the gate already made. When the
   project has no manifest, say so in one line and go to step 1.
1. **Claude review.** Dispatch a general-purpose agent on the most capable
```

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/inline-mode.test.sh
```

Expected: every check passes, including the two new ones.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/reference/final-review.md plugins/dr-superpowers/tests/inline-mode.test.sh
git commit -m "feat(superpowers): run gates before the final review"
```

---

### Task 11: Gates and the completed index in finishing-a-development-branch

**Files:**
- Modify: `plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md` (Step 1; Step 5 Option 1's merged-result verification; a new completed-index section)
- Modify: `plugins/dr-superpowers/tests/gates-manifest.test.sh` (append before the final `printf`)

**Interfaces:**
- Consumes: `dr-superpowers:running-gates` from Task 3; the `completed.md` line forms from Contracts.
- Produces: `docs/superpowers/plans/completed.md` in adopting projects, which `project-status` (Task 2) reads.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

This is the only task that changes the integration path, and the only one at
risk 2: it writes a commit on the base branch. Read Step 6's existing scope line
(`SKILL.md:173`, "Runs for Option 1 and confirmed discards") before editing —
binding the index write to that step is exactly the defect this task exists to
avoid.

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/gates-manifest.test.sh`, insert this block immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
VBC="$P/skills/verification-before-completion/SKILL.md"

present "finishing prefers the gates manifest" "$FIN" 'dr-superpowers:running-gates'
present "finishing verifies the merged result with gates" "$FIN" 'gates when the project declares a manifest'
present "finishing writes the completed index" "$FIN" 'docs/superpowers/plans/completed.md'
present "index write is bound to the outcome" "$FIN" 'not to Step 6'
present "option 2 records via PR" "$FIN" 'via PR'
present "a discard records nothing" "$FIN" 'write nothing'

# All sixteen implementer agents preload verification-before-completion. A
# gates pointer there would tell every task implementer to run a branch-level
# manifest.
absent "verification-before-completion never names running-gates" "$VBC" 'running-gates'
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
plugins/dr-superpowers/tests/gates-manifest.test.sh
```

Expected: FAIL — the six `present` checks report missing needles. The `absent` check should already pass, and must keep passing.

- [ ] **Step 3: Prefer the manifest in Step 1**

In `plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md`, in Step 1, replace:

```markdown
Run the project's full test suite (`npm test` / `cargo test` / `pytest` / `go test ./...`).
```

with:

```markdown
When the project declares `docs/superpowers/gates.md`, run
dr-superpowers:running-gates — it determines its own base, so it works here even
though Step 3 has not established one yet. Otherwise run the project's full test
suite (`npm test` / `cargo test` / `pytest` / `go test ./...`).
```

- [ ] **Step 4: Verify the merged result with the manifest too**

In the same file, in Step 5's Option 1 block, replace:

```bash
# Verify tests on merged result
<test command>
```

with:

```bash
# Verify the merged result: gates when the project declares a manifest
# (dr-superpowers:running-gates), otherwise the full test suite. Gates that
# passed on the branch say nothing about the merged tree.
<test command>
```

- [ ] **Step 5: Add the completed-index section**

In the same file, immediately **before** the `## Step 6: Cleanup Workspace`
heading, insert this section. The outer fence here is four backticks because the
section contains a three-backtick block; write the section with an ordinary
three-backtick fence around the two line forms and none around the section:

````markdown
## Step 5b: Record the plan as completed

A merged plan leaves no committed trace that it ran: its ledger lives in the
gitignored workspace that Step 6 deletes, and its branch is deleted with it.
Without a record, dr-superpowers:project-status cannot tell a merged plan from
one nobody ever started, and will recommend re-executing finished work.

So append one line to `docs/superpowers/plans/completed.md` in the adopting
project. The write is bound to the **outcome**, not to Step 6 — Step 6 also runs
for a confirmed discard, and never runs for Options 2 and 3.

The two line forms:

```markdown
- 2026-09-12 `docs/superpowers/plans/2026-09-12-example.md` — merged into `main` at 6a4619a
- 2026-09-12 `docs/superpowers/plans/2026-09-12-example.md` — via PR
```

| Path | When | Which form |
|---|---|---|
| Option 1, merge locally | On the base branch, as its own commit, after Step 5's merged-result verification passes | the `merged into` form |
| Option 2, push and PR | On the branch, before the push | the `via PR` form |
| Option 3, keep as-is | Never | — |
| Confirmed discard | Never | — |

Option 3 and a confirmed discard write nothing. Step 6 runs for a discard, which
is exactly why this write is bound to the outcome and not to Step 6.

The SHA on an Option 1 line is the base branch head after the merge, not the
merge commit's own hash — a commit cannot contain its own hash, and the merge
fast-forwards when it can, leaving no merge commit at all.

Two branches each appending a last line conflict on integration. Adopting
projects add `docs/superpowers/plans/completed.md merge=union` to
`.gitattributes` so those appends resolve without one; say so once if the file
is missing that line.

There is no index when a project adopted the plugin mid-programme. Create it
with this first line; do not backfill plans whose outcome you cannot verify.

The date is the date the plan landed, which is today's date when you write the
line — not the plan file's own date. Commit an Option 1 index line as
`docs(plans): record <plan basename> as completed`.
````

- [ ] **Step 6: Name the new step in the skill's own summary**

A step the overview omits is a step a reader skips. In the same file, replace:

```markdown
**Core principle:** Verify tests → Detect environment → Present options → Execute choice → Clean up → Report the next step.
```

with:

```markdown
**Core principle:** Verify tests → Detect environment → Present options → Execute choice → Record the plan → Clean up → Report the next step.
```

- [ ] **Step 7: Route Option 1 into the new step**

A section nothing reaches is dead text. In the same file, in Step 5's Option 1
block, replace:

```markdown
Once the merged result is green: clean up the worktree (Step 6), then
delete the branch:
```

with:

```markdown
Once the merged result is green: record the plan (Step 5b), clean up the
worktree (Step 6), then delete the branch:
```

- [ ] **Step 8: Route Option 2 into the new step**

In the same file, in Step 5's Option 2 block, insert this line immediately
before the fenced `bash` block that runs `git push`:

```markdown
First record the plan in the completed index (Step 5b) and commit it on the
branch, so the line travels with the PR. Then:
```

- [ ] **Step 9: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/gates-manifest.test.sh
```

Expected: the summary line ends `0 failed`.

- [ ] **Step 10: Verify no step numbering was broken**

Run:

```bash
grep -n '^## Step' plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md
```

Expected: Steps 1 through 5, then `Step 5b: Record the plan as completed`, then
Step 6 and any later step, in ascending order with nothing renumbered.

- [ ] **Step 11: Commit**

```bash
git add plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md plugins/dr-superpowers/tests/gates-manifest.test.sh
git commit -m "feat(superpowers): gate and index branch integration"
```

---

### Task 12: README, manifests, and the program design amendment

**Files:**
- Modify: `plugins/dr-superpowers/README.md` (What you get, Tests, Reference)
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json` (version)
- Modify: `plugins/dr-superpowers/.codex-plugin/plugin.json` (version)
- Modify: `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` (§6, append the amendment)

**Interfaces:**
- Consumes: every file created by Tasks 1 through 11.
- Produces: nothing.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Bump both manifests to 1.7.0**

In `plugins/dr-superpowers/.claude-plugin/plugin.json` and
`plugins/dr-superpowers/.codex-plugin/plugin.json`, change the `"version"` value
from `"1.6.0"` to `"1.7.0"`.

- [ ] **Step 2: Verify the two agree**

Run:

```bash
grep -h '"version"' plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json
```

Expected: two identical `"version": "1.7.0",` lines.

- [ ] **Step 3: Document the three skills in the README**

In `plugins/dr-superpowers/README.md`, the "What you get" section is a sequence
of paragraphs each opening with a bold lead, not a list. Insert this paragraph
immediately after the one beginning `**Cross-family review.**` and immediately
before the `## Requirements` heading. Match the surrounding style: a single
paragraph with no indented continuation lines.

```markdown
**Project state.** `docs/superpowers/` holds what a project knows about
  itself, not just its specs and plans: `gates.md` declares the verification
  gates in order, `plans/completed.md` indexes merged plans, and `distilled/`
  holds four durable files — constraints, gotchas, reference, rejected —
  collapsed from session notes. Three skills use it. `project-status` reports
  where the work stands and exactly one next step, and writes nothing.
  `running-gates` runs the declared gates in order and stops at the first red,
  judging each by its `Evidence` type so a gate whose proof is a picture is
  never passed off a metric. `distilling-docs` distils notes into the four files
  and deletes the tracked sources it absorbed, once an independent judge has
  confirmed every enumerated fact was carried. Every one of these files is
  optional; a project without them behaves exactly as before.
```

- [ ] **Step 4: Name the new suites and the new reference document**

The Tests section is a `for` loop over `tests/*.test.sh` plus two sentences — it
lists no suites, so nothing is added there but a sentence. In
`plugins/dr-superpowers/README.md`, under `## Tests`, replace:

```markdown
Requires `jq` and `git`. No model calls: the executor suites run against a stub
`codex` on `PATH` and a synthetic roster, never the real CLI.
```

with:

```markdown
Requires `jq` and `git`. No model calls: the executor suites run against a stub
`codex` on `PATH` and a synthetic roster, never the real CLI. `project-status.test.sh`,
`gates-manifest.test.sh` and `distilling-docs.test.sh` check the project-state
skills the same way — structurally, against the documents themselves.
```

The Reference section is prose paragraphs, not a list. Append this sentence as a
new paragraph at the end of that section:

```markdown
`reference/project-state.md` describes the committed project-declared state —
`gates.md`, `plans/completed.md` and `distilled/` — and the precedence order that
settles a disagreement between them.
```

- [ ] **Step 5: Amend the program design**

In `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`, at the end
of §6 (after the last existing amendment paragraph), append:

```markdown
**Amendment 2026-09-14 (sub-project 6 spec).** The decomposition gains a sixth
sub-project, "Project state", after inline mode. `docs/superpowers/` becomes
project-declared state as well as an archive: `gates.md` declares the project's
verification gates in order, `plans/completed.md` indexes merged plans (the
workspace and its ledger are deleted on integration, so nothing committed
otherwise records that a plan ran; the line is written on a local merge and on a
PR, never on a keep or a discard), and `distilled/` holds four durable files
(constraints, gotchas, reference, rejected) distilled from session notes, whose
tracked Markdown sources are deleted once an independent judge confirms every
enumerated fact was carried. Three skills use it — `project-status` reads,
`running-gates` reads, `distilling-docs` reads and writes — and `brainstorming`,
both execution skills and `resume-execution` load `distilled/constraints.md`,
which binds like `handoff.md`'s owner constraints and yields to them on conflict.
Gates are branch-level: they are reached from `finishing-a-development-branch`
and `reference/final-review.md`, never from `verification-before-completion`,
which every implementer agent preloads. Sources: the `status` and `gate` skills
of `darkraise-modder`; its `handoff`, `resume`, `fable-review` and `merge-local`
skills are not imported. Details:
`docs/superpowers/specs/2026-09-14-dr-superpowers-project-state-design.md`.
```

- [ ] **Step 6: Run the whole suite and the validator**

Run from the repository root, with a 600-second timeout:

```bash
node scripts/validate-repository.mjs && node scripts/test-all.mjs
```

Expected: the validator reports no errors. `test-all.mjs` may report one
pre-existing environment failure in `tests/ui-discovery.test.mjs` ("documented
Win32 discovery finds centrally managed versions", `bash: rg: command not
found`) — that failure predates this plan and is not caused by it. Every other
suite passes, including the three added here.

- [ ] **Step 7: Validate the plugin manifests**

Run from the repository root, with a 300-second timeout:

```bash
claude plugin validate .claude-plugin/marketplace.json
claude plugin validate plugins/dr-superpowers
```

Expected: both report valid. If `claude` is unavailable in this environment, say
so and record it; do not claim the check passed.

- [ ] **Step 8: Commit**

```bash
git add plugins/dr-superpowers/README.md plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md
git commit -m "chore(superpowers): bump to 1.7.0"
```
