# dr-superpowers 1.7.0 — project state (sub-project 6 design)

Date: 2026-09-14. Program design:
`docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` (§6 listed five sub-projects;
this is a sixth, recorded as a dated amendment under that §6 — see §12).

Goal: make `docs/superpowers/` hold what a project knows about itself, not just the archive of
what it planned. Three skills read and write that state — one reports where the work stands, one
runs the verification gates the project declares, one collapses accumulated session notes into
four durable files and deletes what it has absorbed.

The source is `D:\Repositories\Personal\darkraise-modder\.claude\skills`, six project-local skills
written over that programme. Two of them (`handoff`, `resume`) are weaker versions of skills this
plugin already has and are not imported. One (`fable-review`) is superseded by
`reference/final-review.md`. One (`merge-local`) is project policy, not a skill. The remaining two
(`status`, `gate`) name real gaps, and the third skill here answers a request the modder programme
produced but never solved: 415 doc files, of which about 90 are session notes and gate reports that
no longer have a reader.

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
  committed. Rejected: `.superpowers/gates.md` — that directory is gitignored and `handoff` forbids
  committing it, so a manifest there could not travel with the repo; and a root `GATES.md`, which
  puts a top-level file in every adopting project.
- **Gates run at branch level, not per task.** `running-gates` is invoked before the final
  whole-branch review and by `finishing-a-development-branch`, never inside the per-task loop. A
  task's own tests stay its gate. Running a five-gate manifest per task on a twelve-task plan would
  cost more than the plan.
- **`distilling-docs` deletes the sources it absorbs** (owner answer), gated on an independent
  judge verdict, in a commit separate from the one that writes the distilled content. Rejected:
  archiving under `docs/superpowers/archive/`, which leaves the same files in the tree under a name
  that invites reading them; and additive-only, which is the status quo that produced 90 orphan
  notes.
- **Specs, plans and hand-written reference documents are never deletable.** They are the authority
  trail that ledgers, handoffs and `CLAUDE.md` depend on. §6.2 fixes the eligible set.
- **The distilled files are loaded on pick-up** (owner answer, option 2 of three).
  `resume-execution` reads `distilled/constraints.md` and `distilled/gotchas.md` in the same step
  that reads `handoff.md`, and they bind the same way. Rejected: on-demand only, which reproduces
  today's failure where a note exists and nothing reads it; and naming them in `using-superpowers`,
  which would put project documents in every session's always-on context, in every repo, including
  those that have none.
- **`project-status` adds no script.** It calls `scripts/repo-audit` and reads the docs tree
  itself. Rejected: teaching `repo-audit` to enumerate un-started plans — five skills depend on that
  script's output shape, and the new data serves one reader.
- **`project-status` never writes.** In particular it does not call `scripts/next-step`, which
  rewrites `latest.md`. Reporting where the work stands is not a handoff.
- **Version 1.7.0** on both manifests. Every change is additive; no existing plan, ledger or
  manifest format changes.

## 2. File layout

Paths relative to `plugins/dr-superpowers/`.

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
- `skills/verification-before-completion/SKILL.md` — a gates pointer (§7.1)
- `skills/finishing-a-development-branch/SKILL.md` — Step 1 prefers the manifest (§7.2)
- `README.md` — What you get, Tests, Reference
- `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` — 1.7.0

`scripts/validate-repository.mjs` discovers skills by directory and needs no edit; its
cross-reference check (line 102) requires that every `dr-superpowers:<name>` mentioned in a skill
resolves to a real skill directory, which the three new names do.

## 3. `docs/superpowers/` as project-declared state

The plugin already writes two kinds of file into a project: specs and plans (authored, permanent,
the record of intent) and `.superpowers/` runtime state (generated, gitignored, disposable). This
sub-project adds a third kind — small, committed, authored-or-distilled documents that tell a
session facts about the project it cannot derive from the code:

```
docs/superpowers/
  specs/                 authored, permanent, never deleted by a skill
  plans/                 authored, permanent, never deleted by a skill
  gates.md               what proves a change works here, in order      (§5)
  distilled/
    constraints.md       owner rulings, do-nots, fixed policy           (§6.1)
    gotchas.md           tooling and environment traps, symptom first
    reference.md         measured facts, formats, corpus numbers
    rejected.md          approaches tried and abandoned, and why
```

Every one of these is optional. A project with none of them loses nothing it has today: each skill
that reads one states what it does when the file is absent, and none of them is an error.

Precedence when two sources disagree: `CLAUDE.md` and a direct instruction from the human partner
outrank everything; then `handoff.md`'s owner constraints for the run in flight; then
`distilled/constraints.md`; then a spec; then a distilled `reference.md` fact. A skill that acts on
the losing side of that order has made an error, not a judgment call.

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
2. **Route out if execution is live.** If the audit shows a plan in flight whose ledger has
   incomplete tasks, say so, name the plan and the task reached, and route to
   `dr-superpowers:resume-execution` instead of continuing. Status orients a session with no
   obvious thread; it never duplicates the resume path.
3. **Find what the audit cannot see.** For each plan in `docs/superpowers/plans/`, ask
   `scripts/sdd-workspace PLAN_FILE` for its workspace and check for `progress.md`: a plan with no
   ledger has never started. For each spec in `docs/superpowers/specs/`, look for a plan whose slug
   matches: a spec with no plan is approved and unplanned. Both classes are invisible to
   `repo-audit`, which walks ledgers.
4. **Read the open constraints.** If `docs/superpowers/distilled/constraints.md` exists, take the
   entries whose scope covers the current work. These are the owner-only items — decisions and
   prohibitions still in force.
5. **Recall, if available.** When an indexed memory tool is present (for example darkmem
   `memory_search`), search the project name for milestones, newest first. When it is absent, skip
   the step silently; the skill's output does not depend on it.
6. **Report** in the shape below, then stop.

### 4.2 Output

Five sections, in this order, nothing else:

- **Repos** — the audit's branch, HEAD and worktree lines.
- **In flight** — one bullet per plan with a ledger, with tasks complete of total and the last
  ledger line.
- **Not started** — one bullet per un-started plan and unplanned spec, with the path.
- **Owner-only items** — decisions, approvals and prohibitions waiting on the human partner.
- **Next step** — exactly one, naming the skill or command that starts it.

Only unfinished plans appear, plus anything touched in the last seven days. A status report that
lists every plan the project ever had has told the reader nothing.

### 4.3 The recommendation is ordered, not chosen

Two sessions running status on the same repo must recommend the same step. The first matching rule
wins:

| # | Condition | Recommendation |
|---|---|---|
| 1 | A ledger has incomplete tasks | `dr-superpowers:resume-execution` (reached via step 2) |
| 2 | Every task complete, no final-review line in the ledger | the final review, via the plan's `**Execution:**` skill |
| 3 | Final review done, branch unmerged | `dr-superpowers:finishing-a-development-branch` |
| 4 | A spec approved with no plan | `dr-superpowers:writing-plans` |
| 5 | A plan with no ledger | `dr-superpowers:using-git-worktrees`, then the plan's execution skill |
| 6 | A dirty tree with no plan in flight | name the files and ask whether they are live work |
| 7 | None of the above | say the project is between programmes, and offer `dr-superpowers:brainstorming` |

When a rule matches in more than one worktree, report each and recommend the one whose branch has
the newest commit, saying why.

### 4.4 Red flags

| Thought | Reality |
|---|---|
| "I'll list every plan so nothing is missed" | A list of forty is a list of none. Unfinished, plus the last seven days. |
| "Three things look important" | Pick one by §4.3 and say which rule matched. |
| "I know roughly where this stands" | Every line comes from the audit or the docs tree. Nothing from memory. |
| "I should write the handoff while I'm here" | Status writes nothing. `latest.md` belongs to `handoff`. |

## 5. `running-gates`

**Description line:** `Use before claiming a change works, before the final review, or before
merging, when the project declares gates in docs/superpowers/gates.md — runs them in order and
stops at the first red.`

**Announce:** "I'm using the running-gates skill to run this project's declared gates."

### 5.1 The manifest format

`docs/superpowers/gates.md` is a document a human maintains, read by a model. It is not parsed by
any shipped script, so the format is a convention with required fields rather than a grammar.

- An H1, optionally followed by prose.
- Each gate is `## <n>. <title>`, where `<n>` is the run order, contiguous from 1.
- Under the heading, one `Field: value` line per field, in any order.
- Required: **`Command`** (what to run) and **`Green`** (what output or observation proves it
  passed).
- Optional: **`Applies`** (default `always`) — prose naming what a change must touch for the gate
  to be required; **`Evidence`** (default `exit`) — one of `exit`, `output`, `image`, `judgment`;
  **`Repo`** — a path, when the manifest orders gates across more than one checkout; **`Setup`**
  and **`Teardown`**; **`Known-flaky`** — the specific failure that is known noise; **`Why`** — the
  reason the gate exists, which is what stops a later session deleting it.
- A field whose value does not fit one line is written as an empty `Field:` line followed
  immediately by a fenced code block.

~~~markdown
# Gates

## 1. Build
Command: `pwsh -NoProfile -File scripts/build.ps1 -Repo both`
Green: 0 errors in both repos

## 4. Graph capture
Command: `pwsh -NoProfile -File scripts/capture-graph.ps1 begin.svr -Sheet`
Green: no card on card, no edge through a card, no edge crossing the whole graph
Evidence: image
Applies: changes touching the script canvas, NodeGraph, layout, routing or rendering

## 5. Script-schema corpus sweep
Setup:
```powershell
$env:DARKRAISE_SCRIPT_CORPUS = "D:/Games Modding/SRHD;D:/Repositories/Personal/SRHD-Mods-Collection"
```
Command: `pwsh -NoProfile -File scripts/test-framework.ps1 ScriptSchemaCorpus`
Green: `Passed!`
Teardown: `Remove-Item Env:DARKRAISE_SCRIPT_CORPUS`
Applies: changes touching ScriptSchema, ScriptValueTables, or any payload-mask or choice read
Why: run-regression never sets the corpus variable, so these suites otherwise sweep only the
  handful of in-repo fixtures and pass green over a real mapping error
~~~

`references/gates-template.md` carries this example and a blank skeleton.

### 5.2 Evidence types

The `Evidence` field is the load-bearing part of the format, and it exists because of a recorded
failure: in the modder programme an Owner payload mask carried the 2004 bit layout instead of
RScript 4.15f's, every `PiratePlanet` in the corpus read as "As player", and the suites were green
throughout, because nothing had looked at the output.

| Evidence | What proves it | What is not enough |
|---|---|---|
| `exit` | Exit code 0 from the command | Output that looks fine |
| `output` | The declared `Green` text in this run's output | A previous run, a partial match |
| `image` | Opening the artifact and writing one sentence describing what it shows | Any metric, including a metric that says zero defects |
| `judgment` | A stated verdict against `Green`, with the observation it rests on | "Looks right" |

An `image` gate is never passed off numbers. The numbers say where to look.

### 5.3 Steps

1. **Locate the manifest** at `<repo root>/docs/superpowers/gates.md`. Absent: say so, offer the
   bootstrap in §5.4, and fall back to the project's full test suite for this run. A missing
   manifest is not an error.
2. **Compute the change set** — `git diff --name-only <base>...HEAD` plus `git status --short` for
   uncommitted work — so conditional gates can be decided against evidence rather than recollection.
3. **Select the gates.** `Applies: always` runs. A conditional gate runs when the change set
   touches what it names. Every skipped conditional gate is reported with the reason it did not
   apply; a silent skip is indistinguishable from a forgotten one.
4. **Run in order, stop at the first red.** Later gates usually depend on earlier ones — a manifest
   whose `Repo` fields order a framework before its consumer encodes a build dependency — so the
   results after a red are not merely unknown, they are meaningless.
5. **Judge by `Evidence`**, per §5.2. For an `image` gate, open the artifact and write the sentence
   before recording a result.
6. **`Known-flaky`** never auto-passes. Re-run the gate once. If it fails again it is red. If it
   passes, record it as passed-on-retry and name the flake.
7. **Report** one row per gate: number, title, result, and the summary line the command printed —
   plus, for `image` gates, the sentence written after looking.

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
| "It failed, but it's just this machine" | Say it failed. Then say why it is noise, with the `Known-flaky` line that predicted it. |
| "The later gates will probably pass" | Stop at the first red. Results after a failed dependency mean nothing. |
| "This gate seems obsolete, I'll skip it" | Read its `Why`. If it is genuinely dead, propose deleting it from the manifest — do not silently skip. |
| "I'll run the gates for each task" | Gates are branch-level. Per-task verification is the task's own tests. |

## 6. `distilling-docs`

**Description line:** `Use when session notes, findings and gate reports have accumulated, or after
a programme completes — distils them into four durable files and deletes the sources it has
absorbed, gated on an independent verification.`

**Announce:** "I'm using the distilling-docs skill to distil <area> into the durable files."

### 6.1 The four files

`docs/superpowers/distilled/`, each file an H1, a one-line statement of what belongs in it, then
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
commit that touched that file, captured with `git log -1 --format=%h -- <path>` **before** the file
is deleted. That line is what makes deletion safe: the original is one `git show` away, forever.

**Size discipline.** A distilled file over 400 lines has become the wall it replaced. The next wave
begins by merging duplicate and obsolete entries in it; if it is still over, split it by area into
`distilled/<area>-<kind>.md` with an index in the original.

### 6.2 What may be deleted

Eligible: `docs/superpowers/notes/`, `docs/superpowers/findings/`, gate and measurement reports,
review reports under `.reviews/`, and archived handoffs under `.superpowers/handoff/` other than
`latest.md`.

**Never eligible**, whatever a judge says: specs, plans, `README`, `CLAUDE.md`, `AGENTS.md`,
licence files, hand-written reference documentation outside `docs/superpowers/` (in the modder
repo, `docs/reverse-engineering/` is primary research, not session detritus), and any non-prose
fixture or asset — the `.svr` files under `notes/fixtures/` are test data that a suite reads.

Specs and plans are read as sources for distillation and are never deleted by it.

### 6.3 Waves

Work in waves of five to fifteen source files covering one area, never the whole tree. A wave is
sized to fit one session with room for the judge round, and is the unit at which work can stop: git
is the ledger, so a fresh session sees which areas remain by reading the distilled files and the
log.

Per wave: inventory the sources, classify each (durable-fact carrier, superseded by code or tests,
or historical record with nothing durable in it), extract into the four files, then §6.4.

### 6.4 The verification gate

Before any deletion, dispatch `dr-superpowers:judge-fable` (`dr-superpowers:judge-opus` when Fable
is unavailable or the human partner declined it — say the substitution aloud) with
`references/distil-judge.md`: it receives the wave's source paths and the four distilled files as
they now stand, read-only, and returns one verdict per source file.

| Verdict | Meaning | Consequence |
|---|---|---|
| `CARRIED` | Every load-bearing fact appears in a named distilled entry | Eligible for deletion |
| `MISSING` | A fact named by the judge is in no entry | Fix the entry, re-judge that file only |
| `DISTORTED` | A fact was carried but its meaning changed | Fix, re-judge that file only |

Deletion proceeds only for files the judge returned `CARRIED`. The judge is a separate seat for the
same reason the final review has one: the context that wrote a summary is the worst available
grader of whether the summary is complete.

### 6.5 Deletion, in two commits

```
docs(<scope>): distil <area> notes        # adds the distilled entries — no deletions
docs(<scope>): remove absorbed <area> notes   # git rm only — no content changes
```

Never combined. Reverting a deletion that turns out to be wrong is then one `git revert` that keeps
the distillation.

### 6.6 Re-runs

The skill runs repeatedly over a project's life, so entries merge rather than accumulate. A new
fact that duplicates an existing entry updates it and adds its `Source:` line. A new fact that
**contradicts** an existing entry wins only when it is both newer and carries evidence; otherwise
both are reported to the human partner and neither is silently dropped. A distilled corpus that
contains two opposed facts is worse than one that contains neither.

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
| "The judge will probably say CARRIED" | Dispatch it. Deletion is gated on the verdict, not the expectation. |
| "This note is obviously superseded, I'll just delete it" | Nothing is deleted outside the two-commit flow, and nothing outside §6.2's eligible set. |
| "One commit is tidier" | Two commits are what make the deletion revertible on its own. |
| "The spec says it, so I'll distil and delete the spec" | Specs and plans are sources, never targets. |

## 7. Changes to existing skills

### 7.1 `verification-before-completion`

One addition under The Gate Function: when `docs/superpowers/gates.md` exists, step 1 ("what
command proves this claim?") is answered by `dr-superpowers:running-gates`, not by guessing. The
Iron Law is unchanged; the skill supplies the discipline, and the manifest supplies the commands.

### 7.2 `finishing-a-development-branch`

Step 1 currently says to run the project's full test suite, with examples. It becomes: run
`dr-superpowers:running-gates` when the project declares a manifest, otherwise the full test suite
as today. The failure path is unchanged — report and stop before the menu.

### 7.3 `resume-execution`

Step 4 already reloads `handoff.md`, the plan header and the ledger, and states that `handoff.md`'s
owner constraints bind as if the human partner had just said them. It gains
`docs/superpowers/distilled/constraints.md` and `distilled/gotchas.md`, when they exist, under the
same sentence and the same binding force. `reference.md` and `rejected.md` are not loaded on
resume: they are consulted when the work reaches them, and loading four files where two are needed
is the cost this plugin exists to avoid.

## 8. Routing

Three rows in `using-superpowers`' routing table:

| When | Skill |
|---|---|
| Where the work stands, what to do next | `dr-superpowers:project-status` |
| Proving a change works in this project | `dr-superpowers:running-gates` |
| Session notes have accumulated | `dr-superpowers:distilling-docs` |

The Process Depth and Session Budget sections are unchanged. The entry point grows by three lines,
which every session pays for; the alternative — a session that does not know these skills exist —
is what the routing table is for.

## 9. Tests

Three structural suites in the house pattern: the claims that make a prose skill work are checkable
without a model, so they are checked here rather than in a review.

- **`tests/project-status.test.sh`** — the skill names `scripts/repo-audit` and
  `scripts/sdd-workspace`; it does **not** name `scripts/next-step` (§1, writes nothing); it routes
  to `dr-superpowers:resume-execution`; its recommendation table's seven rules appear in the order
  §4.3 fixes; the five output sections appear in order.
- **`tests/gates-manifest.test.sh`** — the skill documents both required fields and all six
  optional ones; the four `Evidence` values appear with their proof rules; the example in
  `references/gates-template.md` satisfies the documented format (an awk check inside the test:
  contiguous numbering from 1, `Command` and `Green` present under every gate heading, every
  `Evidence` value one of the four).
- **`tests/distilling-docs.test.sh`** — the four distilled filenames; the never-eligible list
  including specs, plans and fixtures; both judge agent names; the `CARRIED`/`MISSING`/`DISTORTED`
  verdicts; the two-commit rule; the `Source:` provenance line.

Plus the existing repository validation: `node scripts/validate-repository.mjs`,
`claude plugin validate` on the marketplace and each Claude plugin, and the maintained suites.

## 10. Out of scope

- **No gate runner script.** §1 fixes this; a manifest defect is reported by the skill, not by a
  parser.
- **No import of `merge-local`.** `finishing-a-development-branch` keeps its option menu; a project
  that always answers "merge locally" states so in `CLAUDE.md`. Letting a project pin the
  integration decision is a separate change, not required by anything here.
- **No multi-repo review fan-out.** `fable-review`'s one-reviewer-per-repo pattern stays in the
  modder repo; `reference/final-review.md` covers the single-repo case this plugin ships for.
- **No automatic distillation.** Nothing triggers `distilling-docs` on a schedule or a file count.
  It runs when asked or when `project-status` observes the accumulation and recommends it.
- **No migration of the modder repo.** Writing that project's `gates.md` and running the first
  distillation waves over its 90 orphan notes is work for that repo, after this ships.

## 11. Risks

- **A distillation that drops a fact.** Mitigated by the judge seat (§6.4), the two-commit deletion
  (§6.5) and the `Source:` SHA on every entry (§6.1) — but the residual risk is real, because the
  judge reads the sources the session chose to give it. The wave size cap is what keeps that set
  honest.
- **A manifest that rots.** A `gates.md` whose commands no longer exist converts real checks into
  green lines. §5.3 makes a non-launching gate a reported manifest defect rather than a skipped
  step, which is the only automatic defence available without a parser.
- **Status recommending the wrong step.** §4.3's ordered rules make the recommendation
  reproducible and therefore arguable; a wrong recommendation is a wrong rule, which is fixable,
  rather than a wrong mood.
- **Three more skills in the routing table.** Each row is a permanent cost in every session's
  context. Accepted: the three name gaps that are currently filled by improvisation, which costs
  more.

## 12. Program design amendment

To be added under §6 of `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`:

> **Amendment 2026-09-14 (sub-project 6 spec).** The decomposition gains a sixth sub-project,
> "Project state", after inline mode. `docs/superpowers/` becomes project-declared state as well as
> an archive: `gates.md` declares the project's verification gates in order, and `distilled/`
> holds four durable files (constraints, gotchas, reference, rejected) distilled from session
> notes, whose sources are deleted once an independent judge confirms every load-bearing fact was
> carried. Three skills read and write it — `project-status`, `running-gates`, `distilling-docs` —
> and `resume-execution` loads the distilled constraints with the same binding force as
> `handoff.md`'s. Sources: the `status` and `gate` skills of `darkraise-modder`; its `handoff`,
> `resume`, `fable-review` and `merge-local` skills are not imported. Details:
> `docs/superpowers/specs/2026-09-14-dr-superpowers-project-state-design.md`.
