# dflow — design

Status: implemented on 2026-11-12 as `plugins/dflow/`. This is the design record; the
user guide is `plugins/dflow/README.md`. Where the build departed from the
proposal, this text describes what was built.

dflow is a Claude Code workflow plugin for planning, building, reviewing and
shipping changes. It is independent of dforge: no shared scripts, skills,
agents or state, and its own directories (`docs/dflow/`, `.dflow/`). Claude
Code only.

## 1. Goals and how each is met

| Goal | Mechanism | How it is checked |
|---|---|---|
| Low token use | Bookkeeping in one CLI, hooks and a mod; one document per unit of work; lean plans; one review per branch; context reset at task boundaries | `dflow cost` per plan; the same eval cases run through dflow and dforge |
| High output quality | Test-first tasks, a verify command that gates every task, project gates at ship, an independent evidence-bound review, UI proof in the running app | Eval pass rate; findings that reproduce |
| Maintainable docs | Four living files with size budgets, updated by the change that invalidates them; a mechanical staleness check | `dflow doctor` in ship and CI |
| Trackable plan | Checkboxes committed with each task, a board table, the darkmem board, a HUD | `/dflow:status`, `/dflow:hud`, the darkmem board |
| darkmem integration | One-way projection of docs, board and progress under dflow's own URI prefix; section search for reads | Works with darkmem off; sync tests against a stub |
| Frontier models and harness | Per-spawn model and effort, worktree isolation, typed agent output, a workflow script, a mod | Verified against Claude Code 2.1.322 |

## 2. Principles

Drawn from a speed-and-cost study of 56 measured sessions (2026-10-27).

1. **The session does the work.** Tightly coupled work stays in one agent
   loop. Delegation is for parallel independent work, an independent review,
   or reading far more than the session needs afterwards.
2. **Scripts keep the books.** Ticking a task, moving a board row, pushing to
   darkmem and writing a checkpoint cost no model tokens.
3. **Mechanical facts never reach a reviewer.** Whether a test exists, passes
   at the base commit, or a file is outside the plan is computed by the CLI.
4. **Review once, sized to the diff.**
5. **One document per unit of work.** The design is the head of the plan.
6. **Small prompts.** Every skill stays under 6 KB, enforced by a test, so it
   survives compaction whole (the harness keeps 5,000 tokens per skill).
7. **Every rule is measured.** A rule that does not move eval pass rate or
   cost is removed.

## 3. Footprint

| Component | Count | Contents |
|---|---|---|
| Skills | 7 | `plan`, `build`, `review`, `ship`, `status`, `init`, `hud` |
| Agents | 2 | `worker`, `reviewer`; model and effort are set per spawn |
| Hooks | 3 | SessionStart (status line), PreCompact (summary instructions), Stop (async darkmem flush) |
| Mod | 1 | the HUD and the context governor (sections 13 and 14) |
| CLI | 1 | `dflow` in the plugin's `bin/`, dependency-free Node |
| Workflow script | 1 | `workflows/deep-review.js` |

Nothing is injected at session start unless a plan is active on the current
branch; then the hook adds at most three lines (plan, progress, next task).
The `build` and `status` skills embed `dflow status` output through command
injection, so they load with the current state. Reference text that only
some plans need (the UI contract) sits in a file its skill names, loaded on
demand.

Native task tools are not used: they are off by default on the 5.5 models,
and the plan file is the tracker. Node 20 or later on `PATH` is required;
`init` checks it.

## 4. Documents

```
docs/dflow/
  project.md     what the system is, module map, how to run and verify it
  decisions.md   append-only: decision, reason, what it supersedes; owner
                 rulings and rejected approaches included
  gotchas.md     tooling and environment traps, symptom first
  board.md       the backlog table
  config.json    gates, run command, darkmem project, budgets, thresholds
  plans/         one file per unit of work; immutable after merge
.dflow/          gitignored: state, sync hashes, proofs, findings, logs
```

Maintenance rules, all checked by `dflow doctor` without a model:

- **Budgets.** `project.md` at most 150 lines, `gotchas.md` at most 100.
- **Dead references.** Every repository path named in `project.md` or
  `gotchas.md` must exist. `decisions.md` is history and may name files that
  are gone.
- **Docs delta.** A plan's `Docs:` line names the living docs the change
  invalidates, or `none` with a reason. `ship` refuses when a named doc has
  no diff on the branch.
- **Promotion at ship.** Plan log lines marked `D:` are copied to
  `decisions.md` as `D-<plan>/<n>`, numbered within the plan, `G:` lines to
  `gotchas.md`. Both files merge by union (`.gitattributes`, written by
  `init`), so plans shipped from parallel branches merge without a conflict.
  There is no distillation pass.
- **Narrow reads.** `plan` reads `project.md` whole and searches decisions
  and past plans by section. Merged plans are never loaded by default.

## 5. Plan, tracking and the board

```markdown
# Rate-limit meter in the status line
**Board:** 12 · **Branch:** feat/rate-meter
**Goal:** one sentence.
**Acceptance:**
- A1: `npm test -- meter` passes with the header present and absent
- A2 UI: the meter turns red below 10% remaining
**Docs:** project.md, decisions.md
**Risk:** none | security | data-loss | migration | concurrency

## Design
- D1: the decision — the reason
- Interfaces: exact signatures and data shapes
- Out of scope: …

## Tasks
### Task 1: Parse the limit header
**Files:** src/limit.ts, tests/limit.test.ts · **After:** — · **Run:** inline · **Size:** S
- [ ] Test: `x-ratelimit-remaining: 5` parses to `{ remaining: 5 }`; no header gives null
- [ ] Implement `parseLimit(headers): Limit | null`
- [ ] Verify: `npm test -- limit.test.ts`

## Log
- 2026-11-12 T1 D: chose a parser function over a class — one call site
```

A plan states decisions, signatures and test assertions, not code.

**Task states** are `todo`, `wip`, `review`, `blocked`, `done`. `dflow next`
marks a task `wip`; `dflow done` marks it `done`; `dflow block` marks it
`blocked` with a reason; `review` is a task with a risk flag waiting for its
mid-plan check. Each transition is recorded in four places by the CLI: the
plan's checkboxes (committed), the task's commit, `.dflow/state.json` (for
the HUD and hooks), and a darkmem work-log entry. `dflow status` flags a tick
that no `dflow done` recorded. Files outside the task's `Files:` are refused
by `dflow done` itself, before the commit.

`dflow done 1 -m "feat(status): parse limit header"` runs the task's verify
command with a timeout. On success it ticks the boxes, commits the staged
code together with the plan, records the transition and prints the next
task's brief. On failure it prints the failing tail and changes nothing.

`board.md` is one table: `# | Item | Assigned | Acceptance | State | Note`,
states `open planned doing verify done deferred n/a`. The CLI moves a row to
`planned` when its plan is written, `doing` at the first finished task,
`verify` when all tasks are done and `done` at ship. A plan branch changes
only its own row, so parallel branches merge without conflict.

## 6. Definition of done

**A task is done** when all of these hold, checked by `dflow done`:

1. Its verify command exits 0 in this run, executed by the CLI.
2. The change is committed, and files outside the task's `Files:` are
   either absent from the commit or explained by a log line.
3. No test that existed at the base commit was deleted, skipped or had
   assertions removed, unless a log line says why.
4. A verify line edited after plan approval carries a logged reason, and so
   does a change to the task's `Files:`; both are listed in the review pack.

**A plan is done** when all of these hold, checked by `dflow ship`:

1. Every task is `done`. A task the owner drops is taken out of the plan
   with a logged amendment; the CLI has no deferred state.
2. The project gates (lint, type check, full test suite, build) pass on the
   current head, run fresh.
3. Every Acceptance line has evidence at the current head: a passing
   command, or for a `UI` line a proof (section 10). A line changed, added or
   removed after approval needs a plan-level `A:` log line recording that the
   owner agreed, naming the line and each command it now runs.
4. The review ran at its tier, and no blocking finding is open.
5. The docs delta is satisfied and `dflow doctor` passes.

**A board item is done** when its plan is done and merged, or its pull
request is open, whichever the owner chose; the row's note names the commit.

## 7. The loop

**Depth is chosen first, in one line.** A change that touches a couple of
files with no open decision gets no plan: implement test-first, run verify,
commit. Everything else gets a plan. A plan with a risk, a public interface
change or an open approach question also gets one critique by the reviewer
before approval.

1. `/dflow:plan` — search darkmem and the code, ask the owner at most one
   batch of questions for decisions that are theirs, write the plan, link the
   board row, get one approval of the whole document.
2. `/dflow:build` — loop: `dflow next`, implement test-first, `dflow done`.
   Decisions made on the way are ruled and logged in the plan, not asked.
3. `/dflow:review` — `dflow review-pack` computes the tier and the
   mechanical facts. The session then reports the review and stops; the
   owner starts ship. `autoShip` in `config.json` lets it continue.
4. `/dflow:ship` — gates, UI proof check, `doctor`, docs delta, promotion,
   board row to `done`, one `memory_batch_add` of durable facts, then the
   offer to open a pull request or merge. Pushing asks first.

A plan of more than three tasks is built in a fresh session: the build does
not carry the planning context on every turn, and this is the one place a
cheaper model can take over without discarding a warm cache.

**Review tiers**

| Tier | When | What runs |
|---|---|---|
| 0 | about 40 changed lines or fewer, risk `none` | the session checks the diff against Acceptance; no agent |
| 1 | default | one `reviewer`, fresh context, diff first |
| 2 | a risk is set, or a very large diff | the workflow script: two lens reviewers in parallel, then one verifier over all findings |

Every finding carries a file, a line, a claim, what it breaks, and evidence:
a failing command or a quoted line. A reviewer wrote the commands, so the CLI
never runs them: the session runs each with its own shell tool, under the
owner's permission settings, and records the exit status with `dflow review
check`. All findings are reported. Only findings whose evidence reproduces
are fixed, in the session, followed by verify and
gates; a fix to a blocking finding is re-checked once by the same reviewer
against the fix diff only.

## 8. When a task fails

- **Verify fails.** Nothing is ticked or committed. The session reads the
  failing output, states the cause, and fixes the cause.
- **Third failure on one task.** `dflow done` stops accepting patches and
  prints a required choice: the implementation is wrong (continue), the test
  is wrong (amend the verify line with a logged reason), or the plan is wrong
  (amend the plan).
- **Plan amendment.** A change to a task's steps or files is ruled by the
  session and logged. A change to Goal, Acceptance or a Design decision
  stops and asks the owner.
- **Hard blocker.** `dflow block 4 "reason"` records the state and reason.
  The session continues with tasks that do not depend on the blocked one and
  reports the blocked tasks at the end. The plan cannot ship while a task is
  blocked.
- **A worker fails.** It receives the failing output once in the same
  conversation. A second failure returns the task to the session, which
  does it inline. There is no escalation ladder.
- **Never.** Skipping verify, weakening a test to pass, or marking done by
  hand. The CLI is the only writer of task state.

## 9. Tests: what gets written

Tests are part of the plan, so their volume is decided at approval, not
during the build.

1. Each task lists its test assertions. The implementer writes those; an
   extra test needs a log line.
2. One test per behaviour. A behaviour is an Acceptance line, a design
   decision with an observable effect, or a bug being fixed.
3. No test for wording, constants, configuration, private helpers already
   covered through a public path, or framework behaviour. No assertion on
   prose unless a program parses that text.
4. The lowest level that fails for the right reason; at most one
   end-to-end check per Acceptance line; a new case in an existing table
   before a new file.
5. A task that changes no behaviour adds no test and verifies with the
   existing ones.
6. A task's verify runs only its own tests. The full suite runs once, at
   ship.

The review pack reports test lines against source lines added, new test
files, and suite duration at the base and at the head. Past the configured
ratio (default: test lines more than twice source lines, or suite time up
20%) it becomes a finding the session answers by trimming or justifying.

Expected volume: one to three test cases per behaviour-changing task.

## 10. UI proof

A plan with a `UI` Acceptance line gets a `## UI` section, written from a
template the `plan` skill loads only then: the states each screen handles
(empty, loading, error, success, long content), input and keyboard
behaviour, widths, and the design source.

Before ship the session starts the app with the configured run command as a
tracked process, drives each `UI` line, asserts through the page's text
snapshot, saves a screenshot under `.dflow/proof/<plan>/`, and records it
with `dflow proof A2 --shot <file>`, which stamps the commit. The process is
stopped afterwards. The session reads a screenshot only for a line marked
`visual`; other lines are proven on text, which keeps images out of the
context.

`ship` refuses when a `UI` line has no proof, or when its proof is older
than the last commit that touched the plan's UI files. The reviewer of a UI
plan receives the proof manifest.

## 11. Models and effort

| Work | Runs on | Model and effort |
|---|---|---|
| Planning, design decisions | the session | the strongest model in use (Fable 5.2 or Opus 5.5) |
| Building coupled tasks | the session | Opus 5.5 medium or Sonnet 5.5 high in a fresh session |
| Read-heavy exploration | darkmem `code_search`, else built-in `Explore` | — |
| Independent tasks, two or more at once | `worker` in a worktree | Sonnet 5.5; effort low, medium or high by task size |
| Branch review, plan critique | `reviewer` | Opus 5.5 medium; high when a risk is set |
| Verifier in the deep review | workflow agent | Sonnet 5.5 high |

Cache rules the routing follows: the session keeps one model for a whole
phase, because a model switch discards the cache; effort may change freely,
because on the 5.5 models it does not.

## 12. Parallel work

**Tasks inside one plan run as subagents.** A wave starts only when two or
more ready tasks have disjoint `Files:`. Each `worker` runs in a worktree
and commits there; the session stages those commits on the plan branch and
runs `dflow done`, so a worker task ends in the same single commit as an
inline one. A worker's prompt is one line naming a brief file the CLI wrote
(the plan's goal and design, the task, the rules), so dispatching a worker
costs the session a line, not a copy of the task. This fits subagents because
the tasks are short, the session needs each result to continue, and the
result comes back summarised.

The CLI creates each worker's worktree from the current head. The harness's
own worktree isolation starts from the remote default branch unless the
user setting `worktree.baseRef` is `head`, so a worker would miss the plan's
earlier commits.

**Plans run as separate background sessions.** Each plan gets its own
session (`claude --bg`), worktree and branch. A plan build is long, and a
full session has what a subagent lacks: the one-hour prompt cache instead of
five minutes, its own context governor and HUD, survival after the starting
terminal closes, and an owner who can attach and steer. Sessions coordinate
through the board, not through a parent's context, so no session carries
another plan's output. `dflow plans --conflicts` refuses to start two plans
whose `Files:` overlap.

A background session that hits a permission prompt waits until the owner
attaches, so parallel plans need a permission mode chosen for unattended
work; `dflow` reports sessions that are waiting.

Agent teams are not used: they are experimental, their teammates get the
five-minute cache, and the documented cost is about seven times a standard
session when teammates plan.

Parallel work buys wall-clock time, not tokens: a subagent does not read
the session's cache, so one delegated task costs more than doing it inline.

## 13. Context growth

Every tool call re-reads the whole context at the cache-read price, so the
average context size over a build is the main cost lever. The 5.5 models and
Fable 5.2 run with a one-million-token window and compact on their own only
at about 967,000 tokens, so without a rule a long build keeps growing.
Three layers:

1. **Keep it from growing.** CLI output is capped at about 30 lines; verify
   and gate output is cut to the failures, with the full log on disk; the
   session works from the task brief, not the whole plan; reading goes
   through section search or `Explore`; reviewers return typed findings; UI
   is proven on text.
2. **Reset at a task boundary.** Right after `dflow done` everything that
   matters is on disk. When the context is above the configured threshold,
   `dflow done` prints a reset line and the session ends its turn. The mod
   then compacts with instructions to keep only the plan path, the next task
   and unlogged notes, and submits `/dflow:build` to continue. The
   SessionStart hook re-injects the task brief.
3. **Fallback without the mod.** `init` suggests a lower automatic
   compaction window (`/autocompact 300k`). When compaction happens,
   the PreCompact hook supplies the same summary instructions and the
   SessionStart hook re-injects the brief, so the build continues from the
   plan and `git log`. Hooks receive no context size, so here the CLI reads
   it from the transcript.

The threshold starts at 150,000 tokens and is tuned by the evals. There is
no handoff document and no resume procedure.

## 14. HUD

One mod draws two forms from `.dflow/hud.json`, with no model tokens, and only
in a checkout whose git root holds `.dflow`. The band, above the prompt, in the
account's color:

```
╭─ you@example.com · subscription · Remote ● connected ───────────────────── Expand ─╮
│ ~/code/shop ⎇ feat/rate-meter* ↑2 ~1 ?1 · Opus 5.5 · xhigh · dflow 4/7 · Task 5 · ● 2 workers │
│ ctx ▰▰▰▰▱▱▱┃▱▱ 79% · 5h ▰▰▱▱┊▱▱▱ 23% on pace · 3h40m · 7d 61% · $1.20              │
╰──────────────────────────────────────────────────────────────────────────────────╯
```

A third line in red names a blocked task, failed gates or a darkmem conflict
or refusal. Each line shrinks a step at a time to fit; below 48 columns the
frame goes.

The pane, top to bottom:

```
● Task 5 in progress · verify failed 1×
╭ ▾ Account ─────────────────────── subscription ╮
 ≡ Dense   ⚙ Sections   ▁ Minimize
╭ ▾ Plan ───────────────────────── 4/7 · 1 blocked ╮
╭ ▾ Context ─────────────────────── 79% of reset ╮   (⇣ Compact inside)
╭ ▾ Usage ──────────────────────── $4.85 · $2.35/h ╮
╭ ▾ Checks ─────────────────────── ● 1 blocking ╮
╭ ▾ Board ──────────────────────── #12 doing ╮
╭ ▾ Workers ────────────────────── ● 2 running ╮
╭ ▾ Repo ───────────────────────── ● dirty ╮
Next  /dflow:build — Task 5: Wire the meter
```

Each card is drawn in full in its own color; the outline shows only its top
rule, with the title on the left and the headline on the right. The controls
row sits under the Account card, or leads the cards when Account is not first.

A card's title collapses it; **Dense** draws one line per card; **Sections**
hides, shows and reorders the cards. A session that starts on an approved,
unfinished plan offers **Resume** and **Dismiss** above the Now row, or above
the band.

- `/dflow:hud` cycles band, pane, off, and reopens a pane closed by hand;
  `/dflow:hud band|pane|off` sets one; `/dflow:hud sections [<cards>]` opens
  the Sections view or sets the list. Mode, density, collapsed cards and
  sections are kept across sessions.

A mod's own commands cannot contain a colon, so `/dflow:hud` is the plugin's
`hud` skill and the mod answers that command itself, without a model turn.
Where mods are unavailable the skill prints `dflow status` instead.

The same mod is the context governor of section 13 and writes the live
context size where the CLI reads it, one file per session. `dflow done` tags
its reset request with the session it ran in (`CLAUDE_CODE_SESSION_ID`), and
only that session's mod compacts, so a second session in the same checkout
is left alone.

## 15. darkmem

The repository is the source of truth. darkmem is a projection, pushed by
the CLI over REST; no mirror directory and no reconcile step.

**Contract darkmem implements for dflow**

| Thing | Form |
|---|---|
| Document URI | the repository path without `docs/`: `dflow/project.md`, `dflow/board.md`, `dflow/plans/<file>.md` |
| Board register | `dflow/board.md`, the six-column table of section 5 |
| Board plans | `dflow/plans/*.md`; `### Task N: title` headings with checkbox steps |
| Row to plan link | the Assigned cell holds `docs/dflow/plans/<file>.md` |
| Workstream | one per plan, keyed by the plan's file name without `.md`, property `plan_uri` |
| Task state | a ledger entry with properties `task`, `state` (`todo wip review blocked done`), `commit`; the body of a `blocked` entry is the reason; `todo` is sent when a task is unblocked |
| Client header | `X-Darkmem-Client: dflow` |

The routes are the ones darkmem has today (documents, work log, board row
edit). darkmem has to change in three places: read the two board prefixes,
map `docs/dflow/` in the Assigned cell, and accept an API key on the board
row edit route, which today takes a login session only. Until the last one,
a plan branch's row is refused and reported; the plan and the work log still
go through, and the board's task progress comes from the work log.

- **Push.** By content hash after `done`, at `ship` and from the Stop hook.
  The whole `board.md` is pushed only from the default branch; a plan branch
  updates only its own row through the row edit route.
- **Checkpoint.** Script-written at each stop: progress, next task, branch,
  commit.
- **Inbound.** A board row edited in darkmem's UI. At session start on the
  default branch the CLI compares hashes: remote changed and local not, the
  row is written into `board.md`; both changed, one conflict line is printed
  and nothing is overwritten.
- **Reads by the model.** `document_search`, `code_search` when the
  repository is indexed, `memory_search` at plan start, `worklog_resume` on a
  machine with no local state.
- **Consent.** The repository names the project, but sync runs only after
  the owner enables that project for the repository in their own
  `~/.dflow/config.json` (`dflow init --darkmem`, `dflow sync enable`). A
  cloned repository cannot steer writes made with the owner's key.
- **Off or unreachable.** Every darkmem step is skipped with one line.

## 16. Measurement, and the comparison with dforge

- `dflow cost` attributes transcript tokens to a plan and its phases,
  deduplicated per message id, subagents included.
- The eval suite under `evals/`, run with `claude plugin eval
  --max-cost-usd`, replays a fixed set of tasks and reports pass rate, cost
  and duration. The same cases are run through dforge for the comparison.

Sizes measured on 2026-11-12, dforge 4.17.1 against dflow 1.0.0 as built:

| | dforge 4.17.1 | dflow 1.0.0 |
|---|---|---|
| Skills | 23 files, 262 KB | 7 files, 16 KB (cap 6 KB each) |
| Reference and criteria text | 297 KB | one on-demand file, 2.5 KB |
| Agent definitions | 19 | 2 |
| Scripts | 52 files, about 19,300 lines | one CLI, about 3,100 lines (the proposal's target was 2,500) |
| darkmem sync code | about 4,000 lines, two-way | 365 lines, one-way |

No token comparison exists: the same plan has not been built with both.

## 17. Build order

All seven steps are in version 1.0; the order only sequences the work.

1. CLI core, the `plan`, `build`, `status` and `init` skills, the hooks,
   tests.
2. Review tiers 0 to 2 with the workflow script, `ship`, the docs checks,
   the test budget.
3. UI proof.
4. darkmem projection.
5. The mod: HUD and context governor.
6. Worker waves and parallel plan sessions.
7. `dflow cost`, the eval suite, the comparison run, threshold tuning.

## 18. Verified, and not

Verified during the build:

- A workflow agent accepts a model and an effort setting.
- The harness's own worktree isolation starts from the remote default branch,
  so the CLI creates worker worktrees itself.
- The mod loads, its hooks and state contract validate, and its command,
  band, pane and reset flag behave as designed in the engine's test kit.

Not verified in a live session:

- That compaction requested by the mod at the end of a turn, followed by
  `/dflow:build`, resumes the build unattended.
- That `/dflow:hud` reaches the mod's hook under the name `dflow:hud`. If it
  does not, the skill prints the status as text.
- That a background session gets the one-hour cache. Starting one is left to
  the owner: `dflow session` prints the command.
- dflow's tests on Windows. They are written for it and enrolled in every
  shard, but have only run on Linux.

## 19. Decisions taken (2026-11-12)

1. The name is dflow.
2. dflow uses its own darkmem URI prefix; darkmem is updated to read it.
3. `dflow done` makes the task commit.
4. UI proof is in version 1.0, which is the complete design, not a subset.
5. A HUD mod is included, toggled by `/dflow:hud`.
