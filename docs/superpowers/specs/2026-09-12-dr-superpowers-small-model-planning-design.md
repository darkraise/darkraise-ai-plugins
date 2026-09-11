# dr-superpowers 1.4.0 — small-model planning (sub-project 4 design)

Date: 2026-09-12. Program design: `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`
(§5 R2, R3, R5, R6, R9, R10, R11, R12; §6 item 4). This spec departs from the program design in
three places, recorded as a dated amendment under its §6 (see §10).

Reviewed as a draft by an independent Fable pass on 2026-09-12 (verdict: issues found, 2
critical, 10 important, 11 minor). Each claim was checked against the files; every finding is
resolved below. Three further controller judgment points found during that review (borderline
scores, risk-3 score spread, a Codex empty-diff argument) are routed in §5.4.

Goal: a strong model plans once; Sonnet and Haiku execute the plan literally, never owning a
judgment call. The plan carries everything execution needs in a header block, a mechanical
checker enforces its shape, a judge reviews it before it is saved, and judgment during execution
goes to a strong read-only seat whose plan corrections land in an append-only amendments file.

## 1. Decisions fixed here

- **Judgment always goes to the ruling seat** (owner answer), whatever model runs the controller.
- **One seat, controller as scribe** (owner answer, approach A of three). The existing read-only
  `judge-fable` / `judge-opus` rule on judgment items and return amendment text; the controller
  copies it through `scripts/plan-amend`, which validates it. No plan-amender agent exists.
  Rejected: a write-capable Opus-high amender agent (new agent on both hosts, two dispatches per
  design defect); stopping the run on design defects (contradicts "rulings, not stalls").
- **Brainstorming is aligned with the owner's process-depth rules** (owner answer).
- **The plan decides its execution mode** (program decision). writing-plans' "Which approach?"
  offer is removed.
- **Every task brief carries the header's Global Constraints and Contracts**, so implementers,
  reviewers and the Codex executor lane see cross-task names without new dispatch inputs.
- **Borderline review scores (9–13) are recorded, not adjudicated**: the final review triages
  them. The controller makes no judgment on them.
- **The plan-saved stop runs dr-superpowers:handoff**, which commits plan and spec and runs
  `next-step` — one procedure for every stop.
- **`plan-lint` is required for new plans only.** Plans written before 1.4.0 are not retrofitted.
- **Scripts are Bash** under Git Bash on Windows, using only bash, coreutils, awk, git and jq.
- **Version 1.4.0** on both manifests.

## 2. File layout

Paths relative to `plugins/dr-superpowers/`.

New:
- `scripts/plan-lint`, `scripts/plan-amend`
- `criteria/plan-review.md`
- `skills/writing-plans/references/plan-reviewer-prompt.md` — replaces
  `plan-document-reviewer-prompt.md`, which is deleted
- `skills/subagent-driven-development/references/ruling-prompt.md`
- `tests/plan-lint.test.sh`, `tests/plan-amend.test.sh`

Changed:
- `scripts/lib/plan.sh` — new fence rule; new functions (§3.1)
- `scripts/next-step` — uses `plan_header_line` from the library
- `scripts/task-brief` — extracts through the library, applies amendments, appends the header
  excerpt, gains `--header`
- Skills: using-superpowers, brainstorming, writing-plans, subagent-driven-development,
  executing-plans (reinforcement block only), resume-execution, finishing-a-development-branch,
  test-driven-development, systematic-debugging
- `skills/writing-plans/references/assigning-implementers.md`
- `skills/subagent-driven-development/references/implementer-prompt.md`,
  `task-reviewer-prompt.md`
- `reference/session-budget.md`, `reference/external-executor.md`
- `agents/judge-fable.md`, `agents/judge-opus.md` — description only
- Tests: `plan-lib`, `budget-line`, `next-step`, `criteria`, `hook`
- `README.md` (How it fires, What a plan looks like, Differences from upstream, Reference),
  both manifests

## 3. The plan header block (R9)

Everything before the first task heading outside a code fence is the **header**. Order:

1. Title, the agentic-workers line, `**Goal:**`, `**Architecture:**`, `**Tech Stack:**`,
   `**Spec:**`, `**Execution:**`, `**Program:**` (optional), `**Plan review:**` (written after
   review, §6). Codex plans also carry `Host: codex` and `Routing policy: codex-v2`, bare or bold
   (`**Host:** codex`); both forms are accepted. An `> **External executors:**` line stays where
   external-executor.md puts it.
2. `## Global Constraints` — unchanged: project-wide requirements, one per line, values verbatim
   from the spec.
3. `## Contracts` — every name, signature, file path, format or exit code that one task produces
   and another consumes, stated once. Task `**Interfaces:**` blocks cite it rather than restate
   it. A plan with no cross-task names writes `None`.
4. `## Assumptions (evidence)` — one bullet per assumption, each with its evidence: a command and
   the date it ran, a `file:line`, or a documentation URL. An assumption without evidence reads
   `unverified — Task N verifies it`, and Task N contains the verifying step.
5. `## Task index` — `N. <title>`, one line per task, the title identical to the heading's.

Other sections a planner finds useful (a file map, an ordering note) may follow; they count as
header.

The agentic-workers line changes to: "REQUIRED SUB-SKILL: the skill the **Execution:** line names
— dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for
`inline`."

### 3.1 Library contracts (`scripts/lib/plan.sh`)

**Fence rule** for every function below, replacing today's `/^```/` toggle: a line matching
`^ {0,3}(`{3,}|~{3,})` opens a fence; the fence closes at a line whose trimmed content is a
marker of the same character and at least the opening length. This is the rule
`scripts/validate-repository.mjs:66-74` already uses; it makes a 4-backtick block containing
3-backtick fences one block. `plan_tasks` adopts it too (next-step and repo-audit benefit).

**Task heading**: outside a fence, `^#+[ \t]+Task[ \t]+[0-9]+` (unchanged). All output is LF; CR is
stripped on input.

| Function | Output (stdout) | Exit |
|---|---|---|
| `plan_tasks FILE` | unchanged: `N<TAB>title` per task heading | 0 |
| `ledger_done FILE` | unchanged | 0 |
| `plan_header_line FILE LABEL` | first line outside a fence beginning `**LABEL:**`, or nothing | 0 |
| `plan_header FILE` | every line before the first task heading | 0 |
| `plan_task_text FILE N` | task N's heading through the line before the next task heading | 0; 3 if absent |
| `plan_apply_amendments PLAN AMEND` | the plan with every entry in AMEND applied (§5.1); the plan unchanged when AMEND is missing or empty | 0; 1 with `amendment A<k> does not apply` on stderr |
| `plan_amendments_file PLAN` | `<workspace>/amendments.md` when PLAN is inside a git repository and that file exists (workspace from `sdd-workspace`), else nothing | 0 |

`next-step` and `repo-audit` read the raw plan. That is correct because the lines they read
(`**Execution:**`, `**Program:**`, `**Spec:**`) cannot be amended (§5.1).

### 3.2 Task briefs and who reads what

- `scripts/task-brief PLAN_FILE N [OUTFILE]` applies `plan_amendments_file`'s amendments (whatever
  OUTFILE is), writes `plan_task_text`, then appends `## Plan header excerpt` containing the
  amended header's `## Global Constraints` and `## Contracts` sections verbatim. Output lines and
  exit codes are unchanged, plus exit 4 when an amendment does not apply.
- `scripts/task-brief --header PLAN_FILE [OUTFILE]` writes the whole amended header to
  `<workspace>/plan-header.md` (default) and prints `wrote <path>: <N> lines` then the budget
  line.
- The brief stays the single source of requirements for implementers, the Codex executor and task
  reviewers. `task-reviewer-prompt.md`'s `[GLOBAL_CONSTRAINTS]` placeholder is removed: the brief
  carries them. Spec completeness in `ladder.md`'s rubric is scored on what the brief carries,
  header excerpt included.
- The subagent-driven-development controller reads only `plan-header.md` and one task brief at a
  time — never the whole plan or the spec. Setup's "If the plan names a Spec, read that too…"
  paragraph is removed. A plan with no reachable spec is noted in the ledger and passed to the
  ruling seat, whose rulings are then marked provisional.
- Batching small same-shape tasks is decided from the briefs of contiguous candidate tasks, which
  the controller extracts with `task-brief`.
- resume-execution step 4 reloads the header with `task-brief --header` instead of reading the
  plan above its first task.
- The spec is read only by plan review (§6), the ruling seat (§5) and the final review.
- executing-plans keeps its current reading until sub-project 5.

### 3.3 writing-plans additions

- The header template gains Contracts, Assumptions (evidence), Task index and the
  `**Plan review:**` line, and the new agentic-workers line.
- Walking skeleton: for a greenfield system, Task 1 builds the thinnest end-to-end path through
  every layer, with its test, before any layer is fleshed out.
- Self-review item 3 ("Type consistency") becomes "every cross-task name appears in Contracts,
  and every task uses it exactly as stated there".

## 4. `plan-lint` (R11)

Usage: `plan-lint PLAN_FILE [--amendments FILE]`. Default: `plan_amendments_file PLAN_FILE`
(none outside a git repository). Amendments are applied before any check; the checks see the
amended plan. Paths in `**Spec:**` and `**Program:**` lines have surrounding backticks stripped
and resolve against `git -C "$(dirname PLAN_FILE)" rev-parse --show-toplevel`, or the current
directory outside a repository.

Output: one line per finding, `ERROR <where>: <what>` or `WARN <where>: <what>`, where `<where>`
is `header` or `Task N`; then `plan-lint: <E> errors, <W> warnings`. Exit 0 no errors (warnings
allowed), 1 errors, 2 usage or missing file.

**Separators.** Wherever this section writes ` — `, the line may use ` — `, ` – `, ` - ` or
` -- ` (spaces on both sides). Backticks around a command are optional.

### 4.1 Plan-level checks

- Header labels present: `**Goal:**`, `**Spec:**`, `**Execution:**`. The Spec path exists.
- Sections present: `## Global Constraints`, `## Contracts`, `## Assumptions (evidence)`,
  `## Task index`.
- Task numbers are 1..N, contiguous and unique.
- **Malformed task headings** (outside fences): a heading whose text begins with the word `task`
  in any case but does not match `^Task[ \t]+[0-9]+`, or whose text ends with `(Task <digits>)`,
  is an ERROR — the form that corrupts the previous task's brief
  (assigning-implementers.md). Other headings that mention a task are not findings.
- Task index: the same numbers and titles as the headings, in order.
- **Execution line (R6).**
  - Claude: `**Execution:** <inline|subagent> — claude --model <m> --effort <e> — <reason>`,
    `<m>` in `haiku|sonnet|opus|fable` or matching `claude-[a-z0-9.-]+`, `<e>` in
    `low|medium|high|xhigh|max`.
  - Codex plans: the middle part is `codex <model> / <effort>`, a pair from `codex-routing.json`'s
    `execution` or `reserve` arrays.
- **R5.** `inline` requires every task's unweighted `files + spec + coupling + risk` to be at most
  3 and no task at risk 3 (Codex plans: the same, from the raw axes). Otherwise ERROR.
- **Program line**, when present: `**Program:** <path> — sub-project <k> of <n> — next: <title>`,
  or `… — sub-project <k> of <n> — last`; `k <= n`; the path exists.
- `**Plan review:**` missing: WARN (lint runs before review, §6).
- **Placeholders.** Matched per line after removing inline code spans (`` `…` ``):
  - ERROR outside fences, WARN inside: `(^|[^A-Za-z])(TBD|TODO)([^A-Za-z]|$)` (case-sensitive);
    `implement later`, `fill in (the )?details`, `similar to task [0-9]+` (case-insensitive).
  - WARN anywhere: `add appropriate error handling`, `handle edge cases` (case-insensitive).

### 4.2 Per-task checks, Claude plans

- `**Files:**`, `**Implementer:**` and `**Evaluation:**` present.
- Evaluation parses as `files a — spec b — coupling c — risk d = t` (separators as above); each
  axis 0–3; `a+b+c+d = t`.
- Rule S: `a+b+c < 4` and `b < 3`.
- **Implementer name.** The value is `<prefix>:<suffix>`. The suffix is what is checked, per
  legacy-names.md's "resolve by suffix". A prefix other than `dr-superpowers` is a WARN (legacy
  prefix). plan-lint never spells an old prefix literally, so the validator's literal-prefix rule
  holds.
- The suffix equals `ladder.md`'s `assignment` row for `t`. Both tables are parsed from their
  fenced blocks at run time.
- **Reserve names** are the tokens in the `reserve` block's first column that are neither
  `BLOCKED` nor in the `assignment` block — the nine `xhigh`, `max` and Fable agents.
  `impl-opus-high` is not one. A reserve suffix is an ERROR ("reserve tier needs a human
  Override").
- `**Approach:**`, when present: `inline`, `advisor` or `best-of-3`, a separator, and a reason;
  `inline` cites `skip <n>`.
- `**Executor:**`, when present: the task also has an Implementer; `t` passes the `gate` block
  (`min_score <= t`, `d <= max_risk`, no Override); the rung equals the `codex-assignment` row
  for `t`; the executor is named on the header's `> **External executors:**` line.

### 4.3 Per-task checks, Codex plans

- `**Implementer:** codex <model> / <effort>`,
  `**Evaluation:** files=a, spec=b, coupling=c, risk=d; weighted routing score=s` with
  `s = a+b+c+2d`, and `**Assignment source:** rubric|human`.
- Rule S as above.
- `rubric`: the pair is in `codex-routing.json`'s `execution` array with rank ≥ `s` — lower is an
  ERROR, higher a WARN (a capability promotion, native-codex.md:89-91). `human`: no pair check.

### 4.4 Override

A task may carry `**Override:** <reason>` below its Evaluation line. On that task, Rule S,
reserve-name, table-mismatch and Codex-rank findings become WARN. An Executor on an overridden
task stays an ERROR (the lane gate excludes human Rule S overrides). writing-plans documents the
line; planners never write it themselves.

writing-plans' "Check your work" list is replaced by: run `scripts/plan-lint PLAN_FILE`, from the
plugin root, until it reports 0 errors; fix each WARN or explain it in one line of the plan's
Assumptions. The No Placeholders section stays as prose. assigning-implementers.md's pointer to
"Check your work" names `plan-lint` instead.

## 5. Amendments (R2) and the ruling seat (R3)

### 5.1 `amendments.md`

`<workspace>/amendments.md` is append-only; the plan file is never edited during execution.
Entry format:

`````markdown
## A<k> — Task <N>
Reason: <one line>
Cost if wrong: <one line>
### Old
````text
<exact lines>
````
### New
````text
<replacement lines, possibly none>
````
`````

- The heading is `## A<k> — Task <N>` or `## A<k> — Header` (`—` or `-`).
- The Old and New fences are 4 or more backticks under the §3.1 fence rule, so 3-backtick
  fences inside are content.
- The **target text** is `plan_task_text PLAN N` for a task, `plan_header PLAN` for the header,
  each after every earlier amendment.
- Old is one or more whole lines. It must match a contiguous run of whole lines of the target
  exactly once, compared after CR stripping. New replaces that run; New may be empty.
- Old may not contain a line beginning `**Spec:**`, `**Execution:**`, `**Program:**`,
  `**Plan review:**` or a `Host:` / `Routing policy:` line. Those lines are not amendable.
- Amendments never add or remove tasks. A split stays the SPLIT escalation of escalation.md.
- `plan_apply_amendments` applies entries in file order. A stored entry that no longer applies is
  an error: `task-brief` exits 4 naming it, and `plan-lint` reports
  `ERROR header: amendment A<k> does not apply` and checks the plan unamended.

### 5.2 `scripts/plan-amend PLAN_FILE BLOCK_FILE`

BLOCK_FILE holds one entry as the ruling seat returned it, with heading `## A? — Task N`,
`## Task N`, `## A? — Header` or `## Header` (`—` or `-`). The script:

1. validates the shape (heading, `Reason:`, `Cost if wrong:`, both fences), the target and the
   protected-line rule;
2. checks that Old matches exactly once in the target's current text;
3. runs `plan-lint` and keeps its ERROR lines;
4. copies `amendments.md` to a temporary file, numbers the entry `A<k>` (one more than the
   highest existing, starting at 1) and appends it;
5. runs `plan-lint` again. If it reports an ERROR line absent from step 3, the script restores
   the copy and exits 1, printing the new errors.

Comparing before and after lets a pre-1.4.0 plan (no Contracts section) still accept amendments:
only errors the amendment introduces reject it.

It prints `amended: A<k> <Task N|Header>`. Exit 0 appended, 1 rejected, 2 usage. The controller
then writes the ledger line (§5.5) and dispatches from a fresh `task-brief`, which now carries
the amendment.

### 5.3 The ruling seat

The seat is `dr-superpowers:judge-fable`, or `judge-opus` under the Fable-unavailable rule, said
aloud. On Codex it is a native judge at rank 8 (Astra high) or above (native-codex.md). The judge
agents stay read-only with no subagents; their `description` lines gain "rule on execution
judgment items, or review a plan". The ruling seat uses a new template,
`skills/subagent-driven-development/references/ruling-prompt.md`.

**Inputs**, all as paths: the plan, the spec, `amendments.md`, the ledger, and an items file the
controller writes. Each item has an id, a kind (§5.4), its task (or `plan`), and the paths it
needs: brief, report, review packages, findings. Invariant material goes first and the items
file last, as in the task-reviewer template.

**Output per item**:

```
### Item <id>
Verdict: CONFIRMED-GAP | PARK | AMEND | BLOCKED
Ruling: <what> — <why> — <cost if wrong>
[AMEND: one entry in the §5.2 BLOCK_FILE shape]
[BLOCKED: what a human must decide]
```

- **CONFIRMED-GAP** — a real defect; the ruling names the smallest fix. It enters the task's fix
  loop, or at the breaker is carried into the next dependent task's dispatch.
- **PARK** — the code stands; the ruling says why.
- **AMEND** — the plan text is wrong. The controller writes the entry to a file and runs
  `plan-amend`. On rejection it makes one fresh seat dispatch carrying the entry and the
  rejection output; a second rejection is BLOCKED.
- **BLOCKED** — every path forward is a guess. This is the fourth stop class.

**The `preflight` kind** returns, instead of one verdict block, the conflict table that
subagent-driven-development's Setup defines: one row per pair of tasks sharing a file or
interface, and one row per task on self-consistency. After the table comes one verdict block per
row that found something, with ids `preflight-<row>`. The controller writes the whole output to
`<workspace>/preflight.md` and ledgers each ruling.

### 5.4 What goes to the seat, and what stays with the controller

Items at one decision point go in one dispatch.

| Decision point | Item kind | Today | Now |
|---|---|---|---|
| Before Task 1 | `preflight` | Controller builds the conflict table from the whole plan | Seat |
| A finding that conflicts with plan text, or is labelled plan-mandated | `plan-conflict` | Controller rules | Seat |
| "⚠️ Cannot verify from diff" | `cannot-verify` | Controller resolves | Seat |
| Risk-3 scores spread by more than 6 on a criterion | `risk3-spread` | Controller reads the diff | Seat, with the three reviews |
| Breaker at round 5/5 | `breaker` | Controller adjudicates | Seat, one dispatch for all open findings |
| BLOCKED report caused by the plan | `blocked-plan` | Controller rules on a correction | Seat (usually AMEND) |
| Codex fix round returns an empty diff with an argument (external-executor.md:297-299, 401) | `codex-empty-diff` | Controller adjudicates | Seat; two in a row stays a HANDBACK |
| Final-review residuals after the one fix wave | `final-residual` | Controller adjudicates | Seat |
| Final review dedupe | — | Controller dedupes, judge verifies | Folded into the existing judge verify dispatch (CONFIRMED / REJECTED, unchanged) |
| Borderline score 9–13 | — | Controller adjudicates | Recorded on the complete line; the final reviewer triages |

The controller still decides, because each is mechanical: the dispatch-problems table, legacy
name translation, resuming versus fresh dispatch by cache state, batching, re-dispatching a report
missing required sections, tool failures, and `plan-amend` transcription.

subagent-driven-development's "Rulings, not stalls" section is rewritten around this split, and
so are the process graph, Setup, the fix loop's plan-conflict route, the ⚠️ paragraph, the Risk 3
paragraph, the breaker, Final Review and the Common Rationalizations table.

### 5.5 Ledger lines

Added to the grammar block explicitly:

```
Task <N>: Ruling: amendment A<k> — <reason> — <cost if wrong>
Ruling: amendment A<k> (Header) — <reason> — <cost if wrong>
Task <N>: BLOCKED — ruling seat — <what a human must decide>
```

A preflight or header-level BLOCKED is logged against the lowest-numbered incomplete task, so
recovery, `next-step` and the snapshot parse it unchanged. A seat PARK is logged in the existing
`Task <N>: parked — <finding> — Ruling: <why>` form. Every seat `Ruling:` is copied verbatim.

### 5.6 Finish

"Rulings I made" is unchanged and includes every seat ruling. It is followed by
"Amendments made": every `amendments.md` entry in full. The workspace is deleted after a merge,
so this printed list is the only lasting record of plan changes.
finishing-a-development-branch's "Rulings first" step prints both lists when they were not
printed this session.

## 6. Plan review (R10)

**`criteria/plan-review.md`** follows the TEMPLATE shape and is ASCII only: `criteria.test.sh`
rejects other bytes, so dashes are written `-`. Its Ground Truth Note: trust the plan text, the
spec text and the plan-lint output; do not trust the planner's self-review or its claims about
what a task covers. Four criteria:

- `{#executability}` — Look at each task as its implementer will see it: the task text plus the
  header excerpt. HIGH: exact paths, complete code in code steps, exact commands with expected
  output, tests that fail against a stub (a test that passes with `return <constant>` or with the
  implementation deleted is invalid). LOW: a step that needs a decision, a reference to something
  outside the task and header, a test that asserts nothing. Ignore spec coverage.
- `{#coherence}` — Look across tasks, Contracts and Global Constraints. HIGH: every consumed name
  is produced by an earlier task and matches Contracts; Interfaces blocks cite Contracts; no two
  tasks contradict. LOW: a name used before it exists, a signature that differs between tasks, a
  task that breaks a Global Constraint. Ignore whether the spec is covered.
- `{#coverage}` — Look at the spec's requirements against the task index and task text. HIGH:
  every requirement maps to a task, nothing is built beyond the spec. LOW: a requirement with no
  task, a task with no requirement. Ignore how well each task is written.
- `{#assumptions}` — Look at Assumptions (evidence) and at facts tasks rely on. HIGH: each
  assumption's evidence actually supports it; every `unverified` one has its verifying step in
  the named task. LOW: evidence that does not show the claim, an assumption a task relies on that
  is not listed. Ignore executability.

**`plan-reviewer-prompt.md`** dispatches the same seat as §5.3 (Fable, or Opus said aloud; native
Astra high+ on Codex). Inputs: the plan path, the spec path, and `<workspace>/plan-lint.txt`,
which the planner writes with `scripts/plan-lint PLAN_FILE > <workspace>/plan-lint.txt` before
dispatch (the judge cannot run commands). It returns the four scores (1–20) and findings, each
`Critical | Important | Minor` with `Task N` or `header`. Bands as in task review: 1–8 fails,
9–13 borderline, 14–20 passes.

**End of writing-plans**, in order:
1. Self-review (§3.3 change to item 3; item 4 now runs `plan-lint`).
2. `plan-lint` until 0 errors.
3. Plan review. Any score ≤8, or any Critical or Important finding: fix, re-lint, dispatch a
   fresh full review. At most 3 review rounds; after the third, present remaining findings to
   your human partner, who is present during planning. A borderline score gets a one-line
   decision in the plan's Assumptions.
4. Write `**Plan review:** <YYYY-MM-DD> — <judge agent> — executability e / coherence c /
   coverage v / assumptions a (round r)`.
5. Invoke dr-superpowers:handoff. It commits the plan and the spec, writes `latest.md`, runs
   `scripts/next-step PLAN_FILE`, and ends the session with the resume guide: plan saved and
   reviewed is a hard stop (R7). `reference/session-budget.md`'s sentence "The plan-saved stop
   is not yet wired into `writing-plans`…" is deleted.

**Choosing the Execution line** (replaces the "Which approach?" offer):
- `inline` when R5 allows it (the owner's default): `claude --model sonnet --effort <e>`, where
  `<e>` is the effort of the highest-scoring task's assigned tier, `impl-haiku` counting as `low`.
- Otherwise `subagent`: `claude --model sonnet --effort high`. The controller no longer owns
  judgment, so it does not need a stronger model.
- Codex plans: the native pair, per native-codex.md.
- Your human partner may override the line; plan-lint checks only its grammar and R5.

## 7. Entry point and Karpathy placement (R12)

**`skills/using-superpowers/SKILL.md`** is rewritten to at most 4,800 bytes (`wc -c`, about 1.2k
tokens; today 4,078). Content, in order:

1. The `SUBAGENT-STOP` block, and the rule: invoke a matching skill before acting. The red-flags
   table keeps three rows.
2. **Routing table** — task kind → skill, covering every skill in the plugin, handoff and
   resume-execution included.
3. **Four principles** (forrestchang/andrej-karpathy-skills, MIT, already in `LICENSES/`):
   think before coding — state assumptions; ask only in design phases, rule during execution;
   simplicity first; surgical changes; goal-driven — define verifiable success criteria.
4. **Process depth** — take the lightest path that fits; write a spec and plan only when one of
   the seven triggers holds: a new project or subsystem; an interface that something outside its
   own files depends on changes; the files touched cannot be enumerated after exploring; a
   load-bearing approach question is open; irreducible risk (security, data loss, migration,
   concurrency); behaviour intricate enough that edge cases will not survive a chat design; your
   human partner asked for a spec. State the choice as
   `Process: <spike|bounded|architectural>, <inline|subagent> — <trigger | no trigger>`.
   Execution is inline by default when R5 permits. Bugs go to systematic-debugging first.
5. **Session budget and compaction recovery** — the existing section, compressed.
6. Prefer an indexed code tool (for example darkmem `code_search`) over Explore subagents when
   one is available.
7. Platform adaptation; user instructions take precedence.

If the draft exceeds the ceiling, cut in this order: the red-flags table entirely, then the
budget section down to two lines pointing at session-budget.md. The SessionStart hook is
unchanged; a shorter entry point leaves more room for the compaction snapshot.

**brainstorming** classification:
- **Architectural** exactly when one of the seven triggers holds. **Bounded** otherwise,
  including a small feature that adds a new flow. **Spike** unchanged.
- "When in doubt between two paths, take the heavier one" becomes "Doubt means check the trigger
  list, not jump to the heavier path." The one-way ratchet stays: a trigger discovered mid-task
  upgrades the path.
- "If there is no existing flow to change, the task is not bounded" is removed.
- Red-flag rows rewritten: "I'll call it bounded and skip the spec" → "Name the trigger that
  fails, or take the architectural path"; "I understand this kind of app, so it's bounded" →
  "Bounded is decided by the trigger list, not by familiarity". The row about skipping approval on
  bounded work stays.
- The announcement is the `Process:` line, with the same vocabulary as the entry point. The
  approval gate is unchanged on every path.

**Reinforcement blocks**, two to three lines each:
- writing-plans: no speculative abstractions; each task is the minimum that meets the spec; each
  task ends with a check that proves it.
- executing-plans: change only what the task names; note adjacent problems in the ledger without
  fixing them; write assumptions to the ledger.
- implementer-prompt.md: do the simplest thing the brief allows; touch only the files and lines
  the task needs.
- test-driven-development: the test quality bar — a test that still passes with
  `return <constant>`, or with the implementation deleted, is invalid.

**Loop-breaker red flags.** systematic-debugging's red-flags list (a bullet list) already stops at
three failed fixes; its "One more fix attempt" rationalization row and that list item are
sharpened to name both signals below. The implementer template's "When You're in Over Your Head"
list gains them:
- a third attempt at the same fix → stop and question the assumption behind it;
- the same test still failing after three edits → report BLOCKED with what was tried.

Already done in sub-project 2 and not re-added: the implementer report's Discovered issues and
Assumptions made sections.

## 8. Verification

Program design §7: `node scripts/validate-repository.mjs`, `node scripts/test-all.mjs` (the known
`rg`-missing failure in `ui-discovery.test.mjs` is environmental), `claude plugin validate` on the
marketplace and every Claude plugin; bounded timeouts; every started process cleaned up.

Tests (new `.test.sh` files are picked up by `test-all.mjs` automatically). Fixture plans are
written to temporary directories. Any legacy prefix a fixture needs is built by string
concatenation, so no plugin file spells one literally.

- `plan-lint.test.sh`:
  - a clean Claude plan and a clean Codex plan exit 0;
  - one fixture per ERROR class in §4: missing section, index mismatch, both malformed-heading
    forms (and a harmless step heading that is not a finding), sum mismatch, Rule S, wrong agent,
    reserve name, `impl-opus-high` at score 6 accepted, Override downgrade to WARN, Executor on an
    overridden task, Approach, Executor gate and rung, Execution grammar, inline breaking R5,
    Program line, missing Spec path;
  - placeholders in prose, in fences and in inline code spans; separator variants (`—`, `-`, `--`)
    and optional backticks;
  - a legacy-prefixed Implementer gives a WARN;
  - Codex weighted-score mismatch, rank below `s` (ERROR) and promotion (WARN);
  - amendments applied before checks, and a non-applying amendment;
  - a nested 4-backtick fence containing a `### Task 9:` line is not a task;
  - exit codes; CRLF input.
- `plan-amend.test.sh`: append and numbering; old text absent; old text twice; Header target;
  protected-line rejection; rollback restores the previous file byte for byte when the amendment
  introduces a lint error; acceptance on a plan with pre-existing errors; CRLF.
- `plan-lib.test.sh`: the new fence rule (nested fences, tildes); `plan_header_line`,
  `plan_header`, `plan_task_text` (absent task exits 3), `plan_apply_amendments` (multi-line Old,
  Old inside a fenced block, empty New, non-applying entry exits 1), `plan_amendments_file`.
- `budget-line.test.sh` (task-brief): the brief ends with the header excerpt; `--header` output
  and budget line; amendments applied to task and header briefs; exit 4 on a non-applying
  amendment; an explicit OUTFILE still applies amendments.
- `next-step.test.sh`: unchanged expectations pass after `header_line` moves to the library.
- `criteria.test.sh`: plan-review exposes exactly `assumptions coherence coverage executability`.
- `hook.test.sh`: `wc -c` of `using-superpowers/SKILL.md` is at most 4,800.
- `validate-repository.mjs`' reference check covers every new `dr-superpowers:` name.

## 9. Out of scope

- The executing-plans rewrite on R1 and R5 (sub-project 5). Until then an `inline` plan runs
  under the current executing-plans, which stops and asks on a blocker; that is not a regression
  introduced here.
- The Windows `jq` argument-length failure in `run-codex-task.sh`.
- Linting or retrofitting plans written before 1.4.0; a header-size limit.
- The `plugins/darkmem-resume/` directory is the owner's live work: never touched or committed.

## 10. Program amendment

Appended to the program design's §6 as `Amendment 2026-09-12 (sub-project 4 spec)` (committed
with the first draft of this spec):
- R2's plan-amender is not a separate seat: the ruling seat returns AMEND entries and the
  controller transcribes them through `scripts/plan-amend`.
- The ruling seat has a fourth verdict, BLOCKED, the only route to the fourth stop class for a
  plan defect.
- writing-plans no longer offers an execution choice; the Execution line decides.

## 11. Risks

- A header-only controller loses context it used to take from the whole plan. Mitigation: briefs
  carry Contracts and Global Constraints, and the seat reads the whole plan and spec.
- `plan-lint`'s prose regexes can be brittle against planner wording. They are stated verbatim in
  §4, and fixtures pin each form.
- Fable costs about 10× per token. One seat dispatch per decision point bounds it; a clean run
  costs one pre-flight dispatch on top of the final review it already had.
- The pre-flight table passes through the controller's context once, when it writes
  `preflight.md`.
- Briefs grow by the header excerpt on every task. Contracts are meant to be short; plan review's
  executability criterion sees the cost.
- The fence-rule change alters `plan_tasks` for next-step and repo-audit. Their suites pin the
  existing behaviour, and nested fences were previously misparsed.
