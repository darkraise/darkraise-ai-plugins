# dcc-superpower-companions

Extends [superpowers](https://github.com/obra/superpowers) so that every task in
an implementation plan records which implementer subagent runs it, chosen from a
grid of model and reasoning-effort pairings.

## Why

Superpowers already advises picking cheap, standard, or capable models per task.
Two things were missing.

`writing-plans` has no field for the choice, so the decision is invisible in the
plan and re-derived from memory at dispatch. And reasoning effort is unreachable
at dispatch time: the Agent tool exposes a `model` parameter but no `effort`
parameter, so effort can only be set in a subagent definition's frontmatter.
Superpowers dispatches the built-in `general-purpose` agent, so every implementer
runs at the session's effort level regardless of task difficulty.

This plugin ships pre-baked agent definitions, which makes effort reachable, and
three skills: two that write the choice into the plan and read it back, and one
that settles an open approach decision before the choice is made.

## What you get

**Nineteen agents in three classes.** Seven execution implementers - Sonnet 5
and Opus 5 at `low`, `medium`, and `high`, plus one Haiku 4.5 agent - are
everything a score can reach. Nine reserve implementers - the `xhigh` and `max`
efforts, and every Fable 5 tier - are reachable only by a human override, or by
a task that has already been split once and still exhausted `impl-opus-high`.
Three read-only role agents - `judge-fable`, its `judge-opus` fallback, and
`scout-sonnet` - whose `tools:` frontmatter omits `Edit`, `Write`, and `Agent`,
so a reviewer that cannot modify the tree or spawn subagents is a fact about the
registry rather than a request in a prompt.

The reserve exists so that a human ruling, and a task that genuinely cannot be
split any further, both have somewhere to go. It is not a way around the gate:
above `impl-opus-high` the first answer to a hard task is still to split it, and
the reserve is only entered when that split has already been spent.

**A four-axis rubric that gates the plan.** Files, spec completeness, coupling,
and risk, each scored 0 to 3. Three of those four measure how the task was
drawn, not how hard the change is, so Rule S sends a task scoring 4 or more
across them back to be split rather than to a larger model. That cap is what
makes the assignment table stop at 6, which is exactly the seven execution
implementers.

**An escalation ladder.** Every execution implementer has exactly one successor,
changing model before effort except at the two Opus effort rows, where Opus is
already the top model and there is nowhere else to go. Walks terminate at a
SPLIT action rather than an agent, and only a task that survives that split
enters the reserve chain, which terminates at BLOCKED. Used at superpowers' fix
rounds 4 and 5, at its BLOCKED handler, and at round 3 when the re-review
reports stalled progress.

**Criteria-scored reviews.** `criteria/` holds narrow scored criteria adapted
from LLM-as-a-Verifier (arXiv:2607.05391): a ground-truth note the judge sees on
every evaluation, and 2 to 4 criteria that each say where to look, what scores
high, what scores low, and what to ignore. Reviews return a 1-to-20 score per
criterion alongside superpowers' own verdicts - alongside, never replacing them,
because its fix loop keys on those verdicts. Risk-3 tasks are scored three times
and averaged, and a spread above 6 points sends the diff to the controller
instead of to the mean.

**Best-of-3 approach selection.** `selecting-approaches` gates an open approach
decision to inline, one advisory pass, or three scouts ranked by a judge in a
ring pass that cancels positional bias. Five numbered skip conditions send most
decisions to inline, including bug fixes with a located root cause - where
ranking candidates generated before the root cause is known would launder
guesses into a confident pick.

**An external executor lane.** A task scoring 2 to 4 with `risk <= 1` can run on
the Codex CLI instead of a Claude implementer, for quota offload onto a separate
ChatGPT subscription and for a second model family in the loop. The lane is a
gate in front of the assignment table, never a rung on the escalation ladder:
offload selects downward at the cheap end while the ladder only moves upward, and
one total order cannot express both. The Claude ladder stays the sole backstop,
so its termination proof is untouched.

The gate floors at score 2 on purpose. Rule S caps `reducible` at 3, so under
`risk <= 1` the eligible totals are exactly 2, 3, and 4; without the floor the
gate would reduce to `risk <= 1` and capture nearly every task by count, and it
would offload score-0 work where the displaced agent is `impl-haiku` and the
wrapper costs more to orchestrate than it saves.

`**Implementer:**` still names the Claude agent for the score. `**Executor:**` is
an override on a second line, which is what makes a machine without Codex, a cold
session, and an executor whose auth has lapsed all degrade by reading a line that
is already there rather than re-deriving the assignment at dispatch. Under
`superpowers:executing-plans`, which never dispatches subagents, both lines are
simply inert instead - nothing dispatches, so nothing falls back.

These facts were probed against Codex 0.151.0 on Windows with
ChatGPT-subscription auth on 2026-08-31, and the tables depend on all of them:

- Only `gpt-5.5` and `gpt-5.6-sol` are available. `luna` and `terra` are rejected
  with HTTP 400 and Codex holds no metadata for either.
- Valid reasoning efforts are `low`, `medium`, `high`, `xhigh`, `ultra`.
  `minimal` is rejected. The CLI validates neither model nor effort locally - it
  echoes any string and fails at the API - so `scripts/run-codex-task.sh`
  validates both before spawning anything.
- Codex **cannot commit**. Its Windows restricted-token sandbox denies writes to
  `.git` under `-s workspace-write`, which `codex sandbox -- git add -A`
  reproduces with no model call. The wrapper owns the commit, so the ledger's
  commit range is measured rather than reported. It also inlines the repository's
  `CLAUDE.md` into every prompt, because Codex natively reads only `AGENTS.md`,
  and passes the model's own conventional-commit subject to `git commit`
  unmodified.
- `codex exec resume` does **not** inherit `-m` or `-c model_reasoning_effort`.
  The wrapper re-sends every per-invocation flag, because a bare resume would
  silently run a fix round at the user's config default instead of the recorded
  tier.

A different machine, account, or Codex version must re-probe before trusting the
tables in `reference/ladder.md`.

**Cross-family review.** On a risk-3 task one of the three judges is Codex, and
the final whole-branch review gains a `codex exec review` round whose findings
are deduped with superpowers' own and then verified by `judge-fable` - or
`judge-opus` when Fable is unavailable, the same fallback every judge seat uses. Risk-3
tasks are excluded from the executor lane, so the risk-3 judge seat never
reviews Codex's own work. The final whole-branch round is different: the branch
contains whatever the executor lane produced, so that round is not
self-review-free, which is why every finding goes through a third seat.

## Requirements

**superpowers must be installed.** This plugin has no standalone use, and the
coupling is harder than "it extends superpowers": every agent definition
preloads `superpowers:verification-before-completion` through its `skills:`
frontmatter, and the assigning and dispatching skills defer to superpowers'
`sdd-workspace`, `task-brief`, and `review-package` scripts. Claude Code plugin
manifests cannot declare a dependency on another plugin, so nothing enforces
this — with superpowers absent, the fleet loads without its preloaded skill and
the dispatch instructions point at scripts that are not there.

**`bash` and `jq`.** Both are hard requirements of the external executor lane:
`scripts/detect-executors.sh` builds every field with `jq`, and
`scripts/run-codex-task.sh` parses Codex's verdict with it. Each exits 2 with a
message naming the dependency rather than degrading, because a missing `jq`
would otherwise read as "no executor usable" or as a task Codex blocked on. The
hook is the lenient case: without `jq` it degrades to a silent no-op, and
`bash` is required for it to run at all. On Windows that means Git for
Windows. The hook declares `"shell": "bash"` so it takes the Git Bash
route explicitly: without that key Claude Code falls back to PowerShell on a
machine with no Git Bash, where the command is meaningless, and with it the
user gets Claude Code's actionable "requires bash but Git Bash was not found"
message instead.

## How it fires

A `PreToolUse` hook on the `Skill` tool adds context when
`superpowers:writing-plans`, `superpowers:subagent-driven-development`, or
`superpowers:brainstorming` is invoked, and stays silent otherwise.
`superpowers:brainstorming` is matched because that is where an approach
decision is open, and the gate that settles it belongs there rather than after
the plan is drafted. The matcher is the tool name, so the script does run — and
exits without output — on every `Skill` invocation of any kind. That is one
`bash` plus one `jq` per skill call, not zero.

The hook returns `additionalContext` and no `permissionDecision`. It has no
opinion on whether the skill may run, and `defer` in particular would be
actively wrong: it is print-mode only, ignored with a warning in an interactive
session, and in a non-interactive one it defers the `Skill` call itself so the
skill never executes.

`superpowers:executing-plans` is deliberately not matched. It runs plan tasks
inline without subagents, so the `Implementer` lines are inert there, which is
correct rather than broken.

## What a plan looks like

```markdown
### Task 4: Wire the export pipeline

**Files:**
- Create: `src/export/pipeline.ts`

**Interfaces:**
- Consumes: `formatRow(row: Row): string` from Task 2
- Produces: `runExport(cfg: Config): Promise<Report>`

**Implementer:** dcc-superpower-companions:impl-opus-medium
**Evaluation:** files 0 - spec 1 - coupling 2 - risk 2 = 5
**Approach:** inline - skip 2: follows the existing exporter pattern
```

Edit the `**Implementer:**` line to override. The dispatching skill obeys the
line and never recomputes when it is present.

The heading keeps superpowers' `### Task N: <name>` form on purpose.
`scripts/task-brief` finds a task by matching a heading that starts with
`Task <N>`, so a heading like `### Wire the export pipeline (Task 4)` yields an
empty brief and a non-zero exit — and, because the extractor keeps copying
until the next heading it recognizes, quietly appends that task's body to the
previous task's brief.

## Compatibility

The plugin extends four seams. The implementer dispatch names a fleet agent
instead of `general-purpose` and passes no `model` argument. The task-review
seat is a judge agent rather than a general-purpose one, dispatched with a
criteria file appended to superpowers' own reviewer prompt. The scoped
re-review is asked for one extra reading, a progress score, which can pull the
escalation point from round 4 to round 3. And the final whole-branch review
gains a Codex round plus a verification pass over the union of both reviewers'
findings.

Everything else in the superpowers loop is untouched: the brief and report
protocol, the review package, the five-round cap, the breaker and its
adjudication rules, and the handoff to
superpowers:finishing-a-development-branch.

Three superpowers instructions are superseded, and no others.

1. **"Always specify the model explicitly"**, and only for fleet agents whose
   frontmatter pins a model. Passing `model` would override the agent file while
   `effort` kept its frontmatter value, so the agent would run at a tier the
   ledger does not record. The intent survives, since the agent definition pins
   the model.
2. **The final whole-branch review is no longer untouched.** It keeps
   superpowers' own review and model selection and adds a Codex round plus a
   verification pass over the union.
3. **Fix rounds 4 and 5 call for a more capable model**, where an external task
   instead hands back to the Claude assignment-table row for its score - a change
   of model family plus a fresh context, argued as satisfying that rule's intent
   rather than as an exception to it.

The scores the plugin adds to reviews are additive to superpowers' own verdicts
and never replace them, because its fix loop keys on those verdicts.

## Tests

```bash
for t in plugins/dcc-superpower-companions/tests/*.test.sh; do bash "$t"; done
```

Requires `jq` and `git`. No model calls: the executor suites run against a stub
`codex` on `PATH` and a synthetic roster, never the real CLI.

## Reference

`reference/ladder.md` holds the rubric, the assignment table, the escalation
table, and the reserve table. All three skills and the test suite read that one
copy.

`criteria/` holds the verifier criteria; `criteria/TEMPLATE.md` documents the
format. `tests/criteria.test.sh` validates every file in that directory.

`scripts/` holds the external executor lane:

- `detect-executors.sh` emits the JSON roster read at plan time and again as a
  dispatch guard. `usable` means dispatchable, so a batch-capable CLI this
  plugin ships no wrapper for reports `usable: false` with the reason.
- `run-codex-task.sh` runs one plan task on Codex, owns the commit, and prints
  one status line. Exit 0 is `DONE`, 1 is a run that did not reach it, and 2 is
  no status line - either a refusal before launch or a git failure after the run,
  which the dispatching skill tells the controller apart and recovers from
  differently.
- `codex-report-schema.json` is the `--output-schema` the wrapper passes, and
  the shape of the verdict it parses back.
- `codex-task-contract.md` is appended to every prompt the wrapper sends,
  resume rounds included.
