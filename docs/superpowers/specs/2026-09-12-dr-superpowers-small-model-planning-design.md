# dr-superpowers 1.4.0 — small-model planning (sub-project 4 design)

Date: 2026-09-12. Program design: `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`
(§5 R2, R3, R5, R6, R9, R10, R11, R12; §6 item 4). This spec departs from the program design in
three places, recorded as a dated amendment under its §6 (see §10).

Goal: a strong model plans once; Sonnet and Haiku execute the plan literally, never owning a
judgment call. The plan carries everything execution needs in a header block, a mechanical
checker enforces its shape, a judge reviews it before it is saved, and judgment during execution
goes to a strong read-only seat whose plan corrections land in an append-only amendments file.

## 1. Decisions fixed here

- **Judgment always goes to the ruling seat** (owner answer), whatever model runs the controller.
  One rulebook; judges were about 0.7M of 24h tokens, so the extra dispatches are cheap.
- **One seat, controller as scribe** (owner answer, approach A of three). The existing read-only
  `judge-fable` / `judge-opus` rule on judgment items and return amendment text; the controller
  copies it through `scripts/plan-amend`, which validates it. No plan-amender agent exists.
  Rejected: a write-capable Opus-high amender agent (new agent on both hosts, two dispatches per
  design defect); stopping the run on design defects (contradicts "rulings, not stalls").
- **Brainstorming is aligned with the owner's process-depth rules** (owner answer), so the entry
  point and the skill say the same thing.
- **The plan decides its execution mode** (program decision). writing-plans' "Which approach?"
  offer is removed.
- **`plan-lint` is required for new plans only.** Plans written before 1.4.0 are not retrofitted.
- **Scripts are Bash** under Git Bash on Windows, using only bash, coreutils, awk, git and jq,
  like every existing script.
- **Version 1.4.0** on both manifests.

## 2. File layout

New (paths relative to `plugins/dr-superpowers/`):
- `scripts/plan-lint`, `scripts/plan-amend`
- `criteria/plan-review.md`
- `skills/writing-plans/references/plan-reviewer-prompt.md` — replaces
  `plan-document-reviewer-prompt.md`, which is deleted
- `skills/subagent-driven-development/references/ruling-prompt.md`
- `tests/plan-lint.test.sh`, `tests/plan-amend.test.sh`

Changed:
- `scripts/lib/plan.sh` — gains `plan_header_line`, `plan_header`, `plan_task_text`, and
  `plan_apply_amendments`
- `scripts/next-step` — uses `plan_header_line` from the library instead of its local copy
- `scripts/task-brief` — `--header` mode; applies amendments
- Skills: using-superpowers, brainstorming, writing-plans, subagent-driven-development,
  executing-plans (reinforcement block only), test-driven-development, systematic-debugging
- `skills/writing-plans/references/assigning-implementers.md` — its "Check your work" pointer
  now names `plan-lint`
- `skills/subagent-driven-development/references/implementer-prompt.md`
- Tests: `plan-lib`, `budget-line` (task-brief), `next-step`, `criteria`, `hook`
- `README.md`, both manifests

## 3. The plan header block (R9)

Everything before the first `Task N` heading outside a code fence is the **header**. Order:

1. Title, the agentic-workers line, `**Goal:**`, `**Architecture:**`, `**Tech Stack:**`,
   `**Spec:**`, `**Execution:**`, `**Program:**` (optional), `**Plan review:**` (written after
   review, §6). Codex plans also carry `Host: codex` and `Routing policy: codex-v2`
   (native-codex.md). An `> **External executors:**` line stays where external-executor.md puts it.
2. `## Global Constraints` — unchanged: project-wide requirements, one per line, values verbatim
   from the spec.
3. `## Contracts` — every name, signature, file path, format or exit code that one task produces
   and another consumes, stated once. Task `**Interfaces:**` blocks cite it rather than restate
   it. A plan with no cross-task names writes `None`.
4. `## Assumptions (evidence)` — one bullet per assumption, each with its evidence: a command and
   the date it ran, a `file:line`, or a documentation URL. An assumption without evidence reads
   `unverified — Task N verifies it`, and Task N contains the verifying step.
5. `## Task index` — `N. <title>`, one line per task, the title identical to the heading's.

Other sections a planner finds useful (a file map, an ordering note) may sit in the header after
these; they count as header.

**Who reads what:**
- `scripts/task-brief --header PLAN_FILE [OUTFILE]` writes the header, amendments applied, to
  `<workspace>/plan-header.md` (default) and prints `wrote <path>: <N> lines` then the budget
  line — the same shape as a task brief.
- The subagent-driven-development controller reads only that header and one task brief at a
  time. It never reads the whole plan or the spec. The Setup paragraph "If the plan names a Spec,
  read that too…" is removed; a plan with no reachable spec is noted in the ledger and passed to
  the ruling seat, whose rulings are then marked provisional.
- The spec is read only by plan review (§6), the ruling seat (§5) and the final review.
- executing-plans keeps its current reading until sub-project 5.

**writing-plans additions:**
- The header template gains Contracts, Assumptions (evidence) and Task index, and the
  `**Plan review:**` line.
- Walking skeleton: for a greenfield system, Task 1 builds the thinnest end-to-end path through
  every layer, with its test, before any layer is fleshed out.
- Self-review item 3 ("Type consistency") becomes "every cross-task name appears in Contracts,
  and every task uses it exactly as stated there".

## 4. `plan-lint` (R11)

Usage: `plan-lint PLAN_FILE [--task N] [--amendments FILE]`. Default amendments file:
`<workspace>/amendments.md` when it exists (workspace from `sdd-workspace`). Amendments are
applied before any check. CR is stripped on input.

Output: one line per finding, `ERROR <where>: <what>` or `WARN <where>: <what>`, where `<where>`
is `header` or `Task N`; then `plan-lint: <E> errors, <W> warnings`. Exit 0 no errors (warnings
allowed), 1 errors, 2 usage or missing file.

**Plan-level checks** (always run; `--task N` does not skip them):
- Header labels present: `**Goal:**`, `**Spec:**`, `**Execution:**`. The Spec path exists,
  resolved against the repository root.
- Sections present: Global Constraints, Contracts, Assumptions (evidence), Task index.
- Headings: task numbers are 1..N, contiguous and unique. Any heading outside a fence that
  contains `Task <digit>` but does not match `^#+\s+Task\s+[0-9]+` is an ERROR (it silently
  corrupts the previous task's brief; assigning-implementers.md explains).
- Task index: the same numbers and titles as the headings, in order.
- Execution line (R6):
  - Claude: `**Execution:** <inline|subagent> — \`claude --model <m> --effort <e>\` — <reason>`,
    `<m>` in `haiku|sonnet|opus|fable` or matching `claude-[a-z0-9.-]+`, `<e>` in
    `low|medium|high|xhigh|max`.
  - Codex (`Host: codex`): the middle part is `codex <model> / <effort>`, a pair from
    `codex-routing.json`.
  - Hyphen-minus in place of the em dashes is accepted.
- R5: `inline` requires every task's unweighted `files + spec + coupling + risk` to be at most 3
  and no task at risk 3. Otherwise ERROR.
- Program line, when present: `**Program:** <path> — sub-project <k> of <n> — next: <title>`, or
  ending `— last`; `<k> <= <n>`; the path exists.
- Plan review line missing: WARN (it is written after the first lint run).
- Placeholders, matched case-insensitively: `TBD`, `TODO`, `implement later`, `fill in details`,
  `similar to Task [0-9]`, `add appropriate error handling`, `handle edge cases`. ERROR outside
  code fences, WARN inside them.

**Per-task checks, Claude plans** (only task N under `--task N`):
- `**Files:**`, `**Implementer:**` and `**Evaluation:**` present.
- Evaluation parses as `files a - spec b - coupling c - risk d = t` (hyphen or en/em dash); each
  axis 0–3; `a+b+c+d = t`.
- Rule S: `a+b+c < 4` and `b < 3`.
- The Implementer is fully qualified (`dr-superpowers:` or a legacy prefix from
  `reference/legacy-names.md`); after translation, the name equals the `ladder.md` assignment
  table's row for `t`. The table is parsed from its fenced `assignment` block at run time. A name
  in the `reserve` block is an ERROR ("reserve tier needs a human Override").
- `**Approach:**`, when present: `inline`, `advisor` or `best-of-3`, then a dash and a reason;
  `inline` cites `skip <n>`.
- `**Executor:**`, when present: the task also has an Implementer; `t` passes the `gate` block
  (`min_score <= t`, `d <= max_risk`, no Override); the rung equals the `codex-assignment` row
  for `t`; the executor is named on the header's `> **External executors:**` line.

**Per-task checks, Codex plans:**
- `**Implementer:** codex <model> / <effort>`,
  `**Evaluation:** files=a, spec=b, coupling=c, risk=d; weighted routing score=s` with
  `s = a+b+c+2d`, and `**Assignment source:** rubric|human`.
- Rule S as above.
- `rubric`: the pair equals `codex-routing.json`'s row for `s`. `human`: no pair check.

**Override.** A task may carry `**Override:** <reason>` below its Evaluation line. On that task,
Rule S, reserve-name and table-mismatch findings become WARN; an Executor on an overridden task
stays an ERROR (the lane gate excludes human Rule S overrides). This makes a human ruling legal
without the checker guessing who wrote a line. writing-plans documents it; planners never write
it themselves.

writing-plans' "Check your work" list is replaced by: run `scripts/plan-lint PLAN_FILE`, from
the plugin root, until it reports 0 errors; each remaining WARN is either fixed or explained in
one line of the plan's Assumptions. The No Placeholders section stays as prose.

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
<exact text, one or more lines>
````
### New
````text
<replacement text>
````
`````

- The target is `Task <N>` or `Header`. Amendments never add or remove tasks; a split stays the
  SPLIT escalation of escalation.md.
- Old text is non-empty and must occur exactly once in the target's current text, after every
  earlier amendment to that target.
- `plan_apply_amendments` applies entries in file order. `task-brief` (both modes) and
  `plan-lint` call it. A stored amendment whose old text no longer matches is an error:
  `task-brief` exits 4 naming the amendment, and `plan-lint` reports `ERROR Task N: amendment A<k>
  does not apply`.

### 5.2 `scripts/plan-amend PLAN_FILE BLOCK_FILE`

BLOCK_FILE holds one entry as returned by the ruling seat, with `A?` or no number in its heading.
The script:
1. validates the shape (heading, Reason, Cost if wrong, both fences) and that the target exists;
2. checks that the old text occurs exactly once in the target's current text;
3. runs `plan-lint` and keeps its ERROR lines;
4. numbers the entry `A<k>` (one more than the highest existing) and appends it;
5. runs `plan-lint` again; if it reports an ERROR line absent from step 3, removes the appended
   entry and exits 1, printing the new errors.

Comparing before and after means a pre-1.4.0 plan (no Contracts section) still accepts
amendments: only errors the amendment introduces reject it.

Prints `amended: A<k> <target>`. Exit 0 appended, 1 rejected, 2 usage. The controller then
writes `Task <N>: Ruling: amendment A<k> — <reason> — <cost if wrong>` (or a bare `Ruling:` for
a Header target) and dispatches from a fresh `task-brief`, which now carries the amendment.

### 5.3 The ruling seat

The seat is `dr-superpowers:judge-fable`, or `judge-opus` under the Fable-unavailable rule, said
aloud. On Codex it is a native judge at rank 8 (Astra high) or above (native-codex.md). The judge
agents are unchanged: read-only, no subagents.

Template: `skills/subagent-driven-development/references/ruling-prompt.md`. Inputs, all as paths:
the plan, the spec, `amendments.md`, the ledger, and an items file the controller writes. Each
item names its kind, its task, and the paths the seat needs (brief, report, review package,
findings). Invariant material first, the items last, as in the task-reviewer template.

Output, per item:

```
### Item <id>
Verdict: CONFIRMED-GAP | PARK | AMEND | BLOCKED
Ruling: <what> — <why> — <cost if wrong>
[for AMEND: one amendments.md entry, §5.1 format]
[for BLOCKED: what a human must decide]
```

- **CONFIRMED-GAP** — a real defect; the ruling names the smallest fix. It enters the task's fix
  loop, or at the breaker is carried into the next dependent task's dispatch.
- **PARK** — the code stands; the ruling says why. Logged `Task <N>: parked — <finding> — Ruling:
  <why>`.
- **AMEND** — the plan text is wrong; the controller runs `plan-amend` with the entry. If
  `plan-amend` rejects it, the controller makes one fresh seat dispatch carrying the entry and
  the rejection output; a second rejection is `BLOCKED`.
- **BLOCKED** — every path forward is a guess. This is the fourth stop class; the controller
  logs `Task <N>: BLOCKED — ruling seat — <what a human must decide>` and stops per the skill.

Every Ruling line is copied verbatim into the ledger and into the Finish section's "Rulings I
made".

### 5.4 What goes to the seat, and what stays with the controller

Items at one decision point go in one dispatch.

| Decision point | Before | Now |
|---|---|---|
| Pre-flight conflict scan | Controller builds the table from the whole plan | One seat dispatch before Task 1; the seat returns the table and rulings; the controller writes them to `<workspace>/preflight.md` and ledgers each ruling |
| Finding that conflicts with plan text, or is labelled plan-mandated | Controller rules | Seat |
| "⚠️ Cannot verify from diff" item | Controller resolves | Seat |
| Breaker at round 5/5 | Controller adjudicates | Seat, one dispatch for all open findings |
| BLOCKED report whose cause is the plan | Controller rules on a correction | Seat (usually AMEND) |
| Final review dedupe | Controller dedupes, judge verifies | Merged into the existing judge verify dispatch |
| Final-review residuals after the one fix wave | Controller adjudicates | Seat |

The controller still decides, because each is mechanical: the dispatch-problems table, legacy
name translation, resume versus fresh dispatch by cache state, batching, a report missing
required sections (re-dispatch), tool failures, and `plan-amend` transcription.

subagent-driven-development's "Rulings, not stalls" section is rewritten around this split; the
process graph, Setup, the fix loop's plan-conflict route, the breaker, Final Review and the
Common Rationalizations table follow. The ledger grammar is unchanged except that the ruling
seat's `BLOCKED` line reads `Task <N>: BLOCKED — ruling seat — <decision>`.

## 6. Plan review (R10)

**`criteria/plan-review.md`**, in the TEMPLATE shape and ASCII only (`criteria.test.sh` rejects
other bytes, so dashes are written `-`). Ground Truth Note: trust the plan text, the
spec text and the plan-lint output; do not trust the planner's self-review or its claims about
what a task covers. Four criteria:

- `{#executability}` — Look at each task as its implementer will see it: the task text plus the
  header. HIGH: exact paths, complete code in code steps, exact commands with expected output,
  tests that fail against a stub (a test that passes with `return <constant>` or with the
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
Astra high+ on Codex) with the plan path, the spec path and the plan-lint output file. It returns
the four scores (1–20) and findings, each `Critical | Important | Minor` with `Task N` or
`header`. Bands as in task review: 1–8 fails, 9–13 borderline, 14–20 passes.

**End of writing-plans**, in order:
1. Self-review (§3 change to item 3; item 4 now runs `plan-lint`).
2. `plan-lint` until 0 errors.
3. Plan review. Any score ≤8, or any Critical or Important finding: fix, re-lint, dispatch a
   fresh full review. At most 3 review rounds; after the third, present remaining findings to
   your human partner, who is present during planning. A borderline score gets a one-line
   decision in the plan's Assumptions.
4. Write `**Plan review:** <YYYY-MM-DD> — <judge agent> — executability e / coherence c /
   coverage v / assumptions a (round r)`.
5. Commit the plan (and the spec, if uncommitted), then `scripts/next-step PLAN_FILE`. Plan saved
   and reviewed is a hard stop (R7): execution starts in a fresh session.

**Choosing the Execution line** (replaces the "Which approach?" offer):
- `inline` when R5 allows it (the owner's default): `claude --model sonnet --effort <e>`, where
  `<e>` is the effort of the highest-scoring task's assigned tier, `impl-haiku` counting as `low`.
- Otherwise `subagent`: `claude --model sonnet --effort high`. The controller no longer owns
  judgment, so it does not need a stronger model.
- Codex plans: the native pair, per native-codex.md.
- Your human partner may override the line; plan-lint checks only its grammar and R5.

## 7. Entry point and Karpathy placement (R12)

**`skills/using-superpowers/SKILL.md`** is rewritten under a 4,800-character ceiling (about 1.2k
tokens; today 4,078). Content, in order:

1. The `SUBAGENT-STOP` block, and the rule: invoke a matching skill before acting. The red-flags
   table keeps three rows.
2. **Routing table** — task kind → skill, covering every skill in the plugin, handoff and
   resume-execution included.
3. **Four principles** (forrestchang/andrej-karpathy-skills, MIT, already in `LICENSES/`):
   think before coding — state assumptions; ask only in design phases, rule during execution;
   simplicity first; surgical changes; goal-driven — define verifiable success criteria.
4. **Process depth** — take the lightest path that fits; write a spec and plan only when one of
   the seven triggers holds (new project or subsystem; an interface outside its own files
   changes; files not enumerable after exploring; a load-bearing approach question is open;
   irreducible risk — security, data loss, migration, concurrency; behaviour intricate enough
   that edge cases will not survive a chat design; the owner asked for a spec). State the choice
   as `Process: <path> — <trigger | no trigger>`. Execution is inline by default when R5 permits.
   Bugs go to systematic-debugging first.
5. **Session budget and compaction recovery** — the existing section, compressed.
6. Prefer an indexed code tool (for example darkmem `code_search`) over Explore subagents when
   one is available.
7. Platform adaptation; user instructions take precedence.

The SessionStart hook is unchanged; a shorter entry point leaves more room for the compaction
snapshot under its existing `9500 - entry - 400` cap.

**brainstorming** classification:
- **Architectural** exactly when one of the seven triggers holds. **Bounded** otherwise,
  including a small feature that adds a new flow. **Spike** unchanged.
- "When in doubt between two paths, take the heavier one" becomes "Doubt means check the trigger
  list, not jump to the heavier path." The one-way ratchet stays: a trigger discovered mid-task
  upgrades the path.
- "If there is no existing flow to change, the task is not bounded" is removed.
- Red-flag rows rewritten: "I'll call it bounded and skip the spec" → "Name the trigger that
  fails, or take the architectural path"; "I understand this kind of app, so it's bounded" →
  "Bounded is decided by the trigger list, not by familiarity". The row about skipping approval
  on bounded work stays.
- The announcement becomes the `Process:` line. The approval gate is unchanged on every path.

**Reinforcement blocks**, two to three lines each:
- writing-plans: no speculative abstractions; each task is the minimum that meets the spec; each
  task ends with a check that proves it.
- executing-plans: change only what the task names; note adjacent problems in the ledger without
  fixing them; write assumptions to the ledger.
- implementer-prompt.md: do the simplest thing the brief allows; touch only the files and lines
  the task needs.
- test-driven-development: the test quality bar — a test that still passes with
  `return <constant>`, or with the implementation deleted, is invalid.

**Loop-breaker red flags**, in systematic-debugging's red-flags table and the implementer
template's "When You're in Over Your Head" list:
- a third attempt at the same fix → stop and question the assumption behind it;
- the same test still failing after three edits → report BLOCKED with what was tried.

Already done in sub-project 2 and not re-added: the implementer report's Discovered issues and
Assumptions made sections.

## 8. Verification

Program design §7: `node scripts/validate-repository.mjs`, `node scripts/test-all.mjs` (the known
`rg`-missing failure in `ui-discovery.test.mjs` is environmental), `claude plugin validate` on the
marketplace and every Claude plugin; bounded timeouts; every started process cleaned up.

Tests (new `.test.sh` files are picked up by `test-all.mjs` automatically):
- `plan-lint.test.sh`: a clean Claude plan and a clean Codex plan exit 0; one fixture per ERROR
  class in §4 (missing section, index mismatch, malformed heading, sum mismatch, Rule S, wrong
  agent, reserve name, Override downgrade to WARN, Executor on an overridden task, Approach,
  Executor gate and rung, Execution grammar, inline breaking R5, Program line, placeholder in
  prose versus fence, missing Spec path); Codex weighted-score and routing mismatches; amendments
  applied before checks; a non-applying amendment; `--task`; exit codes; CRLF input.
- `plan-amend.test.sh`: append and numbering; old text absent; old text twice; Header target;
  rollback when the amendment introduces a lint error; acceptance on a plan with pre-existing
  errors; CRLF.
- `plan-lib.test.sh`: `plan_header_line`, `plan_header`, `plan_task_text`,
  `plan_apply_amendments`.
- `budget-line.test.sh` (task-brief): `--header` output and budget line; amendments applied to
  task and header briefs; exit 4 on a non-applying amendment.
- `next-step.test.sh`: unchanged expectations pass after `header_line` moves to the library.
- `criteria.test.sh`: plan-review exposes exactly `assumptions coherence coverage executability`.
- `hook.test.sh`: `using-superpowers/SKILL.md` is at most 4,800 characters.
- `validate-repository.mjs`' reference check covers every new `dr-superpowers:` name.

## 9. Out of scope

The executing-plans rewrite on R1 and R5 (sub-project 5); the Windows `jq` argument-length
failure in `run-codex-task.sh`; linting or retrofitting plans written before 1.4.0; a
header-size limit. The `plugins/darkmem-resume/` directory is the owner's live work: never
touched or committed.

## 10. Program amendment

Appended to the program design's §6 as `Amendment 2026-09-12 (sub-project 4 spec)`:
- R2's plan-amender is not a separate seat: the ruling seat returns AMEND entries and the
  controller transcribes them through `scripts/plan-amend`.
- The ruling seat has a fourth verdict, BLOCKED, the only route to the fourth stop class for a
  plan defect.
- writing-plans no longer offers an execution choice; the Execution line decides.

## 11. Risks

- A header-only controller loses context it used to take from the whole plan. Mitigation:
  Contracts carries every cross-task name, and the seat reads the whole plan and spec.
- `plan-lint`'s prose regexes can be brittle against planner wording. Fixtures pin each form;
  hyphen and dash variants are accepted where §4 says so.
- Fable costs about 10× per token. One seat dispatch per decision point bounds it; a clean run
  costs one pre-flight dispatch plus the final review it already had.
- The pre-flight table passes through the controller's context once, when it writes
  `preflight.md`.
- Whether the Agent tool reliably returns a judge's full output for long tables is unverified;
  the plan checks the pre-flight output on the first real run.
