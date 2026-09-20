# Codex session budget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure a Codex session's context from its rollout and report it in the budget line, collecting the per-task growth data that a later phase needs to set a real budget.

**Architecture:** All measurement lands in `scripts/lib/context.sh`, which every consumer already reaches through `ctx_line`. Two new resolvers (a Codex rollout, the existing Claude transcript) run independently and the more recently written file wins; a Codex measurement prints its number with an `unknown` verdict and exit 3, so the count rule stays in charge. Each successful Codex measurement appends a row to a self-ignoring log that a new `--observations` mode reads back as per-task deltas.

**Tech Stack:** Bash (Git Bash on Windows), jq, awk, git plumbing. Tests are the repository's own `.test.sh` harness run by `node scripts/test-all.mjs`.

**Spec:** `docs/superpowers/specs/2026-09-20-dr-superpowers-codex-budget-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — one task is heavy and two are four-band, so the session implements Tasks 1, 5 and 6 itself and delegates Tasks 2, 3 and 4

**Plan review:** 2026-09-20 — dr-superpowers:judge-opus — executability 18 / coherence 18 / coverage 17 / assumptions 16 (round 3)

## Global Constraints

- English only: code, comments, docs, commits, tests.
- Every script runs under Git Bash on Windows. `rg` is not on PATH; use `grep`.
- Call jq only through the existing `ctx_jq` wrapper, which honours `DR_SUPERPOWERS_JQ`.
- A schema surprise degrades the budget line to `unknown`. Never print a number the data does not support, and never let a parse failure abort the caller.
- No Claude-host behaviour changes: every existing assertion in `tests/context-size.test.sh` and `tests/budget-line.test.sh` must still pass unchanged.
- `scripts/lib/context.sh` is sourced by a caller running `set -uo pipefail` and no `set -e`. Functions return status; they never `exit`.
- Every test must be bounded and must leave no process running.
- Commit each task separately with a `<type>(<scope>): <subject>` subject of 50 characters or less.

## Contracts

Names one task produces and another consumes, stated once:

- `ctx_rollout_reduce` — stdin filter, prints the context size or nothing. Task 1 produces.
- `ctx_measure_rollout FILE` — prints the context size, returns 1 when the file carries none. Task 1 produces; Task 3 consumes.
- `ctx_rollout_files DIR` — prints rollout paths newest-first. Task 2 produces.
- `ctx_find_rollout` — sets `CTX_ROLLOUT` to this session's rollout path, returns 1 when none matches. Task 2 produces; Tasks 3 and 4 consume.
- `CTX_ROLLOUT_SCAN` — integer, `40`, the file bound. Task 2 produces.
- `ctx_primary_root` — prints the primary checkout's root, returns 1 outside a repository. Task 4 produces; Task 5 consumes.
- `ctx_log_observation TOKENS` — appends one row, never fails the caller. Task 4 produces; Task 3's rollout branch calls it.
- Log path: `<primary checkout>/.superpowers/sdd/budget-log.tsv`. Row: `<ISO-8601 UTC>\t<tokens>\t<caller>\t<session id>`, tab-separated. Task 4 produces; Task 5 consumes.
- `DR_SUPERPOWERS_BUDGET_CALLER` values: `task-brief:<N>`, `task-brief:header`, `review-package`, unset meaning `direct`. Task 4 produces; Task 5 consumes.
- `ctx_observations` — prints the pair and span rows. Task 5 produces.
- `context-size --observations` — the CLI mode, exits 0. Task 5 produces; Task 6 documents.
- Test fixtures in `tests/context-size.test.sh`: `meta <cwd> [originator] [source]` and
  `usage_line <last> <total>` (Task 1), `REPO_NATIVE` (Task 2). The suite runs
  under `set -u` and each block appends below the last, so Tasks 3 and 4 use
  them exactly as Tasks 1 and 2 define them.
- Budget line forms, exactly:
  - `budget: <N>k measured — unknown — source: rollout`
  - `budget: unknown — unknown — no usage entry in <path>`
  Task 3 produces; Task 6 documents.

## Assumptions (evidence)

- Codex records the context size as `payload.info.last_token_usage.input_tokens` in an `event_msg` entry whose `payload.type` is `token_count`. Verified 2026-09-20 against `~/.codex/sessions/2026/09/`: the series climbs and drops at each `compacted` record, while `total_token_usage.input_tokens` accumulates to 28,023,960 in the same session. Spec §3.
- A rollout's first line is a `session_meta` entry carrying `session_id`, `cwd` and `source`; non-interactive runs add `originator: codex_exec` with `source: exec`, and interactive ones record `source` as `cli` or `vscode` with no `originator` key. Verified 2026-09-20 across the 25 newest rollouts on this machine. Spec §3.
- `.superpowers/sdd/` self-ignores because `scripts/sdd-workspace:41` writes `*` into its `.gitignore`; `scripts/lib/task-state.sh:11` hashes untracked-but-not-ignored files into the review snapshot, which is why the log goes there. Verified 2026-09-20 by reading both files.
- `scripts/task-brief:87` calls `context-size` unconditionally, including in `--header` mode where its task number is empty (`scripts/task-brief:31`). Verified 2026-09-20 by reading the script.
- `scripts/lib/context.sh` has no `set -e`, so a failing command inside a function does not abort the caller. Verified 2026-09-20 by reading `scripts/context-size:7`.
- Codex stores rollouts under `${CODEX_HOME:-$HOME/.codex}/sessions`. `CODEX_HOME` honouring is unverified — the CLI documents the variable for profile configuration only. No task verifies it, deliberately: it is the search root alone, and when it is wrong the search finds nothing and the line reads `unknown`, which is the degradation the spec specifies. Verifying it would mean starting a Codex session under a moved `CODEX_HOME`, which costs more than the failure it would catch.

## Task index

1. Measure a rollout file
2. Find this session's rollout
3. Choose the host and print the line
4. Append the observation row
5. Read the observations back
6. Document the Codex budget line

---

### Task 1: Measure a rollout file

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/context.sh`
- Test: `plugins/dr-superpowers/tests/context-size.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `ctx_rollout_reduce`, `ctx_measure_rollout` — see Contracts.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/context-size.test.sh`, immediately above its final `printf '\n%d passed, %d failed\n'` line:

```bash
# --- Codex rollout measurement ---
# The context size is the last token_count event's last_token_usage.input_tokens.
# A compaction is already reflected in it, so no boundary arithmetic applies,
# and total_token_usage is a cumulative counter that must never be read.
. "$HERE/../scripts/lib/context.sh"

meta() { # meta <cwd> [originator] [source]
  # Built with jq, never printf: a native Windows cwd carries single
  # backslashes, and pasting one into a JSON string produces invalid escapes
  # (`\U`, `\A`) that jq then refuses. That would leave `.payload.cwd` empty and
  # make every discovery test pass or fail for the wrong reason.
  # MSYS_NO_PATHCONV=1 is already exported above, which keeps --arg opaque.
  ctx_jq -c -n --arg cwd "$1" --arg orig "${2:-}" --arg src "${3:-cli}" \
    '{timestamp:"2026-09-15T14:52:58.691Z",ordinal:0,type:"session_meta",
      payload:({session_id:"01a0a58e-8e6c-72b0-92a3-b1586a8ca0ec",cwd:$cwd,
                source:$src,cli_version:"0.154.0",model_provider:"openai"}
               + (if $orig == "" then {} else {originator:$orig} end))}'
}
usage_line() { # usage_line <last_input_tokens> <total_input_tokens>
  printf '{"timestamp":"2026-09-15T14:53:06.085Z","ordinal":10,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":%s,"cached_input_tokens":0,"output_tokens":7,"total_tokens":%s},"last_token_usage":{"input_tokens":%s,"cached_input_tokens":0,"output_tokens":7,"total_tokens":%s}}}}\n' \
    "$2" "$2" "$1" "$1"
}
null_usage() { printf '{"timestamp":"2026-09-15T14:53:06.085Z","ordinal":9,"type":"event_msg","payload":{"type":"token_count","info":null}}\n'; }
compacted_line() { printf '{"timestamp":"2026-09-15T14:59:00.000Z","ordinal":20,"type":"compacted","payload":{"message":"","replacement_history":[{"type":"message","role":"user"}]}}\n'; }

ROLL="$TMP/roll.jsonl"
{ meta 'C:\x'; usage_line 19545 19545; usage_line 171517 400000; } > "$ROLL"
check "rollout: measures the last last_token_usage" "$(ctx_measure_rollout "$ROLL")" "171517"

{ meta 'C:\x'; usage_line 171517 400000; null_usage; } > "$ROLL"
check "rollout: skips a null info" "$(ctx_measure_rollout "$ROLL")" "171517"

{ meta 'C:\x'; usage_line 239510 900000; compacted_line; usage_line 51326 950000; } > "$ROLL"
check "rollout: takes the post-compaction reading" "$(ctx_measure_rollout "$ROLL")" "51326"

{ meta 'C:\x'; printf 'not json\n'; } > "$ROLL"
ctx_measure_rollout "$ROLL" >/dev/null 2>&1
check "rollout: a file with no usage returns 1" "$?" "1"

# The tail is read first because rollouts reach tens of megabytes; the
# whole-file fallback is what finds a reading that sits above it.
{ meta 'C:\x'; usage_line 88000 99000; } > "$ROLL"
i=0; while [ "$i" -lt 500 ]; do compacted_line >> "$ROLL"; i=$((i + 1)); done
check "rollout: falls back past a 400-line tail" "$(ctx_measure_rollout "$ROLL")" "88000"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/context-size.test.sh`
Expected: the five `rollout:` assertions FAIL with `ctx_measure_rollout: command not found` on stderr and empty `got:` values — except the `returns 1` assertion, which reports `got: [127]`.

- [ ] **Step 3: Write the implementation**

Append to `plugins/dr-superpowers/scripts/lib/context.sh`, directly below `ctx_model_window`:

```bash
# Codex rollout entries are one JSON object per line. The context size is the
# last token_count event's last_token_usage.input_tokens: it already reflects a
# compaction, so nothing here reads the compacted record, and total_token_usage
# is a cumulative counter (28 million in one observed session) that would read
# as a context size if taken by mistake. An entry whose info is null carries no
# usage and is skipped.
ctx_rollout_reduce() {
  tr -d '\r' | ctx_jq -R -r -n '
    [inputs | select(length > 0) | (try fromjson catch null) | objects
     | select(.type == "event_msg")
     | .payload | objects | select(.type == "token_count")
     | .info | objects
     | .last_token_usage | objects
     | .input_tokens | numbers]
    | last // empty' 2>/dev/null
}

# ctx_measure_rollout FILE — the context size, or nothing. Reads the tail first:
# rollouts reach tens of megabytes and one compacted entry embeds a whole
# replacement_history.
ctx_measure_rollout() {
  local out
  out=$(tail -n 400 "$1" | ctx_rollout_reduce)
  [ -n "$out" ] || out=$(ctx_rollout_reduce < "$1")
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/context-size.test.sh`
Expected: `0 failed`, including every pre-existing Claude assertion.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/context.sh plugins/dr-superpowers/tests/context-size.test.sh
git commit -m "feat(superpowers): measure a Codex rollout"
```

---

### Task 2: Find this session's rollout

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/context.sh`
- Modify: `plugins/dr-superpowers/tests/context-size.test.sh:31` (the `unset` line)
- Modify: `plugins/dr-superpowers/tests/budget-line.test.sh:28` (its own `unset` line)
- Modify: `plugins/dr-superpowers/tests/repo-audit.test.sh:26` (its own `unset` line)
- Test: `plugins/dr-superpowers/tests/context-size.test.sh`

**Interfaces:**
- Consumes: the test fixtures `meta` and `usage_line` — see Contracts.
- Produces: `ctx_rollout_files`, `ctx_find_rollout`, `CTX_ROLLOUT`, `CTX_ROLLOUT_SCAN`, and the test fixture `REPO_NATIVE` — see Contracts.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Guard the existing suites first**

In `plugins/dr-superpowers/tests/context-size.test.sh`, change:

```bash
unset DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR
```

to:

```bash
unset DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR CODEX_HOME
```

Make the same addition to the corresponding `unset` line in `plugins/dr-superpowers/tests/budget-line.test.sh` (line 28) and in `plugins/dr-superpowers/tests/repo-audit.test.sh` (line 26). All three suites already redirect `HOME` into a temporary directory, so with `CODEX_HOME` unset the search root becomes `$TMP/home/.codex`, which does not exist. Without this, a developer's real rollout tree enters the walk during a test run: it cannot produce a wrong assertion, because no real rollout names the temporary repository, but it costs a jq spawn per file on every `run`.

- [ ] **Step 2: Write the failing test**

Append to `plugins/dr-superpowers/tests/context-size.test.sh`, below Task 1's block:

```bash
# --- Codex rollout discovery ---
# Only an interactive rollout is a candidate: an executor-lane run started by a
# Claude controller records the controller's own cwd, and selecting it would
# strip that Claude session of its verdict.
export CODEX_HOME="$TMP/codex"
roll() { # roll <day> <name> <cwd> [originator] [source]
  mkdir -p "$CODEX_HOME/sessions/2026/09/$1"
  local f="$CODEX_HOME/sessions/2026/09/$1/rollout-$2.jsonl"
  { meta "$3" "${4:-}" "${5:-cli}"; usage_line 123456 999999; } > "$f"
  printf '%s' "$f"
}
REPO_NATIVE=$(native "$(cd "$REPO" && pwd)")

R1=$(roll 15 a "$REPO_NATIVE")
( cd "$REPO" && ctx_find_rollout && printf '%s' "$CTX_ROLLOUT" ) > "$TMP/found"
check "discovery: finds a matching interactive rollout" "$(cat "$TMP/found")" "$R1"

# The executor-lane rollout is NEWER (day 16) and names the same directory, so
# it wins on modification time and only the origin filter can reject it. This
# is the case that protects a live Claude controller's verdict.
roll 16 b "$REPO_NATIVE" codex_exec exec >/dev/null
( cd "$REPO" && ctx_find_rollout && printf '%s' "$CTX_ROLLOUT" ) > "$TMP/found2"
check "discovery: prefers the interactive rollout over a newer executor one" "$(cat "$TMP/found2")" "$R1"

rm -rf "$CODEX_HOME"
roll 15 c "$REPO_NATIVE" codex_exec exec >/dev/null
( cd "$REPO" && ctx_find_rollout ) >/dev/null 2>&1
check "discovery: an executor-lane rollout alone is no match" "$?" "1"

rm -rf "$CODEX_HOME"
roll 15 d 'C:\somewhere\else' >/dev/null
( cd "$REPO" && ctx_find_rollout ) >/dev/null 2>&1
check "discovery: skips a rollout for another directory" "$?" "1"

rm -rf "$CODEX_HOME"
i=0
while [ "$i" -lt 40 ]; do roll 16 "filler-$i" 'C:\somewhere\else' >/dev/null; i=$((i + 1)); done
roll 15 target "$REPO_NATIVE" >/dev/null
( cd "$REPO" && ctx_find_rollout ) >/dev/null 2>&1
check "discovery: stops at the 40-file bound" "$?" "1"

rm -rf "$CODEX_HOME"
i=0
while [ "$i" -lt 39 ]; do roll 16 "filler-$i" 'C:\somewhere\else' >/dev/null; i=$((i + 1)); done
R5=$(roll 15 target "$REPO_NATIVE")
( cd "$REPO" && ctx_find_rollout && printf '%s' "$CTX_ROLLOUT" ) > "$TMP/found40"
check "discovery: finds the 40th-newest match" "$(cat "$TMP/found40")" "$R5"
rm -rf "$CODEX_HOME"
unset CODEX_HOME
```

The two bound tests rely on day `16` sorting after day `15`, so every filler is newer than the target.

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/context-size.test.sh`
Expected: the six `discovery:` assertions FAIL with `ctx_find_rollout: command not found`.

- [ ] **Step 4: Write the implementation**

Append to `plugins/dr-superpowers/scripts/lib/context.sh`, directly below `ctx_measure_rollout`:

```bash
# A session being written to is among the very newest files, and the sessions
# tree holds years of history: an unbounded walk did not finish in 120 seconds
# on the machine this was measured on.
CTX_ROLLOUT_SCAN=40

# ctx_rollout_files DIR — rollout paths newest-first. Day directories are
# walked newest-first, then files by modification time inside each, so the
# <YYYY>/<MM>/<DD> layout does the coarse ordering without stat-ing the tree.
ctx_rollout_files() {
  local day
  find "$1" -mindepth 3 -maxdepth 3 -type d 2>/dev/null | sort -r | while IFS= read -r day; do
    ls -t "$day"/rollout-*.jsonl 2>/dev/null
  done
}

# Sets CTX_ROLLOUT to this session's rollout; returns 1 when none matches.
# Only interactive rollouts count. This plugin makes a Claude controller run
# Codex tasks in its own worktree through run-codex-task.sh, and those runs
# write rollouts carrying the controller's cwd; selecting one would replace a
# live Claude session's verdict with an unknown.
ctx_find_rollout() {
  CTX_ROLLOUT=""
  local sessions cands f cwd n=0
  ctx_have_jq || return 1
  sessions="${CODEX_HOME:-$HOME/.codex}/sessions"
  [ -d "$sessions" ] || return 1
  # ctx_native emits its own newline under Git Bash and none without cygpath,
  # so the printf keeps one candidate per line on both. A blank line never
  # matches a non-empty cwd under grep -qxF.
  cands=$(ctx_candidates | while IFS= read -r c; do
    [ -n "$c" ] && ctx_native "$c" && printf '\n'
  done)
  # One jq per file, with the origin filter inside it: task-brief prints the
  # budget line before every task, so this walk is on the hot path and a
  # process spawn per field would be three times the cost on Windows.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n + 1))
    [ "$n" -le "$CTX_ROLLOUT_SCAN" ] || return 1
    cwd=$(head -n 1 "$f" 2>/dev/null | tr -d '\r' | ctx_jq -r '
      .payload
      | select((.originator // "") != "codex_exec" and (.source // "") != "exec")
      | .cwd // empty' 2>/dev/null)
    [ -n "$cwd" ] || continue
    if grep -qxF -- "$cwd" <<<"$cands"; then CTX_ROLLOUT=$f; return 0; fi
  done < <(ctx_rollout_files "$sessions")
  return 1
}
```

The loop is fed by process substitution rather than a pipe or a here-string.
A pipe would run the loop in a subshell, losing `CTX_ROLLOUT` and `return`. A
here-string would evaluate `ctx_rollout_files` to completion first, so the
40-file bound would limit only how many first lines are parsed while the walk
still stat-ed every rollout in the history — the cost spec §4.2 exists to
avoid. Process substitution keeps the loop in the calling shell and lets the
walk stop early.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/context-size.test.sh`
Expected: `0 failed`.

- [ ] **Step 6: Confirm the guard works**

Run: `bash plugins/dr-superpowers/tests/budget-line.test.sh`
Expected: `0 failed`, with no reference to any real rollout path in the output.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/context.sh plugins/dr-superpowers/tests/context-size.test.sh plugins/dr-superpowers/tests/budget-line.test.sh plugins/dr-superpowers/tests/repo-audit.test.sh
git commit -m "feat(superpowers): find this session's rollout"
```

---

### Task 3: Choose the host and print the line

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/context.sh` (the `ctx_line` function)
- Test: `plugins/dr-superpowers/tests/context-size.test.sh`

**Interfaces:**
- Consumes: `ctx_measure_rollout` (Task 1), `ctx_find_rollout` and `CTX_ROLLOUT` (Task 2), `ctx_log_observation` (Task 4), and the test fixtures `meta`, `usage_line` and `REPO_NATIVE` — see Contracts.
- Produces: the two budget line forms — see Contracts.

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

`ctx_line` is the one code path both hosts share, so a regression here silently changes every Claude session's budget. Step 5 re-runs both suites for that reason.

The host choice compares modification times with `-nt`. The test writes both
files within the same second, which is fine at NTFS and ext4 resolution and
would be flaky only on a filesystem with one-second granularity; `touch`
between the assertions makes the ordering explicit rather than incidental.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/context-size.test.sh`, below Task 2's block:

```bash
# --- host choice: the live session is the one still being appended to ---
export CODEX_HOME="$TMP/codex2"
mkdir -p "$CODEX_HOME"
mkroll() { # mkroll <name> <tokens> — an interactive rollout for $REPO
  mkdir -p "$CODEX_HOME/sessions/2026/09/15"
  local f="$CODEX_HOME/sessions/2026/09/15/rollout-$1.jsonl"
  { meta "$REPO_NATIVE"; usage_line "$2" 999999; } > "$f"
  printf '%s' "$f"
}

RB=$(mkroll live 187000)
run
check "rollout: exit 3" "$status" "3"
has "rollout: measured line" "$out" "budget: 187k measured — unknown — source: rollout"

DR_SUPERPOWERS_BUDGET=100000 run
has "rollout: DR_SUPERPOWERS_BUDGET does not make a verdict" "$out" "measured — unknown"

{ meta "$REPO_NATIVE"; printf 'not json\n'; } > "$RB"
run
check "rollout: unmeasurable exits 3" "$status" "3"
has "rollout: unmeasurable line carries no denominator" "$out" "budget: unknown — unknown — no usage entry in"

# A Claude transcript written after the rollout wins, and its verdict returns.
RB=$(mkroll live 187000)
{ userline; asst 120000; } > "$T"
record s-1 "$(native "$T")"
touch "$T"
run
check "newest wins: the Claude transcript takes it back" "$status" "0"
has "newest wins: Claude source" "$out" "source: record"
touch "$RB"
run
check "newest wins: the rollout takes it again" "$status" "3"
has "newest wins: rollout source" "$out" "source: rollout"

# The regression this whole filter exists for: a Claude controller running
# Codex executor tasks in its own worktree must keep its verdict.
rm -f "$RB"
mkdir -p "$CODEX_HOME/sessions/2026/09/16"
{ meta "$REPO_NATIVE" codex_exec exec; usage_line 187000 999999; } \
  > "$CODEX_HOME/sessions/2026/09/16/rollout-executor.jsonl"
run
check "executor lane: the Claude session keeps its verdict" "$status" "0"
has "executor lane: still the Claude source" "$out" "source: record"
rm -rf "$CODEX_HOME"
unset CODEX_HOME
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/context-size.test.sh`
Expected: the `rollout:` and `newest wins:` assertions FAIL — the line still reports the Claude transcript or `no transcript found`.

- [ ] **Step 3: Write the implementation**

Replace the whole `ctx_line` function in `plugins/dr-superpowers/scripts/lib/context.sh` with:

```bash
# Print the budget line; return 0 ok, 5 handoff, 3 unknown.
ctx_line() {
  local budget="" model="" tokens bk tk pct found=0 claude="" rollout=""
  if ctx_have_jq; then
    if ctx_find_transcript; then claude=$CTX_TRANSCRIPT; fi
    if ctx_find_rollout; then rollout=$CTX_ROLLOUT; fi
  fi
  # The live session is the one still being appended to. Session records are
  # never deleted, so a record source does not by itself prove a live Claude
  # session and modification time is the right tiebreak.
  if [ -n "$rollout" ] && { [ -z "$claude" ] || [ "$rollout" -nt "$claude" ]; }; then
    CTX_TRANSCRIPT=$rollout CTX_SOURCE=rollout
    if ! tokens=$(ctx_measure_rollout "$rollout"); then
      echo "budget: unknown — unknown — no usage entry in $rollout"
      return 3
    fi
    ctx_log_observation "$tokens"
    tk=$(( (tokens + 500) / 1000 ))
    # No denominator: no Codex budget has been set yet, and the verdict stays
    # unknown so reference/session-budget.md's count rule keeps the session.
    # DR_SUPERPOWERS_BUDGET stays a Claude override for the same reason.
    echo "budget: ${tk}k measured — unknown — source: rollout"
    return 3
  fi
  if [ -n "$claude" ]; then
    found=1
    CTX_TRANSCRIPT=$claude
    model=$(ctx_model "$CTX_TRANSCRIPT")
  fi
  case ${DR_SUPERPOWERS_BUDGET:-} in
    ''|*[!0-9]*) ;;
    *) [ "$DR_SUPERPOWERS_BUDGET" -gt 0 ] && budget=$DR_SUPERPOWERS_BUDGET ;;
  esac
  [ -n "$budget" ] || budget=$(ctx_budget "$model")
  bk=$(( (budget + 500) / 1000 ))
  if ! ctx_have_jq; then echo "budget: unknown of ${bk}k — unknown — no jq"; return 3; fi
  if [ "$found" -eq 0 ]; then echo "budget: unknown of ${bk}k — unknown — no transcript found"; return 3; fi
  if ! tokens=$(ctx_measure "$CTX_TRANSCRIPT"); then
    echo "budget: unknown of ${bk}k — unknown — no usage entry in $CTX_TRANSCRIPT"; return 3
  fi
  tk=$(( (tokens + 500) / 1000 ))
  pct=$(( tokens * 100 / budget ))
  if [ "$tokens" -ge "$budget" ]; then
    echo "budget: ${tk}k of ${bk}k (${pct}%) — handoff — source: $CTX_SOURCE"
    return 5
  fi
  echo "budget: ${tk}k of ${bk}k (${pct}%) — ok — source: $CTX_SOURCE"
}
```

Add this stub directly above `ctx_line`, so the function exists before Task 4 fills it in:

```bash
# Filled in by the observation log; a no-op until then.
ctx_log_observation() { :; }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/context-size.test.sh`
Expected: `0 failed`.

- [ ] **Step 5: Run both suites for the shared path**

Run: `bash plugins/dr-superpowers/tests/budget-line.test.sh && bash plugins/dr-superpowers/tests/repo-audit.test.sh`
Expected: `0 failed` from each. These exercise `ctx_line` through its other two callers.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/context.sh plugins/dr-superpowers/tests/context-size.test.sh
git commit -m "feat(superpowers): report a measured Codex budget"
```

---

### Task 4: Append the observation row

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/context.sh` (replace the `ctx_log_observation` stub)
- Modify: `plugins/dr-superpowers/scripts/task-brief:87`
- Modify: `plugins/dr-superpowers/scripts/review-package:54`
- Test: `plugins/dr-superpowers/tests/context-size.test.sh`

**Interfaces:**
- Consumes: `CTX_ROLLOUT` (Task 2), the test fixtures `meta`, `usage_line` and `REPO_NATIVE` — see Contracts; called from `ctx_line`'s rollout branch (Task 3).
- Produces: `ctx_primary_root`, `ctx_log_observation`, the log path, the row format, and the `DR_SUPERPOWERS_BUDGET_CALLER` values — see Contracts.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/context-size.test.sh`, below Task 3's block:

```bash
# --- the observation log ---
# It lives inside .superpowers/sdd/, which self-ignores: an untracked file
# elsewhere in the checkout enters task-state.sh's review snapshot.
export CODEX_HOME="$TMP/codex3"
mkdir -p "$CODEX_HOME"
LOG="$REPO/.superpowers/sdd/budget-log.tsv"
rm -rf "$REPO/.superpowers/sdd"
mkroll2() { mkdir -p "$CODEX_HOME/sessions/2026/09/15"; { meta "$REPO_NATIVE"; usage_line "$1" 999999; } > "$CODEX_HOME/sessions/2026/09/15/rollout-log.jsonl"; }

mkroll2 150000
run
check "log: one row after a rollout measurement" "$(wc -l < "$LOG" | tr -d ' ')" "1"
check "log: the row has four fields" "$(awk -F'\t' 'NR==1 {print NF}' "$LOG")" "4"
check "log: tokens land in field 2" "$(awk -F'\t' 'NR==1 {print $2}' "$LOG")" "150000"
check "log: an unset caller writes direct" "$(awk -F'\t' 'NR==1 {print $3}' "$LOG")" "direct"
check "log: the session id lands in field 4" "$(awk -F'\t' 'NR==1 {print $4}' "$LOG")" "01a0a58e-8e6c-72b0-92a3-b1586a8ca0ec"
check "log: the directory self-ignores" "$(cat "$REPO/.superpowers/sdd/.gitignore")" "*"
check "log: the checkout stays clean" "$(git -C "$REPO" status --porcelain=v1 --untracked-files=all)" ""

DR_SUPERPOWERS_BUDGET_CALLER=task-brief:3 run
check "log: the caller tag lands in field 3" "$(awk -F'\t' 'END {print $3}' "$LOG")" "task-brief:3"

# The tag the shipped script writes, not one the test sets by hand:
# ctx_observations filters on exactly this shape. Task 7 is deliberately a
# different number from the hand-set row above, so the assertion cannot pass
# on the row that is already there. The plan file needs no commit: task-brief
# resolves it with git rev-parse, which works on an untracked file, and this
# suite exports no git identity.
PLANF="$REPO/docs/plans/2026-01-01-demo.md"
mkdir -p "$REPO/docs/plans"
printf '# Demo\n\n**Execution:** inline — `claude --model sonnet --effort high` — x\n\n### Task 7: Seventh\n\nBody.\n' > "$PLANF"
( cd "$REPO" && bash "$HERE/../scripts/task-brief" docs/plans/2026-01-01-demo.md 7 ) >/dev/null 2>&1
check "log: task-brief writes its own task number" "$(awk -F'\t' 'END {print $3}' "$LOG")" "task-brief:7"
( cd "$REPO" && bash "$HERE/../scripts/task-brief" --header docs/plans/2026-01-01-demo.md ) >/dev/null 2>&1
check "log: --header mode writes the header tag" "$(awk -F'\t' 'END {print $3}' "$LOG")" "task-brief:header"

rm -rf "$CODEX_HOME"; unset CODEX_HOME
rm -f "$LOG"
run
check "log: a Claude measurement writes no row" "$([ -f "$LOG" ] && echo yes || echo no)" "no"
```

`run` already executes with `$REPO` as the working directory, and `record`/`$T` from the earlier blocks still make the Claude path measurable for the final assertion.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/context-size.test.sh`
Expected: the `log:` assertions FAIL — no file is created, so the `wc -l` assertion reports an empty value.

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/lib/context.sh`, replace the `ctx_log_observation` stub with:

```bash
# The primary checkout's root: a worktree's .superpowers lives with the
# checkout that owns the repository, so every session logs to one file.
ctx_primary_root() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null || return 1
}

# ctx_log_observation TOKENS — append one row, and never fail the caller: the
# budget line is printed whether or not the observation is recorded.
#
# The log lives inside .superpowers/sdd/ because that directory self-ignores
# (scripts/sdd-workspace writes * into its .gitignore). Only this repository's
# root .gitignore lists .superpowers/, and an untracked-but-not-ignored file
# would enter scripts/lib/task-state.sh's review snapshot, invalidating a Codex
# review, and would block initial execution's clean-worktree check.
ctx_log_observation() {
  local primary base sid
  primary=$(ctx_primary_root) || return 0
  base="$primary/.superpowers/sdd"
  mkdir -p "$base" 2>/dev/null || return 0
  [ -f "$base/.gitignore" ] || printf '*\n' > "$base/.gitignore" 2>/dev/null || return 0
  sid=$(head -n 1 "$CTX_ROLLOUT" 2>/dev/null | tr -d '\r' \
    | ctx_jq -r '.payload.session_id // empty' 2>/dev/null)
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${DR_SUPERPOWERS_BUDGET_CALLER:-direct}" "$sid" \
    >> "$base/budget-log.tsv" 2>/dev/null || return 0
}
```

- [ ] **Step 4: Tag the two callers**

In `plugins/dr-superpowers/scripts/task-brief`, replace line 87:

```bash
bash "$HERE/context-size" 2>/dev/null || true
```

with:

```bash
# --header mode has no task number; --observations ignores the header rows.
DR_SUPERPOWERS_BUDGET_CALLER="task-brief:${n:-header}" bash "$HERE/context-size" 2>/dev/null || true
```

In `plugins/dr-superpowers/scripts/review-package`, replace line 54:

```bash
bash "$(cd "$(dirname "$0")" && pwd)/context-size" 2>/dev/null || true
```

with:

```bash
DR_SUPERPOWERS_BUDGET_CALLER=review-package bash "$(cd "$(dirname "$0")" && pwd)/context-size" 2>/dev/null || true
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash plugins/dr-superpowers/tests/context-size.test.sh && bash plugins/dr-superpowers/tests/working-directory.test.sh`
Expected: `0 failed` from each. The second covers `task-brief` and `review-package` still printing their own output unchanged.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/context.sh plugins/dr-superpowers/scripts/task-brief plugins/dr-superpowers/scripts/review-package plugins/dr-superpowers/tests/context-size.test.sh
git commit -m "feat(superpowers): log Codex budget observations"
```

---

### Task 5: Read the observations back

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/context.sh`
- Modify: `plugins/dr-superpowers/scripts/context-size`
- Test: `plugins/dr-superpowers/tests/context-size.test.sh`

**Interfaces:**
- Consumes: `ctx_primary_root`, the log path, the row format and the caller values (Task 4) — see Contracts.
- Produces: `ctx_observations` and the `--observations` mode — see Contracts.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/context-size.test.sh`, below Task 4's block:

```bash
# --- reading the observations back ---
# The growth between two briefs is one task's cost. A negative delta is a
# compaction, which is the event phase two calibrates against, never data.
mkdir -p "$REPO/.superpowers/sdd"
LOG="$REPO/.superpowers/sdd/budget-log.tsv"
{ printf '2026-09-20T10:00:00Z\t40000\ttask-brief:1\tsess-a\n'
  printf '2026-09-20T10:05:00Z\t78000\ttask-brief:2\tsess-a\n'
  printf '2026-09-20T10:06:00Z\t79000\treview-package\tsess-a\n'
  printf '2026-09-20T10:07:00Z\t80000\ttask-brief:header\tsess-a\n'
  printf '2026-09-20T10:10:00Z\t31000\ttask-brief:3\tsess-a\n'
  printf '2026-09-20T11:00:00Z\t50000\ttask-brief:9\tsess-b\n'
} > "$LOG"
run --observations
check "observations: exits 0" "$status" "0"
has "observations: a positive delta" "$out" "sess-a  Task 1 -> Task 2  +38k"
has "observations: a compaction is not a number" "$out" "sess-a  Task 2 -> Task 3  compacted"
has "observations: the session span" "$out" "sess-a  span  40k -> 31k"
lacks_obs() { if grep -qF -- "$1" <<<"$out"; then printf 'FAIL - observations: %s\n' "$2"; fail=$((fail + 1)); else printf 'ok   - observations: %s\n' "$2"; pass=$((pass + 1)); fi; }
lacks_obs "review-package" "ignores review-package rows"
lacks_obs "Task 3 -> Task 9" "does not pair across session ids"
: > "$LOG"
run --observations
check "observations: an empty log exits 0" "$status" "0"
check "observations: an empty log prints nothing" "$out" ""
rm -f "$LOG"
run --observations
check "observations: an absent log exits 0" "$status" "0"
check "observations: an absent log prints nothing" "$out" ""
run --observations extra
check "observations: a stray argument exits 2" "$status" "2"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/context-size.test.sh`
Expected: the `observations:` assertions FAIL with exit 2 from `context-size`'s existing argument check.

- [ ] **Step 3: Write the reader**

Append to `plugins/dr-superpowers/scripts/lib/context.sh`:

```bash
# Pair consecutive task-brief rows within one session: task-brief runs once per
# task, so the growth between two briefs is one task's cost. A negative delta
# means a compaction fell between them; it is reported, never averaged into the
# data, because compaction is what the budget will be calibrated against.
ctx_observations() {
  local primary log
  primary=$(ctx_primary_root) || return 0
  log="$primary/.superpowers/sdd/budget-log.tsv"
  [ -f "$log" ] || return 0
  tr -d '\r' < "$log" | awk -F'\t' '
    $3 ~ /^task-brief:[0-9]+$/ {
      n = substr($3, 12)
      if ($4 == sid) {
        d = $2 - prev
        if (d < 0) printf "%s  Task %s -> Task %s  compacted\n", $4, pn, n
        else printf "%s  Task %s -> Task %s  +%dk\n", $4, pn, n, int((d + 500) / 1000)
      } else {
        if (sid != "") printf "%s  span  %dk -> %dk\n", sid, int((first + 500) / 1000), int((prev + 500) / 1000)
        sid = $4; first = $2
      }
      prev = $2; pn = n
    }
    END { if (sid != "") printf "%s  span  %dk -> %dk\n", sid, int((first + 500) / 1000), int((prev + 500) / 1000) }
  '
}
```

- [ ] **Step 4: Add the mode**

In `plugins/dr-superpowers/scripts/context-size`, replace:

```bash
[ $# -eq 0 ] || { echo "usage: context-size" >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/context.sh"
```

with:

```bash
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/context.sh"

if [ "${1:-}" = --observations ]; then
  shift
  [ $# -eq 0 ] || { echo "usage: context-size [--observations]" >&2; exit 2; }
  ctx_observations
  exit 0
fi
[ $# -eq 0 ] || { echo "usage: context-size [--observations]" >&2; exit 2; }
```

Update the script's usage comment in the same edit, replacing lines 5-6:

```bash
# Usage: context-size
# Exit: 0 ok; 5 handoff due; 3 unknown; 2 usage.
```

with:

```bash
# Usage: context-size [--observations]
# Exit: 0 ok; 5 handoff due; 3 unknown; 2 usage.
#   --observations  print the per-task growth recorded on Codex hosts
#                   (reference/session-budget.md) and exit 0.
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/context-size.test.sh`
Expected: `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/context.sh plugins/dr-superpowers/scripts/context-size plugins/dr-superpowers/tests/context-size.test.sh
git commit -m "feat(superpowers): read back budget observations"
```

---

### Task 6: Document the Codex budget line

**Files:**
- Modify: `plugins/dr-superpowers/reference/session-budget.md`
- Modify: `plugins/dr-superpowers/reference/native-codex.md`
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md:409`
- Modify: `plugins/dr-superpowers/skills/executing-plans/SKILL.md:28-30`
- Modify: `plugins/dr-superpowers/skills/handoff/SKILL.md:26`
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh`

**Interfaces:**
- Consumes: the budget line forms (Task 3) and the `--observations` mode (Task 5) — see Contracts.
- Produces: nothing later tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing assertions**

Append to `plugins/dr-superpowers/tests/inline-mode.test.sh`, directly below the existing Codex block that ends with the `native Codex states plans carry no delegated task` assertion:

```bash
# The budget line exists on Codex now, and carries no verdict. Four documents
# said it did not exist at all.
SB="$P/reference/session-budget.md"
present "the budget reference names the rollout source" "$SB" 'source: rollout'
present "the budget reference states the Codex line carries no verdict" "$SB" \
  'measured — unknown'
present "the budget reference names the observations mode" "$SB" '--observations'
present "native Codex names the measured line" "$NC" 'measured — unknown — source: rollout'
absent "subagent mode no longer denies the Codex budget line" "$SDD" \
  'On Codex there is no budget line'
absent "inline mode no longer denies the Codex budget line" "$INLINE" \
  'and there is no budget'
present "inline mode names the measured Codex line" "$INLINE" \
  'carries a measured number but no verdict'
present "the handoff skill keeps the count rule authoritative" "$P/skills/handoff/SKILL.md" \
  'the measured number does not override it'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/inline-mode.test.sh`
Expected: eight FAILs naming the missing strings.

- [ ] **Step 3: Update `reference/session-budget.md`**

In the `## The budget line` section, add after the existing three-line example block:

````markdown
On a Codex host the line reports a measured number and no verdict:

```
budget: 187k measured — unknown — source: rollout
budget: unknown — unknown — no usage entry in <path>
```

`source: rollout` is the session's own Codex rollout, found under
`${CODEX_HOME:-~/.codex}/sessions` by its recorded working directory. Only an
interactive rollout counts: an executor-lane run started by a Claude controller
records that controller's directory, so selecting it would replace a live Claude
session's verdict. Where a Claude transcript and a rollout both match, the more
recently written one is the live session.

The verdict stays `unknown` because no Codex budget has been set yet, so the
count rule below still decides when a Codex session hands off.
`DR_SUPERPOWERS_BUDGET` does not apply to a rollout measurement.

Each Codex measurement appends a row to
`<primary checkout>/.superpowers/sdd/budget-log.tsv`, and
`scripts/context-size --observations` prints it back as the growth between
consecutive task briefs — the data a later phase needs to set the budget. A
negative delta is a compaction, reported as `compacted` rather than a number.
````

In the `## Numbers` table, change the `Codex` row's Source cell to read
`Program design R7; the measured line does not override it`.

- [ ] **Step 4: Update `reference/native-codex.md`**

In `## Execution modes and session ends`, replace the whole third paragraph —
it opens by denying that anything is measurable, so replacing only its last
sentence would leave the paragraph contradicting itself two lines later:

```markdown
Sessions end on the count rule rather than a budget line, because there is no
transcript for `scripts/context-size` to measure: hand off after every 3
completed tasks, or after any task that needed 3 or more fix rounds. The budget
line reads `unknown` here, which is that rule's cue, not a fault.
```

with:

```markdown
Sessions end on the count rule rather than on a budget verdict: hand off after
every 3 completed tasks, or after any task that needed 3 or more fix rounds. The
budget line does measure this session —
`budget: 187k measured — unknown — source: rollout`, read from the Codex
rollout — but its verdict stays `unknown` because no Codex budget has been set
yet, so the count rule, not the number, decides when to hand off.
```

- [ ] **Step 5: Update the two skills**

In `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, replace line 409's opening clause:

```markdown
- On Codex there is no budget line: hand off after every 3 completed tasks, or
```

with:

```markdown
- On Codex the budget line carries a measured number but no verdict: hand off
  after every 3 completed tasks, or
```

Keep the rest of that bullet as it stands.

In `plugins/dr-superpowers/skills/executing-plans/SKILL.md`, replace lines
28-30 of Select the host first, which read:

```markdown
([native-codex.md](../../reference/native-codex.md)), and there is no budget
line: hand off after every 3 completed tasks, or after any task that needed 3
or more fix rounds. Everything else here is host-neutral - inline mode
```

with:

```markdown
([native-codex.md](../../reference/native-codex.md)), and the budget line
carries a measured number but no verdict: hand off after every 3 completed
tasks, or after any task that needed 3 or more fix rounds. Everything else
here is host-neutral - inline mode
```

The trailing clause is part of the replaced block: line 30 continues into the
next sentence, and dropping it would delete the host-neutral statement.

In `plugins/dr-superpowers/skills/handoff/SKILL.md`, replace the count-rule bullet at line 26:

```markdown
- On Codex: after every 3 completed tasks, or after any task that needed 3 or
  more fix rounds.
```

with:

```markdown
- On Codex: after every 3 completed tasks, or after any task that needed 3 or
  more fix rounds. The budget line there reports a measured number with an
  `unknown` verdict, and the measured number does not override it.
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/inline-mode.test.sh`
Expected: `0 failed`.

- [ ] **Step 7: Run the whole suite and validate**

Run: `node scripts/test-all.mjs`
Expected: exit 0, no `FAIL` lines.

Run: `node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, and bundled links are valid.`

Run: `claude plugin validate .claude-plugin/marketplace.json` and
`claude plugin validate plugins/dr-superpowers`
Expected: `✔ Validation passed` from each. The project's CLAUDE.md requires
both alongside the test suites.

- [ ] **Step 8: Commit**

```bash
git add plugins/dr-superpowers/reference plugins/dr-superpowers/skills plugins/dr-superpowers/tests/inline-mode.test.sh
git commit -m "docs(superpowers): document the Codex budget line"
```
