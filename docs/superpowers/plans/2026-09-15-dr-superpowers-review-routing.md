# dr-superpowers Review Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Codex the default task reviewer and plan-review round-1 seat with named Claude fallbacks, route risk >= 2 through Astra then Fable, retire `risk3-spread`, put the routing table in a tested script, and put every Codex use behind a once-per-session gate so an unusable or untrusted Codex degrades to Claude seats instead of failing a task.

**Architecture:** A new pure script `scripts/review-route` maps a plan's `**Evaluation:**` and `**Executor:**` lines (or a plan-review round) to a seat and its fallback. `scripts/run-codex-review.sh` gains `--kind task|plan` and `--tier light|heavy` and checks availability on every run. A session gate — `scripts/codex-plugin` locates the official codex plugin, `scripts/codex-gate` reads its login and quota through the plugin's own client once per session, and `scripts/lib/codex-session.sh` reads the per-session answer — decides whether Codex is usable and which surfaces (review, lane) its shipping gates have opened: `review-route` names Claude seats while the review surface is off, the runner refuses unless the gate says usable and turns Codex off on a quota error, and `plan-lint`'s lazy lane probe runs only while the lane surface is on. Skill and reference prose then run the gate before those scripts. Two shipping gates — a calibration replay and a real executor-lane smoke run — produce the evidence tests cannot, and run only when the gate reports Codex usable.

**Tech Stack:** Bash, `jq`, coreutils `timeout`, Node.js (the gate's probe), Markdown, git, the official `codex@openai-codex` Claude Code plugin (the gate's only route to Codex), the `codex` CLI (Tasks 10 and 15 only, and only when the gate reports usable).

**Spec:** `docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md`

**Execution:** inline — `claude --model opus --effort low` — every task totals 4 or less and none is at risk 3; Tasks 2, 5, 7B, 8A, 8B, 10, 11, 14 and 15 are the 4s, so the model follows them into the Opus-low band. Tasks 10 and 15 run Codex as background Bash calls, and only when `scripts/codex-gate` reports it usable.

**Program:** `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` — sub-project 8 of 9 — next: Codex through the plugin

**Plan review:** 2026-09-16 — dr-superpowers:judge-opus — executability 17 / coherence 18 / coverage 18 / assumptions 17 (round 3)

## Global Constraints

- Plugin version stays `1.8.0` until Task 17, which sets `1.9.0` on both `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json`. The two must stay equal.
- Not modified by any task: `reference/codex-routing.json`, `reference/native-codex.md`, `scripts/run-codex-task.sh`, `scripts/detect-executors.sh`, every fenced block in `reference/ladder.md`, `reference/final-review.md` (the final-review Codex round reaches the gate through `reference/external-executor.md` §Final-review Codex round, Task 13), and the ruling-seat, final-verify and spec-review seats.
- `run-codex-review.sh --kind risk3` and `--kind final` keep their exact current behaviour, status line, exit codes and argv, except the spec §15.5 gate refusal and quota mark-off that Task 8 part B adds to every kind.
- English only, in every file: code, comments, docs, commits, tests.
- Commits follow `<type>(<scope>): <subject>`, subject 50 characters or fewer, imperative, no trailing period. The scope is `superpowers`.
- New scripts and test suites are mode `100755` in the index. `git config core.filemode` is `false` on this machine, so `chmod +x` does not reach the index: run `git update-index --chmod=+x <path>` after `git add`.
- Agent files are ASCII only (`tests/fleet.test.sh` checks it): no em dashes in `agents/*.md`.
- No file under a plugin may contain `superpowers:` without the `dr-` prefix, or `dcc-superpower-companions:` (`scripts/validate-repository.mjs:85`).
- Only Tasks 10 and 15 call Codex, and only when `scripts/codex-gate` reports `usable=true`. Every test runs against stubs; no test starts a real Codex or reads the machine's Claude config.
- Every suite touching `scripts/review-route`, `scripts/run-codex-review.sh` or `scripts/plan-lint` exports `DR_CODEX_SESSION_DIR` (a temporary directory) and `CLAUDE_CODE_SESSION_ID` (a fixed id) near its top, so the machine's real session file never reaches a case. `tests/codex-review.test.sh` also points `CODEX_REVIEW_GATE` at a stub.
- The session gate reaches Codex only through the codex plugin: no new script names the `codex` executable or reads Codex-owned state (spec §15.1, ruling 13).
- Code fences marked as verified prototype code (Tasks 6 and 7) are transcribed byte for byte.
- Never commit `.superpowers/`. Never touch the untracked `plugins/darkmem-resume/`.
- Every command in every step runs from the repository root: `bash plugins/dr-superpowers/tests/…`, `node scripts/validate-repository.mjs`, `git …`. Prose written into skill files says `scripts/…` because a skill runs its scripts from the plugin root; that is text to write, not a command to run now.

## Contracts

Paths are repository-relative unless a step says otherwise. `P` in test suites is the plugin root.

**Files this plan creates**

| Path | Produced by |
|---|---|
| `plugins/dr-superpowers/criteria/codex-plan-review-schema.json` | Task 1 |
| `plugins/dr-superpowers/agents/judge-sonnet-high.md` | Task 3 |
| `plugins/dr-superpowers/scripts/review-route` | Task 4, codex-off rows by Task 8 part A |
| `plugins/dr-superpowers/tests/review-route.test.sh` | Task 4, extended by Tasks 5, 8 part A, 9, 11, 12, 13, 17 |
| `plugins/dr-superpowers/reference/codex-plugin.json` | Task 6; `trust` set by Tasks 10 and 15, each only on its gate's PASS |
| `plugins/dr-superpowers/scripts/codex-plugin` | Task 6 |
| `plugins/dr-superpowers/tests/codex-gate.test.sh` | Task 6, extended by Task 7 parts A and B; one check edited by Tasks 10 and 15 on PASS |
| `plugins/dr-superpowers/scripts/lib/codex-session.sh` | Task 7 part A |
| `plugins/dr-superpowers/scripts/lib/codex-gate.mjs`, `plugins/dr-superpowers/scripts/codex-gate` | Task 7 part B |
| `docs/superpowers/notes/2026-09-15-review-routing-calibration.md` | Task 10, extended by Task 15 |
| `docs/superpowers/distilled/constraints.md` | Task 16 |

**`scripts/run-codex-review.sh` interface** (Task 2, gated by Task 8 part B; consumed by Tasks 5, 10, 11, 13):

```
run-codex-review.sh --kind task|risk3|plan|final --cwd <dir> --out <path>
                    (--prompt <file> | --base <ref>) [--tier light|heavy] [--dry-run]
```

- `task` and `risk3` are one kind: `--prompt` required, schema `criteria/codex-review-schema.json`, valid output has `spec_verdict`, `task_quality`, `cannot_verify`.
- `plan`: `--prompt` required, schema `criteria/codex-plan-review-schema.json`, valid output has `executability`, `coherence`, `coverage`, `assumptions`, `findings`.
- `final`: `--base` required, unchanged.
- `--tier` is accepted only with `task`/`risk3`; default `heavy`. `light` runs the `codex-judge` block's last row (`gpt-5.6-sol high`) and never falls back. `heavy` is the existing selection: first row if advertised, else last row, plus one fallback on refusal.
- Status line, exit codes (0 `OK`/`FALLBACK`, 1 `TIMEOUT`/`FAILED`, 2 usage) unchanged: `codex-judge <model>/<effort> status=<S> exit=<n> out=<path> evidence=<fetched_at|unknown>`.
- The gate (Task 8 part B). After argument validation and before the roster, every kind, `--dry-run` included, runs `bash "${CODEX_REVIEW_GATE:-<scripts>/codex-gate}"`. Unless it exits 0 with a last line containing ` usable=true `, the runner prints `codex-judge none/none status=FAILED exit=0 out=<out> evidence=unknown`, writes `run-codex-review: codex is off for this session (<reason>)` to stderr — `<reason>` is the line's `reason=` value, or `codex-gate exited <n>` — and exits 1. It reads `usable` only, never `review`, so a shipping gate can exercise an untrusted surface.
- The quota (Task 8 part B). After an attempt that is neither `TIMEOUT` nor valid output, and whose `error_lines` match `usage limit|rate_limit_reached` (case-insensitive), the runner calls `codex_session_mark_off quota` and prints that attempt's `FAILED` line. The check precedes the refusal check, so a quota error never takes the fallback row; after the fallback attempt it runs on `<out>.fallback`'s logs.

**`criteria/codex-plan-review-schema.json` fields** (Task 1): integers 1-20 `executability`, `coherence`, `coverage`, `assumptions`; `findings` array of `{severity: Critical|Important|Minor, where: string, summary: string}`; every object `additionalProperties: false` with every property required.

**`scripts/review-route` interface** (Task 4, codex-off rows by Task 8 part A; consumed by Tasks 5, 9, 11, 13):

```
review-route PLAN_FILE --task <id> [<id> ...]
review-route PLAN_FILE --plan-round <r>
```

`<id>` is `N` or `N` plus a part letter (`7B`). Output, exit 0, exactly one line:

```
review-seat <scope> primary=<seat> fallback=<seat|-> reason=<executor|risk|band|round|codex-off>
```

`<scope>` is `task=<ids joined by commas>` or `plan-round=<r>`. Seat names: `codex:light`, `codex:heavy`, `codex:heavy+judge-fable`, `codex:plan`, `dr-superpowers:judge-sonnet-high`, `dr-superpowers:judge-opus`, `dr-superpowers:judge-fable`. Routing, first match wins, on the highest total and highest risk across the ids and every Evaluation line inside them: Executor and risk >= 2 → `judge-fable`, fallback `-`, `executor`; Executor → band judge, fallback `-`, `executor`; review surface off (`codex_session_on review` fails) and risk >= 2 → `judge-fable`, fallback `-`, `codex-off`; review surface off → band judge, fallback `-`, `codex-off`; risk >= 2 → `codex:heavy+judge-fable`, fallback `judge-fable`, `risk`; total <= 3 → `codex:light`, fallback band judge, `band`; else `codex:heavy`, fallback band judge, `band`. Band judge: total <= 1 `judge-sonnet-high`, <= 4 `judge-opus`, else `judge-fable`. Plan round 1 → `codex:plan`, fallback `dr-superpowers:judge-fable`, `round`, or with the review surface off `dr-superpowers:judge-fable`, fallback `-`, `codex-off`; round >= 2 → `dr-superpowers:judge-opus`, fallback `-`, `round`, whatever the surface. Exit 2 with a `review-route: …` message on stderr for usage errors, a missing plan, an unknown task or part, a missing or unparseable Evaluation line, or a `Host: codex` plan. The script reads the session file and probes nothing.

**`plan-lint` interface** (Task 14): `plan-lint PLAN_FILE [--amendments FILE] [--no-probe]`, flags in any order. Roster command `bash "${PLAN_LINT_ROSTER:-<scripts>/detect-executors.sh}"` under `timeout 30`, run at most once, only for a non-inline Claude-host plan with at least one lane candidate, no `--no-probe`, and `codex_session_on lane` succeeding. Warning text: `WARN <Task N|Task N part X>: lane-eligible with no **Executor:** line (codex <model> / <effort>)`.

**`reference/codex-plugin.json`** (Task 6), the policy file, path overridable by `DR_CODEX_POLICY`: `{"plugin": "codex@openai-codex", "versions": ["1.0.3"], "trust": { "calibration": "pending", "smoke": "pending" }}`. Task 10 sets `trust.calibration` to `"pass"` only on a calibration PASS, Task 15 sets `trust.smoke` to `"pass"` only on a smoke PASS, each in the same commit as its notes.

**`scripts/codex-plugin` interface** (Task 6; consumed by Task 7 part B): no arguments. One line, exit 0 `codex-plugin ok version=<v> root=<install path, to the end of the line>`, or exit 1 `codex-plugin off reason=<plugin-not-enabled|plugin-not-installed|plugin-missing|plugin-version:<v>>`; exit 2 on an argument, a missing `jq`, or a missing policy file. It reads `enabledPlugins` from `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`, then, only when `CLAUDE_PROJECT_DIR` is set, `$CLAUDE_PROJECT_DIR/.claude/settings.json` and `settings.local.json` (last definition wins), and the format-2 registry `<config>/plugins/installed_plugins.json` (the `scope: "user"` install, else the first).

**`scripts/codex-gate` interface** (Task 7 part B; consumed by Tasks 8 part B, 9, 10, 11, 13, 15):

```
codex-gate [--refresh]
codex-gate usable=<true|false> reason=<r> review=<true|false> lane=<true|false> resets_at=<iso|-> source=<probe|cache>
```

Exit 0 whatever the answer; exit 2 on a usage error or a missing `jq`, `node` or policy file. `reason` is `ok` when usable, else a `codex-plugin` reason, `plugin-api`, `logged-out`, `method-missing`, `quota` or `timeout`. `review=true` needs `usable=true` and `trust.calibration` = `pass`; `lane=true` needs `usable=true` and `trust.smoke` = `pass`; trust is re-read on every call. Without `--refresh` a session file with `usable: true`, or `usable: false` and a null or future `resets_at_epoch`, answers `source=cache`; anything else probes through `node scripts/lib/codex-gate.mjs <plugin-root> <cwd> <timeout-ms>`, which prints one JSON line `{"usable": <bool>, "reason": <string>, "resets_at_epoch": <seconds|null>}`, under the node deadline `DR_CODEX_GATE_TIMEOUT_MS` (default 30000) and an outer coreutils `timeout` of that plus 15 seconds.

**The session file** (written by `codex-gate`, marked off by the runner): `${DR_CODEX_SESSION_DIR:-$HOME/.claude/dr-superpowers/codex-sessions}/<CLAUDE_CODE_SESSION_ID>.json`, one JSON object with `session_id`, `usable`, `review`, `lane`, `reason`, `checked_at`, `resets_at` (UTC ISO with `Z`, or null), `resets_at_epoch` (seconds, or null), `plugin_version` (or null). Written by rename; files older than seven days are pruned. With no session id nothing is written and every reader is off.

**`scripts/lib/codex-session.sh`** (Task 7 part A; sourced by `scripts/codex-gate`, by `scripts/review-route` in Task 8 part A, by `scripts/run-codex-review.sh` in Task 8 part B, and by `scripts/plan-lint` in Task 14): `codex_session_id`; `codex_session_dir`; `codex_session_file` (fails when there is no session id); `codex_session_on <review|lane>` (succeeds only when this session's file parses and that field is `true`); `codex_session_write <json>`; `codex_session_mark_off <reason>` (writes `usable`, `review`, `lane` false, both reset fields null, keeps `plugin_version`; does nothing without a session id).

**Environment seams:** `DR_CODEX_POLICY` (policy file; `codex-plugin`, `codex-gate`), `DR_CODEX_SESSION_DIR` (session directory), `CLAUDE_CODE_SESSION_ID` (session id, set by Claude Code), `DR_CODEX_GATE_TIMEOUT_MS` (probe deadline), `CODEX_REVIEW_GATE` (the gate the runner calls), `CLAUDE_CONFIG_DIR` and `CLAUDE_PROJECT_DIR` (read by `codex-plugin`). Test-only: `GATE_STUB_MODE` and `GATE_STUB_LOG` (the stub plugin client, Task 7 part B), `GATE_STUB_LINE` and `GATE_STUB_EXIT` (the stub gate, Task 8 part B).

**Gate prose** (Tasks 9, 11, 13): every Codex use in skill and reference prose runs `scripts/codex-gate` first and says its line aloud when it ends `source=probe`; the line itself is never ledgered. A surface that is off is reported as `codex off — <reason>`, `<reason>` being the gate's `reason`, or `untrusted` when the gate printed `usable=true`.

**Agents** (Task 3): `dr-superpowers:judge-sonnet-high` (Sonnet 5, high); `dr-superpowers:judge-opus` unchanged except its description.

**Workspace artefacts** (named in prose by Tasks 5 and 11, all under `<workspace>` = the directory `scripts/sdd-workspace PLAN_FILE` prints): `plan-round-<r>.md`, `plan-review-prompt.md`, `plan-review-round-<r>.json` (Codex) or `.md` (Claude), `plan-delta-<r>.diff`, `task-<N>-review-codex-prompt.md`, `task-<N>-review-codex.json`.

**Prompt placeholders** (Tasks 5 and 11): `[DELTA_FILE]`, `[PRIOR_FINDINGS_FILE]`, `[ROUND]` in the plan-review delta template; `[CODEX_REVIEW_FILE]` in the task reviewer's Second Pass section.

**Ledger seat clause** (Task 11): inside the complete line's scores clause, `, seat <seat>` where `<seat>` is `codex <model>/<effort>`, `codex <model>/<effort>+judge-fable`, or a judge's short name, followed by ` (codex <STATUS> — <reason>)` when it replaced a Codex seat, or by ` (codex off — <reason>)` when `review-route` printed `reason=codex-off` (Gate prose). It replaces `, K=3`.

**Test-suite helpers.** `tests/review-route.test.sh` (Task 4) defines `P`, `check`, `present`, `absent`, and `route`; Task 8 part A adds the session exports and `review_surface <true|false|absent>` below its `trap` line and inserts its codex-off cases before the line `route --task 9`. Tasks 5, 9, 11, 12, 13 and 17 append blocks that call `present` and `absent` immediately before its final `printf '\n%d passed, %d failed\n'` line; Task 9 reads `WP`, defined by Task 5's block. `absent` is defined by Task 4 and first called by Task 5 — Task 4 keeps it although Task 4 itself never calls it. `tests/codex-gate.test.sh` (Task 6) defines `P`, `TMP`, `check`, `CFG`, `PLUG`, `enable`, `install_plugin` and `locate`; Task 7 part A adds `SESS`, `POLICY`, `gate`, `field` and `fresh` with the session-reader cases before its final `printf`; Task 7 part B inserts the stub client before the line `SESS="$TMP/sessions"` and the gate cases before the line that begins `# --- the session readers`.

## Assumptions (evidence)

- Codex is not usable for this plan today. On 2026-09-15 all four calibration replays of the old Task 6 (now Task 10) returned `status=FAILED` on `You've hit your usage limit ... try again at Sep 20th, 2026 5:03 PM` (`.superpowers/sdd/2026-09-15-dr-superpowers-review-routing/progress.md`). The prototype gate against the real plugin with `CLAUDE_CONFIG_DIR=C:/Users/quang/.claude` printed `usable=false reason=quota ... resets_at=2026-09-20T10:03:27Z source=probe`, then `source=cache`, and with the `.claude-alt` profile printed `reason=plugin-not-enabled` (`.superpowers/sdd/2026-09-15-dr-superpowers-review-routing/plan-revision.md`, 2026-09-15). The quota resets 2026-09-20 17:03 +07. Tasks 10 and 15 therefore expect to record `PENDING`, and 1.9.0 is expected to ship with every Codex surface off (spec §15.6).
- This session's Bash environment carries `CLAUDE_CONFIG_DIR=C:/Users/quang/.claude-alt` and `CLAUDE_CODE_SESSION_ID` — verified 2026-09-15 (spec §15.2, §15.3).
- Tasks 6 and 7 carry the prototypes in `.superpowers/sdd/2026-09-15-dr-superpowers-review-routing/prototypes/`: `bash prototypes/tests/codex-gate.test.sh` printed `53 passed, 0 failed` in about 30 s on 2026-09-15. Three deliberate changes, each re-verified at 53 passed, 0 failed on 2026-09-15 against scratch copies: `scripts/codex-gate` joins its cache fields with jq's `"\u001f"` escape where the prototype had a literal unit-separator byte a transcriber cannot see (the suite fails 5 cases when that separator is lost), and the suite's policy copy resets `trust` to pending instead of `cp`, so a later trust PASS breaks only the check that records the shipped trust (verified: with both fields `pass`, only `the policy file ships untrusted` fails), and the locator and gate helpers clear `CLAUDE_PROJECT_DIR` so a project setting on the machine running the suite cannot leak in (re-verified 2026-09-16 at 53 passed, 0 failed with `CLAUDE_PROJECT_DIR=/nonexistent` exported). Each stage was also run red then green on scratch copies: Task 6 `0 passed, 15 failed` then `15 passed, 0 failed`; Task 7 part A `20 passed, 2 failed` then `22 passed, 0 failed`; part B `24 passed, 29 failed` then `53 passed, 0 failed`.
- The edits of Tasks 8, 9 and 14 were applied to scratch copies of the plugin at HEAD `18a00a7` on 2026-09-15 and their suites run: `tests/review-route.test.sh` `48 passed, 12 failed` against HEAD's script, then `60 passed, 0 failed`, then `60 passed, 3 failed` and `63 passed, 0 failed` for Task 9's needles; `tests/codex-review.test.sh` `86 passed, 14 failed` against HEAD's runner, then `100 passed, 0 failed`; `tests/plan-lint.test.sh` `72 passed, 5 failed` against HEAD's `plan-lint`, then `77 passed, 0 failed`; `tests/plan-amend.test.sh` `22 passed, 0 failed`.
- Tasks 7 and 8 are split into `#### Part A` / `#### Part B` at planning time: whole, each would carry four files and produce an interface, `files 2 + coupling 2` = reducible 4, which Rule S forbids (`reference/ladder.md`, Rule S). Parts keep the numbering the ledger ruling uses. `scripts/plan-lint:143-150` checks each part as its own unit, `review-route` routes a part id, and the SDD complete line records `; parts A, B` (`skills/subagent-driven-development/SKILL.md:279`) — read 2026-09-15. Under inline execution a split task runs part A, then part B, one commit each.
- The ledger's `Task 6: BLOCKED` line (`progress.md`, 2026-09-15) refers to the old calibration task, now Task 10. Before Task 6 starts the controller appends the revision's `Ruling:` line, and the next `Task 6: implementer inline (assigned; base <sha7>)` line supersedes the BLOCKED line for recovery (`plan-revision.md`, Review and ledger).
- `tests/plan-amend.test.sh` needs no session exports: after Task 14 `scripts/plan-amend` calls `plan-lint --no-probe`, which never reads the session file.
- Git Bash's GNU `date -u -d @<epoch>` formats the quota reset: the prototype suite's quota case printed `resets_at=2026-09-20T10:03:27Z` from `1789898607` on 2026-09-15.
- No existing `tests/plan-lint.test.sh` fixture contains a lane candidate (Claude plan, no Override, Rule S clean, total >= 2, risk <= 1, no Executor): read 2026-09-15, `tests/plan-lint.test.sh:30-307` — Task 1 totals 1, Task 2 carries risk 2, and every variant that raises a total also raises risk or breaks Rule S. Existing cases therefore never reach the probe.
- `reference/ladder.md`'s `assignment` block maps total 2 to `impl-sonnet-medium` and its `codex-assignment` block maps total 2 to `gpt-5.5 medium` (`reference/ladder.md:67,215`, read 2026-09-15); Task 14's `p1`-`p3` fixtures and its expected WARN text depend on both.
- `scripts/plan-amend:76-77` is the only script that runs `plan-lint`, and it reads only `ERROR` lines — grep 2026-09-15.
- `scripts/validate-repository.mjs:98-105` resolves every `dr-superpowers:<name>` in plugin files to a skill directory or an `agents/<name>.md`; hence Task 3 precedes the first file naming `judge-sonnet-high`.
- `scripts/test-all.mjs` runs every `plugins/dr-superpowers/tests/*.test.sh` with a 300-second bound (its `jobs` array) — read 2026-09-15; `tests/codex-gate.test.sh` takes about 30 s. `tests/ui-discovery.test.mjs` fails on this machine with `bash: rg: command not found`, pre-existing — verified 2026-09-14.
- `tests/fleet.test.sh:36` pins the exact agent list (19 names) and, for `judge-*`, requires the tools `Read, Grep, Glob, WebFetch`, effort `high` or `medium`, no `skills:`, ASCII only — read 2026-09-15.
- `tests/codex-review.test.sh:295-299` pins the SDD needles `run-codex-review.sh`, `TIMEOUT or FAILED` and `never re-dispatch the Codex seat`; `tests/inline-mode.test.sh:82` pins `no task reviewer` in `skills/executing-plans/SKILL.md`. Tasks 11 and 12 keep all four. No suite pins the `reference/external-executor.md` or `skills/writing-plans/SKILL.md` lines Tasks 9 and 13 replace — grep of `tests/` 2026-09-15.
- `tests/criteria.test.sh` loops only over `criteria/*.md`, so a new JSON file needs its own checks — read 2026-09-15, `tests/criteria.test.sh:25`.
- The SDD complete-line marker `, K=3` is parsed by no script: grep of `plugins/dr-superpowers` on 2026-09-15 found it only in `skills/subagent-driven-development/SKILL.md:279,696`.
- Replay copies keep only fixture `**Plan review:**` lines: `git show <sha>:<plan> | grep -c '^\*\*Plan review:\*\*'` on 2026-09-15 printed 0 for `d6c288c` (project-state), 1 for `01f5a2a` and `69c6b48`, and 3 for `5e96f14`; after the Task 10 `awk` filter the counts were 0, 0, 0 and 2.
- Calibration inputs exist: `git cat-file -e` on 2026-09-15 succeeded for `d6c288c`, `01f5a2a`, `69c6b48`, `5e96f14` with their plan and spec paths (Task 10 table). `git show e3506c4` shows round 3's fixes to `d6c288c`: the Task 3 `absent` helper contract and the needles `"CLAUDE.md"`, `"optional"`, `'seven'`, `'exit 0'`.
- Plans are uncommitted until the handoff (`skills/writing-plans/SKILL.md`, Execution Handoff), so a plan-review delta needs a snapshot, not git.
- A background Bash call is not bound by the tool's 10-minute `timeout` — measured and recorded in `reference/external-executor.md` §Dispatch.
- `.superpowers/` is git-ignored (`.gitignore:15`), so the smoke worktree and its report can live under it.
- `run-codex-task.sh` takes a JSON array of unique non-empty paths as `--write-set` (`scripts/lib/task-state.sh:48`), requires a clean index and worktree with no untracked files on an initial run (`scripts/lib/task-state.sh:130`), accepts a report path outside `--cwd` and rejects one inside it unless it is under an ignored `.superpowers/` (`scripts/run-codex-task.sh:150-154`), and composes the commit subject from the report's `commit_subject` field (`scripts/run-codex-task.sh:369,380`) — read 2026-09-15.
- Three details were settled during planning and recorded in the spec (§3, §8) in the same commit as this plan: `review-route` prints `reason=round` for plan rounds (spec §3 lists only the task reasons); writing-plans sends a `review-route` exit 2 on a Codex-host plan to the native judge rather than `judge-fable`, because a Codex host has no Claude judge (spec §2 keeps native hosts untouched); and the `plan-lint` probe skips inline plans, where Executor lines are inert (`skills/writing-plans/SKILL.md:245`).
- The distilled entry format — an H1, a one-line statement, `## <area>` sections of `### <entry>` blocks, and for `constraints.md` the fields `Set by`, `Scope`, `Source` — is fixed by `skills/distilling-docs/SKILL.md:17-21` (read 2026-09-15); Task 16's entry follows it.
- The spec is committed (`155fc23`, amended in `0b66016` and `18a00a7`, 2026-09-15), so Task 16's `git log -1 --format=%h -- <spec>` yields a sha.
- This plan carries no `**Executor:**` lines: its Execution line is inline, under which they are inert (`skills/writing-plans/SKILL.md`, Assign an implementer).
- Unverified — Task 10 verifies it when the gate reports usable, and records `PENDING` otherwise: that `codex exec --output-schema criteria/codex-plan-review-schema.json` is accepted, that an Astra plan review finishes inside the runner's 1800-second bound, and that `node <plugin-root>/scripts/codex-companion.mjs setup --json` carries the Codex version in `.codex.detail` (spec §15.6).
- Unverified — Task 15 verifies it when the gate reports usable, and records `PENDING` otherwise: that `run-codex-task.sh`, last exercised on CLI 0.153.4, completes a run on CLI 0.154.0.

## Task index

1. The Codex plan-review schema
2. The review runner's task and plan kinds
3. Judge agents for the tier seats
4. The review-route script
5. Plan review rounds in writing-plans
6. The Codex plugin locator
7. The session gate
8. Codex-off routing and the runner gate
9. The gate in writing-plans
10. Calibration gate
11. Task review routing in subagent-driven-development
12. Retire risk3-spread
13. The external-executor lane prose
14. The lazy lane probe in plan-lint
15. Smoke-test gate
16. The lane declared on for this repository
17. README, version, and the program amendment

---

### Task 1: The Codex plan-review schema

**Files:**
- Create: `plugins/dr-superpowers/criteria/codex-plan-review-schema.json`
- Modify: `plugins/dr-superpowers/tests/criteria.test.sh` (insert before the final `printf`)

**Interfaces:**
- Consumes: nothing.
- Produces: the schema file named in Contracts, passed by Task 2's `--kind plan`.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/criteria.test.sh`, insert this block immediately before the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"`. It relies on `$PR`, defined by the plan-review block just above it:

```bash
# The Codex plan-review seat returns plan-review.md's criteria through a JSON
# schema. Its integer fields must be exactly that file's ids, or round 1 scores
# a different rubric from the judges that run rounds 2 and 3.
PSCHEMA="$CRITERIA/codex-plan-review-schema.json"
check "codex-plan-review-schema.json exists" "$([ -f "$PSCHEMA" ] && echo yes || echo no)" "yes"
if [ -f "$PSCHEMA" ] && [ -f "$PR" ]; then
  want=$(grep -o '{#[a-z0-9_]\{1,\}}' "$PR" | tr -d '{#}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
  got=$(jq -r '.properties | to_entries[] | select(.value.type=="integer") | .key' "$PSCHEMA" \
    | tr -d '\r' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
  check "codex plan-review schema scores exactly the plan-review ids" "$got" "$want"
  check "codex plan-review schema requires every property" \
    "$(jq -r '((.properties|keys)-(.required))|join(",")' "$PSCHEMA" | tr -d '\r')" ""
  check "codex plan-review schema is strict at the top" \
    "$(jq -r '.additionalProperties == false' "$PSCHEMA" | tr -d '\r')" "true"
  check "codex plan-review findings items are strict" \
    "$(jq -r '.properties.findings.items | (.additionalProperties == false) and ((((.properties|keys)-(.required))|length) == 0)' "$PSCHEMA" | tr -d '\r')" "true"
  check "codex plan-review findings carry severity, summary and where" \
    "$(jq -r '.properties.findings.items.properties | keys | join(",")' "$PSCHEMA" | tr -d '\r')" "severity,summary,where"
  check "codex plan-review scores range 1 to 20" \
    "$(jq -r '[.properties[] | select(.type=="integer") | (.enum | length == 20 and min == 1 and max == 20)] | all' "$PSCHEMA" | tr -d '\r')" "true"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/criteria.test.sh`
Expected: FAIL — `FAIL - codex-plan-review-schema.json exists`, and the summary line ends `1 failed`.

- [ ] **Step 3: Write the schema**

Create `plugins/dr-superpowers/criteria/codex-plan-review-schema.json`:

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["executability", "coherence", "coverage", "assumptions", "findings"],
  "properties": {
    "executability": { "type": "integer", "enum": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20], "description": "Executability score, 1 clear failure to 20 clearly met." },
    "coherence": { "type": "integer", "enum": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20], "description": "Coherence score, 1 clear failure to 20 clearly met." },
    "coverage": { "type": "integer", "enum": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20], "description": "Coverage score, 1 clear failure to 20 clearly met." },
    "assumptions": { "type": "integer", "enum": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20], "description": "Assumptions score, 1 clear failure to 20 clearly met." },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["severity", "where", "summary"],
        "properties": {
          "severity": { "type": "string", "enum": ["Critical", "Important", "Minor"] },
          "where": { "type": "string", "description": "Task N, Task N part X, or header." },
          "summary": { "type": "string", "description": "The issue, why it matters for execution, and the fix." }
        }
      }
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/criteria.test.sh`
Expected: the summary line ends `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/criteria/codex-plan-review-schema.json plugins/dr-superpowers/tests/criteria.test.sh
git commit -m "feat(superpowers): add codex plan-review schema"
```

### Task 2: The review runner's task and plan kinds

**Files:**
- Modify: `plugins/dr-superpowers/scripts/run-codex-review.sh` (replace the whole file)
- Modify: `plugins/dr-superpowers/tests/codex-review.test.sh` (one stub case, one inserted block)

**Interfaces:**
- Consumes: Task 1's schema path (Contracts).
- Produces: the `run-codex-review.sh` interface in Contracts.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/codex-review.test.sh`, inside the stub codex heredoc, insert this line immediately after the line `  ok-final) printf 'a review\n' > "\$outfile"; exit 0 ;;`:

```bash
  ok-plan) printf '{"executability":17,"coherence":16,"coverage":17,"assumptions":16,"findings":[]}' > "\$outfile"; exit 0 ;;
```

Then insert this block immediately before the line `# The caller must defer to the runner's outcome rather than running its own`:

```bash
# --- task and plan kinds, and the light tier ---------------------------------
write_roster "$ASTRA"
out=$(run --kind task --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
present "task passes the task-review schema" "$out" "codex-review-schema.json"
present "task defaults to the heavy tier" "$out" "codex-judge gpt-6-astra/high"
if tok x "$out" review; then printf 'FAIL - task never uses codex exec review\n'; fail=$((fail + 1))
else printf 'ok   - task never uses codex exec review\n'; pass=$((pass + 1)); fi

out=$(run --kind task --tier light --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
present "the light tier selects the last judge row" "$out" "codex-judge gpt-5.6-sol/high"
if tok x "$out" gpt-5.6-sol; then printf 'ok   - the light tier reaches -m\n'; pass=$((pass + 1))
else printf 'FAIL - the light tier reaches -m\n'; fail=$((fail + 1)); fi
present "the light tier still reports the catalog date" "$out" "evidence=2026-09-14T13:35:00Z"

out=$(run --kind risk3 --tier light --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
present "risk3 accepts the light tier" "$out" "codex-judge gpt-5.6-sol/high"

out=$(run --kind plan --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
present "plan passes the plan-review schema" "$out" "codex-plan-review-schema.json"
present "plan is read-only" "$out" "read-only"
present "plan takes the heavy selection" "$out" "codex-judge gpt-6-astra/high"
if tok x "$out" review; then printf 'FAIL - plan never uses codex exec review\n'; fail=$((fail + 1))
else printf 'ok   - plan never uses codex exec review\n'; pass=$((pass + 1)); fi

run --kind task --cwd "$TMP/work" --out "$TMP/o.json" --dry-run >/dev/null; rc=$?
check "task without --prompt is a usage error" "$rc" "2"
run --kind plan --cwd "$TMP/work" --out "$TMP/o.json" --dry-run >/dev/null; rc=$?
check "plan without --prompt is a usage error" "$rc" "2"
run --kind plan --tier light --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run >/dev/null; rc=$?
check "--tier with plan is a usage error" "$rc" "2"
run --kind final --tier light --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run >/dev/null; rc=$?
check "--tier with final is a usage error" "$rc" "2"
run --kind task --tier medium --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run >/dev/null; rc=$?
check "an unknown tier is a usage error" "$rc" "2"

out=$(seat ok-plan plan --out "$TMP/o.json" --prompt "$TMP/p.txt"); rc=$?
present "a schema-shaped plan report is OK" "$out" "status=OK"
check "a plan OK exits 0" "$rc" "0"
out=$(seat ok plan --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "a task-shaped report is not a plan review" "$out" "status=FAILED"
out=$(seat ok task --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "a schema-shaped task report is OK" "$out" "status=OK"
out=$(seat refuse-always task --tier light --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "a refused light run is FAILED" "$out" "status=FAILED"
check "the light tier never falls back" "$(cat "$TMP/calls")" "1"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash plugins/dr-superpowers/tests/codex-review.test.sh`
Expected: FAIL lines including `FAIL - task passes the task-review schema` and `FAIL - plan passes the plan-review schema`; the summary does not end `0 failed`.

- [ ] **Step 3: Write the implementation**

Replace the whole of `plugins/dr-superpowers/scripts/run-codex-review.sh` with:

```bash
#!/usr/bin/env bash
# Runs one Codex review seat: selects the judge rung, bounds the run, and
# classifies the outcome.
#
# Every Claude-hosted Codex review seat calls this instead of composing a codex
# command itself. An earlier design left the selection and fallback rules in
# prose, and the runtime never reached the paragraph describing them: the
# fallback was unreachable code written in English. Anything a seat must decide
# lives here, where a test can reach it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER="$HERE/../reference/ladder.md"
TASK_SCHEMA="$HERE/../criteria/codex-review-schema.json"
PLAN_SCHEMA="$HERE/../criteria/codex-plan-review-schema.json"
# Tests point this at a stub roster. Unset in production, where the real
# detector runs and its auth probe is the usability guard.
ROSTER="${CODEX_REVIEW_ROSTER:-$HERE/detect-executors.sh}"

die() { printf 'run-codex-review: %s\n' "$1" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || die "jq is required but not on PATH"
command -v timeout >/dev/null 2>&1 || die "GNU timeout is required but not on PATH"

kind=""; cwd=""; out=""; prompt=""; base=""; tier=""; dry_run=false
while [ $# -gt 0 ]; do
  case "$1" in
    --kind|--cwd|--out|--prompt|--base|--tier) [ $# -ge 2 ] || die "$1 needs a value" ;;
  esac
  case "$1" in
    --kind) kind="$2"; shift 2 ;;
    --cwd) cwd="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --prompt) prompt="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    --tier) tier="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

# task is the name scripts/review-route prints; risk3 is the same seat under
# its sub-project 7 name, kept so earlier callers keep working.
case "$kind" in
  task|risk3) [ -n "$prompt" ] || die "--kind $kind requires --prompt"; kind=task ;;
  plan) [ -n "$prompt" ] || die "--kind plan requires --prompt" ;;
  final) [ -n "$base" ] || die "--kind final requires --base" ;;
  *) die "--kind must be task, risk3, plan or final" ;;
esac
case "$tier" in
  "") tier=heavy ;;
  light|heavy) [ "$kind" = task ] || die "--tier applies only to --kind task or risk3" ;;
  *) die "--tier must be light or heavy" ;;
esac
[ -n "$cwd" ] || die "--cwd is required"
[ -n "$out" ] || die "--out is required"
[ -d "$cwd" ] || die "--cwd is not a directory: $cwd"
[ -d "$(dirname "$out")" ] || die "--out directory not found: $(dirname "$out")"

case "$kind" in
  task) schema="$TASK_SCHEMA" ;;
  plan) schema="$PLAN_SCHEMA" ;;
  *) schema="" ;;
esac

# Resolve before anything runs. The seat runs inside a subshell that cd's to
# --cwd, while the output is read back from here, so a relative path would be
# written into the worktree and then reported missing.
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
cwd="$(cd "$cwd" && pwd)"
[ -z "$schema" ] || [ -r "$prompt" ] || die "--prompt is not readable: $prompt"
[ -z "$schema" ] || [ -r "$schema" ] || die "review schema not found: $schema"
[ -z "$prompt" ] || prompt="$(cd "$(dirname "$prompt")" && pwd)/$(basename "$prompt")"

# The judge policy, first row preferred and last row the fallback.
judge=$(awk '
  $0 == "```codex-judge" { f = 1; next }
  f && $0 == "```" { exit }
  f && NF { print }
' "$LADDER")
[ -n "$judge" ] || die "the codex-judge block is missing from $LADDER"

pref_model=$(printf '%s\n' "$judge" | sed -n 1p | awk '{print $1}')
pref_effort=$(printf '%s\n' "$judge" | sed -n 1p | awk '{print $2}')
back_model=$(printf '%s\n' "$judge" | tail -1 | awk '{print $1}')
back_effort=$(printf '%s\n' "$judge" | tail -1 | awk '{print $2}')
secs_of() { printf '%s\n' "$judge" | awk -v m="$1" -v e="$2" '$1 == m && $2 == e {print $3; exit}'; }

# Selection. The catalog is a negative filter: a pair it does not advertise is
# never attempted, and every state that is not a positive match - no catalog, an
# unreadable one, one that lists nothing, one that lists other models - takes the
# fallback row. That is the owner's fail-closed rule, and null is deliberately
# not treated as [].
# Invoked through bash, not executed directly: core.filemode is false on some
# checkouts, so the detector can arrive at mode 100644 and a direct call would
# fail every seat with "no codex row".
roster=$(bash "$ROSTER" 2>/dev/null) || roster=""
codex_row=$(printf '%s' "$roster" | jq -c '.[]? | select(.id=="codex")' 2>/dev/null)
[ -n "$codex_row" ] || die "no codex row in the executor roster"

usable=$(printf '%s' "$codex_row" | jq -r '.usable')
if [ "$usable" != true ]; then
  reason=$(printf '%s' "$codex_row" | jq -r '.reason // "codex is not usable"')
  printf 'codex-judge none/none status=FAILED exit=0 out=%s evidence=unknown\n' "$out"
  printf 'run-codex-review: %s\n' "$reason" >&2
  exit 1
fi

advertised=$(printf '%s' "$codex_row" | jq -c '.advertised')
if [ "$advertised" = null ]; then
  evidence=unknown
  listed=false
else
  evidence=$(printf '%s' "$advertised" | jq -r '.fetched_at // "unknown"')
  listed=$(printf '%s' "$advertised" | jq --arg m "$pref_model" --arg e "$pref_effort" \
    '[.pairs[]? | select(.model == $m and .effort == $e)] | length > 0')
fi

# The light tier is the last row by definition: it is the known-good rung, so
# the catalog has nothing to veto, and it is already the fallback row, so the
# refusal branch below never retries it against itself.
if [ "$tier" = light ]; then
  model="$back_model"; effort="$back_effort"
elif [ "$listed" = true ]; then
  model="$pref_model"; effort="$pref_effort"
else
  model="$back_model"; effort="$back_effort"
fi
secs=$(secs_of "$model" "$effort")
[ -n "$secs" ] || die "no timeout for $model/$effort in the codex-judge block"

# The command each kind runs. task and plan use plain `codex exec` with this
# plugin's own schema, never `codex exec review`, which imposes its own report
# shape - a seat must return the criteria the Claude judges return.
build_argv() { # build_argv <model> <effort>
  if [ -n "$schema" ]; then
    printf '%s\n' codex exec -s read-only -m "$1" -c "model_reasoning_effort=$2" \
      --output-schema "$schema" -o "$out" -C "$cwd"
  else
    printf '%s\n' codex exec review --base "$base" -m "$1" -c "model_reasoning_effort=$2" \
      -o "$out"
  fi
}

if [ "$dry_run" = true ]; then
  printf 'would-run:\n'
  build_argv "$model" "$effort"
  printf 'codex-judge %s/%s status=OK exit=0 out=%s evidence=%s\n' \
    "$model" "$effort" "$out" "$evidence"
  exit 0
fi

# Valid output is defined per kind. task and plan must parse as their schema's
# keys; final has no schema and only has to be non-empty.
valid_output() {
  case "$kind" in
    task) jq -e 'has("spec_verdict") and has("task_quality") and has("cannot_verify")' \
      "$out" >/dev/null 2>&1 ;;
    plan) jq -e 'has("executability") and has("coherence") and has("coverage") and has("assumptions") and has("findings")' \
      "$out" >/dev/null 2>&1 ;;
    *) [ -s "$out" ] ;;
  esac
}

# A refusal is the one failure a different model repairs. An expired token, an
# exhausted quota, a bad working directory and a cancelled run are not refusals:
# the fallback would fail identically and would cost a second full round.
#
# Only error-shaped lines are searched, and only at column 0. Codex writes its
# whole session transcript - every file the model read, and the review text
# itself - to stderr, and the report to stdout: a 2026-09-14 `--kind final` run
# on this repository left 10,590 stderr lines carrying 20 matches for an
# unanchored search, because this plugin's own tests and prose quote refusal
# messages. Matching those would declare a refusal on a clean run and buy a
# second full round. Both streams are still read: an API-level refusal arrives
# as a JSON event, which can reach either.
REFUSAL='(unsupported|unknown|invalid|not (supported|available|found)).*(model|effort)|(model|effort).*(unsupported|unknown|invalid|not (supported|available|found))'

error_lines() { # error_lines <log-prefix>
  grep -hE '^ERROR:|^\{"type": ?"error"' "$1.stdout" "$1.stderr" 2>/dev/null
}

is_refusal() { # is_refusal <log-prefix>
  error_lines "$1" | grep -qiE "$REFUSAL"
}

# The same line the match came from, not merely the first line of stderr - that
# is the CLI banner, which would make every substitution read as "refused
# (OpenAI Codex v0.154.0)".
refusal_line() { # refusal_line <log-prefix>
  error_lines "$1" | grep -m1 . | tr -d '\r'
}

# Each attempt writes its own pair of logs. Sharing one would let the fallback's
# (usually empty) output overwrite the refusal that explains why the fallback
# ran at all, which is the line the ledger substitution quotes.
run_seat() { # run_seat <model> <effort> <seconds> <log-prefix>; echoes the exit code
  local argv=() line
  while IFS= read -r line; do argv+=("$line"); done < <(build_argv "$1" "$2")
  rm -f "$out"
  ( cd "$cwd" && timeout "$3" "${argv[@]}" >"$4.stdout" 2>"$4.stderr" \
      < "${prompt:-/dev/null}" )
  printf '%s' "$?"
}

status() { # status <model> <effort> <state> <exit>
  printf 'codex-judge %s/%s status=%s exit=%s out=%s evidence=%s\n' \
    "$1" "$2" "$3" "$4" "$out" "$evidence"
}

rc=$(run_seat "$model" "$effort" "$secs" "$out")

# Deadline expiry is tracked apart from every other non-zero exit: a hang and a
# refusal both exit non-zero, and only one of them is worth a second run.
if [ "$rc" -eq 124 ]; then
  status "$model" "$effort" TIMEOUT "$rc"; exit 1
fi

if [ "$rc" -eq 0 ] && valid_output; then
  status "$model" "$effort" OK "$rc"; exit 0
fi

# The fallback is attempted at most once, and never when the row that just ran
# is already the fallback row.
if is_refusal "$out" \
   && { [ "$model" != "$back_model" ] || [ "$effort" != "$back_effort" ]; }; then
  printf 'run-codex-review: %s/%s refused (%s); falling back to %s/%s\n' \
    "$model" "$effort" "$(refusal_line "$out")" "$back_model" "$back_effort" >&2
  back_secs=$(secs_of "$back_model" "$back_effort")
  rc=$(run_seat "$back_model" "$back_effort" "$back_secs" "$out.fallback")
  if [ "$rc" -eq 124 ]; then
    status "$back_model" "$back_effort" TIMEOUT "$rc"; exit 1
  fi
  if [ "$rc" -eq 0 ] && valid_output; then
    status "$back_model" "$back_effort" FALLBACK "$rc"; exit 0
  fi
  status "$back_model" "$back_effort" FAILED "$rc"; exit 1
fi

status "$model" "$effort" FAILED "$rc"; exit 1
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash plugins/dr-superpowers/tests/codex-review.test.sh`
Expected: the summary line ends `0 failed`. Every pre-existing case — including `risk3 without --prompt is a usage error` and `risk3 passes the review schema` — still passes.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/run-codex-review.sh plugins/dr-superpowers/tests/codex-review.test.sh
git commit -m "feat(superpowers): add task and plan review kinds"
```

### Task 3: Judge agents for the tier seats

**Files:**
- Create: `plugins/dr-superpowers/agents/judge-sonnet-high.md`
- Modify: `plugins/dr-superpowers/agents/judge-opus.md:3` (description line)
- Modify: `plugins/dr-superpowers/tests/fleet.test.sh:2-10,36,42`

**Interfaces:**
- Consumes: nothing.
- Produces: the agent `dr-superpowers:judge-sonnet-high` (Contracts), named by Task 4's script.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/fleet.test.sh`, replace the comment block from the line `# The fleet is nineteen agents in three classes. Seven execution implementers` through the line `# subagents" are enforced rather than requested.` (nine lines) with:

```bash
# The fleet is twenty agents in three classes. Seven execution implementers
# pin one model/effort pairing each and are everything the assignment table and
# the escalation ladder can reach. Nine reserve implementers - the xhigh and max
# efforts, and every Fable tier - are never an output of scoring: they are
# reachable only by a human override, or by the reserve chain after a split has
# already been spent. Four role agents - three judges and one scout - are
# read-only by registry: their tools list omits Edit, Write, NotebookEdit, and
# Agent, so "reviewers do not mutate the tree" and "reviewers do not spawn
# subagents" are enforced rather than requested.
```

Replace the line that begins `EXPECTED=` with:

```bash
EXPECTED="impl-fable-high impl-fable-low impl-fable-max impl-fable-medium impl-fable-xhigh impl-haiku impl-opus-high impl-opus-low impl-opus-max impl-opus-medium impl-opus-xhigh impl-sonnet-high impl-sonnet-low impl-sonnet-max impl-sonnet-medium impl-sonnet-xhigh judge-fable judge-opus judge-sonnet-high scout-sonnet"
```

Replace the line `check "fleet contains exactly the 19 expected agents" "$actual" "$EXPECTED"` with:

```bash
check "fleet contains exactly the 20 expected agents" "$actual" "$EXPECTED"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/fleet.test.sh`
Expected: `FAIL - fleet contains exactly the 20 expected agents`.

- [ ] **Step 3: Write the agents**

Create `plugins/dr-superpowers/agents/judge-sonnet-high.md`:

```markdown
---
name: judge-sonnet-high
description: "Read-only task reviewer running Sonnet 5 at high effort. Dispatched by dr-superpowers as the task reviewer for totals 0 and 1 when Codex is not the reviewer."
model: sonnet
effort: high
tools: Read, Grep, Glob, WebFetch
color: yellow
---

You are a judge. Your dispatch prompt carries every input you need: the
paths to read, the criteria to apply, and the exact output format. It is
your complete instruction set; follow it exactly.

You run on Sonnet 5 at high effort.

You cannot modify files and you cannot dispatch subagents. Both are
deliberate. Your verdict is the whole of your output.

Score against the criteria you were given and nothing else. When a
criterion tells you to ignore something, ignoring it is part of scoring
correctly. If an input you were told to read is missing or unreadable,
say so plainly and score what you can; never infer the contents of a
file you could not open.
```

In `plugins/dr-superpowers/agents/judge-opus.md`, replace the `description:` line with:

```yaml
description: "Read-only verifier, ruling seat and approach ranker running Opus 5 at high effort. Dispatched by dr-superpowers as the task reviewer for totals 2 to 4 when Codex is not the reviewer, for plan-review rounds 2 and 3, and in place of judge-fable when Fable is unavailable or declined."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/fleet.test.sh`
Expected: the summary line ends `0 failed`, including `ok   - judge-sonnet-high: carries the read-only toolset` and `ok   - judge-sonnet-high: content is ASCII only`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/agents/judge-sonnet-high.md plugins/dr-superpowers/agents/judge-opus.md plugins/dr-superpowers/tests/fleet.test.sh
git commit -m "feat(superpowers): add the sonnet judge tier"
```

### Task 4: The review-route script

**Files:**
- Create: `plugins/dr-superpowers/scripts/review-route`
- Create: `plugins/dr-superpowers/tests/review-route.test.sh`

**Interfaces:**
- Consumes: Task 3's agent name; `scripts/lib/plan.sh` (`plan_apply_amendments`, `plan_amendments_file`, `plan_header`, `plan_task_text`).
- Produces: the `review-route` interface and the test-suite helpers in Contracts.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/review-route.test.sh`:

```bash
#!/usr/bin/env bash
# review-route is the review routing table as code. Each fixture task below
# pins one row, so a controller of any size reaches the same seat. The prose
# checks appended later pin the skill text that tells a controller to call it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
ROUTE="$P/scripts/review-route"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2" 2>/dev/null; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s] in %s\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <file> <needle>
  if grep -qF -- "$3" "$2" 2>/dev/null; then printf 'FAIL - %s\n       unexpected: [%s] in %s\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fixture lines carry a leading | so a plan that quotes this suite still lints:
# plan-lint's part and Evaluation scans do not skip fenced blocks.
sed 's/^|//' > "$TMP/plan.md" <<'EOF'
|# Routing Fixture Plan
|
|**Goal:** Fixture.
|
|## Task index
|
|1. light low
|2. light mid
|3. heavy
|4. risky
|5. executor
|6. executor risky
|7. split
|8. risk three
|9. broken
|10. band five
|
|### Task 1: light low
|
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: light mid
|
|**Implementer:** dr-superpowers:impl-sonnet-high
|**Evaluation:** files 1 — spec 0 — coupling 1 — risk 1 = 3
|
|### Task 3: heavy
|
|**Implementer:** dr-superpowers:impl-opus-low
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4
|
|### Task 4: risky
|
|**Implementer:** dr-superpowers:impl-opus-low
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4
|
|### Task 5: executor
|
|**Implementer:** dr-superpowers:impl-sonnet-high
|**Executor:** codex gpt-5.5 / high
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3
|
|### Task 6: executor risky
|
|**Implementer:** dr-superpowers:impl-sonnet-high
|**Executor:** codex gpt-5.5 / high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 2 = 3
|
|### Task 7: split
|
|#### Part A: small half
|
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|#### Part B: risky half
|
|**Implementer:** dr-superpowers:impl-opus-medium
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5
|
|### Task 8: risk three
|
|**Implementer:** dr-superpowers:impl-opus-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
|
|### Task 9: broken
|
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** one plus one
|
|### Task 10: band five
|
|**Implementer:** dr-superpowers:impl-opus-medium
|**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5
EOF

route() { # route <args...>; sets out and rc
  out=$(bash "$ROUTE" "$TMP/plan.md" "$@" 2>"$TMP/err"); rc=$?
}

check "script exists" "$([ -f "$ROUTE" ] && echo yes || echo no)" "yes"

route --task 1
check "total 1: light Codex, Sonnet fallback" "$out" "review-seat task=1 primary=codex:light fallback=dr-superpowers:judge-sonnet-high reason=band"
check "a routed task exits 0" "$rc" "0"
route --task 2
check "total 3 with em dashes: light Codex, Opus fallback" "$out" "review-seat task=2 primary=codex:light fallback=dr-superpowers:judge-opus reason=band"
route --task 3
check "total 4 at risk 1: heavy Codex, Opus fallback" "$out" "review-seat task=3 primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"
route --task 4
check "risk 2: Astra then Fable" "$out" "review-seat task=4 primary=codex:heavy+judge-fable fallback=dr-superpowers:judge-fable reason=risk"
route --task 5
check "an Executor task is reviewed by its band judge, never Codex" "$out" "review-seat task=5 primary=dr-superpowers:judge-opus fallback=- reason=executor"
route --task 6
check "an Executor task at risk 2 goes to Fable alone" "$out" "review-seat task=6 primary=dr-superpowers:judge-fable fallback=- reason=executor"
route --task 7A
check "a part routes on its own Evaluation" "$out" "review-seat task=7A primary=codex:light fallback=dr-superpowers:judge-sonnet-high reason=band"
route --task 7B
check "the risky part routes to Astra then Fable" "$out" "review-seat task=7B primary=codex:heavy+judge-fable fallback=dr-superpowers:judge-fable reason=risk"
route --task 7
check "a split task without a part routes on its heaviest part" "$out" "review-seat task=7 primary=codex:heavy+judge-fable fallback=dr-superpowers:judge-fable reason=risk"
route --task 8
check "risk 3 routes like risk 2" "$out" "review-seat task=8 primary=codex:heavy+judge-fable fallback=dr-superpowers:judge-fable reason=risk"
route --task 10
check "total 5 at risk 0: heavy Codex, Fable fallback" "$out" "review-seat task=10 primary=codex:heavy fallback=dr-superpowers:judge-fable reason=band"

route --task 1 2
check "a batch takes its highest total" "$out" "review-seat task=1,2 primary=codex:light fallback=dr-superpowers:judge-opus reason=band"
route --task 1 3
check "a batch crossing into the heavy band" "$out" "review-seat task=1,3 primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"
route --task 1 5
check "one Executor task makes the whole batch Claude-reviewed" "$out" "review-seat task=1,5 primary=dr-superpowers:judge-opus fallback=- reason=executor"

route --plan-round 1
check "plan round 1 is Codex with a Fable fallback" "$out" "review-seat plan-round=1 primary=codex:plan fallback=dr-superpowers:judge-fable reason=round"
route --plan-round 2
check "plan round 2 is Opus" "$out" "review-seat plan-round=2 primary=dr-superpowers:judge-opus fallback=- reason=round"
route --plan-round 3
check "plan round 3 is Opus" "$out" "review-seat plan-round=3 primary=dr-superpowers:judge-opus fallback=- reason=round"

route --task 9
check "an unparseable Evaluation exits 2" "$rc" "2"
check "an unparseable Evaluation prints nothing on stdout" "$out" ""
route --task 99
check "an unknown task exits 2" "$rc" "2"
route --task 7C
check "an unknown part exits 2" "$rc" "2"
route --task x
check "a malformed id exits 2" "$rc" "2"
route --task
check "--task with no id exits 2" "$rc" "2"
route --plan-round 0
check "plan round 0 exits 2" "$rc" "2"
route --bogus 1
check "an unknown flag exits 2" "$rc" "2"
out=$(bash "$ROUTE" "$TMP/nope.md" --task 1 2>/dev/null); rc=$?
check "a missing plan exits 2" "$rc" "2"

{ printf 'Host: codex\n'; cat "$TMP/plan.md"; } > "$TMP/codex.md"
out=$(bash "$ROUTE" "$TMP/codex.md" --task 1 2>"$TMP/err"); rc=$?
check "a Codex-host plan exits 2" "$rc" "2"
present "a Codex-host plan names native-codex.md" "$TMP/err" "native-codex.md"

sed 's/$/\r/' "$TMP/plan.md" > "$TMP/crlf.md"
out=$(bash "$ROUTE" "$TMP/crlf.md" --task 4 2>/dev/null)
check "a CRLF plan routes" "$out" "review-seat task=4 primary=codex:heavy+judge-fable fallback=dr-superpowers:judge-fable reason=risk"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: `FAIL - script exists`; the summary does not end `0 failed`.

- [ ] **Step 3: Write the script**

Create `plugins/dr-superpowers/scripts/review-route`:

```bash
#!/usr/bin/env bash
# Print the review seat for a task, a batch, or a plan-review round, and the
# Claude seat that replaces it when a Codex seat produces nothing.
#
# The routing table lives here rather than in prose for the reason
# run-codex-review.sh gives: a rule a seat must follow is only reachable when a
# test can reach it. This script never probes Codex. run-codex-review.sh checks
# availability on every run, and its status line decides whether the fallback
# is used.
#
# Usage: review-route PLAN_FILE --task ID [ID ...]
#        review-route PLAN_FILE --plan-round R
# ID is a task number, or a task number and part letter for a split task (7B).
# Output: review-seat <scope> primary=<seat> fallback=<seat|-> reason=<why>
# Exit: 0 routed; 2 usage error, missing task, unparseable Evaluation, or a
# Codex-host plan.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/plan.sh"

SONNET=dr-superpowers:judge-sonnet-high
OPUS=dr-superpowers:judge-opus
FABLE=dr-superpowers:judge-fable
SEP='( — | – | - | -- )'

die() { printf 'review-route: %s\n' "$1" >&2; exit 2; }
usage() { die "usage: review-route PLAN_FILE --task ID [ID ...] | --plan-round R"; }

[ $# -ge 3 ] || usage
plan=$1; shift
[ -f "$plan" ] || die "no such plan file: $plan"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
src="$TMP/plan.md"
plan_apply_amendments "$plan" "$(plan_amendments_file "$plan")" > "$src" 2>/dev/null \
  || die "an amendment does not apply; run plan-lint"

if plan_header "$src" | grep -qE '^(\*\*)?Host:(\*\*)?[ \t]+codex[ \t]*$'; then
  die "a Host: codex plan routes reviews through reference/native-codex.md"
fi

case "$1" in
  --plan-round)
    [ $# -eq 2 ] && [[ "$2" =~ ^[1-9][0-9]*$ ]] || usage
    if [ "$2" -eq 1 ]; then
      printf 'review-seat plan-round=1 primary=codex:plan fallback=%s reason=round\n' "$FABLE"
    else
      printf 'review-seat plan-round=%s primary=%s fallback=- reason=round\n' "$2" "$OPUS"
    fi
    exit 0 ;;
  --task) shift ;;
  *) usage ;;
esac

max_total=-1 max_risk=-1 executor=0
for id in "$@"; do
  [[ "$id" =~ ^([0-9]+)([A-Z]?)$ ]] || die "not a task id: $id"
  n=${BASH_REMATCH[1]} part=${BASH_REMATCH[2]}
  text=$(plan_task_text "$src" "$n") || die "no Task $n in the plan"
  if [ -n "$part" ]; then
    text=$(awk -v p="$part" '/^#### Part [A-Z]:/ { on = (substr($3, 1, 1) == p) } on' <<<"$text")
    [ -n "$text" ] || die "no part $part in Task $n"
  fi
  grep -qE '^\*\*Executor:\*\*' <<<"$text" && executor=1
  evs=$(grep -E '^\*\*Evaluation:\*\*' <<<"$text" || true)
  [ -n "$evs" ] || die "Task $id has no **Evaluation:** line"
  # A task without a part letter carries every part's Evaluation line, so it
  # routes on its heaviest part.
  while IFS= read -r ev; do
    [[ "$ev" =~ ^\*\*Evaluation:\*\*\ files\ [0-9]+$SEP"spec "[0-9]+$SEP"coupling "[0-9]+$SEP"risk "([0-9]+)\ =\ ([0-9]+) ]] \
      || die "Task $id: the Evaluation line does not parse: $ev"
    [ "${BASH_REMATCH[4]}" -le "$max_risk" ] || max_risk=${BASH_REMATCH[4]}
    [ "${BASH_REMATCH[5]}" -le "$max_total" ] || max_total=${BASH_REMATCH[5]}
  done <<<"$evs"
done

band() { # band <total> - the Claude judge for a score band
  if [ "$1" -le 1 ]; then echo "$SONNET"
  elif [ "$1" -le 4 ]; then echo "$OPUS"
  else echo "$FABLE"
  fi
}

# Executor first: a task Codex implemented is never reviewed by Codex, whatever
# its risk. Totals 5 and 6 carry risk >= 2 under Rule S, so the risk row catches
# them before the band rows; the band rows still cover an overridden task.
if [ "$executor" -eq 1 ] && [ "$max_risk" -ge 2 ]; then
  primary=$FABLE fallback=- reason=executor
elif [ "$executor" -eq 1 ]; then
  primary=$(band "$max_total") fallback=- reason=executor
elif [ "$max_risk" -ge 2 ]; then
  primary=codex:heavy+judge-fable fallback=$FABLE reason=risk
elif [ "$max_total" -le 3 ]; then
  primary=codex:light fallback=$(band "$max_total") reason=band
else
  primary=codex:heavy fallback=$(band "$max_total") reason=band
fi

printf 'review-seat task=%s primary=%s fallback=%s reason=%s\n' \
  "$(IFS=,; echo "$*")" "$primary" "$fallback" "$reason"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: the summary line ends `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/review-route plugins/dr-superpowers/tests/review-route.test.sh
git update-index --chmod=+x plugins/dr-superpowers/scripts/review-route plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "feat(superpowers): add the review-route script"
```

### Task 5: Plan review rounds in writing-plans

**Files:**
- Modify: `plugins/dr-superpowers/skills/writing-plans/SKILL.md` (§Lint and Review, steps 2-4)
- Modify: `plugins/dr-superpowers/skills/writing-plans/references/plan-reviewer-prompt.md` (the `[JUDGE]` placeholder; append two sections)
- Modify: `plugins/dr-superpowers/tests/review-route.test.sh` (append a block)

**Interfaces:**
- Consumes: `run-codex-review.sh --kind plan` (Task 2), `review-route --plan-round` (Task 4), the test-suite helpers (Task 4) — all in Contracts.
- Produces: the Round 1 on Codex prompt and the delta template, used by Task 6; the workspace artefact names in Contracts.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/review-route.test.sh`, insert immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
# --- plan review prose ---------------------------------------------------------
WP="$P/skills/writing-plans/SKILL.md"
PRP="$P/skills/writing-plans/references/plan-reviewer-prompt.md"
present "writing-plans routes each round" "$WP" 'scripts/review-route PLAN_FILE --plan-round <r>'
present "writing-plans snapshots the plan before each round" "$WP" '<workspace>/plan-round-<r>.md'
present "writing-plans runs the Codex plan kind" "$WP" '--kind plan'
present "writing-plans writes the delta" "$WP" '<workspace>/plan-delta-<r>.diff'
present "writing-plans keeps the round cap" "$WP" 'replaces a fresh full review; rounds are not cut.'
absent "writing-plans no longer dispatches a fresh full review each round" "$WP" 'dispatch a fresh full review'
present "the prompt file has a Codex round-1 section" "$PRP" '## Round 1 on Codex'
present "the Codex round-1 prompt names its schema" "$PRP" 'codex-plan-review-schema.json'
present "the prompt file has a delta template" "$PRP" '## Rounds 2 and 3'
present "the delta template takes the delta file" "$PRP" '[DELTA_FILE]'
present "the delta template verdicts prior findings" "$PRP" '[ADDRESSED|NOT ADDRESSED]'
present "the delta template may read beyond the delta" "$PRP" 'The delta is where to look first, not the limit of'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: `FAIL - writing-plans routes each round` among others; the summary does not end `0 failed`.

- [ ] **Step 3: Rewrite the Lint and Review steps**

In `plugins/dr-superpowers/skills/writing-plans/SKILL.md`, replace everything from the line that begins `2. **Review.** Write the lint output to the plan's workspace:` up to, but not including, the line `## Execution Handoff` with:

````markdown
2. **Review.** Write the lint output to the plan's workspace:
   `scripts/plan-lint PLAN_FILE > <workspace>/plan-lint.txt`, where
   `<workspace>` is the directory `scripts/sdd-workspace PLAN_FILE` prints.
   Before each round `<r>`, copy the plan to `<workspace>/plan-round-<r>.md`,
   run `scripts/review-route PLAN_FILE --plan-round <r>`, and review with the
   seat it prints, using
   [plan-reviewer-prompt.md](references/plan-reviewer-prompt.md). Every seat
   scores executability, coherence, coverage and assumptions (1-20) against
   [plan-review.md](../../criteria/plan-review.md) and lists findings. If
   `review-route` exits 2 naming `native-codex.md`, the plan is a Codex-host
   plan: dispatch the native judge the prompt's `[JUDGE]` placeholder
   describes. On any other exit 2, review with `dr-superpowers:judge-fable`
   and say why, quoting its message.
   - **`primary=codex:plan`** (round 1). Write the prompt its Round 1 on Codex
     section describes to `<workspace>/plan-review-prompt.md`, then run, as a
     background Bash call with no timeout (the rung's bound is longer than the
     Bash tool's ten-minute cap, and a background call is not bound by it):

     ```bash
     bash scripts/run-codex-review.sh --kind plan --cwd <repository-root> \
       --out <workspace>/plan-review-round-1.json --prompt <workspace>/plan-review-prompt.md
     ```

     Read its one status line. `OK` and `FALLBACK` are a review: read the four
     scores and `findings` from the JSON. On `FALLBACK`, or a line naming
     `gpt-5.6-sol/high` with `status=OK`, say the substitution aloud with the
     runner's reason or the line's `evidence=`. `TIMEOUT` or `FAILED` produced
     no review: dispatch the printed `fallback`, `dr-superpowers:judge-fable`
     (`dr-superpowers:judge-opus` when Fable is unavailable or declined), with
     the full-plan template, save its reply to
     `<workspace>/plan-review-round-1.md`, and say why. Never run the Codex seat
     twice in one round.
   - **`primary=dr-superpowers:judge-opus`** (rounds 2 and 3). Write
     `diff -u <workspace>/plan-round-<r-1>.md PLAN_FILE > <workspace>/plan-delta-<r>.diff`,
     dispatch the seat with the Rounds 2 and 3 template, passing that file and
     the previous round's findings file, and save its reply to
     `<workspace>/plan-review-round-<r>.md`.
3. **Fix and repeat.** Any score of 8 or below, or any Critical or Important
   finding: fix the plan, re-lint, and run the next round. A delta round
   replaces a fresh full review; rounds are not cut. At most 3 review rounds;
   after the third, show the remaining findings to your human partner. A
   borderline score (9-13) gets a one-line decision in the plan's Assumptions.
4. **Record.** Only now, add the header line
   `**Plan review:** <YYYY-MM-DD> — <seat> — executability e / coherence c / coverage v / assumptions a (round r)`
   below the `**Program:**` line (below `**Execution:**` when there is no
   Program line). `<seat>` is the seat that ran the last round:
   `codex <model> / <effort>` from the runner's status line, or the judge
   agent. The header template deliberately omits it, so `plan-lint` warns
   until the review has run.

````

- [ ] **Step 4: Update the prompt file**

In `plugins/dr-superpowers/skills/writing-plans/references/plan-reviewer-prompt.md`, replace the two lines

```markdown
- `[JUDGE]` - `dr-superpowers:judge-fable`, or `dr-superpowers:judge-opus` when
  Fable is unavailable or declined (say the substitution aloud); no `model`
```

with

```markdown
- `[JUDGE]` - the `fallback` that `scripts/review-route PLAN_FILE --plan-round 1`
  prints when the Codex round produced nothing: `dr-superpowers:judge-fable`,
  or `dr-superpowers:judge-opus` when Fable is unavailable or declined (say the
  substitution aloud); no `model`
```

The bullet's third line, `  argument. On Codex, a native judge at Astra high or above.`, stays as it is: Step 3's Codex-host branch points at it.

Then append this to the end of the same file:

````markdown

## Round 1 on Codex

When `scripts/review-route` prints `primary=codex:plan`, send the template
above to `scripts/run-codex-review.sh --kind plan` with three changes:

1. Send only the `prompt:` body, unindented: drop the `Subagent ([JUDGE]):` and
   `description:` lines, which mean nothing outside a subagent dispatch.
2. Delete the `## Output Format` section - everything from that heading up to,
   but not including, `## Criteria`. The runner passes
   `criteria/codex-plan-review-schema.json`, and a prompt that orders markdown
   while `--output-schema` forbids it gets neither.
3. End the prompt with this paragraph:

       Return your review as the JSON object the output schema defines: the
       four scores as integers 1-20, and one `findings` entry per problem, with
       `severity`, `where` (`Task N`, `Task N part X`, or `header`), and a
       `summary` carrying the issue, why it matters for execution, and the fix.

Expand `[PLUGIN_ROOT]`, `[PLAN_FILE]`, `[SPEC_FILE]` and `[LINT_FILE]` exactly as
for a judge.

## Rounds 2 and 3

When `scripts/review-route` prints `primary=dr-superpowers:judge-opus`, dispatch
this template instead of the one above:

```
Subagent (dr-superpowers:judge-opus):
  description: "Re-review plan document, round [ROUND]"
  prompt: |
    You are reviewing an implementation plan that failed its previous review
    round and has been revised. Small models will execute it literally: each
    task's implementer sees only that task's text plus the header's Global
    Constraints and Contracts.

    **Plan:** [PLAN_FILE]
    **Spec it implements:** [SPEC_FILE]
    **plan-lint output:** [LINT_FILE] - an ERROR line there is a finding.
    **What changed since the last round:** [DELTA_FILE]
    **The last round's findings:** [PRIOR_FINDINGS_FILE]

    Read the prior findings, then the delta, then whatever part of the plan
    and spec you need. The delta is where to look first, not the limit of
    what you may read: a fix in one task can break a name another task
    consumes. For every name, path, signature, helper or test the delta adds,
    removes or renames, read the tasks that produce and consume it.

    You cannot run commands, modify files, or dispatch subagents.

    ## Output Format

    ## Plan Review

    ### Prior findings
    - [ADDRESSED|NOT ADDRESSED] <the finding, one line> - <evidence>

    ### Findings
    - [Critical|Important|Minor] [Task N|header]: <issue> - <why> - <fix>

    ### Verification Scores
    - executability: <1-20>
    - coherence: <1-20>
    - coverage: <1-20>
    - assumptions: <1-20>

    Write one Prior findings line for every Critical or Important finding of
    the last round, and repeat each NOT ADDRESSED one under Findings at its
    severity. Score the whole plan, not the delta.

    ## Criteria

    Read the criteria file at [PLUGIN_ROOT]/criteria/plan-review.md and score
    each criterion independently on a 1 to 20 scale, where 1 is a clear
    failure, 10 is genuinely uncertain, and 20 is clearly met. Score against
    those criteria and nothing else. Where a criterion tells you to ignore
    something, ignoring it is part of scoring correctly.
```

**Placeholders:** `[PLUGIN_ROOT]`, `[PLAN_FILE]`, `[SPEC_FILE]` and
`[LINT_FILE]` as above, plus:
- `[ROUND]` - REQUIRED: this round's number.
- `[DELTA_FILE]` - REQUIRED: `<workspace>/plan-delta-<r>.diff`.
- `[PRIOR_FINDINGS_FILE]` - REQUIRED: the previous round's
  `<workspace>/plan-review-round-<r-1>.json` or `.md`.

**Reviewer returns:** a verdict per prior Critical or Important finding, new
findings graded Critical, Important or Minor, and four scores for the whole
plan. Bands as above.
````

- [ ] **Step 5: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/review-route.test.sh && node scripts/validate-repository.mjs`
Expected: the suite's summary ends `0 failed`; the validator prints `Repository catalogs, manifests, versions, and bundled links are valid.`

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/skills/writing-plans/SKILL.md plugins/dr-superpowers/skills/writing-plans/references/plan-reviewer-prompt.md plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "feat(superpowers): route plan review rounds"
```

### Task 6: The Codex plugin locator

**Files:**
- Create: `plugins/dr-superpowers/reference/codex-plugin.json`
- Create: `plugins/dr-superpowers/scripts/codex-plugin`
- Create: `plugins/dr-superpowers/tests/codex-gate.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: the policy file and the `scripts/codex-plugin` interface (Contracts), consumed by Task 7 part B; `tests/codex-gate.test.sh` and its helpers (Contracts, Test-suite helpers), extended by Task 7.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

Every fenced file below is verified prototype code: transcribe it exactly, byte for byte.

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/codex-gate.test.sh`:

```bash
#!/usr/bin/env bash
# The session gate decides whether a session may touch Codex at all, so every
# way it can say no is asserted here - against a stub Claude config dir and a
# stub codex plugin whose app-server client is scripted per case. No case
# starts a real Codex.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# A config dir outside any git repository, so no project settings leak in.
CFG="$TMP/config"
PLUG="$TMP/plugin"
mkdir -p "$CFG/plugins" "$PLUG/.claude-plugin" "$PLUG/scripts/lib" "$TMP/work"
enable() { # enable <true|false|absent>
  case "$1" in
    absent) printf '{"enabledPlugins":{"other@x":true}}\n' > "$CFG/settings.json" ;;
    *) printf '{"enabledPlugins":{"codex@openai-codex":%s}}\n' "$1" > "$CFG/settings.json" ;;
  esac
}
install_plugin() { # install_plugin <registry-version> <manifest-version>
  printf '{"version":2,"plugins":{"codex@openai-codex":[{"scope":"user","installPath":"%s","version":"%s"}]}}\n' \
    "$PLUG" "$1" > "$CFG/plugins/installed_plugins.json"
  printf '{"name":"codex","version":"%s"}\n' "$2" > "$PLUG/.claude-plugin/plugin.json"
}

locate() { # locate; sets out and rc
  out=$(cd "$TMP/work" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR= bash "$P/scripts/codex-plugin" 2>"$TMP/err"); rc=$?
}

# --- the locator -------------------------------------------------------------
check "codex-plugin exists" "$([ -f "$P/scripts/codex-plugin" ] && echo yes || echo no)" "yes"
check "the policy file allows 1.0.3" \
  "$(jq -r '.versions | index("1.0.3") != null' "$P/reference/codex-plugin.json" 2>/dev/null | tr -d '\r')" "true"
check "the policy file ships untrusted" \
  "$(jq -r '[.trust.calibration, .trust.smoke] | join(",")' "$P/reference/codex-plugin.json" 2>/dev/null | tr -d '\r')" "pending,pending"

install_plugin 1.0.3 1.0.3
printf 'export class CodexAppServerClient {}\n' > "$PLUG/scripts/lib/app-server.mjs"
enable absent; locate
check "a plugin not named in enabledPlugins is off" "$out" "codex-plugin off reason=plugin-not-enabled"
check "off exits 1" "$rc" "1"
enable false; locate
check "a disabled plugin is off" "$out" "codex-plugin off reason=plugin-not-enabled"
enable true; locate
check "an enabled, installed, allowed plugin is ok" "$out" "codex-plugin ok version=1.0.3 root=$PLUG"
check "ok exits 0" "$rc" "0"
rm "$CFG/plugins/installed_plugins.json"; locate
check "a plugin missing from the registry is not installed" "$out" "codex-plugin off reason=plugin-not-installed"
install_plugin 1.0.3 1.0.2; locate
check "a manifest that disagrees with the registry is missing" "$out" "codex-plugin off reason=plugin-missing"
install_plugin 1.0.4 1.0.4; locate
check "a version outside the allowlist is off" "$out" "codex-plugin off reason=plugin-version:1.0.4"
install_plugin 1.0.3 1.0.3
mv "$PLUG/scripts/lib/app-server.mjs" "$TMP/app-server.mjs"; locate
check "an install without the client library is missing" "$out" "codex-plugin off reason=plugin-missing"
mv "$TMP/app-server.mjs" "$PLUG/scripts/lib/app-server.mjs"
out=$(CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR= bash "$P/scripts/codex-plugin" extra 2>/dev/null); rc=$?
check "an argument is a usage error" "$rc" "2"

# Registry format 2: several installs per plugin; the user-scope one is used.
printf '{"version":2,"plugins":{"codex@openai-codex":[{"scope":"project","installPath":"%s","version":"9.9.9"},{"scope":"user","installPath":"%s","version":"1.0.3"}]}}\n' \
  "$TMP/elsewhere" "$PLUG" > "$CFG/plugins/installed_plugins.json"
locate
check "the user-scope install is chosen over a project one" "$out" "codex-plugin ok version=1.0.3 root=$PLUG"
install_plugin 1.0.3 1.0.3

# Project settings are read only through CLAUDE_PROJECT_DIR, and local wins.
mkdir -p "$TMP/project/.claude"
printf '{"enabledPlugins":{"codex@openai-codex":false}}\n' > "$TMP/project/.claude/settings.local.json"
out=$(cd "$TMP/work" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$TMP/project" bash "$P/scripts/codex-plugin" 2>/dev/null)
check "project-local settings override the user setting" "$out" "codex-plugin off reason=plugin-not-enabled"
rm -rf "$TMP/project"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/codex-gate.test.sh`
Expected: FAIL — the first line is `FAIL - codex-plugin exists`, and the summary is `0 passed, 15 failed`.

- [ ] **Step 3: Write the policy file and the locator**

Create `plugins/dr-superpowers/reference/codex-plugin.json`:

```json
{
  "plugin": "codex@openai-codex",
  "versions": ["1.0.3"],
  "trust": { "calibration": "pending", "smoke": "pending" }
}
```

Create `plugins/dr-superpowers/scripts/codex-plugin`:

```bash
#!/usr/bin/env bash
# Locate the official codex plugin for the running Claude Code profile, and say
# whether this plugin may use it.
#
# Every Codex interaction of the session gate goes through that plugin, which
# owns the codex binary; nothing here names the binary. A plugin that is not
# enabled in this profile has none of its hooks running and may be pruned from
# the shared plugin cache, so enablement is checked, not assumed.
#
# Usage: codex-plugin
# Output: codex-plugin ok version=<v> root=<install path, to end of line>
#         codex-plugin off reason=<plugin-not-enabled|plugin-not-installed|plugin-missing|plugin-version:<v>>
# Exit: 0 ok; 1 off; 2 usage error or missing jq.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# Tests point this at a copy; the shipped file is the allowlist and trust record.
POLICY="${DR_CODEX_POLICY:-$HERE/../reference/codex-plugin.json}"

die() { printf 'codex-plugin: %s\n' "$1" >&2; exit 2; }
off() { printf 'codex-plugin off reason=%s\n' "$1"; exit 1; }

[ $# -eq 0 ] || die "usage: codex-plugin"
command -v jq >/dev/null 2>&1 || die "jq is required but not on PATH"
[ -r "$POLICY" ] || die "policy file not found: $POLICY"

id=$(jq -r '.plugin' "$POLICY" | tr -d '\r')
config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# User, then project, then local settings; the last file that defines the key
# wins. Scripts run from the plugin root, which is not the project, so project
# settings are read only when Claude Code names the project directory.
enabled=""
for f in "$config/settings.json" \
         ${CLAUDE_PROJECT_DIR:+"$CLAUDE_PROJECT_DIR/.claude/settings.json" "$CLAUDE_PROJECT_DIR/.claude/settings.local.json"}; do
  [ -r "$f" ] || continue
  v=$(jq -r --arg id "$id" \
    '.enabledPlugins | if type == "object" and has($id) then .[$id] | tostring else empty end' \
    "$f" 2>/dev/null | tr -d '\r')
  [ -z "$v" ] || enabled=$v
done
[ "$enabled" = true ] || off plugin-not-enabled

# Registry format 2 holds an array of installs per plugin; the user-scope
# install is the one a profile-wide enablement refers to.
entry=$(jq -c --arg id "$id" \
  '.plugins[$id] | if type == "array" then ((map(select(.scope == "user")) + .) | .[0]) else . end // empty' \
  "$config/plugins/installed_plugins.json" 2>/dev/null | tr -d '\r')
[ -n "$entry" ] && [ "$entry" != null ] || off plugin-not-installed

# installPath is a Windows path on Windows; forward slashes serve bash and node.
root=$(jq -r '.installPath // empty' <<<"$entry" | tr -d '\r' | tr '\\' '/')
version=$(jq -r '.version // empty' <<<"$entry" | tr -d '\r')
[ -n "$root" ] && [ -f "$root/scripts/lib/app-server.mjs" ] || off plugin-missing
[ "$(jq -r '.version // empty' "$root/.claude-plugin/plugin.json" 2>/dev/null | tr -d '\r')" = "$version" ] \
  || off plugin-missing

jq -e --arg v "$version" '.versions | index($v) != null' "$POLICY" >/dev/null 2>&1 \
  || off "plugin-version:$version"

printf 'codex-plugin ok version=%s root=%s\n' "$version" "$root"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dr-superpowers/tests/codex-gate.test.sh`
Expected: `15 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/reference/codex-plugin.json plugins/dr-superpowers/scripts/codex-plugin plugins/dr-superpowers/tests/codex-gate.test.sh
git update-index --chmod=+x plugins/dr-superpowers/scripts/codex-plugin plugins/dr-superpowers/tests/codex-gate.test.sh
git commit -m "feat(superpowers): add the codex plugin locator"
```

### Task 7: The session gate

Two parts, run in order, one commit each. Part A adds the session-file readers and writers; part B adds the gate that probes the codex plugin and writes the file. Together they extend Task 6's suite into the verified 53-case prototype.

#### Part A: The session readers

Every fenced file below is verified prototype code: transcribe it exactly, byte for byte.

**Files:**
- Create: `plugins/dr-superpowers/scripts/lib/codex-session.sh`
- Modify: `plugins/dr-superpowers/tests/codex-gate.test.sh` (insert before the final `printf`)

**Interfaces:**
- Consumes: the suite and its helpers (Task 6).
- Produces: `scripts/lib/codex-session.sh` and the session file shape (Contracts), sourced by part B, Task 8 and Task 14; the suite helpers `SESS`, `POLICY`, `gate`, `field` and `fresh`, used by part B.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/codex-gate.test.sh`, insert the block below, followed by one blank line, immediately before the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"`. `gate` is defined here but first called in part B:

```bash
SESS="$TMP/sessions"
# The trust cases edit a copy: the shipped policy must never change under a
# test, even one that dies halfway. The copy starts untrusted whatever the
# shipped file records, so a gate that passes later changes no case below.
POLICY="$TMP/policy.json"
jq '.trust = {"calibration":"pending","smoke":"pending"}' "$P/reference/codex-plugin.json" > "$POLICY"
gate() { # gate <mode> [args...]; sets out and rc
  local mode="$1"; shift
  out=$(cd "$TMP/work" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR= DR_CODEX_SESSION_DIR="$SESS" DR_CODEX_POLICY="$POLICY" \
    CLAUDE_CODE_SESSION_ID="${SID-s1}" GATE_STUB_MODE="$mode" GATE_STUB_LOG="$TMP/log" \
    DR_CODEX_GATE_TIMEOUT_MS="${GATE_MS:-20000}" bash "$P/scripts/codex-gate" "$@" 2>"$TMP/err"); rc=$?
}
field() { jq -r ".$1 | tostring" "$SESS/s1.json" 2>/dev/null | tr -d '\r'; }
fresh() { rm -rf "$SESS" "$TMP/log"; }

# --- the session readers -----------------------------------------------------
. "$P/scripts/lib/codex-session.sh"
export DR_CODEX_SESSION_DIR="$SESS" CLAUDE_CODE_SESSION_ID=s1
on() { # on <name> <surface> <want: on|off>
  if codex_session_on "$2"; then check "$1" on "$3"; else check "$1" off "$3"; fi
}
fresh; mkdir -p "$SESS"
on "no file is off" review off
printf '{"session_id":"s1","usable":true,"review":true,"lane":false}\n' > "$SESS/s1.json"
on "an open review surface is on" review on
on "a closed lane is off" lane off
codex_session_mark_off quota
check "mark_off closes both surfaces" "$(field usable)/$(field review)/$(field lane)/$(field reason)" "false/false/false/quota"
on "a marked-off session is off" review off
printf 'not json' > "$SESS/s1.json"
on "a torn file is off" review off
CLAUDE_CODE_SESSION_ID=""
printf '{"session_id":"","usable":true,"review":true,"lane":true}\n' > "$SESS/.json"
on "no session id is off whatever is on disk" review off
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/codex-gate.test.sh`
Expected: FAIL — `FAIL - an open review surface is on` and `FAIL - mark_off closes both surfaces`; the summary is `20 passed, 2 failed`.

- [ ] **Step 3: Write the library**

Create `plugins/dr-superpowers/scripts/lib/codex-session.sh`:

```bash
# Codex session state: one file per Claude Code session, written by
# scripts/codex-gate and marked off by a runner that hits the quota.
#
# The file is keyed by session id rather than kept in the project: skills run
# these scripts from the plugin root, which for an installed plugin is not the
# project, and a quota is account-wide anyway. Readers fail closed - any state
# that is not a positive answer for this session is off.
#
# Source this file; it defines functions only.

codex_session_id() { printf '%s' "${CLAUDE_CODE_SESSION_ID:-}"; }

codex_session_dir() { printf '%s' "${DR_CODEX_SESSION_DIR:-$HOME/.claude/dr-superpowers/codex-sessions}"; }

# codex_session_file - this session's file; fails when there is no session id.
codex_session_file() {
  local sid; sid=$(codex_session_id)
  [ -n "$sid" ] || return 1
  printf '%s/%s.json' "$(codex_session_dir)" "$sid"
}

# codex_session_on <review|lane> - succeeds only when this session's gate said
# that surface may use Codex.
codex_session_on() {
  local f; f=$(codex_session_file) || return 1
  [ "$(jq -r --arg s "$1" '.[$s] == true' "$f" 2>/dev/null | tr -d '\r')" = true ]
}

# codex_session_write <json> - replace this session's file in one rename, so a
# concurrent reader never sees half a file, and prune week-old sessions.
codex_session_write() {
  local f dir; f=$(codex_session_file) || return 0
  dir=$(codex_session_dir)
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\n' "$1" > "$f.tmp.$$" && mv -f "$f.tmp.$$" "$f"
  find "$dir" -maxdepth 1 -name '*.json' -mtime +7 -delete 2>/dev/null || true
}

# codex_session_mark_off <reason> - Codex is unusable for the rest of this
# session: no reset time, so the gate's cache keeps the answer.
codex_session_mark_off() {
  local f prior; f=$(codex_session_file) || return 0
  prior=$(cat "$f" 2>/dev/null) || prior='{}'
  codex_session_write "$(jq -c --arg sid "$(codex_session_id)" --arg r "$1" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{session_id: $sid, usable: false, review: false, lane: false, reason: $r, checked_at: $at,
      resets_at: null, resets_at_epoch: null, plugin_version: (.plugin_version // null)}' \
    <<<"$prior" 2>/dev/null)"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dr-superpowers/tests/codex-gate.test.sh`
Expected: `22 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/codex-session.sh plugins/dr-superpowers/tests/codex-gate.test.sh
git commit -m "feat(superpowers): add the codex session readers"
```

#### Part B: The gate

Every fenced file below is verified prototype code: transcribe it exactly, byte for byte.

**Files:**
- Create: `plugins/dr-superpowers/scripts/lib/codex-gate.mjs`
- Create: `plugins/dr-superpowers/scripts/codex-gate`
- Modify: `plugins/dr-superpowers/tests/codex-gate.test.sh` (two insertions)

**Interfaces:**
- Consumes: `scripts/codex-plugin` and the policy file (Task 6); `scripts/lib/codex-session.sh` and the suite helpers (part A) — all in Contracts.
- Produces: the `scripts/codex-gate` interface and `scripts/lib/codex-gate.mjs` (Contracts), consumed by Tasks 8, 9, 10, 11, 13 and 15.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/codex-gate.test.sh`, insert this block, followed by one blank line, immediately before the line `SESS="$TMP/sessions"`:

```bash
# --- the gate ----------------------------------------------------------------
# The stub client's behaviour is chosen per case by GATE_STUB_MODE; it records
# the connect options so direct mode is asserted, and every close() call.
cat > "$PLUG/scripts/lib/app-server.mjs" <<'STUB'
import fs from "node:fs";
const mode = process.env.GATE_STUB_MODE;
const log = (line) => fs.appendFileSync(process.env.GATE_STUB_LOG, `${line}\n`);
export class CodexAppServerClient {
  static async connect(cwd, options) {
    log(`connect disableBroker=${options?.disableBroker === true}`);
    if (mode === "connect-throws") throw new Error("spawn failed");
    if (mode === "hang") await new Promise(() => setInterval(() => {}, 1000));
    return new CodexAppServerClient();
  }
  async request(method) {
    log(`request ${method}`);
    if (method === "account/read") {
      if (mode === "logged-out") return { account: null, requiresOpenaiAuth: true };
      return { account: { type: "chatgpt", email: "a@b.c" }, requiresOpenaiAuth: true };
    }
    if (method === "account/rateLimits/read") {
      if (mode === "method-missing") throw new Error("unknown variant `account/rateLimits/read`");
      if (mode === "rpc-error") throw new Error("internal error");
      if (mode === "shapeless") return { rateLimits: {} };
      if (mode === "quota") return { ordinaryUsageAllowed: false, rateLimits: { primary: { usedPercent: 100, resetsAt: 1789898607 } } };
      if (mode === "full") return { ordinaryUsageAllowed: true, rateLimits: { primary: { usedPercent: 100, resetsAt: 1789898607 } } };
      return { ordinaryUsageAllowed: true, rateLimits: { primary: { usedPercent: 12, resetsAt: 1789898607 } } };
    }
    throw new Error(`unexpected ${method}`);
  }
  async close() { log("close"); }
}
STUB
```

Then insert this block, followed by one blank line, immediately before the line that begins `# --- the session readers`:

```bash
check "codex-gate exists" "$([ -f "$P/scripts/codex-gate" ] && echo yes || echo no)" "yes"

fresh; gate usable
check "a usable but untrusted plugin opens no surface" "$out" \
  "codex-gate usable=true reason=ok review=false lane=false resets_at=- source=probe"
check "the gate exits 0 when it answers" "$rc" "0"
check "the probe connects in direct mode" "$(grep -c 'connect disableBroker=true' "$TMP/log")" "1"
check "the probe reads the login, then the limits" \
  "$(grep '^request' "$TMP/log" | tr '\n' ' ')" "request account/read request account/rateLimits/read "
check "the probe closes its client" "$(grep -c '^close$' "$TMP/log")" "1"
check "the session file records the session" "$(field session_id)" "s1"
check "the session file records the plugin version" "$(field plugin_version)" "1.0.3"
gate usable
check "a second call answers from the cache" "$out" \
  "codex-gate usable=true reason=ok review=false lane=false resets_at=- source=cache"
check "a cached answer starts no client" "$(grep -c connect "$TMP/log")" "1"

# Trust is read on every call, cache or probe: flipping it must not wait for a
# new session.
cp "$POLICY" "$TMP/policy.bak"
jq '.trust = {"calibration":"pass","smoke":"pass"}' "$TMP/policy.bak" > "$POLICY"
gate usable
check "both gates passed opens both surfaces" "$out" \
  "codex-gate usable=true reason=ok review=true lane=true resets_at=- source=cache"
jq '.trust = {"calibration":"pass","smoke":"pending"}' "$TMP/policy.bak" > "$POLICY"
gate usable
check "calibration alone opens only the review seats" "$out" \
  "codex-gate usable=true reason=ok review=true lane=false resets_at=- source=cache"
check "the rewritten file carries the review surface" "$(field review)/$(field lane)" "true/false"
jq '.trust = {"calibration":"pending","smoke":"pass"}' "$TMP/policy.bak" > "$POLICY"
gate usable
check "the smoke test alone opens only the lane" "$out" \
  "codex-gate usable=true reason=ok review=false lane=true resets_at=- source=cache"
jq '.trust = {"calibration":"pass","smoke":"pass"}' "$TMP/policy.bak" > "$POLICY"
fresh; gate quota
check "trust never opens a surface on an unusable Codex" "$out" \
  "codex-gate usable=false reason=quota review=false lane=false resets_at=2026-09-20T10:03:27Z source=probe"
cp "$TMP/policy.bak" "$POLICY"

fresh; gate quota
check "an exhausted quota is off with its reset time" "$out" \
  "codex-gate usable=false reason=quota review=false lane=false resets_at=2026-09-20T10:03:27Z source=probe"
fresh; gate full
check "usage at 100 percent is quota even when ordinary usage is allowed" "$out" \
  "codex-gate usable=false reason=quota review=false lane=false resets_at=2026-09-20T10:03:27Z source=probe"
fresh; gate logged-out
check "a logged-out plugin is off" "$out" \
  "codex-gate usable=false reason=logged-out review=false lane=false resets_at=- source=probe"
fresh; gate method-missing
check "an app-server without the limits method is off" "$out" \
  "codex-gate usable=false reason=method-missing review=false lane=false resets_at=- source=probe"
fresh; gate rpc-error
check "any other limits error is off" "$out" \
  "codex-gate usable=false reason=plugin-api review=false lane=false resets_at=- source=probe"
fresh; gate shapeless
check "a limits reply without the signal is off" "$out" \
  "codex-gate usable=false reason=plugin-api review=false lane=false resets_at=- source=probe"
fresh; gate connect-throws
check "a connect that throws is off" "$out" \
  "codex-gate usable=false reason=plugin-api review=false lane=false resets_at=- source=probe"
fresh; GATE_MS=1500 gate hang
check "a hung connect times out" "$out" \
  "codex-gate usable=false reason=timeout review=false lane=false resets_at=- source=probe"

# The quota answer is cached only until its reset time.
fresh; gate quota
jq '.resets_at_epoch = 1577836800' "$SESS/s1.json" > "$TMP/s.json" && mv "$TMP/s.json" "$SESS/s1.json"
gate usable
check "a quota past its reset time is probed again" "$out" \
  "codex-gate usable=true reason=ok review=false lane=false resets_at=- source=probe"
gate quota --refresh
check "--refresh probes even with a cached answer" "$out" \
  "codex-gate usable=false reason=quota review=false lane=false resets_at=2026-09-20T10:03:27Z source=probe"

# Another session's file is never this session's answer.
fresh; gate quota
SID=s2 gate usable
check "a different session probes for itself" "$out" \
  "codex-gate usable=true reason=ok review=false lane=false resets_at=- source=probe"

# Without a session id nothing can be cached or read back, so nothing is written.
fresh; SID= gate usable
check "no session id still answers" "$out" \
  "codex-gate usable=true reason=ok review=false lane=false resets_at=- source=probe"
check "no session id writes no file" "$(ls "$SESS" 2>/dev/null | wc -l | tr -d ' ')" "0"

fresh; enable false; gate usable
check "a disabled plugin never starts a client" "$out" \
  "codex-gate usable=false reason=plugin-not-enabled review=false lane=false resets_at=- source=probe"
check "a disabled plugin writes no client log" "$([ -f "$TMP/log" ] && echo yes || echo no)" "no"
enable true

gate usable --bogus
check "an unknown flag is a usage error" "$rc" "2"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash plugins/dr-superpowers/tests/codex-gate.test.sh`
Expected: FAIL — the first FAIL line is `FAIL - codex-gate exists`; the summary is `24 passed, 29 failed`.

- [ ] **Step 3: Write the probe and the gate**

Create `plugins/dr-superpowers/scripts/lib/codex-gate.mjs`:

```javascript
// Probe Codex availability through the codex plugin's own app-server client.
//
// Usage: node codex-gate.mjs <plugin-root> <cwd> <timeout-ms>
// Prints one JSON object: {"usable": bool, "reason": string, "resets_at_epoch": seconds|null}.
//
// Two requests, neither of which runs a model: account/read for the login, and
// account/rateLimits/read for the quota. The plugin's `setup` command reports
// ready with the quota exhausted, so the rate-limit read is the only signal that
// catches it. Direct mode (disableBroker) is deliberate: the broker is a detached
// daemon the plugin's own SessionEnd hook owns, and it would outlive this probe.
import path from "node:path";
import { pathToFileURL } from "node:url";

const [root, cwd, timeoutArg] = process.argv.slice(2);
let client = null;
let settled = false;

async function finish(usable, reason, resetsAtEpoch = null) {
  if (settled) return;
  settled = true;
  try {
    await client?.close();
  } catch {
    // A client that fails to close has already lost its app-server.
  }
  process.stdout.write(`${JSON.stringify({ usable, reason, resets_at_epoch: resetsAtEpoch })}\n`);
  process.exit(0);
}

// The deadline is ours, not coreutils timeout: on Windows `timeout` kills only
// node and strands the app-server it spawned, while close() ends that tree. A
// connect that hangs before returning a client leaves nothing to close.
setTimeout(() => finish(false, "timeout"), Number(timeoutArg) > 0 ? Number(timeoutArg) : 30000);

async function probe() {
  let mod;
  try {
    mod = await import(pathToFileURL(path.join(root, "scripts", "lib", "app-server.mjs")).href);
  } catch {
    return finish(false, "plugin-api");
  }
  const Client = mod?.CodexAppServerClient;
  if (typeof Client?.connect !== "function") return finish(false, "plugin-api");

  try {
    client = await Client.connect(cwd, { disableBroker: true });
  } catch {
    return finish(false, "plugin-api");
  }
  if (settled) return;

  let account;
  try {
    account = await client.request("account/read", { refreshToken: false });
  } catch {
    return finish(false, "plugin-api");
  }
  // The rule the plugin's own buildAppServerAuthStatus applies.
  const type = account?.account?.type;
  if (!(type === "chatgpt" || type === "apiKey" || account?.requiresOpenaiAuth === false)) {
    return finish(false, "logged-out");
  }

  let limits;
  try {
    limits = await client.request("account/rateLimits/read", {});
  } catch (error) {
    const message = String(error?.message ?? error ?? "");
    const missing = message.includes("unknown variant") || message.includes("unknown method");
    return finish(false, missing ? "method-missing" : "plugin-api");
  }
  if (typeof limits?.ordinaryUsageAllowed !== "boolean") return finish(false, "plugin-api");

  const primary = limits.rateLimits?.primary;
  const used = typeof primary?.usedPercent === "number" ? primary.usedPercent : 0;
  if (limits.ordinaryUsageAllowed === true && used < 100) return finish(true, "ok");
  return finish(false, "quota", typeof primary?.resetsAt === "number" ? primary.resetsAt : null);
}

probe().catch(() => finish(false, "plugin-api"));
```

Create `plugins/dr-superpowers/scripts/codex-gate`:

```bash
#!/usr/bin/env bash
# Decide, once per session, whether this session may use Codex at all.
#
# Codex is usable only when the codex plugin is enabled, installed at an allowed
# version, logged in and within quota. A usable Codex is then used only on a
# surface whose shipping gate has passed (reference/codex-plugin.json `trust`):
# calibration opens the review seats, the smoke test opens the executor lane.
# Anything else turns that surface off for the session, so a Codex outage
# degrades the process instead of failing a task. The probe's answer is cached
# per session; a quota answer is probed again once its reset time has passed.
#
# Usage: codex-gate [--refresh]
# Output: codex-gate usable=<bool> reason=<r> review=<bool> lane=<bool> resets_at=<iso|-> source=<probe|cache>
# Exit: 0 answered, either way; 2 usage error or missing jq or node.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
POLICY="${DR_CODEX_POLICY:-$HERE/../reference/codex-plugin.json}"
. "$HERE/lib/codex-session.sh"

die() { printf 'codex-gate: %s\n' "$1" >&2; exit 2; }

refresh=0
case "$#:${1:-}" in
  0:) ;;
  1:--refresh) refresh=1 ;;
  *) die "usage: codex-gate [--refresh]" ;;
esac
command -v jq >/dev/null 2>&1 || die "jq is required but not on PATH"
command -v node >/dev/null 2>&1 || die "node is required but not on PATH"
[ -r "$POLICY" ] || die "policy file not found: $POLICY"

usable="" reason="" resets="" epoch="" version="" source=probe
file=$(codex_session_file) || file=""
if [ "$refresh" -eq 0 ] && [ -n "$file" ] && [ -r "$file" ]; then
  # A unit separator, not a tab: read collapses runs of whitespace separators,
  # which would shift every field after an empty one.
  cached=$(jq -r '[(.usable | tostring), (.reason // ""), (.resets_at // ""),
                   (.resets_at_epoch // "" | tostring), (.plugin_version // "")] | join("\u001f")' \
    "$file" 2>/dev/null | tr -d '\r')
  IFS=$'\x1f' read -r c_usable c_reason c_resets c_epoch c_version <<<"$cached"
  if [ "$c_usable" = true ] \
     || { [ "$c_usable" = false ] && { [ -z "$c_epoch" ] || [ "$c_epoch" -gt "$(date -u +%s)" ]; }; }; then
    usable=$c_usable reason=$c_reason resets=$c_resets epoch=$c_epoch version=$c_version source=cache
  fi
fi

if [ "$source" = probe ]; then
  line=$(bash "$HERE/codex-plugin"); rc=$?
  case "$rc" in
    0)
      version=$(sed -n 's/^codex-plugin ok version=\([^ ]*\) root=.*/\1/p' <<<"$line")
      root=$(sed -n 's/^codex-plugin ok version=[^ ]* root=//p' <<<"$line")
      # The probe owns its deadline; this outer bound only guarantees the gate
      # returns if node itself wedges.
      ms="${DR_CODEX_GATE_TIMEOUT_MS:-30000}"
      answer=$(timeout $((ms / 1000 + 15)) node "$HERE/lib/codex-gate.mjs" "$root" "$PWD" "$ms" 2>/dev/null | tail -1)
      usable=$(jq -r '.usable | tostring' <<<"$answer" 2>/dev/null | tr -d '\r')
      reason=$(jq -r '.reason // empty' <<<"$answer" 2>/dev/null | tr -d '\r')
      epoch=$(jq -r '.resets_at_epoch // empty' <<<"$answer" 2>/dev/null | tr -d '\r')
      if [ "$usable" != true ] && [ "$usable" != false ]; then
        usable=false reason=timeout epoch=""
      fi
      [ -z "$epoch" ] || resets=$(date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
      ;;
    1) usable=false reason=$(sed -n 's/^codex-plugin off reason=//p' <<<"$line") ;;
    *) die "codex-plugin failed" ;;
  esac
fi

# Trust is read on every call, cache hit or probe, and written back, so a trust
# commit mid-session reaches the readers without a --refresh.
trust() { jq -r --arg g "$1" '.trust[$g] == "pass"' "$POLICY" 2>/dev/null | tr -d '\r'; }
review=false lane=false
if [ "$usable" = true ]; then
  [ "$(trust calibration)" = true ] && review=true
  [ "$(trust smoke)" = true ] && lane=true
fi

if [ -n "$file" ]; then
  codex_session_write "$(jq -cn --arg sid "$(codex_session_id)" \
    --argjson usable "$usable" --argjson review "$review" --argjson lane "$lane" \
    --arg reason "$reason" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg resets "$resets" --arg epoch "$epoch" --arg version "$version" \
    '{session_id: $sid, usable: $usable, review: $review, lane: $lane, reason: $reason,
      checked_at: $at, resets_at: (if $resets == "" then null else $resets end),
      resets_at_epoch: (if $epoch == "" then null else ($epoch | tonumber) end),
      plugin_version: (if $version == "" then null else $version end)}')"
fi

printf 'codex-gate usable=%s reason=%s review=%s lane=%s resets_at=%s source=%s\n' \
  "$usable" "$reason" "$review" "$lane" "${resets:--}" "$source"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/codex-gate.test.sh`
Expected: `53 passed, 0 failed`, in about 30 seconds: every probe case starts node, and the hung-connect case waits out its 1.5-second deadline.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/codex-gate.mjs plugins/dr-superpowers/scripts/codex-gate plugins/dr-superpowers/tests/codex-gate.test.sh
git update-index --chmod=+x plugins/dr-superpowers/scripts/codex-gate
git commit -m "feat(superpowers): add the codex session gate"
```

### Task 8: Codex-off routing and the runner gate

Two parts, run in order, one commit each. Part A makes `review-route` name Claude seats while the session's review surface is off (spec §15.5); part B makes `run-codex-review.sh` refuse unless the gate says `usable=true`, and turn Codex off for the session on a quota error.

#### Part A: The codex-off routes

**Files:**
- Modify: `plugins/dr-superpowers/scripts/review-route` (four edits)
- Modify: `plugins/dr-superpowers/tests/review-route.test.sh` (two insertions)

**Interfaces:**
- Consumes: `codex_session_on` (Task 7 part A); the `review-route` interface and the test-suite helpers (Task 4) — all in Contracts.
- Produces: the codex-off rows of the `review-route` interface (Contracts), named in prose by Tasks 9, 11 and 13; the suite's session exports and its `review_surface` helper.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/review-route.test.sh`, replace the two lines

```bash
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
```

with

```bash
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Routing reads this session's Codex gate file. A fixed session id and a
# temporary directory keep the machine's real session state out of every case.
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=review-route-test
review_surface() { # review_surface <true|false|absent>
  rm -rf "$DR_CODEX_SESSION_DIR"
  [ "$1" != absent ] || return 0
  mkdir -p "$DR_CODEX_SESSION_DIR"
  printf '{"session_id":"review-route-test","usable":true,"review":%s,"lane":false}\n' "$1" \
    > "$DR_CODEX_SESSION_DIR/review-route-test.json"
}
review_surface true
```

Every existing Codex-seat case now runs with the review surface open. Then insert this block, followed by one blank line, immediately before the line `route --task 9`:

```bash
# --- the review surface off ------------------------------------------------------
# While the session's gate has not opened the review surface, no route names a
# Codex seat, and the Claude seat it names has nothing to fall back to.
review_surface false
route --task 1
check "codex off: total 1 goes to Sonnet alone" "$out" "review-seat task=1 primary=dr-superpowers:judge-sonnet-high fallback=- reason=codex-off"
check "codex off: a routed task still exits 0" "$rc" "0"
route --task 2
check "codex off: total 3 goes to Opus alone" "$out" "review-seat task=2 primary=dr-superpowers:judge-opus fallback=- reason=codex-off"
route --task 3
check "codex off: total 4 goes to Opus alone" "$out" "review-seat task=3 primary=dr-superpowers:judge-opus fallback=- reason=codex-off"
route --task 10
check "codex off: total 5 goes to Fable alone" "$out" "review-seat task=10 primary=dr-superpowers:judge-fable fallback=- reason=codex-off"
route --task 4
check "codex off: risk 2 at total 4 goes to Fable, not its band" "$out" "review-seat task=4 primary=dr-superpowers:judge-fable fallback=- reason=codex-off"
route --task 7
check "codex off: a split task routes on its riskiest part" "$out" "review-seat task=7 primary=dr-superpowers:judge-fable fallback=- reason=codex-off"
route --task 1 2
check "codex off: a batch takes its highest total" "$out" "review-seat task=1,2 primary=dr-superpowers:judge-opus fallback=- reason=codex-off"
route --task 5
check "codex off: an Executor task is unchanged" "$out" "review-seat task=5 primary=dr-superpowers:judge-opus fallback=- reason=executor"
route --task 6
check "codex off: an Executor task at risk 2 is unchanged" "$out" "review-seat task=6 primary=dr-superpowers:judge-fable fallback=- reason=executor"
route --plan-round 1
check "codex off: plan round 1 goes to Fable alone" "$out" "review-seat plan-round=1 primary=dr-superpowers:judge-fable fallback=- reason=codex-off"
route --plan-round 2
check "codex off: plan round 2 is unchanged" "$out" "review-seat plan-round=2 primary=dr-superpowers:judge-opus fallback=- reason=round"
review_surface absent
route --task 3
check "no session file is off" "$out" "review-seat task=3 primary=dr-superpowers:judge-opus fallback=- reason=codex-off"
route --plan-round 1
check "no session file keeps plan round 1 off Codex" "$out" "review-seat plan-round=1 primary=dr-superpowers:judge-fable fallback=- reason=codex-off"
review_surface true
printf 'not json' > "$DR_CODEX_SESSION_DIR/review-route-test.json"
route --task 1
check "a torn session file is off" "$out" "review-seat task=1 primary=dr-superpowers:judge-sonnet-high fallback=- reason=codex-off"
review_surface true
CLAUDE_CODE_SESSION_ID="" route --task 1
check "no session id is off, whatever is on disk" "$out" "review-seat task=1 primary=dr-superpowers:judge-sonnet-high fallback=- reason=codex-off"
route --task 1
check "an open review surface routes to Codex again" "$out" "review-seat task=1 primary=codex:light fallback=dr-superpowers:judge-sonnet-high reason=band"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: FAIL — the first FAIL line is `FAIL - codex off: total 1 goes to Sonnet alone`, `FAIL - a torn session file is off` is among the rest, and the summary is `48 passed, 12 failed`.

- [ ] **Step 3: Write the codex-off rows**

In `plugins/dr-superpowers/scripts/review-route`, replace the three comment lines

```bash
# test can reach it. This script never probes Codex. run-codex-review.sh checks
# availability on every run, and its status line decides whether the fallback
# is used.
```

with

```bash
# test can reach it. This script never probes Codex: it reads the file
# scripts/codex-gate keeps for this session, and while that file does not open
# the review surface it names Claude seats only, with reason=codex-off. While
# the surface is open, run-codex-review.sh still checks availability on every
# run, and its status line decides whether the fallback is used.
```

Replace the line `. "$HERE/lib/plan.sh"` with the two lines

```bash
. "$HERE/lib/plan.sh"
. "$HERE/lib/codex-session.sh"
```

Replace

```bash
    if [ "$2" -eq 1 ]; then
      printf 'review-seat plan-round=1 primary=codex:plan fallback=%s reason=round\n' "$FABLE"
    else
```

with

```bash
    if [ "$2" -eq 1 ] && codex_session_on review; then
      printf 'review-seat plan-round=1 primary=codex:plan fallback=%s reason=round\n' "$FABLE"
    elif [ "$2" -eq 1 ]; then
      printf 'review-seat plan-round=1 primary=%s fallback=- reason=codex-off\n' "$FABLE"
    else
```

Replace

```bash
elif [ "$executor" -eq 1 ]; then
  primary=$(band "$max_total") fallback=- reason=executor
elif [ "$max_risk" -ge 2 ]; then
```

with

```bash
elif [ "$executor" -eq 1 ]; then
  primary=$(band "$max_total") fallback=- reason=executor
elif ! codex_session_on review; then
  # Codex is off for this session, so the Codex rows name their Claude seat
  # directly, and there is nothing left to fall back to. Risk stays with Fable.
  if [ "$max_risk" -ge 2 ]; then primary=$FABLE; else primary=$(band "$max_total"); fi
  fallback=- reason=codex-off
elif [ "$max_risk" -ge 2 ]; then
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: `60 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/review-route plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "feat(superpowers): add codex-off review routes"
```

#### Part B: The runner gate and the quota

**Files:**
- Modify: `plugins/dr-superpowers/scripts/run-codex-review.sh` (five edits)
- Modify: `plugins/dr-superpowers/tests/codex-review.test.sh` (four edits)

**Interfaces:**
- Consumes: the `scripts/codex-gate` line (Task 7 part B); `codex_session_mark_off` (Task 7 part A); the `run-codex-review.sh` interface (Task 2) — all in Contracts.
- Produces: the runner's gate refusal and quota mark-off (Contracts), relied on by Tasks 10, 11, 13 and 15.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/codex-review.test.sh`, replace the two lines

```bash
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
```

with

```bash
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The runner marks this session's Codex gate file off on a quota error. A fixed
# session id and a temporary directory keep the machine's real file out of it.
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=codex-review-test
```

Replace

```bash
run() { # run <args...>
  PATH="$TMP/bin:$PATH" CODEX_REVIEW_ROSTER="$TMP/bin/detect-stub" \
    "$BASH_BIN" "$SCRIPT" "$@" 2>"$TMP/err"
}
```

with

```bash
# A stub session gate. Every case sees a usable Codex unless it sets
# GATE_STUB_LINE or GATE_STUB_EXIT.
cat > "$TMP/gate-stub" <<STUB
#!$BASH_BIN
printf '%s\n' "\${GATE_STUB_LINE:-codex-gate usable=true reason=ok review=true lane=true resets_at=- source=cache}"
exit "\${GATE_STUB_EXIT:-0}"
STUB

run() { # run <args...>
  PATH="$TMP/bin:$PATH" CODEX_REVIEW_ROSTER="$TMP/bin/detect-stub" CODEX_REVIEW_GATE="$TMP/gate-stub" \
    "$BASH_BIN" "$SCRIPT" "$@" 2>"$TMP/err"
}
```

Inside the stub codex heredoc, insert these lines immediately after the line that begins `  ok-plan) printf '{"executability":17,`:

```bash
  # The observed form of an exhausted quota, 2026-09-15: a column-0 ERROR: line.
  quota) echo "ERROR: You've hit your usage limit. Upgrade to Pro or try again at Sep 20th, 2026 5:03 PM." >&2; exit 1 ;;
  refuse-then-quota)
    if [ "\$model" = gpt-6-astra ]; then
      echo 'ERROR: {"type":"error","status":400,"error":{"type":"invalid_request_error","message":"The gpt-6-astra model is not supported when using Codex with a ChatGPT account."}}' >&2; exit 1
    fi
    echo "ERROR: You've hit your usage limit. Upgrade to Pro or try again at Sep 20th, 2026 5:03 PM." >&2; exit 1 ;;
```

Then insert this block, followed by one blank line, immediately before the line `# The caller must defer to the runner's outcome rather than running its own`:

```bash
# --- the session gate and the quota ------------------------------------------
write_roster "$ASTRA"
OFF='codex-gate usable=false reason=quota review=false lane=false resets_at=2026-09-20T10:03:27Z source=cache'
calls() { cat "$TMP/calls" 2>/dev/null || echo 0; }

out=$(GATE_STUB_LINE="$OFF" seat ok task --out "$TMP/o.json" --prompt "$TMP/p.txt"); rc=$?
check "an unusable gate prints the unusable line" "$out" "codex-judge none/none status=FAILED exit=0 out=$TMP/o.json evidence=unknown"
check "an unusable gate exits 1" "$rc" "1"
check "an unusable gate runs no codex" "$(calls)" "0"
present "the runner names the gate's reason" "$(cat "$TMP/err")" "run-codex-review: codex is off for this session (quota)"

out=$(GATE_STUB_LINE="$OFF" seat ok-final final --out "$TMP/o.md" --base main --dry-run); rc=$?
present "a dry run is gated too" "$out" "codex-judge none/none status=FAILED"
check "a gated dry run exits 1" "$rc" "1"
case "$out" in
  *would-run*) printf 'FAIL - a gated dry run prints no command\n'; fail=$((fail + 1)) ;;
  *) printf 'ok   - a gated dry run prints no command\n'; pass=$((pass + 1)) ;;
esac
out=$(GATE_STUB_LINE="$OFF" seat ok risk3 --out "$TMP/o.json" --prompt "$TMP/p.txt"); rc=$?
present "risk3 is gated too" "$out" "codex-judge none/none status=FAILED"
check "a gated risk3 runs no codex" "$(calls)" "0"

out=$(GATE_STUB_EXIT=2 seat ok-final final --out "$TMP/o.md" --base main); rc=$?
present "a gate that exits non-zero is refused, whatever it printed" "$out" "codex-judge none/none status=FAILED"
check "a refused gate exits 1" "$rc" "1"
check "a refused gate runs no codex" "$(calls)" "0"

out=$(GATE_STUB_LINE='codex-gate usable=true reason=ok review=false lane=false resets_at=- source=probe' \
  run --kind plan --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
present "an untrusted review surface still runs: the runner reads usable only" "$out" "codex-judge gpt-6-astra/high status=OK"

SFILE="$DR_CODEX_SESSION_DIR/codex-review-test.json"
open_session() {
  mkdir -p "$DR_CODEX_SESSION_DIR"
  printf '{"session_id":"codex-review-test","usable":true,"review":true,"lane":true,"reason":"ok","plugin_version":"1.0.3"}\n' > "$SFILE"
}
open_session
out=$(seat quota task --out "$TMP/o.json" --prompt "$TMP/p.txt"); rc=$?
present "a quota error is FAILED on the model that ran" "$out" "codex-judge gpt-6-astra/high status=FAILED exit=1"
check "a quota error exits 1" "$rc" "1"
check "a quota error is never a refusal: no second seat" "$(calls)" "1"
check "a quota error turns Codex off for the session" \
  "$(jq -r '[.usable, .review, .lane, .reason] | map(tostring) | join("/")' "$SFILE" | tr -d '\r')" "false/false/false/quota"
check "the marked-off file keeps the plugin version" "$(jq -r '.plugin_version' "$SFILE" | tr -d '\r')" "1.0.3"

open_session
out=$(seat refuse-then-quota final --out "$TMP/o.md" --base main); rc=$?
present "a quota error on the fallback run is FAILED" "$out" "codex-judge gpt-5.6-sol/high status=FAILED exit=1"
check "the quota fallback ran exactly one extra seat" "$(calls)" "2"
check "a quota error on the fallback run turns Codex off" "$(jq -r '.usable | tostring' "$SFILE" | tr -d '\r')" "false"

open_session
seat prose-fail final --out "$TMP/o.md" --base main >/dev/null
check "an ordinary failure leaves the session on" "$(jq -r '.usable | tostring' "$SFILE" | tr -d '\r')" "true"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash plugins/dr-superpowers/tests/codex-review.test.sh`
Expected: FAIL — the first FAIL line is `FAIL - an unusable gate prints the unusable line`, `FAIL - a quota error turns Codex off for the session` is among the rest, and the summary is `86 passed, 14 failed`.

- [ ] **Step 3: Write the gate refusal and the quota mark-off**

In `plugins/dr-superpowers/scripts/run-codex-review.sh`, replace the line `ROSTER="${CODEX_REVIEW_ROSTER:-$HERE/detect-executors.sh}"` with:

```bash
ROSTER="${CODEX_REVIEW_ROSTER:-$HERE/detect-executors.sh}"
# Tests point this at a stub gate. Unset in production, where scripts/codex-gate
# answers from this session's cache or probes the codex plugin.
GATE="${CODEX_REVIEW_GATE:-$HERE/codex-gate}"
. "$HERE/lib/codex-session.sh"
```

Insert this block, followed by one blank line, immediately before the line `# Selection. The catalog is a negative filter: a pair it does not advertise is`:

```bash
# The session gate runs before the roster, on every kind and on a dry run: a
# Codex this session may not use is never selected or run. Only `usable` is
# read, never the review surface, so a shipping gate can still exercise an
# untrusted surface.
gate_line=$(bash "$GATE" 2>/dev/null); gate_rc=$?
gate_line=$(printf '%s\n' "$gate_line" | tail -1 | tr -d '\r')
if [ "$gate_rc" -ne 0 ] || [[ "$gate_line" != *" usable=true "* ]]; then
  gate_reason=$(sed -n 's/.* reason=\([^ ]*\).*/\1/p' <<<"$gate_line")
  [ "$gate_rc" -eq 0 ] || gate_reason="codex-gate exited $gate_rc"
  printf 'codex-judge none/none status=FAILED exit=0 out=%s evidence=unknown\n' "$out"
  printf 'run-codex-review: codex is off for this session (%s)\n' "${gate_reason:-no gate answer}" >&2
  exit 1
fi
```

Insert this block, preceded by one blank line, immediately after the three lines

```bash
is_refusal() { # is_refusal <log-prefix>
  error_lines "$1" | grep -qiE "$REFUSAL"
}
```

```bash
# An exhausted quota is not a refusal either: every model on the account hits
# the same limit. It turns Codex off for the rest of the session instead, so the
# next seat goes straight to its Claude judge.
QUOTA='usage limit|rate_limit_reached'

is_quota() { # is_quota <log-prefix>
  error_lines "$1" | grep -qiE "$QUOTA"
}
```

Insert this block, preceded by one blank line, immediately after the three lines

```bash
if [ "$rc" -eq 0 ] && valid_output; then
  status "$model" "$effort" OK "$rc"; exit 0
fi
```

```bash
if is_quota "$out"; then
  codex_session_mark_off quota
  status "$model" "$effort" FAILED "$rc"; exit 1
fi
```

The check sits before the refusal branch, so a quota error never takes the fallback row. Finally, replace

```bash
  status "$back_model" "$back_effort" FAILED "$rc"; exit 1
```

with

```bash
  is_quota "$out.fallback" && codex_session_mark_off quota
  status "$back_model" "$back_effort" FAILED "$rc"; exit 1
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/codex-review.test.sh && timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: `100 passed, 0 failed`, then `60 passed, 0 failed`. Every pre-existing case of both suites still passes.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/run-codex-review.sh plugins/dr-superpowers/tests/codex-review.test.sh
git commit -m "feat(superpowers): gate the review runner"
```

### Task 9: The gate in writing-plans

**Files:**
- Modify: `plugins/dr-superpowers/skills/writing-plans/SKILL.md` (Assign an implementer step 4; Lint and Review step 2)
- Modify: `plugins/dr-superpowers/tests/review-route.test.sh` (insert before the final `printf`)

**Interfaces:**
- Consumes: the `scripts/codex-gate` line (Task 7 part B); the codex-off rows of `review-route` (Task 8 part A); the test-suite helpers and `WP` (Tasks 4 and 5) — all in Contracts.
- Produces: nothing later tasks consume; step 4 points at §Planning, whose gate Task 13 writes.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/review-route.test.sh`, insert immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
# --- the session gate in writing-plans -------------------------------------------
present "writing-plans runs the gate before each round" "$WP" 'run `scripts/codex-gate` (say its line aloud when it ends `source=probe`),'
present "writing-plans sends a codex-off round 1 to Fable" "$WP" '**`primary=dr-superpowers:judge-fable` with `reason=codex-off`**'
present "writing-plans offers the lane only on lane=true" "$WP" 'offers Codex only when'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: FAIL — `FAIL - writing-plans runs the gate before each round` and the other two; the summary is `60 passed, 3 failed`.

- [ ] **Step 3: Edit writing-plans**

In `plugins/dr-superpowers/skills/writing-plans/SKILL.md`, replace

```markdown
4. **Offer an external executor** once per plan and apply the lane gate — see
   [external-executor.md](../../reference/external-executor.md) §Planning. If
   no executor is usable, ask nothing.
```

with

```markdown
4. **Offer an external executor** once per plan and apply the lane gate — see
   [external-executor.md](../../reference/external-executor.md) §Planning,
   which runs `scripts/codex-gate` before the roster and offers Codex only when
   the gate prints `lane=true`. If no executor is usable, ask nothing.
```

Replace

```markdown
   Before each round `<r>`, copy the plan to `<workspace>/plan-round-<r>.md`,
   run `scripts/review-route PLAN_FILE --plan-round <r>`, and review with the
   seat it prints, using
```

with

```markdown
   Before each round `<r>`, copy the plan to `<workspace>/plan-round-<r>.md`,
   run `scripts/codex-gate` (say its line aloud when it ends `source=probe`),
   then `scripts/review-route PLAN_FILE --plan-round <r>`, and review with the
   seat it prints, using
```

Insert these lines immediately before the line that begins `   - **\`primary=dr-superpowers:judge-opus\`** (rounds 2 and 3).`:

```markdown
   - **`primary=dr-superpowers:judge-fable` with `reason=codex-off`** (round 1
     while the gate has not opened the review surface). No Codex seat runs.
     Dispatch it (`dr-superpowers:judge-opus` when Fable is unavailable or
     declined) with the full-plan template, save its reply to
     `<workspace>/plan-review-round-1.md`, and say `codex off — <reason>`,
     quoting the gate line's `reason` (`untrusted` when it printed
     `usable=true`).
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh && timeout 60 node scripts/validate-repository.mjs`
Expected: `63 passed, 0 failed`; the validator prints `Repository catalogs, manifests, versions, and bundled links are valid.`

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/skills/writing-plans/SKILL.md plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "docs(superpowers): run the gate before plan review"
```

### Task 10: Calibration gate

**Files:**
- Create: `docs/superpowers/notes/2026-09-15-review-routing-calibration.md`
- Modify: `plugins/dr-superpowers/reference/codex-plugin.json` (`trust.calibration`, only on PASS)
- Modify: `plugins/dr-superpowers/tests/codex-gate.test.sh` (the shipped-trust check, only on PASS)

**Interfaces:**
- Consumes: the `scripts/codex-gate` and `scripts/codex-plugin` interfaces (Tasks 6 and 7), `run-codex-review.sh --kind plan` (Task 2, gated by Task 8 part B), the Round 1 on Codex prompt (Task 5) — all in Contracts.
- Produces: the calibration notes file (Contracts), extended by Task 15; on PASS, `trust.calibration` = `pass`, which opens the review surface.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

When the gate reports Codex usable, this task makes four paid Codex runs on the
ChatGPT subscription — up to eight if Step 3 retries — and no Claude dispatch.
When it does not, the task makes no Codex run: it records the gate `PENDING`
and execution continues. Run every command from the repository root.

It calls `run-codex-review.sh --kind plan` directly, never through
`review-route`, which names a Claude seat while the review surface is
untrusted (spec §15.6).

| Name | Commit | Plan path | Spec path | Recorded e / c / v / a |
|---|---|---|---|---|
| `project-state` | `d6c288c` | `docs/superpowers/plans/2026-09-14-dr-superpowers-project-state.md` | `docs/superpowers/specs/2026-09-14-dr-superpowers-project-state-design.md` | 17 / 16 / 17 / 16 |
| `judge-seats` | `01f5a2a` | `docs/superpowers/plans/2026-09-14-dr-superpowers-judge-seats.md` | `docs/superpowers/specs/2026-09-14-dr-superpowers-judge-seats-design.md` | 17 / 18 / 16 / 16 |
| `inline-mode` | `69c6b48` | `docs/superpowers/plans/2026-09-12-dr-superpowers-inline-mode.md` | `docs/superpowers/specs/2026-09-12-dr-superpowers-inline-mode-design.md` | 17 / 18 / 14 / 16 |
| `small-model` | `5e96f14` | `docs/superpowers/plans/2026-09-12-dr-superpowers-small-model-planning.md` | `docs/superpowers/specs/2026-09-12-dr-superpowers-small-model-planning-design.md` | 17 / 17 / 16 / 17 |

- [ ] **Step 0: Run the session gate**

```bash
bash plugins/dr-superpowers/scripts/codex-gate
```

Expected: one line, `codex-gate usable=<true|false> reason=<r> review=<true|false> lane=<true|false> resets_at=<iso|-> source=<probe|cache>`. Say it aloud. `review=false` beside `usable=true` is expected: this gate is what opens the review surface.

If the line does not say `usable=true`, skip Steps 1-5 and 7: write the PENDING notes in Step 6, commit them, and continue with Task 11. That is not BLOCKED (spec §15.6). Otherwise continue with Step 1.

- [ ] **Step 1: Extract the replay inputs**

```bash
root=$(git rev-parse --show-toplevel)
cal="$root/.superpowers/calibration-review-routing"
mkdir -p "$cal"
while read -r name sha plan spec; do
  # The first **Plan review:** line is the header's record of the scores being
  # replayed; leaving it in would hand the replay its own answer. Fixture lines
  # further down are kept.
  git show "$sha:$plan" | awk '!done && /^\*\*Plan review:\*\*/ { done = 1; next } { print }' > "$cal/$name-plan.md"
  git show "$sha:$spec" > "$cal/$name-spec.md"
  printf 'plan-lint: 0 errors, 0 warnings (replay: this plan passed plan-lint when it was reviewed)\n' > "$cal/$name-lint.txt"
done <<'EOF'
project-state d6c288c docs/superpowers/plans/2026-09-14-dr-superpowers-project-state.md docs/superpowers/specs/2026-09-14-dr-superpowers-project-state-design.md
judge-seats 01f5a2a docs/superpowers/plans/2026-09-14-dr-superpowers-judge-seats.md docs/superpowers/specs/2026-09-14-dr-superpowers-judge-seats-design.md
inline-mode 69c6b48 docs/superpowers/plans/2026-09-12-dr-superpowers-inline-mode.md docs/superpowers/specs/2026-09-12-dr-superpowers-inline-mode-design.md
small-model 5e96f14 docs/superpowers/plans/2026-09-12-dr-superpowers-small-model-planning.md docs/superpowers/specs/2026-09-12-dr-superpowers-small-model-planning-design.md
EOF
grep -c '^\*\*Plan review:\*\*' "$cal"/*-plan.md
```

Expected: four lines, each an absolute path followed by a count, ending `inline-mode-plan.md:0`, `judge-seats-plan.md:0`, `project-state-plan.md:0` and `small-model-plan.md:2` (its two fixture lines), and no `git show` error.

- [ ] **Step 2: Write the four prompts**

This is the Round 1 on Codex prompt from Task 5, with its placeholders expanded:

```bash
root=$(git rev-parse --show-toplevel)
cal="$root/.superpowers/calibration-review-routing"
for name in project-state judge-seats inline-mode small-model; do
  cat > "$cal/$name-prompt.md" <<EOF
You are reviewing an implementation plan before it is saved. Small models
will execute it literally: each task's implementer sees only that task's
text plus the header's Global Constraints and Contracts.

**Plan:** $cal/$name-plan.md
**Spec it implements:** $cal/$name-spec.md
**plan-lint output:** $cal/$name-lint.txt - the mechanical checks already ran; do
not repeat them, but an ERROR line there is a finding.

Read the spec, then the plan. Read every task as its implementer will:
the task text plus the header's Global Constraints and Contracts, nothing
else.

You cannot run commands, modify files, or dispatch subagents.

## Findings

Report every problem that would make an implementer build the wrong
thing, get stuck, or make a decision the plan should have made. Grade
each one:

- **Critical** - the plan cannot be executed as written, or builds the
  wrong thing
- **Important** - likely rework: an ambiguity, a missing Contracts entry,
  an assumption without evidence, a test that would pass against a stub
- **Minor** - wording or structure that does not change what gets built

Locate each finding by \`Task N\` or \`header\`, and say what is wrong, why it
matters for execution, and the fix.

## Criteria

Read the criteria file at $root/plugins/dr-superpowers/criteria/plan-review.md and score
each criterion independently on a 1 to 20 scale, where 1 is a clear
failure, 10 is genuinely uncertain, and 20 is clearly met. Score against
those criteria and nothing else. Where a criterion tells you to ignore
something, ignoring it is part of scoring correctly.

Return your review as the JSON object the output schema defines: the
four scores as integers 1-20, and one \`findings\` entry per problem, with
\`severity\`, \`where\` (\`Task N\`, \`Task N part X\`, or \`header\`), and a
\`summary\` carrying the issue, why it matters for execution, and the fix.
EOF
done
grep -L "$cal/" "$cal"/*-prompt.md
```

Expected: the final `grep -L` prints nothing (every prompt carries its expanded paths).

- [ ] **Step 3: Run the four replays**

Start four **background** Bash calls, one per name, with no timeout, and wait for all four completion notifications. Each is:

```bash
root=$(git rev-parse --show-toplevel)
cal="$root/.superpowers/calibration-review-routing"
name=project-state   # then judge-seats, inline-mode, small-model
bash "$root/plugins/dr-superpowers/scripts/run-codex-review.sh" --kind plan \
  --cwd "$root" --out "$cal/$name-review.json" --prompt "$cal/$name-prompt.md"
```

Expected per call: one line `codex-judge gpt-6-astra/high status=OK exit=0 out=…`. The gate calibrates the Astra seat, so any other line is not a calibration of it: a `FALLBACK` line or a line naming `gpt-5.6-sol/high` makes that row `SUBSTITUTED`. On `TIMEOUT` or `FAILED`, re-run that one call once; a second `TIMEOUT` or `FAILED` makes the row `NO-RUN`. Step 4 does not score a `SUBSTITUTED` or `NO-RUN` row.

After all four calls have finished, and after any re-run, run `bash plugins/dr-superpowers/scripts/codex-gate` again. A quota error during a replay turns Codex off for the session (the runner marks the session file off, and a later call's stderr reads `run-codex-review: codex is off for this session (quota)`). If this line no longer says `usable=true`, Codex became unusable mid-gate: skip Steps 4 and 5, write the PENDING notes in Step 6 with `<reason>` from this line and every row marked `PENDING — codex unusable: <reason>` (a row that returned `status=OK` also keeps its status line and scores, as Step 6 says; read its scores with `jq -r '"\(.executability) / \(.coherence) / \(.coverage) / \(.assumptions)"' "$cal/<name>-review.json"`), commit them, run Step 7, and continue with Task 11. A quota never fails this gate (spec §15.1, ruling 10).

- [ ] **Step 4: Compare the scores**

```bash
root=$(git rev-parse --show-toplevel)
cal="$root/.superpowers/calibration-review-routing"
while read -r name e c v a; do
  jq -r --arg n "$name" --argjson e "$e" --argjson c "$c" --argjson v "$v" --argjson a "$a" '
    def d(x; y): (x - y) | if . < 0 then -. else . end;
    [d(.executability; $e), d(.coherence; $c), d(.coverage; $v), d(.assumptions; $a)] as $ds
    | "\($n): astra \(.executability) / \(.coherence) / \(.coverage) / \(.assumptions); recorded \($e) / \($c) / \($v) / \($a); max delta \($ds | max); \(if ($ds | max) <= 2 then "within" else "MISS" end)"
  ' "$cal/$name-review.json"
done <<'EOF'
project-state 17 16 17 16
judge-seats 17 18 16 16
inline-mode 17 18 14 16
small-model 17 17 16 17
EOF
```

Expected: one line per replayed plan, each ending `within` or `MISS`. A `SUBSTITUTED` or `NO-RUN` row from Step 3 keeps that result whatever this step prints for it; for a `NO-RUN` row, jq reports the missing file instead of a line.

- [ ] **Step 5: Check the known defects**

```bash
root=$(git rev-parse --show-toplevel)
cal="$root/.superpowers/calibration-review-routing"
jq -r '.findings[] | "\(.severity) \(.where): \(.summary)"' "$cal/project-state-review.json"
```

Read every printed finding and decide, quoting the finding that shows it:

1. **The cross-task helper** — a finding that `absent` (or "a helper") is defined in Task 3 of `tests/gates-manifest.test.sh` but only used by Task 11, so Task 3 might drop it or Task 11 might not find it.
2. **The vacuous needles** — a finding that one or more `present` assertions use needles too generic to fail (`"CLAUDE.md"`, `"optional"`, `'seven'`, `'exit 0'`), i.e. they would pass against unrelated text.

A finding counts only if it names the defect's substance; a general remark about test quality that names neither does not.

- [ ] **Step 6: Write the notes and apply the gate**

`docs/superpowers/notes/` does not exist yet: run `mkdir -p docs/superpowers/notes` first.

**When Step 0 did not say `usable=true`**, or Codex became unusable during Step 3, create `docs/superpowers/notes/2026-09-15-review-routing-calibration.md` with the actual date, the gate line and its `reason` filled in (a row that did return `status=OK` before Codex went off keeps its status line and Astra scores in their columns, with Max delta `-` and the same `PENDING — codex unusable: <reason>` Result, since it was never compared):

```markdown
# Review routing — calibration and smoke results

Spec: `docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md` §11, §15.6.
Run: <YYYY-MM-DD>, not run to completion — `<the gate line>`.

## Calibration

| Plan | Version | Status line | Astra e / c / v / a | Recorded | Max delta | Result |
|---|---|---|---|---|---|---|
| project-state | d6c288c | - | - | 17 / 16 / 17 / 16 | - | PENDING — codex unusable: <reason> |
| judge-seats | 01f5a2a | - | - | 17 / 18 / 16 / 16 | - | PENDING — codex unusable: <reason> |
| inline-mode | 69c6b48 | - | - | 17 / 18 / 14 / 16 | - | PENDING — codex unusable: <reason> |
| small-model | 5e96f14 | - | - | 17 / 17 / 16 / 17 | - | PENDING — codex unusable: <reason> |

Gate: PENDING — codex unusable: <reason>. The review surface stays off: `trust.calibration` in `plugins/dr-superpowers/reference/codex-plugin.json` stays `pending`.
```

Commit it with the commit command below, leave `reference/codex-plugin.json` and `tests/codex-gate.test.sh` unchanged, and continue with Task 11.

**Otherwise**, read the Codex version from the plugin, not from `codex --version`:

```bash
root=$(bash plugins/dr-superpowers/scripts/codex-plugin | sed -n 's/^codex-plugin ok version=[^ ]* root=//p')
node "$root/scripts/codex-companion.mjs" setup --json | jq -r '.codex.detail'
```

Expected: one line naming the Codex version. Then create `docs/superpowers/notes/2026-09-15-review-routing-calibration.md` with the actual values filled in from Steps 3-5:

```markdown
# Review routing — calibration and smoke results

Spec: `docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md` §11, §15.6.
Run: <YYYY-MM-DD>, Codex <the `codex.detail` line>.

## Calibration

| Plan | Version | Status line | Astra e / c / v / a | Recorded | Max delta | Result |
|---|---|---|---|---|---|---|
| project-state | d6c288c | <status line> | <scores> | 17 / 16 / 17 / 16 | <n> | within / MISS / SUBSTITUTED / NO-RUN |
| judge-seats | 01f5a2a | <status line> | <scores> | 17 / 18 / 16 / 16 | <n> | within / MISS / SUBSTITUTED / NO-RUN |
| inline-mode | 69c6b48 | <status line> | <scores> | 17 / 18 / 14 / 16 | <n> | within / MISS / SUBSTITUTED / NO-RUN |
| small-model | 5e96f14 | <status line> | <scores> | 17 / 17 / 16 / 17 | <n> | within / MISS / SUBSTITUTED / NO-RUN |

Only project-state's replay is the exact version its recorded scores came from.
The other three replay the committed plan, which already carries its last
round's fixes.

Known defects in the d6c288c replay:
- Cross-task helper (Task 3 / Task 11): found / not found — <quoted finding or "none">
- Vacuous needles: found / not found — <quoted finding or "none">

Gate: PASS / FAIL — <one line>
```

The gate passes only when all four status lines name `gpt-6-astra/high` with `status=OK`, all four rows read `within`, and both defects read `found`. A `MISS`, `SUBSTITUTED` or `NO-RUN` row, or a defect not found, is a FAIL.

**On PASS only**, open the review surface in the same commit. In `plugins/dr-superpowers/reference/codex-plugin.json`, replace

```json
  "trust": { "calibration": "pending", "smoke": "pending" }
```

with

```json
  "trust": { "calibration": "pass", "smoke": "pending" }
```

and in `plugins/dr-superpowers/tests/codex-gate.test.sh`, replace the two lines

```bash
check "the policy file ships untrusted" \
  "$(jq -r '[.trust.calibration, .trust.smoke] | join(",")' "$P/reference/codex-plugin.json" 2>/dev/null | tr -d '\r')" "pending,pending"
```

with

```bash
check "the policy file records the gates that passed" \
  "$(jq -r '[.trust.calibration, .trust.smoke] | join(",")' "$P/reference/codex-plugin.json" 2>/dev/null | tr -d '\r')" "pass,pending"
```

Then run `timeout 300 bash plugins/dr-superpowers/tests/codex-gate.test.sh`. Expected: `53 passed, 0 failed`.

Commit whichever notes you wrote — PENDING, PASS or FAIL:

```bash
git add docs/superpowers/notes/2026-09-15-review-routing-calibration.md plugins/dr-superpowers/reference/codex-plugin.json plugins/dr-superpowers/tests/codex-gate.test.sh
git commit -m "docs(superpowers): record review calibration"
```

On FAIL, stop the plan here: write the ledger line `Task 10: BLOCKED — calibration gate failed — <rows not within and defects not found>; the owner decides whether Codex takes plan-review round 1`, and report it to your human partner, quoting the defect findings verbatim rather than only found or not found. Do not start Task 11.

- [ ] **Step 7: Remove the replay inputs**

Skip this step when Step 0 did not say `usable=true`: nothing was extracted.

```bash
rm -rf "$(git rev-parse --show-toplevel)/.superpowers/calibration-review-routing"
```

Expected: no output.

### Task 11: Task review routing in subagent-driven-development

**Files:**
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` (Seats table row, the Ledger grammar, §3 Review the task, §5 Complete the task)
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/references/task-reviewer-prompt.md`
- Modify: `plugins/dr-superpowers/tests/review-route.test.sh` (append a block)

**Interfaces:**
- Consumes: `review-route --task` and its codex-off rows (Tasks 4 and 8 part A), `run-codex-review.sh --kind task --tier` and its gate refusal (Tasks 2 and 8 part B), the `scripts/codex-gate` line and the Gate prose (Task 7 part B), the test-suite helpers (Task 4) — all in Contracts.
- Produces: the `[CODEX_REVIEW_FILE]` placeholder and the ledger seat clause (Contracts); the section name `§Codex task review seats` that Task 13 creates in `reference/external-executor.md`.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/review-route.test.sh`, insert immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
# --- task review prose -----------------------------------------------------------
SDD="$P/skills/subagent-driven-development/SKILL.md"
TRP="$P/skills/subagent-driven-development/references/task-reviewer-prompt.md"
present "the Seats table routes the task reviewer" "$SDD" '| Task reviewer | The seat `scripts/review-route PLAN_FILE --task <N>` prints'
present "SDD runs the light tier for codex:light" "$SDD" '`codex:light` is `--tier light`'
present "SDD has the risk 2 section" "$SDD" '**Risk 2 and above.**'
absent "SDD no longer averages three seats" "$SDD" 'average each criterion'
absent "SDD no longer writes K=3" "$SDD" 'K=3'
present "SDD writes the seat clause" "$SDD" ', seat <seat>'
present "SDD keeps the runner name" "$SDD" 'run-codex-review.sh'
present "SDD keeps the FAILED deferral" "$SDD" 'TIMEOUT or FAILED'
present "SDD keeps the no-redispatch rule" "$SDD" 'never re-dispatch the Codex seat'
present "SDD runs the gate before routing" "$SDD" '- **The seat:** run `scripts/codex-gate` (say its line aloud when it ends'
present "SDD names a codex-off route" "$SDD" 'On `reason=codex-off` the review surface is off for'
present "SDD records a codex-off seat" "$SDD" '` (codex off — <reason>)` when `review-route` printed `reason=codex-off`'
present "the reviewer prompt has the second pass" "$TRP" '## Second Pass: The Codex Review'
present "the second pass names the Codex file by path" "$TRP" '[CODEX_REVIEW_FILE]'
present "the second pass comes after Fable's own review" "$TRP" 'Do this only after your Spec Compliance'
present "a Codex finding never raises a score" "$TRP" 'review raises a score, and nothing else you wrote before reading it changes.'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: `FAIL - the Seats table routes the task reviewer` among others.

- [ ] **Step 3: Edit the Seats table and the Ledger**

In `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, replace the line

```markdown
| Task reviewer | `dr-superpowers:judge-fable`; `dr-superpowers:judge-opus` when Fable is unavailable or your human partner declined it — say the substitution aloud | None |
```

with

```markdown
| Task reviewer | The seat `scripts/review-route PLAN_FILE --task <N>` prints (§3 Review the task); its `fallback` when a Codex seat's status line is `TIMEOUT` or `FAILED`; `dr-superpowers:judge-opus` wherever it names `judge-fable` and Fable is unavailable or your human partner declined it — say every substitution aloud | None |
```

In the Ledger grammar block, replace `[; scores spec s / scope c / verification v / quality q[, K=3]]` with `[; scores spec s / scope c / verification v / quality q, seat <seat>]`.

Below that block, replace the bullet `- The scores clause is present whenever a judge scored the task.` with `- The scores clause is present whenever a review seat, Codex or judge, scored the task.`

- [ ] **Step 4: Rewrite the seat and risk paragraphs of §3**

In the same file, replace the bullet that begins `- **The seat:** \`dr-superpowers:judge-fable\`, or \`judge-opus\` under the` — through its last line, `  identical prefix.` — with:

```markdown
- **The seat:** run `scripts/codex-gate` (say its line aloud when it ends
  `source=probe`), then `scripts/review-route PLAN_FILE --task <N>` (all of a
  batch's task numbers for a batch), and review with the `primary` it prints.
  A judge seat gets [task-reviewer-prompt.md](references/task-reviewer-prompt.md)
  with `[PLUGIN_ROOT]` expanded to this plugin's resolved directory; a Codex
  seat is run as below. On `reason=codex-off` the review surface is off for
  this session: the `primary` is a judge, no Codex seat runs, and the seat
  clause records `(codex off — <reason>)` with the gate line's `reason`
  (`untrusted` when it printed `usable=true`). If `review-route` exits 2,
  review with `dr-superpowers:judge-fable` and say why, quoting its message.
```

Then replace the paragraph that begins `**Risk 3.** When the task's \`**Evaluation:**\` line scored risk 3, dispatch three` — through its last line, `A seat that produced no report is never averaged in as if it had voted.` — with:

````markdown
**Codex seats.** Write the task-reviewer prompt for Codex as
[external-executor.md](../../reference/external-executor.md) §Codex task review
seats describes, to `<workspace>/task-<N>-review-codex-prompt.md`, and run it
as a background Bash call with no timeout:

```bash
bash "<plugin-root>/scripts/run-codex-review.sh" --kind task --tier <light|heavy> \
  --cwd <worktree-root> --out <workspace>/task-<N>-review-codex.json \
  --prompt <workspace>/task-<N>-review-codex-prompt.md
```

`codex:light` is `--tier light`; `codex:heavy` and `codex:heavy+judge-fable` are
`--tier heavy`. Read the runner's status line and take its word: `OK` and
`FALLBACK` are a seat that reviewed — on `FALLBACK`, or a `--tier heavy` line
naming `gpt-5.6-sol/high` with `status=OK`, say the substitution aloud — and
`TIMEOUT or FAILED` is a seat that did not: dispatch the route's `fallback`
seat with the ordinary prompt, say so with the runner's reason, and
never re-dispatch the Codex seat. The runner has already applied its own one-shot
fallback, so a second attempt here would turn one refused run into two. A
`FAILED` whose reason reads `codex is off for this session` is the same case:
the runner's own gate refused, or a quota error turned Codex off for the rest of
the session, so the next task's `review-route` names Claude seats. Read a
Codex review from its JSON — `spec_verdict` (`compliant` or `issues`),
`task_quality` (`approved` or `needs_fixes`), the four scores, `findings` and
`cannot_verify` — and apply the bands, the ⚠️ route and the fix loop to it
exactly as to a judge's report.

**Risk 2 and above.** On `primary=codex:heavy+judge-fable`, run the Codex seat
first, then dispatch `dr-superpowers:judge-fable` (`judge-opus` under the
Fable-unavailable rule) with the task-reviewer prompt and its Second Pass
section, `[CODEX_REVIEW_FILE]` set to the Codex seat's `--out` path. The task's
verdicts and scores are Fable's. Fable's findings, plus every Codex finding it
marks CONFIRMED, drive the fix loop; each CONFIRMED cannot-verify item goes to
the ruling seat as a `cannot-verify` item. A reply whose `### Codex findings`
section is not its last section formed its own review after reading Codex's:
re-dispatch it. If the Codex seat produced nothing, dispatch Fable without the
Second Pass section and say so. This replaces the three-seat average earlier
versions used for risk 3.
````

- [ ] **Step 5: Edit §5 Complete the task**

In the same file, replace the bullet `- append \`, K=3\` inside the scores clause on a risk-3 task` with:

```markdown
- end the scores clause with `, seat <seat>`: `codex gpt-5.6-sol/high`,
  `codex gpt-6-astra/high+judge-fable`, or the judge's short name, followed by
  ` (codex <STATUS> — <reason>)` when it replaced a Codex seat, or by
  ` (codex off — <reason>)` when `review-route` printed `reason=codex-off`
```

- [ ] **Step 6: Add the Second Pass to the reviewer prompt**

In `plugins/dr-superpowers/skills/subagent-driven-development/references/task-reviewer-prompt.md`, insert these lines inside the fenced template, immediately after the line `    ride alongside the verdicts above and never replace them.` and before the closing fence:

```markdown

    ## Second Pass: The Codex Review

    [Include this section only on a risk 2 or above task whose Codex seat
    produced a review. Delete it otherwise.]

    Do this only after your Spec Compliance, Strengths, Issues, Assessment and
    Verification Scores sections are written in full. Then read the Codex
    review of the same diff: [CODEX_REVIEW_FILE]

    It is a JSON object; read its `findings` and `cannot_verify`. Append this
    section to the end of your report:

    ### Codex findings
    - [CONFIRMED|REJECTED] <file:line> <the finding, one line> - <your evidence>
    - [CONFIRMED|REJECTED] cannot-verify: <the item, one line> - <your evidence>

    Write one line for every entry in `findings` and every entry in
    `cannot_verify`. CONFIRMED means the diff supports it. A CONFIRMED finding
    your Issues section missed is added there too, at your own severity and
    marked `(from codex)`, and may lower a score you gave; nothing in the Codex
    review raises a score, and nothing else you wrote before reading it changes.
```

Then replace the placeholder bullet

```markdown
- `[JUDGE]` — `dr-superpowers:judge-fable`, or `dr-superpowers:judge-opus`
  when Fable is unavailable or declined (say the substitution aloud); no
  `model` argument
```

with

```markdown
- `[JUDGE]` — the judge `scripts/review-route` printed, as its `primary` or,
  after a Codex seat produced nothing, its `fallback`;
  `dr-superpowers:judge-opus` in place of `dr-superpowers:judge-fable` when
  Fable is unavailable or declined (say the substitution aloud); no `model`
  argument
- `[CODEX_REVIEW_FILE]` — only with the Second Pass section: the Codex seat's
  `--out` JSON path. Pass the path, never the findings pasted inline: Fable
  cannot anchor on a review it has not opened yet
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bash plugins/dr-superpowers/tests/review-route.test.sh && bash plugins/dr-superpowers/tests/codex-review.test.sh && node scripts/validate-repository.mjs`
Expected: both summaries end `0 failed`; the validator prints `Repository catalogs, manifests, versions, and bundled links are valid.` — the `§Codex task review seats` link target file already exists, and Task 13 adds the section.

- [ ] **Step 8: Commit**

```bash
git add plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md plugins/dr-superpowers/skills/subagent-driven-development/references/task-reviewer-prompt.md plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "feat(superpowers): route task reviews through Codex"
```

### Task 12: Retire risk3-spread

**Files:**
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` (the ruling-seat kinds table)
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/references/ruling-prompt.md` (the kinds list)
- Modify: `plugins/dr-superpowers/skills/executing-plans/SKILL.md` (the kinds it does not run)
- Modify: `plugins/dr-superpowers/tests/inline-mode.test.sh:75,79` (two comments that count the kinds)
- Modify: `plugins/dr-superpowers/tests/review-route.test.sh` (append a block)

**Interfaces:**
- Consumes: the test-suite helpers (Task 4).
- Produces: nothing later tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/review-route.test.sh`, insert immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
# --- risk3-spread is retired -----------------------------------------------------
for f in "$P/skills/subagent-driven-development/SKILL.md" \
         "$P/skills/subagent-driven-development/references/ruling-prompt.md" \
         "$P/skills/executing-plans/SKILL.md"; do
  absent "no risk3-spread in ${f#"$P/"}" "$f" 'risk3-spread'
done
present "inline mode lists four kinds it does not run" "$P/skills/executing-plans/SKILL.md" 'The other four kinds belong to seats this mode does not run'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: `FAIL - no risk3-spread in skills/subagent-driven-development/SKILL.md` and the two others.

- [ ] **Step 3: Remove the kind**

In `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, delete the table row:

```markdown
| `risk3-spread` | A risk-3 criterion whose three scores spread by more than 6 points |
```

In `plugins/dr-superpowers/skills/subagent-driven-development/references/ruling-prompt.md`, delete these three lines:

```markdown
    - risk3-spread: three reviews of one risk-3 task disagree by more than 6
      points on a criterion. Decide what the diff supports: CONFIRMED-GAP
      for each finding that stands, PARK otherwise.
```

In `plugins/dr-superpowers/skills/executing-plans/SKILL.md`, replace

```markdown
The other five kinds belong to seats this mode does not run: `preflight` (there
is no pre-flight scan), `cannot-verify` and `risk3-spread` (no task reviewer),
`breaker` (no five-round review loop), and `codex-empty-diff` (no external
executor).
```

with

```markdown
The other four kinds belong to seats this mode does not run: `preflight` (there
is no pre-flight scan), `cannot-verify` (no task reviewer), `breaker` (no
five-round review loop), and `codex-empty-diff` (no external executor).
```

In `plugins/dr-superpowers/tests/inline-mode.test.sh`, replace the comment line `# The three ruling-seat kinds this mode can reach, and the five it cannot.` with `# The three ruling-seat kinds this mode can reach, and the four it cannot.`, and replace `# The skill names all eight kinds - three it runs and five it explains away -` with `# The skill names all seven kinds - three it runs and four it explains away -`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash plugins/dr-superpowers/tests/review-route.test.sh && bash plugins/dr-superpowers/tests/inline-mode.test.sh`
Expected: both summaries end `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md plugins/dr-superpowers/skills/subagent-driven-development/references/ruling-prompt.md plugins/dr-superpowers/skills/executing-plans/SKILL.md plugins/dr-superpowers/tests/inline-mode.test.sh plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "refactor(superpowers): retire the risk3-spread kind"
```

### Task 13: The external-executor lane prose

**Files:**
- Modify: `plugins/dr-superpowers/reference/external-executor.md` (§Planning, §Dispatch steps 1 and 4, §When a run fails, §Risk-3 Codex seat, §Final-review Codex round, §Failure rows)
- Modify: `plugins/dr-superpowers/reference/ladder.md` (the prose paragraph above the `codex-judge` block)
- Modify: `plugins/dr-superpowers/tests/review-route.test.sh` (append a block)

**Interfaces:**
- Consumes: `run-codex-review.sh --tier` and its gate refusal (Tasks 2 and 8 part B), `review-route --task` (Task 4), the `scripts/codex-gate` line and the Gate prose (Task 7 part B), the Second Pass section (Task 11), the test-suite helpers (Task 4) — all in Contracts.
- Produces: the section `## Codex task review seats`, which Task 11's link targets; the Planning rule that runs the gate and reads `docs/superpowers/distilled/constraints.md`, which Task 16 writes and Task 9's step 4 points at.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/review-route.test.sh`, insert immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
# --- external-executor and ladder prose ------------------------------------------
EXEC="$P/reference/external-executor.md"
LAD="$P/reference/ladder.md"
present "the lane reference has the task seats section" "$EXEC" '## Codex task review seats'
absent "the lane reference drops the risk-3 seat section" "$EXEC" '## Risk-3 Codex seat'
present "planning reads the distilled constraints" "$EXEC" 'Read `docs/superpowers/distilled/constraints.md` first'
present "a declared lane is ticked without asking" "$EXEC" 'tick it without asking'
present "an executor task routes to a Claude judge" "$EXEC" 'always routes to a Claude judge'
absent "the final round no longer cites the risk-3 seat" "$EXEC" 'Unlike the risk-3 seat'
present "the ladder names the light tier" "$LAD" '`--tier light` runs the last row directly'
present "planning runs the gate before the roster" "$EXEC" 'Unless it prints `lane=true`, stop here:'
present "dispatch runs the gate before guarding the roster" "$EXEC" '1. **Gate, then guard the roster.**'
present "a failed run refreshes the gate" "$EXEC" 'bash "<plugin-root>/scripts/codex-gate" --refresh'
present "the final Codex round needs the review surface" "$EXEC" 'Unless it prints `review=true`, skip the round'
present "the task seats name the runner's gate" "$EXEC" 'codex is off for this session (<reason>)'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: `FAIL - the lane reference has the task seats section` among others.

- [ ] **Step 3: Edit §Planning and §Dispatch**

In `plugins/dr-superpowers/reference/external-executor.md`, replace the two lines

```markdown
Run this once per plan, after scoring every task and before writing any
assignment line:
```

with

````markdown
Run this once per plan, after scoring every task and before writing any
assignment line. Run the session gate first:

```bash
bash "<plugin-root>/scripts/codex-gate"
```

Say its line aloud when it ends `source=probe`. Unless it prints `lane=true`, stop here:
ask nothing, run no roster, and write the plan Claude-only, saying
`codex off — <reason>` in one line, `<reason>` being the gate's `reason`
(`untrusted` when it printed `usable=true`). Otherwise run the roster:
````

Then replace the line

```markdown
Render the roster as a multi-select question: one tickable option per executor
```

with

```markdown
Read `docs/superpowers/distilled/constraints.md` first, when the project has
one. If a constraint there declares an executor's lane on and the roster reports
that executor `usable`, tick it without asking and say so in one line; the
question below then covers only the other executors. An absent file is not an
error.

Render the roster as a multi-select question: one tickable option per executor
```

Replace

```markdown
1. **Guard the roster.** Run
   `bash "<plugin-root>/scripts/detect-executors.sh"` and read the entry
   for the named executor. **Never trust the plan's copy** - it records what was
   available when the plan was written.
```

with

```markdown
1. **Gate, then guard the roster.** Run `bash "<plugin-root>/scripts/codex-gate"`
   first, saying its line aloud when it ends `source=probe`.
   Unless it prints `lane=true`, run neither the roster nor the wrapper:
   dispatch the task's `**Implementer:**` agent on the Claude lane, say the
   substitution aloud, and record it with the line below, quoting the gate's
   `reason` (`untrusted` when it printed `usable=true`). Otherwise run
   `bash "<plugin-root>/scripts/detect-executors.sh"` and read the entry
   for the named executor. **Never trust the plan's copy** - it records what was
   available when the plan was written.
```

Replace

```markdown
4. **Review as normal.** Dispatch the judge exactly as for a Claude task. Do not
   tell it which lane produced the diff: a judge that knows the author scores
   the author, and nothing in its inputs needs to change to keep it unaware.
```

with

```markdown
4. **Review with the routed seat.** Run `scripts/review-route PLAN_FILE --task <N>`
   and review with the seat it prints. A task carrying an `**Executor:**` line
   always routes to a Claude judge, so Codex never reviews its own work. Do not
   tell the judge which lane produced the diff: a judge that knows the author
   scores the author, and nothing in its inputs needs to change to keep it
   unaware.
```

Then insert this paragraph, followed by one blank line, immediately before the line that begins `**This section covers an initial run.**`:

```markdown
**Refresh the gate first.** After any run whose status is not `DONE`, run
`bash "<plugin-root>/scripts/codex-gate" --refresh` before the next Codex use of
any kind - a retry, a successor rung, a resume or a review seat - so a quota or
login failure turns Codex off for the rest of the session. When the refreshed
line no longer says `lane=true`, the response is `HANDBACK` whatever the tables
below say; record it with the gate's `reason`.
```

- [ ] **Step 4: Replace the risk-3 seat section**

In the same file, replace everything from the line `## Risk-3 Codex seat` up to, but not including, the line `## Final-review Codex round` with:

````markdown
## Codex task review seats

`scripts/review-route PLAN_FILE --task <N>` names a Codex seat for every task
without an `**Executor:**` line: `codex:light` for totals 0 to 3, `codex:heavy`
for 4 to 6, and `codex:heavy+judge-fable` at risk 2 or above. A task carrying
an `**Executor:**` line routes to a Claude judge, so these seats never review
Codex's own work - a property the final-review Codex round does not share.
Batched tasks never carry one, and route on the batch's highest total and risk.

The controller runs `scripts/codex-gate` before `review-route`, which names no
Codex seat while the gate has not opened the review surface. The runner runs the
gate again before its roster and reports `FAILED` with
`run-codex-review: codex is off for this session (<reason>)` unless it says
`usable=true`; a quota error during a run turns Codex off for the rest of the
session. It then establishes usability from the roster itself and never trusts the
plan's copy, applies the `codex-judge` row's bound with coreutils `timeout`, and
reports `FAILED` with the roster's own `reason` when Codex is not usable. Run it
as a background Bash call: the Bash tool's `timeout` caps at ten minutes, the
rung's bound is longer, and a background call is not bound by it at all.

```bash
bash "<plugin-root>/scripts/run-codex-review.sh" --kind task --tier <light|heavy> \
  --cwd <worktree-root> --out <workspace>/task-<N>-review-codex.json \
  --prompt <workspace>/task-<N>-review-codex-prompt.md
```

`codex:light` passes `--tier light`, which runs the `codex-judge` block's last
row and never falls back. `codex:heavy` and `codex:heavy+judge-fable` pass
`--tier heavy`: the runner takes the block's first row when the local model
catalog advertises it, takes the last row whenever the catalog is absent,
unreadable or silent, and falls back once on a refusal. `--kind risk3` is the
same seat under its earlier name and stays accepted. The runner prints one
status line:

```
codex-judge <model>/<effort> status=OK|FALLBACK|TIMEOUT|FAILED exit=<n> out=<path> evidence=<fetched_at>
```

Read that line and nothing else. `OK` and `FALLBACK` are a seat that reviewed;
`FALLBACK` additionally means the preferred rung refused the run, so say the
substitution aloud and record it in the task's ledger line with the reason the
runner prints in its own `refused (...)` message — it reads that line from
`<out>.stderr` or `<out>.stdout`, because an API-level refusal arrives on the
JSON stream rather than on stderr.

On a `--tier heavy` run, a status line naming the block's last row with
`status=OK` is a substitution as well: the catalog did not advertise the
preferred rung, so selection fell closed before the run. Say that aloud too,
quoting the line's `evidence=` value, which is the catalog's own date or
`unknown`. It is not `FALLBACK`, because nothing refused anything. On a
`--tier light` run the last row is the rung that tier selects, and there is
nothing to say.

`TIMEOUT` or `FAILED` is a seat that produced no review. Dispatch the route's
`fallback` seat with the ordinary task-reviewer prompt and say so. Never read an
absent or malformed report as a clean review: the runner has already
distinguished a report that is missing from one that is merely unfavourable.

**The prompt** is
[task-reviewer-prompt.md](../skills/subagent-driven-development/references/task-reviewer-prompt.md)
with its criteria block, with three changes. Send only the `prompt:` body,
without the `Subagent ([JUDGE]):` and `description:` lines. Leave out the Second
Pass section: that pass is Fable's. And **replace the Output Format section and
the criteria block's output-format paragraph with the schema, rather than
appending to them.** The shipped schema, `criteria/codex-review-schema.json`,
carries the four criterion names, the 1 to 20 range, and the spec and quality
verdicts, and the final message is JSON rather than a markdown
`### Verification Scores` section. Send the criteria themselves - where to look,
what scores high, what to ignore - and let the schema state the shape. Sent
unedited, the prompt would order markdown while `--output-schema` forbids it.

Use `codex exec`, not `codex exec review`: the latter imposes its own report
shape. The schema is a plugin file, outside every worktree, so it can never land
in a task's commit.

**At risk 2 or above** this review is the first of two steps: the controller
then dispatches `judge-fable` with the Second Pass section naming this seat's
`--out` path, per
[subagent-driven-development](../skills/subagent-driven-development/SKILL.md)
§3 Review the task. Fable's verdicts and scores are the task's.

````

- [ ] **Step 5: Edit §Final-review Codex round and §Failure rows**

In the same file, replace the two lines

```markdown
The final whole-branch review adds this round. The runner decides whether Codex
is usable:
```

with

````markdown
The final whole-branch review adds this round. Run the session gate first:

```bash
bash "<plugin-root>/scripts/codex-gate"
```

Say its line aloud when it ends `source=probe`.
Unless it prints `review=true`, skip the round: say `codex off — <reason>`,
`<reason>` being the gate's `reason` (`untrusted` when it printed
`usable=true`), and report the Claude review alone. Otherwise the runner decides
whether Codex is usable:
````

Replace

```markdown
The runner establishes usability itself from the same `detect-executors.sh`
roster the risk-3 seat uses, so this round needs no separate guard; a Codex that
```

with

```markdown
The runner establishes usability itself from the same `detect-executors.sh`
roster the task seats use, so this round needs no separate guard; a Codex that
```

and replace

```markdown
Unlike the risk-3 seat, this round is **not** self-review-free. The branch
```

with

```markdown
Unlike the task seats, this round is **not** self-review-free. The branch
```

In §Failure rows, replace the row

```markdown
| Task has an `**Executor:**` line and the CLI is usable | Run the wrapper; do not dispatch a subagent for it |
```

with the two rows

```markdown
| Task has an `**Executor:**` line and `scripts/codex-gate` does not print `lane=true` | Dispatch the `**Implementer:**` agent, say the substitution aloud, record the gate's `reason` in the assigned line |
| Task has an `**Executor:**` line, the gate prints `lane=true`, and the CLI is usable | Run the wrapper; do not dispatch a subagent for it |
```

- [ ] **Step 6: Edit the ladder prose**

In `plugins/dr-superpowers/reference/ladder.md`, replace

```markdown
The two Claude-hosted review seats — the risk-3 seat and the final-review
round — take their model from this block, not from `codex-assignment`. The
first row is preferred; the last row is the fallback.
```

with

```markdown
Every Claude-hosted Codex review seat — the task seats, plan-review round 1,
and the final-review round — takes its model from this block, not from
`codex-assignment`. The first row is preferred; the last row is the fallback.
`--tier light` runs the last row directly, for tasks totalling 0 to 3; every
other seat uses the first row with its fallback.
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bash plugins/dr-superpowers/tests/review-route.test.sh && bash plugins/dr-superpowers/tests/lanes.test.sh && bash plugins/dr-superpowers/tests/ladder.test.sh && bash plugins/dr-superpowers/tests/inline-mode.test.sh && node scripts/validate-repository.mjs`
Expected: every summary ends `0 failed`; the validator prints `Repository catalogs, manifests, versions, and bundled links are valid.`

- [ ] **Step 8: Commit**

```bash
git add plugins/dr-superpowers/reference/external-executor.md plugins/dr-superpowers/reference/ladder.md plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "docs(superpowers): describe the codex task seats"
```

### Task 14: The lazy lane probe in plan-lint

**Files:**
- Modify: `plugins/dr-superpowers/scripts/plan-lint:7-27` (usage, argument parsing and sourcing), `:138` (candidate list), `:214-222` (candidate collection), before `:233` (the probe)
- Modify: `plugins/dr-superpowers/scripts/plan-amend:76-77`
- Modify: `plugins/dr-superpowers/tests/plan-lint.test.sh`

**Interfaces:**
- Consumes: `reference/ladder.md`'s `gate` and `codex-assignment` blocks through `ladder_block` (existing); `codex_session_on lane` (Task 7 part A, Contracts).
- Produces: the `plan-lint` interface in Contracts.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/plan-lint.test.sh`, insert immediately after the line `printf '# Program\n' > docs/program.md`:

```bash
# The lane probe reads this session's Codex gate file. A fixed session id and a
# temporary directory keep the machine's real session state out of every case.
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=plan-lint-test
lane_surface() { # lane_surface <true|false>
  mkdir -p "$DR_CODEX_SESSION_DIR"
  printf '{"session_id":"plan-lint-test","usable":true,"review":false,"lane":%s}\n' "$1" \
    > "$DR_CODEX_SESSION_DIR/plan-lint-test.json"
}
lane_surface true
# Stub rosters for the lane probe. Every case uses one, so no case depends on
# whether Codex is installed on the machine running the suite.
cat > usable.sh <<EOF
printf 'called\n' >> "$TMP/probe-calls"
echo '[{"id":"codex","usable":true,"reason":null}]'
EOF
cat > unusable.sh <<EOF
printf 'called\n' >> "$TMP/probe-calls"
echo '[{"id":"codex","usable":false,"reason":"present but not authenticated; run codex login"}]'
EOF
export PLAN_LINT_ROSTER="$TMP/unusable.sh"
calls() { cat "$TMP/probe-calls" 2>/dev/null | grep -c called; }
```

Then insert immediately before the line `# --- amendments ---`:

```bash
# --- the lazy lane probe ---
# p1 makes Task 1 lane-eligible: total 2, risk 0, no Executor, no Override.
variant p1.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/'
export PLAN_LINT_ROSTER="$TMP/usable.sh"
rm -f probe-calls; lint p1.md
has "usable codex: an eligible task without Executor warns" "$out" "WARN Task 1: lane-eligible with no **Executor:** line (codex gpt-5.5 / medium)"
check "usable codex: the warning does not fail the lint" "$status" "0"
lacks "usable codex: a risk-2 task is not named" "$out" "WARN Task 2: lane-eligible"
check "usable codex: the probe runs once" "$(calls)" "1"
rm -f probe-calls; lint p1.md --no-probe
lacks "--no-probe: no lane warning" "$out" "lane-eligible"
check "--no-probe: the roster never runs" "$(calls)" "0"
rm -f probe-calls; lint clean.md
check "no candidate: the roster never runs" "$(calls)" "0"
lane_surface false
rm -f probe-calls; lint p1.md
lacks "lane surface off: no lane warning" "$out" "lane-eligible"
check "lane surface off: the roster never runs" "$(calls)" "0"
rm -rf "$DR_CODEX_SESSION_DIR"
rm -f probe-calls; lint p1.md
check "no session file: the roster never runs" "$(calls)" "0"
lane_surface true
export PLAN_LINT_ROSTER="$TMP/unusable.sh"
rm -f probe-calls; lint p1.md
lacks "unusable codex: no lane warning" "$out" "lane-eligible"
check "unusable codex: the probe still ran once" "$(calls)" "1"
export PLAN_LINT_ROSTER="$TMP/usable.sh"
variant p2.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Executor:** codex gpt-5.5 \/ medium/; s/^(\*\*Program:\*\* .*)$/\1\n\n> **External executors:** codex/'
rm -f probe-calls; lint p2.md
lacks "an Executor line clears the candidate" "$out" "lane-eligible"
lacks "the Executor fixture is otherwise clean" "$out" "ERROR Task 1"
check "a plan whose only candidate has an Executor never probes" "$(calls)" "0"
variant p3.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-high/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Override:** owner kept the Sonnet-high tier/'
rm -f probe-calls; lint p3.md
lacks "an overridden task is not a candidate" "$out" "lane-eligible"
variant p4.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/; s/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — x/'
rm -f probe-calls; lint p4.md
lacks "an inline plan gets no lane warning" "$out" "lane-eligible"
check "an inline plan never probes" "$(calls)" "0"
lint p1.md --no-probe --amendments am-none.md
check "flags parse in any order" "$status" "0"
export PLAN_LINT_ROSTER="$TMP/unusable.sh"
check "plan-amend never probes" "$(grep -c -- '--no-probe' "$HERE/../scripts/plan-amend")" "2"
```

The `am-none.md` file does not exist; `plan_apply_amendments` treats a missing amendments file as none, so the case isolates flag order.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash plugins/dr-superpowers/tests/plan-lint.test.sh`
Expected: FAIL lines for `usable codex: an eligible task without Executor warns`, `usable codex: the probe runs once`, `unusable codex: the probe still ran once`, `flags parse in any order` (today's parser exits 2 on `--no-probe`) and `plan-amend never probes`; the summary is `72 passed, 5 failed`. The `--no-probe`, no-candidate, lane-surface-off and no-session-file cases pass already, because nothing probes yet.

- [ ] **Step 3: Change the argument parsing**

In `plugins/dr-superpowers/scripts/plan-lint`, replace the lines from `# Usage: plan-lint PLAN_FILE [--amendments FILE]` through `fi` that closes the amendments `if` (the block ending `  amend=$(plan_amendments_file "$plan")` / `fi`) with:

```bash
# Usage: plan-lint PLAN_FILE [--amendments FILE] [--no-probe]
# Default amendments: <workspace>/amendments.md inside a git repository.
# --no-probe skips the lane probe, for runs whose verdict must not depend on
# whether Codex is usable on the machine.
# Output: "ERROR|WARN <header|Task N>: <what>" lines, then a summary line.
# Exit: 0 no errors; 1 errors; 2 usage or missing file.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/plan.sh"
. "$HERE/lib/codex-session.sh"
ROUTING="$HERE/../reference/codex-routing.json"

usage() { echo "usage: plan-lint PLAN_FILE [--amendments FILE] [--no-probe]" >&2; exit 2; }
[ $# -ge 1 ] || usage
plan=$1; shift
amend="" amend_given=0 probe=1
while [ $# -gt 0 ]; do
  case "$1" in
    --amendments) [ $# -ge 2 ] || usage; amend=$2 amend_given=1; shift 2 ;;
    --no-probe) probe=0; shift ;;
    *) usage ;;
  esac
done
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }
[ "$amend_given" -eq 1 ] || amend=$(plan_amendments_file "$plan")
```

- [ ] **Step 4: Collect and probe the candidates**

In the same file, replace the line `r5_bad="" max_total=0` with:

```bash
r5_bad="" max_total=0 lane=""
```

Replace the Executor block — from `    executor=$(line Executor)` through the `    fi` that closes `if [ -n "$executor" ]` — with:

```bash
    executor=$(line Executor)
    if [ -n "$executor" ]; then
      [ "$sev" = ERROR ] || say ERROR "$where" "an Executor line on an overridden task fails the lane gate"
      { [ "$t" -ge "$min_score" ] && [ "$d" -le "$max_risk" ]; } \
        || say ERROR "$where" "total $t / risk $d fails the lane gate (min_score $min_score, max_risk $max_risk)"
      rung=$(awk -v t="$t" '$1 == t { print $2 " / " $3 }' <<<"$(ladder_block codex-assignment)")
      { [ -n "$rung" ] && [[ "$executor" == *"codex $rung"* ]]; } || say ERROR "$where" "Executor does not name the codex-assignment rung for total $t (codex ${rung:-none})"
      [[ "$externals" == *codex* ]] || say ERROR "$where" "Executor used but the header's '> **External executors:**' line does not name codex"
    elif [ "$sev" = ERROR ] && [ $((a + b + c)) -lt 4 ] && [ "$b" -lt 3 ] \
         && [ "$t" -ge "$min_score" ] && [ "$d" -le "$max_risk" ]; then
      rung=$(awk -v t="$t" '$1 == t { print $2 " / " $3 }' <<<"$(ladder_block codex-assignment)")
      [ -z "$rung" ] || lane="$lane$where"$'\t'"$rung"$'\n'
    fi
```

Then insert immediately before the line `# R5: inline eligibility, and the inline model follows the highest total —`:

```bash
# The lane probe is lazy: the detector costs about two seconds, so it runs only
# when some task could have taken the lane and did not, and only when this
# session's Codex gate opened the lane surface. A plan without Executor lines is
# correct on a machine where Codex is unusable, so every outcome other than a
# usable codex row prints nothing. Inline plans are skipped: Executor lines are
# inert under inline execution, so the warning would be noise.
if [ -n "$lane" ] && [ "$probe" -eq 1 ] && [ "$mode" != inline ] && codex_session_on lane; then
  roster=$(timeout 30 bash "${PLAN_LINT_ROSTER:-$HERE/detect-executors.sh}" 2>/dev/null) || roster=""
  usable=$(jq -r '.[]? | select(.id == "codex") | .usable' <<<"$roster" 2>/dev/null | tr -d '\r')
  if [ "$usable" = true ]; then
    while IFS=$'\t' read -r w r; do
      [ -z "$w" ] || say WARN "$w" "lane-eligible with no **Executor:** line (codex $r)"
    done <<<"$lane"
  fi
fi

```

- [ ] **Step 5: Keep plan-amend off the probe**

In `plugins/dr-superpowers/scripts/plan-amend`, replace the two lines

```bash
bash "$HERE/plan-lint" "$plan" --amendments "$TMP/before" | grep '^ERROR' | sort > "$TMP/lint-before"
bash "$HERE/plan-lint" "$plan" --amendments "$TMP/after" | grep '^ERROR' | sort > "$TMP/lint-after"
```

with

```bash
bash "$HERE/plan-lint" "$plan" --amendments "$TMP/before" --no-probe | grep '^ERROR' | sort > "$TMP/lint-before"
bash "$HERE/plan-lint" "$plan" --amendments "$TMP/after" --no-probe | grep '^ERROR' | sort > "$TMP/lint-after"
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/plan-lint.test.sh && timeout 300 bash plugins/dr-superpowers/tests/plan-amend.test.sh`
Expected: `77 passed, 0 failed`, then `22 passed, 0 failed`, including every pre-existing case (`clean Claude plan: summary` still `plan-lint: 0 errors, 1 warnings`). The plan-lint suite takes about two minutes.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/scripts/plan-lint plugins/dr-superpowers/scripts/plan-amend plugins/dr-superpowers/tests/plan-lint.test.sh
git commit -m "feat(superpowers): add a lazy lane probe to plan-lint"
```

### Task 15: Smoke-test gate

**Files:**
- Modify: `docs/superpowers/notes/2026-09-15-review-routing-calibration.md` (append a section)
- Modify: `plugins/dr-superpowers/reference/codex-plugin.json` (`trust.smoke`, only on PASS)
- Modify: `plugins/dr-superpowers/tests/codex-gate.test.sh` (the shipped-trust check, only on PASS)

**Interfaces:**
- Consumes: the notes file (Task 10); the `scripts/codex-gate` and `scripts/codex-plugin` interfaces (Tasks 6 and 7, Contracts).
- Produces: on PASS, `trust.smoke` = `pass`, which opens the lane surface; nothing later tasks consume.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

When the gate reports Codex usable, this task makes one paid Codex run. When it
does not, it makes none, records the gate `PENDING`, and execution continues.
The wrapper runs directly: the lane surface is what this gate opens. Run every
command from the repository root.

- [ ] **Step 0: Run the session gate**

```bash
bash plugins/dr-superpowers/scripts/codex-gate --refresh
```

Expected: one line, `codex-gate usable=<true|false> reason=<r> review=<true|false> lane=<true|false> resets_at=<iso|-> source=probe`. Say it aloud. `lane=false` beside `usable=true` is expected: this gate is what opens the lane surface. `--refresh` makes the answer current, since Task 10 may have run hours earlier.

If the line does not say `usable=true`, skip Steps 1-3 and 5: append the PENDING section in Step 4, commit it, and continue with Task 16. That is not BLOCKED (spec §15.6). Otherwise continue with Step 1.

- [ ] **Step 1: Prepare a disposable worktree and brief**

```bash
root=$(git rev-parse --show-toplevel)
smoke="$root/.superpowers/smoke-review-routing"
rm -rf "$smoke"; mkdir -p "$smoke"
git worktree add --detach "$smoke/wt" HEAD
printf '["smoke.txt"]\n' > "$smoke/write-set.json"
cat > "$smoke/brief.md" <<'EOF'
# Task: smoke file

Create the file `smoke.txt` at the repository root containing exactly this one
line, followed by a newline:

codex lane smoke test

Change no other file. Use the commit subject `test(superpowers): add codex smoke file`.
EOF
git -C "$smoke/wt" status --porcelain
```

Expected: `git worktree add` reports `HEAD is now at …`; the final `status --porcelain` prints nothing.

- [ ] **Step 2: Run the wrapper**

Run as a **background** Bash call with no timeout, then wait for its completion notification:

```bash
root=$(git rev-parse --show-toplevel)
smoke="$root/.superpowers/smoke-review-routing"
bash "$root/plugins/dr-superpowers/scripts/run-codex-task.sh" \
  --brief "$smoke/brief.md" --report "$smoke/report.md" \
  --cwd "$smoke/wt" --task-id smoke-review-routing \
  --write-set "$smoke/write-set.json" --model gpt-5.5 --effort medium
echo "wrapper-exit=$?"
```

Expected: a status line containing `status=DONE` and `exit=0` with a `commits=<a7>..<b7>` range, then `wrapper-exit=0`.

If the status is not `DONE`, run `bash plugins/dr-superpowers/scripts/codex-gate --refresh`. If that line no longer says `usable=true` (the report's `## Codex error` names a quota, a usage limit or a login failure), Codex became unusable mid-gate: skip Step 3, append the PENDING section in Step 4 with this line's `reason`, add this line, with the wrapper's status line filled in, above the section's `Gate:` line:

```markdown
- Status line before Codex went off: `<the wrapper's status line>`
```

Then commit, run Step 5, and continue with Task 16. A quota never fails this gate (spec §15.1, ruling 10). If the refreshed line still says `usable=true`, skip Step 3 and record FAIL in Step 4, quoting the wrapper's status line.

- [ ] **Step 3: Verify the result**

```bash
root=$(git rev-parse --show-toplevel)
smoke="$root/.superpowers/smoke-review-routing"
range=<the a7..b7 value of the status line's commits= field>
git -C "$smoke/wt" rev-list --count "$range"
git -C "$smoke/wt" log --oneline -1
cat "$smoke/wt/smoke.txt"
git -C "$smoke/wt" status --porcelain
plugin_root=$(bash "$root/plugins/dr-superpowers/scripts/codex-plugin" | sed -n 's/^codex-plugin ok version=[^ ]* root=//p')
node "$plugin_root/scripts/codex-companion.mjs" setup --json | jq -r '.codex.detail'
```

Expected: `rev-list --count` prints `1`; the log line shows the commit (its subject is recorded, ideally `test(superpowers): add codex smoke file`); `smoke.txt` prints `codex lane smoke test`; `status --porcelain` prints nothing; the last command prints the Codex version from the plugin's `setup --json`, not from `codex --version`.

- [ ] **Step 4: Record and apply the gate**

**When Step 0 did not say `usable=true`**, or Codex became unusable during Step 2, append to `docs/superpowers/notes/2026-09-15-review-routing-calibration.md`, with the actual values:

```markdown

## Smoke test

Run: <YYYY-MM-DD>, not run to completion — `<the gate line>`.

Gate: PENDING — codex unusable: <reason>. The lane surface stays off: `trust.smoke` in `plugins/dr-superpowers/reference/codex-plugin.json` stays `pending`.
```

Commit it with the commit command below, leave `reference/codex-plugin.json` and `tests/codex-gate.test.sh` unchanged, and continue with Task 16.

**Otherwise**, append to the same file, with the actual values:

```markdown

## Smoke test

Run: <YYYY-MM-DD>, Codex <the `codex.detail` line from Step 3>, `gpt-5.5 / medium`, disposable linked worktree.

- Status line: `<the wrapper's status line>`
- Wrapper exit: <n>
- Commit: `<the log line from Step 3>`
- File content correct: yes / no

Gate: PASS / FAIL — <one line>
```

The gate passes only on `status=DONE`, wrapper exit 0, exactly one new commit, the exact file content, and a clean worktree. The commit subject is recorded, not gated: the wrapper takes it from Codex's structured report, so a paraphrase says nothing about whether the lane works. An `exit=2` inside the status line is a wrapper/CLI disagreement: quote the report's stderr tail in the notes.

**On PASS only**, open the lane surface in the same commit. In `plugins/dr-superpowers/reference/codex-plugin.json`, replace `"smoke": "pending"` with `"smoke": "pass"`. In `plugins/dr-superpowers/tests/codex-gate.test.sh`, replace the trust check's two lines - never the `check "the policy file allows 1.0.3" \` check above them. When Task 10 did not pass, replace

```bash
check "the policy file ships untrusted" \
  "$(jq -r '[.trust.calibration, .trust.smoke] | join(",")' "$P/reference/codex-plugin.json" 2>/dev/null | tr -d '\r')" "pending,pending"
```

with

```bash
check "the policy file records the gates that passed" \
  "$(jq -r '[.trust.calibration, .trust.smoke] | join(",")' "$P/reference/codex-plugin.json" 2>/dev/null | tr -d '\r')" "pending,pass"
```

When Task 10 passed, replace

```bash
check "the policy file records the gates that passed" \
  "$(jq -r '[.trust.calibration, .trust.smoke] | join(",")' "$P/reference/codex-plugin.json" 2>/dev/null | tr -d '\r')" "pass,pending"
```

with

```bash
check "the policy file records the gates that passed" \
  "$(jq -r '[.trust.calibration, .trust.smoke] | join(",")' "$P/reference/codex-plugin.json" 2>/dev/null | tr -d '\r')" "pass,pass"
```

Then run `timeout 300 bash plugins/dr-superpowers/tests/codex-gate.test.sh`. Expected: `53 passed, 0 failed`.

Commit whichever section you appended — PENDING, PASS or FAIL:

```bash
git add docs/superpowers/notes/2026-09-15-review-routing-calibration.md plugins/dr-superpowers/reference/codex-plugin.json plugins/dr-superpowers/tests/codex-gate.test.sh
git commit -m "docs(superpowers): record the codex lane smoke test"
```

On FAIL, stop the plan here: keep the worktree for inspection, write the ledger line `Task 15: BLOCKED — smoke test failed — <status line>; the owner decides whether the lane is trusted`, and report it to your human partner. Do not start Task 16.

- [ ] **Step 5: Remove the disposable worktree**

Only after a PASS, or a PENDING recorded after Step 1 created the worktree:

```bash
root=$(git rev-parse --show-toplevel)
git worktree remove --force "$root/.superpowers/smoke-review-routing/wt"
rm -rf "$root/.superpowers/smoke-review-routing"
git worktree list
```

Expected: `git worktree list` no longer shows `smoke-review-routing`.

### Task 16: The lane declared on for this repository

**Files:**
- Create: `docs/superpowers/distilled/constraints.md`
- Modify: `plugins/dr-superpowers/reference/project-state.md` (Who writes what table; What never happens to these files)
- Modify: `plugins/dr-superpowers/tests/project-status.test.sh` (insert before the final `printf`)

**Interfaces:**
- Consumes: the Planning rule in `reference/external-executor.md` (Task 13), which runs the gate and then reads this file; the `scripts/codex-gate` line (Task 7 part B, Contracts), which the entry names.
- Produces: nothing later tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/project-status.test.sh`, insert immediately before the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"`:

```bash
# An approved spec's owner decision may land in constraints.md by hand; the
# writer rule must say so, or the first such entry breaks it. The last five
# checks read this repository's own docs tree, not a plugin file.
present "project-state allows an owner-decision entry" "$STATE" "a human may add an entry that an approved spec's owner decisions"
present "project-state names writing-plans as a constraints reader" "$STATE" '`constraints.md` also dr-superpowers:writing-plans'
CONSTRAINTS="$P/../../docs/superpowers/distilled/constraints.md"
check "exists: docs/superpowers/distilled/constraints.md" \
  "$([ -f "$CONSTRAINTS" ] && echo yes || echo no)" "yes"
present "the Codex lane is declared on" "$CONSTRAINTS" "### The Codex executor lane is on"
present "the lane entry cites the review-routing spec" "$CONSTRAINTS" "Source: docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md@"
present "the lane entry records who set it" "$CONSTRAINTS" "Set by: owner"
present "the lane entry waits for the session gate" "$CONSTRAINTS" 'When `scripts/codex-gate` reports `lane=true`'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/project-status.test.sh`
Expected: `FAIL - project-state allows an owner-decision entry` and `FAIL - exists: docs/superpowers/distilled/constraints.md`.

- [ ] **Step 3: Edit project-state.md**

In `plugins/dr-superpowers/reference/project-state.md`, replace the table row

```markdown
| `distilled/*.md` | dr-superpowers:distilling-docs | dr-superpowers:project-status, dr-superpowers:brainstorming, dr-superpowers:resume-execution, both execution skills |
```

with

```markdown
| `distilled/*.md` | dr-superpowers:distilling-docs, or a human recording an approved spec's owner decision | dr-superpowers:project-status, dr-superpowers:brainstorming, dr-superpowers:resume-execution, both execution skills; `constraints.md` also dr-superpowers:writing-plans |
```

Replace

```markdown
`distilled/*.md` are written only by dr-superpowers:distilling-docs, which
deletes sources under its own rules and never touches a spec, a plan,
`completed.md`, or anything outside `docs/superpowers/notes/` and
`docs/superpowers/findings/`. `gates.md` is edited by a human or by an approved
bootstrap, never silently. `completed.md` is append-only.
```

with

```markdown
`distilled/*.md` are written only by dr-superpowers:distilling-docs, with one
exception: a human may add an entry that an approved spec's owner decisions
name, citing that spec as its `Source`. distilling-docs deletes sources under
its own rules and never touches a spec, a plan, `completed.md`, or anything
outside `docs/superpowers/notes/` and `docs/superpowers/findings/`. `gates.md`
is edited by a human or by an approved bootstrap, never silently.
`completed.md` is append-only.
```

- [ ] **Step 4: Write constraints.md**

Run from the repository root:

```bash
mkdir -p docs/superpowers/distilled
sha=$(git log -1 --format=%h -- docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md)
cat > docs/superpowers/distilled/constraints.md <<EOF
# Constraints

Rulings and policy that bind future work in this repository.

## Execution lanes

### The Codex executor lane is on
When \`scripts/codex-gate\` reports \`lane=true\`, the planner ticks \`codex\` without asking and gives every task that passes the lane gate an \`**Executor:**\` line.
Set by: owner, 2026-09-15 review-routing design session
Scope: every plan written for this repository on a Claude host
Source: docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md@$sha
EOF
cat docs/superpowers/distilled/constraints.md
```

Expected: the file prints with a seven-character sha after `@`.

- [ ] **Step 5: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/project-status.test.sh`
Expected: the summary line ends `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/distilled/constraints.md plugins/dr-superpowers/reference/project-state.md plugins/dr-superpowers/tests/project-status.test.sh
git commit -m "docs(superpowers): declare the codex lane on"
```

### Task 17: README, version, and the program amendment

**Files:**
- Modify: `plugins/dr-superpowers/README.md` (What you get; the reference and criteria paragraphs)
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json`, `plugins/dr-superpowers/.codex-plugin/plugin.json` (`version`)
- Modify: `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` (§6, after the sub-project 7 amendment)
- Modify: `plugins/dr-superpowers/tests/review-route.test.sh` (append a block)

**Interfaces:**
- Consumes: the test-suite helpers (Task 4).
- Produces: nothing.

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/review-route.test.sh`, insert immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
# --- README, version and program amendment -------------------------------------
RD="$P/README.md"
present "README counts twenty agents" "$RD" '**Twenty agents in three classes.**'
absent "README drops the three-seat risk-3 mean" "$RD" 'spread above 6 points'
present "README names review-route" "$RD" '`scripts/review-route` prints the review seat'
present "README names the plan-review schema" "$RD" '`codex-plan-review-schema.json`'
present "the Claude manifest is 1.9.0" "$P/.claude-plugin/plugin.json" '"version": "1.9.0"'
present "the Codex manifest is 1.9.0" "$P/.codex-plugin/plugin.json" '"version": "1.9.0"'
present "the program design records sub-project 8" "$P/../../docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md" '**Amendment 2026-09-15 (sub-project 8 spec).**'
present "README names the session gate" "$RD" '`scripts/codex-gate` checks the official codex plugin'
present "README records trust per surface" "$RD" 'recorded per surface in `reference/codex-plugin.json`'
present "the program design records the session gate" "$P/../../docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md" 'A session gate (`scripts/codex-gate`) reads'
present "the program design names sub-project 9" "$P/../../docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md" 'A ninth sub-project, "Codex through the plugin", moves'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: `FAIL - README counts twenty agents` among others.

- [ ] **Step 3: Edit the README**

In `plugins/dr-superpowers/README.md`, replace

```markdown
**Nineteen agents in three classes.** Seven execution implementers - Sonnet 5
```

with

```markdown
**Twenty agents in three classes.** Seven execution implementers - Sonnet 5
```

Replace

```markdown
Three read-only role agents - `judge-fable`, its `judge-opus` fallback, and
`scout-sonnet` - whose `tools:` frontmatter omits `Edit`, `Write`, and `Agent`,
```

with

```markdown
Four read-only role agents - the judges `judge-fable`, `judge-opus` and
`judge-sonnet-high`, and `scout-sonnet` - whose `tools:` frontmatter omits
`Edit`, `Write`, and `Agent`,
```

Replace

```markdown
verdicts. Risk-3 tasks are scored three times
and averaged, and a spread above 6 points sends the diff to the controller
instead of to the mean.
```

with

```markdown
verdicts. Tasks at risk 2 or above are reviewed by Codex `gpt-6-astra` and then
by `judge-fable`, which rules CONFIRMED or REJECTED on every Codex finding in the
same pass.
```

Replace the whole paragraph that begins `**Cross-family review.** On a risk-3 task one of the three judges is Codex, and` — through its last line, `instead of a silently missing seat.` — with:

```markdown
**Cross-family review.** Codex is the default task reviewer: `gpt-5.6-sol` for
tasks totalling 0 to 3, `gpt-6-astra` for 4 to 6, and Astra followed by
`judge-fable` at risk 2 or above. A task the executor lane implemented is always
reviewed by a Claude judge, so Codex never reviews its own work there; when a
Codex seat produces nothing, `judge-sonnet-high`, `judge-opus` or `judge-fable`
takes it by score band. Plan review takes Astra for round 1 and `judge-opus` for
delta rounds 2 and 3. The final whole-branch review gains a Codex round whose
findings are deduped with the Claude reviewer's and then verified by
`judge-fable` - or `judge-opus` when Fable is unavailable. That round is not
self-review-free, because the branch contains whatever the executor lane
produced, which is why every finding goes through a third seat.
`scripts/review-route` prints the review seat for a task or plan round, and
every Codex seat runs through `scripts/run-codex-review.sh`, which checks
availability on each run and falls back to `gpt-5.6-sol` whenever the local
model catalog does not advertise Astra. Selection, the run bound and the four
outcomes live in those scripts rather than in prose, so a refused model is a
recorded substitution instead of a silently missing seat.

**The Codex session gate.** Before any Codex use, `scripts/codex-gate` checks the official codex plugin
once per session - enabled, installed at an allowed version, logged in, and
within quota - through the plugin's own client, and caches the answer per
session. When Codex is unusable, every Codex seat, the final-review Codex round,
the executor lane and `plan-lint`'s lane probe are skipped for the session and
Claude seats take over; a quota error mid-run turns Codex off the same way. A
usable Codex is still used only on a surface whose shipping gate passed,
recorded per surface in `reference/codex-plugin.json`: the calibration replay
opens the review seats, and the executor-lane smoke test opens the lane.
```

Replace

```markdown
`scripts/run-codex-review.sh` runs one Codex review seat for both of them: it
```

with

```markdown
`scripts/run-codex-review.sh` runs every Codex review seat: it
```

Replace

```markdown
review and `codex-review-schema.json` for the risk-3 Codex seat; `criteria/TEMPLATE.md` documents the format.
```

with

```markdown
review, `codex-review-schema.json` for the Codex task seats, and
`codex-plan-review-schema.json` for the Codex plan-review round;
`criteria/TEMPLATE.md` documents the format.
```

- [ ] **Step 4: Bump both manifests**

In `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json`, replace `"version": "1.8.0",` with `"version": "1.9.0",`.

- [ ] **Step 5: Amend the program design**

In `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`, insert this paragraph, preceded by one blank line, immediately after the line ``Details: `docs/superpowers/specs/2026-09-14-dr-superpowers-judge-seats-design.md`.`` and before `## 7. Verification (every sub-project)`:

```markdown
**Amendment 2026-09-15 (sub-project 8 spec).** The decomposition gains an eighth
sub-project, "Review routing", after Codex judge seats. Per-task review moves to
Codex by default — `gpt-5.6-sol / high` for totals 0-3, `gpt-6-astra / high` for
4-6 — with Claude judges as named fallbacks (`judge-sonnet-high`, new;
`judge-opus`; `judge-fable`) on a Codex seat that produced nothing. A task
carrying an `**Executor:**` line is always reviewed by Claude, so Codex never
reviews its own work. Risk >= 2 is reviewed by Astra and then by Fable, which
rules on Astra's findings in the same pass; this replaces the three-seat risk-3
mean, and the `risk3-spread` ruling kind is retired. Plan review takes Codex
Astra for round 1 and `judge-opus` for delta rounds 2 and 3; rounds are not cut.
A new `scripts/review-route` holds the routing table; `run-codex-review.sh`
gains `--kind task|plan` and `--tier light|heavy`; `plan-lint` gains a lazy lane
probe with `--no-probe`. Shipping is gated on a calibration replay of four
recorded plan reviews and one real executor-lane smoke run.
A session gate (`scripts/codex-gate`) reads the official codex plugin's install
state and account rate limits through the plugin's own client, overturning the
2026-09-14 ruling that the plugin is not the substrate; when Codex is unusable,
every Codex seat, the lane and the lane probe are skipped for the session and
Claude seats take over; a usable Codex is still used only on a surface whose
shipping gate passed - calibration for the review seats, the smoke test for the
lane. The shipping gates run only when Codex is usable and record `PENDING`
otherwise.
A ninth sub-project, "Codex through the plugin", moves `run-codex-review.sh`,
`run-codex-task.sh` and the executor roster onto the plugin's client. Details:
`docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md` (§15).
```

The paragraph is spec §14's amendment as committed in `18a00a7`, unquoted and re-wrapped.

- [ ] **Step 6: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: the summary line ends `0 failed`.

- [ ] **Step 7: Run the whole verification**

Run from the repository root, each bounded:

```bash
timeout 60 node scripts/validate-repository.mjs
timeout 1800 node scripts/test-all.mjs
timeout 120 claude plugin validate .
for d in plugins/dr-status plugins/dr-superpowers plugins/dcc-darkraise-ui plugins/dcc-darkraise-win32ui; do timeout 120 claude plugin validate "$d"; done
```

Expected: the validator prints `Repository catalogs, manifests, versions, and bundled links are valid.`; `test-all.mjs` fails only on `tests/ui-discovery.test.mjs` with `bash: rg: command not found` (pre-existing), and every `plugins/dr-superpowers/tests/*.test.sh` summary ends `0 failed`; every `claude plugin validate` reports success. Afterwards, `git worktree list` shows no worktree this plan created, and no process started by these commands is still running.

- [ ] **Step 8: Commit**

```bash
git add plugins/dr-superpowers/README.md plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "chore(superpowers): bump to 1.9.0"
```
