# dr-superpowers 1.9.0 — Review routing and the external lane (sub-project 8 design)

Date: 2026-09-15. Program design:
`docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`, whose seven sub-projects were
recorded complete on 2026-09-15; this is an eighth, added by dated amendment (§14). Source: the
design approved in chat on 2026-09-15 and committed as
`docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-DRAFT.md` (`d10571c`). This
document supersedes that draft.

**Goal:** cut Claude quota spent on review seats without losing what those seats catch, and put
the Codex implementer lane to use — 51 of 77 tasks in the last four plans met its gate and none
carried an `**Executor:**` line.

## 1. Decisions fixed here

Owner rulings from the 2026-09-15 design session (binding). Rulings 10-18, added after execution
stopped at the calibration gate, are in §15 and override this section where they disagree:

1. **Codex is the default task reviewer**, on `gpt-5.6-sol` for light tasks and `gpt-6-astra` for
   heavy ones. Claude judges become fallback seats.
2. **Risk >= 2 is reviewed by Astra, then Fable**, where Fable reviews the diff itself *and*
   rules on Astra's findings in the same pass. No reconcile round.
3. **Every Codex seat checks availability first** and degrades to its named Claude seat, aloud
   and in the ledger.
4. **No self-review.** A task carrying an `**Executor:**` line ran on Codex and is reviewed by a
   Claude judge, never by Codex.
5. **`plan-lint` gets a lazy availability probe**, with `--no-probe` for CI.
6. **Codex takes plan-review round 1**; Fable only on fallback.
7. **Calibration before trust:** replay the plans that carry recorded plan-review scores and gate
   on agreement (§11).

Owner answers given while writing this spec (2026-09-15):

8. **`risk3-spread` is retired**, not redefined. Fable's CONFIRMED/REJECTED on each Astra finding
   is the adjudication; a two-seat spread would send Fable's own disagreement to another Fable
   seat.
9. **Routing lives in a new `scripts/review-route`**, not in prose. It follows the rule
   sub-project 7 established in `scripts/run-codex-review.sh`'s header: a decision a seat must
   make lives where a test can reach it.

Settled here, where the draft was silent:

- **Risk >= 2 with Codex unusable** is `judge-fable` alone, not the score band's Claude judge:
  the seat is Fable-anchored, and dropping Astra must not also drop the model.
- **Executor beats risk.** The lane gate (`max_risk 1`) makes an `**Executor:**` task at risk
  >= 2 unreachable in a lint-clean plan; if one exists anyway, it gets `judge-fable` and no Codex
  seat.
- **Plan-review delta rounds may read the whole plan.** The delta is the reviewer's focus, not
  its fence: the round-3 defect that justifies keeping rounds was cross-task, and a reviewer
  forbidden from reading Task 11 could not have found it.
- **`judge-opus` keeps its name.** The draft's "`judge-opus-high`" in its fallback table means
  the existing `judge-opus` agent, which already runs at high effort.

## 2. What does not change

- The 475k session budget and the 1-hour cache TTL.
- The ruling seat, the final whole-branch verify, and spec review stay on `judge-fable`, with
  `judge-opus` under the existing Fable-unavailable rule.
- The final-review Codex round (`run-codex-review.sh --kind final`).
- Scoped re-reviews after a fix round stay on a general-purpose seat with an explicit
  cheap-to-mid model.
- Plan-review rounds are not cut: at most three, same fail rule (any score <= 8 or any Critical
  or Important finding).
- Native Codex hosts: `reference/native-codex.md` and its raw-risk-3 evaluations are untouched.
  Everything here is the Claude-hosted path.
- The execution lane's gate, rungs, successor column and timeouts.
- Inline mode (dr-superpowers:executing-plans) has no per-task reviewer, so only the plan-review
  change reaches it.

## 3. `scripts/review-route` — the routing table as code

A pure function of the plan. It reads the amended plan through `scripts/lib/plan.sh`
(`plan_apply_amendments`, `plan_task_text`), exactly as `plan-lint` does, and never probes
anything: availability belongs to `run-codex-review.sh`, which already checks it on every run.

```
review-route PLAN_FILE --task <id> [<id> ...]
review-route PLAN_FILE --plan-round <r>
```

`<id>` is a task number, or a task number and part letter for a split task (`7B`). Several ids
route a batch: the batch takes the highest total and highest risk among its tasks, and any
`**Executor:**` line among them.

Output is one line, then exit 0:

```
review-seat <scope> primary=<seat> fallback=<seat|-> reason=<why>
```

`<scope>` is `task=<ids>` or `plan-round=<r>`. Seats are one vocabulary:

| Seat | Meaning |
|---|---|
| `codex:light` | `run-codex-review.sh --kind task --tier light` — the `codex-judge` block's last row, `gpt-5.6-sol / high` |
| `codex:heavy` | `run-codex-review.sh --kind task --tier heavy` — first row, `gpt-6-astra / high`, with the runner's existing fallback |
| `codex:heavy+judge-fable` | the two-step risk seat (§4) |
| `codex:plan` | `run-codex-review.sh --kind plan` (§5) |
| `dr-superpowers:judge-sonnet-high`, `dr-superpowers:judge-opus`, `dr-superpowers:judge-fable` | a Claude judge dispatched as today |

**Task routing**, first matching row wins. `total` and `risk` come from the `**Evaluation:**`
line.

| Row | Condition | primary | fallback | reason |
|---|---|---|---|---|
| 1 | an `**Executor:**` line, risk >= 2 | `judge-fable` | `-` | `executor` |
| 2 | an `**Executor:**` line | band judge (below) | `-` | `executor` |
| 3 | risk >= 2 | `codex:heavy+judge-fable` | `judge-fable` | `risk` |
| 4 | total 0-3 | `codex:light` | band judge | `band` |
| 5 | total 4-6 | `codex:heavy` | band judge | `band` |

**Band judge:** total 0-1 `dr-superpowers:judge-sonnet-high`; 2-4 `dr-superpowers:judge-opus`;
5-6 `dr-superpowers:judge-fable`. Totals 5-6 always carry risk >= 2 under Rule S, so row 3
catches them first; the band row exists so the table is total.

**Plan-review routing:** round 1 `primary=codex:plan fallback=dr-superpowers:judge-fable`;
round 2 or later `primary=dr-superpowers:judge-opus fallback=-`; both print `reason=round`.

**Exit 2**, with a message on stderr and nothing on stdout: usage errors, a missing plan, an id
with no task, an `**Evaluation:**` line that does not parse, or a `Host: codex` plan (native hosts
route through `native-codex.md`). On exit 2 the controller reviews with `judge-fable` — today's
seat — and says why; a planner on a Codex-host plan dispatches its native judge instead, because a
Codex host has no Claude judge.

The Fable-unavailable rule applies after routing: wherever a line names `judge-fable` and Fable is
unavailable or declined, the controller dispatches `judge-opus` and says so. `review-route` does
not know about it, because it is a session fact, not a plan fact.

## 4. The risk >= 2 seat

1. **Astra reviews.** `run-codex-review.sh --kind task --tier heavy` with the task-review prompt,
   writing `<workspace>/task-<N>-review-codex.json`.
2. **Fable reviews and rules.** One `judge-fable` dispatch with the ordinary task-reviewer inputs
   plus a final section that names the Astra file's **path**, never its content.

**Ordering is structural.** The prompt tells Fable to write its own findings, verdicts and
scores in full, and only then to open the Astra file and append a `### Codex findings` section:
one line per Astra finding and per Astra `cannot_verify` item, each `CONFIRMED` or `REJECTED`
with a reason. Passing a path rather than pasted findings is the enforcement available: Fable
cannot anchor on text it has not read yet. The output format puts Fable's own sections first, so
a reply that reverses the order is visibly malformed and is re-dispatched.

**Scores are Fable's.** A CONFIRMED Astra finding that Fable's own pass missed may lower a score
and joins the finding list marked `(from codex)`; reading Astra never raises a score. The
finding set that drives the fix loop is Fable's findings plus the CONFIRMED Astra findings. A
CONFIRMED Astra `cannot_verify` item goes to the ruling seat as a `cannot-verify` item, like
Fable's own.

**This replaces the three-seat mean for risk 3.** The `risk3-spread` ruling kind is retired from
`subagent-driven-development`'s kinds table, `references/ruling-prompt.md`, and
`executing-plans`' list of kinds it does not run.

**Astra produced nothing.** On `TIMEOUT` or `FAILED`, dispatch `judge-fable` with the ordinary
prompt and no Codex section, say so, and record it. Never re-run the Codex seat: the runner has
already spent its one fallback.

## 5. Plan review

| Round | Seat | Reads |
|---|---|---|
| 1 | `codex:plan` (`gpt-6-astra / high`) | the whole plan |
| 1, Codex produced nothing | `judge-fable`, substitution said aloud | the whole plan |
| 2, 3 | `judge-opus` | the delta, the prior round's findings, and the whole plan as needed |

**Snapshots.** Before each round's dispatch, the planner copies the plan to
`<workspace>/plan-round-<r>.md`. The round's findings land in
`<workspace>/plan-review-round-<r>.json` (Codex) or `.md` (Claude). Plans are not committed until
the handoff, so git cannot supply the delta; the snapshot does.

**Round 1 on Codex.** The prompt is `references/plan-reviewer-prompt.md` with its Output Format
paragraph replaced by the schema, as the risk-3 seat already does for the task prompt. The runner
validates the output against `criteria/codex-plan-review-schema.json` (§6).

**Rounds 2 and 3** use a delta variant added to `plan-reviewer-prompt.md`. Its inputs are the
plan, the spec, the lint file, `diff -u plan-round-<r-1>.md PLAN_FILE` written to
`<workspace>/plan-delta-<r>.diff`, and the prior round's findings. It returns, in order: one
`ADDRESSED` / `NOT ADDRESSED` line per prior Critical or Important finding; new findings in the
existing grammar; four scores for the whole plan. It is told to check every cross-task name the
delta touches against the tasks that produce and consume it.

**Record line** is unchanged in shape and names the last round's seat:
`**Plan review:** <date> — codex gpt-6-astra / high — … (round 1)` or `— dr-superpowers:judge-opus
— … (round r)`. `plan-lint` already accepts either.

## 6. `scripts/run-codex-review.sh`

- **`--kind task`** is accepted as an alias of `risk3`: the same command, schema and validation.
  `risk3` stays accepted, so sub-project 7's callers and tests keep working.
- **`--tier light|heavy`** for `task` and `risk3`; default `heavy`, which is today's behaviour.
  `light` selects the `codex-judge` block's last row directly, skips the catalog check (the last
  row is the known-good rung) and attempts no fallback, because the row that ran is already the
  fallback row. `--tier` with `plan` or `final` is a usage error.
- **`--kind plan`** requires `--prompt`, runs `codex exec -s read-only --output-schema
  <plan-schema> -o <out> -C <cwd>` on the heavy selection with its fallback, and is valid when the
  output parses with `executability`, `coherence`, `coverage`, `assumptions` and `findings`.
- **New `criteria/codex-plan-review-schema.json`:** the four criteria as integers 1-20, and
  `findings` as objects of `severity` (`Critical` / `Important` / `Minor`), `where` (string,
  `Task N` or `header`) and `summary`. `additionalProperties: false` throughout, matching
  `codex-review-schema.json`.
- The status line, exit codes, refusal detection and outcome policy are unchanged.

## 7. Availability and the outcome policy

Every Codex seat resolves through the runner, which reads `detect-executors.sh` on every run.
The controller acts on the status line alone:

| Status | Task seat | Plan round 1 |
|---|---|---|
| `OK` | use the report | use the report |
| `FALLBACK`, or last row with `OK` on a `heavy` run | use the report; say the substitution with the runner's reason or `evidence=` | same |
| `TIMEOUT`, `FAILED` | dispatch the route's `fallback` seat; say so with the reason | dispatch `judge-fable`; say so |

A `light` run naming the last row with `OK` is not a substitution: it is the rung that tier
selects.

**Ledger.** The task's complete line replaces `, K=3` with a seat clause inside the scores
clause: `, seat codex gpt-5.6-sol/high`, `, seat codex gpt-6-astra/high+judge-fable`, or
`, seat judge-opus (codex FAILED — <reason>)`. No script parses the old marker (checked
2026-09-15: it appears only in `subagent-driven-development/SKILL.md`).

**Reading a Codex task report.** The controller reads the JSON's `spec_verdict`, `task_quality`,
the four scores, `findings` and `cannot_verify`, and applies the existing bands and fix-loop
trigger to them unchanged. A report that fails to parse was already classified `FAILED` by the
runner.

## 8. `plan-lint`: the lazy probe

Today `plan-lint:214-221` validates an `**Executor:**` line when present but never notices its
absence.

- **Grammar:** `plan-lint PLAN_FILE [--amendments FILE] [--no-probe]`, flags in any order after
  the plan.
- **Candidates:** on a Claude-host plan, each task or part with no `**Override:**` line, Rule S
  clean, `total >= min_score`, `risk <= max_risk`, and no `**Executor:**` line.
- **Inline plans are skipped:** `**Executor:**` lines are inert under inline execution, so a
  warning there would be noise.
- **Lazy:** the scan runs first and collects candidates. Only when at least one exists, and
  `--no-probe` is absent, does it run the roster once — `bash "${PLAN_LINT_ROSTER:-$HERE/detect-executors.sh}"`
  under `timeout 30` (measured 2.0s).
- **When Codex is usable**, one line per candidate:
  `WARN Task N: lane-eligible with no **Executor:** line (codex <model> / <effort>)`, the rung
  taken from `codex-assignment` for its total.
- **When Codex is unusable, the probe fails, or times out:** no line. A plan without Executor
  lines is correct on a machine without Codex.
- **Callers:** `scripts/plan-amend` passes `--no-probe`, since it compares only ERROR lines and
  runs `plan-lint` twice. `tests/plan-lint.test.sh` sets `PLAN_LINT_ROSTER` to a stub for every
  existing case and adds usable, unusable and `--no-probe` cases.

A WARN obeys writing-plans' existing rule: fix it — add the `**Executor:**` line and the header's
`> **External executors:** codex` line — or explain it in one Assumptions line (a batched task is
the usual reason).

## 9. Agents and the Seats table

- **New `agents/judge-sonnet-high.md`:** the `judge-opus` body with `model: sonnet`, `effort:
  high`, and a description naming its one seat — the Claude task reviewer for totals 0-1 when
  Codex is not the reviewer.
- **`agents/judge-opus.md` description** states both roles: the tier seat (task reviews at totals
  2-4 when Codex is not the reviewer, plan-review rounds 2 and 3) and the stand-in for
  `judge-fable` when Fable is unavailable or declined.
- **`subagent-driven-development` Seats table:** the Task reviewer row becomes "the seat
  `scripts/review-route` prints (§3), with its fallback on `TIMEOUT`/`FAILED`"; the section
  "Risk 3" becomes "Risk 2 and above" and describes §4.
- **`writing-plans` Lint and Review** and `references/plan-reviewer-prompt.md` describe §5.

## 10. The lane declared on for this repository

`docs/superpowers/distilled/constraints.md` is created with one entry in the field format
`reference/project-state.md` fixes (`Set by`, `Scope`, `Source`): the Codex executor lane is on
for this repository — when `detect-executors.sh` reports Codex usable, the planner ticks it
without asking.

Two edits make that line reachable:

- **`reference/external-executor.md` §Planning** reads `distilled/constraints.md` before
  rendering the roster question, and skips the question when a constraint declares the lane on
  and the executor is usable. Today writing-plans is not among that file's readers.
- **`reference/project-state.md`** says `distilled/*.md` are written only by
  dr-superpowers:distilling-docs. It gains one exception — an entry an approved spec's owner
  decisions name — and adds `dr-superpowers:writing-plans` to the readers of `constraints.md`.
  Without the exception this spec would break the rule it depends on.

## 11. Gates before it ships

Both gates produce evidence no test can; both run before the final review.

**Calibration.** Run `review-route`'s `codex:plan` seat on four plans and compare with their
recorded `**Plan review:**` lines:

| Plan | Version replayed | Recorded (e / c / v / a) |
|---|---|---|
| `2026-09-14-dr-superpowers-project-state.md` | `d6c288c` — the exact input to its round 3 | 17 / 16 / 17 / 16 |
| `2026-09-14-dr-superpowers-judge-seats.md` | as committed | 17 / 18 / 16 / 16 |
| `2026-09-12-dr-superpowers-inline-mode.md` | as committed | 17 / 18 / 14 / 16 |
| `2026-09-12-dr-superpowers-small-model-planning.md` | as committed | 17 / 17 / 16 / 17 |

Passes only if every axis lands within +/-2 of the recorded score **and** the `d6c288c` replay
reports both defects its round 3 caught: the test helper `absent` defined in Task 3 and called
only in Task 11, and the vacuous assertion needles (`"CLAUDE.md"`, `"optional"`, `'seven'`,
`'exit 0'`) that `e3506c4` replaced.

Correction to the draft: only project-state's pre-fix version exists in git (`ffd604f`,
`d6c288c`, `e3506c4`). The other three plans were committed once, after their last review round's
fixes, so their replays score a slightly better plan than the one their recorded scores came
from. Any miss — on any plan — stops the plan at that task as BLOCKED with the numbers, and your
human partner rules; the version caveat is part of that report, not an automatic pass. Four
Codex runs, no Claude quota. Results go to
`docs/superpowers/notes/2026-09-15-review-routing-calibration.md`.

**Smoke test.** One real run of `scripts/run-codex-task.sh` in a disposable linked worktree, on a
one-file brief, at `gpt-5.5 / medium`. Passes on `status=DONE exit=0` with a one-commit range;
the worktree is removed afterwards. The wrapper is untouched since Codex 0.153.4 while the CLI is
now 0.154.0, and it reports a CLI parse failure as `BLOCKED`, which reads as a model giving up —
so `exit=2` here is a wrapper/CLI mismatch to fix, not a lane to trust. Result recorded in the
same notes file.

## 12. Prose and files this changes

| File | Change |
|---|---|
| `scripts/review-route` (new) | §3 |
| `scripts/run-codex-review.sh` | §6 |
| `criteria/codex-plan-review-schema.json` (new) | §6 |
| `scripts/plan-lint`, `scripts/plan-amend` | §8 |
| `agents/judge-sonnet-high.md` (new), `agents/judge-opus.md` | §9 |
| `skills/subagent-driven-development/SKILL.md` | Seats table, Risk section, kinds table, complete-line marker |
| `skills/subagent-driven-development/references/task-reviewer-prompt.md` | the Codex-findings section (§4) |
| `skills/subagent-driven-development/references/ruling-prompt.md` | drop `risk3-spread` |
| `skills/executing-plans/SKILL.md` | drop `risk3-spread` from the kinds it does not run |
| `skills/writing-plans/SKILL.md`, `references/plan-reviewer-prompt.md` | §5 |
| `reference/external-executor.md` | §Planning (§10); §Risk-3 Codex seat becomes the task and risk seats (§4, §7) |
| `reference/ladder.md` | `codex-judge` prose: tiers `light` / `heavy` and their callers |
| `reference/project-state.md` | §10 |
| `README.md` | the cross-family review paragraph and the risk-3 sentence |
| `docs/superpowers/distilled/constraints.md` (new) | §10 |
| `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` | §14 |
| both plugin manifests | 1.9.0 |

Suites: `tests/codex-review.test.sh` (kinds, tiers, plan schema), `tests/plan-lint.test.sh`
(probe), a new `tests/review-route.test.sh` (every row of §3, batches, parts, exit 2),
and `tests/fleet.test.sh`, whose exact 19-agent list becomes 20. `tests/lanes.test.sh` needs no
change: it pins the `codex-judge` block's two rows, and this design changes only the prose that
explains how they are selected.

## 13. Verification

- `node scripts/validate-repository.mjs`
- `node scripts/test-all.mjs`, plus the dr-superpowers bash suites; the known
  `tests/ui-discovery.test.mjs` `rg: command not found` failure on this machine predates this work.
- `claude plugin validate` on the marketplace and every Claude plugin.
- Both gates in §11.
- Every command bounded; every process started is stopped.

## 14. Program design amendment

Appended to §6 of the program design, after the 2026-09-14 sub-project 7 amendment:

> **Amendment 2026-09-15 (sub-project 8 spec).** The decomposition gains an eighth sub-project,
> "Review routing", after Codex judge seats. Per-task review moves to Codex by default —
> `gpt-5.6-sol / high` for totals 0-3, `gpt-6-astra / high` for 4-6 — with Claude judges as named
> fallbacks (`judge-sonnet-high`, new; `judge-opus`; `judge-fable`) on a Codex seat that produced
> nothing. A task carrying an `**Executor:**` line is always reviewed by Claude, so Codex never
> reviews its own work. Risk >= 2 is reviewed by Astra and then by Fable, which rules on Astra's
> findings in the same pass; this replaces the three-seat risk-3 mean, and the `risk3-spread`
> ruling kind is retired. Plan review takes Codex Astra for round 1 and `judge-opus` for delta
> rounds 2 and 3; rounds are not cut. A new `scripts/review-route` holds the routing table;
> `run-codex-review.sh` gains `--kind task|plan` and `--tier light|heavy`; `plan-lint` gains a
> lazy lane probe with `--no-probe`. Shipping is gated on a calibration replay of four recorded
> plan reviews and one real executor-lane smoke run. A session gate (`scripts/codex-gate`) reads
> the official codex plugin's install state and account rate limits through the plugin's own
> client, overturning the 2026-09-14 ruling that the plugin is not the substrate; when Codex is
> unusable or not yet trusted by both gates, every Codex seat, the lane and the lane probe are
> skipped for the session and Claude seats take over. The shipping gates run only when Codex is
> usable and record `PENDING` otherwise. A ninth sub-project, "Codex through the plugin", moves
> `run-codex-review.sh`, `run-codex-task.sh` and the executor roster onto the plugin's client.
> Details: `docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md` (§15).

## 15. Amendment 2026-09-15: the Codex session gate

Execution stopped at the calibration gate: all four replays returned `status=FAILED` on
`You've hit your usage limit ... try again at Sep 20th, 2026 5:03 PM`. The owner then ruled that
a Codex outage must degrade the process, not block it, and that Codex in Claude Code is reached
only through the official codex plugin. A `judge-fable` design review (verdict REVISE) shaped
the rulings below; the owner accepted every recommendation. This section overrides §1-§14
wherever they disagree.

### 15.1 Owner rulings (binding)

10. **Codex out of quota never fails a task.** The seat falls back to its Claude seat, and Codex
    is skipped for the rest of the session.
11. **Availability is confirmed before Codex is first needed.** If Codex is unavailable for any
    reason, the process ignores everything Codex-related: Codex review seats, the executor lane,
    and `plan-lint`'s lane probe.
12. **The codex plugin is the substrate.** This overturns the program design's 2026-09-14 ruling
    that "the official OpenAI `codex` plugin is deliberately not adopted as the substrate". What
    changed is the owner's requirement. Its objections - no caller schema or prompt, no effort,
    no deadline, no backgrounding, no job id, a detached broker - are answered by using the
    plugin's client library rather than its commands, in direct mode (`disableBroker: true`),
    with a deadline the caller owns. The coupling to an internal library is accepted and bounded
    by a version allowlist that fails closed.
13. **The boundary.** dr-superpowers never names the `codex` executable and never reads
    Codex-owned state; the plugin may, because it owns the binary. The gate in this section meets
    that boundary. The existing runners (`run-codex-review.sh`, `run-codex-task.sh`,
    `detect-executors.sh`) still call the binary; moving them onto the plugin is sub-project 9
    (§15.8).
14. **Codex is off by default until it is trusted.** Codex seats and the lane are used only when
    the gate reports the plugin usable *and* both shipping gates of §11 have passed. Until then
    the gate reports `available=false reason=untrusted`.
15. **The gate runs lazily**, at the first Codex need in a session, and answers from a per-session
    cache afterwards. It is not a SessionStart hook: a hook would start a Codex app-server on
    every session, Codex-using or not.
16. **The session key** is the Claude Code session id plus the quota reset time (§15.3).
17. **The availability signal** is `ordinaryUsageAllowed === true` and
    `rateLimits.primary.usedPercent < 100`. Credits and the per-model entries in
    `rateLimitsByLimitId` are ignored.
18. **The model catalog** stays a read of `models_cache.json` by `detect-executors.sh` for now;
    sub-project 9 settles it.

### 15.2 `scripts/codex-plugin` - the locator

```
codex-plugin
```

Prints one line; exit 0 when the plugin is usable, 1 when it is not, 2 on a usage error or a
missing `jq`:

```
codex-plugin ok root=<install path> version=<v>
codex-plugin off reason=<plugin-not-enabled|plugin-not-installed|plugin-missing|plugin-version:<v>>
```

- **Config dir:** `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`. Verified 2026-09-15: this session's Bash
  environment carries `CLAUDE_CONFIG_DIR=C:/Users/quang/.claude-alt`.
- **Enabled:** `enabledPlugins["codex@openai-codex"]` is `true`, taking the last value defined in
  `<config>/settings.json`, then `<repo>/.claude/settings.json`, then
  `<repo>/.claude/settings.local.json` - user, project, local precedence. Not `true` =>
  `plugin-not-enabled`. Verified 2026-09-15: the `.claude-alt` profile registers the
  `openai-codex` marketplace but does not enable the plugin; the owner enables it.
- **Installed:** `<config>/plugins/installed_plugins.json` has a `plugins["codex@openai-codex"]`
  entry, giving `installPath` and `version`; none => `plugin-not-installed`. The install path must
  hold `.claude-plugin/plugin.json` with the same `version`, and `scripts/lib/app-server.mjs`;
  else `plugin-missing`.
- **Allowlist:** the version must appear in `reference/codex-plugin.json` `versions`; else
  `plugin-version:<v>`. The file ships with `["1.0.3"]`.

### 15.3 `scripts/codex-gate` - the session gate

```
codex-gate [--refresh]
```

One line on stdout, exit 0 whatever the answer; exit 2 on a usage error or a missing `node` or
`jq`:

```
codex-gate available=<true|false> usable=<true|false> reason=<r> resets_at=<iso|-> source=<probe|cache>
```

**Session id:** `$CLAUDE_CODE_SESSION_ID` (verified present in this session's Bash environment);
else none. With no session id the gate probes on every call and consumers treat Codex as off.

**Session file:** `${DR_CODEX_SESSION_FILE:-<primary checkout>/.superpowers/codex-session.json}`,
where the primary checkout is the one `git rev-parse --git-common-dir` belongs to, so linked
worktrees share it. Fields: `session_id`, `available`, `usable`, `trusted`, `reason`,
`checked_at`, `resets_at` (ISO or null), `plugin_version`.

**Cache.** Without `--refresh`, when a session id exists and equals the file's: a file with
`usable: true` is reused; a file with `usable: false` is reused while `resets_at` is null or in
the future. Anything else probes.

**Probe**, fail-closed at every step, the first failure naming the reason:

1. `scripts/codex-plugin` - its `off` reason.
2. `node scripts/lib/codex-gate.mjs <root>` imports `<root>/scripts/lib/app-server.mjs`; no
   `CodexAppServerClient.connect` function => `plugin-api`.
3. `connect(<cwd>, { disableBroker: true })`, then `account/read`. Logged in when `account.type`
   is `chatgpt` or `apiKey`, or `requiresOpenaiAuth` is `false` - the rule the plugin's own
   `buildAppServerAuthStatus` applies. Else `logged-out`. A connect that throws => `plugin-api`.
4. `account/rateLimits/read`. An error whose message contains `unknown variant` or
   `unknown method` => `method-missing`; any other error, or a response without a boolean
   `ordinaryUsageAllowed` => `plugin-api`. Ruling 17 false => `quota`, with
   `resets_at = rateLimits.primary.resetsAt` (epoch seconds) as ISO, or null when absent.
5. The whole probe runs under a 30-second deadline owned by the script
   (`DR_CODEX_GATE_TIMEOUT_MS` overrides it): on expiry it calls `close()` on the client, which
   ends the app-server process tree, and reports `timeout`. It never relies on coreutils
   `timeout`, which on Windows kills only `node` and strands the app-server.
6. The client is closed on every path.

Verified 2026-09-15 with a probe script: step 4 returned `ordinaryUsageAllowed: false`,
`primary.usedPercent: 100`, `resetsAt: 1789898607` (2026-09-20 17:03 +07), with no model call
and no Codex process left running.

**Trust.** `usable` is the probe's answer. `trusted` is `reference/codex-plugin.json`
`trust.calibration == "pass"` and `trust.smoke == "pass"`, read on every call, cache or probe.
`available = usable && trusted`. `reason` is the probe's failure, else `untrusted`, else `ok`.

### 15.4 Readers of the session file - `scripts/lib/codex-session.sh`

- **`codex_session_on`** succeeds only when the file exists, its `session_id` equals the current
  session id, and `available` is `true`. Every other state is off: routing fails closed.
- **`codex_session_refused`** succeeds only when the file's `session_id` equals the current one
  and `usable` is `false`, printing the reason. A missing file refuses nothing, so callers that
  predate the gate keep their behaviour.
- **`codex_session_mark_off <reason>`** rewrites the file for the current session with `usable`
  and `available` `false` and `resets_at` null. With no session id it does nothing.

### 15.5 What reads it

- **`review-route`** (overrides §3 when Codex is off). When `codex_session_on` fails, Executor
  rows 1-2 are unchanged; risk >= 2 => `primary=dr-superpowers:judge-fable fallback=-`; every
  band row => `primary=<band judge> fallback=-`; plan round 1 =>
  `primary=dr-superpowers:judge-fable fallback=-`; rounds 2+ are unchanged. Every changed line
  prints `reason=codex-off`. `review-route` still probes nothing: it reads a file.
- **`run-codex-review.sh`**, every kind. When `codex_session_refused` succeeds, before the roster
  runs, it prints the existing unusable line `codex-judge none/none status=FAILED exit=0
  out=<out> evidence=unknown`, the reason on stderr, and exits 1. After a run whose error lines
  (the existing `error_lines`) match `usage limit|rate_limit_reached`, it calls
  `codex_session_mark_off quota` and prints the run's ordinary `FAILED` line. A quota error is
  never a refusal, so it never takes the fallback row. This is the only change to `--kind risk3`
  and `--kind final`, and it fires only when the session file says Codex is unusable or a run
  hits the quota.
- **`plan-lint`** (adds to §8's trigger). The lane probe runs only when `codex_session_on`
  succeeds; otherwise no WARN lines.
- **Skills.** `writing-plans` runs `scripts/codex-gate` before its roster question and before each
  review round's `review-route`; `subagent-driven-development` before each `review-route` and
  before dispatching an Executor task; `reference/external-executor.md` §Planning renders the
  roster question and ticks the lane only when the gate says `available=true`. The session says
  the gate line aloud when `source=probe`. After any executor run that is not `DONE`, the
  controller runs `scripts/codex-gate --refresh` before the next Codex use. When the gate says
  `available=false`, an `**Executor:**` task runs on its `**Implementer:**` agent, recorded with
  the existing substitution ledger line quoting the gate's `reason`.

§7's outcome table gains a row: **gate `available=false`** => no Codex seat runs; the route
already names the Claude seat.

### 15.6 The shipping gates become conditional

§11 still defines both gates, with these changes:

- **Each runs only when `scripts/codex-gate` reports `usable=true`.** Otherwise the notes file
  records the gate as `PENDING — codex unusable: <reason>` and execution continues.
- **A gate that runs and passes sets its `trust` field** in `reference/codex-plugin.json` to
  `pass`, in the same commit as the notes. A gate that runs and fails still stops the plan as
  BLOCKED, as §11 says.
- **The notes record the Codex version from the plugin:** `codex.detail` from
  `node <root>/scripts/codex-companion.mjs setup --json`, not `codex --version`.

With the quota exhausted until 2026-09-20, 1.9.0 is expected to ship with both gates `PENDING`,
so every Codex seat and the lane stay off until they pass.

### 15.7 Files and suites this adds

| File | Change |
|---|---|
| `reference/codex-plugin.json` (new) | allowlist and trust record |
| `scripts/codex-plugin` (new) | §15.2 |
| `scripts/codex-gate`, `scripts/lib/codex-gate.mjs` (new) | §15.3 |
| `scripts/lib/codex-session.sh` (new) | §15.4 |
| `scripts/review-route`, `scripts/run-codex-review.sh`, `scripts/plan-lint` | §15.5 |
| `skills/writing-plans/SKILL.md`, `skills/subagent-driven-development/SKILL.md`, `reference/external-executor.md` | §15.5 |

New suite `tests/codex-gate.test.sh` runs against a stub config dir (settings and
`installed_plugins.json` fixtures) and a stub plugin root whose `scripts/lib/app-server.mjs`
exports a scripted `CodexAppServerClient` (usable, quota, logged-out, method-missing, a hung
connect). `tests/review-route.test.sh`, `tests/codex-review.test.sh` and
`tests/plan-lint.test.sh` gain Codex-off cases driven by `DR_CODEX_SESSION_FILE` and
`CLAUDE_CODE_SESSION_ID`. No test starts a real Codex.

### 15.8 Sub-project 9 - Codex through the plugin

Out of scope here, recorded so the program amendment names it: a plugin-backed roster replacing
`detect-executors.sh`; `run-codex-review.sh` and `run-codex-task.sh` launching through the
plugin's `scripts/lib/codex.mjs` (`runAppServerTurn` with an output schema, model, effort,
sandbox and exact-thread resume) in direct mode, with an in-script deadline that sends
`turn/interrupt` and closes the client; the model-catalog decision (ruling 18); stub-plugin
fixtures for those suites; and its own calibration and smoke evidence through the new path. It
lifts this plan's constraints on `run-codex-task.sh`, `detect-executors.sh` and the `risk3` /
`final` argv.
