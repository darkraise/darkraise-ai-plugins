# A lane-agnostic executor interface

**Status:** approved design, revised after review rounds 1 and 2, not yet planned
**Sub-project:** A of two. B is `dr-opencode`, the second executor instance.
**Forced by:** docs/superpowers/notes/2026-09-20-dr-opencode-spec-review.md
**Review rounds 1 and 2:** docs/superpowers/notes/2026-09-20-executor-interface-review.md
**Superseded design:** docs/superpowers/specs/2026-09-20-dr-opencode-executor-design.md
**Register:** docs/superpowers/registers/2026-09-20-opencode-executor.md
**Owner decisions:** 2026-09-20 brainstorming session

## 1. Purpose

dr-superpowers offloads plan tasks to one external CLI. The intent was always an
*external executor lane* with Codex as its occupant, but the implementation
names Codex directly in the lint rules, the session library, the ruling kinds,
the roster and the skill prose. Two review seats, asked to judge a design that
proposed adding a second executor beside it, independently concluded that no
second executor can be added without first separating the two.

This sub-project performs that separation. It adds no executor. Its deliverable
is that adding one becomes **a registry entry, a wrapper, and a block in
`reference/ladder.md`**, rather than a rewrite of eight files.

The ladder edit is named because it cannot be avoided here: `ladder_block`
(`scripts/lib/plan.sh:70-72`) hardcodes the path to the shipped `ladder.md`,
so an executor's assignment, successor and timeout rows live in that shared
file whatever the registry says. Making the policy source per-executor is a
larger change than this sub-project, and is listed out of scope in §15.

**It has no user-visible benefit on its own** beyond §9's offload. That is
accepted: the payoff is sub-project B, and the cost of skipping it is a second
hardcoded lane beside the first.

Every file path below was read during this design. Where an earlier draft
described behaviour from the reference documents rather than the code, review
round 1 caught it; §9 in particular is rewritten around what `scripts/lib/plan.sh`
and `scripts/task-brief` actually do.

## 2. What forced it

From the merged findings of the superseded spec's review, the Critical items
this sub-project answers:

| # | Finding | Evidence |
|---|---|---|
| 1 | `plan-lint` requires every `**Executor:**` line to name the `codex-assignment` rung and the header to say `codex` | `scripts/plan-lint:272-279` |
| 2 | `lib/codex-session.sh` hardcodes one directory and the `usable/review/lane` fields; a second lane's mark-off would switch off Codex's review seats | `scripts/lib/codex-session.sh:13,24,41` |
| 5 | The ruling allowlist is Codex-specific | `scripts/review-route:187` |
| 7 | The surfaces that drive dispatch are Codex-specific prose | skill files |
| 8 | Inline mode implements exactly the band a cheap executor would serve | `skills/executing-plans/SKILL.md:164` |
| 9 | `detect-executors.sh`'s plugin branch is `if [ "$id" = codex ]` with three `/codex:setup` remedies hardcoded | `scripts/detect-executors.sh:40,75-87` |

One claim survived review and is load-bearing: `lib/task-state.sh`,
`lib/task-execution.sh` and `scripts/repo-audit` contain no Codex reference.
The durable task record, snapshotting, scoped staging and commit recovery are
already executor-neutral and are not touched.

## 3. Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | A registry of per-executor data files, each executor keeping its own gate and locator script | Auth models genuinely differ. What must be shared is the *state*, not the probe |
| D2 | Inline mode offloads cheap tasks downward, mirroring its upward delegation | A lane whose band is exactly what inline mode keeps for itself can never fire. Owner's choice over restricting the lane to subagent plans |
| D3 | `executor-empty-diff` replaces `codex-empty-diff`, old name still accepted | The `--kind risk3` precedent. A hard rename breaks in-flight plans for no gain |
| D4 | A fixture executor id, used only by the suites, reached through a directory override | It proves the abstraction supports a second executor with no second CLI installed |
| D5 | Codex's observable behaviour is unchanged except where §9 and §10 say otherwise | This is a refactor. Every deviation is named; anything unnamed must stay identical in effect |
| D6 | The ledger keeps the field name `thread` | `task-state.sh` stores `thread`, the wrapper prints `thread=`. Renaming to `session` would make a third name for one value and create a compatibility cost that is entirely self-inflicted |

## 4. The registry

`reference/executors/<id>.json`, one per executor. The directory is
`${DR_EXECUTORS_DIR:-<plugin-root>/reference/executors}`, following the
`DR_CODEX_POLICY` precedent; every reader below honours that variable, which is
how §12's fixture executor exists without touching the shipped registry.

The Codex entry:

```json
{
  "id": "codex",
  "locator": "scripts/codex-plugin",
  "probe": { "command": "scripts/lib/codex-client.mjs", "op": "auth" },
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
  "reasons": {
    "not_enabled": "the codex plugin is not enabled in this profile",
    "logged_out": "the codex plugin is installed but not logged in; run /codex:setup",
    "probe_failed": "the codex plugin auth probe failed; run /codex:setup"
  }
}
```

Every existing name is preserved, including the ladder block literally called
`gate`, the environment variable `DR_CODEX_SESSION_DIR` and the remedy text
embedded in the reason strings. The registry records what is, so nothing about
Codex has to move for the abstraction to exist.

`session_dir` is relative to `$HOME/.claude/dr-superpowers/`, which is today's
base path. `session_dir_env`, when set, replaces the whole resolved path.

### 4.1 The two contracts the registry points at

Both are interfaces today, enforced by their callers' parsing, and both must be
written down because §12's stub has to satisfy them.

**The locator** prints one line and exits 0 for ok, 1 for off, 2 for a usage or
dependency error:

```
<id>-plugin ok version=<v> root=<path to end of line>
<id>-plugin off reason=<token>
```

`detect-executors.sh:49-51` and `codex-gate:57-58` parse exactly this.

**The probe** reads one JSON request on stdin and prints one JSON object. The
roster sends `{"op": "<probe.op>", "cwd": "<native-form path>"}` and reads
`.authed`, which is `true`, `false`, or absent for a failed probe — mapping to
`authenticated`, `logged_out` and `probe_failed` respectively. The probe is
invoked as `node <probe.command> <locator root>`.

**The probe is not the gate.** `codex-gate` additionally reads quota, consults
the trust record and writes session state; using it as the roster's probe would
change Codex's roster behaviour and cache an answer the roster is not entitled
to write. They stay separate.

### 4.2 `scripts/executors`

The only reader of the registry:

| Invocation | Output | Exit |
|---|---|---|
| `executors list` | one id per line, for every **valid** entry | 0, even when the directory is empty |
| `executors get <id> <dotted.key>` | one field; an array prints one element per line | 0; 1 when the id or key is absent |
| `executors path <id> <dotted.key>` | a path field resolved absolute against the plugin root; takes the same dotted key as `get` | as `get` |

Nothing else parses the registry. A caller needing three fields calls it three
times; these are local spawns on paths already taken, and one parser is worth
more than the spawns cost.

**Validity, and how a bad entry behaves.** An entry is valid when it parses as
JSON, carries `id`, `locator`, `probe.command`, `probe.op`, `wrapper`,
`session_dir`, `surfaces` and `blocks.gate`, its `id` matches its filename
stem, and no earlier entry claimed that id. An invalid entry is **skipped by
`list`, with one diagnostic line per bad entry on stderr**, and `get` on its id
exits 1. `list` never fails as a whole: one malformed file must not remove
every executor, which is the silent-downgrade failure `detect-executors.sh` was
already written to avoid.

A caller therefore distinguishes three states: the id is absent from `list`
(not registered, or registered invalidly — stderr says which), the id is
present but its probe reports unusable (registered but unavailable), or the id
is present and usable.

An id matches `[a-z][a-z0-9-]*`. An unknown id is an error naming
`executors list` **when it appears in an `**Executor:**` line or is passed to
`executors get`**. It is not an error elsewhere: §8 keeps PATH-probed ids
(`cursor-agent`, `opencode`, `antigravity`) that have no registry entry, and
those are reported exactly as they are today.

### 4.3 Which fields are read, and by whom

Stated so a reviewer can check for dead schema rather than infer it.

| Field | Read by |
|---|---|
| `locator`, `probe`, `reasons` | `detect-executors.sh` (§8) |
| `session_dir`, `session_dir_env`, `surfaces` | `lib/executor-session.sh` (§5) |
| `blocks.gate`, `blocks.assignment` | `plan-lint` (§6) |
| `wrapper` | `detect-executors.sh`, to decide that a lane exists (§8) |
| `gate`, `reference`, `blocks.successor`, `blocks.timeout`, `blocks.judge` | **No script.** The *controller* reads them, through `scripts/executors`, when the executor-neutral prose of §10 and §11 tells it to run an executor's gate, open its reference, or take its successor rung |

The distinction matters and an earlier draft got it wrong by forbidding
"readers" outright. `reference/executor-lane.md` instructs a controller to run
the gate, consult the successor column and read the per-executor section; with
one executor it may resolve those literally, but the prose must name them as
`executors get <id> gate` and so on, or the neutral reference is neutral in
name only. What the plan must **not** do is add a *script* that reads these
five fields: `run-codex-task.sh` and `run-codex-review.sh` keep their literal
block names per §13, and widening them is sub-project B's work, not this one's.

## 5. Session state

`scripts/lib/executor-session.sh` replaces `scripts/lib/codex-session.sh`. Same
mechanism — one file per Claude Code session, keyed by session id, readers fail
closed, week-old files pruned on write — with the executor id as the first
argument:

```
executor_session_id                        # unchanged; no id argument
executor_session_dir <id>
executor_session_file <id>                 # fails when there is no session id
executor_session_on <id> <surface>
executor_session_write <id> <json>
executor_session_mark_off <id> <reason>
```

`mark_off` writes the record `codex_session_mark_off` writes today, with the
surface list taken from the registry rather than hardcoded:

```json
{ "session_id": …, "usable": false, "<each surface>": false,
  "reason": …, "checked_at": …, "resets_at": null, "resets_at_epoch": null,
  "plugin_version": "<preserved from the prior file>" }
```

Preserving `plugin_version` and writing `reason`, `checked_at` and both
`resets_at` fields is not optional: `codex-gate:39-50` reads all of them back
out of the cache, and `tests/codex-gate.test.sh:247` asserts `reason`. The
earlier draft's optional `resets_at_epoch` argument is dropped — no caller
passes one, because a gate with a reset time writes through
`executor_session_write`, not through `mark_off`.

`mark_off` touches only its own executor's file. This is finding 2: today a
second lane hitting a rate limit would mark the one shared file off and take
Codex's review seats down with it.

`codex-session.sh` is deleted rather than kept as a shim; a shim would leave two
ways to reach one state. It has **five** callers, not four: `codex-gate`,
`plan-lint`, `review-route`, `run-codex-review.sh`, and
`tests/codex-gate.test.sh:236`, which sources it directly and calls
`codex_session_on` and `codex_session_mark_off`. That test's harness lines
change; its `check` assertions do not (§12).

Existing `~/.claude/dr-superpowers/codex-sessions/<sid>.json` files keep their
path, because the registry records that directory. Nothing is migrated.

## 6. `plan-lint`

Two independent code paths touch executors, and they have different predicates.
The earlier draft conflated them; they are specified separately here.

### 6.1 Validating an `**Executor:**` line

The line's first token is the executor id. The rules, in order, preserving
today's three ERRORs verbatim with the id templated in:

1. The id must be in `executors list`, else ERROR naming the registry. (New.)
2. The Override rule: an Executor line on an overridden task is an ERROR.
   Unchanged, and omitted from the earlier draft.
3. The task must pass that executor's gate block — read via `blocks.gate`,
   and reading **exactly `min_score` and `max_risk`**, as today. The block also
   carries `require_rule_s_clean` and `require_external_enabled`, which
   plan-lint enforces as rules 2 and 5 rather than by evaluating keys; the
   earlier draft's "any further keys that block defines" invited a generic key
   evaluator nobody specified and is withdrawn.
4. The rung must match that executor's `blocks.assignment` row for the total.
5. The header's `> **External executors:**` line must name that id.

The Executor branch emits four ERROR messages (`plan-lint:273,275,277,278`), of
which three are pinned at `tests/plan-lint.test.sh:391-395`. All four keep
their exact wording with `codex` substituted by the id, so a Codex plan's
output is byte-identical.

### 6.2 The lane-eligible warning

**Its predicate is not the header tick.** Today, at `plan-lint:294-308`, the
warning fires when a task is eligible (clean, non-overridden, within the gate,
no Executor line) **and** `codex_session_on lane` **and** the roster reports
`usable` **and** lazy probing is enabled **and** the plan is not inline. The
`p1.md` fixture at `tests/plan-lint.test.sh:416-420` carries no External
executors header and still expects the warning, so a tick-based predicate would
break a fixture §12 declares unchangeable.

Generalised: for each id in `executors list` with `executor_session_on <id> lane`
and a `usable` roster row, warn on tasks that id's gate admits, naming that id's
rung. Codex alone is registered, so the output is unchanged.

### 6.3 The inline skip

`plan-lint:300` skips the warning for inline plans, and its comment at 294-299
justifies the skip with "Executor lines are inert under inline execution" —
the premise §9 removes. `tests/plan-lint.test.sh:452` pins the skip.

**The skip stays and only the comment is rewritten.** Under §9 an inline plan
can carry Executor lines, so the warning becomes meaningful there, but turning
it on would change an existing fixture for a warning that is advisory. The new
comment says the skip is a deliberate deferral, and a register row records it.

## 7. `review-route`

The ruling allowlist gains `executor-empty-diff` and keeps `codex-empty-diff`
as an accepted legacy spelling.

**The legacy spelling is not canonicalised on output.** `review-route:205`
prints `ruling=%s` with the kind it was given, so resolving the old spelling to
the new one would change an observable for an existing caller — outside the §9
and §10 exceptions D5 allows. The two spellings therefore share routing
internally and each prints the value it was invoked with. The `--kind risk3`
precedent does not transfer: that alias lives in `run-codex-review.sh`, whose
status line does not echo the input kind.

The kind is named in three places beyond the script:
`skills/subagent-driven-development/SKILL.md`'s ruling table,
`skills/subagent-driven-development/references/ruling-prompt.md:96`, which
explains the kind to the judge, and `skills/executing-plans/SKILL.md:346-347`
(§9). All three are in §11's table.

The Codex-off rows call `executor_session_on codex review` literally. Codex is
the only executor with a review surface (§15), so nothing iterates.

**Seat routing is otherwise untouched.** `review-route:257-260` keys on the
presence of an `**Executor:**` line, not on the word `codex`, so the
"no executor reviews its own work" rule already generalises and needs only its
prose widened.

## 8. `detect-executors.sh`

Registry ids are enumerated from `executors list` and emitted first; the three
PATH-probed ids stay as literal `emit` calls, **each skipped when its id is
registered**. Without that skip, registering `opencode` in sub-project B would
produce two rows with the same id — one describing the lane, one still saying
no lane exists — and every consumer selects by id expecting one value
(`run-codex-review.sh:113-117`). §12 tests the collision with a fixture named
`opencode`.

For a registry id the roster runs
that entry's `locator`, then its `probe` per §4.1, and takes every reason
string from the entry's `reasons` map — replacing `if [ "$id" = codex ]` at
line 40 and the three hardcoded remedies at 75-87.

`batch_capable` stays a hand-maintained argument for PATH-probed ids and is
`true` by definition for a registry id: an executor with a wrapper is one that
runs headlessly. `lane_implemented` stops being an argument and becomes "this
id's entry names a readable `wrapper`" — the fact the field always stood in
for, and one that cannot drift.

That makes "registered but the wrapper is unreadable" newly reachable, and no
`reasons` key covers it. It is a broken installation rather than an executor's
own state, so it keeps a **generated** message naming the id and the missing
path, as `detect-executors.sh:82-83` generates today — an explicit exception to
"every reason comes from the map".

The cwd handed to the probe is converted with `dr_native_path` (`1bc0602`).

The "only codex has a wrapper" reason string is rewritten to name
`executors list`.

## 9. Inline offload — the one behaviour change

The earlier draft placed this in `writing-plans` at plan time. **That was
wrong.** The delegated set is computed mechanically at execution time by
`plan_delegated` (`scripts/lib/plan.sh:157-169`) from `plan_scores` alone, and
`scripts/task-brief:56-75` renders it into the workspace's `plan-header.md` and
into each delegated brief's second line. No `**Dispatch:**` line exists in the
plan file, and `writing-plans` never writes one.

### 9.1 `plan_delegated` gains a third row kind

It emits `<task>\t<kind>` rows, today `heavy` and `total 4`. It gains
`executor`, keyed on the presence of an `**Executor:**` line rather than on
re-evaluating a gate. **The Executor line is the decision**; it was made when
the plan was written, and execution time must not second-guess it.

**A sibling helper, not an extension.** `plan_delegated` is one awk pass over
`plan_scores` output, and `plan_task_text` is a full awk pass per task, so
reading task text inside it would add a second per-task loop. Instead
`plan_executors FILE` emits `<task>\t<id>`, fence-aware exactly as
`plan_scores` is (`plan.sh:132`), and `plan_delegated` merges it in through
`-v`. `plan-lint` §6.1's "the first token is the id" shares the same helper,
so one parser reads Executor lines. The plan and `tests/plan-lib.test.sh` cite
it by name.

**`heavy` wins over `executor`; `executor` wins over `total 4`.** An earlier
draft claimed `heavy` and `executor` cannot collide because the gate caps risk
at 1. That is false for a split task: `plan-lint:200-209` validates each
`#### Part` independently, so Part A at total 2 / risk 0 may legally carry an
Executor line, while `plan_scores:137-138` reports the *highest* total and risk
across parts and can therefore mark the same task `heavy`.
`review-route:253-257` already carries a guard for exactly this shape.

Heavy must win because the `(heavy)` label is what
`executing-plans/SKILL.md:169-171` keys the preflight ruling on; letting
`executor` take the label would silently stop the preflight firing. The task is
delegated either way, and `delegated-task.md` §1 still reads the Executor line
per part, so nothing about the part's dispatch is lost. `plan_executors` must
therefore match an Executor line in **any** part, and the row it produces is
suppressed only when the task is already `heavy`.

**The threshold counts the original four-band population.** `plan_delegated`
increments `four` for every total-4 row and drops them all when
`3 * four > n` (`plan.sh:163,166`). If an offloaded total-4 task left that
numerator, removing it could flip the condition true and newly delegate *other*
total-4 tasks that carry no Executor line — moving tasks outside the set §9.4
promises. So a total-4 task still counts toward `four` when it carries an
Executor line; `executor` changes only the row's admission and its displayed
kind. `tests/plan-lib.test.sh` pins a six-task plan with three total-4 tasks,
one of them offloaded, and asserts the other two stay in session.

`task-brief` renders the new kind as `Task <n> (executor)` in the header's
Dispatch line, with no change to its format, and gives such a task the same
`**Dispatch:** delegated — total <t>, risk <r>` second line every delegated
task gets. `task-brief`'s `dispatch=1` guard is unchanged: in subagent mode the
set stays empty because every task is dispatched anyway.

### 9.2 The consequence for `plan-lint`'s inline model and effort

`plan-lint:326-350` derives an inline plan's required model and effort from
`plan_delegated`, so adding rows changes its verdicts. Two effects, both
intended, both named here because §12's regression bar would otherwise read
them as defects:

- `self_max` excludes delegated tasks, so an offloaded total-4 task no longer
  forces `--model opus`. Correct: the session does not implement it.
- `need=high` fires whenever anything is delegated, so an inline plan whose
  only offloaded task is a total 2 now requires `--effort high`. Also correct:
  the session is orchestrating a dispatch, a review seat and a fix loop.

The NOTE line `delegated: Task <n> (<kind>)` gains the executor rows.

The plan must enumerate every `tests/plan-lint.test.sh` fixture whose expected
output moves, and each such change is justified against one of these two
bullets or treated as a defect.

### 9.3 `executing-plans`

The sentence at line 164 saying `**Executor:**` lines are inert is replaced by
the rule that a task whose brief's second line marks it delegated is
dispatched, which already routes an Executor line through
`reference/delegated-task.md` §1. `writing-plans/SKILL.md:265` carries a second
copy of the "inert" rule and is corrected with it.

**The prose that defines the delegated set changes too**, and an earlier draft
listed none of it: `executing-plans/SKILL.md:50-59` ("every heavy task, and
each total-4 task while those are a third...", including the verbatim example
`**Dispatch:** delegated — Task <a> (heavy), Task <b> (total 4)`),
`reference/delegated-task.md:5-9`, and the README sentence naming both
reasons. `tests/inline-mode.test.sh:101` pins the example string and `:105-106`
pin the README and delegated-task.md sentences, so all three move together.

**Consecutive offloads need an explicit release.** `lib/task-state.sh` retains
`owner.json` for a worktree and rejects a different task id in it;
`tests/executor-recovery.test.sh:111-117` demonstrates that
`run-codex-task.sh --release` is required before a second task can run there.
Under §9 an inline plan offloads several cheap tasks in sequence into one
worktree, so without a release every offload after the first fails preflight —
the single most likely way this section breaks in practice. The loop releases
ownership after a task's review completes, and after a `HANDBACK` it reconciles
ownership before the Claude implementer takes the worktree. §12 covers two
consecutive offloaded tasks in one worktree.

`executing-plans/SKILL.md:346-347` says "Only `codex-empty-diff` belongs to a
seat this mode never runs (no external executor)" and omits the kind from its
ruling table. Under §9 an inline session runs executor fix rounds, so an
empty-diff round is reachable: the sentence goes and the table gains
`executor-empty-diff`. `tests/inline-mode.test.sh:88` and
`tests/review-route.test.sh:384` pin that sentence and move with it.

### 9.4 What moves, exactly

Codex's gate is `min_score 2, max_risk 1`, and Rule S caps a compliant total at
4, so the eligible band is totals 2 to 4 at risk 0 or 1. Of those, an inline
plan today already delegates the total-4 tasks while they are a third of the
plan or fewer, and a delegated task carrying an Executor line already runs on
Codex through `delegated-task.md` §1. **What newly moves is the
self-implemented remainder:** totals 2 and 3 at risk 0 or 1, plus total-4 tasks
the third-of-the-plan rule left in session.

**An offloaded task whose executor is unavailable at dispatch stays
delegated.** The roster guard (`external-executor.md:110-128`) already
substitutes the task's `**Implementer:**` agent and says so aloud, so such a
task runs as an ordinary delegated subagent with its own review seat rather
than reverting to in-session implementation. The plan's dispatch set is a
record of what the session does not implement, and a run-time availability
answer must not silently change it.

This lands in its own commit, late in the plan, so it can be reverted without
unpicking the abstraction.

## 10. The reference, and two defects in it

`reference/external-executor.md` becomes `reference/executor-lane.md`: the
planning flow, dispatch contract, failure taxonomy and resume rules stated once
in executor-neutral terms, with a per-executor section for what differs.

The file is linked from eight places, all of which are updated in the same
change: `README.md`, `reference/delegated-task.md` (lines 27, 50, 111, 196,
278, which also describe resuming "its Codex session"),
`reference/final-review.md`,
`skills/subagent-driven-development/references/escalation.md` (which likewise
says an external task resumes a Codex session),
`skills/subagent-driven-development/SKILL.md`, `skills/writing-plans/SKILL.md`,
`tests/inline-mode.test.sh:70-72,180` and `tests/review-route.test.sh:346-347,387`.

Two live defects are fixed while the file is rewritten:

- It says the wrapper polls for the rung's timeout and kills Codex (lines
  94-97, 233-236). There is no poll loop: `run-codex-task.sh:241` runs
  `timeout $((timeout_s + 60)) node codex-client.mjs`, and the deadline, the
  interrupt and the reap belong to the client. The stale comment at
  `run-codex-task.sh:106-107` is corrected with it.
- It documents `note=codex-may-still-be-running` as an outcome a controller
  must detect and clean up. `survivor=yes` is never assigned, so the note
  cannot print. **The note and its dead statements are removed** —
  `survivor=no` at line 275, the conditional `note=` at 364 and the comment at
  360-361 — which §13 explicitly permits.

**Removing the note does not remove the hazard, so the new reference documents
the real one** — and does not overstate what the evidence proves. The outer
`timeout $((timeout_s + 60))` fires only when the client itself wedges; then
`$result` is empty, `timedOut` is unset, the run reports `exit=1
status=BLOCKED` with no error section, and a grandchild may survive on Windows.

**`reaped` is not a termination certificate.** `codex-client.mjs:183-192`
deliberately sets no reap context when a broker already existed, because that
broker belongs to the user's own `/codex:*` work and must survive — so
`reaped:false` may mean "correctly left alone" rather than "a process
survived". A reap can also report success while teardown actually failed. And
a timed-out run (`exit=124`) reaches none of this, so a rule that inspects only
BLOCKED runs misses the case most likely to strand a child.

The new reference therefore states: after **any** run that did not reach DONE,
read the durable record's `phase` and `reaped` as *evidence*, not as proof;
where the evidence is inconclusive — `reaped:false` with no recorded
pre-existing broker, or a wedged client — the controller reconciles process
ownership before it retries, resumes or hands back, and a retry into an
unreconciled worktree is forbidden. Child-process survival is the client's
responsibility only while the client lives; when it does not, the controller
owns it.

**Three further code/document mismatches in this file are out of scope here
and fixed separately** (§15), because rewriting a document while knowingly
carrying wrong statements forward is worse than either fixing or leaving them,
and folding them in would blur this sub-project's regression bar. They are:
the `exit=` field described as Codex's own exit code when
`run-codex-task.sh:270-274` synthesizes 0, 1 or 124 from `ok` and `timedOut`;
the claim at lines 319 and 495 that exit 2 means nothing launched, when the
wrapper can exit 2 after execution on thread-persistence, reap-persistence,
scope-validation or report-copy failure; and the empty-`commit_subject` branch
at lines 200-206 telling a controller to stage manually, which
`dr_task_stage` now blocks outright. The neutral rewrite inherits whatever
those statements say **after** that fix lands, so it must land first.

## 11. Skill and reference prose

| File | Change |
|---|---|
| `scripts/lib/plan.sh` | `plan_delegated` gains the `executor` row kind (§9.1) |
| `scripts/task-brief` | Renders `(executor)` in the header line (§9.1) |
| `skills/writing-plans/SKILL.md` | The roster question and gate flow run per ticked executor; line 265's "inert" copy; the Choosing the Execution line paragraph at 119-143, whose model and effort rule §9.2 changes; the four-band definition at 121-127, which §9.1's threshold rule touches; and the one-Executor-line rule below |
| `skills/subagent-driven-development/SKILL.md` | Ledger grammar becomes `executor <id> <model>/<effort>, thread <id>`; the ruling table names `executor-empty-diff` |
| `skills/subagent-driven-development/references/ruling-prompt.md` | Line 96 explains `executor-empty-diff` |
| `skills/subagent-driven-development/references/escalation.md` | The link, and "resumes a Codex session" |
| `skills/executing-plans/SKILL.md` | §9.3 |
| `reference/delegated-task.md` | §1 reads the executor id from the line; the link and the Codex-session wording |
| `reference/final-review.md` | The link |
| `reference/external-task-recovery.md` | Declares itself Codex-only and hardcodes `run-codex-task.sh` for every recovery operation, and is linked from `external-executor.md:107,256`. It is **generalised**, not rewritten: the recovery contract is already executor-neutral in substance, so the commands resolve through the selected executor's `wrapper` and the Codex-only preamble goes |
| `skills/executing-plans/SKILL.md` (second row) | §9.3's prose defining the delegated set, lines 50-59 |
| `reference/delegated-task.md` (second row) | Lines 5-9, the same definition; plus the ownership release of §9.3 |
| `README.md` | The sentence naming both delegation reasons, per §9.3 |
| `skills/handoff/SKILL.md` | **No change.** It records no executor state today, so there is nothing to generalise; the earlier draft's row is withdrawn |

**A task carries at most one `**Executor:**` line, and the planner chooses it.**
When two ticked executors' gates both admit a task, nothing mechanical picks
between them: the planner writes one line, and `plan-lint` validates only what
is written. No automatic precedence rule is introduced here, because with one
registered executor there is no choice to make and a rule invented now would be
untested against real second-executor behaviour. Sub-project B introduces the
precedence rule together with the executor whose existence makes it necessary;
§12 still covers the mechanics — a `stub` line and a `codex` line each
validating against their own blocks — so B inherits a tested seam.

**The ledger keeps `thread`** (D6). The earlier draft claimed
`resume-execution` and `repo-audit` parse the clause and would need both
grammars; that is false. `repo-audit:55-68` reads only `ledger_plan`,
`ledger_done` and the last line; `resume-execution/SKILL.md` contains no
`executor`, `thread` or `codex` string; `review-route`'s `task_agents` regex
stops at `(assigned`. The clause's only readers are controller prose. So the
only change is `codex` becoming `<id>`, and no dual-grammar parsing is needed
anywhere.

## 12. Testing

**The fixture executor is the central device.** The suites ship a registry
directory reached by pointing `DR_EXECUTORS_DIR` at it, holding a stub locator,
probe, gate and wrapper. It exists only under test, and it is what proves the
abstraction rather than merely asserting it. The stub locator emits the §4.1
grammar and the stub probe honours the §4.1 request and `authed` contract.

**The fixture directory contains a copy of `codex.json` beside `stub.json`.**
`DR_EXECUTORS_DIR` replaces the shipped directory rather than adding to it, so
a fixture directory holding only `stub` would make `executors list` omit
`codex` — and then §6.1 rule 1 would reject every `codex` Executor fixture,
`detect.test.sh` would lose its codex row, and `run-codex-review.sh:113-117`
would die with "no codex row", in the same suites this section declares
byte-identical. The copy keeps both ids visible. A suite that specifically
tests an absent registry points the override at an empty directory instead.

A third fixture entry named `opencode` exercises the §8 collision: a
registered id must suppress its PATH-probe row rather than produce two rows
with one id.

| Suite | Covers |
|---|---|
| `tests/executors.test.sh` (new) | `list/get/path`, dotted keys, `DR_EXECUTORS_DIR`, unknown id, array output, and each §4.2 validity failure: malformed JSON, a missing required field, an id/filename mismatch, a duplicate id — each skipped with a stderr line while `list` still exits 0 and still names the valid entries |
| `tests/executor-session.test.sh` (new) | Per-id files, surfaces from the registry, the full `mark_off` record including preserved `plugin_version`, one executor's mark-off leaving another's file alone, no session id, pruning |
| `tests/plan-lib.test.sh` | `plan_executors` fence-awareness and part matching; the `executor` row kind; `heavy` winning over `executor` on a split task whose Part A carries the line and whose Part B is risk 3; `executor` winning over `total 4`; and the six-task three-total-4 fixture proving an offloaded total-4 still counts toward the threshold |
| `tests/plan-lint.test.sh` | Existing Codex fixtures byte-identical for §6.1 and §6.2; a `stub` Executor line accepted against its own blocks; an unknown id rejected; **new** inline-mode fixtures carrying Executor lines to cover §9.2 |
| `tests/review-route.test.sh` | `executor-empty-diff` accepted, `codex-empty-diff` still accepted, a `stub` Executor task routed to a Claude judge |
| `tests/detect.test.sh` | Registry-driven locator and probe for the stub id, reasons from the registry, PATH probe unchanged for non-registry ids |
| `tests/inline-mode.test.sh` | The `(executor)` marker; the replaced "inert" prose; the ruling-table addition; and the three pins that move with §9.3 — the example string at `:101` and the README and delegated-task.md sentences at `:105-106` |
| `tests/executor-recovery.test.sh` | Two consecutive offloaded tasks in one worktree, proving the §9.3 release (in addition to passing its existing assertions unchanged) |
| `tests/codex-gate.test.sh` | Harness lines change to the new library (§5); every `check` assertion unchanged |
| `tests/codex-client.test.sh`, `tests/codex-review.test.sh`, `tests/lanes.test.sh`, `tests/run-codex-task.test.sh` | Pass with **no assertion changed**. The earlier draft carved out `run-codex-task.test.sh` for §10's survivor removal; that carve-out is withdrawn, because the suite asserts nothing on `note=` or the survivor path, so removing dead statements must leave it untouched |

That table is the regression bar. An edit to an existing assertion outside the
rows that name one is a signal that Codex's behaviour moved when it should not
have, and is treated as a defect rather than a test update.

Repository validation per CLAUDE.md: `node scripts/validate-repository.mjs`,
both test runners, and `claude plugin validate` on the marketplace and every
Claude plugin. Every test and CLI call takes an explicit timeout and every
process started is terminated.

## 13. What does not change

Stated so a reviewer can check the claim rather than infer it. Review round 1
found three entries of the earlier draft's list to be false; they have been
moved to §11 and §12.

- `lib/task-state.sh`, `lib/task-execution.sh`, `scripts/repo-audit` — verified
  by grep to contain no Codex reference.
- `run-codex-task.sh`'s staging, commit, write-set validation and recovery
  paths. Two carve-outs: the stale comment at 106-107, and the survivor
  statements at 275, 360-361 and 364 that §10 removes.
- `scripts/codex-gate` and `scripts/codex-plugin` keep their names, output
  grammar and logic; the gate changes only to call the new session library.
- `scripts/run-codex-review.sh` and `run-codex-task.sh` keep their literal
  ladder block names; they do not read the registry.
- The plan file syntax, so no existing plan is migrated.
- `criteria/` and the review schemas. **Not** "every judge prompt":
  `ruling-prompt.md` changes, per §11.
- The mode-selection rule in `using-superpowers` §Process Depth. Whether a plan
  is inline or subagent still follows the heavy-task majority; offloading does
  not make a plan more or less inline.
- The ladder's scoring rubric, Rule S, and the assignment, escalation and
  reserve tables.

## 14. Repository integration

| File | Change |
|---|---|
| `plugins/dr-superpowers/.claude-plugin/plugin.json` | 1.15.1 to 1.16.0 |
| `plugins/dr-superpowers/.codex-plugin/plugin.json` | Same version |
| `plugins/dr-superpowers/README.md` | The lane described per executor; the renamed reference |
| `tests/review-route.test.sh` | Its two pinned version assertions |

No catalog or marketplace change: this sub-project adds no plugin.

## 15. Out of scope

- **Any second executor.** Sub-project B. This one ships one registry entry.
- **Unifying the wrapper.** Declined: it rewrites the script that owns staging
  and commit while its only caller works correctly. B adds a second wrapper
  reusing the same two libraries; a later sub-project may merge them once two
  exist to compare.
- **The review-seat runner.** `run-codex-review.sh` stays Codex-only; no other
  executor has a review surface.
- **Turning on the lane-eligible warning for inline plans** (§6.3), deferred to
  a register row.
- **A per-executor policy source.** `ladder_block` hardcodes the shipped
  `ladder.md` (§1), so adding an executor still edits that shared file. Making
  the policy source per-executor is its own change and is not attempted here.
- **An automatic precedence rule between two admitting executors** (§11),
  which belongs with sub-project B.
- **The three code/document mismatches in `external-executor.md`** (§10).
  These are pre-existing defects, not consequences of this design, and they are
  fixed as a **prerequisite** to this sub-project rather than inside it: the
  neutral rewrite must inherit a correct document. Tracked as its own register
  row and landed before Task 1.
- **The calibration decision**, recorded in
  `2026-09-20-review-routing-calibration.md`.

## 16. Risks

**The regression bar is the whole risk.** This sub-project touches the lint
rules, the routing table, the session state, two shared shell libraries and six
skill or reference files, and its success condition is that Codex behaves
identically afterwards. §12's rule — an unexplained assertion change is a
defect signal — is the mitigation, but a suite catches only what it asserts,
and the skill prose is covered by string checks rather than by execution.

**§9 is not covered by that bar**, by construction: it is a deliberate
behaviour change, it moves `plan-lint` verdicts for inline plans (§9.2), and
the first plan executed afterwards will offload tasks that previously ran in
session. Its own commit, late in the plan.

**The earlier draft's failure mode is the one to watch during planning.** It
described dispatch from the reference documents rather than from `plan.sh` and
`task-brief`, and every Critical in round 1 followed from that. Each task in
the plan must cite the file and line it changes, and a task whose description
can be satisfied without opening that file is under-specified.
