# dcc-superpower-companions: external executors

Let a plan's cheap-to-middling tasks run on an external agent CLI instead of a
Claude implementer, without loosening Rule S, changing the rubric, or altering
superpowers' brief, report, ledger, or fix-loop contracts.

## Problem

Two things the current fleet cannot do.

1. **Every task spends Claude quota.** A user with a separate ChatGPT
   subscription has a second budget the plan cannot reach. The rubric already
   identifies which tasks are cheap; nothing acts on that beyond picking a
   smaller Claude model.
2. **Every seat is one model family.** Implementer, judge, and scout all run
   Claude. A failure mode Claude systematically misses is missed by every seat in
   the loop, including the review seats meant to catch it.

## Non-goals

- **The rubric does not change.** Four axes, 0-3 each, scored exactly as today.
- **Rule S does not change.** `reducible >= 4` or `spec = 3` still sends a task
  back to be split or re-designed. The external lane sits *downstream* of Rule S
  and never runs on a task that failed it.
- **The Claude assignment and escalation tables do not change.** The Claude
  ladder remains the sole backstop and the only path that terminates.
- **The reserve is untouched.**
- **No new agent definitions.** The fleet stays at nineteen and
  `tests/fleet.test.sh` stays as written.

## Verified environment

Every fact below was probed on the target machine (win32, Codex 0.151.0, npm
install, ChatGPT-subscription auth) on 2026-08-31. The design depends on all of
them; a port to another machine must re-probe.

| Probe | Result |
|-------|--------|
| `codex exec -m luna` / `-m terra` | **Rejected.** HTTP 400, "not supported when using Codex with a ChatGPT account". Codex has no model metadata for either name |
| `codex exec -m gpt-5.5` / `-m gpt-5.6-sol` | Work |
| `model_reasoning_effort` | `low`, `medium`, `high`, `xhigh`, `ultra` valid. `minimal` rejected |
| Effort validation | **Client-side validation does not exist.** The CLI echoes any string into its banner and fails at the API. The wrapper must validate locally |
| `-s workspace-write`, file writes | Work |
| `-s workspace-write`, `git commit` | **Blocked.** `.git/index.lock: Permission denied` |
| Sandbox enforcement on Windows | Real, via a Windows restricted-token sandbox. Confirmed independently of any model call with `codex sandbox -- git add -A`, which fails identically |
| Default approval policy for `codex exec` | `on-request`, with no approver present in a non-interactive run |
| `codex exec review` | Has `-m`, `--base <branch>`, `--commit <sha>`, `--json`, `-o`, `--output-schema`. Has no sandbox flag; review is read-only by nature |
| `antigravity` | Installed, but its only agent-shaped subcommand is `antigravity chat -m agent`, which opens a GUI chat session with no output file, no completion signal, and no exit code tied to the work. Not batch-capable |
| `cursor-agent`, `opencode` | Not installed |

Two of these overturned earlier assumptions and are called out because the design
would have been wrong without them: the sandbox is enforced on Windows rather
than advisory, and Codex **cannot commit its own work**.

## Design

### Two lanes, one rubric

Scoring is unchanged. A **lane gate** sits between the score and the assignment
table:

```gate
eligible = external_enabled AND cleared_rule_s_without_override AND score >= 2 AND risk <= 1
```

An eligible task goes to the external lane; everything else goes to the Claude
assignment table exactly as today.

External executors are **not rungs on the Claude escalation ladder.** Offload
selects *downward* at the cheap end while the ladder only moves upward; one total
order cannot express both. Keeping them off the ladder is what preserves the
existing acyclicity and termination proofs unchanged.

**Why the floor is 2, not 0.** Rule S caps `reducible` at 3, so under `risk <= 1`
the eligible totals are exactly 2, 3, and 4 - totals 5 and 6 require `risk >= 2`
and are excluded by the risk clause alone. Without the floor the gate would
reduce to `risk <= 1`, capturing nearly every task by count and turning the
seven-agent execution fleet into a handback-only bench. It would also offload
where offload is worthless: a score-0 task displaces `impl-haiku`, so the run
costs more to orchestrate than it saves.

**Why the Rule S clause names an override.** The legacy floor permits a human to
keep a `spec = 3` task as written. Such a task can score
`files 0 + spec 3 + coupling 0 + risk 0 = 3` and would otherwise pass the gate,
sending a task whose approach nobody decided to a one-shot external agent. The
gate applies only to tasks that cleared Rule S on their own.

### The codex tables

New fenced blocks in `reference/ladder.md`, parsed by the test suite the way the
existing blocks are.

```codex-assignment
2 gpt-5.5 medium
3 gpt-5.5 high
4 gpt-5.6-sol high
```

```codex-successor
gpt-5.5/medium gpt-5.5/high
gpt-5.5/high gpt-5.6-sol/high
gpt-5.6-sol/high gpt-5.6-sol/xhigh
gpt-5.6-sol/xhigh HANDBACK
```

`codex-successor` is a single-successor column used at most once per task, not a
walkable chain. Naming it `successor` rather than `escalation` is deliberate: an
earlier draft called it an escalation chain and asserted a multi-step walk in its
tests, but nothing walks it - the fix loop resumes on rounds 1-3 and hands back
on round 4, so only a failed *run* consults it, and a run may consult it once. A
table whose tests validate a traversal the code never performs is dead weight
that reads as load-bearing.

`HANDBACK` is an action, not an executor - the same shape as `SPLIT` at the top
of the Claude ladder. It resolves to the Claude assignment-table row for the
task's score, after which the existing ladder governs.

**Rung liveness is verified, not assumed.** `detect-executors.sh` validates each
model named in `codex-assignment` and marks dead rungs. The original draft of
this design bound scores 0 and 1 to `luna` and `terra`; the probe showed both are
rejected on this account, which would have failed every task at those scores on
every run. Two models times five efforts is ten rungs of headroom, all of it from
the effort axis.

### Plan format

A task block gains one line:

```markdown
**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Executor:** codex gpt-5.5 / medium
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
```

`**Implementer:**` continues to name the **Claude agent for the score**, and
`**Executor:**` is an override the dispatching skill checks first. This ordering
matters: a machine without Codex, a cold session, an `executing-plans` run, and a
revoked executor all degrade to correct behaviour with no new logic and no
re-derivation. Putting the executor in the `**Implementer:**` line instead would
force the fallback path to recompute the assignment at dispatch time - precisely
the failure this plugin was built to eliminate - and would break two written
checks requiring every `**Implementer:**` value to appear in the assignment or
reserve table.

The plan header gains one blockquote line, appended alongside the existing ones:

```markdown
> **External executors:** codex
```

### Dispatch

**No driver subagent.** `run-codex-task.sh` is invoked by the controller as a
background Bash call, the same way the controller already invokes superpowers'
`sdd-workspace` and `task-brief`. An earlier draft placed a Sonnet driver agent
between the two; it was removed because a driver doing bookkeeping costs roughly
what the implementer it displaces would have cost, netting the offload to zero,
and because it added a third verification seat with no authority next to
superpowers' reviewer, which already treats implementer test claims as unverified.

**No dedicated worktree.** Codex runs in the SDD worktree, on the task branch,
exactly where a Claude implementer runs. An earlier draft gave it its own
worktree on an `sdd-ext/task-N` branch merged back with `--ff-only`; that was
removed because superpowers' `subagent-driven-development` already creates a
worktree at setup (`SKILL.md:127`), making the extra one a worktree nested inside
a worktree, and because superpowers' finish step is `rm -rf <workspace>`
(`SKILL.md:483`), which would delete a registered worktree's directory out from
under git. The isolation it was buying already exists; the merge choreography,
the handback ambiguity, and a crash window between accepting a task and merging
it did not.

```
controller
  1. read **Executor:**; absent -> Claude lane, unchanged
  2. detect-executors.sh -> fresh roster (never the plan's copy)
     codex unusable -> dispatch **Implementer:** on the Claude lane,
                       say it aloud, record it in the ledger
  3. sdd-workspace / task-brief          (superpowers' scripts, unchanged)
  4. bash run-codex-task.sh --brief B --report R --model M --effort E
          --cwd <worktree> --timeout T        (background; prints one line)
  5. ledger: Task N: implementer impl-sonnet-medium
             (assigned; executor codex gpt-5.5/medium, thread <id>)
  6. judge-fable reviews, unchanged and blind to the lane
```

### run-codex-task.sh

Owns the command line, the timeout, the commit, and the process tree.

1. **Validate locally** - model against the `codex-assignment` allowlist, effort
   against `{low, medium, high, xhigh, ultra}`. The CLI does neither, so an
   unvalidated typo becomes a paid API failure.
2. `BASE=$(git rev-parse HEAD)`.
3. Compose the prompt: the task brief, superpowers' report contract, the RED and
   GREEN evidence format, the repo conventions block described below, the
   ask-don't-guess rule, and the explicit statement that the agent cannot write
   to `.git` and must not attempt git commands.
4. Invoke:

   ```
   codex exec -C <worktree> -s workspace-write -m <model> \
     -c model_reasoning_effort=<effort> \
     --json --output-schema <schema> -o <last.json> < <prompt>
   ```

   JSONL is tee'd to `<sdd>/task-N-codex.jsonl`; the thread id is read from the
   `thread.started` event.
5. **Commit on `DONE` only.** `git add -A && git commit -m "<subject>"` using the
   schema's `commit_subject`, conformed to `type(scope): subject`. On any other
   status the tree is left dirty and the report says so, which is how a Claude
   implementer behaves when it reports BLOCKED mid-task.
6. `HEAD=$(git rev-parse HEAD)`; write the report file including the commit
   range, the thread id, the model and effort, and the status.
7. Print one status line. Trap on every exit path: `taskkill /F /T /PID` on the
   tree, since GNU `timeout` signals only the direct child and Codex runs under a
   node wrapper.

**The commit boundary is a feature.** Codex physically cannot write to `.git`, so
it cannot rewrite history, and the script's `BASE..HEAD` range is measured rather
than reported. It also puts the repo's commit convention in a script instead of
hoping a model that has never read `CLAUDE.md` infers it.

**Output schema** (`--output-schema`), which makes the status mapping
deterministic instead of parsed prose:

```json
{"type":"object",
 "required":["status","summary","commit_subject"],
 "properties":{
   "status":{"enum":["DONE","BLOCKED","NEEDS_CONTEXT"]},
   "summary":{"type":"string"},
   "commit_subject":{"type":"string"},
   "questions":{"type":"array","items":{"type":"string"}}}}
```

**Repo conventions.** Codex does not read `CLAUDE.md`; it reads `AGENTS.md`, and
the host repo may have neither. The wrapper therefore inlines whichever of
`CLAUDE.md` and `AGENTS.md` exist at the repo root into the prompt under a
"Repository conventions" heading, rather than assuming Codex picked them up. The
plugin does not create an `AGENTS.md`: it ships to arbitrary repos, and writing
one would silently change how the user's own Codex sessions behave outside this
loop.

**Ask-don't-guess.** `codex exec` is one-shot and cannot ask questions the way
superpowers' implementer flow allows. The prompt therefore instructs: if the
brief is ambiguous, implement nothing, set `status: NEEDS_CONTEXT`, and put the
questions in `questions`. The controller answers them and continues with
`codex exec resume`. Without this the agent guesses and superpowers loses one of
its quality mechanisms silently.

**TDD evidence.** superpowers' report contract requires RED and GREEN evidence
where TDD was required, and its reviewer template is told the implementer already
produced it. RED evidence can only be generated before implementation, so the
prompt must demand test-first and require the failing and passing output be
logged in the report's exact format. Without this a faithful judge reports a spec
gap on nearly every external task and the offload converts into fix rounds.

### Per-tier timeouts

One constant cannot serve a `medium` and an `xhigh` run.

```codex-timeout
gpt-5.5/medium 900
gpt-5.5/high 1200
gpt-5.6-sol/high 1800
gpt-5.6-sol/xhigh 2400
```

### Run failure

A failed *run* is distinct from a failed *review*.

| Failure | Response |
|---------|----------|
| Transient - network, 429, 5xx | Retry once at the same tier |
| Capability - empty diff, `status: BLOCKED` | Escalate one rung via `codex-successor`, run once |
| Either, twice | `HANDBACK` |

At most two Codex runs per task before Claude takes over.

### Fix loop

Rounds 1-3 resume the same Codex session, mirroring superpowers' rule that rounds
1-3 resume the same implementer to preserve its model, effort, and context:

```
codex exec resume <thread-id> -C <worktree> -s workspace-write \
  -m <model> -c model_reasoning_effort=<effort> ...
```

**Every flag must be re-sent on resume.** `-m` and `-c model_reasoning_effort`
are per-invocation; a bare `codex exec resume <id>` silently falls back to the
user's config defaults, so round 2 would run at a tier the ledger does not
record. A stub test asserts this.

**The thread id persists in the report file and in the ledger's `(assigned)`
clause**, never only in a controller's context. If it lived in context alone, a
compaction would turn round 2 into a fresh dispatch dressed as a resume.

Round 4 is `HANDBACK`. The Claude implementer inherits the working tree, the
commits, and the report, which is exactly superpowers' "supply the context and
re-dispatch" case.

**Batching is forbidden in the external lane.** superpowers' rule to batch small
same-shape work fires on low-scoring tasks, and one batch is several tasks in one
dispatch, which the per-task `**Executor:**` line, thread id, and ledger clause
cannot represent. Batched tasks stay on the Claude lane.

### Detection

`scripts/detect-executors.sh` emits a JSON roster: id, present, path, version,
authed, `batch_capable`, and a reason when false. It runs at plan time to
populate the checkbox and again at dispatch as a guard, because a roster can go
stale between the two.

At plan time `assigning-implementers` renders the roster as a multi-select: one
tickable option per executor where `present && authed && batch_capable`, and a
prose line naming the rest with the reason each is unusable. If no executor
qualifies, no question is asked and the plan is written Claude-only - an empty
checkbox is a worse answer than no checkbox. The tick becomes the plan header's
`> **External executors:**` line, which is the only place the selection is
stored.

Antigravity is listed as detected with `batch_capable: false` and a reason. It is
not dead weight: the user asked which CLIs are usable, and answering "present but
its agent mode only opens a GUI window" is the answer.

A selected-but-now-unusable executor **never falls back silently**, matching the
plugin's existing rule.

### Cross-family review

Two additions, both on seats where the plugin already pays for extra review.
Neither interacts with the executor lane: risk-3 tasks are excluded from it by
the gate, so a Codex judge never reviews Codex's own work.

**The K=3 seat.** On a risk-3 task the plugin already dispatches three judges and
averages. One seat becomes Codex, using `codex exec -s read-only` with the same
criteria file and an `--output-schema` holding it to the criteria format. Not
`codex exec review`, which imposes its own report shape.

**The final whole-branch review.** superpowers' own review runs unchanged, plus
one Codex round:

```
codex exec review --base <base-branch> -m gpt-5.6-sol \
  -c model_reasoning_effort=high --json -o <file>
```

The two finding sets are deduped into one list tagged by source, then
`judge-fable` verifies each surviving finding against the diff and returns
CONFIRMED or REJECTED with evidence. The verifier is a third seat, so neither
reviewer grades its own work. Confirmed findings are reported ranked; rejected
ones are listed with the reason.

### The judge stays blind

`judge-fable` is not told which lane produced a diff, and nothing in its inputs
needs to change to achieve that. This is a property, not an enforced mechanism -
a report's voice and a diff's fingerprints leak the lane, and laundering them
would be pure ceremony. The controller retains lane knowledge, which is where
escalation and adjudication need it.

## What this supersedes

The plugin currently states in writing that the final whole-branch review and its
model selection are untouched. That is no longer true: a Codex round and a
verification pass are added. Recorded here explicitly because the plugin's own
discipline is to name supersessions and argue them rather than let them accrete.

Round-4 `HANDBACK` also lands a task on the Claude assignment-table row for its
score, whereas superpowers specifies a *more capable* model at rounds 4-5. The
argument for parity is that a family switch plus a fresh context satisfies the
rule's intent, and that the recorded score is the only evidence-free anchor
available. If it proves too weak in practice, entering at the row's escalation
successor is the one-line change.

## Error handling

| Situation | Response |
|-----------|----------|
| `**Executor:**` present, codex absent or unauthenticated at dispatch | Dispatch the `**Implementer:**` line's Claude agent, say it aloud, record in the ledger. Never silent |
| Model or effort fails local validation | Refuse to run; the plan or the table is wrong |
| A `codex-assignment` rung is dead on this account | Detection marks it; the gate skips to the first live rung and says so |
| Transient run failure | Retry once at the same tier |
| Capability run failure | One rung up via `codex-successor`, then `HANDBACK` |
| `status: NEEDS_CONTEXT` | Answer the questions, `codex exec resume` |
| Timeout | Kill the tree, leave the tree dirty for inspection, report, count as a run failure |
| Review failure, rounds 1-3 | `codex exec resume` with the full flag set |
| Review failure, round 4 | `HANDBACK` |

## Testing

Three new suites, all model-call-free, so the README's "no model calls" property
survives.

- `tests/lanes.test.sh` - `codex-assignment` covers exactly 2, 3, 4; every model
  it names is in the verified set; every effort is in the valid set;
  `codex-successor` strictly increases by rank and terminates at `HANDBACK`;
  every assignment rung has a `codex-timeout` entry; the gate expression matches
  `score >= 2 AND risk <= 1`.
- `tests/detect.test.sh` - synthetic PATH; asserts Antigravity is
  `batch_capable: false` with a reason, absent tools are `present: false`, and
  the JSON shape.
- `tests/run-codex-task.test.sh` - a stub `codex` on PATH asserting the full flag
  set, that resume re-sends `-m` and `-c model_reasoning_effort`, that local
  validation rejects a bad model or effort without invoking codex, that no commit
  happens on a non-`DONE` status, and that the trap runs on every exit path.

The four existing suites must pass unmodified. `tests/fleet.test.sh` in
particular asserts "exactly the 19 expected agents" and hard-fails an unknown
name prefix; since this design adds no agent file, it is untouched.

## Risks and open items

1. **Model availability is per-account and can change.** Detection validates the
   rungs, so a revoked model degrades to a marked-dead rung rather than a
   recurring paid failure.
2. **A systematically weak lane surfaces as review failures, not as a signal.**
   Mitigated by the ledger recording the executor per task, making the handback
   rate greppable.
3. **The `HANDBACK`-at-parity choice is unproven** - see supersessions.
4. **Every environment fact is machine-local.** A different machine, account, or
   Codex version must re-probe before trusting the tables.

## Files touched

| File | Change |
|------|--------|
| `reference/ladder.md` | Add the `gate`, `codex-assignment`, `codex-successor`, and `codex-timeout` blocks. Existing blocks unchanged |
| `scripts/detect-executors.sh` | New |
| `scripts/run-codex-task.sh` | New |
| `scripts/codex-report-schema.json` | New - the `--output-schema` file |
| `skills/assigning-implementers/SKILL.md` | Add detection, the checkbox, the gate, and the `**Executor:**` line. Existing scoring text unchanged |
| `skills/dispatching-tiered-implementers/SKILL.md` | Add executor dispatch, run-failure handling, resume, `HANDBACK`, the K=3 Codex seat, and the final-review round |
| `scripts/tier-nudge.sh` | One added clause in the `writing-plans` context string |
| `tests/lanes.test.sh`, `tests/detect.test.sh`, `tests/run-codex-task.test.sh` | New |
| `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | Version to 0.4.0; description mentions the external lane. Both must agree |
| `README.md` | Document the lane, the gate, the probed environment facts, and the two supersessions |

No file under `agents/` is added, changed, or removed.
