# dr-opencode spec review — merged findings

Spec reviewed: `docs/superpowers/specs/2026-09-20-dr-opencode-executor-design.md` @ `251880b`.
Run: 2026-09-20. Two seats, same prompt, same four criteria reinterpreted for a spec.

| Seat | executability | coherence | coverage | assumptions | Findings |
|---|---|---|---|---|---|
| `gpt-6-astra/high` via `run-codex-review.sh --kind plan` | 6 | 6 | 8 | 6 | 33 |
| `dr-superpowers:judge-fable` | 7 | 8 | 7 | 9 | 25 |

The astra seat ran as a human override: `codex-gate` reported
`usable=true review=false` because `trust.calibration` is `pending`
(see `2026-09-20-review-routing-calibration.md`).

**A calibration data point in passing.** On this artifact the two seats scored
within 3 of each other on every axis, against 5 to 9 between astra and the
recorded Claude baselines in the same day's calibration. That is evidence the
calibration's baselines were the outlier rather than the astra seat.

## Verdict

Neither seat considers the spec implementable as written. Every Critical
finding points at one cause: **dr-superpowers does not have an executor lane
that happens to run Codex. It has Codex** — named in the scripts, the lint
rules, the session library, the ruling kinds and the skill prose. The spec's
founding premise, that OpenCode could be added as a structural sibling, is what
failed. The work was therefore decomposed into two sub-projects; this file is
the requirements source for the first.

Attribution: **A** astra, **F** fable, **A+F** both independently.
"Verified" means checked against the code during this session.

## Critical — the lane cannot exist without these

1. **`plan-lint` rejects every OpenCode Executor line** (A+F, verified).
   `scripts/plan-lint:272-279` validates each `**Executor:**` line against the
   `codex-assignment` rung for the task's total and requires the header's
   external-executors line to name `codex`. An OpenCode line produces two
   ERRORs, and writing-plans requires `0 errors`, so the lane cannot be planned
   into existence. Fix: the Executor line's first token selects the assignment
   block; the header must name that token.

2. **`scripts/lib/codex-session.sh` is not lane-agnostic** (F, verified).
   It hardcodes the `codex-sessions` directory, the `DR_CODEX_SESSION_DIR`
   override and the `usable/review/lane` fields, and `codex_session_mark_off`
   rewrites all three to false. A copied gate sourcing it would overwrite the
   Codex gate's cached answer, and an OpenCode rate-limit mark-off would switch
   off Codex's review seats — which `review-route` and `plan-lint` both read.
   Fix: a per-executor session library and separate files.

3. **The free-cost guarantee leaks by design** (A+F). The runtime assertion
   sits in the dr-superpowers wrapper, so the standalone rescue seat spawns
   without it; a spawn without an explicit `--model` uses the user's configured
   default, which may be paid; OpenCode's separately configurable auxiliary
   models (title generation, agent-selected models) are unconstrained; a stale
   cached catalog still reads cost-0 after a provider starts charging, and
   "fail closed" was specified only for an absent catalog, never a stale one;
   and the predicate checks input and output price only, not cache or other
   billable dimensions. Fix: the assertion belongs in the companion,
   immediately before every model-bearing spawn, with a maximum catalog age and
   an explicit statement of residual exposure.

4. **Timeout and process ownership were misdescribed** (A+F, verified).
   `run-codex-task.sh:241` runs `timeout $((timeout_s + 60)) node
   codex-client.mjs`; the deadline, the interrupt and the reap live in the
   client. There is no wrapper poll loop. The proposed companion takes no
   deadline and returns no `timedOut`, yet the failure table depends on
   `note=timed-out exit=124`. On Windows the outer `timeout` kills node and
   strands the grandchild. Fix: give `run`/`resume` a deadline input and
   `timedOut`/`killed` outputs, and make the companion terminate the process
   tree.

5. **`opencode-empty-diff` is not a ruling kind** (A+F, verified).
   `scripts/review-route:187` allowlists
   `preflight|plan-conflict|cannot-verify|breaker|blocked-plan|codex-empty-diff|final-residual`
   and dies on anything else; `subagent-driven-development/SKILL.md` lists the
   same set. So "`review-route` is unchanged" is false. Fix: rename to a
   lane-neutral `executor-empty-diff` across routing, prompts and tests.

6. **The copied wrapper cannot consume the proposed companion result** (A).
   The wrapper reads `ok`, `finalMessage`, `threadId`, `timedOut`, `reason` and
   `reaped`; the spec's companion returns flattened report fields plus
   `session_id`, `exit` and `error`. A literal copy sees no `ok` and reports
   BLOCKED. Fix: either an explicit adapter or a companion implementing the
   existing normalized client contract.

7. **The integration table omits every surface that drives the lane** (A+F).
   Missing: `skills/writing-plans/SKILL.md` (whose planning flow stops at the
   Codex gate), `reference/delegated-task.md` (which routes every Executor line
   through the Codex reference and resumes a Codex session),
   `subagent-driven-development/SKILL.md` (ledger grammar `executor codex
   <m>/<e>, thread <id>`, and the ruling table), `scripts/plan-lint`,
   `tests/plan-lint.test.sh`, `tests/review-route.test.sh`,
   `tests/repository-layout.test.mjs` (hardcodes catalog membership), and the
   root `CLAUDE.md` catalog list.

8. **Inline mode ignores the lane entirely** (A, verified).
   `skills/executing-plans/SKILL.md:164` states `**Executor:**` lines "are
   inert" for tasks the session implements itself. The spec never says whether
   the lane is restricted to subagent-mode plans or changes inline dispatch.

## Important

9. **`detect-executors.sh`'s codex branch is hardcoded well past one string**
   (F, verified): `if [ "$id" = codex ]`, the locator and client by name, and
   three `/codex:setup` remedy strings. A per-id locator, probe and reason set
   is needed.
10. **The rate-limit mark-off has no mechanism** (A+F). The probe has no quota
    signal, and the prescribed `--refresh` after every non-DONE run reopens the
    gate the second 429 was meant to close. Where the 429 count lives is unsaid.
11. **The agent definition that denies `git` has no home** (F). In the worktree
    it dirties the clean-worktree preflight; in the user's global config it
    changes their own sessions. Likely `OPENCODE_CONFIG` pointing at a file
    shipped in the plugin — and that config-override path is itself unverified.
12. **`--variant` = reasoning effort is unverified and load-bearing** (A+F). If
    it does not select `reasoning_options.effort`, the three Muse rungs are the
    same call and the successor column is empty in practice.
13. **The companion's `error` is untyped** (A+F). The whole failure table keys
    off "the companion's classified error". Needs an enumeration and a
    statement of which members are transient.
14. **Windows spawn is unaddressed** (F). An npm-installed `opencode` is
    `opencode.cmd`, which node's `spawn` cannot exec unresolved, and `--dir`
    needs a native path — the same class of bug as `1bc0602`, fixed today.
15. **The companion's request contract is undefined** (A). Prompt transport
    matters on Windows: the Codex wrapper deliberately avoids long
    command-line arguments.
16. **The standalone plugin has no source for its policy or ladder** (A). Both
    authoritative files live in dr-superpowers, yet `dr-opencode` must work
    alone.
17. **OpenCode's cached catalog is treated as a known interface** (A) — no
    location, schema, version or precedence, and the network fallback has no
    deadline.
18. **`session_id` versus the durable `thread` field** (A+F). `task-state.sh`
    requires `thread`; renaming it would fail schema validation.
19. **A fenced JSON block is weaker than a schema** (A+F). "The last fence in
    the event stream" does not identify the terminal assistant message, and
    `structured_output` metadata does not guarantee compliance with a prose
    request.
20. **Failed fix-round resumes have no complete response table** (A).
21. **Repeated `NEEDS_CONTEXT` has no bound** (A). The Codex reference makes a
    second one a capability failure; the spec adopts no equivalent.
22. **The `smoke` trust gate has no acceptance procedure** (A+F), so the lane
    would ship permanently disabled with no documented way to enable it.
23. **Muse Spark 1.3 capability metadata is assumed** (A). Its catalog entry
    says capabilities follow 1.2 pending public specifications.
24. **The version allowlist constrains the plugin, not the CLI** (A+F). The
    five experiments can pass on one OpenCode release and break on the next.
25. **§16 understates the blast radius** (A+F). A failed V3 means every run
    hangs to the rung's timeout and is retried once — two full budgets per task
    before HANDBACK; a failed V4 invalidates the whole context-preserving fix
    loop.
26. **The drift reporter has no replacement-selection rule** (A). Several
    reserve models lack the properties the current ladder was justified by.
27. **Tests cross the plugin boundary** (F). `opencode-client` and
    `free-models` exercise code in `dr-opencode`, but every suite was placed in
    `dr-superpowers/tests/` and `dr-opencode` was given no `tests/` or runner.
28. **`not-free` conflates two causes** (F): model went paid, versus no catalog
    resolved. The second should behave like a shut gate, not a permanent
    HANDBACK.
29. **The local-source caveat is undecided** (F). No anchor is named for
    "resolves to `plugins/dr-opencode` in the current repository", and skipping
    the allowlist for any non-cache path is a trust hole.

## Minor, including four factual errors in the spec

30. The timeout figures are not "the Codex budgets carried over": Codex is
    900/1200/1800/2400, the spec proposed 900/900/1200/1800 (A+F).
31. Muse Spark 1.2 also has structured output, an effort axis and the same
    context, so §7's "only live model with both" is wrong (A).
32. `validate-repository.mjs:46` applies the empty-Codex-hooks rule only to
    `dr-superpowers`, so "satisfies all four by construction" overstates (A+F).
33. §14 names `tests/native-routing.test.sh`, which exercises
    `select-native-tier.sh`, not `review-route` (A, verified).
34. §5.2's no-session-id claim is not `codex-gate`'s behaviour: it prints the
    probe's answer with `lane=false` and writes no file (A+F, verified).
35. §2.2 is headed "Verified facts" but the CLI table was read from
    documentation, the binary being absent (F).
36. D5 says no precedence rule is needed while §8 introduces one (A).
37. The rank argument gives `-` and `minimal` the same rank, and
    `tests/lanes.test.sh` hardcodes a Codex-only `rank()` and model list (F).
38. `scripts/opencode-task-contract.md` is named in §9.2 but missing from §5's
    file tree; the wrapper's `$SCHEMA` preflight needs an explicit "dropped"
    note (F).
39. "The last fence" parse accepts a model echoing the contract's own example
    block as its verdict (F).

## Adjacent finding in the shipped plugin, unrelated to this spec

Chasing finding 4 turned up a live defect in the Codex lane.
`reference/external-executor.md` (lines 94-95, 233) documents a wrapper poll
loop that kills Codex on timeout, and a `note=codex-may-still-be-running`
outcome the controller is instructed to detect and clean up before retrying.
Neither exists: there is no poll loop, and `survivor=yes` is never assigned
anywhere in `run-codex-task.sh`, so that note can never print. The shipped
reference describes a mechanism the code no longer has, and instructs a
controller to handle a state it can never observe.
