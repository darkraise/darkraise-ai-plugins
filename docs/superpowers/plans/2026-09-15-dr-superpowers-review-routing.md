# dr-superpowers Review Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Codex the default task reviewer and plan-review round-1 seat with named Claude fallbacks, route risk >= 2 through Astra then Fable, retire `risk3-spread`, and put the routing table in a tested script.

**Architecture:** A new pure script `scripts/review-route` maps a plan's `**Evaluation:**` and `**Executor:**` lines (or a plan-review round) to a seat and its fallback. `scripts/run-codex-review.sh` gains `--kind task|plan` and `--tier light|heavy` and stays the only availability check. Skill and reference prose then call those two scripts; `plan-lint` gains a lazy lane probe. Two gates — a calibration replay and a real executor-lane smoke run — produce the evidence tests cannot.

**Tech Stack:** Bash, `jq`, coreutils `timeout`, Markdown, git, the `codex` CLI (Tasks 6 and 11 only).

**Spec:** `docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md`

**Execution:** inline — `claude --model opus --effort low` — every task totals 4 or less and none is at risk 3; Tasks 2, 5, 7 and 10 are the 4s, so the model follows them into the Opus-low band. Tasks 6 and 11 run Codex as background Bash calls, which the main session can await.

**Program:** `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` — sub-project 8 of 8 — last

**Plan review:** 2026-09-15 — dr-superpowers:judge-fable — executability 18 / coherence 18 / coverage 18 / assumptions 17 (round 3)

## Global Constraints

- Plugin version stays `1.8.0` until Task 13, which sets `1.9.0` on both `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json`. The two must stay equal.
- Not modified by any task: `reference/codex-routing.json`, `reference/native-codex.md`, `scripts/run-codex-task.sh`, `scripts/detect-executors.sh`, every fenced block in `reference/ladder.md`, `reference/final-review.md`, and the ruling-seat, final-verify and spec-review seats.
- `run-codex-review.sh --kind risk3` and `--kind final` keep their exact current behaviour, status line, exit codes and argv.
- English only, in every file: code, comments, docs, commits, tests.
- Commits follow `<type>(<scope>): <subject>`, subject 50 characters or fewer, imperative, no trailing period. The scope is `superpowers`.
- New scripts and test suites are mode `100755` in the index. `git config core.filemode` is `false` on this machine, so `chmod +x` does not reach the index: run `git update-index --chmod=+x <path>` after `git add`.
- Agent files are ASCII only (`tests/fleet.test.sh` checks it): no em dashes in `agents/*.md`.
- No file under a plugin may contain `superpowers:` without the `dr-` prefix, or `dcc-superpower-companions:` (`scripts/validate-repository.mjs:85`).
- Only Tasks 6 and 11 call Codex. Every test runs against stubs.
- Never commit `.superpowers/`. Never touch the untracked `plugins/darkmem-resume/`.
- Every command in every step runs from the repository root: `bash plugins/dr-superpowers/tests/…`, `node scripts/validate-repository.mjs`, `git …`. Prose written into skill files says `scripts/…` because a skill runs its scripts from the plugin root; that is text to write, not a command to run now.

## Contracts

Paths are repository-relative unless a step says otherwise. `P` in test suites is the plugin root.

**Files this plan creates**

| Path | Produced by |
|---|---|
| `plugins/dr-superpowers/criteria/codex-plan-review-schema.json` | Task 1 |
| `plugins/dr-superpowers/agents/judge-sonnet-high.md` | Task 3 |
| `plugins/dr-superpowers/scripts/review-route` | Task 4 |
| `plugins/dr-superpowers/tests/review-route.test.sh` | Task 4, extended by Tasks 5, 7, 8, 9, 13 |
| `docs/superpowers/notes/2026-09-15-review-routing-calibration.md` | Task 6, extended by Task 11 |
| `docs/superpowers/distilled/constraints.md` | Task 12 |

**`scripts/run-codex-review.sh` interface** (Task 2; consumed by Tasks 5, 6, 7, 9):

```
run-codex-review.sh --kind task|risk3|plan|final --cwd <dir> --out <path>
                    (--prompt <file> | --base <ref>) [--tier light|heavy] [--dry-run]
```

- `task` and `risk3` are one kind: `--prompt` required, schema `criteria/codex-review-schema.json`, valid output has `spec_verdict`, `task_quality`, `cannot_verify`.
- `plan`: `--prompt` required, schema `criteria/codex-plan-review-schema.json`, valid output has `executability`, `coherence`, `coverage`, `assumptions`, `findings`.
- `final`: `--base` required, unchanged.
- `--tier` is accepted only with `task`/`risk3`; default `heavy`. `light` runs the `codex-judge` block's last row (`gpt-5.6-sol high`) and never falls back. `heavy` is the existing selection: first row if advertised, else last row, plus one fallback on refusal.
- Status line, exit codes (0 `OK`/`FALLBACK`, 1 `TIMEOUT`/`FAILED`, 2 usage) unchanged: `codex-judge <model>/<effort> status=<S> exit=<n> out=<path> evidence=<fetched_at|unknown>`.

**`criteria/codex-plan-review-schema.json` fields** (Task 1): integers 1-20 `executability`, `coherence`, `coverage`, `assumptions`; `findings` array of `{severity: Critical|Important|Minor, where: string, summary: string}`; every object `additionalProperties: false` with every property required.

**`scripts/review-route` interface** (Task 4; consumed by Tasks 5, 7, 9):

```
review-route PLAN_FILE --task <id> [<id> ...]
review-route PLAN_FILE --plan-round <r>
```

`<id>` is `N` or `N` plus a part letter (`7B`). Output, exit 0, exactly one line:

```
review-seat <scope> primary=<seat> fallback=<seat|-> reason=<executor|risk|band|round>
```

`<scope>` is `task=<ids joined by commas>` or `plan-round=<r>`. Seat names: `codex:light`, `codex:heavy`, `codex:heavy+judge-fable`, `codex:plan`, `dr-superpowers:judge-sonnet-high`, `dr-superpowers:judge-opus`, `dr-superpowers:judge-fable`. Routing, first match wins, on the highest total and highest risk across the ids and every Evaluation line inside them: Executor and risk >= 2 → `judge-fable`, fallback `-`, `executor`; Executor → band judge, fallback `-`, `executor`; risk >= 2 → `codex:heavy+judge-fable`, fallback `judge-fable`, `risk`; total <= 3 → `codex:light`, fallback band judge, `band`; else `codex:heavy`, fallback band judge, `band`. Band judge: total <= 1 `judge-sonnet-high`, <= 4 `judge-opus`, else `judge-fable`. Plan round 1 → `codex:plan`, fallback `dr-superpowers:judge-fable`, `round`; round >= 2 → `dr-superpowers:judge-opus`, fallback `-`, `round`. Exit 2 with a `review-route: …` message on stderr for usage errors, a missing plan, an unknown task or part, a missing or unparseable Evaluation line, or a `Host: codex` plan.

**`plan-lint` interface** (Task 10): `plan-lint PLAN_FILE [--amendments FILE] [--no-probe]`, flags in any order. Roster command `bash "${PLAN_LINT_ROSTER:-<scripts>/detect-executors.sh}"` under `timeout 30`, run at most once, only for a non-inline Claude-host plan with at least one lane candidate and no `--no-probe`. Warning text: `WARN <Task N|Task N part X>: lane-eligible with no **Executor:** line (codex <model> / <effort>)`.

**Agents** (Task 3): `dr-superpowers:judge-sonnet-high` (Sonnet 5, high); `dr-superpowers:judge-opus` unchanged except its description.

**Workspace artefacts** (named in prose by Tasks 5 and 7, all under `<workspace>` = the directory `scripts/sdd-workspace PLAN_FILE` prints): `plan-round-<r>.md`, `plan-review-prompt.md`, `plan-review-round-<r>.json` (Codex) or `.md` (Claude), `plan-delta-<r>.diff`, `task-<N>-review-codex-prompt.md`, `task-<N>-review-codex.json`.

**Prompt placeholders** (Tasks 5 and 7): `[DELTA_FILE]`, `[PRIOR_FINDINGS_FILE]`, `[ROUND]` in the plan-review delta template; `[CODEX_REVIEW_FILE]` in the task reviewer's Second Pass section.

**Ledger seat clause** (Task 7): inside the complete line's scores clause, `, seat <seat>` where `<seat>` is `codex <model>/<effort>`, `codex <model>/<effort>+judge-fable`, or a judge's short name, followed by ` (codex <STATUS> — <reason>)` when it replaced a Codex seat. It replaces `, K=3`.

**Test-suite helpers.** `tests/review-route.test.sh` (Task 4) defines `P`, `check`, `present`, `absent`, and `route`. Tasks 5, 7, 8, 9 and 13 append blocks that call `present` and `absent` immediately before its final `printf '\n%d passed, %d failed\n'` line. `absent` is defined by Task 4 and first called by Task 5 — Task 4 keeps it although Task 4 itself never calls it.

## Assumptions (evidence)

- Codex is usable here: `bash plugins/dr-superpowers/scripts/detect-executors.sh` on 2026-09-15 reported the codex row `usable: true`, `reason: null`, with 12 advertised `gpt-5.6-sol`/`gpt-6-astra` pairs; CLI 0.154.0 and a 2.0s detector run are recorded in `.superpowers/handoff/latest.md` (2026-09-15).
- No existing `tests/plan-lint.test.sh` fixture contains a lane candidate (Claude plan, no Override, Rule S clean, total >= 2, risk <= 1, no Executor): read 2026-09-15, `tests/plan-lint.test.sh:30-307` — Task 1 totals 1, Task 2 carries risk 2, and every variant that raises a total also raises risk or breaks Rule S. Existing cases therefore never reach the probe.
- `reference/ladder.md`'s `assignment` block maps total 2 to `impl-sonnet-medium` and its `codex-assignment` block maps total 2 to `gpt-5.5 medium` (`reference/ladder.md:67,215`, read 2026-09-15); Task 10's `p1`-`p3` fixtures and its expected WARN text depend on both.
- `scripts/plan-amend:76-77` is the only script that runs `plan-lint`, and it reads only `ERROR` lines — grep 2026-09-15.
- `scripts/validate-repository.mjs:98-105` resolves every `dr-superpowers:<name>` in plugin files to a skill directory or an `agents/<name>.md`; hence Task 3 precedes the first file naming `judge-sonnet-high`.
- `scripts/test-all.mjs` runs every `plugins/dr-superpowers/tests/*.test.sh` with a 300-second bound (its `jobs` array) — read 2026-09-15. `tests/ui-discovery.test.mjs` fails on this machine with `bash: rg: command not found`, pre-existing — verified 2026-09-14.
- `tests/fleet.test.sh:36` pins the exact agent list (19 names) and, for `judge-*`, requires the tools `Read, Grep, Glob, WebFetch`, effort `high` or `medium`, no `skills:`, ASCII only — read 2026-09-15.
- `tests/codex-review.test.sh:248-252` pins the SDD needles `run-codex-review.sh`, `TIMEOUT or FAILED` and `never re-dispatch the Codex seat`; `tests/inline-mode.test.sh:82` pins `no task reviewer` in `skills/executing-plans/SKILL.md`. Tasks 7 and 8 keep all four.
- `tests/criteria.test.sh` loops only over `criteria/*.md`, so a new JSON file needs its own checks — read 2026-09-15, `tests/criteria.test.sh:25`.
- The SDD complete-line marker `, K=3` is parsed by no script: grep of `plugins/dr-superpowers` on 2026-09-15 found it only in `skills/subagent-driven-development/SKILL.md:279,696`.
- Replay copies keep only fixture `**Plan review:**` lines: `git show <sha>:<plan> | grep -c '^\*\*Plan review:\*\*'` on 2026-09-15 printed 0 for `d6c288c` (project-state), 1 for `01f5a2a` and `69c6b48`, and 3 for `5e96f14`; after the Task 6 `awk` filter the counts were 0, 0, 0 and 2.
- Calibration inputs exist: `git cat-file -e` on 2026-09-15 succeeded for `d6c288c`, `01f5a2a`, `69c6b48`, `5e96f14` with their plan and spec paths (Task 6 table). `git show e3506c4` shows round 3's fixes to `d6c288c`: the Task 3 `absent` helper contract and the needles `"CLAUDE.md"`, `"optional"`, `'seven'`, `'exit 0'`.
- Plans are uncommitted until the handoff (`skills/writing-plans/SKILL.md`, Execution Handoff), so a plan-review delta needs a snapshot, not git.
- A background Bash call is not bound by the tool's 10-minute `timeout` — measured and recorded in `reference/external-executor.md` §Dispatch.
- `.superpowers/` is git-ignored (`.gitignore:15`), so the smoke worktree and its report can live under it.
- `run-codex-task.sh` takes a JSON array of unique non-empty paths as `--write-set` (`scripts/lib/task-state.sh:48`), requires a clean index and worktree with no untracked files on an initial run (`scripts/lib/task-state.sh:130`), accepts a report path outside `--cwd` and rejects one inside it unless it is under an ignored `.superpowers/` (`scripts/run-codex-task.sh:150-154`), and composes the commit subject from the report's `commit_subject` field (`scripts/run-codex-task.sh:369,380`) — read 2026-09-15.
- Three details were settled during planning and recorded in the spec (§3, §8) in the same commit as this plan: `review-route` prints `reason=round` for plan rounds (spec §3 lists only the task reasons); writing-plans sends a `review-route` exit 2 on a Codex-host plan to the native judge rather than `judge-fable`, because a Codex host has no Claude judge (spec §2 keeps native hosts untouched); and the `plan-lint` probe skips inline plans, where Executor lines are inert (`skills/writing-plans/SKILL.md:245`).
- The distilled entry format — an H1, a one-line statement, `## <area>` sections of `### <entry>` blocks, and for `constraints.md` the fields `Set by`, `Scope`, `Source` — is fixed by `skills/distilling-docs/SKILL.md:17-21` (read 2026-09-15); Task 12's entry follows it.
- The spec is committed (`155fc23`, 2026-09-15), so Task 12's `git log -1 --format=%h -- <spec>` yields a sha.
- This plan carries no `**Executor:**` lines: its Execution line is inline, under which they are inert (`skills/writing-plans/SKILL.md`, Assign an implementer).
- Unverified — Task 6 verifies it: that `codex exec --output-schema criteria/codex-plan-review-schema.json` is accepted and that an Astra plan review finishes inside the runner's 1800-second bound.
- Unverified — Task 11 verifies it: that `run-codex-task.sh`, last exercised on CLI 0.153.4, completes a run on CLI 0.154.0.

## Task index

1. The Codex plan-review schema
2. The review runner's task and plan kinds
3. Judge agents for the tier seats
4. The review-route script
5. Plan review rounds in writing-plans
6. Calibration gate
7. Task review routing in subagent-driven-development
8. Retire risk3-spread
9. The external-executor lane prose
10. The lazy lane probe in plan-lint
11. Smoke-test gate
12. The lane declared on for this repository
13. README, version, and the program amendment

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

### Task 6: Calibration gate

**Files:**
- Create: `docs/superpowers/notes/2026-09-15-review-routing-calibration.md`

**Interfaces:**
- Consumes: `run-codex-review.sh --kind plan` (Task 2), the Round 1 on Codex prompt (Task 5).
- Produces: the calibration notes file (Contracts), extended by Task 11.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2

This task makes four paid Codex runs on the ChatGPT subscription — up to eight
if Step 3 retries — and no Claude dispatch. Run every command from the
repository root.

| Name | Commit | Plan path | Spec path | Recorded e / c / v / a |
|---|---|---|---|---|
| `project-state` | `d6c288c` | `docs/superpowers/plans/2026-09-14-dr-superpowers-project-state.md` | `docs/superpowers/specs/2026-09-14-dr-superpowers-project-state-design.md` | 17 / 16 / 17 / 16 |
| `judge-seats` | `01f5a2a` | `docs/superpowers/plans/2026-09-14-dr-superpowers-judge-seats.md` | `docs/superpowers/specs/2026-09-14-dr-superpowers-judge-seats-design.md` | 17 / 18 / 16 / 16 |
| `inline-mode` | `69c6b48` | `docs/superpowers/plans/2026-09-12-dr-superpowers-inline-mode.md` | `docs/superpowers/specs/2026-09-12-dr-superpowers-inline-mode-design.md` | 17 / 18 / 14 / 16 |
| `small-model` | `5e96f14` | `docs/superpowers/plans/2026-09-12-dr-superpowers-small-model-planning.md` | `docs/superpowers/specs/2026-09-12-dr-superpowers-small-model-planning-design.md` | 17 / 17 / 16 / 17 |

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

`docs/superpowers/notes/` does not exist yet: run `mkdir -p docs/superpowers/notes` first. Then create `docs/superpowers/notes/2026-09-15-review-routing-calibration.md` with the actual values filled in from Steps 3-5:

```markdown
# Review routing — calibration and smoke results

Spec: `docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md` §11.
Run: <YYYY-MM-DD>, Codex CLI <version from `codex --version`>.

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

Commit either way:

```bash
git add docs/superpowers/notes/2026-09-15-review-routing-calibration.md
git commit -m "docs(superpowers): record review calibration"
```

On FAIL, stop the plan here: write the ledger line `Task 6: BLOCKED — calibration gate failed — <rows not within and defects not found>; the owner decides whether Codex takes plan-review round 1`, and report it to your human partner, quoting the defect findings verbatim rather than only found or not found. Do not start Task 7.

- [ ] **Step 7: Remove the replay inputs**

```bash
rm -rf "$(git rev-parse --show-toplevel)/.superpowers/calibration-review-routing"
```

Expected: no output.

### Task 7: Task review routing in subagent-driven-development

**Files:**
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` (Seats table row, the Ledger grammar, §3 Review the task, §5 Complete the task)
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/references/task-reviewer-prompt.md`
- Modify: `plugins/dr-superpowers/tests/review-route.test.sh` (append a block)

**Interfaces:**
- Consumes: `review-route --task` (Task 4), `run-codex-review.sh --kind task --tier` (Task 2), the test-suite helpers (Task 4) — all in Contracts.
- Produces: the `[CODEX_REVIEW_FILE]` placeholder and the ledger seat clause (Contracts); the section name `§Codex task review seats` that Task 9 creates in `reference/external-executor.md`.

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
- **The seat:** run `scripts/review-route PLAN_FILE --task <N>` (all of a
  batch's task numbers for a batch) and review with the `primary` it prints.
  A judge seat gets [task-reviewer-prompt.md](references/task-reviewer-prompt.md)
  with `[PLUGIN_ROOT]` expanded to this plugin's resolved directory; a Codex
  seat is run as below. If `review-route` exits 2, review with
  `dr-superpowers:judge-fable` and say why, quoting its message.
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
fallback, so a second attempt here would turn one refused run into two. Read a
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
  ` (codex <STATUS> — <reason>)` when it replaced a Codex seat
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
Expected: both summaries end `0 failed`; the validator prints `Repository catalogs, manifests, versions, and bundled links are valid.` — the `§Codex task review seats` link target file already exists, and Task 9 adds the section.

- [ ] **Step 8: Commit**

```bash
git add plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md plugins/dr-superpowers/skills/subagent-driven-development/references/task-reviewer-prompt.md plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "feat(superpowers): route task reviews through Codex"
```

### Task 8: Retire risk3-spread

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

### Task 9: The external-executor lane prose

**Files:**
- Modify: `plugins/dr-superpowers/reference/external-executor.md` (§Planning, §Dispatch step 4, §Risk-3 Codex seat, §Final-review Codex round)
- Modify: `plugins/dr-superpowers/reference/ladder.md` (the prose paragraph above the `codex-judge` block)
- Modify: `plugins/dr-superpowers/tests/review-route.test.sh` (append a block)

**Interfaces:**
- Consumes: `run-codex-review.sh --tier` (Task 2), `review-route --task` (Task 4), the Second Pass section (Task 7), the test-suite helpers (Task 4).
- Produces: the section `## Codex task review seats`, which Task 7's link targets; the Planning rule that reads `docs/superpowers/distilled/constraints.md`, which Task 12 writes.

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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: `FAIL - the lane reference has the task seats section` among others.

- [ ] **Step 3: Edit §Planning and §Dispatch**

In `plugins/dr-superpowers/reference/external-executor.md`, replace the line

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

The runner establishes usability from the roster itself and never trusts the
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

- [ ] **Step 5: Edit §Final-review Codex round**

In the same file, replace

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

### Task 10: The lazy lane probe in plan-lint

**Files:**
- Modify: `plugins/dr-superpowers/scripts/plan-lint:7-27` (usage and argument parsing), `:138` (candidate list), `:214-222` (candidate collection), before `:233` (the probe)
- Modify: `plugins/dr-superpowers/scripts/plan-amend:76-77`
- Modify: `plugins/dr-superpowers/tests/plan-lint.test.sh`

**Interfaces:**
- Consumes: `reference/ladder.md`'s `gate` and `codex-assignment` blocks through `ladder_block` (existing).
- Produces: the `plan-lint` interface in Contracts.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/plan-lint.test.sh`, insert immediately after the line `printf '# Program\n' > docs/program.md`:

```bash
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
Expected: FAIL lines for `usable codex: an eligible task without Executor warns`, `usable codex: the probe runs once`, `unusable codex: the probe still ran once`, `flags parse in any order` (today's parser exits 2 on `--no-probe`) and `plan-amend never probes`. The `--no-probe` and no-candidate cases pass already, because nothing probes yet.

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
# when some task could have taken the lane and did not. A plan without Executor
# lines is correct on a machine where Codex is unusable, so every outcome other
# than a usable codex row prints nothing. Inline plans are skipped: Executor
# lines are inert under inline execution, so the warning would be noise.
if [ -n "$lane" ] && [ "$probe" -eq 1 ] && [ "$mode" != inline ]; then
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

Run: `bash plugins/dr-superpowers/tests/plan-lint.test.sh && bash plugins/dr-superpowers/tests/plan-amend.test.sh`
Expected: both summaries end `0 failed`, including every pre-existing case (`clean Claude plan: summary` still `plan-lint: 0 errors, 1 warnings`).

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/scripts/plan-lint plugins/dr-superpowers/scripts/plan-amend plugins/dr-superpowers/tests/plan-lint.test.sh
git commit -m "feat(superpowers): add a lazy lane probe to plan-lint"
```

### Task 11: Smoke-test gate

**Files:**
- Modify: `docs/superpowers/notes/2026-09-15-review-routing-calibration.md` (append a section)

**Interfaces:**
- Consumes: the notes file (Task 6).
- Produces: nothing later tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 1 - coupling 0 - risk 0 = 1

This task makes one paid Codex run. Run every command from the repository root.

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

- [ ] **Step 3: Verify the result**

```bash
root=$(git rev-parse --show-toplevel)
smoke="$root/.superpowers/smoke-review-routing"
range=<the a7..b7 value of the status line's commits= field>
git -C "$smoke/wt" rev-list --count "$range"
git -C "$smoke/wt" log --oneline -1
cat "$smoke/wt/smoke.txt"
git -C "$smoke/wt" status --porcelain
codex --version
```

Expected: `rev-list --count` prints `1`; the log line shows the commit (its subject is recorded, ideally `test(superpowers): add codex smoke file`); `smoke.txt` prints `codex lane smoke test`; `status --porcelain` prints nothing; `codex --version` prints the CLI version.

- [ ] **Step 4: Record and apply the gate**

Append to `docs/superpowers/notes/2026-09-15-review-routing-calibration.md`, with the actual values:

```markdown

## Smoke test

Run: <YYYY-MM-DD>, Codex CLI <version>, `gpt-5.5 / medium`, disposable linked worktree.

- Status line: `<the wrapper's status line>`
- Wrapper exit: <n>
- Commit: `<the log line from Step 3>`
- File content correct: yes / no

Gate: PASS / FAIL — <one line>
```

The gate passes only on `status=DONE`, wrapper exit 0, exactly one new commit, the exact file content, and a clean worktree. The commit subject is recorded, not gated: the wrapper takes it from Codex's structured report, so a paraphrase says nothing about whether the lane works. An `exit=2` inside the status line is a wrapper/CLI disagreement: quote the report's stderr tail in the notes.

Commit either way:

```bash
git add docs/superpowers/notes/2026-09-15-review-routing-calibration.md
git commit -m "docs(superpowers): record the codex lane smoke test"
```

On FAIL, stop the plan here: keep the worktree for inspection, write the ledger line `Task 11: BLOCKED — smoke test failed — <status line>; the owner decides whether the lane is trusted`, and report it to your human partner. Do not start Task 12.

- [ ] **Step 5: Remove the disposable worktree**

Only after a PASS:

```bash
root=$(git rev-parse --show-toplevel)
git worktree remove --force "$root/.superpowers/smoke-review-routing/wt"
rm -rf "$root/.superpowers/smoke-review-routing"
git worktree list
```

Expected: `git worktree list` no longer shows `smoke-review-routing`.

### Task 12: The lane declared on for this repository

**Files:**
- Create: `docs/superpowers/distilled/constraints.md`
- Modify: `plugins/dr-superpowers/reference/project-state.md` (Who writes what table; What never happens to these files)
- Modify: `plugins/dr-superpowers/tests/project-status.test.sh` (insert before the final `printf`)

**Interfaces:**
- Consumes: the Planning rule in `reference/external-executor.md` (Task 9), which reads this file.
- Produces: nothing later tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/project-status.test.sh`, insert immediately before the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"`:

```bash
# An approved spec's owner decision may land in constraints.md by hand; the
# writer rule must say so, or the first such entry breaks it. The last four
# checks read this repository's own docs tree, not a plugin file.
present "project-state allows an owner-decision entry" "$STATE" "a human may add an entry that an approved spec's owner decisions"
present "project-state names writing-plans as a constraints reader" "$STATE" '`constraints.md` also dr-superpowers:writing-plans'
CONSTRAINTS="$P/../../docs/superpowers/distilled/constraints.md"
check "exists: docs/superpowers/distilled/constraints.md" \
  "$([ -f "$CONSTRAINTS" ] && echo yes || echo no)" "yes"
present "the Codex lane is declared on" "$CONSTRAINTS" "### The Codex executor lane is on"
present "the lane entry cites the review-routing spec" "$CONSTRAINTS" "Source: docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md@"
present "the lane entry records who set it" "$CONSTRAINTS" "Set by: owner"
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
When \`scripts/detect-executors.sh\` reports Codex usable, the planner ticks \`codex\` without asking and gives every task that passes the lane gate an \`**Executor:**\` line.
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

### Task 13: README, version, and the program amendment

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
recorded plan reviews and one real executor-lane smoke run. Details:
`docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md`.
```

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
