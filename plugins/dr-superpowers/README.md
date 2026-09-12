# dr-superpowers

Available for Claude Code and Codex. Install `dr-superpowers@darkraise` from the
repository-root marketplace. Claude uses its registered fleet and hooks; Codex
uses native agent tools and explicit model/effort pairs, with Claude hooks
disabled in its native manifest. The fleet details below describe Claude.

For Codex, read [native-codex.md](reference/native-codex.md). Its `codex-v2` policy
routes scores 0–9 through Luna, Terra, Sol, and Astra. The selector calculates
files + spec + coupling + twice risk from the four raw axes, preserving the
existing split gate. Scouts start at Sol medium; judges start at Astra high.
It filters advertised capabilities at planning and dispatch, preserves human
pins, and records promotions and actual attempts.

Upgrading from a version before 0.6.0 required explicit conversion of old Codex
or Claude plans: preserve the raw axes and original assignments, preview the
recalculated score and proposed assignment, and obtain approval. Old policy
ranks cannot be reused as v2 history.
Claude translates skill and agent names written under older plugin prefixes at
read time, per [legacy-names.md](reference/legacy-names.md); disable the older
plugins before enabling this one. Original assignments and evaluations remain
intact.

Native reviewers have independent contexts, without a promised cross-provider
seat. Enforce read-only tool restrictions when available; otherwise disclose
instruction-only restrictions and compare complete snapshots without concurrent
writers. A mutation blocks continuation and is preserved for inspection.

The Claude-hosted external CLI lane requires an exclusively assigned linked
worktree, stable task IDs, approved file paths, and durable recovery. Read
[external-task-recovery.md](reference/external-task-recovery.md) before offload.
It refuses the primary checkout and initial staged, unstaged, or untracked work.
Only the verified task diff is staged. Other writing agents/watchers and manual
editing must stop in this worktree; fingerprints cannot establish authorship.

A standalone fork of [superpowers](https://github.com/obra/superpowers) 6.3.0
(MIT — see `LICENSES/`) that also records, for every task in an implementation
plan, which implementer subagent runs it, chosen from a grid of model and
reasoning-effort pairings.

## Why

Superpowers already advises picking cheap, standard, or capable models per task.
Two things were missing.

`writing-plans` has no field for the choice, so the decision is invisible in the
plan and re-derived from memory at dispatch. And reasoning effort is unreachable
at dispatch time: the Agent tool exposes a `model` parameter but no `effort`
parameter, so effort can only be set in a subagent definition's frontmatter.
Superpowers dispatches the built-in `general-purpose` agent, so every implementer
runs at the session's effort level regardless of task difficulty.

This plugin ships pre-baked agent definitions, which makes effort reachable.
`writing-plans` writes the choice into the plan, `subagent-driven-development`
reads it back and dispatches it, and `selecting-approaches` settles an open
approach decision before the choice is made.

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
enters the reserve chain, which terminates at BLOCKED. Used at fix rounds 4
and 5, at the BLOCKED handler, and at round 3 when the re-review reports
stalled progress.

**Criteria-scored reviews.** `criteria/` holds narrow scored criteria adapted
from LLM-as-a-Verifier (arXiv:2607.05391): a ground-truth note the judge sees on
every evaluation, and 2 to 4 criteria that each say where to look, what scores
high, what scores low, and what to ignore. Task reviews score four criteria -
spec, scope, verification, quality - 1 to 20 each, alongside the spec and
quality verdicts and never replacing them, because the fix loop keys on those
verdicts. Risk-3 tasks are scored three times
and averaged, and a spread above 6 points sends the diff to the controller
instead of to the mean.

**Best-of-3 approach selection.** `selecting-approaches` gates an open approach
decision to inline, one advisory pass, or three scouts ranked by a judge in a
ring pass that cancels positional bias. Five numbered skip conditions send most
decisions to inline, including bug fixes with a located root cause - where
ranking candidates generated before the root cause is known would launder
guesses into a confident pick.

**Two execution modes, chosen by the plan.** The `**Execution:**` line decides
whether a plan runs under subagent-driven-development, a dispatch and a scored
review per task, or under executing-plans, where one session implements every
task itself. Inline mode is available only when every task scores 3 or less
with none at risk 3 - `plan-lint` refuses the line otherwise - and it trades
per-task review for one whole-branch review at the end, which both modes now
share. A task that will not converge after three fix rounds escalates to
subagent mode at the next task boundary, recorded in the ledger both modes
write.

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
`dr-superpowers:executing-plans`, which dispatches only the ruling seat and the
final review, both lines are simply inert instead - no task is dispatched, so
nothing falls back.

The following observations were made against the external CLI lane on Windows
with ChatGPT-subscription auth on 2026-08-31. They are historical CLI policy
evidence, not native Codex capability declarations:

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
- `codex exec resume` accepts a **narrower flag set than `codex exec`**. It takes
  `-m`, `-c`, `--json`, `--output-schema`, and `-o`, but rejects `-C` and `-s`
  outright - `error: unexpected argument '-C' found`, exit 2, before any model
  call. Those two therefore precede the subcommand, where the parent `codex exec`
  takes them and honours them for the resumed thread. Re-confirmed against
  0.153.4 on 2026-09-06, which is also where this was first caught: the earlier
  argv put every flag after the subcommand, so each fix round on this lane died
  at argument parsing and was reported as an ordinary `BLOCKED`.

A different machine, account, or Codex version must verify advertised capabilities
and supported CLI flags before using the tables. Do not make paid capability
probes. The flag-position fact above is the one that has
already changed once, and it fails silently - the wrapper turns a parse error
into `status=BLOCKED`, which reads as a model that gave up rather than a CLI that
refused. `tests/run-codex-task.test.sh` now asserts the ordering on both the
composed and the spawned argv, but a stub cannot notice a flag the real CLI stops
accepting; only a re-probe can.

**Cross-family review.** On a risk-3 task one of the three judges is Codex, and
the final whole-branch review gains a `codex exec review` round whose findings
are deduped with the Claude reviewer's and then verified by `judge-fable` - or
`judge-opus` when Fable is unavailable, the same fallback every judge seat uses. Risk-3
tasks are excluded from the executor lane, so the risk-3 judge seat never
reviews Codex's own work. The final whole-branch round is different: the branch
contains whatever the executor lane produced, so that round is not
self-review-free, which is why every finding goes through a third seat.

## Requirements

**The superpowers workflow ships in-plugin.** The fork carries the full skill
set — brainstorming through finishing-a-development-branch — frozen at upstream
6.3.0, so no other plugin is required: every agent definition preloads
`dr-superpowers:verification-before-completion` through its `skills:`
frontmatter, and writing-plans and subagent-driven-development use the plugin's own
`scripts/sdd-workspace`, `task-brief`, `review-package`, `next-step`,
`context-size`, `repo-audit`, `plan-lint`, and `plan-amend` — `next-step` ends every session with its next
action and keeps `.superpowers/handoff/latest.md` pointing at it. Disable the
upstream `superpowers` plugin: same-named skills in two enabled plugins can
double-trigger.

**Bash, jq, Git, and GNU timeout/coreutils.** These are requirements of the external executor lane:
`scripts/detect-executors.sh` builds every field with `jq`, and
`scripts/run-codex-task.sh` parses Codex's verdict with it. Each exits 2 with a
message naming the dependency rather than degrading, because a missing `jq`
would otherwise read as "no executor usable" or as a task Codex blocked on. The
SessionStart hook is the lenient case: without `jq` it still injects the entry
point and only skips persisting the session record, and `bash` is required for
it to run at all. On Windows that means Git for
Windows. The hook declares `"shell": "bash"` so it takes the Git Bash
route explicitly: without that key Claude Code falls back to PowerShell on a
machine with no Git Bash, where the command is meaningless, and with it the
user gets Claude Code's actionable "requires bash but Git Bash was not found"
message instead.

## How it fires

A `SessionStart` hook (matcher `startup|resume|clear|compact`) injects the
`dr-superpowers:using-superpowers` entry point as `additionalContext`, so every
session starts with the skill-routing rules — including the pointers to
`selecting-approaches`, implementer assignment in `writing-plans`, and tiered
dispatch in `subagent-driven-development` that a PreToolUse nudge used to add. The same
script persists the session's `transcript_path`, `session_id`, `cwd`, and
`source` to `~/.claude/dr-superpowers/sessions/<sanitized-cwd>.json` (last
writer wins per directory), which `scripts/context-size` reads. On the
`compact` source it also appends a compaction snapshot (see Session budget).
Malformed stdin skips persistence but never blocks the injection, and the
hook always exits 0.

## Session budget

Long sessions cost more than they look: every request re-reads the whole
context, and compaction drops the reports, findings and rulings a controller
needs. dr-superpowers hands off instead.

- **The budget line.** `scripts/task-brief` and `scripts/review-package` end
  with `budget: 312k of 475k (65%) — ok — source: record`, so the controller
  checks before every task and every review at no extra request;
  `scripts/context-size` prints it on demand. At `handoff`, the `handoff`
  skill writes `latest.md` and the plan's `handoff.md` and ends with the
  resume guide from `scripts/next-step`.
- **Stops.** A saved plan, a finished task list under
  subagent-driven-development, and a switch from inline to subagent mode are
  hard stops; executing-plans' finished task list is a soft stop, continuing
  in-session unless the budget says otherwise. So the final whole-branch review
  runs in a fresh session under subagent mode and in the same session under
  inline mode; see [session-budget.md](reference/session-budget.md) for the
  full Stops table.
- **Resuming.** `resume-execution` runs `scripts/repo-audit` — one read-only
  snapshot of branch, worktrees, dirty files, plans in flight and handoff
  staleness — verifies the worktree, and hands control back to the plan's
  execution skill.
- **Compaction.** The SessionStart hook appends a snapshot of what summaries
  drop. Compaction fires at about 93-96% of `autoCompactWindow`, so set the
  window well above the budget — 650000 for the default 475k — and paste the
  Compact Instructions block from
  [session-budget.md](reference/session-budget.md) into your project's
  CLAUDE.md.

## Migrating from 0.x

1.0.0 is standalone and breaking. On a machine with the old setup:

1. **Re-point the marketplace.** The `darkraise` marketplace registration in
   `~/.claude/settings.json` may still name `darkraise/claude-code-plugins`;
   the canonical repository is `darkraise/darkraise-ai-plugins`. Remove and
   re-add the marketplace (or edit the registration) to point there.
2. **Statusline.** `dcc-statusline` is `dr-status` in this catalog; enable
   `dr-status@darkraise` and disable the old name.
3. **Telegram notifications.** `dcc-telegram-notify` is not in this catalog;
   keep it installed from its previous source or drop it.
4. **Disable the superseded plugins:** `superpowers` (its skills now ship
   here), `dcc-superpower-companions` (folded into this plugin), and
   `andrej-karpathy-skills` (its guidelines are folded into the skills where
   they fire).

## What a plan looks like

A plan opens with a header block: Goal, Spec, the `**Execution:**` line that
decides inline or subagent execution, Global Constraints, Contracts (every name
one task produces and another consumes), Assumptions with evidence, and a Task
index. `scripts/plan-lint` checks it, and a judge reviews it against
`criteria/plan-review.md` before it is saved. That Execution line is binding: a
session does not change mode because subagents happen to be available, and only
your explicit instruction overrides it. Each task then reads:

```markdown
### Task 4: Wire the export pipeline

**Files:**
- Create: `src/export/pipeline.ts`

**Interfaces:**
- Consumes: `formatRow(row: Row): string` from Task 2
- Produces: `runExport(cfg: Config): Promise<Report>`

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 0 - spec 1 - coupling 2 - risk 2 = 5
**Approach:** inline - skip 2: follows the existing exporter pattern
```

Edit the `**Implementer:**` line to override. `subagent-driven-development`
obeys the line and never recomputes when it is present. Add
`**Override:** <reason>` below the Evaluation line so that `plan-lint` reports
the deviation as a warning instead of an error.

The heading keeps superpowers' `### Task N: <name>` form on purpose.
`scripts/task-brief` finds a task by matching a heading that starts with
`Task <N>`, so a heading like `### Wire the export pipeline (Task 4)` yields an
empty brief and a non-zero exit — and, because the extractor keeps copying
until the next heading it recognizes, quietly appends that task's body to the
previous task's brief.

## Differences from upstream 6.3.0

The superpowers loop is kept - the brief and report protocol, the review
package, the five-round cap, the breaker (whose adjudication now goes to the ruling seat), and the
handoff to dr-superpowers:finishing-a-development-branch - with these
differences:

1. **Named seats.** The implementer is the fleet agent the plan's
   `**Implementer:**` line names, dispatched with no `model` argument: passing
   one would override the agent file's model while `effort` kept its
   frontmatter value. The task reviewer is a judge agent scoring the criteria
   file. General-purpose seats still name their model explicitly.
2. **Scores and progress.** Task reviews add four 1-to-20 scores alongside the
   verdicts, and the scoped re-review adds a progress reading that can pull
   escalation from round 4 to round 3.
3. **Escalation ladder.** Rounds 4 and 5 and the BLOCKED handler climb
   [ladder.md](reference/ladder.md)'s table, ending in one split and then the
   reserve chain. An external task hands back to its Claude implementer instead.
4. **Cache-aware resumes.** Fix rounds 1 to 3 resume the implementer only while
   its cache is warm - returned under five minutes ago, or under about 100k
   tokens of context - and otherwise dispatch a fresh copy on the same tier.
5. **One ledger grammar.** Every task gets an assigned line and a complete line
   carrying its scores and a checkpoint (done, verified, remaining, discovered
   issues, assumptions), which crash recovery and the final review read.
6. **Cross-family final review.** The final whole-branch review adds a Codex
   round, and a judge verifies the union of both reviewers' findings.
7. **Rulings, not stops.** Dispatch problems - an unknown agent name, an
   unavailable model, an Executor line the wrapper refuses - are logged
   rulings, never silent fallbacks and never stops.
8. **Session budget.** A budget line, a compaction snapshot, and the
   dr-superpowers:handoff / dr-superpowers:resume-execution pair replace
   upstream's unmeasured sessions - see [Session budget](#session-budget).
9. **Small-model planning.** A strong model plans once; small models execute.
   Every task brief carries the header's Global Constraints and Contracts, the
   controller reads only the header and one brief at a time, and judgment
   calls go to a read-only ruling seat (`judge-fable`). Its plan corrections
   land in an append-only `amendments.md` through `scripts/plan-amend`; the
   plan file is never edited during execution.
10. **Two modes, chosen by the plan.** Upstream picks `executing-plans` when
    subagents are unavailable and recommends subagent execution otherwise. Here
    the `**Execution:**` line decides and is binding: `executing-plans` is a
    full inline mode that writes the same ledger, sends its judgment to the
    same ruling seat, and ends at the same shared
    [final-review.md](reference/final-review.md), with no per-task review. A
    task it cannot land in three fix rounds escalates to subagent mode at the
    next task boundary.

Names written under older plugin prefixes resolve through
[legacy-names.md](reference/legacy-names.md).

## Licenses

MIT. `LICENSES/` carries the licenses of the forked and folded projects:
[superpowers](https://github.com/obra/superpowers) by Jesse Vincent (MIT),
frozen at 6.3.0 with no upstream sync, and
[andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills)
(MIT).

## Tests

```bash
for t in plugins/dr-superpowers/tests/*.test.sh; do bash "$t"; done
```

Requires `jq` and `git`. No model calls: the executor suites run against a stub
`codex` on `PATH` and a synthetic roster, never the real CLI.

## Reference

`reference/ladder.md` holds the raw rubric, Rule S, and Claude assignment,
escalation, reserve, and external CLI tables. Native Codex reads
`reference/codex-routing.json`; `reference/native-codex.md` explains its weighted
score, request format, and plan conversion. `scripts/select-native-tier.sh`
validates raw scores and history before returning a native routing decision.

`reference/external-executor.md` holds the Claude-hosted Codex CLI lane,
`reference/legacy-names.md` translates names written under older plugin
prefixes, `reference/session-budget.md` holds the budget numbers, checkpoints,
stops and the Compact Instructions block, and `reference/final-review.md` holds
the whole-branch review both execution skills end at.

`criteria/` holds the verifier criteria, including `plan-review.md` for plan
review and `codex-review-schema.json` for the risk-3 Codex seat; `criteria/TEMPLATE.md` documents the format.
`tests/criteria.test.sh` validates every file in that directory.

`scripts/` holds the external executor lane:

- `detect-executors.sh` emits the JSON roster read at plan time and again as a
  dispatch guard. `usable` means dispatchable, so a batch-capable CLI this
  plugin ships no wrapper for reports `usable: false` with the reason.
- `run-codex-task.sh` runs one plan task on Codex, owns the commit, and prints
  one status line. Exit 0 is `DONE`, 1 is a run that did not reach it, and 2 is
  no status line - either a refusal before launch or a git failure after the run,
  which the dispatching skill tells the controller apart and recovers from
  differently. The status line also carries Codex's own `exit=` code and a
  `note=timed-out` marker, and the report lifts Codex's error text out of the
  `--json` stream into a `## Codex error` section. All three exist because
  `status` is forced to `BLOCKED` on any non-zero exit, so on its own it cannot
  separate a parse failure, a timeout, and a model that gave up - and the error
  text is on stdout, where a controller reading `<report>.stderr` never finds it.
- `codex-report-schema.json` is the `--output-schema` the wrapper passes, and
  the shape of the verdict it parses back.
- `codex-task-contract.md` is appended to every prompt the wrapper sends,
  resume rounds included.
