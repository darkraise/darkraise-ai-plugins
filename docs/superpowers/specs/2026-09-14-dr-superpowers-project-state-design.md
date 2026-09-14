# dr-superpowers 1.7.0 — project state (sub-project 6 design)

Date: 2026-09-14. Program design:
`docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` (§6 listed five sub-projects;
this is a sixth, recorded as a dated amendment under that §6 — see §12). Revised 2026-09-14 after
an independent Fable review returned REJECT with 30 findings; every one is resolved here, and the
changes they forced are marked **[R<n>]**.

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
  `reference/final-review.md` and from `finishing-a-development-branch`, and from nowhere else. In
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
  both execution skills' Setup and `resume-execution` all read it. **[R25]** Rejected: on-demand
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
  the repo). **[R1]** Rejected: teaching `repo-audit` to enumerate un-started plans — two skills,
  two library scripts and the snapshot hook depend on its output shape **[R6]**, and the new data
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
`distilled/constraints.md`; then a spec; then a distilled `reference.md` fact. A skill that acts on
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
3. **Classify each plan.** A file under `docs/superpowers/plans/` is a plan only if it carries an
   `**Execution:**` header line — the line `plan-lint` requires — which excludes notes filed
   beside plans, such as `2026-08-09-reply-back-spike-results.md`. **[R2, R3]** For each plan, in
   this order:
   - **In flight** — `<root>/.superpowers/sdd/<basename minus .md>/progress.md` exists with
     incomplete tasks. That path is computed directly, never by calling `scripts/sdd-workspace`.
     **[R1]**
   - **Complete** — listed in `docs/superpowers/plans/completed.md` (§4.4), or its ledger records
     every task complete. Reported only if merged within the last seven days.
   - **Not started** — neither of the above. A plan is called not started only when the committed
     index does not list it; "no ledger" alone never means "never ran", because
     `finishing-a-development-branch` deletes the workspace on merge. **[R2]**
4. **Match specs to plans.** The slug of a spec is its filename minus the leading `YYYY-MM-DD-`
   and the trailing `-design`; a plan matches if its filename minus its own date prefix equals that
   slug, or begins with it. Dates need not agree. A spec whose body contains a decomposition
   section listing sub-projects is a program design and is never reported as unplanned — its plans
   are the sub-projects'. **[R3]**
5. **Find unmerged work with no plan.** `git branch --no-merged <base>` and the audit's worktree
   list: a branch carrying commits that is not merged into its base is open work even when no plan
   names it. **[R29]**
6. **Read the open constraints.** If `docs/superpowers/distilled/constraints.md` exists, take the
   entries whose scope covers the current work — the owner-only items still in force.
7. **Recall, if available.** When an indexed memory tool is present (for example darkmem
   `memory_search`), search the project name for milestones, newest first. When it is absent, skip
   the step silently; the output does not depend on it.
8. **Report** in the shape below, then stop.

### 4.2 Output

Five sections, in this order, nothing else:

- **Repos** — the audit's branch, HEAD and worktree lines.
- **In flight** — one bullet per plan with an active ledger, with tasks complete of total and the
  last ledger line; plus each unmerged branch from step 5.
- **Not started** — one bullet per un-started plan and unplanned spec, with the path.
- **Owner-only items** — decisions, approvals and prohibitions waiting on the human partner,
  including every `BLOCKED` ledger line (§4.3 rule 0).
- **Next step** — exactly one, naming the skill or command that starts it.

Unfinished work always appears; finished work appears only when touched in the last seven days,
where touched means `git log -1 --format=%cs -- <path>` is within seven days of today. **[R5]** A
status report that lists every plan the project ever had has told the reader nothing.

### 4.3 The recommendation is ordered, not chosen

Two sessions running status on the same repo must recommend the same step. The first matching rule
wins, and the report names the rule that matched:

| # | Condition | Recommendation |
|---|---|---|
| 0 | A ledger has a `Task N: BLOCKED` line | No skill. The decision the line names goes under Owner-only items **[R4]** |
| 1 | A ledger has incomplete tasks and no `BLOCKED` line | `dr-superpowers:resume-execution` (reached at step 2) |
| 2 | Every task complete, no `Final review: clean` line in the ledger | the final review, via the plan's `**Execution:**` skill |
| 3 | Final review clean, branch unmerged — `git merge-base --is-ancestor <branch> <base>` exits non-zero **[R5]** | `dr-superpowers:finishing-a-development-branch` |
| 4 | A spec approved with no plan (§4.1 step 4) | `dr-superpowers:writing-plans` |
| 5 | A plan absent from `completed.md` with no ledger | `dr-superpowers:using-git-worktrees`, then the plan's execution skill |
| 6 | A dirty tree with no plan in flight | name the files and ask whether they are live work |
| 7 | None of the above | say the project is between programmes, and offer `dr-superpowers:brainstorming` |

`BLOCKED` outranks everything because `scripts/next-step` already treats it as terminal — it sets
`launch=0` and hands the decision to the human partner — and status must not contradict the script
the rest of the plugin uses. **[R4]** When a rule matches in more than one worktree, report each
and recommend the one whose branch has the newest commit, saying why.

### 4.4 `docs/superpowers/plans/completed.md`

Append-only, one line per merged plan, written by `finishing-a-development-branch` (§7.2):

```markdown
- 2026-09-12 `docs/superpowers/plans/2026-09-12-dr-superpowers-inline-mode.md` — merged into `main` at 6a4619a
```

It exists because a merged plan leaves no committed trace that it ran: the ledger is deleted with
the workspace, and the branch is deleted with it. A project that adopts the plugin mid-programme
has no index, so status treats an absent `completed.md` as "no plans are known complete" and says
so in the Not started section rather than claiming twenty-five plans were never started. **[R2]**

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
- **Value form** **[R17]**: backticks delimit a value and are not part of it, so
  ``Green: `Passed!` `` matches the text `Passed!`.
- **Continuation** **[R13]**: a value may continue on following lines indented by two spaces, or —
  when it contains its own newlines, such as a shell snippet — be given as an empty `Field:` line
  followed immediately by a fenced code block. Those two forms are the only ones.
- **`Repo`** **[R15]**: a path relative to the manifest's repository root. The gate's `Command`,
  `Setup` and `Teardown` run with that repository as the working directory; step 2 computes a
  change set in every distinct `Repo` named by the manifest, and a conditional gate applies when
  the change set of *its own* `Repo` matches. Omitted means the manifest's own repository. This is
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

An `image` gate is never passed off numbers. The numbers say where to look.

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

Eligible **by path**: `docs/superpowers/notes/**` and `docs/superpowers/findings/**`. **[R22]**

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
3. **Unreferenced** — `grep` for the file's path and its basename across the repository outside
   `docs/superpowers/notes/` and `findings/` returns nothing. **[R22]** A note read by a test, a
   script or a spec is a dependency, not detritus, whatever its extension.

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

Never combined, and **never squashed on integration** — a squash merge collapses the two commits
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

**Step 6**, which deletes the plan's workspace on a local merge or PR, first appends the plan's line
to `docs/superpowers/plans/completed.md` (§4.4) and includes that file in the merge commit or the
branch. Deleting the only committed evidence that a plan ran, without recording that it ran, is what
makes `project-status` unable to tell a merged plan from an untouched one. **[R2]**

### 7.3 Skills that load the distilled constraints **[R25]**

`distilled/constraints.md` outranks a spec (§3), so every skill that could act against one reads it
where it already reads project context, when it exists:

| Skill | Where | What it loads |
|---|---|---|
| `resume-execution` | Step 4, beside `handoff.md`, with the same binding force | constraints, gotchas |
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

## 9. Tests

Three structural suites in the house pattern: the claims that make a prose skill work are checkable
without a model, so they are checked here rather than in a review.

- **`tests/project-status.test.sh`** — the skill names `scripts/repo-audit`; it does **not** name
  `scripts/next-step` or `scripts/sdd-workspace` **[R1]**; it routes to
  `dr-superpowers:resume-execution`; rules 0–7 of §4.3 appear in that order, with `BLOCKED` first;
  the five output sections appear in order; `completed.md` is named as the completion signal.
- **`tests/gates-manifest.test.sh`** — the skill documents both required fields and all seven
  optional ones **[R14]**; the four `Evidence` values appear with their proof rules and `output` is
  stated as the default **[R16]**; `references/gates-template.md` satisfies the documented format,
  checked by awk: contiguous numbering from 1 **[R12]**, `Command` and `Green` present under every
  gate heading, every `Evidence` value one of the four, every non-field line either a two-space
  continuation or inside a fenced block **[R13]**.
- **`tests/distilling-docs.test.sh`** — the four distilled filenames; the three eligibility
  conditions including `git ls-files --error-unmatch` **[R19]** and the clean check **[R20]**; the
  never-eligible list including specs, plans and `docs/reverse-engineering`; both judge agent names;
  the `CARRIED`/`MISSING`/`DISTORTED` verdicts; enumerate-then-map **[R23]**; commit-before-judge
  **[R21]**; the two-commit and no-squash rules **[R24]**.
- **Cross-skill assertions** added to the existing suites rather than a fourth file **[R27]**:
  `resume-execution`, both execution skills and `brainstorming` name
  `docs/superpowers/distilled/constraints.md`; `finishing-a-development-branch` names
  `running-gates` and `completed.md`; `final-review.md` names `running-gates`;
  `verification-before-completion` does **not** name it; `using-superpowers` carries the three
  routing rows.

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
  three gaps currently filled by improvisation.

## 12. Program design amendment

To be added under §6 of `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`:

> **Amendment 2026-09-14 (sub-project 6 spec).** The decomposition gains a sixth sub-project,
> "Project state", after inline mode. `docs/superpowers/` becomes project-declared state as well as
> an archive: `gates.md` declares the project's verification gates in order, `plans/completed.md`
> indexes merged plans (the workspace and its ledger are deleted on integration, so nothing
> committed otherwise records that a plan ran), and `distilled/` holds four durable files
> (constraints, gotchas, reference, rejected) distilled from session notes, whose tracked sources
> are deleted once an independent judge confirms every enumerated fact was carried. Three skills
> use it — `project-status` reads, `running-gates` reads, `distilling-docs` reads and writes
> **[R28]** — and `brainstorming`, both execution skills and `resume-execution` load
> `distilled/constraints.md` with the same binding force as `handoff.md`'s owner constraints.
> Gates are branch-level: they are reached from `finishing-a-development-branch` and
> `reference/final-review.md`, never from `verification-before-completion`, which every implementer
> agent preloads. Sources: the `status` and `gate` skills of `darkraise-modder`; its `handoff`,
> `resume`, `fable-review` and `merge-local` skills are not imported. Details:
> `docs/superpowers/specs/2026-09-14-dr-superpowers-project-state-design.md`.
