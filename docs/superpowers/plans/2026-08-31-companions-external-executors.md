# External Executors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Implementer assignments:** each task names its implementer agent in an
> `**Implementer:**` line. When executing with
> superpowers:subagent-driven-development, REQUIRED SUB-SKILL:
> dcc-superpower-companions:dispatching-tiered-implementers. Under
> superpowers:executing-plans these lines are inert; ignore them.

> **External executors:** none. This plan builds the external lane, so the lane
> cannot run it. Every task is Claude-lane and carries no `**Executor:**` line.

**Goal:** Let a plan's score-2..4, risk<=1 tasks run on Codex instead of a Claude implementer, and add a Codex seat to the two review stages that already pay for extra opinions.

**Architecture:** A lane gate sits in front of the existing assignment table; eligible tasks get an `**Executor:**` override line while `**Implementer:**` keeps naming the Claude fallback. A wrapper script owns the Codex command line, validation, the commit, and the process tree. No new agents, no new worktree, no driver subagent.

**Tech Stack:** bash, jq, the Codex CLI (`codex exec`, `codex exec resume`, `codex exec review`), and the existing `check()`/`block()` test harness in `plugins/dcc-superpower-companions/tests/`.

**Spec:** `docs/superpowers/specs/2026-08-31-companions-external-executors-design.md`

## Global Constraints

- All paths below are relative to `plugins/dcc-superpower-companions/` unless stated otherwise. The repo root is `D:\Repositories\Personal\claude-code-plugins`.
- **Verified Codex facts. Do not re-derive, do not substitute.** Models: only `gpt-5.5` and `gpt-5.6-sol` work on a ChatGPT account. Efforts: `low`, `medium`, `high`, `xhigh`, `ultra` (`minimal` is rejected). The CLI validates neither locally.
- **Codex cannot write to `.git`** under `-s workspace-write`. The wrapper commits; Codex must never be asked to run git.
- **No test may call a model.** Every new suite uses a stub or synthetic input.
- **The four existing suites must pass unmodified** except `hook.test.sh`, which Task 8 extends. `fleet.test.sh` must not be touched — this plan adds no agent file.
- Language is English only, in code, comments, docs, and commit messages.
- Commits follow `<type>(<scope>): <subject>`, subject <=50 chars, imperative, no period.
- Comments only where the WHY is non-obvious. Never explain WHAT the code does.
- Run `claude plugin validate .` from the repo root before any commit that touches a manifest.

---

### Task 1: Lane tables in ladder.md

**Files:**
- Modify: `reference/ladder.md` (append four fenced blocks at the end)
- Create: `tests/lanes.test.sh`

**Interfaces:**
- Consumes: nothing
- Produces: four fenced blocks read by every later task —
  `gate` (keys `min_score`, `max_risk`, `require_rule_s_clean`, `require_external_enabled`),
  `codex-assignment` (rows `<score> <model> <effort>`),
  `codex-successor` (rows `<model>/<effort> <model>/<effort>|HANDBACK`),
  `codex-timeout` (rows `<model>/<effort> <seconds>`).
  The `block()` awk helper already used by `tests/ladder.test.sh` parses them.

**Implementer:** dcc-superpower-companions:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1
**Approach:** inline - skip 3: the spec fixes the tables and their values

- [ ] **Step 1: Write the failing test**

Create `tests/lanes.test.sh`:

```bash
#!/usr/bin/env bash
# The lane tables are data the skills and the wrapper script read at runtime, so
# their integrity is checkable without a model. Two invariants matter most: no
# rung may name a model that does not exist on a ChatGPT account, and the
# successor column must terminate at HANDBACK rather than cycling.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER="$HERE/../reference/ladder.md"

# Probed on 2026-08-31 against Codex 0.151.0 with ChatGPT-subscription auth.
# luna and terra are rejected with HTTP 400; minimal is rejected as an effort.
VALID_MODELS="gpt-5.5 gpt-5.6-sol"
VALID_EFFORTS="low medium high xhigh ultra"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

block() {
  awk -v tag="$1" '
    $0 == "```" tag { f = 1; next }
    f && $0 == "```" { exit }
    f && NF { print }
  ' "$LADDER"
}

in_list() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# rank orders a rung for the termination proof: model major, effort minor.
rank() {
  local m="${1%%/*}" e="${1##*/}" mr er
  case "$m" in gpt-5.5) mr=0 ;; gpt-5.6-sol) mr=1 ;; *) echo -1; return ;; esac
  case "$e" in low) er=0 ;; medium) er=1 ;; high) er=2 ;; xhigh) er=3 ;; ultra) er=4 ;; *) echo -1; return ;; esac
  echo $((mr * 10 + er))
}

check "ladder.md exists" "$([ -f "$LADDER" ] && echo yes || echo no)" "yes"

# --- gate -------------------------------------------------------------------
gate=$(block gate)
check "gate min_score is 2" "$(printf '%s\n' "$gate" | awk '$1=="min_score"{print $2}')" "2"
check "gate max_risk is 1" "$(printf '%s\n' "$gate" | awk '$1=="max_risk"{print $2}')" "1"
check "gate requires a clean Rule S pass" \
  "$(printf '%s\n' "$gate" | awk '$1=="require_rule_s_clean"{print $2}')" "true"
check "gate requires an enabled executor" \
  "$(printf '%s\n' "$gate" | awk '$1=="require_external_enabled"{print $2}')" "true"

# --- codex-assignment -------------------------------------------------------
assignment=$(block codex-assignment)
check "codex-assignment has 3 rows" "$(printf '%s\n' "$assignment" | grep -c .)" "3"

bad_model=NONE bad_effort=NONE seen=""
while read -r score model effort; do
  [ -n "$score" ] || continue
  in_list "$model" "$VALID_MODELS" || bad_model="$model"
  in_list "$effort" "$VALID_EFFORTS" || bad_effort="$effort"
  seen="$seen $score"
done <<< "$assignment"
check "every assigned model is available on a ChatGPT account" "$bad_model" "NONE"
check "every assigned effort is valid" "$bad_effort" "NONE"

missing=NONE
for s in 2 3 4; do in_list "$s" "$seen" || missing="$s"; done
check "codex-assignment covers scores 2, 3 and 4" "$missing" "NONE"

# Rule S caps reducible at 3, so under max_risk 1 no eligible total exceeds 4.
outside=$(printf '%s\n' "$assignment" | awk 'NF && ($1 < 2 || $1 > 4) {print $1}' | tr '\n' ' ' | sed 's/ $//')
check "codex-assignment has no row outside 2..4" "${outside:-NONE}" "NONE"

# --- codex-successor --------------------------------------------------------
successor=$(block codex-successor)
succ_of() { printf '%s\n' "$successor" | awk -v k="$1" '$1 == k {print $2}'; }

bad_rank=NONE
while read -r from to; do
  [ -n "$from" ] || continue
  [ "$to" = HANDBACK ] && continue
  fr=$(rank "$from"); tr=$(rank "$to")
  { [ "$fr" -lt 0 ] || [ "$tr" -lt 0 ]; } && { bad_rank="unrankable:$from->$to"; continue; }
  [ "$tr" -gt "$fr" ] || bad_rank="not-increasing:$from->$to"
done <<< "$successor"
check "every successor ranks strictly above its source" "$bad_rank" "NONE"

bad_walk=NONE
while read -r start _; do
  [ -n "$start" ] || continue
  cur="$start"
  for _ in 1 2 3 4 5 6; do
    [ "$cur" = HANDBACK ] && break
    cur=$(succ_of "$cur")
    [ -n "$cur" ] || { bad_walk="dead-end-from:$start"; break; }
  done
  [ "$cur" = HANDBACK ] || bad_walk="${bad_walk#NONE}no-terminal-from:$start"
  [ "$bad_walk" = NONE ] || break
done <<< "$successor"
check "every rung reaches HANDBACK without cycling" "$bad_walk" "NONE"

# Every assignment rung must have somewhere to go on a capability failure.
bad_entry=NONE
while read -r _ model effort; do
  [ -n "$model" ] || continue
  [ -n "$(succ_of "$model/$effort")" ] || bad_entry="$model/$effort"
done <<< "$assignment"
check "every assignment rung has a successor" "$bad_entry" "NONE"

# --- codex-timeout ----------------------------------------------------------
timeouts=$(block codex-timeout)
bad_timeout=NONE
while read -r from to; do
  [ -n "$from" ] || continue
  secs=$(printf '%s\n' "$timeouts" | awk -v k="$from" '$1 == k {print $2}')
  [ -n "$secs" ] || { bad_timeout="missing:$from"; continue; }
  printf '%s' "$secs" | grep -qE '^[0-9]+$' || bad_timeout="non-numeric:$from"
  [ "$to" = HANDBACK ] && continue
  secs_to=$(printf '%s\n' "$timeouts" | awk -v k="$to" '$1 == k {print $2}')
  [ -n "$secs_to" ] || bad_timeout="missing:$to"
done <<< "$successor"
check "every rung named anywhere has a numeric timeout" "$bad_timeout" "NONE"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run from the repo root:

```bash
bash plugins/dcc-superpower-companions/tests/lanes.test.sh
```

Expected: FAIL. The `gate`, `codex-assignment`, `codex-successor`, and `codex-timeout` blocks do not exist yet, so `block()` returns empty and the row-count and coverage checks fail.

- [ ] **Step 3: Append the tables to ladder.md**

Append to the end of `reference/ladder.md`:

````markdown
## The external lane

An external executor is not a rung on the escalation ladder above. Offload
selects downward at the cheap end while the ladder only moves upward, and one
total order cannot express both. The Claude ladder remains the sole backstop, so
its termination proof is unchanged by anything in this section.

### The lane gate

```gate
min_score 2
max_risk 1
require_rule_s_clean true
require_external_enabled true
```

All four conditions must hold. `require_rule_s_clean` excludes a task whose
`spec = 3` was kept by a human override under the legacy floor: such a task can
score `0 + 3 + 0 + 0 = 3` and would otherwise pass, sending a task whose approach
nobody decided to a one-shot external agent.

`min_score 2` is not arbitrary. Rule S caps `reducible` at 3, so under
`max_risk 1` the eligible totals are exactly 2, 3, and 4 - totals 5 and 6 need
`risk >= 2` and the risk clause already excludes them. Without the floor the gate
would reduce to `risk <= 1` and capture nearly every task by count. It would also
offload where offload is worthless: a score-0 task displaces `impl-haiku`, which
costs less to run than the wrapper costs to orchestrate.

### Codex assignment

```codex-assignment
2 gpt-5.5 medium
3 gpt-5.5 high
4 gpt-5.6-sol high
```

Only `gpt-5.5` and `gpt-5.6-sol` appear. `luna` and `terra` are rejected with
HTTP 400 on a ChatGPT account - "not supported when using Codex with a ChatGPT
account" - and Codex holds no model metadata for either. A table naming them
would fail every task at those rungs on every run.

Valid efforts are `low`, `medium`, `high`, `xhigh`, and `ultra`. `minimal` is
rejected. Two models across five efforts is ten rungs of headroom, all of it on
the effort axis.

### Codex successor

```codex-successor
gpt-5.5/medium gpt-5.5/high
gpt-5.5/high gpt-5.6-sol/high
gpt-5.6-sol/high gpt-5.6-sol/xhigh
gpt-5.6-sol/xhigh HANDBACK
```

This is a single-successor column consulted at most once per task, not a
walkable chain. Only a failed *run* consults it: the fix loop resumes the same
session on rounds 1 to 3 and hands back on round 4, so no fix round ever reads
it. It is named `successor` rather than `escalation` for that reason.

`HANDBACK` is an action, not an executor - the same shape as `SPLIT` at the top
of the escalation table. It resolves to the Claude assignment-table row for the
task's score, after which the ordinary ladder governs.

Ranking a rung as `model_rank * 10 + effort_rank`, where `gpt-5.5` ranks 0 and
`gpt-5.6-sol` ranks 1, gives every successor a strictly higher rank than its
source, so the column is acyclic and every walk reaches `HANDBACK`.

### Codex timeout

```codex-timeout
gpt-5.5/medium 900
gpt-5.5/high 1200
gpt-5.6-sol/high 1800
gpt-5.6-sol/xhigh 2400
```

Seconds. One constant cannot serve both a `medium` and an `xhigh` run.
````

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash plugins/dcc-superpower-companions/tests/lanes.test.sh
```

Expected: PASS, `0 failed`.

- [ ] **Step 5: Verify the existing suites still pass**

```bash
for t in plugins/dcc-superpower-companions/tests/*.test.sh; do echo "== $t"; bash "$t" | tail -1; done
```

Expected: every suite reports `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-superpower-companions/reference/ladder.md plugins/dcc-superpower-companions/tests/lanes.test.sh
git commit -m "feat(companions): add external lane tables"
```

---

### Task 2: Executor detection

**Files:**
- Create: `scripts/detect-executors.sh`
- Create: `tests/detect.test.sh`

**Interfaces:**
- Consumes: nothing
- Produces: `detect-executors.sh`, which prints a JSON array to stdout. Each element has `id`, `present` (bool), `path` (string or null), `version` (string or null), `authed` (bool or null), `batch_capable` (bool), `usable` (bool), `reason` (string or null; non-null exactly when `usable` is false). Consumed by Task 5 (checkbox) and Task 6 (dispatch guard).

**Implementer:** dcc-superpower-companions:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1
**Approach:** inline - skip 3: the spec fixes the roster fields and the antigravity verdict

- [ ] **Step 1: Write the failing test**

Create `tests/detect.test.sh`:

```bash
#!/usr/bin/env bash
# Detection must be honest about three distinct states: absent, present but not
# batch-capable, and usable. Conflating the middle state with either neighbour
# is the failure that matters - it either hides a tool the user asked about or
# offers one that cannot be dispatched.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/detect-executors.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# A synthetic PATH holding only the stubs we choose, so the result does not
# depend on what happens to be installed on the machine running the suite.
mkdir -p "$TMP/bin" "$TMP/codexhome"
BASH_BIN=$(command -v bash)
make_stub() { printf '#!%s\necho "%s"\n' "$BASH_BIN" "$2" > "$TMP/bin/$1"; chmod +x "$TMP/bin/$1"; }

# PATH isolation has to be structural, not a coincidence of one machine's layout.
# A wide PATH hides the real executors only as long as none of them shares a
# directory with the script's own dependencies - and on most Linux distros both
# jq and codex land in /usr/bin, which would resolve the real binary and flip
# every not-present assertion. Shim just the four commands the script needs, so
# PATH can be exactly one directory this test controls.
# Shebangs here must name bash by absolute path: `#!/usr/bin/env bash` resolves
# bash through PATH, and PATH no longer contains it.
for dep in jq timeout head tr; do
  printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$(command -v "$dep")" > "$TMP/bin/$dep"
  chmod +x "$TMP/bin/$dep"
done
run() { PATH="$TMP/bin" CODEX_HOME="$TMP/codexhome" "$BASH_BIN" "$SCRIPT"; }
field() { jq -r --arg i "$1" --arg f "$2" '.[] | select(.id==$i) | .[$f]' <<< "$3"; }

check "script exists" "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"

# --- nothing installed ------------------------------------------------------
out=$(run)
check "empty PATH: emits valid JSON" "$(jq -e 'type=="array"' >/dev/null 2>&1 <<<"$out" && echo yes || echo no)" "yes"
check "empty PATH: reports all four executors" "$(jq 'length' <<<"$out")" "4"
check "empty PATH: codex not present" "$(field codex present "$out")" "false"
check "empty PATH: codex not usable" "$(field codex usable "$out")" "false"
check "empty PATH: codex has a reason" \
  "$(field codex reason "$out" | grep -qi 'path' && echo yes || echo no)" "yes"

# --- codex installed and authenticated --------------------------------------
make_stub codex "codex-cli 0.151.0"
printf '{"tokens":{}}' > "$TMP/codexhome/auth.json"
out=$(run)
check "codex present" "$(field codex present "$out")" "true"
check "codex version captured" "$(field codex version "$out")" "codex-cli 0.151.0"
check "codex authed" "$(field codex authed "$out")" "true"
check "codex batch capable" "$(field codex batch_capable "$out")" "true"
check "codex usable" "$(field codex usable "$out")" "true"
check "usable executor carries no reason" "$(field codex reason "$out")" "null"

# --- codex installed but unauthenticated ------------------------------------
rm -f "$TMP/codexhome/auth.json"
out=$(run)
check "unauthenticated codex is not usable" "$(field codex usable "$out")" "false"
check "unauthenticated codex says so" \
  "$(field codex reason "$out" | grep -qi 'auth' && echo yes || echo no)" "yes"
printf '{"tokens":{}}' > "$TMP/codexhome/auth.json"

# --- antigravity is present but never dispatchable --------------------------
# Its only agent-shaped subcommand opens a GUI chat session: no output file, no
# completion signal, no exit code tied to the work. Present is not usable.
make_stub antigravity "Antigravity 1.107.0"
out=$(run)
check "antigravity present" "$(field antigravity present "$out")" "true"
check "antigravity not batch capable" "$(field antigravity batch_capable "$out")" "false"
check "antigravity not usable" "$(field antigravity usable "$out")" "false"
check "antigravity reason mentions the GUI" \
  "$(field antigravity reason "$out" | grep -qi 'gui' && echo yes || echo no)" "yes"

# --- invariant across every row ---------------------------------------------
out=$(run)
check "reason is set exactly when usable is false" \
  "$(jq '[.[] | select((.usable == false) != (.reason != null))] | length' <<<"$out")" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-superpower-companions/tests/detect.test.sh
```

Expected: FAIL at `script exists`, then every subsequent check, because `scripts/detect-executors.sh` does not exist.

- [ ] **Step 3: Write the detection script**

Create `scripts/detect-executors.sh`:

```bash
#!/usr/bin/env bash
# Emits a JSON roster of external agent CLIs. Read at plan time to populate the
# executor checkbox, and again at dispatch as a guard, because a roster can go
# stale between the two.
#
# batch_capable is a static fact about a tool, not a probe result: it records
# whether the CLI can run a task headlessly and return a result a script can
# read. Antigravity fails that test on its interface, not on its installation.
set -uo pipefail

emit() { # emit <id> <batch_capable> <incapable_reason>
  local id="$1" capable="$2" incapable_reason="$3"
  local path present version authed reason usable

  path=$(command -v "$id" 2>/dev/null || true)
  if [ -n "$path" ]; then present=true; else present=false; fi

  version=null
  if [ "$present" = true ]; then
    local v
    v=$(timeout 20 "$id" --version 2>/dev/null | head -1 | tr -d '\r')
    [ -n "$v" ] && version=$(jq -Rn --arg v "$v" '$v')
  fi

  # Auth is only checkable offline for codex, whose credentials live in a file.
  # For everything else the honest answer is null, not a guess.
  authed=null
  if [ "$id" = codex ] && [ "$present" = true ]; then
    if [ -f "${CODEX_HOME:-$HOME/.codex}/auth.json" ]; then authed=true; else authed=false; fi
  fi

  usable=false
  reason=null
  if [ "$present" != true ]; then
    reason='"not on PATH"'
  elif [ "$capable" != true ]; then
    reason=$(jq -Rn --arg r "$incapable_reason" '$r')
  elif [ "$authed" = false ]; then
    reason='"present but not authenticated; run codex login"'
  else
    usable=true
  fi

  jq -n \
    --arg id "$id" \
    --argjson present "$present" \
    --argjson version "$version" \
    --argjson authed "$authed" \
    --argjson batch_capable "$capable" \
    --argjson usable "$usable" \
    --argjson reason "$reason" \
    --arg path "$path" \
    '{id:$id, present:$present, path:(if $path=="" then null else $path end),
      version:$version, authed:$authed, batch_capable:$batch_capable,
      usable:$usable, reason:$reason}'
}

{
  emit codex true ""
  emit cursor-agent true ""
  emit opencode true ""
  emit antigravity false "installed, but its only agent mode (antigravity chat -m agent) opens a GUI editor session with no output file, no completion signal, and no exit code tied to the work"
} | jq -s '.'
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash plugins/dcc-superpower-companions/tests/detect.test.sh
```

Expected: PASS, `0 failed`.

- [ ] **Step 5: Sanity-check against the real machine**

```bash
bash plugins/dcc-superpower-companions/scripts/detect-executors.sh | jq -c '.[] | {id, present, usable, reason}'
```

Expected on the development machine: `codex` usable true; `antigravity` present true, usable false, reason mentioning the GUI; `cursor-agent` and `opencode` present false, reason "not on PATH". This is an observation step, not an assertion — do not edit the script to force this output on a different machine.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-superpower-companions/scripts/detect-executors.sh plugins/dcc-superpower-companions/tests/detect.test.sh
git commit -m "feat(companions): add executor detection roster"
```

---

### Task 3: Wrapper validation and dry run

**Files:**
- Create: `scripts/codex-report-schema.json`
- Create: `scripts/run-codex-task.sh` (argument parsing, validation, `--dry-run` only)
- Create: `tests/run-codex-task.test.sh`

**Interfaces:**
- Consumes: the `codex-assignment` and `codex-timeout` blocks from Task 1.
- Produces: `run-codex-task.sh` accepting `--brief F --report F --model M --effort E --cwd D [--timeout S] [--resume THREAD] [--dry-run]`. With `--dry-run` it prints the exact command line it would run and exits 0. Invalid input exits 2 with a message on stderr and prints nothing on stdout. Task 4 adds execution behind the same interface.

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2
**Approach:** inline - skip 3: the spec fixes the flag set and the schema

- [ ] **Step 1: Write the failing test**

Create `tests/run-codex-task.test.sh`:

```bash
#!/usr/bin/env bash
# The Codex CLI validates neither the model nor the reasoning effort: it echoes
# any string into its banner and fails at the API, which bills for the round
# trip. Local validation is therefore the wrapper's job, and these tests are the
# only thing that proves it happens before a process is spawned.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/run-codex-task.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

mkdir -p "$TMP/work"
printf 'do the thing\n' > "$TMP/brief.md"

dry() { bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
          --cwd "$TMP/work" --dry-run "$@" 2>"$TMP/err"; }
rc_of() { dry "$@" >/dev/null; echo $?; }

check "script exists" "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"
check "schema exists" "$([ -f "$HERE/../scripts/codex-report-schema.json" ] && echo yes || echo no)" "yes"
check "schema is valid JSON" \
  "$(jq -e . >/dev/null 2>&1 < "$HERE/../scripts/codex-report-schema.json" && echo yes || echo no)" "yes"
check "schema status enum matches the contract" \
  "$(jq -r '.properties.status.enum | sort | join(",")' < "$HERE/../scripts/codex-report-schema.json")" \
  "BLOCKED,DONE,NEEDS_CONTEXT"

# --- validation happens before anything is spawned --------------------------
check "rejects a model absent from codex-assignment" "$(rc_of --model gpt-4o --effort medium)" "2"
check "rejects luna, which 400s on a ChatGPT account" "$(rc_of --model luna --effort medium)" "2"
check "rejects an invalid effort" "$(rc_of --model gpt-5.5 --effort minimal)" "2"
check "rejects a missing brief" \
  "$(bash "$SCRIPT" --brief "$TMP/nope.md" --report "$TMP/r.md" --cwd "$TMP/work" \
      --model gpt-5.5 --effort medium --dry-run >/dev/null 2>&1; echo $?)" "2"
check "accepts a valid rung" "$(rc_of --model gpt-5.5 --effort medium)" "0"

# --- the composed command line ----------------------------------------------
cmd=$(dry --model gpt-5.5 --effort medium)
for frag in "exec" "-C" "-s workspace-write" "-m gpt-5.5" \
            "model_reasoning_effort=medium" "--json" "--output-schema" "-o"; do
  check "dry run includes [$frag]" "$(grep -qF -- "$frag" <<<"$cmd" && echo yes || echo no)" "yes"
done
check "dry run never bypasses the sandbox" \
  "$(grep -qF -- "--dangerously-bypass" <<<"$cmd" && echo yes || echo no)" "no"

# --- timeouts come from the table unless overridden -------------------------
check "timeout defaults from codex-timeout" \
  "$(grep -qE '^timeout=900$' <<<"$cmd" && echo yes || echo no)" "yes"
check "explicit timeout wins" \
  "$(out=$(dry --model gpt-5.5 --effort medium --timeout 42); grep -qE '^timeout=42$' <<<"$out" && echo yes || echo no)" "yes"

# --- resume must re-send every per-invocation flag ---------------------------
# A bare `codex exec resume <id>` falls back to the user's config defaults, so a
# round-2 fix would silently run at a tier the ledger does not record.
res=$(dry --model gpt-5.5 --effort high --resume 01a0-thread)
check "resume names the subcommand" "$(grep -qF -- "resume" <<<"$res" && echo yes || echo no)" "yes"
check "resume carries the thread id" "$(grep -qF -- "01a0-thread" <<<"$res" && echo yes || echo no)" "yes"
check "resume re-sends the model" "$(grep -qF -- "-m gpt-5.5" <<<"$res" && echo yes || echo no)" "yes"
check "resume re-sends the effort" \
  "$(grep -qF -- "model_reasoning_effort=high" <<<"$res" && echo yes || echo no)" "yes"

# --- malformed input fails fast, and the dry run tells the truth ------------
check "a trailing flag with no value exits 2 rather than hanging" \
  "$(timeout 10 bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
      --cwd "$TMP/work" --model gpt-5.5 --effort medium --resume \
      >/dev/null 2>&1; echo $?)" "2"

check "rejects an unknown flag" "$(rc_of --model gpt-5.5 --effort medium --bogus x)" "2"
# Assert the message, not just the exit code: a multi-word effort already exited
# 2 before the fix, via an unrelated timeout-lookup miss. Only the message proves
# the effort check itself rejected it.
#
# Captured to a variable rather than piped straight into grep: the wrapper's own
# validation failure exits 2, and with `set -o pipefail` active in this suite, a
# direct `cmd 2>&1 >/dev/null | grep ...` pipeline reports cmd's exit code (2)
# instead of grep's match result, so the check would fail regardless of the
# message. Command substitution sidesteps that: only the text is captured.
msg=$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
      --cwd "$TMP/work" --model gpt-5.5 --effort 'medium high' --dry-run 2>&1 >/dev/null)
check "rejects a multi-word effort at the effort check, not downstream" \
  "$(grep -qF 'invalid reasoning effort' <<<"$msg" && echo yes || echo no)" "yes"

check "rejected input prints nothing on stdout" \
  "$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
      --cwd "$TMP/work" --model luna --effort medium --dry-run 2>/dev/null \
      | wc -c | tr -d ' \r\n')" "0"

# The dry run's contract is that it shows what would actually run, so re-parse
# what it printed and confirm a space-containing path survives as ONE argument.
mkdir -p "$TMP/dir with space"
printed=$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
  --cwd "$TMP/dir with space" --model gpt-5.5 --effort medium --dry-run 2>/dev/null \
  | grep '^codex ')
eval "set -- $printed"
roundtrip=no
while [ $# -gt 0 ]; do
  if [ "$1" = "-C" ] && [ "${2:-}" = "$TMP/dir with space" ]; then roundtrip=yes; fi
  shift
done
check "dry run round-trips a space-containing path as one argument" "$roundtrip" "yes"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-superpower-companions/tests/run-codex-task.test.sh
```

Expected: FAIL at `script exists` and `schema exists`, and at every check after them.

- [ ] **Step 3: Write the output schema**

Create `scripts/codex-report-schema.json`:

```json
{
  "type": "object",
  "required": ["status", "summary", "commit_subject", "questions"],
  "additionalProperties": false,
  "properties": {
    "status": {
      "type": "string",
      "enum": ["DONE", "BLOCKED", "NEEDS_CONTEXT"]
    },
    "summary": {
      "type": "string",
      "description": "What was changed and why, in the voice of an implementer report."
    },
    "commit_subject": {
      "type": "string",
      "description": "Conventional-commit subject line: type(scope): subject, imperative, no trailing period, 50 characters or fewer."
    },
    "questions": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Required when status is NEEDS_CONTEXT; empty otherwise."
    }
  }
}
```

- [ ] **Step 4: Write the wrapper's validation half**

Create `scripts/run-codex-task.sh`:

```bash
#!/usr/bin/env bash
# Runs one plan task on Codex and leaves behind a superpowers-shaped report.
#
# The Codex CLI validates neither --model nor model_reasoning_effort: it accepts
# any string, prints it in its banner, and fails at the API. Validating here is
# what keeps a typo from becoming a paid round trip.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER="$HERE/../reference/ladder.md"
SCHEMA="$HERE/codex-report-schema.json"

VALID_EFFORTS="low medium high xhigh ultra"

die() { printf 'run-codex-task: %s\n' "$1" >&2; exit 2; }

block() {
  awk -v tag="$1" '
    $0 == "```" tag { f = 1; next }
    f && $0 == "```" { exit }
    f && NF { print }
  ' "$LADDER"
}

brief="" report="" model="" effort="" cwd="" timeout_s="" thread="" dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift; continue ;;
    --brief|--report|--model|--effort|--cwd|--timeout|--resume) ;;
    *) die "unknown argument: $1" ;;
  esac
  # Every flag reaching here takes a value. `shift 2` fails when only one
  # positional remains, and with no `set -e` the loop would re-enter with $1
  # unchanged and spin forever instead of reporting the malformed input.
  [ $# -ge 2 ] || die "missing value for $1"
  case "$1" in
    --brief)   brief="$2" ;;
    --report)  report="$2" ;;
    --model)   model="$2" ;;
    --effort)  effort="$2" ;;
    --cwd)     cwd="$2" ;;
    --timeout) timeout_s="$2" ;;
    --resume)  thread="$2" ;;
  esac
  shift 2
done

[ -n "$brief" ]  || die "--brief is required"
[ -n "$report" ] || die "--report is required"
[ -n "$model" ]  || die "--model is required"
[ -n "$effort" ] || die "--effort is required"
[ -n "$cwd" ]    || die "--cwd is required"
[ -f "$brief" ]  || die "brief not found: $brief"
[ -d "$cwd" ]    || die "cwd not found: $cwd"
[ -f "$SCHEMA" ] || die "schema not found: $SCHEMA"

block codex-assignment | awk '{print $2}' | sort -u | grep -qxF -- "$model" \
  || die "model is not a rung in codex-assignment: $model"
# Word-exact, mirroring the model check above. A containment test on the padded
# string admits a multi-word value like "medium high", which would then fail far
# downstream in the timeout lookup instead of here.
printf '%s\n' $VALID_EFFORTS | grep -qxF -- "$effort" \
  || die "invalid reasoning effort: $effort (valid: $VALID_EFFORTS)"

if [ -z "$timeout_s" ]; then
  timeout_s=$(block codex-timeout | awk -v k="$model/$effort" '$1 == k {print $2}')
  [ -n "$timeout_s" ] || die "no codex-timeout row for $model/$effort"
fi

# Every per-invocation flag is rebuilt here, including on resume: a bare
# `codex exec resume <id>` inherits the user's config defaults instead.
argv=(exec)
[ -n "$thread" ] && argv+=(resume "$thread")
argv+=(
  -C "$cwd"
  -s workspace-write
  -m "$model"
  -c "model_reasoning_effort=$effort"
  --json
  --output-schema "$SCHEMA"
  -o "$report.last.json"
)

if [ "$dry" -eq 1 ]; then
  # %q, not %s: a dry run that prints a command different from the one that
  # would execute is worse than no dry run, and a path containing a space
  # silently splits into several arguments under %s. The timeout is its own
  # labelled line because execution enforces it with a poll loop rather than by
  # invoking timeout(1), so printing it as part of the command would be a lie.
  printf 'timeout=%s\n' "$timeout_s"
  printf 'codex'
  printf ' %q' "${argv[@]}"
  printf '\n'
  exit 0
fi

die "execution is not implemented yet"
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
bash plugins/dcc-superpower-companions/tests/run-codex-task.test.sh
```

Expected: PASS, `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-superpower-companions/scripts/codex-report-schema.json plugins/dcc-superpower-companions/scripts/run-codex-task.sh plugins/dcc-superpower-companions/tests/run-codex-task.test.sh
git commit -m "feat(companions): validate codex task invocations"
```

---

### Task 4: Wrapper execution, commit, and cleanup

**Files:**
- Create: `scripts/codex-task-contract.md`
- Modify: `scripts/run-codex-task.sh` (replace the final `die "execution is not implemented yet"` line)
- Modify: `tests/run-codex-task.test.sh` (append the execution section before the summary footer)

**Interfaces:**
- Consumes: `run-codex-task.sh`'s validated `argv` and `timeout_s` from Task 3.
- Produces: on exit, a report file at `--report` containing `- executor:`, `- thread:`, `- status:`, and `- commits: <base7>..<head7>` lines; a commit on the task branch when and only when status is `DONE`; and one stdout status line of the form `codex <model>/<effort> status=<S> commits=<a7>..<b7> thread=<id> report=<path>`. Task 6 parses that line.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3
**Approach:** inline - skip 3: the spec fixes the commit boundary and the cleanup rule

- [ ] **Step 1: Write the failing test**

Append to `tests/run-codex-task.test.sh`, immediately before the `printf '\n%d passed` footer:

```bash
# --- execution against a stub codex -----------------------------------------
# No model is ever called. The stub writes the JSONL and last-message files a
# real run would produce, so commit behaviour and report shape are provable.
mkdir -p "$TMP/stub" "$TMP/repo"
git -C "$TMP/repo" init -q .
git -C "$TMP/repo" config user.email t@t.t
git -C "$TMP/repo" config user.name t
printf 'seed\n' > "$TMP/repo/seed.txt"
git -C "$TMP/repo" add -A
git -C "$TMP/repo" commit -qm seed

cat > "$TMP/stub/codex" <<'STUB'
#!/usr/bin/env bash
# Mimics `codex exec --json -o FILE`: JSONL on stdout, final message to -o.
out=""; cwd=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -C) cwd="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf '{"type":"thread.started","thread_id":"%s"}\n' "${STUB_THREAD:-th-001}"
printf '{"type":"item.completed"}\n'
[ -n "$cwd" ] && printf 'produced\n' > "$cwd/produced.txt"
cat > "$out" <<JSON
{"status":"${STUB_STATUS:-DONE}","summary":"stub summary","commit_subject":"feat(x): stub change","questions":[]}
JSON
exit "${STUB_RC:-0}"
STUB
chmod +x "$TMP/stub/codex"

run_exec() { # run_exec  -> prints the wrapper's stdout status line
  PATH="$TMP/stub:$PATH" bash "$SCRIPT" \
    --brief "$TMP/brief.md" --report "$TMP/report.md" \
    --cwd "$TMP/repo" --model gpt-5.5 --effort medium "$@" 2>"$TMP/err"
}

before=$(git -C "$TMP/repo" rev-parse HEAD)
line=$(STUB_STATUS=DONE run_exec)
after=$(git -C "$TMP/repo" rev-parse HEAD)

check "DONE commits exactly one commit" \
  "$(git -C "$TMP/repo" rev-list --count "$before".."$after")" "1"
check "DONE uses the schema commit subject" \
  "$(git -C "$TMP/repo" log -1 --pretty=%s)" "feat(x): stub change"
check "status line reports DONE" "$(grep -qF 'status=DONE' <<<"$line" && echo yes || echo no)" "yes"
check "status line carries the thread id" "$(grep -qF 'thread=th-001' <<<"$line" && echo yes || echo no)" "yes"
check "report file was written" "$([ -f "$TMP/report.md" ] && echo yes || echo no)" "yes"
check "report records the executor tier" \
  "$(grep -qE '^- executor: codex gpt-5\.5 / medium' "$TMP/report.md" && echo yes || echo no)" "yes"
check "report records the thread id" \
  "$(grep -qE '^- thread: th-001' "$TMP/report.md" && echo yes || echo no)" "yes"
check "report records a commit range" \
  "$(grep -qE '^- commits: [0-9a-f]{7}\.\.[0-9a-f]{7}' "$TMP/report.md" && echo yes || echo no)" "yes"

# A non-DONE status must leave the tree dirty rather than commit broken work,
# which is how a Claude implementer behaves when it reports BLOCKED mid-task.
before=$(git -C "$TMP/repo" rev-parse HEAD)
line=$(STUB_STATUS=BLOCKED STUB_THREAD=th-002 run_exec)
after=$(git -C "$TMP/repo" rev-parse HEAD)
check "BLOCKED creates no commit" "$(git -C "$TMP/repo" rev-list --count "$before".."$after")" "0"
check "BLOCKED is reported on the status line" \
  "$(grep -qF 'status=BLOCKED' <<<"$line" && echo yes || echo no)" "yes"
check "BLOCKED leaves the tree dirty" \
  "$(git -C "$TMP/repo" status --porcelain | grep -q . && echo yes || echo no)" "yes"
git -C "$TMP/repo" reset -q --hard HEAD
git -C "$TMP/repo" clean -qfd

# A non-zero exit is a run failure regardless of what the last message claimed.
before=$(git -C "$TMP/repo" rev-parse HEAD)
line=$(STUB_RC=1 STUB_STATUS=DONE run_exec) || true
after=$(git -C "$TMP/repo" rev-parse HEAD)
check "non-zero exit creates no commit" "$(git -C "$TMP/repo" rev-list --count "$before".."$after")" "0"
git -C "$TMP/repo" reset -q --hard HEAD
git -C "$TMP/repo" clean -qfd

check "the prompt inlines repo conventions when present" \
  "$(printf 'be terse\n' > "$TMP/repo/CLAUDE.md"; STUB_STATUS=DONE run_exec >/dev/null; \
     grep -qF 'be terse' "$TMP/report.md.prompt.md" && echo yes || echo no)" "yes"
git -C "$TMP/repo" reset -q --hard HEAD; git -C "$TMP/repo" clean -qfd
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-superpower-companions/tests/run-codex-task.test.sh
```

Expected: FAIL from `DONE commits exactly one commit` onward. The script still exits 2 with "execution is not implemented yet", so no commit, report, or status line is produced.

- [ ] **Step 3: Write the task contract Codex is held to**

Create `scripts/codex-task-contract.md`:

```markdown
## How to complete this task

You are implementing one task from an implementation plan. The brief above is
your complete instruction set.

**You cannot use git.** Your sandbox denies writes to `.git`, so `git add`,
`git commit`, and `git stash` will fail. Do not attempt them. Leave your work in
the working tree; the wrapper that invoked you commits it.

**Test-first is required where the brief calls for it.** The report contract
requires evidence that a test failed before your change and passed after it.
That evidence can only be produced by writing the test first and running it
twice. Record both runs: the exact command, the failing output, and the passing
output.

**Do not guess at an ambiguous brief.** If the brief does not determine what to
build, implement nothing, set `status` to `NEEDS_CONTEXT`, and put your
questions in the `questions` array. Someone will answer them and resume this
session. A plausible guess is more expensive than a question, because it passes
review and fails later.

**Your final message must match the output schema**, with:

- `status`: `DONE` when the task is complete and its tests pass; `BLOCKED` when
  you cannot complete it; `NEEDS_CONTEXT` when the brief is ambiguous.
- `summary`: what you changed and why, including the RED and GREEN evidence
  described above.
- `commit_subject`: a conventional-commit subject, `type(scope): subject`,
  imperative mood, no trailing period, 50 characters or fewer. Types are
  `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`.
- `questions`: required when `status` is `NEEDS_CONTEXT`, empty otherwise.
```

- [ ] **Step 4: Replace the placeholder line with the execution half**

In `scripts/run-codex-task.sh`, replace the single line
`die "execution is not implemented yet"` with:

```bash
prompt="$report.prompt.md"
jsonl="$report.jsonl"
last="$report.last.json"

{
  cat "$brief"
  # Codex reads AGENTS.md, never CLAUDE.md, and the host repo may have neither.
  # Inlining beats assuming: this plugin ships to arbitrary repositories, and
  # writing an AGENTS.md would change the user's own Codex sessions too.
  for f in CLAUDE.md AGENTS.md; do
    if [ -f "$cwd/$f" ]; then
      printf '\n\n## Repository conventions (%s)\n\n' "$f"
      cat "$cwd/$f"
    fi
  done
  printf '\n\n'
  cat "$HERE/codex-task-contract.md"
} > "$prompt"

# `git add -A` stages the whole repository no matter which subdirectory it runs
# from, so a cwd below the root would sweep unrelated uncommitted work into this
# task's commit. --show-prefix is empty only at the root, and unlike comparing
# --show-toplevel against pwd it does not care that git and MSYS disagree over
# whether a path starts with D:/ or /d/.
prefix=$(git -C "$cwd" rev-parse --show-prefix) || die "not a git repository: $cwd"
[ -z "$prefix" ] || die "cwd must be the repository root, but sits under $prefix"
base=$(git -C "$cwd" rev-parse HEAD) || die "cannot resolve HEAD in $cwd"

codex_pid=""
codex_winpid=""
# Two mechanisms for two topologies. `codex` on PATH is a POSIX shim that
# execs node, which then spawns codex's real payload - a native codex-*.exe -
# via a raw CreateProcess outside the MSYS runtime entirely; that binary holds
# no MSYS pgid, so only `taskkill //T`, which walks native ParentProcessId,
# can reach it. `kill -TERM -<pgid>` is the complementary case: it reaches
# whatever MSYS-aware descendants share the `set -m` group below, which is
# what a real Windows ParentProcessId lookup was shown live NOT to find (a
# backgrounded MSYS child survived `taskkill //F //T` on its own parent's
# winpid while confirmed still running). Both run every time, since neither
# topology can be assumed absent.
kill_codex_tree() {
  kill -0 "$codex_pid" 2>/dev/null || return 0
  [ -n "$codex_winpid" ] && taskkill //F //T //PID "$codex_winpid" >/dev/null 2>&1
  kill -TERM -"$codex_pid" 2>/dev/null || true
  sleep 1
  kill -0 "$codex_pid" 2>/dev/null && kill -KILL -"$codex_pid" 2>/dev/null
  return 0
}
cleanup() {
  [ -n "$codex_pid" ] && kill_codex_tree
  return 0
}
trap cleanup EXIT INT TERM HUP

# Codex can exit 0 without writing its final message. Left in place, a previous
# run's verdict would be read as this one's - guaranteed on every resume round,
# which reuses the same report path - and the wrapper would commit under a stale
# subject it never earned. rm -f succeeds on a missing file but can fail on a
# locked one, so the clear is verified rather than assumed.
rm -f "$last" "$jsonl"
[ ! -f "$last" ] || die "could not clear stale verdict file: $last"

# A non-interactive script has job control off, so a plain `cmd &` inherits
# this script's own process group instead of getting a fresh one - confirmed
# live: `kill -TERM -"$codex_pid"` then fails with "No such process" because
# no group with that id exists. `set -m` around just this launch is what makes
# the backgrounded job (and anything it execs) its own group, which is what
# `kill_codex_tree` signals; `setsid` would do the same but isn't on this box.
set -m
codex "${argv[@]}" < "$prompt" > "$jsonl" 2> "$report.stderr" &
codex_pid=$!
set +m
# Captured once, right after launch, while codex_pid (node) is still alive:
# this is node's own Windows process, which is what taskkill //T needs to
# start its native tree-walk from.
codex_winpid=$(cat "/proc/$codex_pid/winpid" 2>/dev/null || true)

# Polled rather than wrapped in `timeout`: the kill has to happen while the
# child is still live. `timeout` reaps its child before wait returns, leaving
# nothing left to signal by the time a kill would fire - and it would also put
# a wrapper process between us and node, which is exactly what breaks
# taskkill's native tree-walk (see codex_winpid above).
timed_out=no
waited=0
while [ "$waited" -lt "$timeout_s" ] && kill -0 "$codex_pid" 2>/dev/null; do
  sleep 1
  waited=$((waited + 1))
done
if kill -0 "$codex_pid" 2>/dev/null; then
  timed_out=yes
  kill_codex_tree
fi

# Bounded rather than a bare `wait`: a child that survived both signals would
# block forever, and this wrapper must always return a status line to the
# controller. Reintroducing `timeout` is not the answer - it would reinsert a
# process between us and node, which is what made taskkill unable to walk the
# native tree.
grace=0
while [ "$grace" -lt 30 ] && kill -0 "$codex_pid" 2>/dev/null; do
  sleep 1
  grace=$((grace + 1))
done
if kill -0 "$codex_pid" 2>/dev/null; then
  rc=124
else
  wait "$codex_pid"; rc=$?
fi
[ "$timed_out" = yes ] && rc=124
codex_pid=""
codex_winpid=""

# Event field naming has varied across Codex releases, so match on any of the
# shapes rather than pinning one that a later version may rename.
thread_id=$(jq -r 'select(type=="object")
  | (.thread_id // .threadId // .session_id // .sessionId // empty)' \
  "$jsonl" 2>/dev/null | head -1)
[ -n "$thread_id" ] || thread_id="${thread:-unknown}"

status=BLOCKED
summary=""
subject=""
if [ -f "$last" ]; then
  status=$(jq -r '.status // "BLOCKED"' "$last" 2>/dev/null || echo BLOCKED)
  summary=$(jq -r '.summary // ""' "$last" 2>/dev/null || true)
  subject=$(jq -r '.commit_subject // ""' "$last" 2>/dev/null || true)
fi
[ "$rc" -eq 0 ] || status=BLOCKED

committed=no
if [ "$status" = DONE ] && [ -n "$subject" ]; then
  git -C "$cwd" add -A -- . || die "git add failed in $cwd"
  # Keep the wrapper's own scratch out of the task's commit. A no-op when the
  # report lives in a git-ignored directory, load-bearing when it does not.
  for artefact in "$prompt" "$jsonl" "$last" "$report.stderr" "$report"; do
    git -C "$cwd" reset -q -- "$artefact" 2>/dev/null || true
  done
  if git -C "$cwd" diff --cached --quiet; then
    # A task can legitimately finish with nothing to commit. Dying here would
    # leave the controller no report and no status line to read.
    committed=empty
  else
    git -C "$cwd" commit -q -m "$subject" || die "commit failed in $cwd"
    committed=yes
  fi
fi

head=$(git -C "$cwd" rev-parse HEAD)

{
  printf '# Task report\n\n'
  printf -- '- executor: codex %s / %s\n' "$model" "$effort"
  printf -- '- thread: %s\n' "$thread_id"
  printf -- '- status: %s\n' "$status"
  printf -- '- commits: %s..%s\n' "${base:0:7}" "${head:0:7}"
  [ "$committed" = empty ] && printf -- '- note: DONE with an empty diff; nothing was committed\n'
  printf '\n## Summary\n\n%s\n' "$summary"
  if [ "$status" = NEEDS_CONTEXT ]; then
    printf '\n## Questions\n\n'
    jq -r '.questions[]? | "- " + .' "$last" 2>/dev/null || true
  fi
  if [ "$status" != DONE ]; then
    printf '\n## Working tree\n\nLeft uncommitted on purpose. Last 20 stderr lines:\n\n```\n'
    tail -20 "$report.stderr" 2>/dev/null || true
    printf '```\n'
  fi
} > "$report"

printf 'codex %s/%s status=%s commits=%s..%s thread=%s report=%s\n' \
  "$model" "$effort" "$status" "${base:0:7}" "${head:0:7}" "$thread_id" "$report"

[ "$status" = DONE ]
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
bash plugins/dcc-superpower-companions/tests/run-codex-task.test.sh
```

Expected: PASS, `0 failed`.

- [ ] **Step 6: Verify no process was left behind**

```bash
tasklist //FI "IMAGENAME eq codex.exe" | head -3
```

Expected: `INFO: No tasks are running which match the specified criteria.`

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-superpower-companions/scripts/codex-task-contract.md plugins/dcc-superpower-companions/scripts/run-codex-task.sh plugins/dcc-superpower-companions/tests/run-codex-task.test.sh
git commit -m "feat(companions): execute and commit codex tasks"
```

---

### Task 5: Assign executors when writing a plan

**Files:**
- Modify: `skills/assigning-implementers/SKILL.md`

**Interfaces:**
- Consumes: `scripts/detect-executors.sh` (Task 2) and the `gate` and `codex-assignment` blocks (Task 1).
- Produces: the `**Executor:** codex <model> / <effort>` task line and the `> **External executors:** <ids>` plan-header line, both read by Task 6.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 1 = 3
**Approach:** inline - skip 3: the spec fixes the gate, the line format, and the checkbox behaviour

- [ ] **Step 1: Insert the executor section**

In `skills/assigning-implementers/SKILL.md`, insert this section immediately
after the `## Reserve agents are never an assignment output` section and before
`## Write the assignment`:

````markdown
## Offer an external executor, then apply the lane gate

Run this once per plan, after scoring every task and before writing any
assignment line:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-executors.sh"
```

Render the roster as a multi-select question: one tickable option per executor
whose `usable` is `true`, and a prose line naming every other detected executor
with its `reason`. **If no executor is usable, ask nothing** and write the plan
Claude-only - an empty checkbox is a worse answer than no checkbox.

Record the tick as one appended blockquote line in the plan header:

```markdown
> **External executors:** codex
```

Then apply the lane gate from the `gate` block of
[`../../reference/ladder.md`](../../reference/ladder.md) to each task. All four
conditions must hold:

- an executor was ticked,
- the task cleared Rule S without a human override,
- `total >= min_score`,
- `risk <= max_risk`.

A task that passes the gate takes its model and effort from that file's
`codex-assignment` block and gains one extra line. A task that fails it is
assigned from the Claude table exactly as before and gains nothing.

**The `**Implementer:**` line still names the Claude agent for the score.** The
executor is an override on a second line, never a replacement on the first:

```markdown
**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Executor:** codex gpt-5.5 / medium
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
```

That ordering is what makes every degradation free. A machine without Codex, a
cold session, an `executing-plans` run, and an executor whose auth has lapsed all
fall back by *reading a line that is already there*, rather than re-deriving the
assignment at dispatch time - which is the failure this whole plugin exists to
remove. It also keeps every `**Implementer:**` value inside the assignment or
reserve table, so the checks below still mean what they say.

**Why the gate excludes an overridden Rule S pass.** The legacy floor lets a
human keep a `spec = 3` task as written. Such a task can score
`files 0 + spec 3 + coupling 0 + risk 0 = 3` and would otherwise pass the gate,
handing a task whose approach nobody decided to a one-shot external agent that
cannot ask questions mid-run.

**Batched tasks stay on the Claude lane.** superpowers' rule to batch small
same-shape work produces one dispatch covering several tasks, which a per-task
`**Executor:**` line and per-task thread id cannot represent. Do not write an
`**Executor:**` line on a batched task.
````

- [ ] **Step 2: Extend the checklist**

In the same file, in the `## Check your work` section, add these three bullets
to the end of the existing list:

```markdown
- Every `**Executor:**` line names a rung that appears in `reference/ladder.md`'s
  `codex-assignment` block, and the model and effort match the row for that
  task's total. A rung that is not in the table cannot be dispatched.
- Every task carrying an `**Executor:**` line also carries an `**Implementer:**`
  line naming its Claude fallback. An executor line alone leaves nothing to fall
  back to when the CLI is missing at dispatch time.
- No task carrying an `**Executor:**` line scores below the gate's `min_score`,
  above its `max_risk`, or passed Rule S only by human override.
```

- [ ] **Step 3: Verify the skill still parses and the suites pass**

```bash
head -5 plugins/dcc-superpower-companions/skills/assigning-implementers/SKILL.md
for t in plugins/dcc-superpower-companions/tests/*.test.sh; do echo "== $t"; bash "$t" | tail -1; done
```

Expected: the frontmatter block is intact and unchanged, and every suite reports `0 failed`.

- [ ] **Step 4: Commit**

```bash
git add plugins/dcc-superpower-companions/skills/assigning-implementers/SKILL.md
git commit -m "feat(companions): assign external executors in plans"
```

---

### Task 6: Dispatch, resume, and hand back

**Files:**
- Modify: `skills/dispatching-tiered-implementers/SKILL.md`

**Interfaces:**
- Consumes: the `**Executor:**` line (Task 5), `detect-executors.sh` (Task 2), `run-codex-task.sh` and its stdout status line (Tasks 3 and 4), and the `codex-successor` block (Task 1).
- Produces: the ledger clause `(assigned; executor codex <model>/<effort>, thread <id>)`, extending the plugin's existing `(assigned)` line.

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 0 - spec 1 - coupling 2 - risk 1 = 4
**Approach:** inline - skip 3: the spec fixes the dispatch flow, the failure taxonomy, and the handback rule

- [ ] **Step 1: Insert the executor dispatch section**

In `skills/dispatching-tiered-implementers/SKILL.md`, insert this section
immediately after the `## Dispatch a task` section and before `## Escalate`:

````markdown
## Dispatch an external executor

A task carrying an `**Executor:**` line runs on that CLI instead of its
`**Implementer:**` agent. Everything downstream - the review seat, the fix loop,
the ledger, the five-round cap - is unchanged, because the contract superpowers
enforces is files and commits, not a particular runtime.

**There is no driver subagent.** Run the wrapper yourself as a background Bash
call, exactly as you already run `sdd-workspace` and `task-brief`. It prints one
status line and writes everything else to files.

**There is no separate worktree.** Codex runs in the SDD worktree, on the task
branch, where a Claude implementer would run. superpowers already created that
worktree at setup, and its finish step is `rm -rf <workspace>`, so a nested
worktree would be deleted out from under git.

1. **Guard the roster.** Run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-executors.sh"` and read the entry
   for the named executor. **Never trust the plan's copy** - it records what was
   available when the plan was written.

   If `usable` is false, dispatch the task's `**Implementer:**` agent on the
   Claude lane instead, say the substitution aloud, and record it:

   ```
   Task <N>: implementer impl-sonnet-medium (assigned; executor codex unavailable - <reason>)
   ```

   Never fall back silently. A silent fallback makes the whole lane invisible.

2. **Run the wrapper**, using the brief path `task-brief` printed and the
   workspace path `sdd-workspace` printed:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-task.sh" \
     --brief <brief> --report <workspace>/task-<N>-report.md \
     --cwd <worktree> --model <model> --effort <effort>
   ```

   The timeout comes from `reference/ladder.md`'s `codex-timeout` block; do not
   pass `--timeout` unless you are deliberately overriding it.

3. **Record the assignment** by extending the `(assigned)` line this skill
   already owns:

   ```
   Task <N>: implementer impl-sonnet-medium (assigned; executor codex gpt-5.5/medium, thread 01a0...)
   ```

   The thread id must reach the ledger. It also lands in the report file. If it
   lived only in your context, a compaction would turn round 2 into a fresh
   dispatch wearing a resume's name.

4. **Review as normal.** Dispatch the judge exactly as for a Claude task. Do not
   tell it which lane produced the diff: a judge that knows the author scores
   the author, and nothing in its inputs needs to change to keep it unaware.

## When a run fails

A failed *run* is not a failed *review*, and they take different paths. A run
failure is a non-zero exit from the wrapper, a `status` of `BLOCKED` on the first
attempt, or an empty diff.

| Failure | Response |
|---------|----------|
| Transient - network, rate limit, 5xx in `<report>.stderr` | Retry once at the same rung |
| Capability - empty diff, or `status: BLOCKED` | Move one rung via the `codex-successor` block and run once |
| `status: NEEDS_CONTEXT` | Answer the questions in the report, then resume (below). Not a failure and not a retry |
| Either failure a second time | `HANDBACK` |

At most two Codex runs per task before Claude takes over. `HANDBACK` is an
action, not a rung: dispatch the task's `**Implementer:**` agent on the Claude
lane and let the ordinary ladder govern from there. Record it inside the line the
loop is already writing, never as a line of its own.

## Resuming a Codex task

Fix rounds 1 to 3 resume the same Codex session, mirroring superpowers' rule that
those rounds resume the same implementer to preserve its model, effort, and
context. Pass the review feedback as the brief:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-task.sh" \
  --brief <feedback-file> --report <workspace>/task-<N>-report.md \
  --cwd <worktree> --model <model> --effort <effort> --resume <thread-id>
```

**Round 4 is `HANDBACK`.** The Claude implementer inherits the working tree, the
commits, and the report, which is superpowers' own "supply the context and
re-dispatch" case.

This supersedes superpowers' rounds 4 and 5 instruction to escalate to a *more
capable* model. Handing back lands the task on the Claude assignment-table row
for its score, which is the same tier the rubric picked before the fix rounds
happened. The argument for parity is that a change of model family plus a fresh
context satisfies the rule's intent, and that the recorded score is the only
evidence-free anchor available. Say the handback aloud when it happens.
````

- [ ] **Step 2: Extend the failure-modes table**

In the same file, add these rows to the end of the `## Failure modes` table:

```markdown
| Task has an `**Executor:**` line and the CLI is usable | Run the wrapper; do not dispatch a subagent for it |
| Task has an `**Executor:**` line and the CLI is missing, unauthenticated, or not batch-capable | Dispatch the `**Implementer:**` agent, say the substitution aloud, record the reason in the ledger |
| The `**Executor:**` line names a rung absent from `codex-assignment` | Stop and ask your human partner. The wrapper refuses it anyway, exit 2 |
| Wrapper exits 2 | A validation error, not a run failure. The plan or the table is wrong; fix it rather than retrying |
| Two Codex runs have failed | `HANDBACK` to the `**Implementer:**` agent and continue on the Claude ladder |
```

- [ ] **Step 3: Verify the suites still pass**

```bash
for t in plugins/dcc-superpower-companions/tests/*.test.sh; do echo "== $t"; bash "$t" | tail -1; done
```

Expected: every suite reports `0 failed`.

- [ ] **Step 4: Commit**

```bash
git add plugins/dcc-superpower-companions/skills/dispatching-tiered-implementers/SKILL.md
git commit -m "feat(companions): dispatch and resume codex tasks"
```

---

### Task 7: Cross-family review

**Files:**
- Modify: `skills/dispatching-tiered-implementers/SKILL.md`

**Interfaces:**
- Consumes: `criteria/task-review.md` and the K=3 rule already in this skill; `scripts/codex-report-schema.json` (Task 3) as the shape precedent for the criteria schema.
- Produces: nothing later tasks consume.

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 0 - spec 1 - coupling 2 - risk 1 = 4
**Approach:** inline - skip 3: the spec fixes both seats and the aggregation order

- [ ] **Step 1: Add the Codex judge seat**

In `skills/dispatching-tiered-implementers/SKILL.md`, inside
`### Repeated evaluation on risk-3 tasks`, append after the existing paragraphs
and before the ledger example:

````markdown
**One of the three seats is Codex**, when it is usable. Risk-3 tasks are excluded
from the executor lane by the gate's `max_risk`, so a Codex judge never reviews
Codex's own work.

```bash
codex exec -s read-only -m gpt-5.6-sol -c model_reasoning_effort=high \
  --output-schema <criteria-schema> -o <out.json> -C <worktree> < <prompt>
```

Use `codex exec`, not `codex exec review`: the latter imposes its own report
shape, and this seat must return the criteria format the other two judges return.
The prompt is superpowers' task-reviewer prompt with the same criteria block
appended, and the schema requires one integer 1 to 20 per criterion plus
superpowers' own verdicts.

If Codex is not usable, dispatch the third `judge-fable` as before and say so.
Average and read the spread exactly as this section already specifies - a Codex
seat changes who scores, not how the scores are read.
````

- [ ] **Step 2: Add the final-review round**

Append this section to the end of the same file:

````markdown
## The final whole-branch review

superpowers' final whole-branch review runs unchanged, including its own model
selection. This adds a second reviewer and a verification pass over the union.

**This supersedes a written promise.** The plugin's README states that the final
whole-branch review and its model selection are untouched. That is no longer
true, and it is recorded here rather than left to accrete silently.

1. **Run superpowers' review** exactly as written. Keep its findings.
2. **Run a Codex round** over the same branch:

   ```bash
   codex exec review --base <base-branch> -m gpt-5.6-sol \
     -c model_reasoning_effort=high --json -o <codex-review.md>
   ```

   `codex exec review` is purpose-built for this and takes no sandbox flag,
   because review is read-only by nature. If Codex is not usable, skip this step,
   say so, and report superpowers' review alone.
3. **Dedupe into one list**, tagging each finding `claude`, `codex`, or `both`.
   Two findings are the same when they name the same defect in the same place,
   not merely the same file.
4. **Verify each surviving finding** with `judge-fable`, one dispatch for the
   whole list, returning `CONFIRMED` or `REJECTED` with evidence for each. The
   verifier is a third seat, so neither reviewer grades its own work.
5. **Report** confirmed findings ranked most severe first, then the rejected ones
   with the reason each was rejected. A finding both reviewers raised and the
   judge confirmed is the strongest signal available in this loop; say so.

The handoff to superpowers:finishing-a-development-branch is unchanged.
````

- [ ] **Step 3: Verify the suites still pass**

```bash
for t in plugins/dcc-superpower-companions/tests/*.test.sh; do echo "== $t"; bash "$t" | tail -1; done
```

Expected: every suite reports `0 failed`.

- [ ] **Step 4: Commit**

```bash
git add plugins/dcc-superpower-companions/skills/dispatching-tiered-implementers/SKILL.md
git commit -m "feat(companions): add codex review seats"
```

---

### Task 8: Hook context

**Files:**
- Modify: `scripts/tier-nudge.sh` (the `superpowers:writing-plans` case only)
- Modify: `tests/hook.test.sh` (add one assertion)

**Interfaces:**
- Consumes: nothing
- Produces: nothing

**Implementer:** dcc-superpower-companions:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1
**Approach:** inline - skip 2: a fourth clause beside three existing ones in the same script

- [ ] **Step 1: Write the failing assertion**

In `tests/hook.test.sh`, immediately before the `printf '\n%d passed` footer, add:

```bash
# The planning nudge must mention the executor lane, or a planner will score
# tasks correctly and never learn that an external lane exists.
plan_ctx=$(run superpowers:writing-plans | jq -r '.hookSpecificOutput.additionalContext')
check "writing-plans context mentions the external lane" \
  "$(grep -qiF 'Executor' <<<"$plan_ctx" && echo yes || echo no)" "yes"
check "writing-plans context names the detection script" \
  "$(grep -qF 'detect-executors' <<<"$plan_ctx" && echo yes || echo no)" "yes"
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-superpower-companions/tests/hook.test.sh
```

Expected: FAIL on both new checks; the existing checks still pass.

- [ ] **Step 3: Extend the context string**

In `scripts/tier-nudge.sh`, in the `superpowers:writing-plans)` case, replace the
`context=` assignment with:

```bash
    context="Plans in this repository record an implementer assignment for each task: an \`**Implementer:**\` line naming a dcc-superpower-companions agent, an \`**Evaluation:**\` line showing the four-axis scores behind it, and an \`**Approach:**\` line when the task involved an approach decision. The dcc-superpower-companions:assigning-implementers skill holds the scoring rubric, the assignment table, and Rule S, which sends an over-scoring task back to be split rather than to a larger model. That skill also runs scripts/detect-executors.sh to offer any usable external agent CLI as an executor, and adds an \`**Executor:**\` line to each task that clears the lane gate."
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash plugins/dcc-superpower-companions/tests/hook.test.sh
```

Expected: PASS, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-superpower-companions/scripts/tier-nudge.sh plugins/dcc-superpower-companions/tests/hook.test.sh
git commit -m "feat(companions): nudge planners toward the executor lane"
```

---

### Task 9: Manifests and documentation

**Files:**
- Modify: `.claude-plugin/plugin.json` (repo-relative: `plugins/dcc-superpower-companions/.claude-plugin/plugin.json`)
- Modify: `.claude-plugin/marketplace.json` (repo root)
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above
- Produces: nothing

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2
**Approach:** inline - skip 3: the spec fixes the version and what the README must record

- [ ] **Step 1: Bump the plugin manifest**

In `plugins/dcc-superpower-companions/.claude-plugin/plugin.json`, set
`"version": "0.4.0"` and replace `"description"` with:

```
"Extends superpowers with 19 tiered subagents and an external executor lane. Scores every plan task on a four-axis rubric that sends over-scoring tasks back to be split, routes score-2..4 low-risk tasks to Codex for quota offload, dispatches with a defined escalation ladder, and scores task reviews against named criteria with a cross-family review seat."
```

Add `"codex"` and `"external-executors"` to the end of the `keywords` array.

- [ ] **Step 2: Mirror it in the marketplace manifest**

In the repo root `.claude-plugin/marketplace.json`, find the
`"name": "dcc-superpower-companions"` entry and replace its `"description"` with
the identical string from Step 1, and add the same two keywords. The two files
must agree.

- [ ] **Step 3: Validate the manifests**

```bash
claude plugin validate .
```

Expected: no errors. If it reports a mismatch between the two descriptions, fix the file it names rather than editing the schema.

- [ ] **Step 4: Document the lane in the README**

In `plugins/dcc-superpower-companions/README.md`, insert this section
immediately after the `**Best-of-3 approach selection.**` paragraph and before
`## Requirements`:

````markdown
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
an override on a second line, which is what makes a missing CLI, a cold session,
and an `executing-plans` run all degrade by reading a line that is already there
rather than re-deriving the assignment at dispatch.

These facts were probed against Codex 0.151.0 on Windows with
ChatGPT-subscription auth on 2026-08-31, and the tables depend on all of them:

- Only `gpt-5.5` and `gpt-5.6-sol` are available. `luna` and `terra` are rejected
  with HTTP 400 and Codex holds no metadata for either.
- Valid reasoning efforts are `low`, `medium`, `high`, `xhigh`, `ultra`.
  `minimal` is rejected. The CLI validates neither model nor effort locally - it
  echoes any string and fails at the API - so `scripts/run-codex-task.sh`
  validates both before spawning anything.
- Codex **cannot commit**. Its Windows restricted-token sandbox denies writes to
  `.git` under `-s workspace-write`, which `codex sandbox -- git add -A`
  reproduces with no model call. The wrapper owns the commit, so the ledger's
  commit range is measured rather than reported and the repository's commit
  convention is applied by a script rather than inferred by a model that has
  never read `CLAUDE.md`.
- `codex exec resume` does **not** inherit `-m` or `-c model_reasoning_effort`.
  The wrapper re-sends every per-invocation flag, because a bare resume would
  silently run a fix round at the user's config default instead of the recorded
  tier.

A different machine, account, or Codex version must re-probe before trusting the
tables in `reference/ladder.md`.

**Cross-family review.** On a risk-3 task one of the three judges is Codex, and
the final whole-branch review gains a `codex exec review` round whose findings
are deduped with superpowers' own and then verified by `judge-fable`. Risk-3
tasks are excluded from the executor lane, so a Codex judge never reviews Codex's
own work.
````

- [ ] **Step 5: Correct the compatibility claim**

In the same README, in the `## Compatibility` section, replace the sentence
beginning "Everything else in the superpowers loop is untouched:" through the end
of that paragraph with:

```markdown
Everything else in the superpowers loop is untouched: the brief and report
protocol, the review package, the five-round cap, the breaker and its
adjudication rules, and the handoff to
superpowers:finishing-a-development-branch.

Two further instructions are superseded. The final whole-branch review is no
longer untouched: it keeps superpowers' own review and model selection and adds
a Codex round plus a verification pass over the union. And rounds 4 and 5 call
for a more capable model, where an external task instead hands back to the Claude
assignment-table row for its score - a change of model family plus a fresh
context, argued as satisfying that rule's intent rather than as an exception to
it.
```

- [ ] **Step 6: Document the new tests**

In the same README, in the `## Tests` section, replace "Requires `jq`. No model
calls." with:

```markdown
Requires `jq` and `git`. No model calls: the executor suites run against a stub
`codex` on `PATH` and a synthetic roster, never the real CLI.
```

- [ ] **Step 7: Run every suite and validate**

```bash
for t in plugins/dcc-superpower-companions/tests/*.test.sh; do echo "== $t"; bash "$t" | tail -1; done
claude plugin validate .
```

Expected: seven suites, every one reporting `0 failed`, and validation with no errors.

- [ ] **Step 8: Commit**

```bash
git add plugins/dcc-superpower-companions/.claude-plugin/plugin.json .claude-plugin/marketplace.json plugins/dcc-superpower-companions/README.md
git commit -m "docs(companions): document the external executor lane"
```
