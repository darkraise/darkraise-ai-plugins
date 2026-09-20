# dr-opencode: a free-model OpenCode executor lane

**Status:** SUPERSEDED as a standalone design, 2026-09-20. Two review seats found
its founding premise unsound: dr-superpowers has no executor lane that happens
to run Codex, it has Codex, named in the scripts, the lint rules, the session
library, the ruling kinds and the skill prose. The work was decomposed into two
sub-projects. This file is retained as the source material for the second, and
must not be planned from as it stands.

- **Sub-project A** — extract a lane-agnostic executor interface, with Codex as
  its first instance and no change to Codex's behaviour. Spec pending.
- **Sub-project B** — `dr-opencode` as the second instance: this document,
  revised against the review findings, once A has landed.

**Review findings:** docs/superpowers/notes/2026-09-20-dr-opencode-spec-review.md
**Register:** docs/superpowers/registers/2026-09-20-opencode-executor.md
**Owner decisions:** 2026-09-20 brainstorming session

## 1. Purpose

dr-superpowers can offload plan tasks to one external CLI: Codex, through the
`codex@openai-codex` plugin. This spec adds a second lane driven by
[OpenCode](https://opencode.ai), restricted to models that cost nothing.

Two artifacts come out of it:

- **`plugins/dr-opencode`** - a new marketplace plugin that owns the OpenCode
  binary, its authentication, and its free-model roster, playing the role
  `codex@openai-codex` plays for the Codex lane.
- **an OpenCode lane inside `plugins/dr-superpowers`** - locator, session gate,
  task wrapper, routing table and lane reference, structurally a sibling of the
  Codex lane in `reference/external-executor.md`.

The lane exists to run the cheap end of a plan for free. It is not a capability
upgrade and never appears on the escalation ladder.

## 2. Verified facts

Everything in this section was established on 2026-09-20 and is the factual
basis of the design. Section 16 lists what could *not* be established, because
OpenCode is not installed on the development machine.

### 2.1 The free roster

OpenCode resolves models through the [models.dev](https://models.dev/api.json)
catalog. Its own gateway, OpenCode Zen, is the provider id `opencode`, API base
`https://opencode.ai/zen/v1`, credential `OPENCODE_API_KEY`.

The catalog carries `cost.input`, `cost.output`, `tool_call`, `status`,
`reasoning_options`, `structured_output` and `limit.context` per model, so
"free" is a computed property rather than a maintained list.

Thirty-one Zen models are cost-0 and tool-calling. Twenty-four of them carry
`status: "deprecated"`. The seven live ones are the whole ladder's raw material:

| Model | Context | Max output | `reasoning_options` | `structured_output` |
|---|---|---|---|---|
| `muse-spark-1.3-contributor-free` | 1,048,576 | 131,072 | effort: minimal/low/medium/high/xhigh | yes |
| `muse-spark-1.2-contributor-free` | 1,048,576 | 131,072 | effort: minimal/low/medium/high/xhigh | yes |
| `nemotron-3-ultra-free` | 1,000,000 | 128,000 | none | no |
| `nemotron-3.5-lightning-free` | 262,144 | 262,144 | none | yes |
| `ling-3.0-flash-fin-free` | 262,144 | 32,768 | toggle | no |
| `mimo-v2.5-free` | 200,000 | 32,000 | none | no |
| `big-pickle` | 200,000 | 32,000 | none | yes |

Two consequences run through the rest of this spec. **Effort is not a universal
axis**: only the two Muse Spark models take an effort value, one model takes a
reasoning on/off toggle, and four take neither. And **structured output is not
universal either**: three of the seven cannot be asked for a schema-conforming
final message.

Deprecated models are excluded. A deprecated model still answers, but the
catalog is announcing its removal, and a lane pinned to one would break without
warning on a date nobody chose.

### 2.2 The CLI surface

`opencode run <prompt>` is the headless entry point. The flags this lane uses:

| Flag | Use |
|---|---|
| `--model provider/model` | The rung's model, always `opencode/<id>` |
| `--format json` | Machine-readable event stream on stdout |
| `--session <id>` | Resume an existing session - the fix-round mechanism |
| `--continue` | Resume the last session; not used, `--session` is explicit |
| `--agent <name>` | Select an agent definition, and with it a tool allowlist |
| `--variant <v>` | Reasoning effort, where the model supports one |
| `--auto` | Auto-approve every permission that is not explicitly denied |
| `--dir <path>` | Working directory - the linked worktree root |
| `--fork` | Fork rather than extend a resumed session; not used |

Neighbouring subcommands: `opencode auth login` / `auth list`, `opencode models
[provider]` (`--refresh`, `--verbose` for cost metadata), `opencode serve`,
`opencode session list`, `opencode export <id>`.

Installation on Windows: `npm install -g opencode-ai`, `scoop install opencode`,
or `choco install opencode`.

## 3. Decisions taken

| # | Decision | Rationale |
|---|---|---|
| D1 | A full mirror plugin, `dr-opencode`, not a lane-only addition | The owner wants OpenCode usable on its own - setup and rescue - and the marketplace symmetric with the Codex lane |
| D2 | Pinned ladder plus a runtime cost assertion | The free roster rotates; a pinned ladder keeps routing reproducible, and the assertion makes a model that starts charging fail closed |
| D3 | Zen only | One credential, one rate-limit regime, thirty-one candidates. `providers` stays an array so a second provider is later a config change |
| D4 | Executor lane only, no review seats | Review is the check that makes cheap execution safe. A free model does not staff it |
| D5 | Score split, not failover | The two lanes coexist in one plan divided by score band, so the free lane has a permanent job and no precedence rule between equals is needed |
| D6 | One-shot subprocess transport | Each task is one bounded child process the wrapper can kill. A long-lived `opencode serve` broker is a daemon the session would have to own and reap |

## 4. Artifact A - `plugins/dr-opencode`

A marketplace plugin with both client manifests, mirroring the layout of
`codex@openai-codex` 1.0.3 (`commands/`, `agents/`, `skills/`, `scripts/`).

```
plugins/dr-opencode/
  .claude-plugin/plugin.json      name dr-opencode, version 0.1.0
  .codex-plugin/plugin.json       same version, skills "./skills/", hooks {}
  README.md
  commands/setup.md               /dr-opencode:setup
  commands/rescue.md              /dr-opencode:rescue
  agents/opencode-rescue.md       the delegation seat
  skills/opencode-cli-runtime/    internal contract for calling the companion
  skills/opencode-result-handling/  how to present companion output
  scripts/opencode-companion.mjs  the only transport
  scripts/lib/free-models.mjs     catalog resolution and the free filter
  scripts/lib/event-stream.mjs    --format json event parsing
```

### 4.1 `opencode-companion.mjs`

One executable with subcommands, each accepting `--json` and printing a single
JSON object on stdout. This is the only place in either plugin that spawns the
`opencode` binary.

| Subcommand | Answers |
|---|---|
| `setup` | Is the binary present, at what version, is Zen authenticated, how many live free models resolve, does the pinned ladder still match the catalog |
| `auth` | `{ authed, provider, reason }` - the probe `detect-executors.sh` reads |
| `models` | The live free roster as `{ id, context, effort, structured_output }` records |
| `run` | One task: spawn, stream, parse, return `status`, `summary`, `commit_subject`, `questions`, `discovered_issues`, `assumptions`, `session_id`, `exit`, `error` |
| `resume` | The same, with `--session <id>` |

`run` and `resume` never touch git, never stage, and never commit. They return a
parsed result; the dr-superpowers wrapper owns the repository.

### 4.2 `free-models.mjs`

Resolves the catalog, preferring OpenCode's own cached copy over the network so
a dispatch does not depend on models.dev being reachable, and applies the policy
filter: cost-0 on input and output, `tool_call` true, `status` not `deprecated`,
provider in `policy.providers`.

It exposes `isFree(modelId)` - the single predicate the wrapper's runtime
assertion calls - and `roster()`.

When no catalog can be resolved at all, `isFree` returns `false`. A lane that
cannot prove a model is free does not dispatch to it.

### 4.3 The rescue seat

`agents/opencode-rescue.md` and `/dr-opencode:rescue` mirror `codex:codex-rescue`:
delegate an investigation or a bounded fix to a free model and return its
findings. It is a standalone convenience and no part of the executor lane; the
lane never dispatches through it.

## 5. Artifact B - the dr-superpowers lane

```
plugins/dr-superpowers/
  scripts/opencode-plugin          locator + version allowlist
  scripts/opencode-gate            per-session on/off, cached by session id
  scripts/run-opencode-task.sh     the task wrapper
  scripts/detect-executors.sh      the opencode row becomes lane-implemented
  reference/opencode-plugin.json   allowlisted versions + trust record
  reference/opencode-routing.json  policy + catalog snapshot date
  reference/opencode-executor.md   the lane reference
  reference/ladder.md              four new fenced blocks
```

Two existing libraries are reused unchanged rather than duplicated:
`scripts/lib/task-state.sh` and `scripts/lib/task-execution.sh`, which own the
durable task record, snapshotting, scoped staging and commit recovery. Nothing
in them is Codex-specific.

### 5.1 `scripts/opencode-plugin`

A copy of `scripts/codex-plugin` reading `reference/opencode-plugin.json`:
resolve the plugin id from the policy file, confirm it is enabled in this
profile's settings, find its install path in `installed_plugins.json`, confirm
the install carries `scripts/opencode-companion.mjs`, confirm the installed
version is in the allowlist.

```
opencode-plugin ok version=<v> root=<path>
opencode-plugin off reason=<plugin-not-enabled|plugin-not-installed|plugin-missing|plugin-version:<v>>
```

Exit 0 ok, 1 off, 2 usage error or missing jq.

**Local-source caveat.** `dr-opencode` ships from this repository, so during
development it may be enabled from a local marketplace path rather than a cache
install. The locator therefore accepts an install entry whose `installPath`
resolves to `plugins/dr-opencode` in the current repository, and the allowlist
check is skipped for such an entry, with `version=local` in the ok line. This is
the one deliberate divergence from `codex-plugin`, and it exists because we ship
the plugin we are locating.

### 5.2 `scripts/opencode-gate`

A copy of `scripts/codex-gate`: same session-file mechanism, same `--refresh`
flag, same output grammar minus the review surface.

```
opencode-gate usable=<bool> reason=<r> lane=<bool> resets_at=<iso|-> source=<probe|cache>
```

`review=` is absent, because D4 gives this lane no review surface; a reader
looking for it has the wrong gate.

`usable=true` requires: the locator says ok, the companion's `auth` reports
authenticated, and its `models` returns at least one live free model. `lane=true`
additionally requires the trust record's `smoke` gate to read `pass`, exactly as
the Codex lane's does.

The answer is cached per `CLAUDE_CODE_SESSION_ID`. With no session id the gate
reports `usable=false reason=no-session-id`, as the Codex gate does. A
rate-limit answer caches with a reset time and is re-probed once it passes.

### 5.3 `scripts/detect-executors.sh`

The `opencode` row stops being a PATH probe and becomes a locator probe, the
branch the `codex` id already takes. Both ids now route through their plugin;
`cursor-agent` and `antigravity` keep the PATH branch. The dispatch call becomes
`emit opencode true true ""`.

The hardcoded reason string "no executor lane is implemented for $id in this
plugin; only codex has a wrapper" is rewritten to name the lane-bearing ids
generically, since two ids now have wrappers.

## 6. Free-model policy

`reference/opencode-routing.json`:

```json
{
  "version": "opencode-free-v1",
  "policy": {
    "providers": ["opencode"],
    "max_cost": 0,
    "require_tool_call": true,
    "exclude_status": ["deprecated"]
  },
  "catalog_snapshot": "2026-09-20"
}
```

The ladder itself lives in `reference/ladder.md` with every other routing table;
this file holds the policy the wrapper enforces and the date the ladder was last
reconciled against the catalog.

**The runtime assertion.** Before spawning anything, `run-opencode-task.sh`
calls the companion's `models` subcommand and refuses unless the requested model
is in the returned roster. A model that has gone paid, gone deprecated, or lost
tool calling exits 2 with `not-free`, which section 11 routes straight to
`HANDBACK` with no retry. The check costs one local process and no model call.

**Drift reporting.** `/dr-opencode:setup --refresh` compares the live roster
against the pinned ladder and reports both directions: rungs whose model is no
longer free or no longer live, and live free models absent from the ladder. It
prints a suggested ladder; it does not rewrite `ladder.md`, because a routing
table is a reviewed artifact.

## 7. The ladder blocks

Four new fenced blocks in `reference/ladder.md`, parsed by `tests/ladder.test.sh`
alongside the Codex ones. Efforts are written `-` where the model takes none.

```opencode-gate
min_score 0
max_score 2
max_risk 0
require_rule_s_clean true
require_external_enabled true
```

```opencode-assignment
0 nemotron-3.5-lightning-free -
1 muse-spark-1.3-contributor-free low
2 muse-spark-1.3-contributor-free medium
```

```opencode-successor
nemotron-3.5-lightning-free/- muse-spark-1.3-contributor-free/low
muse-spark-1.3-contributor-free/low muse-spark-1.3-contributor-free/medium
muse-spark-1.3-contributor-free/medium muse-spark-1.3-contributor-free/high
muse-spark-1.3-contributor-free/high HANDBACK
```

```opencode-timeout
nemotron-3.5-lightning-free/- 900
muse-spark-1.3-contributor-free/low 900
muse-spark-1.3-contributor-free/medium 1200
muse-spark-1.3-contributor-free/high 1800
```

**Why these two models.** The rungs need structured output, since the report
contract is a JSON final message (section 9.2), and the top rungs need an effort
axis, since a capability failure must have somewhere to go. Muse Spark 1.3 is
the only live free model with both, plus the largest context. Nemotron 3.5
Lightning takes rank 0 because a score-0 task does not need a million-token
context and a lighter model returns sooner. The other five live models are the
reserve the drift report draws from when one of these two leaves the free tier.

**Termination.** Ranking a rung as `model_rank * 10 + effort_rank`, with
Nemotron 3.5 Lightning at 0 and Muse Spark 1.3 at 1, and effort ranked 0 to 4
from `-`/`minimal` upward, gives every successor a strictly higher rank than its
source, so the column is acyclic and every walk reaches `HANDBACK`. This is the
same proof shape `tests/lanes.test.sh` already asserts for the Codex column, and
it is extended to cover this one.

**Timeouts are provisional.** No free-model run has been measured. These four
figures are the Codex lane's operating budgets carried over, to be revised once
real runs exist.

## 8. Lane precedence and the gate

Two lanes now gate the same task, and their admissible sets overlap: the Codex
`gate` block is `min_score 2, max_risk 1`, and this lane's is 0 to 2 at risk 0.
A task scoring 2 at risk 0 is admissible to both.

**Lanes are evaluated cheapest-first, and the first lane that admits the task
takes it.** OpenCode is evaluated before Codex. The Codex `gate` block is not
modified; the overlap is resolved by order, not by narrowing an existing table.

This keeps two properties. A total-2 task at risk 1 still goes to Codex, because
OpenCode's `max_risk 0` rejects it, so no task loses its lane. And the Codex
lane's own justification for `min_score 2` is untouched: it still refuses to
orchestrate a wrapper around a task `impl-haiku` would finish first, and the
free lane's reason for accepting those tasks is a different one - the wrapper
costs controller time, and the alternative costs Claude tokens.

Rule S is checked exactly as the Codex gate checks it, for the same reason: a
`spec = 3` task kept by a human override can score 3 and must not reach a
one-shot external agent.

A task admitted to this lane keeps its `**Implementer:**` line and gains one
override line:

```markdown
**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** opencode muse-spark-1.3-contributor-free / low
**Evaluation:** files 0 - spec 1 - coupling 0 - risk 0 = 1
```

The effort slot is `-` on a model that takes none. Batched tasks never carry an
`**Executor:**` line, on this lane as on the Codex one.

The plan header records both lanes when both are ticked:

```markdown
> **External executors:** codex, opencode
```

## 9. Dispatch

### 9.1 The wrapper

```bash
bash "<plugin-root>/scripts/run-opencode-task.sh" \
  --brief <brief> --report <workspace>/task-<N>-report.md \
  --cwd <worktree-root> --task-id <stable-task-id> --write-set <approved-paths.json> \
  --model <model> --effort <effort|-> [--resume <session-id>] [--review-round <K>]
```

Flags, durable artifacts, worktree ownership, write-set validation, scoped
staging and commit recovery are `run-codex-task.sh`'s, unchanged - the wrapper
sources the same two libraries. What differs is the child process, the effort
validation, the free assertion, and the status line's first token.

Effort validation reads the catalog rather than a fixed list: a rung's effort
must be among that model's `reasoning_options` effort values, or be `-` when the
model has none. Passing an effort a model does not take is exit 2, not a paid
round trip.

The status line, printed exactly once, on every path:

```
opencode <model>/<effort> status=DONE|BLOCKED|NEEDS_CONTEXT exit=<n> commits=<a7>..<b7> session=<id> report=<path>[ note=...]
```

`session=` replaces the Codex line's `thread=`; it is the same field under the
name OpenCode uses, and it must reach the ledger, because a compaction that
loses it turns a fix round into a fresh dispatch wearing a resume's name.

Run it as a background Bash call. Every rung's timeout exceeds the Bash tool's
600,000 ms ceiling, exactly as on the Codex lane, so a foreground call is cut
mid-run and misread as a lane failure.

### 9.2 The report contract

`scripts/opencode-task-contract.md` is `codex-task-contract.md` with two
substantive changes.

**Git is refused by permission, not by sandbox.** The Codex contract tells the
model its sandbox denies `.git` writes. OpenCode has no such sandbox, so the
prohibition is enforced two ways: the dispatch passes an agent definition whose
permission block denies `git` bash invocations, and the contract states the
prohibition in prose. The wrapper's existing scope validation is the backstop -
a run that commits anyway fails write-set validation and is blocked.

**The final message is a fenced JSON block, not a schema-enforced object.**
OpenCode's `run` has no `--output-schema`. The contract therefore asks for the
same six fields - `status`, `summary`, `commit_subject`, `questions`,
`discovered_issues`, `assumptions` - inside a single fenced JSON block as the
final message, and the companion parses the last such fence in the event stream.

A run whose final message contains no parseable fence is `BLOCKED` with
`reason=unparseable-report`, which section 11 treats as a capability failure.
Every ladder rung has `structured_output: true`, so a missing fence means the
model did not follow the contract rather than that it could not.

The human-readable report keeps the Codex report's headings, including
`## Discovered issues (not fixed)` and `## Assumptions made`, so the task's
complete line takes its checkpoint fields the same way. `## Codex error` becomes
`## OpenCode error` and carries the companion's classified error plus the tail
of stderr.

### 9.3 Recording the assignment

```
Task <N>: implementer impl-sonnet-low (assigned; base <sha7>; executor opencode muse-spark-1.3-contributor-free/low, session ses_01a0...)
```

And when the gate is shut or the roster reports the executor unusable, the
substitution is said aloud and recorded, never silent:

```
Task <N>: implementer impl-sonnet-low (assigned; base <sha7>; executor opencode unavailable - <reason>)
```

## 10. Review

Unchanged by this spec. `scripts/review-route` already routes any task carrying
an `**Executor:**` line to a Claude judge, and that rule covers this lane
without modification: OpenCode never reviews, and never reviews its own work.
No `opencode:*` seat exists, `criteria/` gains nothing, and the final-review
round stays Claude plus Codex.

The one change is documentary: `review-route`'s comment and
`reference/final-review.md` say "a task carrying an `**Executor:**` line routes
to a Claude judge", which is already lane-agnostic and needs only its Codex-only
phrasing generalised.

## 11. Failure model

The Codex lane's taxonomy applies with one addition and one substitution.

| Failure | Response |
|---|---|
| Transient - network, rate limit, quota, 5xx, in `## OpenCode error` | Retry once at the same rung |
| Timeout - `note=timed-out`, `exit=124` | Retry once at the same rung with `--timeout` raised; never take the successor |
| Capability - empty diff, `BLOCKED` with no transient cause, or `unparseable-report` | Move one rung via `opencode-successor` and run once |
| `NEEDS_CONTEXT` | Answer the questions, resume. Not a failure |
| **`not-free` - the model left the free tier between planning and dispatch** | **`HANDBACK` immediately. Never retried, never escalated: every other rung may have gone paid too, and this lane exists to cost nothing** |
| Any failure a second time | `HANDBACK` |

At most two runs may fail per task before the Claude implementer takes over.
Fix-round resumes do not count against that budget.

**The substitution is quota.** Zen publishes no rate limits for free models, so
a 429 cannot be distinguished from a daily cap by its text alone. A rate-limit
error is therefore treated as transient and retried once; a second one closes
the gate for the session with `reason=rate-limited`, and a reset time only if
the response carries one. This is deliberately more conservative than the Codex
lane, whose quota reset time is authoritative.

After any run whose status is not `DONE`, run `opencode-gate --refresh` before
the next use of the lane, exactly as the Codex lane does.

Exit codes are the Codex wrapper's: 0 DONE, 1 ran without reaching DONE, 2 no
status line - a validation or preflight failure that never launched the child,
and never retried unchanged.

## 12. Resume and fix rounds

Rounds 1 to 3 resume the same OpenCode session with `--session <id>`, preserving
its model, effort and context. Round 4 is `HANDBACK` to the `**Implementer:**`
agent, pulled earlier to round 3 when the progress reading says the loop has
stalled.

Each round writes its own report path. `opencode-successor` is never consulted
by a fix round, for the same reason it is never consulted on the Codex lane:
changing rung mid-loop discards the session context the rounds exist to
preserve.

A fix round returning `DONE` with an empty diff is a position, not a failure -
the model read the findings and elected to change nothing. Send its argument to
the ruling seat as an `opencode-empty-diff` item. Two in a row is a stalled loop
and a `HANDBACK`.

## 13. Repository integration

| File | Change |
|---|---|
| `.claude-plugin/marketplace.json` | Add `dr-opencode`; catalog version 0.4.0 to 0.5.0 |
| `.agents/plugins/marketplace.json` | Add `dr-opencode` with `installation: AVAILABLE` |
| `scripts/validate-repository.mjs` | Add `dr-opencode` to the `names` array |
| `README.md` | Document the plugin and the lane |
| `docs/superpowers/distilled/constraints.md` | Add the OpenCode lane constraint, sibling of the Codex one |
| `plugins/dr-superpowers/.claude-plugin/plugin.json` | 1.15.0 to 1.16.0, keyword `opencode` |
| `plugins/dr-superpowers/.codex-plugin/plugin.json` | Same version |
| `plugins/dr-superpowers/README.md` | Document the lane |

`dr-opencode` ships at 0.1.0 in both manifests. `validate-repository.mjs`
enforces equal versions across clients, the `./plugins/<name>` source form, the
`./skills/` skills path and empty Codex hooks; the new plugin satisfies all four
by construction.

The constraint added to `constraints.md`:

> ### The OpenCode executor lane is on
> When `scripts/opencode-gate` reports `lane=true`, the planner ticks `opencode`
> without asking and gives every task the OpenCode lane gate admits an
> `**Executor:**` line.

## 14. Testing

New suites, each mirroring its Codex counterpart:

| Suite | Covers |
|---|---|
| `tests/opencode-plugin.test.sh` | Locator: enabled, installed, version allowlist, local-source acceptance |
| `tests/opencode-gate.test.sh` | Probe, cache, `--refresh`, rate-limit reset, no-session-id |
| `tests/opencode-client.test.sh` | Companion result parsing: DONE, BLOCKED, NEEDS_CONTEXT, unparseable fence, classified errors |
| `tests/free-models.test.sh` | The policy filter, including deprecated exclusion and the empty-catalog false |
| `tests/opencode-task.test.sh` | Wrapper: effort validation, free assertion, write-set scope, status line, exit codes |
| `tests/fixtures/stub-opencode-plugin/` | A stub companion the suites drive without the real binary |

Amended suites: `tests/detect.test.sh` (the `opencode` row is now
lane-implemented and locator-probed), `tests/ladder.test.sh` (the four new
blocks parse), `tests/lanes.test.sh` (the successor column's termination proof),
`tests/native-routing.test.sh` (a task with an OpenCode `**Executor:**` line
routes to a Claude judge).

Repository validation per CLAUDE.md: `node scripts/validate-repository.mjs`,
both test runners, and `claude plugin validate` on the marketplace and every
Claude plugin including the new one. Every test and CLI call takes an explicit
timeout, and every process the validation run starts is terminated.

## 15. Out of scope

- **Review seats.** D4. Revisit only with evidence that a free model's review
  verdicts agree with a Claude judge's.
- **Providers other than Zen.** D3. `policy.providers` is the extension point.
- **A server transport.** D6. The companion's surface would satisfy one.
- **Failover from Codex to OpenCode.** D5 chose the score split; a Codex gate
  that closes still falls back to the Claude implementer.
- **Native OpenCode hosting.** This plugin is not designed to run *inside*
  OpenCode as dr-superpowers runs inside Codex. `reference/native-codex.md` has
  no OpenCode sibling.

## 16. Must verify before coding

OpenCode is not installed on the development machine: `~/.config/opencode` and
`~/.local/share/opencode` exist from 2026-08-22, but no binary is on PATH in
either Git Bash or `cmd`. The first plan task is installation and Zen login,
which the owner runs, because `opencode auth login` is interactive.

These five assumptions are load-bearing and unverified. Each must be confirmed
against the installed CLI before the code that depends on it is written; a plan
task that depends on a falsified one is re-designed, not worked around.

| # | Assumption | How to check |
|---|---|---|
| V1 | `opencode run` exits non-zero on failure, and distinguishably | Run against a bad model id, a denied permission, and a killed child; record each exit code |
| V2 | `--format json` emits a parseable event stream containing the assistant's final message and the session id | Capture one run's stdout and inspect the event shapes |
| V3 | `--auto` is sufficient for file writes inside a linked worktree with no prompt | One run that creates a file under `--dir <worktree>` |
| V4 | `--session <id>` resumes across separate processes, preserving context | Two sequential runs; the second must reference the first's content |
| V5 | An agent definition can deny `git` bash invocations while allowing other commands | One run instructed to commit; it must fail on permission, not succeed |

V2 and V5 are the two that can force a redesign. If the event stream carries no
recoverable final message, the report contract needs a different carrier - most
likely `opencode export <session>` after the run. If permissions cannot deny
`git` selectively, the contract falls back to prose plus the write-set backstop,
and that weakening is recorded rather than hidden.
