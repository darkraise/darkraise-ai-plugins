# Typed seats, fork limits and a plan-drafting seat

**Execution strategy:** parallel — Task 1's measurement runs alone and decides
which drafter is built; after it, the cockpit hook (`hooks/cockpit/`,
`tests/cockpit.test.ts`) and the skill, agent and script changes share no file.

**Register:** `docs/dforge/registers/2026-10-25-token-efficiency.md` rows 1, 7
and 9.

## Decisions

- **Scope.** Asked which rows one spec covers. Answer: "9, 7 and 1 together".
  Row 9's drafting exception needs row 1's seat, and row 7's spawn check needs
  to know which seat a fork may fill.
- **Enforcement.** Asked what the cockpit's spawn hook does with an untyped or
  fork dispatch in a dforge session. Answer: "Deny, naming the seat".
- **Measurement.** Asked how to choose between a fork drafter and a typed
  Sonnet drafter. Answer: "Throwaway clone, same spec".
- **Approach.** Offered skill text only (the do-less option), rules plus a
  spawn hook plus a drafter, or that plus a Workflow drafting loop. Answer:
  "Rules + spawn hook + drafter". The Workflow loop stays with row 8.
- **Spec review.** Answer: "Approve and run unattended"; finish: "Merge into
  main".

Finish: merge

## Problem

From the 2026-10-25 usage analysis (register rows 1, 7, 9):

- 930 agents ran untyped, as general-purpose or default agents that inherit
  the session's Opus, and used 9.2B tokens. dforge itself prescribes one:
  `skills/requesting-code-review/SKILL.md` dispatches a `general-purpose`
  reviewer with no model (6 runs on Opus at $4.98 each). That breaks the rule
  in `skills/subagent-driven-development/SKILL.md` §Seats that general-purpose
  seats always take an explicit model. Register-row verification has no
  prescription at all and ran as general-purpose Opus.
- Fork mode has been on by default since Claude Code 2.1.302. Of 123 fork runs,
  110 drafted plans and 13 did verification or consolidation, which belongs on
  typed seats.
- writing-plans says nothing about who drafts tasks, so drafting is improvised:
  380 agents, $3,609, $9.50 and 86 calls per run. Fork drafters cost about
  $1.65 per task, against about $2.07 for general-purpose drafters in the same
  sessions, because they reuse the parent's cache.

## Design

### 1. The seat rule (skill text)

`skills/using-dforge/SKILL.md` gains a short `## Seats` section, kept to about
four lines because the file is injected into every session:

- Every dispatch names a seat: a `dforge:` agent or a typed built-in such as
  `Explore`.
- A `general-purpose` dispatch, or one that names no type, takes an explicit
  `model`.
- No forks, except as the plan drafter when Task 1 picks forks.
- Read-only checks, such as verifying register rows against code,
  consolidating findings or checking a claim, go to `dforge:judge-sonnet-high`,
  or to `dforge:judge-opus` when the check needs judgment across several files.

`skills/requesting-code-review/SKILL.md` dispatches `dforge:judge-opus` as
`subagent_type` with no `model`. The session first writes the diff file itself:
the commit list, `git diff --stat` and `git diff -U10` for `BASE..HEAD`, saved
under the scratchpad or `<state>`. `scripts/review-package` needs a plan, so it
does not apply outside one.
`skills/requesting-code-review/references/code-reviewer.md` names the judge
seat, makes `[DIFF_FILE]` mandatory, and drops the git fallback and the
Read-Only Review section's git instructions. Judges have no shell, and
`reference/final-review.md` already sets those instructions aside; its note
about the template's general-purpose line goes with that line.

**Repository check.** A test fails when a dforge skill or reference prescribes
a general-purpose seat without a model. A prescription is a
`Subagent (general-purpose):` line, or a Seats table row whose Agent cell is
`general-purpose`. It passes only when a `model:` line in the same template
block, or a backticked model alias in the same table row, goes with it. Today's
passing cases are `skills/subagent-driven-development/references/re-review-prompt.md`
(its block's model line) and `reference/delegated-task.md` §Seats (its row's
`sonnet`).

### 2. The spawn check (cockpit hook)

The `agent.spawn` hook in `hooks/cockpit/register.tsx` runs a check before
`next(e)`. A pure function in `hooks/cockpit/lib.ts`,
`seatDenial(spawn, isPlanSession, forkDrafting)`, returns a deny reason or
`null`:

- It applies only when `isPlanSession` is true, the spawn is in the main loop
  (`parentAgentId` undefined), and it is not a workflow agent, a teammate or a
  resume. `isPlanSession` turns true only when a dforge skill runs or a dforge
  agent spawns. The using-dforge entry point that `scripts/session-start.sh`
  injects as context does not set it, so before any dforge skill runs nothing
  is denied. Tests mark a session dforge by running a skill or spawning a
  dforge agent, not by injecting the entry point.
- **Fork:** `fork` is true. It is allowed only when `forkDrafting` is true and
  `description` starts with `Draft plan tasks`. The prefix is a guard against
  mistakes, not enforcement: any fork with that description passes. Otherwise
  the reason is: forks are kept out of dforge sessions; use
  `dforge:judge-sonnet-high` for a read-only check and the drafting seat for
  plan drafting (using-dforge §Seats).
- **Untyped:** `subagentType` is `general-purpose` or `claude` (see Riskiest
  assumption), and `model` is undefined. The reason names the seats: a
  `dforge:judge-*` agent for a review or read-only check, a `dforge:impl-*`
  agent for implementation, and otherwise the same dispatch with
  `model: "sonnet"` (using-dforge §Seats).

`forkDrafting` is an exported constant in `hooks/cockpit/lib.ts`, set from
Task 1's result. Changing it later takes a plugin release, and hosts on older
versions keep the old rule; no setting is added for it.

A denied spawn returns `{ deny }` and never reaches the spawn list. The hook
does not retry it; the session reads the reason and re-dispatches. The denial
is also appended to the existing `refusals` list, with tool `Agent` and the
reason as its line, so the person sees in the cockpit why an auto run is
re-dispatching. A check that throws fails open: the hook's existing
`.catch(($, e, next) => next(e))` lets the spawn go ahead. That is intended,
because a broken guard must not stop every dispatch.

On a Codex host, and on hosts still on dforge 4.4.1, nothing enforces the rule:
the skill text alone carries it.

### 3. The drafting seat (writing-plans)

`skills/writing-plans/SKILL.md` gains `## Drafting the tasks`, placed after
Task index:

- A plan of 1-3 tasks is drafted in the session.
- For 4 or more tasks, the session writes the header, Global Constraints,
  Contracts, Assumptions, File Structure and Task index itself. It then splits
  the index into slices of 2-3 consecutive tasks and dispatches one drafter per
  slice, all slices at once.
- Contracts settle every interface the slices share. A drafter that finds a
  missing contract reports `NEEDS_CONTEXT`, and the session amends the header
  and re-dispatches that slice. An amendment that changes an existing Contract,
  rather than adding one, re-dispatches every slice, since slices drafted
  against the old Contract are stale and `--join` cannot tell.
- Each drafter follows `skills/writing-plans/references/drafter-prompt.md`: the
  slice range, the Task Structure and No Placeholders rules by reference, the
  slice path and a report contract (status and one line). It writes nothing in
  the checkout except its slice under `<state>`; any prototype runs in a
  scratch worktree of its own.
- Every slice is written to `<state>/drafts/<plan basename>/tasks-A-B.md`,
  under both drafters.
- `scripts/draft-pack --join PLAN_FILE` appends the slices in task order and
  deletes them, so the session never reads them. Its exit codes follow
  `scripts/task-brief`: 2 for bad usage, 3 when the slices do not cover every
  Task index task the plan does not yet hold, with no gap or overlap; the plan
  is left unchanged. With no task missing and no slice present, it exits 0 and
  changes nothing.
- The skill then continues at Assign an implementer as today.

What the dispatch carries depends on the drafter Task 1 picks:

- **Typed Sonnet drafter.** `agents/drafter-sonnet.md` runs Sonnet 5.5 at high
  effort, with exactly the tools Read, Grep, Glob, Bash, Write and Edit. It has
  no `Agent` tool, which is what keeps it from dispatching subagents. Its
  context pack is the dispatch prompt: the spec path, the plan path, the slice
  range and the slice path. At drafting time the plan file holds exactly the
  header and the Task index, so a separate pack file would copy what one Read
  gives. `agents/drafter-sonnet.md` is not built if forks win.
- **Fork drafter.** The fork already holds the spec and the header, so it gets
  only the template, the slice range and the slice path, under the description
  `Draft plan tasks A-B`.

`tests/fleet.test.sh` gains a drafter class beside impl, judge and scout:
`drafter-*` carries exactly `tools: Read, Grep, Glob, Bash, Write, Edit`,
`model: sonnet` and `effort: high`, with no `Agent`. The expected roster grows
from 20 to 21; `README.md` lists the agent.

On a Codex host the session drafts every task itself, as today.

### 4. The measurement (Task 1)

All of it runs in a throwaway clone of this repository under the scratchpad,
never in the real checkout.

- **Subject.** A copy of `docs/dforge/plans/2026-10-24-ui-ux-skill.md`, trimmed
  to its header and Task index rows 1-6, with no task bodies. Both runs start
  from that same file, and the three slices (1-2, 3-4, 5-6) cover it, so
  `--join` and `scripts/plan-lint` run on a complete plan.
- **Parent context.** Each nested parent session reads the ui-ux spec and the
  trimmed plan, then dispatches its three drafters, with nothing else in
  context first. That keeps the fork's inherited context equal across runs.
- **Runs.** The fork run uses fork drafters. The typed run uses a prototype
  `drafter-sonnet` agent placed in the clone's `.claude/agents/`. Both use the
  prototype `drafter-prompt.md` and `draft-pack --join`.
- **Nested sessions.** Each run is its own tmux session, launched through a
  script with `env -i HOME=/root PATH=<…, nvm node bin> CLAUDE_CONFIG_DIR=<an
  already logged-in alternate config dir> IS_SANDBOX=1`, and
  `claude --setting-sources project,local --settings <file> --plugin-dir
  <clone>/plugins/dforge`. Credentials are never copied between config
  directories. Only that tmux session is killed afterwards, and the user's
  `settings.json` `model` is checked unchanged.

For each run, record:

- dollars per drafted task, from the transcripts, deduplicated per message id,
  with uncached input, cache-read, cache-write and output tokens each priced at
  its own current list rate (Sonnet's looked up at run time). The fork's
  advantage is cache reuse, so pricing every input token at one rate would
  erase the effect under test;
- the `scripts/plan-lint` result on the joined plan;
- the Critical and Important counts from one `dforge:judge-opus` plan-review
  round, using the full-plan template.

**Decision rule:** the typed Sonnet drafter wins unless it costs more per task
than the fork, or its review finds a Critical finding the fork's does not, or
more than one Important finding beyond the fork's. A tie goes to the typed
drafter. The report goes to
`docs/dforge/notes/2026-10-25-drafter-measurement.md`; the plan is amended to
drop the losing branch's tasks.

## Parallel decomposition

Task 1, the measurement, runs alone first: it sets `forkDrafting` and decides
whether `agents/drafter-sonnet.md` is built. The other three parts then may run
together. Each file below has one owner, and none of the three consumes
another's output: the spawn check's deny text names seats and a skill section,
not files. Their tests share nothing at run time, since `cockpit.test.ts` runs
in its own fixture and the shell tests use their own temporary directories.

| Part | Files | Tests |
|---|---|---|
| Measurement | throwaway clone; `docs/dforge/notes/2026-10-25-drafter-measurement.md` | the report itself |
| Spawn check | `hooks/cockpit/lib.ts`, `hooks/cockpit/register.tsx` | `tests/cockpit.test.ts` |
| Seat rule and review seat | `skills/using-dforge/SKILL.md`, `skills/requesting-code-review/SKILL.md`, `.../references/code-reviewer.md`, `reference/final-review.md`, `tests/seats.test.sh` | `tests/seats.test.sh` (the repository check in §1) |
| Drafting seat | `skills/writing-plans/SKILL.md`, `.../references/drafter-prompt.md`, `scripts/draft-pack`, `agents/drafter-sonnet.md` (typed branch), `README.md`, `tests/fleet.test.sh` | a new `tests/draft-pack.test.sh`, `tests/fleet.test.sh` |

## Acceptance

A1. [test, high] In a dforge session, a main-loop spawn of `general-purpose` or `claude` with no `model` is denied, and the reason names a `dforge:judge-*` seat, a `dforge:impl-*` seat and the `model: "sonnet"` remedy.
A2. [test, neg, high] In a dforge session, a `general-purpose` spawn with an explicit `model`, any `dforge:` agent and a typed built-in such as `Explore` are not denied.
A3. [test, neg, high] No spawn is denied by the seat check before any dforge skill or agent has run, nor from a subagent's loop, a workflow agent, a teammate or a resume.
A4. [test, high] In a dforge session a fork spawn is denied; only when Task 1 picks fork drafters is a fork whose description starts `Draft plan tasks` allowed, and every other fork is still denied.
A5. [test, high] `requesting-code-review` and `code-reviewer.md` name `dforge:judge-opus` and require a diff file, and the repository check in §1 fails on a `Subagent (general-purpose):` block or Seats row that carries no model.
A6. [test, high] `using-dforge` carries the Seats rule: typed seats only, an explicit model on general-purpose, forks only for drafting when picked, and read-only checks such as register-row verification on a judge seat.
A7. [test, high] writing-plans drafts a plan of 4 or more tasks in slices of 2-3 consecutive tasks, one drafter per slice, all dispatched at once, and drafts a plan of 1-3 tasks in the session.
A8. [test, high] A denied spawn is appended to the cockpit's `refusals` list with tool `Agent` and the deny reason.
A9. [test, neg, high] `scripts/draft-pack --join PLAN_FILE` appends every slice in task order and deletes the slice files; when the slices leave a gap or overlap it exits 3 and leaves the plan byte-identical, and with nothing missing and no slice present it exits 0 and changes nothing.
A10. [test, high] When the typed drafter wins, `agents/drafter-sonnet.md` runs Sonnet 5.5 at high effort with exactly the tools Read, Grep, Glob, Bash, Write and Edit, and `tests/fleet.test.sh` enforces that class and a roster of 21.
A11. [demo, high] The measurement report gives, for both drafters on tasks 1-6 of the trimmed ui-ux plan, dollars per task with cache tokens priced at their own rates, the plan-lint result and the plan-review Critical and Important counts, records the `subagentType` an untyped dispatch in the nested session resolves to, and names the drafter the decision rule picks.
A12. [test, high] The decision rule picks the typed Sonnet drafter unless it costs more per task than the fork, or its review finds a Critical the fork's does not or more than one additional Important finding; otherwise, a tie included, the typed drafter.
A13. [test, neg, high] The measurement leaves the real repository untouched: no plan edit, no worktree and no shared state in it; everything runs in the throwaway clone.
A14. [test, high] On a Codex host, writing-plans has the session draft every task itself and dispatches no drafting seat.

## Riskiest assumption

That a typed Sonnet drafter given the spec and plan paths writes slices about
as good as a fork drafter's. The fork's advantage is the parent's full context:
the spec reading, the exploration and the decisions made while the header was
written. The typed drafter gets the header but not that exploration, so it may
re-explore (cost) or guess (quality). Evidence so far covers only fork against
general-purpose Opus drafters, $1.65 against $2.07 per task (register row 1).
Status: unverified — the plan's first task verifies it.

A smaller assumption the hook rests on: that a dispatch naming no type reaches
`agent.spawn` as `general-purpose` or `claude`. The SDK types
(`.claude-plugin/types/claude-code/index.d.ts`, `AgentSpawnInput.subagentType`)
call the field the resolved type and list `general-purpose`, `Explore`, plugin
agents and `fork`; they name no `claude` type. That `claude` is a catch-all is
inference from this host's Agent tool roster as of 2026-10-25, which describes
it as the default when no agent name is typed. The spawn check's tests pin both
names, and Task 1 records which type an untyped dispatch in the nested session
resolves to.

## Review rulings

- Fable, spec: §4 subject — the clone's plan copy is trimmed to the header and Task index rows 1-6, so `--join` and plan-lint can run.
- Fable, spec: §2 untyped deny reason — names concrete seats (`dforge:judge-*`, `dforge:impl-*`) and the `model: "sonnet"` remedy.
- Fable, spec: A5 repository check — grammar defined: a `Subagent (general-purpose):` block or Seats row passes only with a model in the same block or row.
- Fable, spec: §3 fleet test — drafter class with exact tools, `model: sonnet`, `effort: high`, no `Agent`, roster 21.
- Fable, spec: §3 NEEDS_CONTEXT — an amendment that changes an existing Contract re-dispatches every slice.
- Fable, spec: §3 checkout rule — "writes nothing in the checkout except its slice under `<state>`".
- Fable, spec: Riskiest assumption — the `claude` catch-all labelled inference, with where it was observed.
- Fable, spec: §4 nested runs — the launch steps are inlined, since the private memory note is not citable.
- Fable, spec: §4 pricing — cache-read and cache-write tokens priced at their own rates.
- Fable, spec: §2 failure — a throwing check fails open, by choice.
- Fable, spec: `draft-pack` exit codes — 2 usage, 3 coverage refusal, as `task-brief`.
- Fable, spec: `--join` with nothing missing and no slices — exit 0, no change.
- Fable, spec: A7 — kept, raised to high.
- Fable, spec: A10 — kept, raised to high.
- Fable, spec: A12 — reworded: a new Critical, or more than one additional Important finding, beats the cost advantage.
- Fable, spec (round 2): A8 — the fail-open clause dropped; it is the hook's existing `.catch` and needs no statement.
- Fable, spec (round 2): repository check — owned by the seat-rule part as `tests/seats.test.sh`.
- Fable, spec (round 2): A11 — the report also records the type an untyped dispatch resolves to.

## Critic findings

Folded into Fable's first review round.

- High — the measurement could not run as written, because the ui-ux plan's full Task index makes `--join` refuse and plan-lint error. Fixed: §4 trims the subject to tasks 1-6.
- Medium — `draft-pack --tasks` copied a file region the drafter can read itself. Fixed: dropped; the dispatch names the paths and `draft-pack` keeps only `--join`.
- Medium — a denial was invisible to the person. Fixed: denials go to the cockpit's `refusals` list (§2, A8).
- Medium — the fork measurement's parent context was unspecified. Fixed: both parents read the same two files, then dispatch (§4).
- Medium — `forkDrafting` is a build-time constant with no path back. Accepted; §2 says where it lives and that changing it takes a release.
- Nit — the `Draft plan tasks` prefix is the only thing that admits a fork. Fixed: §2 calls it a guard against mistakes, not enforcement.
- Nit — nothing enforces the rule before the first dforge skill runs, because the injected entry point does not set `isPlanSession`. Fixed: stated in §2.
