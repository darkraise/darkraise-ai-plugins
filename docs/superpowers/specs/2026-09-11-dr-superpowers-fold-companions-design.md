# dr-superpowers 1.2.0 — fold the companion skills in (sub-project 2 design)

Date: 2026-09-11. Status: approved design for sub-project 2 of the program design
`2026-09-11-dr-superpowers-fork-design.md` (§6 item 2). Scope rule: behaviour unchanged
except where this spec says otherwise; budget, planning, and inline-mode work belong to
sub-projects 3–5.

Approach: inline — skip 3: the program design (§1 goal 1, §6 item 2) already chose a
native fold that drops the upstream-compatibility layer.

Reviewed by an independent Fable pass on 2026-09-11 (verdict: approve with changes);
all 22 findings are resolved below.

## 1. Decisions fixed here

- **Version** (owner, 2026-09-11): both manifests move 1.1.0 → **1.2.0**. The program is
  one 1.x line; the legacy-name table (§7) keeps old plans working.
- **Validator reference check** (owner, 2026-09-11): in scope (§7).
- **Dispatch problems become rulings, not stops** (owner, 2026-09-11): SDD keeps exactly
  its four stop classes; every folded "stop and ask" row becomes a logged, spoken ruling
  (§4 Dispatch).
- **The Codex report contract gains the checkpoint fields** (owner, 2026-09-11): the
  executor lane reports discovered issues and assumptions like a Claude implementer
  (§4 Codex contract).
- **Native rewrite, not append.** `dispatching-tiered-implementers` (736 lines) and
  `subagent-driven-development` (581) would exceed 1,300 lines appended. SDD's SKILL.md
  and the new writing-plans section are rewritten; arguments that exist only to coexist
  with upstream are dropped. Material that moves to on-demand files moves **verbatim**
  (§4 Moves).
- **Skill count.** Program design §4 says "skills/ (15)" but lists 16 names. After this
  sub-project there are 14 skills; sub-project 3 adds `handoff` and `resume-execution`
  for 16. The program design is not edited.

## 2. File layout

Deleted: `skills/assigning-implementers/`, `skills/dispatching-tiered-implementers/`.

| File | Change |
|---|---|
| `skills/writing-plans/SKILL.md` | New section "Assign an implementer to every task" (§3) |
| `skills/writing-plans/references/assigning-implementers.md` | New: rationale behind the assignment rules |
| `skills/subagent-driven-development/SKILL.md` | Native rewrite (§4) |
| `skills/subagent-driven-development/references/escalation.md` | New, verbatim move: split, reserve chain, model-unavailable substitution |
| `skills/subagent-driven-development/references/{implementer,task-reviewer,re-review}-prompt.md` | Seat names, criteria block, Progress line, two report sections (§4) |
| `reference/external-executor.md` | New, verbatim move: the whole Codex CLI lane, planning and execution (§4) |
| `reference/legacy-names.md` | New: translation table (§7) |
| `reference/native-codex.md` | "Claude rename compatibility" rule replaced by a pointer (§7) |
| `criteria/task-review.md` | `{#scope}` added, reciprocal ignore clauses, header names SDD (§6) |
| `criteria/codex-review-schema.json` | New: four-score schema (§6) |
| `scripts/codex-report-schema.json`, `scripts/codex-task-contract.md`, `scripts/run-codex-task.sh` | Two new report fields (§4 Codex contract) |
| `skills/using-superpowers/SKILL.md` | Routing lines point to writing-plans and SDD |
| `README.md` | Drop the deleted skill names; "Compatibility" becomes "Differences from upstream 6.3.0" |
| `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` | version 1.2.0 |
| `scripts/validate-repository.mjs`, `tests/repository-layout.test.mjs` | Reference check (§7) |
| `plugins/dr-superpowers/tests/criteria.test.sh` | Four ids and schema parity (§6) |
| `plugins/dr-superpowers/tests/run-codex-task.test.sh`, `tests/executor-recovery.test.sh` | New fields in fixtures and report (§4 Codex contract) |

Unchanged: the 19 agent files, `reference/ladder.md` (its fenced blocks are parsed by
`ladder.test.sh` and `lanes.test.sh`), `reference/external-task-recovery.md`, every other
script. Neither catalog entry carries a plugin version, so the catalogs are unchanged.

## 3. writing-plans: assigning implementers

`SKILL.md` gains a procedure section of about 60 lines, placed after Task Structure:

- Codex host: follow `native-codex.md`'s `codex-v2` selector instead of the Claude table.
- Score every task against `reference/ladder.md` (never restate its tables); apply
  Rule S before the assignment table; `spec = 3` routes to selecting-approaches; never
  buy a bigger model to cover a decomposition defect.
- Reserve agents are never an assignment output; only a human edit puts one in a plan.
- Run `detect-executors.sh` once per plan and offer usable executors; if none is usable,
  ask nothing and write the plan Claude-only. Record `> **External executors:** …` in
  the header and apply the lane gate — procedure in `reference/external-executor.md`
  §Planning.
- Task lines, in order, directly below `**Interfaces:**`: `**Implementer:**` (always,
  fully qualified), `**Executor:**` (lane gate passed), `**Evaluation:**` (always),
  `**Approach:**` (an approach decision was made; `inline` cites a skip number).
- Task headings keep `### Task N: <name>`.
- Check your work before saving: the existing list, kept as prose until sub-project 4
  moves it into `plan-lint` (R11).
- Retrofitting an existing plan is the same process; legacy names resolve through §7.
- A human may edit any `**Implementer:**` line; the Evaluation line stays.
- Under executing-plans the lines are inert.

The conditional "Implementer assignments … REQUIRED SUB-SKILL" header line is dropped:
SDD reads the lines natively. The `next-step` call in Execution Handoff stays.

`references/assigning-implementers.md` holds the why: file shapes vs instances, why the
Executor is a second line (free degradation), why an overridden Rule S pass is excluded
from the lane, why batched tasks stay on Claude, how a malformed heading corrupts the
previous task's brief, and how overrides keep their Evaluation line.

## 4. subagent-driven-development

### Structure

Top to bottom: host selection (Codex → `native-codex.md` `codex-v2` protocol), overview
and the four stop classes (unchanged), the `next-step` ending (unchanged), when to use,
process graph (updated for seats, R4, progress), setup, seats, task loop, final review,
finish, rationalizations, example.

### Seats (replace upstream's Model Selection section)

| Seat | Agent | Notes |
|---|---|---|
| Implementer | the task's `**Implementer:**` agent as `subagent_type` | No `model` argument: it would override the agent's pinned model while effort kept its frontmatter value |
| External implementer | `**Executor:**` line, via `reference/external-executor.md` | `**Implementer:**` is the fallback |
| Task reviewer | `judge-fable`; `judge-opus` when Fable is unavailable or declined, said aloud | Criteria file appended; three seats on risk 3 |
| Scoped re-review | general-purpose, explicit cheap-to-mid model | Returns the Progress line |
| Final review | general-purpose, most capable model | Plus the Codex round and judge verification |

"Always specify the model explicitly" applies to the general-purpose seats only.

### Setup

Adds: resolve legacy names (§7) in the plan header and `**Implementer:**` lines. The
pre-flight conflict scan is unchanged.

### Dispatch

Record BASE, then read `**Executor:**` first (lane in external-executor.md), else
`**Implementer:**`. A reserve name dispatches as written and is noted `reserve tier`.
`task-brief` prints `wrote <path>: <N> lines`; read the path out of it. When a task body
names a legacy skill, the dispatch's context line says legacy names resolve per
`reference/legacy-names.md` (the brief itself is never edited).

Dispatch problems are rulings — said aloud, logged as `Ruling: <what> — <why> — <cost
if wrong>`, never a silent fallback and never a stop:

| Problem | Ruling |
|---|---|
| No `**Implementer:**` line | Score at dispatch; assigned line notes `scored at dispatch` |
| Name in neither the assignment nor the reserve table, after legacy translation | Score at dispatch and dispatch the scored agent |
| Implementer's model unavailable | Same effort one model down; where none exists (any Sonnet or Haiku agent), dispatch the ladder successor |
| Fable unavailable inside an automatically entered reserve chain | `Task <N>: BLOCKED` (unchanged: the Opus rungs already failed) |
| `**Executor:**` names a pair outside `codex-assignment` / `codex-timeout`, or the wrapper refuses it with exit 2 before launch | Dispatch the `**Implementer:**` agent (HANDBACK) |

### Review

The task-reviewer template carries the criteria block natively: invariant material
first, criteria block last (a shared prefix for the K=3 path), `[PLUGIN_ROOT]` expanded
to the resolved plugin path. Scores are additive to the spec and quality verdicts, which
still drive the fix loop; bands 1–8 fail (joins the trigger), 9–13 adjudicated, 14–20
pass. A judge that drops the verdicts is re-dispatched. The judge is never told which
lane produced the diff. Risk 3: three independent seats, average per criterion; a spread
above 6 on any criterion means the controller reads the diff. One seat is Codex when
usable (external-executor.md), else a third judge; a Codex seat that times out (124) is
replaced by a third Claude judge, never an average of two.

### Fix loop

- Rounds 1–3 resume the implementer, subject to R4. Rounds 4–5 dispatch fresh on the
  ladder's successor rung with the framing "A prior implementer attempted this task N
  times; you own it now. Read the report file for what was tried."
- Progress: the re-reviewer returns `**Progress:** <1-20>`; if round N ≤ round N-1,
  escalate at the start of the next round — never before round 3, never later than 4.
- None of the three escalation points (rounds 4–5, the BLOCKED handler, a round-3 stall)
  applies to an external task; it leaves the lane by HANDBACK (external-executor.md).
- BLOCKED report: context problem → same agent with context; reasoning problem →
  successor rung, logged as a new assigned line (§5).
- Top rung `impl-opus-high` exhausted → split once (Rule S on each half); a half that
  exhausts again enters the reserve at `impl-opus-xhigh`, said aloud; `impl-fable-max`
  exhausted → `Task <N>: BLOCKED`. Split and reserve entries are `Ruling:` lines.
- The breaker and its adjudication rules are unchanged.

**R4 — resume or re-dispatch by cache state** (Claude implementers, rounds 1–3). One rule
replaces SDD's "harness cannot send another message → fresh":

- Resume only when all hold: the harness can message the live agent, its agent id is
  still in context (compaction loses it; then the answer is always fresh), and either
  `t1 − t0 < 300` seconds or its context is under ~100k tokens.
- `t0`: `date +%s` in the same Bash call as the `review-package` run that follows the
  implementer's return. `t1`: `date +%s` in a dedicated Bash call immediately before the
  resume-or-fresh decision.
- Context: the token total the Agent tool reports for the implementer (inference; the
  plan verifies it on one real dispatch). If absent, the time test decides alone.
- Otherwise dispatch a fresh copy of the same agent with the brief, the report file, and
  the findings. The ledger records `fresh (<why>)`. This is not an escalation.
- Never dispatch `fork` implementers. Not applied to Codex resumes (separate
  subscription) or rounds 4–5 (already fresh).

### Templates

Each template names its seat instead of `general-purpose`. The implementer report gains
`## Discovered issues (not fixed)` and `## Assumptions made` ("None" when empty). The
re-review output gains the Progress line.

### Codex contract

- `scripts/codex-report-schema.json` gains `discovered_issues` and `assumptions`, each an
  array of strings, both required (the schema stays fully strict).
- `scripts/codex-task-contract.md` describes both fields: problems noticed and not fixed;
  assumptions made where the brief was silent. Empty arrays when there are none.
- `scripts/run-codex-task.sh` writes `## Discovered issues (not fixed)` and
  `## Assumptions made` into the human report after `## Summary`, one bullet per item or
  "None", parsed leniently like `summary` (`// []`).
- Tests: `run-codex-task.test.sh` asserts both sections appear in a DONE report;
  `executor-recovery.test.sh`'s stub fixture gains both fields.

### Final review

Run the general-purpose review with the ledger's deferred-minor, parked, and
`discovered:` fields; run the Codex round (external-executor.md) when usable, else — or
on a 124 timeout — skip it and say so; dedupe into one list tagged `claude` / `codex` /
`both`; one judge dispatch verifies every finding (CONFIRMED / REJECTED with evidence);
confirmed findings enter the existing single fix wave and scoped re-review.

### Moves

`reference/external-executor.md` and `references/escalation.md` are **verbatim moves**
from `dispatching-tiered-implementers/SKILL.md`, including every table. Allowed edits
only: "superpowers'" → "SDD's", "this skill" → "this reference" or "SDD", link paths,
removal of sentences that argue against an upstream instruction, and the Dispatch table
above replacing stop-and-ask rows. The plan carries the full new text of SDD's SKILL.md,
the writing-plans section, and the three templates — no section outlines for an
implementer to re-author.

`reference/external-executor.md` sections: Planning (roster offer, header line, lane
gate from `ladder.md`'s `gate` block, batched tasks excluded), Dispatch, When a run
fails, Resuming a Codex task, When the resume itself fails, Risk-3 Codex seat (command
with `criteria/codex-review-schema.json`), Final-review Codex round, Failure rows.

### Disposition of dispatching-tiered-implementers

| Section | Goes to |
|---|---|
| Select the host first | SDD host section |
| Announce; What changes and what does not | Dropped — upstream-coexistence framing |
| The superpowers instructions this supersedes | SDD Seats: one-sentence no-`model` rule; argument dropped |
| Dispatch a task (steps 1–5, reserve handling, `task-brief` output note) | SDD Dispatch |
| Dispatch a task: verb-ownership rule | Dropped — SDD owns the ledger (§5 keeps the verbs) |
| Dispatch an external executor | external-executor.md Dispatch |
| When a run fails | external-executor.md |
| Resuming a Codex task; When the resume itself fails | external-executor.md; the "supersedes rounds 4–5" argument becomes the one-line HANDBACK rule |
| Escalate (three points, clause on the fix-round line) | SDD Fix loop |
| Escalate: split, reserve entry, reserve exhaustion | SDD Fix loop (rule) + escalation.md (detail) |
| Escalate: last-line rationale | Replaced by the recovery rule in §5 |
| Score the review | SDD Review + task-reviewer template |
| Repeated evaluation on risk-3 tasks | SDD Review; Codex seat command and schema to external-executor.md |
| Progress | SDD Fix loop + re-review template |
| Failure modes table | Claude rows to SDD Dispatch table / escalation.md; Codex rows to external-executor.md |
| Model-unavailable substitution prose | escalation.md (amended by the Dispatch table) |
| The final whole-branch review | SDD Final review; Codex command to external-executor.md; "supersedes a written promise" dropped |
| `next-step` ending on stop rows | SDD (already there) |

**Must-keep rules** the section rows do not name. The plan checks each by name:

| Rule (source line in dispatching SKILL.md) | Target |
|---|---|
| Judge is never told which lane produced the diff (227-229) | SDD Review + external-executor.md Dispatch |
| A round-3 stall pulls the Codex HANDBACK to round 3, never later (329-333) | external-executor.md Resuming |
| No escalation point applies to an external task (405-407) | SDD Fix loop |
| Risk-3 Codex seat 124 → third Claude judge, never average two (566-567) | SDD Review + external-executor.md |
| Final-review Codex round 124 → skip and say so (709-711) | SDD Final review + external-executor.md |
| `note=codex-may-still-be-running` cleared before retry (286-289) | external-executor.md |
| Second `NEEDS_CONTEXT` is a capability failure (291-294) | external-executor.md |
| Two-failure budget counts initial runs only (295-299, 356-359) | external-executor.md |
| Exit-0 empty diff vs `base==head` with a dirty tree (248-254) | external-executor.md |
| Fix-round empty diff is a position; two in a row → HANDBACK (369-377) | external-executor.md |
| `BASH_MAX_TIMEOUT_MS` foreground note (166-169) | external-executor.md |
| Same `--task-id` across runs; write-set from plan paths; report path must be ignored (200-211) | external-executor.md |
| Thread id must reach the ledger (223-225) | external-executor.md + §5 grammar |
| Schema written outside the worktree → replaced by the shipped schema (580-588) | external-executor.md |
| Fresh-implementer framing for rounds 4–5 (SDD SKILL.md 394-399) | SDD Fix loop |
| If no executor is usable, ask nothing (assigning SKILL.md 98-99) | writing-plans + external-executor.md Planning |

### Disposition of assigning-implementers

| Section | Goes to |
|---|---|
| Select the host first | writing-plans section, first bullet |
| When this applies | writing-plans (inert under executing-plans) |
| Score every task; Rule S; resist a bigger model | writing-plans (rule) + references (why) |
| Reserve agents are never an assignment output | writing-plans |
| Offer an external executor, lane gate | external-executor.md Planning; pointer in writing-plans |
| Write the assignment (order, format, heading form) | writing-plans (rule) + references (why) |
| Amend the plan header | Dropped — SDD reads the lines natively; the `External executors` header line stays |
| Check your work | writing-plans, until plan-lint |
| Overriding | writing-plans (one line) + references |

## 5. Ledger grammar (R1)

SDD owns every ledger line. Existing verbs keep their exact spelling (`implementer`,
`complete`, `fix round`, `minor (deferred)`, `parked`, `BLOCKED`, `Ruling:`).

```
# SDD ledger — plan: <path>
Task <N>: implementer <agent> (assigned; base <sha7>[; reserve tier][; scored at dispatch][; executor codex <m>/<e>, thread <id>][; escalated from <old>: BLOCKED][; <substitution>])
Task <N>: fix round R/5 (X addressed, Y open — <one-liners>; commits a..b[; progress p -> q]; resumed | fresh (<why>) | escalated <old> -> <new> | HANDBACK to <agent>)
Group <a>-<b>: review round R/5 (<same fields>)
Task <N>: minor (deferred): <one-liner>
Task <N>: parked — <finding> — Ruling: <why the code stands>
Task <N>: Ruling: <finding> — <what was decided and why>
Task <N>: BLOCKED — <agent> exhausted — <what a human must decide>
Task <N>: complete (commits a..b, review clean | K parked[; scores spec s / scope c / verification v / quality q[, K=3]]) — done: …; verified: <command → result>; remaining: none | <parked>; discovered: none | …; assumptions: none | …
Ruling: <what> — <why> — <cost if wrong>
```

- Every task gets its own assigned line and its own complete line, including tasks
  reviewed as a batch. Batches are contiguous task ranges so `Group <a>-<b>` names them;
  only a batch's review rounds log on its Group line.
- `; scores …` is present whenever a judge scored the task; it is optional in the
  grammar so inline mode (sub-project 5) uses the same line.
- The checkpoint after `—` comes from the report's two sections — the Claude
  implementer's or the Codex wrapper's. A batch report's sections are copied onto each
  task's complete line, attributed per task where the report names one.
- A translation ruling has a fixed form:
  `Ruling: translated <old> -> <new> — legacy plugin name — none`.

**Recovery.** For task N, take the last line in file order among its `Task <N>:` lines
and any `Group` line covering N, stepping over `minor (deferred)`, `parked`,
`Task <N>: Ruling:`, and bare `Ruling:` lines. Then:

| Last line | Action |
|---|---|
| `complete` | Done; never re-dispatch |
| `BLOCKED` | Terminal; never re-dispatch; handled as a stop (SDD's fourth class) and named in the final message |
| `fix round R/5` or `review round R/5`, R < 5 | Resume the loop at round R+1 (R4 makes it fresh after compaction) |
| `fix round 5/5` or `review round 5/5` | Go to the breaker and adjudicate |
| `implementer … (assigned …)` | If the report file has a status and `git log <base>..HEAD` is non-empty, review; otherwise dispatch the same agent fresh |
| none | Not started |

1.1.0 ledgers: an assigned line without `base` takes the previous task's complete-line
head (or the branch's merge base for Task 1); an old `(scored at dispatch)` line reads
as assigned.

Mode switches (subagent ↔ inline) happen only at a task boundary where every earlier
task is complete, recorded as a `Ruling:`.

## 6. Scope criterion and four-score schema

`criteria/task-review.md` gains **Scope Hygiene {#scope}**. Where to look: every diff
hunk that does not trace to a brief requirement. HIGH: every changed line traces to the
brief, and orphans this change created (imports, helpers made unused) are removed. LOW:
reformatting or style drift on untouched lines, unrelated comment edits, adjacent
refactors, deletion of pre-existing dead code nobody asked for, orphans this change
left. Ignore missing requirements and unrequested features (`spec`), test evidence
(`verification`), correctness (`quality`).

Reciprocal ignore clauses: `{#spec}` adds "Ignore style drift, comment edits, adjacent
refactors, and orphans; Scope Hygiene owns those." `{#quality}` adds "Ignore whether a
hunk was requested; Spec Compliance and Scope Hygiene own that." The file stays
ASCII-only with 4 pinned ids. The Verification Scores block carries four scores; bands
unchanged.

`criteria/codex-review-schema.json`: fully strict JSON Schema — `additionalProperties:
false` and every property required, at the top level and in the nested `findings` item.
Properties: `spec`, `scope`, `verification`, `quality` (integers 1–20); `spec_verdict`
(`compliant` | `issues`); `task_quality` (`approved` | `needs_fixes`); `findings` (array
of `{severity: Critical|Important|Minor, file, line, summary}`); `cannot_verify` (array
of strings). Plan-time check against the Codex docs, no paid call: whether
`minimum`/`maximum` are accepted under strict output; if not, the scores use an integer
`enum` 1..20.

`tests/criteria.test.sh`: line 57's contract becomes `quality scope spec verification`.
A new check asserts that
`jq -r '.properties | to_entries[] | select(.value.type=="integer") | .key'` over the
schema, sorted, equals task-review.md's ids.

## 7. Legacy names and the validator

`reference/legacy-names.md` resolves by suffix, whatever old prefix precedes it
(`superpowers:`, `dcc-superpower-companions:`, or `dr-superpowers:`):

| Suffix | Resolves to |
|---|---|
| One of the 13 copied skills, `selecting-approaches`, or one of the 19 agents | `dr-superpowers:` + the same suffix |
| `dispatching-parallel-agents` | No skill: dispatch independent agents in one message |
| `assigning-implementers` | `dr-superpowers:writing-plans`, "Assign an implementer to every task" |
| `dispatching-tiered-implementers` | `dr-superpowers:subagent-driven-development` |

Rule: translate at read time, never rewrite the plan, log one translation ruling (§5)
per distinct name. A suffix not in the table stops and asks. Readers: SDD setup;
writing-plans when retrofitting. `native-codex.md`'s "Claude rename compatibility"
sentence ("translate … when its suffix names an existing bundled agent file. Reject
unknown suffixes.") is replaced with "translate per `legacy-names.md`; reject suffixes
not in that table"; its conversion rules stay.

**Literal prefixes.** Only `reference/legacy-names.md` may contain the literal
`superpowers:` (without the `dr-` prefix) or `dcc-superpower-companions:`; the existing
check at `validate-repository.mjs:85-86` enforces this. Every other file — SDD,
writing-plans, native-codex.md, the README — refers to them indirectly (e.g. "the old
plugin name followed by a colon").

**Reference check** in `scripts/validate-repository.mjs`: a line-based scan of every file
in the four maintained plugin directories (not fence-aware, unlike the bundled-link
check) with `/dr-superpowers:([a-z0-9-]+)/g`. A match whose next character is `<` is a
template placeholder and is skipped. Every other captured name must match
`plugins/dr-superpowers/skills/<name>/` or `plugins/dr-superpowers/agents/<name>.md`.
Exempt: `reference/legacy-names.md`. `tests/repository-layout.test.mjs` gains one
rejection case for a dangling name.

## 8. Verification

Program design §7: `node scripts/validate-repository.mjs`, `node scripts/test-all.mjs`
(the known `rg`-missing failure in `ui-discovery.test.mjs` is environmental),
`claude plugin validate` on the marketplace and every Claude plugin; bounded timeouts;
every started process cleaned up.

## 9. Out of scope

Plan header block, plan-lint, plan review, amendments, R3, Execution-line rules, and the
Karpathy reinforcement blocks (sub-project 4); context-size, repo-audit, handoff,
resume-execution, session-budget.md (3); executing-plans rewrite (5). The two new
implementer-report sections are program R12's last bullet, brought forward because R1's
checkpoint needs them; sub-project 4 does not re-add them. The
`plugins/darkmem-resume/` directory is the owner's live work: never touched or committed.

## 10. Risks

- The rewrite can drop a load-bearing rule. Mitigation: verbatim moves, the disposition
  and must-keep tables in §4, and the full new text in the plan.
- The Agent tool's token figure is unverified; R4 falls back to the time test.
- Codex's handling of numeric bounds under strict output is unverified; §6 names the
  fallback.
- In-flight 1.1.0 ledgers stay readable (§5 compatibility rules); a 1.1.0 plan's
  dispatching header line resolves through legacy-names.md.
