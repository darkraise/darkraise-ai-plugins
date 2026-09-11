# dr-superpowers 1.2.0 — fold the companion skills in (sub-project 2 design)

Date: 2026-09-11. Status: approved design for sub-project 2 of the program design
`2026-09-11-dr-superpowers-fork-design.md` (§6 item 2). Scope rule: behaviour unchanged
except where this spec says otherwise; budget, planning, and inline-mode work belong to
sub-projects 3–5.

Approach: inline — skip 3: the program design (§1 goal 1, §6 item 2) already chose a
native fold that drops the upstream-compatibility layer.

## 1. Decisions fixed here

- **Version** (owner, 2026-09-11): both manifests move 1.1.0 → **1.2.0**. The program is
  one 1.x line; the legacy-name table (§7) keeps old plans working.
- **Validator reference check** (owner, 2026-09-11): in scope (§7).
- **Native rewrite, not append.** `dispatching-tiered-implementers` (736 lines) and
  `subagent-driven-development` (581) would exceed 1,300 lines appended. Arguments that
  exist only to coexist with upstream are dropped; rare paths move to on-demand reference
  files.
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
| `skills/subagent-driven-development/references/escalation.md` | New: split, reserve chain, model-unavailable substitution |
| `skills/subagent-driven-development/references/{implementer,task-reviewer,re-review}-prompt.md` | Seat names, criteria block, Progress line, two report sections (§4) |
| `reference/external-executor.md` | New: the whole Codex CLI lane, planning and execution (§4) |
| `reference/legacy-names.md` | New: translation table (§7) |
| `reference/native-codex.md` | "Claude rename compatibility" points to legacy-names.md |
| `criteria/task-review.md` | `{#scope}` added, header names SDD (§6) |
| `criteria/codex-review-schema.json` | New: four-score schema (§6) |
| `skills/using-superpowers/SKILL.md` | Routing lines point to writing-plans and SDD |
| `README.md` | Drop the deleted skill names; "Compatibility" becomes "Differences from upstream 6.3.0" |
| `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` | version 1.2.0 |
| `scripts/validate-repository.mjs`, `tests/repository-layout.test.mjs` | Reference check (§7) |
| `plugins/dr-superpowers/tests/criteria.test.sh` | Four ids and schema parity (§6) |

Unchanged: the 19 agent files, `reference/ladder.md` (its fenced blocks are parsed by
`ladder.test.sh` and `lanes.test.sh`), `reference/external-task-recovery.md`, every
script. The catalog entries change only if one carries a dr-superpowers version.

## 3. writing-plans: assigning implementers

`SKILL.md` gains a procedure section of about 60 lines, placed after Task Structure:

- Codex host: follow `native-codex.md`'s `codex-v2` selector instead of the Claude table.
- Score every task against `reference/ladder.md` (never restate its tables); apply
  Rule S before the assignment table; `spec = 3` routes to selecting-approaches.
- Reserve agents are never an assignment output; only a human edit puts one in a plan.
- Run `detect-executors.sh` once per plan, offer usable executors, record
  `> **External executors:** …` in the header, and apply the lane gate —
  procedure in `reference/external-executor.md` §Planning.
- Task lines, in order, directly below `**Interfaces:**`: `**Implementer:**` (always,
  fully qualified), `**Executor:**` (lane gate passed), `**Evaluation:**` (always),
  `**Approach:**` (an approach decision was made; `inline` cites a skip number).
- Task headings keep `### Task N: <name>`.
- Check your work before saving: the existing list, kept as prose until sub-project 4
  moves it into `plan-lint` (R11).
- Retrofitting an existing plan is the same process; legacy names resolve through §7.
- Under executing-plans the lines are inert.

The conditional "Implementer assignments … REQUIRED SUB-SKILL:
dispatching-tiered-implementers" header line is dropped: SDD reads the lines natively.
The `next-step` call in Execution Handoff stays.

`references/assigning-implementers.md` holds the why: file shapes vs instances, why the
Executor is a second line (free degradation), why an overridden Rule S pass is excluded
from the lane, why batched tasks stay on Claude, how a malformed heading corrupts the
previous task's brief, and how overrides keep their Evaluation line.

## 4. subagent-driven-development: native rewrite

Structure, top to bottom: host selection (Codex → `native-codex.md` `codex-v2`
protocol), overview and the four stop classes (unchanged), the `next-step` ending
(unchanged), when to use, process graph (updated for seats, R4, progress), setup,
seats, task loop, final review, finish, rationalizations, example.

**Seats** replace upstream's Model Selection section:

| Seat | Agent | Notes |
|---|---|---|
| Implementer | the task's `**Implementer:**` agent as `subagent_type` | No `model` argument: it would override the agent's pinned model while effort kept its frontmatter value |
| External implementer | `**Executor:**` line, via `reference/external-executor.md` | `**Implementer:**` is the fallback |
| Task reviewer | `judge-fable`; `judge-opus` when Fable is unavailable or declined, said aloud | Criteria file appended; three seats on risk 3 |
| Scoped re-review | general-purpose, explicit cheap-to-mid model | Returns the Progress line |
| Final review | general-purpose, most capable model | Plus the Codex round and judge verification |

"Always specify the model explicitly" applies to the general-purpose seats only.

**Setup** adds: resolve legacy names (§7) in the plan header and `**Implementer:**`
lines. The pre-flight conflict scan is unchanged.

**Dispatch.** Read `**Executor:**` first (lane in external-executor.md), else
`**Implementer:**`. A reserve name dispatches as written and is noted `reserve tier`. A
missing line is scored at dispatch and noted `scored at dispatch`. An unknown name stops
and asks. `task-brief` prints `wrote <path>: <N> lines`; read the path out of it.

**Review.** The task-reviewer template carries the criteria block natively: invariant
material first, criteria block last (a shared prefix for the K=3 path), `[PLUGIN_ROOT]`
expanded to the resolved plugin path. Scores are additive to the spec and quality
verdicts, which still drive the fix loop; bands 1–8 fail (joins the trigger), 9–13
adjudicated, 14–20 pass. A judge that drops the verdicts is re-dispatched. Risk 3: three
independent seats, average per criterion, and a spread above 6 on any criterion means
the controller reads the diff. One seat is Codex when usable (external-executor.md),
else a third judge.

**Fix loop.** Rounds 1–3 resume, subject to R4 below. Progress: the re-reviewer returns
`**Progress:** <1-20>`; if round N ≤ round N-1, escalate at the start of the next round,
never before round 3 and never later than round 4. Rounds 4–5 escalate one rung per
`ladder.md`. BLOCKED: context problem → same agent with context; reasoning problem →
successor rung. Top rung `impl-opus-high` exhausted → split once (Rule S on each half);
a half that exhausts again enters the reserve at `impl-opus-xhigh`, said aloud;
`impl-fable-max` exhausted → BLOCKED. Split and reserve entries are `Ruling:` lines.
Details and the model-unavailable substitution rules live in `references/escalation.md`.
The breaker and its adjudication rules are unchanged.

**R4 — resume or re-dispatch by cache state** (Claude implementers, rounds 1–3):

- Resume only when the implementer returned under 5 minutes ago, or its context is under
  ~100k tokens. Otherwise dispatch a fresh copy of the same agent with the brief, the
  report file, and the findings. This is not an escalation.
- Time: add `date +%s` to the Bash call already made after the implementer returns
  (`review-package`) and to the first Bash call of the fix round.
- Context: the token total the Agent tool reports for the implementer (inference; the
  plan verifies it on one real dispatch). If absent, the time test decides alone.
- Never dispatch `fork` implementers.
- Not applied to Codex resumes (separate subscription) or rounds 4–5 (already fresh).

**Templates.** Each template names its seat instead of `general-purpose`. The implementer
report gains `## Discovered issues (not fixed)` and `## Assumptions made`. The re-review
output gains the Progress line.

**Final review.** Run the general-purpose review with the ledger's deferred-minor,
parked, and `discovered:` fields; run the Codex round (external-executor.md) when usable,
else say it was skipped; dedupe into one list tagged `claude` / `codex` / `both`; one
judge dispatch verifies every finding (CONFIRMED / REJECTED with evidence); confirmed
findings enter the existing single fix wave and scoped re-review.

**`reference/external-executor.md`** sections: Planning (roster offer, header line, lane
gate from `ladder.md`'s `gate` block, batched tasks excluded), Dispatch (roster guard,
background wrapper run and why, ledger thread id, exclusive linked worktree,
external-task-recovery.md), When a run fails (exit codes, failure table, `## Codex
error`, exit-2 recovery), Resuming (rounds 1–3 resume the thread, per-round report
paths, round 4 is HANDBACK), When the resume fails, Risk-3 Codex seat (command with
`criteria/codex-review-schema.json`), Final-review Codex round, Failure rows.

### Disposition of dispatching-tiered-implementers

| Section | Goes to |
|---|---|
| Select the host first | SDD host section |
| Announce; What changes and what does not | Dropped — upstream-coexistence framing |
| The superpowers instructions this supersedes | SDD Seats: one-sentence no-`model` rule; argument dropped |
| Dispatch a task (steps 1–5, reserve handling, `task-brief` output note) | SDD Dispatch |
| Dispatch a task: verb-ownership rule | Dropped — SDD owns the ledger (§5 grammar keeps the verbs) |
| Dispatch an external executor | external-executor.md Dispatch |
| When a run fails | external-executor.md |
| Resuming a Codex task; When the resume itself fails | external-executor.md; the "supersedes rounds 4–5" argument becomes the one-line HANDBACK rule |
| Escalate (three points, clause on the fix-round line) | SDD fix loop |
| Escalate: split, reserve entry, reserve exhaustion | SDD fix loop (rule) + escalation.md (detail) |
| Escalate: last-line rationale | Replaced by the recovery rule in §5 |
| Score the review | SDD Review + task-reviewer template |
| Repeated evaluation on risk-3 tasks | SDD Review; Codex seat command and schema to external-executor.md |
| Progress | SDD fix loop + re-review template |
| Failure modes table | Claude rows to SDD / escalation.md; Codex rows to external-executor.md |
| Model-unavailable substitution prose | escalation.md |
| The final whole-branch review | SDD Final review; Codex command to external-executor.md; "supersedes a written promise" dropped |
| `next-step` ending on stop rows | SDD (already there) |

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

SDD owns every ledger line. Existing verbs keep their exact spelling so a 1.1.0 ledger
still recovers.

```
# SDD ledger — plan: <path>
Task <N>: implementer <agent> (assigned[; reserve tier][; executor codex <m>/<e>, thread <id>][; <substitution>])
Task <N>: fix round R/5 (X addressed, Y open — <one-liners>; commits a..b[; progress p -> q]; resumed | fresh (<why>) | escalated <old> -> <new>)
Group <a>-<b>: review round R/5 (<same fields>)
Task <N>: minor (deferred): <one-liner>
Task <N>: parked — <finding> — Ruling: <why>
Task <N>: complete (commits a..b, review clean | K parked; scores spec s / scope c / verification v / quality q[, K=3]) — done: …; verified: <command → result>; remaining: none | <parked>; discovered: none | …; assumptions: none | …
Ruling: <what> — <why> — <cost if wrong>
```

- Every task gets its own complete line, including tasks reviewed as a batch.
- Batches are contiguous task ranges so `Group <a>-<b>` names them; a batch's fix rounds
  log on its Group line.
- The checkpoint after `—` comes from the implementer report's two new sections.
- Recovery reads a task's last `Task <N>:` or covering `Group` line: complete → done;
  fix round → resume at the next round; assigned → dispatched, not yet reviewed.
  `Ruling:` lines are stepped over.
- Mode switches (subagent ↔ inline) happen only at a task boundary where every earlier
  task is complete, recorded as a `Ruling:`.

## 6. Scope criterion and four-score schema

`criteria/task-review.md` gains **Scope Hygiene {#scope}**. Where to look: every diff
hunk that does not trace to a brief requirement. HIGH: every changed line traces to the
brief, and orphans this change created (imports, helpers made unused) are removed. LOW:
reformatting or style drift on untouched lines, unrelated comment edits, adjacent
refactors, deletion of pre-existing dead code nobody asked for, orphans this change left.
Ignore missing requirements and unrequested features (`spec`), test evidence
(`verification`), correctness (`quality`). `{#spec}` keeps features and requirements.
File stays ASCII-only.

The Verification Scores block and the complete line carry four scores; bands unchanged.

`criteria/codex-review-schema.json`: strict JSON Schema (`additionalProperties: false`,
all properties required — inference about Codex structured output, confirmed from Codex
docs at plan time with no paid call). Properties: `spec`, `scope`, `verification`,
`quality` (integers 1–20); `spec_verdict` (`compliant` | `issues`); `task_quality`
(`approved` | `needs_fixes`); `findings` (array of `{severity: Critical|Important|Minor,
file, line, summary}`); `cannot_verify` (array of strings).

`tests/criteria.test.sh`: line 57's contract becomes `quality scope spec verification`;
a new jq check asserts the schema's score property names equal task-review.md's ids.

## 7. Legacy names and the validator

`reference/legacy-names.md`:

| Old name | Resolves to |
|---|---|
| `superpowers:<skill>` (the 13 copied skills) | `dr-superpowers:<skill>` |
| `superpowers:dispatching-parallel-agents` | No skill: dispatch independent agents in one message |
| `dcc-superpower-companions:<agent>` (19), `dcc-superpower-companions:selecting-approaches` | `dr-superpowers:` + same name |
| `dcc-superpower-companions:assigning-implementers`, `dr-superpowers:assigning-implementers` | `dr-superpowers:writing-plans`, "Assign an implementer to every task" |
| `dcc-superpower-companions:dispatching-tiered-implementers`, `dr-superpowers:dispatching-tiered-implementers` | `dr-superpowers:subagent-driven-development` |

Rule: translate at read time, never rewrite the plan, record one
`Ruling: translated <old> -> <new>` per distinct name. An unknown suffix stops and asks
(matches `native-codex.md`). Readers: SDD setup; writing-plans when retrofitting.

`scripts/validate-repository.mjs`: every `dr-superpowers:<name>` in the four maintained
plugin directories must match `plugins/dr-superpowers/skills/<name>/` or
`plugins/dr-superpowers/agents/<name>.md`. Exempt: `reference/legacy-names.md`. A match
followed by `<` is a template placeholder and is skipped. `tests/repository-layout.test.mjs`
gains one rejection case for a dangling name.

## 8. Verification

Program design §7: `node scripts/validate-repository.mjs`, `node scripts/test-all.mjs`
(the known `rg`-missing failure in `ui-discovery.test.mjs` is environmental),
`claude plugin validate` on the marketplace and every Claude plugin; bounded timeouts;
every started process cleaned up.

## 9. Out of scope

Plan header block, plan-lint, plan review, amendments, R3, Execution-line rules, and the
Karpathy reinforcement blocks (sub-project 4); context-size, repo-audit, handoff,
resume-execution, session-budget.md (3); executing-plans rewrite (5). The
`plugins/darkmem-resume/` directory is the owner's live work: never touched or committed.

## 10. Risks

- The rewrite can drop a load-bearing rule from 736 lines. Mitigation: the disposition
  tables in §4; the plan checks coverage row by row.
- The Agent tool's token figure is unverified; R4 falls back to the time test.
- Codex's strict-schema requirement is inferred; confirmed at plan time.
- In-flight 1.1.0 ledgers stay readable because verb spellings are unchanged; a 1.1.0
  plan's dispatching header line resolves through legacy-names.md.
