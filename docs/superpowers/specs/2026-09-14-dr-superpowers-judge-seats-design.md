# dr-superpowers 1.8.0 — Codex judge seats (sub-project 7 design)

Date: 2026-09-14. Program design:
`docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` (§6 listed five sub-projects; a
sixth was added by dated amendment; this is a seventh, recorded the same way — see §10).

Designed against two independent review rounds, each by two seats — `dr-superpowers:judge-fable`
and Codex `gpt-6-astra / high`. Round one rejected the design's central premise and its fallback,
resolved and marked **[R<n>]**. Round two rejected the substrate proposal outright and caught a
regression introduced while fixing round one, resolved and marked **[S<n>]**.

Goal: put the Claude-hosted Codex review seats on `gpt-6-astra`, the model this plugin's own native
policy already floors judges at, and make every seat verify model availability before spending a
round on it — without the fiction that a configured preference is evidence of access.

## 1. Decisions fixed here

- **Astra in both Claude-hosted judge seats** (owner answer). The risk-3 seat in
  `reference/external-executor.md` §Risk-3 Codex seat, and the final-review round in §Final-review
  Codex round that `reference/final-review.md` step 2 invokes. Execution rungs stay on `gpt-5.5`
  and `gpt-5.6-sol`.
- **Unverifiable availability fails closed** (owner answer) to the last known-good rung, announced
  aloud and written to the ledger.
- **One substrate: the `codex` CLI, for all three call sites** **[S1]**. The official OpenAI
  `codex` plugin is not adopted — see §3.
- **No new dependency.** `jq` is already required by `scripts/detect-executors.sh`; nothing else is
  added.

## 2. What the two review rounds overturned

Both rounds are recorded because the rejected positions are the ones a later session would
re-propose. §9 of this document is where they live permanently.

**Round one killed the evidence rule.** The design read `~/.codex/config.toml` and treated
`model = "gpt-6-astra"` as proof the account could call Astra. Both seats rejected it: that proves
someone typed a string, and a user who tried Astra and was refused still has that string. The CLI
validates neither model nor effort locally — `scripts/run-codex-task.sh:4-6` already records that
it "accepts any string, prints it in its banner, and fails at the API". **[R1]**

**Round one killed the premise under it.** The design asserted no free enumeration exists. Two
exist. `codex app-server generate-json-schema` emits a `ClientRequest.json` carrying `model/list`
and `modelProvider/capabilities/read` (verified, CLI 0.153.4), and
`${CODEX_HOME:-$HOME/.codex}/models_cache.json` is a local catalog carrying `slug`, `visibility`
and `supported_reasoning_levels[].effort` per model (verified: 244,853 bytes, `fetched_at`
2026-09-14, `client_version` 0.153.4). **[R2]**

**Round one killed the fallback.** The design consulted the fallback only in a pre-check, while
both seats' text handles exactly one failure — `timeout` exit 124. A rejected model name exits
non-zero in seconds with no output, so the single failure the design existed to absorb would have
produced no Codex seat at all and the fallback row would never once have been read. **[R3]**

**Round two killed the substrate proposal** — see §3. **[S1]**

**Round two caught a regression.** While fixing **[R1]**, the revision replaced "fall back when
unverified" with "take the first row whose pair is advertised" and defined no outcome when nothing
matches. Both seats flagged it: an absent, malformed or Astra-less cache left the selector with no
output at all. The owner's fail-closed decision is restored in §6. **[S2]**

**Round two killed the fast-versus-slow asymmetry.** The revision fell back on any non-124 failure
on the reasoning that a rejection is fast. A non-124 failure need not be fast — a failure at 29
minutes would start another 30-minute run — and an explicit user cancellation must never trigger a
model swap. **[S3]**

## 3. Why the official OpenAI plugin is not adopted

The owner observed that OpenAI ships a Claude Code plugin and that this plugin shells out to
`codex` instead. That is accurate: marketplace `openai-codex`, plugin `codex` v1.0.3, runtime
`scripts/codex-companion.mjs` with `setup`, `review`, `adversarial-review`, `task`, `status`,
`result`, `cancel`. Its `review` accepts `--model` and `--cwd` (present in `valueOptions`, absent
from its usage line) and routes through the app-server rather than `codex exec`, returning a
structured payload with a thread id and reasoning summary.

It is nonetheless not adopted, for reasons specific to what these two seats must do. Every claim
below was verified in the installed source. **[S1]**

- **The risk-3 seat cannot be expressed through it.** That seat requires a caller-supplied prompt
  *and* `criteria/codex-review-schema.json` (four 1–20 scores, `spec_verdict`, `task_quality`,
  `cannot_verify`), which `skills/subagent-driven-development/SKILL.md:565-573` averages across
  three seats. `review` throws on any focus text (`codex-companion.mjs:268-273`);
  `adversarial-review` hardcodes a different schema shape — approve/needs-attention plus a severity
  scale (`schemas/review-output.schema.json`); `task` never forwards an output schema.
  `reference/external-executor.md:343` already forbids `codex exec review` for this seat on exactly
  this ground, and the companion's `review` is that same native reviewer.
- **The selected effort is silently dropped.** `buildThreadParams` (`lib/codex.mjs:55-66`) carries
  no effort field and `review/start` sends only `threadId`, `delivery`, `target`
  (`lib/codex.mjs:932-936`). Effort reaches the server only on `turn/start`, which review does not
  use. A `high` judge rung would be unenforceable: the run inherits the user's configured effort,
  or the model's own default, while the ledger records `high` and the timeout budget assumes it.
- **There is no run bound, and `--background` does not background.** `handleReviewCommand` parses
  `background`/`wait` and then calls `runForegroundCommand` unconditionally
  (`codex-companion.mjs:685,709`); only `task` enqueues. Nothing in the review path imposes a
  deadline. Wrapping the client in coreutils `timeout` kills the client, not the turn: the turn runs
  in a broker spawned `detached: true` and `unref()`ed (`lib/broker-lifecycle.mjs:59-70`).
- **A hung run cannot be cancelled.** `cancel` needs a job id, and `review --json`'s payload
  (`codex-companion.mjs:365-383`) carries `review`, `target`, `threadId`, `sourceThreadId` and a
  `codex` object — no job id. The companion also records `cancelled` when its turn interrupt
  failed, and the broker's socket-disconnect handler clears ownership without interrupting the
  active turn.
- **Review artifacts are not durable.** `session-lifecycle-hook.mjs` removes the session's jobs at
  `SessionEnd` and `lib/state.mjs` prunes old job files and logs, so a ledger line holding only a
  job id becomes unrecoverable across the handoff this plugin is built around.
- **Daemon ownership.** That broker is reaped by the plugin's own `SessionEnd` hook. Invoking the
  script directly from this plugin — which is what "use the official plugin" means here — leaks one
  node daemon per worktree when that plugin is absent or disabled, against the owner's
  process-hygiene rules.
- **The surface relied on is undocumented.** `--model` and `--cwd` on `review` are absent from
  `printUsage`. A marketplace plugin built on another vendor's undocumented flags breaks silently.

The companion is a slash-command product for a human at the keyboard: it drives `AskUserQuestion`,
renders markdown, and marks review threads `ephemeral: true`. What it offers these seats is a
thread id and a reasoning summary; what it costs is effort control, schema control, the run bound,
cancellation and daemon ownership. The trade is bad for this purpose and good for its own.

**This is not a permanent judgement.** If a later version accepts a caller schema, a caller prompt
and an effort on review, and returns a job id, §7's script is the one file that changes. Presence on
disk must never by itself select it: a present-but-incompatible companion would silently degrade a
working seat, so any future adoption is gated on capability, not on a path existing. **[S4]**

## 4. What does not change

- `reference/codex-routing.json` and `reference/native-codex.md`. Native hosts already floor judges
  at rank 8, `gpt-6-astra / high`. That policy is correct and is evidence about the native client,
  never about CLI access.
- `scripts/run-codex-task.sh` and the execution lane. Both seats confirmed the wrapper's
  guarantees — declared write set, clean-index precondition, fingerprint drift detection, scoped
  staging, verified commit — have no equivalent in `task --write`, which sets `workspace-write`,
  reports touched files, and neither commits nor scopes.
- `reference/ladder.md`'s `gate`, `codex-assignment` and `codex-successor` blocks. Execution
  admission is unchanged.

## 5. `reference/ladder.md` gains a `codex-judge` block

````markdown
```codex-judge
gpt-6-astra high 1800
gpt-5.6-sol high 1800
```
````

Three fields: model, effort, timeout in seconds. **First row preferred, last row the fallback.**

It is a separate block, not rows in the execution blocks, for two mechanical reasons both seats
found independently: `scripts/run-codex-task.sh:93-94` validates `--model` against
`codex-assignment`, so an Astra row there would widen execution admission against the owner's
decision; and `tests/lanes.test.sh:35` returns `-1` for any model outside the execution set, so an
Astra row in `codex-successor` would fail the termination proof. That `-1` also protects the
separation against a future edit. **[R4]**

1800 seconds is a provisional operational budget, not a derived figure. The only measurement is a
`gpt-5.6-sol / high` whole-branch round at roughly four minutes. The `codex-timeout` table's
900/1200/1800/2400 progression would suggest 2400 for a rank-8 rung; there is no evidence
justifying the increase, so the budget stays and is revised when real runs warrant it. **[S5]**

## 6. Selection: `advertised` is a negative filter

`scripts/detect-executors.sh` gains one field on the **codex row only** — the script emits every
executor through one `emit` function, so Cursor, OpenCode and Antigravity carry `null` **[S6]**:

- `advertised`: model/effort pairs from `${CODEX_HOME:-$HOME/.codex}/models_cache.json`, filtered
  to `visibility: "list"`, each pair carrying the cache's `fetched_at` and `client_version` so the
  ledger can say how old the evidence was. **[S7]**

The script does not currently read `CODEX_HOME` at all — `tests/detect.test.sh` sets it, but only
the stubbed `codex` ever sees it — so that seam is built here, not assumed. **[S8]**

**`advertised` is a negative filter and the spec says so in the prose and in the script's own
comment.** A pair absent from it is never attempted. A pair present in it is attempted, and §7's
runtime rule is what carries the guarantee. Catalog listing is not entitlement: `gpt-5.6-luna` and
`gpt-5.6-terra` are both `visibility: "list"` in today's cache yet returned HTTP 400 on this
account on 2026-08-31. Those are observations from different dates and this design does not claim
either is inaccessible today. **[R5]**

The three states are distinct, and `null` is not `[]`:

| `advertised` | Meaning | Selection |
|---|---|---|
| a list containing the preferred pair | the catalog knows it | preferred row |
| a list without it | the catalog does not know it | last row, said aloud |
| `[]` | catalog read, nothing listed | last row, said aloud |
| `null` | absent, malformed, or unreadable | last row, said aloud |

The last three rows are the owner's fail-closed decision, restored after round two. **[S2]**

`model/list` over the app-server is the better-supported interface and is not used: it needs a
process spawn and an `initialize` handshake inside a guard that runs at plan time and again at
every dispatch, to obtain what the CLI already wrote to the cache. If a seat is ever already
holding an app-server connection, its discovery interface is the right source there. **[R6]**

## 7. `scripts/run-codex-review.sh` — the seat runner

Both rounds converged on this: the rule must not live in prose. Round one's fallback was dead
precisely because the runtime never reached the paragraph describing it, and prose would fail the
same way again. **[S9]**

```
scripts/run-codex-review.sh --kind risk3|final --cwd <worktree> --out <path>
                            (--prompt <file> | --base <ref>) [--dry-run]
```

It reads `codex-judge`, applies the `advertised` filter, runs the selected row under coreutils
`timeout`, applies §8's outcome policy, captures stderr beside the output, and prints exactly one
status line:

```
codex-judge <model>/<effort> status=OK|FALLBACK|TIMEOUT|FAILED exit=<n> out=<path> evidence=<fetched_at>
```

`--dry-run` prints the argv it would run and exits 0, which is the seam the tests use. Both seat
sections in `reference/external-executor.md` and `reference/final-review.md` step 2 then reduce to
"run the script, read the status line", and a future substrate decision is a one-file change.

The two kinds differ in three ways, and the script owns the difference:

| | `risk3` | `final` |
|---|---|---|
| Input | `--prompt <file>`, the seat's own prompt | `--base <ref>` |
| Codex form | `codex exec -s read-only` with `--output-schema criteria/codex-review-schema.json` | `codex exec review --base <ref>` |
| Valid output | JSON parsing against that schema | a non-empty report file |

`risk3` keeps `codex exec`, never `codex exec review`: `reference/external-executor.md:343` rejects
the latter because it imposes its own report shape, and the three risk-3 judges must be scored
alike. The three judges must also receive the same task inputs, which a branch-scoped review is
not. **[S10]**

Whether `codex exec review --base` accepts a sha as well as a branch name is **unknown and stays
unknown**: `--help` only exercises the argument parser, which accepts any string, and the ref is
resolved inside a real review, so no cheap probe settles it. The round passes a **base branch
name**, which is what the command passes today and is therefore already known to work.
`reference/final-review.md:21` computes `MERGE_BASE` as a sha for the review package; the two are
not the same value, and the seat prose says which one it takes. The question is logged in §12
rather than answered. **[S11]**

## 8. The outcome policy

Round two's central finding: the revision mixed process exit, job state and output validity into
one rule, and over-corrected into treating nearly every failure as a reason to change models.
Three axes are tracked separately. **[S3]**

| Outcome | Condition | Response |
|---|---|---|
| `OK` | ran to completion **and** produced valid output for its kind | the seat's result |
| `FALLBACK` | the preferred row was refused for its model or effort | run the last row **once**, say it aloud, ledger the substitution with the first line of stderr |
| `TIMEOUT` | the deadline expired | today's behaviour: a third Claude judge for risk-3, a disclosed skip for the final round. Never a second long run behind a hang |
| `FAILED` | anything else, the fallback's own failure included | the same terminal outcome as `TIMEOUT`, disclosed |

Rules that fall out of it, each from a round-two finding:

- **Deadline expiry is tracked separately from exit codes**, because a client killed by `timeout`
  and a model refusal both surface as non-zero.
- **Only an explicit model or effort refusal selects the fallback.** Authentication failure, a bad
  working directory, an unsupported argument, quota exhaustion and user cancellation do not — a
  different model repairs none of them, and a second run would fail identically. **[S3]**
- **Exit 0 with absent or invalid output is `FAILED`, not `OK`.** Native success is derived from
  turn completion independently of whether report text was produced.
  `scripts/run-codex-task.sh:252-261` already records the exit-0-without-final-message case.
  **[S12]**
- **Absent output is never a clean review and never a third vote.** Unchanged from today, and
  restated because it is what the whole policy protects.
- **Stderr is captured to `<out>.stderr`** and its first line quoted in the ledger substitution, so
  a refusal, an expired auth and an exhausted quota are distinguishable afterwards rather than all
  reading as "non-zero, no output". **[S13]**
- **The fallback is attempted at most once** and never when it was already the selected row.

## 9. Rejected approaches, recorded

Kept because each is what a later session re-proposes.

- **Reading `config.toml` for a `default_model`.** A configured preference, not evidence of access,
  and wrong in both directions: a user defaulting to a cheaper model loses an available Astra seat,
  a user configuring an inaccessible Astra gets assigned one. **[R1]**
- **A pre-check as the only fallback.** Dead data: the runtime path never reached it. **[R3]**
- **Routing the judge seats through the official plugin.** §3. **[S1]**
- **Adding Astra to `codex-assignment`.** Widens execution admission through
  `run-codex-task.sh:93-94`. **[R4]**
- **Standing up an app-server for `model/list`.** A daemon for data already on disk. **[R6]**

## 10. Prose this falsifies

Each must change in the same sub-project, because each becomes false the moment the block lands:

- `reference/ladder.md:220` — "Only `gpt-5.5` and `gpt-5.6-sol` appear in this external CLI
  policy."
- `reference/external-executor.md:376-381` — 1800 described as borrowed "for a round that block has
  no row for" — and the hardcoded `-m gpt-5.6-sol` at `:334` and `:369`.
- `reference/external-executor.md:390-401` — the Failure rows table gains the refusal row.
- `reference/final-review.md:37-39` — enumerates only "not usable" and "times out".
- `skills/subagent-driven-development/SKILL.md:556-573` — handles only unusability and timeout, and
  its generic missing-verdict rule says to redispatch; it must defer to §8 so invalid output cannot
  reopen retries. Missed in round one's fix and restored here. **[S14]**
- `README.md:171-178`, the cross-family review paragraph. `README.md:136` gets a dated addendum
  rather than a deletion — it is the historical HTTP 400 evidence. **[S15]**

"The CLI path is unchanged" is the wrong wording for any of this: its transport is unchanged, but
its model selection and failure handling consume the new policy, or companion-absence would
preserve hardcoded Sol forever. **[S16]**

## 11. Verification

- `tests/lanes.test.sh`: a judge allowlist **separate** from the execution `VALID_MODELS`, so the
  assignment assertion keeps saying what it says today. Assert the exact preferred and fallback
  pairs — not merely "two distinct rows whose last model is historically verified", which admits
  `gpt-5.5` as fallback and does not pin either row to `high` **[S17]** — plus exact field counts,
  positive integer timeouts, and agreement with any duplicated `codex-timeout` row.
- `tests/detect.test.sh`: `advertised` against a cache containing Astra, a cache without it, `[]`,
  malformed JSON, an absent file, and `null` on every non-codex row. `jq` is the only parser, so
  the isolated `PATH` needs no new shim. **[S18]**
- **`tests/codex-review.test.sh`, new:** the runner's `--dry-run` argv under the stub pattern
  `tests/run-codex-task.test.sh:36-38` already uses — asserting the chosen `-m` and
  `-c model_reasoning_effort`, the per-kind Codex form, schema versus base wiring, and every branch
  of §8: no-match selection, refusal into fallback, fallback failure, exit-0-empty, timeout, and
  cancellation. No model call. **[S19]**
- The three existing suites, `scripts/validate-repository.mjs`, and `claude plugin validate` on the
  marketplace and the plugin.

One environment failure predates this work and is not caused by it: `tests/ui-discovery.test.mjs`
fails with `bash: rg: command not found` on this machine.

## 12. Logged, not fixed here

Pre-existing, surfaced by the review rounds, each its own change:

- `reference/final-review.md:21` requires the review package in every dispatch, but the Codex round
  passes only `--base` and an output path — no package, no spec, no ledger context.
- `reference/external-executor.md:288` says an exit-2 resume never launched and should be reissued,
  while `scripts/run-codex-task.sh:337,422` can exit 2 after execution during child-termination
  persistence or report writing; `:222` correctly demands durable-state inspection. The initial-run
  table at `:398` carries the same assumption.
- `reference/external-executor.md:169`'s missing-commit-subject advice recommends manual staging,
  which the current implementation refuses.
- Whether `codex --version` or `login status` refreshes `models_cache.json` is unknown; cache
  staleness is bounded by the last real `codex` run.
- Whether `codex exec review --base` resolves a commit sha as well as a branch name is unknown, and
  no probe short of a real review settles it: the argument parser accepts any string. The
  final-review round therefore passes a base branch name, which it already passed before this
  sub-project, and `reference/final-review.md`'s `MERGE_BASE` sha is not handed to it. Settling this
  would let the round review exactly the range the review package shows.
- In the official plugin, not ours: unlocked read-modify-write with non-atomic JSON writes in
  `lib/state.mjs`, a startup race between a background task's worker spawn and its request being
  persisted, and a `terminateProcessTree` that on POSIX returns after a missing-process-group error
  without trying the individual pid.

## 13. Program design amendment

To be added under §6 of `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`:

> **Amendment 2026-09-14 (sub-project 7 spec).** The decomposition gains a seventh sub-project,
> "Codex judge seats", after project state. Both Claude-hosted Codex review seats — the risk-3 seat
> and the final-review round — move from `gpt-5.6-sol / high` to `gpt-6-astra / high`, the rung
> `codex-routing.json` already floors native judges at, with `gpt-5.6-sol / high` as a fallback
> declared in a new `codex-judge` block in `reference/ladder.md`. Execution admission is unchanged:
> the block is separate because `run-codex-task.sh` validates `--model` against `codex-assignment`.
> `scripts/detect-executors.sh` gains an `advertised` field of model/effort pairs read from the
> local Codex model cache, used strictly as a negative filter — catalog listing is not entitlement
> — and selection falls closed to the fallback row whenever the cache is absent, malformed or
> silent. A new `scripts/run-codex-review.sh` owns selection, the run bound and the outcome policy
> for both seats, so the rule is executable and testable rather than prose. The official OpenAI
> `codex` plugin is deliberately not adopted as the substrate: its review path accepts no caller
> schema and no caller prompt, drops the selected reasoning effort, imposes no deadline, does not
> background, returns no job id to cancel with, and leaves a detached broker daemon its own session
> hook owns. Details:
> `docs/superpowers/specs/2026-09-14-dr-superpowers-judge-seats-design.md`.
