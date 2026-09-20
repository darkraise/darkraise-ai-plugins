# A lane-agnostic executor interface

**Status:** approved design, not yet planned
**Sub-project:** A of two. B is `dr-opencode`, the second executor instance.
**Forced by:** docs/superpowers/notes/2026-09-20-dr-opencode-spec-review.md
**Superseded design:** docs/superpowers/specs/2026-09-20-dr-opencode-executor-design.md
**Register:** docs/superpowers/registers/2026-09-20-opencode-executor.md
**Owner decisions:** 2026-09-20 brainstorming session

## 1. Purpose

dr-superpowers offloads plan tasks to one external CLI. The intent was always
an *external executor lane* with Codex as its occupant, but the implementation
names Codex directly in the lint rules, the session library, the ruling kinds,
the roster and the skill prose. Two review seats, asked to judge a design that
proposed adding a second executor beside it, independently concluded that no
second executor can be added without first separating the two.

This sub-project performs that separation. It adds no executor. Its deliverable
is that adding one becomes a configuration change plus a wrapper, rather than a
rewrite of eight files.

**It has no user-visible benefit on its own.** That is accepted: the payoff is
sub-project B, and the cost of skipping it is a second hardcoded lane beside
the first.

## 2. What forced it

From the merged review findings, the Critical items this sub-project answers:

| # | Finding | Evidence |
|---|---|---|
| 1 | `plan-lint` requires every `**Executor:**` line to name the `codex-assignment` rung and the header to say `codex`, so any other executor is two ERRORs and writing-plans demands zero | `scripts/plan-lint:272-279` |
| 2 | `lib/codex-session.sh` hardcodes one directory and the `usable/review/lane` fields; a second lane's rate-limit mark-off would switch off Codex's review seats | `scripts/lib/codex-session.sh:13,24,41` |
| 5 | `opencode-empty-diff` is rejected: the ruling allowlist is Codex-specific | `scripts/review-route:187` |
| 7 | The surfaces that actually drive dispatch — writing-plans, delegated-task, the ledger grammar — are Codex-specific prose | skill files |
| 8 | Inline mode implements exactly the band a cheap executor would serve, so the lane would never fire in an inline plan | `skills/executing-plans/SKILL.md:164` |
| 9 | `detect-executors.sh`'s plugin branch is `if [ "$id" = codex ]`, with the locator, the client and three `/codex:setup` remedies hardcoded | `scripts/detect-executors.sh:40,75-87` |

One claim from the superseded spec survived review and is load-bearing here:
`lib/task-state.sh`, `lib/task-execution.sh` and `scripts/repo-audit` contain no
Codex reference at all. The durable task record, snapshotting, scoped staging
and commit recovery are already lane-agnostic and are not touched.

## 3. Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | A registry of per-executor data files, with each executor keeping its own gate and locator script | Auth models genuinely differ — Codex authenticates through a plugin app-server, another executor may use an API key. Forcing one gate script would be false generality. What must be shared is the *state*, not the probe |
| D2 | Inline mode offloads cheap tasks downward, mirroring its upward delegation | An executor lane whose band is exactly what inline mode keeps for itself can never fire. Chosen by the owner over restricting the lane to subagent plans |
| D3 | `executor-empty-diff` replaces `codex-empty-diff`, old name still accepted | The `--kind risk3` precedent in `run-codex-review.sh`. A hard rename breaks in-flight plans for no gain |
| D4 | A fixture executor id, used only by the test suites | It proves the abstraction supports a second executor without any second CLI being installed, so B inherits a tested seam instead of discovering one |
| D5 | Codex's observable behaviour is unchanged except where §9 and §10 say otherwise | This is a refactor. Every deviation is named, and everything unnamed must stay byte-identical in effect |

## 4. The registry

`reference/executors/<id>.json`, one per executor. The Codex entry:

```json
{
  "id": "codex",
  "locator": "scripts/codex-plugin",
  "gate": "scripts/codex-gate",
  "wrapper": "scripts/run-codex-task.sh",
  "reference": "reference/executor-lane.md",
  "session_dir": "codex-sessions",
  "session_dir_env": "DR_CODEX_SESSION_DIR",
  "surfaces": ["review", "lane"],
  "blocks": {
    "gate": "gate",
    "assignment": "codex-assignment",
    "successor": "codex-successor",
    "timeout": "codex-timeout",
    "judge": "codex-judge"
  },
  "remedy": "/codex:setup",
  "reasons": {
    "not_enabled": "the codex plugin is not enabled in this profile",
    "logged_out": "the codex plugin is installed but not logged in; run /codex:setup",
    "probe_failed": "the codex plugin auth probe failed; run /codex:setup"
  }
}
```

Every existing name is preserved, including the ladder block literally called
`gate` and the environment variable `DR_CODEX_SESSION_DIR`. The registry
records what is, so that nothing about Codex has to move for the abstraction to
exist. A second executor names its own blocks and directory.

`scripts/executors` is the only reader:

| Invocation | Output |
|---|---|
| `executors list` | one id per line, for every readable registry file |
| `executors get <id> <dotted.key>` | one field, exit 1 when the id or key is absent |
| `executors path <id> <key>` | a field holding a plugin-relative path, resolved absolute |

Nothing else parses the registry. A script that needs three fields calls it
three times; these are local process spawns on paths already taken, and one
parser is worth more than the spawns cost.

An id is `[a-z][a-z0-9-]*`. An unknown id anywhere is an error naming
`executors list`, never a silent skip: a silent skip is how a lane disappears
without saying so, which is the failure mode `detect-executors.sh` was already
written to avoid.

## 5. Session state

`scripts/lib/executor-session.sh` replaces `scripts/lib/codex-session.sh`. Same
mechanism — one file per Claude Code session, keyed by session id, readers fail
closed, week-old files pruned — with the executor id as the first argument of
every function:

```
executor_session_dir <id>          # registry session_dir, overridable by its session_dir_env
executor_session_file <id>         # <dir>/<sid>.json; fails with no session id
executor_session_on <id> <surface> # true only when this session's gate opened that surface
executor_session_write <id> <json>
executor_session_mark_off <id> <reason> [resets_at_epoch]
```

`mark_off` writes `usable:false` plus every surface in that executor's
`surfaces` list set false, and touches no other executor's file. This is
finding 2: today a second lane hitting a rate limit would mark the one shared
file off and take Codex's review seats down with it.

`codex-session.sh` is deleted rather than kept as a shim. Its four callers —
`codex-gate`, `plan-lint`, `review-route`, `run-codex-review.sh` — are updated
in the same change. A shim would leave two ways to reach the same state, which
is the ambiguity this sub-project exists to remove.

Existing `~/.claude/dr-superpowers/codex-sessions/<sid>.json` files keep their
path, because the registry records that directory. Nothing is migrated.

## 6. `plan-lint`

The `**Executor:**` line's first token is the executor id. Validation becomes:

1. The id must be in `executors list`, else ERROR naming the registry.
2. The header's `> **External executors:**` line must name that id.
3. The task must pass that executor's gate block, read via
   `blocks.gate` — `min_score`, `max_risk`, and any further keys that block
   defines.
4. The rung must match that executor's `blocks.assignment` row for the task's
   total.

The lane-eligible warning at `plan-lint:279-282` becomes per-executor: a task
that no ticked executor's gate admits gets no warning, and a task admitted by
one gets that executor's rung suggested.

**The plan syntax does not change.** `**Executor:** codex gpt-5.5 / high`
already leads with the id, and `> **External executors:** codex` already names
it. No existing plan needs migrating, and `tests/plan-lint.test.sh`'s existing
Codex fixtures must pass unchanged — that is the regression bar for this
section.

## 7. `review-route`

Two changes, both narrow.

The ruling allowlist gains `executor-empty-diff` and keeps `codex-empty-diff`
as an accepted alias resolving to it, exactly as `--kind risk3` is kept as the
earlier name of `--kind task`. `subagent-driven-development/SKILL.md`'s ruling
table and the ruling prompt name the new kind and stop naming the Codex one.

The Codex-off rows consult `executor_session_on <id> review` for the executor
under consideration rather than a single Codex answer.

**Seat routing is otherwise untouched.** A task carrying an `**Executor:**`
line of any id still routes to a Claude judge, because the rule was never about
which CLI wrote the diff — it is that no executor reviews its own work. That
rule already generalises and needs only its Codex-only phrasing widened.

## 8. `detect-executors.sh`

The `if [ "$id" = codex ]` branch becomes "if the id has a registry entry". For
such an id the roster runs that entry's `locator`, then its companion auth
probe, and takes every reason string from the entry's `reasons` map. Ids with
no registry entry keep the PATH probe.

`lane_implemented` stops being a hand-maintained argument to `emit` and becomes
"this id has a registry entry naming a readable wrapper". That is the fact the
field was always standing in for, and it cannot drift from reality.

The reason for a batch-capable id with no lane is rewritten to name
`executors list` rather than asserting that only Codex has a wrapper.

## 9. Inline offload — the one behaviour change

Today an inline plan delegates a task when it is too heavy to implement in
session: total 5 or more, or risk 3, plus total-4 tasks while they are a third
of the plan or fewer. `plan-header.md` records the set as
`**Dispatch:** delegated — Task <a> (heavy), Task <b> (total 4)`.

**A task an executor's lane gate admits joins that set.** It is a delegated
task whose dispatch is the wrapper rather than an implementer subagent — which
`reference/delegated-task.md` §1 already does for any delegated task carrying
an `**Executor:**` line. So the brief, the review seat, the fix rounds, the
five-round cap and the ledger line all apply unchanged; what changes is only
which tasks reach that path.

The header line gains the marker:

```
**Dispatch:** delegated — Task 3 (heavy), Task 5 (total 4), Task 1 (executor), Task 2 (executor)
```

The set is computed by `writing-plans` when the plan is written, as the
existing set is, so `executing-plans` reads a decision rather than making one.
`executing-plans` loses the sentence saying `**Executor:**` lines are inert and
gains the rule that an `(executor)` task is dispatched, not implemented.

**This changes the existing Codex lane.** Codex's gate is `min_score 2,
max_risk 1`, so an inline plan that ticks Codex will now offload its total-2
and total-3 tasks at risk 0 or 1, and any total-4 task at risk 0 or 1 that the
existing third-of-the-plan rule left in session. All of those were previously
implemented by the session itself. That is the intended effect and the reason
the owner chose it: inline mode already delegates upward when a task exceeds
what the session should do itself, and this is the mirror image. It is called
out here because it is the one place where a reader expecting a pure refactor
will find behaviour that moved.

**An offloaded task whose executor is unavailable at dispatch stays
delegated.** The roster guard already substitutes the task's
`**Implementer:**` agent and says so aloud; that path is unchanged, so such a
task runs as an ordinary delegated subagent with its own review seat rather
than falling back to in-session implementation. This is deliberate: the plan's
Dispatch line is a record of what the session does not implement, and a
run-time availability answer must not silently change that.

The mode-selection rule in `using-superpowers` §Process Depth is **not**
changed. Whether a plan is inline or subagent still follows the heavy-task
majority; offloading does not make a plan more or less inline.

## 10. The reference, and two defects in it

`reference/external-executor.md` becomes `reference/executor-lane.md`: the
planning flow, the dispatch contract, the failure taxonomy and the resume rules
stated once in executor-neutral terms, with a short per-executor section for
what differs. `external-executor.md` is deleted; `legacy-names.md` is not the
right place for a reference rename, so every referrer is updated in the same
change.

Two live defects in that file are fixed while it is being rewritten. Both were
found by checking the superseded spec's claim that it copied a poll loop:

- The file says the wrapper polls for the rung's timeout and kills Codex
  (lines 94-95, 233). There is no poll loop. `run-codex-task.sh:241` runs
  `timeout $((timeout_s + 60)) node codex-client.mjs`, and the deadline, the
  interrupt and the reap belong to the client.
- The file documents `note=codex-may-still-be-running` as an outcome a
  controller must detect and clean up before retrying. `survivor=yes` is never
  assigned anywhere in `run-codex-task.sh`, so the note cannot be printed and
  the controller is being told to handle a state it can never observe. Either
  the note is removed from both files, or the wrapper is given the check that
  would set it. **This spec removes it**, and records in the new reference that
  child-process survival is the client's responsibility, because that is where
  the deadline already lives. Reinstating a survivor check belongs with
  whichever executor needs one.

The stale comment at `run-codex-task.sh:106-107`, which also describes the
absent poll loop, is corrected in the same change.

## 11. Skill prose

| File | Change |
|---|---|
| `skills/writing-plans/SKILL.md` | The roster question and gate flow run per ticked executor; the header's Dispatch line records `(executor)` tasks |
| `skills/subagent-driven-development/SKILL.md` | Ledger grammar becomes `executor <id> <model>/<effort>, session <sid>`; the ruling table names `executor-empty-diff` |
| `skills/executing-plans/SKILL.md` | The "Executor lines are inert" sentence is replaced by the offload rule |
| `skills/handoff/SKILL.md` | Executor state recorded per id |
| `reference/delegated-task.md` | §1 reads the executor id from the line rather than assuming Codex |

The ledger grammar change is the one with a compatibility cost: a resumed plan
whose ledger carries `executor codex gpt-5.5/high, thread 01a0...` must still
be readable. `resume-execution` and `repo-audit` parse the ledger, so both
grammars are accepted on read and only the new one is written.

## 12. Testing

**The fixture executor is the central device.** The suites ship
`tests/fixtures/executors/stub.json` plus a stub locator, gate and wrapper. It
exists only under test — `executors list` in production sees only the shipped
registry — and it is what proves the abstraction rather than merely asserting
it.

| Suite | Covers |
|---|---|
| `tests/executors.test.sh` (new) | `executors list/get/path`, unknown id, malformed entry, id validation |
| `tests/executor-session.test.sh` (new) | Per-id files, surfaces from the registry, `mark_off` touching one executor only, no session id, pruning |
| `tests/plan-lint.test.sh` | Existing Codex fixtures unchanged, plus a `stub` Executor line accepted and an unknown id rejected |
| `tests/review-route.test.sh` | `executor-empty-diff` accepted, `codex-empty-diff` still accepted, a `stub` Executor task routed to a Claude judge |
| `tests/detect.test.sh` | Registry-driven probe for a fixture id, remedies from the registry, PATH probe for a non-registry id |
| `tests/inline-mode.test.sh` | The Dispatch line's `(executor)` markers, and the prose rule replacing "inert" |
| `tests/codex-gate.test.sh`, `tests/codex-client.test.sh`, `tests/codex-review.test.sh`, `tests/lanes.test.sh`, `tests/executor-recovery.test.sh` | Must pass with no assertion changed except where §9 and §10 moved behaviour |

That last row is the regression bar. Any other edit to an existing assertion is
a signal that Codex's behaviour moved when it should not have, and it is
treated as a defect rather than a test update.

Repository validation per CLAUDE.md: `node scripts/validate-repository.mjs`,
both test runners, and `claude plugin validate` on the marketplace and every
Claude plugin. Every test and CLI call takes an explicit timeout and every
process started is terminated.

## 13. What does not change

Stated explicitly so a reviewer can check the claim rather than infer it:

- `lib/task-state.sh`, `lib/task-execution.sh`, `scripts/repo-audit` — already
  executor-neutral, verified by grep.
- `run-codex-task.sh`'s staging, commit, write-set validation and recovery
  paths. Only the stale comment at 106-107 changes.
- `scripts/codex-gate` and `scripts/codex-plugin` keep their names, their
  output grammar and their logic; they gain the registry only as the source of
  the session directory.
- The plan file syntax, so no existing plan is migrated.
- `criteria/`, the review schemas, and every judge prompt.
- The mode-selection rule in `using-superpowers`.
- The ladder's scoring rubric, Rule S, the assignment, escalation and reserve
  tables.

## 14. Repository integration

| File | Change |
|---|---|
| `plugins/dr-superpowers/.claude-plugin/plugin.json` | 1.15.1 to 1.16.0 |
| `plugins/dr-superpowers/.codex-plugin/plugin.json` | Same version |
| `plugins/dr-superpowers/README.md` | The lane described per executor |
| `tests/review-route.test.sh` | Its two pinned version assertions |

No catalog or marketplace change: this sub-project adds no plugin.

## 15. Out of scope

- **Any second executor.** That is sub-project B. This one ships with exactly
  one registry entry.
- **Unifying the wrapper.** `run-executor-task.sh` with per-executor adapters
  was considered and declined: it rewrites the script that owns staging and
  commit while its only caller works correctly. B adds a second wrapper reusing
  the same two libraries; a later sub-project may merge them once two exist to
  compare.
- **The review-seat runner.** `run-codex-review.sh` stays Codex-only. No
  executor but Codex has a review surface, and D4 of the superseded spec keeps
  it that way.
- **The calibration decision.** Whether `trust.calibration` should be
  re-baselined against astra is recorded in
  `2026-09-20-review-routing-calibration.md` and is independent of this work.

## 16. Risks

**The regression bar is the whole risk.** This sub-project touches the lint
rule, the routing table, the session state and four skills, and its success
condition is that Codex behaves identically afterwards. The mitigation is §12's
rule that an existing assertion changing is a defect signal, not a test update
— but a suite can only catch what it asserts, and the skill prose is covered by
`present`/`absent` string checks rather than by execution.

**The inline offload is not covered by that bar**, by construction: it is a
deliberate behaviour change to an existing lane, and the first plan executed
after it will offload tasks that previously ran in session. It should land in
its own commit, late in the plan, so it can be reverted without unpicking the
abstraction.
