# dr-superpowers Session Budget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use dr-superpowers:subagent-driven-development (recommended) or dr-superpowers:executing-plans to implement this plan task-by-task. Where only the older plugins are enabled, use superpowers:subagent-driven-development with dcc-superpower-companions:dispatching-tiered-implementers. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Implementer assignments:** each task names its implementer agent in an
> `**Implementer:**` line. Under executing-plans these lines are inert; ignore them.

**Goal:** Ship dr-superpowers 1.3.0 with a measured session budget (`context-size`), a resume snapshot (`repo-audit`), the `handoff` and `resume-execution` skills, a compaction snapshot injected by the existing SessionStart hook, and budget checkpoints in the execution skills.

**Architecture:** Shared shell libraries land first (`lib/plan.sh`, `lib/context.sh`), then the tools built on them (`context-size`, the budget line in `task-brief`/`review-package`, `repo-audit`, `lib/snapshot.sh`), then the hook wiring, then the two skills and the reference file, then `next-step` (which names `resume-execution`, so the skill must exist first for the reference validator), then the skill edits, README and version.

**Tech Stack:** Bash (Git Bash on Windows) + jq + git; Markdown skills; Node 22 for the repository validator.

**Spec:** `docs/superpowers/specs/2026-09-11-dr-superpowers-session-budget-design.md`

**Execution:** subagent — `claude --model sonnet --effort high` — Task 9 scores 5 and Tasks 1, 2, 6, 7, 8 score 4, so R5 inline eligibility fails; every task carries its full text for literal execution.

**Program:** docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md — sub-project 3 of 5 — next: Small-model planning

Execute in a worktree (using-git-worktrees) branched from `docs/dr-superpowers-fork-design`, which carries the spec and this plan.

## Global Constraints

- Never touch `plugins/darkmem-resume/` (owner's live work) or historical docs under `docs/superpowers/`. Never push. Never merge to main.
- Claude and Codex dr-superpowers manifest versions stay equal: both become `1.3.0` (Task 11). Catalogs are unchanged.
- Literal prefix rule (enforced by `scripts/validate-repository.mjs`): outside `plugins/dr-superpowers/reference/legacy-names.md`, no file under `plugins/` may contain `superpowers:` unless preceded by `dr-`, or `dcc-superpower-companions:`.
- Reference rule (enforced by the same validator): every `dr-superpowers:<name>` under `plugins/` must name `plugins/dr-superpowers/skills/<name>/` or `plugins/dr-superpowers/agents/<name>.md`. Nothing may name `dr-superpowers:handoff` or `dr-superpowers:resume-execution` before Task 7 creates them.
- Scripts are Bash with `#!/usr/bin/env bash`, run under Git Bash on Windows, and use only bash, coreutils, git and jq. New executables are added with `git add --chmod=+x`.
- Hook output (`additionalContext`) is capped at 10,000 characters by Claude Code; the compaction snapshot is capped at 5,500, or less when the entry point leaves less room.
- Do not modify `reference/ladder.md`, `reference/external-task-recovery.md`, or any file in `agents/`.
- Commits: `<type>(superpowers): <subject>`, subject ≤50 chars, imperative, English.
- Every test/CLI run bounded with `timeout`; kill any process you start.
- `P` below means `plugins/dr-superpowers`. Paths are relative to the repository root.

## Contracts

- **`P/scripts/lib/plan.sh`** (sourced): `plan_tasks FILE` prints `N<TAB>title` per `Task N` heading outside code fences, CR stripped; `ledger_done FILE` prints the task numbers that have a `Task N: complete` line, sorted, unique.
- **`P/scripts/lib/context.sh`** (sourced): `ctx_line` prints the budget line and returns 0 ok, 5 handoff, 3 unknown. Also `ctx_find_transcript` (sets `CTX_TRANSCRIPT`, `CTX_SOURCE`), `ctx_measure FILE`, `ctx_key DIR`. Environment: `DR_SUPERPOWERS_BUDGET` (default 475000), `DR_SUPERPOWERS_JQ` (default `jq`).
- **Budget line**, exactly one of:
  - `budget: <T>k of <B>k (<P>%) — ok — source: <record|record?|guessed>`
  - `budget: <T>k of <B>k (<P>%) — handoff — source: <…>`
  - `budget: unknown of <B>k — unknown — <no jq|no transcript found|no usage entry in PATH>`
  where `<T>` and `<B>` round to the nearest thousand and `<P>` is `tokens*100/budget` truncated.
- **`P/scripts/context-size`**: no arguments; prints the budget line; exit 0 ok, 5 handoff, 3 unknown, 2 usage. `task-brief` and `review-package` print the same line as their last output line and keep their own exit codes.
- **`P/scripts/repo-audit`**: no arguments; markdown starting `# Repo audit`; exit 0, or 2 outside a git repository.
- **`P/scripts/lib/snapshot.sh`** (sourced): `snapshot_build TRANSCRIPT CWD [CAP]` prints markdown starting `## Compaction snapshot`, at most CAP characters (default `SNAPSHOT_CAP=5500`). The hook passes `min(5500, 9500 - entry-point length - 400)`.
- **Ledger line** (new): `Final review: clean (commits <a7>..<b7>[, K parked])`.
- **`next-step`** usage: `next-step [--complete] PLAN_FILE` or `next-step --draft DRAFT_FILE --next ACTION`.
- **Handoff files:** `<worktree>/.superpowers/sdd/<plan-basename>/handoff.md` (≤40 lines: `## Owner constraints`, `## Gotchas`, `## Do not`, `## Open questions`); `<primary>/.superpowers/handoff/latest.md` (sections `## State`, `## Gotchas`, `## Do not`, then `## Next session` written by `next-step`).

## Assumptions (evidence)

- `git worktree remove` deletes git-ignored files such as `.superpowers/` without `--force`: probed 2026-09-11 in a scratch repository (exit 0, directory gone).
- Transcript shapes, observed 2026-09-11 in `~/.claude/projects/*/*.jsonl`: compaction writes `{"type":"system","subtype":"compact_boundary","isSidechain":false,"compactMetadata":{"trigger":"auto","preTokens":467031,"postTokens":10954,…}}`; the summary follows as a `user` entry with `isCompactSummary: true`; typed owner prompts carry `"origin":{"kind":"human"}` and string `message.content`; an Agent dispatch's `tool_result` text contains `agentId: <id>`; assistant entries carry `message.usage.{input_tokens,cache_creation_input_tokens,cache_read_input_tokens}`.
- Largest transcript on this machine is 24 MB, so measurement reads the last 400 lines first and the whole file only when that window holds no usable entry.
- No `**Executor:**` lines: the Codex executor lane fails on this Windows box (`jq: Argument list too long` in `run-codex-task.sh`'s snapshot, parked from sub-project 2) and the Codex quota is exhausted until 2026-09-16.
- Implementer lines use `dcc-superpower-companions:` names because dr-superpowers is not enabled on this machine; dr-superpowers' subagent-driven-development translates them through `reference/legacy-names.md`.
- Plan-time ruling: `task-brief` and `review-package` call the `context-size` executable rather than sourcing `lib/context.sh`, so the measurement runs outside their `set -e` and can never fail them.

## Task index

1. Shared plan parser (`lib/plan.sh`) used by next-step
2. Context measurement: `lib/context.sh` and `context-size`
3. Budget line in `task-brief` and `review-package`
4. `repo-audit`
5. Compaction snapshot library
6. SessionStart hook injects the snapshot on compact
7. `handoff` and `resume-execution` skills, `reference/session-budget.md`
8. next-step: draft mode, resume routing, final-review state
9. subagent-driven-development and executing-plans checkpoints
10. finishing, brainstorming and using-superpowers edits
11. README and 1.3.0
12. Full verification sweep

---

### Task 1: Shared plan parser (`lib/plan.sh`) used by next-step

**Files:**
- Create: `plugins/dr-superpowers/scripts/lib/plan.sh`
- Modify: `plugins/dr-superpowers/scripts/next-step:17-17,36-46,70`
- Test: `plugins/dr-superpowers/tests/plan-lib.test.sh` (create); `plugins/dr-superpowers/tests/next-step.test.sh` must stay green unchanged

**Interfaces:**
- Consumes: nothing
- Produces: `plan_tasks FILE`, `ledger_done FILE` (used by Tasks 4 and 8)

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/plan-lib.test.sh`:

```bash
#!/usr/bin/env bash
# lib/plan.sh is the one task parser next-step and repo-audit share, so both
# count the same tasks: headings outside code fences only, CRLF tolerated.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/lib/plan.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf '# Plan\n\n### Task 1: First thing\n\n```bash\n### Task 9: fenced\n```\n\n## Task 2 - Second\n\n### Task 10: Tenth\n' > "$TMP/plan.md"
check "plan_tasks: numbers outside fences" "$(plan_tasks "$TMP/plan.md" | cut -f1 | tr '\n' ' ')" "1 2 10 "
check "plan_tasks: titles" "$(plan_tasks "$TMP/plan.md" | cut -f2 | tr '\n' '|')" "First thing|Second|Tenth|"
sed 's/$/\r/' "$TMP/plan.md" > "$TMP/crlf.md"
check "plan_tasks: CRLF" "$(plan_tasks "$TMP/crlf.md" | cut -f2 | tr '\n' '|')" "First thing|Second|Tenth|"
printf '# Empty\n' > "$TMP/none.md"
check "plan_tasks: no tasks prints nothing" "$(plan_tasks "$TMP/none.md")" ""

printf '# SDD ledger — plan: x\nTask 2: complete (a)\nTask 1: fix round 1/5 (x)\nTask 1: complete (b)\nTask 2: complete (again)\nGroup 1-2: review round 1/5\n' > "$TMP/ledger.md"
check "ledger_done: unique and sorted" "$(ledger_done "$TMP/ledger.md" | tr '\n' ' ')" "1 2 "
sed 's/$/\r/' "$TMP/ledger.md" > "$TMP/ledger-crlf.md"
check "ledger_done: CRLF" "$(ledger_done "$TMP/ledger-crlf.md" | tr '\n' ' ')" "1 2 "
printf '# SDD ledger — plan: x\nTask 3: fix round 1/5 (x)\n' > "$TMP/open.md"
check "ledger_done: nothing complete" "$(ledger_done "$TMP/open.md")" ""

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 60 bash plugins/dr-superpowers/tests/plan-lib.test.sh`
Expected: fails at the `.` line with "No such file or directory" (lib/plan.sh does not exist); exit non-zero.

- [ ] **Step 3: Create the library**

Create `plugins/dr-superpowers/scripts/lib/plan.sh`:

```bash
# Plan and ledger parsing shared by next-step and repo-audit, so both count the
# same tasks. Sourced; defines functions only.

# plan_tasks FILE — one "N<TAB>title" line per Task heading outside code fences.
# Same heading rule as task-brief.
plan_tasks() {
  tr -d '\r' < "$1" | awk '
    /^```/ { infence = !infence }
    !infence && /^#+[ \t]+Task[ \t]+[0-9]+/ {
      line = $0
      sub(/^#+[ \t]+Task[ \t]+/, "", line)
      n = line; sub(/[^0-9].*$/, "", n)
      t = line; sub(/^[0-9]+[: \t.-]*/, "", t)
      print n "\t" t
    }
  '
}

# ledger_done FILE — the task numbers with a "Task N: complete" line, sorted,
# unique.
ledger_done() {
  tr -d '\r' < "$1" | sed -n 's/^Task \([0-9][0-9]*\): complete.*/\1/p' | sort -un
}
```

- [ ] **Step 4: Run the library test**

Run: `timeout 60 bash plugins/dr-superpowers/tests/plan-lib.test.sh`
Expected: `7 passed, 0 failed`, exit 0.

- [ ] **Step 5: Make next-step use the library**

In `plugins/dr-superpowers/scripts/next-step`, after line 17 (`usage() { … }`), insert:

```bash
. "$(cd "$(dirname "$0")" && pwd)/lib/plan.sh"
```

Replace lines 36-46:

```bash
# Same fence-aware heading rule as task-brief, so both count the same tasks.
tasks=$(awk '
  /^```/ { infence = !infence }
  !infence && /^#+[ \t]+Task[ \t]+[0-9]+/ {
    line = $0
    sub(/^#+[ \t]+Task[ \t]+/, "", line)
    n = line; sub(/[^0-9].*$/, "", n)
    t = line; sub(/^[0-9]+[: \t.-]*/, "", t)
    print n "\t" t
  }
' <<<"$plan_text")
```

with:

```bash
tasks=$(plan_tasks "$plan")
```

Replace line 70:

```bash
    done_tasks=$(sed -n 's/^Task \([0-9][0-9]*\): complete.*/\1/p' <<<"$ledger_text" | sort -un)
```

with:

```bash
    done_tasks=$(ledger_done "$ledger_file")
```

- [ ] **Step 6: Run both suites**

Run: `timeout 120 bash plugins/dr-superpowers/tests/plan-lib.test.sh && timeout 120 bash plugins/dr-superpowers/tests/next-step.test.sh`
Expected: both end `… passed, 0 failed`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/plan.sh plugins/dr-superpowers/scripts/next-step
git add --chmod=+x plugins/dr-superpowers/tests/plan-lib.test.sh
git commit -m "refactor(superpowers): share plan parsing via lib"
```

### Task 2: Context measurement: `lib/context.sh` and `context-size`

**Files:**
- Create: `plugins/dr-superpowers/scripts/lib/context.sh`
- Create: `plugins/dr-superpowers/scripts/context-size`
- Test: `plugins/dr-superpowers/tests/context-size.test.sh` (create)

**Interfaces:**
- Consumes: the session record `~/.claude/dr-superpowers/sessions/<key>.json` (`session_id`, `transcript_path`) written by `scripts/session-start.sh`
- Produces: `ctx_line`, `ctx_find_transcript`, `ctx_measure`, `ctx_key`; the `context-size` executable and the budget line (Contracts) used by Tasks 3, 4, 7, 9, 10

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/context-size.test.sh`:

```bash
#!/usr/bin/env bash
# context-size must measure the main session's context from its transcript —
# ignoring subagent, synthetic and interrupted entries, restarting at the last
# compaction — find the transcript by session record or, failing that, by
# guess, and print one budget line with a verdict exit code.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/context-size"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export MSYS_NO_PATHCONV=1
unset DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ

REPO="$TMP/repo"
git init -q "$REPO"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
KEY=$(printf '%s' "$(native "$(cd "$REPO" && pwd)")" | tr -c 'A-Za-z0-9' '-')
PROJ="$HOME/.claude/projects/$KEY"
SESS="$HOME/.claude/dr-superpowers/sessions"
mkdir -p "$PROJ" "$SESS"

asst() { # asst <tokens> [isSidechain] [model]
  printf '{"type":"assistant","isSidechain":%s,"message":{"model":"%s","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s}}}\n' \
    "${2:-false}" "${3:-claude-opus-5}" "$1"
}
boundary() { # boundary <postTokens>
  printf '{"type":"system","subtype":"compact_boundary","isSidechain":false,"compactMetadata":{"trigger":"auto","preTokens":460000,"postTokens":%s}}\n' "$1"
}
userline() { printf '{"type":"user","isSidechain":false,"message":{"role":"user","content":"hi"}}\n'; }
record() { # record <session_id> <transcript>
  jq -n --arg sid "$1" --arg tp "$2" '{session_id:$sid,transcript_path:$tp,cwd:"x",source:"startup",timestamp:"t"}' > "$SESS/$KEY.json"
}
run() { out=$(cd "$REPO" && bash "$SCRIPT" "$@" 2>"$TMP/stderr"); status=$?; }

T="$PROJ/s-1.jsonl"

# --- record; sidechain, synthetic and zero-usage entries ignored ---
{ asst 285000; asst 900000 true; asst 999000 false '<synthetic>'; asst 0; } > "$T"
record s-1 "$T"
run
check "record: exit 0" "$status" "0"
check "record: line" "$out" "budget: 285k of 475k (60%) — ok — source: record"

# --- over budget ---
asst 500000 > "$T"
run
check "over: exit 5" "$status" "5"
check "over: line" "$out" "budget: 500k of 475k (105%) — handoff — source: record"

# --- boundary with no assistant after it: postTokens ---
{ asst 460000; boundary 12000; userline; } > "$T"
run
check "boundary only: line" "$out" "budget: 12k of 475k (2%) — ok — source: record"

# --- boundary then an assistant ---
{ asst 460000; boundary 12000; userline; asst 30000; } > "$T"
run
check "after boundary: line" "$out" "budget: 30k of 475k (6%) — ok — source: record"

# --- usable entry outside the 400-line tail window ---
{ asst 50000; for i in $(seq 1 450); do userline; done; } > "$T"
run
check "whole-file fallback: line" "$out" "budget: 50k of 475k (10%) — ok — source: record"

# --- no usage entry ---
userline > "$T"
run
check "no usage: exit 3" "$status" "3"
check "no usage: line" "$out" "budget: unknown of 475k — unknown — no usage entry in $T"

# --- budget override ---
asst 285000 > "$T"
DR_SUPERPOWERS_BUDGET=300000 run
check "override: line" "$out" "budget: 285k of 300k (95%) — ok — source: record"

# --- CRLF transcript ---
asst 285000 | sed 's/$/\r/' > "$T"
run
check "crlf: line" "$out" "budget: 285k of 475k (60%) — ok — source: record"

# --- record whose session is not the newest in its project directory ---
asst 285000 > "$T"
touch -d '5 minutes ago' "$T"
asst 1000 > "$PROJ/other.jsonl"
run
check "record?: line" "$out" "budget: 285k of 475k (60%) — ok — source: record?"

# --- no record: newest transcript, flagged as a guess ---
rm -f "$SESS/$KEY.json"
asst 100000 > "$PROJ/other.jsonl"
run
check "guessed: line" "$out" "budget: 100k of 475k (21%) — ok — source: guessed"
has "guessed: warns on stderr" "$(cat "$TMP/stderr")" "a guess"

# --- nothing to read ---
HOME="$TMP/empty" run
check "no transcript: exit 3" "$status" "3"
check "no transcript: line" "$out" "budget: unknown of 475k — unknown — no transcript found"

# --- no jq ---
DR_SUPERPOWERS_JQ=no-such-jq run
check "no jq: exit 3" "$status" "3"
check "no jq: line" "$out" "budget: unknown of 475k — unknown — no jq"

# --- usage ---
run extra
check "usage: exit 2" "$status" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 bash plugins/dr-superpowers/tests/context-size.test.sh`
Expected: FAIL lines (the script does not exist; `status` is 127); exit non-zero.

- [ ] **Step 3: Create the library**

Create `plugins/dr-superpowers/scripts/lib/context.sh`:

```bash
# Measure the running Claude session's context against the handoff budget.
# Sourced by scripts/context-size; defines functions only.
#
# The transcript schema is observed, not documented: main-chain entries carry
# isSidechain false, assistant entries carry message.usage, and compaction
# writes a system entry with subtype compact_boundary. A schema change must
# degrade the verdict to unknown, never produce a wrong number.

CTX_DEFAULT_BUDGET=475000

ctx_jq() { "${DR_SUPERPOWERS_JQ:-jq}" "$@"; }
ctx_have_jq() { command -v "${DR_SUPERPOWERS_JQ:-jq}" >/dev/null 2>&1; }

# Keys are built from the native path so they match what the hook received from
# Claude Code (a Windows path under Git Bash).
ctx_native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}
ctx_posix() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi
}
ctx_key() { printf '%s' "$(ctx_native "$1")" | tr -c 'A-Za-z0-9' '-'; }

ctx_candidates() {
  printf '%s\n' "$PWD"
  local root common
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  printf '%s\n' "$root"
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null || true
}

# Sets CTX_TRANSCRIPT and CTX_SOURCE (record | record? | guessed); returns 1
# when no transcript is found. Records go first across every candidate, so a
# worktree's own old transcript never outranks the running session's record.
ctx_find_transcript() {
  CTX_TRANSCRIPT="" CTX_SOURCE=""
  local cands c key rec tp sid newest
  cands=$(ctx_candidates)
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    key=$(ctx_key "$c")
    rec="$HOME/.claude/dr-superpowers/sessions/$key.json"
    [ -f "$rec" ] || continue
    tp=$(ctx_jq -r '.transcript_path // empty' "$rec" 2>/dev/null | tr -d '\r')
    [ -n "$tp" ] || continue
    tp=$(ctx_posix "$tp")
    [ -f "$tp" ] || continue
    CTX_TRANSCRIPT=$tp CTX_SOURCE=record
    sid=$(ctx_jq -r '.session_id // empty' "$rec" 2>/dev/null | tr -d '\r')
    newest=$(ls -t "$HOME/.claude/projects/$key"/*.jsonl 2>/dev/null | head -n 1)
    if [ -n "$newest" ] && [ -n "$sid" ] && [ "$(basename "$newest" .jsonl)" != "$sid" ]; then
      CTX_SOURCE='record?'
    fi
    return 0
  done <<<"$cands"
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    newest=$(ls -t "$HOME/.claude/projects/$(ctx_key "$c")"/*.jsonl 2>/dev/null | head -n 1)
    if [ -n "$newest" ]; then CTX_TRANSCRIPT=$newest CTX_SOURCE=guessed; return 0; fi
  done <<<"$cands"
  return 1
}

# stdin: transcript lines. stdout: token count, or nothing.
ctx_reduce() {
  tr -d '\r' | ctx_jq -R -r -n '
    [inputs | select(length > 0) | (try fromjson catch null) | objects
     | select((.isSidechain // false) == false)
     | if .type == "system" and .subtype == "compact_boundary" then {b: .compactMetadata.postTokens}
       elif .type == "assistant" and (.message.model // "") != "<synthetic>"
            and ((.message.usage | type) == "object") then
         ((.message.usage.input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0)
          + (.message.usage.cache_read_input_tokens // 0)) as $t
         | if $t > 0 then {a: $t} else empty end
       else empty end]
    | reduce .[] as $e ({}; if ($e | has("b")) then {b: $e.b} else . + {a: $e.a} end)
    | (.a // .b) // empty' 2>/dev/null
}

# ctx_measure FILE — the last main-chain assistant usage after the last
# compaction boundary, else that boundary's postTokens. Reads the tail first:
# transcripts reach tens of megabytes.
ctx_measure() {
  local out
  out=$(tail -n 400 "$1" | ctx_reduce)
  [ -n "$out" ] || out=$(ctx_reduce < "$1")
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# Print the budget line; return 0 ok, 5 handoff, 3 unknown.
ctx_line() {
  local budget=${DR_SUPERPOWERS_BUDGET:-$CTX_DEFAULT_BUDGET} tokens bk tk pct
  case $budget in ''|*[!0-9]*) budget=$CTX_DEFAULT_BUDGET ;; esac
  [ "$budget" -gt 0 ] || budget=$CTX_DEFAULT_BUDGET
  bk=$(( (budget + 500) / 1000 ))
  if ! ctx_have_jq; then echo "budget: unknown of ${bk}k — unknown — no jq"; return 3; fi
  if ! ctx_find_transcript; then echo "budget: unknown of ${bk}k — unknown — no transcript found"; return 3; fi
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

- [ ] **Step 4: Create the executable**

Create `plugins/dr-superpowers/scripts/context-size`:

```bash
#!/usr/bin/env bash
# Print the running session's context size against the handoff budget as one
# budget line (see reference/session-budget.md).
#
# Usage: context-size
# Exit: 0 ok; 5 handoff due; 3 unknown; 2 usage.
set -uo pipefail

[ $# -eq 0 ] || { echo "usage: context-size" >&2; exit 2; }
. "$(cd "$(dirname "$0")" && pwd)/lib/context.sh"

ctx_line
status=$?
if [ "${CTX_SOURCE:-}" = guessed ]; then
  echo "context-size: no usable session record; measured the newest transcript for this directory — a guess" >&2
fi
exit "$status"
```

- [ ] **Step 5: Run the test**

Run: `timeout 120 bash plugins/dr-superpowers/tests/context-size.test.sh`
Expected: `19 passed, 0 failed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/context.sh
git add --chmod=+x plugins/dr-superpowers/scripts/context-size plugins/dr-superpowers/tests/context-size.test.sh
git commit -m "feat(superpowers): measure context with context-size"
```

### Task 3: Budget line in `task-brief` and `review-package`

**Files:**
- Modify: `plugins/dr-superpowers/scripts/task-brief:41`
- Modify: `plugins/dr-superpowers/scripts/review-package:46`
- Test: `plugins/dr-superpowers/tests/budget-line.test.sh` (create)

**Interfaces:**
- Consumes: `scripts/context-size` (Task 2) and its budget line
- Produces: both scripts print the budget line as their last output line (consumed by Task 9's skill text)

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/budget-line.test.sh`:

```bash
#!/usr/bin/env bash
# task-brief and review-package carry the budget line, so the controller sees
# the session budget before every task and every review without an extra
# request. A measurement problem must never fail them.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ

REPO="$TMP/repo"
git init -q "$REPO"
mkdir -p "$REPO/docs"
printf '# Plan\n\n### Task 1: Only thing\n\nBody.\n' > "$REPO/docs/plan.md"
git -C "$REPO" add -A && git -C "$REPO" commit -qm plan
BASE=$(git -C "$REPO" rev-parse HEAD)
printf 'x\n' > "$REPO/file.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -qm file
cd "$REPO"

# --- no transcript: unknown, exit unchanged ---
out=$(bash "$P/scripts/task-brief" docs/plan.md 1 2>/dev/null); status=$?
check "task-brief: exit 0 with no transcript" "$status" "0"
check "task-brief: first line unchanged" "$(sed -n 1p <<<"$out" | cut -c1-6)" "wrote "
check "task-brief: last line is the budget line" "$(tail -n 1 <<<"$out")" \
  "budget: unknown of 475k — unknown — no transcript found"

# --- over budget: handoff, exit unchanged ---
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
KEY=$(printf '%s' "$(native "$(pwd)")" | tr -c 'A-Za-z0-9' '-')
mkdir -p "$HOME/.claude/projects/$KEY" "$HOME/.claude/dr-superpowers/sessions"
T="$HOME/.claude/projects/$KEY/s-1.jsonl"
printf '{"type":"assistant","isSidechain":false,"message":{"model":"m","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":500000}}}\n' > "$T"
jq -n --arg tp "$T" '{session_id:"s-1",transcript_path:$tp}' > "$HOME/.claude/dr-superpowers/sessions/$KEY.json"

out=$(bash "$P/scripts/review-package" docs/plan.md "$BASE" HEAD 2>/dev/null); status=$?
check "review-package: exit 0 over budget" "$status" "0"
check "review-package: first line unchanged" "$(sed -n 1p <<<"$out" | cut -c1-6)" "wrote "
check "review-package: budget line says handoff" "$(tail -n 1 <<<"$out")" \
  "budget: 500k of 475k (105%) — handoff — source: record"
out=$(bash "$P/scripts/task-brief" docs/plan.md 1 2>/dev/null)
check "task-brief: budget line says handoff" "$(tail -n 1 <<<"$out")" \
  "budget: 500k of 475k (105%) — handoff — source: record"

# --- a missing task still fails the way it did ---
bash "$P/scripts/task-brief" docs/plan.md 9 >/dev/null 2>&1; status=$?
check "task-brief: missing task still exits 3" "$status" "3"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 bash plugins/dr-superpowers/tests/budget-line.test.sh`
Expected: FAIL on the three "budget line" checks (the last line is still the `wrote …` line); exit non-zero.

- [ ] **Step 3: Print the budget line from both scripts**

In `plugins/dr-superpowers/scripts/task-brief`, after the last line (`echo "wrote ${out}: …"`), append:

```bash

# The budget line rides on a call the controller already makes before every
# task, so checking the session budget costs no extra request. It must never
# fail the brief.
"$(cd "$(dirname "$0")" && pwd)/context-size" 2>/dev/null || true
```

In `plugins/dr-superpowers/scripts/review-package`, after the last line (`echo "wrote ${out}: ${commits} commit(s), …"`), append:

```bash

# The budget line rides on a call the controller already makes before every
# review, so checking the session budget costs no extra request. It must never
# fail the package.
"$(cd "$(dirname "$0")" && pwd)/context-size" 2>/dev/null || true
```

Update each script's header comment usage block by adding, as its last comment line before `set -euo pipefail`:

```bash
# Last output line: the session budget line from scripts/context-size.
```

- [ ] **Step 4: Run the tests**

Run: `timeout 120 bash plugins/dr-superpowers/tests/budget-line.test.sh`
Expected: `8 passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/task-brief plugins/dr-superpowers/scripts/review-package
git add --chmod=+x plugins/dr-superpowers/tests/budget-line.test.sh
git commit -m "feat(superpowers): print budget line with briefs"
```

### Task 4: `repo-audit`

**Files:**
- Create: `plugins/dr-superpowers/scripts/repo-audit`
- Test: `plugins/dr-superpowers/tests/repo-audit.test.sh` (create)

**Interfaces:**
- Consumes: `plan_tasks`, `ledger_done` from `scripts/lib/plan.sh` (Task 1); `scripts/context-size` (Task 2)
- Produces: the `repo-audit` executable (Contracts), used by Tasks 6, 7 and 10

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/repo-audit.test.sh`:

```bash
#!/usr/bin/env bash
# repo-audit replaces a resuming session's orientation calls with one read-only
# snapshot: branch, worktrees, dirty files, plans in flight, handoff staleness,
# the CLAUDE.md compaction section, the budget line and recent commits.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/repo-audit"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ

REPO="$TMP/repo"
git init -q -b main "$REPO"
mkdir -p "$REPO/docs"
printf '# Plan\n\n### Task 1: One\n\n### Task 2: Two\n\n### Task 3: Three\n' > "$REPO/docs/plan.md"
printf '# Project\n\nNo compaction notes.\n' > "$REPO/CLAUDE.md"
printf '.superpowers/\n' > "$REPO/.gitignore"
git -C "$REPO" add -A && git -C "$REPO" commit -qm init
ROOT="$(git -C "$REPO" rev-parse --show-toplevel)"

WT="$TMP/wt"
git -C "$REPO" worktree add -q -b feat "$WT"
WT_ROOT="$(git -C "$WT" rev-parse --show-toplevel)"
WS="$WT/.superpowers/sdd/plan"
mkdir -p "$WS"
printf '# SDD ledger — plan: docs/plan.md\nTask 1: complete (commits a..b, review clean)\nTask 2: fix round 1/5 (1 addressed, 1 open — x)\n' > "$WS/progress.md"
printf '# Handoff notes\n' > "$WS/handoff.md"

mkdir -p "$REPO/.superpowers/handoff"
printf '# Handoff\n\n## Next session\n\n**Status:** Plan `docs/plan.md`: 1 of 3 tasks complete.\n**Next:** Resume at Task 2 (Two).\n' \
  > "$REPO/.superpowers/handoff/latest.md"
touch -d '1 hour ago' "$REPO/.superpowers/handoff/latest.md"
printf 'later\n' > "$REPO/later.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -qm second

run() { out=$(cd "$1" && bash "$SCRIPT" "${@:2}" 2>"$TMP/stderr"); status=$?; }

# --- primary checkout ---
run "$REPO"
check "primary: exit 0" "$status" "0"
has "primary: heading" "$out" "# Repo audit"
has "primary: root" "$out" "- Root: \`$ROOT\`"
has "primary: branch" "$out" "- Branch: \`main\` at "
has "primary: budget line" "$out" "- budget: unknown of 475k — unknown — no transcript found"
has "primary: worktree listed with branch" "$out" "[feat]"
has "primary: clean tree" "$out" "## Dirty files (0)"
has "primary: plan in flight" "$out" "- \`docs/plan.md\` in \`$WT_ROOT\`: 1 of 3 tasks complete; handoff.md: yes"
has "primary: last ledger line" "$out" "  - last ledger line: Task 2: fix round 1/5 (1 addressed, 1 open — x)"
has "primary: handoff status" "$out" "- **Status:** Plan \`docs/plan.md\`: 1 of 3 tasks complete."
has "primary: handoff staleness" "$out" "- Commits on the primary checkout's HEAD since it was written: 2"
has "primary: no compact section" "$out" "- CLAUDE.md has no Compact Instructions section"
has "primary: recent commits" "$out" " second"

# --- dirty tree and a Compact Instructions section ---
printf '# Project\n\n# Compact instructions\n\nKeep paths.\n' > "$REPO/CLAUDE.md"
run "$REPO"
has "dirty: counted" "$out" "## Dirty files (1)"
has "compact section: found" "$out" "- CLAUDE.md has a Compact Instructions section"

# --- from the worktree ---
run "$WT"
has "worktree: primary named" "$out" "- Primary checkout: \`$ROOT\`"
has "worktree: branch" "$out" "- Branch: \`feat\` at "

# --- errors ---
mkdir -p "$TMP/notrepo"
run "$TMP/notrepo"
check "outside a repository: exit 2" "$status" "2"
run "$REPO" extra
check "usage: exit 2" "$status" "2"

git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 bash plugins/dr-superpowers/tests/repo-audit.test.sh`
Expected: FAIL lines (the script does not exist); exit non-zero.

- [ ] **Step 3: Create the script**

Create `plugins/dr-superpowers/scripts/repo-audit`:

```bash
#!/usr/bin/env bash
# Print a read-only orientation snapshot for a session that picks up work, so
# it costs one command instead of the five to eight a fresh session otherwise
# spends on git status, logs, worktrees, ledgers and the handoff file.
#
# Usage: repo-audit
# Exit: 0 ok; 2 usage or not inside a git repository.
set -uo pipefail

[ $# -eq 0 ] || { echo "usage: repo-audit" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/plan.sh"

root=$(git rev-parse --show-toplevel 2>/dev/null) \
  || { echo "repo-audit: not inside a git repository" >&2; exit 2; }
common=$(git rev-parse --path-format=absolute --git-common-dir)
primary=$(git -C "$(dirname "$common")" rev-parse --show-toplevel)

branch=$(git symbolic-ref --short -q HEAD || echo "(detached)")
head=$(git log -1 --format='%h %s' 2>/dev/null || echo "(no commits)")
tracking=""
if up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
  read -r ahead behind < <(git rev-list --left-right --count "HEAD...$up")
  tracking=" — $ahead ahead, $behind behind \`$up\`"
fi

echo "# Repo audit"
echo
echo "- Root: \`$root\`"
[ "$root" = "$primary" ] || echo "- Primary checkout: \`$primary\`"
echo "- Branch: \`$branch\` at $head$tracking"
echo "- $("$here/context-size" 2>/dev/null)"

echo
echo "## Worktrees"
git worktree list --porcelain | tr -d '\r' | awk '
  /^worktree / { if (line != "") print line; line = "- `" substr($0, 10) "`"; next }
  /^HEAD /     { line = line " " substr($0, 6, 7); next }
  /^branch /   { b = substr($0, 8); sub(/^refs\/heads\//, "", b); line = line " [" b "]"; next }
  /^detached/  { line = line " (detached)"; next }
  /^prunable/  { line = line " — prunable"; next }
  END { if (line != "") print line }
'

dirty=$(git status --short)
count=$(printf '%s' "$dirty" | grep -c . || true)
echo
echo "## Dirty files ($count)"
[ "$count" -eq 0 ] || printf '%s\n' "$dirty" | head -n 20 | sed 's/^/    /'

echo
echo "## Plans in flight"
found=0
while IFS= read -r wt; do
  for ledger in "$wt"/.superpowers/sdd/*/progress.md; do
    [ -f "$ledger" ] || continue
    found=1
    plan_rel=$(head -n 1 "$ledger" | tr -d '\r' | sed -n 's/^# SDD ledger — plan: //p')
    total="?"
    if [ -n "$plan_rel" ] && [ -f "$wt/$plan_rel" ]; then
      total=$(plan_tasks "$wt/$plan_rel" | grep -c . || true)
    fi
    done_n=$(ledger_done "$ledger" | grep -c . || true)
    last=$(tr -d '\r' < "$ledger" | grep -v '^[[:space:]]*$' | tail -n 1 | cut -c1-160)
    has_handoff=no
    [ -f "$(dirname "$ledger")/handoff.md" ] && has_handoff=yes
    echo "- \`${plan_rel:-unknown plan}\` in \`$wt\`: $done_n of $total tasks complete; handoff.md: $has_handoff"
    echo "  - last ledger line: $last"
  done
done < <(git worktree list --porcelain | tr -d '\r' | sed -n 's/^worktree //p')
[ "$found" -eq 1 ] || echo "- none"

echo
echo "## Handoff"
latest="$primary/.superpowers/handoff/latest.md"
if [ -f "$latest" ]; then
  echo "- \`$latest\`"
  tr -d '\r' < "$latest" | grep -E '^\*\*(Status|Next):\*\*' | sed 's/^/- /'
  mtime=$(stat -c %Y "$latest" 2>/dev/null || stat -f %m "$latest")
  since=$(git -C "$primary" log -n 500 --format=%ct HEAD 2>/dev/null | awk -v t="$mtime" '$1 > t' | grep -c . || true)
  echo "- Commits on the primary checkout's HEAD since it was written: $since"
else
  echo "- none"
fi

echo
echo "## Compaction"
if [ -f "$root/CLAUDE.md" ] && tr -d '\r' < "$root/CLAUDE.md" | grep -qiE '^#+[[:space:]]*compact instructions'; then
  echo "- CLAUDE.md has a Compact Instructions section"
else
  echo "- CLAUDE.md has no Compact Instructions section — see reference/session-budget.md"
fi

echo
echo "## Recent commits"
git log -5 --oneline 2>/dev/null | sed 's/^/- /'
```

- [ ] **Step 4: Run the test**

Run: `timeout 120 bash plugins/dr-superpowers/tests/repo-audit.test.sh`
Expected: `19 passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add --chmod=+x plugins/dr-superpowers/scripts/repo-audit plugins/dr-superpowers/tests/repo-audit.test.sh
git commit -m "feat(superpowers): add repo-audit orientation snapshot"
```

### Task 5: Compaction snapshot library

**Files:**
- Create: `plugins/dr-superpowers/scripts/lib/snapshot.sh`
- Test: `plugins/dr-superpowers/tests/snapshot.test.sh` (create)

**Interfaces:**
- Consumes: nothing from earlier tasks (reads the ledger and `latest.md` formats already in use)
- Produces: `snapshot_build TRANSCRIPT CWD [CAP]` (Contracts), used by Task 6

**Implementer:** dcc-superpower-companions:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/snapshot.test.sh`:

```bash
#!/usr/bin/env bash
# The compaction snapshot must carry what compaction summaries drop — the
# handoff's next step, ledger tails and rulings, files the session edited, the
# owner's last prompts, background agent ids — and stay under its cap by
# dropping the least important sections first.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/lib/snapshot.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
lacks() { # lacks <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n' "$1" "$3"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DR_SUPERPOWERS_JQ

REPO="$TMP/repo"
git init -q -b main "$REPO"
printf '.superpowers/\n' > "$REPO/.gitignore"
git -C "$REPO" add -A && git -C "$REPO" commit -qm init
WT="$TMP/wt"
git -C "$REPO" worktree add -q -b feat "$WT"
mkdir -p "$WT/.superpowers/sdd/plan"
{
  printf '# SDD ledger — plan: docs/plan.md\n'
  printf 'Ruling: translated old -> new — legacy plugin name — none\n'
  printf 'Task 1: complete (commits a..b, review clean)\n'
  printf 'Task 2: Ruling: kept the retry — spec 4.2 — a second fix round\n'
  printf 'Task 2: fix round 1/5 (1 addressed, 1 open — x)\n'
} > "$WT/.superpowers/sdd/plan/progress.md"
mkdir -p "$REPO/.superpowers/handoff"
printf '# Handoff\n\n## State\nstate\n\n## Next session\n\n**Next:** Resume at Task 2 (Two).\n\n## Do not\nKeep out of the snapshot.\n' \
  > "$REPO/.superpowers/handoff/latest.md"

prompt() { jq -cn --arg c "$1" '{type:"user",isSidechain:false,origin:{kind:"human"},message:{role:"user",content:$c}}'; }
tool() { # tool <name> <path> [isSidechain]
  jq -cn --arg n "$1" --arg p "$2" --argjson s "${3:-false}" \
    '{type:"assistant",isSidechain:$s,message:{model:"m",content:[{type:"tool_use",id:"t",name:$n,input:{file_path:$p}}]}}'
}
agent_use() { jq -cn '{type:"assistant",isSidechain:false,message:{model:"m",content:[{type:"tool_use",id:"toolu_1",name:"Agent",input:{description:"Fable review"}}]}}'; }
agent_result() { jq -cn '{type:"user",isSidechain:false,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_1",content:[{type:"text",text:"Async agent launched.\nagentId: abc123 (internal)"}]}]}}'; }
meta() { jq -cn '{type:"user",isSidechain:false,isMeta:true,message:{role:"user",content:"<command-name>/clear</command-name>"}}'; }
summary() { jq -cn '{type:"user",isSidechain:false,isCompactSummary:true,message:{role:"user",content:"This session is being continued"}}'; }

T="$TMP/t.jsonl"
{
  prompt 'please keep the API stable'
  meta
  summary
  tool Edit /repo/a.sh
  tool Write /repo/b.md
  tool Edit /repo/c.txt
  tool Read /repo/d.md
  tool Edit /repo/side.sh true
  tool Edit /repo/a.sh
  agent_use
  agent_result
  prompt 'second prompt'
  prompt 'third prompt'
  prompt 'fourth prompt'
} > "$T"

out=$(snapshot_build "$T" "$REPO")
check "heading first" "$(sed -n 1p <<<"$out")" "## Compaction snapshot"
has "handoff next step" "$out" "**Next:** Resume at Task 2 (Two)."
lacks "handoff stops at the next section" "$out" "Keep out of the snapshot."
has "ledger last line" "$out" "Task 2: fix round 1/5 (1 addressed, 1 open — x)"
has "rulings heading" "$out" "Rulings (most recent 10):"
has "ruling line" "$out" "Task 2: Ruling: kept the retry — spec 4.2 — a second fix round"
has "files heading" "$out" "### Files edited by this session (most recent first)"
check "files: most recent first, unique" \
  "$(grep -A3 '^### Files edited' <<<"$out" | tail -n 3 | tr '\n' '|')" \
  "- \`/repo/a.sh\`|- \`/repo/c.txt\`|- \`/repo/b.md\`|"
lacks "files: sidechain edits excluded" "$out" "/repo/side.sh"
lacks "files: reads excluded" "$out" "/repo/d.md"
has "prompts: the latest" "$out" "- fourth prompt"
lacks "prompts: only the last three" "$out" "please keep the API stable"
lacks "prompts: meta entries excluded" "$out" "<command-name>"
lacks "prompts: the summary excluded" "$out" "This session is being continued"
has "agents: id and description" "$out" "- abc123 — Fable review"

# --- no jq: transcript sections skipped, the rest kept ---
out=$(DR_SUPERPOWERS_JQ=no-such-jq snapshot_build "$T" "$REPO")
has "no jq: ledger kept" "$out" "Task 2: fix round 1/5"
lacks "no jq: no transcript sections" "$out" "### Files edited"

# --- cap: sections dropped from 6 up to 3 until the snapshot fits ---
LONG=$(printf '%0400d' 0)
T2="$TMP/t2.jsonl"
{ for i in $(seq 1 20); do tool Edit "/repo/$i-$LONG"; done; agent_use; agent_result; prompt 'x'; } > "$T2"
out=$(snapshot_build "$T2" "$REPO")
check "cap: at most 5500 characters" "$([ "${#out}" -le 5500 ] && echo yes || echo no)" "yes"
check "cap: heading kept" "$(sed -n 1p <<<"$out")" "## Compaction snapshot"
has "cap: handoff kept" "$out" "Resume at Task 2 (Two)."
has "cap: ledger kept" "$out" "Task 2: fix round 1/5"
lacks "cap: oversized files section dropped" "$out" "### Files edited"
lacks "cap: agents dropped" "$out" "### Background agents"

# --- an explicit cap, as the hook passes when the entry point leaves less room ---
out=$(snapshot_build "$T" "$REPO" 1500)
check "explicit cap: at most 1500 characters" "$([ "${#out}" -le 1500 ] && echo yes || echo no)" "yes"
has "explicit cap: ledger kept" "$out" "Task 2: fix round 1/5"

git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 bash plugins/dr-superpowers/tests/snapshot.test.sh`
Expected: fails at the `.` line with "No such file or directory"; exit non-zero.

- [ ] **Step 3: Create the library**

Create `plugins/dr-superpowers/scripts/lib/snapshot.sh`:

```bash
# Build the compaction snapshot: what a compaction summary drops that the next
# turn needs — the handoff's next step, ledger tails and rulings, files the
# session edited, the owner's last prompts, background agent ids. Sourced by
# scripts/session-start.sh on the compact source; defines functions only.
#
# Capped because hook output over 10,000 characters is replaced by a file
# reference, and the injected entry point already takes about 3,400.

SNAPSHOT_CAP=5500

snapshot_latest() { # CWD — the Next session block of the primary checkout's latest.md
  local common primary latest
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  primary=$(git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null) || return 0
  latest="$primary/.superpowers/handoff/latest.md"
  [ -f "$latest" ] || return 0
  echo "### From \`$latest\`"
  tr -d '\r' < "$latest" | awk '/^## Next session/ { f = 1; next } f && /^## / { exit } f'
}

snapshot_ledgers() { # CWD — every worktree's ledgers: last 8 lines, last 10 rulings
  local wt ledger plan_rel rulings
  git -C "$1" worktree list --porcelain 2>/dev/null | tr -d '\r' | sed -n 's/^worktree //p' |
  while IFS= read -r wt; do
    for ledger in "$wt"/.superpowers/sdd/*/progress.md; do
      [ -f "$ledger" ] || continue
      plan_rel=$(head -n 1 "$ledger" | tr -d '\r' | sed -n 's/^# SDD ledger — plan: //p')
      echo "### Ledger \`$ledger\` (plan \`${plan_rel:-unknown}\`)"
      echo "Last lines:"
      tr -d '\r' < "$ledger" | grep -v '^[[:space:]]*$' | tail -n 8 | sed 's/^/    /'
      rulings=$(tr -d '\r' < "$ledger" | grep 'Ruling:' | tail -n 10)
      if [ -n "$rulings" ]; then
        echo "Rulings (most recent 10):"
        printf '%s\n' "$rulings" | sed 's/^/    /'
      fi
    done
  done
}

# FILE — sections 4-6 from the transcript's last 3000 lines, separated by
# @@4 / @@5 / @@6 marker lines.
snapshot_transcript_sections() {
  tail -n 3000 "$1" | tr -d '\r' | "${DR_SUPERPOWERS_JQ:-jq}" -R -r -n '
    [inputs | select(length > 0) | (try fromjson catch null) | objects
     | select((.isSidechain // false) == false)] as $e
    | ([$e[] | select(.type == "assistant") | .message.content[]?
        | select(type == "object" and .type == "tool_use"
                 and (.name == "Write" or .name == "Edit" or .name == "NotebookEdit"))
        | (.input.file_path // .input.notebook_path // empty)]
       | reverse | reduce .[] as $f ([]; if any(.[]; . == $f) then . else . + [$f] end)
       | .[:20]) as $files
    | ([$e[] | select(.type == "user" and ((.isCompactSummary // false) | not)
                      and ((.isMeta // false) | not)
                      and ((.message.content | type) == "string")
                      and ((.origin.kind // "") == "human"
                           or (.origin == null and (.message.content | startswith("<") | not))))
        | .message.content | gsub("\\s+"; " ") | .[:300]] | .[-3:]) as $prompts
    | ([$e[] | select(.type == "assistant") | .message.content[]?
        | select(type == "object" and .type == "tool_use" and .name == "Agent")
        | {key: .id, value: (.input.description // "")}] | from_entries) as $desc
    | ([$e[] | select(.type == "user") | .message.content | arrays | .[]
        | select(type == "object" and .type == "tool_result" and ($desc[.tool_use_id] != null))
        | . as $r
        | ([.content] | flatten | map(if type == "object" then (.text // "") else tostring end) | join(" "))
        | capture("agentId: (?<id>[A-Za-z0-9]+)")?
        | "\(.id) — \($desc[$r.tool_use_id])"] | .[-5:]) as $agents
    | "@@4",
      (if ($files | length) > 0
       then "### Files edited by this session (most recent first)", ($files[] | "- `\(.)`")
       else empty end),
      "@@5",
      (if ($prompts | length) > 0
       then "### The owner'"'"'s last prompts (verbatim, truncated)", ($prompts[] | "- \(.)")
       else empty end),
      "@@6",
      (if ($agents | length) > 0
       then "### Background agents (resume by id while still running)", ($agents[] | "- \(.)")
       else empty end)
  ' 2>/dev/null
}

# snapshot_build TRANSCRIPT CWD [CAP] — the markdown snapshot, at most CAP
# characters (default SNAPSHOT_CAP). Sections 6, 5, 4, 3 are dropped whole, in
# that order, until it fits; sections 1-2 are never dropped.
snapshot_build() {
  local tp=${1:-} cwd=${2:-$PWD} cap=${3:-$SNAPSHOT_CAP} s1 s2 s3 s4="" s5="" s6="" raw out part i
  s1='## Compaction snapshot

This session was just compacted. Trust this snapshot, the ledger and `git log`
over the summary above. If anything is unclear, run `scripts/repo-audit` from the
dr-superpowers plugin root; if the next budget line says `handoff`, run the
dr-superpowers handoff skill.'
  s2=$(snapshot_latest "$cwd")
  s3=$(snapshot_ledgers "$cwd")
  if [ -n "$tp" ] && command -v "${DR_SUPERPOWERS_JQ:-jq}" >/dev/null 2>&1; then
    if command -v cygpath >/dev/null 2>&1; then tp=$(cygpath -u "$tp"); fi
    if [ -f "$tp" ]; then
      raw=$(snapshot_transcript_sections "$tp")
      s4=$(printf '%s\n' "$raw" | awk '/^@@4$/ { f = 1; next } /^@@5$/ { f = 0 } f')
      s5=$(printf '%s\n' "$raw" | awk '/^@@5$/ { f = 1; next } /^@@6$/ { f = 0 } f')
      s6=$(printf '%s\n' "$raw" | awk '/^@@6$/ { f = 1; next } f')
    fi
  fi
  for i in 6 5 4 3 0; do
    out=""
    for part in "$s1" "$s2" "$s3" "$s4" "$s5" "$s6"; do
      [ -n "$part" ] && out+="$part"$'\n\n'
    done
    [ "${#out}" -le "$cap" ] && break
    case $i in 6) s6="" ;; 5) s5="" ;; 4) s4="" ;; 3) s3="" ;; esac
  done
  printf '%s\n' "${out%$'\n\n'}"
}
```

- [ ] **Step 4: Run the test**

Run: `timeout 120 bash plugins/dr-superpowers/tests/snapshot.test.sh`
Expected: `25 passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/snapshot.sh
git add --chmod=+x plugins/dr-superpowers/tests/snapshot.test.sh
git commit -m "feat(superpowers): build the compaction snapshot"
```

### Task 6: SessionStart hook injects the snapshot on compact

**Files:**
- Modify: `plugins/dr-superpowers/scripts/session-start.sh:10-11,30-31,48-49`
- Modify: `plugins/dr-superpowers/hooks/hooks.json:2` (description only)
- Test: `plugins/dr-superpowers/tests/hook.test.sh:66` (insert before `# --- hooks.json wiring ---`)

**Interfaces:**
- Consumes: `snapshot_build TRANSCRIPT CWD` (Task 5)
- Produces: on `source == "compact"`, `additionalContext` = entry point, a blank line, then the snapshot; other sources unchanged

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/hook.test.sh`, insert before the line `# --- hooks.json wiring ---`:

```bash
# --- compact source: the snapshot follows the entry point ---
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" commit -q --allow-empty -m init
mkdir -p "$REPO/.superpowers/handoff"
printf '# Handoff\n\n## Next session\n\n**Next:** Resume at Task 4 (Four).\n' > "$REPO/.superpowers/handoff/latest.md"
TR="$TMP/transcript.jsonl"
MSYS_NO_PATHCONV=1 jq -cn '{type:"user",isSidechain:false,origin:{kind:"human"},message:{role:"user",content:"keep the API stable"}}' > "$TR"
compact_payload() {
  MSYS_NO_PATHCONV=1 jq -n --arg tp "$TR" --arg cwd "$REPO" \
    '{hook_event_name:"SessionStart",session_id:"s-9",transcript_path:$tp,cwd:$cwd,source:"compact"}'
}
HOME_D="$TMP/d"; mkdir -p "$HOME_D"
out=$(compact_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null)
status=$?
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
check "compact: exits 0" "$status" "0"
check "compact: emits valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$out" && echo yes || echo no)" "yes"
check "compact: entry point still injected" "$(grep -c 'dr-superpowers:using-superpowers' <<<"$ctx")" "1"
check "compact: snapshot appended" "$(grep -c '^## Compaction snapshot' <<<"$ctx")" "1"
check "compact: carries the handoff next step" "$(grep -c 'Resume at Task 4 (Four)' <<<"$ctx")" "1"
check "compact: carries the owner prompt" "$(grep -c 'keep the API stable' <<<"$ctx")" "1"
check "compact: under the 10,000-character hook cap" "$([ "${#ctx}" -lt 10000 ] && echo yes || echo no)" "yes"
startup_ctx=$(payload | HOME="$HOME_A" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
check "startup: no snapshot" "$(grep -c '^## Compaction snapshot' <<<"$startup_ctx")" "0"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 bash plugins/dr-superpowers/tests/hook.test.sh`
Expected: FAIL on "compact: snapshot appended", "compact: carries the handoff next step" and "compact: carries the owner prompt"; exit non-zero.

- [ ] **Step 3: Wire the snapshot into the hook**

In `plugins/dr-superpowers/scripts/session-start.sh`, replace lines 1-4 (the header comment):

```bash
#!/usr/bin/env bash
# SessionStart hook: inject the using-superpowers entry point and persist the
# session's transcript path for the budget tooling. Injection must survive a
# missing jq or malformed stdin; only persistence is allowed to degrade.
```

with:

```bash
#!/usr/bin/env bash
# SessionStart hook: inject the using-superpowers entry point, persist the
# session's transcript path for the budget tooling, and on the compact source
# append the compaction snapshot (scripts/lib/snapshot.sh). Injection must
# survive a missing jq or malformed stdin; persistence and the snapshot's
# transcript sections are allowed to degrade.
```

Replace line 10:

```bash
stdin_json="$(cat 2>/dev/null || true)"
```

with:

```bash
stdin_json="$(cat 2>/dev/null || true)"
transcript_path="" cwd=""
```

After the line that assigns `context="<EXTREMELY_IMPORTANT>…</EXTREMELY_IMPORTANT>"`, insert:

```bash

# The compact source is detected without jq, so a machine without jq still
# gets the handoff and ledger sections. Hook output over 10,000 characters is
# replaced by a file reference, so the snapshot gets only the room the entry
# point leaves, with headroom for the wrapper text.
if grep -qE '"source"[[:space:]]*:[[:space:]]*"compact"' <<<"$stdin_json" \
   && . "${SCRIPT_DIR}/lib/snapshot.sh" 2>/dev/null; then
  cap=$(( 9500 - ${#content} - 400 ))
  [ "$cap" -le "$SNAPSHOT_CAP" ] || cap=$SNAPSHOT_CAP
  if [ "$cap" -gt 1000 ]; then
    snapshot=$(snapshot_build "$transcript_path" "${cwd:-$PWD}" "$cap" 2>/dev/null || true)
    if [ -n "$snapshot" ]; then
      context="${context}\n\n$(escape_for_json "$snapshot")"
    fi
  fi
fi
```

In `plugins/dr-superpowers/hooks/hooks.json`, replace the `description` value with:

```json
  "description": "Injects the dr-superpowers entry point at session start, persists the session's transcript path for budget tooling, and appends a compaction snapshot after compaction.",
```

- [ ] **Step 4: Run the tests**

Run: `timeout 120 bash plugins/dr-superpowers/tests/hook.test.sh && timeout 120 bash plugins/dr-superpowers/tests/snapshot.test.sh`
Expected: both end `… passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/session-start.sh plugins/dr-superpowers/hooks/hooks.json plugins/dr-superpowers/tests/hook.test.sh
git commit -m "feat(superpowers): inject snapshot after compaction"
```

### Task 7: `handoff` and `resume-execution` skills, `reference/session-budget.md`

**Files:**
- Create: `plugins/dr-superpowers/skills/handoff/SKILL.md`
- Create: `plugins/dr-superpowers/skills/resume-execution/SKILL.md`
- Create: `plugins/dr-superpowers/reference/session-budget.md`

**Interfaces:**
- Consumes: `context-size`, the budget line, `repo-audit`, `sdd-workspace`, `next-step` and its current usage (Tasks 2-4; `--draft` lands in Task 8)
- Produces: skill names `dr-superpowers:handoff` and `dr-superpowers:resume-execution`; the `handoff.md` and `latest.md` section formats (Contracts), used by Tasks 8-11

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Confirm the names do not resolve yet**

Run: `printf 'see dr-superpowers:handoff and dr-superpowers:resume-execution\n' > plugins/dr-superpowers/reference/zz-probe.md && timeout 60 node scripts/validate-repository.mjs; rm plugins/dr-superpowers/reference/zz-probe.md`
Expected: exit non-zero with `unresolved dr-superpowers reference handoff` and `… resume-execution`.

- [ ] **Step 2: Create the handoff skill**

Create `plugins/dr-superpowers/skills/handoff/SKILL.md`:

````markdown
---
name: handoff
description: Use when a budget line says handoff, at a hard phase stop (plan saved, every plan task complete), after 3 Codex tasks or a task that needed 3+ fix rounds, or when your human partner steps away or asks to stop - ends the session with durable handoff files and a resume guide
---

# Handoff

End this session so a fresh one continues without loss. Past its budget a
session re-reads its whole context on every request, and near the auto-compact
point compaction drops the reports, findings and rulings a controller needs.
A fresh session reloads only its baseline plus these files. The numbers are in
[session-budget.md](../../reference/session-budget.md).

**Announce at start:** "I'm using the handoff skill to end this session cleanly."

## When

- A budget line — printed by `scripts/task-brief`, `scripts/review-package`
  and `scripts/context-size` — said `handoff`. Act at the next ledger write,
  never mid-dispatch: finish the step you are in, write the ledger line that
  records it, then hand off.
- A hard stop: the plan is saved, or every plan task is complete (the final
  whole-branch review runs in a fresh session).
- On Codex: after every 3 completed tasks, or after any task that needed 3 or
  more fix rounds.
- Your human partner says they are stepping away for more than an hour, or
  asks you to stop.

## Steps

1. **Make the durable record current.**
   - Execution: the ledger's last line records where you are (a
     `Task N: complete`, a `fix round R/5`, or an assigned line). Update
     `<workspace>/handoff.md` (below); `<workspace>` is the directory
     `scripts/sdd-workspace PLAN_FILE` prints.
   - Design phase (brainstorming, a spec, a plan in progress): save the draft
     file. It is the authority.
2. **Commit the plan and the spec** if either has uncommitted changes, in a
   `docs(<scope>): …` commit of their own. Never commit `.superpowers/`.
3. **Write the notes sections of `latest.md`** at
   `<primary checkout>/.superpowers/handoff/latest.md`. The primary checkout is
   `git -C "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" rev-parse --show-toplevel`.
   Replace everything above `## Next session` with exactly these sections,
   each under 15 lines:

   ```markdown
   # Handoff — <YYYY-MM-DD> (<budget | phase stop | Codex count | owner request>)

   ## State
   - Worktree: `<absolute worktree path>` (branch `<branch>`, HEAD `<sha7>`)
   - Plan: `<plan path>`; ledger: `<workspace>/progress.md`; handoff: `<workspace>/handoff.md`
   - <one line on where the work stands>

   ## Gotchas
   - <what the next session would otherwise rediscover>

   ## Do not
   - <owner constraints and prohibitions>
   ```

   In a design phase, `State` names the draft instead of a plan and ledger.
4. **Run `scripts/next-step`**, from the plugin root (two levels above this
   skill's directory):
   - Execution: `scripts/next-step PLAN_FILE`.
   - Design phase: `scripts/next-step --draft DRAFT_FILE --next "<the next action, naming its skill>"`,
     for example `--next "Write the implementation plan with dr-superpowers:writing-plans."`
   It prints the `## Next session` block and writes it into `latest.md`. If it
   exits 4, say `latest.md` could not be written.
5. **End the session.** Your final message is one line on why you stopped,
   then the block, verbatim, as the last thing. The block is the resume guide:
   the launch command, the directory to launch it in, and the first prompt.

## handoff.md

`<workspace>/handoff.md` holds what the ledger cannot, in under 40 lines:

```markdown
# Handoff notes — <plan path>

## Owner constraints
- <a constraint your human partner gave during execution, verbatim>

## Gotchas
- <a tooling or environment surprise and its workaround>

## Do not
- <a prohibition>

## Open questions
- <a question for your human partner, and what you assumed meanwhile>
```

dr-superpowers:subagent-driven-development writes it at Setup and updates it
in the same message as a ledger write whenever one of these sections changes —
not after every task: task state lives in the ledger and git.

## Red Flags

| Thought | Reality |
|---------|---------|
| "One more dispatch, then I'll hand off" | The verdict is acted on at the next ledger write. Record the step you are in; start nothing new. |
| "The next session can read my summary" | It has none of your context. Only files cross the boundary. |
| "I'll write the resume prompt myself" | `next-step` computes it from the plan and ledger. Hand-written guides go stale. |
| "Compaction will take care of it" | Compaction drops reports, findings and rulings. Hand off before it fires. |
````

- [ ] **Step 3: Create the resume-execution skill**

Create `plugins/dr-superpowers/skills/resume-execution/SKILL.md`:

````markdown
---
name: resume-execution
description: Use when continuing a plan's execution in a fresh session after a handoff or compaction - verifies the worktree against the ledger, reloads the durable record, and hands control to the plan's execution skill
---

# Resume Execution

**Announce at start:** "I'm using the resume-execution skill to pick up <plan>."

The durable record — `latest.md`, the ledger, `handoff.md` and git — is the
authority. Your context is empty by design: do not reconstruct the previous
session from memory or from a summary.

## Steps

1. **Orient in one call.** Run `scripts/repo-audit`, from the plugin root (two
   levels above this skill's directory). Read
   `<primary checkout>/.superpowers/handoff/latest.md`; the audit prints its path.
2. **Verify the worktree** named in latest.md's `## State` against
   `git worktree list --porcelain`. Normalise both paths before comparing:
   forward slashes, lowercase drive letter, no trailing slash
   (`D:\Repos\x`, `D:/Repos/x` and `/d/Repos/x` are one path).
   - Listed: continue.
   - Missing, but its branch still exists (`git branch --list <branch>`): run
     `git worktree prune`, then `git worktree add <path> <branch>`, and log
     `Ruling: re-added worktree <path> for <branch> — stale registration — none`
     in the ledger once you can read it.
   - Missing, and the branch is gone: stop and ask your human partner. The
     work may have been merged or discarded; guessing either way is worse than
     asking.
3. **Enter the worktree** (EnterWorktree with its path on Claude Code; `cd`
   elsewhere). Take the head commit of the ledger's last `Task N: complete`
   line and check `git merge-base --is-ancestor <sha> HEAD`. If it fails, the
   history was rewritten after the handoff: log
   `Ruling: HEAD no longer descends from <sha> — history rewritten after the handoff — tasks re-verified from git log`
   and continue from the ledger plus `git log`.
4. **Reload** `<workspace>/handoff.md`, the plan's header (everything above its
   first `### Task`), and the ledger. The owner constraints and do-nots in
   `handoff.md` bind you as if your human partner had just said them.
5. **Continue** with what latest.md's `**Next:**` line says:
   - Start or resume at Task N: invoke the skill the plan's `**Execution:**`
     line names — dr-superpowers:subagent-driven-development for `subagent`,
     dr-superpowers:executing-plans for `inline`. Its ledger recovery takes over.
   - Run the final whole-branch review: invoke
     dr-superpowers:subagent-driven-development; with every task complete it
     goes straight to its Final Review section.
   - Run finishing: invoke dr-superpowers:finishing-a-development-branch.

## Red Flags

| Thought | Reality |
|---------|---------|
| "The summary says Task 5 is done" | Only a `Task 5: complete` ledger line says that. |
| "The worktree is gone — I'll recreate the branch from main" | A missing branch means merged or discarded. Ask. |
| "I'll look around instead of running repo-audit" | Looking around costs five to eight requests at a fresh session's full reload; the audit is one. |
````

- [ ] **Step 4: Create the reference file**

Create `plugins/dr-superpowers/reference/session-budget.md`:

````markdown
# Session budget

The numbers and rules behind dr-superpowers' handoffs. The cost model they rest
on is §3 of the program design
(`docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`).

## Numbers

| Item | Value | Source |
|------|-------|--------|
| Handoff budget | 475,000 tokens; `DR_SUPERPOWERS_BUDGET` overrides | Owner ruling, 2026-09-11 |
| `autoCompactWindow` | 650,000, in `~/.claude/settings.json` | Set 2026-09-11 |
| Where auto-compaction fires | About 93-96% of the window: 467k, 467k and 479k observed at 500,000 | Inference from three transcripts |
| Hook output cap | 10,000 characters; longer output becomes a file reference | Claude Code hooks reference |
| Skill bodies after compaction | First 5,000 tokens per skill, 25,000 in total, oldest dropped | Claude Code context-window docs |
| Codex | Hand off every 3 tasks, or after a task that needed 3+ fix rounds | Program design R7 |

The budget has to sit below the point where compaction fires by more than one
task's growth — a controller adds about 140k across a long fix loop. At a
650,000 window compaction lands near 605-625k, so 475k leaves that margin.

## The budget line

```
budget: 312k of 475k (65%) — ok — source: record
budget: 480k of 475k (101%) — handoff — source: record
budget: unknown of 475k — unknown — no transcript found
```

`source` is `record` (the SessionStart hook's session record), `record?` (a
newer transcript exists in the same directory: two sessions may share it) or
`guessed` (no record; the newest transcript for the directory). `unknown` means
apply the count rule on Codex and the phase stops everywhere.

`scripts/task-brief` and `scripts/review-package` print it as their last line,
so checking before every task and every review costs no extra request.
`scripts/context-size` prints it on demand (exit 0 ok, 5 handoff, 3 unknown);
`scripts/repo-audit` includes it.

## Checkpoints

- **subagent-driven-development:** every `task-brief` and `review-package`. On
  `handoff`, act at the next ledger write.
- **executing-plans:** `context-size` after each `Task N: complete` line.
- **brainstorming:** `context-size` once, after the spec is committed.
- **Anywhere:** `context-size` when in doubt.

## Stops

- **Hard:** the plan is saved; every plan task is complete under
  subagent-driven-development (the final review runs in a fresh session).
- **Soft:** the final review is clean; executing-plans' last task is complete.
  Finishing follows in the same session unless the budget line says `handoff`.
- **Budget:** a `handoff` verdict at any checkpoint.
- **Codex:** the count rule above.

Every stop runs dr-superpowers:handoff.

## Idle

After more than an hour idle the one-hour prompt cache is cold: the next
request re-writes the whole context at twice the input price. Start a fresh
session from `latest.md` rather than continuing (Claude Code also offers
"Resume from summary" in that case), and hand off before a planned break.

## After compaction

The SessionStart hook appends a compaction snapshot (`scripts/lib/snapshot.sh`):
the handoff's next step, ledger tails and rulings, the files the session
edited, the owner's last three prompts and background agent ids. Trust it, the
ledger and `git log` over the summary. The long execution skills open with an
"After compaction" block because only their first 5,000 tokens come back.

## Compact Instructions for CLAUDE.md

Claude Code re-reads the project-root CLAUDE.md after compaction and uses a
"Compact Instructions" section to shape the summary. Paste this into it:

```markdown
# Compact instructions

Preserve verbatim: the worktree path; the plan, ledger and handoff paths; the
current HEAD; every owner constraint and prohibition; every `Ruling:` line; and
every open question. Name the task in progress and its fix round.
```

`scripts/repo-audit` reports whether the section is present.
````

- [ ] **Step 5: Verify**

Run: `timeout 60 node scripts/validate-repository.mjs`
Expected: exit 0 with no output about `handoff`, `resume-execution` or `session-budget.md`.

Run: `for s in handoff resume-execution; do sed -n 2p "plugins/dr-superpowers/skills/$s/SKILL.md"; done`
Expected: `name: handoff` then `name: resume-execution`.

Run: `timeout 120 claude plugin validate plugins/dr-superpowers`
Expected: validation passes.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/skills/handoff plugins/dr-superpowers/skills/resume-execution plugins/dr-superpowers/reference/session-budget.md
git commit -m "feat(superpowers): add handoff and resume skills"
```

### Task 8: next-step: draft mode, resume routing, final-review state

**Files:**
- Modify (full replacement): `plugins/dr-superpowers/scripts/next-step`
- Test: `plugins/dr-superpowers/tests/next-step.test.sh:87` and `:177` (insertions)

**Interfaces:**
- Consumes: `plan_tasks`, `ledger_done` (Task 1); skill names `dr-superpowers:resume-execution`, `dr-superpowers:finishing-a-development-branch` (Task 7 and existing)
- Produces: `next-step --draft DRAFT_FILE --next ACTION`; resume prompts naming resume-execution whenever the plan has a ledger; the `Final review: clean` state (used by Tasks 9-10)

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/next-step.test.sh`, after line 87 (`has "mid-plan: prompt points at the ledger" …`), insert:

```bash
has "mid-plan: prompt routes through resume-execution" "$out" "Resume \`$PLAN_REL\` with dr-superpowers:resume-execution. Resume at Task 3 (Third thing)."
```

Before the line `# --- usage errors ---`, insert:

```bash
# --- final review clean: finishing is next ---
ledger 'Task 1: complete (x)' 'Task 2: complete (x)' 'Task 3: complete (x)' 'Final review: clean (commits a1b2c3d..d4e5f6a)'
run "$REPO" "$PLAN_REL"
has "final review clean: status" "$out" "**Status:** Plan \`$PLAN_REL\`: all 3 tasks complete; the final review is clean."
has "final review clean: next is finishing" "$out" "**Next:** Run dr-superpowers:finishing-a-development-branch."
has "final review clean: prompt routes through resume-execution" "$out" "Resume \`$PLAN_REL\` with dr-superpowers:resume-execution. Run dr-superpowers:finishing-a-development-branch."
rm -rf "$LEDGER_DIR"

# --- draft mode: a design phase hands off ---
mkdir -p "$REPO/docs/specs" "$REPO/.superpowers/handoff"
printf '# Draft\n' > "$REPO/docs/specs/draft.md"
printf '# Handoff\n\n## State\nKeep me.\n\n## Next session\nOld block.\n' > "$HANDOFF"
run "$REPO" --draft docs/specs/draft.md --next "Write the implementation plan with dr-superpowers:writing-plans"
check "draft: exits 0" "$status" "0"
has "draft: status names the authority" "$out" "**Status:** Design in progress: \`docs/specs/draft.md\` is the authority."
has "draft: next action gains a full stop" "$out" "**Next:** Write the implementation plan with dr-superpowers:writing-plans."
has "draft: planning launch command" "$out" "claude --model opus --effort high"
has "draft: prompt" "$out" "Continue from \`docs/specs/draft.md\` (the authority): Write the implementation plan with dr-superpowers:writing-plans. Read \`.superpowers/handoff/latest.md\` first."
hand=$(cat "$HANDOFF")
has "draft: handoff keeps the notes" "$hand" "Keep me."
lacks "draft: handoff drops the stale block" "$hand" "Old block."
run "$REPO" --draft docs/specs/draft.md
check "draft without --next: exits 2" "$status" "2"
run "$REPO" --draft docs/specs/missing.md --next "x"
check "draft of a missing file: exits 2" "$status" "2"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 bash plugins/dr-superpowers/tests/next-step.test.sh`
Expected: FAIL on the resume-execution, final-review-clean and draft checks; exit non-zero.

- [ ] **Step 3: Replace next-step**

Replace the whole of `plugins/dr-superpowers/scripts/next-step` with:

```bash
#!/usr/bin/env bash
# Print the one next action — for a plan: start, resume, final review,
# finishing, next program sub-project, or nothing; for a design draft: its
# next step — as a "## Next session" block, and write the same block into the
# primary checkout's .superpowers/handoff/latest.md.
#
# Sessions end by pasting this block verbatim, so what comes next is computed
# here rather than remembered by the model: small executors reliably forget to
# say it, and a hand-written handoff goes stale the moment work moves on.
#
# Usage: next-step [--complete] PLAN_FILE
#        next-step --draft DRAFT_FILE --next ACTION
#   --complete  the plan is finished and its branch integrated; the ledger may
#               already be deleted. Replaces latest.md wholesale.
#   --draft     a design phase (brainstorming, a spec, a plan being written) is
#               handing off; DRAFT_FILE is the authority and ACTION names the
#               next step and its skill.
# Exit: 0 ok; 2 usage or missing file; 3 plan has no tasks; 4 block printed but
#       latest.md could not be written.
set -euo pipefail

usage() { echo "usage: next-step [--complete] PLAN_FILE | next-step --draft DRAFT_FILE --next ACTION" >&2; exit 2; }
. "$(cd "$(dirname "$0")" && pwd)/lib/plan.sh"

complete=0 draft=0 next_action=""
case "${1:-}" in
  --complete) complete=1; shift ;;
  --draft)
    draft=1; shift
    { [ $# -eq 3 ] && [ "$2" = "--next" ] && [ -n "$3" ]; } || usage
    next_action=$3
    set -- "$1"
    ;;
esac
[ $# -eq 1 ] || usage
plan=$1
[ -f "$plan" ] || { echo "no such file: $plan" >&2; exit 2; }

root=$(git rev-parse --show-toplevel)
common=$(git rev-parse --path-format=absolute --git-common-dir)
primary=$(git -C "$(dirname "$common")" rev-parse --show-toplevel)

root_posix=$(cd "$root" && pwd)
plan_abs="$(cd "$(dirname "$plan")" && pwd)/$(basename "$plan")"
rel=${plan_abs#"$root_posix"/}
slug=$(basename "$plan" .md)

status_line="" next_line="" prompt="" launch=1 dir="$primary" launch_cmd=""

if [ "$draft" -eq 1 ]; then
  case $next_action in *[.!?]) ;; *) next_action="$next_action." ;; esac
  status_line="Design in progress: \`$rel\` is the authority."
  next_line=$next_action
  launch_cmd="claude --model opus --effort high"
  prompt="Continue from \`$rel\` (the authority): $next_action Read \`.superpowers/handoff/latest.md\` first."
else
  plan_text=$(tr -d '\r' < "$plan")
  tasks=$(plan_tasks "$plan")
  [ -n "$tasks" ] || { echo "no tasks in ${plan} (no heading matching 'Task N')" >&2; exit 3; }
  total=$(wc -l <<<"$tasks" | tr -d ' ')

  header_line() { # first unfenced line starting with **<label>:**
    awk -v p="^\\\\*\\\\*$1:\\\\*\\\\*" '/^```/ { f = !f } !f && $0 ~ p { print; exit }' <<<"$plan_text"
  }
  execution=$(header_line Execution)
  program=$(header_line Program)

  launch_cmd=$(grep -oE 'claude --model [^ `]+ --effort [^ `]+' <<<"$execution" | head -n 1 || true)
  skill=subagent-driven-development
  if grep -qE '^\*\*Execution:\*\*[ \t]*`?inline' <<<"$execution"; then skill=executing-plans; fi

  ledger_shown="$root/.superpowers/sdd/$slug/progress.md"
  ledger_file="$root_posix/.superpowers/sdd/$slug/progress.md"
  ledger_note="no ledger at \`$ledger_shown\`"
  ledger_text=""
  done_tasks=""
  has_ledger=0
  if [ "$complete" -eq 0 ] && [ -f "$ledger_file" ]; then
    ledger_text=$(tr -d '\r' < "$ledger_file")
    if head -n 1 <<<"$ledger_text" | grep -qF "plan: $rel"; then
      has_ledger=1
      ledger_note="ledger \`$ledger_shown\`"
      done_tasks=$(ledger_done "$ledger_file")
    else
      ledger_note="the ledger at \`$ledger_shown\` belongs to another plan and is ignored"
    fi
  fi

  if [ "$complete" -eq 1 ]; then
    spec=$(sed -E 's/^\*\*Program:\*\*[ \t]*`?([^` \t]+)`?.*/\1/' <<<"$program")
    k=$(grep -oE 'sub-project [0-9]+ of [0-9]+' <<<"$program" | head -n 1 | awk '{print $2}' || true)
    n=$(grep -oE 'sub-project [0-9]+ of [0-9]+' <<<"$program" | head -n 1 | awk '{print $4}' || true)
    next_title=$(sed -nE 's/.*[Nn]ext:[ \t]*(.*[^ \t])[ \t]*$/\1/p' <<<"$program")
    launch=0
    if [ -z "$program" ]; then
      status_line="Plan \`$rel\` is complete."
      next_line="Nothing — the plan records no follow-on work."
    elif grep -qiE '(^|[^a-z])last[ \t.]*$' <<<"$program" || { [ -n "$k" ] && [ "$k" -ge "$n" ]; }; then
      status_line="Plan \`$rel\` is complete${k:+; sub-project $k of $n is done}."
      next_line="Nothing — every sub-project of \`$spec\` is done."
    elif [ -n "$next_title" ] && [ -n "$k" ]; then
      k1=$((k + 1))
      status_line="Plan \`$rel\` is complete; sub-project $k of $n is done."
      next_line="Sub-project $k1 ($next_title): write its spec in a fresh session."
      launch_cmd="claude --model opus --effort high"
      prompt="Start sub-project $k1 ($next_title) of the program in \`$spec\`: use dr-superpowers:brainstorming to write its spec."
      launch=1
    else
      status_line="Plan \`$rel\` is complete."
      next_line="Read \`$spec\` for the sub-project after ${k:-this one} — the plan's Program line names no next step."
    fi
  else
    first_open="" open_title="" done_count=0
    while IFS=$'\t' read -r num title; do
      if grep -qx "$num" <<<"$done_tasks"; then
        done_count=$((done_count + 1))
      elif [ -z "$first_open" ]; then
        first_open=$num open_title=$title
      fi
    done <<<"$tasks"

    if [ -z "$first_open" ]; then
      if [ "$has_ledger" -eq 1 ] && grep -q '^Final review: clean' <<<"$ledger_text"; then
        status_line="Plan \`$rel\`: all $total tasks complete; the final review is clean."
        next_line="Run dr-superpowers:finishing-a-development-branch."
      else
        status_line="Plan \`$rel\`: all $total tasks complete."
        next_line="Run the final whole-branch review, then dr-superpowers:finishing-a-development-branch."
      fi
    elif [ "$done_count" -eq 0 ]; then
      status_line="Plan \`$rel\`: 0 of $total tasks complete ($ledger_note)."
      next_line="Start at Task $first_open ($open_title)."
    else
      status_line="Plan \`$rel\`: $done_count of $total tasks complete ($ledger_note)."
      next_line="Resume at Task $first_open ($open_title)."
    fi

    # With a ledger there is state to verify before continuing, which is
    # resume-execution's job; without one the plan simply starts.
    if [ "$has_ledger" -eq 1 ]; then
      prompt="Resume \`$rel\` with dr-superpowers:resume-execution. $next_line"
    else
      prompt="Continue \`$rel\` with dr-superpowers:$skill. $next_line"
    fi
    if [ "$root" != "$primary" ]; then
      prompt="$prompt First enter the existing worktree \`$root\`."
    fi
    if [ "$has_ledger" -eq 1 ]; then
      prompt="$prompt Progress ledger: \`$ledger_shown\` — trust its \`Task N: complete\` lines."
    fi
  fi
fi

block=$(
  printf '## Next session\n\n**Status:** %s\n**Next:** %s\n' "$status_line" "$next_line"
  if [ "$launch" -eq 1 ]; then
    if [ -n "$launch_cmd" ]; then
      printf '\nLaunch in `%s`:\n\n```\n%s\n```\n' "$dir" "$launch_cmd"
    else
      printf '\nLaunch: see the **Execution:** line in `%s`.\n' "$rel"
    fi
    printf '\nPaste as the first prompt:\n\n```\n%s\n```\n' "$prompt"
  fi
)
printf '%s\n' "$block"

handoff="$primary/.superpowers/handoff/latest.md"
today=$(date -u +%Y-%m-%d)
write_handoff() {
  mkdir -p "$(dirname "$handoff")" || return 1
  if [ "$complete" -eq 1 ] || [ ! -f "$handoff" ]; then
    printf '# Handoff — %s\n\n%s\n' "$today" "$block" > "$handoff.tmp" || return 1
  else
    # Replace only the Next session section; the rest is the session's own notes.
    BLOCK="$block" awk '
      /^## Next session[ \t\r]*$/ { print ENVIRON["BLOCK"]; skip = 1; found = 1; next }
      skip && /^## / { skip = 0; print "" }
      !skip { print }
      END { if (!found) { print ""; print ENVIRON["BLOCK"] } }
    ' "$handoff" > "$handoff.tmp" || return 1
  fi
  mv "$handoff.tmp" "$handoff"
}
if ! write_handoff 2>/dev/null; then
  rm -f "$handoff.tmp" 2>/dev/null || true
  echo "next-step: could not write $handoff — copy the block above into it by hand" >&2
  exit 4
fi
```

- [ ] **Step 4: Run the tests**

Run: `timeout 120 bash plugins/dr-superpowers/tests/next-step.test.sh && timeout 120 bash plugins/dr-superpowers/tests/plan-lib.test.sh && timeout 60 node scripts/validate-repository.mjs`
Expected: both suites end `… passed, 0 failed`; the validator exits 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/next-step plugins/dr-superpowers/tests/next-step.test.sh
git commit -m "feat(superpowers): route resumes and drafts in next-step"
```

### Task 9: subagent-driven-development and executing-plans checkpoints

**Files:**
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` (lines 6-7, 130, 159-160, 187-188, 347-349, 273, 303-305, 307, 609-611, 651, 660-663, 731, 736)
- Modify: `plugins/dr-superpowers/skills/executing-plans/SKILL.md` (lines 6-7, 32)

**Interfaces:**
- Consumes: the budget line (Task 3), `context-size` (Task 2), `dr-superpowers:handoff` and `dr-superpowers:resume-execution` (Task 7), the `Final review: clean` state (Task 8)
- Produces: the `Final review: clean (commits <a7>..<b7>[, K parked])` ledger line; workspace deletion handed to finishing (Task 10)

**Implementer:** dcc-superpower-companions:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Record the current state**

Run: `grep -c "delete this plan's workspace" plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md; grep -c '^## After compaction' plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md plugins/dr-superpowers/skills/executing-plans/SKILL.md`
Expected: `4`, then `…SKILL.md:0` for both files.

- [ ] **Step 2: subagent-driven-development — After compaction block**

In `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, replace:

```markdown
# Subagent-Driven Development

## Select the host first
```

with:

```markdown
# Subagent-Driven Development

## After compaction

If this session was compacted — a compaction snapshot or summary sits above —
your memory of the run is gone, and only the start of this file may have come
back. Before anything else:

1. Run `scripts/sdd-workspace PLAN_FILE`, from the plugin root (two levels
   above this skill's directory), and read `progress.md` and `handoff.md` in
   the directory it prints.
2. Trust the ledger and `git log` over the summary. For each task the last
   ledger line decides: `complete` is done; `fix round R/5` resumes at round
   R+1 with a fresh dispatch; an assigned line with commits after its base
   goes to review.
3. Run `scripts/context-size`. On exit 5, invoke dr-superpowers:handoff.
4. Re-read this skill in full before the next dispatch.

## Select the host first
```

- [ ] **Step 3: subagent-driven-development — process graph**

Replace all three occurrences of the node label `Final review clean: delete this plan's workspace` with `Final review clean: ledger it, print rulings` (lines 130, 159, 160; the text is identical in each).

- [ ] **Step 4: subagent-driven-development — Setup keeps handoff.md**

Replace:

```markdown
- Create the ledger with its identity as the first line:
  `# SDD ledger — plan: <plan file path>`.
```

with:

```markdown
- Create the ledger with its identity as the first line:
  `# SDD ledger — plan: <plan file path>`.
- Create `<workspace>/handoff.md` from the template in dr-superpowers:handoff
  if it does not exist. Update it in the same message as a ledger write
  whenever an owner constraint, gotcha, prohibition or open question changes —
  not after every task.
```

- [ ] **Step 5: subagent-driven-development — task-brief output**

Replace:

```markdown
  to a uniquely named file and prints `wrote <path>: <N> lines`. Read the path
  out of that line; do not pipe the output into a prompt as if it were a
  filename.
```

with:

```markdown
  to a uniquely named file and prints `wrote <path>: <N> lines`, then the
  budget line (see Session Budget). Read the path out of the first line; do
  not pipe the output into a prompt as if it were a filename.
```

- [ ] **Step 6: subagent-driven-development — ledger grammar and plan state**

In the grammar block under `## The Ledger`, the last line (line 273) is
`Ruling: <what> — <why> — <cost if wrong>`. Directly below it, inside the same
block and above its closing fence, add this line:

```text
Final review: clean (commits <merge-base7>..<head7>[, K parked])
```

Replace:

```markdown
merge base for Task 1. An old `(scored at dispatch)` line reads as assigned.
```

with:

```markdown
merge base for Task 1. An old `(scored at dispatch)` line reads as assigned.

**Plan state.** Every task complete and no `Final review:` line: go to Final
Review. A `Final review: clean` line: the review is done — go to
dr-superpowers:finishing-a-development-branch.
```

- [ ] **Step 7: subagent-driven-development — Session Budget section**

Immediately before the line `## The Task Loop`, insert:

```markdown
## Session Budget

`scripts/task-brief` and `scripts/review-package` end their output with the
budget line ([session-budget.md](../../reference/session-budget.md)), so you
check the session budget before every task and every review at no extra
request:

    budget: 312k of 475k (65%) — ok — source: record

- `ok` or `unknown`: carry on.
- `handoff`: finish the step in flight — let the dispatched agent return and
  write its ledger line — then invoke dr-superpowers:handoff. Dispatch nothing
  new first.
- After the last task's `Task N: complete` line, hand off whatever the budget
  says: the final whole-branch review runs in a fresh session, which
  dr-superpowers:resume-execution brings to Final Review.
- On Codex there is no budget line: hand off after every 3 completed tasks, or
  after any task that needed 3 or more fix rounds.

```

- [ ] **Step 8: subagent-driven-development — Final Review and Finish**

Replace:

```markdown
## Final Review

The final whole-branch review gets a package too: run
```

with:

```markdown
## Final Review

This runs in a fresh session: after the last task's complete line you handed
off, and dr-superpowers:resume-execution brought the next session here.

The final whole-branch review gets a package too: run
```

Replace:

```markdown
Before you delete anything, collect every ledger line containing `Ruling:` —
```

with:

```markdown
Before you leave this skill, collect every ledger line containing `Ruling:` —
```

Replace:

```markdown
When the final whole-branch review is clean and its fixes are merged,
delete this plan's workspace (`rm -rf <workspace>`) — the git history is
the record now. Sibling directories belong to other plans; leave them
alone.
```

with:

```markdown
When the final whole-branch review is clean and its fixes are committed,
append `Final review: clean (commits <merge-base7>..<head7>[, K parked])` to
the ledger in the same message as printing the rulings. Do not delete the
workspace: dr-superpowers:finishing-a-development-branch removes it with the
worktree once the work is merged or discarded, and until then it is what a
later session resumes from. Then continue to finishing — unless the last
budget line said `handoff`, in which case invoke dr-superpowers:handoff.
```

- [ ] **Step 9: subagent-driven-development — example workflow**

Replace:

```
[After all tasks]
```

with:

```
[After the last task's complete line: dr-superpowers:handoff prints the resume guide]

[Fresh session: dr-superpowers:resume-execution → Final Review]
```

Replace:

```
[Delete this plan's workspace — the record now lives in git]
```

with:

```
[Ledger: Final review: clean (commits a1b2c3d..f0e1d2c); print Rulings I made; budget ok — continue]
```

- [ ] **Step 10: executing-plans — After compaction and per-task check**

In `plugins/dr-superpowers/skills/executing-plans/SKILL.md`, replace:

```markdown
# Executing Plans

## Overview
```

with:

```markdown
# Executing Plans

## After compaction

If this session was compacted, your memory of the run is gone. Re-read the
ledger — `progress.md` in the directory `scripts/sdd-workspace PLAN_FILE`
prints — and trust it and `git log` over the summary: resume at the first task
without a `Task <N>: complete` line.

## Overview
```

Replace:

```markdown
4. Append `Task <N>: complete (commits <base7>..<head7>)` to the ledger, then mark as completed
```

with:

```markdown
4. Append `Task <N>: complete (commits <base7>..<head7>)` to the ledger, then mark as completed
5. Run `scripts/context-size` from the plugin root. On exit 5 (handoff), invoke dr-superpowers:handoff and stop; see [session-budget.md](../../reference/session-budget.md)
```

- [ ] **Step 11: Verify**

Run: `grep -c "delete this plan's workspace" plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`
Expected: `0`.

Run: `head -n 30 plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md | grep -c '^## After compaction'; grep -c '^## After compaction' plugins/dr-superpowers/skills/executing-plans/SKILL.md; grep -c 'Final review: clean' plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`
Expected: `1`, `1`, `4`.

Run: `timeout 60 node scripts/validate-repository.mjs && timeout 120 claude plugin validate plugins/dr-superpowers`
Expected: both pass.

- [ ] **Step 12: Commit**

```bash
git add plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md plugins/dr-superpowers/skills/executing-plans/SKILL.md
git commit -m "feat(superpowers): add budget checkpoints to execution"
```

### Task 10: finishing, brainstorming and using-superpowers edits

**Files:**
- Modify: `plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md` (lines 28-29, 56, 164-172)
- Modify: `plugins/dr-superpowers/skills/brainstorming/SKILL.md:228-231`
- Modify: `plugins/dr-superpowers/skills/using-superpowers/SKILL.md:55` (insert before `## Platform Adaptation`)

**Interfaces:**
- Consumes: `context-size`, `repo-audit` (Tasks 2, 4); `dr-superpowers:handoff`, `dr-superpowers:resume-execution` (Task 7); `next-step --draft` (Task 8); the kept workspace and `Final review: clean` line (Task 9)
- Produces: finishing owns workspace deletion; the entry point carries the Session Budget rules

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Record the current state**

Run: `grep -c 'may already be deleted' plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md; grep -c 'context-size' plugins/dr-superpowers/skills/brainstorming/SKILL.md; grep -c '^## Session Budget' plugins/dr-superpowers/skills/using-superpowers/SKILL.md`
Expected: `1`, `0`, `0`.

- [ ] **Step 2: finishing — Step 1 note**

In `plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md`, replace:

```markdown
Do not run `scripts/next-step` here: the plan is not finished, and its ledger
may already be deleted, so it would report the wrong next step.
```

with:

```markdown
Do not run `scripts/next-step` here: the branch is not ready to integrate, and
it would send the next session straight back into this skill.
```

- [ ] **Step 3: finishing — rulings before the menu**

Replace:

```markdown
Confirm before merging: merging into the wrong base is expensive to undo.
```

with:

```markdown
Confirm before merging: merging into the wrong base is expensive to undo.

**Rulings first.** If this work came from a plan with a ledger (`progress.md`
in the directory `scripts/sdd-workspace PLAN_FILE` prints) and this session
has not yet printed its "Rulings I made" list, print it now: every ledger line
containing `Ruling:`, in order. Your human partner chooses how to integrate
with those decisions in view.
```

- [ ] **Step 4: finishing — the workspace goes with the worktree**

Replace:

```markdown
and use the `GIT_DIR`/`GIT_COMMON`/`WORKTREE_PATH` values captured in
Step 2, from before that directory change.

**If `GIT_DIR == GIT_COMMON`:** Normal repo, no worktree to clean up. Done.
```

with:

```markdown
and use the `GIT_DIR`/`GIT_COMMON`/`WORKTREE_PATH` values captured in
Step 2, from before that directory change.

A plan's workspace (`.superpowers/sdd/<plan>/`: ledger, briefs, reports,
`handoff.md`) is git-ignored and lives in the worktree, so it goes with it —
`git worktree remove` deletes ignored files without `--force`. Options 2 and 3
keep it for the next session.

**If `GIT_DIR == GIT_COMMON`:** Normal repo, no worktree to clean up. If this
work came from a plan, delete its workspace — `rm -rf` on the directory
`scripts/sdd-workspace PLAN_FILE` prints. Done.
```

- [ ] **Step 5: brainstorming — one budget check before the plan**

In `plugins/dr-superpowers/skills/brainstorming/SKILL.md`, replace:

```markdown
**Implementation:**

- Invoke the writing-plans skill to create a detailed implementation plan
- Do NOT invoke any other skill. writing-plans is the next step.
```

with:

```markdown
**Implementation:**

- Run `scripts/context-size`, from the plugin root (two levels above this
  skill's directory). On exit 5 (handoff), invoke dr-superpowers:handoff with
  the spec as the draft and the next action "Write the implementation plan
  with dr-superpowers:writing-plans." — the plan is written in a fresh session.
- Otherwise invoke the writing-plans skill to create a detailed implementation plan.
- Do NOT invoke any other skill. writing-plans is the next step — in this
  session or, after a handoff, the next one.
```

- [ ] **Step 6: using-superpowers — Session Budget**

In `plugins/dr-superpowers/skills/using-superpowers/SKILL.md`, immediately before the line `## Platform Adaptation`, insert:

```markdown
## Session Budget

- `scripts/task-brief`, `scripts/review-package` and `scripts/context-size`
  print a budget line. `handoff` means: finish the step in flight, then use
  dr-superpowers:handoff. See [session-budget.md](../../reference/session-budget.md).
- A session that picks up earlier work runs `scripts/repo-audit` first; a plan
  with a ledger continues through dr-superpowers:resume-execution.
- After more than an hour idle, start a fresh session from
  `.superpowers/handoff/latest.md` rather than continuing: the prompt cache is
  cold, and the next request re-writes the whole context.
- After compaction, trust the compaction snapshot, the ledger and `git log`
  over the summary.

```

- [ ] **Step 7: Verify**

Run: `grep -c 'may already be deleted' plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md; grep -c 'context-size' plugins/dr-superpowers/skills/brainstorming/SKILL.md; grep -c '^## Session Budget' plugins/dr-superpowers/skills/using-superpowers/SKILL.md`
Expected: `0`, `1`, `1`.

Run: `timeout 60 node scripts/validate-repository.mjs && timeout 120 bash plugins/dr-superpowers/tests/hook.test.sh`
Expected: the validator exits 0; the hook suite ends `… passed, 0 failed` (its "under the 10,000-character hook cap" check covers the larger entry point).

- [ ] **Step 8: Commit**

```bash
git add plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md plugins/dr-superpowers/skills/brainstorming/SKILL.md plugins/dr-superpowers/skills/using-superpowers/SKILL.md
git commit -m "feat(superpowers): wire budget into entry and finish"
```

### Task 11: README and 1.3.0

**Files:**
- Modify: `plugins/dr-superpowers/README.md` (lines 183-185, 210-214, 216, 318-320)
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json:5`
- Modify: `plugins/dr-superpowers/.codex-plugin/plugin.json:3`

**Interfaces:**
- Consumes: everything above, by name
- Produces: dr-superpowers 1.3.0 on both clients

**Implementer:** dcc-superpower-companions:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Requirements paragraph**

In `plugins/dr-superpowers/README.md`, replace:

```markdown
`scripts/sdd-workspace`, `task-brief`, `review-package`, and `next-step` —
the last ends every execution session with the plan's next action and keeps
`.superpowers/handoff/latest.md` pointing at it. Disable the
```

with:

```markdown
`scripts/sdd-workspace`, `task-brief`, `review-package`, `next-step`,
`context-size`, and `repo-audit` — `next-step` ends every session with its next
action and keeps `.superpowers/handoff/latest.md` pointing at it. Disable the
```

- [ ] **Step 2: How it fires**

Replace:

```markdown
writer wins per directory); the session-budget tooling of a later release reads
it. Malformed stdin skips persistence but never blocks the injection, and the
hook always exits 0.
```

with:

```markdown
writer wins per directory), which `scripts/context-size` reads. On the
`compact` source it also appends a compaction snapshot (see Session budget).
Malformed stdin skips persistence but never blocks the injection, and the
hook always exits 0.
```

- [ ] **Step 3: Session budget section**

Immediately before the line `## Migrating from 0.x`, insert:

```markdown
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
- **Stops.** A saved plan and a finished task list always hand off; the final
  review and finishing continue in the same session unless the budget says
  otherwise.
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

```

- [ ] **Step 4: Reference section**

Replace:

```markdown
`reference/external-executor.md` holds the Claude-hosted Codex CLI lane, and
`reference/legacy-names.md` translates names written under older plugin
prefixes.
```

with:

```markdown
`reference/external-executor.md` holds the Claude-hosted Codex CLI lane,
`reference/legacy-names.md` translates names written under older plugin
prefixes, and `reference/session-budget.md` holds the budget numbers,
checkpoints, stops and the Compact Instructions block.
```

- [ ] **Step 5: Version 1.3.0**

In `plugins/dr-superpowers/.claude-plugin/plugin.json` replace `"version": "1.2.0",` with `"version": "1.3.0",`. In `plugins/dr-superpowers/.codex-plugin/plugin.json` make the same replacement.

- [ ] **Step 6: Verify**

Run: `grep -h '"version"' plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json`
Expected: two lines, both `"version": "1.3.0",`.

Run: `timeout 60 node scripts/validate-repository.mjs && timeout 120 claude plugin validate plugins/dr-superpowers`
Expected: both pass.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/README.md plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json
git commit -m "feat(superpowers)!: add session budget, 1.3.0"
```

### Task 12: Full verification sweep

**Files:**
- Modify: none, unless a check fails (then only the failing file, in a `fix(superpowers): …` commit)

**Interfaces:**
- Consumes: the whole branch
- Produces: a green run of the project's validation (CLAUDE.md "Validation")

**Implementer:** dcc-superpower-companions:impl-haiku
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

- [ ] **Step 1: Repository validator**

Run: `timeout 60 node scripts/validate-repository.mjs`
Expected: exit 0.

- [ ] **Step 2: All suites**

Run: `timeout 1800 node scripts/test-all.mjs`
Expected: every suite passes except the known environmental failure in `tests/ui-discovery.test.mjs` ("documented Win32 discovery finds centrally managed versions", `rg: command not found`). The output shows `plan-lib.test.sh`, `context-size.test.sh`, `budget-line.test.sh`, `repo-audit.test.sh` and `snapshot.test.sh` running and ending `0 failed`.

- [ ] **Step 3: Plugin validation**

Run each, one at a time:

```bash
timeout 120 claude plugin validate .
timeout 120 claude plugin validate plugins/dr-status
timeout 120 claude plugin validate plugins/dr-superpowers
timeout 120 claude plugin validate plugins/dcc-darkraise-ui
timeout 120 claude plugin validate plugins/dcc-darkraise-win32ui
```

Expected: each passes.

- [ ] **Step 4: Smoke the tools in this worktree**

Run: `bash plugins/dr-superpowers/scripts/repo-audit | head -n 12; bash plugins/dr-superpowers/scripts/context-size; echo "exit=$?"`
Expected: the audit starts `# Repo audit` and names this worktree; `context-size` prints one `budget:` line and exits 0, 5 or 3.

- [ ] **Step 5: Clean up**

Confirm that no process started by this task is still running (`node scripts/test-all.mjs` kills its own child trees on exit and on timeout). Report the results of Steps 1-4 in the task report.
