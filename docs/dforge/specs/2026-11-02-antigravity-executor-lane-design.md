# Antigravity executor lane

**Execution strategy:** sequential — the registry entry, ladder blocks, gate,
wrapper and planner routing form one chain, and `reference/executor-lane.md`,
`reference/ladder.md` and `scripts/plan-lint` are touched by several parts.
**Depth:** standard — interface

## Goal

Let dforge hand plan tasks to the Antigravity CLI (`agy`) so that work which
today runs as a native Claude implementer subagent runs on the owner's
Antigravity quota instead. `agy` becomes the second registered executor beside
Codex, preferred over it, for implementation only.

## Decisions

- **Models.** Asked which models the lane runs; answer: "Both, by score" —
  Gemini for the easy band, Claude-via-agy for harder scores.
- **Score bands.** Answer: "Gemini 0-2, Claude 3-8, risk ≤2 (Recommended)" —
  Gemini 3.8 Flash on totals 0-2; Claude via `agy` mirrors the native ladder for
  3-8; risk-3 tasks stay native.
- **Routing between lanes.** Answer: "Agy first, then Codex (Recommended)" —
  every task `agy`'s gate admits goes to `agy`; Codex keeps only tasks `agy`
  refuses; native Claude takes the rest and every handback.
- **Surfaces.** Answer: "Implementation only (Recommended)" — no review seats;
  work `agy` produces is reviewed by native Claude judges.
- **Approach.** Answer: "Sibling agy scripts (Recommended)" — a registry entry
  with its own locator, auth probe, gate and wrapper on the shared task
  libraries; `scripts/run-codex-task.sh` is not touched. Rejected: extracting a
  lane-neutral wrapper (refactors the working Codex path in the same change) and
  the do-less option of widening Codex's band (uses no Antigravity quota).
- **Execution strategy.** Not asked (`autoRun=on`); sequential, for the reason
  on the line above.
- **Gemini rung.** Asked (spec review) whether `medium` is the Gemini effort
  for totals 0-2; answer: "Should we evaluate first then decide the model and
  effort?" — so a calibration task decides the 0-2 rung from replayed tasks.
- **Auto-tick here.** Answer: "Auto-tick (Recommended)".
- **Unsandboxed reach.** Answer: "Accept and document (Recommended)".
- **Per-plan breaker.** Answer: "Off after 2 handbacks (Recommended)".
- **Early CI.** Answer: "No early run (Recommended)".

Early CI: none

Finish: merge

## Measured behaviour of `agy` 1.4.12 (2026-11-02, this host)

- `agy -p "<prompt>" --output-format json` runs headless in its working
  directory, edits files, and prints one JSON object:
  `conversation_id`, `status` (`SUCCESS`/`ERROR`), `response`, `error`,
  `usage`, sometimes `finished_reason`. Exit 0 on success, 1 on error (an
  unknown `--model` gave exit 1, `status: ERROR`, `finished_reason: "error"`
  and the reason in `error`).
- `--json-schema <file>` adds `structured_output` holding the final message
  validated against the schema.
- `--conversation <id>` resumes a run with its context (the resumed turn
  recalled the earlier edit).
- `--model claude-sonnet-5-5 --effort low` and `--model gemini-3.8-flash
  --effort low` both work; `agy models` lists Gemini 4 Argon, Gemini 3.8 Flash,
  Claude Opus 5.5, Claude Sonnet 5.5 (each low, medium, high) and GPT-OSS 120B.
- `--dangerously-skip-permissions` is required for unattended edits.
- `--print-timeout 5s` on a turn running `sleep 60` returned after 9 s with
  **exit 0, `status: SUCCESS`, `finished_reason: "print_timeout"`** and an
  empty response, plus a stderr line `print timeout after 5s with turn in
  progress`. The `sleep` child did not survive. A print timeout therefore looks
  like success unless `finished_reason` is read.
- `--sandbox` is unusable: it made the working directory read-only and let a
  shell command write outside it.
- The prompt cannot come from stdin (`-p -` is taken literally), and a 189 KB
  `-p` argument fails with "Argument list too long". A short prompt pointing at
  a file, plus `--add-dir <that file's directory>`, works: `agy` read the file
  outside its working tree and followed it.
- No `agy` process outlived a finished run (`ps` after six runs).
- Login state lives in `~/.gemini/antigravity-cli/`. What `agy` prints when
  logged out or over quota was not observed, and `agy models` gives no quota
  information.

## Design

### Registry entry

`plugins/dforge/reference/executors/agy.json`:

| Field | Value |
|---|---|
| `id` | `agy` |
| `locator` | `scripts/agy-locate` |
| `probe` | `scripts/lib/agy-probe.mjs`, op `auth` |
| `gate` | `scripts/agy-gate` (the script; distinct from the ladder block below) |
| `wrapper` | `scripts/run-agy-task.sh` |
| `reference` | `reference/executor-lane.md` |
| `session_dir` / `session_dir_env` | `agy-sessions` / `DR_AGY_SESSION_DIR` |
| `surfaces` | `["lane"]` |
| `priority` | `10` (new optional field; Codex gets `20`) |
| `blocks` | `gate: agy-lane-gate`, `assignment: agy-assignment`, `successor: agy-successor`, `timeout: agy-timeout` |
| `reasons` | `not_installed` (agy not on PATH), `not_enabled`, `logged_out` ("run agy and sign in"), `probe_failed`; no `missing`, which `agy-locate` never reports |

`priority` is optional and must be a non-negative integer; any other value
counts as absent, with one stderr line, as invalid entries are reported today.
An entry without it ranks after every entry with one. `scripts/executors` gains
`executors ranked`, printing valid ids by ascending priority then id.
`executors list` keeps its current output.

### Locator, probe, policy

- `scripts/agy-locate` prints `agy-locate ok version=<v> root=<dir>` when `agy`
  is on PATH and `agy --version` (bounded at 20 s) lies inside the range in
  `reference/agy-policy.json`; otherwise it exits 1 with
  `agy-locate off reason=<plugin-not-installed|plugin-version:<v>>`, the reason
  names `detect-executors.sh` already maps.
- `reference/agy-policy.json`: `min_version 1.4.12`, `max_major 1`,
  `trust: { smoke: "fail" }` until the smoke task passes and flips it to
  `pass` in its own commit. `DR_AGY_POLICY` replaces the file's path, as
  `DR_CODEX_POLICY` does for Codex.
- `scripts/lib/agy-probe.mjs` answers `{op:"auth"}` by running `agy models`
  under a 30 s bound: `authed: true` when it exits 0 and lists at least one
  model id, `authed: false` when its output asks for a login, `null` otherwise.

### Gate

`scripts/agy-gate [--refresh]` follows `scripts/codex-gate`'s shape without the
review surface: setting `agyLane` (new, boolean, default `true`,
`enforcedBy: 'script'`, label `Agy tasks`, in `config/schema.mjs`), then
locator and probe, cached per session through
`scripts/lib/executor-session.sh`. `lane=true` needs usable, a session file,
`trust.smoke = pass` and `agyLane` on. Output:
`agy-gate usable=<b> reason=<r> review=false lane=<b> resets_at=- source=<probe|cache|setting>`.

**Quota is sticky for the session.** Antigravity publishes no reset time and
`agy models` cannot see quota, so a quota failure marks the lane off
(`executor_session_mark_off agy quota`) and **`--refresh` keeps a cached
`usable=false reason=quota`** instead of re-probing it away. Without that, the
`--refresh` that `executor-lane.md` orders after every non-DONE run would
reopen the lane after each quota failure. Every other cached answer is
re-probed on `--refresh` as Codex's is.

### Ladder blocks (`reference/ladder.md`)

```agy-lane-gate
min_score 0
max_score 8
max_risk 2
require_rule_s_clean true
require_external_enabled true
```

```agy-assignment
0 gemini-3.8-flash medium
1 gemini-3.8-flash medium
2 gemini-3.8-flash medium
3 claude-sonnet-5-5 medium
4 claude-sonnet-5-5 medium
5 claude-sonnet-5-5 high
6 claude-opus-5-5 high
7 claude-opus-5-5 high
8 claude-opus-5-5 high
```

Totals 3-8 mirror the native Claude table (Sonnet medium, Sonnet high, Opus
high). Rows 0-2 are provisional: the calibration task below replaces them, and
the `agy-successor` and `agy-timeout` rows for the Gemini rung follow its
result.

```agy-successor
gemini-3.8-flash/medium claude-sonnet-5-5/medium
claude-sonnet-5-5/medium claude-sonnet-5-5/high
claude-sonnet-5-5/high claude-opus-5-5/high
claude-opus-5-5/high HANDBACK
```

A failed Gemini run moves to Claude rather than to a higher Gemini effort: the
second attempt should differ in model family, not only in effort. The rank
`model_rank * 10 + effort_rank` (every Gemini model 0, claude-sonnet-5-5 1,
claude-opus-5-5 2; low 0, medium 1, high 2) is strictly higher for every
successor than its source, so the column is acyclic and every walk reaches
`HANDBACK`.

```agy-timeout
gemini-3.8-flash/medium 900
claude-sonnet-5-5/medium 1200
claude-sonnet-5-5/high 1800
claude-opus-5-5/high 2400
```

`ladder.md` §The external lane is rewritten per executor: "The lane gate"
becomes one subsection per executor's gate block, and `agy-lane-gate` states
why its floor is 0 where Codex's is 2. Codex's floor exists because a score-0
offload costs more to orchestrate than `impl-sonnet-low` costs to run; `agy`'s
purpose is to move work onto another quota, so even a score-0 task it takes is
Claude quota saved.

### Wrapper `scripts/run-agy-task.sh`

Same flags, durable task record, control operations, report format and status
line as `run-codex-task.sh`, built on the same `lib/task-state.sh`,
`lib/task-execution.sh` and `lib/executor-session.sh` calls. Status line:
`agy <model>/<effort> status=<s> exit=<0|1|124> commits=<a7>..<b7> thread=<conversation_id> report=<path>[ note=timed-out][ note=writer-unconfirmed]`.

Differences from the Codex wrapper:

1. **Validation.** `--model` must be a model in `agy-assignment`; `--effort`
   one of `low medium high`.
2. **Prompt.** The brief, the repository's `CLAUDE.md` and `AGENTS.md`, and
   `scripts/agy-task-contract.md` are written to a prompt-only subdirectory,
   `$DR_TASK_DIR/prompt/attempt-<n>.md` (the record's `artifacts.prompt`
   points there). `agy` receives only a pointer —
   `Your complete instructions are in <prompt file>. Read the whole file first and follow it.`
   — with `--add-dir` naming that subdirectory, never the task directory that
   holds `state.json` and the snapshots. Both paths go through
   `dr_native_path`, as `codex-gate` does for `cwd`, so the native `agy`
   binary resolves them on Windows.
3. **Invocation.** In `--cwd`:
   `agy --output-format json --json-schema scripts/agy-report-schema.json --model <m> --effort <e> --dangerously-skip-permissions --add-dir <prompt dir> --print-timeout <t>s [--conversation <id>] -p "<pointer>"`,
   started as a background job under `timeout -k 10 $((t + 60))`, its pid
   kept, then `wait`ed on. `agy-report-schema.json` holds the same six fields
   as `codex-report-schema.json`, and a test keeps the two byte-identical.
4. **Result and classification.** `.structured_output` becomes the verdict
   file; `.conversation_id` becomes the thread. `exit=` is normalised as the
   Codex wrapper does: 124 when `finished_reason` is `print_timeout` or the
   outer `timeout` fired, 1 when `agy` exited non-zero or `status` is `ERROR`,
   else 0; any non-zero forces `BLOCKED`, and 124 adds `note=timed-out`. A
   non-DONE report carries `## Agy error` with the keys the controller tables
   read — `reason=<quota|timeout|unknown-model|error>`, `timedOut=true` on
   either deadline — then the raw `.error`. `reason=quota` when `.error`
   matches `quota|rate.?limit|RESOURCE_EXHAUSTED|429` (case-insensitive), which
   also marks the lane off for the session. `reason=unknown-model` only when
   it matches `unknown model|model .* not (found|available|supported|recognized)`;
   the wrapper already validated `--model`, so this means a withdrawn model and
   goes straight to `HANDBACK`, as a Codex refusal does. Anything else is
   `reason=error`, the capability row.
5. **Git guard.** The contract forbids every git command that writes (add,
   commit, stash, reset, checkout, switch, rebase, branch, tag, update-ref,
   worktree). Before the run the wrapper records
   `git for-each-ref --format='%(refname) %(objectname)'` and
   `git symbolic-ref -q HEAD`; after it, any difference blocks the task with a
   reason naming the ref that moved (`refs/stash` included), before staging.
   HEAD and index changes are already caught by `dr_task_validate_scope`
   (`lib/task-state.sh:255`), which `dr_task_stage` runs, and in-tree writes
   outside the approved paths by the same write-set check.
6. **Writer stopped.** GNU `timeout` leads its own process group and signals
   the group on expiry. After `wait`, the wrapper scans `ps -eo pid=,pgid=`
   for that group: any survivor gives `writer_stopped=no`,
   `note=writer-unconfirmed` and a blocked task, as Codex's unconfirmed case
   does. On Windows, where `ps` does not list native processes, every outer
   `timeout` kill reports `writer-unconfirmed`; a run that ended by itself, or
   by `--print-timeout`, counts as stopped.
7. **Piped Node children are fine.** The Codex-only rule that keeps tasks
   spawning piped Node child processes off the lane does not apply to `agy`
   (no sandbox).

### Planning and routing

- `executor-lane.md` §Planning runs every registered executor's gate in
  `executors ranked` order. The roster and the timed question are skipped only
  when **no** gate prints `lane=true`; a closed gate drops only its own
  executor.
- The header line lists ticked ids in priority order:
  `> **External executors:** agy, codex`.
- Each task goes to the **first ticked executor, in priority order, whose gate
  block admits it**; its `**Executor:**` line names that executor's rung. With
  both ticked, totals 0-8 at risk ≤ 2 go to `agy` and Codex receives nothing;
  with `agy` unticked or off, today's Codex routing is unchanged.
- `scripts/plan-revise` lists each unit's rungs in priority order;
  `scripts/plan-lint` adds an ERROR when a task's `**Executor:**` names an
  executor while a higher-priority ticked executor's gate admits that task, and
  its "lane-eligible with no Executor line" warning names the first admitting
  executor.
- At dispatch, when the named executor's gate is closed, the task runs on its
  `**Implementer:**` agent as today (no hop to the next executor), with the
  substitution said aloud and recorded.
- Review routing needs no change: `scripts/review-route` already sends every
  task carrying an `**Executor:**` line to a Claude judge.

### Single-executor passages to rewrite in `executor-lane.md`

Each becomes executor-neutral or moves to its executor's own section:

- lines 16-19: the block names (`gate`, `codex-assignment`, …) become "the
  blocks the registry entry names";
- lines 30-33: "unless it prints `lane=true`, stop here … run no roster"
  becomes the any-gate rule above;
- lines 128-133: the background-call timeout formula reads the executor's own
  timeout block, not `codex-timeout`;
- lines 164-165: the exit-2 text is `<id> lane is off for this session`;
- lines 279-291 and 298-312: failure rows name `## <Id> error`, `reason=`,
  `timedOut=true`, `exit=124` and "a refusal marker" (`refusal=true` for
  Codex, `reason=unknown-model` for `agy`) instead of Codex's fields;
- line 572: the failure row names the executor's assignment and timeout
  blocks;
- lines 634-649 and the piped-Node rule (lines 102-110): move to
  `## Per-executor: codex` (`reaped` is Codex's alone);
- a new `## Per-executor: agy`: unsandboxed reach (below), pointer prompt,
  sticky quota, the git guard, efforts `low|medium|high`, `finished_reason`.
- The registry table gains `priority`.

### Smaller changes

- `scripts/detect-executors.sh`: drop the stale `antigravity` PATH row, whose
  "GUI only" reason the 2026-09-22 survey already found wrong; the registered
  `agy` row replaces it.
- `docs/superpowers/distilled/constraints.md` (this repository only, subject to
  A14): "The Antigravity executor lane is on", committed together with the
  `trust.smoke: pass` flip, never before it.
- README lane section; plugin version 4.10.0.

### Calibration and smoke task (decides the 0-2 rung, opens the lane)

A task of this spec's own plan, ordered after the wrapper and gate exist and
before every routing and documentation task. Every run goes through
`run-agy-task.sh` by hand, with `DR_AGY_POLICY` exported to a trusted policy
copy for all three gate reads (the planning gate, the controller's dispatch
gate and the wrapper's own), in a scratch worktree, and spends Antigravity
quota only.

1. **Replay set.** Three completed tasks from this repository's own plans,
   each scored 0-2, each with its own tests. Each is replayed from its parent
   commit with its plan brief and write set.
2. **Candidates for totals 0-2,** cheapest first: `gemini-3.8-flash/low`,
   `gemini-3.8-flash/medium`, `gemini-4-argon/low`.
3. **A run passes** when it reports DONE, the task's own tests pass on the
   result, nothing outside the write set or in git refs changed, and a Claude
   judge (`dforge:judge-sonnet-high`, not told the author) passes the diff.
   Wall time and `usage.total_tokens` are recorded for each run.
4. **Decision.** The 0-2 rung is the cheapest candidate that passes all three
   tasks. When none does, totals 0-2 run `claude-sonnet-5-5/low`, the native
   rung, and the lane's Gemini use ends there. The rows 0-2, the Gemini
   successor row (always to `claude-sonnet-5-5/medium`) and its timeout row
   are written from the result, and the results table is committed under
   `docs/dforge/notes/`.
5. **Smoke.** One more replayed task, scored 3-5, runs at its Claude rung and
   passes the same check.

A pass of steps 4-5 flips `trust.smoke` in its own commit, together with this
repository's auto-tick constraint; a smoke failure stops the plan before
routing is built on the lane.

### Per-plan breaker

After two `agy` handbacks in one plan, the controller treats `agy` as
`off — unreliable` for the rest of that plan: it says so aloud, records it in
the ledger as `Plan: executor agy off - unreliable (2 handbacks)`, and
dispatches later `agy` tasks on their `**Implementer:**` agents. A resumed
controller reads the ledger line and keeps the lane off. This is additive to
the per-task rules; `agyLane` stays the manual switch.

### Unsandboxed reach

`agy` runs with the same reach as a native Claude implementer subagent: it can
write anywhere the user can, including other worktrees, the primary checkout
and `~`. This is accepted. `## Per-executor: agy` states it, so a recovery
reader knows the fingerprints cover only the linked worktree and its refs.

### Tests

Stub `agy` (a bash script on a sealed PATH) driven by environment variables to
emit success, error, quota, unknown-model, schema-less, print-timeout and
outer-timeout outputs, and optionally to run `git commit`, `git stash` or
`git branch`, or to write outside the write set.

- `tests/run-agy-task.test.sh`: each result shape gives the right status line,
  report keys, durable phase and staging; ref, HEAD or index changes block;
  quota marks the session off; resume passes `--conversation`; the prompt
  reaches `agy` as a pointer only; `--add-dir` names the prompt directory.
- `tests/agy-gate.test.sh`: setting off, not installed, version out of range,
  logged out, probe failed, untrusted, cache reuse, quota surviving
  `--refresh`.
- `tests/executors.test.sh`, `tests/detect.test.sh`: `ranked`, `priority`
  validation, the `agy` row, no `antigravity` row.
- `tests/plan-lint.test.sh`, `tests/plan-revise.test.sh`: priority routing with
  both executors ticked, and with only Codex ticked (unchanged output). The
  survey cases at `plan-revise.test.sh:276-278` are pinned to
  `DR_EXECUTORS_DIR=tests/fixtures/executors`, since survey mode counts every
  registered executor.
- `tests/lanes.test.sh` (or a sibling suite): every `agy-successor` row ranks
  strictly above its source, every walk reaches `HANDBACK`, every
  `agy-assignment` rung has a successor and a timeout row, and no
  `agy-timeout` bound plus 120 s exceeds 7,200 s.
- A drift check that `agy-report-schema.json` equals
  `codex-report-schema.json`.
- New suites get Windows shard weights in `scripts/test-all.mjs`.

### Amendment (2026-11-03)

Ruled on register `docs/dforge/registers/2026-11-02-antigravity-executor-lane-auto.md`:

- Row 1, Wrapper item 5 and A7: refs are shared with every other worktree, so
  the git guard blocks only on `HEAD`, the index, this worktree's branch and
  per-worktree refs, a stash entry made on its branch, a deleted ref or stash
  entry, a tag change, or a branch moved to a commit that does not descend from
  where it was. Other ref changes are listed in the report, `refs/remotes` is
  ignored, and `git branch` no longer blocks.
- Row 3, Wrapper item 4: a quota matched only in stderr gives `reason=quota`
  without marking the lane off; `.error` and non-JSON stdout still mark it off.

## Acceptance

A1. [test, high] With `agy` registered and its gate open, `detect-executors.sh` reports `agy` as `usable: true` with its version, and reports no `antigravity` row.
A2. [test, high] `executors ranked` prints `agy` before `codex`; `executors list` output is unchanged apart from the added `agy` id; a non-integer `priority` ranks last with one stderr line.
A3. [test, high] With both executors ticked, a task with total 0-8 and risk ≤ 2 that clears the lane gate gets `**Executor:** agy <model> / <effort>` from `agy-assignment`, and `plan-lint` reports an ERROR when such a task names `codex` instead.
A4. [test, neg, high] A risk-3 task, a batched task, or a task with a human override never gets an `agy` Executor line, and `plan-lint` rejects one written by hand.
A5. [test, neg, high] With `agy` unticked or `agyLane=false`, `plan-lint` and per-plan `plan-revise` output are unchanged on the existing fixtures, and Codex routing is unchanged; survey-mode `eligible=` counts may change and are pinned to the fixture registry.
A6. [test, high] `run-agy-task.sh` on a stub `agy` returning `structured_output.status = DONE` commits only the approved write set under the reported subject and prints `agy <model>/<effort> status=DONE exit=0 commits=<a>..<b> thread=<conversation_id> report=<path>`.
A7. [test, neg, high] When the stub `agy` runs `git commit`, `git stash` or `git branch`, or changes the index, the wrapper commits nothing, blocks the task, and names the moved ref or the index in the report.
A8. [test, high] An `agy` error whose text matches the quota pattern turns the lane off for the rest of the session: `agy-gate` and `agy-gate --refresh` both print `lane=false reason=quota`, and the next wrapper call exits 2 without running `agy`.
A9. [test, high] A resume passes `--conversation <id>` with the thread, model and effort pinned in the task record; a mismatch is refused before `agy` runs.
A10. [test, neg, high] The brief never reaches `agy` as a command-line argument: the `-p` argument is the fixed pointer sentence whatever the brief's size, and `--add-dir` never names the directory holding `state.json`.
A11. [test, high] `agy-gate` prints `usable=false lane=false` with reasons `setting`, `plugin-not-installed`, `plugin-version:<v>`, `logged-out` and `probe-failed` for each of those states, `usable=true lane=false` while `trust.smoke` is not `pass`, and `lane=true` only when every condition holds.
A12. [demo, confirmed] The plan's smoke step runs one real replayed task scored 3-5 through `run-agy-task.sh` at its Claude rung, with `DR_AGY_POLICY` exported for all three gate reads, before any routing or documentation task; the change passes its Claude task review, and only then does a separate commit set `trust.smoke: "pass"`.
A13. [demo, confirmed] The model and effort for totals 0-2 come from the calibration task: the cheapest of `gemini-3.8-flash/low`, `gemini-3.8-flash/medium` and `gemini-4-argon/low` that passes all three replayed tasks (tests pass, scope clean, Claude judge passes), else `claude-sonnet-5-5/low`; the results table is committed under `docs/dforge/notes/` and the `agy-assignment` rows 0-2 match it.
A14. [test, confirmed] In this repository, plans tick `agy` without asking when its gate says `lane=true`, by a constraints entry committed together with the trust flip and never before it.
A18. [test, high] After two `agy` handbacks in one plan, every later `agy` task in that plan is dispatched on its `**Implementer:**` agent, the ledger carries `Plan: executor agy off - unreliable (2 handbacks)`, and a resumed controller keeps the lane off.
A19. [test, neg, high] `## Per-executor: agy` states that `agy` is unsandboxed and that the fingerprints cover only the linked worktree and its refs.
A15. [test, high] A print timeout (`finished_reason: "print_timeout"`, exit 0) reports `status=BLOCKED exit=124 note=timed-out` with `reason=timeout` and `timedOut=true`, never DONE.
A16. [test, high] The `agy-successor` column is acyclic by rank and every walk reaches `HANDBACK`, checked by a suite rather than by reading.
A17. [test, high] The validation run passes: `node scripts/validate-repository.mjs`, the maintained suites, `claude plugin validate` on the marketplace and every Claude plugin, and `claude plugin test plugins/dforge`; and the pushed commit's `Validate marketplace` run is green on every job, Windows shards included.

## Riskiest assumption

That `agy` completes a real dforge task brief — tens of kilobytes of brief, test
commands and a TDD contract — headless within the write set, returning a valid
`structured_output`, the way it completed the small edits measured on
2026-11-02. If it routinely stops early, ignores the contract or edits git, the
lane costs a wrapper run, a review and a handback per task and offloads nothing.

Unverified — the plan verifies it with the smoke task (A12), as soon as the
wrapper and gate exist and before any routing or documentation task. The
shipped lane stays closed (`trust.smoke: "fail"`) until that run passes. A
second unknown rides on it: the text `agy` prints when logged out or over quota
was never observed, so the quota and logged-out patterns (A8, A11) are assumed
until a real occurrence is recorded.

## Review rulings

- Fable, spec: A13 — keep `medium`; superseded by the owner, who chose to decide the 0-2 rung by calibration.
- Fable, spec: A14 — add the constraint, committed with the `trust.smoke` flip, never before.
- Fable, spec: A12 — the smoke task belongs to this plan, before routing and documentation, with `DR_AGY_POLICY` exported for all three gate reads; the trust flip is its own commit.
- Fable, spec: `agy-gate --refresh` keeps a cached `reason=quota` for the session.
- Fable, spec: the git guard compares refs and the symbolic HEAD; HEAD and index are already covered by `dr_task_validate_scope`.
- Fable, spec: `--add-dir` names a prompt-only subdirectory, never the task directory.
- Fable, spec: writer-stopped scans `timeout`'s process group after `wait`; on Windows every outer kill is `writer-unconfirmed`.
- Fable, spec: `## Agy error` carries `reason=` and `timedOut=`; `exit=` is normalised to 0/1/124 with `note=timed-out`.
- Fable, spec: `reason=unknown-model` only on a stated pattern; anything else is `reason=error`.
- Fable, spec: measure `--print-timeout` before relying on it (done 2026-11-02: exit 0 with `finished_reason: "print_timeout"`, now classified as a timeout).
- Fable, spec: A5 excludes plan-revise survey mode; the survey cases are pinned to the fixture registry.
- Fable, spec: the successor column gets a rank-based termination test.
- Fable, spec: `ladder.md`'s lane prose is rewritten per executor, with the reason for `agy`'s floor of 0.
- Fable, spec: the single-executor passages of `executor-lane.md` are enumerated for rewrite.
- Fable, spec: a drift test keeps `agy-report-schema.json` equal to `codex-report-schema.json`.
- Fable, spec: `priority` is validated as a non-negative integer.
- Fable, spec: the setting's label is `Agy tasks` (16-character limit).
- Fable, spec: the pointer path and `--add-dir` go through `dr_native_path`.

## Critic findings

Folded into Fable's round 1: 1 Blocker, 4 High (all fixed by the rulings above),
9 Medium, 5 Nit.

- [Blocker, fixed] Quota mark-off undone by `--refresh` — Gate §Quota is sticky.
- [High, fixed] Git guard missed stash and ref writes — Wrapper item 5.
- [High, fixed] `--add-dir` exposed the task record — Wrapper item 2.
- [High, fixed] Writer-stopped had no mechanism — Wrapper item 6.
- [High, fixed] Report lacked classification keys — Wrapper item 4.
- [Medium, fixed] A5 false for survey mode — A5 and Tests.
- [Medium, fixed] No successor termination proof — Ladder blocks and A16.
- [Medium, fixed] `ladder.md` prose contradicts a floor of 0 — Ladder blocks.
- [Medium, fixed] Single-executor passages only partly listed — the enumerated section.
- [Medium, fixed] `--print-timeout` unmeasured — measured, Wrapper item 4, A15.
- [Medium, fixed] Windows path forms — Wrapper item 2.
- [Medium, fixed] Smoke override in one of three places — Smoke task.
- [Medium, decided] No per-plan circuit breaker — owner: "Off after 2 handbacks"; Per-plan breaker.
- [Medium, decided] Out-of-worktree writes unaccepted — owner: "Accept and document"; Unsandboxed reach.
- [Nit, fixed] unknown-model pattern; schema drift; `priority` validation; `reasons.missing` dropped; block renamed `agy-lane-gate`.
