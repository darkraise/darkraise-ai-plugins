# dr-superpowers 1.7.0 — project state (sub-project 6 design)

Date: 2026-09-14. Program design:
`docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` (§6 listed five sub-projects;
this is a sixth, recorded as a dated amendment under that §6 — see §12). Revised 2026-09-14 after
two independent Fable reviews. Round one returned REJECT with 30 findings, resolved and marked
**[R<n>]**; round two confirmed 23 of those resolved and returned REJECT with 27 further findings,
resolved and marked **[S<n>]**.

Goal: make `docs/superpowers/` hold what a project knows about itself, not just the archive of
what it planned. Three skills read and write that state — one reports where the work stands, one
runs the verification gates the project declares, one collapses accumulated session notes into
four durable files and deletes what it has absorbed.

The source is `D:\Repositories\Personal\darkraise-modder\.claude\skills`, six project-local skills
written over that programme. Two of them (`handoff`, `resume`) are weaker versions of skills this
plugin already has and are not imported. One (`fable-review`) is superseded by
`reference/final-review.md`. One (`merge-local`) is project policy, not a skill. The remaining two
(`status`, `gate`) name real gaps, and the third skill here answers a problem that programme
produced but never solved: 51 Markdown files under `docs/superpowers/notes/` and
`docs/superpowers/findings/` that no longer have a reader. **[R7]**

## 1. Decisions fixed here

- **Three new skills, one sub-project** (owner answer). `project-status`, `running-gates` and
  `distilling-docs` ship together because they share one interface — project-declared state under
  `docs/superpowers/` — and cross-reference each other. Rejected: three separate specs, which would
  have written the same §3 three times.
- **The gate manifest is read by a skill, not executed by a script** (owner answer). A project
  declares its gates in `docs/superpowers/gates.md`; `running-gates` reads it and runs each command
  itself. Rejected: a machine-readable manifest plus a `scripts/run-gates` executor — it cannot
  judge a gate whose evidence is an image, and it would make the format a parser contract rather
  than a document a human maintains.
- **`gates.md` lives under `docs/superpowers/`** (owner answer), with the specs and plans, and is
  committed. Rejected: `.superpowers/gates.md` — every adopting project so far gitignores that
  directory (this repo's `.gitignore:15`, the modder's `.gitignore:432`) and the plugin never
  commits it, so a manifest there could not travel with the repo **[R8]**; and a root `GATES.md`,
  which puts a top-level file in every adopting project.
- **Gates run at branch level, never inside the per-task loop.** `running-gates` is invoked from
  `reference/final-review.md` and from `finishing-a-development-branch`, and from no other skill
  (`using-superpowers` routes to it, which is not an invocation). **[S14]** In
  particular it is **not** referenced from `verification-before-completion`, which all sixteen
  `agents/impl-*.md` preload — a pointer there would tell every task implementer to run the whole
  branch manifest. **[R9]** A task's own tests stay its gate.
- **`distilling-docs` deletes only tracked files**, gated on an independent judge verdict given
  committed content, in a commit separate from the one that writes the distilled content.
  **[R19, R21]** Rejected: archiving under `docs/superpowers/archive/`, which leaves the same files
  in the tree under a name that invites reading them; and additive-only, which is the status quo.
- **Specs, plans and hand-written reference documentation are never deletable**, and neither is
  anything untracked. §6.2 fixes the eligible set by path.
- **The distilled constraints are loaded wherever they can bind** (owner answer, option 2 of
  three), not only on resume: §3 ranks `distilled/constraints.md` above a spec, so `brainstorming`,
  both execution skills' Setup and `resume-execution` all read it, below `handoff.md`'s constraints and yielding to them on conflict. **[R25, S13]**
  Rejected: on-demand
  only, which reproduces today's failure where a note exists and nothing reads it; and naming them
  in `using-superpowers`, which would put project documents in every session's always-on context,
  in every repo, including those that have none.
- **A merged plan is recorded in a committed index.** `finishing-a-development-branch` deletes a
  plan's workspace on integration (`SKILL.md:185`), and the ledger lives in a gitignored directory,
  so after a merge nothing committed says the plan ever ran. It appends one line to
  `docs/superpowers/plans/completed.md` instead. Without it, `project-status` reports every merged
  plan as never started and recommends re-executing it. **[R2]**
- **`project-status` adds no script and never writes.** It calls `scripts/repo-audit`, computes
  ledger paths directly, and reads the docs tree. It does not call `scripts/next-step` (which
  rewrites `latest.md`) and it does not call `scripts/sdd-workspace` (which runs `mkdir -p` and
  rewrites a `.gitignore`, so calling it per plan would create an empty workspace for every plan in
  the repo). **[R1]** Rejected: teaching `repo-audit` to enumerate un-started plans — `resume-execution`,
  `using-superpowers`, `reference/session-budget.md`, `README.md` and `tests/repo-audit.test.sh`
  name it **[R6, S11]**, and the new data
  serves one reader.
- **Version 1.7.0** on both manifests. Every change is additive; no existing plan, ledger or
  manifest format changes.

## 2. File layout

Paths relative to `plugins/dr-superpowers/` unless stated.

New:
- `skills/project-status/SKILL.md`
- `skills/running-gates/SKILL.md`
- `skills/running-gates/references/gates-template.md`
- `skills/distilling-docs/SKILL.md`
- `skills/distilling-docs/references/distil-judge.md`
- `reference/project-state.md`
- `tests/project-status.test.sh`
- `tests/gates-manifest.test.sh`
- `tests/distilling-docs.test.sh`

Changed:
- `skills/using-superpowers/SKILL.md` — three routing rows (§8)
- `skills/resume-execution/SKILL.md` — step 4 loads the distilled constraints (§7.3)
- `skills/subagent-driven-development/SKILL.md`, `skills/executing-plans/SKILL.md` — Setup loads
  them too (§7.3) **[R25]**
- `skills/brainstorming/SKILL.md` — the context step loads them (§7.3) **[R25]**
- `skills/finishing-a-development-branch/SKILL.md` — Step 1 prefers the manifest; Step 6 appends to
  the completed index (§7.2)
- `reference/final-review.md` — gates run before the review (§7.4) **[R10]**
- `.gitattributes` (adopting project, not the plugin) — `docs/superpowers/plans/completed.md merge=union`,
  so two branches appending a line do not conflict (§4.4) **[S2]**
- `README.md` — What you get, Tests, Reference
- `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` — 1.7.0

Not changed: `skills/verification-before-completion/SKILL.md` **[R9]**, and `scripts/repo-audit`.

`scripts/validate-repository.mjs` (repo root) discovers skills by directory and needs no edit; its
cross-reference check requires that every `dr-superpowers:<name>` mentioned in a skill resolves to
a real skill directory, which the three new names do.

## 3. `docs/superpowers/` as project-declared state

The plugin already writes two kinds of file into a project: specs and plans (authored, permanent,
the record of intent) and `.superpowers/` runtime state (generated, gitignored, disposable). This
sub-project adds a third kind — small, committed documents that tell a session facts about the
project it cannot derive from the code:

```
docs/superpowers/
  specs/                 authored, permanent, never deleted by a skill
  plans/                 authored, permanent, never deleted by a skill
    completed.md         append-only index of merged plans                (§4.4)
  gates.md               what proves a change works here, in order        (§5)
  distilled/
    constraints.md       owner rulings, do-nots, fixed policy             (§6.1)
    gotchas.md           tooling and environment traps, symptom first
    reference.md         measured facts, formats, corpus numbers
    rejected.md          approaches tried and abandoned, and why
```

Every one of these is optional. A project with none of them loses nothing it has today: each skill
that reads one states what it does when the file is absent, and none of them is an error.

Precedence when two sources disagree: `CLAUDE.md` and a direct instruction from the human partner
outrank everything; then `handoff.md`'s owner constraints for the run in flight; then
`distilled/constraints.md` (which yields to `handoff.md` whenever both speak) **[S13]**; then a
spec; then a distilled `reference.md` fact. A skill that acts on
the losing side of that order has made an error, not a judgment call. §7.3 places the read in every
skill where that precedence can be exercised — a constraint that only loads on resume would rank
above a spec in this table and below it in practice. **[R25]**

`reference/project-state.md` carries this section, the precedence order and the file table, so the
three skills point at one description instead of restating it.

## 4. `project-status`

**Description line:** `Use when asked what to do next, where the project stands, whether the work
is done, or for a checkpoint — reports state and exactly one recommended next step, and writes
nothing.`

**Announce:** "I'm using the project-status skill to report where this project stands."

### 4.1 Steps

1. **Run `scripts/repo-audit`** from the plugin root. It supplies branch and HEAD, worktrees, dirty
   files, plans in flight with ledger progress, the handoff file with its `**Status:**` and
   `**Next:**` lines, and recent commits — in one call rather than the five to eight a session
   would otherwise spend.
2. **Route out if execution is live.** If the audit shows a plan whose ledger has incomplete tasks
   and no `BLOCKED` line, say so, name the plan and the task reached, and route to
   `dr-superpowers:resume-execution` instead of continuing. Status orients a session with no
   obvious thread; it never duplicates the resume path.
3. **Classify each plan.** A file under `docs/superpowers/plans/` is a plan when it contains at
   least one `Task N` heading outside a fenced block — what `plan_tasks` in `scripts/lib/plan.sh`
   extracts, and the same test `scripts/next-step` applies when it fails with "no tasks". **[S1]**
   Not the `**Execution:**` header: `plan-lint` requires it, but only plans written since 1.4.0
   have one — 5 of 20 plans in this repo and 9 of 78 in the modder repo — so that discriminator
   would ignore most real plans while excluding the one file it was aimed at.
   `2026-08-09-reply-back-spike-results.md` has no task headings and is correctly excluded by the
   task test. For each plan, in this order:
   - **In flight** — `<worktree>/.superpowers/sdd/<basename minus .md>/progress.md` exists with
     incomplete tasks, checked under **every** worktree `repo-audit` lists, not only the current
     root: a ledger lives in the worktree executing it, which is why the audit walks them all.
     **[S5]** That path is computed directly, never by calling `scripts/sdd-workspace`. **[R1]**
     A plan whose every task is complete but which is not yet indexed as merged is also In flight —
     it still has a final review or an integration ahead of it. **[S4]**
   - **Complete** — listed in `docs/superpowers/plans/completed.md` (§4.4). That index is the only
     completion signal; a ledger recording every task complete is not one, because the work may
     still be unmerged. **[S4]**
   - **Not started** — neither of the above, and only when `completed.md` exists (§4.4). "No ledger"
     alone never means "never ran", because `finishing-a-development-branch` deletes the workspace
     on integration. **[R2]**
4. **Match specs to plans.** The slug of a spec is its filename minus the leading `YYYY-MM-DD-`
   and the trailing `-design`; a plan matches if its filename minus its own date prefix equals that
   slug. Dates need not agree. A prefix match counts only when no other spec claims that plan by
   exact match — otherwise spec `dcc-statusline` would count `2026-07-28-dcc-statusline-visual-redesign`,
   which belongs to a different spec. **[S25]** A spec whose body contains a decomposition
   section listing sub-projects is a program design and is never reported as unplanned — its plans
   are the sub-projects'. **[R3]**
5. **Find unmerged work with no plan.** `git branch --no-merged <base>` and the audit's worktree
   list: a branch carrying commits that is not merged into its base is open work even when no plan
   names it. **[R29]** `<base>` is the plan's recorded base when a ledger names one, else the
   repository default branch from `git symbolic-ref refs/remotes/origin/HEAD`, else `main`; status
   states which it used, because unlike `finishing-a-development-branch` it has no plan, no
   conversation and no upstream to derive one from. **[S6]**
6. **Read the open constraints.** If `docs/superpowers/distilled/constraints.md` exists, take the
   entries whose scope covers the current work — the owner-only items still in force.
7. **Report** in the shape below, then stop. There is no memory-store step: §4.2 fixes five
   sections with no home for recalled milestones, and §4.5 forbids reporting anything not read from
   the audit or the tree. **[S18]**

### 4.2 Output

Five sections, in this order, nothing else:

- **Repos** — the audit's branch, HEAD and worktree lines.
- **In flight** — one bullet per plan with an active ledger, with tasks complete of total and the
  last ledger line; plus each unmerged branch from step 5.
- **Not started** — one bullet per un-started plan and unplanned spec, with the path.
- **Owner-only items** — decisions, approvals and prohibitions waiting on the human partner,
  including every `BLOCKED` ledger line (§4.3 rule 0).
- **Next step** — exactly one, naming the skill or command that starts it.

Unfinished work always appears; finished work appears only when touched in the last seven days.
For an indexed plan, touched means the date on its `completed.md` line — a merged plan's file date
is when it was authored, not when it landed, and its ledger is gitignored. For anything else it
means `git log -1 --format=%cs -- <path>` within seven days of today. **[R5, S21]** A
status report that lists every plan the project ever had has told the reader nothing.

### 4.3 The recommendation is ordered, not chosen

Two sessions running status on the same repo must recommend the same step. The first matching rule
wins, and the report names the rule that matched:

| # | Condition | Recommendation |
|---|---|---|
| 0 | A task's **last** ledger line is `Task N: BLOCKED` | No skill. The decision the line names goes under Owner-only items **[R4, S19]** |
| 1 | A ledger has incomplete tasks and no `BLOCKED` line | `dr-superpowers:resume-execution` (reached at step 2) |
| 2 | Every task complete, no `Final review: clean` line in the ledger | the final review, via the plan's `**Execution:**` skill |
| 3 | Final review clean, branch unmerged — `git merge-base --is-ancestor <branch> <base>` exits non-zero **[R5]** | `dr-superpowers:finishing-a-development-branch` |
| 4 | `completed.md` exists and a spec has no plan (§4.1 step 4) | `dr-superpowers:writing-plans` |
| 5 | `completed.md` exists and a plan is absent from it with no ledger | `dr-superpowers:using-git-worktrees`, then the plan's execution skill **[S3]** |
| 6 | A dirty tree with no plan in flight | name the files and ask whether they are live work |
| 7 | None of the above | say the project is between programmes, and offer `dr-superpowers:brainstorming` |

`BLOCKED` outranks everything because `scripts/next-step` already treats it as terminal — it sets
`launch=0` and hands the decision to the human partner — and status must not contradict the script
the rest of the plugin uses. **[R4]** Rule 0 reads the **last** line for each task, as both
execution skills' recovery tables do, so a task that was BLOCKED and later ruled and completed no
longer matches. **[S19]**

Rules 4 and 5 require `completed.md` to exist. Without it no plan can be shown to have finished, so
firing rule 5 would recommend re-executing arbitrary merged work; status falls to rule 7 and says
the index is absent. **[S3]** When several plans match one rule, take the newest filename date and
say so. When a rule matches in more than one worktree, report each and recommend the one whose
branch has the newest commit, saying why.

### 4.4 `docs/superpowers/plans/completed.md`

Append-only, one line per merged plan, written by `finishing-a-development-branch` (§7.2):

```markdown
- 2026-09-12 `docs/superpowers/plans/2026-09-12-dr-superpowers-inline-mode.md` — merged into `main` at 6a4619a
```

A line is written on exactly two of `finishing-a-development-branch`'s paths, and the format
differs because the available evidence does. **[S2]**

| Path | When the line is written | Form |
|---|---|---|
| Option 1, merge locally | On the base branch, as its own commit, after Step 5's merged-result verification passes | `merged into <base> at <sha7>`, the SHA being the base head at that moment |
| Option 2, push and PR | On the branch, before the push | `via PR` and no SHA |
| Option 3, keep as-is | Never | — |
| Confirmed discard | Never | — |

The SHA cannot be the merge commit's own — a commit cannot contain its own hash, and Step 5's
`git merge` fast-forwards when it can, leaving no merge commit at all. A discard runs Step 6 too,
so the write is bound to the outcome rather than to the step. Two branches each appending a last
line collide on integration, which
`docs/superpowers/plans/completed.md merge=union` in the adopting project's `.gitattributes`
resolves without a conflict.

It exists because a merged plan leaves no committed trace that it ran: the ledger is deleted with
the workspace, and the branch is deleted with it. A project that adopts the plugin mid-programme
has no index, so status treats an absent `completed.md` as "no plans are known complete", says so,
and suppresses rules 4 and 5 (§4.3) rather than declaring every plan in the repository
unstarted. **[R2, S3, S23]**

### 4.5 Red flags

| Thought | Reality |
|---|---|
| "I'll list every plan so nothing is missed" | A list of forty is a list of none. Unfinished, plus seven days. |
| "Three things look important" | Pick one by §4.3 and say which rule matched. |
| "I know roughly where this stands" | Every line comes from the audit or the docs tree. Nothing from memory. |
| "No ledger, so nobody ever ran it" | The workspace is deleted on merge. Check `completed.md` first. |
| "I should write the handoff while I'm here" | Status writes nothing — not `latest.md`, not a workspace. |

## 5. `running-gates`

**Description line:** `Use before the final whole-branch review or before merging, when the project
declares gates in docs/superpowers/gates.md — runs the applicable gates in order and stops at the
first red.`

**Announce:** "I'm using the running-gates skill to run this project's declared gates."

### 5.1 The manifest format

`docs/superpowers/gates.md` is a document a human maintains, read by a model. It is not parsed by
any shipped script, so the format is a convention with required fields rather than a grammar — but
it is tight enough that two sessions write and read it the same way.

- An H1, optionally followed by prose.
- Each gate is `## <n>. <title>`, where `<n>` is the run order, contiguous from 1.
- Under the heading, one `Field: value` line per field, in any order.
- Required: **`Command`** and **`Green`**.
- Optional, seven of them **[R14]**: **`Applies`** (default `always`) — prose naming what a change
  must touch for the gate to be required; **`Evidence`** (default `output`) — one of `exit`,
  `output`, `image`, `judgment`; **`Repo`**; **`Setup`**; **`Teardown`**; **`Known-flaky`** — the
  specific failure that is known noise; **`Why`** — the reason the gate exists, which is what stops
  a later session deleting it.
- **Value form** **[R17, S16]**: when a value both begins and ends with a backtick, those two
  delimiters are stripped and the rest is the value, so ``Green: `Passed!` `` matches `Passed!`.
  Otherwise the value is the remainder of the line verbatim, backticks included — a `Why` line that
  quotes two command names mid-sentence is prose, not a quoted value.
- **Continuation** **[R13]**: a value may continue on following lines indented by two spaces, or —
  when it contains its own newlines, such as a shell snippet — be given as an empty `Field:` line
  followed immediately by a fenced code block. Those two forms are the only ones.
- **`Repo`** **[R15]**: a path relative to the manifest's repository root. The gate's `Command`,
  `Setup` and `Teardown` run with that repository as the working directory; step 2 computes a
  change set in every distinct `Repo` named by the manifest, and a conditional gate applies when
  the change set of *its own* `Repo` matches. Each repository has its own base — `git merge-base`
  against that repository's default branch, run inside it, unless the gate supplies one — since the
  manifest's base says nothing about a sibling checkout. **[S17]** Omitted means the manifest's own
  repository. This is
  what lets a manifest order a framework's gates before its consumer's.

~~~markdown
# Gates

## 1. Build
Command: `pwsh -NoProfile -File scripts/build.ps1 -Repo both`
Green: 0 errors in both repos
Evidence: output

## 2. Layout suite
Command: `pwsh -NoProfile -File scripts/test-framework.ps1 layout`
Green: `Passed!`
Known-flaky: the routing timing gate under load

## 3. Graph capture
Command: `pwsh -NoProfile -File scripts/capture-graph.ps1 begin.svr -Sheet`
Green: no card on card, no edge through a card, no edge crossing the whole graph
Evidence: image
Applies: changes touching the script canvas, NodeGraph, layout, routing or rendering
Why: metrics have reported zero overlaps over a sheet that was visibly wrong
~~~

`references/gates-template.md` carries this example, numbered contiguously from 1 so that the
shipped template satisfies the check the shipped test runs **[R12]**, plus a blank skeleton and one
gate using the fenced-block form for `Setup`.

### 5.2 Evidence types

The `Evidence` field is the load-bearing part of the format, and it exists because of a recorded
failure: in the modder programme an Owner payload mask carried the 2004 bit layout instead of
RScript 4.15f's, every `PiratePlanet` in the corpus read as "As player", and the suites were green
throughout, because nothing had looked at the output.

| Evidence | What proves it | What is not enough |
|---|---|---|
| `output` (default) | The declared `Green` text appears in this run's output, **and** the command exits 0 | A previous run, a partial match |
| `exit` | Exit code 0 | Output that looks fine |
| `image` | Opening the artifact and writing one sentence describing what it shows | Any metric, including one that reports zero defects |
| `judgment` | A stated verdict against `Green`, with the observation it rests on | "Looks right" |

The default is `output`, not `exit` **[R16]**: a gate that declares `Green: `Passed!`` and omits
`Evidence` must be judged against that text. Defaulting to `exit` would have made every `Green`
line in a minimal manifest decorative — which is the exact failure §5.2 exists to prevent.

Every gate additionally requires its command to exit 0, `image` and `judgment` included: a crashed
run that happened to leave a readable artifact is red. **[S24]** An `image` gate is never passed off
numbers — the numbers say where to look.

### 5.3 Steps

1. **Locate the manifest** at `<repo root>/docs/superpowers/gates.md`. Absent: say so, offer the
   bootstrap in §5.4, and fall back to the project's full test suite for this run. A missing
   manifest is not an error.
2. **Compute the change set and the base.** `running-gates` determines its own base — the plan's
   base if a plan is in force, else `git merge-base <default branch> HEAD`, else ask — and states
   it in the report. It never expects a caller to supply one, because
   `finishing-a-development-branch` establishes its base in Step 3, after the Step 1 that invokes
   this skill. **[R11]** The change set is `git diff --name-only <base>...HEAD` plus
   `git status --short`, computed per `Repo` (§5.1).
3. **Select the gates.** `Applies: always` runs. A conditional gate runs when its repository's
   change set touches what it names. Every skipped conditional gate is reported with the reason it
   did not apply; a silent skip is indistinguishable from a forgotten one.
4. **Run in order, stop at the first red.** Later gates usually depend on earlier ones — a manifest
   whose `Repo` fields order a framework before its consumer encodes a build dependency — so
   results after a red are not merely unknown, they are meaningless.
5. **Judge by `Evidence`**, per §5.2. For an `image` gate, open the artifact and write the sentence
   before recording a result.
6. **`Known-flaky` never auto-passes, and never covers a different failure.** Re-run once **only**
   when the observed failure matches the `Known-flaky` text. **[R18]** Any other failure is red on
   the first occurrence. A retry that passes is recorded as passed-on-retry, naming the flake.
7. **Report** one row per gate: number, title, result, and the summary line the command printed —
   plus, for `image` gates, the sentence written after looking. The report names the base from
   step 2.

A gate whose command cannot launch at all (missing script, bad path) is a **manifest defect**, not
a red gate. Report it as such and say the manifest needs updating: a manifest that has rotted
silently is worse than no manifest, because it converts a real check into a green line.

### 5.4 Bootstrap

When no manifest exists and the human partner wants one, propose it from evidence rather than
asking them to dictate it: read the build, test and lint entry points under `scripts/` or the
package manifest, any CI workflow, and the verification commands `CLAUDE.md` already names. Present
the draft — ordered, with a `Green` for each — and write it only after approval. The first version
does not need every gate; it needs the ones that are run today.

### 5.5 Red flags

| Thought | Reality |
|---|---|
| "The metrics say zero overlaps, so the picture is fine" | Open the picture. That is what `Evidence: image` means. |
| "It failed, but it's just this machine" | Only a failure matching `Known-flaky` gets a retry. Everything else is red. |
| "The later gates will probably pass" | Stop at the first red. Results after a failed dependency mean nothing. |
| "This gate seems obsolete, I'll skip it" | Read its `Why`. If it is genuinely dead, propose deleting it from the manifest. |
| "I'll run the gates for each task" | Gates are branch-level. Per-task verification is the task's own tests. |

## 6. `distilling-docs`

**Description line:** `Use when session notes, findings and gate reports have accumulated, or after
a programme completes — distils them into four durable files and deletes the tracked sources it has
absorbed, gated on an independent verification.`

**Announce:** "I'm using the distilling-docs skill to distil <area> into the durable files."

### 6.1 The four files

`docs/superpowers/distilled/`, each an H1, a one-line statement of what belongs in it, then
`## <area>` sections holding `### <entry>` blocks.

**`constraints.md`** — rulings and policy that bind future work.
```markdown
### The modder repo is never merged before the framework
Set by: owner, 2026-09-08
Scope: any branch touching both checkouts
Source: docs/superpowers/notes/2026-09-08-merge-order.md@a1b2c3d
```

**`gotchas.md`** — the symptom leads, because that is how a session recognises it is inside one.
```markdown
### `bash: rg: command not found` in a test that greps
Cause: ripgrep is not on PATH in Git Bash on this machine; the suite assumes it
Workaround: use the Grep tool, or `fd`; treat this one ui-discovery failure as environmental
Verified: 2026-09-11
Source: docs/superpowers/notes/2026-09-11-test-env.md@e4f5a6b
```

**`reference.md`** — measured facts, with how they were measured and what settled them.
```markdown
### Auto-compaction fires at 93–96% of autoCompactWindow, not at the window
Measured: preTokens 467,031 / 466,982 / 479,296 observed at autoCompactWindow=500000, from
  transcript `compact_boundary` entries
Authority: Claude Code session transcripts
Verified: 2026-09-11
Source: docs/superpowers/notes/2026-09-11-compaction.md@c7d8e9f
```

**`rejected.md`** — the approaches a future session would otherwise re-propose.
```markdown
### A PreCompact hook that shapes the compaction summary
Tried: 2026-09-11
Why it looked right: compaction drops rulings, so shaping the summary would preserve them
Why it failed: a PreCompact hook cannot influence the summary content
Would change if: the host exposes summary content to the hook
Source: docs/superpowers/specs/2026-09-11-dr-superpowers-session-budget-design.md@2120edc
```

Every entry carries a `Source:` line naming the file it came from and the short SHA of the last
commit that touched it, from `git log -1 --format=%h -- <path>`, captured before deletion. Because
§6.2 admits only tracked, clean files, that SHA always resolves and the original is one `git show`
away, permanently. **[R19, R20]**

**Size discipline.** A distilled file over 400 lines has become the wall it replaced. The next wave
begins by merging duplicate and obsolete entries in it; if it is still over, split it by area into
`distilled/<area>-<kind>.md` with an index in the original. Splitting is part of a wave's extraction
step, never something done after that wave's judge has ruled (§6.4). **[R21]**

### 6.2 What may be deleted

Eligible **by path and extension**: `*.md` directly under `docs/superpowers/notes/**` and
`docs/superpowers/findings/**`. **[R22, S7]** Every non-Markdown file under those paths is never
eligible — the modder repo holds 52 PNG captures and 25 `.svr` fixtures there, and a judge whose
tools are `Read, Grep, Glob, WebFetch` cannot enumerate the facts in a binary, so `CARRIED` is
unreachable for one by construction.

Three conditions, each checked per file, all required:

1. **Tracked** — `git ls-files --error-unmatch <path>` succeeds. **[R19]** Untracked files have no
   SHA, cannot be `git rm`'d, and cannot be recovered by `git show`, so the §6.5 recovery story
   does not hold for them. This excludes `.reviews/` (0 tracked files in the modder repo) and
   `.superpowers/handoff/` archives, both of which are gitignored project conventions rather than
   anything this plugin writes; they are out of the eligible set entirely, and the skill never
   proposes deleting them.
2. **Clean** — `git status --porcelain -- <path>` is empty. **[R20]** A file with uncommitted edits
   would get a `Source:` SHA pointing at older content while the distilled working-tree content
   went unrecoverable. A dirty source is not in the wave; commit it first or leave it.
3. **Unreferenced** — `git grep` over tracked files outside `docs/superpowers/notes/` and
   `findings/`, plus the primary checkout's `.superpowers/handoff/latest.md`, finds neither the
   file's path, nor its basename, nor any ancestor directory path beneath those two roots.
   **[R22, S27]** The ancestor check matters: a plan that names `notes/p4-captures/` as a directory
   references every file in it without naming one. **[S7]** A note read by a test, a script or a
   spec is a dependency, not detritus.

**Never eligible**, whatever a judge says: specs, plans, `completed.md`, `README`, `CLAUDE.md`,
`AGENTS.md`, licence files, everything outside the two eligible paths — including hand-written
research such as the modder repo's `docs/reverse-engineering/` — and anything failing one of the
three conditions. Specs and plans are read as sources for distillation and are never deleted by it.

### 6.3 Waves

Work on a branch (`dr-superpowers:using-git-worktrees`), in waves of five to fifteen source files
covering one area, never the whole tree. **[R24]** A wave is sized to fit one session with room for
the judge round, and is the unit at which work can stop: git is the ledger, so a fresh session sees
which areas remain by reading the distilled files and the log.

Per wave: inventory the sources, apply §6.2's three conditions, classify each survivor (durable-fact
carrier, superseded by code or tests, or historical record with nothing durable in it), extract into
the four files, then §6.4.

### 6.4 The verification gate

**Commit the extraction first.** The first commit of §6.5 lands before the judge is dispatched, and
the judge is given that commit's SHA. **[R21]** A judge that reads uncommitted files can be
invalidated by any later edit — a merge under §6.6, a split under §6.1, or a fix made for another
file's `MISSING` verdict — and its verdict would then attest to text that no longer exists.

**The judge reads the working tree, not the commit.** `agents/judge-fable.md` grants
`Read, Grep, Glob, WebFetch` and no Bash, so it cannot run `git show <sha>:<path>`. Committing first
therefore binds the verdict only under three conditions the dispatcher must hold: the working tree
is clean at that SHA when the judge is dispatched, nothing is edited until the verdict returns, and
the verdict names the SHA it was given. A verdict returned against an edited tree is void and the
wave is re-judged. **[S8]**

Dispatch `dr-superpowers:judge-fable` (`dr-superpowers:judge-opus` when Fable is unavailable or the
human partner declined it — say the substitution aloud) with `references/distil-judge.md`. It
receives the wave's source paths and the commit SHA, read-only, and must work in this order
**[R23]**: first enumerate every fact in each source file as a numbered list, then map each
numbered fact to the distilled entry that carries it, then return a verdict per source file.

| Verdict | Meaning | Consequence |
|---|---|---|
| `CARRIED` | Every enumerated fact maps to a named distilled entry | Eligible for deletion |
| `MISSING` | An enumerated fact maps to nothing | Fix, re-commit, re-judge |
| `DISTORTED` | A fact was carried but its meaning changed | Fix, re-commit, re-judge |

Enumerate-then-map is required rather than a holistic reading, because a holistic judge grades the
summary it was given and cannot notice the fact that is absent from both the summary and its own
attention. Any edit after a verdict re-judges **every** file whose entries changed, not only the
file that prompted it. **[R21]**

### 6.5 Deletion, in two commits

```
docs(<scope>): distil <area> notes            # adds the distilled entries — no deletions
docs(<scope>): remove absorbed <area> notes   # git rm only — no content changes
```

One or more distil commits — §6.4's `MISSING` and `DISTORTED` verdicts each produce another — then
exactly one removal commit. **[S10]** Never combined, and **never squashed on integration** — a squash merge collapses the two commits
the recovery story depends on, so a distillation branch is merged with `--no-ff` or fast-forwarded,
never squashed. **[R24]** Reverting a deletion that turns out to be wrong is then one `git revert`
that keeps the distillation.

The second commit lands only for files the judge returned `CARRIED` against the first commit's
content.

### 6.6 Re-runs

The skill runs repeatedly over a project's life, so entries merge rather than accumulate. A new
fact that duplicates an existing entry updates it and adds its `Source:` line. A new fact that
**contradicts** an existing entry wins only when it is both newer and carries evidence; otherwise
both are reported to the human partner and neither is silently dropped. A distilled corpus that
contains two opposed facts is worse than one that contains neither. Every such merge happens during
a wave's extraction step, before that wave's commit and judge round (§6.4).

A wave that edits entries carried by an **earlier** wave is editing facts whose sources may already
be deleted, and its own judge sees only its own sources. So when a wave touches a pre-existing
entry, the dispatcher includes that entry's diff and a `git show` extract of the source named in its
`Source:` line, and the judge rules on the rewrite as well as on the new material. **[S9]** Without
it a fact can be rewritten out of the corpus with no seat having checked it.

### 6.7 Relationship to an external memory store

The distilled files are repo-scoped, committed, and readable with no MCP server present — they
survive a fresh clone, reach a Codex session, and travel with the branch. An external store such as
darkmem holds cross-repo facts for one human's agents. They are not substitutes, and a fact can
belong in both: when one is available, the skill offers to push newly distilled constraints and
gotchas there as well, and never does so silently.

### 6.8 Red flags

| Thought | Reality |
|---|---|
| "I read the whole notes directory, I can summarise it all" | Waves of five to fifteen. A summary written from a full context loses the specifics that made the note worth keeping. |
| "The judge will probably say CARRIED" | Dispatch it, against a commit. Deletion is gated on the verdict, not the expectation. |
| "This note is obviously superseded, I'll just delete it" | Three conditions, two commits, one judge. Nothing else deletes. |
| "It's only in `.reviews/`, deleting it is free" | It is untracked. Deleting it destroys it. It is not in the eligible set. |
| "One commit is tidier" | Two commits are what make the deletion revertible on its own. |
| "The spec says it, so I'll distil and delete the spec" | Specs and plans are sources, never targets. |

## 7. Changes to existing skills

### 7.1 `verification-before-completion` — unchanged **[R9]**

The obvious edit is to answer its "what command proves this claim?" with `running-gates`. It is not
made: all sixteen `agents/impl-*.md` preload this skill, so the pointer would reach every task
implementer and contradict §1's branch-level rule. Gates are reached through §7.2 and §7.4 instead.

### 7.2 `finishing-a-development-branch`

Two edits. **Step 1** currently says to run the project's full test suite: it becomes run
`dr-superpowers:running-gates` when `docs/superpowers/gates.md` exists, otherwise the full suite as
today. The failure path is unchanged — report and stop before the menu. `running-gates` computes its
own base (§5.3 step 2), so this works at Step 1 despite the base being established at Step 3.
**[R11]**

**Step 5 Option 1's merged-result verification** ("Verify tests on merged result") uses the manifest
too when one exists. Gates that passed on the branch say nothing about the merged tree. **[S22]**

**The completed-index write is bound to the outcome, not to Step 6.** Step 6 runs for Option 1 *and*
for a confirmed discard, and never for Options 2 and 3, so attaching the write to it would both miss
every PR and record discarded work as merged. The three cases and their line forms are in §4.4:
Option 1 writes its own commit on the base after Step 5 passes; Option 2 writes on the branch before
the push; Option 3 and discard write nothing. **[S2]** Deleting the only committed evidence that a
plan ran, without recording that it ran, is what makes `project-status` unable to tell a merged plan
from an untouched one. **[R2]**

### 7.3 Skills that load the distilled constraints **[R25]**

`distilled/constraints.md` outranks a spec (§3), so every skill that could act against one reads it
where it already reads project context, when it exists:

| Skill | Where | What it loads |
|---|---|---|
| `resume-execution` | Step 4, beside `handoff.md`; binds the same way but yields to `handoff.md` on conflict (§3) **[S13]** | constraints, gotchas |
| `subagent-driven-development` | Setup (`SKILL.md:184` area, where `handoff.md` is created) | constraints |
| `executing-plans` | Setup (`SKILL.md:105` area) | constraints |
| `brainstorming` | the explore-project-context step | constraints, rejected |

`reference.md` is never preloaded; it is consulted when the work reaches it. `rejected.md` loads
only in `brainstorming`, the one place where re-proposing a dead approach is the failure mode.
Loading four files where one is needed is the cost this plugin exists to avoid.

### 7.4 `reference/final-review.md` **[R10]**

A line in "The review": when the project declares a manifest, `dr-superpowers:running-gates` runs
before the reviewers are dispatched, and a red gate stops the review — reviewing a branch that does
not build wastes both reviewer seats. Without this, §1's claim that gates run before the final
review is carried by no file.

## 8. Routing

Three rows in `using-superpowers`' routing table:

| When | Skill |
|---|---|
| Where the work stands, what to do next | `dr-superpowers:project-status` |
| Before the final review or merge, when `gates.md` exists **[R26]** | `dr-superpowers:running-gates` |
| Session notes have accumulated | `dr-superpowers:distilling-docs` |

The gates row is worded by position in the workflow rather than by "proving a change works", which
would overlap the existing "Before claiming done → verification-before-completion" row. The Process
Depth and Session Budget sections are unchanged.

**Byte budget.** `tests/hook.test.sh:124` caps this file at 4,800 bytes because it rides in every
session's baseline and shares the hook's 10,000-character budget with the compaction snapshot. It
is 4,135 bytes today, so the three rows have about 665 bytes of headroom and fit. If a later edit
pushes it over, the routing table's three new rows are shortened to their skill names before any
existing row or principle is touched. **[S12]**

## 9. Tests

Three structural suites in the house pattern: the claims that make a prose skill work are checkable
without a model, so they are checked here rather than in a review.

- **`tests/project-status.test.sh`** — the skill names `scripts/repo-audit`; it does **not** name
  `scripts/next-step` or `scripts/sdd-workspace` **[R1]**; it routes to
  `dr-superpowers:resume-execution`; rules 0–7 of §4.3 appear in that order, with `BLOCKED` first
  and reading each task's last line **[S19]**; the five output sections appear in order;
  `completed.md` is named as the completion signal and as the precondition of rules 4 and 5
  **[S3]**; the plan discriminator is the task-heading test, and `**Execution:**` is **not** named
  as one **[S1]**; `reference/project-state.md` exists **[S26]**.
- **`tests/gates-manifest.test.sh`** — the skill documents both required fields and all seven
  optional ones **[R14]**; the four `Evidence` values appear with their proof rules and `output` is
  stated as the default **[R16]**; `references/gates-template.md` satisfies the documented format,
  checked by awk: contiguous numbering from 1 **[R12]**, `Command` and `Green` present under every
  gate heading, and every `Evidence` value one of the four in lower case. The line check enumerates
  the admitted classes rather than rejecting by exclusion **[S15]**: the H1, prose before the first
  gate heading, a `## <n>. <title>` heading, a blank line, a `Field:` line whose name is one of the
  nine, a two-space continuation, or any line inside a fenced block — anything else fails.
  `references/gates-template.md` exists **[S26]**.
- **`tests/distilling-docs.test.sh`** — the four distilled filenames; the three eligibility
  conditions including `git ls-files --error-unmatch` **[R19]** and the clean check **[R20]**; the
  `*.md`-only rule and the ancestor-directory reference check **[S7, S27]**; the never-eligible list
  including specs, plans and `docs/reverse-engineering`; both judge agent names; the
  `CARRIED`/`MISSING`/`DISTORTED` verdicts; enumerate-then-map **[R23]**; commit-before-judge with
  its three tree conditions **[R21, S8]**; one-or-more distil commits and exactly one removal commit
  **[S10]**; the no-squash rule **[R24]**; `references/distil-judge.md` exists **[S26]**.
- **Cross-skill assertions**, each named to a host suite, because no existing suite reads most of
  these files **[R27, S20]**: `inline-mode.test.sh` already reads `executing-plans`,
  `subagent-driven-development` and `final-review.md`, so their assertions go there — both execution
  skills name `distilled/constraints.md`, and `final-review.md` names `running-gates`.
  `hook.test.sh` already reads `using-superpowers` and enforces its byte cap, so the three routing
  rows are asserted there **[S12]**. The rest have no host and go into the three new suites:
  `project-status.test.sh` asserts `resume-execution` and `brainstorming` name
  `distilled/constraints.md`; `gates-manifest.test.sh` asserts `finishing-a-development-branch`
  names `running-gates` and `completed.md` and that `verification-before-completion` does **not**
  name `running-gates` **[R9]**.

Plus the existing repository validation: `node scripts/validate-repository.mjs`,
`claude plugin validate` on the marketplace and each Claude plugin, and the maintained suites.

## 10. Out of scope

- **No gate runner script.** §1 fixes this; a manifest defect is reported by the skill, not by a
  parser.
- **No import of `merge-local`.** `finishing-a-development-branch` keeps its option menu; a project
  that always answers "merge locally" states so in `CLAUDE.md`.
- **No multi-repo review fan-out.** `fable-review`'s one-reviewer-per-repo pattern stays in the
  modder repo; `reference/final-review.md` covers the single-repo case this plugin ships for.
- **No automatic distillation.** Nothing triggers `distilling-docs` on a schedule or a file count.
- **No migration of the modder repo.** Writing that project's `gates.md` and running the first
  distillation waves over its 51 notes is work for that repo, after this ships. Two rules from its
  `gate` skill are project policy with no home in this spec and must land there or be lost
  **[R30]**: that an unnamed script value or bit is never fixed by widening a table to swallow it
  (it belongs in that manifest's `Why` for the corpus gate, or in `distilled/constraints.md`), and
  that a suite needing a game or corpus path takes it through `run-app.ps1 -Env` (a `Setup` field,
  or `distilled/gotchas.md`).

## 11. Risks

- **A distillation that drops a fact.** Mitigated by §6.4's enumerate-then-map judge over committed
  content, §6.2's three conditions, §6.5's two commits and the `Source:` SHA on every entry. The
  residual risk is that the judge sees only the sources the session hands it, which the wave-size
  cap keeps honest.
- **A manifest that rots.** A `gates.md` whose commands no longer exist converts real checks into
  green lines. §5.3's rule that a non-launching gate is a reported manifest defect rather than a
  skipped step is the only automatic defence available without a parser.
- **`completed.md` is only as good as the skill that writes it.** A branch merged by hand, outside
  `finishing-a-development-branch`, leaves no line, and status will call that plan not started.
  Accepted: the failure is visible and one line fixes it, where the alternative — status silently
  recommending re-execution of merged work — is not.
- **Four more skills read `constraints.md`.** Each read costs context in every session in every
  repo that has the file. Accepted because §3's precedence is otherwise a claim no file honours,
  and mitigated by loading only the one or two files each skill can act on.
- **Three more skills in the routing table.** A permanent cost in every session's context, against
  three gaps currently filled by improvisation, with 665 bytes of headroom under the 4,800-byte cap
  (§8). **[S12]**
- **The judge cannot verify what it was told to verify.** `judge-fable` has no Bash, so
  commit-before-judge (§6.4) rests on the dispatcher holding the tree still rather than on the judge
  reading the commit. A dispatcher that edits mid-round voids the verdict silently unless it follows
  §6.4's three conditions. **[S8]**

**Adjacent defect, not fixed here.** `scripts/next-step` (via `ledger_blocked` in
`scripts/lib/plan.sh`) matches *any* `Task N: BLOCKED` line rather than a task's last line, so once
a task is blocked its own instruction — "record the ruling in the ledger, then run next-step again"
— can never clear it. §4.3 rule 0 avoids the bug rather than inheriting it. **[S19]** The fix
belongs to a `next-step` change, not to this sub-project.

## 12. Program design amendment

To be added under §6 of `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`:

> **Amendment 2026-09-14 (sub-project 6 spec).** The decomposition gains a sixth sub-project,
> "Project state", after inline mode. `docs/superpowers/` becomes project-declared state as well as
> an archive: `gates.md` declares the project's verification gates in order, `plans/completed.md`
> indexes merged plans (the workspace and its ledger are deleted on integration, so nothing
> committed otherwise records that a plan ran; the line is written on a local merge and on a PR,
> never on a keep or a discard), and `distilled/` holds four durable files
> (constraints, gotchas, reference, rejected) distilled from session notes, whose tracked sources
> are deleted once an independent judge confirms every enumerated fact was carried. Three skills
> use it — `project-status` reads, `running-gates` reads, `distilling-docs` reads and writes
> **[R28]** — and `brainstorming`, both execution skills and `resume-execution` load
> `distilled/constraints.md`, which binds like `handoff.md`'s owner constraints and yields to them
> on conflict.
> Gates are branch-level: they are reached from `finishing-a-development-branch` and
> `reference/final-review.md`, never from `verification-before-completion`, which every implementer
> agent preloads. Sources: the `status` and `gate` skills of `darkraise-modder`; its `handoff`,
> `resume`, `fable-review` and `merge-local` skills are not imported. Details:
> `docs/superpowers/specs/2026-09-14-dr-superpowers-project-state-design.md`.
