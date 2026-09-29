# dr-superpowers on Sonnet 5.5

Date: 2026-09-29
Status: design, owner-approved section by section on 2026-09-29.
Register: `docs/superpowers/registers/2026-09-29-sonnet-5-5.md` rows 1 and 2.
Precedent: `fedd67a` (tune Opus agents for Opus 5.5).

## Rulings (owner, 2026-09-29)

1. **Shift the ladder, not only the prompts.** Chosen over a prompt-only pass
   and over a prompt pass plus an eval plan.
2. **Sonnet 5.5 takes score 4, nothing more.** Chosen over also moving score 5
   to `impl-sonnet-xhigh` (restructures the execution and reserve sets and
   relies on `xhigh` without eval evidence) and over also lowering score 3 to
   `medium` (no measurement from this repository behind it).

## Facts this design rests on

- Claude Code 2.1.284 resolves the `sonnet` alias to `claude-sonnet-5-5`
  (probe on 2026-09-29: `modelUsage` names `claude-sonnet-5-5`, context window
  1,000,000, max output 128,000). Every `model: sonnet` agent already runs
  Sonnet 5.5; no model ID is pinned.
- Anthropic's launch figures, Sonnet 5.5 vs Opus 5.5: Terminal-Bench 4.0 70.6%
  vs 66.4%; CursorBench 4.0 55.5% vs 57.8%; FrontierCode 1.1 46.2% (max effort)
  vs 54.4%. Price $2/$10 per MTok vs $4/$20. Anthropic positions Sonnet 5.5 for
  well-scoped work and Opus 5.5 for "complex, open-ended work requiring
  sustained judgment". Source: <https://www.anthropic.com/claude-sonnet-5-5>,
  <https://platform.claude.com/docs/en/models/overview>.
- Sonnet 5.5 effort levels are recalibrated against Sonnet 5. Anthropic's start
  points: `medium` for well-specified agentic coding, `high` for harder or
  longer tasks, `xhigh`/`max` only where evals show a gain. Source:
  <https://platform.claude.com/docs/en/build-with-claude/effort> §Recommended
  effort levels for Claude Sonnet 5.5.
- Documented Sonnet 5.5 behaviours, each with a recommended prompt paragraph:
  at `low` it can report a change done without running a check; at `low` and
  `medium` it can check in before a task is finished; at every level it adds
  unrequested tests, docs and files; at `xhigh` and `max` it starts its own
  review rounds and reviewer subagents. Source:
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5>.
- `tests/fleet.test.sh` requires an agent's `effort:` to match its name
  suffix, so this design changes no effort value.

## 1. The Sonnet agents (register row 1)

All paths are under `plugins/dr-superpowers/`.

**Rename.** In `agents/impl-sonnet-{low,medium,high,xhigh,max}.md`,
`agents/judge-sonnet-high.md` and `agents/scout-sonnet.md`, "Sonnet 5" becomes
"Sonnet 5.5" in the `description:` and in the body's "You run on" line. The
`README.md` roster sentence and the `reference/session-budget.md` model-window
row ("1,000,000 for Fable 5.1, Opus 5.5 and Sonnet 5.5"; source: Claude API
model table and a CLI probe, 2026-09-29) change the same way.

**Every Sonnet implementer** gains two paragraphs at the end of its body:

1. The early-stop paragraph the Opus implementers carry since `fedd67a`,
   verbatim:

   > Your final message ends your turn, and the controller reads it as your
   > report. Do not end a turn with a summary that announces the next step, an
   > offer to continue, or a list of decisions none of which blocks the rest of
   > the task: take the step instead, and put any progress note in the same
   > message as your next tool call. End the turn only when the report contract
   > is met, or when you are BLOCKED or NEEDS_CONTEXT. This does not relax any
   > limit the brief sets on risky or destructive actions.

2. A scope paragraph:

   > Change only what the brief asks for. Do not add features, tests, files,
   > docs or refactors the brief does not call for; if you think one would
   > help, say so in your report instead.

**`impl-sonnet-low`** also gains a verification paragraph, Anthropic's text
adapted to the report contract and without its dependency-install clause, so
an implementer never installs packages the brief did not ask for:

> When you change code that can be run, built, or type-checked, run a real
> check that exercises the change before reporting DONE: the project's tests,
> type-checker, or build, or the changed command itself. A syntax-only check,
> or a check command that failed to start, does not count. If no real check can
> run here, report DONE_WITH_CONCERNS and name the check you did not run and
> why.

**`impl-sonnet-xhigh` and `impl-sonnet-max`** also gain a review paragraph:

> When the task is done and its checks pass, write the report and stop. Do not
> start extra rounds of review or hardening on your own, and do not launch
> reviewer subagents: the controller reviews your work after you report. If
> you think a deeper review is worth doing, say so in your report.

**Judge and scout** are renamed only. No prompt under `agents/`, `skills/` or
`reference/` asks a model to put its reasoning in its reply, so the
`reasoning_extraction` refusal category needs no change.

## 2. The ladder shift (register row 2)

### The table

In `reference/ladder.md` the assignment block's row `4 impl-opus-low` becomes
`4 impl-sonnet-high`. The escalation and reserve blocks are unchanged:
`impl-opus-low` remains an execution implementer and an escalation target of
`impl-sonnet-low`, so the seven-implementer set `tests/ladder.test.sh` and
`tests/fleet.test.sh` check is unchanged. A total-4 task that exhausts
`impl-sonnet-high` escalates to `impl-opus-high`, by the existing
model-before-effort rule.

Prose that states or depends on the old row changes with it:

- `reference/ladder.md` §What the range actually reaches: initial assignments
  cluster in the 0 to 4 band, Haiku and Sonnet; Opus is reached at 5 and 6 or
  by escalation.
- `agents/impl-opus-low.md` description: "Escalation rung for impl-sonnet-low;
  no score assigns it." `agents/impl-sonnet-high.md` description: "score 3 or
  4".
- `README.md` §What you get: the seven execution implementers are no longer
  "everything a score can reach" but everything the assignment table and the
  escalation ladder can reach, the wording `tests/fleet.test.sh` already uses.
- `reference/ladder.md` §Reserve table: "Nine implementers exist that no score
  can reach" becomes nine that neither the assignment table nor the escalation
  table reaches, since `impl-opus-low` is now also unassigned but stays on the
  escalation ladder.

### Removing the four-band rule

The four-band rule delegates total-4 tasks from an inline plan while they are
a third of the plan or fewer, and past that third puts the session on Opus. It
exists only because total 4 meant Opus. With total 4 on `impl-sonnet-high`, the
default inline session (`sonnet`, `high` when a total-4 task is present)
already covers it, so the rule is removed:

- `scripts/lib/plan.sh` `plan_delegated`: drop the total-4 counting and the
  `total 4` rows. An inline plan delegates its heavy tasks and the tasks an
  `**Executor:**` line marks, nothing else. Its header comment follows.
- `scripts/plan-lint`: drop the ERROR "inline execution with a
  self-implemented task at total 4 needs --model opus". The existing effort
  check already requires `high` for a total-4 task because its row now names
  `impl-sonnet-high`. `opus` stays an accepted inline model.
- `scripts/plan-revise`: drop `any_four_self`; the recommended inline model is
  `sonnet`.
- Prose: `skills/writing-plans/SKILL.md` §Choosing the Execution line (the
  four-band definition, the third rule, the offloaded-count sentence, and the
  `opus` clause of the inline model rule, which keeps only the all-heavy
  override); `skills/executing-plans/SKILL.md` (the delegation list, the
  Dispatch-line example losing `Task <b> (total 4)`, and the §Preflight clause
  "even when it delegates total-4 tasks"); `skills/using-superpowers/SKILL.md` §Process Depth;
  `reference/delegated-task.md` opening paragraph; `README.md` §Two execution
  modes.
- Tests: the four-band cases in `tests/plan-lint.test.sh`,
  `tests/plan-lib.test.sh`, `tests/plan-revise.test.sh` and
  `tests/inline-mode.test.sh` are rewritten to assert the new behaviour — a
  total-4 task is self-implemented, is never a `total 4` delegation row, and
  needs no `opus` session — and the "wrong agent" fixture expects
  `impl-sonnet-high` for total 4.

### Unchanged

- Review routing: `scripts/review-route` still sends totals 4 to 6 to
  `judge-opus` and risk 3 to Opus, so a total-4 task is implemented by Sonnet
  and reviewed by Opus.
- The Codex external lane: its gate still admits totals 2 to 4 at risk 1 or
  less and its `codex-assignment` row 4 still names `gpt-6-sol high`; a
  `HANDBACK` resolves to the assignment row, now `impl-sonnet-high`.
- Native Codex (`reference/native-codex.md`): its weighted score and its
  "total 4 or less" inline rule are a separate scale.
- Completed plans under `docs/superpowers/plans/`, per the repository rule
  against editing historical plans.

### Plans written before this change

A plan naming `impl-opus-low` for a total-4 task gets the existing `plan-lint`
ERROR "Implementer impl-opus-low does not match the assignment table's
impl-sonnet-high for total 4", which drops to WARN when the task carries an
`**Override:**` line. No compatibility code is added. `reference/ladder.md`
gains one sentence beside §The one legacy floor naming the two fixes: change
the line to `impl-sonnet-high`, or add an `**Override:**` to keep Opus.

## 3. Release and verification

- Commits, one concern each: `feat(superpowers): tune Sonnet agents for Sonnet
  5.5` (§1); `feat(superpowers): route score 4 to Sonnet 5.5` (§2, with the
  four-band removal the new row requires); `chore(superpowers): release
  1.23.0` (both `plugin.json` manifests and any version pin in
  `tests/review-route.test.sh`, as in `a2faed6`).
- Verification: `node scripts/validate-repository.mjs`, every
  `plugins/dr-superpowers/tests/*.test.sh`, and `claude plugin validate` on the
  marketplace and each Claude plugin, all under timeouts, with no process left
  running.
- Out of scope: any effort change and any eval harness. The untracked Opus
  effort-sweep note is the place to add Sonnet seats later.

## Acceptance

- Register row 1: every Sonnet agent names Sonnet 5.5, and carries the
  paragraphs §1 assigns it; `fleet.test.sh` passes.
- Register row 2: the assignment block maps 4 to `impl-sonnet-high`; no
  `plan_delegated` row reads `total 4`; `plan-lint` accepts a `sonnet` inline
  session with a self-implemented total-4 task; `plan-revise` recommends
  `sonnet` for it; every maintained test suite passes.
